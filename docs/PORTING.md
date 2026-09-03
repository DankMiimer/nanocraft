# Pocket Edition 0.8.1 on the RG Nano

**Status: runs, in a world, on hardware.** 2026-09-01.

This is the result `nano/README.md` and `nano/DELTAS.md` were written in
anticipation of, but it arrived by a different and much cheaper route than
either predicted. Bedrock 1.2 on this device manages 2.2 fps and crashes after
75 seconds. Pocket Edition 0.8.1 runs **at native 240x240 resolution, at 7.8 fps
under a real recorded play session**, and stays up.

No Minecraft files are in this repository. The game comes from the owner's own
APK.

---

## The route: nothing was rebuilt

`DELTAS.md` opens with "Every binary in the MM+ port is unusable on the Nano."
For the Bedrock client that was the right call to plan around. For Ninecraft it
is wrong, and the reason is worth stating plainly because it inverts the whole
cost estimate:

```text
$ readelf -d ninecraft | grep NEEDED
  libdl.so.2   libm.so.6   libpthread.so.0   libc.so.6
```

That is the entire dependency list. SDL is statically linked (the MM+ build sets
`SDL_OFFSCREEN=ON` and links it in) and everything graphical is `dlopen`ed at
runtime. So the only thing standing between the MM+ binary and this device was
the missing ELF interpreter `/lib/ld-linux-armhf.so.3`.

**Route B without patchelf.** `launch-mcpe-nano.sh` solves the interpreter
problem for the Bedrock client by rewriting `PT_INTERP` to a bundled loader.
This port does the same thing from the other end — it *invokes* the bundled
loader and hands it the binary:

```sh
runtime/ld-linux-armhf.so.3 --library-path "$LP" ./ninecraft --game ... --home ...
```

Same result, and strictly better in one respect: `PT_INTERP` is an absolute path
that cannot use `$ORIGIN`, so a patched binary breaks with
"No such file or directory" the moment its directory is renamed. This does not.

## Two corrections to DELTAS.md

**1. llvmpipe is available, and it is not optional.** DELTAS §2 argues the Nano
build "starts on softpipe" because there is no LLVM for arm-musl. That reasoning
holds for a musl build and dissolves entirely for a glibc one — the MM+'s
llvmpipe Mesa bundle runs here unmodified. Measured on the title screen at
120x120:

| driver | frame | fps |
| --- | ---: | ---: |
| llvmpipe | 38.3 ms | **26.1** |
| softpipe | 140.9 ms | 7.1 |

**3.7x.** Starting on softpipe would have produced a slideshow and made the
project look impossible.

**2. The RAM wall is not where it was expected.** DELTAS §8 calls memory "the
delta that decides the project" and `tools/nano-swap.sh` exists to add a
loopback swap file. Pocket Edition needs none of it: in-world RSS is **40 MB
with 28 MB swapped**, against the 128 MB stock swap partition. The 512 MB
`swap.img` left over from the Bedrock work is unused.

## Measured

llvmpipe, stock 1008 MHz, `FBEGL_PBO=1`.

Title screen:

| internal | frame | fps |
| ---: | ---: | ---: |
| 240x240 (native) | 86.5 ms | 11.6 |
| 120x120 | 38.3 ms | 26.1 |
| 80x80 | 28.0 ms | 35.8 |

**In-world, same world, same replayed input** (see *Recording and replay*
below) — this is the honest number:

| internal | app+submit | rasterize | blit | frame | fps |
| ---: | ---: | ---: | ---: | ---: | ---: |
| **240x240 (native)** | 48.7 | 77.6 | 1.1 | 127.5 ms | **7.8** |
| 120x120 (2x upscale) | ~44 | ~37 | 1.1 | 83.9 ms | 11.9 |

### Why 120x120 is the default, and why 240x240 was until v1.0.5

Quartering the pixel count buys **+52%**, not the 4x a fill-rate-bound workload
would give, because **`app+submit` is flat at ~45-49 ms** — that is Minecraft's
own logic and chunk work on one A7, and no resolution setting touches it. It is
38% of a 240x240 frame and 53% of a 120x120 one.

