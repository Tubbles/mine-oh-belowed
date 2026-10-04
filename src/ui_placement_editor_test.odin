package game

import "core:slice"
import "core:testing"

// The placement editor (0215).

// The direct placement limit the editor tests use: 2 wide, 3 high, 2 deep.
EDITOR_TEST_LIMIT :: [3]i32{2, 3, 2}
// The cell the editor tests aim at: the top face of the pad's (3, 0, 3),
// so the adjacent cell, the footprint's centre, is (3, 1, 3).
EDITOR_TEST_AIMED :: World_Coordinate{3, 0, 3}
EDITOR_TEST_CENTRE :: World_Coordinate{3, 1, 3}

// A 7 by 7 pad of foundation cells (0..6, 0, 0..6), its frame's forward
// along +x, and a player standing on cell (3, 0, 0) with the stacks,
// holding the machine (a foundation as the foundation tool), aimed at the
// top face of (3, 0, 3).
make_placement_editor_test :: proc(t: ^testing.T, machine_id: string, stacks: ..Starting_Item) -> (simulation: Simulation_State, content: Simulation_Content, items: Item_Registry, frame: Frame) {
	simulation, content, items = make_pick_up_test()
	content.field.direct_placement_limit = EDITOR_TEST_LIMIT
	with_test_foundation_blocks(&content)
	frame = lay_test_pad(&simulation.world.entities, content.machines, 0, 0, {0, 0, 0}, {6, 0, 6})
	stand_test_player_on_cell(&simulation, content, items, frame, {3, 0, 0}, ..stacks)
	player := &simulation.players[0]
	machine := test_machine(content.machines, machine_id)
	player.field.held_machine = machine
	player.field.tool = content.machines.machines[machine].kind == .Foundation ? .Foundation : .Machine
	testing.expect(t, aim_test_player_at_cell(&simulation, content, frame.id, EDITOR_TEST_AIMED), "the reticle meets the pad's middle")
	testing.expect_value(t, player.field.frame_target.adjacent, EDITOR_TEST_CENTRE)
	return
}

// One editor frame with the actions just pressed and held.
editor_test_press :: proc(editor: ^Placement_Editor, simulation: ^Simulation_State, content: Simulation_Content, actions: Action_Set) -> Placement_Editor_Outcome {
	return update_placement_editor(editor, simulation, content, simulation.players[0], {just_pressed = actions, pressed = actions})
}

@(test)
test_the_direct_placement_limit_sends_large_machines_to_the_editor :: proc(t: ^testing.T) {
	testing.expect(t, !placement_exceeds_direct_limit({2, 3, 2}, EDITOR_TEST_LIMIT))
	testing.expect(t, placement_exceeds_direct_limit({2, 4, 2}, EDITOR_TEST_LIMIT))
	testing.expect(t, placement_exceeds_direct_limit({3, 1, 1}, EDITOR_TEST_LIMIT))
	testing.expect(t, placement_exceeds_direct_limit({1, 1, 3}, EDITOR_TEST_LIMIT))
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.direct_placement_limit = EDITOR_TEST_LIMIT
	with_test_foundation_blocks(&content)
	Case :: struct {
		machine: string,
		size:    u8,
		height:  u8,
		applies: bool,
	}
	// TEST_FOUNDATION_SIZES {1, 2, 5}, TEST_FOUNDATION_HEIGHTS {1, 2}.
	cases := [?]Case {
		{"wood_gasifier", 0, 0, false},
		{"big_pole", 0, 0, true},
		{"assembler_1", 0, 0, true},
		{"wooden_foundation", 2, 0, true},
		{"wooden_foundation", 1, 1, false},
	}
	for test_case in cases {
		player: Field_Player
		player.held_machine = test_machine(content.machines, test_case.machine)
		player.tool = content.machines.machines[player.held_machine].kind == .Foundation ? .Foundation : .Machine
		player.foundation_size_index, player.foundation_height_index = test_case.size, test_case.height
		testing.expectf(t, placement_editor_applies({on = true}, player, content) == test_case.applies, "%s on", test_case.machine)
		testing.expectf(t, !placement_editor_applies({}, player, content), "%s off", test_case.machine)
	}
}

