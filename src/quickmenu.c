/* quickmenu.c - the in-game quick menu for NanoCraft on the RG Nano.
 *
 * A port of quickmenu.py, which this replaces. The Python version worked
 * perfectly on the console it was written on and could not run anywhere else:
 * DrUm78's factory FunKey-OS ships no Python at all, so on every console but
 * the author's the menu never appeared. Worse than absent - run.sh SIGSTOPped
 * the game to make room for a menu that then failed to start, which looked
 * exactly like the console hanging.
 *
 * C rather than shell because of what the menu actually does. Every redraw
 * composites onto /dev/fb0, and in shell each row of each rectangle is one dd,
 * which is one fork: a cursor, two bars and a value strip come to roughly 150
 * forks, about half a second of lag per keypress. Shell also cannot issue
 * EVIOCGRAB, so every press made in the menu would queue in the stopped game's
 * event buffer and replay into the world on resume. Built static, like
 * nano-clk, so it needs nothing from the OS: the console is musl and this is a
 * glibc toolchain.
 *
 * All the pre-rendered assets are reused byte for byte. No font engine, no
 * asset regeneration: make-menu-bg.sh still produces exactly what this reads.
 *
 * WHY A MENU EXISTS AT ALL. On this OS the power-button menu is not a service -
 * it is drawn by whatever app is in the foreground. fkgpiod answers the button
 * with `powerdown schedule 0.1`, which signals the foreground process and then
 * cuts power 100 ms later unless that process cancels it. GMenu2X's menu is
 * GMenu2X catching that signal. A game that ignores it just gets switched off
 * mid-session, so the menu is provided here or not at all.
 *
 * TWO THINGS MAKE IT POSSIBLE, both arranged by run.sh:
 *   1. The game is launched with MIYOO_NO_GRAB=1, so Ninecraft does not take an
 *      exclusive EVIOCGRAB on /dev/input/event0 and this process can grab
 *      instead - which is what stops menu presses reaching the game.
 *   2. The game is SIGSTOPped. It repaints /dev/fb0 every frame, so anything
 *      drawn over a running game would survive about 130 ms.
 *
 * Exit codes are the action for run.sh:
 *     0 resume, 2 close game, 3 shut down, 4 restart the game
 */
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>

#define W 240
#define H 240
#define BPP 2
#define FBSIZE (W * H * BPP)

/* Codes as this port's fkgpiod keymap emits them (see minecraft.key). */
enum { K_UP = 103, K_DOWN = 108, K_LEFT = 105, K_RIGHT = 106, K_A = 57, K_B = 29 };

#define IDLE_TIMEOUT_MS 90000   /* never leave the console wedged in the menu */

/* Main list. CLOSE is labelled "FORCE CLOSE" on screen and the name is
 * accurate: SIGTERM then SIGKILL. Anything since Minecraft's last autosave is
 * lost. Quitting through the game's own pause menu (L+START) saves first. */
enum { VOLUME, BRIGHT, CPU, VIDEO, RESTART, CLOSE, SHUTDOWN, RESUME };
/* The video page, reached from the VIDEO row. */
enum { V_SCREEN, V_GUISCALE, V_FOV, V_CAP, V_BACK };
enum { PAGE_MAIN, PAGE_VIDEO };
static const int PAGE_ROWS[2] = { 8, 5 };

static const int ROW_TOP[8] = { 34, 58, 82, 106, 130, 154, 178, 202 };
#define ROW_H 22
#define BAR_X 118
#define BAR_W 106
#define BAR_H 11
#define VAL_X 140
#define VAL_W 76
#define VAL_H 18
#define STRIP_BYTES (VAL_W * VAL_H * BPP)

/* Only these two divide the 240x240 panel cleanly; anything between shimmers.
 * 120 is the default and run.sh assumes the same when resolution.txt is absent:
 * a menu showing 240 while the game launches at 120 is worse than no row. */
static const int SIZES[2] = { 240, 120 };
#define DEFAULT_SIZE 120

/* Interface scale, passed to the launcher as NINECRAFT_GUI_SCALE. "fit" is the
 * default because it is the one setting that suits both screen sizes. */
static const char *const SCALES[3] = { "auto", "fit", "1.0" };
static const char *const SCALE_STRIP[3] = { "gsauto.raw", "gsfit.raw", "gsstock.raw" };
#define DEFAULT_SCALE 1

