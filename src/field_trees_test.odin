package game

import "core:math"
import "core:slice"
import "core:testing"

// The field's trees (work item 0197) in field test sessions: a player
// standing FELLING_TEST_STAND_MILLIMETRES from the trunk of a tree near
// the home, on the generated ground, facing it.

FELLING_TEST_STAND_MILLIMETRES :: 1200
// The stand's ground may lie this much above or below the tree's.
FELLING_TEST_GROUND_TOLERANCE_MILLIMETRES :: 300
// No other trunk this near the stand or a test spot.
FELLING_TEST_CLEARANCE_MILLIMETRES :: 2000
FELLING_TEST_SETTLE_TICKS :: 60

Felling_Test :: struct {
	session:      ^Session,
	game_content: Game_Content,
	content:      Simulation_Content,
	tree:         Planet_Tree,
	species:      Field_Tree_Species,
	trunk:        Field_Capsule,
	// The unit tangent from the stand towards the trunk.
	toward:       [3]i64,
	// The tree's candidate on the sphere, its axis's foot.
	on_sphere:    [3]i64,
	trees:        []Planet_Tree,
}

// The trees in a 120 m box round the home, nearest the home first.
felling_test_trees :: proc(generation: ^Planet_Generation) -> []Planet_Tree {
	home := generation.trees.home
	minimum, maximum := tree_test_box(home, 60)
	trees := planet_trees_in_box(generation, minimum, maximum)
	Ordered :: struct {
		tree:     Planet_Tree,
		distance: i64,
	}
	ordered := make([]Ordered, len(trees), context.temp_allocator)
	for tree, index in trees {
		ordered[index] = {tree, vector_length(tree_test_on_sphere(generation^, tree) - home)}
	}
	slice.sort_by(ordered, proc(first, second: Ordered) -> bool {return first.distance < second.distance})
	sorted := make([]Planet_Tree, len(trees), context.temp_allocator)
	for entry, index in ordered {
		sorted[index] = entry.tree
	}
	return sorted
}

// No trunk but the tree's within the clearance of the point on the
// sphere.
felling_test_spot_is_clear :: proc(generation: ^Planet_Generation, trees: []Planet_Tree, tree: Planet_Tree, point: [3]i64) -> bool {
	clearance := millimetres_to_position_units(FELLING_TEST_CLEARANCE_MILLIMETRES)
	for other in trees {
		if other.key != tree.key && vector_length(tree_test_on_sphere(generation^, other) - point) < clearance {
			return false
		}
	}
	return true
}

// The point on the sphere distance_millimetres from the tree's axis along
// the bearing, and the tangent along it.
felling_test_point :: proc(on_sphere, up: [3]i64, bearing: i32, distance_millimetres: int) -> (point, tangent: [3]i64) {
	tangent = planet_home_tangent(up, bearing)
	return on_sphere + fixed_scale(tangent, millimetres_to_position_units(distance_millimetres)), tangent
}

// The bearing whose ground at the stand lies nearest the tree's, clear of
// the other trunks; found is false when none lies within the tolerance.
felling_test_stand :: proc(generation: ^Planet_Generation, trees: []Planet_Tree, tree: Planet_Tree) -> (feet: World_Position, toward: [3]i64, found: bool) {
	on_sphere := tree_test_on_sphere(generation^, tree)
	ground := tree.base + World_Position(fixed_scale(tree.up, millimetres_to_position_units(PLANET_TREE_BASE_SINK_MILLIMETRES)))
	best := millimetres_to_position_units(FELLING_TEST_GROUND_TOLERANCE_MILLIMETRES)
	for step in 0 ..< 8 {
		point, tangent := felling_test_point(on_sphere, tree.up, i32(step * ANGLE_UNITS_PER_TURN / 8), FELLING_TEST_STAND_MILLIMETRES)
		if !felling_test_spot_is_clear(generation, trees, tree, point) {
			continue
		}
		stand := field_surface_under(generation^, World_Position(point), 0)
		if difference := abs(fixed_dot(cast([3]i64)(stand - ground), tree.up)); difference <= best {
			best, feet, toward, found = difference, stand, -tangent, true
		}
	}
	return
}

// The pitch in angle units that looks from the eye at the point.
felling_test_pitch :: proc(eye: World_Position, point: World_Position, up: [3]i64) -> i32 {
	offset := cast([3]i64)(point - eye)
	vertical := fixed_dot(offset, up)
	horizontal := vector_length(offset - fixed_scale(up, vertical))
	return i32(math.atan2(f64(vertical), f64(horizontal)) * ANGLE_UNITS_PER_TURN / math.TAU)
}

