# Pocket Edition 0.8.1 on the RG Nano — session handoff

Written 2026-09-01. Read [PE081-NANO.md](PORTING.md) first for the port
itself; this is the working state, the open bugs and the traps that cost time.

**No Minecraft files are in this repository and none ever will be.** The game
comes from the owner's own APK.

---

## Status in one paragraph

**Shipped.** MCPE 0.8.1 runs in a world on the RG Nano at **7.8 fps, native
240x240**, released as **NanoCraft v1.0.0** —
https://github.com/DankMiimer/nanocraft. Controls are owner-verified, the
in-game quick menu works on **L+SELECT**, and the release was installed onto a
wiped console from its own archive and verified file-by-file against what is on
the device. Bedrock on this console is **parked**; see below.

## Device access

| | |
| --- | --- |
| RG Nano | `<device-ip>`, root, key `~/.ssh/<your-key>` (no passphrase) |
| Miyoo Mini Plus | `<device-ip>`, passwordless telnet, `tools/mm.ps1` |
| MM+ file pull | `httpd -p 8081 -h /mnt/SDCARD` on the MM+, then `curl` |

Nano transfers are plain `cat` over ssh — its dropbear has no working sftp/scp:

```bash
gzip -c file | ssh root@<device-ip> 'gunzip > /path'
tar cz -C dir . | ssh root@<device-ip> 'cd /dest && gunzip | tar x'
```

Its busybox `tar` has **no `-z`**, hence the separate `gunzip`.

## Layout

```text
/mnt/FunKey/nanocraft/          writable: game, saves, logs, trigger script
  ninecraft  runtime/ gl/ mesa/ egl-wrap/ lib/   the port (see PE081-NANO.md)
  game081/                        the owner's extracted APK - NEVER redistribute
  home/  home.snap/               saves; home.snap is a restore point for A/B runs
  minecraft.key                   OPTIONAL live override of the packaged keymap
  pemenu.sh                       quick-menu trigger, run by fkgpiod
  run.log  play.log  power-probe.log
/mnt/Native games/NanoCraft_funkey-s.opk   the package (+ .png beside it)

nano/opk-pe/                      OPK sources; pack-pe-opk.sh builds it
nano/release/                     the published archive + build-archive.sh
nano/nanocraft/                   the public repo tree (build-nanocraft-repo.sh)
nano/src/                         same scripts, plus the remote-driving rig
nano/pe081/                       scratch: session logs, screenshots, replays
```

## Build and deploy loop

```bash
wsl -e bash "<repo>/opk/pack-pe-opk.sh"      # build (needs WSL)
cat NanoCraft_funkey-s.opk | ssh root@<device-ip> \
    'cat > "/mnt/Native games/NanoCraft_funkey-s.opk"'
ssh root@<device-ip> 'pkill gmenu2x'                    # supervisor rescans
```

**NEVER overwrite the OPK while it is mounted.** Check first — the frontend
loop-mounts the running package at `/opk`:

```bash
ssh root@<device-ip> 'mount | grep -q "on /opk type squashfs" && echo PLAYING'
```

Keymap-only changes need no rebuild: write `/mnt/FunKey/nanocraft/minecraft.key`
and `keymap load` it. `run.sh` prefers that file over the packaged copy.

## Open bugs

### 1. FIXED 2026-09-01 — `wait` returns after a trapped signal

**Symptom:** the quick menu worked exactly once per launch. After pressing
*resume* the owner was driving the front end while the game carried on
rendering underneath, and the power button never worked again.

**Root cause:** `wait` returns as soon as a trapped signal has been handled —
it does not resume. So the first menu trap fell straight through to `run.sh`'s
exit path. `opkrun` then saw the OPK's `Exec` finish and brought the front end
back, while the game kept running orphaned. The registered PID for the power
signal was now dead, so nothing could raise the menu again, and `keymap default`
had already been restored — hence "I control the frontend in the background".

**Fix** (in `opk-pe/run.sh`):

```sh
RC=0
while kill -0 "$GAME" 2>/dev/null; do
  wait "$GAME"
  RC=$?
done
```

The earlier guess — that `SIGTERM` was being ignored on *close game* — was
wrong, but the hardening is worth keeping and shipped anyway: `stop_game()`
sends `SIGTERM`, waits up to 3 s, then `SIGKILL`s, because a "close game" that
leaves the game running is worse than not offering one.

**Lesson worth carrying:** any `wait` in a script that also traps signals must
be written as a loop. This one cost several rounds of misdiagnosis, including a
confident and wrong claim that the power button was unreachable.

### 2. Unverified

- `FN` alone (hotbar previous) has never been exercised.
- Crafting (`R2+X`) is unreachable by design — `L+X` is place-block.
- The quick menu is confirmed opening on `L+FN` and rendering correctly, but
  **resume has not yet been retested since the `wait` fix**. That is the first
  thing to check.

## The power button — corrected

An earlier conclusion in this session that "Linux never sees the power button"
was **wrong**, and the correction matters:

- It is true that a press produces **no evdev event** (`powerwatch.py` logged
  none), that `MAP POWER` is silently dropped by `fkgpiod`, and that
  `axp20x-pek` is not loaded.
