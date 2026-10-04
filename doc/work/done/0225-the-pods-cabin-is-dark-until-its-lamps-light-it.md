# 0225: The pod's cabin is dark until its lamps light it

Status: landed (2026-10-04, commit 5125964 "Darken the pod's cabin to its interior light share (0225)", the play build installed; the specification approved the same day with the decisions below; the implementer works in `.claude/worktrees/0225` on `item/0225` from `main`, from the user's note on the first lit cabin shots of 0224, "i like the colors but it still looks flat"; the main agent's reading of the cause is below)

## Goal

Inside the pod the lamps carve pools of light out of a dark cabin, as the booklet's interior does, instead of adding a little warmth to a room that is already lit at full daylight.

## Why it looks flat

A field session lights every model with the full sky light (`Model_Frame.open_sky`, `model_frame_light` in `render_models.odin`, 0179: machines stand on frames the block light does not reach), the pod's hull and its fixtures included, whatever surrounds them. The point lights of 0224 only add on top (`model.fs`, the sum is added to the base), so a lamp inside the cabin brightens a wall that is already at its brightest and the far side of the cabin is as bright as the near side. The lamps' pools can only show when the base inside is dark. The point lights cast no shadows and never will in this renderer; the depth comes from the base being dark and the lamps local.

## Controls

No binding changes.

## Change

- The base light of the pod's own model and of its fixtures (the hatches, the locker, the bench and the oxygen generator placed by `validate_pod_fixtures`) is scaled by a record key on the pod, `interior_light_share` (0 to 1, the pod ships a low value such as 0.25), applied to the light tint of their lit layers before the point lights add; the emissive layers keep their brightness, so the screens and strips stay lit. The hull seen from outside takes the same scale: the pod is a dark shell outside too, which the portholes' and the door's emissive patches offset. The design stage settles whether the share also applies to players' bodies seen inside the cabin (the viewer never sees their own body in first person; a second player inside would glow at full daylight against the dark walls) and to loose items.
- The simulation reads nothing of it; presentation only, the hash untouched.
- Docs: `doc/presentation.md` (Machine models: the pod bullet), `doc/content.md` (the key).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the key is bounded (a value outside 0 to 1 is refused with the machine named); the pod's and its fixtures' light tint carries the share and an ordinary machine's does not; the emissive layer's brightness is unchanged by it; the hash of a session with the key equals the hash without it.
- A headless screenshot pass (`tmp/pod_shots.sh`) with the lab's model and its two lamps: the walls near the lamps read as pools and the far side of the cabin stays dark.

## Specification (design, 2026-10-04)

Written from the item, `doc/work/done/0224-point-lights-on-machine-models.md`, `doc/work/0221-the-pod-remade-from-the-booklet.md`, `doc/presentation.md`, `doc/content.md`, `doc/code_map.md` and the code named below. Presentation only: no simulation state, save layout, network message or hash input changes. No binding changes.

### Order against 0221

Assumed: 0225 lands before 0221. 0221 waits on the user accepting the round three model (its Status line), while 0225 touches no file 0221 rewrites except two appends (`data/machines.sjson`'s pod record gains one line, `src/entity_pod_test.odin` gains tests at its end), which the rebase at 0221's landing keeps. 0221's implementer then finds the key on `main` and puts the two lamps beside it. The tests below set the share and the lamps on the registry themselves, so they hold before and after 0221's record.

### The mechanism, decided

- Fixtures learn their pod's share by place, not by handle: once per scene the alive pods are gathered into a short list of their boxes on their frames with their share (`gather_interior_lights`), and every model whose origin cell lies in a pod's box on the pod's frame takes that share (`model_interior_light_share`). The pod's own origin lies in its box, so the pod and its fixtures (whose boxes the record keeps inside the footprint, `validate_pod_fixtures`) take it by one rule, the locker in the chests' loop as well as the hatches, the bench and the generator in the foundations' loop, with no change to any loop of `draw_entities`. A machine a player places on the pod's frame outside its box keeps full light; one placed inside the cabin takes the share, which is right for where it stands. No handle and no field on an entity, so no save layout change. A per entity scan of the foundations' pool would cost pods times entities per draw; the list is built once per viewport in the temp allocator and is one entry long in every world today.
- Players' bodies take the share: a player whose feet cell (`frame_cell_of_feet`, the cell a quarter pitch over the feet) lies in a pod's box on its frame is lit at the share (`field_player_interior_light_share`), so a second player in the cabin is as dark as the walls and stands in the same pools. The viewer's own body is not drawn in first person (`draw_field_players`), and a field session has no first person hands (`draw_first_person_hands` is called only by the block world's `draw_session_world`, `loop.odin` line 1193).
- Loose items: none to do. A field session draws no loose items (`draw_field_scene` calls no `draw_loose_items`; only `draw_session_world` does).
- The key is the pod's only (`interior_light_share`, refused on other kinds): the fixtures read their pod's, so no other record needs it, and a general `model_light_share` would invite a record to darken itself where nothing lights it.
- Not covered, named so the verifier does not look for them: an inserter's arm placed inside the cabin (`draw_inserter_model` computes its own tint; an arm has its own lamp) and the box fallback of a machine without a model (unlit flat colours). The workbench (`draw_model_preview_scene`) keeps full light: it has no point lights, and the pod's previews must stay readable.

