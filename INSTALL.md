# Installing NanoCraft

Every step here was walked through on a wiped console, from the release archive
alone. If something needs knowledge this page does not contain, that is a bug in
this page.

> **No game files are included.** You supply your own legally obtained Minecraft
> Pocket Edition 0.8.1 APK, 32-bit `armeabi-v7a`.

## Already have NanoCraft? Read this first

Most releases change only the launcher, so upgrading is one file. **v1.0.11 is
not one of those.** It changes the game runtime, which lives in the payload, so
you need step 1 **and** step 2. Replacing only the `.opk` leaves the old runtime
behind the new menu — which is the fault this release exists to fix.

Overwrite `/mnt/FunKey/nanocraft/ninecraft` along with the rest of step 2. Your
worlds, options and installed game are elsewhere and are untouched, and you can
skip step 3.

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

## Controls

The console has no second stick, so **the four face buttons are the right
stick**, and **L is the modifier** for everything else.

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

**Crafting is not bound.** In this engine jump, crouch, inventory and craft all
live on the same modifier, and `L+X` is spent on place-block. Inventory is the
more useful of the two screens on a console this size.

## Optional settings

**Resolution.** The default is 120x120, for roughly 12 fps instead of 8, at the
cost of a soft 2x-upscaled picture. Write `240 240` into
`/mnt/FunKey/nanocraft/resolution.txt` for the native, sharper image. Those are
the only two sizes that divide the panel cleanly. The quick menu's SETTINGS page
does the same thing.

**GUI scale.** `/mnt/FunKey/nanocraft/guiscale.txt` holds `fit` (the default:
size the interface to the hotbar, which shrinks it to fit at 120x120 and grows
it into the spare room at 240x240), `auto` (shrink only when it must, so
240x240 is left as older versions drew it) or a number. Also on the quick menu's
SETTINGS page.

**Field of view.** `/mnt/FunKey/nanocraft/fov.txt` holds an angle in degrees
from 50 to 100. 70 is what Minecraft ships with and is the default; choosing it
changes nothing. The game itself has no FOV setting — the launcher rewrites the
angle the renderer uses. Also on the quick menu's SETTINGS page.

**Camera and cursor speed (new test build).** Open **L + SELECT → SETTINGS**,
choose CAMERA or CURSOR, and use left/right. Both range from 10% to 200% in
10% steps and apply on resume. CAMERA defaults to 100%, retaining the existing
camera movement. CURSOR defaults to 20%, with screen-relative movement at both
resolutions. `/mnt/FunKey/nanocraft/sensitivity.txt` stores the two percentages
as `100 20`. Install the matching runtime and OPK together; an older runtime
will ignore the sliders. See [build and test notes](docs/SENSITIVITY-BUILD.md).

**Controls.** Drop your own `minecraft.key` into `/mnt/FunKey/nanocraft/` and it
overrides the packaged one. Verify any edit with `keymap save`, because
`fkgpiod`'s config parser is off by one above key code 96 — see
[docs/PORTING.md](docs/PORTING.md).

**Overclocking.** NanoCraft ships no overclock code. DrUm78's separate
`Overclock.opk` gains about 20% everywhere with no loss of picture quality, at
your own risk; the setting persists until reboot, so set it once and launch.

**The game's own icon in the front end.** Off by default. Turn it on with a
file on the card:

```sh
echo 1 > /mnt/FunKey/nanocraft/game-icon.txt
```

Next launch, the front-end artwork beside the `.opk` is replaced with the
launcher icon out of **your own installed game**, and `echo 0` (or deleting the
file) puts the shipped icon back — the original is kept at
`/mnt/FunKey/nanocraft/icon-original.png`.

It is off by default, and shipped separately from the artwork, for a reason
worth stating: that icon is Mojang's artwork and their trademark. Including it
in the download would mean this project distributing their art and using their
logo as its own identity. Copying it on your console, out of a game you own and
installed yourself, is a different act — nothing is distributed and it stays on
your card. That is the same principle as the rest of the port: you supply the
game, it is unpacked on your device.

Only front ends that read that file see it — RetroFE, the default here, does.
The icon inside the `.opk` cannot be changed on the console at all, so gmenu2x
keeps showing the shipped one.

## Things worth knowing

**No audio.** The game runs on SDL's dummy audio driver. Sound is untested.

**LAN multiplayer appears to work.** With another 0.8.1 console on the same
wifi, its world showed up in the list. Not tested beyond that, and not a feature
claim.

**A frozen picture usually means the game exited**, not that it hung — nothing
else redraws the screen afterwards.

**FORCE CLOSE is named for what it does.** It sends `SIGTERM` and then
`SIGKILL`, so anything since Minecraft's last autosave is lost. To quit with a
save, use the game's own pause menu (**L + START**) and leave the world from
there. RESTART and SHUTDOWN close the game the same way.

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

**Then check memory.** In a world this port needs about **65 MB of anonymous
memory** on a console with 56 MB of RAM. Menus fit; a world does not.

The launcher makes up the difference itself, in RAM. It loads zram — a
compressed block device the kernel can move idle pages into — and lets LZ4 hold
them at about 2.7:1, so roughly 40 MB of idle pages cost about 14 MB. **Nothing
is written to your SD card at any point.** Every run logs what happened to
`run.log`:

```text
[mem] RAM 55 MB total, 41 MB available
[mem] zram: 80 MB logical, lz4, 24 MB RAM ceiling
[mem] took /dev/mmcblk0p3 out of the paging path
[mem] compressed memory ready, 79 MB
```

That third line is NanoCraft taking your console's own disk-backed paging out of
the picture for as long as the game runs, which is the whole reason none of this
reaches your card. It is put back exactly as it was found when you quit, and a
reboot would restore it anyway.

The RG Nano's kernel has no zram of its own, so the package carries its own
modules — and a kernel module is built for one specific kernel. If yours is not
one they have been verified against, NanoCraft says so and will not start:

```text
[mem] this kernel is not one the bundled modules were built for:
[mem]     4.14.14-funkey #1 Thu Jun 18 07:57:19 CEST 2026
[mem]
[mem] EVERYTHING NEEDED TO FIX THIS HAS BEEN WRITTEN FOR YOU:
[mem]     nanocraft-kernel.txt   at the root of your SD card
[mem] Put the card in a PC and send that one file.
```

**This is stricter than the kernel's own check on purpose.** Linux compares a
short "vermagic" string that covers the version and a handful of build options
and nothing else, so two differently configured builds of the same kernel pass
it — and loading a module into the wrong one corrupts memory instead of failing
cleanly. NanoCraft therefore only loads into builds someone has actually
verified, listed in `opk/modules/kernels`.

It refuses rather than running without the memory it needs, because the failure
that would otherwise follow — every menu working and the game dying the moment
terrain loads — is a far more confusing thing to debug.

**If that happens to you, NanoCraft collects the answer itself.** It writes
`nanocraft-kernel.txt` to the root of your SD card — your kernel's identity,
version, configuration if the build exposes it, and its full symbol table. Put
the card in a PC and attach that one file to an issue. Nothing has to be typed
or fetched by hand.

That symbol table is what matters: every symbol these modules need can be
checked against your actual kernel *before* anything is loaded on your hardware,
so building you a working set is a small job. It needs no firmware change.

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
