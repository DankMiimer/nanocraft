# NanoCraft

**Minecraft Pocket Edition 0.8.1 on the Anbernic RG Nano.**

![Minecraft Pocket Edition running on an RG Nano: a grass field with a tree, a
chest and furnaces, hearts and a full hotbar, on the console's square 240x240
screen.](docs/img/in-world.png)

*Not a mock-up. That is 0.8.1 running on the Nano at its native 240x240, drawn
entirely in software on one CPU core.*

> **No game files are included.** You supply your own official Minecraft Pocket
> Edition APK.
>
> **NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH
> MOJANG OR MICROSOFT.**

---

## This is Pocket Edition, not Bedrock — and that is the point

My two other ports run **Bedrock** on handhelds. On the RG Nano that barely
works: Bedrock 1.2.20.2 manages **2.2 fps** here and crashes reproducibly after
about 75 seconds.

NanoCraft runs **Pocket Edition 0.8.1** instead, a 2013 build with a fraction of
the engine cost. Same console, same software renderer:

| | Bedrock 1.2.20.2 | **Pocket Edition 0.8.1** |
| --- | ---: | ---: |
| In a world | 2.2 fps | **7.8 fps** |
| Resolution | 80x80, upscaled | **240x240 native** |
| Stability | crashes at ~75 s | stable |

0.8.1 is also the last version before infinite worlds, which is the version
worth having on a console like this.

## What performance to honestly expect

The RG Nano has **no GPU at all** and **one** Cortex-A7 core at 1008 MHz. Every
pixel is drawn by a software rasterizer.

| Internal resolution | Frame rate | Picture |
| --- | ---: | --- |
| **120x120 — the default** | **11.9 fps** | soft 2x upscale, whole interface |
| 240x240 | 7.8 fps | native, 1:1, sharpest |

**Both figures are in-world**, measured by replaying a recorded real play session
against the same restored world — not by standing still on a title screen. A
title screen reads 11.6 fps at 240x240 and means nothing.

**Why 120x120 is the default.** Quartering the pixel count buys +52%, not the
4x a fill-rate-bound workload would give, because about **70 ms of every frame
is fixed** — roughly 46 ms of Minecraft's own logic and 23 ms of rasterizer
overhead, neither of which cares about resolution:

```text
frame_ms  ~=  70.6  +  0.00094 x pixels
```

So resolution alone tops out near 14 fps no matter how far you drop it. +52% is
still the largest single gain available, though, and until v1.0.5 it came with a
hotbar cut off at both edges, which is why 240x240 was recommended instead. That
is fixed, so the trade is now four frames against a softer picture, and four
frames matter a great deal at eight.

**Prefer the sharper image?** 240x240 is one row away in the quick menu
(**L + SELECT → VIDEO → SCREEN**), then RESTART to apply it — the game reads the
size once at startup, so it cannot change in a running process. Editing
`/mnt/FunKey/nanocraft/resolution.txt` does the same thing. Those two are the
only sizes that divide the panel cleanly; anything between them shimmers.

### GUI scale

120x120 used to cut the ends off the hotbar, which is the only reason it was not
the default. That was never a Minecraft setting going wrong: Ninecraft lays the
interface out at a scale it computes from the window and **floors that scale at
1.0**, and Minecraft's hotbar is 182 interface pixels wide, so a 120-pixel-wide
screen was simply 62 pixels too narrow for it.
Nothing in the game's own options could reach it — `gfx_pixeldensity`, despite
the name, is the touch d-pad's size in pixels per millimetre and is recomputed
from the window on every launch.

This port's launcher takes the scale from the environment and will go below that
floor. **VIDEO → GUI SCALE**:

| | What it does |
| --- | --- |
| **FIT** (default) | Size the interface to the hotbar in either direction. At 120x120 that shrinks it to fit; at 240x240 it *grows* into the spare room. Never clipped at either, so it is the one setting that suits both screen sizes. |
| **AUTO** | Shrink only as far as the hotbar needs, and never grow. Identical to FIT at 120x120; leaves 240x240 exactly as older versions drew it. |
| **STOCK** | One interface pixel per rendered pixel, exactly as Ninecraft ships. Crispest, and clips at 120x120. |

Like SCREEN, it is read at startup, so it takes a RESTART.
`/mnt/FunKey/nanocraft/guiscale.txt` holds the same value.

### Field of view

**VIDEO → FOV**, 50 to 100 degrees. **70 is what Minecraft ships with**, and
choosing 70 changes nothing at all.