### Where the share multiplies, and why there

In a new pure `posed_model_light`, called by `draw_posed_model` in place of its first lines: the light tint from the frame's light (`model_light_tint`), then the share (`interior_light_tint`), then the broken tint, then `emissive_brightness` from that tint. `draw_posed_model` is the one procedure every model of `draw_entities` goes through (`draw_machine_model` for the pools, `draw_hatch` directly), so one place covers the pod and every fixture; `Model_Pose` is built per pool (`clock_pose`, `hatch_pose`) and would need the lookup twice; a `Model_Frame` field alone holds the list, not the per entity answer.

The emissive layers: `emissive_brightness` gives a working machine 1 (or the glow's pulse) whatever the tint, so the pod's screens and strips (the pod always works, `foundation_model_working`), an open hatch's strips and a supplying generator's strip keep their full brightness. An idle emissive layer is drawn "lit like the rest" (`emissive_brightness`, `model_motion.odin` line 269), so a closed hatch's strips and an idle generator's take the darkened tint as the walls round them; fed the undarkened tint they would glow at full daylight in the dark cabin while switched off. Question 2 asks the main agent to confirm this reading of "the emissive layers keep their brightness".

The floor: the darkened tint never goes below `MINIMUM_MODEL_BRIGHTNESS` (0.06, matching `chunk.fs`), so at night the cabin sits at the floor every other model has and the lamps carry it.

### The shipped value: 0.25

The lamp term in `model.fs` adds the vertex colour times `colour * share * share * facing` (`share` the distance falloff `1 - d^2/r^2`, `facing` 0.5 to 1). At full day the tint is 1, so a wall far from the lamps draws at 0.25 of its colour, four times the floor of 0.06, so the pre-shaded faces (0.775 plus up to about 0.3 by direction) still read the shapes. An amber lamp (255, 150, 40) adds up to 1.0 of the red channel next to it and 0.28 to 0.56 at half its radius: a pool from 2 to 5 times the far side. At 0.5 the half radius pool is only 1.5 times the base (the flatness the user saw); at 0.1 the far side sits next to the floor (0.1 against 0.06) and the cabin's shapes away from the lamps go to one flat dark. 0.25 is the middle that keeps both.

### Files and procedures

`src/machine.odin`:
- `Machine_Definition` gains `interior_light_share: Maybe(f32)` after `lights` (as `dispatch_order: Maybe(int)`, so an absent key is told from 0).
- `Machine` gains `interior_light_share: f32` after `light_count`, commented: "A pod's model, its fixtures' and the players' in its box are lit at this share of the light round them before the point lights add (work item 0225, presentation only: the simulation never reads it); 1 for every other machine. A hand built `Machine{}` holds 0."
- `resolve_machine` sets `interior_light_share = definition.interior_light_share.? or_else 1`.
- `validate_interior_light_share :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string`, after `resolve_machine_lights`; called by `validate_machine_definition` right after `validate_machine_lights`. Absent: "". Present on a kind other than `.Pod`: `machine %q is not a pod and cannot have interior_light_share`. Present and not `share >= 0 && share <= 1` (written so, so a NaN fails): `machine %q has interior_light_share %.3f, not 0 to 1`.

`src/model_motion.odin`:
- `interior_light_tint :: proc(light_tint: [3]f32, share: f32) -> [3]f32`: `linalg.clamp(light_tint * share, MINIMUM_MODEL_BRIGHTNESS, 1)`. Pure; called by `posed_model_light` and `player_body_light`. Comment: a pod's interior light (0225), never below the models' floor. With share 1 it returns the tint unchanged, since `model_light_tint` already clamps to the same range.

`src/render_models.odin`:
- `Interior_Light :: struct { frame: Frame, box: Cell_Box, share: f32 }`, commented: a pod's box of cells on its frame (inclusive, the rotated size from its origin) and its `interior_light_share` (0225).
- `Model_Frame` gains `interiors: []Interior_Light` (last field), its comment extended: "interiors are the pods' boxes whose models and players take the pod's interior light share (0225, `gather_interior_lights`); nil outside a field scene, which leaves every share 1." The three builders (`loop.odin` line 1160, `loop_field_session.odin` line 408, `loop_planet_preview.odin` line 484) stay as they are (named fields, nil).
- `gather_interior_lights :: proc(entities: ^Entities, machines: Machine_Registry, allocator := context.temp_allocator) -> []Interior_Light`: every alive foundations' entry whose machine (index checked against `len(machines.machines)`, as `pod_on_frame`'s neighbours do) is `.Pod` and whose frame is found (`find_frame`): `{frame, Cell_Box{from = cast([3]i32)entry.origin, to = cast([3]i32)entry.origin + entry.size - 1}, machine.interior_light_share}`. Called by `draw_field_scene`.
- `model_interior_light_share :: proc(interiors: []Interior_Light, frame: Frame_Id, cell: World_Coordinate) -> f32`: the share of the first interior with `interior.frame.id == frame` whose box contains `cell` (`cell_box_contains`), else 1. Pure; called by `posed_model_light`.
- `field_player_interior_light_share :: proc(interiors: []Interior_Light, player: Field_Player) -> f32`: the share of the first interior whose box contains `frame_cell_of_feet(interior.frame, player)`, else 1. Pure; called by `draw_field_player_body`.
- `posed_model_light :: proc(frame: Model_Frame, common: Entity_Common, machine: Machine, pose: Model_Pose) -> (light_tint, glow: [3]f32)`: `light_tint = interior_light_tint(model_light_tint(model_frame_light(frame, model_light_cell(common)), frame.day_factor, frame.sky_tint), model_interior_light_share(frame.interiors, common.frame, common.origin))`; times `BROKEN_MODEL_TINT` when `common.broken`; `glow = emissive_brightness(machine.motion.kind, pose.phase, pose.working, light_tint)`. Pure (with `open_sky` it reads no world).
- `draw_posed_model`: its first five lines become `light_tint, glow := posed_model_light(frame, common, machine, pose)`; its comment: "lit by the cell model_light_cell names, at its pod's interior light share inside a pod's box (0225), darkened while broken."

