/* fb_nano.h — /dev/fb0 blit for the Anbernic RG Nano (DrUm78 / FunKey OS).
 *
 * Forked from the Miyoo Mini Plus port's smoke/src/fb.h. Same job — take the
 * RGBA8 buffer glReadPixels hands back and get it onto the panel — but almost
 * none of the MM+ code survives contact with this display:
 *
 *   MM+                                  Nano
 *   640x480                              240x240 (square)
 *   BGRA, 32 bpp, one aligned word/px    RGB565, 16 bpp, needs packing
 *   panel mounted 180 degrees            UNKNOWN, so it is a runtime switch
 *   307,200 px/frame fixed present tax   57,600 px/frame, 2 bytes each
 *
 * That last line is the one good piece of news in this whole fork: the MM+
 * notes call its blit "a FIXED per-frame tax that lowering MCPE_W/MCPE_H does
 * not reduce", and here that tax is about a tenth of the bytes.
 *
 * Ground truth for this panel, from the device's own boot log and a live probe:
 *   fb_st7789v, 240x240, virtual 240x720, RGB565, line_length=480,
 *   smem_len=115200, ~337 KiB video memory (triple-buffer-ish), SPI 50-75 MHz.
 *
 * STATUS: compiles, never run on hardware. The orientation switch exists
 * because guessing wrong is the single most likely first-run surprise.
 */
#ifndef NANO_FB_H
#define NANO_FB_H

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <linux/fb.h>

typedef struct {
    int      fd;
    uint8_t *mem;
    size_t   size;
    int      w, h, bpp, line;
    int      rot;            /* 0 or 180 — see fb_open() */
    uint8_t *saved;          /* page 0 contents at open, restored on close */
} fb_t;

/* Panel orientation.
 *
 * The MM+ panel is physically mounted upside down and its fb.h bakes a 180
 * degree rotation into the blit. NOBODY HAS CHECKED THE NANO'S. Rather than
 * guess and ship an upside-down game, read it from the environment:
 *
 *   FBNANO_ROT=0     no rotation (default)
 *   FBNANO_ROT=180   rotate 180 degrees
 *
 * One launch settles it. When it is known, change the default here and leave
 * the override in place — it costs nothing and documents the finding.
 */
static inline int fb_env_rot(void) {
    const char *e = getenv("FBNANO_ROT");
    return (e && atoi(e) == 180) ? 180 : 0;
}

static inline int fb_open(fb_t *fb, const char *dev) {
    memset(fb, 0, sizeof(*fb));
    fb->fd = open(dev ? dev : "/dev/fb0", O_RDWR);
    if (fb->fd < 0) { perror("open /dev/fb0"); return -1; }

    struct fb_var_screeninfo vi;
    struct fb_fix_screeninfo fi;
    if (ioctl(fb->fd, FBIOGET_VSCREENINFO, &vi) < 0) { perror("VSCREENINFO"); return -1; }
    if (ioctl(fb->fd, FBIOGET_FSCREENINFO, &fi) < 0) { perror("FSCREENINFO"); return -1; }

    fb->w    = vi.xres;
    fb->h    = vi.yres;
    fb->bpp  = vi.bits_per_pixel;
    fb->line = fi.line_length ? (int)fi.line_length : fb->w * (fb->bpp / 8);
    fb->size = fi.smem_len ? fi.smem_len : (size_t)fb->line * fb->h;
    fb->rot  = fb_env_rot();

    fb->mem = mmap(NULL, fb->size, PROT_READ | PROT_WRITE, MAP_SHARED, fb->fd, 0);
    if (fb->mem == MAP_FAILED) { perror("mmap /dev/fb0"); return -1; }

    fprintf(stderr, "fb: %dx%d bpp=%d line=%d size=%zu virtual=%ux%u pan=%u,%u rot=%d\n",
            fb->w, fb->h, fb->bpp, fb->line, fb->size,
            vi.xres_virtual, vi.yres_virtual, vi.xoffset, vi.yoffset, fb->rot);

    if (fb->bpp != 16)
        fprintf(stderr, "fb: WARNING bpp=%d, this panel is documented as RGB565/16 — "
                        "blits will be skipped\n", fb->bpp);

    /* Take page 0, exactly as the MM+ port learned to.
     *
     * This panel's virtual height is 240x720 — three pages — and whatever was
     * drawing before us may have left the display panned to page 1 or 2. Every
     * blit below targets page 0, so if we do not pan back we render perfectly
     * into a page nobody can see: the process is alive, burning the core,
     * presenting frames, and the screen never changes. From the outside that is
     * indistinguishable from "it will not start", and it is intermittent in the
     * worst way because it depends on where the previous app left the pan.
     *
     * The MM+ hit this live on a double-buffered panel; this one has more pages
     * to get lost in, not fewer. Non-fatal if the ioctl fails — say so, carry on.
     */
    if (vi.xoffset != 0 || vi.yoffset != 0) {
        struct fb_var_screeninfo pan = vi;
        pan.xoffset = 0;
        pan.yoffset = 0;
        if (ioctl(fb->fd, FBIOPAN_DISPLAY, &pan) == 0)
            fprintf(stderr, "fb: panned %u,%u -> 0,0 (page 0 is what we blit)\n",
                    vi.xoffset, vi.yoffset);
        else
            perror("fb: FBIOPAN_DISPLAY (screen may stay blank)");
    }

    /* Save page 0 so fb_close() can put the launcher's screen back. The
     * previous Nano fork's smoke test did this and it is the difference between
     * quitting to GMenu2X and quitting to a frozen last frame. One page only:
     * 240*480 = 112 KiB, which is real money on a 57 MB device but worth it. */
    size_t page = (size_t)fb->line * fb->h;
    if (page <= fb->size && (fb->saved = (uint8_t *)malloc(page)) != NULL)
        memcpy(fb->saved, fb->mem, page);

    return 0;
}