@(test)
test_place_anchors_with_the_editor_on_and_places_directly_with_it_off :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	place := Input_Frame{pressed = {.Place, .Use_Item}, just_pressed = {.Place, .Use_Item}}
	{
		simulation, content, _, _ := make_placement_editor_test(t, "assembler_1", {"assembler_1", 1})
		defer destroy_simulation(&simulation)
		editor := Placement_Editor{on = true}
		applies := placement_editor_applies(editor, simulation.players[0].field, content)
		testing.expect(t, applies)
		world := placement_editor_world_frame(place, editor, applies)
		testing.expect(t, .Place not_in world.just_pressed && .Use_Item not_in world.just_pressed)
		outcome := editor_test_press(&editor, &simulation, content, {.Place})
		testing.expect(t, editor.anchored)
		testing.expect(t, !outcome.commit)
		testing.expect_value(t, outcome.refusal, Field_Edit_Refusal.None)
		testing.expect_value(t, editor.placement.cell, World_Coordinate{2, 1, 2})
		testing.expect_value(t, editor.centre, EDITOR_TEST_CENTRE)
	}
	{
		simulation, content, _, _ := make_placement_editor_test(t, "wood_gasifier", {"wood_gasifier", 1})
		defer destroy_simulation(&simulation)
		editor := Placement_Editor{on = true}
		applies := placement_editor_applies(editor, simulation.players[0].field, content)
		editor_test_press(&editor, &simulation, content, {.Place})
		testing.expect(t, !editor.anchored)
		testing.expect(t, .Place in placement_editor_world_frame(place, editor, applies).just_pressed)
	}
	{
		simulation, content, _, _ := make_placement_editor_test(t, "assembler_1", {"assembler_1", 1})
		defer destroy_simulation(&simulation)
		editor: Placement_Editor
		applies := placement_editor_applies(editor, simulation.players[0].field, content)
		editor_test_press(&editor, &simulation, content, {.Place})
		testing.expect(t, !editor.anchored)
		testing.expect(t, .Place in placement_editor_world_frame(place, editor, applies).just_pressed)
	}
}

@(test)
test_a_red_outline_refuses_the_anchor_with_the_reason :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	{
		simulation, content, _, frame := make_placement_editor_test(t, "assembler_1", {"assembler_1", 1})
		defer destroy_simulation(&simulation)
		_, refusal := place_on_frame(&simulation.world.entities, content.machines, test_machine(content.machines, "wooden_chest"), frame.id, {2, 1, 3}, 0)
		testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
		editor := Placement_Editor{on = true}
		ghost, shown := placement_editor_ghost(editor, &simulation, content, simulation.players[0])
		testing.expect(t, shown && ghost.kind == .Outline)
		testing.expect_value(t, ghost.refusal, Field_Edit_Refusal.Frame_Cell_Taken)
		outcome := editor_test_press(&editor, &simulation, content, {.Place})
		testing.expect(t, !editor.anchored)
		testing.expect_value(t, outcome.refusal, Field_Edit_Refusal.Frame_Cell_Taken)
	}
	{
		simulation, content, _, _ := make_placement_editor_test(t, "wooden_foundation", {"wooden_foundation", 1})
		defer destroy_simulation(&simulation)
		simulation.players[0].field.foundation_size_index = 2
		editor := Placement_Editor{on = true}
		outcome := editor_test_press(&editor, &simulation, content, {.Place})
		testing.expect(t, !editor.anchored)
		testing.expect_value(t, outcome.refusal, Field_Edit_Refusal.Too_Few_Foundations)
		testing.expect_value(t, [2]int{outcome.needed, outcome.held}, [2]int{25, 1})
		testing.expect_value(t, placement_refusal_toast(outcome), "Needs 25 foundations, 1 held")
	}
}

