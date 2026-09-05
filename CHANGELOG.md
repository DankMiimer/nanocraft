# Changelog

## v1.0.9

**If NanoCraft will not start on your kernel, it now collects the fix for you.**

Since v1.0.6 the package refuses to load its compressed-memory modules into a
kernel nobody has verified them against, and asked the reporter to send
`uname -a` and a copy of `/boot/zImage`. That is an unreasonable request on a
console with no network and no shell.

It now writes **`nanocraft-kernel.txt`** to the root of the SD card instead,
carrying the identity line, `uname -a`, the OS release, the vermagic the loader
expects, the kernel configuration where the build exposes it, and the running
kernel's full symbol table — which is the part that actually matters, because
every symbol these modules import can be checked against the real kernel before
anything is loaded on the hardware. Put the card in a PC, send the one file.

A copy of the kernel image is placed beside it as a convenience; the audit does
not need it.

If the card root cannot be written the report goes to
`/mnt/FunKey/nanocraft/` instead, and if it cannot be written at all the message
says so rather than pointing at a file that is not there.

## v1.0.8

**About 16% more frames, by putting a default back where the code said it was.**

`launch-pe-nano.sh` had been setting `FBEGL_PBO=1` since the beginning, turning
on the presenter's asynchronous pixel-pack path. The presenter's own source says
that path should be off here, and says why: it is a two-core optimisation, and
with one core there is nothing for the readback to overlap into. It left a note
asking someone to measure rather than assume. Measured, in a world at 120x120:

| | PBO on | PBO off |
| --- | ---: | ---: |
| readback | 37.6 ms | **0.4 ms** |
| glFinish | — | 33.3 ms |
| total per frame | 77.7 ms | **67.1 ms** |
| **frame rate** | **12.9 fps** | **14.9 fps** |

The async path never hid the wait; it added about 4 ms a frame on top of it and
reported the same stall under a different name. It is now off by default, which
is what `src/fbegl_nano.c` documents. `FBEGL_PBO=1` still turns it back on.

**The frame cap goes up to 30.** 20, 25 and 30 FPS join the ladder in
**VIDEO → FPS CAP**. A cap does not make anything faster, it makes the pace
even — and what is reachable moved when the present path changed.

**The CPU clock is remembered.** Screen size, interface scale, FOV and the frame
cap have always been written to the card and read back at launch; the clock was
the one dial that reset every time, because it applies as a live register write
and is restored to stock when the game exits. The quick menu now saves it and
the launcher puts it back, so a console does not have to be dialled in again
every session.

Stock is still restored on exit and a reboot clears it regardless — nothing
outside the game is left overclocked. Delete `clock.txt` from the card to forget
it.

**With a guard, because this SoC has no thermal management and no voltage
control.** A saved clock a particular unit cannot hold would otherwise hang the
console on every launch, recoverable only by editing the card on a PC. So a
marker is written before the saved clock is applied and cleared only after the
game exits normally. If it is still there at startup, the last run at that clock
did not finish, and stock is used instead:

```text
[opk] last run at 1248 MHz did not exit cleanly - using stock
```

## v1.0.7

**Play works on consoles that are not mine.** This is the release that fixes
the report that has been open since v1.0.0: *"main menu works, options menu
works, Play crashes to desktop."*

Pressing Play opens the world list, and 0.8.1 answers that by asking RakNet to
broadcast for LAN games. On a console with **no network interface at all** that
faults — a null dereference inside `RakNet::RakPeer::Ping`, about eight seconds
after the button, leaving the last drawn frame on the panel so it reads as a
freeze rather than a crash.

It never happened on the console this port was developed on, because that one
has a WiFi dongle fitted for an unrelated project. Every console without a
network hit it every time; the one it was written on never did.

**The fix is to bring up loopback before starting the game.** `lo` exists on
every kernel, costs nothing, and gives the socket layer something real to answer
with. Reproduced on a factory RG Nano, fixed, and a world then created, played,
saved and quit on that console.

**The quick menu is a program now, not a script.**

`quickmenu.py` is gone; `opk/quickmenu` is a static ARM binary built from
`src/quickmenu.c`. The Python version could not run on DrUm78's factory image,
which ships no interpreter at all — so on every console but the author's,
**L + SELECT did nothing**, and worse, the launcher had already frozen the game
to make room for a menu that never appeared. Same two pages, same rows, same
settings, same exit codes; it reuses the existing pre-rendered assets byte for
byte, so nothing about the build changed.

The launcher also no longer freezes the game when there is no menu to show.

**The log stops lying about how the game ended.**

`run.sh` reported `status=138` — SIGUSR1 — on every run where the power button
was pressed. That number came from the launcher's own `wait` being interrupted,
not from the game, and it sent the investigation of the crash above after a
signal the game demonstrably ignores. The log now distinguishes `game closed
from the menu` from `game ended on its own, status=N`. **139 is a segfault; 138
was an artifact.**

**Also:** an optional memory tracer, off unless
`/mnt/FunKey/nanocraft/memtrace` exists, which records per-thread state,
`wchan`, signal dispositions and zram occupancy once a second; and an
`env.txt` on the card whose `KEY=VALUE` lines are applied to the game's
environment, so a setting can be A/B tested on a console with no network without
rebuilding the package.