// Eye level when the eye lies within the trunk's height, else aimed at
// the trunk's middle.
felling_test_aim :: proc(test: ^Felling_Test) {
	player := &test.session.simulation.players[0].field
	eye := field_player_eye(player^, test.content.field.tuning)
	height := fixed_dot(cast([3]i64)(eye - test.trunk.bottom), test.trunk.up)
	margin := metres_to_position_units(1) / 5
	player.pitch = 0
	if height < margin || height > test.trunk.length - margin {
		player.pitch = felling_test_pitch(eye, test.trunk.bottom + World_Position(fixed_scale(test.trunk.up, test.trunk.length / 2)), player.up)
	}
}

// A new field world with its player standing at the stand of the first
// tree near the home that has one, settled and aiming at the trunk.
start_felling_test :: proc(config: Game_Config, game_content: Game_Content) -> (test: Felling_Test, found: bool) {
	test.game_content = game_content
	test.session = start_field_test_session(config, game_content)
	test.content = field_test_content(test.session, game_content)
	state := &test.session.simulation
	generation := field_tree_generation(&state.field)
	test.trees = felling_test_trees(generation)
	feet: World_Position
	for tree in test.trees {
		if feet, test.toward, found = felling_test_stand(generation, test.trees, tree); found {
			test.tree = tree
			break
		}
	}
	if !found {
		return test, false
	}
	test.on_sphere = tree_test_on_sphere(generation^, test.tree)
	test.species, _ = field_tree_species(test.content.field, test.tree)
	test.trunk = field_tree_trunk(test.tree, test.species)
	state.players[0].field = make_field_player(feet + World_Position(fixed_scale(test.tree.up, millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES))), test.toward)
	for _ in 0 ..< FELLING_TEST_SETTLE_TICKS {
		tick_field_test_simulation(state, test.content, {})
	}
	felling_test_aim(&test)
	tick_field_test_simulation(state, test.content, {})
	return test, true
}

// The feet's distance from the trunk's axis across its up.
felling_test_axis_distance :: proc(test: Felling_Test, feet: World_Position) -> i64 {
	offset := cast([3]i64)(feet - test.trunk.bottom)
	return vector_length(offset - fixed_scale(test.trunk.up, fixed_dot(offset, test.trunk.up)))
}

FELLING_TEST_WALK :: Input_Frame{move = {0, 1}, pressed = {.Move}}
FELLING_TEST_MINE :: Input_Frame{pressed = {.Mine}}

// Mine held from the first tick for ticks ticks.
hold_felling_test_mine :: proc(test: Felling_Test, ticks: int) {
	for tick in 0 ..< ticks {
		frame := FELLING_TEST_MINE
		if tick == 0 {
			frame.just_pressed = {.Mine}
		}
		tick_field_test_simulation(&test.session.simulation, test.content, frame)
	}
}

aims_at_test_tree :: proc(test: Felling_Test) -> bool {
	target := test.session.simulation.players[0].field.tree_target
	return target.hit && target.key == test.tree.key
}

@(test)
test_mine_held_fells_a_tree_for_its_logs :: proc(t: ^testing.T) {
	test, found := start_felling_test(test_field_game_config(), make_field_test_game_content())
	defer end_session(test.session)
	testing.expect(t, found, "a tree near the home has a stand")
	if !found {
		return
	}
	state := &test.session.simulation
	player := &state.players[0]
	testing.expect(t, aims_at_test_tree(test), "the trunk takes the aim")
	log := test_item(test.content.items, "log")
	before := inventory_count(player.inventory, log)
	ticks := int(test.species.felling_ticks)
	testing.expect_value(t, ticks, 360)
	hold_felling_test_mine(test, ticks - 1)
	testing.expect_value(t, inventory_count(player.inventory, log), before)
	testing.expect(t, player.mining.tree, "the progress is a felling")
	testing.expect(t, mining_fraction(player.mining) > 0 && mining_fraction(player.mining) < 1)
	tick_field_test_simulation(state, test.content, FELLING_TEST_MINE)
	testing.expect_value(t, inventory_count(player.inventory, log), before + 4)
	testing.expect(t, test.tree.key in state.field.felled_trees, "the tree is felled")
	tick_field_test_simulation(state, test.content, {})
	testing.expect(t, !aims_at_test_tree(test), "the felled trunk takes no aim")
	closest := i64(max(i64))
	for _ in 0 ..< 180 {
		tick_field_test_simulation(state, test.content, FELLING_TEST_WALK)
		closest = min(closest, felling_test_axis_distance(test, player.field.position))
	}
	testing.expectf(t, closest < test.trunk.radius + test.content.field.tuning.capsule_radius - FIELD_PENETRATION_TOLERANCE, "the walk passes the felled trunk's place, %d units off", closest)
}