`src/render_player.odin`:
- `player_body_light :: proc(frame: Model_Frame, eye: [3]f32, interior_share: f32) -> rl.Color`: `brightness_color(interior_light_tint(model_light_tint(light, frame.day_factor, frame.sky_tint), interior_share))`; comment adds "at the interior share of the pod the body stands in (0225, 1 elsewhere)". `loop.odin` line 1189 passes `1` (the block world has no pods).

`src/loop_field_session.odin`:
- `draw_field_scene`: first lines `scene := scene` and `scene.frame.interiors = gather_interior_lights(&scene.state.world.entities, scene.content.machines)`, so `draw_entities` and `draw_field_players` read it; the planet preview, which draws through the same procedure, follows. The file's header comment: "the machines on their frames (draw_entities, lit by the open sky, a pod's box at its interior light share)".
- `draw_field_player_body`: `light := player_body_light(scene.frame, feet, field_player_interior_light_share(scene.frame.interiors, player))`.

`tools/models/records.py`: the docstring's sentence on `lights` adds `interior_light_share` (0225) as read by the game only. No code change (`read_machine` reads with `.get`).

### The data key

- `data/machines.sjson`, header, a paragraph after the `lights` one: "interior_light_share (optional, pods only, work item 0225) is 0 to 1: the pod's model, its fixtures' models and the bodies of players standing in its footprint are lit at this share of the light round them, never below the models' floor, before the point lights add, so the cabin is dark but where its lamps reach; the emissive materials of a working model keep their brightness. 1 when absent. Presentation only."
- The pod's record: `interior_light_share = 0.25` above `lights`, with the comment "The cabin and the hull at a quarter of the light round them, so the lamps' pools show (0225)." (Question 1.)
- Bounds: 0 to 1 inclusive, pods only; error texts as in `validate_interior_light_share` above. Record errors are logged as `error: invalid <path>: <message>` by the load as for every record.

### Save layout

None changes: the share lives in the machine record, and the interior lookup is derived each frame from the pods' entries already saved (frame, origin, size). No entity gains a field, so no remap and no log line.