**Known:** the diagnostic build's memory probe and crash-address resolver are
still Python and do nothing on factory firmware. The rest of that build works.

## v1.0.6

**The game no longer writes to your SD card to make room for itself.**

Entering a world needs about 65 MB of anonymous memory on a console with 56 MB
of RAM, and every release until now found the difference on the card. It worked,
and it charged the card's finite flash endurance for every world load, forever.

That difference is now found **in RAM**. The launcher loads zram, a compressed
block device the kernel can move idle pages into, with LZ4. Measured on this
game's heap the ratio is **2.7:1**, with around 1,500 identical pages
deduplicated outright, so 40 MB of idle pages occupy about 14 MB. Your card is
not touched at any point while the game runs, and the console is left exactly as
it was found when you quit.

Measured across three sessions including a cold launch and a world entry:

| | |
|---|---:|
| Anonymous memory in a world | 65.4 MB |
| Held compressed | 14.4 MB peak |
| MemAvailable at world entry | 3.9 MB, then 17 MB |

That floor is thin and worth knowing about: this port now lives inside a ~4 MB
budget at its worst instant, and a heavier world or a firmware change costing a
few megabytes could turn that dip into a kill. It reproduced three times, but on
one save.

**The stock kernel has no zram**, so the package carries four modules (97 KB)
built from unmodified Linux 4.14.14 configured to match DrUm78's RG Nano kernel.
They are loaded at launch and unloaded by a reboot; nothing is written to the
read-only rootfs and there is no firmware to flash. Source, configuration and
build instructions are in `opk/modules/README.md`.

**A kernel module is built for one kernel**, and these were built for and tested
on one console. NanoCraft checks that before loading anything, and it checks
more strictly than the kernel does: Linux compares a short "vermagic" string
covering the version and a few build options and nothing else, so two
differently configured builds of the same kernel pass it — and loading into the
wrong one corrupts memory rather than failing cleanly. `opk/modules/kernels`
lists the builds somebody has actually verified, and nothing is loaded into a
kernel that is not on it.

Two sets ship, because there are two kernels: DrUm78's factory RG Nano image is
built SMP and the console this port was developed on is a custom uniprocessor
build, and their vermagic strings differ by that one word. The factory kernel
was read out of DrUm78's own published SD-card image and its export table
audited against every symbol the modules import, so a factory console is
supported without having had one to develop on.

If yours is not on the list NanoCraft says so and refuses to start rather than
running without the memory it needs — a game whose menus all work and which dies
the instant terrain loads is a far more confusing thing to be handed. Send
`uname -a` and a copy of `/boot/zImage` and a verified set can be built for your
console; it needs no firmware change.

`ensure-swap.sh` is now `ensure-memory.sh`, because providing memory was always
the point.

## v1.0.5

**A field of view setting, in a game that does not have one.**

Pocket Edition 0.8.1's entire settings vocabulary is 21 keys and none of them is
FOV. `en_US.lang` carries `options.fov=FOV`, but that file is inherited
desktop-Minecraft boilerplate sitting beside 3D Anaglyph and a warning about
64-bit *Java* installs, so a string there proves nothing.

`GameRenderer::getFov()` is exported, though, and `setupCamera()` hands its
result straight to `gluPerspective` — and the base angle is a single `70.0f`
literal in the code. The launcher now rewrites that one number, which is exactly
what Minecraft's own slider does: the sprint and low-health effects stay
multiplicative on top of the new base instead of being scaled along with it. The
held item keeps its own fixed angle, as it does in vanilla, so your hand does not
distort at the wide end.

**VIDEO → FOV**, 50 to 100 degrees. **70 is stock and patches nothing at all**,
so a console nobody has touched renders identically to one running a build
without any of this. Needs a restart, like the rest of that page.

The literal is found by scanning for the single word reading exactly 70.0f
rather than by a hardcoded offset, and a library where it is missing or not
unique is left alone rather than written into.

**120x120 is now the default, with GUI SCALE on FIT.**

v1.0.4 removed the only real objection to the faster mode — a hotbar with both
ends cut off — so there is no longer a reason to ship the slower one. 11.9 fps
against 7.8 is +52%, the largest single gain available on this console, and at
eight frames a second that is worth a softer picture. FIT is the default scale
because it is the one that suits both sizes: at 120x120 it is identical to AUTO,
and at 240x240 it fills the spare room instead of leaving it.

**This changes what you get on upgrade** if you never set a resolution: the next
launch comes up at 120x120. Anything already in `resolution.txt` or
`guiscale.txt` is still honoured, and **L + SELECT → VIDEO → SCREEN** puts
240x240 back in two presses and a RESTART.

## v1.0.4

**120x120 no longer clips the hotbar.** It was the one thing keeping the faster
mode from being recommendable, and it was never a Minecraft setting going wrong.

