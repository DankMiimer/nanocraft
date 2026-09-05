# resolve-fault.awk - turn a kernel fault dump into "which library faulted".
#
# A segfault's program counter is meaningless on its own. Resolved against the
# process's own /proc/PID/maps it names the mapped file and the offset inside
# it, which is the difference between "it crashes when I press Play" and
# "it faults in RakNet::RakPeer::Ping". That is exactly how the crash fixed in
# v1.0.7 was found.
#
# Needs /proc/sys/kernel/print-fatal-signals set to 1 BEFORE the crash. On this
# kernel that produces, in dmesg:
#
#     potentially unexpected fatal signal 11.
#     CPU: 0 PID: 5636 Comm: ld-linux-armhf. ...
#     pc : [<b6ef9c70>]    lr : [<0000feff>]    psr: 60000010
#
# awk rather than Python, because DrUm78's factory firmware ships no
# interpreter at all and this has to run on the consoles that actually have
# problems.
#
#     awk -v maps=<maps-file> -f resolve-fault.awk <dmesg-file>

# BusyBox awk has no strtonum, so hex is converted by hand.
function hex2dec(s,    i, c, n, d) {
    n = 0
    s = tolower(s)
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        d = index("0123456789abcdef", c) - 1
        if (d < 0) continue
        n = n * 16 + d
    }
    return n
}

function fmt_hex(n,    s, d) {          # for printing addresses back out
    if (n == 0) return "0"
    s = ""
    while (n > 0) {
        d = n % 16
        s = substr("0123456789abcdef", d + 1, 1) s
        n = int(n / 16)
    }
    return s
}