### Tests

- `test_the_interior_light_share_is_a_pods_and_bounded` (`machine_test.odin`): the `room` pod definition of `test_machine_lights_stay_on_the_footprint_with_a_bounded_radius` (without its lights) with `interior_light_share = 0.25` resolves to 0.25; without the key it resolves to 1; 0 and 1 are accepted; -0.01 and 1.01 are refused with the prefix `machine "room" has interior_light_share`; an oxygen generator definition (`id = "niche"`, `name_key = "machine_pod"`, `kind = "oxygen_generator"`, footprint 1 by 2 by 3) with the key is refused with `machine "niche" is not a pod and cannot have interior_light_share`, and without it resolves with share 1. `make_test_machines()`: the shipped pod's share is 0.25 and the stone furnace's (`find_machine_of_kind(machines, .Furnace)`) is 1.
- `test_the_interior_light_tint_never_goes_below_the_floor` (`model_motion_test.odin`): `interior_light_tint({1, 0.5, 0.2}, 0.25)` is `{0.25, 0.125, MINIMUM_MODEL_BRIGHTNESS}`; with share 1 `{1, 0.5, 0.2}` unchanged; with share 0 every channel `MINIMUM_MODEL_BRIGHTNESS`; within 1e-6.
- `test_the_pod_and_its_fixtures_take_the_interior_light_share` (`entity_pod_test.odin`, at the end): `make_test_machines`, the pod's `interior_light_share` set to 0.25 on the registry, `place_test_pod`; a frame `Model_Frame{open_sky = true, day_factor = 1, sky_tint = {1, 1, 1}, interiors = gather_interior_lights(&entities, machines)}` (one interior). `posed_model_light` gives a lit tint of 0.25 per channel (within 1e-5) for the pod (pose working, from `foundation_model_working`), each closed hatch (`hatch_pose`), the bench and the generator (their foundations' entries, pose working from `foundation_model_working`) and the locker (its chests' entry, `test_pod_fixture(..., TEST_LOCKER)`, pose `{}`). The glow: 1 for the pod and the supplying generator (working emissive unchanged), 0.25 for a closed hatch (an idle emissive follows the lit layer), and 1 for the outer hatch after `toggle_hatch` opens it. Full light (tint 1, the share not applied): an `Entity_Common` on the pod's frame at `pod_origin(pod) + {-2, 0, 0}`, size `{1, 1, 1}` (outside the box), and one on `BLOCK_FRAME` at `pod_origin(pod)` (the same cell numbers, another frame). With `interiors = nil` the pod's tint is 1.
- `test_a_player_in_the_cabin_takes_the_interior_light_share` (`entity_pod_test.odin`, at the end): the pod placed as above with share 0.25; `spawn, found := field_pod_spawn(&entities, machines)`: `field_player_interior_light_share(interiors, spawn)` is 0.25; the same player moved to `frame_cell_centre(frame, pod_origin(pod) + {-2, 0, 0})` (position and previous position) gives 1; nil interiors give 1.
- `test_the_interior_light_share_leaves_the_hash` (`simulation_arrival_test.odin`, after `test_the_machine_lights_leave_the_hash`, its pattern): two contents from `make_field_test_game_content()`, the watched one's pod share 0.25, the plain one's 1 (as a record without the key); each of 700 ticks both worlds tick, and on the watched one `gather_interior_lights`, `posed_model_light` of the pod's common (`pod_on_frame` of `find_pod_frame`'s id) with a full sky frame, and `field_player_interior_light_share` of the first player; at ticks 300, 540 and 700 one interior is gathered, the pod's tint is 0.25 and `lockstep_state_hash` equals the plain world's.

### Commands (implementer, in the worktree)

