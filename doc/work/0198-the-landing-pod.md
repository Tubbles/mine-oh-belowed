# 0198: The landing pod: larger, an airlock, a chest, a bench, an oxygen generator

Status: designed (2026-10-03, the specification approved; after 0197 and 0205; user, 2026-10-03: "the landing pod should be larger, with an airlock, chest, crafting bench, it needs to house an oxygen generator and have infinite oxygen on board"; after 0197)

## Goal

The pod is the arrival of `DESIGN.md` (Arrival: an infinite water reserve feeding its oxygen generator, a bed, the first tools) and the sealed room of M15 (`PLAN.md`, Survival: the pod's oxygen generator and panels). Today it is 6 by 6 by 8 cells with a bed and a door (`pod()` in `tools/make_placeholder_models.py`, the record in `data/machines.sjson`, 0186's open cells).

## Change

- Larger: 8 wide by 12 deep by 8 high cells (4 by 6 by 4 m at the 500 mm pitch, the numbers in the record, so the user tunes them), in its crater (0199: no pad). The front 2 cells of depth are the airlock: an outer hatch on the front face and an inner hatch to the cabin, each 1 m wide and 2 m high.
- Hatches are a machine of kind `hatch`, 2 by 1 by 4 cells, placed by the world in the pod's wall cells: closed it is solid, Interact on it toggles it open (its cells become open cells, 0186) through the switch toggle path that exists (`Toggled_Switch`, `Power_Switch_Command`), so the airlock is two hatches the player opens one at a time. The hatch's state is lockstep state and saved. The model shows the hatch open or shut.
- Fixtures placed by the world inside the cabin, each a machine with its own footprint and panel, opened with the inventory binding (0194): the bed (as today, no panel), a `pod_locker` chest of 16 slots (the capsule's quest rewards keep going where they go today; say in the report if the locker should take them instead), a `crafting_bench` whose panel is the crafting view (hand crafting stays available everywhere in peaceful; in survival, M15, it is where crafting happens), and an `oxygen_generator` whose panel says what it does and shows "Oxygen: unlimited" for now. All are `machine_kind_is_placed_by_world` like the pod: never crafted, held or picked up (0195 refuses them).
- Infinite oxygen on board: the pod's cabin and airlock are registered as a sealed room with an unlimited oxygen supply (`Sealed_Room` on the simulation, the cells of the pod's open cells behind closed hatches), which M15's suit drain reads later. Until M15 nothing breathes, but the room exists, is saved, and the F3 World page says whether the feet are inside it.
- The model: `pod()` regenerated at the new size with the airlock chamber, the hatches' openings, the fixtures' footprints visible, the bed, windows and the band as today; the hatches and fixtures get their own placeholder models.
- `doc/content.md` (The pod, Hatches, the fixtures), `doc/architecture.md` (sealed rooms, the hatch's toggle), `PLAN.md` M15 (what this item already provides), the log.

## Controls

- Interact (F, gamepad South) on a hatch toggles it, the existing switch control; the hint reads "Open" or "Close". Open_Inventory (E, West) on a fixture opens its panel (0194). Nothing else is bound.

## Verify

- The build and check commands of 0168.
- Tests: the pod places in its crater with the two hatches and the fixtures at their cells; a closed hatch is solid and an open one is passed; toggling is lockstep state and round trips a save; the sealed room's cells are exactly the cabin and the airlock behind closed hatches; the fixtures refuse pick up and placement over them.
- The couch: the user opens the outer hatch, closes it, opens the inner one, reaches the locker, the bench and the generator, and F3 says "inside the pod".

## Specification (design, 2026-10-03)

Designed against `main` at bccc7e5 and against three items not on `main` yet, each by its approved specification: 0199 (`.claude/worktrees/0199`, being implemented; the names read off its tree: `place_pod`, `pod_origin`, `POD_ROTATION`, `pod_cabin_floor_centre`, `field_pod_spawn`, `field_spawn_player`, `validate_pod_cabin`, `field_entity_is_placed_by_world` as `item == NO_ITEM`, `test_place_pod_stands_the_pod_on_its_frame_with_no_pad`, `test_an_old_save_with_a_pad_still_loads`), 0197 (trees, main checkout: it adds `Machine_Kind.Tree` after `.Pod`, `tree` to `machine_kind_is_placed_by_world`, a clearing of 24 m round the home, and the felled tree table after `write_machine_wear_table`; 0198 touches none of them and keeps the clearing, which already holds the pod) and 0205 (the kit, `.claude/worktrees/0205`: `kit.box`, `cylinder`, `cone`, `cut`, `opening`, `wedge`, `ring`, `pipe`, `hatch`, `strip`, `rib_row`, `model_random`, `expect_footprint`, `join`, `join_part`, `records.open_cell_box`, `palette.MATERIALS` with 0205's `timber`, `timber_dark`, `stone`, `lamp_glow`). Where a landed name differs, the landed code wins and the report says so. Integer only in the simulation: the hatch state, the occupancy and the sealed room are integers and booleans; floats only in the draw and the models.

The implementer may run `./build.sh model-check`, `tools/make_models.sh` and `tools/model_preview.sh` (0207's approval); a session, `--planet-preview`, the benchmark and the play build stay forbidden.

### Answers to what the item left open

1. **Orientation of the record.** "8 wide by 12 deep" is the player's sense: 12 cells from the outer hatch to the back wall, 8 across. The record's width is the front axis (+x is the front, `data/machines.sjson` header), so the record is `footprint = {width = 12, depth = 8, height = 8}`. `POD_ROTATION` turns it to 8 by 12 on the frame, the 12 along the frame's forward, which is the 4 by 6 m 0199 sized the crater floor for (corners 3.6 m out on a 4 m floor). The hatch is `{width = 1, depth = 2, height = 4}`, not 2 by 1 by 4: the same cells, but its front (+x) then faces out of the wall, so its model is drawn facing the doorway.
2. **`MAXIMUM_FOOTPRINT_SIZE` rises from 9 to 12.** Nothing but `validate_footprint` reads it (grep); voxel scaling, the occupant index and the model check do not bound a side.
3. **How the pod shares its cells with the hatches and fixtures.** A new pod record key `fixtures` lists each fixture's machine, minimum cell in the pod's unrotated footprint and quarter turns. The pod occupies its footprint minus the fixtures' boxes (`machine_held_cells`), and `place_pod` adds each fixture as its own entity on the pod's frame in those cells. One occupant per cell, independent of the order the pools are rebuilt in; the frame's cell count stays the footprint's volume. Data, not code, says where each fixture stands.
4. **Kinds.** Four new machine kinds, all placed by the world: `hatch` (foundations' pool, the state on `Foundation`), `locker` (the chests' pool, a `Chest` entry, so every chest path works), `crafting_bench` (foundations' pool, the crafting station's panel with the hand maker) and `oxygen_generator` (foundations' pool, a text panel). The bed stays part of the pod (solid pod cells, as today).
5. **The hatch mechanism.** Interact on a hatch flips `Foundation.hatch_open` in `interact_on_field`, the path that turns a power switch, and raises `.Toggled_Switch`. Closed: its cells are `Solid`. Open: none is `Solid`; every row but the top is `Open` (the aiming ray passes), the top row has neither flag, so the player walks under it and the ray stops at it, which keeps an open hatch aimable to close it. `Power_Switch_Command` stays the switch panel's button: a hatch has no panel, so no command is added; the toggle rides the player's input frame, which is lockstep already. Closing is refused while a player's capsule meets a hatch cell (no toast, see the questions).
6. **The hatch's model.** One model with a moving part and a new motion kind `slide`: the part (the door panel) moves along the axis by `amplitude` cells times the open fraction, which follows the hatch's state, not the clock, eased over `period_seconds` from the tick of the last toggle. `model_motion.odin` drives pump, spin, swing and bob from the clock only, so the kind is new. The panel rises into a pocket in the pod's wall above the door. The jamb's cyan strips glow while the hatch is open.
7. **The sealed room.** Derived, never saved: `Entities.sealed_rooms`, rebuilt from the occupancy by a flood fill when a pod is placed, a hatch toggles, and a world loads. The hatch states it derives from are saved and hashed, so two sessions and a loaded save agree. Saving the cells would be a second copy that could disagree with the hatches; the item's "is saved" is met through them.
8. **Start state.** A new world places both hatches closed: the room is sealed from tick 0, players spawn in the cabin (0199) and open the inner hatch, then the outer, to leave. 0200 opens them at the end of the fall through `toggle_hatch`. 0199's Change line ("before it, the spawn is inside with the hatches open") predates this; question 1 asks to confirm.
9. **Quest rewards.** They keep going to the drop capsule (`tick_quests`, `land_rewards`). I read that `start_session` runs `choose_world_start` and `make_simulation` places the capsule at the block generator's landing pad for a field session too (`session.odin`, `simulation_state.odin` `place_capsule`), on the block frame, which I did not verify the field player can reach. The locker taking them is the better home on the field, but it changes what counts as a delivery (`observe_capsule`, the objectives that count capsule contents) and the quest texts that name the capsule, which is the quest chapter's design, not this item's. Recommended as a separate item (question 2).
10. **The bench in peaceful.** Its panel is the crafting station mode of 0196 with the `hand` maker: the hand recipes, unlocked only. Hand crafting from the inventory stays everywhere; M15 gates it to the bench in survival.
11. **The generator's supply.** A room is supplied when an oxygen generator's footprint cell is face adjacent to one of its cells; the supply is `Unlimited` (no rate, no stock) until M15.
12. **Old saves.** A pod whose saved `Entity_Common.size` differs from its record's rotated footprint is replaced at load by the new pod with its fixtures, on a new frame standing on the old pod's floor centre, facing the old frame's forward; players whose feet fall in the new pod's box move to its cabin. One log line. The old frame goes if nothing else is on it (a 0199 era save); a pad save keeps its pad, the new pod standing on it.

### The records (`data/machines.sjson`)

The pod's record becomes (comments in the file's style):

```
	{
		id = "pod"
		name_key = "machine_pod"
		description_key = "describe_machine_pod"
		kind = "pod"
		stands_on_ground = true
		// 12 cells from the outer hatch (the front, +x) to the back wall,
		// 8 across, 8 high: 6 by 4 by 4 m at the 500 mm pitch.
		footprint = {width = 12, depth = 8, height = 8}
		model = "pod"
		// The cabin (the first box: players spawn at the centre of its
		// floor, validate_pod_cabin), past the bed's foot, over the bed,
		// the airlock between the hatches.
		open_cells = [
			{from = {x = 1, y = 0, z = 1}, to = {x = 7, y = 5, z = 4}}
			{from = {x = 5, y = 0, z = 5}, to = {x = 7, y = 5, z = 6}}
			{from = {x = 1, y = 1, z = 5}, to = {x = 4, y = 5, z = 6}}
			{from = {x = 9, y = 0, z = 1}, to = {x = 10, y = 5, z = 6}}
		]
		// The outer hatch in the front wall, the inner hatch between the
		// airlock and the cabin, then the locker, the bench and the
		// oxygen generator along the cabin's z 0 wall, facing in.
		fixtures = [
			{machine = "pod_hatch", cell = {x = 11, y = 0, z = 3}, rotation = 0}
			{machine = "pod_hatch", cell = {x = 8, y = 0, z = 3}, rotation = 0}
			{machine = "pod_locker", cell = {x = 1, y = 0, z = 1}, rotation = 1}
			{machine = "crafting_bench", cell = {x = 3, y = 0, z = 1}, rotation = 1}
			{machine = "oxygen_generator", cell = {x = 5, y = 0, z = 1}, rotation = 1}
		]
	}
```

The layout in the pod's unrotated cells (x front to back 11 to 0, z across 0 to 7, y up): walls x 0, x 11, z 0, z 7; the inner wall x 8; the roof y 6 and 7; the cabin x 1 to 7, z 1 to 6, y 0 to 5 (3.5 by 3 by 3 m); the airlock x 9 to 10 (two cells of depth, 1 m), z 1 to 6, y 0 to 5; the outer hatch x 11, z 3 to 4, y 0 to 3 (1 m wide, 2 m high); the inner hatch x 8, same z and y; the bed x 1 to 4, z 5 to 6, y 0 (solid pod cells); the locker x 1 to 2, z 1, y 0 to 3; the bench x 3 to 4, z 1, y 0 to 1; the generator x 5 to 6, z 1, y 0 to 2. Every interior cell is in an open box, a fixture box or the bed. The spawn (0199, the first box's floor centre) lies at x 4.5, z 3.0, a cell clear of the fixtures' row and two of the bed. On the frame (`pod_origin` {-3, 0, -5}, `POD_ROTATION` 1) the outer hatch takes frame cells x 0 to 1, z 6, the airlock z 4 to 5, the inner hatch z 3, the cabin z -4 to 2.

Four new records after the pod (after 0197's `pine_tree` if it sits there):

```
	{
		id = "pod_hatch"
		name_key = "machine_pod_hatch"
		description_key = "describe_machine_pod_hatch"
		model = "pod_hatch"
		// The door panel rises 3.95 cells into the wall's pocket.
		motion = {kind = "slide", axis = "y", amplitude = 3.95, period_seconds = 0.8}
		kind = "hatch"
		stands_on_ground = true
		footprint = {width = 1, depth = 2, height = 4}
	}
	{
		id = "pod_locker"
		name_key = "machine_pod_locker"
		description_key = "describe_machine_pod_locker"
		model = "pod_locker"
		kind = "locker"
		stands_on_ground = true
		footprint = {width = 1, depth = 2, height = 4}
		slots = 16
	}
	{
		id = "crafting_bench"
		name_key = "machine_crafting_bench"
		description_key = "describe_machine_crafting_bench"
		model = "crafting_bench"
		kind = "crafting_bench"
		stands_on_ground = true
		footprint = {width = 1, depth = 2, height = 2}
		recipe_maker = "hand"
	}
	{
		id = "oxygen_generator"
		name_key = "machine_oxygen_generator"
		description_key = "describe_machine_oxygen_generator"
		model = "oxygen_generator"
		kind = "oxygen_generator"
		stands_on_ground = true
		footprint = {width = 1, depth = 2, height = 3}
	}
```

`stands_on_ground` keeps them out of the wear (0201) like the pod; none ever operates either way.

The file's header comment: the footprint line says "each from 1 to 12"; the motion paragraph adds "kind slide (hatches only, 0198) moves the part along axis by amplitude blocks (0 to 12) times the hatch's open fraction, eased over period_seconds from its last toggle, and needs the part group of its OBJ"; the kind list adds `hatch`, `locker`, `crafting_bench` and `oxygen_generator`; the pod paragraph is rewritten (no pad: 0199's text, plus the `fixtures` key: "fixtures (pods only, at most 8) lists {machine, cell = {x, y, z}, rotation}: a machine of kind hatch, locker, crafting_bench or oxygen_generator placed by the world with its minimum corner at cell of the pod's unrotated footprint and turned by rotation quarter turns against the pod. Its box (the rotated footprint from cell) lies inside the pod's footprint, overlaps no other fixture's box and not the cabin's spawn cells; the pod leaves those cells to it"); a new paragraph: "Hatches (kind hatch, 0198): no item, at least 2 cells high, no open_cells, a slide motion or none. Closed its cells are solid; open none is, and every row but the top is an open cell. Lockers (kind locker): a chest placed by the world, slots 1 to 32. Crafting benches (kind crafting_bench): recipe_maker hand, no slots, power, speed or ports; the panel is the crafting station's. Oxygen generators (kind oxygen_generator): no slots, power or ports; a sealed room one touches has an unlimited supply."

### Strings (`data/strings/en.sjson`)

- `describe_machine_pod` = "The venture's landing pod: a cabin behind an airlock of two hatches. Home, for the length of the lease."
- `machine_pod_hatch` = "Hatch", `describe_machine_pod_hatch` = "A pressure hatch of the pod. With both closed, the cabin and the airlock hold air."
- `machine_pod_locker` = "Locker", `describe_machine_pod_locker` = "Sixteen slots of storage built into the pod's wall."
- `machine_crafting_bench` = "Crafting bench", `describe_machine_crafting_bench` = "The pod's workbench. Whatever the hands can make is made here."
- `machine_oxygen_generator` = "Oxygen generator", `describe_machine_oxygen_generator` = "Splits water from the pod's reserve into air for the sealed cabin and airlock."
- `oxygen_generator_supply_unlimited` = "Oxygen: unlimited"
- The hatch's hint reuses `hint_open` ("Open") and `hint_close` ("Close").

### Content (`machine.odin`, `model_motion.odin`, `assembler.odin`)

- `MAXIMUM_FOOTPRINT_SIZE :: 12`; new `MAXIMUM_POD_FIXTURES :: 8`; `MINIMUM_HATCH_HEIGHT :: 2`.
- `Machine_Kind` gains, after the last kind (after 0197's `Tree`), with comments: `Hatch` (a door of the pod, placed by the world, its state on `Foundation`, entity_pod.odin), `Locker` (a chest placed by the world: the chests' pool), `Crafting_Bench` (a crafting station placed by the world with the hand maker: the foundations' pool), `Oxygen_Generator` (supplies the sealed room it touches: the foundations' pool). `machine_kind_names`: `"hatch"`, `"locker"`, `"crafting_bench"`, `"oxygen_generator"`. Every complete switch and enumerated array over `Machine_Kind` gets them (the compiler names them; known: `validate_machine_kind_fields`, `fluid_machine_colors` in `render_fluids.odin` `{}`, `machine_area_width` and `machine_area_height` in `ui_machine.odin`, the switch in `add_entity`).
- `Pod_Fixture_Definition :: struct { machine: string, cell: Machine_Cell_Definition, rotation: int }`; `Machine_Definition.fixtures: []Pod_Fixture_Definition` after `open_cells`.
- `Pod_Fixture :: struct { machine: Machine_Id, cell: [3]i32, rotation: u8 }`; `Machine` gains `fixtures: [MAXIMUM_POD_FIXTURES]Pod_Fixture`, `fixture_boxes: [MAXIMUM_POD_FIXTURES]Cell_Box` (each fixture's cells in the pod's unrotated footprint, inclusive) and `fixture_count: int`, after `open_cell_box_count`.
- `machine_kind_is_placed_by_world` also returns true for the four names.
- `pod_fixture_box :: proc(cell: Machine_Cell_Definition, rotation: int, footprint: Machine_Footprint_Definition) -> Cell_Box`: from the cell to the cell plus the rotated footprint minus one (width and depth swapped for an odd rotation). Pure.
- `pod_fixture_kind_name_ok :: proc(kind_name: string) -> bool`: one of the four names.
- `validate_pod_fixtures :: proc(definitions: []Machine_Definition, index: int) -> string`, called in `validate_machine_definition` after `validate_open_cells` (and after 0199's `validate_pod_cabin`, which comes before so the cabin box exists). Refusals in order: fixtures on a kind other than pod `machine %q lists fixtures, which only a pod may`; more than 8 `pod %q has more than %d fixtures`; per fixture i: unknown machine `pod %q fixture %d names unknown machine %q`; a kind other than the four `pod %q fixture %d is a %q, not a hatch, locker, crafting_bench or oxygen_generator`; rotation outside 0 to 3 `pod %q fixture %d has rotation %d outside 0 to 3`; box outside the footprint `pod %q fixture %d is not inside the footprint`; overlapping an earlier fixture j `pod %q fixtures %d and %d overlap`; holding a cabin spawn cell `pod %q fixture %d stands on the cabin's spawn`. The spawn cells are `((from.x + to.x) / 2, 0, (from.z + to.z) / 2)` and `((from.x + to.x + 1) / 2, 0, (from.z + to.z + 1) / 2)` of the first open box (for the shipped cabin (4, 0, 2) and (4, 0, 3)).
- `resolve_pod_fixtures :: proc(definitions: []Machine_Definition, definition: Machine_Definition) -> (fixtures: [MAXIMUM_POD_FIXTURES]Pod_Fixture, boxes: [MAXIMUM_POD_FIXTURES]Cell_Box, count: int)`: validated before; the machine id is the definition's index (`find_definition_index`), the registry being dense in file order. Called in `resolve_machine_registry` after `resolve_machine`.
- `validate_machine_kind_fields` cases: `.Hatch: return validate_hatch_definition(definition)`; `.Locker`: slots 1 to `MAXIMUM_CHEST_SLOTS` `locker %q has slots %d outside 1 to %d`, an item refused `locker %q cannot be placed by an item`; `.Crafting_Bench: return validate_crafting_bench_definition(definition)`; `.Oxygen_Generator`: an item refused `oxygen generator %q cannot be placed by an item`, any slots, power or fluid port refused `oxygen generator %q may not list slots, power or fluid ports`.
- `validate_hatch_definition :: proc(definition: Machine_Definition) -> string`: an item `hatch %q cannot be placed by an item`; height below 2 `hatch %q needs a footprint at least %d cells high`; any `open_cells` `hatch %q lists open_cells; it opens its own cells`; slots, power or ports `hatch %q may not list slots, power or fluid ports`; a motion other than none or slide `hatch %q may only have a slide motion`.
- `validate_crafting_bench_definition :: proc(definition: Machine_Definition) -> string` (`assembler.odin`, beside `validate_crafting_station_definition`): the maker must parse to `.Hand` `crafting bench %q needs the recipe_maker hand`; slots, fuel, power, speed or ports as the station's message `crafting bench %q may not list slots, fuel, power, speed or fluid ports`; an item `crafting bench %q cannot be placed by an item`.
- `machine_is_crafting_station :: proc(machine: Machine) -> bool` (`assembler.odin`): `.Crafting_Station` or `.Crafting_Bench`. Replaces the kind test in `player_craft_makers` (`crafting.odin`), `browser_station_machine` (`ui_recipes.odin`), `machine_screen` (`ui_machine.odin`) and `machines_with_panels` in `ui_audit_test.odin`. `crafting_station_recipes_problem` keeps `.Crafting_Station` only (the hand recipes are the hand queue's already).
- `model_motion.odin`: `Motion_Kind.Slide` after `.Arm` (comment: moves the part along the axis by amplitude blocks times the open fraction a hatch's state gives, hatch_open_fraction; not the clock), `motion_kind_names[.Slide] = "slide"`; `validate_motion_definition`: `kind == .Slide` and `definition.kind != "hatch"` refused `machine %q has a slide motion but is no hatch`, and an amplitude outside 0 (exclusive) to `MAXIMUM_FOOTPRINT_SIZE` refused `machine %q has a slide amplitude outside 0 to %d cells`; the axis and period checks apply as for a pump. `motion_has_part` needs no change (it is true for `.Slide`). `motion_transform`: `case .Slide: return translation_matrix(direction * motion.amplitude * phase)`. `emissive_brightness` unchanged (working means full brightness).
- `hatch_open_fraction :: proc(open: bool, toggle_tick: u64, tick: u64, alpha: f32, tick_rate: int, period_seconds: f32) -> f32` (`model_motion.odin`, presentation, floats): `open ? 1 : 0` when `toggle_tick == 0` or the period is not positive; else `elapsed = (tick + alpha - (toggle_tick - 1)) / (period_seconds * tick_rate)` clamped to 0 to 1, `eased = motion_stroke(elapsed / 2)` (0 at 0, 1 at 1, flat at both ends), `open ? eased : 1 - eased`.

### The hatch and the pod's cells (`entity.odin`, `entity_pod.odin`)

- `Foundation` gains, with a comment (a hatch's state, 0198; zero for every other entry and in a save from before 0198):
  - `hatch_open: bool`
  - `hatch_toggle_tick: u64`: the tick of the last toggle plus one, 0 when never toggled.
- `cell_in_fixture_box :: proc(machine: Machine, cell: [3]i32) -> bool` (`entity.odin`): the unrotated cell lies in one of `fixture_boxes[:fixture_count]`.
- `machine_held_cells :: proc(origin: World_Coordinate, machine: Machine, rotation: u8) -> []World_Coordinate` (`entity.odin`, temp): `footprint_cells` minus the cells in a fixture box, iterating the unrotated cells as `footprint_cells` does. Equal to `footprint_cells` for a machine without fixtures.
- `machine_open_cells` skips cells in a fixture box.
- `occupy_entity_cells`: an open hatch (`machine.kind == .Hatch` and `hatch_is_open(entities, common.handle)`) goes to `occupy_open_hatch_cells` and returns; otherwise as today over `machine_held_cells` instead of `common_cells`, then the open cells.
- `occupy_open_hatch_cells :: proc(entities: ^Entities, common: Entity_Common, occupant: Occupant)`: every footprint cell with `occupant.flags - {.Solid}`, plus `.Open` on every row below the top (`cell.y < common.origin.y + common.size.y - 1`).
- `vacate_entity_cells` iterates `machine_held_cells` instead of `common_cells`, so removing a pod never vacates its fixtures' cells.
- `add_entity`: `case .Chest, .Locker:` the chest entry; `case .Foundation, .Pod, .Crafting_Station, .Hatch, .Crafting_Bench, .Oxygen_Generator:` the foundations' pool.
- `entity_has_panel`: the foundations' branch returns true for the kinds `.Crafting_Station`, `.Crafting_Bench`, `.Oxygen_Generator` (a hatch and the pod have none); its comment names them.
- `entity_pod.odin` (the file header gains the fixtures, the hatches, the sealed room and the upgrade):
  - `hatch_is_open :: proc(entities: ^Entities, handle: Entity_Handle) -> bool`: the foundations' entry's `hatch_open`, false for any other handle.
  - `hatch_state :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> (open: bool, is_hatch: bool)`: for the HUD and the interact answer.
  - `field_player_capsules :: proc(players: []Player, tuning: Field_Player_Tuning) -> []Field_Capsule` (temp): `field_player_capsule` of each player's body.
  - `capsule_meets_frame_cell :: proc(frame: Frame, cell: World_Coordinate, capsule: Field_Capsule) -> bool`: the capsule's axis sampled from its bottom to `bottom + up * length` every `capsule.radius / 2` (both ends included); true when any sample's `cell_box_distance(frame_local_position(frame, sample), cell, frame_pitch_units(frame))` is below `capsule.radius`. Exact enough for a door; `frame_cell_meets_capsule` is too generous (0.73 m at the 500 mm pitch would refuse a player standing in the 1 m airlock).
  - `toggle_hatch :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, tick: u64, capsules: []Field_Capsule) -> bool`: false unless the handle is an alive hatch; closing is refused (false, nothing changes) when a capsule meets one of its footprint cells; else `hatch_open = !hatch_open`, `hatch_toggle_tick = tick + 1`, `occupy_entity_cells` again (it overwrites the same keys, the cell count unchanged), `rebuild_sealed_rooms`, true. 0200 calls it with no capsules at the end of the fall.
  - `pod_fixture_placement :: proc(pod: Machine, pod_origin: World_Coordinate, pod_rotation: u8, index: int) -> (origin: World_Coordinate, rotation: u8)`: the box's two corners on x and z through `rotate_footprint_cell` with the pod's footprint and rotation; origin `pod_origin + {min x, box.from.y, min z}`; rotation `(fixture.rotation + pod_rotation) % 4`. Checked: every cell of every fixture lands where the pod's rotation takes the corresponding cell of its box, for all 16 pairs of rotations (a test below; the composition holds by a brute force check in this design).
  - `place_pod` (0199's signature unchanged): after `add_entity` of the pod, `place_pod_fixtures(entities, machines, pod_machine, origin, POD_ROTATION, frame)`, then `rebuild_sealed_rooms(entities, machines)`. Hatches start closed.
  - `place_pod_fixtures :: proc(entities: ^Entities, machines: Machine_Registry, pod: Machine, origin: World_Coordinate, rotation: u8, frame: Frame_Id)`: `add_entity` of each fixture at `pod_fixture_placement`, in record order.
- `player.odin` `entity_answers_interact`: also true for a hatch (`hatch_state`'s `is_hatch`), so A does not jump on a hatch and a touch tap presses Interact there (`entity_takes_interact`).
- `simulation_field.odin` `interact_on_field :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, frame: Input_Frame) -> (input: Input_Frame, events: Player_Events)`: the player is `&state.players[index]`, the rest as today; after `toggle_power_switch` and before `request_launch`: `if toggle_hatch(&state.world.entities, content.machines, handle, state.tick, field_player_capsules(state.players[:], content.field.tuning)) { return input, {.Toggled_Switch} }`. `tick_field_session_player` passes `state, content, index, frame`. Its comment names the hatch.
- `loop.odin` `show_simulation_events`: the `.Toggled_Switch` comment says the switch's colour or the hatch's model shows the change.

### The sealed room (`entity_pod.odin`)

- `Oxygen_Supply :: enum u8 { None, Unlimited }`.
- `Sealed_Room :: struct { pod: Entity_Handle, frame: Frame_Id, cells: [dynamic]World_Coordinate, supplier: Entity_Handle, oxygen: Oxygen_Supply }`: the sealed cells in the pod's frame in scan order (y, then z, then x), the first oxygen generator in pool order touching them (`NO_ENTITY` for none) and the supply it gives.
- `Entities.sealed_rooms: [dynamic]Sealed_Room` after the networks, with the comment: derived from the occupancy, rebuilt by `rebuild_sealed_rooms`, never saved. `destroy_entities` deletes every room's cells and the list.
- `rebuild_sealed_rooms :: proc(entities: ^Entities, machines: Machine_Registry)`: deletes the rooms; for each alive `.Pod` entry of the foundations' pool in pool order, `cells := pod_sealed_cells(&entities.frames, entry.frame, entry.origin, entry.origin + entry.size - 1)`; when not empty, appends a room with the cells cloned, `supplier := room_supplier(entities, machines, entry.frame, cells)` and `oxygen = supplier != NO_ENTITY ? .Unlimited : .None`. Called by `place_pod`, `toggle_hatch` and `rebuild_loaded_world` (after `rebuild_entity_cells`).
- `pod_sealed_cells :: proc(frames: ^Frame_Table, frame: Frame_Id, minimum, maximum: World_Coordinate) -> []World_Coordinate` (temp, integer): a cell of the box is air when it has no occupant or its occupant lacks `.Solid`. The outside reaches every air cell on the box's four side faces (x minimum or maximum, z minimum or maximum) and its top face (y maximum); the bottom face is the hull's floor on the ground and lets nothing in. A breadth first fill over the six neighbours inside the box, through air cells, from those seeds in scan order, with a dense `[]bool` of the box's volume (at most 768 cells). The result is every air cell the fill did not reach, in scan order.
- `room_supplier :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id, cells: []World_Coordinate) -> Entity_Handle`: the first alive `.Oxygen_Generator` of the foundations' pool on the frame with a footprint cell (`common_cells`) face adjacent to a room cell (a temp map of the cells).
- `sealed_room_at_feet :: proc(entities: ^Entities, feet: World_Position) -> (room: Sealed_Room, inside: bool)`: for each room, its frame (`find_frame`), the cell `world_to_frame_cell(frame, feet + up * pitch / 4)` (up the frame's), inside when the room's cells hold it (`slice.contains`). For the F3 line now and the suit's drain in M15.
- `oxygen_generator_supplies_a_room :: proc(entities: ^Entities, handle: Entity_Handle) -> bool`: a room's `supplier` is the handle. For the draw.
- What the shipped pod gives: both hatches closed, one room of exactly the pod's open cells (the four boxes less the fixtures' cells), supplied by the generator. The outer hatch open: the cabin's cells (boxes 0 to 2 less the fixtures), supplied. The inner hatch open with the outer closed: the open cells plus the inner hatch's 8 cells. Both open: no room.

### The old pod at load (`entity_pod.odin`, `save_state.odin`)

- `Upgraded_Pod :: struct { old_frame: Frame_Id, old_size: [3]i32, pod: Entity_Handle }`.
- `pod_floor_centre :: proc(frame: Frame, origin: World_Coordinate, size: [3]i32) -> World_Position`: `frame.origin` plus the right axis scaled by `(2 * origin.x + size.x) * pitch / 2`, the up by `origin.y * pitch` and the forward by `(2 * origin.z + size.z) * pitch / 2` (`fixed_scale`, `frame_pitch_units`). Integer.
- `upgrade_resized_pods :: proc(entities: ^Entities, machines: Machine_Registry) -> []Upgraded_Pod` (temp): for each alive `.Pod` entry whose `size != rotated_footprint_size(machine.footprint, rotation)`: its frame, `floor := pod_floor_centre(frame, origin, size)`, `pool_remove` of the entry (the occupancy is not built yet), `place_pod(entities, machines, floor, frame.axes[FRAME_FORWARD], frame.pitch_millimetres)`, and the record appended with the new pod's handle. Called in `read_simulation_state` right before `rebuild_loaded_world`, so the rebuild sees only the new pod and its fixtures.
- `finish_pod_upgrades :: proc(state: ^Simulation_State, machines: Machine_Registry, upgraded: []Upgraded_Pod)`: after `rebuild_loaded_world`, when the list is not empty: `release_empty_frame` of each old frame; every player whose feet cell on the new pod's frame (`world_to_frame_cell` a quarter pitch over the feet) lies inside the new pod's box gets `move_field_player_body(&player.field, field_pod_spawn body)`; one log line per pod: `save: the pod of an older build (%d by %d by %d cells) is replaced by the pod of %d by %d by %d cells with its hatches and fixtures, on a frame of its own at the old floor; %d players moved into its cabin`.
- `move_field_player_body :: proc(body: ^Field_Player, spawn: Field_Player)`: copies `position`, `previous_position`, `up`, `forward` and zeroes `yaw`, `pitch`, `velocity`, `motion_fraction`, `on_ground`; the tool, the targets and the run start stay.
- No save layout change otherwise: `Foundation`'s two fields are read by name (`save_binary.odin`), so a save from before 0198 loads every hatch field zero, and no pre 0198 save has a hatch. No format version step, no remap table entry; the pod keeps its id `pod`.

### The draw (`render_entities.odin`, `render_models.odin`)

- In `draw_entities`' foundations' loop: a `.Hatch` goes to `draw_hatch(foundation, machine, models, frame)`; an `.Oxygen_Generator` passes `working = oxygen_generator_supplies_a_room(&frame.world.entities, foundation.handle)` to `draw_entity_cells`; the rest as today. Its comment names the hatches, the bench and the generator.
- `draw_hatch :: proc(hatch: Foundation, machine: Machine, models: Model_Renderer, frame: Model_Frame)` (`render_entities.odin`): with a model, `draw_posed_model` with `hatch_pose`; without one, `draw_entity_cells(..., false, ...)`.
- `hatch_pose :: proc(frame: Model_Frame, hatch: Foundation, machine: Machine) -> Model_Pose` (`render_models.odin`): `{phase = hatch_open_fraction(hatch.hatch_open, hatch.hatch_toggle_tick, frame.tick, frame.alpha, frame.tick_rate, machine.motion.period_seconds), working = hatch.hatch_open}`.
- The locker is a chest entry and is drawn by the chests' loop with its model.

### The HUD, the F3 page, the panels

- `hud.odin`: after the pick up block and before the panel block, `if open, is_hatch := field_target_hatch(screen_context, hud); is_hatch { hints := [?]Glyph_Hint{{.Interact, text(open ? "hint_close" : "hint_open")}, {.Inventory, text("hint_inventory")}, {.Pause, text("hint_pause")}} ...; return }`. `field_target_hatch :: proc(screen_context: Screen_Context, hud: Hud_Context) -> (open: bool, is_hatch: bool)`: the field player's `frame_target` through `hatch_state`, as `field_target_is_power_switch`.
- `diagnostics.odin`: `World_Facts` gains `field_session: bool`, `sealed_room_inside: bool`, `sealed_room_oxygen: Oxygen_Supply`. `world_page_lines` appends after the tick line, in a field session only: `sealed_room_line(facts.sealed_room_inside, facts.sealed_room_oxygen)`. `sealed_room_line :: proc(inside: bool, oxygen: Oxygen_Supply) -> string`: "sealed room: inside the pod, oxygen unlimited", "sealed room: inside the pod, no oxygen" or "sealed room: outside". `loop.odin` `world_facts` fills them when `session.simulation.field.enabled` from `sealed_room_at_feet(&world.entities, session_local_player(session).field.position)`.
- `ui_machine.odin`: `.Locker` joins `.Chest, .Capsule` in `machine_area_width`, `machine_area_height` and the sort line (`kind == .Chest || kind == .Locker`); `.Hatch` and `.Crafting_Bench` join the empty case; `.Oxygen_Generator` returns `oxygen_generator_area_size()`'s x and y. `machine_screen`'s station test is `machine_is_crafting_station(machine)`. `machine_slot_region` gains `case .Foundation:` that, for an `.Oxygen_Generator`, calls `oxygen_generator_panel_region(state, content)` and returns `{grid = {activated = -1, focused = -1}}`.
- `oxygen_generator_area_size :: proc() -> [2]f32`: `{slot_grid_width(MACHINE_CHEST_COLUMNS), UI_ROW_HEIGHT}`. `oxygen_generator_panel_region :: proc(state: ^Ui_State, area: Ui_Rectangle)`: one row, `draw_text_fitted` of `text("oxygen_generator_supply_unlimited")` at `UI_BODY_TEXT_SIZE`, left. The machine's name and its wrapped description come first as for every panel.
- `quick_transfer.odin` `machine_transfer_buttons`: `.Locker` with `.Chest, .Capsule` (Take all, Store all).
- The bench: no UI code beyond `machine_is_crafting_station`; its panel is the station mode with `station_categories(recipes, .Hand)`.

### The models (kit scripts, `tools/models/machines/`)

Conventions of 0205: Blender frame in cells (x the front, y = game -z, z up, footprint centred), `B` a box minimum to maximum, `C` a cylinder; each script starts with `kit.expect_footprint`; door openings, cavities and fixture boxes come from `records`, never typed (the values below are what they return, for checking). `records.py` gains: `"slide"` in `PART_MOTIONS`; `Fixture` (machine, cell, rotation, size: the rotated (width, height, depth)) and `Machine.fixtures`, sizes filled in a second pass of `load_machines` from the named records; `fixture_box(machine, index)` returning the box's (minimum, maximum) in the Blender frame like `open_cell_box`. `records_test.py` asserts the shipped pod's fixture 0 box is ((5, -1, 0), (6, 1, 4)) and fixture 2's is ((-5, 2, 0), (-3, 3, 4)). `machines/__init__.py` imports the five and adds them to `MACHINES` after 0205's, in this order: `pod`, `pod_hatch`, `pod_locker`, `crafting_bench`, `oxygen_generator`.

**pod** `{12, 8, 8}`, kind `pod`, no motion. A white hull with a sloped roof, the airlock and cabin cavities, two door openings with pockets the panels rise into, a band, two windows, the bed, a mast with a dish, a roof hatch as the scale cue. Materials science_white, steel_dark, steel, galvanised, mining_ochre, soot, fluids_teal, power_yellow (8).
- hull science_white B (-6, -4, 0) to (6, 4, 6.4), no bevel (12); the cabin cavity `cut` by the bounding box of open boxes 0 to 2, lowered to z -0.01: (-5, -3, -0.01) to (2, 3, 6) (about 20); the airlock cavity by open box 3, (3, -3, -0.01) to (5, 3, 6) (about 20); the door openings by fixture boxes 0 and 1 widened 0.01 on x and lowered 0.01: (4.99, -1, -0.01) to (6.01, 1, 4) and (1.99, -1, -0.01) to (3.01, 1, 4) (about 32).
- roof slab science_white B (-5.6, -3.4, 6.4) to (5.6, 3.4, 8.0) (12); wedges science_white `wedge((-5.6, -4, 6.4), (5.6, -3.4, 8), rise="+Y")`, `wedge((-5.6, 3.4, 6.4), (5.6, 4, 8), rise="-Y")`, `wedge((-6, -3.4, 6.4), (-5.6, 3.4, 8), rise="+X")`, `wedge((5.6, -3.4, 6.4), (6, 3.4, 8), rise="-X")` (32).
- pockets: for each door, centred on its fixture box's x centre c (5.5 and 2.5), `cut` of the hull by (c - 0.11, -0.9, 3.99) to (c + 0.11, 0.9, 6.41) and of the roof slab by (c - 0.11, -0.9, 6.39) to (c + 0.11, 0.9, 7.95) (about 64). The hatch's panel (x ±0.10 with its handles, y ±0.86, top 7.91 when open) stays inside.
- decks steel_dark B (-5, -3, 0) to (2, 3, 0.015) and (3, -3, 0) to (5, 3, 0.015) (24): under the open boxes' shrunk bottom (0.02), on the crater floor.
- band mining_ochre (the orange band of today): (-6.015, -4.015, 4.4) to (6.015, -4.0, 4.8), its mirror at y 4.0 to 4.015, (6.0, -4.0, 4.4) to (6.015, 4.0, 4.8) and its mirror at x -6.015 to -6.0 (48).
- windows: `cut` (-3.6, -4.01, 2.4) to (-1.4, -2.99, 3.6) over the bed with a pane soot B (-3.6, -3.55, 2.4) to (-1.4, -3.45, 3.6); `cut` (-3.0, 2.99, 2.4) to (-1.2, 4.01, 3.6) over the bench with a pane at y 3.45 to 3.55 (56).
- bed (its solid cells x -5 to -1, y -3 to -1, z 0 to 1): frame steel_dark B (-4.95, -2.95, 0) to (-1.05, -1.05, 0.30); mattress galvanised B (-4.9, -2.9, 0.30) to (-1.1, -1.1, 0.42); blanket fluids_teal B (-3.9, -2.92, 0.40) to (-1.08, -1.08, 0.48); pillow science_white B (-4.8, -2.6, 0.42) to (-4.2, -1.4, 0.52) (48).
- back ribs steel `rib_row("Y", -3.4, 3.4, 3, 0.10, (-6.015, 0, 0.3), (-6.0, 0, 6.0), "steel", kit.model_random(machine, "back_ribs"))` (36); mast galvanised C (-4.0, 2.4) z 8.0 to 9.2 r 0.06, 6 sides (20) and dish galvanised `cone((-4.0, 2.4), 9.0, 9.3, 0.04, 0.35, 8, "galvanised")` (about 28); roof hatch (scale cue) `hatch("+Z", (1.5, 0, 8.0), 1.2, 1.2, "steel")` (56).
- door trims power_yellow: front B (6.0, -1.25, 0) to (6.015, -1.0, 4.25), its mirror at y 1.0 to 1.25, top (6.0, -1.25, 4.0) to (6.015, 1.25, 4.25); the inner door's on the airlock face at x 3.0 to 3.015, same y and z (72).
- Body about 600 (booleans approximate), within 800. Nothing in an open box or a fixture box (the decks and trims stop inside the 0.02 shrink). No part, no glow.

**pod_hatch** `{1, 2, 4}`, kind `hatch`, `motion = {kind = "slide", axis = "y", amplitude = 3.95, period_seconds = 0.8}`. Two jambs, a sill, guide rails, cyan strips that glow while open; the panel slides up. Materials steel_dark, hazard_black, galvanised, electric_glow, steel, soot, power_yellow (7).
- Body: jambs steel_dark B (-0.5, -1.0, 0) to (0.5, -0.88, 4.0) and mirror (24); sill hazard_black B (-0.5, -0.88, 0) to (0.5, 0.88, 0.06) (12); rails galvanised B (-0.10, -0.90, 0.06) to (-0.07, -0.86, 3.96), (0.07, -0.90, 0.06) to (0.10, -0.86, 3.96) and their mirrors at y 0.86 to 0.90 (48); strips `strip("+X", (0.5, -0.94, 2.4), 0.08, 0.6, "electric_glow")` and `strip("-X", (-0.5, 0.94, 2.4), 0.08, 0.6, "electric_glow")` (24). About 108, emissive. No header across the panel's path.
- Part (slide, no pivot, `kit.join_part(part, machine)`): panel steel B (-0.06, -0.86, 0.06) to (0.06, 0.86, 3.96) bevel 0.01 (44); viewport soot B (-0.065, -0.25, 2.6) to (0.065, 0.25, 3.2) (12); handles galvanised B (0.06, -0.55, 1.7) to (0.10, -0.47, 2.3) and (-0.10, 0.47, 1.7) to (-0.06, 0.55, 2.3) (24); kick band power_yellow B (-0.065, -0.86, 0.06) to (0.065, 0.86, 0.30) (12). About 92.
- Sweep: the part rises along z only; the rails sit beside it in x, the jambs beside it in y, nothing of the body above z 4, so no phase crosses; the part stays inside x ±0.5 and y ±1 and rises above the height, which the loader allows.

**pod_locker** `{1, 2, 4}`, kind `locker`. A grey cabinet with two doors, yellow front edges and uneven vents. Materials logistics_grey, steel_dark, steel, galvanised, power_yellow (5).
- plinth steel_dark B (-0.48, -0.98, 0) to (0.42, 0.98, 0.12) (12); cabinet logistics_grey B (-0.45, -0.95, 0.12) to (0.40, 0.95, 3.9) bevel 0.03 (44); doors `hatch("+X", (0.40, -0.47, 2.0), 0.86, 3.4, "steel")` and `hatch("+X", (0.40, 0.47, 2.0), 0.86, 3.4, "steel")` (112); edges power_yellow B (0.36, -0.97, 0.12) to (0.42, -0.91, 3.88) and mirror (24); vents steel_dark `rib_row("Z", 3.0, 3.6, 3, 0.04, (0.43, -0.80, 0), (0.45, -0.20, 0), ..., kit.model_random(machine, "left_vents"))` and 2 on the other door at y 0.20 to 0.80, salt `"right_vents"` (60).
- About 252.

**crafting_bench** `{1, 2, 2}`, kind `crafting_bench`. A steel top at 0.8 m on four legs, a shelf, a back board with hanging tools, a vise as the scale cue. Materials steel_dark, steel, galvanised, logistics_grey, power_yellow (5).
- legs steel_dark 0.08 square at (±0.40, ±0.90), z 0 to 1.5 (48); top steel B (-0.48, -0.98, 1.5) to (0.48, 0.98, 1.62) bevel 0.02 (44); shelf galvanised B (-0.42, -0.92, 0.40) to (0.42, 0.92, 0.46) (12); back board logistics_grey B (-0.48, -0.98, 1.62) to (-0.42, 0.98, 1.98) (12); vise power_yellow B (0.25, 0.55, 1.62) to (0.45, 0.80, 1.80) with a jaw galvanised B (0.45, 0.58, 1.66) to (0.48, 0.77, 1.78) (24); tools galvanised `rib_row("Y", -0.8, 0.2, 4, 0.04, (-0.42, 0, 1.70), (-0.38, 0, 1.92), ..., kit.model_random(machine, "tools"))` (48).
- About 188.

**oxygen_generator** `{1, 2, 3}`, kind `oxygen_generator`. A galvanised cabinet with a fan grille and a cyan strip, a teal water tank beside it with a valve wheel, a pipe from the tank's top over to the cabinet. Glows while it supplies a room. Materials steel_dark, galvanised, fluids_teal, electric_glow (4).
- skid steel_dark B (-0.48, -0.98, 0) to (0.48, 0.98, 0.10) (12); cabinet galvanised B (-0.45, -0.95, 0.10) to (0.35, 0.10, 2.6) bevel 0.03 (44); tank fluids_teal C (-0.05, 0.52) z 0.10 to 2.40 r 0.38, 10 sides (36) and cap galvanised `cone((-0.05, 0.52), 2.40, 2.55, 0.38, 0.12, 10, "galvanised")` (about 36); pipe fluids_teal `pipe([(-0.05, 0.52, 2.50), (-0.05, 0.52, 2.80), (-0.05, -0.30, 2.80)], 0.06, ...)` (76) and stub C (-0.05, -0.30) z 2.6 to 2.8 r 0.06, 8 sides (28); strip `strip("+X", (0.35, -0.42, 1.9), 0.5, 0.06, "electric_glow")` (12); grille steel_dark `ring((0.36, -0.42, 1.2), 0.25, 0.03, "steel_dark", axis="X", sides=8, minor_sides=3)` (48) with bars `rib_row("Z", 0.98, 1.42, 3, 0.03, (0.35, -0.62, 0), (0.37, -0.22, 0), "steel_dark", kit.model_random(machine, "grille"))` (36); valve (scale cue) galvanised stem C (0.52, 1.0) x 0.33 to 0.40 r 0.03, 6 sides, axis X (20) and `ring((0.40, 0.52, 1.0), 0.14, 0.025, "galvanised", axis="X", sides=8, minor_sides=3)` (48).
- About 396, emissive.

`tools/make_placeholder_models.py`: remove `pod()` and its `MODELS` entry and the names only it used (`BED_FRAME`, `BED_BLANKET`, `PILLOW`; grep each, `CAPSULE_WHITE`, `CAPSULE_TOP` and `WINDOW` stay for the drop capsule); `git rm data/models/pod.vox`. Running it after the change leaves every other `.vox` byte identical. 0206's list loses the pod (its status line already says the pod's model is written here).

`model_check.odin`: `model_open_cell_problems` gains a parameter `label: string` before the allocator (`"open cells box"` or `"fixture box"`, the detail reading `%s %d (cells %v to %v): ...`), and `check_obj_machine_model` runs it a second time over `machine.fixture_boxes[:machine.fixture_count]` with `"fixture box"`, so no pod geometry stands where a fixture's model stands.

### Docs

- `doc/content.md`, The pod: rewritten for 12 by 8 by 8 (the record's width the front axis, 6 by 4 by 4 m), the four open boxes, the bed, the `fixtures` key (what it lists, the box rule, the pod leaving those cells, `MAXIMUM_POD_FIXTURES`), the airlock of two cells between the hatches, the spawn, hatches closed at a new world, and the old save rule (a pod of another size is replaced at load on a frame of its own at the old floor, players in its box moved into the cabin, one log line; a later change to `fixtures` alone is not remapped). New subsections after it: "Hatches" (kind, footprint, closed solid, open passable with the top row aimable, Interact toggles, the hint, closing refused on a player, the slide motion, saved state) and "The pod's fixtures" (the locker as a 16 slot chest placed by the world, the bench's panel and its role in peaceful and in M15, the generator's panel and supply; all refuse pick up, 0195). The machines line about footprints says 1 to 12.
- `doc/architecture.md`: Frames: the held cells (`machine_held_cells`), the fixtures' own occupants, an open hatch's flags. Simulation: a bullet "Sealed rooms (0198)": `Entities.sealed_rooms`, the flood fill and its seeds, when it is rebuilt, the supply, `sealed_room_at_feet` for M15, derived and never saved. The field session ("The start"): the pod placed with its hatches closed and its fixtures. Save format: `Foundation`'s `hatch_open` and `hatch_toggle_tick` read by name, the pod upgrade at load and its log line.
- `doc/presentation.md`, Machine models: the five OBJ models (the pod no longer voxel), the slide motion and `hatch_open_fraction`, the hatch's strips lit while open, the generator lit while it supplies a room; the model check line (line 138) names the fixture boxes.
- `doc/build.md`, The workbench: the open cells check also covers a pod's fixture boxes.
- `doc/hud.md`, Layout, the glyph bar row: on a hatch the Interact glyph reads "Open" or "Close".
- `doc/input.md` line 109 (Interact): on a hatch Interact opens or closes it, on the field.
- `doc/ui.md`, Recipe browser, Station mode: the crafting bench uses the mode with the hand maker; a line under Other screens (or the machine panel's place) for the oxygen generator's panel.
- `doc/developer_tools.md`, the World row: in a field session, whether the feet are in a sealed room and its supply.
- `doc/code_map.md`: the `entity_pod.odin` line: the pod in its crater with its hatches and fixtures (`place_pod`, `toggle_hatch`), the sealed room (`Sealed_Room`, `rebuild_sealed_rooms`, `sealed_room_at_feet`) and the old pod's upgrade (`upgrade_resized_pods`); the counts `code_graph.py` reports (the world cluster's reach into simulation grows by the calls in `save_state.odin`, accepted as the save codec's).
- `PLAN.md`, M15: "The pod's sealed room (the cabin and the airlock behind its hatches) and its oxygen generator with an unlimited supply exist since 0198; M15 adds the suit's drain reading `sealed_room_at_feet`, the generator's water and rate, and the bench as the place crafting happens in survival."
- `data/machines.sjson` header (above), `tools/check_dead_code.py` if it describes `place_pod`.
- `doc/log/2026-10-03.md`: "The landing pod: airlock, hatches, fixtures, sealed room (0198)", tags `pod, hatch, sealed-room, fixtures, save, models, m14, m15`: the orientation of the record, the footprint maximum, the fixtures key, the four kinds, the hatch's flags and the slide motion, the derived room, closed at start, the rewards staying with the capsule, and the behaviour change for old saves (the pod replaced on a new frame at its old floor, machines a player put round an old pod may now stand inside the larger hull, players inside moved to the cabin, and a pad foundation under an old pod picks up, since the new pod stands on a frame of its own).

### Tests

- `machine_test.odin`:
  - `test_machine_open_cells_are_boxes_inside_the_footprint`: the shipped pod has 4 boxes and `open_cells[3] == Cell_Box{from = {9, 0, 1}, to = {10, 5, 6}}`.
  - `test_a_footprint_side_of_twelve_is_accepted`: a chest of width 12 resolves, 13 is refused with the footprint message.
  - `test_the_pod_fixtures_are_checked`: on a test pod of 6 by 4 by 3 with a cabin box from (1, 0, 1) to (4, 1, 2) and a 1 by 2 by 2 locker record: each refusal of `validate_pod_fixtures` in turn (non pod, nine fixtures, unknown machine, a chest as fixture, rotation 4, a box past the footprint, two overlapping, one on the spawn cells) gives a message containing its key words; a valid list resolves with `fixture_count`, the machine ids and the boxes; the shipped pod has 5 fixtures with fixture 0's box `{from = {11, 0, 3}, to = {11, 3, 4}}` and fixture 2's `{from = {1, 0, 1}, to = {2, 3, 1}}`.
  - `test_the_world_placed_fixture_kinds_are_validated`: a hatch with an item, with `open_cells`, of height 1, with a spin motion; a slide on a chest, a slide of amplitude 0 and 13; a locker with 0 and 33 slots and with an item; a bench with `recipe_maker = "assembler"`, with slots, with an item; a generator with slots, with an item: each refused. The four shipped records pass, and `machine_kind_is_placed_by_world` is true for their kinds.
- `entity_pod_test.odin` (0199's file, its tests updated):
  - `test_place_pod_stands_the_pod_on_its_frame_with_no_pad`: the pod's `machine_held_cells` are the pod's; each fixture's `footprint_cells` at `pod_fixture_placement` are that fixture's handle; `frame_cell_count` stays the footprint's volume (768); the rest as 0199's.
  - `test_pod_fixture_placement_composes_the_rotations`: a test pod of 7 by 4 by 1 with a fixture of 1 by 3 by 1: for each pod rotation and fixture rotation (16 pairs) and each box position inside the footprint, every unrotated fixture cell u lands at the same frame cell placed as `pod_fixture_placement` gives as through the box (`rotate_footprint_cell` of the box cell, then of the pod).
  - `test_place_pod_places_its_hatches_and_fixtures`: two `.Hatch` entries closed with toggle tick 0, a `.Chest` entry of the `pod_locker` machine with 16 empty slots, a `.Crafting_Bench` and an `.Oxygen_Generator` entry, each at its placement; the outer hatch's frame cells are x 0 to 1, z 6, y 0 to 3 (`pod_origin` {-3, 0, -5}); `entity_has_panel` true for the locker, the bench and the generator, false for the hatches and the pod; `field_entity_is_placed_by_world` true for all six.
  - `test_the_pods_interior_is_open_and_its_hull_bed_and_closed_hatches_solid` (replaces the door test): every held cell is solid exactly when not an open cell; every hatch cell is solid; the wall over the outer hatch (y 4), the bed, the roof and a side wall solid; the fixtures' cells solid and theirs.
  - `test_a_hatch_toggles_its_cells`: on the outer hatch, `toggle_hatch` true; rows 0 to 2 have `.Open` and not `.Solid`; row 3 has neither; the cell count unchanged; toggled again, every cell `.Solid` and `hatch_toggle_tick` the second tick plus one; `toggle_hatch` on the locker's handle and on `NO_ENTITY` false.
  - `test_closing_a_hatch_on_a_player_is_refused`: the outer hatch open, a capsule standing in its cells (`field_player_capsule` of a body at the hatch's floor centre): closing false and still open; a capsule centred in the airlock (frame z 4 to 5 boundary): closing true.
  - `test_a_field_player_walks_through_the_pods_door_and_the_walls_stop_it` (0199's, updated): at every spacing of `TEST_FIELD_SPACINGS` (333, 500, 1000), with the outer hatch closed the walk from the door stops at it (the feet's local z stays at least the hatch's outer face, 7 pitches, plus the capsule radius minus `FIELD_GROUND_TOLERANCE`); with both hatches open the player walks through the airlock and the inner hatch into a cabin cell (frame z at most 2), on the ground; the side wall check as 0199's.
  - `test_the_aiming_ray_passes_the_pods_open_cells_and_stops_at_its_walls` (0199's, updated): with the outer hatch closed the ray from the airlock towards the chest outside stops at the hatch; open, a ray at row 1 height reaches the chest and a ray at row 3 height stops at the hatch's top row.
  - `test_a_saved_pod_loads_with_its_open_cells` (updated): over the held cells as before, the fixtures' cells their fixtures' after the load, the occupant count equal.
  - `test_the_sealed_room_follows_the_hatches`: after `place_test_pod`: one room, its cells (sorted y, z, x) equal to `machine_open_cells` of the pod sorted, its supplier the generator and `.Unlimited`; outer open: the cells of boxes 0 to 2 less the fixtures' (box 3's rotated cells removed), still supplied; outer closed and inner open: the open cells plus the inner hatch's 8 cells; both open: no room.
  - `test_the_feet_tell_the_sealed_room`: `sealed_room_at_feet` at `field_pod_spawn`'s feet is inside and `.Unlimited`; at a point 2 m in front of the outer hatch outside; `sealed_room_line` gives the three texts.
  - `test_the_fixtures_refuse_pick_up_and_placement_over_them`: a wooden chest and a foundation through `place_on_frame` on the cell above the bench and on the cell in front of the locker: `Occupied`; with `make_pick_up_test`, `stand_test_player_on_cell` on the bench's top cell and `hold_test_mine` for `PICK_UP_TEST_TICKS + 4`: the bench is alive and the frame's cell count unchanged (the other fixtures' tops lie too close under the roof for the helper's stance; they share the same rule, `field_entity_is_placed_by_world`, asserted above).
  - `test_an_old_pod_is_replaced_at_load`: on the save test simulation, a pod added by `add_entity` on a free frame at the test site with `POD_ROTATION` and its entry's `size` set to {6, 8, 6} (the bytes an older build wrote), a player's body in the old pod's middle; saved and loaded through `save_world` and `load_save_test_simulation`: one alive pod of the record's size on a frame other than the old one, the old frame gone, the five fixtures present, the new frame's origin and axes equal to `free_frame_at(pod_floor_centre(old frame, old origin, {6, 8, 6}), old frame's forward, old pitch)`, the player in a cabin cell, a sealed room present.
- `simulation_field_test.odin`:
  - `test_a_new_world_sinks_the_pod_in_its_crater_and_players_spawn_in_the_cabin` (0199's): unchanged expectations hold; add: both hatches closed and one sealed room.
  - `test_toggling_a_hatch_is_lockstep_state`: two `start_field_test_session` on one seed; on both, after `stage_generated_field_set`, player 0's body is set to `make_field_player(frame_floor_point(frame, 1, 0, 0), frame.axes[FRAME_FORWARD])` (a cabin point on the hatches' centre line, 1.5 m from the inner hatch, which is solid on every row while closed; the spawn itself lies on the hatch's edge line) and gets one `Input_Frame` with `.Interact` just pressed: on both the inner hatch is open, `hatch_toggle_tick` equal, a `.Toggled_Switch` event raised, and `simulation_state_hash` equal after 60 more ticks; a session without the press hashes differently. The opened session round trips through the save path of `test_a_field_world_save_round_trips`: the hatch open with its tick, its cells passable, the room the cabin and airlock plus the inner hatch, and the hash equal to before the save.
  - `test_an_old_save_with_a_pad_still_loads` (0199's): the pod built as in that test gets its entry's size set to {6, 8, 6} before the save; after the load the pod is the new one on a frame of its own standing on the pad's top (its frame equal to `free_frame_at` of the old pod's floor centre as above), the 100 foundations still there, the spawn in a cabin cell of row 0 on the new frame. 0199's "one under the pod refuses `Something_Stands_On_It`" no longer holds, since the new pod stands on a frame of its own and holds no pad foundation up; that expectation goes (named in the log), and "a pad foundation outside the old footprint picks up and returns a foundation" stays.
- `model_motion_test.odin`, `test_a_slide_moves_its_part_by_the_open_fraction`: `motion_transform` of a slide (axis 1, amplitude 3.95) at 0 is the identity, at 0.5 moves y by 1.975, at 1 by 3.95; `hatch_open_fraction`: never toggled, 1 open and 0 closed; toggled open at tick 100 (stored 101) with a period of 0.8 s at 60 Hz: 0 at tick 100 alpha 0, 0.5 at tick 124, 1 from tick 148, rising monotonically; closed the mirror.
- `model_triangle_mesh_test.odin`, `test_the_shipped_obj_machines_load`: five rows, glows false for `pod`, `pod_locker`, `crafting_bench` and true for `pod_hatch`, `oxygen_generator`; `model_check_test.odin` `test_the_shipped_models_pass_the_checks`: the OBJ floor rises by 5 (to `>= 26` on 0205's 21); a new `test_a_body_in_a_fixture_box_is_found`: a body triangle inside a test pod's fixture box gives one `.Open_Cells` problem whose detail starts with "fixture box 0".
- `diagnostics_test.odin`, `test_the_world_page_tells_the_sealed_room`: field facts inside give the "inside the pod" line, outside the "outside" line, block world facts no such line.
- `entity_test.odin`, `test_a_crafting_station_has_a_panel`: adds the bench and the generator (panel) and a hatch (none).
- `ui_audit_test.odin`: `place_missing_machines` steps x by `MAXIMUM_FOOTPRINT_SIZE` (was 8, which the 12 cell pod would overlap); `machines_with_panels` uses `machine_is_crafting_station`, so the generator's panel and the locker's are audited as machine panels; a new case "crafting bench" (`screens = {.Machine, .Recipes}`, `machine` and `station` the bench, `walk_focus`) beside "crafting station".
- Tests that loop over every machine record must hold for the four new ones (the compiler and the suite name them).

Verify commands: `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, `python3 tools/check_dead_code.py`, `python3 tools/models/records_test.py`, `tools/make_models.sh` twice (the second run changes nothing), `./build.sh model-check` over the five, `tools/model_preview.sh` over the five (the implementer reads `front_rest` of each and `front_0.5` of the hatch and reports one line each), `python3 tools/make_placeholder_models.py` then `git status --short data/models` (only `pod.vox` deleted and the new OBJ and MTL files).

### Hand-back lines that apply

- Memory a frame draws from: the rooms' cells are freed and rebuilt inside the tick (`toggle_hatch`, `place_pod`) and at load; the draw and the F3 page read them within the frame and keep no slice (`sealed_room_at_feet` returns a copy of the struct whose cells the caller does not keep; `oxygen_generator_supplies_a_room` returns a bool). No UI pass frees anything.
- Numbers parsed from text: the fixtures' cells, rotations and count, the slide amplitude, the locker's slots and the footprint sides are range checked at load.
- A changed save layout loads an old save: `Foundation`'s fields default to closed and never toggled; an older build's pod is replaced with one log line; `test_an_old_pod_is_replaced_at_load` and the updated `test_an_old_save_with_a_pad_still_loads`; the behaviour change is in the log.
- A long string fitted: the generator's line through `draw_text_fitted`, the description wrapped as every panel's; the audit's smallest size covers the generator's panel through `machines_with_panels`.
- A UI audit case made obsolete: none; the bench case is added beside the station's.
- Tests never touch the machine's state: the save tests use `make_save_test_directory`.
- Not applicable: no file written outside the save path, no start up load that can fail, no shared budget (the supply is unlimited, nothing draws power), no list without bound (one room per pod, at most 768 cells).

### Questions for the main agent

1. Hatches start closed at a new world (answer 8), against 0199's Change line, which spoke of them open until 0200. Closed gives 0200 the sealed start it opens and the airlock walk the couch check describes. Confirm, or name open.
2. The quest rewards stay with the capsule (answer 9). Should a follow up item make the pod's locker the quest state's capsule on a field world? It changes the delivery counting and the texts that name the capsule.
3. Closing a hatch on a player is refused without a toast: a field refusal toast would need Interact counted as a press in `field_refusal_is_news`, which would retell an older refusal on any Interact. Accept silence, or add a refusal key and that change?
4. The room is derived and not saved (answer 7). Confirm that the hatch states being saved meets "the room exists, is saved".

### Approval (main agent, 2026-10-03)

Approved as specified. Answers: 1, hatches start closed at a new world (0199's "open until 0200" is superseded; the first player opens the inner hatch with Interact). 2, the rewards stay with the capsule in this item; work item 0210 makes the pod's locker the quest state's capsule on a field world, so the texts and the delivery counting change there, not here. 3, silence accepted: a hatch that cannot close on a player simply stays open. 4, confirmed: the room is derived from the saved and hashed hatch states, so it exists on every machine and after every load without a layout of its own. The implementer starts on the 0197 tree once 0197 is snapshotted (the stream order), with 0205 landed first so the kit primitives exist.
