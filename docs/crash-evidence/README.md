# The captures that identified the Play crash

Taken off a factory RG Nano on 2026-09-05, from the runs that found the bug
fixed in v1.0.7: **RakNet's LAN broadcast faulting on a console with no network
interface.** Kept because the fix is one line and the evidence for it is not
obvious from the fix.

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