/* Field of view in degrees. 70 is the stock angle and asking for it patches
 * nothing, so a console that never touches this renders identically to one
 * running a build without any of it. */
static const int FOVS[6] = { 50, 60, 70, 80, 90, 100 };
#define DEFAULT_FOV_INDEX 2

/* Frame cap, passed to the presenter as FBEGL_FPS_CAP. 0 is off and off is the
 * default: nothing paced frames before this existed, and a cap that arrived
 * switched on would quietly slow every console that upgraded. */
static const int CAPS[9] = { 0, 6, 8, 10, 12, 15, 20, 25, 30 };
#define N_CAPS 9
#define DEFAULT_CAP_INDEX 0

/* The CPU ladder, 48 MHz per step from stock. It stops at 1248: the V3s is
 * specified at 1.2 GHz, this SoC has no thermal management, and what an
 * individual unit tolerates is not knowable from here. */
static const int CLOCKS[6] = { 1008, 1056, 1104, 1152, 1200, 1248 };

static unsigned short rgb(int r, int g, int b)
{
    return (unsigned short)(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
}

static unsigned short C_CURSOR, C_BAR_BG, C_BAR_FG, C_BAR_ED;

static char appdir[PATH_MAX];   /* where the .raw assets and nano-clk live */
static char datadir[PATH_MAX];  /* where the settings files live */

/* ---------------------------------------------------------------- framebuffer */

static unsigned char *fb;       /* the visible 240x240 frame */
static int fbfd = -1;

static int fb_open(void)
{
    fbfd = open("/dev/fb0", O_RDWR);
    if (fbfd < 0)
        return -1;
    /* The panel's virtual buffer is 240x720 (triple buffered) but the port
     * never pans, so the visible frame is always the first 240x240. */
    fb = mmap(NULL, FBSIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fbfd, 0);
    if (fb == MAP_FAILED) {
        close(fbfd);
        fbfd = -1;
        return -1;
    }
    return 0;
}

static void fb_close(void)
{
    if (fb && fb != MAP_FAILED)
        munmap(fb, FBSIZE);
    if (fbfd >= 0)
        close(fbfd);
}

/* Read a pre-rendered asset. Returns NULL when it is missing or the wrong size,
 * and every caller treats that as "draw nothing" rather than failing: a menu
 * with one blank value is far better than no menu. */
static unsigned char *load_raw(const char *name, size_t want)
{
    char path[PATH_MAX];
    unsigned char *buf;
    FILE *f;
    size_t got;

    snprintf(path, sizeof path, "%s/%s", appdir, name);
    f = fopen(path, "rb");
    if (!f)
        return NULL;
    buf = malloc(want);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    got = fread(buf, 1, want, f);
    fclose(f);
    if (got != want) {
        free(buf);
        return NULL;
    }
    return buf;
}

static void blit_bg(const unsigned char *bg)
{
    if (bg)
        memcpy(fb, bg, FBSIZE);
}

/* Copy a small pre-rendered strip in, row by row. */
static void blit(const unsigned char *data, int x, int y, int w, int h)
{
    int row;

    if (!data)
        return;
    for (row = 0; row < h; row++) {
        size_t dst = (size_t)((y + row) * W + x) * BPP;
        size_t src = (size_t)(row * w) * BPP;
        if (y + row < 0 || y + row >= H)
            continue;
        memcpy(fb + dst, data + src, (size_t)w * BPP);
    }
}

static void rect(int x, int y, int w, int h, unsigned short color)
{
    unsigned short row[W];
    int i, yy;

    if (w <= 0 || h <= 0)
        return;
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x >= W || y >= H)
        return;
    if (w > W - x) w = W - x;
    if (h > H - y) h = H - y;
    if (w <= 0 || h <= 0)
        return;
    for (i = 0; i < w; i++)
        row[i] = color;
    for (yy = y; yy < y + h; yy++)
        memcpy(fb + (size_t)(yy * W + x) * BPP, row, (size_t)w * BPP);
}

/* A solid triangle, drawn as a stack of rows - cheaper than any glyph and
 * unambiguous at this size. */
static void cursor(int y_center)
{
    int i;

    for (i = 0; i < 9; i++) {
        int hgt = 2 * (9 - i) - 1;
        rect(5 + i, y_center - hgt / 2, 1, hgt, C_CURSOR);
    }
}