Against that, 120x120 costs a soft 2x-upscaled picture. It used to cost a
clipped HUD as well; that is fixed, and the fix is worth recording because the
cause was not where it looked.

**The clipping was never a Minecraft setting.** Ninecraft installs the interface
scale itself, in `set_ninecraft_size()`, from

```c
clamp(round(dpi/96*1.2 + (w/1920 + h/1080)*0.8), 1, 4)
```

with `dpi` stuck at 96 because SDL's offscreen driver reports none. Both 240x240
(1.478) and 120x120 (1.339) round to **1.0, the clamp floor**, so the interface
was laid out 120 logical pixels wide while Minecraft's hotbar sprite is 182x22 —
measured at (0,0) of this build's `gui.png`, where the opaque run ends at x=181
and the 24x24 selection box begins on the next row. 62 pixels short, both ends
off the screen.

No option in `options.txt` could reach it, and the one that looks like it could
is a trap: `gfx_pixeldensity` is labelled **"D-Pad size"** by the game
(`options.guiScale=D-pad size`, `options.pixelspermilimeter=D-Pad size`), it is
the touch d-pad's size in pixels per millimetre, and
`AppPlatform_linux$getPixelsPerMillimeter()` recomputes it as `(w + h) * 0.5 /
25.4` on every launch. Two exact matches confirm it: this console stores
`9.44882` = 240/25.4, and the MM+ options.txt seeded into it stored `7.16535` =
182/25.4, 182 being the mean of that port's 208x156 window.

So the launcher patch adds `NINECRAFT_GUI_SCALE`, which lets the scale go below
the floor. At 120x120 `auto` gives 0.6522 and a 184-pixel logical screen — the
hotbar fits with the two pixels of slack the constant leaves for the truncation
in `Screen::setSize(width / scale, ...)`. At 240x240 the fit scale is 1.304, so
`auto` returns before touching anything and that mode is byte-for-byte what it
was. The MM+ port documented the same failure mode at 160x120, where Settings
and Store fell off entirely; the same lever would fix it there.

So the trade is now just a soft 2x-upscaled picture for 4 fps, and at 8 fps four
frames is worth more than sharpness. **120x120 became the default in v1.0.5**;
240x240 stays one row away in the quick menu for anyone who would rather have
the native image.

The present path is not worth optimising: the RGB565 blit is **1.1 ms**, under
1% of a frame. `fb_nano.h`'s prediction that it would be cheap is confirmed, and
the async PBO path makes no measurable difference on one core (26.35 fps without
it, 26.08 with) — it exists to overlap the game thread with the rasterizer, and
there is nothing to overlap with here.

## What is left to optimise (2026-09-01)

**The graphics settings are already at their floor.** The `options.txt` inherited
from the MM+ carries `gfx_lowquality:true`, `gfx_fancygraphics:0`,
`gfx_fancyskies:0`, `gfx_animatetextures:0` and `gfx_renderdistance:3` — Tiny,
the minimum. The MM+'s own A/B research measured Low Quality at **+189%**, so
the single largest lever was already pulled before the first Nano run.

### Measured dead ends — do not spend time here again

| lever | result |
| --- | --- |
| `LP_NUM_THREADS` 0 / 1 / 2 | **no difference** (84.7 / 85.1 / 85.8 ms warm) |
| `FBEGL_PBO` | no difference on one core — nothing to overlap with |
| softpipe | 3.7x slower than llvmpipe |
| `LP_NATIVE_VECTOR_WIDTH=128` | no change (MM+ measured; already NEON width) |

**Methodology trap:** the first cell of any sweep on this device pays a cold page
cache and cold swap and reads ~2x slow. A first run of `LP_NUM_THREADS=1`
measured 173.7 ms and looked like a catastrophic finding; re-run warm it was
84.7 ms, identical to the others. **Always repeat the first variant last.**