@(test)
test_nudge_and_rotate_turn_the_ghost_about_its_centre_on_a_frame :: proc(t: ^testing.T) {
	simulation, content, _, frame := make_placement_editor_test(t, "boiler", {"boiler", 1})
	defer destroy_simulation(&simulation)
	editor := Placement_Editor{on = true}
	editor_test_press(&editor, &simulation, content, {.Place})
	testing.expect(t, editor.anchored)
	testing.expect_value(t, editor.placement.cell, World_Coordinate{2, 1, 3})
	start := editor
	// The heading is +x, the frame's forward (+z in the frame).
	editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Away})
	testing.expect_value(t, editor.centre, World_Coordinate{3, 1, 4})
	editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Towards})
	testing.expect_value(t, editor.centre, EDITOR_TEST_CENTRE)
	right := frame_local_direction(frame, field_player_right(simulation.players[0].field))
	expected_x := right.x < 0 ? i32(2) : i32(4)
	editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Right})
	testing.expect_value(t, editor.centre, World_Coordinate{expected_x, 1, 3})
	editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Left})
	testing.expect_value(t, editor.centre, EDITOR_TEST_CENTRE)
	editor_test_press(&editor, &simulation, content, {.Rotate_Building})
	testing.expect_value(t, editor.placement.rotation, u8(1))
	testing.expect_value(t, editor.placement.cell, World_Coordinate{3, 1, 2})
	testing.expect_value(t, editor.centre, EDITOR_TEST_CENTRE)
	for _ in 0 ..< 3 {
		editor_test_press(&editor, &simulation, content, {.Rotate_Building})
	}
	testing.expect_value(t, editor.placement, start.placement)

	// The step alone, on a frame whose axes are the world's.
	axes := Frame{axes = {{UNIT_VECTOR_ONE, 0, 0}, {0, UNIT_VECTOR_ONE, 0}, {0, 0, UNIT_VECTOR_ONE}}, pitch_millimetres = 500}
	up := [3]i64{0, UNIT_VECTOR_ONE, 0}
	Case :: struct {
		heading: [3]i64,
		away:    World_Coordinate,
	}
	cases := [?]Case {
		{{UNIT_VECTOR_ONE, 0, 0}, {1, 0, 0}},
		{{-UNIT_VECTOR_ONE, 0, 0}, {-1, 0, 0}},
		{{0, 0, UNIT_VECTOR_ONE}, {0, 0, 1}},
		{{0, 0, -UNIT_VECTOR_ONE}, {0, 0, -1}},
		// 30 degrees from +z towards +x.
		{{UNIT_VECTOR_ONE / 2, 0, UNIT_VECTOR_ONE * 866 / 1000}, {0, 0, 1}},
	}
	for test_case in cases {
		heading_right := fixed_cross(test_case.heading, up)
		testing.expectf(t, placement_nudge_step(axes, test_case.heading, heading_right, .Away) == test_case.away, "away along %v", test_case.heading)
		testing.expectf(t, placement_nudge_step(axes, test_case.heading, heading_right, .Towards) == -test_case.away, "towards along %v", test_case.heading)
		step := placement_nudge_step(axes, test_case.heading, heading_right, .Right)
		testing.expectf(t, step.y == 0 && step != {} && step != test_case.away && step != -test_case.away, "right along %v: %v", test_case.heading, step)
		testing.expectf(t, i64(step.x) * heading_right.x + i64(step.z) * heading_right.z > 0, "right along %v: %v", test_case.heading, step)
		testing.expectf(t, placement_nudge_step(axes, test_case.heading, heading_right, .Left) == -step, "left along %v", test_case.heading)
	}
}

// The ground point under the site at x metres along +x.
editor_test_ground_hit :: proc(world: ^Field_World, spacing_millimetres: int, x: i64) -> World_Position {
	above := test_site_point(x, 4 * POSITION_UNITS_PER_METRE, 0)
	return raycast_field(world, spacing_millimetres, above, {0, -UNIT_VECTOR_ONE, 0}, 8 * POSITION_UNITS_PER_METRE).position
}

