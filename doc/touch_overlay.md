# Touch overlay

A virtual gamepad the game draws on a touch screen (0115, `src/touch_overlay.odin`). How touch reaches the UI's screens (the pointer, the touch row, drag and drop) is in [ui.md](ui.md); the other devices are in [input.md](input.md).

- To the rest of the game it is a gamepad: each frame it fills a `Raw_Gamepad` named "Touch overlay" and a look delta, and the backend merges that into the physical gamepad. `data/bindings.sjson` maps its controls like any gamepad's.
- Default, the shipped layout, has no buttons (0134): a floating stick on the left, and on the whole free screen a drag looks, a hold mines, a tap interacts or places, and a tap at the right edge jumps.
- The hotbar's slots and the HUD's touch buttons beside it take their own fingers; they select, drop, and open the inventory, the map and the pause menu.
- It runs only in a world. Over a screen it reads a layout's Start and Back buttons alone and every other touch is the pointer.

## When it is on

`settings.touch_overlay` (`auto`, `on`, `off`; the Accessibility tab's Touch controls row): `auto` is on for the Android build and off elsewhere (`touch_overlay_enabled`). `--touch-overlay` forces it on for a run. It is read only in a world (the title screens take touch as the pointer alone) and not while the touch layout editor is on top.

On the desktop raylib has no touch points, so the mouse is touch point 0 while its left button is down (`read_touch_points`): a drag on the left walks, one elsewhere looks, a click places or interacts, a click at the right edge jumps, a held click mines. The cursor stays free in the world while the overlay is on. It works on both backends, so `--touch-overlay` also runs on the couch and the Deck with SDL3.

## Into the gamepad

- `touch_overlay_raw_gamepad` numbers the buttons in the backend's numbering: SDL's buttons and trigger axes, or raylib's buttons with the triggers as `LEFT_TRIGGER_2`, `RIGHT_TRIGGER_2` and trigger axes resting at -1.
- `merge_touch_overlay_gamepad`: buttons or'ed, stick axes summed and clamped, trigger axes the larger. A physical gamepad keeps working and keeps its name, touchpads and motion.
- The overlay's gamepad alone carries `on_screen`, which `detect_input_device` skips, so a touch leaves touch the active device: a screen opened by a touch keeps the pointer instead of gamepad glyphs and focus.
- While the overlay drives the world (on, and no screen open, `touch_overlay_drives_world`), the mouse's delta and buttons read nothing, since the first touch holds raylib's left mouse button. Mouse look, the gyro Steam sends as mouse movement, and mouse mining are off then too.
- The diagnostics Input page shows the merged gamepad.
- The look delta is converted from render pixels to the mouse delta's window coordinates (`render_pixels_to_window_units`), so the look settings apply and a scaled desktop looks at the mouse's speed.
- Apart from two actions (the hotbar's slot selection and the jump tap, below) the overlay only presses gamepad controls and sets the aim. `apply_touch_overlay_hotbar` and `apply_touch_overlay_jump` put those two into the input frame.

## Fingers

`update_touch_overlay` keeps one `Touch_Slot` per raylib touch point id, up to `TOUCH_POINT_CAPACITY` (8). A finger keeps the role it landed with (`classify_touch`) until it lifts, in this order:

1. On a button of the layout: holds that button until it lifts, also when it slides off. Over a screen only Start and Back count.
2. Over a screen, any other finger is the pointer's (`Ignored`).
3. On a HUD touch button (`Hud_Button`) or a hotbar slot (`Hotbar`), ahead of the free screen that reaches under them.
4. Inside a free static stick's base: that stick, at once.
5. Anywhere else on either half: undecided (`Pending`) until it moves or rests.

A `Pending` finger becomes:

- a drag once it moves more than `TOUCH_TAP_SLOP` from where it landed, taking the whole drag so far on that frame. It is the floating stick when it landed on the stick's half while no finger holds the stick (`pending_drag_stick`), else the look drag.
- a hold (`Hold`) once it rests `TOUCH_HOLD_SECONDS` inside the slop. A hold that landed on the stick's half and then moves past the slop while the stick is free becomes the stick, ending its Mine and its aim (a thumb that rested before it pushed). Any other hold keeps mining where the finger goes.
- a tap when it lifts before either (below).

| Constant | Value | Meaning |
| --- | --- | --- |
| `TOUCH_TAP_SLOP` | 12 | Pixels at 1080 high, scaled like the layout; beyond it a finger drags |
| `TOUCH_HOLD_SECONDS` | 0.25 | Rest that makes a hold, a hotbar long press, a slot split ([ui.md](ui.md)) |
| `TOUCH_DOUBLE_TAP_SECONDS` | 0.3 | Window for a latching double tap |
| `TOUCH_OVERLAY_ELEMENT_CAPACITY` | 64 | Elements per layout (the latches are a bit set) |

- **Stick**: the drag over the stick's `radius` (130), clamped to the unit disc, with the backend's stick dead zone. The first time the drag passes `sprint_rim` (1.25) times the radius within 45 degrees of straight up, the stick click (Sprint) is held until the finger lifts (`stick_sprint_latched`): push to the rim to sprint, lift to stop.
- In the default toggle mode that one press switches sprinting on and it ends when movement stops; in hold mode it sprints until the lift. Easing back or wobbling across the rim makes no new press. Under a screen the stick reads nothing and a rim crossing does not latch.
- **Look drag**: the movement since the last frame times the look element's `sensitivity` (1.0). The look's `side` is kept for the file's form and the same side check, but does not limit where the drag lands.
- A finger held when a screen opens reads nothing while it is open and again once it closes. A finger that landed in a menu stays the pointer's after the menu closes. Several fingers do all of this at once.

## Taps, holds and aiming

`settings.touch_interaction` (`tap` or `crosshair`, the Accessibility tab's Touch aiming row, 0118) chooses where the hold and the tap aim. Both schemes read the same gestures; `crosshair` drops the aim (`touch_scheme_output`), so they act at the view's centre as a gamepad's would.

- A hold presses the look element's `hold_control` (RT, Mine) and, in `tap`, aims at the finger as it moves.
- A tap aims at the lifted point until a simulation tick has run with that aim, then presses `tap_interact_control` (A, Interact) when that tick's target takes Interact (`entity_takes_interact`: an entity with a panel or a schematic crate) and `tap_place_control` (LT, Place, or Use_Item with a usable item) otherwise, and holds it until a tick has run with the press. Waiting for ticks keeps a tap from being lost on a display faster than 60 Hz, where a frame often runs no tick.
- A tap that waits longer than `TOUCH_HOLD_SECONDS` for a tick (a developer pause holds them) is dropped. A lift while another tap is still in flight starts no tap, nor does one while another finger holds; a hold that begins drops a tap in flight; a screen opening drops it.
- **Jump tap**: a tap in the rightmost `jump_zone_share` of the screen (0.2 in Default) presses the Jump action at once and aims nowhere, held until a tick ran with it (`Touch_Overlay_Output.jump_tap`, `jump_tap_edge` on its first frame). It is an action, not `SOUTH`, since `SOUTH` is Interact too and would open an entity under the view's centre. A drag or a hold in the zone looks and mines as anywhere.
- **Aim**: `touch_aim_direction` casts the render camera's ray through the point (`GetScreenToWorldRayEx` with the camera the world was last drawn with) against the world, reaching `PLAYER_REACH` plus the camera's distance to the eye. The direction from the eye to the hit (`eye_aim_direction`) goes into `Input_Frame.aim_direction` with `aim_overrides` (`apply_touch_overlay_aim`), and `tick_player` targets along it (`player_target_direction`, kept as `Player.target_direction` for the half a slab takes). In third person the target is thus the block under the finger.
- In `tap` the HUD draws no crosshair and rings the mined block instead of the bar ([hud.md](hud.md)).

## Hotbar and HUD buttons

- **Hotbar** (0119, both schemes): the frame hands the overlay the slots in render pixels as the HUD last drew them (`hud_hotbar_pixel_rectangles`). A finger on a slot claims the pointer and turns neither the view nor the stick.
- Past `TOUCH_TAP_SLOP` a hotbar finger fires nothing, so a drag that begins on the hotbar neither selects nor drops. A lift before `TOUCH_HOLD_SECONDS` selects the slot (`hotbar_tap`, an edge of `Hotbar_Slot_<n>` that the tick accumulator carries). Resting that long is the long press, firing once: on the selected slot it holds `hotbar_drop_control` (`DPAD_DOWN`, Drop_Stack) until the lift, on another slot it only selects.
- **HUD touch buttons** (0134): with the overlay on in a world and no screen open, the HUD draws backpack, map, pause and, while Rotate_Building acts, rotate ([hud.md](hud.md)). A finger on one presses the gamepad control bound to its action (`touch_control_for_action`: the first gamepad binding outside the menus on this backend that the overlay can press; `WEST`, `BACK`, `START`, `NORTH` with the shipped bindings), so a rebinding takes the button along, and a button whose action has no such binding is not shown.
- The frame hands the HUD buttons' rectangles over as for the hotbar (`frame_hud_touch_buttons`). Over a screen they are neither drawn nor read.
- Sneak has no touch control in Default (a user layout may add a B button); Sprint is the stick's rim, hotbar cycling the hotbar's taps, Drop the long press.

## The pointer and screens

- A finger the overlay claimed never clicks the UI: when raylib's first touch is on a layout button (in the world or over a screen), a hotbar slot or a HUD button, both backends read the left mouse button up that frame (`Touch_Overlay_Frame.pointer_claimed`, `touch_overlay_mouse`). The pointer's position still follows it.
- With a screen open the overlay draws and reads a layout's Start and Back buttons alone, over the screen. Start pauses or steps back one screen.
- Over a screen a layout's Back presses `BACK`, which the bindings give `Open_Map`, not the menus' Back (0137), so it only opens or closes the map. raylib keeps Android's back key to itself.
- Screens close with their touch row's Back or a tap off their panel ([ui.md](ui.md), Touch button row and Tap or click off a panel).

## Layout file

`data/touch_overlay.sjson` is loaded with the content tables (a change reloads with them); its header documents every key. Lengths are pixels of a `reference_height` (1080) high screen, scaled by the screen's height (`overlay_layout`), each button anchored to a corner, the bottom centre or the top centre, so a wider screen keeps the buttons where the thumbs are.

The loader refuses the file, naming the element by its label (`elements[7] ("A"): unknown control "SOUTHH"`), for: an unknown kind, control, shape, anchor or side; a misspelt key; two sticks or two looks; a stick and a look on the same side; a floating stick with an anchor or position, or a static one without them; a look without its three controls; `jump_zone_share` outside 0 to below 1; `opacity` outside 0.1 to 1 (0 or left out is 1); more than 64 elements; an unknown `hotbar_drop_control`. A control is any gamepad button raylib can also express, or a trigger (`touch_overlay_control_from_name`), so a user layout may carry any button.

- **Static stick** (0120): `static = true` puts the base at `anchor` and `position` like a button, drawn with the knob centred at rest. Only a touch that begins inside the base circle drives it, centred on the base; a touch elsewhere on its half is free screen.
- **Double tap latch** (0120): a button with `double_tap_toggles = true` latches down when a touch lands on it within `TOUCH_DOUBLE_TAP_SECONDS` of a tap on it lifting (a tap is down less than `TOUCH_HOLD_SECONDS`). The next touch releases it; neither touch starts a new double tap.
- A latched button presses like a held one, draws filled, and under a screen reads only if it is Start or Back.
- Latching works only while the sneak setting is Hold (`Touch_Interaction_Frame.double_tap_latches`): in Toggle a tap already toggles, and a latched B would swallow the next edge, so the latches release. A data reload (`release_touch_latches` in `replace_frame_content`) and a change of the active layout release them too, since they index the elements.
- **Discovery card**: while the overlay is drawn the card sits a gap below the lowest `top_center` button of the layout in use (`touch_overlay_top_center_clearance`, 0123).
- `test_no_touch_overlay_element_covers_a_hotbar_slot` keeps Default's elements and the HUD's touch buttons off the hotbar; a user layout may cover it.

## Drawing

`draw_touch_overlay` runs after the screens, with a screen open only for Start and Back. Outlines 4 UI units wide (`TOUCH_OVERLAY_LINE`) and labels in the UI font at alpha 0.55 (`TOUCH_OVERLAY_COLOR`) times the element's `opacity` (0121); a held or latched button filled; the stick's ring at its origin with the knob under the finger; nothing for the look. Nothing pulses or moves but with a finger ([DESIGN.md](../DESIGN.md), No perceivable repetition).

## User layouts and the editor

Rule: Default is the data file's and never changes; the user's layouts live in `touch_overlay.sjson` in the user configuration directory, beside `config.d/` but not a configuration layer (0121).

- The file holds `selected = "<name>"` (Default when left out) and `layouts = [{name = "..." reference_height = ... hotbar_drop_control = "..." elements = [...]}]`, each layout in the data file's form and validated the same way (`layouts[0] ("Mine"): elements[3] ("A"): unknown control ...`). A name must not be empty or Default (trimmed, any case); names are unique; `selected` must name a layout. No layout needs a START button, since the HUD's pause button opens the pause menu.
- `load_touch_layouts` reads it at start. A file that cannot be read or is refused is logged, Default is used, and the file is locked until the next start (`Touch_Layouts.locked_path`): the Touch layout row and the editor's Save, Save as and Delete only toast that the file must be fixed or removed, so its layouts are never overwritten.
- The overlay reads the selected user layout, else Default (`active_touch_layout`), so a reload of `data/touch_overlay.sjson` still applies to Default.
- The file is always written whole (`write_touch_layouts_file`), since arrays replace wholesale, by the frame loop (`serve_touch_layouts`) when the Accessibility tab's Touch layout row steps the selection (Default, then the file's order) or the editor saves or deletes.

The editor (Edit touch layout on the Accessibility tab, `ui_touch_layout_editor.odin`; its screen is in [ui.md](ui.md)) edits a draft of the selected layout:

- Move; size (a circle stays round) in steps of 10 reference pixels from 40 to 600; opacity in steps of 0.1; a button's control (steps through every control the loader knows, the label following) and `double_tap_toggles`; a stick's radius (40 to 400) and static flag (turning static puts it at the bottom corner of its half, two radii in).
- After a move, a resize or a switch to static the element is held on the screen and a stick on its own half; the anchor stays and the position is recomputed from it in whole reference pixels. The look element is not shown. The editor adds no buttons: a user layout carries buttons only when written by hand or saved before Default lost its buttons (0134).
- Save writes the draft over its layout (never Default), Save as under the name field's name (replacing a layout of that name) and selects it, Delete removes it and selects Default, Reset to Default replaces the draft with Default's elements, `reference_height` and `hotbar_drop_control` under the draft's name.
- The screen only records these requests; the frame loop serves them after the frame's draw list ran (`apply_touch_layout_request`), since starting the draft again frees the arena that frame's text points into.
- While the editor is on top the overlay neither reads nor draws, so every touch is the pointer's.