Pocket Edition 0.8.1 has no FOV setting — its entire settings vocabulary is 21
keys and none of them is one. (`assets/lang/en_US.lang` does contain
`options.fov=FOV`, but that file is inherited desktop-Minecraft boilerplate; it
also offers 3D Anaglyph and warns you about 64-bit *Java* installs. A string
there is not evidence the game implements anything.)

What the engine does have is `GameRenderer::getFov()`, whose result
`setupCamera()` hands straight to `gluPerspective`, and whose base angle is a
single number sitting in the code. This port's launcher rewrites that one
number at startup. That is exactly what Minecraft's own FOV slider does, so the
sprint and low-health effects still apply on top of whatever you pick, and the
item in your hand keeps its own fixed angle — which is why it does not distort
when you go wide, the same as in vanilla.

A narrow angle magnifies distant things; a wide one shows far more around you
at the cost of stretching the edges. Neither is faster: the same world is drawn
either way. Read at startup, so it takes a RESTART, and
`/mnt/FunKey/nanocraft/fov.txt` holds the same value.

**8 fps is what this hardware does.** It is enough to build, explore and potter
about. It is not enough for combat.

### Overclocking, in the quick menu

It is the only lever left that attacks that fixed 70 ms, because all of it is
CPU time — and unlike dropping the resolution it costs **no picture quality**.

| Clock | 240x240 | 120x120 |
| --- | ---: | ---: |
| 1008 MHz (stock) | 7.8 fps | 11.9 fps |
| 1200 MHz | ~9.4 fps | ~14.2 fps |

**L + SELECT → CPU**, then left/right. 1008 to 1248 MHz in 48 MHz steps,
applied immediately. Measured here: a fixed workload runs in 1.34 s at stock and
1.11 s at 1200 MHz, a 1.21x speed-up against the 1.19x the clock ratio predicts.

**Read this before using it.** This SoC has **no thermal management and no
voltage control**, so nothing steps in to protect it and these are overclocks at
the stock voltage. The ladder stops at 1248 because the V3s is specified at
1.2 GHz; the tool refuses to go further. Every step was verified on one console
here — yours may differ. Nothing is written to storage: the clock lives in a
register, NanoCraft restores stock when you quit, and a reboot clears it
regardless. If the console locks up, power-cycle it and pick a lower step.

## What you need

- An **Anbernic RG Nano** running DrUm78's FunKey-OS build.
- About **300 MB free** on the card.
- **Your own Pocket Edition 0.8.1 APK**, 32-bit `armeabi-v7a`.

## FunKey S: menus work, entering a world does not (yet)

I only own an RG Nano, but a **FunKey S** owner on the latest DrUm78 build has
tried it, and the result is genuinely useful:

> main menu works, options menu works, **Play crashes to desktop**

So the hard parts port cleanly. Their log shows the framebuffer at 240x240, the
RGB565 presenter running, llvmpipe rendering and the buttons arriving correctly
— then `rc=139`, which is a **segfault**, at the moment Play is pressed.

### Ruled out: the APK

My first guess was that they had a different build of 0.8.1, because Ninecraft
reads the game's C++ objects at hard-coded byte offsets that were validated
against one specific library. **That guess was wrong.** Both 0.8.1 APKs from the
archive.org set contain a `libminecraftpe.so` that is **byte-identical** to the
one this port was tested against:

```text
libminecraftpe.so   9,668,996 bytes
sha256              baf9ca243fa301b7a9b4755ddc97aba1f0d35c9b1b80479980b47d6455a32677
```

Same game, same file, different result. So the difference is the console or its
OS image, not the content.

(The installer still records that size and sha256 into `install.log`, because
ruling this out in one line is worth the second it costs.)

### What is measured, and what shipped

Measured on an RG Nano, which is the same hardware class:

| | Resident | Held compressed | Total anonymous |
| --- | ---: | ---: | ---: |
| Title screen | 37 MB | 5 MB | 42 MB |
| **In a world** | 28 MB | 37 MB | **65 MB** |

The console has **56 MB of RAM**, of which roughly 41 MB is available to the
game. So **entering a world needs about 10 MB more anonymous memory than this
hardware physically has**, on any console of this class.

Menus fit; a world does not. A console that cannot find that extra headroom
therefore shows every menu perfectly and dies the moment terrain loads — which
is exactly the reported symptom.

**Since v1.0.6 NanoCraft makes that headroom itself, in RAM.** It loads zram, a
compressed block device the kernel can move idle pages into, and lets LZ4 do
the rest: measured on this game the ratio is **2.7:1**, with around 1,500
identical pages deduplicated outright, so 40 MB of idle pages occupy about
14 MB. Nothing is written to your card at any point. Details in
[docs/PORTING.md](docs/PORTING.md).

