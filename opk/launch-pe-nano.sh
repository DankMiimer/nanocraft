#!/bin/sh
# launch-pe-nano.sh - run Minecraft Pocket Edition 0.8.1 on the Anbernic RG Nano
# through Ninecraft, the MM+ port's software-GL stack and the RGB565 framebuffer
# presenter.
#
# This is the Pocket Edition sibling of launch-mcpe-nano.sh. It is a much
# smaller job than Bedrock: `ninecraft` links only libdl/libm/libpthread/libc
# and statically carries SDL, so the whole port surface is the bundled glibc,
# the GL bundle and the presenter.
#
# ROUTE B WITHOUT PATCHELF. The MM+ binary is ARMv7 armhf glibc 2.28 and this
# device is musl, so it cannot start on its own: /lib/ld-linux-armhf.so.3 does
# not exist here. launch-mcpe-nano.sh solves that by rewriting PT_INTERP to a
# bundled loader. This does the same thing the other way round, by INVOKING the
# bundled loader explicitly and passing the binary to it. Same result, and it
# survives the directory being moved or renamed, which a baked PT_INTERP does
# not.
#
#   ./launch-pe-nano.sh [extracted-apk-dir]
set -u

D="${MCPE_DATA:-/mnt/FunKey/nanocraft}"
GAME="${1:-$D/game081}"
LOADER="$D/runtime/ld-linux-armhf.so.3"
LOG="${MCPE_LOG:-$D/run.log}"

W="${NINECRAFT_WIDTH:-120}"
H="${NINECRAFT_HEIGHT:-120}"

if [ ! -f "$GAME/lib/armeabi-v7a/libminecraftpe.so" ]; then
  echo "no game at $GAME (needs lib/armeabi-v7a/libminecraftpe.so + assets/)"
  exit 1
fi
if [ ! -x "$LOADER" ]; then
  echo "no bundled glibc loader at $LOADER"
  exit 1
fi

mkdir -p "$D/home"

# --- memory ------------------------------------------------------------------
# 55 MB of RAM. 0.11.0 plateaued at ~63 MB RSS on the MM+, so this game does not
# fit in RAM alone and the paging levers are load-bearing, not tuning.
if [ "${MCPE_FREERAM:-1}" = 1 ]; then
  echo 100 > /proc/sys/vm/swappiness       2>/dev/null
  echo 1   > /proc/sys/vm/overcommit_memory 2>/dev/null
  echo 262144 > /proc/sys/vm/max_map_count  2>/dev/null
  echo 3   > /proc/sys/vm/drop_caches       2>/dev/null
fi

# --- library path ------------------------------------------------------------
# egl-wrap FIRST: its libEGL.so.1 is the framebuffer presenter and must win over
# Mesa's real one, which it loads itself as librealEGL.so.
LP="$D/egl-wrap:$D/gl:$D/lib:$D/mesa:$D/runtime"
export LD_LIBRARY_PATH="$LP"

export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER="${MCPE_GALLIUM:-llvmpipe}"
export LP_NUM_THREADS="${LP_NUM_THREADS:-1}"
export LIBGL_DRIVERS_PATH="$D/mesa/dri"
export MESA_LOADER_DRIVER_OVERRIDE=swrast
export MESA_GL_VERSION_OVERRIDE=2.1

export SDL_VIDEO_DRIVER=offscreen
export SDL_VIDEODRIVER=offscreen
export EGL_PLATFORM=surfaceless
export SDL_AUDIO_DRIVER=dummy
export SDL_AUDIODRIVER=dummy

export FBNANO_ROT="${FBNANO_ROT:-0}"
export FBPRESENT_QUIET="${FBPRESENT_QUIET:-1}"
export FBEGL_PBO="${FBEGL_PBO:-1}"
export NINECRAFT_WIDTH="$W"
export NINECRAFT_HEIGHT="$H"

# Interface scale. Ninecraft lays the GUI out at a scale it derives from the
# window and floors at 1.0; that floor leaves a 120x120 screen 62 pixels too
# narrow for the 182-pixel hotbar, which is why 120x120 used to clip. This
# launcher takes the scale from here and will go below the floor when asked.
# "fit" sizes the interface to the hotbar in whichever direction it has to go,
# so it fits at 120x120 and fills the spare room at 240x240.
export NINECRAFT_GUI_SCALE="${NINECRAFT_GUI_SCALE:-fit}"

# Field of view. 0.8.1 has no such setting -- the launcher rewrites the base
# angle inside GameRenderer::getFov, which is where the projection actually
# comes from. 70 is what the game ships with, and asking for 70 patches nothing
# at all, so this default leaves an untouched console byte-for-byte stock.
export NINECRAFT_FOV="${NINECRAFT_FOV:-70}"

echo "[pe] ${W}x${H} gui=$NINECRAFT_GUI_SCALE fov=$NINECRAFT_FOV gallium=$GALLIUM_DRIVER game=$GAME" | tee -a "$LOG"

exec "$LOADER" --library-path "$LP" \
  "$D/ninecraft" --game "$GAME" --home "$D/home"