static void bar(int top, int pct)
{
    int y = top + (ROW_H - BAR_H) / 2;
    int fill;

    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    rect(BAR_X, y, BAR_W, BAR_H, C_BAR_BG);
    rect(BAR_X, y, BAR_W, 1, C_BAR_ED);
    rect(BAR_X, y + BAR_H - 1, BAR_W, 1, C_BAR_ED);
    rect(BAR_X, y, 1, BAR_H, C_BAR_ED);
    rect(BAR_X + BAR_W - 1, y, 1, BAR_H, C_BAR_ED);
    fill = (BAR_W - 4) * pct / 100;
    rect(BAR_X + 2, y + 2, fill, BAR_H - 4, C_BAR_FG);
}

/* Defined with the other settings writers below; set_clock needs it here. */
static void write_int_setting(const char *file, int v);

/* ------------------------------------------------------------- subprocesses */

/* Run a helper and return its stdout. fork/exec rather than popen so nothing
 * depends on a shell being present or on how it would quote a path. */
static int run_capture(char *const argv[], char *out, size_t outsz)
{
    int fds[2];
    pid_t pid;
    ssize_t n;
    size_t used = 0;
    int status;

    if (out && outsz)
        out[0] = '\0';
    if (pipe(fds) < 0)
        return -1;
    pid = fork();
    if (pid < 0) {
        close(fds[0]);
        close(fds[1]);
        return -1;
    }
    if (pid == 0) {
        int devnull = open("/dev/null", O_RDWR);
        close(fds[0]);
        dup2(fds[1], STDOUT_FILENO);
        if (devnull >= 0) {
            dup2(devnull, STDERR_FILENO);
            dup2(devnull, STDIN_FILENO);
        }
        close(fds[1]);
        execv(argv[0], argv);
        _exit(127);
    }
    close(fds[1]);
    while (out && used + 1 < outsz) {
        n = read(fds[0], out + used, outsz - used - 1);
        if (n <= 0)
            break;
        used += (size_t)n;
    }
    if (out)
        out[used] = '\0';
    close(fds[0]);
    waitpid(pid, &status, 0);
    return status;
}

static int get_pct(const char *what)
{
    char path[PATH_MAX], out[64];
    char *argv[3];
    int v;

    snprintf(path, sizeof path, "/usr/local/sbin/%s", what);
    argv[0] = path;
    argv[1] = (char *)"get";
    argv[2] = NULL;
    if (run_capture(argv, out, sizeof out) < 0)
        return 50;
    if (sscanf(out, "%d", &v) != 1)
        return 50;               /* unreadable: show something sane */
    if (v < 0) v = 0;
    if (v > 100) v = 100;
    return v;
}

/* `set` rather than the up/down wrappers: those post an on-screen notification
 * that would paint straight over this menu. */
static void set_pct(const char *what, int value)
{
    char path[PATH_MAX], num[16];
    char *argv[4];

    snprintf(path, sizeof path, "/usr/local/sbin/%s", what);
    snprintf(num, sizeof num, "%d", value);
    argv[0] = path;
    argv[1] = (char *)"set";
    argv[2] = num;
    argv[3] = NULL;
    run_capture(argv, NULL, 0);
}

/* Current CPU MHz, or -1 if the tool is missing or /dev/mem is refused. */
static int read_clock(void)
{
    char path[PATH_MAX], out[512], *p;
    char *argv[2];
    int mhz;

    snprintf(path, sizeof path, "%s/nano-clk", appdir);
    argv[0] = path;
    argv[1] = NULL;
    if (run_capture(argv, out, sizeof out) < 0)
        return -1;
    p = strstr(out, "CPU CLOCK:");
    if (!p)
        return -1;
    if (sscanf(p + strlen("CPU CLOCK:"), "%d", &mhz) != 1)
        return -1;
    return mhz;
}

/* Apply a clock. Unlike the screen size this takes effect at once - it is a
 * register write, not something the game reads at startup. */
static int set_clock(int mhz)
{
    char path[PATH_MAX], num[16];
    char *argv[4];

    snprintf(path, sizeof path, "%s/nano-clk", appdir);
    snprintf(num, sizeof num, "%d", mhz);
    argv[0] = path;
    argv[1] = (char *)"--set";
    argv[2] = num;
    argv[3] = NULL;
    run_capture(argv, NULL, 0);
    mhz = read_clock();
    /* Remember it. Screen size, interface scale, FOV and the frame cap have
     * always been written straight to the card and read back by the launcher;
     * the clock was the one dial that reset every launch, so it had to be
     * dialled in again every time. run.sh reapplies this at startup and still
     * restores the stock clock on exit, so nothing outside the game is left
     * overclocked. Delete clock.txt from the card to forget it. */
    if (mhz > 0)
        write_int_setting("clock.txt", mhz);
    return mhz;
}

