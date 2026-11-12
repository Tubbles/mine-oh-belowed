# 0362: The field session draws every machine

Status: implementing (2026-11-12)

Found by 0347's design: `draw_fluid_entities` and `draw_power_entities` are called only from the block world's pass (`loop.odin`), so on a field world a boiler, a steam engine, a pipe, a pump, a tank, a lamp and a pole are placed and simulated and never drawn. And `draw_drill`'s bar and arrow and `draw_launch_pad`'s fallback platform, tower and rocket draw in raw cells without their frame's matrix, so on a planet they land near its centre.

## Goal

Everything placed on a field world is drawn where it stands.

## Controls

None.

## Change

- The field session's entity pass draws the fluid and the power machines under their frames' matrices, lit and hazed as the other machines.
- The drill's bar and arrow and the launch pad's fallback take their frame's matrix.
- After 0347, through its instance list, and with 0355 in mind: the poles leave the content there, and a cable's draw is that item's.

## Verify

- The checks and the suite, with a test that every machine kind of the shipped table reaches the field session's draw list.
- Captures of a boiler, a steam engine, a tank and a drill on the tech demo's planet, sent to the user.

## Specification (design, 2026-11-12)

Designed against `main` at `85e046f`. Presentation only (checked at the end). No control, binding, setting, data key or shader change.

### Every machine kind, today and after

"Instanced": the scene's instance list (`emit_posed_model`). "Flat": rlgl's batch through the model shader's flat mode (0360), unlit and hazed. Every row's draws go under the entity's frame's matrix after this item. Every machine has a model but the belts, the pipe, the foundations, the belt pole and the vessel kinds.

