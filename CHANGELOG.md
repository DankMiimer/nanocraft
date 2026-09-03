# Changelog

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
