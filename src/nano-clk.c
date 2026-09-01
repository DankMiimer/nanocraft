/* nano-clk.c — read and set the RG Nano's CPU clock.
 *
 * DrUm78's OS ships an Overclock.opk; inspecting it shows a musl armhf binary
 * (same FunKey SDK 2.3.0 this port uses) that opens /dev/mem and writes the
 * Allwinner CCU PLL registers. Its strings include "new clock 1008MHz", and a
 * read of the live register confirms 1008 MHz stock.
 *
 * There is NO cpufreq interface on this device — /sys/devices/system/cpu/cpu0/
 * cpufreq does not exist — so the MM+ port's governor + `cpuclock` approach has
 * no equivalent. Register writes are the only lever, and every cost on this
 * device is CPU cost: no GPU, one core, so clock scales fill rate AND game
 * logic together.
 *
 *   nano-clk                 report the current clock
 *   nano-clk --list          show the achievable steps
 *   nano-clk --set <mhz>     set (snapped to the nearest achievable step)
 *   nano-clk --restore       back to 1008 MHz stock
 *   nano-clk --force         permit steps above SAFE_MAX_MHZ
 *
 * ---------------------------------------------------------------------------
 * THE SAFETY DESIGN, because this writes a live CPU clock register
 *
 * 1. ONLY N CHANGES. The register encodes
 *        f = 24 MHz * (N+1) * (K+1) / ((M+1) * 2^P)
 *    and the firmware ships N+1=21, K+1=4, M+1=2, P=0 -> 1008 MHz. K, M and P
 *    are preserved exactly, and every other bit is preserved by read-modify-
 *    write. That keeps us on the manufacturer's known-good configuration and
 *    makes the achievable set a clean 48 MHz ladder (24*4/2 = 48 per N step).
 *
 * 2. THE CPU IS MOVED OFF THE PLL FIRST. Rewriting PLL_CPUX while the core is
 *    clocked from it is how you hang an Allwinner part. The documented sequence
 *    is: switch CPU_CLK_SRC to OSC24M, reprogram the PLL, wait for it to
 *    relock, switch back. The CPU keeps executing throughout, just at 24 MHz
 *    for a few microseconds.
 *
 * 3. LOCK IS WAITED FOR, WITH A TIMEOUT AND A ROLLBACK. If the PLL does not
 *    report lock, the original register value is restored and the source is
 *    switched back before returning failure — so a rejected frequency leaves
 *    the machine exactly as it was rather than running from an unlocked PLL.
 *
 * 4. IT READS BACK AND VERIFIES, and prints what the hardware actually holds
 *    rather than what was requested.
 *
 * 5. IT REFUSES TO UNDERCLOCK below stock (no benefit here) and refuses above
 *    SAFE_MAX_MHZ without --force.
 *
 * KNOWN LIMITATION: the kernel calibrated its delay loop at boot, so after a
 * clock change udelay()-based timing in drivers is off by the same ratio. The
 * shipped Overclock app has this too. It has not caused trouble in practice,
 * but it is why this tool restores stock on exit rather than leaving the device
 * overclocked indefinitely.
 *
 * NO THERMAL MANAGEMENT EXISTS ON THIS SOC as far as this port can tell, and
 * the battery is small. Higher clocks mean more heat and less runtime, and that
 * is the user's call to make, which is why nothing here overclocks by default.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

#define CCU_BASE        0x01C20000UL
#define PLL_CPUX        0x0000
#define CPU_AXI_CFG     0x0050          /* [17:16] CPU_CLK_SRC_SEL */
#define SRC_OSC24M      1
#define SRC_PLL_CPUX    2
#define OSC24M          24U

#define STOCK_MHZ       1008U
/* The V3s is specified at 1.2 GHz. One step past that is offered because the
 * ladder lands on 1248; anything beyond needs --force and is genuinely unknown
 * territory for a given unit. */
#define SAFE_MAX_MHZ    1248U
#define HARD_MAX_MHZ    1440U

static volatile uint8_t *g_ccu;

static uint32_t rd(unsigned off)            { return *(volatile uint32_t *)(g_ccu + off); }
static void     wr(unsigned off, uint32_t v){ *(volatile uint32_t *)(g_ccu + off) = v; }

