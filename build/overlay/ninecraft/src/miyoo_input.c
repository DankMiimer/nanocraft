/* Direct Miyoo Mini Plus input for SDL's offscreen video driver.
 *
 * Offscreen SDL has no keyboard or mouse backend, so read the console's
 * gpio_keys device and publish normal SDL events for Ninecraft's existing
 * keyboard/mouse callbacks.  The layout mirrors the Bedrock 1.2 Onion port:
 *
 *   D-pad       move                         X/B/Y/A  look up/down/left/right
 *   L1          use/place (right click)      R1       attack/break (left click)
 *   SELECT      previous hotbar slot         START    next hotbar slot
 *   L2          pause                        MENU     hold two seconds to quit
 *   hold R2     X=craft, B=sneak, Y=inventory, A=jump
 *
 * In menus the d-pad and unmodified face buttons move a virtual cursor. R1
 * clicks; R2+A also clicks and R2+B goes back, matching the 1.2 modifier habit.
 */
#include <ninecraft/input/miyoo_input.h>
#include <ninecraft/input/sensitivity.h>
#include <glad/gl.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define QUIT_HOLD_MS 2000u
#define MIN_PRESS_MS 120u
#define LOOK_BASE_PER_TICK 1.6f
#define LOOK_MAX_PER_TICK 11.0f
#define LOOK_RAMP_MS 550.0f

enum {
    MB_MENU = 1,    MB_R2 = 14,     MB_L2 = 15,     MB_L1 = 18,
    MB_R1 = 20,     MB_START = 28,  MB_B = 29,      MB_X = 42,
    MB_Y = 56,      MB_A = 57,      MB_SELECT = 97, MB_UP = 103,
    MB_LEFT = 105,  MB_RIGHT = 106, MB_DOWN = 108,
};

extern bool mouse_pointer_hidden;

static int input_fd = -1;
static int input_grabbed;
static unsigned char physical_held[KEY_MAX + 1];
static unsigned char held[KEY_MAX + 1];
static Uint32 held_since[KEY_MAX + 1];
static Uint32 release_at[KEY_MAX + 1];
static SDL_Keycode face_action[KEY_MAX + 1];
static unsigned char face_click[KEY_MAX + 1];
static int move_sent[4];
static int cursor_x;
static int cursor_y;
static float carry_x;
static float carry_y;
static Uint32 last_tick;
static int quit_sent;
static nc_sensitivity sensitivity = { NC_CAMERA_DEFAULT, NC_CURSOR_DEFAULT };
static const char *sensitivity_path;
static int sensitivity_enabled;
static Uint32 sensitivity_checked;
static int last_in_world;

static void reload_sensitivity(Uint32 now) {
    if (!sensitivity_path) return;
    nc_sensitivity next = nc_sensitivity_read(sensitivity_path);
    if (next.camera != sensitivity.camera || next.cursor != sensitivity.cursor) {
        carry_x = carry_y = 0.0f;
        fprintf(stderr, "[input] camera=%d%% cursor=%d%%\n", next.camera, next.cursor);
    }
    sensitivity = next;
    sensitivity_checked = now;
}

static void push_key(SDL_Keycode key, int down) {
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = down ? SDL_KEYDOWN : SDL_KEYUP;
    event.key.type = event.type;
    event.key.state = down ? SDL_PRESSED : SDL_RELEASED;
    event.key.repeat = 0;
    event.key.keysym.sym = key;
    event.key.keysym.scancode = SDL_GetScancodeFromKey(key);
    SDL_PushEvent(&event);
}

static void push_click(Uint8 button, int down) {
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = down ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
    event.button.type = event.type;
    event.button.state = down ? SDL_PRESSED : SDL_RELEASED;
    event.button.button = button;
    event.button.x = cursor_x;
    event.button.y = cursor_y;
    SDL_PushEvent(&event);
}

static void push_wheel(float y) {
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = SDL_MOUSEWHEEL;
    event.wheel.type = SDL_MOUSEWHEEL;
    event.wheel.y = (int)y;
    event.wheel.preciseY = y;
    event.wheel.direction = SDL_MOUSEWHEEL_NORMAL;
    SDL_PushEvent(&event);
}

