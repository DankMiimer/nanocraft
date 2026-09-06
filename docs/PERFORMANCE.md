# What performance to honestly expect

The RG Nano has **no GPU at all** and **one** Cortex-A7 core at 1008 MHz. Every
pixel is drawn by a software rasterizer. Everything below was measured on a
physical console, not estimated.

| Internal resolution | Frame rate | Picture |
| --- | ---: | --- |
| **120x120 — the default** | **11.9 fps** | soft 2x upscale of the world only |
| 240x240 | 7.8 fps | native, 1:1, sharpest |

The default no longer costs a soft *interface*. At 120x120 the world renders at
120x120 and the hotbar, items, HUD and menus are drawn over it at the panel's
real 240x240, so only the world is upscaled. See [NATIVE-UI.md](NATIVE-UI.md).

**Both figures are in-world**, measured by replaying a recorded real play session
against the same restored world — not by standing still on a title screen. A
title screen reads 11.6 fps at 240x240 and means nothing.

> **These numbers are from before v1.0.8 and now understate the port.** The
> launcher had been overriding the presenter's own documented default and
> enabling an asynchronous present path that cannot pay on a single core. With
> it off, a live session at 120x120 measured **12.9 → 14.9 fps median**, about
> +16%, with the readback dropping from 37.6 ms a frame to 0.4. The table above
> and the frame-time model below have not been re-measured on the replay rig, so
> treat them as a floor rather than as current.

**8 fps is what this hardware does.** It is enough to build, explore and potter
about. It is not enough for combat.

## Why 120x120 is the default

Quartering the pixel count buys +52%, not the 4x a fill-rate-bound workload
would give, because about **70 ms of every frame is fixed** — roughly 46 ms of
Minecraft's own logic and 23 ms of rasterizer overhead, neither of which cares
about resolution:

```text
frame_ms  ~=  70.6  +  0.00094 x pixels
```

So resolution alone tops out near 14 fps no matter how far you drop it. +52% is
still the largest single gain available, though, and until v1.0.5 it came with a
hotbar cut off at both edges, which is why 240x240 was recommended instead. That
is fixed, so the trade is now four frames against a softer world, and four
frames matter a great deal at eight.

**Prefer the sharper image?** 240x240 is one row away in the quick menu
(**L + SELECT → SETTINGS → SCREEN**), then RESTART to apply it — the game reads
the size once at startup, so it cannot change in a running process. Editing
`/mnt/FunKey/nanocraft/resolution.txt` does the same thing. Those two are the
only sizes that divide the panel cleanly; anything between them shimmers.

## GUI scale

120x120 used to cut the ends off the hotbar, which is the only reason it was not
the default. That was never a Minecraft setting going wrong: Ninecraft lays the
interface out at a scale it computes from the window and **floors that scale at
1.0**, and Minecraft's hotbar is 182 interface pixels wide, so a 120-pixel-wide
screen was simply 62 pixels too narrow for it. Nothing in the game's own options
could reach it — `gfx_pixeldensity`, despite the name, is the touch d-pad's size
in pixels per millimetre and is recomputed from the window on every launch.

This port's launcher takes the scale from the environment and will go below that
floor. **SETTINGS → GUI SCALE**:

| | What it does |
| --- | --- |
| **FIT** (default) | Size the interface to the hotbar in either direction. At 120x120 that shrinks it to fit; at 240x240 it *grows* into the spare room. Never clipped at either, so it is the one setting that suits both screen sizes. |
| **AUTO** | Shrink only as far as the hotbar needs, and never grow. Identical to FIT at 120x120; leaves 240x240 exactly as older versions drew it. |
| **STOCK** | One interface pixel per rendered pixel, exactly as Ninecraft ships. Crispest, and clips at 120x120. |

Like SCREEN, it is read at startup, so it takes a RESTART.
`/mnt/FunKey/nanocraft/guiscale.txt` holds the same value.