@(test)
test_felling_is_refused_with_a_full_inventory :: proc(t: ^testing.T) {
	test, found := start_felling_test(test_field_game_config(), make_field_test_game_content())
	defer end_session(test.session)
	testing.expect(t, found)
	if !found {
		return
	}
	state := &test.session.simulation
	player := &state.players[0]
	stone := test_item(test.content.items, "stone")
	for &slot in player.inventory.slots {
		slot = Item_Stack{stone, item_stack_size(test.content.items, stone)}
	}
	clear(&state.events)
	hold_felling_test_mine(test, 60)
	testing.expect(t, !player.mining.active, "no progress")
	testing.expect_value(t, count_field_refused_events(state.events[:], .Inventory_Full), 1)
	testing.expect(t, test.tree.key not_in state.field.felled_trees, "the tree stands")
}

@(test)
test_a_felled_tree_stays_felled_after_a_save_and_load :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	test, found := start_felling_test(config, content)
	testing.expect(t, found)
	if !found {
		end_session(test.session)
		return
	}
	state := &test.session.simulation
	hold_felling_test_mine(test, int(test.species.felling_ticks))
	testing.expect(t, test.tree.key in state.field.felled_trees)
	felled := make(map[Tree_Key]struct{}, context.temp_allocator)
	for key in state.field.felled_trees {
		felled[key] = {}
	}
	hash := simulation_state_hash(state)
	files := encode_save_files(state, test.content, "felled", 0)
	end_session(test.session)
	loaded := load_test_field_save(config, content, &files)
	defer end_session(loaded)
	restored := &loaded.simulation
	stage_generated_field_set(restored)
	testing.expect(t, restore_arrived_field_set(&restored.field), "the staged set restores")
	testing.expect_value(t, len(restored.field.felled_trees), len(felled))
	for key in felled {
		testing.expect(t, key in restored.field.felled_trees)
	}
	testing.expect(t, restored.field.felled_trees_recorded)
	testing.expect_value(t, simulation_state_hash(restored), hash)
	for tree in field_trees_near(&restored.field, test.tree.base, metres_to_position_units(5)) {
		testing.expect(t, tree.key != test.tree.key, "the felled tree does not regenerate")
	}
}

@(test)
test_two_sessions_fell_alike :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	tests: [3]Felling_Test
	for &test, index in tests {
		found: bool
		test, found = start_felling_test(config, content)
		testing.expectf(t, found, "session %d has a stand", index)
	}
	defer for test in tests {
		end_session(test.session)
	}
	ticks := int(tests[0].species.felling_ticks) + 30
	for tick in 0 ..< ticks {
		frame := tick < ticks - 30 ? FELLING_TEST_MINE : Input_Frame{}
		if tick == 0 {
			frame.just_pressed = {.Mine}
		}
		for index in 0 ..< 2 {
			tick_field_test_simulation(&tests[index].session.simulation, tests[index].content, frame)
		}
		tick_field_test_simulation(&tests[2].session.simulation, tests[2].content, {})
		if tick % 30 == 29 {
			testing.expectf(t, simulation_state_hash(&tests[0].session.simulation) == simulation_state_hash(&tests[1].session.simulation), "the hashes part at tick %d", tick)
		}
	}
	testing.expect(t, tests[0].tree.key in tests[0].session.simulation.field.felled_trees)
	testing.expect_value(t, simulation_state_hash(&tests[0].session.simulation), simulation_state_hash(&tests[1].session.simulation))
	testing.expect(t, simulation_state_hash(&tests[0].session.simulation) != simulation_state_hash(&tests[2].session.simulation), "a session that does not fell hashes apart")
}

