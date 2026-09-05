/* fbegl_nano.c — a wrapper libEGL.so.1 that presents to the RG Nano's panel.
 *
 * Forked from the MM+ port's src/fbegl.c. The trick is identical and it is the
 * reason this fork exists at all:
 *
 *   SDL resolves eglSwapBuffers by dlopen'ing libEGL.so.1 and dlsym'ing the
 *   symbol, which bypasses an LD_PRELOAD interposer. So instead we BECOME
 *   libEGL.so.1 — placed first on LD_LIBRARY_PATH, exporting our own
 *   eglSwapBuffers (read the finished frame back, blit it to /dev/fb0) and our
 *   own eglGetProcAddress (hand back that eglSwapBuffers), and forwarding every
 *   other EGL entry point to real Mesa EGL, shipped alongside as
 *   librealEGL.so (same binary, soname patched) and pulled in as NEEDED.
 *
 * There is no GPU and no compositor on the V3s. This readback+blit IS the
 * display path.
 *
 * WHAT DIFFERS FROM THE MM+ VERSION
 *   - fb_nano.h instead of fb.h: RGB565 240x240, runtime rotation switch.
 *   - The touch-cursor overlay is gone. It exists on the MM+ to drive
 *     Pocket-Edition-era 1.1.5 builds through an injected virtual cursor; this
 *     fork targets 1.2.20.2 only, which has a real gamepad API, so the overlay
 *     would be dead code carried across an already-difficult port.
 *   - The default is the SYNCHRONOUS path. See the PBO note below — the MM+'s
 *     asynchronous present is a two-core optimisation and there is no reason to
 *     expect it to pay here.
 *
 * STATUS: compiles, never run on hardware.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <errno.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>

#include "fb_nano.h"

#ifndef GL_FRAMEBUFFER_BINDING
#define GL_FRAMEBUFFER_BINDING 0x8CA6
#endif
#ifndef GL_IMPLEMENTATION_COLOR_READ_FORMAT
#define GL_IMPLEMENTATION_COLOR_READ_FORMAT 0x8B9B
#endif
#ifndef GL_IMPLEMENTATION_COLOR_READ_TYPE
#define GL_IMPLEMENTATION_COLOR_READ_TYPE   0x8B9A
#endif

/* --- present-path instrumentation (FBEGL_STATS=<frames per report>) ---------
 *
 * On a device where the first real question is "does a frame ever appear",
 * this is not a nice-to-have: it is how Gate 5 and Gate 6 get answered. Do not
 * strip it to save space.
 *
 * The decomposition only means anything with an explicit glFinish FIRST.
 * Gallium defers — nothing is rasterized until something forces a flush, and
 * that something would otherwise be our glReadPixels. Timing glReadPixels alone
 * charges the ENTIRE scene rasterization to "readback" and makes the present
 * path look like the bottleneck no matter what the truth is. Draining the pipe
 * separately splits "the renderer is slow" from "our copy is slow", and on this
 * hardware those two want completely different responses.
 */
static int    g_stats_n;          /* 0 = instrumentation off */
static int    g_stats_i;
static double a_finish, a_read, a_blit, a_swap, a_gap, a_map, a_cap;
static double g_prev_end;

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1.0e6;
}

/* --- frame cap (FBEGL_FPS_CAP=<fps>, 0 or unset = off) ----------------------
 *
 * Nothing paces frames on this console. There is no vsync wait in the present
 * path -- fb_nano.h pans and returns -- so the game runs as fast as one A7 can
 * finish a frame, which is not a steady rate: measured in-world at 120x120 the
 * slow tenth of frames land near 7 fps and the fast tenth near 18. A cap trades
 * the fast frames away to make the pace even, and gives the battery the
 * difference, since a capped frame is spent asleep rather than working.
 *
 * It cannot help a frame that is ALREADY slower than the target; those pass
 * through untouched. So a cap set above the slow tail buys very little, and the
 * value worth choosing sits near the bottom of the measured spread rather than
 * near its middle.
 *
 * Deliberately no catch-up: a frame that overruns its deadline does not cause
 * the next one to be released early. Winning the time back would reintroduce
 * exactly the unevenness the cap exists to remove.
 */
