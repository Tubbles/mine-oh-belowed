# 0233: Interact moves from A to X, A jumps alone

Status: landed (2026-10-04, "Move Interact from A to X, A jumps alone (0233)", 3949848, installed the same day; the review of the same day weighed, its nits (long comment lines, a full crate in the input doc) fixed in the landing amend, in `.claude/worktrees/0233` on `item/0233` from 0231's pass A snapshot a7aae5f, the specification approved the same day with the decisions below; from the user: "Do we still have 'A to interact' still left bound for anything? In that case i want it moved to X. A shall be solely for jumping"; today A and the L4 paddle carry Jump and Interact, Interact winning on a power switch, a launch pad and a schematic crate (`without_interact_jump`, `without_field_interact_jump`); after 0231, which takes the hatch off Interact)

## Goal

On the gamepad A jumps and nothing else in the world. Interact lives on X beside Open_Inventory, and what X does is decided by the aimed thing, one action per target, so a press never does two things and never jumps.

## Controls

Control design (main agent, 2026-10-04). The world layer only; menus are unchanged (A confirms, X is the context action, as on every pad).

- **Bindings** (`data/bindings.sjson`): Interact leaves `SOUTH` and `LEFT_PADDLE1` and is bound to `WEST` in the world context; `MISC2` (the right trackpad's click) keeps Interact, since it carries nothing else; Jump keeps `SOUTH` and `LEFT_PADDLE1`; Open_Inventory keeps `WEST` in both contexts; Confirm keeps `SOUTH` in the menu context. Keyboard and mouse are unchanged (Space jumps, F interacts, E opens).
- **X in the world, one action per aimed target**: a power switch turns (Interact, the lever; its panel is the pole panel with the network's name and the same toggle, reached from any pole of the network or with E on the keyboard); a schematic crate is taken and read (Interact); a launch pad opens its panel (Open, where Assemble and Launch are; Interact's direct launch from the pad goes, so a ready rocket can still be inspected); any other machine with a panel opens it (Open, as today); nothing aimed, or a thing with neither, opens the inventory (as today). The design stage picks the seam: either the presentation's routing (`route_open_inventory_press`, which turns Open_Inventory into Open_Aimed on a panel) leaves the press as Interact on a switch and a crate, or the simulation's `resolve_interact` and `interact_on_field` check the lever and the crate before Open_Aimed; the outcome per target above is what the tests assert.
- **A jumps always**: `without_interact_jump` and `without_field_interact_jump` go, since Jump no longer shares a control with Interact; a press on a switch or a pad jumps as anywhere.
- **What every existing control still does**: B Sneak, Y Rotate_Building, the D-pad, the bumpers, the triggers (R2 Mine, L2 Place and Use_Item), the trackpads, the paddles L5 and R5, View and Menu: unchanged. The right trackpad's click stays Interact (a lever turn or a crate take with the pad, as today); on a launch pad it does nothing, since the launch is the panel's.
- **Touch**: the tap on a switch or a crate presses `WEST` as on any panelled machine (today `tap_interact_control` presses `SOUTH` there); the design stage says whether the look element's `tap_interact_control` key stays for user layouts (set to `WEST` in Default) or goes with its loader line and the tap always presses `tap_open_control` where the target takes Interact or has a panel.
- **HUD**: the Interact glyph follows the binding and shows X; a switch shows Turn alone (today Turn beside Open, two hints on what are now one control), a pad Open alone, a crate Take alone; the inventory hint shows X as today.
- **The placement editor**: A Jump, unchanged; its table in `doc/input.md` already says so.

## Change

- `data/bindings.sjson` and its header comment; `src/player.odin` (`resolve_interact`, `without_interact_jump`, `entity_answers_interact`, `entity_takes_interact`), `src/simulation_field.odin` (`interact_on_field`, `without_field_interact_jump`), `src/input_actions.odin` (`route_open_inventory_press`) as the design stage decides; `src/hud.odin` (the switch's double hint); the touch tap routing (`tap_control`, `touch_overlay.odin`) and `data/touch_overlay.sjson`'s look element.
- Docs: `doc/input.md` (the bindings table rows A, X and L4, the Interact paragraphs, the editor table's A row), `doc/touch_overlay.md` (the tap line), `doc/ui.md` (line 59's tap routing), `doc/hud.md` (the hints), `doc/content.md` (the switch and the pad lines), `doc/log/2026-10-04.md`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the shipped bindings give `SOUTH` Jump and Confirm only, `WEST` Open_Inventory and Interact in the world, `LEFT_PADDLE1` Jump only, `MISC2` Interact; aimed at a power switch an X press turns it and opens no panel, in the block world and on the field; aimed at a launch pad with a rocket ready an X press opens the panel and launches nothing; aimed at a schematic crate an X press takes it; an A press aimed at a switch jumps and turns nothing; the glyph bar on a switch shows Turn once; the touch tap on a switch presses `WEST`; the existing Open_Aimed tests pass unchanged.
- The couch: turn a switch with X, open a furnace with X, jump with A in front of a switch; the phone: tap a switch.

## Specification (design, 2026-10-04)

Designed against 0231's approved specification and its worktree (`.claude/worktrees/0231`, pass A). This item's worktree is made from 0231's tip, so these 0231 hunks are already there and are built on, never redone or undone: `entity_answers_interact` without the hatch (`player.odin`), `interact_on_field` without the `pod_airlock_refuses_opening` and `toggle_hatch` branches and its new comment (`simulation_field.odin`), `without_field_interact_jump`'s 0231 comment, the HUD's hatch case and the `field_target_hatch*` procedures gone (`hud.odin`), and 0231's edits of `doc/input.md` lines 108 and 109, `doc/hud.md`'s glyph bar row and `doc/content.md`'s hatch Interact bullet. Where this item replaces one of those lines whole, the replacement below already carries 0231's facts.

### The seam (decided): the presentation's routing

`route_open_inventory_press` decides what an X press is, before the frame reaches the session or the UI. Why there and not in the simulation:

- The crate has no panel, so today's routing leaves Open_Inventory in the frame and the UI opens the inventory on the same press that takes the crate. Only the presentation can keep the inventory shut; a simulation order cannot.
- On the keyboard Open_Inventory (E) and Interact (F) are separate keys, and the Controls section keeps E opening a switch's panel. The routing sees both actions in one frame only when one control carries both (the gamepad's X, the touch tap), so a rule "both pressed at once on a target that takes Interact: the press is Interact's" leaves E alone.
- The routed frame is what the input record carries (`Record_Input.pressed`, `just_pressed` are the whole `Action_Set`), as Open_Aimed is today: every peer's tick sees Interact without Open_Aimed or Open_Inventory, so the simulation stays deterministic and online needs nothing new. Online the press lands a window later on whatever the player aims at then, as Open_Aimed already does.
- The simulation's order (Open_Aimed before Interact in `resolve_interact` and `interact_on_field`) stays as it is: a frame never carries both on a switch any more, and on a launch pad or a furnace Open_Aimed wins and Interact does nothing (a pad no longer answers Interact).

`src/input_actions.odin`:

```odin
// Open_Inventory means "open" (0194): a press while no screen is open
// and a machine with a panel is aimed (aims_at_panel, decided from the
// target the HUD shows) becomes the simulation's Open_Aimed instead, so
// the UI opens no inventory; any other press stays Open_Inventory and
// the simulation opens nothing. A press that is Interact's too in the
// same frame (the gamepad's X, the touch tap, 0233) on a target that
// takes Interact (aimed_takes_interact: a power switch, a schematic
// crate) is Interact's alone: Open_Inventory leaves the frame, so the
// switch turns, the crate is taken and nothing opens.
route_open_inventory_press :: proc(frame: Input_Frame, world_blocked, aims_at_panel, aimed_takes_interact: bool) -> Input_Frame {
	result := frame
	if world_blocked || .Open_Inventory not_in frame.just_pressed {
		return result
	}
	if aimed_takes_interact && .Interact in frame.just_pressed {
		result.just_pressed -= {.Open_Inventory}
		return result
	}
	if !aims_at_panel {
		return result
	}
	result.just_pressed -= {.Open_Inventory}
	result.just_pressed += {.Open_Aimed}
	return result
}
```

Only `just_pressed` changes, as today (`pressed` keeps Open_Inventory; the UI reads the edge, `ui_input.odin` `open_inventory = .Open_Inventory in just`).

Outcome per target for the gamepad's X (Open_Inventory and Interact both pressed): a power switch (has a panel, takes Interact): Interact alone, the tick turns it (`Toggled_Switch`), no panel. A schematic crate (no panel, takes Interact): Interact alone, `resolve_use_item` takes it, no inventory. A launch pad (has a panel, no longer takes Interact): Open_Aimed and Interact, `resolve_interact` opens the panel and returns; nothing launches anywhere (the launch path from Interact is gone, below). Any other panelled machine: Open_Aimed (and an Interact that acts on nothing). Nothing aimed or a thing with neither: Open_Inventory stays, the inventory opens. The field: the same routing, `aimed_entity` reads the field's frame cell.

`src/player.odin`, beside `aims_at_panel`, the procedure moved from `touch_overlay.odin` (`touch_tap_target`, same body, renamed since the loop uses it now; its two callers, `touch_interaction_frame` in `touch_overlay.odin` and `test_a_tap_on_the_field_turns_a_switch_and_opens_a_furnace`, take the new name):

```odin
// What the aimed thing calls for, read as the HUD shows the target
// (aimed_entity): Interact (entity_takes_interact) and a panel the
// inventory binding opens (aims_at_panel, 0194). The frame's routing of
// the inventory binding (route_open_inventory_press) and the touch tap
// (tap_control) read it.
aimed_target_calls_for :: proc(entities: ^Entities, machines: Machine_Registry, block_target: Entity_Handle, field_target: Frame_Raycast_Hit) -> (takes_interact, has_panel: bool)
```

`src/loop.odin`: `viewport_aims_at_panel` is replaced by

```odin
// What the viewport's player aims at calls for (aimed_target_calls_for),
// read from the target its HUD shows: the confirmed player's raycast in
// the block world, the predicted field player's frame cell on the field.
// While the placement editor is anchored it takes Interact (0215), so
// no target takes Interact there and X stays Open_Inventory.
viewport_aimed_target :: proc(state: ^Frame_State, viewport: Viewport) -> (takes_interact, has_panel: bool)
```

returning `false, false` when `!viewport_player_ready`, else `aimed_target_calls_for(...)` with `takes_interact && !viewport.interaction.placement_editor.anchored`. `update_frame_world`'s first loop: `takes_interact, has_panel := viewport_aimed_target(state, viewport)`, then `route_open_inventory_press(viewport.interaction.input, viewport_world_blocked(viewport), has_panel, takes_interact)`. Its comment: "an Open_Inventory press aimed at a panel turned into Open_Aimed (0194), or dropped where the same press is Interact's (0233), the guards, ...".

### Bindings (`data/bindings.sjson`)

The world gamepad block's first four lines become exactly (WEST before MISC2, so Interact's glyph is X, `first_binding_on_device`):

```
	{action = "Jump" device = "gamepad" control = "SOUTH" context = "world"}
	{action = "Jump" device = "gamepad" control = "LEFT_PADDLE1" context = "world"}
	{action = "Interact" device = "gamepad" control = "WEST" context = "world"}
	{action = "Interact" device = "gamepad" control = "MISC2" context = "world"}
```

The lines `Interact SOUTH` and `Interact LEFT_PADDLE1` go. Open_Inventory `WEST` `both`, Confirm `SOUTH`, `LEFT_PADDLE1`, `MISC2` in `menu`, Context_Action `WEST` `menu`, keyboard `F` Interact and `E` Open_Inventory: unchanged. The header's sentences from "One control may carry" to "(route_open_inventory_press in src/input_actions.odin)." become (wrapped at the file's width):

