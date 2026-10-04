# 0227: A crouch control on the touch overlay

Status: verified (2026-10-04, the review of the same day weighed, its one nit (a stale HUD comment) fixed in the landing amend, in `.claude/worktrees/0227` on `item/0227` from `main` after 0222 landed, the specification approved the same day with the decisions below; from the user on the phone with the round three pod preview: "How do i toggle crouch on phone"; there is none, Default carries no Sneak control since 0134 took the buttons out, and the airlock of 0221 needs crouching)

## Goal

A player on the phone can crouch, hold the crouch and stand up again without writing a layout file by hand: the pod's airlock (0221, the user's rule "the pod airlock doors shall need crouching to pass through") is passable on touch.

## Controls

Control design (main agent, 2026-10-04). Touch is a virtual gamepad, so the control presses the Sneak binding (`EAST`), never a touch code path of its own (Code rules).

- **The control: a B button in Default**, a layout element (`kind = "button"`, `control = "EAST"`, `shape = "circle"`, `label = "B"`, `double_tap_toggles = true`), anchored `bottom_right` in the look half, above the thumb's resting place in the jump zone, so the right thumb reaches it without leaving the view. The preview layout the user crawled through the airlock with (`{kind = "button" control = "EAST" shape = "circle" anchor = "bottom_right" position = [130, 300] size = [120, 120] label = "B" double_tap_toggles = true}`, the 2026-10-04 reply) is the starting point; the design stage fixes the position and the size against `test_no_touch_overlay_element_covers_a_hotbar_slot` and the HUD's touch buttons and the placement editor's grid (0215) at the smallest audit size, and names them.
- **Why a layout button and not a HUD button**: the HUD's touch buttons (0134) open screens and act once (backpack, map, pause, tools, rotate); crouch is a world mode held through a crawl while the other thumb steers, so it needs the double tap latch, which is a layout button's mechanism (0120). Why not a stick gesture: a gesture would be a touch code path of its own, which the Code rules forbid, and the rim is already Sprint. 0134's "the layout has no buttons" was about the buttons that taps and holds replaced; Sneak has no tap equivalent, so one circle comes back for it.
- **Mode and layer**: the world layer only. Over a screen the overlay draws and reads a layout's Start and Back buttons alone, so B is neither drawn nor read in a menu, and it presses nothing there. It has one meaning, Sneak, with every item held and in every world context (the field and the block world alike): no second meaning (Code rules, keybindings).
- **How it reads under the Sneak setting**: Hold: Sneak while touched, a double tap latches it down, the next touch releases it (`double_tap_latches`); Toggle: a tap toggles the sneak as a B press does and the latch is released as 0120 already does, so a latched B never swallows an edge.
- **What every existing control still does with the button present**: a tap in the jump zone outside the button still jumps; a drag or a hold starting on the button neither looks nor mines (the button claims its finger, as every layout button does), elsewhere on the look half they look and mine as today; the stick, the hotbar's taps and long press, and the HUD's touch buttons are unchanged. The editor still adds no buttons, but Reset to Default now carries the B button into a user layout, and a user layout saved before this item keeps lacking it until reset (doc line to update).

## Change

