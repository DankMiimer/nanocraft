# Sensitivity controls: build and verification

September 6, 2026. This is an unreleased test build, based on NanoCraft
`e679c0fc2a8a4b9383b3d9f87cb64737a45f79fe`.

## Behavior

Open **L + SELECT → SETTINGS**. CAMERA and CURSOR are independent sliders,
10–200% in 10% steps. Defaults are CAMERA **100%**, CURSOR **20%**.

Camera 100% preserves the existing relative input deltas. Cursor motion is
normalized against a 240-pixel baseline, so traversing a menu takes the same
time at 120x120 and 240x240. At full held-key acceleration, default cursor
motion is about 66 internal pixels/second at 120 and 132 at 240, before edge
clamping. The previous unscaled speed was about 660 pixels/second at either
resolution. Taps retain the existing acceleration curve and fractional motion
accumulates until it reaches a pixel.

The pair is saved as `100 20\n` in
`/mnt/FunKey/nanocraft/sensitivity.txt`, using a temporary file and rename.
The running input code checks it every 500 ms. A missing, invalid or incomplete
file restores the same defaults in both menu and runtime. Long pauses and
camera/menu transitions reset motion accumulation. Walking, click and hotbar
controls are unchanged. Minecraft's own `ctrl_sensitivity` is not overwritten.

The launcher enables this via `NINECRAFT_INPUT_SETTINGS`. A shared Miyoo build
without that variable retains its original movement multipliers.

## Build provenance

The test runtime was built from upstream Ninecraft
`0d952d682d1044689eebaed98cb451a975f75a7e`, with
`build/ninecraft-main.patch` and `build/overlay/`. The patch was verified
against the actual build tree with `git apply --reverse --check`.
`build/Dockerfile.mm-buster` supplied the ARMv7/Cortex-A7 build environment.
The dynamic runtime requires no GLIBC version newer than 2.28. The quick menu
is a separate statically linked ARM executable.

Test runtime SHA256:

```text
87a039fb2fc9556198d86ff00f3141b9226028f3ae9896f96cc22c6c9848cacc
```

Reproduction outline from this repository, under Linux/WSL (choose a new
build directory; the clone command intentionally refuses an existing tree):

```bash
PORT="$PWD"
WORK="$(mktemp -d /tmp/nanocraft-build.XXXXXX)"
git clone https://github.com/MCPI-Revival/Ninecraft.git "$WORK/Ninecraft"
git -C "$WORK/Ninecraft" checkout 0d952d682d1044689eebaed98cb451a975f75a7e
git -C "$WORK/Ninecraft" submodule update --init --recursive
git -C "$WORK/Ninecraft" apply "$PORT/build/ninecraft-main.patch"
cp -r "$PORT/build/overlay/." "$WORK/Ninecraft/"
cp "$PORT/build/Dockerfile.mm-buster" "$WORK/Ninecraft/"
docker build -f "$WORK/Ninecraft/Dockerfile.mm-buster" --target export \
  --output "type=local,dest=$WORK/runtime" "$WORK/Ninecraft"
python3 tools/verify-runtime.py "$WORK/runtime/ninecraft"
bash src/build-quickmenu.sh
```

Generate the assets with `opk/make-menu-bg.sh` after supplying `opk/menufont.ttf`
as described by that script. Supply/build `opk/nano-clk` using the existing
CPU-tool recipe, then run `bash opk/pack-pe-opk.sh /absolute/output.opk`.
The packer validates every sensitivity strip, menu frame, executable, module
set and launcher script. An optional output path and a unique temporary
staging directory allow test packages without replacing an existing release.

Compiler timestamps/build IDs may change binary hashes on a rebuild. For
each new build, compute its hash and require that same hash after extraction
from the final package with `tools/verify-runtime.py --sha256 HASH FILE`.

## Tests performed

```bash
SDL_INCLUDE=/path/to/Ninecraft/SDL/include \
  bash tests/run-input-tests.sh /path/to/generated-menu-assets
```

Requires native GCC and Python 3. The final event-loop test runs when the
generated assets are present; Pillow additionally saves visual captures.
OpenGL and SDL calls are stubbed only in the host input test; the ARM build
uses the real libraries.

- Production input code: camera/cursor independence, speed across 10–60 fps
  at both resolutions, low-speed taps, edge clamps, screen transitions, long
  pause, walking/click events, live reload and opt-in behavior. Passed.
- Production configuration code: defaults, atomic round-trip, out-of-range
  and malformed settings. Passed.
- Actual quick-menu event loop with synthetic evdev input and a file-backed
  framebuffer: navigation, independent sliders, min/max clamping, saving,
  Back/Resume and a fresh process reading saved values. Passed.
- Native ARM runtime and static quickmenu builds. Passed.
- Quick-settings framebuffer visually inspected: all seven rows, percentages,
  sliders and both footer lines fit within 240x240. This menu renders directly
  at panel resolution even when the game renders at 120x120.
- OPK packaging checks and runtime feature/hash guard. Passed.

The tests do not run Minecraft or verify the physical display/input driver.
An on-device gameplay check is still required.

## Paired update and expected visible changes

Update **both** files in the test package:

```text
Native games/NanoCraft_funkey-s.opk
FunKey/nanocraft/ninecraft
```

This is an update for an existing NanoCraft installation, not a full runtime
payload or APK installer. Keep backups of the two originals. It contains no
Minecraft game files and does not replace worlds, game options or user settings.

The local v1.0.10 archive contained an older executable without the already
documented FIT/FOV patches. This new runtime includes those existing patches
as well as the sensitivity controls. Consequently, FIT will begin scaling the
UI and the selected FOV will begin affecting the world view. A camera value
of 100% preserves input movement, but a newly active FOV setting can change
the apparent camera feel. See the [UI analysis](UI-120-PLAN.md).

For a controlled old-layout comparison, select STOCK and FOV 70 before a fresh
launch; restore FIT afterwards. Do not interpret this comparison setting as
the intended final UI. New menu layouts and chat-icon removal remain planned.

On device: confirm an `[input] camera=100% cursor=20%` line and GUI/FOV patch
messages in `run.log`; open inventory and test precise cursor selection;
adjust CURSOR alone, resume, then adjust CAMERA alone. Reopen Quick Settings
after a game relaunch to verify persistence. Test 120 and 240 separately.
The outstanding tester kernel issue has not been changed by this update.