```
// One control may carry several actions, a world and a menu meaning: A is
// Jump and Confirm, X is Open_Inventory and Interact in the world and
// Context_Action in menus (work item 0233). Open_Inventory opens the
// targeted machine's panel instead of the inventory, and on a target
// Interact acts on (a power switch, a schematic crate) a press of both is
// Interact's alone (route_open_inventory_press in src/input_actions.odin).
```

`Action`'s comment on Interact (`input_actions.odin`): "Turns the targeted power switch like a lever and takes a schematic crate's schematic (resolve_use_item). X on a gamepad beside Open_Inventory, where the press is Interact's alone on such a target (route_open_inventory_press, 0233); the right pad's click; F." The Open_Aimed comment keeps its text.

### The removals and what replaces each call

- `without_interact_jump` (`player.odin`) goes. `resolve_interact` becomes `resolve_interact :: proc(player: ^Player, entities: ^Entities, machines: Machine_Registry, input: Input_Frame) -> Player_Events` (no frame returned: it no longer changes one): Open_Aimed on a panel opens it (`{.Open_Machine}`), else Interact just pressed turns a switch (`{.Toggled_Switch}`), else `{}`; the `request_launch` branch goes. Comment: "Open_Aimed (an Open_Inventory press the presentation routed, 0194) opens the targeted entity's panel; Interact turns a power switch like a lever. A launch pad launches from its panel's Launch alone (0233)." `tick_player`: `input := with_sneaking(frame, player.sneaking)` then `events := resolve_interact(player, &world.entities, content.machines, input)`. `predict_player_motion`: `input := with_sneaking(frame, player.sneaking)`.
- `without_field_interact_jump` (`simulation_field.odin`) goes. `interact_on_field` becomes `interact_on_field :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, frame: Input_Frame) -> Player_Events`: the panel first, then `.Interact in frame.just_pressed && toggle_power_switch(...)`; the `request_launch` branch goes. Comment: "Open_Aimed on a frame cell whose machine has a panel opens it, as the block world's does (resolve_interact, 0194); Interact turns a power switch there (a hatch takes no Interact since 0231, a launch pad launches from its panel since 0233)." `tick_field_session_player`: `resolved := with_sneaking(frame, player.sneaking)` then `events := interact_on_field(state, content, index, resolved)`. `predict_field_player_motion` (`lockstep.odin`): `resolved := with_sneaking(frame, player.sneaking)`; its comment drops "Interact's jump suppression on a frame's switch or launch pad,".
- `entity_answers_interact` goes (its other callers were the two removed procedures; after 0231 and this item it would be `entity_is_power_switch` alone). `entity_takes_interact` becomes `return entity_is_power_switch(entities, machines, handle) || schematic_crate_takes_interact(entities, handle)`, comment: "Whether Interact acts on the entity: a power switch it turns or a schematic crate it takes (resolve_use_item). On such a target the X press is Interact's alone (route_open_inventory_press, 0233)."
- `Player_Event.Launch_Requested` goes (Interact was its only source; the panel's Launch, `apply_launch_command`, sends none): the enum value and its comment (`player.odin`), the `.Launch_Requested` case of `show_simulation_events` (`loop.odin`), the `.Launch_Requested in events` term in `tick_player` and in `tick_field_session_player`'s set, and the string `toast_rocket_launch` in `data/strings/en.sjson` (no other reference). Events are transient (`Simulation_State.events`), never saved, recorded or hashed. `request_launch`'s comment (`launch_pad.odin`): "The Launch button: served by apply_launch_requests."
- `resolve_use_item` (`schematic.odin`): on a crate it takes Interact alone, `result.pressed -= {.Interact}` and `result.just_pressed -= {.Interact}` (no longer Jump: A jumps at a crate). `schematic_crate_takes_interact`'s comment: "Interact on a schematic crate takes its schematic; an empty one takes the press and does nothing."

### The touch tap (decided: the key is read and ignored)

The tap presses `tap_open_control` wherever the target takes Interact or has a panel, and `tap_interact_control` stops being a control. A user layout always names the key (the editor's writer, `touch_overlay_element_text`, wrote it into every saved layout, with `SOUTH`), and the loader is strict, so removing the key would refuse every user file and lock it. Keeping it as a control would keep those saved `SOUTH` values, which jump now. So:

- `Touch_Overlay_Element_Entry.tap_interact_control: string` stays, commented "Read and ignored since 0233 (the tap presses tap_open_control where Interact acts), so a layout saved before it loads." No log line: the player loses nothing (the decision log names it).
- `Touch_Overlay_Element.tap_interact_control` goes, with its line in `resolve_touch_overlay_look`'s `controls` list (so an empty or unknown value is no error), its line in `touch_overlay_element_text` (a saved layout drops the key at the next save), and the element comment becomes "the hold presses hold_control, a tap tap_open_control (Open_Inventory's, 0194) on a target that takes Interact or has a panel, which the frame routes (route_open_inventory_press: Interact on a switch or a crate, the panel on another machine), else tap_place_control."
- `tap_control :: proc(look: Touch_Overlay_Element, target_takes_interaction, target_has_panel: bool) -> Touch_Overlay_Control` keeps its signature; body: `if target_takes_interaction || target_has_panel { return look.tap_open_control }`, then `return look.tap_place_control`. Comment: "Open_Inventory's control on a target that takes Interact or has a panel, which the frame routes into turning a switch, taking a crate or opening a panel (route_open_inventory_press, 0194, 0233), else Place's, through the bindings like the buttons."
- `Touch_Interaction_Frame` keeps both fields; its comment's "target_takes_interaction: ... (entity_takes_interact)" names `aimed_target_calls_for`.
- Comments: the file header's "a tap (Interact or Place through gamepad controls ...)" becomes "a tap (X or Place through gamepad controls ...)"; `Touch_Tap_Phase`'s "(Interact's SOUTH or Place's LEFT_TRIGGER, chosen by that target)" becomes "(Open_Inventory's WEST or Place's LEFT_TRIGGER, chosen by that target)"; `apply_touch_overlay_jump`'s reason "SOUTH is Interact too, and Interact wins over Jump on a power switch or a launch pad (resolve_interact), so a jump tap through the gamepad would turn a switch under the view's centre." becomes "the Jump action itself, aimed nowhere (0134, chosen while SOUTH was Interact too; 0233 left it)."
- `data/touch_overlay.sjson`: the look element loses `tap_interact_control = "SOUTH"`; the header's look paragraph: "Mine), tap_interact_control (pressed by a tap on a target that takes Interact), tap_open_control (work item 0194, pressed by a tap on another machine with a panel: Open_Inventory's WEST, which the game turns into opening that machine; WEST when left out)" becomes "Mine), tap_open_control (work items 0194, 0233, pressed by a tap on a target that takes Interact or has a panel: Open_Inventory's WEST, which the game turns into turning a switch, taking a schematic crate or opening that machine; WEST when left out; tap_interact_control, written before 0233, is read and ignored)", and "presses the Jump action itself instead, aimed nowhere (not SOUTH, which is Interact too)" becomes "presses the Jump action itself instead, aimed nowhere". Wrapped at the header's width.

### The HUD

Today aimed at a switch the bar shows Interact "Turn" (`aimed_glyph_hints`) and Inventory "Open" (`world_glyph_hints`, `inventory_hint_key`): on the gamepad both are X now. A full crate shows Interact "Take" and Inventory "Inventory": both X too. A launch pad shows Inventory "Open" only (no Launch hint exists; checked, nothing to remove).

The rule: where the aimed thing takes Interact and Interact's glyph is the Inventory's on the active device, the bar shows the aimed hint alone (no Open, no Inventory), since the press is Interact's there. With the keyboard (F and E) both still show, which is right: E opens the switch's panel.

- `world_glyph_hints :: proc(screen_context: Screen_Context, hud: Hud_Context, interact_shares_inventory_control := false) -> (hints: []Glyph_Hint, kept: int)`: `merged := interact_shares_inventory_control && hud_target_takes_interact(screen_context, hud)`; `opens := !merged && inventory_hint_key(screen_context, hud) == "hint_open"`; the tail's Inventory hint only `if !opens && !merged`. Comment gains: "Where the aimed thing takes Interact on the Inventory's control (the gamepad's X, 0233) neither Open nor Inventory shows: the press is Interact's there." The default keeps the existing callers in `hud_test.odin` and `ui_audit_test.odin` unchanged.
- New `hud_target_takes_interact :: proc(screen_context: Screen_Context, hud: Hud_Context) -> bool` beside `inventory_hint_key`: `entity_takes_interact(&screen_context.world.entities, screen_context.machines, aimed_entity(screen_context.player.target.entity, hud_field_player(screen_context, hud).frame_target))`. Comment: "The aimed thing takes Interact (a switch, a crate), as the frame's routing reads it."
- `draw_hud`: `hints, kept := world_glyph_hints(screen_context, hud, glyph(state, .Interact) == glyph(state, .Inventory))` (a `Glyph` compares with `==`, as the audit test already does).
- The Interact glyph follows the binding: `glyph` reads `first_binding_on_device` on the effective bindings (`ui_widgets.odin`); nothing in `src/` outside the tests names `.Button_South` for Interact (checked: `ui_theme.odin`'s enum and name table and `ui_widgets.odin:968`, the control name mapping). The test table `default_gamepad_glyph_icons` in `ui_theme_test.odin` pins `.Interact = .Button_South` and changes to `.Button_West`.
- An empty crate takes Interact (unchanged predicate) and shows no Take, so on the gamepad its bar shows neither Take nor Inventory and X does nothing there (see Decisions).

### The right trackpad's click (MISC2, Interact alone)

After the change: on a power switch it turns it; on a full schematic crate it takes the schematic (an empty one: nothing); on a launch pad nothing (the launch is the panel's); on any other machine nothing (no Open_Inventory on it, so no panel). In menus Confirm, unchanged.

### Tests

New:

1. `test_the_shipped_bindings_put_interact_on_x_and_leave_a_to_jump` (`bindings_test.odin`): from `shipped_default_bindings`, the SDL3 tables give `SOUTH` exactly `{.Jump, .Confirm}`, `LEFT_PADDLE1` `{.Jump, .Confirm}`, `WEST` `{.Open_Inventory, .Interact, .Context_Action}`, `MISC2` `{.Interact, .Confirm}`; the raylib tables `RIGHT_FACE_DOWN` `{.Jump, .Confirm}` and `RIGHT_FACE_LEFT` `{.Open_Inventory, .Interact, .Context_Action}`; and the first gamepad binding of Interact (`first_binding_on_device`, `.Gamepad`, `.Sdl3` and `.Raylib`) has control `"WEST"`.
2. A helper `shipped_gamepad_press :: proc(t: ^testing.T, button: sdl.GamepadButton) -> Input_Frame` in `bindings_test.odin` (which imports `vendor:sdl3`): the SDL3 tables of the shipped bindings, a `Raw_Gamepad{connected = true, button_count = RAW_GAMEPAD_BUTTON_CAPACITY}` with that button down, `gamepad_button_actions`, returned as `pressed` and `just_pressed`. Tests 4, 5 and 7 use it.
3. `test_an_x_press_on_a_target_that_takes_interact_is_interacts_alone` (`input_actions_test.odin`): a frame with `{.Open_Inventory, .Interact}` pressed and just pressed: `(false, true, true)` (a switch) gives `just_pressed == {.Interact}`; `(false, false, true)` (a crate) `{.Interact}`; `(false, true, false)` (a pad, a furnace) `{.Open_Aimed, .Interact}`; `(false, false, false)` unchanged; `(true, true, true)` (a screen open) unchanged. Open_Inventory alone (E) with `(false, true, true)` gives `{.Open_Aimed}` (E opens a switch's panel); Interact alone (F, the pad click) is unchanged.
4. `test_x_turns_a_switch_and_opens_a_furnace_and_a_jumps_at_a_switch` (`entity_test.odin`, replacing `test_open_aimed_opens_an_entity_and_interact_turns_a_switch`, same world and aim): each press built with `shipped_gamepad_press` and routed with `aimed_target_calls_for(&world.entities, content.machines, players[0].target.entity, {})`. At the furnace X gives `{.Open_Machine}` and `open_machine == handle`. At the switch (in the furnace's place) X gives `{.Toggled_Switch}`, the switch's `on` flips, `open_machine == NO_ENTITY`, `velocity.y <= 0`; A (`.SOUTH`) on the ground gives `{}`, `on` unchanged, `velocity.y > 0`. Looking away X gives `{}` and Open_Inventory stays in the routed frame.
5. `test_the_field_turns_a_switch_on_x_and_jumps_on_a` (`simulation_field_test.odin`, replacing `test_the_field_opens_a_panel_on_open_aimed_and_turns_a_switch_on_interact`, same session, frame, furnace and switch): the `without_field_interact_jump` lines go; Open_Aimed at the furnace opens it and counts one world action (kept); Interact alone at the furnace gives no `Open_Machine` or `Toggled_Switch`; at the switch the routed X (`shipped_gamepad_press(t, .WEST)` through `route_open_inventory_press` with `aimed_target_calls_for(entities, machines, NO_ENTITY, frame_target)`) has no Open_Inventory or Open_Aimed, and the tick gives `Toggled_Switch`, no `Open_Machine`, `open_machine == NO_ENTITY`, `on` flipped; A (`{.Jump}`) at the switch gives no `Toggled_Switch` and `on` unchanged.
6. `test_x_on_a_ready_pad_opens_its_panel_and_launches_nothing` (`launch_pad_test.odin`, replacing `test_interact_launches_a_ready_rocket`): `entity_takes_interact` is false on the pad; with the rocket ready and cargo in, `press({.Open_Aimed, .Interact})` (what the routing makes of X there) gives `{.Open_Machine}` and `!pad.launch_requested`; `press({.Interact})` (the pad click) gives `{}` and `!pad.launch_requested`; then `request_launch` (the panel's Launch path) and `apply_launch_requests(&test.world, &test.records, 99)` give `Launching` and the shipment at tick 99, as the old test's tail.
7. `test_use_item_resolution` (`schematic_test.odin`): the crate part becomes: `press({.Interact})` takes the schematic with `input.pressed == {}`; `press({.Jump, .Interact})` on the empty crate gives `NO_ITEM` and `input.pressed == {.Jump}` (A jumps at a crate); and before them, X routed at the crate (`route_open_inventory_press(shipped_gamepad_press(t, .WEST), false, false, true)`) has `just_pressed == {.Interact}` (no Open_Inventory: the inventory stays shut) and through `resolve_use_item` yields the schematic. The comment: "Interact on a crate takes its schematic in one press; A jumps there."
8. `test_x_shows_one_hint_on_a_switch_and_a_crate` (`hud_test.odin`): `use_shipped_strings`; a `make_test_content()` world with a power switch aimed (`player.target`), `Screen_Context{content = content, world = &world, player = &player}`: `world_glyph_hints(..., true)` buttons are `{.Interact, .Pause}` with `hints[0].label == "Turn"`; with `false`, `{.Interact, .Inventory, .Pause}` and the Inventory label "Open". A full crate built as `test_use_item_resolution` builds it (`make_drill_world`, `register_crate_sites`, `place_pending_crates`), aimed: with `true` `{.Interact, .Pause}` (Take); with `false` `{.Interact, .Inventory, .Pause}` (Take, Inventory). A furnace aimed with `true`: `{.Inventory, .Pause}` with "Open" (no Interact hint).
9. `test_a_layout_saved_with_tap_interact_control_loads_and_taps_x` (`touch_overlay_test.odin`): `parse_touch_layouts_file` on an in-memory user file whose one layout's look names `tap_interact_control = "SOUTH"` and no `tap_open_control` gives no problem; `tap_control(look, true, false)` and `tap_control(look, false, true)` are `{button = .WEST}`, `tap_control(look, false, false)` the place control; `touch_overlay_element_text(look)` holds no `tap_interact_control`. Also `tap_interact_control = "NONSENSE"` loads (ignored).

Changed:

- `test_default_bindings_equal_the_former_tables`: `reference_raylib_buttons` loses `{.RIGHT_FACE_DOWN, .Interact}` and gains `{.RIGHT_FACE_LEFT, .Interact}`; `reference_sdl3_buttons` loses `{.SOUTH, .Interact}` and `{.LEFT_PADDLE1, .Interact}` and gains `{.WEST, .Interact}`; raylib's unsupported count 12 becomes 11, the comment "Paddles (8), the right pad click (2) and the left pad."
- `test_an_open_inventory_press_aimed_at_a_panel_becomes_open_aimed`: each call gains the trailing argument `false`; its assertions are unchanged.
- `test_a_tap_presses_interact_on_a_machine_and_place_elsewhere` becomes `test_a_tap_presses_x_on_a_machine_and_place_elsewhere`: `output.buttons[int(sdl.GamepadButton.WEST)] == takes_interaction`; through the bindings `.Interact in actions` and `.Open_Inventory in actions` equal `takes_interaction`.
- `test_the_tap_and_hold_controls_come_from_the_layout`: the `tap_interact_control` line becomes `shipped.elements[look].tap_open_control == {button = .WEST}`.
- `touch_tap_into_tick`: `inputs.target_takes_interaction, inputs.target_has_panel = aimed_target_calls_for(&world.entities, content.machines, target, {})` and the routing gets both. The tests using it (the switch turns with no `Open_Machine`, the furnace opens, the ground places) pass unchanged.
- `test_a_tap_on_the_field_turns_a_switch_and_opens_a_furnace`: `aimed_target_calls_for` and the routing's fourth argument from it.
- `test_a_jump_tap_jumps_with_a_machine_under_the_views_centre`: the comment's "where the gamepad's A would turn it" becomes "as A does since 0233"; the body is unchanged.
- `test_the_hint_beside_a_machine_shows_the_inventory_glyph` (`ui_audit_test.odin`, the UI audit case that shows the switch's two hints, see Hand-back): `draw_hud` now passes the shared glyph flag. Per device and target: the drill shows Open with `glyph(.Inventory)` and no Turn; the switch shows Turn with `glyph(.Interact)`, and Open with the keyboard only (on the gamepad `glyph(.Interact) == glyph(.Inventory)`, asserted, and no Open). The size and text scale loop runs with `.Keyboard_Mouse`, where Turn (F) and Open (E) both still show, asserting both fit inside the safe area as today; after it, one gamepad pass at the smallest audited size and the largest text scale asserts Turn shown and Open not. The comment says so.
- `default_gamepad_glyph_icons` (`ui_theme_test.odin`): `.Interact = .Button_West`.

Lockstep and records: no test covers Open_Aimed through the record or the network today (checked: `lockstep_test.odin` and `session_network_test.odin` name neither Open_Aimed nor Interact). `Record_Input` carries the routed `Action_Set` whole, so the routing's result crosses the network as Open_Aimed does; no lockstep test is added. `simulation_arrival_test.odin`'s record (Jump and Interact pressed) is unaffected: nothing it aims at takes Interact after 0231.

### Docs

- `doc/input.md`, Bindings: the bullet "One control carries a world and a menu meaning. A is Jump, Interact and Confirm; ..." (as 0231 leaves it) becomes: "One control carries a world and a menu meaning: A is Jump and Confirm, X Open_Inventory and Interact in the world and the context action in menus (0233). A jumps everywhere." The bullet "On a power switch Interact turns it ..." becomes: "Interact turns a power switch like a lever, in the block world and on the field, and takes a schematic crate's schematic. It opens no panel and launches nothing: a launch pad launches from its panel (0233). On the pod's hatch it does nothing (0231: the doors open and shut on their own, [content.md](content.md), Hatches)." The Open_Inventory bullet gains after "the simulation sees nothing.": "A press that is Interact's in the same frame (the gamepad's X, the touch tap) on a target that takes Interact (`entity_takes_interact`: a power switch, a schematic crate) is Interact's alone: Open_Inventory leaves the frame, so the switch turns or the crate is taken and nothing opens (0233, `viewport_aimed_target`; not while the placement editor is anchored, which takes Interact). The keyboard's E and F are separate keys, so E opens a switch's panel (the pole panel with the network's name and the same toggle, also reached from any pole of the network)." The Place and Use_Item bullet's "and Interact on a schematic crate takes and reads it in one press" stays.
- `doc/input.md`, Gamepad table: Right trackpad's world cell "Look as a mouse surface. Click: Interact (turns a switch, takes a crate's schematic; nothing on a launch pad)"; A "Jump"; X "Open_Inventory and Interact, one action per aimed target: a power switch turns, a schematic crate is taken, a machine with a panel (a launch pad included) opens it, else the inventory opens"; L4, R4 "Jump, Sneak".
- `doc/input.md`, The placement editor: "and Interact (A is Jump alone)" becomes "and Interact (so X there is Open_Inventory alone)". The editor table's A row (Jump) is already right.
- `doc/touch_overlay.md`: line 59's "then presses `tap_interact_control` (A, Interact) when that tick's target takes Interact (`entity_takes_interact`: a power switch, a launch pad or a schematic crate), `tap_open_control` (X, Open_Inventory, 0194; WEST when a layout leaves it out) on another machine with a panel (`aims_at_panel`), which the frame routes into opening that machine as it does the binding's press ([input.md](input.md))," becomes "then presses `tap_open_control` (X, Open_Inventory, 0194; WEST when a layout leaves it out) when that tick's target takes Interact (`entity_takes_interact`: a power switch, a schematic crate) or has a panel (`aims_at_panel`), which the frame routes as it does the binding's press: a switch turns, a crate is taken, a machine opens (0233, [input.md](input.md)),". Line 61's "It is an action, not `SOUTH`, since `SOUTH` is Interact too and would turn a switch under the view's centre." becomes "It is an action, not `SOUTH` (chosen while `SOUTH` was Interact too, 0134; kept by 0233)." Line 87's "a look without its three controls" becomes "a look without `hold_control` or `tap_place_control`", and the paragraph gains: "`tap_interact_control`, which layouts before 0233 carry, is read and ignored, so a saved layout still loads."
- `doc/ui.md`: nothing. It has no tap routing sentence (line 59 is blank; line 43, Open_Inventory closing screens, is unaffected). Checked.
- `doc/hud.md`, the glyph bar row: from "Beside a machine with a panel the Inventory glyph says "Open"" to the end of the hatch clause becomes: "Beside a machine with a panel the Inventory glyph says "Open", since that binding opens it (`inventory_hint_key`, 0194); a power switch adds the Interact glyph with "Turn", a full schematic crate "Take". Where the aimed thing takes Interact and Interact's glyph is the Inventory's (the gamepad's X, 0233) the bar shows that hint alone, with no Open or Inventory, since the press is Interact's there (`hud_target_takes_interact`); with the keyboard F and E both show. The pod's hatch offers nothing (0231: its doors follow the players)."
- `doc/content.md`: it has no switch or pad Interact line (checked). In the hatch bullet 0231 writes, "so the A press jumps there as on any other cell" becomes "so X there opens the inventory as on any other cell without a panel".
- `doc/fluids.md` line 60: "Interact turns a switch. The inventory binding opens its panel ([input.md](input.md))." becomes "Interact turns a switch (X on the gamepad, F); its panel opens from any pole of its network, or with E on the keyboard ([input.md](input.md))."
- `doc/architecture.md` line 43: "and Interact turns a switch or launches from a pad (`interact_on_field`)" becomes "and Interact turns a switch (`interact_on_field`; a pad launches from its panel, 0233)". Line 65: "Interact's jump suppression on a switch or a launch pad (`without_field_interact_jump`), " goes.
- `data/strings/en.sjson`: `settings_touch_interaction_tooltip`'s "with RT, LT and A" becomes "with RT, LT and X"; `toast_rocket_launch` goes.
- `doc/log/2026-10-04.md`: a section "## Interact moves from A to X (0233)" with a `Tags:` line (input, bindings, touch, hud, lockstep) and the decisions: the seam and why; one action per target; the touch key read and ignored with no log line; the launch from Interact and its toast gone; the HUD's device aware merge; the empty crate.
- `doc/code_map.md`: only what `python3 tools/code_graph.py --check doc/code_map.md` reports (the procedure moved from the touch overlay to `player.odin` and the loop's new call may shift a cross cluster count).

### Hand-back check lines that apply

- A UI audit case a change makes obsolete is replaced: `test_the_hint_beside_a_machine_shows_the_inventory_glyph` drew the switch's Turn and Open side by side on the gamepad. On the gamepad that state is gone by design; the two hints still show with the keyboard, so the fit loop moves to `.Keyboard_Mouse` and keeps drawing them at every size and text scale, and one gamepad pass asserts the single Turn (Tests, Changed).
- A start-up load the game itself can make fail falls back: every saved user touch layout names `tap_interact_control`; the loader keeps reading it, so none is refused or locked (test 9).
- A changed layout loads an old file: the user layouts file loses a key on the next save and still loads with it (test 9). No save, record or network layout changes (events are transient; `Record_Input` is unchanged).
- Tests never touch the state directory: test 9 parses from memory.
- Frame memory, file writes, number parsing, shared budgets, unbounded lists: not touched.

### Decisions on the open points

- The seam is the presentation's routing (above): the crate needs it, the keyboard needs it, and the record already carries its result.
- The routing's Interact rule needs Open_Inventory and Interact in the same frame, not a binding comparison: it holds for any user binding layout (two controls pressed at once on a switch also turn and do not open, which is harmless).
- The anchored placement editor reports no Interact target, so X there opens the inventory or the aimed panel as the editor's table says, instead of being swallowed.
- One routing procedure with a fourth argument rather than a second procedure: one place decides what the X press is; the existing Open_Aimed test changes by the argument alone.
- `touch_tap_target` moves to `player.odin` as `aimed_target_calls_for`, since the loop now reads it too.
- The touch key is read and ignored, not kept as a control (old saves hold `SOUTH`, which jumps now) and not removed (the strict loader would refuse every saved user file).
- The HUD's merge depends on the active device's glyphs, so the keyboard keeps E's Open on a switch, which the Controls section names as the way to the switch's panel.
- `Launch_Requested` and its toast go with the Interact launch; the panel's Launch never sent them.
- An empty schematic crate keeps taking Interact (unchanged predicate): X there does nothing and the bar shows no X hint, which agree. See question 1.
- `resolve_interact` and `interact_on_field` return events only, since they no longer change the frame.

### Questions for the main agent

1. An empty schematic crate: as specified X does nothing there (no inventory). The alternative is `schematic_crate_takes_interact` true only on a full crate, so X on an empty one opens the inventory and the bar shows Inventory; it changes a simulation predicate the touch tap and the routing read alike. Keep as specified, or take the alternative?
2. The HUD merge is device aware (keyboard shows F Turn and E Open on a switch). The Controls section reads "a switch shows Turn alone"; if that is meant for every device, `world_glyph_hints` drops the parameter and merges on `hud_target_takes_interact` alone, and the audit's fit loop keeps the gamepad. Which?

### Commands (implementer, in the item's worktree)

- `taskset -c 8-15 nice -n 10 ./build.sh check`
- `taskset -c 8-15 nice -n 10 ./build.sh check-android`
- `taskset -c 8-15 nice -n 10 ./build.sh test`
- `taskset -c 8-15 nice -n 10 python3 tools/check_docs.py`
- `taskset -c 8-15 nice -n 10 python3 tools/code_graph.py --check doc/code_map.md`

### Decisions at the approval (main agent, 2026-10-04)

1. The seam in the presentation's routing (`route_open_inventory_press` with `aimed_takes_interact`), the bindings lines with `WEST` listed first so the glyph shows X, `tap_interact_control` read and ignored so every saved user layout still loads, the removals (`without_interact_jump`, `without_field_interact_jump`, `entity_answers_interact`, the launch from Interact with `Launch_Requested` and its toast): approved as specified.
2. Question 1: a schematic crate takes Interact only while it holds a schematic; an empty one is a thing with neither, so X opens the inventory there instead of doing nothing (one action per target, and never a dead press). `schematic_crate_takes_interact` (or the predicate the implementer finds) reads the crate's content, and the crate test covers the empty crate.
3. Question 2: on the keyboard a switch keeps both hints, Turn for F and Open for E, since they are two keys; the one hint rule applies where both actions share a glyph (the gamepad's X, the touch tap), as specified.