// A save written before the trees (its entities cut before the felled
// table) reads with no tree felled and the set not recorded; its load
// fells once the tree standing in its free foundation, and only that one.
@(test)
test_an_old_save_without_the_tree_table_loads_with_no_tree_felled :: proc(t: ^testing.T) {
	empty: Field_Simulation
	defer destroy_field_simulation(&empty)
	reader := Byte_Reader{}
	testing.expect(t, read_felled_tree_table(&reader, &empty))
	testing.expect_value(t, len(empty.felled_trees), 0)
	testing.expect(t, !empty.felled_trees_recorded)
	twice := make([dynamic]byte, context.temp_allocator)
	write_list(&twice, []Felled_Tree_Record{{key = {1, 2, 3}}, {key = {1, 2, 3}}})
	reader = Byte_Reader{data = twice[:]}
	testing.expect(t, !read_felled_tree_table(&reader, &empty), "a key listed twice is malformed")

	config := test_field_game_config()
	content := make_field_test_game_content()
	test, found := start_felling_test(config, content)
	testing.expect(t, found)
	if !found {
		end_session(test.session)
		return
	}
	state := &test.session.simulation
	ground := test.tree.base + World_Position(fixed_scale(test.tree.up, millimetres_to_position_units(PLANET_TREE_BASE_SINK_MILLIMETRES)))
	place_free_foundation(&state.world.entities, test.content.machines, field_pad_foundation(test.content), ground, test.toward, test.content.field.foundation_pitch_millimetres)
	other: Tree_Key
	other_found := false
	for tree in test.trees {
		if distance := vector_length(tree_test_on_sphere(state.field.world.water_planet.generation, tree) - test.on_sphere); distance >= metres_to_position_units(8) && distance <= metres_to_position_units(12) {
			other, other_found = tree.key, true
			break
		}
	}
	testing.expect(t, other_found, "a second tree about 10 m off")
	files := encode_save_files(state, test.content, "before trees", 0)
	table := make([dynamic]byte, context.temp_allocator)
	write_felled_tree_table(&table, &state.field)
	// The arrival's table (0200) follows; a save from before the trees
	// ends before both.
	write_field_arrival_table(&table, &state.field)
	end_session(test.session)
	testing.expect(t, slice.equal(files.entities[len(files.entities) - len(table):], table[:]), "the save ends with the felled and the arrival tables")
	files.entities = files.entities[:len(files.entities) - len(table)]
	loaded := load_test_field_save(config, content, &files)
	defer end_session(loaded)
	felled := loaded.simulation.field.felled_trees
	testing.expect_value(t, len(felled), 1)
	testing.expect(t, test.tree.key in felled, "the tree in the foundation is cleared")
	testing.expect(t, other not_in felled, "the tree 10 m off stands")
	testing.expect(t, loaded.simulation.field.felled_trees_recorded)
}

@(test)
test_a_trunk_stops_the_walk :: proc(t: ^testing.T) {
	test, found := start_felling_test(test_field_game_config(), make_field_test_game_content())
	defer end_session(test.session)
	testing.expect(t, found)
	if !found {
		return
	}
	state := &test.session.simulation
	tuning := test.content.field.tuning
	allowed := test.trunk.radius + tuning.capsule_radius - FIELD_PENETRATION_TOLERANCE
	closest := i64(max(i64))
	for tick in 0 ..< 120 {
		predicted := state.players[0]
		predict_field_player_motion(state, test.content, &predicted, FELLING_TEST_WALK)
		tick_field_test_simulation(state, test.content, FELLING_TEST_WALK)
		testing.expectf(t, predicted.field.position == state.players[0].field.position, "the prediction walks as the tick at tick %d", tick)
		closest = min(closest, felling_test_axis_distance(test, state.players[0].field.position))
	}
	testing.expectf(t, closest >= allowed, "the walk came %d units from the axis, %d allowed", closest, allowed)
	testing.expectf(t, closest <= allowed + millimetres_to_position_units(100), "the walk reached the trunk, %d units from the axis", closest)
}

@(test)
test_the_trunk_takes_the_aim :: proc(t: ^testing.T) {
	test, found := start_felling_test(test_field_game_config(), make_field_test_game_content())
	defer end_session(test.session)
	testing.expect(t, found)
	if !found {
		return
	}
	state := &test.session.simulation
	player := &state.players[0].field
	testing.expect(t, aims_at_test_tree(test))
	testing.expect(t, !player.target.hit && !player.frame_target.hit, "the trunk clears the other targets")
	eye := field_player_eye(player^, test.content.field.tuning)
	expected := f64(felling_test_axis_distance(test, eye) - test.trunk.radius) / math.cos(f64(player.pitch) * math.TAU / ANGLE_UNITS_PER_TURN)
	testing.expectf(t, abs(f64(player.tree_target.distance) - expected) <= f64(millimetres_to_position_units(60)), "the trunk at %d units, %.0f expected", player.tree_target.distance, expected)
	player.yaw = degrees_to_angle_units(30)
	tick_field_test_simulation(state, test.content, {})
	testing.expect(t, !aims_at_test_tree(test), "turned aside the trunk takes no aim")
}

