/* Exercise the production compositor with real software OpenGL/EGL. */
#include <assert.h>
#include <glad/egl.h>
#include "../build/overlay/ninecraft/src/nano_ui.c"

void *SDL_GL_GetProcAddress(const char *name) { return (void *)eglGetProcAddress(name); }
void add_custom_hook(char *name, void *address) { (void)name; (void)address; }
void *android_dlsym(void *handle, const char *name) { (void)handle; (void)name; return NULL; }

static void expect_rect(GLenum what, int x, int y, int w, int h)
{
    GLint rect[4]; glGetIntegerv(what, rect);
    assert(rect[0] == x && rect[1] == y && rect[2] == w && rect[3] == h);
}

static void fake_world(void *calls, float alpha)
{
    ++*(int *)calls; assert(alpha == 0.25f);
    GLint bound; glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &bound);
    assert((GLuint)bound == world_fbo && world_active);
    game_viewport(0, 0, 240, 240);
    expect_rect(GL_VIEWPORT, 0, 0, 120, 120);
    game_scissor(3, 5, 5, 7);
    expect_rect(GL_SCISSOR_BOX, 1, 2, 3, 4);
    game_scissor(3, -3, 0, 0);
    expect_rect(GL_SCISSOR_BOX, 1, -2, 0, 0);
    glDisable(GL_SCISSOR_TEST);
    glClearColor(0, 0, 1, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    glEnable(GL_SCISSOR_TEST);
    game_scissor(20, 0, 2, 240);
    glClearColor(1, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
    game_scissor(0, 24, 240, 2);
    glClearColor(0, 1, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
    glDisable(GL_SCISSOR_TEST);
}

static void quad(int x, int y, int w, int h)
{
    glBegin(GL_QUADS);
    glVertex2i(x, y); glVertex2i(x+w, y);
    glVertex2i(x+w, y+h); glVertex2i(x, y+h);
    glEnd();
}

static void pixel(int x, int y, int r, int g, int b)
{
    unsigned char p[4]; glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p);
    assert(abs((int)p[0]-r) <= 1 && abs((int)p[1]-g) <= 1 && abs((int)p[2]-b) <= 1);
}

int main(int argc, char **argv)
{
    assert(gladLoaderLoadEGL(EGL_NO_DISPLAY));
    /* eglGetPlatformDisplay is EGL 1.5 core, and a vendor library only advertises
     * that version through an initialized display, so the no-display load can
     * leave it null. EGL_EXT_platform_base is a client extension and is loaded
     * either way; both spellings take the same arguments. */
    assert(eglGetPlatformDisplay || eglGetPlatformDisplayEXT);
    EGLDisplay display = eglGetPlatformDisplay
        ? eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL)
        : eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
    assert(display != EGL_NO_DISPLAY);
    EGLint major, minor, count;
    assert(eglInitialize(display, &major, &minor));
    assert(gladLoaderLoadEGL(display));
    assert(eglBindAPI(EGL_OPENGL_API));
    EGLint attributes[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24, EGL_STENCIL_SIZE, 8, EGL_NONE };
    EGLConfig config; assert(eglChooseConfig(display, attributes, &config, 1, &count) && count);
    EGLint dimensions[] = { EGL_WIDTH, 240, EGL_HEIGHT, 240, EGL_NONE };
    EGLSurface surface = eglCreatePbufferSurface(display, config, dimensions);
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, NULL);
    assert(eglMakeCurrent(display, surface, surface, context));
    assert(gladLoadGL((GLADloadfunc)eglGetProcAddress));
    printf("GL test: %s / %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));

    int w = 120, h = 120;
    unsetenv("NINECRAFT_NATIVE_UI"); nano_ui_configure(&w, &h);
    assert(!requested && w == 120 && h == 120);
    setenv("NINECRAFT_NATIVE_UI", "1", 1); nano_ui_configure(&w, &h);
    assert(requested && w == 240 && h == 240);
    assert(setup_targets()); installed = 1; original_render = fake_world;
    int calls = 0;
    for (int frame = 0; frame < 3; ++frame) {
        glViewport(0, 0, 240, 240);
        glDisable(GL_SCISSOR_TEST);
        glDepthMask(GL_TRUE); glClearDepth(0); glClear(GL_DEPTH_BUFFER_BIT);
        glDepthMask(GL_FALSE); glStencilMask(0x3);
        render_level(&calls, 0.25f);
        assert(!world_active);
        expect_rect(GL_VIEWPORT, 0, 0, 240, 240);
        expect_rect(GL_SCISSOR_BOX, 0, 24, 240, 2);
        GLint bound; glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &bound); assert(bound == 0);
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &bound); assert(bound == 0);
        GLboolean mask; glGetBooleanv(GL_DEPTH_WRITEMASK, &mask); assert(!mask);
        glGetIntegerv(GL_STENCIL_WRITEMASK, &bound); assert(bound == 3);
        assert(!glIsEnabled(GL_SCISSOR_TEST));
        /* World details occupy two native pixels, never four. */
        pixel(19, 40, 0, 0, 255); pixel(20, 40, 255, 0, 0);
        pixel(21, 40, 255, 0, 0); pixel(22, 40, 0, 0, 255);
        pixel(30, 24, 0, 255, 0); pixel(30, 25, 0, 255, 0);
        pixel(30, 26, 0, 0, 255);
        /* UI is drawn afterwards; a one-native-pixel stroke stays one pixel. */
        glEnable(GL_SCISSOR_TEST); game_scissor(50, 0, 1, 240);
        expect_rect(GL_SCISSOR_BOX, 50, 0, 1, 240);
        glClearColor(1, 1, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        glDisable(GL_SCISSOR_TEST);
        pixel(49, 40, 0, 0, 255); pixel(50, 40, 255, 255, 0); pixel(51, 40, 0, 0, 255);
        glMatrixMode(GL_PROJECTION); glLoadIdentity(); glOrtho(0, 240, 0, 240, -1, 1);
        glMatrixMode(GL_MODELVIEW); glLoadIdentity();
        glEnable(GL_DEPTH_TEST); glDepthFunc(GL_LESS); glDepthMask(GL_TRUE);
        glColor4f(1, 1, 1, 1); quad(70, 30, 2, 2);
        pixel(70, 30, 255, 255, 255); /* UI depth was freshly cleared. */
        glDisable(GL_DEPTH_TEST);
        glEnable(GL_BLEND); glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glColor4f(1, 0, 0, 0.5f); quad(100, 100, 20, 20);
        pixel(110, 110, 128, 0, 127); glDisable(GL_BLEND);
        assert(glGetError() == GL_NO_ERROR);
    }
    assert(calls == 3);
    if (argc == 2) {
        unsigned char pixels[240*240*3]; glReadPixels(0, 0, 240, 240, GL_RGB, GL_UNSIGNED_BYTE, pixels);
        FILE *f = fopen(argv[1], "wb"); assert(f); fprintf(f, "P6\n240 240\n255\n");
        for (int y=239; y>=0; --y) fwrite(pixels+y*240*3, 3, 240, f);
        fclose(f);
    }
    p_bind_fbo(GL_DRAW_FRAMEBUFFER, world_fbo);
    assert(!begin_world()); /* Another framebuffer is never redirected. */
    p_bind_fbo(GL_FRAMEBUFFER, 0);
    nano_ui_shutdown(); assert(!installed && !world_fbo);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display, context); eglDestroySurface(display, surface); eglTerminate(display);
    puts("PASS: real GL world at 120, UI at 240, odd/empty scissors, depth, alpha, state, repeat frames and cleanup");
}