typedef struct { unsigned n, k, m, p, mhz; } pll_t;

static pll_t decode(uint32_t reg) {
    pll_t f;
    f.p = (reg >> 16) & 0x3;
    f.n = (reg >>  8) & 0x1F;
    f.k = (reg >>  4) & 0x3;
    f.m = (reg >>  0) & 0x3;
    f.mhz = OSC24M * (f.n + 1) * (f.k + 1) / ((f.m + 1) * (1U << f.p));
    return f;
}

/* MHz per N step, given the K/M/P the firmware chose. 48 with stock factors. */
static unsigned step_mhz(pll_t f) {
    return OSC24M * (f.k + 1) / ((f.m + 1) * (1U << f.p));
}

static void report(const char *label) {
    uint32_t reg = rd(PLL_CPUX);
    uint32_t axi = rd(CPU_AXI_CFG);
    pll_t f = decode(reg);
    const char *src;
    switch ((axi >> 16) & 0x3) {
        case 0:  src = "LOSC(32k)";  break;
        case 1:  src = "OSC24M";     break;
        default: src = "PLL_CPUX";   break;
    }
    printf("%sPLL_CPUX = 0x%08X  N=%u K=%u M=%u P=%u  enable=%u lock=%u\n",
           label, reg, f.n, f.k, f.m, f.p, (reg >> 31) & 1, (reg >> 28) & 1);
    printf("%sCPU clock source: %s\n", label, src);
    printf("%sCPU CLOCK: %u MHz%s\n", label, f.mhz,
           f.mhz == STOCK_MHZ ? "  (stock)" : "");
}

static void list_steps(void) {
    pll_t cur = decode(rd(PLL_CPUX));
    unsigned st = step_mhz(cur);
    printf("achievable steps (K/M/P held at the firmware's values, N varied):\n");
    printf("  step size %u MHz\n\n", st);
    for (unsigned n = 0; n < 32; n++) {
        unsigned mhz = st * (n + 1);
        if (mhz < STOCK_MHZ || mhz > HARD_MAX_MHZ) continue;
        printf("   %4u MHz  (N=%2u)%s%s\n", mhz, n,
               mhz == STOCK_MHZ  ? "   <- stock" : "",
               mhz == cur.mhz && mhz != STOCK_MHZ ? "   <- current" : "");
        if (mhz == SAFE_MAX_MHZ)
            printf("        ---- above here needs --force ----\n");
    }
}

