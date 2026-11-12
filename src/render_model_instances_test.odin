package game

import "core:math/linalg"
import "core:testing"
import rl "shared:raylib"

// Work item 0347: the machines' draws culled and instanced, without GL.

@(test)
test_a_frame_matrix_table_finds_every_frame :: proc(t: ^testing.T) {
	entities: Entities
	defer destroy_entities(&entities)
	for index in 0 ..< 4 {
		origin := World_Position{i64(index) * 3 * POSITION_UNITS_PER_METRE, 8000 * POSITION_UNITS_PER_METRE, 0}
		add_frame(&entities.frames, origin, TEST_RUN_AXES, 500 + 100 * index)
	}
	remove_frame(&entities.frames, Frame_Id(2))
	table := frame_matrix_table(&entities.frames)
	with_table := Model_Frame{frames = &table}
	for id in ([3]Frame_Id{1, 3, 4}) {
		record, _ := find_frame(&entities.frames, id)
		entry, found := find_frame_matrix(table, id)
		testing.expectf(t, found && entry.frame == record, "frame %d found with its record", id)
		testing.expectf(t, entry.transform == frame_render_matrix(record), "frame %d's matrix", id)
		testing.expectf(t, model_frame_entity_matrix(with_table, &entities, id) == entity_frame_matrix(&entities, id), "frame %d as entity_frame_matrix", id)
	}
	for id in ([2]Frame_Id{2, 99}) {
		entry, found := find_frame_matrix(table, id)
		testing.expectf(t, !found && entry.transform == 1, "frame %d is missing, the identity", id)
		testing.expectf(t, model_frame_entity_matrix(with_table, &entities, id) == entity_frame_matrix(&entities, id), "frame %d as entity_frame_matrix", id)
	}
	block, found := find_frame_matrix(table, BLOCK_FRAME)
	testing.expect(t, found && block.transform == 1, "the block frame is found, the identity")
	testing.expect_value(t, block.frame.pitch_millimetres, BLOCK_FRAME_PITCH_MILLIMETRES)
	testing.expect(t, model_frame_entity_matrix(with_table, &entities, BLOCK_FRAME) == entity_frame_matrix(&entities, BLOCK_FRAME))
}

// A metre's box round the centre.
model_test_box :: proc(centre: [3]f32) -> (minimum, maximum: [3]f32) {
	return centre - 0.5, centre + 0.5
}

@(test)
test_the_view_cull_takes_the_frustum_and_the_haze_end :: proc(t: ^testing.T) {
	eye := [3]f32{0, 8000, 0}
	view := Model_View{frustum = tree_test_frustum(eye, 0), eye = eye, distance_metres = 512, transform = 1}
	testing.expect(t, model_view_shows(&view, model_test_box(eye + {10, 0, 0})), "10 m ahead")
	testing.expect(t, !model_view_shows(&view, model_test_box(eye - {10, 0, 0})), "10 m behind")
	testing.expect(t, !model_view_shows(&view, model_test_box(eye + {600, 0, 0})), "600 m ahead, past the haze's end")
	testing.expect(t, model_view_shows(&view, eye + {500, -0.5, -0.5}, eye + {520, 0.5, 0.5}), "from 500 to 520 m ahead")
	moved := view
	moved.transform = linalg.matrix4_translate_f32({20, 0, 0})
	testing.expect(t, model_view_shows(&moved, model_test_box(eye - {10, 0, 0})), "10 m behind moved 20 m ahead")
	view.distance_metres = 0
	testing.expect(t, model_view_shows(&view, model_test_box(eye + {600, 0, 0})), "600 m ahead, the frustum alone")
	testing.expect(t, model_view_shows(nil, model_test_box(eye - {10, 0, 0})), "no view shows everything")
}

// Work item 0360: only the scene's pass collecting instances draws the
// pools' batch through the model shader's flat batch.
@(test)
test_only_the_scenes_collecting_pass_draws_its_batch_flat :: proc(t: ^testing.T) {
	view := Model_View{transform = 1}
	instances: [dynamic]Model_Instance
	casters: Sun_Shadow_Casters
	testing.expect(t, model_frame_flat_batch(Model_Frame{view = &view, instances = &instances}), "the scene's collecting pass")
	testing.expect(t, !model_frame_flat_batch(Model_Frame{view = &view}), "a view alone, whose models draw by DrawMesh")
	testing.expect(t, !model_frame_flat_batch(Model_Frame{instances = &instances, casters = &casters}), "the sun's pass")
	testing.expect(t, !model_frame_flat_batch(Model_Frame{}), "the zero frame")
}