Ninecraft installs the interface scale itself, from a `calculate_scale()` that
**floors at 1.0** — a sensible floor for a desktop and 62 pixels too generous
here, because Minecraft's hotbar is 182 interface pixels wide and a 120-pixel
screen cannot hold it. Nothing in the game's own options could reach that.
`gfx_pixeldensity` looks like the right key and is not: the game labels it
"D-Pad size", it is the touch d-pad's size in pixels per millimetre, and the
launcher recomputes it from the window as `(w + h) / 2 / 25.4` on every launch,
so a hand-written value never survives.

- **The launcher now takes its interface scale from `NINECRAFT_GUI_SCALE`** and
  will go below 1.0. With the variable unset it behaves exactly as upstream
  does, on any device.
- **New quick menu VIDEO page**, holding SCREEN — moved off the main list — and
  a new **GUI SCALE** row: AUTO (shrink only as far as the hotbar needs, so
  240x240 is untouched and 120x120 fits), FIT (size the interface to the hotbar
  either way, which is *larger* at 240x240), STOCK (upstream, crispest, clips at
  120x120). AUTO is the default. Both rows are read at startup, so the page says
  a restart is needed and the main list's RESTART row does it.

Verified on hardware at 120x120: the launcher reports `scale 0.6522, 120 px laid
out as 184`, and the hotbar, hearts and chat button are all fully on screen
where the ends of all three used to run off it. At 240x240 the fit scale is
1.304, so AUTO returns before touching anything and that mode is unchanged.

## v1.0.3

- **"CLOSE GAME" is now "FORCE CLOSE".** It sends `SIGTERM` and then `SIGKILL`,
  so anything since Minecraft's last autosave is lost — the old label implied a
  tidier exit than it performs. RESTART and SHUTDOWN end the game the same way.
  To quit with a save, leave the world through the game's own pause menu
  (**L + START**). Documented rather than only renamed.

## v1.0.2

The quick menu gained the two settings worth having, and both are applied from
the console rather than by editing files.

- **CPU speed, 1008 to 1248 MHz in 48 MHz steps, applied immediately.** This is
  the only lever that touches the fixed ~70 ms of every frame, and unlike
  lowering the resolution it costs no picture quality. Measured: a fixed
  workload runs in 1.34 s at stock and 1.11 s at 1200 MHz — a 1.21x speed-up
  against the 1.19x the clock ratio predicts, so the register write really does
  change how fast the machine computes.
- **Screen size, 240x240 or 120x120**, with a RESTART row beside it because the
  game reads its render size once at startup and cannot change it while running.

The clock is set by writing the Allwinner CCU PLL through `/dev/mem`, which is
the only route on a console with no cpufreq interface. The CPU is moved onto the
24 MHz oscillator before the PLL it is running from is touched, the lock is
waited for with a timeout, and a PLL that does not lock is rolled back so a
rejected clock leaves the machine exactly as it was. The ladder stops at
1248 MHz — the V3s is specified at 1.2 GHz, and this SoC has neither thermal
management nor voltage control. Stock is restored when the game exits, and the
setting does not survive a reboot.

## v1.0.1

Driven by the first outside test report — a FunKey S owner whose menus worked
and whose Play exited with `rc=139`.

- **The launcher now provides swap when the console is short of it.** Entering a
  world needs about 68 MB of anonymous memory (40 MB resident + 28 MB swapped,
  measured) on hardware with 56 MB of RAM. The RG Nano's stock image has a
  128 MB swap partition and earlier versions simply assumed one. Where swap is
  adequate this does nothing; where it is not, menus fit and worlds do not,
  which fails in a thoroughly confusing way.
- **Every launch now logs its memory situation and the game library's identity**
  — size and sha256 — so a bug report carries the facts needed to triage it
  without a second round trip.
- Documented that both 0.8.1 APKs in the widely mirrored archive.org set contain
  a library byte-identical to the tested one, so a mismatched APK can be ruled
  out quickly.

**Not claimed:** that this fixes the FunKey S report. The tester's segfault
could not be reproduced here — removing swap from an RG Nano wedges it rather
than segfaulting it. The memory arithmetic stands on its own; whether it is
their bug is still unconfirmed.

## v1.0.0

First release. Minecraft Pocket Edition 0.8.1 on the Anbernic RG Nano.

- Runs in a world at **7.8 fps at the native 240x240**, measured by replaying a
  recorded play session. For comparison, Bedrock 1.2 on the same console manages
  2.2 fps and crashes after about 75 seconds.
- **Nothing is recompiled for this console.** The glibc launcher runs on a musl
  system via a bundled loader invoked explicitly; Mesa llvmpipe draws in
  software to `/dev/fb0` as RGB565.
- **Controls remapped at the GPIO source** through `fkgpiod`, so the binary's
  expectation of another console's key codes is satisfied without a rebuild.
- **In-game quick menu** on L+SELECT: volume, brightness, close game, shutdown,
  resume. It freezes the game while open, which is what lets it draw at all.
- **Installs your own APK on the device**, including the nested "wrapper" layout
  most 0.8.1 downloads use.
- Performance options are **seeded on first run**, so a fresh install matches the
  documented figures instead of starting on the engine's defaults.