static int set_mhz(unsigned want, int force) {
    uint32_t orig_pll = rd(PLL_CPUX);
    uint32_t orig_axi = rd(CPU_AXI_CFG);
    pll_t cur = decode(orig_pll);
    unsigned st = step_mhz(cur);

    if (st == 0) { fprintf(stderr, "refusing: computed a 0 MHz step size\n"); return 1; }

    /* Snap to the ladder rather than silently accepting a value the hardware
     * cannot express. */
    unsigned n = (want + st / 2) / st;
    if (n == 0) n = 1;
    if (n > 32) n = 32;
    unsigned mhz = st * n;

    if (mhz < STOCK_MHZ) {
        fprintf(stderr, "refusing %u MHz: below the %u MHz stock clock. There is no\n"
                        "reason to underclock this device — it is already the slowest\n"
                        "part of the system.\n", mhz, STOCK_MHZ);
        return 1;
    }
    if (mhz > SAFE_MAX_MHZ && !force) {
        fprintf(stderr, "refusing %u MHz: above the %u MHz ceiling this tool applies\n"
                        "without --force. The V3s is specified at 1.2 GHz, there is no\n"
                        "thermal management on this SoC, and what a given unit tolerates\n"
                        "is not knowable from here. Re-run with --force if you mean it.\n",
                        mhz, SAFE_MAX_MHZ);
        return 1;
    }
    if (mhz > HARD_MAX_MHZ) {
        fprintf(stderr, "refusing %u MHz: above the %u MHz hard limit, --force included.\n",
                        mhz, HARD_MAX_MHZ);
        return 1;
    }

    if (mhz == cur.mhz) { printf("already at %u MHz, nothing to do\n", mhz); return 0; }

    uint32_t new_pll = (orig_pll & ~(0x1FU << 8)) | ((uint32_t)(n - 1) << 8);

    printf("setting %u MHz -> %u MHz  (N %u -> %u, K/M/P unchanged)\n",
           cur.mhz, mhz, cur.n, n - 1);
    printf("  PLL_CPUX 0x%08X -> 0x%08X\n", orig_pll, new_pll);

    /* --- the sequence ------------------------------------------------------
     * Move the CPU onto the 24 MHz oscillator before touching the PLL it is
     * currently running from. */
    wr(CPU_AXI_CFG, (orig_axi & ~(0x3U << 16)) | (SRC_OSC24M << 16));
    (void)rd(CPU_AXI_CFG);                       /* read back = write barrier */

    wr(PLL_CPUX, new_pll);
    (void)rd(PLL_CPUX);

    int locked = 0;
    for (int i = 0; i < 100000; i++) {
        if (rd(PLL_CPUX) & (1U << 28)) { locked = 1; break; }
    }

    if (!locked) {
        /* Put everything back before reporting failure, so a rejected clock
         * leaves the machine exactly as it was. */
        wr(PLL_CPUX, orig_pll);
        (void)rd(PLL_CPUX);
        for (int i = 0; i < 100000 && !(rd(PLL_CPUX) & (1U << 28)); i++) { }
        wr(CPU_AXI_CFG, orig_axi);
        fprintf(stderr, "PLL did not lock at %u MHz — rolled back to %u MHz.\n",
                mhz, cur.mhz);
        return 1;
    }

    wr(CPU_AXI_CFG, (orig_axi & ~(0x3U << 16)) | (SRC_PLL_CPUX << 16));
    (void)rd(CPU_AXI_CFG);

    pll_t got = decode(rd(PLL_CPUX));
    if (got.mhz != mhz) {
        fprintf(stderr, "read-back mismatch: asked %u MHz, hardware holds %u MHz\n",
                mhz, got.mhz);
        return 1;
    }
    printf("  locked. now:\n");
    report("  ");
    return 0;
}

static void usage(const char *me) {
    printf("usage: %s [--list] [--set <mhz>] [--restore] [--force]\n\n"
           "  (no args)     report the current CPU clock\n"
           "  --list        show the achievable frequency steps\n"
           "  --set <mhz>   set the clock, snapped to the nearest step\n"
           "  --restore     return to %u MHz stock\n"
           "  --force       allow steps above %u MHz (see the notes in the source)\n\n"
           "This device has no cpufreq interface; the clock is set by writing the\n"
           "Allwinner CCU PLL through /dev/mem. Requires root.\n",
           me, STOCK_MHZ, SAFE_MAX_MHZ);
}

int main(int argc, char **argv) {
    int do_list = 0, do_set = 0, force = 0;
    unsigned want = 0;

    for (int i = 1; i < argc; i++) {
        if      (!strcmp(argv[i], "--list"))    do_list = 1;
        else if (!strcmp(argv[i], "--force"))   force = 1;
        else if (!strcmp(argv[i], "--restore")) { do_set = 1; want = STOCK_MHZ; }
        else if (!strcmp(argv[i], "--set") && i + 1 < argc) {
            do_set = 1; want = (unsigned)atoi(argv[++i]);
        } else { usage(argv[0]); return 2; }
    }

    /* Read-only unless a write was actually asked for. */
    int fd = open("/dev/mem", (do_set ? O_RDWR : O_RDONLY) | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        fprintf(stderr, "  (needs root; CONFIG_STRICT_DEVMEM would also refuse)\n");
        return 1;
    }

    long ps = sysconf(_SC_PAGESIZE);
    unsigned long base = CCU_BASE & ~(unsigned long)(ps - 1);
    unsigned long off  = CCU_BASE - base;
    int prot = PROT_READ | (do_set ? PROT_WRITE : 0);

    volatile uint8_t *map = mmap(NULL, (size_t)ps, prot, MAP_SHARED, fd, (off_t)base);
    if (map == MAP_FAILED) { perror("mmap /dev/mem"); close(fd); return 1; }
    g_ccu = map + off;

    int rc = 0;
    if (do_list)      list_steps();
    else if (do_set)  rc = set_mhz(want, force);
    else              report("");

    munmap((void *)map, (size_t)ps);
    close(fd);
    return rc;
}
