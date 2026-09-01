# Changelog

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