- Decided by the control design: the element or the HUD button, its place against `test_no_touch_overlay_element_covers_a_hotbar_slot` and the placement editor's grid (0215), and how it reads under the Sneak setting (Hold: held while touched, double tap latches; Toggle: a tap toggles).
- Docs: `doc/touch_overlay.md` (Default's elements, the Sneak line), `doc/input.md` (the touch column of the bindings table), `data/touch_overlay.sjson`'s header.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`.
- Tests: the control presses Sneak in the world context and nothing in a menu; the latch follows the Sneak setting; the element covers no hotbar slot and none of the HUD's touch buttons at the smallest audit size.
- On the phone: crawl through the airlock of the round three pod crouched, both doors, and stand up in the cabin.

## Specification (design, 2026-10-04)

No new file, no new procedure in `src/`: the change is one data line, its header, tests and docs. The mechanism (a layout button, `double_tap_toggles`, the latch following `Touch_Interaction_Frame.double_tap_latches`) exists since 0120 and is element generic.

### The element

Appended to Default's `elements` in `data/touch_overlay.sjson`, after the look element (so the stick and the look keep indices 0 and 1):

```
	{kind = "button" control = "EAST" shape = "circle" anchor = "bottom_right" position = [60, 320] size = [100, 100] label = "B" double_tap_toggles = true}
```

Why not the preview's `[130, 300]` size 120: it covers the placement editor's grid. On the phone at UI scale 1 (2424 by 1080) the circle's box is x 2234 to 2354, y 720 to 840, and the grid's Nudge_Right and Cancel cells reach x 2254.8 (grid x 1998.8 to 2254.8, y 666 to 922): 20.8 px of overlap. At 1920 by 1080 (and so 1280 by 720 and 960 by 540, same proportions) it overlaps Nudge_Right by 46 reference px, and at 1920 by 1080 scale 1.5 it covers Tools by 55. A layout button wins over a HUD button in `classify_touch` (buttons first), so an overlap would steal the editor's taps.

Where the room is: overlay lengths scale with the screen's height, the HUD with height times UI scale, so in reference pixels (screen height 1080, width W) the obstacles near the bottom right corner are the row (bottom 54 to 54 + 80s, rows going up when it wraps) and the grid, whose right edge stands `0.05 W + 48 s` from the screen's right edge (`hud_touch_button_rectangles`: middle column centre two steps left of the safe area's right edge, the safe area 5 percent in). That distance is smallest at 2880 by 1920 scale 1 (W 1620): 81 + 48 = 129. Above the row there is no band free of the grid at a thumb's height (the grids reach from 158 to 858 above the bottom across the sizes). So B sits in the strip along the right edge: its right extent from the edge is `60 + 50 = 110 < 129`, its left extent 10, and its bottom 270 above the screen's bottom clears every row (the highest row reaching the right strip is 1280 by 800 at 1.2: up to 150).

Arithmetic at the smallest audit size, 960 by 540 at UI scale 1 (render pixels; `pixels_per_unit` 0.5, overlay scale 0.5):

- B: centre `(960 - 60 * 0.5, 540 - 320 * 0.5) = (930, 380)`, size 50: x 905 to 955, y 355 to 405.
- Safe area in units: x 96 to 1824, y 54 to 1026. Hotbar width `7 * 88 + 100 = 716` units, x 602 to 1318, top 926 at the highest (selected slot): pixels x 301 to 659, y 463 to 513. Clear (B's bottom 405, B's left 905).
- Row: left `1318 + 24 = 1342`, columns `int((1824 - 1342 + 8) / 88) = 5`, one row: units x 1342 to 1774, y 946 to 1026, pixels x 671 to 887, y 473 to 513. Clear by 68 px in y.
- Grid: row top 946, grid top `946 - 24 - 256 = 666`, grid left `1824 - 176 - 40 - 88 = 1520`: units x 1520 to 1776, y 666 to 922, pixels x 760 to 888, y 333 to 461. B's left 905 is 17 px (34 reference) right of the grid's right edge (Nudge_Right, x 848 to 888, y 377 to 417).

Clearance to the nearest HUD rectangle at every size the new test runs (reference px): 1920x1080 at 1, 1.2, 1.5: 34, 43.6, 25 (Tools); 1280x800 at 1, 1.2, 1.5: 24.4, 34, 61; 2880x1920 at 1: 19 (the tightest, Nudge_Right); 960x540: 34; 1920x540: 130; 960x1080 at 0.5: 36; phone 2424x1080 at 0.75, 1, 1.5: 47.2, 59.2, 96; 1280x720 at 1: 34. It also clears at every UI scale from 0.75 to 1.5 on 2424x1080, 1280x720, 1280x800 and 2880x1920 (smallest 7, at 1280x800 0.75). The phone box: x 2314 to 2414, y 710 to 810, inside the jump zone (x from 1939.2).

Thumb: B hugs the right edge 270 to 370 above the bottom, so the right thumb resting low in the jump zone (left of and below it) keeps jumping, looking and mining there; B takes 100 of the zone's 485 px width on the phone. Positions and size are whole tens, so the editor's 10 px steps and its 40 to 600 size range take it as is.

### Data header (`data/touch_overlay.sjson`)

Replace the last paragraph (lines 75 to 79, "The layout has no buttons (work item 0134): ... Sneak has no touch control; a user layout may add a B button.") with:

```
// Default has one button (work item 0227): B, Sneak, along the right edge
// above the jump zone's thumb rest; a double tap keeps it down while the
// sneak setting is Hold. The rest has no buttons (work item 0134): taps
// and holds anywhere place and mine, a tap at the right edge jumps, the
// stick's rim sprints, the hotbar's taps and long press select and drop,
// and the HUD's touch buttons beside the hotbar open the inventory, the
// map and the pause menu and rotate. B stays clear of the hotbar, the
// HUD's touch buttons and the placement editor's grid at every audited
// size (test_no_touch_overlay_element_covers_a_hud_touch_button).
```

### Tests (`src/touch_overlay_test.odin` unless named)

- `test_shipped_touch_overlay_loads` (changed): `len(layout.elements)` 3; `len(overlay_layout(layout, PHONE_SCREEN, ...))` 1; the element labelled B (`touch_element_index` lives in the editor test file, same package; or `layout.elements[2]`) has `kind .Button`, `control == Touch_Overlay_Control{button = .EAST}`, `shape .Circle`, `anchor .Bottom_Right`, `position {60, 320}`, `size {100, 100}`, `double_tap_toggles` true. The comment above it becomes "Default has the stick, the look and one button, B (0134, 0227)." The data load test is this one (it parses the shipped file through `#load`); `data_reload_test.odin` loads the file too and needs no change.
- `test_no_touch_overlay_element_covers_a_hotbar_slot` (unchanged): until now vacuous for Default's elements (none placed), it now checks B against the hotbar on the phone and 1280 by 720.
- `test_no_touch_overlay_element_covers_a_hud_touch_button` (new, after the one above). Sizes: every `UI_AUDIT_SIZES` entry (copy to a variable first, `audit_sizes := UI_AUDIT_SIZES`) plus `{PHONE_SCREEN, UI_SCALE_RANGE.minimum}`, `{PHONE_SCREEN, 1}`, `{PHONE_SCREEN, UI_SCALE_RANGE.maximum}`, `{{1280, 720}, 1}`, in a `[dynamic]Ui_Audit_Size` in the temp allocator. Per size: a `Ui_State` with `pixels_per_unit` and `screen_units` set as in the hotbar test, `safe := ui_safe_area(&ui)`, `placed := overlay_layout(layout, size.pixels, context.temp_allocator)`, expect `len(placed) > 0`; for each placed element `element := pixels_to_units_rectangle(placed.centre, placed.size, ui.pixels_per_unit)` and expect, with a message naming the label, the size and the other rectangle: `!rectangles_overlap(element, rectangle)` for every rectangle of `hud_touch_button_rectangles(safe)` (all of `Hud_Touch_Button`, row and grid, whether shown or not), and for every slot of `hud_hotbar_rectangles(safe, selected)` for `selected in 0 ..< HOTBAR_SLOT_COUNT`; and `rectangle_inside(element, {0, 0, ui.screen_units.x, ui.screen_units.y}, 0)`. Comment: "Default's buttons (0227) clear the hotbar, the HUD's row and the placement editor's grid at every audited size and on the phone at the UI scale range's ends, since a layout button takes a finger before a HUD button."
- `tap_b` (helper, changed): gains a last parameter `point := B_BUTTON_POINT`, used for both frames; existing callers unchanged.
- `DEFAULT_B_POINT :: [2]f32{2424 - 60, 1080 - 320}` (new constant beside `B_BUTTON_POINT`, the B's centre on `PHONE_SCREEN`).
- `test_defaults_b_presses_sneak_in_the_world_and_nothing_over_a_screen` (new, shape of `test_with_a_screen_open_only_start_and_back_read_and_are_drawn`, `test_touch_overlay_draws_start_and_back_alone_over_a_screen` and the bindings lines of `test_a_tap_in_the_jump_zone_jumps_without_an_aim`). Shipped layout, `TAP_TOUCH`, `tables, _ := build_input_bindings(shipped_default_bindings(t), .Raylib, context.temp_allocator)`. World: a finger down on `DEFAULT_B_POINT` gives `slot_by_id(state, id).role == .Button`, `output.buttons[EAST]`, `.Sneak in gamepad_button_actions(touch_overlay_raw_gamepad(output, .Raylib), tables)`, `!output.aims`, `!output.jump_tap`, and `touch_overlay_frame(...)`'s `pointer_claimed` (one call with the same point); after the lift EAST is up, `!output.jump_tap` and `output.triggers == {}` (the tap in the jump zone neither jumped nor placed). A drag starting on B (down at the point, then 60 px left) gives `output.look_delta == {}`. Over a screen (`world_shown` false, a fresh state): the same finger gives `output == Touch_Overlay_Output{}`; with the finger lifted, `draw_touch_overlay(&ui, state, layout, PHONE_SCREEN, false)` draws no text label and `true` draws exactly the label "B".
- `test_defaults_b_latches_while_the_sneak_setting_is_hold` (new, mirroring `test_a_double_tap_latches_b_and_the_next_tap_releases_it` and `test_double_taps_latch_only_while_the_sneak_setting_is_hold`, which run on GameNative's B at `B_BUTTON_POINT` and so do not cover Default's element). Shipped layout, `tap_b(..., point = DEFAULT_B_POINT)`: in Hold (`TAP_TOUCH`) the second tap of a double tap leaves EAST down after its lift and for 60 frames after, the next tap releases it on its lift; in Toggle (`double_tap_latches = false`) two quick taps each press and release; a latch made in Hold is released by the first Toggle frame (`state.latched` empty, output zero).

### Docs

- `doc/touch_overlay.md`:
  - Line 6 becomes: "Default, the shipped layout, has one button, B for Sneak along the right edge (0227); the rest is a floating stick on the left, and on the whole free screen a drag looks, a hold mines, a tap interacts or places, and a tap at the right edge jumps (0134)."
  - Fingers, Jump tap bullet: after "A drag or a hold in the zone looks and mines as anywhere." add "A finger landing on Default's B is the button's (1. above), so B's circle does not jump."
  - Hotbar and HUD buttons, line 74 becomes: "Sneak is Default's B (0227), a circle 100 across at `position = [60, 320]` from the bottom right corner, clear of the row and the placement editor's grid; in Hold a double tap keeps it down until the next tap, in Toggle a tap toggles. Sprint is the stick's rim, hotbar cycling the hotbar's taps, Drop the long press."
  - Layout file, line 94 becomes: "`test_no_touch_overlay_element_covers_a_hotbar_slot` keeps Default's elements and the HUD's touch buttons off the hotbar, and `test_no_touch_overlay_element_covers_a_hud_touch_button` keeps Default's buttons off the hotbar, the row and the placement editor's grid at every audited size and on the phone at UI scale 0.75, 1 and 1.5, since a layout button takes a finger before a HUD button; a user layout may cover them."
  - User layouts and the editor, line 112's last sentence becomes: "The editor adds no buttons: a user layout carries the buttons it was saved with or written with by hand. One saved while Default had no buttons (0134 to 0227) has no B until Reset to Default."
  - Line 113: after "Reset to Default replaces the draft with Default's elements" insert "(B included, 0227)".
- `doc/input.md`: there is no touch column in the bindings table (see Questions). Under Hold or toggle, after the table, add: "On touch, Default's B (0227) presses Sneak's `EAST`: in Hold it sneaks while touched and a double tap keeps it down until the next tap, in Toggle a tap toggles ([touch_overlay.md](touch_overlay.md), Layout file)." In The placement editor's table, the Touch row's cell gains at its end: "; Default's B is Sneak".
- `doc/hud.md`: no change (its touch lines name no Sneak and the HUD gains nothing).
- `src/ui_touch_layout_editor_test.odin` lines 8 and 9, comment: "standing in for Default, which has none (0134)" becomes "standing in for Default, which has only B (0227)".
- `doc/log/2026-10-04.md`, appended at the end, never rewriting earlier paragraphs:

```
## A crouch control on touch (0227)

Tags: touch, input, sneak, hud

- Default gains one layout button, B (`EAST`, Sneak, `double_tap_toggles`), since the pod's airlock needs crouching and Sneak had no touch control since 0134. A layout button, not a HUD button: a crouch is held through a crawl while the other thumb steers, which needs the 0120 latch; a stick gesture would be a touch code path of its own.
- It stands at `[60, 320]` from the bottom right, 100 across, not at the preview's `[130, 300]` size 120: the preview covered the placement editor's grid on the phone and at 16:9, and a layout button takes a finger before a HUD button. The only room clear of the row and the grid at every audited size at a thumb's height is the strip along the right edge, narrowest at 3:2 (129 reference px from the edge to the grid), so the circle shrank to fit it with 19 px to spare.
```

- `doc/code_map.md`: no change (no file added).

### Save and settings

None. Default is content (`data/touch_overlay.sjson`, reloaded with the tables); no save, record, hash or settings field changes. User layouts in the configuration directory are untouched: a layout saved before this item keeps its elements (no B) until the user resets it, and Reset to Default copies Default's elements as today (`reset_touch_layout`), now with B. The latch state already resets on a data reload (`release_touch_latches`), so the reload that adds the element needs nothing.

### Hand-back check

- A list that grows, a long string: none (one fixed element, label "B").
- The smallest audit size: `test_no_touch_overlay_element_covers_a_hud_touch_button` runs every `UI_AUDIT_SIZES` entry, 960 by 540 included, with the arithmetic above.
- Tests never touch the machine's state directory: every new test parses the shipped file through `#load` and works in memory.
- Frees memory a frame draws from, file writes, start-up loads, parsed numbers, save layouts, shared budgets, obsolete audit cases: not touched. The UI audit's editor cases now show Default with B in the draft (`ui_audit_test.odin` 669, 785); no audit case is made obsolete.

### Open questions answered

- Element order: last, after the look, so tests and code that find the stick and look by `zone_element` and `layout_element` see no shift, and `button_at`'s "last listed wins" has one button to pick.
- Size: 100, not 120. A 120 circle fits the strip only centred 68 from the edge (8 px to the edge, 1 px to the grid at 3:2). 100 is still larger than the HUD's touch buttons (80 at UI scale 1).
- Label: "B", as the Controls name it and as GameNative's layout drew it. Layout labels are data drawn as written, so no string key is added.
- In the placement editor B stays Sneak (one meaning, Controls) and does not cover the editor's grid.

### Questions for the main agent

- The item and the task name "the touch column of the bindings table" in `doc/input.md`; the table (Gamepad, three columns: input, world, menus) has none. The specification puts the touch sentence under Hold or toggle and in the placement editor table's Touch row instead. Approve, or name the place.
- The preview the user crawled with was 120 across at `[130, 300]`; B moves 70 px nearer the edge and 20 px higher and shrinks to 100. Worth naming to the user with the play build, since the thumb learned the old place.

### Commands (implementer, in the item's worktree)

- `taskset -c 8-15 nice -n 10 ./build.sh check`
- `taskset -c 8-15 nice -n 10 ./build.sh check-android`
- `taskset -c 8-15 nice -n 10 ./build.sh test`
- `taskset -c 8-15 nice -n 10 python3 tools/check_docs.py`
- `taskset -c 8-15 nice -n 10 python3 tools/code_graph.py --check doc/code_map.md`

### Decisions at the approval (main agent, 2026-10-04)

1. The element as specified, `position = [60, 320]`, `size = [100, 100]`, not the preview's `[130, 300]` at 120: the preview covers the placement editor's grid on the phone and at 16:9, and a layout button takes a finger before a HUD button, so the editor's Nudge_Right and Cancel would go to B. The strip along the right edge is the one place clear of the row and the grid at every audited size, so the circle shrinks to fit it. The user is told with the play build that B moved 70 px nearer the edge and 20 px higher and shrank, since their thumb learned the preview's place.
2. `doc/input.md` has no touch column in the bindings table (the item was wrong); the touch sentence goes under Hold or toggle and into the placement editor table's Touch row, as the specification says.
3. The new covering test runs every `UI_AUDIT_SIZES` entry plus the phone at the UI scale range's ends and 1280 by 720, against the hotbar, the row and the grid whether shown or not: approved, the stricter check costs nothing and the grid's buttons are HUD buttons the user reaches while B is drawn.
4. No new string key, no save or settings change, no code_map change: approved.
