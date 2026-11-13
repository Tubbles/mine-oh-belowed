# 0376: The field's pumps draw from nothing

Status: implementing (2026-11-13)

Found by 0356's design: on the field the offshore pump and the tar pit pump have no source check and produce their fluid wherever they stand.

## Goal

A pump produces only where its source is.

## Controls

None.

## Change

- The offshore pump draws from the field's water at its intake (the sea, a lake, a body), the tar pit pump from its deposit, each refused or idle elsewhere with the reason shown.
- What drawing does to the water it draws from (a lake's level, a body's volume) is decided in the design against the water models and 0370.

## Verify

- The checks and the suite.

## Specification (design, 2026-11-13)

Designed against `main` at 63befd45 (0356 landed). No control changes. The offshore pump only: on a field frame the tar pit pump still draws from nothing until tar pits exist there (0391, Decisions).

### The rule

- Scope: offshore pumps on a field frame (`common.frame != BLOCK_FRAME`). One on the block frame (every block world, the benchmark's modules, which stand on frame 0 of its field world) keeps the block rule, checked at placement only, and is never read here.
- The intake: the cell in front of its intake end, `offshore_pump_intake_cell(origin, machine, rotation)` on its frame, as the block world. From that cell's centre (`frame_cell_centre`) the reading walks down along the frame's up a sample at a time (`nearest_field_sample` of the centre less `up × k` samples, k from 0 to `ceil(FIELD_OFFSHORE_INTAKE_REACH_MILLIMETRES / spacing)`, a sample equal to the one before skipped), adding each sample's water byte, the first ground sample (density above 0) ending it. Wet when the sum reaches `FIELD_OFFSHORE_INTAKE_DEPTH_MILLIMETRES` (`water × spacing ≥ DEPTH × FIELD_WATER_FULL`), else Dry. Any field water counts: the sea's, a lake's, a body's, front water; the owner plane is not read, since a body's bytes are its level's fill under both models. A stream's sheet (0.2 sample) does not count, a pool in it does.
- When: at placement (refused, the block world's precedent) and every tick after the water step (idle with the reason), since the field's water changes after placement: a dig drains a lake through a breach, a teleport lake runs out at the set's edge (0370), the tech demo's buckets and water pump. The read takes one to eight sample lookups a pump a tick (2 m at 1 m spacing is three samples, at 333 mm eight).
- Drawing takes nothing from the water (Decisions, 1).

### Lockstep, loads and pumps far from every player

- State: the water bytes of the loaded chunks (and under bodies the owner plane and the body table), saved and hashed; a chunk outside the set holds its water frozen (its saved bytes in `saved_chunks`, or the generation's when no tick changed it), and frozen water never changes, since only moving water inside the set leaves at its edge (0370) and a frozen body part's bytes wait for the thaw. The pump's answer is state: `Fluid_Machine.source`, in `entities.bin`, saved and hashed, so a joiner and a load hold it.
- The read: every tick, for every pump; a walk that reaches a sample in a chunk not loaded before it decides leaves the pump's answer as it was, which is the frozen water's answer, and the tick the chunk returns reads it. The set is lockstep state, so every machine reads alike on the same ticks.
- Derived from the seed: only an old save's pump (Unread) whose column is not loaded on its first tick reads the generation's water for the missing samples (`field_water_outside`, 0370: -1 for ground and a world without a planet, else the sea's or a lake's fill), once.

### Machine state, panel, HUD

- `Missing` is checked first in the advance: the pump shows `No water` (`machine_state_no_water`, existing) whatever its power, fills nothing, asks no power, wears nothing and does not count as operating. The panel's state line and the crosshair's line (`fluid_status_text`: "Offshore pump  No water") show it; the marker is red (No_Water is already red).
- Placement: the ghost is red (`field_placement_refusal`) and Place toasts `field_refused_no_water_at_intake` "An offshore pump needs water in front of its intake". The tool line over bare ground stays "wears out", as for a drill off a vein.
- Chapter 4's quest text on a field world names the water (Quests below).

### Code

`src/fluid_machine.odin`:

- `Pump_Source :: enum u8 {Unread, Present, Missing}` before `Fluid_Machine`. `Fluid_Machine.source: Pump_Source` after `water_pump`, its comment: an offshore pump's water on a field frame (0376, `field_offshore_pump.odin`); Unread on the block frame, for every other kind, and in a save from before 0376 until the first field tick; saved by name.
- `advance_offshore_pump`: first case `pump.source == .Missing: pump.state = .No_Water`. `advance_tar_pit_pump` unchanged.

`src/power_network.odin`, `fluid_machine_wants_power`: `.Offshore_Pump` returns `fluid_machine.source != .Missing && source_pump_has_room(fluid_machine, machine)`; `.Tar_Pit_Pump` keeps `source_pump_has_room`; the comment names the offshore pump's water.

`src/field_offshore_pump.odin` (new, simulation cluster after `field_water_pump.odin`; head comment: the field's offshore pumps and their water, 0376, doc/fluids.md, Fluid machines; imports `platform`):

- `FIELD_OFFSHORE_INTAKE_REACH_MILLIMETRES :: 2000` (the block world's "its height or one below" over two 1 m blocks), `FIELD_OFFSHORE_INTAKE_DEPTH_MILLIMETRES :: 500` (a submerged intake; a film, a puddle and a stream's sheet fall short). Code constants, as 0295's `WATER_PUMP_INTAKE_CLIMB`: geometry of the rule, not tuning.
- `Offshore_Intake_Reading :: enum u8 {Unloaded, Dry, Wet}`.
- `read_offshore_pump_intake :: proc(world: ^Field_World, spacing_millimetres: int, frame: Frame, intake_cell: World_Coordinate, generation: bool) -> Offshore_Intake_Reading`: the walk of The rule; a sample whose chunk is not loaded reads `field_water_outside(world, sample, field_water_span(sample))` when `generation` (below 0 ends the walk as ground), else returns `Unloaded`.
- `field_offshore_pump_refusal :: proc(state: ^Simulation_State, content: Simulation_Content, machine: Machine_Id, frame: Frame, cell: World_Coordinate, rotation: u8) -> Field_Edit_Refusal`: for an offshore pump `None` when `read_offshore_pump_intake(..., offshore_pump_intake_cell(cell, definition, rotation), generation = false)` is Wet, else `No_Water_At_Intake` (Unloaded too); `None` for any other machine.
- `mark_offshore_pump_source_present :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle)`: a live offshore pump off the block frame gets `source = .Present` (its placement just passed the refusal); nothing for another handle.
- `refresh_offshore_pump_sources :: proc(state: ^Simulation_State, content: Simulation_Content) -> (old_missing: int)`: the fluid machines in pool order, alive, of kind offshore pump and off the block frame (the frame found with `find_frame`, else skipped): Wet `Present`, Dry `Missing`, Unloaded unchanged, read with `generation = source == .Unread`. Counts the pumps that were Unread and are now Missing and, when above 0, logs `save: %d offshore pumps on the field found no water at their intake and stand idle (0376)`; each pump is Unread once, so the line comes once a load.

`src/field_mining.odin`:

- `Field_Edit_Refusal` gains `No_Water_At_Intake`, last, comment "an offshore pump's intake on a field frame meets less than half a metre of water (0376, field_offshore_pump_refusal)"; `field_refusal_keys` gains `field_refused_no_water_at_intake`.
- `finish_field_tick`: `refresh_offshore_pump_sources(state, content)` right after `step_field_water_keeping_events`, inside the Field_Water section; the head comment says the offshore pumps' intakes are read after the water.

`src/entity_frames.odin`:

- `field_placement_refusal`: the bare ground branch returns `bare_ground_placement_refusal`'s refusal when it is not None, else `field_offshore_pump_refusal(state, content, placement.machine, frame, cell, placement.rotation)`; the snapped path returns the same in place of its final `None`, after `Would_Bury_Player`. Its comment names the offshore pump.
- `apply_field_placement`: after the water pump's settle, `mark_offshore_pump_source_present(entities, content.machines, handle)`.

`src/developer.odin`, `place_on_frame_for_developer`: after the bury check, a `field_offshore_pump_refusal` other than None returns `field_refusal_keys[refusal]` (as the cable path returns its key); the handle `place_on_frame` returns is marked with `mark_offshore_pump_source_present`.

`src/loop_planet_preview.odin`, `field_edit_refusal_text`: `.No_Water_At_Intake` "  an offshore pump needs water in front of its intake".

`data/strings/en.sjson`: `field_refused_no_water_at_intake = "An offshore pump needs water in front of its intake"` after `field_refused_cable_end_gone`; `quest_steam_text_field` after `quest_steam_text` (Quests below).

No data keys.

### Old saves, kits, quests

- `Fluid_Machine.source` is read by name: a save from before reads Unread, and the first field tick reads it (a column outside the set from the generation). An offshore pump standing off water (it was placed anywhere) stops at No water, with the log line above. No production is lost today: a port on a field frame joins no netlist until 0374 (fluids.md, Fluid netlists), so such a pump only filled its own 200 L port.
- Kits: `data/dev_kits.sjson` gives the offshore pump in chapters 4 and 5 as items and places nothing. None breaks.
- Quests: chapter 4's `place offshore_pump` (quest `steam`) on a field world now needs water: no lake lies within 250 m of the home, and at 8 km the tiles within 1500 m hold 41 (content.md, the shipped `home`); the record springs' streams are sheets that do not count until pooled. Its text `quest_steam_text` says only "an offshore pump at the water", which on the field leaves a player at the pod, whose plain is dry for every seed (the landforms' calm circle), with a red ghost. A field variant (`field_variant_key`, 0263) names it: `quest_steam_text_field = "The offshore pump needs power: place a fuel generator, give it coal and run a light cable from it to the pump. Then an offshore pump at a lake or the sea, with open water in front of its intake: the plain round the pod is dry. Then a boiler fed by it and a steam engine fed by the boiler. The steam engine recipe came with the schematics."` No hint or note names the offshore pump. The quest chapter tests run on the block world and are unchanged.
- The benchmark's power module stands on the block frame: never read, unchanged.

### Tests

`src/field_offshore_pump_test.odin` (new). Fixture `make_offshore_pump_test_state :: proc(model: Water_Model) -> (state: Simulation_State, content: Simulation_Content)`: `make_water_test_world()` or `make_body_test_world()`; air over the land, `carve_water_test_box(world, water_test_sample({0, 12, 0}), water_test_sample({31, 31, 31}))` (the land's surface between local y 11 and 12); the pond, air at `{16, 8, 4}` to `{23, 11, 11}`, full water `{16, 8, 4}` to `{23, 10, 11}` (`pour_test_water`), settled (`settle_test_water` or `settle_body_test_water`, one body under bodies); the content, tuning (`dry_ticks = 1_000_000`), pitch 1000, bare ground tuning and spacing 1000 as `make_water_tool_test_state`; a miner at `FAR_FEET` holding 3 offshore pumps and 1 tar pit pump. `offshore_pump_test_pier(t, state, content, column: Sample_Coordinate) -> Frame_Id`: a free foundation (`place_free_foundation`, heading `{UNIT_VECTOR_ONE, 0, 0}`, pitch 1000) whose hit is the top of `column`'s sample along the radial (its position plus half a sample along the normalised position), and a second foundation at `{1, 0, 0}`. A pump queued at `{0, 1, 0}`, rotation 0, on such a pier stands one cell over its floor and its intake cell's centre half a pitch higher: over the pond's pier (`column` `{19, 10, 7}`, the water's top) the walk reads y 12, 11 (air) and 10 (full); the intake lies 2 m from the hit along the frame's right, inside the pond for any yaw (the hit 3 to 4 samples from every wall). The dry pier's column is `{6, 11, 24}`, the land's top.

- `test_an_offshore_intake_reads_the_water_under_it` (teleport): `read_offshore_pump_intake` on a hand built `Frame` (identity axes, pitch 1000) whose cell `{2, 0, 0}` centre is the centre of a chosen sample: `{19, 12, 7}` Wet; `{6, 12, 24}` (land under it) Dry; `{19, 13, 7}` (the water three samples down, past the reach) Dry; with `{19, 10, 7}` set to 127 Wet and to 126 Dry (the walk ends at y 10); the chunk detached (`field_world_detach_chunk`), `generation` false Unloaded and true Dry (no planet: -1); then reinserted.
- `test_a_field_offshore_pump_is_placed_only_over_water` (both models): on the pond's pier the drained placement leaves `field_refusal` None, one live offshore pump with `source == .Present`; on the dry pier `No_Water_At_Intake` and no second pump; the miner holds one offshore pump fewer after the three placements; a bare ground placement (`new_frame`, the hit on the land at `{6, 11, 24}`'s top, `field_footprint_origin({}, footprint, 0)`) `No_Water_At_Intake`, and `frame_ghost_color(field_placement_refusal(...)) == GHOST_INVALID_COLOR`.
- `test_a_field_offshore_pump_stops_when_its_water_is_gone` (teleport): the pump placed on the pond's pier, powered (`power.satisfaction = POWER_FULL`); refresh and `advance_fluid_machine`: Producing, its buffer above 0. Every pond sample set to 0 (`set_field_water`): refresh Missing; advance `No_Water`, the buffer unchanged, `fluid_machine_wants_power` false, `fluid_status_text` ending in `text("machine_state_no_water")`. Poured full again: refresh Present, advance Producing.
- `test_an_offshore_pump_beyond_the_set_keeps_its_answer` (teleport): the placed pump Present; its chunk detached: refresh returns 0 and keeps Present; the detached chunk's pond bytes set to 0 and the chunk reinserted: refresh Missing; detached again: Missing kept.
- `test_an_old_saves_offshore_pump_reads_once`: offshore pumps added with `add_entity` (Unread) on the pond's pier and on the dry pier: refresh returns 1, Present and Missing; a second refresh 0. In a second fixture state with `water_planet = water_test_sea_planet()` (a missing sample there is sea), an Unread pump on the dry pier with its chunk detached: Present (the generation's sea, read once).
- `test_pumps_the_offshore_rule_leaves_alone`: an offshore pump added on `BLOCK_FRAME` at `{0, 40, 0}`, and a tar pit pump placed on the dry pier (its refusal None, Decisions 2): refresh leaves both Unread; powered, both advance to Producing.
- `test_the_developer_place_refuses_an_offshore_pump_off_water`: `place_on_frame_for_developer` on the dry pier returns `field_refusal_keys[.No_Water_At_Intake]` and places nothing; on the pond's pier returns "" and the pump is Present.
- `test_an_offshore_pumps_source_round_trips`: a Fluid_Machine with `source = .Missing` through `write_value_of` and `read_value_of` reads back Missing (0295's pattern).
- `data_strings_test.odin`: `FIELD_VARIANT_BASE_KEYS` gains `"quest_steam_text"`, so `test_shipped_field_variants_have_a_base_and_name_the_pod` asserts the variant exists, has its base and names no capsule or pad.
- Covered as they stand: the refusal string by `data_strings_test.odin` and the UI audit's loop over `field_refusal_keys`.

### Docs

- `doc/fluids.md`, Fluid machines: the offshore pump's bullet gains the field rule (the intake's walk, its reach and depth, refused at placement, read each tick while loaded and held while not, No water asking no power, draws free, the block frame's pumps on the block rule) and an old save sentence with the log line; the tar pit pump's bullet gains "On a field frame it still draws from nothing until tar pits exist there (0391)."
- `doc/architecture.md`: The water field, the step's bullet: the field's offshore pumps read their intakes right after the step (fluids.md); Save format: `Fluid_Machine.source` by name, Unread before 0376, resolved on the first field tick.
- `doc/code_map.md`: `field_offshore_pump.odin` after `field_water_pump.odin`; `field_mining.odin`'s line names the intakes' read after the water.
- `data/machines.sjson` header, the offshore pump's paragraph: "on a field frame, half a metre of the field's water within 2 m under its intake cell's centre (0376)".

### Hand-back check

- Save layout: the field by name, Unread before; the first tick resolves it with one log line; the behaviour change (old offshore pumps off water stop) named in the log section; kits checked above.
- Shared budget: an offshore pump without water leaves its network's demand, so the other consumers there get more; nothing joins a budget.
- Strings: the toast fits at the smallest audit size (the existing loop); the quest variant is wrapped by the journal as its base is.
- Tests: in-memory worlds only.

### Decided

1. Refused at placement and idle each tick: placement is the block world's precedent and tells the player at once; the tick's read follows water dug, drained or run away after it.
2. Read every tick while the column is loaded, held while not: a few lookups a pump, and no event bookkeeping on the water's writes.
3. The bytes decide, not the owner: the same read under both models, front water included.
4. No hysteresis: a teleport surface waving at exactly half a metre can flip a pump between Producing and No water; accepted as a known limit.
5. An Unread pump reads the generation once where its column is not loaded, so an old save's pump at a lake beyond the set keeps running, and one off water stops at once.
6. The developer's place refuses as Place does, with the key.

### Decisions (main agent, 2026-11-13)

1. Draws stay free. For the log: a pump that lowers its water needs its own item, since under teleport a draw rewrites loaded samples only, so a pump beyond every player's set would stop or draw from nothing, under bodies the pump would have to follow its body across merges, splits and refloods, and which water is endless (the sea, a spring's lake, a generated lake) is a rule of its own.
2. Tar: the tar pit pump on a field frame stays as it is today, producing wherever it stands, until tar pits exist on the field; refusing it everywhere would take the oil chapter from every field playthrough, a larger change than this defect. This item touches only the offshore pump. The main agent writes item 0391 "tar pits on the field" as todo.
3. Chapter 4 on a field world needing a lake or the sea, the nearest at least 250 m from the home: accepted, with `quest_steam_text_field` naming the water.
4. Hysteresis after all (replaces design decision 4 above): a pump with water keeps it while the walk holds at least 0.5 m, a pump without needs 0.75 m to start again, both as data keys beside the depth key with the same bounds, and placement asks for the starting depth. `Fluid_Machine.source` already carries which side the pump is on, so no state is added. A wave at the threshold must not blink the pump's state and model every tick. One test: a surface stepping between 0.45 m and 0.55 m every tick leaves the pump's state unchanged from either side.
5. Approved with these.