@(test)
test_a_placement_into_a_trunk_is_refused :: proc(t: ^testing.T) {
	test, found := start_felling_test(test_field_game_config(), make_field_test_game_content())
	defer end_session(test.session)
	testing.expect(t, found)
	if !found {
		return
	}
	state := &test.session.simulation
	content := test.content
	// The furnace's flatness is not what this test is about.
	content.field.bare_ground.flatness_millimetres = MILLIMETRES_PER_METRE * 100
	player := &state.players[0]
	foundation := field_pad_foundation(content)
	furnace := test_machine(content.machines, "stone_furnace")
	inventory_add(player.inventory, content.items, content.machines.machines[foundation].item, 8)
	inventory_add(player.inventory, content.items, content.machines.machines[furnace].item, 1)
	generation := field_tree_generation(&state.field)
	ground := test.tree.base + World_Position(fixed_scale(test.tree.up, millimetres_to_position_units(PLANET_TREE_BASE_SINK_MILLIMETRES)))
	free := Field_Placement{machine = foundation, new_frame = true, hit = ground, heading = test.toward}
	testing.expect_value(t, field_placement_refusal(state, content, player^, free), Field_Edit_Refusal.Tree_In_The_Way)
	bare := Field_Placement{machine = furnace, new_frame = true, hit = ground, heading = test.toward}
	testing.expect_value(t, field_placement_refusal(state, content, player^, bare), Field_Edit_Refusal.Tree_In_The_Way)
	beyond := test.on_sphere + fixed_scale(test.toward, millimetres_to_position_units(1000))
	_, frame := place_free_foundation(&state.world.entities, content.machines, foundation, field_surface_under(generation^, World_Position(beyond), 0), -test.toward, content.field.foundation_pitch_millimetres)
	snapped := Field_Placement{machine = foundation, frame = frame, cell = {0, 0, 2}, normal = {0, 0, 1}, size = 1, height = 1}
	testing.expect_value(t, field_placement_refusal(state, content, player^, snapped), Field_Edit_Refusal.Tree_In_The_Way)
	away_found := false
	for step in 0 ..< 8 {
		point, tangent := felling_test_point(test.on_sphere, test.tree.up, i32(step * ANGLE_UNITS_PER_TURN / 8), 4000)
		if !felling_test_spot_is_clear(generation, test.trees, test.tree, point) {
			continue
		}
		away := Field_Placement{machine = foundation, new_frame = true, hit = field_surface_under(generation^, World_Position(point), 0), heading = tangent}
		testing.expect_value(t, field_placement_refusal(state, content, player^, away), Field_Edit_Refusal.None)
		away_found = true
		break
	}
	testing.expect(t, away_found, "a spot 4 m away clear of trunks")
}

// Approval of 0197: a dig that hollows the ground under a trunk's base
// fells the tree without yield; a shallow dig leaves it.
@(test)
test_a_tree_falls_into_a_hole_dug_under_it :: proc(t: ^testing.T) {
	test, found := start_felling_test(test_field_game_config(), make_field_test_game_content())
	defer end_session(test.session)
	testing.expect(t, found)
	if !found {
		return
	}
	state := &test.session.simulation
	content := test.content
	log := test_item(content.items, "log")
	before := inventory_count(state.players[0].inventory, log)
	ground := test.tree.base + World_Position(fixed_scale(test.tree.up, millimetres_to_position_units(PLANET_TREE_BASE_SINK_MILLIMETRES)))
	brush := Field_Brush{shape = .Sphere, radius = millimetres_to_position_units(600), rate = MAXIMUM_DENSITY * 2}
	shallow := Field_Edit{mode = .Dig, brush = brush, centre = ground + World_Position(fixed_scale(test.tree.up, millimetres_to_position_units(400))), up = test.tree.up}
	append(&state.field.edits, Queued_Field_Edit{player = 0, edit = shallow})
	tick_field_test_simulation(state, content, {})
	testing.expect(t, test.tree.key not_in state.field.felled_trees, "a dig above the base leaves the tree")
	for depth in ([3]int{200, 800, 1400}) {
		deep := shallow
		deep.centre = test.tree.base - World_Position(fixed_scale(test.tree.up, millimetres_to_position_units(depth)))
		for _ in 0 ..< 4 {
			append(&state.field.edits, Queued_Field_Edit{player = 0, edit = deep})
			tick_field_test_simulation(state, content, {})
		}
	}
	testing.expect(t, test.tree.key in state.field.felled_trees, "the tree falls into the hole")
	testing.expect_value(t, inventory_count(state.players[0].inventory, log), before)
}
