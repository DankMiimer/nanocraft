# Changelog

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