static void push_motion(SDL_Window *window, int dx, int dy) {
    int width = 720, height = 480;
    SDL_GetWindowSize(window, &width, &height);

    if (!mouse_pointer_hidden) {
        cursor_x += dx;
        cursor_y += dy;
        if (cursor_x < 0) cursor_x = 0;
        if (cursor_y < 0) cursor_y = 0;
        if (cursor_x >= width) cursor_x = width - 1;
        if (cursor_y >= height) cursor_y = height - 1;
    }

    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = SDL_MOUSEMOTION;
    event.motion.type = SDL_MOUSEMOTION;
    event.motion.x = cursor_x;
    event.motion.y = cursor_y;
    event.motion.xrel = dx;
    event.motion.yrel = dy;
    SDL_PushEvent(&event);
}

static SDL_Keycode action_for_face(unsigned int code) {
    switch (code) {
        case MB_X: return SDLK_c;
        case MB_B: return SDLK_LSHIFT;
        case MB_Y: return SDLK_e;
        case MB_A: return SDLK_SPACE;
        default: return SDLK_UNKNOWN;
    }
}

static float ramp(unsigned int code, Uint32 now) {
    if (code > KEY_MAX || !held[code]) return 0.0f;
    float t = (float)(now - held_since[code]) / LOOK_RAMP_MS;
    if (t > 1.0f) t = 1.0f;
    return LOOK_BASE_PER_TICK + (LOOK_MAX_PER_TICK - LOOK_BASE_PER_TICK) * t;
}

static void apply_button(unsigned int code, int down, Uint32 now) {
    if (code > KEY_MAX) return;

    Uint32 was_since = held_since[code];
    held[code] = down ? 1 : 0;
    held_since[code] = down ? now : 0;
    release_at[code] = 0;

    fprintf(stderr, "miyoo-input: logical code=%u %s at=%u\n",
            code, down ? "down" : "up", now);
    fflush(stderr);

    switch (code) {
        case MB_R1:
            push_click(SDL_BUTTON_LEFT, down);
            break;
        case MB_L1:
            push_click(SDL_BUTTON_RIGHT, down);
            break;
        case MB_SELECT:
            if (down) push_wheel(1.0f);
            break;
        case MB_START:
            if (down) push_wheel(-1.0f);
            break;
        case MB_L2:
            push_key(SDLK_ESCAPE, down);
            break;
        case MB_X:
        case MB_B:
        case MB_Y:
        case MB_A:
            if (down && held[MB_R2]) {
                if (!mouse_pointer_hidden && code == MB_A) {
                    face_click[code] = 1;
                    push_click(SDL_BUTTON_LEFT, 1);
                } else if (!mouse_pointer_hidden && code == MB_B) {
                    face_action[code] = SDLK_ESCAPE;
                    push_key(SDLK_ESCAPE, 1);
                } else {
                    SDL_Keycode key = action_for_face(code);
                    face_action[code] = key;
                    push_key(key, 1);
                }
            } else if (!down) {
                if (face_click[code]) push_click(SDL_BUTTON_LEFT, 0);
                if (face_action[code] != SDLK_UNKNOWN) push_key(face_action[code], 0);
                face_click[code] = 0;
                face_action[code] = SDLK_UNKNOWN;
            }
            break;
        case MB_MENU:
            if (!down && was_since && now - was_since < QUIT_HOLD_MS)
                quit_sent = 0;
            break;
        default:
            break;
    }
}

static int time_reached(Uint32 now, Uint32 deadline) {
    return (Sint32)(now - deadline) >= 0;
}