/* RGBA8 (GL channel order) -> RGB565 little-endian, the panel's format. */
static inline uint16_t fb_pack565(uint8_t r, uint8_t g, uint8_t b) {
    return (uint16_t)(((uint16_t)(r & 0xF8) << 8) |
                      ((uint16_t)(g & 0xFC) << 3) |
                      ((uint16_t)(b) >> 3));
}

#ifndef FB_MAXDIM
#define FB_MAXDIM 1024
#endif

/* Nearest-neighbour upscale of src (w*h RGBA8) to the full panel, packed to
 * RGB565. gl_bottom_up != 0 means row 0 of src is the BOTTOM of the image,
 * which is what glReadPixels gives you.
 *
 * The optimisations carried over from the MM+ blit, and why they still apply:
 *
 *   1. The source x/y mapping is two precomputed tables, rebuilt only when the
 *      geometry changes. The naive form needs an integer divide per pixel and
 *      Cortex-A7 divides are slow. Same core here, same problem.
 *
 *   2. Pixels are written as 16-bit halfword stores rather than two byte
 *      stores. Framebuffer memory is uncached device memory where each store
 *      can become its own bus transaction, so halving the store count is a
 *      direct win. Alignment holds because line_length (480) is even.
 *
 * What is NOT carried over is the MM+'s 32-bit-word trick — there is no 32-bit
 * pixel here. Writing pairs of 565 pixels as one word is a possible future
 * optimisation but only when the two source pixels are adjacent in the
 * destination, which the rotation path breaks. Not worth the complexity until
 * a profile says the blit matters, and at 57,600 pixels it probably will not.
 */
static inline void fb_blit_rgba_scaled(fb_t *fb, const uint8_t *src,
                                       int w, int h, int gl_bottom_up) {
    if (fb->bpp != 16) return;
    if (fb->w > FB_MAXDIM || fb->h > FB_MAXDIM) return;

    static int xmap[FB_MAXDIM], ymap[FB_MAXDIM];
    static int c_w, c_h, c_fw, c_fh, c_bu, c_rot;
    if (w != c_w || h != c_h || fb->w != c_fw || fb->h != c_fh ||
        gl_bottom_up != c_bu || fb->rot != c_rot) {
        for (int fx = 0; fx < fb->w; fx++) xmap[fx] = fx * w / fb->w;
        for (int fy = 0; fy < fb->h; fy++) {
            int sy0 = fy * h / fb->h;
            ymap[fy] = gl_bottom_up ? (h - 1 - sy0) : sy0;
        }
        c_w = w; c_h = h; c_fw = fb->w; c_fh = fb->h;
        c_bu = gl_bottom_up; c_rot = fb->rot;
    }

    for (int fy = 0; fy < fb->h; fy++) {
        const uint8_t *srow = src + (size_t)ymap[fy] * w * 4;

        if (fb->rot == 180) {
            /* Destination row runs bottom-up AND right-to-left, so walk a
             * pointer backwards instead of recomputing fb->w-1-fx per pixel. */
            uint16_t *d = (uint16_t *)(fb->mem + (size_t)(fb->h - 1 - fy) * fb->line)
                        + (fb->w - 1);
            for (int fx = 0; fx < fb->w; fx++) {
                const uint8_t *s = srow + (size_t)xmap[fx] * 4;
                *d-- = fb_pack565(s[0], s[1], s[2]);
            }
        } else {
            uint16_t *d = (uint16_t *)(fb->mem + (size_t)fy * fb->line);
            for (int fx = 0; fx < fb->w; fx++) {
                const uint8_t *s = srow + (size_t)xmap[fx] * 4;
                *d++ = fb_pack565(s[0], s[1], s[2]);
            }
        }
    }
}

/* Unscaled 1:1 blit, for the smoke harness and for the 240x240 native mode
 * where the scaled path's table lookups are pure overhead. */
static inline void fb_blit_rgba(fb_t *fb, const uint8_t *src,
                                int w, int h, int gl_bottom_up) {
    if (fb->bpp != 16) return;
    int rows = h < fb->h ? h : fb->h;
    int cols = w < fb->w ? w : fb->w;
    for (int y = 0; y < rows; y++) {
        int sy = gl_bottom_up ? (h - 1 - y) : y;
        const uint8_t *srow = src + (size_t)sy * w * 4;
        if (fb->rot == 180) {
            uint16_t *d = (uint16_t *)(fb->mem + (size_t)(fb->h - 1 - y) * fb->line)
                        + (fb->w - 1);
            for (int x = 0; x < cols; x++) {
                const uint8_t *s = srow + (size_t)x * 4;
                *d-- = fb_pack565(s[0], s[1], s[2]);
            }
        } else {
            uint16_t *d = (uint16_t *)(fb->mem + (size_t)y * fb->line);
            for (int x = 0; x < cols; x++) {
                const uint8_t *s = srow + (size_t)x * 4;
                *d++ = fb_pack565(s[0], s[1], s[2]);
            }
        }
    }
}

static inline void fb_close(fb_t *fb) {
    if (fb->saved && fb->mem && fb->mem != MAP_FAILED) {
        memcpy(fb->mem, fb->saved, (size_t)fb->line * fb->h);
        free(fb->saved);
        fb->saved = NULL;
    }
    if (fb->mem && fb->mem != MAP_FAILED) munmap(fb->mem, fb->size);
    if (fb->fd >= 0) close(fb->fd);
}

#endif /* NANO_FB_H */
