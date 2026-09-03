# Changelog

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