static void handle_physical_button(unsigned int code, int down, Uint32 now) {
    if (code > KEY_MAX) return;

    fprintf(stderr, "miyoo-input: physical code=%u %s at=%u\n",
            code, down ? "down" : "up", now);
    fflush(stderr);
    physical_held[code] = down ? 1 : 0;

    if (down) {
        release_at[code] = 0;
        if (!held[code]) apply_button(code, 1, now);
    } else if (held[code]) {
        Uint32 deadline = held_since[code] + MIN_PRESS_MS;
        if (time_reached(now, deadline)) {
            apply_button(code, 0, now);
        } else {
            release_at[code] = deadline;
        }
    }
}

static void apply_due_releases(Uint32 now) {
    for (unsigned int code = 0; code <= KEY_MAX; ++code) {
        if (release_at[code] && !physical_held[code] &&
                time_reached(now, release_at[code])) {
            apply_button(code, 0, now);
        }
    }
}

int miyoo_input_init(SDL_Window *window) {
    const char *enabled = getenv("NINECRAFT_MIYOO_INPUT");
    if (enabled && !strcmp(enabled, "0")) return 0;

    const char *device = getenv("MIYOO_INPUT_DEVICE");
    if (!device || !*device) device = "/dev/input/event0";

    input_fd = open(device, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (input_fd < 0) {
        fprintf(stderr, "miyoo-input: cannot open %s: %s (continuing without pad)\n",
                device, strerror(errno));
        return -1;
    }

    if (!getenv("MIYOO_NO_GRAB")) {
        if (ioctl(input_fd, EVIOCGRAB, 1) == 0) {
            input_grabbed = 1;
        } else {
            fprintf(stderr, "miyoo-input: EVIOCGRAB failed: %s\n", strerror(errno));
        }
    }

    int width = 720, height = 480;
    SDL_GetWindowSize(window, &width, &height);
    cursor_x = width / 2;
    cursor_y = height / 2;
    last_tick = SDL_GetTicks();
    last_in_world = mouse_pointer_hidden;
    sensitivity_path = getenv("NINECRAFT_INPUT_SETTINGS");
    sensitivity_enabled = sensitivity_path && *sensitivity_path;
    if (!sensitivity_enabled) sensitivity_path = NULL;
    reload_sensitivity(last_tick);
    if (sensitivity_enabled)
        fprintf(stderr, "[input] camera=%d%% cursor=%d%% (240px baseline)\n",
                sensitivity.camera, sensitivity.cursor);
    fprintf(stderr, "miyoo-input: ready on %s%s\n", device,
            input_grabbed ? " (exclusive grab)" : "");
    return 0;
}

void miyoo_input_tick(SDL_Window *window, bool *running) {
    if (input_fd < 0) return;

    Uint32 now = SDL_GetTicks();
    if ((Uint32)(now - sensitivity_checked) >= 500u)
        reload_sensitivity(now);
    struct input_event event;
    while (read(input_fd, &event, sizeof(event)) == (ssize_t)sizeof(event)) {
        if (event.type == EV_KEY && event.value != 2)
            handle_physical_button(event.code, event.value != 0, now);
    }
    apply_due_releases(now);

    if (held[MB_MENU] && !quit_sent && now - held_since[MB_MENU] >= QUIT_HOLD_MS) {
        fprintf(stderr, "miyoo-input: MENU held for two seconds, quitting\n");
        fflush(stderr);
        quit_sent = 1;
        *running = false;
        return;
    }

    static const unsigned int dpad_code[4] = { MB_UP, MB_DOWN, MB_LEFT, MB_RIGHT };
    static const SDL_Keycode dpad_key[4] = { SDLK_w, SDLK_s, SDLK_a, SDLK_d };
    for (int i = 0; i < 4; ++i) {
        int wanted = mouse_pointer_hidden && held[dpad_code[i]];
        if (wanted != move_sent[i]) {
            push_key(dpad_key[i], wanted);
            move_sent[i] = wanted;
        }
    }

    Uint32 elapsed = now - last_tick;
    last_tick = now;
    /* SIGSTOP in the quick menu must not accumulate movement on resume.
     * Reset acceleration and subpixel remainder when switching input modes. */
    if (elapsed > 1000u || last_in_world != mouse_pointer_hidden) {
        carry_x = carry_y = 0.0f;
        for (unsigned int code = 0; code <= KEY_MAX; ++code)
            if (held[code]) held_since[code] = now;
        elapsed = 0;
        last_in_world = mouse_pointer_hidden;
    }
    if (elapsed > 250u) elapsed = 250u;
    float tick_scale = (float)elapsed * 60.0f / 1000.0f;

    float dx = 0.0f, dy = 0.0f;
    if (!held[MB_R2]) {
        dx += ramp(MB_A, now) - ramp(MB_Y, now);
        dy += ramp(MB_B, now) - ramp(MB_X, now);
    }
    if (!mouse_pointer_hidden) {
        dx += ramp(MB_RIGHT, now) - ramp(MB_LEFT, now);
        dy += ramp(MB_DOWN, now) - ramp(MB_UP, now);
    }

    int width, height;
    SDL_GetWindowSize(window, &width, &height);
    float gain_x = sensitivity_enabled ? nc_motion_gain(sensitivity, mouse_pointer_hidden, width) : 1.0f;
    float gain_y = sensitivity_enabled ? nc_motion_gain(sensitivity, mouse_pointer_hidden, height) : 1.0f;
    carry_x += dx * tick_scale * gain_x;
    carry_y += dy * tick_scale * gain_y;
    int ix = (int)carry_x;
    int iy = (int)carry_y;
    carry_x -= ix;
    carry_y -= iy;
    if (ix || iy) push_motion(window, ix, iy);
}

void miyoo_input_draw_cursor(SDL_Window *window) {
    if (input_fd < 0 || mouse_pointer_hidden) return;

    int width = 720, height = 480;
    GLint old_matrix_mode = GL_MODELVIEW;
    GLint old_program = 0;
    SDL_GetWindowSize(window, &width, &height);
    glGetIntegerv(GL_MATRIX_MODE, &old_matrix_mode);
    glGetIntegerv(GL_CURRENT_PROGRAM, &old_program);

    glPushAttrib(GL_COLOR_BUFFER_BIT | GL_CURRENT_BIT | GL_DEPTH_BUFFER_BIT |
                 GL_ENABLE_BIT | GL_LINE_BIT | GL_VIEWPORT_BIT);
    glUseProgram(0);
    glViewport(0, 0, width, height);
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glDisable(GL_ALPHA_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDepthMask(GL_FALSE);

    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    glLoadIdentity();
    glOrtho(0.0, (GLdouble)width, (GLdouble)height, 0.0, -1.0, 1.0);
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();

    GLfloat x = (GLfloat)cursor_x + 0.5f;
    GLfloat y = (GLfloat)cursor_y + 0.5f;
    glColor4f(1.0f, 1.0f, 1.0f, 0.95f);
    glBegin(GL_TRIANGLES);
    glVertex2f(x, y);
    glVertex2f(x, y + 11.0f);
    glVertex2f(x + 8.0f, y + 8.0f);
    glEnd();

    glLineWidth(2.0f);
    glColor4f(0.0f, 0.0f, 0.0f, 1.0f);
    glBegin(GL_LINE_LOOP);
    glVertex2f(x, y);
    glVertex2f(x, y + 11.0f);
    glVertex2f(x + 8.0f, y + 8.0f);
    glEnd();

    glPopMatrix();
    glMatrixMode(GL_PROJECTION);
    glPopMatrix();
    glMatrixMode(old_matrix_mode);
    glUseProgram((GLuint)old_program);
    glPopAttrib();
}

void miyoo_input_shutdown(void) {
    if (input_fd < 0) return;
    if (input_grabbed) ioctl(input_fd, EVIOCGRAB, 0);
    close(input_fd);
    input_fd = -1;
    input_grabbed = 0;
}

#else

int miyoo_input_init(SDL_Window *window) {
    (void)window;
    return 0;
}

void miyoo_input_tick(SDL_Window *window, bool *running) {
    (void)window;
    (void)running;
}

void miyoo_input_draw_cursor(SDL_Window *window) {
    (void)window;
}

void miyoo_input_shutdown(void) {
}

#endif
