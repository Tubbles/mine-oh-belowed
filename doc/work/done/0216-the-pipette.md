# 0216: The pipette

Status: landed (2026-11-13, a843560d)

## Goal

The pipette picks what the player aims at into the hotbar: aimed at a placed machine, a foundation, a belt or a pole, a tap selects the hotbar slot holding that item, or moves one stack of it from the inventory into the selected slot when no slot holds it, so a player extending a line never opens the inventory to find the belt again. Since 0215 the control's hold opens the tools radial; the tap stays the pipette.

## Change

- `Pipette` pressed in the world with an entity aimed in reach (the HUD's target, as `Open_Aimed` reads it) becomes a player command carrying the aimed item (or the hotbar selection is local presentation when the slot already holds it; the design stage decides which parts are simulation and which are presentation, since the hotbar selection is simulation state today).
- Aimed at nothing placeable (terrain, a tree, a player): nothing, no toast.
- The item under the reticle is read from the entity's record (`item`), a foundation from the frame's cell record, a belt or a pole from the run.
- `doc/input.md` (Bindings) and the HUD's glyph hint when a pipette target is aimed.

## Controls

- None new: the `Pipette` action and its bindings exist; the tap (a release before the tools radial of 0215 shows) is the pipette.

## After 0278 (main agent, 2026-11-13)

The hotbar holds no stacks any more: a toolbar slot names a kind (done item 0278). So the tap selects the active toolbar's slot that names the aimed kind, and when none does it assigns the kind to the selected slot (`Toolbar_Assign_Command`), whether or not the inventory holds any; no stack moves. An absent kind then draws grey, which tells the player what to craft. "Hotbar" above reads as the active toolbar.

## Verify

- Tests: aiming at a placed furnace selects the slot holding stone furnaces, moves a stack from the inventory when no slot holds one, does nothing with an empty inventory and with nothing aimed; the command round trips.
- The couch: aim at a belt, tap, the belt is in hand.

## Specification (design, 2026-11-13)

Read off `main` at `6705810a`. No split. 0279 (implementing) edits `toolbar.odin`, so the pipette goes into a new file beside it and leaves `toolbar.odin` alone.

### Decisions

1. **A tick action, no command.** `Pipette` already reaches the simulation as one press in the input record: `tools_radial_world_frame` adds it to the world frame's `just_pressed` on a tap's release or on the radial's Pipette entry, and `Record_Input.just_pressed` carries it. The tick reads it where it reads the slot keys (`cycle_hotbar_slot`) and Drop_Stack, reads the aimed thing and selects or names on the spot (`apply_pipette`). Today the selection changes through both paths: the slot keys, L1, R1 and the wheel as actions the tick reads, the hotbar radial as `Hotbar_Slot_Command` (`hotbar_radial`). The pipette uses neither command. Why the tick: it reads `active_toolbar`, `selected_hotbar_slot` and the toolbars as they stand when the press applies, after that tick's commands and slot keys, where the frame would read the confirmed state, which lags the records still in the lockstep window (R1 then a tap, online, would name the kind on the slot R1 left); nothing new crosses the network, so there is no tag, no validation and nothing a peer can refuse; and the seat (`seated_field_frame`), the fall (`arrival_input`) and a screen (`world_input`) already strip the action from the tick's frame. A selection and an assign are never both needed: an assign names the kind on the selected slot, which stays selected. A lockstep peer sees the Pipette bit in the player's record and runs the same procedure on the same state at the same tick; `simulation_state_hash` covers `toolbars` and `selected_hotbar_slot` (0278). The change shows when the record's tick runs, as R1's and the radial's do. The write is the one `Toolbar_Assign_Command` makes (`toolbars[active_toolbar][selected_hotbar_slot] = item`), made by the tick instead of through the command: question 1.
2. **Which slot.** The selected slot when it names the kind (a tap on what is in hand changes nothing), else the lowest slot of the active toolbar naming it. Other toolbars are not searched (the item says the active toolbar's): a kind named only on another row is named again on the active row's selected slot.
3. **The assign.** With no slot of the active toolbar naming the kind, it is named on the selected slot, replacing what that slot named, whether or not the inventory holds any. No stack moves. An absent kind draws grey and the hand holds nothing (0278).
4. **No toast.** In the world the slot's icon and the selected kind's name above the toolbars show the change. Y toasts because the crafting view covers the HUD (0278, Q1). Aimed at nothing placed: nothing, no toast.
5. **What is aimed**, through one procedure the tick and the HUD share (`pipette_aimed_item`):
   - An aimed cable (0368, `field_aimed_cable`): its `Cable.item`, before what lies behind it, as Mine's take up goes to the cable first. The cable aim only finds cables nearer than the frame or terrain hit (`field_aim_limit`).
   - Else the aimed entity (`aimed_entity`: the field's frame cell when it hits, else the block world's raycast): its machine's `item`. On the field that is a machine, a foundation cell (every cell of a foundation block is a 1 by 1 by 1 foundation entity, so the cell's occupant is its own record), a belt pole, a flat belt on a frame cell, a splitter, a chest, a vessel part; in the block world every entity the raycast names.
   - NO_ITEM for what the world placed (`field_entity_is_placed_by_world`: the pod, its hatches, bench, cradle and charge controller, a schematic crate, all without an item), for terrain and for nothing hit, and for a tree (a nearer trunk clears the frame target, `aim_field_player_at_trees`). Players and loose items are never a target.
   - Left out: belt and pipe runs between poles. A run is no entity with a cell (`belt_run.odin`), no ray meets its curve and the HUD names none. Its pole is aimed instead, and the pole's item gives the same run tool as a belt's (`field_tool_for_item` maps Belt and Belt_Pole to Belt_Run, whose belt is the field's `run_belt`), so the couch line of Verify reads "aim at a belt pole, tap, the run tool is in hand". Torches: question 2. Pipes run by hand (0374): question 3.
6. **Reach.** By construction: the frame ray stops at `tuning.reach` (6 m, 0219), the cable aim is within the reach and before the frame or terrain hit, the block world's raycast stops at `PLAYER_REACH`. The tick reads the confirmed body's aim from the tick before (on the field the move and aim run after, in `queue_field_player_edit`, as for `interact_on_field`'s Open_Aimed and Interact), the HUD reads the predicted body (`hud_field_player`). The same procedure on the body the HUD shows, so the hint names what a tap picks, the prediction's tick apart, as Open does.
7. **Where it does nothing.** Under a screen (`world_input` drops `WORLD_ACTIONS`, `draw_hud` resets the tools radial). In the anchored placement editor (`PLACEMENT_EDITOR_TAKEN_ACTIONS` drops it, the radial does not open); with the editor on and only the outline showing it works, and the outline follows the new held kind. Strapped, seated or cradled (`seated_field_frame` keeps no Pipette). During the fall (`arrival_input`). During a cable run: the tick skips it, since the run holds the hand on `cable_slot` and another slot or kind would end it silently (`update_field_cable_tool`), and the run is a mode the player carries (0368), as the anchored editor takes Pipette. In the water tech demo (`tech_demo_world_frame` drops it and the radial is off).
8. **Not copied.** A foundation's block size (the configure pop-up's) and a machine's rotation (the player's `placement_rotation`) stay as they are: the toolbar names a kind.
9. **The hint.** "Pipette" on the Tools glyph (Pipette's first control: D-pad Up, Q) whenever `hud_pipette_item` gives an item, after the aimed thing's hints and Open and before the held hints, in the held "Tools" hint's place: one hint per glyph, the tap is what the glyph does on a target, and the hold still opens the radial. It is a kept hint. With an item held the count of kept hints does not grow (Pipette replaces Tools); with nothing held it is at most the aimed hints, Open and Pipette. At the smallest audit size (1280 by 800, UI scale 1.5, text 1.6) a chest aimed with the furnace held keeps Pick up, Open, Pipette, Place, Turn: the bar stands above the toolbars in one row and sheds from the end, so Pipette, third, shows (the audit case asserts it at every size). Should the audit find it dropped at a size, the pipette hint goes before Open and the report names it.
10. **Touch.** Nothing new: the HUD's Tools button presses Pipette's control (0215), so its tap is the pipette. The free screen's taps press no Pipette.

### Code

New file `src/toolbar_pipette.odin` (simulation cluster by its `toolbar` prefix). Header: the pipette (work item 0216, doc/hud.md, Toolbars): what a tap of Pipette's control picks and where on the active toolbar it goes, read by the ticks and by the HUD's hint alike. No ui type in its signatures.

- `pipette_aimed_item :: proc(entities: ^Entities, machines: Machine_Registry, block_target: Entity_Handle, frame_target: Frame_Raycast_Hit, aimed_cable: int) -> Item_Id`: `entities.cables.cables[aimed_cable].item` when `index_in_range(aimed_cable, len(entities.cables.cables))`; else `handle := aimed_entity(block_target, frame_target)`, NO_ITEM when `field_entity_is_placed_by_world(entities, machines, handle)`, else `machines.machines[entity_common(entities, handle).machine].item`. Pure. Called by the two ticks and `hud_pipette_item`.
- `pipette_slot :: proc(toolbar: Toolbar, selected: int, item: Item_Id) -> int`: `selected` when `toolbar[selected] == item`, else the lowest slot naming the item, -1 for none. Pure.
- `apply_pipette :: proc(player: ^Player, item: Item_Id)`: nothing for NO_ITEM; a slot from `pipette_slot(player.toolbars[player.active_toolbar], player.selected_hotbar_slot, item)` becomes `selected_hotbar_slot`; at -1 `player.toolbars[player.active_toolbar][player.selected_hotbar_slot] = item`.

`simulation_field.odin`, `tick_field_session_player`, right after the `cycle_hotbar_slot` line and before `field_tick_input`; the procedure's comment gains "the pipette" beside "the hotbar":

```odin
// The pipette (0216) after the slot keys, before the tool follows the
// selection; not during a cable run, which holds the hand.
if .Pipette in resolved.just_pressed && !player.field.cable_run {
	entities := &state.world.entities
	cable := field_aimed_cable(entities, content.machines, player.field, content.field.tuning)
	apply_pipette(player, pipette_aimed_item(entities, content.machines, NO_ENTITY, player.field.frame_target, cable))
}
```

`player.odin`, `tick_player`, right after the `cycle_hotbar_slot` line:

```odin
// The pipette (0216), after the slot keys.
if .Pipette in input.just_pressed {
	apply_pipette(player, pipette_aimed_item(&world.entities, content.machines, player.target.entity, {}, -1))
}
```

`hud.odin`:

- `hud_pipette_item :: proc(screen_context: Screen_Context, hud: Hud_Context) -> Item_Id`, beside `field_pick_up_hint_shown`: NO_ITEM when `screen_context.world == nil`, `screen_context.content.field.tech_demo`, `screen_context.arrival_falling`, or the HUD's body (`hud_field_player`) is not `.Standing` or has `cable_run`; else `pipette_aimed_item(&screen_context.world.entities, screen_context.machines, screen_context.player.target.entity, body.frame_target, hud.aimed_cable.? or_else hud_aimed_cable(screen_context, hud))`. Comment: the ticks' rule on the body the HUD shows, so the hint names what a tap picks.
- `world_glyph_hints`: after the Open hint, `pipette := hud_pipette_item(screen_context, hud) != NO_ITEM`; when set, `append(&list, Glyph_Hint{.Tools, text("hint_pipette")})`. The held hints' call passes `pipette`. The comment's order gains the pipette.
- `held_glyph_hints :: proc(tool: Field_Held_Tool, cable_run: bool, tech_demo := false, pipette := false) -> []Glyph_Hint`: the Tools hint only when `!pipette`; the tech demo's Torch hint unchanged. Comment updated.

`data/strings/en.sjson`, after `hint_tools`: the comment `// The aimed thing's pipette on the Tools glyph (0216): a tap picks its kind onto the toolbar.` and `hint_pipette = "Pipette"`.

No data key, no save or record layout change, no new action, binding or command tag.

### Tests

The Verify list for toolbars: a placed thing aimed selects the active toolbar's slot naming its kind (tests 1, 3, 4); with no slot naming it, the kind is named on the selected slot and no stack moves (1, 3); an empty inventory names it all the same, grey (1, 3); nothing aimed changes nothing (3); no command, so nothing to round trip: the Pipette bit already rides in `Record_Input`.

New `src/toolbar_pipette_test.odin`:

1. `test_the_pipette_selects_the_named_slot_or_names_the_selected_one`: `make_player({}, context.temp_allocator)`, the test items' dirt, steel furnace and wooden chest. Toolbar 0 names dirt on 0 and the furnace on 1 and 5, toolbar 1 the chest on 0. Selected 3, the furnace: selected 1, the toolbars unchanged. Selected 5, the furnace: stays 5. Selected 2, the chest: toolbar 0's slot 2 names the chest, selected stays 2, toolbar 1 unchanged, every inventory slot still empty, `selected_stack_index` -1; after `inventory_add` of 3 chests `selected_stack_index` is that stack's slot. NO_ITEM: nothing changes. `active_toolbar` 1, selected 4, the chest: selected 0.
2. `test_the_pipette_reads_the_aimed_things_item`: `make_test_content()`, `make_floor_world(content.blocks, 32)` (destroyed), `add_entity` of `steel_furnace` at {4, 1, 4}, `belt` at {6, 1, 4}, `belt_pole` at {8, 1, 4}, `test_foundation(content.machines)` at {10, 1, 4}, `schematic_crate` at {12, 1, 4}, and `place_test_pod` (`find_pod` gives its handle). A frame hit is `Frame_Raycast_Hit{hit = true, occupant = {handle = entity_occupant_handle(handle)}}`. Block target the furnace: its item; NO_ENTITY: NO_ITEM. Frame hits on the belt, the pole and the foundation: their machines' items; the pod and the crate: NO_ITEM; an unhit frame target with NO_ENTITY: NO_ITEM. A frame hit on the belt with the furnace as block target: the belt's item. A `Cable{item = light_cable}` appended to `entities.cables.cables`: index 0 with the belt's frame hit gives light cable, index 1 the belt's. The furnace removed (`remove_entity`): its stale handle gives NO_ITEM.
3. `test_a_pipette_press_on_the_field_selects_or_names_the_aimed_kind`: the fixture of `test_the_glyph_bar_during_a_run_and_on_a_switch_behind_a_cable` (`make_pick_up_test`, `lay_cable_test_pad`, `power_switch` at {2, 1, 0}, junction boxes south {3, 1, -2} and north {3, 1, 2}, `lay_test_cable` light cable {south, 3} to {north, 2}) plus a `wooden_chest` at {8, 1, 0}, the player by `stand_test_player_on_cell` on {6, 0, 0} with {"light_cable", 100} (named on slot 0, selected). A press is `simulation.tick += 1`, `tick_field_session_player(&simulation, content, 0, Input_Frame{just_pressed = {.Pipette}})`, `finish_field_tick`; an aim is `look_test_player_at` then `tick_field_simulation(&simulation, content, {})`. In order:
   - Aimed at the chest's `.Negative_X` face centre (`frame_target` names the chest), selected 2: slot 2 names the chest, selected stays 2, slot 0 still names light cable, no chest in the inventory, the field tool `.Hand` after the press.
   - Selected 5, the same aim: selected 2, the toolbar unchanged.
   - Aimed at the test's `switch_point` (150 mm under the switch's `.Positive_X` face centre, `field_aimed_cable` 0): selected 0, the tool `.Cable`.
   - `pitch = -FIELD_PITCH_LIMIT`, aimed (`frame_target.cell` {6, 0, 0}), selected 3: slot 3 names the pad foundation's item (`test_foundation`).
   - `pitch = FIELD_PITCH_LIMIT`, aimed (no frame hit): the toolbars and the selection unchanged.
   - Selected 0, one press of `{}` (the tool follows: `.Cable`), `begin_test_run(&simulation, content, frame, {3, 1, 2})` (`cable_run`), aimed at the chest again: a Pipette press leaves the toolbars and the selection unchanged and the run carried.
   - `seated_field_frame(Input_Frame{just_pressed = {.Pipette}}, seat)` for `.Seated` and `.Strapped` carries no Pipette.
4. `test_only_a_tap_of_the_tools_control_pipettes` (the block world through `tick_player`): the fixture of `test_x_turns_a_switch_and_opens_a_furnace_and_a_jumps_at_a_switch` (`steel_furnace` at {4, 1, 4}, `make_test_player(content.blocks, {4.5, 1, 1.5})` at pitch -30 and yaw 90; one tick of `{}` aims it, `target.entity` the furnace), toolbar 0 naming the furnace on slot 3, selected 0; `use_shipped_strings`. A step is `test_ui_frame(&state, input, seconds)`, `tools_radial(&state, nil)`, the world frame `tools_radial_world_frame(raw, state.tools_radial)` where `raw` carries Pipette in `pressed` while held and in `just_pressed` on the press's first frame (as `world_input` gives it), one `tick_player` of it, then `pipette_selected = false` (as `update_frame_world` clears it). Held past `TOOLS_RADIAL_SHOW_SECONDS` and released in the dead centre: selected 0 after every step. Steered to the placement editor entry (`look_delta` {0, 200}) and released, no editor: selected 0. Steered to the Pipette entry (`look_delta` {0, -200}): 0 while held, 3 after the release step. Selected 0 again, a tap (one step down, one up): 0 after the first, 3 after the release.

`src/hud_test.odin`:

5. `test_the_pipette_hint_names_what_a_tap_picks`: a zero `World` (destroyed), the test machines and items, a `wooden_chest` added at {4, 1, 4}, `place_test_pod`, a player as `test_the_chair_hints_unbuckle_stand_and_sit` makes it holding the stone furnace (`hold_test_stack`), `Hud_Context{field_view_set = true, field_session = true}` with `field_view.tool = .Machine`. Nothing aimed: Place, Tools, Turn, Inventory, Pause. The chest as frame target: `hud_pipette_item` its item, the buttons Mine, Inventory, Tools, Use_Item, Rotate, Pause, kept 5, the Tools hint's label "Pipette" and no "Tools" label. Nothing held (`hold_test_stack` EMPTY_STACK): Mine, Inventory, Tools, Pause, kept 3. The pod as frame target: no Pipette, Tools back among the held hints. With `field_view.cable_run` (tool `.Cable`) on the chest, with `seat = .Seated`, with `content.field.tech_demo`, with `arrival_falling` (each undone after): `hud_pipette_item` NO_ITEM and no Pipette label; on the run the held hints are Connect, Take back, Tools. A `Cable{item = light_cable}` in the table, `hud.aimed_cable = 0`, no frame target: `hud_pipette_item` is light cable. The block world (a fresh `Hud_Context{field_view_set = true}`, `player.target` the chest): Inventory "Open", Tools "Pipette", Pause.
6. `test_x_shows_one_hint_on_a_switch_and_a_crate` (changed, the switch and the furnace have items): the switch with the shared control Interact, Tools, Pause; with separate controls Interact, Inventory ("Open"), Tools, Pause; the furnace Inventory ("Open"), Tools, Pause. The crate cases are unchanged (a crate has no item). The comment adds the pipette.

`src/ui_audit_test.odin`: the audit case below. Every other test that reads glyph hints keeps its expectations: the cable tests read labels per glyph, the glyph bar tests aim at nothing.

### UI audit

- `Ui_Audit_Case.aimed: Entity_Handle` (comment: the HUD's field player aims at this entity's cell, so the bar keeps Pipette at every size, 0216; NO_ENTITY for none). In the frame, after `audit_field_session_hud`, a set `aimed` sets `hud.field_view.frame_target = Frame_Raycast_Hit{hit = true, occupant = {handle = entity_occupant_handle(audit_case.aimed)}}`; after the frame, beside the Unbuckle check, with `aimed` set and no touch, a missing `glyph_beside_label` of `text("hint_pipette")` reports `.Glyph_Hint_Dropped`.
- New case "hud field pipette target" right after "hud field furnace held": `{hud = true, field_session = true, aimed = <the first alive entry of simulation.world.entities.chests.entries>}` (`place_missing_machines` placed one). It draws Pick up, Open, Pipette, Place, Turn at every size, text scale and device.
- None obsolete. The block world HUD cases aim at the audit's drill and now show Pipette beside Open, under the same checks.

### Docs

- `doc/hud.md`, Toolbars: a bullet after Y's: the pipette (0216, `toolbar_pipette.odin`): a tap of Pipette's control on a placed thing in reach selects the active toolbar's slot naming its kind (the selected one if it does, else the lowest) and, with none, names the kind on the selected slot whether or not the inventory holds any (absent, it draws grey); no stack moves, no toast. The kind: an aimed cable's, else the aimed entity's item (a foundation cell its foundation, a belt pole or a flat belt its own); a run between poles is never aimed (its pole is), and terrain, a tree, the pod and what the world placed give nothing. Layout, the glyph bar cell: the world's order becomes the aimed thing's hints, Open, Pipette, the held item's; "Tools ... with any item" gains "unless Pipette shows"; one sentence on Pipette (the Tools glyph, while a tap would pick something, `hud_pipette_item`).
- `doc/input.md`, Bindings: a bullet after the Rotate_Building one: Pipette (0216) reaches the tick as one press in the input record (the tools radial's tap or its Pipette entry), never a command; the tick reads the aimed thing as the HUD's hint does (`pipette_aimed_item`) and selects or names ([hud.md](hud.md), Toolbars); it does nothing under a screen, strapped, seated or cradled, during the fall, during a cable run, in the anchored placement editor and in the water tech demo; touch through the Tools button's tap.
- `doc/architecture.md`, line 44 (the field tick): after `field_tick_input`, "the slot keys and the pipette pick the selected slot (0216, `apply_pipette`)".
- `doc/touch_overlay.md`, Hotbar and HUD buttons, Tools: "a tap is Pipette" becomes "a tap is the pipette ([hud.md](hud.md), Toolbars)".
- `doc/code_map.md`, simulation, after `toolbar.odin`: "`toolbar_pipette.odin`: the pipette (0216), the aimed thing's item (`pipette_aimed_item`) and the slot it selects or names (`apply_pipette`)."; the file counts on line 3 and in the simulation row. Run `python3 tools/check_docs.py` and `python3 tools/code_graph.py --check doc/code_map.md`; if the check reports a simulation edge into ui (the `.Pipette` reads), record it as the 0179 input types are, with 0216.

### Hand-back lines that apply

- A long string fitted at the smallest audit size: "Pipette" in a bar that sheds from the end; the new audit case asserts it at every size (decision 9).
- An obsolete UI audit case: none, one added.
- Tests in memory only, no state directory.
- Not applicable: frame memory (the tick writes two integers), file writes, start-up loads, numbers from text (no data key, no command), a save layout (the toolbars and the selection are saved since 0278, nothing new), shared budgets, unbounded lists.

### Questions for the main agent

1. The item and the brief say the assign goes "with `Toolbar_Assign_Command`". Provisional: the tick makes that write on the Pipette action (decision 1), for the fresh selection across the lockstep window and nothing new on the network. The alternative: the frame reads the HUD's target and queues `Hotbar_Slot_Command{slot}` or `Toolbar_Assign_Command{active_toolbar, selected_hotbar_slot, item}` (one or the other, never both), from the confirmed toolbars.
2. Torches are placed things with an item (`field_aimed_torch`, Dig takes one back), but the HUD names no aimed torch and the torch list lives in the field simulation, outside `Screen_Context`. Provisional: left out; a torch in front of a frame cell leaves the pipette on the cell, as the Pick up hint does. Including them needs `Hud_Context` to carry the aimed torch from `make_hud_context`.
3. 0374 (designing) replaces pipe runs with hand-run pipes like cables. Provisional: 0374's specification adds its aimed pipe to `pipette_aimed_item` (one branch beside the cable's) and to the tests 2 and 5.

### Decisions (main agent, 2026-11-13)

1. Approved: the pipette as a tick action on the `Pipette` bit, no command. The "After 0278" note's `Toolbar_Assign_Command` is replaced by the same write made in the tick.
2. Torches stay out: the HUD names no torch target, and the tap never picks what the hints do not name.
3. Hand run pipes (0374) need nothing here or there: they are records of the cable table told by their item, so the aimed cable's item is the pipe.

### Fix round

- Decision 9's claim does not hold: placed after Open, Pipette pushed Place and Turn out at the largest text (1920 by 1080 and 1280 by 800 at UI scale 1.5, text 1.6, keyboard). Pipette takes the held Tools hint's place (after Open with nothing held), and no hint that drew before 0216 drops because of it (main agent).
- Deviation (implementation, 2026-11-13): "Pipette" is wider than "Tools", so in that place it still pushed Turn or Pause out at some sizes. `hud_world_glyph_bar_layout` lays the bar out with and without it and shows Pipette only where both draw the same hints, else the Tools hint (or none with nothing held). So Pipette does not show everywhere the Tools hint drew before. For the audit's chest with the furnace held it shows Tools at 1920 by 1080 scale 1.2 text 1.6 on the keyboard and scale 1.5 text 1.6 on both glyph sets (approximate text widths).