// Layers without GL, each with vertexCount set.
test_uploaded_layers :: proc(lit, emissive: i32) -> Uploaded_Layers {
	return {.Lit = {vertexCount = lit}, .Emissive = {vertexCount = emissive}}
}

// A machine's uploaded model as its CPU meshes would give it, without GL.
test_uploaded_model :: proc(mesh: Machine_Model_Mesh) -> (model: Uploaded_Machine_Model) {
	counts :: proc(layers: Model_Layers) -> Uploaded_Layers {
		return test_uploaded_layers(i32(len(layers[.Lit].positions)), i32(len(layers[.Emissive].positions)))
	}
	model.body, model.part = counts(mesh.body), counts(mesh.part)
	for layers, part in mesh.arm {
		model.arm[part] = counts(layers)
	}
	model.bounds = machine_model_bounds(mesh)
	return model
}

// A hatch of footprint 3 by 1 by 3 whose iris has three blades.
test_iris_hatch :: proc() -> Machine {
	machine := Machine{kind = .Hatch, footprint = {3, 1, 3}}
	machine.motion = {kind = .Iris, axis = 1, amplitude = 0.25, period_seconds = 1, pivot = {1.5, 0.5, 1.5}, blades = 3, hinge = {1.5, 0.5, 2.5}}
	return machine
}

@(test)
test_a_posed_model_appends_what_it_would_draw :: proc(t: ^testing.T) {
	models := [1]Uploaded_Machine_Model{{body = test_uploaded_layers(24, 6), part = test_uploaded_layers(12, 0)}}
	models[0].bounds[.Body] = {{-1.5, 0, -1.5}, {1.5, 1, 1.5}}
	models[0].bounds[.Part] = {{-0.5, 0, -0.5}, {0.5, 0.2, 0.5}}
	renderer := Model_Renderer{models = models[:]}
	machine := test_iris_hatch()
	common := Entity_Common{machine = 0, origin = {2, 1, 3}, size = {3, 1, 3}, rotation = 1, frame = BLOCK_FRAME}
	world: World
	list := make([dynamic]Model_Instance, context.temp_allocator)
	frame := Model_Frame{world = &world, open_sky = true, day_factor = 1, sky_tint = 1, instances = &list}
	pose := Model_Pose{phase = 0.5, working = true}
	testing.expect(t, draw_posed_model(renderer, common, machine, frame, pose), "the model is shown")
	testing.expect_value(t, len(list), 4)
	if len(list) != 4 {
		return
	}
	body := model_transform(common.origin, common.size, common.rotation)
	poses := motion_part_transforms(machine.motion, machine.footprint, pose.phase)
	light_tint, glow := posed_model_light(frame, common, machine, pose)
	colors := [Model_Layer]rl.Color{.Lit = brightness_color(light_tint), .Emissive = brightness_color(glow)}
	testing.expect_value(t, list[0].piece, Model_Piece{0, .Body})
	testing.expect(t, list[0].transform == body, "the body's transform")
	for blade in 0 ..< 3 {
		instance := list[1 + blade]
		testing.expect_value(t, instance.piece, Model_Piece{0, .Part})
		testing.expectf(t, instance.transform == body * poses.transforms[blade], "blade %d's transform", blade)
	}
	for instance in list {
		testing.expect_value(t, instance.colors, colors)
	}
	eye := [3]f32{100, 0, 0}
	away := Model_View{frustum = tree_test_frustum(eye, 0), eye = eye, transform = 1}
	frame.view = &away
	clear(&list)
	testing.expect(t, !draw_posed_model(renderer, common, machine, frame, pose), "a view looking away leaves it out")
	testing.expect_value(t, len(list), 0)
	testing.expect(t, !model_frame_takes_instances(frame, .Pod), "the pod draws alone")
	testing.expect(t, model_frame_takes_instances(frame, .Hatch), "a hatch is instanced")
}

// Whether the point lies in the box, within a thousandth.
point_in_posed_box :: proc(point, minimum, maximum: [3]f32) -> bool {
	for axis in 0 ..< 3 {
		if point[axis] < minimum[axis] - 1e-3 || point[axis] > maximum[axis] + 1e-3 {
			return false
		}
	}
	return true
}