### The resolution model, and the ceiling it implies

Fitted from the two measured in-world points and cross-checked against three
title-screen points (predicts 80x80 within 4.6%):

```text
frame_ms  ~=  70.6  +  0.00094 x pixels
              ^^^^     ^^^^^^^ rasterizer, scales with resolution
              fixed: ~46 ms game logic + ~23 ms raster overhead
```

| internal | upscale | predicted | measured |
| ---: | --- | ---: | ---: |
| 240x240 | 1x, clean | 8.0 fps | **7.84** |
| 200x200 | 1.2x | 9.2 fps | — |
| 176x176 | 1.36x | 10.0 fps | — |
| 160x160 | 1.5x | 10.6 fps | — |
| 120x120 | 2x, clean | 11.9 fps | **11.92** |

**The ~70 ms fixed term is the story.** Even at a 1x1 render the frame could not
drop below it, so **resolution alone tops out near 14 fps** and everything
between 240 and 120 buys a few frames for a non-integer upscale. Only 240x240
(1x) and 120x120 (2x) divide the panel cleanly; the intermediates shimmer.

### The one lever that attacks the floor

**Overclocking**, because that 70 ms is all CPU. Stock is confirmed 1008 MHz
(`nano-clk`: `PLL_CPUX = 0x90001431`, N=20 K=3 M=1 P=0). Scaling the whole frame
by the clock ratio:

| clock | 240x240 | 120x120 |
| --- | ---: | ---: |
| 1008 MHz (stock) | 7.8 fps | 11.9 fps |
| 1200 MHz | ~9.4 fps | ~14.2 fps |
| 1300 MHz | ~10.1 fps | ~15.4 fps |

It costs **no picture quality at all**, which no other remaining lever can say.

**Use DrUm78's `Overclock.opk`, not a setter of our own.** Inspecting it
(`Overclock.elf`, unstripped): it `mmap`s `/dev/mem`, offers a `- %d Mhz +`
slider and reports `new clock %dMHz`, defaulting to 1008. It is the community's
supported tool for this console, it writes the same PLL register `nano-clk.c`
decodes, and the setting persists until reboot — so it can be set once and then
the game launched. `src/nano-clk.c` remains read-only on purpose: a wrong PLL
value hangs the console until a power cycle, and that is not a risk to take
inside a game launcher.

## Controls: remap the device, not the binary

The binary reads `/dev/input/event0` and expects the **Miyoo Mini's** evdev
codes, hard-coded as an enum in `miyoo_input.c`. Rather than rebuild it, this
port remaps at the source. `fkgpiod` is the daemon that turns GPIO into the
uinput keyboard, and `/usr/local/sbin/keymap load <file>` retargets it live, at
zero runtime cost. `src/minecraft.key` is that file; `src/play.sh` loads it and
restores `keymap default` on exit through a trap *and* a watchdog, because a
console left holding a game's mapping with no front end is the failure worth
engineering against.

| Nano | emits | Ninecraft function |
| --- | --- | --- |
| D-pad | arrows | move / move cursor |
| X / B / Y / A | LSHIFT / LCTRL / LALT / SPACE | look up / down / left / right |
| R | `KEY_T` | attack, break, **click** in menus |
| **L** (held) | BACKSPACE | modifier — see below |
| **L+X** | `KEY_E` | place block |
| **L+Y** | (passes through) | open inventory |
| **L+A** | (passes through) | jump |
| **L+B** | (passes through) | crouch |
| **L+START** | TAB | start menu |
| START | ENTER | hotbar next |
| FN | RIGHTCTRL | hotbar previous |
| MENU (hold 2 s) | ESC | quit |
| power (short) | — | quick menu |

**`L` is the R2 modifier**, and that is not a naming choice: jump, crouch,
inventory and craft are not independent bindings in this binary. They exist only
as `R2`-held + face-button chords decoded inside `miyoo_input.c`, so whichever
button carries `KEY_BACKSPACE` becomes the modifier for all four. `L+X` and
`L+START` are defined combos and therefore suppress the face button's own key;
`L+A`, `L+B` and `L+Y` are *not* defined, so both codes pass through and the
binary resolves them into jump, crouch and inventory.

