/* Native 240x240 UI over a 120x120 world, for the verified PE 0.8.1 renderer.
 * The world pass keeps the game's camera/projection and draws into its own
 * color/depth/stencil attachments. A nearest-neighbor color blit precedes
 * the game's normal HUD and Screen rendering. No world-sized UI screenshot
 * is enlarged, and no item/text rendering is reimplemented here. */
#include <ninecraft/gfx/nano_ui.h>
#include <ninecraft/version_ids.h>
#include <ancmp/android_dlfcn.h>
#include <ancmp/hooks.h>
#include <ancmp/abi_fix.h>
#include <SDL.h>
#include <glad/gl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <sys/mman.h>
#include <unistd.h>
#endif

static int requested, installed, world_active;
static int world_w, world_h, canvas_w, canvas_h;
static GLuint world_fbo, color_buffer, depth_buffer;
static GLint saved_read, saved_draw;
static GLint logical_scissor[4];
static unsigned world_frames;

/* Explicitly resolve the core/ARB or EXT family: the advertised context is
 * GL 2.1, where framebuffer objects/blits are extensions, not core promises. */
static PFNGLGENFRAMEBUFFERSPROC p_gen_fbo;
static PFNGLBINDFRAMEBUFFERPROC p_bind_fbo;
static PFNGLDELETEFRAMEBUFFERSPROC p_delete_fbo;
static PFNGLCHECKFRAMEBUFFERSTATUSPROC p_check_fbo;
static PFNGLGENRENDERBUFFERSPROC p_gen_rb;
static PFNGLBINDRENDERBUFFERPROC p_bind_rb;
static PFNGLDELETERENDERBUFFERSPROC p_delete_rb;
static PFNGLRENDERBUFFERSTORAGEPROC p_rb_storage;
static PFNGLFRAMEBUFFERRENDERBUFFERPROC p_attach_rb;
static PFNGLBLITFRAMEBUFFERPROC p_blit;

typedef void (FLOAT_ABI_FIX *level_render_fn)(void *, float);
static level_render_fn original_render;
#if defined(__arm__) && !defined(_WIN32)
static void *trampoline;
static unsigned char *render_entry;
static size_t page_size;
static const uint32_t expected_prologue[2] = { 0x4ff0e92d, 0x8b04ed2d };
#endif

void nano_ui_configure(int *width, int *height)
{
    const char *value = getenv("NINECRAFT_NATIVE_UI");
    requested = value && !strcmp(value, "1") && *width == 120 && *height == 120;
    world_w = *width;
    world_h = *height;
    if (requested) *width = *height = 240;
    canvas_w = *width;
    canvas_h = *height;
}

/* Floor the starting edge and ceil the ending edge, including negative
 * origins. This keeps odd native-pixel scissor rectangles from losing a row. */
static int floor_half(int value)
{
    return value / 2 - (value < 0 && value % 2 != 0);
}

static void half_rect(GLint *x, GLint *y, GLsizei *width, GLsizei *height)
{
    int empty_w = *width == 0, empty_h = *height == 0;
    int right = floor_half(*x + *width) + ((*x + *width) % 2 != 0);
    int top = floor_half(*y + *height) + ((*y + *height) % 2 != 0);
    *x = floor_half(*x);
    *y = floor_half(*y);
    *width = empty_w ? 0 : right - *x;
    *height = empty_h ? 0 : top - *y;
}

static void game_viewport(GLint x, GLint y, GLsizei width, GLsizei height)
{
    if (world_active && width >= 0 && height >= 0)
        half_rect(&x, &y, &width, &height);
    glViewport(x, y, width, height);
}

static void game_scissor(GLint x, GLint y, GLsizei width, GLsizei height)
{
    if (world_active && width >= 0 && height >= 0) {
        logical_scissor[0] = x; logical_scissor[1] = y;
        logical_scissor[2] = width; logical_scissor[3] = height;
        half_rect(&x, &y, &width, &height);
    }
    glScissor(x, y, width, height);
}

void nano_ui_register_gl_hooks(void)
{
    if (!requested) return;
    /* Called after gles_hook and before loading the game, so its imported
     * viewport/scissor functions use these replacements. */
    add_custom_hook("glViewport", (void *)game_viewport);
    add_custom_hook("glScissor", (void *)game_scissor);
}

static int extension_present(const char *name)
{
    const char *extensions = (const char *)glGetString(GL_EXTENSIONS);
    size_t length = strlen(name);
    if (!extensions) return 0;
    for (const char *p = extensions; (p = strstr(p, name)); p += length)
        if ((p == extensions || p[-1] == ' ') &&
            (p[length] == ' ' || p[length] == '\0')) return 1;
    return 0;
}