@(test)
test_a_posed_box_holds_a_slid_part_and_a_reaching_arm :: proc(t: ^testing.T) {
	door := [1]Uploaded_Machine_Model{{body = test_uploaded_layers(8, 0), part = test_uploaded_layers(8, 0)}}
	door[0].bounds[.Body] = {{-1, 0, -1}, {1, 2, 1}}
	door[0].bounds[.Part] = {{-1, 0, -1}, {1, 2, 1}}
	machine := Machine{kind = .Hatch, footprint = {2, 2, 2}}
	machine.motion = {kind = .Slide, axis = 0, amplitude = 12, period_seconds = 1}
	body := model_transform({}, {2, 2, 2}, 0)
	posed := pose_machine_model(Model_Renderer{models = door[:]}, 0, body, machine, 1)
	testing.expect_value(t, posed.count, 2)
	slide := body * motion_part_transforms(machine.motion, machine.footprint, 1).transforms[0]
	for corner in 0 ..< 8 {
		point := [3]f32{corner & 1 == 0 ? -1 : 1, corner & 2 == 0 ? 0 : 2, corner & 4 == 0 ? -1 : 1}
		testing.expectf(t, point_in_posed_box(transform_point(slide, point), posed.minimum, posed.maximum), "the slid part's corner %d", corner)
	}
	testing.expectf(t, abs(posed.maximum.x - 14) < 1e-4, "the box reaches 12 cells past the body's 2: %v", posed.maximum)

	machines := make_test_machines()
	inserter := machines.machines[test_machine(machines, "burner_inserter")]
	mesh, problem := load_machine_model_mesh(test_data_directory(), inserter)
	defer destroy_machine_model_mesh(mesh)
	testing.expect_value(t, problem, "")
	arm := [1]Uploaded_Machine_Model{test_uploaded_model(mesh)}
	renderer := Model_Renderer{models = arm[:]}
	testing.expect(t, model_slot_bounds({}).minimum.x > model_slot_bounds({}).maximum.x, "empty layers' bounds are inverted")
	common := Entity_Common{size = {1, 1, 1}}
	for fraction in ([5]f32{0, ARM_GRAB_END, 0.25, ARM_DROP_FRACTION, 0.75}) {
		placement := Arm_Placement{transform = arm_entity_transform(common, 500), dimensions = arm_dimensions_on_frame(4, 500), fraction = fraction}
		arm_posed, angles := pose_arm(renderer, 0, placement)
		testing.expectf(t, arm_posed.count == 7, "%v: %d pieces", fraction, arm_posed.count)
		hand := transform_point(placement.transform, arm_hand_point(placement.dimensions, angles))
		testing.expectf(t, point_in_posed_box(hand, arm_posed.minimum, arm_posed.maximum), "%v: the hand %v in %v to %v", fraction, hand, arm_posed.minimum, arm_posed.maximum)
		if arm_shows_held_item(fraction) {
			low, high := held_item_box(hand)
			grow_posed_box(&arm_posed, low, high)
			testing.expectf(t, point_in_posed_box(low, arm_posed.minimum, arm_posed.maximum) && point_in_posed_box(high, arm_posed.minimum, arm_posed.maximum), "%v: the held item", fraction)
		}
		if fraction == ARM_GRAB_END || fraction == ARM_DROP_FRACTION {
			outside := max(-hand.x, hand.x - 1, -hand.z, hand.z - 1)
			testing.expectf(t, outside > 3, "%v: the hand %v cells outside the footprint", fraction, outside)
			margin_low, margin_high := sun_shadow_entity_box(1, {}, {1, 1, 1}, 1)
			testing.expectf(t, !point_in_posed_box(hand, margin_low, margin_high), "%v: past the one cell margin", fraction)
		}
	}
}