static double g_cap_period;       /* ms between frames, 0 = uncapped */
static double g_cap_next;         /* when the next frame may be released */

static double cap_wait(void) {
    if (g_cap_period <= 0.0) {
        return 0.0;
    }
    double t = now_ms();
    if (g_cap_next <= 0.0) {
        g_cap_next = t + g_cap_period;
        return 0.0;
    }
    if (t >= g_cap_next) {
        g_cap_next = t + g_cap_period;
        return 0.0;
    }
    double ms = g_cap_next - t;
    struct timespec req;
    req.tv_sec  = (time_t)(ms / 1000.0);
    req.tv_nsec = (long)((ms - (double)req.tv_sec * 1000.0) * 1.0e6);
    while (nanosleep(&req, &req) == -1 && errno == EINTR) {
        /* a signal, not a failure: finish the remainder nanosleep handed back */
    }
    g_cap_next += g_cap_period;
    return ms;
}

static EGLBoolean (*real_swap)(EGLDisplay, EGLSurface);
static __eglMustCastToProperFunctionPointerType (*real_gpa)(const char *);
static EGLBoolean (*real_query)(EGLDisplay, EGLSurface, EGLint, EGLint *);

static fb_t           g_fb;
static int            g_fb_state = -1;
static unsigned char *g_buf;
static int            g_bw, g_bh, g_frames, g_quiet;

/* --- async PBO present (FBEGL_PBO=1, OFF by default) ------------------------
 *
 * The MM+ turns this ON and gains a lot. Its measurement, in-world at 320x240:
 * the main thread was busy 57% of the frame doing app+submit and the blit,
 * while the two llvmpipe workers were saturated for the other 43% and idle the
 * rest. Reading back into a pixel-pack buffer (returns immediately) and
 * blitting the PREVIOUS frame let those two halves overlap, worth about +74%
 * for one frame of added latency.
 *
 * That argument does not obviously carry to the Nano, for two reasons:
 *
 *   1. ONE CORE. There is no second execution resource for the rasterizer to
 *      overlap into. "Main thread work" and "rasterizer work" are the same
 *      core taking turns, so removing the barrier between them mostly moves
 *      the same total work around rather than hiding it.
 *   2. SOFTPIPE, not llvmpipe. Softpipe does not defer and thread the way
 *      llvmpipe does, so there is much less in flight to overlap with.
 *
 * It also costs two full-frame pixel-pack buffers of RAM, which at 57 MB is not
 * free: 120x120 is only 115 KB, but 240x240 native is 460 KB.
 *
 * So it is built, kept, and left OFF. Turn it on with FBEGL_PBO=1 and measure
 * — do not assume either way. If it does win here that is a genuine finding
 * worth writing into the port plan; if it does not, that is one too.
 *
 * GLES3 entry points are resolved at RUNTIME rather than linked, so this object
 * still builds against GLES2 headers and degrades to the synchronous path on
 * any driver lacking them.
 */
#define FBEGL_GL_PIXEL_PACK_BUFFER 0x88EB
#define FBEGL_GL_STREAM_READ       0x88E1
#define FBEGL_GL_MAP_READ_BIT      0x0001

typedef void *(*fn_map_range)(GLenum, GLintptr, GLsizeiptr, GLbitfield);
typedef GLboolean (*fn_unmap)(GLenum);
static fn_map_range p_map_range;
static fn_unmap     p_unmap;

static int    g_pbo_want;              /* FBEGL_PBO=1 requested */
static int    g_pbo_on;                /* actually running the async path */
static GLuint g_pbo[2];
static int    g_pbo_cur, g_pbo_have_prev;
static size_t g_pbo_size;

static void *resolve_gl(const char *name) {
    void *f = dlsym(RTLD_DEFAULT, name);
    if (!f && real_gpa) f = (void *)real_gpa(name);
    return f;
}