**Release audit, September 2026:** the v1.0.10 release archive shipped an older
runtime without the GUI-scale and FOV patches described here, so selecting FIT
could not fix anything — the binary had no code behind the setting. That is
corrected from v1.0.11, and the packaging guard that would have caught it now
runs on every package. See the [120x120 UI plan](UI-120-PLAN.md) for the
evidence and what followed.

## Field of view

**SETTINGS → FOV**, 50 to 100 degrees. **70 is what Minecraft ships with**, and
choosing 70 changes nothing at all.

Pocket Edition 0.8.1 has no FOV setting — its entire settings vocabulary is 21
keys and none of them is one. (`assets/lang/en_US.lang` does contain
`options.fov=FOV`, but that file is inherited desktop-Minecraft boilerplate; it
also offers 3D Anaglyph and warns you about 64-bit *Java* installs. A string
there is not evidence the game implements anything.)

What the engine does have is `GameRenderer::getFov()`, whose result
`setupCamera()` hands straight to `gluPerspective`, and whose base angle is a
single number sitting in the code. This port's launcher rewrites that one number
at startup. That is exactly what Minecraft's own FOV slider does, so the sprint
and low-health effects still apply on top of whatever you pick, and the item in
your hand keeps its own fixed angle — which is why it does not distort when you
go wide, the same as in vanilla.

A narrow angle magnifies distant things; a wide one shows far more around you at
the cost of stretching the edges. Neither is faster: the same world is drawn
either way. Read at startup, so it takes a RESTART, and
`/mnt/FunKey/nanocraft/fov.txt` holds the same value.

## Overclocking

It is the only lever left that attacks that fixed 70 ms, because all of it is
CPU time — and unlike dropping the resolution it costs **no picture quality**.

| Clock | 240x240 | 120x120 |
| --- | ---: | ---: |
| 1008 MHz (stock) | 7.8 fps | 11.9 fps |
| 1200 MHz | ~9.4 fps | ~14.2 fps |

**L + SELECT → CPU**, then left/right. 1008 to 1248 MHz in 48 MHz steps, applied
immediately. Measured here: a fixed workload runs in 1.34 s at stock and 1.11 s
at 1200 MHz, a 1.21x speed-up against the 1.19x the clock ratio predicts.

**Read this before using it.** This SoC has **no thermal management and no
voltage control**, so nothing steps in to protect it and these are overclocks at
the stock voltage. The ladder stops at 1248 because the V3s is specified at
1.2 GHz; the tool refuses to go further. Every step was verified on one console
here — yours may differ. Nothing is written to storage: the clock lives in a
register, NanoCraft restores stock when you quit, and a reboot clears it
regardless. If the console locks up, power-cycle it and pick a lower step.

## Memory: the budget this port lives inside

Measured in a world, on two different consoles:

| | development console | factory console |
| --- | ---: | ---: |
| Game resident | 28 MB | 42 MB |
| Held compressed | 37 MB | 36 MB |
| **Total anonymous** | **65 MB** | **65 MB** |
| RAM the console has | 56 MB | 54 MB |
| Free at the worst moment | 3.9 MB | 4.2 MB |

**Entering a world needs about 10 MB more anonymous memory than this hardware
physically has**, and since v1.0.6 that difference is found in RAM rather than on
your card. The launcher loads zram and LZ4 holds those pages at a measured
**2.7:1**, so roughly 36 MB of idle pages occupy about 13 MB. Nothing is written
to the SD card at any point. Details in [PORTING.md](PORTING.md).

That ~4 MB floor is why you will feel occasional stalls: a page the game touches
that lives in zram has to be decompressed on the same core that draws the frame.

**The one thing that may not travel is the kernel modules.** These kernels have
no zram, so NanoCraft ships its own — and a kernel module is built for one
specific kernel. `opk/modules/kernels` lists the builds that have actually been
verified; on anything else NanoCraft says so and refuses to start rather than run
without the memory it needs. Adding a console needs no firmware change and often
no new modules at all: see [kernel-audits/](kernel-audits/) for how the FunKey S
was added, and [`opk/modules/README.md`](../opk/modules/README.md) for the build.
