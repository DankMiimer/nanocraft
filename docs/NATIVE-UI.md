# Native-resolution interface over a 120x120 world

September 6, 2026. Unreleased test build, based on NanoCraft
`e679c0fc2a8a4b9383b3d9f87cb64737a45f79fe`.

## Behavior

At **120x120** the world renders at 120x120, exactly as before, and the hotbar,
item icons, HUD and every menu render at the panel's real **240x240**. Nothing
else changes: the same world image, the same frame cost, an interface with four
times the pixels.

At 240x240, and at any other size, the build behaves as it always did. The
launcher enables this for 120x120 only, because no other size has anything to
gain from it. `NINECRAFT_NATIVE_UI=0` asks for the old path outright.

The launcher line in `run.log` reports it:

```text
[pe] 120x120 gui=fit ui=1 fov=70 cap=0 gallium=llvmpipe game=...
[native-ui] enabled: world=120x120 UI=240x240, framebuffer complete
[native-ui] world pass 120x120 -> 240x240; HUD/screens render next at native resolution
```

`ui=1` is what the launcher asked for. The two `[native-ui]` lines are what the
runtime actually did; if they are missing, or one of the fallback lines appears
instead, the old path is in use and the runtime is not the one that was built.

## Why this shape

The world is the expensive surface and the interface is not. A 240x240 world is
four times the fragments of a 120x120 one, and llvmpipe pays for every one of
them — that cost is exactly why 120x120 became the default. The interface is a
few dozen textured quads drawn over a finished picture, and its cost barely
depends on the resolution it is drawn at.

Rendering everything at 120 and upscaling therefore paid for coarse world pixels
and got coarse text thrown in for nothing. `NINECRAFT_GUI_SCALE=fit` fixed the
*clipping* — the hotbar had been laid out 120 logical pixels wide against a
182-pixel sprite — but 8-pixel glyphs still landed on 4 real pixels and were
doubled by the presenter.

The alternative that does not work is enlarging a finished 120x120 frame more
carefully: no filter invents the glyph that was never rasterized. The interface
has to be *drawn* at 240 by the game itself, which is what this does.

## How it works

`ninecraft/src/nano_ui.c`. The window, the engine, the pointer and every input
coordinate are 240x240 — identical to the native setting. Only
`GameRenderer::renderLevel` is redirected:

1. Before the call, bind a 120x120 framebuffer (RGBA8 colour, packed
   depth24/stencil8) and halve the current viewport and scissor.
2. Call the original `renderLevel`.
3. Blit the colour buffer to the window with `GL_NEAREST`, clear depth and
   stencil, and restore the viewport, scissor and bindings in canvas
   coordinates.

The HUD and `Screen` rendering that follow in the same frame then draw onto the
240x240 window at full resolution. No interface code is reimplemented and no
image of the interface is ever enlarged.

Three details are load-bearing:

- **Scissor and viewport halving floors the low edge and ceils the high edge**,
  including negative origins, so an odd rectangle keeps its last row rather than
  losing it, and an empty rectangle stays empty.
- **Depth and stencil are cleared after the blit.** HUD item icons are
  depth-tested and must not inherit the world's depth buffer, or the previous
  frame's UI depth.
- **The hook refuses anything unverified.** It requires version 0.8.1, the exact
  two-instruction `renderLevel` prologue, the expected distance to
  `GameRenderer::render`, and a complete framebuffer with a working blit — ARB
  or the EXT family, since the advertised context is GL 2.1 where neither is
  core. Anything missing prints one line and renders the old way. A frame where
  another mod already owns the draw framebuffer is left alone.

Cleanup marks the compositor inactive and deletes the attachments; the
trampoline page is left to the process, because a later destructor may still
call through it.

## Verification

`tests/native_ui_gl_test.c`, run by `tests/run-native-ui-gl-test.sh` through
`build/Dockerfile.native-ui-test`, exercises the production file against real
software OpenGL (llvmpipe, EGL surfaceless) — no GPU and no console:

- framebuffer completeness and extension resolution;
- odd and empty scissor rectangles, and negative origins;
- a world detail lands on exactly two native pixels, never four, while a UI
  stroke drawn afterwards stays one;
- depth, stencil, scissor state and both framebuffer bindings come back as the
  game left them, and a depth-tested UI quad is not occluded;
- three consecutive frames behave identically;
- a redirect is refused when another framebuffer is bound, and shutdown is
  clean.

```sh
./tests/run-native-ui-gl-test.sh <ninecraft-checkout> [output-directory]
```

It writes the 240x240 frame it rendered as a PPM for eyeballing. A failing
assertion fails the Docker build.

This is a host test of the compositor, not of the game. **Gameplay on the
console is still required**, and is what would show a screen this build does not
know about drawing outside the world pass.