`./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/models/records_test.py`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`. Prefix the heavy ones with `taskset -c 8-15 nice -n 10`. No benchmark, no game run.

### Docs (same commit)

- `doc/presentation.md`, The field session, the scene bullet: after "lit by the open sky ... light grid)", "except inside a pod: the pod's model, its fixtures' and the bodies of players standing in its footprint take the pod's `interior_light_share` of that light (`gather_interior_lights` once per scene, `posed_model_light`, `field_player_interior_light_share`, 0225)".
- `doc/presentation.md`, Machine models, the point lights bullet (0224): one sentence: the lit tint is scaled by the interior share before the point lights add (`interior_light_tint`, never below `MINIMUM_MODEL_BRIGHTNESS`); a working model's emissive materials keep their brightness, an idle one's follow the darkened tint.
- `doc/presentation.md`, Machine models, the pod bullet (line 165): "Its record's `interior_light_share` (0.25) darkens its hull, cabin and fixtures to a quarter of the light round them, inside and out, so the lamps' pools show and the portholes' and screens' emissive patches stand out (0225); the workbench previews keep full light."
- `doc/presentation.md`, The player: one bullet: in a field session a body standing in a pod's footprint is lit at the pod's interior share (0225).
- `doc/content.md`, The pod: a bullet for the key (pods only, 0 to 1, absent 1, the shipped 0.25 and why: the far side at a quarter, the lamps' pools 2 to 5 times brighter; the two refusals).
- `doc/code_map.md`, the `render_entities.odin`, `render_models.odin` line: "the pods' interior light (`gather_interior_lights`, `posed_model_light`, 0225)". No new file, no new dependency (render reads the simulation's `frame_cell_of_feet`, an allowed direction), no record count changes.
- `doc/log/2026-10-04.md`: a section "The pod's cabin dark until its lamps light it (0225)", tags `models, light, pod, presentation, m15`: the share by place, not by handle, and why (no save change, one rule for the pod and its fixtures); players included, loose items absent from the field; the idle emissive following the darkened tint; the floor kept; 0.25 and the arithmetic; the workbench left at full light; the old lamp-less pod (question 1's outcome).

### Hand-back check lines that apply

- "A number parsed from text is range checked": `interior_light_share` is bounded to 0 to 1 (NaN refused) and refused off a pod; tested.
- "A changed save layout loads an old save": no layout changes (the share is the record's, the interior derived each frame).
- "A list that grows without bound is capped where it draws": the interiors list holds one entry per alive pod, in the temp allocator per viewport; nothing accumulates.
- The others (frame memory, file writes, start-up loads, shared budgets, UI audit cases) do not apply; the tests touch no state directory.

### Questions the item left open, answered

1. How a fixture learns its pod's share: by place, a lookup of the entity's origin cell in the pods' boxes on their frames, gathered once per scene (above).
2. Players' bodies: yes, by their feet cell; the viewer's own body is not drawn in first person and the field has no first person hands.
3. Loose items: a field session draws none.
4. Pod only or any machine: pod only, `interior_light_share`.
5. Where it multiplies: `posed_model_light`, called by `draw_posed_model`, before the broken tint and before `emissive_brightness`.
6. The value: 0.25 (arithmetic above).
7. Night: floored at `MINIMUM_MODEL_BRIGHTNESS`, like every model.

### Questions for the main agent

1. The shipped pod has no lamps (`lights = []`, `data/machines.sjson`) and no emissive material (every `Ke` in `data/models/pod.mtl` is 0). Shipping 0.25 in this item, as decided, makes the installed build's pod a uniformly dim shell with no pools until 0221 lands. Keep it (the decision as written), or move the one record line to 0221 with the two lamps and set 0.25 only in the private data copy (`tmp/pod_data`) for the screenshot pass now, as 0224 did with its lamps? The tests do not depend on the shipped value except the one assertion in `test_the_interior_light_share_is_a_pods_and_bounded`, which would then read 1 and move to 0221.
2. The item says "the emissive layers keep their brightness". This specification reads that as the working ones (the pod's always, an open hatch's, a supplying generator's), and lets an idle emissive layer (a closed hatch's strips, an idle generator's strip) follow the darkened tint, as `emissive_brightness` draws an idle one "lit like the rest". Confirm, or should idle emissive layers stay at the undarkened tint (then `posed_model_light` passes the tint before the share to `emissive_brightness`, and the test's closed hatch glow reads 1)?

### Decisions at the approval (main agent, 2026-10-04)

1. The shipped value moves to 0221: `data/machines.sjson` gets the header paragraph only and the pod's record no key in this item (an absent key is 1, so the installed build's old lamp-less pod draws as before), the private data copy `tmp/pod_data` gets `interior_light_share = 0.25` for the screenshot pass now, and 0221's implementer writes the 0.25 beside the two lamps with the model. `test_the_interior_light_share_is_a_pods_and_bounded` asserts the shipped pod's share is 1 (0221 flips that assertion with the record) and keeps the furnace's 1.
2. Confirmed: an idle emissive layer (a closed hatch's strips, an idle generator's strip) follows the darkened tint, as the specification reads it. A working model's emissive layer keeps its full brightness.
3. 0225 lands before 0221, as assumed.
