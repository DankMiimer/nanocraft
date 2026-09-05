#include <assert.h>
#include <math.h>
#include <unistd.h>
#include "../build/overlay/ninecraft/src/miyoo_input.c"

bool mouse_pointer_hidden;
static Uint32 test_time;
static int test_extent = 120, motion_x, motion_y, clicks, walk_keys;
Uint32 SDL_GetTicks(void) { return test_time; }
void SDL_GetWindowSize(SDL_Window *w, int *x, int *y) {
    (void)w; *x = *y = test_extent;
}
SDL_Scancode SDL_GetScancodeFromKey(SDL_Keycode key) { (void)key; return 0; }
int SDL_PushEvent(SDL_Event *e) {
    if (e->type == SDL_MOUSEMOTION) { motion_x += e->motion.xrel; motion_y += e->motion.yrel; }
    if (e->type == SDL_MOUSEBUTTONDOWN) ++clicks;
    if (e->type == SDL_KEYDOWN && e->key.keysym.sym == SDLK_w) ++walk_keys;
    return 1;
}
static void reset(int world, int extent) {
    memset(held, 0, sizeof held); memset(physical_held, 0, sizeof physical_held);
    memset(release_at, 0, sizeof release_at); memset(move_sent, 0, sizeof move_sent);
    memset(face_action, 0, sizeof face_action); memset(face_click, 0, sizeof face_click);
    test_extent = extent; mouse_pointer_hidden = world; last_in_world = world;
    test_time = last_tick = 2000; carry_x = carry_y = 0;
    cursor_x = cursor_y = 0; motion_x = motion_y = clicks = walk_keys = 0;
    sensitivity = (nc_sensitivity){100, 20}; sensitivity_path = NULL; sensitivity_enabled = 1;
    held[MB_A] = 1; held_since[MB_A] = 1000;
}
static void tick(Uint32 time) { bool running = true; test_time = time; miyoo_input_tick(NULL, &running); assert(running); }
static int travel(int world, int extent, int fps, int camera, int cursor) {
    reset(world, extent); sensitivity = (nc_sensitivity){camera, cursor};
    for (int i = 1; i <= fps; ++i) tick(2000 + 1000 * i / fps);
    return motion_x;
}
int main(void) {
    input_fd = open("/dev/null", O_RDONLY);
    assert(input_fd >= 0);
    /* At full acceleration the old injector emits 11 * 60 = 660 px/s. */
    for (int fps = 10; fps <= 60; fps += 5) {
        assert(abs(travel(1, 120, fps, 100, 20) - 660) <= 1);
        assert(abs(travel(1, 240, fps, 100, 200) - 660) <= 1);
        assert(abs(travel(1, 120, fps, 50, 200) - 330) <= 1);
        assert(abs(travel(0, 120, fps, 200, 20) - 66) <= 1);
        assert(abs(travel(0, 240, fps, 10, 20) - 132) <= 1);
    }
    reset(0, 120); held[MB_A] = 0;
    handle_physical_button(MB_RIGHT, 1, 2000);
    tick(2083); handle_physical_button(MB_RIGHT, 0, 2083); tick(2166);
    assert(cursor_x >= 1 && cursor_x <= 5); /* a tap can target adjacent cells */
    reset(0, 120); cursor_x = 119; tick(2100); assert(cursor_x == 119);
    reset(0, 120); held[MB_A] = 0; held[MB_LEFT] = 1; held_since[MB_LEFT] = 1000;
    tick(2100); assert(cursor_x == 0);
    reset(1, 120); carry_x = .9f; mouse_pointer_hidden = false; tick(2100);
    assert(motion_x == 0 && carry_x == 0); /* no carry across menu/world */
    reset(1, 120); tick(12000); assert(motion_x == 0); /* suspended time is ignored */
    reset(1, 120); held[MB_A] = 0; held[MB_UP] = 1; tick(2100);
    assert(walk_keys == 1 && motion_x == 0 && motion_y == 0);
    reset(0, 120); apply_button(MB_R1, 1, 2000); assert(clicks == 1);
    reset(0, 120); sensitivity_enabled = 0; tick(2100);
    assert(motion_x == 66); /* shared Miyoo injector stays stock without opt-in */
    char path[] = "/tmp/nanocraft-input-XXXXXX";
    int config = mkstemp(path); assert(config >= 0);
    assert(write(config, "50 40\n", 6) == 6); close(config);
    reset(1, 120); sensitivity_path = path; sensitivity_checked = 1900;
    tick(2100); assert(sensitivity.camera == 100);
    motion_x = 0; tick(2500);
    assert(sensitivity.camera == 50 && sensitivity.cursor == 40);
    assert(abs(motion_x - 82) <= 1); /* 250 ms cap, newly reloaded 50% gain */
    unlink(path); tick(3000);
    assert(sensitivity.camera == 100 && sensitivity.cursor == 20);
    close(input_fd);
    puts("PASS: camera baseline, independent gains, 10-60 FPS, both resolutions, taps, edges, transitions, resume, walking, clicks, opt-in and live reload");
}
