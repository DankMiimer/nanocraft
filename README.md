# NanoCraft

**Minecraft Pocket Edition 0.8.1 on the Anbernic RG Nano and the FunKey S.**

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

## Why Pocket Edition and not Bedrock

My other ports run Bedrock. On hardware this small it barely works — 2.2 fps,
and it crashes after about 75 seconds. Pocket Edition 0.8.1 is a 2013 build with
a fraction of the engine cost, it runs at the panel's native resolution, and it
is the last version before infinite worlds, which is the version worth having on
a console like this.

## Honestly, how well does it run?

**About 12–15 fps in a world.** No GPU, one CPU core, every pixel drawn in
software. It is enough to build, explore and potter about; it is not enough for
combat. Nothing here is estimated — the numbers came off a physical console.

Full measurements, the settings that affect them, and the overclock:
**[docs/PERFORMANCE.md](docs/PERFORMANCE.md)**.

## What you need

- An **Anbernic RG Nano** or a **FunKey S**, running DrUm78's FunKey-OS build.
- About **300 MB free** on the card.
- **Your own Pocket Edition 0.8.1 APK**, 32-bit `armeabi-v7a`.

## Get it

Download the latest release, copy the `.opk` into `/mnt/Native games/`, extract
the payload into `/mnt/FunKey/nanocraft/`, and drop your APK in
`/mnt/FunKey/nanocraft/apk/`. The first launch installs the game by itself.

**[Releases](https://github.com/DankMiimer/nanocraft/releases/latest)** ·
**[Full install guide](INSTALL.md)**

**If it will not start**, your console's kernel probably has not been checked
yet — NanoCraft refuses rather than risk it. It writes `nanocraft-kernel.txt` to
the root of your card when that happens;
[open an issue](https://github.com/DankMiimer/nanocraft/issues) and attach it.
That is all it took to add the FunKey S.

## The controls you would not guess

**L is the modifier**, and the four face buttons are the right stick.

| Input | Action |
| --- | --- |
| X / B / Y / A | look up / down / left / right |
| **R** | break block — also *click* in menus |
| **L + X** | place block |
| **L + SELECT** | quick menu |
| hold MENU 2 s | quit |

Full map in [INSTALL.md](INSTALL.md).

## The quick menu

![The NanoCraft quick menu: volume and brightness bars, close game, shutdown and
resume.](docs/img/quick-menu.png)

**L + SELECT** for volume, brightness, CPU clock, resolution, field of view and
camera and cursor sensitivity. It exists because on this OS the power menu is
drawn by whatever app is in the foreground, so a game either provides one or you
get nothing.

## Under the hood

Nothing was recompiled for this console — it ships Debian's glibc, draws through
Mesa llvmpipe into `/dev/fb0`, and remaps the buttons at the GPIO source.

- **[docs/PORTING.md](docs/PORTING.md)** — the engineering write-up
- **[docs/PERFORMANCE.md](docs/PERFORMANCE.md)** — what was measured, and how
- **[docs/NATIVE-UI.md](docs/NATIVE-UI.md)** — a 120x120 world under a 240x240 interface
- **[docs/crash-evidence/](docs/crash-evidence/)** — how Play crashed on every console but mine
- **[docs/kernel-audits/](docs/kernel-audits/)** — how a console gets added to the supported list
- **[CHANGELOG.md](CHANGELOG.md)** · **[build/](build/)** — history, and the build recipes

## How much of this was written by AI

Most of it, and you should know that before running it on your own hardware.
NanoCraft was built with AI coding assistants working from my direction.

What that does not cover is the hardware: **every performance and memory figure
was measured on a physical console**, and where something is untested the text
says so rather than rounding it up into a claim. I chose the approach, ran the
console, decided what shipped, and the mistakes are mine.

## Legal

NanoCraft distributes launcher scripts, a presenter, a quick menu and a software
OpenGL stack. **No Minecraft APKs, libraries, assets or worlds are included, and
none ever will be.** Nothing here mirrors game files, defeats a protection
measure, or provides any way to obtain Minecraft without owning it.

See [LEGAL.md](LEGAL.md), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[TRADEMARKS.md](TRADEMARKS.md).

## Credits

- **[Ninecraft](https://github.com/MCPI-Revival/Ninecraft)** (MIT) — the launcher
  this port patches and ships. It does the hard part.
- **[Mesa](https://www.mesa3d.org/)** — llvmpipe and OSMesa, doing all the drawing.
- **[DrUm78's FunKey-OS](https://github.com/DrUm78/FunKey-OS)** — the OS, its
  `fkgpiod` remapping and GMenu2X.
- **[badcats72](https://github.com/badcats72)** — testing on the FunKey S across
  four releases, and sending the kernel image that got that console supported.

## My other Minecraft handheld ports

- **[minecraft-bedrock-miyoo-mini-plus](https://github.com/DankMiimer/minecraft-bedrock-miyoo-mini-plus)**
  — Bedrock on the Miyoo Mini Plus. NanoCraft's client and Mesa build come from there.
- **[minecraft-bedrock-handheld-port](https://github.com/DankMiimer/minecraft-bedrock-handheld-port)**
  — the RG34xxSP / PortMaster port.
- **[mcbedrock-get](https://github.com/DankMiimer/mcbedrock-get)** — a helper for
  downloading your own Bedrock APK.
