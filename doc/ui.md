# User interface system

How every screen in the game is built, so that the pillars "couch first" and "one coherent game" hold from the first panel. The screen list itself is in [DESIGN.md](../DESIGN.md).

## Principles

- 10 foot UI. Body text is at least 24 pixels at 1080p, headings 32, the glyph bar 28. Everything scales with screen height and a user UI scale setting. A five percent safe area keeps content away from television edges.
- Two navigation styles, one model. Every interactive widget has a rectangle and a stable id. A focus cursor moves between widgets with the d-pad or left stick using a spatial rule (the nearest widget in the pressed direction, wrapping inside the panel). The pointer (right trackpad or mouse) sets focus to whatever it hovers, so both styles drive the same focus state and every screen works fully with either. Confirm is A or a click, Back is B, tabs are the bumpers, Y opens the info panel, X is the panel's context action (sort, split).
- No hover only information. Tooltips are panels that open on Y and dock to the edge of the current panel.
- Radial menus for quick choices: the hotbar, categories, the letter wheel. Shown while the pad is touched, highlight follows the finger angle, release selects, the dead centre cancels.
- Text only from data. Every player facing string comes from `data/strings/en.sjson` by key. Numbers go through one formatting procedure per unit (per minute, kW, MW, L, blocks).
- Stick repeat: 350 ms initial delay, then 80 ms per step, for held directions in lists and grids.

## Architecture

- An immediate mode UI written in Odin over raylib draw calls. raygui is not used: it is mouse centric and has no focus navigation.
- Per frame: `ui_begin` resets the frame, screens declare widgets (each call returns the widget's interaction result for this frame), `ui_end` resolves focus movement and pointer hover, then draws from a deferred command list so that focus resolved this frame is drawn this frame. Activation is decided inside the widget call (Confirm on the previous frame's focus, or a click hit tested this frame), so results arrive without delay; only focus moves show up in widget results one frame late. The UI runs after the simulation in the frame, so a screen opening or closing reaches the world one frame later, and a world action still held when a screen closes stays suppressed until it is released.
- One `Ui_State` in the frame state: focus id, focus panel, per widget scroll offsets and selections keyed by id, the open screen stack, radial state, repeat timers, the pointer position and whether the pointer or the sticks moved last (the glyph bar shows what fits the active device).
- Layout in UI units where 1080 units span the screen height; conversion to pixels happens in the draw layer. Rows, columns and grids compute rectangles with a small set of layout helpers; no constraint solver.
- Drawing: rectangles, borders, text and icons from raylib, with scissor rectangles for scrolling lists. Text uses raylib's default font at first and a loaded TTF from `data/fonts/` once one is chosen.
- Look sensitivities and the gyro toggle from the settings are applied in the input layer, not in the simulation, so the simulation only ever reads its input. Pause acts as Back while a screen is open, and Back first closes an open tooltip. Tabs are not focus targets, the bumpers switch them.
- Screens form a stack over the world and its HUD. Panels such as the inventory, machine panels, the recipe browser and the journal do not pause the simulation, the factory keeps running behind them. The pause menu, settings and world setup do pause.

## Widgets

Label, button, toggle, slider, tabs, vertical list with letter jump, grid of slots, item slot (icon, count, highlight), progress bar, tooltip panel, radial menu, text field (opens the on-screen keyboard), glyph bar, toast.

## Item slots on a gamepad

A picks up the focused stack, A on another slot drops it or swaps, X splits the stack in half, Y shows the item's info panel, holding A while moving the focus across machine slots distributes the held stack evenly (the Even Distribution gesture from `input.md`). The pointer does the same with clicks. A held stack follows the focus and the pointer.

## HUD

Hotbar of eight slots bottom centre with the selected slot enlarged, the held item name above it, the name and state of the targeted block or entity near the crosshair, the current quest objective top right, toasts top left, the glyph bar bottom right, the compass strip top centre.

## Icons

Placeholder icons are the block's atlas tile for blocks, and a coloured square with two letters for items and machines. Real icons come with the art pass.

## On-screen keyboard

A QWERTY grid under the text field, driven by focus navigation and the pointer, with shift, space, backspace and done as large keys. A physical keyboard types into the same field when present.