@(test)
test_a_bare_ground_nudge_restands_the_frame_on_the_terrain :: proc(t: ^testing.T) {
	machines := make_test_machines()
	furnace := test_machine(machines, "steel_furnace")
	pitch_millimetres :: 500
	heading := [3]i64{UNIT_VECTOR_ONE, 0, 0}
	terrains := [?]Test_Terrain{{kind = .Slope, slope_degrees = 5}, {kind = .Flat}}
	for terrain in terrains {
		spacing := 1000
		world := make_test_field(terrain, spacing)
		defer destroy_field_world(&world)
		hit := editor_test_ground_hit(&world, spacing, 0)
		placement := Field_Placement{machine = furnace, new_frame = true, cell = field_footprint_origin({}, machines.machines[furnace].footprint, 0), hit = hit, heading = heading}
		editor := Placement_Editor{on = true, anchored = true, machine = furnace, placement = placement}
		origin, axes := free_frame_at(hit, heading, pitch_millimetres)
		old := Frame{origin = origin, axes = axes, pitch_millimetres = pitch_millimetres}
		right := fixed_cross(heading, old.axes[FRAME_UP])
		step := placement_nudge_step(old, heading, right, .Away)
		testing.expect_value(t, step, World_Coordinate{0, 0, 1})
		moved, found := nudge_placement_editor(editor, step, &world, spacing, pitch_millimetres, machines)
		testing.expectf(t, found, "%v: the ground is found", terrain.kind)
		before := frame_local_position(old, hit)
		after := frame_local_position(old, moved.placement.hit)
		pitch := millimetres_to_position_units(pitch_millimetres)
		sample := millimetres_to_position_units(spacing)
		testing.expectf(t, abs(after.z - before.z - pitch) <= sample, "%v: moved %d along, a pitch is %d", terrain.kind, after.z - before.z, pitch)
		rise := after.y - before.y
		if terrain.kind == .Slope {
			expected := pitch * fixed_sine(degrees_to_angle_units(5)) / fixed_cosine(degrees_to_angle_units(5))
			testing.expectf(t, abs(rise - expected) <= sample, "slope: rose %d, expected %d", rise, expected)
		} else {
			testing.expectf(t, abs(rise) <= tenth_sample(spacing), "flat: rose %d", rise)
		}
		new_origin, new_axes := free_frame_at(moved.placement.hit, heading, pitch_millimetres)
		restood := Frame{origin = new_origin, axes = new_axes, pitch_millimetres = pitch_millimetres}
		height, under := bare_ground_height(&world, spacing, restood, {pitch / 2, pitch / 2})
		testing.expectf(t, under && abs(height) <= sample, "%v: the re-stood frame's centre cell stands %d off the ground", terrain.kind, height)
	}
}

@(test)
test_a_nudge_rechecks_the_refusal :: proc(t: ^testing.T) {
	simulation, content, _, frame := make_placement_editor_test(t, "assembler_1", {"assembler_1", 1})
	defer destroy_simulation(&simulation)
	_, refusal := place_on_frame(&simulation.world.entities, content.machines, test_machine(content.machines, "wooden_chest"), frame.id, {3, 1, 5}, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	editor := Placement_Editor{on = true}
	editor_test_press(&editor, &simulation, content, {.Place})
	testing.expect(t, editor.anchored)
	ghost, _ := placement_editor_ghost(editor, &simulation, content, simulation.players[0])
	testing.expect_value(t, ghost.refusal, Field_Edit_Refusal.None)
	editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Away})
	ghost, _ = placement_editor_ghost(editor, &simulation, content, simulation.players[0])
	testing.expect_value(t, ghost.kind, Placement_Editor_Ghost_Kind.Model)
	testing.expect_value(t, ghost.refusal, Field_Edit_Refusal.Frame_Cell_Taken)
	editor.guard = {}
	outcome := editor_test_press(&editor, &simulation, content, {.Place})
	testing.expect(t, editor.anchored && !outcome.commit)
	testing.expect_value(t, outcome.refusal, Field_Edit_Refusal.Frame_Cell_Taken)
	editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Towards})
	ghost, _ = placement_editor_ghost(editor, &simulation, content, simulation.players[0])
	testing.expect_value(t, ghost.refusal, Field_Edit_Refusal.None)
	outcome = editor_test_press(&editor, &simulation, content, {.Place})
	testing.expect(t, outcome.commit && !editor.anchored)
}

// Decision 10: a bare ground nudge whose moved centre finds no ground in
// the probe's reach (over a pit 10 m deep) keeps the ghost where it was
// and toasts Too steep.
@(test)
test_a_nudge_over_no_ground_keeps_the_ghost_and_toasts_too_steep :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	spacing :: 1000
	half_width := i64(2 * POSITION_UNITS_PER_METRE)
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.foundation_pitch_millimetres = 500
	world := make_test_field(Test_Terrain{kind = .Hole, ledge_height = 10 * POSITION_UNITS_PER_METRE, half_width = half_width}, spacing)
	simulation := make_test_field_state(world, spacing)
	defer destroy_simulation(&simulation)
	furnace := test_machine(content.machines, "steel_furnace")
	add_test_miner(&simulation, items, test_site_point(half_width + 3 * POSITION_UNITS_PER_METRE, 0, 0), {"steel_furnace", 1})
	player := &simulation.players[0]
	player.field.forward = {-UNIT_VECTOR_ONE, 0, 0}
	player.field.tool, player.field.held_machine = .Machine, furnace
	// On the rim a quarter metre from the pit's edge, the heading into
	// the pit: Away moves the centre half a metre, over the pit.
	above := test_site_point(half_width + POSITION_UNITS_PER_METRE / 4, 4 * POSITION_UNITS_PER_METRE, 0)
	ground := raycast_field(&simulation.field.world, spacing, above, {0, -UNIT_VECTOR_ONE, 0}, 8 * POSITION_UNITS_PER_METRE)
	testing.expect(t, ground.hit, "the rim is ground")
	placement := Field_Placement{machine = furnace, new_frame = true, cell = field_footprint_origin({}, content.machines.machines[furnace].footprint, 0), hit = ground.position, heading = field_player_heading(player.field)}
	editor := Placement_Editor{on = true, anchored = true, machine = furnace, hotbar_slot = player.selected_hotbar_slot, placement = placement}
	outcome := editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Away})
	testing.expect(t, editor.anchored)
	testing.expect_value(t, editor.placement, placement)
	testing.expect_value(t, outcome.refusal, Field_Edit_Refusal.Too_Steep)
	testing.expect_value(t, placement_refusal_toast(outcome), text("field_refused_too_steep"))
}