static void delete_targets(void)
{
    if (depth_buffer) p_delete_rb(1, &depth_buffer);
    if (color_buffer) p_delete_rb(1, &color_buffer);
    if (world_fbo) p_delete_fbo(1, &world_fbo);
    depth_buffer = color_buffer = world_fbo = 0;
}

static int setup_targets(void)
{
    const char *suffix;
    if (extension_present("GL_ARB_framebuffer_object")) suffix = "";
    else if (extension_present("GL_EXT_framebuffer_object") &&
             extension_present("GL_EXT_framebuffer_blit") &&
             extension_present("GL_EXT_packed_depth_stencil")) suffix = "EXT";
    else return 0;

#define RESOLVE(member, type, name) do { \
    char symbol[80]; snprintf(symbol, sizeof symbol, "%s%s", name, suffix); \
    member = (type)SDL_GL_GetProcAddress(symbol); \
    if (!member) return 0; \
} while (0)
    RESOLVE(p_gen_fbo, PFNGLGENFRAMEBUFFERSPROC, "glGenFramebuffers");
    RESOLVE(p_bind_fbo, PFNGLBINDFRAMEBUFFERPROC, "glBindFramebuffer");
    RESOLVE(p_delete_fbo, PFNGLDELETEFRAMEBUFFERSPROC, "glDeleteFramebuffers");
    RESOLVE(p_check_fbo, PFNGLCHECKFRAMEBUFFERSTATUSPROC, "glCheckFramebufferStatus");
    RESOLVE(p_gen_rb, PFNGLGENRENDERBUFFERSPROC, "glGenRenderbuffers");
    RESOLVE(p_bind_rb, PFNGLBINDRENDERBUFFERPROC, "glBindRenderbuffer");
    RESOLVE(p_delete_rb, PFNGLDELETERENDERBUFFERSPROC, "glDeleteRenderbuffers");
    RESOLVE(p_rb_storage, PFNGLRENDERBUFFERSTORAGEPROC, "glRenderbufferStorage");
    RESOLVE(p_attach_rb, PFNGLFRAMEBUFFERRENDERBUFFERPROC, "glFramebufferRenderbuffer");
    RESOLVE(p_blit, PFNGLBLITFRAMEBUFFERPROC, "glBlitFramebuffer");
#undef RESOLVE

    GLint read, draw, rb;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &draw);
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &rb);
    p_gen_fbo(1, &world_fbo);
    p_bind_fbo(GL_FRAMEBUFFER, world_fbo);
    p_gen_rb(1, &color_buffer);
    p_bind_rb(GL_RENDERBUFFER, color_buffer);
    p_rb_storage(GL_RENDERBUFFER, GL_RGBA8, world_w, world_h);
    p_attach_rb(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, color_buffer);
    p_gen_rb(1, &depth_buffer);
    p_bind_rb(GL_RENDERBUFFER, depth_buffer);
    p_rb_storage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, world_w, world_h);
    p_attach_rb(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depth_buffer);
    p_attach_rb(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, depth_buffer);
    int complete = p_check_fbo(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
    if (complete) {
        /* The game may scissor the world behind an inventory pane. Initialize
         * pixels outside that first scissor before ever copying this buffer. */
        glPushAttrib(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT |
                     GL_STENCIL_BUFFER_BIT | GL_SCISSOR_BIT);
        glDisable(GL_SCISSOR_TEST);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glDepthMask(GL_TRUE);
        glStencilMask(~0u);
        glClearColor(0, 0, 0, 1);
        glClearDepth(1);
        glClearStencil(0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
        glPopAttrib();
    }
    p_bind_rb(GL_RENDERBUFFER, (GLuint)rb);
    p_bind_fbo(GL_READ_FRAMEBUFFER, (GLuint)read);
    p_bind_fbo(GL_DRAW_FRAMEBUFFER, (GLuint)draw);
    if (!complete) delete_targets();
    return complete;
}

static int begin_world(void)
{
    if (!installed || world_active) return 0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &saved_read);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &saved_draw);
    /* This 0.8.1 pass draws to the window. Do not redirect another mod's FBO. */
    if (saved_draw != 0) return 0;
    glGetIntegerv(GL_SCISSOR_BOX, logical_scissor);
    p_bind_fbo(GL_FRAMEBUFFER, world_fbo);
    world_active = 1;
    game_viewport(0, 0, canvas_w, canvas_h);
    game_scissor(logical_scissor[0], logical_scissor[1],
                 logical_scissor[2], logical_scissor[3]);
    return 1;
}