BEGIN {
    nmaps = 0
    if (maps != "") {
        while ((getline line < maps) > 0) {
            # 0000-1111 r-xp 0000 fd:00 123  /path/to/file
            if (match(line, /^[0-9a-f]+-[0-9a-f]+ /) == 0) continue
            split(line, f, " ")
            split(f[1], r, "-")
            lo[nmaps]    = hex2dec(r[1])
            hi[nmaps]    = hex2dec(r[2])
            perm[nmaps]  = f[2]
            foff[nmaps]  = hex2dec(f[3])
            # the path is field 6 onward, and may be absent
            # field 6 is the path, and is absent for anonymous mappings
            name[nmaps] = ""
            if (f[6] ~ /^\// || f[6] ~ /^\[/) name[nmaps] = f[6]
            if (perm[nmaps] ~ /^r-x/ && name[nmaps] == "") {
                sz = hi[nmaps] - lo[nmaps]
                if (sz > big_sz) { big_sz = sz; big_lo = lo[nmaps]; big_hi = hi[nmaps] }
            }
            nmaps++
        }
        close(maps)
    }
}

function resolve(addr,   i) {
    for (i = 0; i < nmaps; i++)
        if (addr >= lo[i] && addr < hi[i]) return i
    return -1
}

function signame(n) {
    if (n == 4)  return "SIGILL"
    if (n == 6)  return "SIGABRT"
    if (n == 7)  return "SIGBUS"
    if (n == 8)  return "SIGFPE"
    if (n == 11) return "SIGSEGV"
    return "signal " n
}

function report(label, addr,   i, off, sz, guess) {
    i = resolve(addr)
    if (i < 0) {
        if (addr < 4096)
            printf "  %s  0x%08x  ->  not in any mapped region   (a null-pointer dereference)\n", label, addr
        else
            printf "  %s  0x%08x  ->  not in any mapped region\n", label, addr
        return
    }
    if (name[i] != "") {
        printf "  %s  0x%08x  ->  %s+0x%s  [%s]\n", label, addr, name[i], fmt_hex(addr - lo[i] + foff[i]), perm[i]
        return
    }
    sz = hi[i] - lo[i]
    guess = ""
    # libminecraftpe.so does NOT appear as a file in the map: Ninecraft loads it
    # with a bundled Android linker that maps it by hand, so the game's own code
    # lands in ANONYMOUS executable memory. Without this, a fault in the game -
    # the single most interesting outcome - would report only "anonymous".
    if (big_sz > 0 && addr >= big_lo && addr < big_hi)
        guess = "  <-- very likely libminecraftpe.so (the game)"
    else if (perm[i] ~ /^r-x/)
        guess = "  (anonymous executable memory)"
    printf "  %s  0x%08x  ->  anonymous+0x%s  [%s, %d kB region]%s\n", \
        label, addr, fmt_hex(addr - lo[i]), perm[i], int(sz / 1024), guess
}

/potentially unexpected fatal signal/ {
    if (match($0, /signal [0-9]+/)) {
        s = substr($0, RSTART + 7, RLENGTH - 7) + 0
        sig = s
    }
}
/PID:[ \t]*[0-9]+[ \t]+Comm:/ {
    if (match($0, /PID:[ \t]*[0-9]+/)) {
        pid = substr($0, RSTART + 4, RLENGTH - 4) + 0
    }
    if (match($0, /Comm:[ \t]*[^ \t]+/)) {
        comm = substr($0, RSTART + 5, RLENGTH - 5)
        gsub(/[ \t]/, "", comm)
    }
}
# The kernel prints the faulting addresses twice, and this form is
# unambiguous, so prefer it:
#     PC is at 0xb1bb34f4
/PC is at 0x[0-9a-fA-F]+/ {
    if (match($0, /0x[0-9a-fA-F]+/)) {
        pcv = hex2dec(substr($0, RSTART + 2, RLENGTH - 2)); have_pc = 1
    }
}
/LR is at 0x[0-9a-fA-F]+/ {
    if (match($0, /0x[0-9a-fA-F]+/)) {
        lrv = hex2dec(substr($0, RSTART + 2, RLENGTH - 2)); have_lr = 1
    }
}

# Fallback for the combined register line, which carries both:
#     pc : [<b1bb34f4>]    lr : [<b1bb0df5>]    psr: 600e0030
#
# Split on "lr" first, and match the bracketed hex rather than stripping
# non-hex characters from the line: the "c" of "pc" is itself a hex digit and
# silently prepends itself to the address, which cost the top nibble.
/pc[ \t]*:[ \t]*\[</ {
    left = $0
    right = ""
    if (match($0, /lr[ \t]*:/)) {
        left  = substr($0, 1, RSTART - 1)
        right = substr($0, RSTART)
    }
    if (!have_pc && match(left, /\[<[0-9a-fA-F]+>\]/)) {
        pcv = hex2dec(substr(left, RSTART + 2, RLENGTH - 4)); have_pc = 1
    }
    if (!have_lr && right != "" && match(right, /\[<[0-9a-fA-F]+>\]/)) {
        lrv = hex2dec(substr(right, RSTART + 2, RLENGTH - 4)); have_lr = 1
    }
}

END {
    if (!sig && !have_pc) {
        print "  No fatal-signal record in dmesg."
        print "  Either the game did not crash, or print-fatal-signals was off"
        print "  when it did, or the ring buffer wrapped."
        exit 0
    }
    if (sig)  printf "  Fatal signal: %s (%d)\n", signame(sig), sig
    if (comm) printf "  Process:      %s (pid %d)\n", comm, pid
    if (nmaps == 0) {
        print "  No usable memory map was captured, so the address below"
        print "  cannot be attributed to a library."
    }
    if (have_pc) report("PC", pcv)
    if (have_lr) report("LR", lrv)
    if (big_sz > 0) {
        print ""
        printf "  Largest anonymous executable region: 0x%08x-0x%08x (%d kB)\n", big_lo, big_hi, int(big_sz / 1024)
        print "  That is where the game's own code lives - it has no filename"
        print "  because Ninecraft's Android linker maps it by hand."
    }
    print ""
    print "  How to read this: a fault in the largest anonymous executable"
    print "  region is the game's own code; inside swrast_dri.so or libGL is the"
    print "  software renderer; inside libEGL.so.1 is this port's presenter;"
    print "  inside libc/libpthread is usually the caller's bug, not libc's."
}
