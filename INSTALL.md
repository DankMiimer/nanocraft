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

**Resolution.** Write `120 120` into `/mnt/FunKey/nanocraft/resolution.txt` for
roughly 12 fps instead of 8, at the cost of a soft 2x-upscaled picture and a
hotbar that clips at the screen edges. Delete the file to go back to native
240x240. Those are the only two sizes that divide the panel cleanly.

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

**Not every APK labelled 0.8.1 is the same build.** Ninecraft reads the game's
own C++ objects at hard-coded byte offsets, validated against one specific
library. A different build of the same version can render every menu correctly
and then fault the moment those offsets are used for real — which is the
menu-to-world transition, i.e. pressing Play.

The installer records what you actually gave it. Check `install.log`:

```text
Game library: 9668996 bytes
sha256: baf9ca243fa301b7a9b4755ddc97aba1f0d35c9b1b80479980b47d6455a32677
```

Those are the tested values. If yours differ, the installer will have said so,
and that is the first thing to report. A different build is not *guaranteed* to
fail — but it is the first thing to rule out.

## Uninstall

Delete `/mnt/Native games/NanoCraft_funkey-s.opk`, its `.png`, and
`/mnt/FunKey/nanocraft/`.

**Your worlds live in `/mnt/FunKey/nanocraft/home/`** — copy that somewhere first
if you want to keep them.
