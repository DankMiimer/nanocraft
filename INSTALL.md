# Installing NanoCraft

Every step here was walked through on a wiped console, from the release archive
alone. If something needs knowledge this page does not contain, that is a bug in
this page.

> **No game files are included.** You supply your own legally obtained Minecraft
> Pocket Edition 0.8.1 APK, 32-bit `armeabi-v7a`.

## What you need

- An **Anbernic RG Nano** running DrUm78's FunKey-OS build.
- About **300 MB free** on the card — 48 MB port, ~20 MB extracted game, the
  rest headroom for worlds.
- Your own **Pocket Edition 0.8.1 APK**.
- A card reader, or SSH access to the console.

## 1. Copy the launcher

From the release archive, into the games folder:

```text
NanoCraft_funkey-s.opk  ->  /mnt/Native games/
NanoCraft_funkey-s.png  ->  /mnt/Native games/
```

## 2. Extract the payload

Create `/mnt/FunKey/nanocraft/` and extract `nanocraft-payload.tar.gz` into it,
so you end up with exactly this:

```text
/mnt/FunKey/nanocraft/ninecraft
/mnt/FunKey/nanocraft/runtime/
/mnt/FunKey/nanocraft/gl/
/mnt/FunKey/nanocraft/mesa/
/mnt/FunKey/nanocraft/egl-wrap/
/mnt/FunKey/nanocraft/lib/
```

Easiest is to extract on your PC and copy the six entries across.

**If you extract on the console over SSH**, note that its BusyBox `tar` has
**neither `-z` nor `-a`**, so the obvious command fails:

```bash
mkdir -p /mnt/FunKey/nanocraft && gunzip -c nanocraft-payload.tar.gz | tar x -C /mnt/FunKey/nanocraft/
```

## 3. Add your own APK

```text
/mnt/FunKey/nanocraft/apk/your-minecraft.apk
```

The root of the card also works.

Most 0.8.1 downloads are **wrapper APKs**, with the real game nested inside at
`assets/applications/package.apk`. NanoCraft detects that and unwraps it for
you — you do not need to do anything special.

## 4. Launch

Reboot, or restart the front end, then pick **NanoCraft** from Games.

**The first launch installs the game from your APK.** It takes a minute or two
and **the screen does not move while it works** — that is normal, do not power
off. Every launch after that goes straight to the game.

## Optional settings

**Resolution.** The default is 120x120, for roughly 12 fps instead of 8, at the
cost of a soft 2x-upscaled picture. Write `240 240` into
`/mnt/FunKey/nanocraft/resolution.txt` for the native, sharper image. Those are
the only two sizes that divide the panel cleanly. The quick menu's VIDEO page
does the same thing.

**GUI scale.** `/mnt/FunKey/nanocraft/guiscale.txt` holds `fit` (the default:
size the interface to the hotbar, which shrinks it to fit at 120x120 and grows
it into the spare room at 240x240), `auto` (shrink only when it must, so
240x240 is left as older versions drew it) or a number. Also on the quick menu's
VIDEO page.

**Field of view.** `/mnt/FunKey/nanocraft/fov.txt` holds an angle in degrees
from 50 to 100. 70 is what Minecraft ships with and is the default; choosing it
changes nothing. The game itself has no FOV setting — the launcher rewrites the
angle the renderer uses. Also on the quick menu's VIDEO page.

**Controls.** Drop your own `minecraft.key` into `/mnt/FunKey/nanocraft/` and it
overrides the packaged one. Verify any edit with `keymap save`, because
`fkgpiod`'s config parser is off by one above key code 96 — see
[docs/PORTING.md](docs/PORTING.md).

**Overclocking.** NanoCraft ships no overclock code. DrUm78's separate
`Overclock.opk` gains about 20% everywhere with no loss of picture quality, at
your own risk; the setting persists until reboot, so set it once and launch.

## If something goes wrong

Logs are written to `/mnt/FunKey/nanocraft/`:

| File | What |
| --- | --- |
| `run.log` | the launcher and the game |
| `install.log` | the APK installer |

| Message | Cause |
| --- | --- |
| `NanoCraft's runtime is missing` | Step 2 did not land in the right place. |
| `No Minecraft APK found` | Step 3 — check it is really a `.apk`. |
| `no armeabi-v7a game library` | An arm64 or x86 APK. This console is 32-bit ARM. |
| `NanoCraft targets Pocket Edition 0.8.1` | Wrong version. Only 0.8.1 is supported. |
| **Menus work, but Play exits to the launcher** | **Most likely a different 0.8.1 build — see below.** |
| Black screen for a long time | First load is slow. Give it two minutes. |
| Entry missing from the menu | Restart the front end so it rescans. |

