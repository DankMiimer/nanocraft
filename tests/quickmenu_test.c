#include <assert.h>
#define main quickmenu_program_main
#include "../src/quickmenu.c"
#undef main

/* Exercise the production framebuffer/menu against an ordinary temporary file. */
int __real_open(const char *, int, ...);
int __wrap_open(const char *path, int flags, ...) {
    if (!strcmp(path, "/dev/fb0")) path = getenv("TEST_FRAMEBUFFER");
    return __real_open(path, flags, 0600);
}
int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "--menu")) return quickmenu_program_main(1, argv);
    assert(argc == 2);
    snprintf(datadir, sizeof datadir, "%s", argv[1]);
    char path[PATH_MAX]; setting_path(path, sizeof path, "sensitivity.txt");
    nc_sensitivity v = nc_sensitivity_read(path);
    assert(v.camera == 100 && v.cursor == 20);
    assert(write_sensitivity((nc_sensitivity){150, 30}) == 0);
    v = nc_sensitivity_read(path); assert(v.camera == 150 && v.cursor == 30);
    const char *bad[] = {"", "100", "nan 20", "100 20 extra", "0 20", "100 210",
                         "100 25", "100 20\n10 30", "10000000000000000000000000 20"};
    for (size_t i = 0; i < sizeof bad / sizeof *bad; ++i) {
        FILE *f = fopen(path, "w"); assert(f); fputs(bad[i], f); fclose(f);
        v = nc_sensitivity_read(path); assert(v.camera == 100 && v.cursor == 20);
    }
    assert(write_sensitivity((nc_sensitivity){10, 200}) == 0);
    v = nc_sensitivity_read(path); assert(v.camera == 10 && v.cursor == 200);
    unlink(path);
    puts("PASS: defaults, atomic round-trip, range and malformed config handling");
}