/* ---------------------------------------------------------------- settings */

static void setting_path(char *dst, size_t n, const char *file)
{
    snprintf(dst, n, "%s/%s", datadir, file);
}

static int read_first_int(const char *file, int missing)
{
    char path[PATH_MAX], buf[64];
    FILE *f;
    int v;

    setting_path(path, sizeof path, file);
    f = fopen(path, "r");
    if (!f)
        return missing;
    if (!fgets(buf, sizeof buf, f)) {
        fclose(f);
        return missing;
    }
    fclose(f);
    if (sscanf(buf, "%d", &v) != 1)
        return missing;
    return v;
}

static int write_text(const char *file, const char *text)
{
    char path[PATH_MAX];
    FILE *f;

    mkdir(datadir, 0755);          /* harmless when it already exists */
    setting_path(path, sizeof path, file);
    f = fopen(path, "w");
    if (!f)
        return -1;
    fputs(text, f);
    fclose(f);
    return 0;
}

/* Index into a table, or a stated default when the file says something this
 * build does not offer - the same rule the Python version used. */
static int index_of(const int *table, int n, int value, int fallback)
{
    int i;

    for (i = 0; i < n; i++)
        if (table[i] == value)
            return i;
    return fallback;
}

static int read_size_index(void)
{
    int w = read_first_int("resolution.txt", DEFAULT_SIZE);
    return index_of(SIZES, 2, w, 1);          /* 1 == 120, the default */
}

static void write_size(int w)
{
    char buf[32];

    snprintf(buf, sizeof buf, "%d %d\n", w, w);
    write_text("resolution.txt", buf);
}

static int read_guiscale_index(void)
{
    char path[PATH_MAX], buf[64];
    FILE *f;
    int i;

    setting_path(path, sizeof path, "guiscale.txt");
    f = fopen(path, "r");
    if (!f)
        return DEFAULT_SCALE;
    if (!fgets(buf, sizeof buf, f)) {
        fclose(f);
        return DEFAULT_SCALE;
    }
    fclose(f);
    buf[strcspn(buf, " \t\r\n")] = '\0';
    for (i = 0; i < 3; i++)
        if (strcmp(buf, SCALES[i]) == 0)
            return i;
    return DEFAULT_SCALE;
}

static void write_guiscale(int idx)
{
    char buf[32];

    snprintf(buf, sizeof buf, "%s\n", SCALES[idx]);
    write_text("guiscale.txt", buf);
}

static void write_int_setting(const char *file, int v)
{
    char buf[32];

    snprintf(buf, sizeof buf, "%d\n", v);
    write_text(file, buf);
}

/* ------------------------------------------------------------- memory probe */

/* How much memory can this console actually give a process?
 *
 * Entering a world needs about 65 MB of anonymous memory on hardware with 54-56
 * MB of RAM, so it depends on compressed swap. This asks the question directly,
 * without running the game: allocate and TOUCH memory a megabyte at a time
 * until it fails, and report how far it got.
 *
 * Touching matters. Linux overcommits, so an untouched allocation proves
 * nothing; the pages must be written to be real. That is also why this cannot
 * be shell - dd into tmpfs measures a different thing, because tmpfs pages are
 * shared and swap-backed rather than private to a process.
 *
 * Deliberately capped and deliberately gentle: it stops at the target, releases
 * everything immediately, and never pushes the system to the thrashing point an
 * uncapped test would.
 */
static long meminfo_mb(const char *key)
{
    char line[256];
    FILE *f = fopen("/proc/meminfo", "r");
    size_t n = strlen(key);
    long v = -1;

    if (!f)
        return -1;
    while (fgets(line, sizeof line, f)) {
        if (strncmp(line, key, n) == 0 && line[n] == ':') {
            v = strtol(line + n + 1, NULL, 10) / 1024;
            break;
        }
    }
    fclose(f);
    return v;
}

#define PROBE_CHUNK (1024 * 1024)

