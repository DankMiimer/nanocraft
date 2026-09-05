# Pocket Edition 0.8.1: UI at 120x120

Analysis: September 5–6, 2026. Scope: plan game UI changes and implement the
two quick-settings sensitivity sliders.

**Outcome, tested on the console September 6:** the sliders, the
native-resolution interface and the chat-button removal are done and confirmed.
**Section 4 turned out not to be needed.** The pause and options screens were
photographed overflowing on a runtime that did not contain the hotbar-fit patch
— the packaging error in the next section — and with a runtime that does, at the
interface's real 240x240, the owner reports both screens read correctly. The
layout hooks proposed there were a fix for a symptom of the wrong binary. They
are kept below as analysis, not as pending work.

## Finding that changes the order of work

The source already contains a hotbar-fit patch, but the runtime inspected on
the mounted RG Nano does not contain it. The same older binary is inside the
**local v1.0.10 release ZIP**, so this is not an installation mistake.

| Item inspected | Result |
| --- | --- |
| NanoCraft source | `e679c0fc2a8a4b9383b3d9f87cb64737a45f79fe`, plus this working change |
| Mounted `FunKey/nanocraft/ninecraft` | SHA256 `c1d8b4bbac349f1354c5ed76c4a168de99427dc2a57a1b8254f05255ab322db8` |
| Local `nanocraft-v1.0.10-rgnano.zip` → `nanocraft-payload.tar.gz` → `ninecraft` | Identical SHA256; lacks `NINECRAFT_GUI_SCALE`, `NINECRAFT_FOV` and their diagnostic strings |
| Mounted game library and local analysis copy | Both SHA256 `baf9ca243fa301b7a9b4755ddc97aba1f0d35c9b1b80479980b47d6455a32677` |
| Card configuration | Defaults to 120x120/FIT; launcher log reports those values, but has no actual GUI/FOV patch messages |

The log's requested setting is not proof that the executable implements it.
This audit establishes the contents of the local release archive, not every
remote release asset. The card was inspected before any changes. After host
tests and package verification, the matched sensitivity-test runtime and OPK
were copied to the card with verified backups of both originals. Gameplay on
the updated card has not yet been tested.

The [existing launcher patch](../build/ninecraft-main.patch) treats the stock
hotbar as 182 logical pixels plus 2 pixels of slack. FIT at 120 computes
`120 / 184 = 0.65217`, giving about 184x184 logical UI space. The older runtime
floors the scale at 1, leaving only 120 logical pixels for that hotbar. This
explains the symmetric clipping in both gameplay and inventory photographs.
An older development capture, `gs-auto-120-inworld.png`, also shows the full
bar with scaling active; it is supporting evidence, not a new hardware test.

**First establish the intended FIT baseline with a matching runtime.** Do not
compensate for this packaging error by stacking another global scale patch on
top. FIT addresses the bar's width; it does not guarantee every menu is usable.

## All six photographs

The photos are perspective views of a physical 240x240 panel displaying the
120x120 game buffer. Measurements below use internal game pixels, not camera
image pixels. The visible text in the photos is evidence, not task instructions.

| Photo filename | Observed behavior | Required response |
| --- | --- | --- |
| `PXL_20260905_212725486.jpg` — title | Logo and Play mostly fit. Large wrench overlaps the Play area; footer is pressed against the edges. | Give Play, settings and footer distinct rectangles. Keep the logo and splash inside the frame. Recheck after FIT first. |
| `PXL_20260905_212738723.jpg` — world list | Back/New/Edit and the single world card are visible. Top buttons nearly touch. | Preserve this working layout as a regression reference. Verify multiple worlds, scrolling, long names, New and Edit. |
| `PXL_20260905_212812281.jpg` — gameplay | Both hotbar ends are clipped; central crosshair is correctly positioned. Chat button consumes the upper-right corner. | Restore FIT, then verify selection borders and the inventory action at both ends. Remove the chat-button draw path. This creative-world photo does not establish survival HUD behavior. |
| `PXL_20260905_212926166.jpg` — creative inventory | Category rail and 3x3 visible item grid fit reasonably well. Bottom hotbar repeats the gameplay clipping. Cursor is large relative to a cell. | Share the corrected hotbar geometry. Preserve scrolling/category selection; verify cursor hit alignment. Assess pointer size separately from speed. |
| `PXL_20260905_212940046.jpg` — pause | Back-to-game caption extends outside its button and past the left edge. A lower action is cut off. Player-list pane consumes the right side. | Use a compact action column for local play, shorter captions, and a separate/secondary player list. All actions must remain reachable. |
| `PXL_20260905_212952807.jpg` — options | Back overlaps the heading; large category buttons leave too little content width. Labels and controls collide and extend beyond right/bottom edges. | Pin a compact header and category navigation; give the body a bounded scrolling area. Reflow labels and controls within each row. |