/* Returns 1 if the async path is usable for this geometry. Any failure falls
 * back to the synchronous path and says so once — a silent fallback here would
 * look exactly like "the optimization did nothing". */
static int pbo_setup(int w, int h) {
    size_t need = (size_t)w * h * 4;
    if (!g_pbo_want) return 0;
    if (g_pbo_on && g_pbo_size == need) return 1;

    if (!p_map_range) {
        p_map_range = (fn_map_range)resolve_gl("glMapBufferRange");
        p_unmap     = (fn_unmap)resolve_gl("glUnmapBuffer");
    }
    if (!p_map_range || !p_unmap) {
        fprintf(stderr, "[fbegl] PBO unavailable (no glMapBufferRange/glUnmapBuffer) "
                        "- staying on the synchronous path\n");
        g_pbo_want = 0;
        return 0;
    }

    if (g_pbo[0] || g_pbo[1]) { glDeleteBuffers(2, g_pbo); g_pbo[0] = g_pbo[1] = 0; }
    while (glGetError() != GL_NO_ERROR) { }
    glGenBuffers(2, g_pbo);
    for (int i = 0; i < 2; i++) {
        glBindBuffer(FBEGL_GL_PIXEL_PACK_BUFFER, g_pbo[i]);
        glBufferData(FBEGL_GL_PIXEL_PACK_BUFFER, (GLsizeiptr)need, NULL, FBEGL_GL_STREAM_READ);
    }
    glBindBuffer(FBEGL_GL_PIXEL_PACK_BUFFER, 0);
    if (glGetError() != GL_NO_ERROR || !g_pbo[0] || !g_pbo[1]) {
        fprintf(stderr, "[fbegl] PBO allocation failed (%zu bytes x2) "
                        "- staying on the synchronous path\n", need);
        g_pbo_want = 0; g_pbo_on = 0;
        return 0;
    }
    g_pbo_size = need; g_pbo_cur = 0; g_pbo_have_prev = 0; g_pbo_on = 1;
    fprintf(stderr, "[fbegl] async PBO present ENABLED (%dx%d, 2 x %zu bytes, "
                    "1 frame of latency)\n", w, h, need);
    return 1;
}

static void resolve(void) {
    real_swap  = (EGLBoolean (*)(EGLDisplay, EGLSurface))dlsym(RTLD_NEXT, "eglSwapBuffers");
    real_gpa   = (__eglMustCastToProperFunctionPointerType (*)(const char *))dlsym(RTLD_NEXT, "eglGetProcAddress");
    real_query = (EGLBoolean (*)(EGLDisplay, EGLSurface, EGLint, EGLint *))dlsym(RTLD_NEXT, "eglQuerySurface");
    if (!real_swap) {                                  /* fallback: explicit handle */
        void *h = dlopen("librealEGL.so", RTLD_NOW | RTLD_GLOBAL);
        if (h) {
            real_swap  = (EGLBoolean (*)(EGLDisplay, EGLSurface))dlsym(h, "eglSwapBuffers");
            real_gpa   = (__eglMustCastToProperFunctionPointerType (*)(const char *))dlsym(h, "eglGetProcAddress");
            real_query = (EGLBoolean (*)(EGLDisplay, EGLSurface, EGLint, EGLint *))dlsym(h, "eglQuerySurface");
        }
    }
}

__attribute__((constructor))
static void fbegl_init(void) {
    const char *s = getenv("FBEGL_STATS");
    g_quiet = getenv("FBPRESENT_QUIET") != NULL;
    g_stats_n = s ? atoi(s) : 0;
    { const char *pb = getenv("FBEGL_PBO"); g_pbo_want = pb && atoi(pb) != 0; }
    { const char *fc = getenv("FBEGL_FPS_CAP");
      double cap = fc ? atof(fc) : 0.0;
      /* Below 1 fps is indistinguishable from a hang and above 60 cannot be
       * reached here, so both mean "no cap" rather than something surprising. */
      g_cap_period = (cap >= 1.0 && cap <= 60.0) ? 1000.0 / cap : 0.0; }
    if (g_stats_n < 0) g_stats_n = 0;
    resolve();
    fprintf(stderr, "[fbegl] nano wrapper init real_swap=%p real_gpa=%p real_query=%p "
                    "stats=%d pbo=%d cap=%.1ffps\n",
            (void *)real_swap, (void *)real_gpa, (void *)real_query, g_stats_n, g_pbo_want,
            g_cap_period > 0.0 ? 1000.0 / g_cap_period : 0.0);
}