static int memprobe(int target)
{
    unsigned char **blocks;
    int got = 0, i;
    long off;

    if (target <= 0)
        target = 80;
    printf("  target:    %d MB (a world needs about 65 MB)\n", target);
    printf("  before:    RAM avail %ld MB, swap free %ld MB\n",
           meminfo_mb("MemAvailable"), meminfo_mb("SwapFree"));
    fflush(stdout);

    blocks = calloc((size_t)target, sizeof *blocks);
    if (!blocks) {
        printf("  allocated: 0 MB  (stopped: no room for the block table)\n");
        return 0;
    }
    for (i = 0; i < target; i++) {
        blocks[i] = malloc(PROBE_CHUNK);
        if (!blocks[i])
            break;
        /* Write one byte per page so the kernel has to back it with something
         * real rather than promising it. */
        for (off = 0; off < PROBE_CHUNK; off += 4096)
            blocks[i][off] = 1;
        got++;
    }

    printf("  allocated: %d MB%s\n", got,
           got < target ? "  (stopped: allocation failed)" : "");
    printf("  during:    RAM avail %ld MB, swap free %ld MB\n",
           meminfo_mb("MemAvailable"), meminfo_mb("SwapFree"));

    for (i = 0; i < got; i++)
        free(blocks[i]);
    free(blocks);

    if (got >= target)
        printf("  VERDICT:   OK - this console can supply a world's working set\n");
    else if (got >= 65)
        printf("  VERDICT:   TIGHT - reached %d MB, enough for a world but with"
               " little headroom\n", got);
    else {
        printf("  VERDICT:   TOO LITTLE - stopped at %d MB, below the ~65 MB a"
               " world needs.\n", got);
        printf("             That alone would explain menus working and Play"
               " failing.\n");
    }
    fflush(stdout);
    return 0;
}

/* -------------------------------------------------------------------- input */

/* Drop anything already queued, so the press that opened the menu - or a button
 * still held from gameplay - cannot immediately pick an item. */
static void drain(int fd)
{
    struct pollfd p = { fd, POLLIN, 0 };
    char scratch[4096];

    while (poll(&p, 1, 0) > 0 && (p.revents & POLLIN)) {
        if (read(fd, scratch, sizeof scratch) <= 0)
            break;
    }
}

/* ------------------------------------------------------------------- screen */

struct assets {
    unsigned char *bg[2];
    unsigned char *val[2];       /* screen sizes */
    unsigned char *clk[6];
    unsigned char *gs[3];
    unsigned char *fov[6];
    unsigned char *cap[N_CAPS];
};

static void load_assets(struct assets *a)
{
    char name[64];
    int i;

    a->bg[0] = load_raw("menubg.raw", FBSIZE);
    a->bg[1] = load_raw("videobg.raw", FBSIZE);
    for (i = 0; i < 2; i++) {
        snprintf(name, sizeof name, "res%d.raw", SIZES[i]);
        a->val[i] = load_raw(name, STRIP_BYTES);
    }
    for (i = 0; i < 6; i++) {
        snprintf(name, sizeof name, "cpu%d.raw", CLOCKS[i]);
        a->clk[i] = load_raw(name, STRIP_BYTES);
    }
    for (i = 0; i < 3; i++)
        a->gs[i] = load_raw(SCALE_STRIP[i], STRIP_BYTES);
    for (i = 0; i < 6; i++) {
        snprintf(name, sizeof name, "fov%d.raw", FOVS[i]);
        a->fov[i] = load_raw(name, STRIP_BYTES);
    }
    for (i = 0; i < N_CAPS; i++) {
        if (CAPS[i] == 0)
            snprintf(name, sizeof name, "capoff.raw");
        else
            snprintf(name, sizeof name, "cap%d.raw", CAPS[i]);
        a->cap[i] = load_raw(name, STRIP_BYTES);
    }
}

/* One full repaint. Cheap enough to do unconditionally on every change: the
 * background is a single memcpy and the panel's SPI flush is driven by the
 * driver's deferred IO rather than by us. */
