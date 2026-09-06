# Play used to crash on every console but mine. Here is why

A **FunKey S** owner reported this against v1.0.0:

> main menu works, options menu works, **Play crashes to desktop**

It was reproduced on a factory RG Nano and fixed in v1.0.7. The cause turned out
to have nothing to do with memory, graphics or the game files:

**Pressing Play opens the world list, and 0.8.1 answers that by asking RakNet to
broadcast for LAN games. On a console with no network interface at all, that
faults.** The crash is a null dereference inside
`RakNet::RakPeer::Ping(char const*, unsigned short, bool, unsigned int)`, about
eight seconds after the button, and the console is left showing the last frame it
drew — which reads as a freeze, because nothing repaints afterwards.

It never happened here because **this console has a WiFi dongle**, added for an
unrelated project. That single difference hid the bug through seven releases:
every console without a network — a stock RG Nano, a FunKey S — hit it every
time, and the one it was developed on never did.

The fix is three lines in the launcher: bring up loopback before starting the
game. `lo` exists on every kernel, costs nothing, and gives the socket layer
something real to answer with. Nothing else was needed.

## Four wrong explanations came first

Memory pressure, a SIGUSR1 kill, a thread deadlock, and world generation. Each
was wrong the same way: inferred from instrumentation that had not itself been
verified. The specific trap was the exit code, and it is step 1 of the chain
below.

The lesson worth keeping: **`139` is a segfault and `138` was an artifact.**
Since v1.0.7 the log says `game ended on its own, status=N` or `game closed from
the menu`, so the two can never be confused again.

## Ruled out along the way: the APK

An early guess was that the reporter had a different build of 0.8.1, because
Ninecraft reads the game's C++ objects at hard-coded byte offsets validated
against one specific library. **That guess was wrong.** Both 0.8.1 APKs from the
archive.org set contain a `libminecraftpe.so` byte-identical to the tested one:

```text
libminecraftpe.so   9,668,996 bytes
sha256              baf9ca243fa301b7a9b4755ddc97aba1f0d35c9b1b80479980b47d6455a32677
```

The installer still records that size and sha256 into `install.log`, because
ruling this out in one line is worth the second it costs.

## The captures

Taken off a factory RG Nano on 2026-09-05, from the runs that found the bug.
Kept because the fix is one line and the evidence for it is not obvious from
the fix.

| File | What it is |
|---|---|
| `memtrace-dmesg.txt` | The kernel's fatal-signal report. `PC is at 0xb1bb34f4`, `LR is at 0xb1bb0df5`, `r1 = 0`, `r3 = 0` — signal 11. |
| `memtrace-maps.txt` | `/proc/PID/maps` from the **same tick**, which is what makes the PC resolvable at all; addresses move with ASLR. |
| `memtrace.txt` | One line a second: memory, zram occupancy, signal dispositions, process group. |
| `diag-*.txt` | The diagnostic build's own captures from an earlier run. |

## How the address became a function name

`libminecraftpe.so` is never mapped from the file — Ninecraft's Android linker
maps it privately, so the crash PC lands in an anonymous `r-xp` region and
resolves to nothing by default. The chain that worked:

1. Capture the game's exit status **outside** the launcher's signal handling.
   `run.sh`'s own `wait` returns `128 + signum` when a trapped signal is
   handled, and that artifact had been reported as the game's status on every
   run — it says `138` (SIGUSR1) when the truth was `139` (SIGSEGV).
2. Turn on `/proc/sys/kernel/print-fatal-signals` and keep dumping `dmesg`,
   because a console showing a dead game's last frame has to be power-cycled and
   anything unsynced is lost.
3. Take `/proc/PID/maps` in the same tick, find the 2.5 MB anonymous `r-xp`
   region, and treat the offset into it as the offset into the library.
4. Look that offset up in the `.so`'s **dynamic** symbol table — it is stripped
   of locals, so `nm -D`, not `nm`.

That gave `RakNet::RakPeer::Ping(char const*, unsigned short, bool, unsigned
int) +0x74` on the first try. `opk/resolve-fault.awk` does steps 3 and 4 automatically and is what the
diagnostic build runs; `research/2026-09-05/resolve-crash.sh` does the final
symbol lookup and can be pointed at any future address.

Run the resolver against these files to reproduce the finding:

```sh
awk -v maps=memtrace-maps.txt -f ../../opk/resolve-fault.awk memtrace-dmesg.txt
```

## Worth knowing before trusting a trace like this

Two of my own instrumentation bugs produced confident, wrong conclusions here:
caching the game's pid (so a pid that changed read as "the game exited after ten
seconds" when it was still running), and referencing an unset variable under
`set -u` (so a tracer wrote a header and silently nothing else). Both were
invisible in the output. Check the trace agrees with the launcher's own view
before reasoning from it.

The sampler wrote `memtrace.log`; it is `.txt` here because the packaging
refuses to publish anything named `*.log`, and that guard is worth more than
the extension.

A note on provenance: these are the captures from the run that crashed. An
earlier version of this folder held the same filenames from a later,
crash-free session - they were collected during cleanup, after the tracer had
already overwritten the ring buffer. If a capture here does not contain
"potentially unexpected fatal signal", it is the wrong one.