static void end_world(void)
{
    world_active = 0;
    p_bind_fbo(GL_READ_FRAMEBUFFER, world_fbo);
    p_bind_fbo(GL_DRAW_FRAMEBUFFER, (GLuint)saved_draw);
    glPushAttrib(GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT | GL_SCISSOR_BIT);
    glDisable(GL_SCISSOR_TEST); /* A blit is clipped by the scissor test. */
    p_blit(0, 0, world_w, world_h, 0, 0, canvas_w, canvas_h,
           GL_COLOR_BUFFER_BIT, GL_NEAREST);
    /* HUD item icons use depth testing. They must not see last frame's UI
     * depth buffer, or the world buffer's unrelated depth/stencil contents. */
    glDepthMask(GL_TRUE);
    glStencilMask(~0u);
    glClearDepth(1);
    glClearStencil(0);
    glClear(GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    glPopAttrib();
    p_bind_fbo(GL_READ_FRAMEBUFFER, (GLuint)saved_read);
    glViewport(0, 0, canvas_w, canvas_h);
    glScissor(logical_scissor[0], logical_scissor[1],
              logical_scissor[2], logical_scissor[3]);
    if (++world_frames == 1) {
        printf("[native-ui] world pass %dx%d -> %dx%d; HUD/screens render next at native resolution\n",
               world_w, world_h, canvas_w, canvas_h);
        fflush(stdout);
    }
}

static FLOAT_ABI_FIX void render_level(void *renderer, float alpha)
{
    int redirected = begin_world();
    original_render(renderer, alpha);
    if (redirected) end_world();
}

int nano_ui_install(void *game, int version)
{
    if (!requested) return 0;
#if defined(__arm__) && !defined(_WIN32)
    void *symbol = android_dlsym(game, "_ZN12GameRenderer11renderLevelEf");
    void *outer = android_dlsym(game, "_ZN12GameRenderer6renderEf");
    render_entry = (unsigned char *)((uintptr_t)symbol & ~(uintptr_t)1);
    /* Verified build: renderLevel begins with two complete, position-independent
     * instructions (push r4-r11/lr; vpush d8-d9). Copying arbitrary Thumb
     * instructions to a trampoline would break PC-relative loads/branches. */
    if (version != version_id_0_8_1 || !symbol || !outer ||
        !((uintptr_t)symbol & 1) || ((uintptr_t)render_entry & 3) ||
        (uintptr_t)outer - (uintptr_t)symbol != 0x38c ||
        memcmp(render_entry, expected_prologue, sizeof expected_prologue)) {
        fprintf(stderr, "[native-ui] unsupported renderer; using original rendering\n");
        return 0;
    }
    if (!setup_targets()) {
        fprintf(stderr, "[native-ui] framebuffer/blit unavailable; using original rendering\n");
        return 0;
    }
    long size = sysconf(_SC_PAGESIZE);
    if (size <= 0) { delete_targets(); return 0; }
    page_size = (size_t)size;
    trampoline = mmap(NULL, page_size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (trampoline == MAP_FAILED) { trampoline = NULL; delete_targets(); return 0; }
    uint32_t *code = (uint32_t *)trampoline;
    memcpy(code, expected_prologue, 8);
    code[2] = 0xf000f8df; /* Thumb ldr.w pc, [pc, #0], aligned literal follows. */
    code[3] = (uint32_t)(uintptr_t)(render_entry + 8) | 1u;
    if (mprotect(trampoline, page_size, PROT_READ | PROT_EXEC)) {
        munmap(trampoline, page_size); trampoline = NULL; delete_targets(); return 0;
    }
    __builtin___clear_cache((char *)trampoline, (char *)trampoline + 16);
    void *page = (void *)((uintptr_t)render_entry & ~(page_size - 1));
    if (mprotect(page, page_size, PROT_READ | PROT_WRITE | PROT_EXEC)) {
        munmap(trampoline, page_size); trampoline = NULL; delete_targets(); return 0;
    }
    original_render = (level_render_fn)((uintptr_t)trampoline | 1u);
    uint32_t patch[2] = { 0xf000f8df, (uint32_t)(uintptr_t)render_level };
    memcpy(render_entry, patch, sizeof patch);
    __builtin___clear_cache((char *)render_entry, (char *)render_entry + 8);
    if (mprotect(page, page_size, PROT_READ | PROT_EXEC))
        fprintf(stderr, "[native-ui] could not restore renderer page protection\n");
    installed = 1;
    printf("[native-ui] enabled: world=%dx%d UI=%dx%d, framebuffer complete\n",
           world_w, world_h, canvas_w, canvas_h);
    fflush(stdout);
    return 1;
#else
    (void)game; (void)version;
    return 0;
#endif
}

void nano_ui_shutdown(void)
{
    /* The hook remains installed until process exit. Mark it inactive before
     * deleting attachments; do not free a trampoline that a later destructor
     * could still call. The process reclaims its single code page on exit. */
    installed = 0;
    if (world_fbo) delete_targets();
}