static void draw(const struct assets *a, int page, int sel, int vol, int bri,
                 int clock_mhz, int size_i, int gs_i, int fov_i, int cap_i)
{
    int vy = (ROW_H - VAL_H) / 2;

    blit_bg(a->bg[page]);
    if (page == PAGE_MAIN) {
        bar(ROW_TOP[VOLUME], vol);
        bar(ROW_TOP[BRIGHT], bri);
        if (clock_mhz >= 0) {
            int ci = index_of(CLOCKS, 6, clock_mhz, -1);
            if (ci >= 0)
                blit(a->clk[ci], VAL_X, ROW_TOP[CPU] + vy, VAL_W, VAL_H);
        }
    } else {
        blit(a->val[size_i], VAL_X, ROW_TOP[V_SCREEN] + vy, VAL_W, VAL_H);
        blit(a->gs[gs_i], VAL_X, ROW_TOP[V_GUISCALE] + vy, VAL_W, VAL_H);
        blit(a->fov[fov_i], VAL_X, ROW_TOP[V_FOV] + vy, VAL_W, VAL_H);
        blit(a->cap[cap_i], VAL_X, ROW_TOP[V_CAP] + vy, VAL_W, VAL_H);
    }
    cursor(ROW_TOP[sel] + ROW_H / 2);
}

/* The diagnostic build also runs this binary as a memory probe. It lives here
 * rather than in a second static binary because this one already ships in both
 * packages, and 380 KB of glibc for one diagnostic is not a good trade. */