**Honesty about what this does not prove.** I could not reproduce the tester's
`rc=139` on my own hardware, and the memory arithmetic above being solid does
not make it *their* bug. What v1.0.6 changes is that the headroom now exists on
any console where the modules load, so if memory was the cause, it should be
gone. Every launch logs what happened:

```text
[mem] RAM 55 MB total, 41 MB available
[mem] zram: 80 MB logical, lz4, 24 MB RAM ceiling
```

so the next report will contain the answer whether or not anyone thinks to ask.

**The one thing that may not travel is the modules.** The RG Nano's kernel has
no zram, so NanoCraft ships its own — and a kernel module is built for one
specific kernel and refuses to load on any other. Mine were built for, and
tested on, **my** console. If yours is a different build they will not load, and
NanoCraft will say so and refuse to start rather than run without the memory it
needs. That is a worse outcome than v1.0.5 gave you, and it is the thing most
worth reporting.

Rebuilding them needs no firmware change and no special hardware — the
configuration, the exact build commands and the audit step are all in
[`opk/modules/README.md`](opk/modules/README.md). If they do not load on your
console, please open an issue with the `[mem]` line and `uname -a`; that is
enough for me to build a set that does.

Everything else about a FunKey S looks compatible — same FunKey-OS, same
`fkgpiod`, same 240x240 panel, same Allwinner V3s family, and this package is
already named `.funkey-s.desktop` because that is the suffix the OS wants on
both. Reports welcome either way.

### If it fails for you, there is a diagnostic build