static void present(EGLDisplay dpy, EGLSurface surf) {
    if (!real_query) return;
    EGLint w = 0, h = 0;
    real_query(dpy, surf, EGL_WIDTH,  &w);
    real_query(dpy, surf, EGL_HEIGHT, &h);
    if (w <= 0 || h <= 0) return;

    if (g_fb_state < 0)
        g_fb_state = (fb_open(&g_fb, "/dev/fb0") == 0) ? 0 : 1;
    if (w != g_bw || h != g_bh) {
        free(g_buf);
        g_buf = (unsigned char *)malloc((size_t)w * h * 4);
        g_bw = w; g_bh = h;
        if (!g_quiet) fprintf(stderr, "[fbegl] surface %dx%d\n", w, h);
    }
    if (g_fb_state != 0 || !g_buf) return;

    GLint prev = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    /* Report what the driver would rather hand us. If this is not
     * RGBA/UNSIGNED_BYTE we are paying a per-pixel swizzle inside Mesa's
     * readback on top of the RGB565 pack the blit already does — worth knowing
     * on a single core.
     *
     * Nano-specific follow-up worth trying if this is expensive: the panel is
     * RGB565 and Mesa can read back GL_RGB/GL_UNSIGNED_SHORT_5_6_5 directly on
     * some paths, which would delete the pack entirely. Measure first. */
    if (g_stats_n && g_frames == 0) {
        GLint fmt = 0, typ = 0;
        glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_FORMAT, &fmt);
        glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_TYPE, &typ);
        fprintf(stderr, "[fbegl] preferred read format=0x%04X type=0x%04X "
                        "(requesting GL_RGBA=0x1908 / GL_UNSIGNED_BYTE=0x1401)\n",
                (unsigned)fmt, (unsigned)typ);
    }

    /* Native 240x240 skips the scaling tables entirely. */
    int native = (w == g_fb.w && h == g_fb.h);

    if (pbo_setup(w, h)) {
        /* ASYNC PATH. Deliberately NO glFinish, not even under FBEGL_STATS: a
         * pipeline drain is the exact thing this path exists to remove, and
         * instrumenting it back in would hide its own effect. Residual stall
         * shows up as "map" time — that is the number to watch. */
        int nxt = g_pbo_cur ^ 1;
        double t0 = now_ms();
        glBindBuffer(FBEGL_GL_PIXEL_PACK_BUFFER, g_pbo[g_pbo_cur]);
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, (void *)0);
        double t1 = now_ms(), t2 = t1, t3 = t1;

        if (g_pbo_have_prev) {
            glBindBuffer(FBEGL_GL_PIXEL_PACK_BUFFER, g_pbo[nxt]);
            void *p = p_map_range(FBEGL_GL_PIXEL_PACK_BUFFER, 0,
                                  (GLsizeiptr)g_pbo_size, FBEGL_GL_MAP_READ_BIT);
            t2 = now_ms();
            if (p) {
                if (native) fb_blit_rgba(&g_fb, (const uint8_t *)p, w, h, 1);
                else        fb_blit_rgba_scaled(&g_fb, (const uint8_t *)p, w, h, 1);
                p_unmap(FBEGL_GL_PIXEL_PACK_BUFFER);
            }
            t3 = now_ms();
        }
        glBindBuffer(FBEGL_GL_PIXEL_PACK_BUFFER, 0);
        if (prev) glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev);
        g_pbo_cur = nxt;
        g_pbo_have_prev = 1;
        if (g_stats_n) { a_read += t1 - t0; a_map += t2 - t1; a_blit += t3 - t2; }

    } else if (g_stats_n) {
        double t0 = now_ms();
        glFinish();                 /* drain the rasterizer, charged separately */
        double t1 = now_ms();
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, g_buf);
        double t2 = now_ms();
        if (prev) glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev);
        if (native) fb_blit_rgba(&g_fb, g_buf, w, h, 1);
        else        fb_blit_rgba_scaled(&g_fb, g_buf, w, h, 1);
        double t3 = now_ms();
        a_finish += t1 - t0; a_read += t2 - t1; a_blit += t3 - t2;

    } else {
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, g_buf);
        if (prev) glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev);
        if (native) fb_blit_rgba(&g_fb, g_buf, w, h, 1);
        else        fb_blit_rgba_scaled(&g_fb, g_buf, w, h, 1);
    }

    if (!g_quiet && (g_frames < 3 || g_frames % 30 == 0))
        fprintf(stderr, "[fbegl] presented frame %d (%dx%d -> %dx%d)\n",
                g_frames, w, h, g_fb.w, g_fb.h);
    g_frames++;
}

EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surface) {
    if (!g_stats_n) {
        present(dpy, surface);
        EGLBoolean r = real_swap ? real_swap(dpy, surface) : EGL_TRUE;
        cap_wait();
        return r;
    }

    /* "gap" is everything that is NOT us: the game's own frame — simulation
     * plus the GL calls it issues — measured from the end of the previous swap
     * to the start of this one. It is the denominator the present cost has to
     * be judged against. On one core it is also where chunk meshing lands, so
     * expect it to dominate and to spike while walking. */
    double t0 = now_ms();
    if (g_prev_end > 0.0) a_gap += t0 - g_prev_end;
    present(dpy, surface);
    double t1 = now_ms();
    EGLBoolean r = real_swap ? real_swap(dpy, surface) : EGL_TRUE;
    double t2 = now_ms();
    a_swap += t2 - t1;
    a_cap += cap_wait();
    g_prev_end = now_ms();

    if (++g_stats_i >= g_stats_n) {
        double n = (double)g_stats_i;
        double total = a_gap + a_finish + a_read + a_blit + a_swap + a_map + a_cap;
        /* Only when capping, so an uncapped run's line is byte-identical to
         * what every earlier measurement in the notes was read off. */
        char capbuf[48];
        capbuf[0] = '\0';
        if (g_cap_period > 0.0)
            snprintf(capbuf, sizeof capbuf, " | cap %.1f", a_cap / n);
        if (g_pbo_on) {
            fprintf(stderr,
                    "[fbegl] stats n=%d PBO ms/frame: app+submit %.1f | readpx-issue %.2f | "
                    "map %.1f | blit %.1f | eglSwap %.2f%s | total %.1f (%.2f fps)\n",
                    g_stats_i, a_gap / n, a_read / n, a_map / n, a_blit / n,
                    a_swap / n, capbuf, total / n, total > 0.0 ? 1000.0 * n / total : 0.0);
        } else {
            fprintf(stderr,
                    "[fbegl] stats n=%d ms/frame: app+submit %.1f | glFinish %.1f | "
                    "readpx %.1f | blit %.1f | eglSwap %.2f%s | total %.1f "
                    "(%.2f fps) | present share %.0f%%\n",
                    g_stats_i, a_gap / n, a_finish / n, a_read / n,
                    a_blit / n, a_swap / n, capbuf, total / n,
                    total > 0.0 ? 1000.0 * n / total : 0.0,
                    total > 0.0 ? 100.0 * (a_read + a_blit) / total : 0.0);
        }
        a_gap = a_finish = a_read = a_blit = a_swap = a_map = a_cap = 0.0;
        g_stats_i = 0;
    }
    return r;
}

__eglMustCastToProperFunctionPointerType eglGetProcAddress(const char *name) {
    if (name && strcmp(name, "eglSwapBuffers") == 0)
        return (__eglMustCastToProperFunctionPointerType)eglSwapBuffers;
    return real_gpa ? real_gpa(name) : NULL;
}