- But the owner saw the menu appear on a real press, so the **SIGUSR1 path does
  work**: `fkgpiod` → `powerdown schedule 0.1` → SIGUSR1 to the PID `opkrun`
  registered via `pid record` (the OPK's `run.sh`) → 100 ms later the console
  powers off unless something `pkill`s the pending `powerdown schedule`.

So the power button is usable, and `powerwatch.py` — written to cover the
evdev-code hypothesis — is redundant. Leave it or remove it, but do not treat
its silence as evidence the button is unreachable.

**Long-hold power-off is the AXP209 PMIC in hardware** and is unaffected by any
of this. The owner wants that behaviour kept.

## Traps that cost real time

**`fkgpiod`'s config parser is off by one above key code 96.** `KEY_UP` stores
`KEY_HOME`. Name each affected key one code higher — `KEY_PAGEUP` for `KEY_UP`,
`KEY_KPSLASH` for `KEY_RIGHTCTRL`. Its *save* path is correct, so
`keymap save /tmp/v.key && cat /tmp/v.key` is the check. Do it after every edit.

**`fkgpiod` does not defer a mapped button's own key while waiting for a combo.**
It fires immediately, so a modifier's own key must be harmless in game. `L` is
mapped to `KEY_BACKSPACE` on purpose: that code *is* the R2 modifier and does
nothing alone.

**Undefined pairs pass both codes through; defined combos consume the second
key.** That is the whole basis of the control scheme — `L+A`/`L+B`/`L+Y` are
undefined so the binary resolves them into jump/crouch/inventory, while `L+X`
and `L+START` are defined and therefore suppress the face button.

**Jump, crouch, inventory and craft are not bindable individually.** They exist
only as R2-held + face-button chords inside `miyoo_input.c`. Whichever button
carries `KEY_BACKSPACE` becomes the modifier for all four.

**The `.desktop` suffix is `.funkey-s`, not `.anbernic`.** `nano/opk/pack-opk.sh`
asserts otherwise on the strength of `rg_nano_dev_reference.md` §3 and was never
run. Every working package on the device uses `funkey-s`.

**Stage OPK contents in the Linux filesystem, not on `/mnt/c`.** drvfs drops the
executable bit and a non-`+x` `run.sh` makes GMenu2X do nothing — indistinguishable
from a segfault. Strip CRLF too; busybox `ash` treats a stray `\r` as a syntax error.

**`pkill -f <pattern>` matches the shell running your own command.** This wasted
several cycles: `pkill -f keydump.py` killed the ssh command issuing it, and a
`pgrep -f powerdown` watcher logged only itself. Use a bracket (`powerdow[n]`).

**Do not pipe a long-running remote listener through `tail`/`grep`** — it buffers
until the pipeline ends, so nothing is visible while it runs. Redirect to a file
and poll the file.

**A blocking `os.read()` cannot honour a deadline.** The first `keydump.py` hung
forever whenever nobody pressed anything, which looked like "the device emits no
events". Use `select()`.

**Never run the game over SSH while the owner is using the device**, and expect
`/dev/input/event0` reads to see nothing while a grab is held.

## Remote-driving rig (works, worth keeping)

`miyoo_input` honours `MIYOO_INPUT_DEVICE`, so pointing it at a FIFO plus
`MIYOO_NO_GRAB=1` lets synthetic 16-byte `struct input_event` records drive the
game over SSH with no hardware:

```bash
ssh root@<device-ip> 'W=240 H=240 sh /mnt/FunKey/nanocraft/pe-start.sh'
printf "tap r1 300\nsleep 3000\n" | ssh ... 'python3 pe-inject.py /tmp/pe.fifo'
ssh root@<device-ip> 'head -c 115200 /dev/fb0' > shot.raw
ffmpeg -f rawvideo -pix_fmt rgb565le -video_size 240x240 -i shot.raw shot.png
```

Menu aiming this way is painful: `MIN_PRESS_MS` floors every press at 120 ms so
the cursor moves in ~25-30 px steps. **Edge clamping is the reliable primitive**
— holding a direction ~2.5 s parks the cursor at an exact screen edge. Menu
navigation is frame-rate dependent and therefore **does not replay across
resolutions**; replay in-world segments only.

`run.log` lines `physical code=N down at=T` are a complete session recording;
`mkreplay.py` turns them back into an injectable script. `session1.log` and
`session-bench.rep` in `nano/pe081/` are a real 14-minute session and the
112-second window used for the A/B above.

## Bedrock on this console is parked

`README.md`, `DELTAS.md` and `PORT-PLAN.md` in this directory describe the
**Bedrock** effort, which is **not being pursued** as of 2026-09-01. It reached
a world at 2.2 fps and crashed after ~75 s, and its own profiling explains why:
86% of every frame is the game's CPU work on one core, which no renderer or
resolution change reaches.

Treat those three files as **reference, not a to-do list**. They are still the
best account of the glibc-loader route, the RGB565 presenter and the llvmpipe
finding — all of which are what made Pocket Edition work. `nano-swap.sh`,
`inject_nano_input.py` and the `out-client-*` trees belong to that effort.

The console also still carries ~1.1 GB of Bedrock payload at
`/mnt/FunKey/minecraftnano/` (a 512 MB swap file, a 202 MB extracted game and
307 MB of version downloads). NanoCraft does not use any of it.

## Suggested next steps

1. **Re-test the quick menu end to end** — open with `L+FN`, resume, then open it
   again. Before the `wait` fix it only ever worked once per launch.
2. Confirm `FN` (hotbar previous), and ask whether the owner wants crafting back
   (moving place-block to `L+R` frees `L+X`).
3. Overclock: `src/nano-clk.c` decodes `PLL_CPUX` and confirms 1008 MHz stock.
   Every cost here is CPU cost, so ~1200 MHz is ~19% on everything including the
   flat ~45 ms of game logic. **The setter is unwritten and a wrong PLL value
   hangs the console until a power cycle — ask before touching it.**
4. Audio is still SDL dummy and untested.
5. LAN multiplayer appears to work by accident — the Nano's world list showed the
   MM+ broadcasting. Means RakNet is alive and the Bedrock port's IPv4-only shim
   is not needed for 0.8.1.