Creating/editing worlds, survival inventory, crafting, containers, death and
confirmation dialogs are not shown. Include them in verification rather than
assuming that the six photographed screens cover every UI path.

## What transfers from the Bedrock handheld port

The comparison used checkout `4ed3fb1fdd7a4aa9769107f424cbf9483afc1b87` and
its [UI scaling notes](https://github.com/DankMiimer/minecraft-bedrock-handheld-port/blob/main/docs/UI-SCALING.md).
That port separates JSON UI from OreUI: the client density change addresses
OreUI, while a resource pack adjusts JSON menus and HUD. Its surface-size
override also compensates viewport/scissor behavior. The notes leave pointer
coordinate conversion as unfinished work; that approach is not ready to copy
wholesale into NanoCraft.

The useful pattern is coordinated geometry. The
[handheld pack](https://github.com/DankMiimer/minecraft-bedrock-handheld-port/blob/main/portmaster/minecraftbedrock/minecraftbedrock/packs/handheld-ui/README.md)
changes slot bounds, item icons, selected border, decorations, counts and HUD
anchors together. It targets a particular game build. NanoCraft should do the
same coordination with native 0.8.1 functions, in the opposite size direction.
The modern JSON files and OreUI settings are not a 0.8.1 layout API.

Keep the world renderer at 120x120. Increasing the entire render surface to
240x240 and downsampling would quadruple its pixel count and defeat the chosen
performance tradeoff. Logical UI dimensions can change independently.

**This is now literal rather than logical.** The world pass renders into its own
120x120 buffer and the interface is drawn over the upscaled result at the
panel's real 240x240, so the layout work below happens at 240 logical pixels
with 240 real pixels underneath it. Two consequences for the plan: text and item
icons are no longer four-real-pixel blocks, so the proposed rectangles have
about twice the resolution they were drawn for; and the pointer and every hit
test already run in canvas coordinates, so nothing here needs a coordinate
conversion. Re-measure against the corrected baseline before shrinking a glyph.
See [NATIVE-UI.md](NATIVE-UI.md).

## Pocket Edition mod research

- [Ninecraft](https://github.com/MCPI-Revival/Ninecraft) supports these older PE
  versions and already hosts the game's native library. Its
  [mod loader](https://github.com/MCPI-Revival/Ninecraft/blob/master/ninecraft/src/mods/mod_loader.c)
  loads shared libraries from the user's mods directory and exposes lifecycle
  and input callbacks. This is a suitable architecture for a small, versioned
  native UI module, or the equivalent built-in launcher patch.
- [BlockLauncher](https://github.com/zhuowei/MCPELauncher) uses native patching
  and JavaScript on Android. Its Android/Java UI integration is not available
  in NanoCraft's Linux launcher. A ModPE script displaying an Android popup
  cannot be treated as a drop-in replacement for this game's native UI.
- The original author's
  [Bionicle texture pack for MCPE 0.8.1](https://www.planetminecraft.com/texture-pack/bionicle-after-the-swarm-for-mcpe-081/)
  documents period GUI texture customization through BlockLauncher. It is
  evidence that GUI artwork can be replaced, not that native layout bounds or
  hit tests can be resized through textures alone.
- [Native mod examples](https://github.com/byteandahalf/MCPE-NativeMods) provide
  further examples of hooking techniques, but were not verified against this
  exact 0.8.1 library. Do not copy their offsets as compatibility evidence.

No verified ready-made 120x120 UI mod for this 0.8.1 build was found. The
practical route is a small native patch with explicit version checks, retaining
the game's item rendering and behavior.

## Implementation sequence

### 1. Correct and record the runtime baseline

Build from a pinned upstream Ninecraft revision plus this repository's patch
and overlay. Put that exact output in the payload and pair it with the new
OPK. Verify the executable after packaging and after copying to a test card,
not merely the build-directory binary. Record hashes and build provenance.

Launch at 120/FIT, confirm GUI/FOV diagnostic messages, and capture all six
screens again. Record render size, GUI scale, logical screen size and current
screen class at creation/configuration changes. A screen transition must not
silently restore scale 1 or reuse stale width/height.

Relevant code: `apply_gui_scale_override`, GUI-scale assignment and
`Screen::setSize` in `build/ninecraft-main.patch`. The special
`resize_current_screen_build_1` branch targets 0.11.0; its object offsets must
not be reused for 0.8.1. Disassembly of this 0.8.1 build uses Screen width and
height at offsets 8 and 12 in the inspected setup routines. Resolve symbols
and verify the exact build before using any native layout fields.

### 2. Finish the hotbar and survival HUD first

Use a physical safe rectangle of `[2,118) × [2,118)` at 120x120 for interactive
content. Backgrounds may reach the edge. Keep the crosshair at (60,60).

FIT currently budgets almost the full 120-pixel width. Measure the complete
drawn bounds, including selection halo and the inventory action. If necessary,
budget 116 pixels for the same 184-unit envelope: `116 / 184 = 0.63043`.
Prefer a HUD-local adjustment once menus have their own layout; avoid making
all text smaller merely to obtain another two pixels of hotbar margin.

Relevant native symbols in the inspected library:

| Symbol | Address in this build | Purpose |
| --- | --- | --- |
| `Gui::onConfigChanged` | `0x116108` | Selects the visible slot count for the input mode |
| `Gui::getNumSlots` | `0x115fbc` | Reads the current slot count |
| `Gui::getSlotPos` | `0x116098` | Uses 20-unit slot pitch and a bottom-relative position |
| `Gui::getSlotIdAt` | `0x115fc4` | Converts input using inverse GUI scale before slot lookup |
| `Gui::renderToolBar` | `0x1173f8` | Renders the bar and its contents |
| `Gui::handleClick` | `0x117abe` | Last visible position opens inventory |
| `Gui::renderHearts`, `Gui::renderBubbles` | `0x116d80`, `0x116f00` | Survival HUD elements to verify |

In this input mode, nine visible positions include the inventory action;
do not assume that means nine interchangeable item slots. Preserve every
existing position and START/SELECT cycling. Render the bar identically while
the inventory is open. Apply bounds changes consistently to background,
selection, icons, stack counts, item decorations and click lookup.

SDL pointer coordinates should remain in render pixels. The game's slot hit
test already applies inverse GUI scale; applying it again in the input
injector would move clicks away from the visible slots. Cursor *speed*
normalization is separate and is implemented in this pass.

Check creative and survival, first/last selection, inventory action, stacks,
damaged tools, hearts and underwater air. Derive supported HUD elements from
0.8.1 itself rather than copying a modern hunger/XP layout.

### 3. Remove the upper-right chat button — **implemented**

Done as described below, in `inputs_fix_mod_inject`, guarded and logged, and off
unless `NINECRAFT_CHAT_BUTTON=0` is set — which `launch-pe-nano.sh` does. Three
things were confirmed in the shipped library before it was written, and
`tests/chat_button_vtable_check.py` re-checks the first two against any library
you point it at:

- `_ZTV15XperiaPlayInput` slot 5 holds `XperiaPlayInput::render(float)`, so the
  hook replaces the method it is named after rather than trusting an index;
- that method's literal pool holds exactly the four texture coordinates of the
  `gui/gui.png` chat sprite, which is what identifies its single quad;
- nothing branches to `0x139a70` directly — the vtable is the only way in, so an
  empty slot removes the draw completely.

The concern about an invisible click target resolved the same way: the hit
rectangle at `this+0x40` is tested only by `XperiaPlayInput::tick`, against
`Mouse::isButtonDown(1)`, and this port has replaced that method with keyboard
movement since long before this change. Nothing else reads it.

The original analysis follows.

The inspected draw path is `XperiaPlayInput::render(float)` at `0x139a70`,
mangled `_ZN15XperiaPlayInput6renderEf`. It renders one quad using the chat
sprite in `gui/gui.png`, atlas rectangle x=200..218, y=82..100. Its
`onConfigChanged` method constructs the matching upper-right rectangle.
This matches the photograph's button.

Hook that render method to a no-op for the supported 0.8.1 handheld profile.
Guard symbol resolution and the identified game build, and log whether the
hook was installed. Ninecraft already replaces Xperia Play's `tick` with its
keyboard movement handler for 0.8.1, bypassing the native chat click path.
Verify that this remains true in the shipped build so the removed button does
not leave an invisible click target. Preserve keyboard movement and flying.

Do not suppress `Gui::renderChatMessages`: the button and the message display
are separate. Do not erase a screen rectangle after drawing, which would also
erase the world behind the icon. Do not change the whole input implementation
to hide one button.

### 4. Reflow the menus that still overflow after FIT — **not needed**

Superseded by the corrected runtime. The overflow this section was written to
fix came from the FIT patch being absent from the packaged binary, and the
native interface then gave these screens four times the pixels to lay out in.
Checked on the console: pause and options are fine as the game draws them. Do
not implement layout hooks against the photographs in this document — they show
a binary nobody is running any more.

If a specific screen is ever found genuinely overflowing, the analysis below
still holds and the symbol addresses are still good. The original text follows.

Implement guarded screen-specific layout hooks and set both render bounds and
hit rectangles. Suggested starting rectangles below are design targets in
physical 120x120 pixels, not claims about a tested final layout. Convert these
once into the screen's current logical coordinates.

| Screen | Proposed compact layout |
| --- | --- |
| Title | Keep logo above y=38; Play x=8..112, y=62..80. Put settings in its own 18x18 region below Play. Reserve two short footer lines near the bottom without overlapping settings. |
| Pause | Header above y=24; full-width local-play actions x=8..112 with 16-pixel height and 4-pixel gaps. Start at y=32 and fit up to four actions. Use a short Resume caption. Preserve actual actions; place extra/multiplayer actions on a secondary page. |
| Options | Header y=2..18; compact category rail x=2..20; body x=22..118, y=20..116. Use a scrollable list with labels above sliders/toggles when a single line will not fit. Back stays pinned and never shares its title rectangle. |
| Inventory/crafting | Retain the photographed category rail and grid reflow. Bound the scroll area above the shared hotbar. Verify every tab and the last row of items; correct a screen's own bounds before shrinking icons again. |
| World list/dialogs | Preserve the working world-list structure. Give top buttons small gaps; clip/ellipsize long names inside their card. Fit creation, edit and confirmation actions on screen, with scrolling for excess fields. |

The injected cursor currently draws an 8x11-pixel triangle plus an outline.
Assess a smaller glyph after the slower speed is tested. At the right/bottom
edges, flip the glyph around its click tip or otherwise keep its drawing in
frame; do not move the click point away from the actual selectable edge.

`PauseScreen::setupPositions` (`0x1261a4`) uses a narrow fraction of screen
width and fixed button Y positions 48/80/112/144. That explains why global
scaling alone is an incomplete pause-menu solution. Other useful targets are
`StartMenuScreen::setupPositions` (`0x12bae0`),
`OptionsScreen::setupPositions` (`0x1258fe`) and the inventory pane layout
methods. Prefer symbol-based hooks and explicit structures for this build to
unexplained memory writes.

Text must fit its own button, not merely the screen. Use short localized
labels, per-control font scaling and scrolling where necessary. Avoid a global
0.5 scale as the final solution: although its 240 logical pixels would fit more
controls, small text would become roughly four internal pixels high.

### 5. Acceptance checks and rollout

1. At 120/FIT, every hotbar position and selection border is visible with an
   inward margin; clicking and START/SELECT select the same displayed item.
2. Chat icon is absent in-world, its old rectangle has no invisible action,
   and ordinary movement/flying/system messages still work. (Implemented; the
   click path was already gone. Confirm on the console that messages still
   appear and that flying and movement are unchanged.)
3. All six photographed screens have no off-frame interactive bounds or
   overlapping captions. Long lists and dialog actions remain reachable.
4. Test survival inventory, crafting, chest/furnace, death and world creation
   as applicable to 0.8.1. Capture at actual resolution plus a nearest-neighbor
   enlarged view; camera photos supplement pixel captures.
5. Repeat at 240/FIT and 240/AUTO. Keep STOCK's intentional 120 clipping clearly
   documented rather than treating that diagnostic mode as a fit guarantee.
6. At low frame rates, cursor taps can target individual cells; camera 100%
   preserves the previous look behavior. Changing one slider never changes the
   other. Resume and screen transitions do not cause a jump.
7. Run a matched in-world replay before/after layout changes, keeping world,
   camera path, FOV, cap and CPU clock fixed. Check CPU time, memory and frame
   rate; do not confound the FOV correction with UI performance.

Land the runtime/package correction, hotbar/chat work, and screen-specific
layouts as separate reviewable steps. None depends on receiving testers'
`nanocraft-kernel.txt`; kernel compatibility remains a separate investigation.

## Completed in this pass

The two independent quick-settings sliders, their persistent configuration,
screen-relative cursor motion, production-code tests and an ARM test package
are complete. See [SENSITIVITY-BUILD.md](SENSITIVITY-BUILD.md).

The native-resolution interface is also complete: at 120x120 the world renders
into its own buffer and the game's own HUD and screens are drawn over it at
240x240. See [NATIVE-UI.md](NATIVE-UI.md). It is verified against a real
software GL driver and packaged, and still needs an on-device test.

The chat button is gone (section 3). No game UI layout hooks were applied and
none are planned: section 4's premise did not survive testing the corrected
runtime on hardware.