// The cells as a sorted copy, for comparing two orders.
sorted_editor_cells :: proc(cells: []World_Coordinate) -> []World_Coordinate {
	sorted := slice.clone(cells, context.temp_allocator)
	slice.sort_by(sorted, proc(first, second: World_Coordinate) -> bool {
		if first.x != second.x {
			return first.x < second.x
		}
		if first.y != second.y {
			return first.y < second.y
		}
		return first.z < second.z
	})
	return sorted
}

// The anchored editor committed: one command queued, run through the
// tick; the machine stands where the ghost stood.
expect_editor_commit_matches_the_ghost :: proc(t: ^testing.T, simulation: ^Simulation_State, content: Simulation_Content, editor: ^Placement_Editor, item: Item_Id) {
	ghost, shown := placement_editor_ghost(editor^, simulation, content, simulation.players[0])
	testing.expect(t, shown && ghost.kind == .Model && ghost.refusal == .None)
	ghost_cells := slice.clone(ghost.cells, context.temp_allocator)
	held := inventory_count(simulation.players[0].inventory, item)
	frames := len(simulation.world.entities.frames.frames)
	outcome := editor_test_press(editor, simulation, content, {.Place})
	testing.expect(t, outcome.commit)
	testing.expect(t, !editor.anchored && .Place in editor.guard)
	testing.expect_value(t, outcome.command, machine_placement_command(editor.placement))
	queue_player_command(&simulation.player_commands, 0, outcome.command)
	testing.expect_value(t, len(simulation.player_commands), 1)
	apply_player_commands(simulation, content)
	tick_field_simulation(simulation, content, {})
	testing.expect_value(t, simulation.players[0].field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, inventory_count(simulation.players[0].inventory, item), held - 1)
	frame := editor.placement.frame
	if editor.placement.new_frame {
		testing.expect_value(t, len(simulation.world.entities.frames.frames), frames + 1)
		frame = simulation.world.entities.frames.frames[frames].id
	}
	common := entity_common(&simulation.world.entities, entity_at(&simulation.world.entities, ghost.origin, frame))
	testing.expect(t, common != nil)
	if common == nil {
		return
	}
	testing.expect_value(t, common.origin, ghost.origin)
	testing.expect_value(t, common.rotation, ghost.rotation)
	testing.expect_value(t, slice.equal(sorted_editor_cells(common_cells(common^, content.machines)), sorted_editor_cells(ghost_cells)), true)
}