**`NanoCraftDiag_funkey-s.opk`** on the
[releases page](https://github.com/DankMiimer/nanocraft/releases/latest) answers
most of the questions in one run, so nobody has to be asked the same thing five
times. It records the console, probes how much memory a process can really
obtain, runs the game normally, and — the useful part — turns on the kernel's
fault reporting first and captures the game's memory map while it lives, so any
crash address can be **resolved to the library that faulted and the offset
inside it**.

It writes `nanocraft-report.txt` to the **root of the SD card** and **sends
nothing** — the packaging script refuses to build it if any network code
appears. These consoles have no networking, so the card is how the file
travels, and the root is where you will actually find it. Full instructions in
[INSTALL.md](INSTALL.md).

## Install

See **[INSTALL.md](INSTALL.md)**. In short: copy the `.opk` into
`/mnt/Native games/`, extract the payload into `/mnt/FunKey/nanocraft/`, drop
your APK in `/mnt/FunKey/nanocraft/apk/`, and launch. The first run installs the
game from your APK by itself.

## Controls

The Nano has no second stick, so **the four face buttons are the right stick**,
and **L is the modifier** for everything else.

| Input | Action |
| --- | --- |
| D-pad | move |
| X / B / Y / A | look up / down / left / right |
| **R** | break block — also *click* in menus |
| **L + X** | place block |
| **L + Y** | inventory |
| **L + A** | jump |
| **L + B** | crouch |
| **L + START** | start menu |
| START | hotbar right |
| SELECT | hotbar left |
| **L + SELECT** | quick menu |
| hold MENU 2 s | quit |

Looking accelerates: a tap nudges the camera, holding speeds it up.

## The quick menu

![The NanoCraft quick menu: volume and brightness bars, close game, shutdown and
resume.](docs/img/quick-menu.png)

**L + SELECT** brings it up. D-pad to move, left/right to change a value, A to
pick, B to go back.

| Row | What it does |
| --- | --- |
| VOLUME / BRIGHT | adjust, immediately |
| **CPU** | 1008 – 1248 MHz in 48 MHz steps, **applies at once** |
| **VIDEO** | opens the video page — SCREEN, GUI SCALE and FOV |
| RESTART | relaunch the game, which is how a video change is applied |
| **FORCE CLOSE** | kills the game — see below |
| SHUTDOWN / RESUME | leave |

The video page holds the settings the game reads only at startup, which is why
they share a page and why it says so at the bottom of it:

| Row | What it does |
| --- | --- |
| **SCREEN** | 240x240 or 120x120 — **needs a restart** |
| **GUI SCALE** | AUTO, FIT or STOCK — **needs a restart**. See [GUI scale](#gui-scale) |
| **FOV** | 50 to 100 degrees, 70 is stock — **needs a restart**. See [Field of view](#field-of-view) |
| BACK | to the main list; B does the same |

**FORCE CLOSE is named for what it does.** It sends `SIGTERM` and then `SIGKILL`,
so anything since Minecraft's last autosave is lost. To quit with a save, use
the game's own pause menu (**L + START**) and leave the world from there.
RESTART and SHUTDOWN close the game the same way, so the same applies.

This exists because on this OS **the power menu is drawn by whatever app is in
the foreground**, not by the system — so a game either provides one or you get
nothing. The menu freezes the game while it is open, which is why it can draw
over it at all.

## Things worth knowing

**No audio.** The game runs on SDL's dummy audio driver. Sound is untested.

**Crafting is not bound.** In this engine jump, crouch, inventory and craft all
live on the same modifier, and `L+X` is spent on place-block. Inventory is the
more useful of the two screens on a console this size.

**LAN multiplayer appears to work.** With another 0.8.1 console on the same
wifi, its world showed up in the list. Not tested beyond that, and not a feature
claim.

**A frozen picture usually means the game exited**, not that it hung — nothing
else redraws the screen afterwards.

## How it works

The interesting part is that **nothing was recompiled for this console.**

- **The RG Nano is a musl system; the launcher is a glibc binary.** Rather than
  port it, NanoCraft ships Debian Buster's glibc and *invokes the bundled loader
  explicitly* — `ld-linux-armhf.so.3 --library-path … ./ninecraft`. Unlike
  patching `PT_INTERP`, this survives the install directory being moved.
- **Software OpenGL via Mesa llvmpipe**, blitted to `/dev/fb0` as RGB565 by a
  small presenter written for this port. llvmpipe measured **3.7x faster than
  softpipe** here — the opposite of what the port plan assumed.
- **Controls are remapped at the GPIO source.** The binary expects a *different
  console's* key codes, so instead of rebuilding it, `fkgpiod` is told to emit
  those codes. Zero runtime cost.

Full engineering write-up: **[docs/PORTING.md](docs/PORTING.md)**.

## Building it yourself

The build recipes ship in [`build/`](build/) — the Dockerfiles and the Ninecraft
patch — so what you are running can be reproduced. A verified step-by-step build
guide is not written yet.

## How much of this was written by AI

Most of it, and you should know that before you run it on your own hardware.

NanoCraft was built with AI coding assistants — Claude and ChatGPT — working
from my direction. That covers the launcher scripts, the framebuffer presenter,
the quick menu, the packaging, the zram work, and most of the documentation in
this repository including this README. The write-ups in `docs/` started life as
notes one agent left for the next, which is why they read the way they do.

What it does not cover is the hardware. **Every performance and memory figure
here was measured on a physical RG Nano**, not estimated and not produced by a
model, and every feature was tried on the console before it was described as
working. The frame rates, the 2.7:1 compression ratio, the memory floor during
world entry — those came off the device. Where something is unmeasured or
untested, the text says so rather than rounding it up into a claim.

I chose the approach, ran the console, decided what shipped, and the mistakes in
it are mine. I am saying this plainly because "an AI wrote it" is worth knowing
when you are deciding whether to trust software with your SD card, and finding
it out later is worse than being told.

## Legal

NanoCraft distributes launcher scripts, a framebuffer presenter, a quick menu and
a software OpenGL stack. **No Minecraft APKs, game libraries, assets or worlds
are included, and none ever will be.** You supply your own legally obtained copy.

Nothing here mirrors or hosts game files, defeats a protection measure, or
provides any way to obtain Minecraft without owning it.

See [LEGAL.md](LEGAL.md), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[TRADEMARKS.md](TRADEMARKS.md).

## Credits

- **[Ninecraft](https://github.com/MCPI-Revival/Ninecraft)** (MIT) — the launcher
  this port patches and ships. It does the hard part.
- **[Mesa](https://www.mesa3d.org/)** — llvmpipe and OSMesa, doing all the drawing.
- **[DrUm78's FunKey-OS](https://github.com/DrUm78/FunKey-OS)** — the RG Nano OS,
  its `fkgpiod` remapping and GMenu2X.

## My other Minecraft handheld ports

- **[minecraft-bedrock-miyoo-mini-plus](https://github.com/DankMiimer/minecraft-bedrock-miyoo-mini-plus)**
  — Bedrock 1.2.20.2 on the Miyoo Mini Plus. NanoCraft's client, Mesa build and
  EGL shim all come from there.
- **[minecraft-bedrock-handheld-port](https://github.com/DankMiimer/minecraft-bedrock-handheld-port)**
  — the RG34xxSP / PortMaster port.
- **[mcbedrock-get](https://github.com/DankMiimer/mcbedrock-get)** — a helper for
  downloading your own Bedrock APK. Bedrock only; NanoCraft needs a Pocket
  Edition APK instead.