Crafting (`R2+X`) is the one casualty, since `L+X` is claimed by place-block.
Owner-verified on hardware, 2026-09-01: everything in the table above works.

### fkgpiod does not defer the base key — which decides what a modifier may be

Any button can be a modifier: `L+X` and `L+START` work, not just `FN+` combos.
But `fkgpiod` emits a mapped button's own key **immediately on press** rather
than holding it back to see whether a combo follows. An earlier layout mapped
`L` to `KEY_E` (place block) *and* defined `L+START`, and a real press produced:

```text
code=18 down     <- L, place block, fired straight away
code=15 down     <- START completes the combo, start menu
code=18 up       <- base key released as the combo fires
```

so opening the start menu also placed a block.

**The rule that follows: a modifier's own key must be harmless in game.** The
first fix was to leave `L` unmapped entirely, which works — combos still fire
without a base mapping. The final layout does the opposite and maps `L` to
`KEY_BACKSPACE` on purpose, because that code *is* the R2 modifier and does
nothing by itself, so firing it early costs nothing and is in fact required for
the jump/crouch/inventory chords to resolve.

Two corollaries worth keeping:

- An **undefined** pair passes both codes through — that is what makes `L+A`,
  `L+B` and `L+Y` work at all.
- A **defined** combo consumes the second button's key, which is how `L+X`
  places a block instead of looking up.

### The trap: fkgpiod's parser is off by one

Its config **parser** has an off-by-one in its key-name table for codes >= 96.
`KEY_UP` (103) stores `KEY_HOME` (102); `KEY_RIGHTCTRL` (97) stores
`KEY_KPENTER` (96). Names below ~96 are fine, and the stock
`/etc/fkgpiod.conf` only uses `KEY_A`-`KEY_Z`, so the OS never exercises it.

`minecraft.key` therefore **names each affected key one code higher than the one
it wants** — `KEY_PAGEUP`/`KEY_PAGEDOWN`/`KEY_RIGHT`/`KEY_END` for the arrows,
`KEY_KPSLASH` for `KEY_RIGHTCTRL`.

The **save path is correct**, which gives a clean check. After any edit:

```sh
keymap load minecraft.key && sleep 1 && keymap save /tmp/v.key && cat /tmp/v.key
```

If it reads back the true names you intended, the right codes are stored. Do
this rather than trusting the file you wrote.

## Recording and replay

`miyoo_input` logs every physical event with `SDL_GetTicks()` attached:

```text
miyoo-input: physical code=103 down at=26016
```

so **a play session is already a recording**. `src/mkreplay.py` recovers the
timing deltas into a script for `src/pe-inject.py`, which writes 16-byte
`struct input_event` records into a FIFO. `miyoo_input` honours
`MIYOO_INPUT_DEVICE`, so pointing it at that FIFO (with `MIYOO_NO_GRAB=1`,
since `EVIOCGRAB` cannot work on a pipe) makes the game driveable with no
hardware and no hands. The two in-world figures above are the same 112-second
window of one real session replayed against the same restored world snapshot.

**Menu navigation does not replay across resolutions.** The cursor moves per
game tick, so its speed is frame-rate dependent and a recorded click lands
somewhere else at a different resolution. Replay the in-world portion only, and
navigate the menus separately at each setting.

**Aiming the cursor remotely is genuinely awkward**, and the reason is
`MIN_PRESS_MS`: every press is floored to 120 ms, so the smallest possible
cursor step is ~25-30 px at 240x240. The reliable primitive is **edge clamping**
— `push_motion` clamps to the window, so holding a direction for 2.5 s puts the
cursor at an exact known coordinate. Corner-clamping is how the settings gear
gets clicked; everything else is clamp-then-nudge with a framebuffer capture
between steps.

## Packaging