@(test)
test_commit_queues_one_placement_and_the_machine_matches_the_ghost :: proc(t: ^testing.T) {
	{
		simulation, content, items, _ := make_placement_editor_test(t, "assembler_1", {"assembler_1", 2})
		defer destroy_simulation(&simulation)
		editor := Placement_Editor{on = true}
		editor_test_press(&editor, &simulation, content, {.Place})
		editor.guard = {}
		editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Away})
		editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Right})
		editor_test_press(&editor, &simulation, content, {.Rotate_Building})
		testing.expect_value(t, editor.placement.rotation, u8(1))
		expect_editor_commit_matches_the_ghost(t, &simulation, content, &editor, test_item(items, "assembler_1"))
	}
	{
		// Bare ground beside the pad, aimed 2.5 m ahead of a player
		// standing on the flat ground.
		simulation, content, items := make_pick_up_test()
		defer destroy_simulation(&simulation)
		content.field.direct_placement_limit = EDITOR_TEST_LIMIT
		content.field.bare_ground.flatness_millimetres = 100
		add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"assembler_1", 2})
		player := &simulation.players[0]
		player.field.held_machine = test_machine(content.machines, "assembler_1")
		player.field.tool = .Machine
		player.field.pitch = degrees_to_angle_units(-30)
		tick_field_simulation(&simulation, content, {})
		testing.expect(t, player.field.target.hit && !player.field.frame_target.hit, "the ground is aimed at")
		editor := Placement_Editor{on = true}
		editor_test_press(&editor, &simulation, content, {.Place})
		testing.expect(t, editor.anchored && editor.placement.new_frame)
		editor.guard = {}
		editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Away})
		editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Left})
		editor_test_press(&editor, &simulation, content, {.Rotate_Building})
		testing.expect_value(t, editor.placement.rotation, u8(1))
		hit, heading := editor.placement.hit, editor.placement.heading
		outcome_command := machine_placement_command(editor.placement)
		testing.expect_value(t, outcome_command.hit, hit)
		testing.expect_value(t, outcome_command.heading, heading)
		expect_editor_commit_matches_the_ghost(t, &simulation, content, &editor, test_item(items, "assembler_1"))
	}
}

@(test)
test_cancel_the_hotbar_and_the_pause_row_drop_the_ghost :: proc(t: ^testing.T) {
	simulation, content, items, _ := make_placement_editor_test(t, "assembler_1", {"assembler_1", 2})
	defer destroy_simulation(&simulation)
	editor := Placement_Editor{on = true}
	editor_test_press(&editor, &simulation, content, {.Place})
	testing.expect(t, editor.anchored)
	editor_test_press(&editor, &simulation, content, {.Mine})
	testing.expect(t, !editor.anchored)
	// Mine held after the cancel stays from the world until released.
	held := update_placement_editor(&editor, &simulation, content, simulation.players[0], {pressed = {.Mine}})
	testing.expect_value(t, held, Placement_Editor_Outcome{})
	mine := Input_Frame{pressed = {.Mine}, just_pressed = {}}
	testing.expect(t, .Mine not_in placement_editor_world_frame(mine, editor, false).pressed)
	update_placement_editor(&editor, &simulation, content, simulation.players[0], {})
	mine.just_pressed = {.Mine}
	testing.expect(t, .Mine in placement_editor_world_frame(mine, editor, false).just_pressed)

	// A changed slot cancels; so does the held stack running out.
	editor_test_press(&editor, &simulation, content, {.Place})
	testing.expect(t, editor.anchored)
	simulation.players[0].selected_hotbar_slot += 1
	update_placement_editor(&editor, &simulation, content, simulation.players[0], {})
	testing.expect(t, !editor.anchored)
	simulation.players[0].selected_hotbar_slot -= 1
	editor.guard = {}
	editor_test_press(&editor, &simulation, content, {.Place})
	testing.expect(t, editor.anchored)
	// The held stack runs out: the tick reads the empty slot as no
	// machine held (update_field_held_tool).
	player := &simulation.players[0]
	held_stack := selected_hotbar_stack(player^)
	testing.expect_value(t, held_stack.item, test_item(items, "assembler_1"))
	inventory_remove(player.inventory, held_stack.item, inventory_count(player.inventory, held_stack.item))
	testing.expect(t, stack_is_empty(selected_hotbar_stack(player^)))
	update_field_held_tool(player, content, {})
	update_placement_editor(&editor, &simulation, content, player^, {})
	testing.expect(t, !editor.anchored)
	inventory_add(player.inventory, items, held_stack.item, 2)
	update_field_held_tool(player, content, {})
	testing.expect_value(t, player.field.tool, Field_Held_Tool.Machine)
	editor.guard = {}
	editor_test_press(&editor, &simulation, content, {.Place})
	testing.expect(t, editor.anchored)
	cancel_placement_editor(&editor)
	testing.expect(t, !editor.anchored)

	// In the mode the D-pad's hotbar meaning goes with its nudge; L1 keeps
	// it, and changes the slot.
	editor.anchored = true
	dpad := Input_Frame{pressed = {.Placement_Nudge_Left, .Hotbar_Previous}, just_pressed = {.Placement_Nudge_Left, .Hotbar_Previous}}
	testing.expect(t, .Hotbar_Previous not_in placement_editor_world_frame(dpad, editor, true).just_pressed)
	bumper := Input_Frame{pressed = {.Hotbar_Previous}, just_pressed = {.Hotbar_Previous}}
	testing.expect(t, .Hotbar_Previous in placement_editor_world_frame(bumper, editor, true).just_pressed)
}