int main(int argc, char **argv)
{
    if (argc > 1 && strcmp(argv[1], "--memprobe") == 0)
        return memprobe(argc > 2 ? atoi(argv[2]) : 80);

    struct assets a;
    const char *dev, *env;
    int page = PAGE_MAIN, sel = RESUME;
    int vol, bri, clock_mhz;
    int size_i, gs_i, fov_i, cap_i;
    int fd, grabbed = 0, action = 0, running = 1;

    C_CURSOR = rgb(120, 220, 120);
    C_BAR_BG = rgb(35, 45, 68);
    C_BAR_FG = rgb(120, 220, 120);
    C_BAR_ED = rgb(140, 155, 185);

    /* The assets and nano-clk sit beside this binary in the OPK. /proc/self/exe
     * rather than argv[0]: run.sh invokes this by absolute path today, but a
     * relative one would silently find no assets at all. */
    {
        ssize_t n = readlink("/proc/self/exe", appdir, sizeof appdir - 1);
        char *slash;
        if (n <= 0)
            return 0;
        appdir[n] = '\0';
        slash = strrchr(appdir, '/');
        if (slash)
            *slash = '\0';
    }
    env = getenv("MCPE_DATA");
    snprintf(datadir, sizeof datadir, "%s", env ? env : "/mnt/FunKey/nanocraft");

    vol = get_pct("volume");
    bri = get_pct("brightness");
    size_i = read_size_index();
    gs_i = read_guiscale_index();
    fov_i = index_of(FOVS, 6, read_first_int("fov.txt", FOVS[DEFAULT_FOV_INDEX]),
                     DEFAULT_FOV_INDEX);
    cap_i = index_of(CAPS, N_CAPS, read_first_int("fpscap.txt", CAPS[DEFAULT_CAP_INDEX]),
                     DEFAULT_CAP_INDEX);
    clock_mhz = read_clock();

    if (fb_open() < 0)
        return 0;                 /* no screen: give the game straight back */
    load_assets(&a);

    /* Overridable so the menu can be driven from a FIFO for testing, the same
     * way miyoo_input honours MIYOO_INPUT_DEVICE. */
    dev = getenv("QUICKMENU_INPUT");
    if (!dev)
        dev = "/dev/input/event0";
    fd = open(dev, O_RDONLY);
    if (fd < 0) {
        fb_close();
        return 0;
    }
    if (ioctl(fd, EVIOCGRAB, 1) == 0) {
        grabbed = 1;
    } else if (!getenv("QUICKMENU_INPUT")) {
        /* The game still holds the grab - without MIYOO_NO_GRAB=1 there is no
         * way to read the buttons here. Give the screen back rather than draw a
         * menu nobody can operate. A FIFO cannot be grabbed, and that is
         * expected when driving this for a test. */
        close(fd);
        fb_close();
        return 0;
    }
    drain(fd);

    draw(&a, page, sel, vol, bri, clock_mhz, size_i, gs_i, fov_i, cap_i);

    while (running) {
        struct pollfd p = { fd, POLLIN, 0 };
        struct input_event ev[64];
        ssize_t n;
        size_t i;
        int dirty = 0;

        if (poll(&p, 1, IDLE_TIMEOUT_MS) <= 0)
            break;                /* idle: resume the game */
        n = read(fd, ev, sizeof ev);
        if (n <= 0)
            break;

        for (i = 0; i < (size_t)n / sizeof ev[0] && running; i++) {
            int code = ev[i].code;

            if (ev[i].type != EV_KEY || ev[i].value != 1)
                continue;
            if (code == K_UP) {
                sel = (sel - 1 + PAGE_ROWS[page]) % PAGE_ROWS[page];
                dirty = 1;
            } else if (code == K_DOWN) {
                sel = (sel + 1) % PAGE_ROWS[page];
                dirty = 1;
            } else if (code == K_LEFT || code == K_RIGHT) {
                int dir = (code == K_RIGHT) ? 1 : -1;
                int step = dir * 10;

                if (page == PAGE_VIDEO) {
                    if (sel == V_SCREEN) {
                        /* Only two settings, so either direction toggles. Both
                         * rows here are written at once and read by the game
                         * only at startup, which is what the footer says and
                         * what the main list's RESTART row is for. */
                        size_i = size_i ? 0 : 1;
                        write_size(SIZES[size_i]);
                        dirty = 1;
                    } else if (sel == V_GUISCALE) {
                        /* Wraps: three values, and a wrap is fewer presses than
                         * walking back. */
                        gs_i = (gs_i + dir + 3) % 3;
                        write_guiscale(gs_i);
                        dirty = 1;
                    } else if (sel == V_FOV) {
                        /* Stops at the ends rather than wrapping: on a ladder of
                         * numbers a wrap from 100 to 50 reads as a mistake
                         * rather than a choice. */
                        fov_i += dir;
                        if (fov_i < 0) fov_i = 0;
                        if (fov_i > 5) fov_i = 5;
                        write_int_setting("fov.txt", FOVS[fov_i]);
                        dirty = 1;
                    } else if (sel == V_CAP) {
                        cap_i += dir;              /* same clamped ladder */
                        if (cap_i < 0) cap_i = 0;
                        if (cap_i > N_CAPS - 1) cap_i = N_CAPS - 1;
                        write_int_setting("fpscap.txt", CAPS[cap_i]);
                        dirty = 1;
                    }
                } else if (sel == VOLUME) {
                    vol += step;
                    if (vol < 0) vol = 0;
                    if (vol > 100) vol = 100;
                    set_pct("volume", vol);
                    dirty = 1;
                } else if (sel == BRIGHT) {
                    bri += step;
                    if (bri < 0) bri = 0;
                    if (bri > 100) bri = 100;
                    set_pct("brightness", bri);
                    dirty = 1;
                } else if (sel == CPU && clock_mhz >= 0) {
                    /* Steps along the ladder rather than jumping, so a console
                     * that cannot hold a clock fails at the smallest increment
                     * past what it can do. */
                    int ci = index_of(CLOCKS, 6, clock_mhz, 0) + dir;
                    int got;
                    if (ci < 0) ci = 0;
                    if (ci > 5) ci = 5;
                    got = set_clock(CLOCKS[ci]);
                    if (got >= 0)
                        clock_mhz = got;
                    dirty = 1;
                }
            } else if (code == K_A) {
                if (page == PAGE_VIDEO) {
                    if (sel == V_BACK) {
                        page = PAGE_MAIN;
                        sel = VIDEO;
                        dirty = 1;
                    }
                    continue;
                }
                if (sel == VIDEO) {
                    page = PAGE_VIDEO;
                    sel = V_SCREEN;
                    dirty = 1;
                    continue;
                }
                if (sel == RESTART)       action = 4;
                else if (sel == CLOSE)    action = 2;
                else if (sel == SHUTDOWN) action = 3;
                else if (sel == RESUME)   action = 0;
                else                      continue;
                running = 0;
            } else if (code == K_B) {
                /* B is "back" on the video page and "resume" on the main one,
                 * which is the same gesture either way: leave where you are. */
                if (page == PAGE_VIDEO) {
                    page = PAGE_MAIN;
                    sel = VIDEO;
                    dirty = 1;
                    continue;
                }
                action = 0;
                running = 0;
            }
        }
        if (running && dirty)
            draw(&a, page, sel, vol, bri, clock_mhz, size_i, gs_i, fov_i, cap_i);
    }

    if (grabbed)
        ioctl(fd, EVIOCGRAB, 0);
    close(fd);
    fb_close();
    return action;
}