@(test)
test_model_instances_pack_by_layer_and_piece :: proc(t: ^testing.T) {
	models := [3]Uploaded_Machine_Model{}
	models[1].body = test_uploaded_layers(11, 0)
	models[1].part = test_uploaded_layers(12, 13)
	models[2].body = test_uploaded_layers(21, 22)
	renderer := Model_Renderer{models = models[:]}
	at :: proc(x: f32) -> matrix[4, 4]f32 {
		return linalg.matrix4_translate_f32({x, 2 * x, 3 * x})
	}
	lit, glow := rl.Color{10, 20, 30, 255}, rl.Color{200, 100, 50, 255}
	instances := [5]Model_Instance {
		{piece = {2, .Body}, transform = at(1), colors = {.Lit = lit, .Emissive = glow}},
		{piece = {1, .Part}, transform = at(2), colors = {.Lit = lit, .Emissive = glow}},
		{piece = {2, .Body}, transform = at(3), colors = {.Lit = lit, .Emissive = glow}},
		{piece = {1, .Body}, transform = at(4), colors = {.Lit = lit, .Emissive = glow}},
		{piece = {1, .Part}, transform = at(5), colors = {.Lit = lit, .Emissive = glow}},
	}
	packed := make([dynamic]matrix[4, 4]f32, context.temp_allocator)
	groups: [Model_Layer][dynamic]Model_Instance_Group
	for &list in groups {
		list = make([dynamic]Model_Instance_Group, context.temp_allocator)
	}
	pack_model_instances(renderer, instances[:], &packed, &groups)
	testing.expect_value(t, len(packed), 9)
	expected := [Model_Layer][]Model_Instance_Group {
		.Lit      = {{mesh = {vertexCount = 11}, first = 0, count = 1}, {mesh = {vertexCount = 12}, first = 1, count = 2}, {mesh = {vertexCount = 21}, first = 3, count = 2}},
		.Emissive = {{mesh = {vertexCount = 13}, first = 5, count = 2}, {mesh = {vertexCount = 22}, first = 7, count = 2}},
	}
	for layer in Model_Layer {
		testing.expectf(t, len(groups[layer]) == len(expected[layer]), "%v: %d groups", layer, len(groups[layer]))
		for group, index in groups[layer] {
			if index < len(expected[layer]) {
				wanted := expected[layer][index]
				testing.expectf(t, group.mesh.vertexCount == wanted.mesh.vertexCount && group.first == wanted.first && group.count == wanted.count, "%v group %d: %v", layer, index, group)
			}
		}
	}
	// The packed order: machine 1's body, its parts, machine 2's bodies in
	// their order, then the emissive layer's.
	order := [9]f32{4, 2, 5, 1, 3, 2, 5, 1, 3}
	colors := [9]rl.Color{lit, lit, lit, lit, lit, glow, glow, glow, glow}
	for instance, index in packed {
		expected_transform := at(order[index])
		for row in 0 ..< 3 {
			for column in 0 ..< 4 {
				testing.expectf(t, instance[row, column] == expected_transform[row, column], "matrix %d at %d, %d", index, row, column)
			}
		}
		color := colors[index]
		testing.expectf(t, instance[3, 0] == f32(color.r) / 255 && instance[3, 1] == f32(color.g) / 255 && instance[3, 2] == f32(color.b) / 255 && instance[3, 3] == 1, "matrix %d's colour row %v", index, instance)
	}
}

@(test)
test_the_unit_cube_and_its_edges :: proc(t: ^testing.T) {
	cube := unit_cube_mesh()
	testing.expect_value(t, len(cube.positions), 24)
	testing.expect_value(t, len(cube.indices), 36)
	for position in cube.positions {
		for axis in 0 ..< 3 {
			testing.expectf(t, abs(position[axis]) == 0.5, "corner %v", position)
		}
	}
	for color in cube.colors {
		testing.expect_value(t, color, [4]u8{255, 255, 255, 255})
	}
	for triangle in 0 ..< 12 {
		corners: [3][3]f32
		for corner in 0 ..< 3 {
			corners[corner] = cube.positions[cube.indices[3 * triangle + corner]]
		}
		winding := linalg.cross(corners[1] - corners[0], corners[2] - corners[0])
		middle := (corners[0] + corners[1] + corners[2]) / 3
		testing.expectf(t, linalg.dot(winding, middle) > 0, "triangle %d winds counter clockwise from outside", triangle)
	}
	edges := cube_edge_mesh(FRAME_EDGE_COLOR)
	testing.expect_value(t, len(edges.positions), 24)
	testing.expect_value(t, len(edges.indices), 0)
	seen: [3][4]bool
	for segment in 0 ..< 12 {
		start, end := edges.positions[2 * segment], edges.positions[2 * segment + 1]
		along := -1
		for axis in 0 ..< 3 {
			if start[axis] != end[axis] {
				along = axis
			}
		}
		testing.expectf(t, along >= 0 && linalg.length(end - start) == 1, "segment %d is 1 long along one axis", segment)
		if along < 0 {
			continue
		}
		first, second := start[(along + 1) % 3], start[(along + 2) % 3]
		testing.expectf(t, abs(first) == 0.5 && abs(second) == 0.5, "segment %d lies on an edge", segment)
		slot := (first > 0 ? 1 : 0) + (second > 0 ? 2 : 0)
		testing.expectf(t, !seen[along][slot], "segment %d is drawn once", segment)
		seen[along][slot] = true
	}
	for color in edges.colors {
		testing.expect_value(t, color, [4]u8{FRAME_EDGE_COLOR.r, FRAME_EDGE_COLOR.g, FRAME_EDGE_COLOR.b, FRAME_EDGE_COLOR.a})
	}
}