### "Play exits to the launcher"

`run.log` ending in `[opk] exit rc=139` means the game **segfaulted** (139 is
128 + signal 11), not that it quit.

**First, rule out the APK.** Ninecraft reads the game's own C++ objects at
hard-coded byte offsets validated against one specific library, so a different
build of the same version number could in principle render every menu and then
fault. The installer records what you actually gave it — check `install.log`:

```text
Game library: 9668996 bytes
sha256: baf9ca243fa301b7a9b4755ddc97aba1f0d35c9b1b80479980b47d6455a32677
```

Those are the tested values, and both 0.8.1 APKs in the widely mirrored
archive.org set match them exactly. So if your hash matches, **the APK is not
your problem** and this is not the answer.

**Then check memory.** In a world this port uses about 28 MB resident and
**37 MB swapped** — roughly 10 MB more anonymous memory than this hardware
physically has. Menus fit; a world does not.

The launcher handles this itself, and since v1.0.6 it does so **entirely in
RAM**: it loads zram, a compressed block device, and lets the kernel keep
evicted pages there under LZ4 instead of writing them to your card. Measured
compression on this game is 2.7:1, so 40 MB of evicted pages cost about 14 MB.
Every run logs what happened to `run.log`:

```text
[mem] RAM 55 MB total, 41 MB available; swap 0 MB
[mem] zram: 80 MB logical, lz4, 24 MB RAM ceiling
[mem] disabled disk swap /dev/mmcblk0p3
[mem] swap now 79 MB, RAM-backed only
```

Your SD card is switched **out** of the paging path for as long as the game is
running, and put back when you quit. Nothing is written to it, and no swap file
is created anywhere. If you are upgrading, the old 128 MB `nanocraft.swap` is
deleted on first launch and you get the space back.

If the modules will not load — a firmware update is the usual reason — the
launcher says so and **refuses to start**:

```text
[mem] could not set up RAM-only swap on kernel 4.14.14-funkey.
[mem] Entering a world needs about 65 MB of anonymous memory and this
[mem] console has 56 MB of RAM, so NanoCraft will not start without
[mem] them. Rebuilding them for your kernel is documented in
[mem] modules/README.md; it needs no firmware change.
```

There is no fallback to the SD card, deliberately: paging to flash is the
behaviour this release removed, and offering a way back into it would be
shipping it. The modules are ordinary out-of-tree kernel modules and rebuilding
them for a different kernel is documented in `opk/modules/README.md`. It needs
no firmware change.

**Please include those `[mem]` lines in any report** — they are the single most
useful thing you can send.

## Reporting a problem: the diagnostic build

If NanoCraft misbehaves — especially if the menus work and **Play exits** —
there is a diagnostic build that answers most of the questions in one go, so you
are not asked the same thing five times.

**`NanoCraftDiag_funkey-s.opk`**, on the
[releases page](https://github.com/DankMiimer/nanocraft/releases/latest).

1. Copy it into `/mnt/Native games/` beside the normal package.
2. Launch **NanoCraft Diag** from Games.
3. It records the console, probes how much memory a process can really get,
   then **starts the game normally**. Play until it crashes, or quit with a long
   press on MENU if it does not.
4. It finishes by itself and shows **REPORT SAVED** on screen.
5. **Power off, put the SD card in a PC**, and take `nanocraft-report.txt` from
   the **root** of the large data partition.

These consoles have no networking, so the SD card is the only way the file
travels. That is why the report is written to the root of the card rather than
buried next to the game — it is the first thing you see when the card mounts.
(A second copy is left at `/mnt/FunKey/nanocraft/nanocraft-report.txt` for
anyone who does have a shell.)

**It writes a file and sends nothing.** There is no network code in it — the
packaging script refuses to build it if any appears. The report contains
hardware details and this port's own state: no personal files, no credentials,
no game content. Read it before sending if you like; it is plain text.

Delete the `.opk` afterwards and it is gone.

What makes it worth running: it turns the kernel's fault reporting on before the
game starts, captures the game's memory map while it lives, and afterwards
resolves any crash address against that map. Instead of "it crashes when I press
Play" the report says which library faulted and at what offset — the difference
between guessing and knowing.

## Uninstall

Delete `/mnt/Native games/NanoCraft_funkey-s.opk`, its `.png`, and
`/mnt/FunKey/nanocraft/`. Nothing is left anywhere else: the zram modules are
loaded from the package at runtime and a reboot unloads them.

**Your worlds live in `/mnt/FunKey/nanocraft/home/`** — copy that somewhere first
if you want to keep them.