| kind (ids) | pool | field today | field after |
| --- | --- | --- | --- |
| chest (2), locker | chests | instanced | unchanged |
| furnace (stone, steel), capsule, schematic crate, lab, core sample drill, crafting machine (11) | own pools | instanced | the crafting machines' fluid ports added (flat) |
| inserter (5) | inserters | the arm instanced, a held item flat | unchanged |
| drill (burner, electric; bore never stands on a frame, No_Vein) | drills | model instanced; arrow and a modelless bar in raw cells, culled away inside the planet | arrow and ports flat, a modelless bar flat |
| launch pad | launch_pads | model instanced; tower and rocket (and a modelless platform) in raw cells, culled away | flat; a launching rocket after the opaque scene; ports flat |
| splitter | splitters | not drawn (`draw_belts` is the block world's) | model instanced, arrow flat; no belt halves |
| boiler (glow), storage tank (none), flare stack (glow), fuel generator (glow) | fluid_machines | not drawn | model instanced, still caster; ports flat |
| steam engine, combustion generator, hydro turbine (spin); offshore pump, pump, tar pit pump, water pump (bob) | fluid_machines | not drawn | model instanced, moving caster; ports flat, the arrow of the three with `fluid_machine_has_arrow` flat |
| small pole, big pole, substation, power switch | poles | not drawn | model instanced, still caster; no wires |
| lamp | lamps | not drawn | model instanced, still caster |
| hatch, crafting station, crafting bench, charge controller | foundations | instanced | unchanged |
| pod | foundations | `DrawMesh` alone | unchanged |
| foundation (3) | foundations | `draw_field_foundations` | unchanged |
| vessel part (8), control unit | vessel_parts | boxes, flat | unchanged |
| belt (6), belt pole, pipe | belts, belt_poles, pipes | runs and poles (`draw_belt_runs`); no cell belt or pipe stands on a field world (`field_tool_for_item`, `machine_takes_placement_command`) | unchanged |
| tree | none | `draw_field_trees` | unchanged |

### Decisions

1. **The splitters', fluid machines', poles' and lamps' bodies join `draw_entities`** on both worlds, inside its first flat region after the launch pads, in pool order. The field's scene and the sun's cast pass then take them with every other machine: the same cull (`model_frame_draws_entity`, the posed box against `Model_View`), the same instancing, light (the open sky) and haze. A modelless fallback is a flat box. None of their models is the pod, so the region holds no `DrawMesh`.
2. **Every box a pool draws on a frame goes under the frame's matrix** through one pair, `begin_entity_cells_draw` and `end_entity_cells_draw`: cull the box in the frame's cells under the matrix (`model_frame_shows_cells`), push the matrix (the block frame's identity skipped, as `draw_entity_cells` does), pop. `draw_entity_cells`, `draw_inserter` and `draw_vessel_part` keep their own inline pushes.
3. **The ports and arrows leave the bodies' draws** for `draw_ports_and_arrows`, called by the field's scene after `draw_entities` and by the block world in place of `draw_fluid_entities`' ports. They are signs, not bodies: never in the sun's pass (a 3 cm square and a line cast nothing useful). This also keeps `draw_entities` free of rlgl calls for a machine with a model, which the coverage test needs.
4. **The launching rocket** (the only translucent box: `rocket_ascent`'s alpha) stays out of `draw_entities` in the scene and the sun's pass, and is drawn by `draw_launching_rockets` after the players, before `clear_model_open_sky`, in a flat region of its own with the depth test on and depth writes off. Drawn in `draw_entities`' region it is flushed before the instanced machines and the trees and its depth would hide what stands behind it (0360's note). Assembling and ready it is opaque (alpha 255): drawn in the region with depth, and it casts. Launching it casts nothing. The block world keeps drawing it inline.
5. **Poles, switches and lamps**: their bodies are `draw_pole` and `draw_lamp` from `draw_entities`' pool loops, so 0368 deletes the pole and substation branches of `draw_pole` and gives the junction box its look there, and keeps the loops. The wires stay the block world's (`draw_wires`): a field pole draws none until 0368 replaces wires with cables on both worlds. `draw_power_entities` goes.
6. **The splitter's belt halves stay the block world's** (`draw_splitter`, the belt texture through `DrawModelEx`, unlit, unhazed, and a `DrawMesh` the flat region forbids). A field world holds no cell belt, so its splitter feeds nothing; it draws its model and arrow.
7. **The motion's phase offset takes the frame** (`motion_phase_offset`). A machine on bare ground stands at `field_footprint_origin({}, …)` of a frame of its own, so every steam engine or pump of one rotation on bare ground shares a cell and today would turn in step: a perceivable repetition. Frame 0 keeps today's value, so the block world is unchanged. The cadence stays the tick clock's (`clock_pose`: `frame.tick`, `alpha`, `tick_rate`); the drill's bar and the rocket follow their machines' tick counters. None reads the frame time or the cheat speed.
8. **A record's lamps shine on every pool `draw_entities` draws**: `gather_machine_lights` gains the fluid machines, the poles (a switch while on) and the lamps (while lit), each by the flag its draw uses. No shipped record of these lists `lights`, so nothing changes on screen; the rule in `data/machines.sjson` and `doc/content.md` loses the fluid and power machines from its exceptions.
9. **The kept sun shadow map needs no new key.** A placement or a removal occupies or vacates frame cells (`add_entity` → `occupy_entity_cells` → `occupy_frame_cell`), which moves `Frame_Table.revision`, so the kept map recentres and draws the new still casters (the glow and still kinds, the poles, the switch, the lamp, the splitter). A switch's state, a lamp's light and a glow change emissive colour only, never depth. The spin and bob kinds are moving casters (`sun_shadow_entity_moves`: motion neither None nor Glow), drawn over the copy every frame.

### Files and procedures

`src/render_entities.odin`:
- `PORT_AND_ARROW_MARGIN_CELLS :: 0.1`, `PORT_AND_ARROW_RISE_CELLS :: 0.2`: today's literals of `draw_drill`'s cull box (`low - margin`, `high + {margin, rise, margin}`).
- `begin_entity_cells_draw :: proc(frame: Model_Frame, frame_id: Frame_Id, low, high: [3]f32) -> (shown: bool)` and `end_entity_cells_draw :: proc(frame_id: Frame_Id)`: decision 2.
- `drill_bar_ends :: proc(drill: Drill, machine: Machine, tick_rate: int) -> (start, end: [3]f32)`: today's bar in the frame's cells (the top centre plus 0.02, ± half `DRILL_BIT_LENGTH` turned by `drill_progress_fraction` × `DRILL_BIT_TURNS_PER_CYCLE` turns).
- `draw_drill`: returns after `draw_entity_cells` when the drill has its model (no rlgl call); else the bar between `drill_bar_ends` inside `begin_entity_cells_draw` with the margin box. The arrow leaves.
- `Launch_Pad_Boxes :: struct {platform_centre, platform_size, tower_centre, tower_size, rocket_centre, rocket_size: [3]f32, rocket_color: rl.Color, rocket: bool}` and `launch_pad_boxes :: proc(pad: Launch_Pad, machine: Machine, tick_rate: int) -> Launch_Pad_Boxes`: today's three boxes in the frame's cells; `rocket` while Assembling, Rocket_Ready or Launching; `rocket_color` is `ROCKET_COLOR` with `rocket_ascent`'s alpha.
- `draw_launch_pad`: the model, then inside `begin_entity_cells_draw` (today's box up to the ascent) the platform without a model, the tower and the rocket, the rocket left out while Launching when `frame.view != nil || frame.casters != nil`.
- `draw_launching_rockets :: proc(world: ^World, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame)`: nothing unless a pad launches; else `begin_flat_batch`, `rlgl.DrawRenderBatchActive`, `rlgl.DisableDepthMask`, each launching rocket inside `begin_entity_cells_draw` with its box, `rlgl.DrawRenderBatchActive`, `rlgl.EnableDepthMask`, `end_flat_batch`.
- `Machine_Arrow :: enum u8 {None, Drill_Output, Flow, Splitter}`.
- `draw_entity_ports_and_arrow :: proc(common: Entity_Common, machine: Machine, buffers: []Fluid_Buffer, fluids: Fluid_Registry, frame: Model_Frame, arrow: Machine_Arrow)`: nothing for no port and no arrow; else inside `begin_entity_cells_draw` with the margin box `draw_fluid_ports`, then `draw_drill_arrow` (at the footprint's top plus 0.02, `DRILL_ARROW_COLOR`), `draw_direction_arrow` (`FLUID_MACHINE_ARROW_COLOR`) or `draw_splitter_arrow` (`SPLITTER_ARROW_COLOR`).
- `draw_ports_and_arrows :: proc(world: ^World, machines: Machine_Registry, fluids: Fluid_Registry, models: Model_Renderer, frame: Model_Frame)`: in a flat region when `model_frame_flat_batch`; the drills (Drill_Output), the assemblers and the launch pads (None), the fluid machines (Flow when `fluid_machine_has_arrow`), the splitters (Splitter, nil buffers).
- `fluid_machine_model_working :: proc(fluid_machine: Fluid_Machine) -> bool` (the expression `draw_fluid_machine` uses today) and `pole_model_working :: proc(pole: Pole, machine: Machine) -> bool` (a power switch that is on), beside the other `*_model_working`.
- `draw_entities`: loops for `splitters` (`draw_splitter_body`), `fluid_machines` (`draw_fluid_machine`), `poles` (`draw_pole`), `lamps` (`draw_lamp`) after the launch pads, each behind `model_frame_draws_entity`; header comment updated.
- `gather_machine_lights`: the fluid machines, the poles and the lamps (decision 8). Today's 0362 comments in `draw_drill` and `draw_launch_pad` go.

`src/render_fluids.odin`: `draw_fluid_machine` draws the body only (`draw_entity_cells` with today's colours and `fluid_machine_model_working`). `draw_fluid_entities` becomes `draw_pipes :: proc(world: ^World, machines: Machine_Registry, fluids: Fluid_Registry)`, the pipes alone. Header comment updated.

`src/render_power.odin`: `draw_pole` and `draw_lamp` draw their fallbacks inside `begin_entity_cells_draw` with the entity's cell box; `draw_pole` takes `pole_model_working`. `draw_power_entities` goes.

`src/render_belts.odin`: `draw_splitter_body :: proc(splitter: Splitter, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame)`: the model, else today's wire frame inside `begin_entity_cells_draw`. `draw_splitter :: proc(renderer: ^Belt_Renderer, splitter: Splitter)` keeps the halves. `models` leaves `draw_belt_surfaces` and `draw_belts` (and the call in `loop.odin`).

`src/model_motion.odin`: `motion_phase_offset :: proc(origin: World_Coordinate, frame: Frame_Id = BLOCK_FRAME) -> f32`, `u32(frame) * 0x27D4EB2F` xored into the first line. `src/render_models.odin`: `clock_pose` passes `common.frame`.

`src/loop_field_session.odin`, `draw_field_scene`: `draw_ports_and_arrows(world, scene.content.machines, scene.content.fluids, scene.models, machines_frame)` after `draw_entities`; `draw_launching_rockets(world, scene.content.machines, scene.models, machines_frame)` after `draw_field_players`, inside its pod transform. Header comment names both.

`src/loop.odin`, `draw_session_world`: `draw_ports_and_arrows`, `draw_pipes` and `draw_wires` in place of `draw_fluid_entities` and `draw_power_entities`.

### Tests

`src/render_entities_test.odin` (new), in memory, no GL:
- `test_every_machine_kind_reaches_the_fields_draw_list`: the shipped table (`make_test_machines`), a pad (`lay_test_pad`) and one entity of every record on its frame by `add_entity`, at cells 13 apart, except the runs' kinds (belt, belt pole, pipe), the tree, the foundation, the pod (`DrawMesh`) and the launch pad (its tower is rlgl's batch; the next tests and its pool's model of 0347 cover it), excluded by a `#partial switch` on the kind so a new kind is placed by default. Every machine gets a stand-in model (vertex counts and unit bounds, the arm's parts for the arm machines, as `test_uploaded_model`). `draw_entities` with `Model_Frame{open_sky, tick_rate = 60, instances, frames = frame_matrix_table}` and no view. Asserts: each placed entity has an instance of its machine whose translation lies in its cells' box under its frame's matrix grown a cell (`transformed_box`, `point_in_posed_box`); the pad's cells are in `build_foundation_bricks`.
- `test_a_drills_bar_lands_at_the_drill_on_its_frame`: a burner drill on a pad at `TEST_SITE_RADIUS_METRES`; at progress 0 and half a cycle, both of `drill_bar_ends` under `entity_frame_matrix` lie in the drill's box under it, grown 0.5 cells, over 1000 m from the planet's centre, and the two progresses give different ends.
- `test_a_launch_pads_tower_and_rocket_stand_on_its_frame`: a launch pad on a pad; Waiting_For_Parts no rocket; Assembling at half, Rocket_Ready and Launching at half: under the frame's matrix the tower's centre lies over the first cell's column (its box up to `LAUNCH_TOWER_HEIGHT`), the rocket's over the footprint's centre column; alpha 255 but at Launching, where it is under 255.
- `test_fluid_and_power_machines_cast_still_or_moving_by_their_motion`: `sun_shadow_entity_moves` false for the boiler, the storage tank, the small pole, the power switch, the lamp and the splitter, true for the steam engine and the pump; `add_entity` of a boiler on a frame moves `Frame_Table.revision`.
- `test_the_fluid_and_power_pools_gather_their_lamps`: hand made records of a boiler, a power switch and a lamp with one lamp each, entries by `pool_add`: working (Producing, on, lit) gathers three lights, idle none.

`src/model_motion_test.odin`: `test_a_machines_phase_offset_takes_its_frame`: frame 0 equals the one argument form at three cells; frames 1 to 16 at cell 0 give 16 offsets different from each other and from frame 0's; two working steam engines at one cell on frames 1 and 2 get different `clock_pose` phases at one tick.

### Docs

- `doc/presentation.md`, Frame order: the block world's order becomes the machines (every pool), the bottleneck markers, the ports and arrows, the pipes and the wires, belts, and on.
- `doc/presentation.md`, The field session, the scene bullet: the ports and arrows after the machines; a launching rocket after the players without writing depth.
- `doc/presentation.md`, Light on the field: the haze bullet's flat list gains the fallback boxes, the ports and arrows, a drill's bar and the launch pad's platform, tower and rocket; the shadow bullet's "Not drawn" gains the ports and arrows and a launching rocket.
- `doc/presentation.md`, Machine models: one sentence that `draw_entities` draws every pool on both worlds (decisions 1, 2, 5, 6), and in the motion sentence the offset by cell and frame (decision 7).
- `doc/content.md`, Models, the lamps bullet, and the header of `data/machines.sjson`: the exceptions are an inserter (its lamp is `arm_point_light`) and a tree.
- `doc/code_map.md`: the presentation entries of `render_entities.odin` and of `render_belts.odin`, `render_fluids.odin`, `render_power.odin`; the header's test file count.
- `tools/frame_profile_views.sjson`: `factory_large`'s comment (its machines were the ones drawn before 0362). The `factory` view now draws its boiler, steam engine, poles and lamp, so its numbers before and after this item differ by those five.
- `SUGGESTIONS.md`: the 0360 line on the rocket goes at the landing.

### Captures (main agent)

Start as `tools/frame_profile.py` does (`GAME_FLAGS`, a new world of the shipped seed on the default planet, the tech demo's planet), then its `preparation_lines`. Lay this item's layout through the profile's own helpers (`factory_site`, `factory_lines`, `placed_machines`, `factory_stand`, `factory_framing`) with this dict in place of the views file's `factory`:

```
pad = [26, 18], corner = [-34, 3, 36], view_from = [-0.5, 1], pitch_degrees = 33
machines (cell from the pad's corner, rotation 0):
  boiler [1, 1, 1] insert coal 20, steam_engine [5, 1, 1], storage_tank [9, 1, 1],
  pump [13, 1, 1], lamp [16, 1, 1], power_switch [18, 1, 1], small_pole [20, 1, 1],
  splitter [22, 1, 1], launch_pad [1, 1, 8], offshore_pump [12, 1, 8],
  combustion_generator [15, 1, 8], flare_stack [19, 1, 8], hydro_turbine [21, 1, 8],
  tar_pit_pump [12, 1, 11], fuel_generator [15, 1, 11], water_pump [18, 1, 11],
  big_pole [21, 1, 11], substation [23, 1, 11]
```

The words are `place <machine> <frame> <x> <y> <z> 0` and `insert <item> <count> <frame> <x> <y> <z>`. The drill needs a vein's disc under it and `place` starts no frame, so: `query veins 256` (the nearest's `surface`), `give wooden_foundation 20`, select its slot (`press Hotbar_Slot_<n>`, `query player`'s `held`), `fly on`, `teleport` 4 m over the surface along the radial, `look at` the surface, `pause`, `hold Place`, `tick 2`, `release Place`, `tick 2`, `query frames 16` (the new frame N), `place wooden_foundation N 1 0 0 0`, `N 0 0 1 0` and `N 1 0 1 0` as needed for a 2 by 2 floor, `place burner_mining_drill N 0 1 0 0`, `insert coal 10 N 0 1 0`, `resume`. Shots, each after `time noon` and `weather clear`: near, from `factory_stand`'s eye; at the haze, `view_distance 256` and the same look from 120 m and 230 m; the drill near from its own `look at`. A pipe on a field world is a pipe run, which `place` refuses and this item does not change (question 4).

### Presentation only

Checked: every changed procedure is in a presentation file or a loop draw (`draw_session_world`, `draw_field_scene`); they read the pools and the registries by value or pointer and write only rlgl's batch, the matrix stack, the frame's temp instance list and the point light list. `motion_phase_offset`'s callers are `clock_pose` and `render_loose_items.odin` (grep). `Frame_Table.revision` is "never saved, hashed or read by the simulation" (`world_frame.odin`). No data key changes; `data/machines.sjson` changes in a comment only, and the join's `content_tables_hash` reads the tables, not the text. Nothing reaches the tick, the state hash, the save or the network.

### Hand-back check

- The point lights' eight slots (a shared budget): the new gather loops add candidates only for records listing `lights`, none shipped, nearest first as before.
- A UI audit case made obsolete: none, no UI changes. Tests touch no state: in memory.
- Not applicable: memory freed between frames, file writes, start-up loads, parsed numbers, save layouts, unbounded HUD lists.

### Questions to the main agent

1. The splitter, which the item does not name, is placeable on a frame (`.Machine` tool) and never drawn on the field: included here. Keep?
2. Decision 8 adds three gather loops that change nothing shipped. Keep, or reword the docs' exception instead? Separately, whether a lit lamp should light the field (a `lights` entry on the lamp record) is content and is not done here.
3. Decision 7 shifts every field machine's phase, the already drawn ones too (the block world keeps its). Accept?
4. The item's "a pipe" placed and never drawn: no cell pipe stands on a field world; its pipes are runs, drawn since 0176. Drop the pipe from the captures, or lay a pipe run with the run tool (`hold Place` twice with the pipe held)?
5. The coverage test leaves out the pod and the launch pad, whose draws need GL (decision 3's reason, the tower's rlgl batch). Accept, or a launch pad through a view that culls its tower?

### Decisions (main agent, 2026-11-12)

1. Approved as specified.
2. The splitter stays in this item: it is placed on a frame and never drawn, which is the item's goal.
3. Decision 8 stays (the fluid machines, poles and lamps gathered for lights). A lamp that lights the ground on the field needs a `lights` entry in its record, a content change that is not this item's: a note for `SUGGESTIONS.md` at the landing.
4. Decision 6's phase change of every field machine's animation is accepted; no save holds a phase.
5. No pipe capture: a field pipe is a run, drawn since 0176.
6. The coverage test without the pod and the launch pad, with the two separate tests for the pad's tower and rocket and the drill's bar, is accepted.
7. The profile's `factory` view draws more after this item (its boiler, steam engine, poles and lamp), so its rows before and after are not comparable: the log says so at the landing.
