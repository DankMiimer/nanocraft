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
| **240x240 — recommended** | **7.8 fps** | native, 1:1, nothing clipped |
| 120x120 | 11.9 fps | soft 2x upscale, hotbar clips at the edges |

**Both figures are in-world**, measured by replaying a recorded real play session
against the same restored world — not by standing still on a title screen. A
title screen reads 11.6 fps at 240x240 and means nothing.

**Why 240x240 despite being slower.** Quartering the pixel count buys only
+52%, because about **70 ms of every frame is fixed** — roughly 46 ms of
Minecraft's own logic and 23 ms of rasterizer overhead, neither of which cares
about resolution:

```text
frame_ms  ~=  70.6  +  0.00094 x pixels
```

So resolution alone tops out near 14 fps no matter how far you drop it, while
120x120 costs you a soft picture and a clipped hotbar for four frames. 240x240
and 120x120 are the only sizes that divide the panel cleanly; anything between
them shimmers.

Set `/mnt/FunKey/nanocraft/resolution.txt` to `120 120` if you want to try it.

**8 fps is what this hardware does.** It is enough to build, explore and potter
about. It is not enough for combat.

### Overclocking helps, and costs no picture quality

It is the only lever left that attacks that fixed 70 ms, because all of it is
CPU time:

| Clock | 240x240 | 120x120 |
| --- | ---: | ---: |
| 1008 MHz (stock) | 7.8 fps | 11.9 fps |
| 1200 MHz | ~9.4 fps | ~14.2 fps |

**NanoCraft ships no overclock code and never will** — a wrong PLL value hangs
the console until you pull the battery. Use DrUm78's separate `Overclock.opk`,
at your own risk. The setting persists until reboot, so set it once and launch.

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

| | Resident | Swapped | Total anonymous |
| --- | ---: | ---: | ---: |
| Title screen | 37 MB | 5 MB | 42 MB |
| **In a world** | 40 MB | 28 MB | **68 MB** |

The console has **56 MB of RAM**, of which roughly 41 MB is available to the
game. So **entering a world needs about 27 MB more than RAM alone can provide**,
on any console of this class. The RG Nano's stock image happens to include a
128 MB swap partition, and earlier versions of NanoCraft simply assumed it.

Menus fit in RAM; a world does not. A console short of swap therefore shows
every menu perfectly and dies the moment terrain loads — which is exactly the
reported symptom.

**Since v1.0.1 NanoCraft checks, and provides swap when the system is short**
(`opk/ensure-swap.sh`). On a console with adequate swap it reads
`/proc/meminfo`, logs three numbers and does nothing. `/mnt` is vfat and Linux
will not swap to a file on vfat, so it loops the file through a block device —
and it has to find a free one, because the running OPK is itself a loop-mounted
squashfs occupying `/dev/loop0`.

**Honesty about what this does not prove.** I could not reproduce the tester's
`rc=139` on my own hardware. Taking swap away from an RG Nano makes it *wedge*
under memory pressure rather than segfault — a different failure. So the memory
arithmetic above is solid and the guard is worth having regardless, but whether
it is *their* bug is unconfirmed. Every launch now logs

```text
[mem] RAM 55 MB total, 36 MB available; swap 127 MB
```

so the next report will contain the answer whether or not anyone thinks to ask.

Everything else about a FunKey S looks compatible — same FunKey-OS, same
`fkgpiod`, same 240x240 panel, same Allwinner V3s family, and this package is
already named `.funkey-s.desktop` because that is the suffix the OS wants on
both. Reports welcome either way.

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

**L + SELECT** brings up volume, brightness, close game, shutdown and resume.
D-pad to move, left/right to change a value, A to pick, B to go back.

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