`NanoCraft_funkey-s.opk` (12 KB), built by `opk-pe/pack-pe-opk.sh` under WSL,
installed to `/mnt/Native games/` with `NanoCraft_funkey-s.png` beside it for
RetroFE. It appears as **Minecraft PE** in the Games menu.

**The OPK holds the launcher only** — `run.sh`, `launch-pe-nano.sh`,
`minecraft.key`, the icon and the `.desktop`. The binaries, the GL stack, the
game and the saves stay on `/mnt/FunKey/nanocraft/`, because a squashfs mount
is read-only and because a 20 MB `libGL.so.1` decompressed out of squashfs on a
55 MB device is a cost with nothing to show for it.

**Correction to `opk/pack-opk.sh` and DELTAS §7: the suffix is `.funkey-s`, not
`.anbernic`.** That script refuses to build without `<name>.anbernic.desktop`,
citing `rg_nano_dev_reference.md` §3, and it has never been run. Every package
that actually works on this console — `PokemonEmeraldNano_funkey-s.opk`,
`WiFiGUI.opk`, `eduke32_funkey-s.opk`, `sm64_us_v1.3_funkey-s.opk` — uses
`funkey-s`, verified by `unsquashfs -l` on the installed files. The rest of that
script's rules hold and are kept: trailing newline on the `.desktop`, a PNG
matching `Icon=`, `-all-root -noappend -no-xattrs -comp gzip`.

Two further things `pack-pe-opk.sh` does that matter:

- **Stages into the Linux filesystem, not the Windows mount.** drvfs does not
  carry the executable bit, and a non-`+x` `run.sh` makes GMenu2X do nothing at
  all — indistinguishable from a segfault.
- **Strips CRLF from every script.** busybox `ash` treats a stray `\r` as a
  syntax error, which the MM+ side already learned the hard way.

`run.sh` deliberately does **not** call `frontend set none`. That writes
`/mnt/disable_frontend` on the persistent vfat partition, so any launch that
never reaches its restore — SIGKILL, crash, flat battery — leaves the console
booting with no launcher and no working buttons. GMenu2X hands the framebuffer
over by itself.

**Restoring the keymap is watchdogged, not just trapped.** A trap does not run
on SIGKILL, and a console left holding Minecraft's mapping has an unusable front
end. A detached loop watches the game process and runs `keymap default` when it
disappears. Verified: killing the game with `kill -9` still restored `A` from
`KEY_SPACE` back to stock `KEY_A`.

Verified end to end by loop-mounting the built OPK on the device and running its
`run.sh`: it mounts, `run.sh` is `+x`, the keymap loads and restores, and the
game reaches the title screen. The missing-payload path was tested separately
and writes a plain-English explanation to `run.log`.

Resolution is read from `/mnt/FunKey/nanocraft/resolution.txt` (`W H`, e.g.
`120 120`); absent or malformed, it defaults to 240x240.

Controls can be retuned without rebuilding: `run.sh` prefers
`/mnt/FunKey/nanocraft/minecraft.key` over the packaged copy if one exists.
Nothing is placed there by default, so the OPK stays authoritative — a stale
override would otherwise silently outrank a package update.

## The in-game quick menu

**On this OS the power-button menu is not an OS service — it is drawn by
whatever app is in the foreground.** `fkgpiod` answers the button with
`powerdown schedule 0.1`, which signals the registered foreground process (the
PID `opkrun` stored via `pid record` — for an OPK that is `run.sh`) and then
cuts power 100 ms later unless something cancels it, by `pkill`ing the pending
`powerdown schedule`. GMenu2X's familiar menu is simply GMenu2X catching that
signal. **A game that ignores it just gets switched off mid-session**, so the
menu has to be provided by the port or not at all.

`quickmenu.py` provides it — volume, brightness, close game, shut down, resume.
Two things had to be arranged before it was possible:

1. **The game now runs with `MIYOO_NO_GRAB=1`.** Ninecraft otherwise holds an
   exclusive `EVIOCGRAB` on `/dev/input/event0`, leaving no way for any other
   process to read the buttons. Releasing it is free here: that grab exists to
   stop a front end also seeing input, and no front end runs while an OPK owns
   the screen. The menu then takes the grab itself, so while it is up the game
   receives nothing and no stale presses queue behind it.
2. **The game is `SIGSTOP`ped while the menu is open.** It repaints `/dev/fb0`
   every frame, so anything drawn over it would survive about 130 ms. Frozen,
   the panel holds still and the menu owns the screen. `SIGCONT` on exit.

**No font engine is used.** The device has no PIL and no TTF stack reachable
from python, so every glyph is pre-rendered by `make-menu-bg.sh` into
`menubg.raw`, a flat 240x240 RGB565 buffer. On device the menu blits that and
draws only what changes — the cursor and the two value bars — as rectangles.
`pack-pe-opk.sh` refuses to ship a `menubg.raw` that is not exactly 115200
bytes, because a short read would leave the menu half-drawn over a frozen game.

Volume and brightness call `volume set N` / `brightness set N` rather than
`up`/`down`: the `up`/`down` wrappers post their own on-screen notification,
which would paint straight over the menu.

The menu resumes itself after 90 s idle so it can never wedge the console, and a
second power press while it is open only cancels that new shutdown instead of
stacking a second menu.

**Two possible triggers, both wired.** Whether a short press arrives as SIGUSR1
or as a plain `KEY_POWER` event on the input device was not settled by reading
the system — the console's observed behaviour (short press inert in game, long
hold powers off) fits the event path, while `fkgpiod`'s strings fit the signal
path. So `powerwatch.py` reads the input device for any plausible power code
(`KEY_POWER`, `KEY_SLEEP`, `KEY_WAKEUP`, `KEY_POWER2`) and raises the same
SIGUSR1 that `run.sh` already traps — one code path, both routes covered. It
also logs every unrecognised key code to `power-probe.log`, so the real
behaviour gets settled by a press rather than by theory.

**Mount USB is deliberately absent.** The OPK is loop-mounted from the storage
partition and the game reads its assets from it, so exporting the card as mass
storage mid-session would pull the filesystem out from under both. It belongs in
the front end's menu, where nothing is running off the card.

## Deployed layout

```text
/mnt/FunKey/nanocraft/
  ninecraft              MM+ build, unmodified
  runtime/               bundled Buster glibc + loader
  gl/libGL.so.1          OSMesa (SONAME libOSMesa.so.8), dlopened by SDL
  mesa/                  llvmpipe libEGL/libGLESv2/libglapi + dri/
  egl-wrap/              fbegl_nano RGB565 presenter + librealEGL.so
  lib/                   libstdc++, libz, libtinfo, libdrm, libexpat, ...
  game081/               the owner's own extracted APK  -- NEVER redistributed
  home/                  saves and settings
  minecraft.key  play.sh  launch-pe-nano.sh  pe-inject.py  mkreplay.py
```

`runtime/`, `mesa/`, `egl-wrap/` and `lib/` were copied from the already-deployed
`/mnt/FunKey/minecraftnano/client/` — the Bedrock attempt's one durable legacy.

## Open items

- **MENU+A jump chord** — unverified; needs one overlapping press on hardware.
- **FN+R (hotbar previous)** — never exercised.
- **Overclock.** `src/nano-clk.c` decodes `PLL_CPUX` and confirms 1008 MHz
  stock. Every cost here is CPU cost, so ~1200 MHz would be ~19% on everything.
  The setter is still unwritten, and a wrong PLL value hangs the device until a
  power cycle — not a change to make on someone's console without asking.
- **Audio** — still SDL dummy, untested.
- **LAN multiplayer works, apparently by accident.** With both consoles on wifi
  the Nano's world list showed the MM+ broadcasting `World on wifi
  <device-ip>`. Not pursued, but it means RakNet is alive here and the
  IPv4-only shim the Bedrock port needed is not required for 0.8.1.