@(test)
test_the_world_frame_hides_the_editors_controls :: proc(t: ^testing.T) {
	// R1's Hotbar_Next, the D-pad's Left and Right not held.
	everything := Input_Frame{move = {0, 1}, look = {1, 0}, look_delta = {3, 4}}
	everything.pressed = PLACEMENT_EDITOR_TAKEN_ACTIONS - {.Placement_Nudge_Left, .Placement_Nudge_Right} + {.Jump, .Sneak, .Sprint, .Open_Inventory, .Open_Map, .Pause, .Hotbar_Next, .Move, .Look}
	everything.just_pressed = everything.pressed
	anchored := placement_editor_world_frame(everything, {on = true, anchored = true}, true)
	testing.expect_value(t, anchored.pressed & PLACEMENT_EDITOR_TAKEN_ACTIONS, Action_Set{})
	testing.expect_value(t, anchored.just_pressed, Action_Set{.Jump, .Sneak, .Sprint, .Open_Inventory, .Open_Map, .Pause, .Hotbar_Next, .Move, .Look})
	testing.expect_value(t, anchored.move, everything.move)
	testing.expect_value(t, anchored.look_delta, everything.look_delta)
	outline := placement_editor_world_frame(everything, {on = true}, true)
	testing.expect_value(t, everything.just_pressed - outline.just_pressed, Action_Set{.Place, .Use_Item, .Placement_Nudge_Away, .Placement_Nudge_Towards})
	off := placement_editor_world_frame(everything, {}, false)
	testing.expect_value(t, everything.just_pressed - off.just_pressed, Action_Set{.Placement_Nudge_Away, .Placement_Nudge_Towards})
	sideways := Input_Frame{pressed = {.Placement_Nudge_Left, .Placement_Nudge_Right}, just_pressed = {.Placement_Nudge_Left, .Placement_Nudge_Right}}
	testing.expect_value(t, placement_editor_world_frame(sideways, {}, false).pressed, Action_Set{})

	pipette := Input_Frame{pressed = {.Pipette, .Look}, just_pressed = {.Pipette}, look_delta = {5, 0}}
	plain := tools_radial_world_frame(pipette, {})
	testing.expect(t, .Pipette not_in plain.pressed && .Pipette not_in plain.just_pressed)
	testing.expect_value(t, plain.look_delta, pipette.look_delta)
	selected := tools_radial_world_frame({}, {pipette_selected = true})
	testing.expect_value(t, selected.just_pressed, Action_Set{.Pipette})
	open := tools_radial_world_frame(pipette, {radial = {open = true, highlight = -1}})
	testing.expect(t, .Look not_in open.pressed)
	testing.expect_value(t, open.look_delta, [2]f32{})
}

@(test)
test_the_placement_editor_leaves_the_save_and_the_hash_alone :: proc(t: ^testing.T) {
	simulation, content, _, _ := make_placement_editor_test(t, "assembler_1", {"assembler_1", 1})
	defer destroy_simulation(&simulation)
	hash := simulation_state_hash(&simulation)
	bytes := make([dynamic]byte, context.temp_allocator)
	write_frame_tables(&bytes, &simulation.world.entities, true)
	editor: Placement_Editor
	toggle_placement_editor(&editor)
	editor_test_press(&editor, &simulation, content, {.Place})
	editor.guard = {}
	editor_test_press(&editor, &simulation, content, {.Placement_Nudge_Away})
	editor_test_press(&editor, &simulation, content, {.Rotate_Building})
	testing.expect(t, editor.anchored)
	testing.expect_value(t, simulation_state_hash(&simulation), hash)
	after := make([dynamic]byte, context.temp_allocator)
	write_frame_tables(&after, &simulation.world.entities, true)
	testing.expect(t, slice.equal(bytes[:], after[:]), "the frame tables are written as before")
	outcome := editor_test_press(&editor, &simulation, content, {.Place})
	testing.expect(t, outcome.commit)
	queue_player_command(&simulation.player_commands, 0, outcome.command)
	testing.expect_value(t, simulation_state_hash(&simulation), hash)
	toggle_placement_editor(&editor)
	testing.expect(t, !editor.on && !editor.anchored)
}
