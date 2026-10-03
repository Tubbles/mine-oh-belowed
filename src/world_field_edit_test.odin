package game

import "core:testing"

// A world of the chunks round the origin, every sample the given one.
make_uniform_test_field :: proc(sample: Field_Sample, reach: i32 = 1) -> Field_World {
	world: Field_World
	for z in -reach ..< reach {
		for y in -reach ..< reach {
			for x in -reach ..< reach {
				chunk := new(Field_Chunk)
				chunk.coordinate = {x, y, z}
				for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
					field_chunk_set_sample(chunk, index, sample)
				}
				field_world_insert_chunk(&world, chunk)
			}
		}
	}
	return world
}

test_brush :: proc(shape: Field_Brush_Shape, radius_millimetres: int, rate: i32) -> Field_Brush {
	return {shape = shape, radius = millimetres_to_position_units(radius_millimetres), rate = rate}
}

// The sum of the positive densities, the ground's volume in steps.
field_ground_steps :: proc(world: ^Field_World) -> i64 {
	total: i64 = 0
	for _, chunk in world.chunks {
		for density in chunk.density {
			total += field_ground_volume(density)
		}
	}
	return total
}

field_worlds_equal :: proc(first, second: ^Field_World) -> bool {
	if len(first.chunks) != len(second.chunks) {
		return false
	}
	for coordinate, chunk in first.chunks {
		other := second.chunks[coordinate] or_else nil
		if other == nil || chunk.density != other.density || chunk.material != other.material || chunk.tint != other.tint {
			return false
		}
	}
	return true
}

// A dig of stone counts the positive part it took; a place raises air to
// ground of its material up to its budget and stops there.
@(test)
test_a_dig_counts_the_ground_it_takes_and_a_place_its_budget :: proc(t: ^testing.T) {
	world := make_uniform_test_field({MAXIMUM_DENSITY, .Stone, 2})
	defer destroy_field_world(&world)
	centre := sample_to_world_position({0, 0, 0}, 1000)
	dig := Field_Edit {
		mode     = .Dig,
		brush    = test_brush(.Sphere, 1500, 50),
		centre   = centre,
		diggable = {.Stone},
	}
	result := apply_field_edit(&world, 1000, dig)
	// 19 samples lie within 1.5 samples of a sample: 1, 6 faces, 12 edges.
	testing.expect_value(t, result.steps[.Stone], 19 * 50)
	testing.expect_value(t, field_ground_steps(&world), 8 * FIELD_CHUNK_SAMPLE_COUNT * MAXIMUM_DENSITY - 19 * 50)
	testing.expect(t, len(world.edited_chunks) > 0, "the edit records its chunks for the coarser levels")

	air := make_uniform_test_field(FIELD_AIR_SAMPLE)
	defer destroy_field_world(&air)
	place := Field_Edit {
		mode     = .Place,
		brush    = test_brush(.Sphere, 1500, 254),
		centre   = centre,
		material = .Stone,
		tint     = 1,
		budget   = 300,
	}
	placed := apply_field_edit(&air, 1000, place)
	testing.expect_value(t, placed.steps[.Stone], 300)
	testing.expect_value(t, field_ground_steps(&air), 300)
	// In sample order (z, then y, then x) the first two inside fill and the
	// third takes the rest of the budget.
	testing.expect_value(t, field_world_get_sample(&air, {0, -1, -1}), Field_Sample{MAXIMUM_DENSITY, .Stone, 1})
	testing.expect_value(t, field_world_get_sample(&air, {0, 0, -1}).density, 300 - 2 * MAXIMUM_DENSITY)
	testing.expect_value(t, field_world_get_sample(&air, {1, 0, -1}), FIELD_AIR_SAMPLE)
}

// Ground outside the diggable materials is left and reported; a place
// never raises ground of another material.
@(test)
test_an_edit_leaves_other_materials :: proc(t: ^testing.T) {
	world := make_uniform_test_field({MAXIMUM_DENSITY, .Deep_Stone, 0})
	defer destroy_field_world(&world)
	before := make_uniform_test_field({MAXIMUM_DENSITY, .Deep_Stone, 0})
	defer destroy_field_world(&before)
	centre := sample_to_world_position({0, 0, 0}, 1000)
	result := apply_field_edit(&world, 1000, Field_Edit{mode = .Dig, brush = test_brush(.Sphere, 1500, 50), centre = centre, diggable = {.Stone}})
	testing.expect_value(t, result.blocked, bit_set[Field_Material]{.Deep_Stone})
	testing.expect_value(t, result.steps[.Deep_Stone], 0)
	world.chunks[{0, 0, 0}].density[0] = 10
	before.chunks[{0, 0, 0}].density[0] = 10
	placed := apply_field_edit(&world, 1000, Field_Edit{mode = .Place, brush = test_brush(.Sphere, 1500, 50), centre = centre, material = .Stone, budget = 1000})
	testing.expect_value(t, placed.steps[.Stone], 0)
	testing.expect(t, field_worlds_equal(&world, &before), "nothing changed")
}

// The level mode flattens a slope to the plane through the hit across
// the up: a dig cuts what lies above, a place fills what lies below.
@(test)
test_the_level_mode_flattens_a_slope_to_the_plane :: proc(t: ^testing.T) {
	world := make_test_field(Test_Terrain{kind = .Slope, slope_degrees = 20}, 1000)
	defer destroy_field_world(&world)
	edit := Field_Edit {
		brush    = test_brush(.Level, 3000, 254),
		centre   = test_site_point(0, 0, 0),
		up       = {0, UNIT_VECTOR_ONE, 0},
		diggable = {.Stone},
		material = .Stone,
		budget   = 1 << 40,
	}
	for mode in Field_Edit_Mode {
		edit.mode = mode
		apply_field_edit(&world, 1000, edit)
	}
	first, last := field_edit_bounds(edit, 1000)
	off_plane := 0
	inside := 0
	for z in first.z ..= last.z {
		for y in first.y ..= last.y {
			for x in first.x ..= last.x {
				position := sample_to_world_position({x, y, z}, 1000)
				if !field_sample_in_brush(edit, position) {
					continue
				}
				inside += 1
				if field_world_get_sample(&world, {x, y, z}).density != field_plane_density(edit, position, 1000) {
					off_plane += 1
				}
			}
		}
	}
	testing.expect(t, inside > 50, "the brush covers the slope")
	testing.expect_value(t, off_plane, 0)
}

// The same edits on two worlds give the same bytes.
@(test)
test_the_same_edits_give_the_same_bytes :: proc(t: ^testing.T) {
	worlds := [2]Field_World{make_test_field(Test_Terrain{kind = .Slope, slope_degrees = 30}, 500), make_test_field(Test_Terrain{kind = .Slope, slope_degrees = 30}, 500)}
	defer destroy_field_world(&worlds[0])
	defer destroy_field_world(&worlds[1])
	edits := [?]Field_Edit {
		{mode = .Dig, brush = test_brush(.Sphere, 1700, 37), centre = test_site_point(300, 0, -200), diggable = {.Stone}},
		{mode = .Place, brush = test_brush(.Sphere, 900, 90), centre = test_site_point(-4000, 0, 1000), material = .Topsoil, tint = 2, budget = 5000},
		{mode = .Dig, brush = test_brush(.Level, 2500, 11), centre = test_site_point(800, 500, 0), up = {0, UNIT_VECTOR_ONE, 0}, diggable = {.Stone, .Topsoil}},
	}
	results: [2][len(edits)]Field_Edit_Result
	for &world, index in worlds {
		for edit, edit_index in edits {
			results[index][edit_index] = apply_field_edit(&world, 500, edit)
		}
	}
	testing.expect(t, field_worlds_equal(&worlds[0], &worlds[1]), "the bytes agree")
	testing.expect_value(t, results[0], results[1])
	testing.expectf(t, results[0][0].steps[.Stone] > 0 && results[0][1].steps[.Topsoil] > 0, "the edits changed the field: %v", results[0])
}

// The reticle reads the strongest ground corner round the hit.
@(test)
test_the_ground_sample_at_a_point :: proc(t: ^testing.T) {
	world := make_uniform_test_field(FIELD_AIR_SAMPLE)
	defer destroy_field_world(&world)
	field_world_set_sample(&world, {1, 0, 0}, {40, .Topsoil, 2})
	field_world_set_sample(&world, {0, 1, 0}, {90, .Stone, 1})
	position := sample_to_world_position({0, 0, 0}, 1000) + {100, 100, 100}
	testing.expect_value(t, field_ground_sample_at(&world, 1000, position), Field_Sample{90, .Stone, 1})
	testing.expect_value(t, field_ground_sample_at(&world, 1000, sample_to_world_position({8, 8, 8}, 1000)).material, Field_Material.Air)
}

// A cavity dug under the surface of a loaded chunk shows in the coarser
// level's grid over it, where the generation alone has ground, and the
// streaming forgets the coarser nodes over the edited chunk so they mesh
// again.
@(test)
test_a_coarse_grid_over_an_edited_chunk_shows_the_edit :: proc(t: ^testing.T) {
	planet := make_test_planet()
	generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
	world: Field_World
	defer destroy_field_world(&world)
	coordinate := Field_Chunk_Coordinate{0, 249, 0}
	chunk := new(Field_Chunk)
	generate_field_chunk(TEST_PLANET_SEED, planet, 1000, coordinate, chunk)
	field_world_insert_chunk(&world, chunk)
	column := field_chunk_origin(coordinate) + {16, 0, 16}
	surface := column
	for y := i32(FIELD_CHUNK_SIZE - 1); y >= 0; y -= 1 {
		if field_world_get_sample(&world, column + {0, y, 0}).density > 0 {
			surface = column + {0, y, 0}
			break
		}
	}
	edit := Field_Edit {
		mode     = .Dig,
		brush    = test_brush(.Sphere, 4000, 254),
		centre   = sample_to_world_position(surface - {0, 4, 0}, 1000),
		diggable = {.Topsoil, .Stone, .Deep_Stone},
	}
	result := apply_field_edit(&world, 1000, edit)
	testing.expect(t, result.steps[.Topsoil] + result.steps[.Stone] > 0, "the dig took ground")
	node := Field_Node{1, {0, 124, 0}}
	pure := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, pure)
	edited := gather_coarse_field_grid(&world, node, context.temp_allocator)
	testing.expect(t, edited != nil, "the node reads the loaded chunk")
	generate_field_grid(generation, node, edited)
	dug := 0
	for index in 0 ..< FIELD_GRID_SAMPLE_COUNT {
		if pure.density[index] > 0 && edited.density[index] <= 0 {
			dug += 1
		}
	}
	testing.expect(t, dug > 0, "the cavity shows at the coarser level")
	testing.expect(t, gather_coarse_field_grid(&world, Field_Node{1, {40, 124, 0}}, context.temp_allocator) == nil, "a node over no loaded chunk is generated whole")

	streaming: Field_Streaming
	defer delete(streaming.mesh_revisions)
	defer delete(streaming.remesh)
	streaming.mesh_revisions[node] = 1
	streaming.mesh_revisions[Field_Node{2, {0, 62, 0}}] = 2
	far := Field_Node{1, {40, 124, 0}}
	streaming.mesh_revisions[far] = 3
	mark_edited_coarse_nodes(&streaming, &world)
	testing.expect(t, node in streaming.remesh && Field_Node{2, {0, 62, 0}} in streaming.remesh, "the nodes over the edit mesh again")
	testing.expect(t, far not_in streaming.remesh, "a node elsewhere keeps its mesh")
	testing.expect_value(t, len(world.edited_chunks), 0)
}

// Unedited loaded chunks give the coarser grid the generation's densities
// within one step, so the loaded chunks do not show as a seam.
@(test)
test_an_unedited_loaded_coarse_grid_matches_the_generation :: proc(t: ^testing.T) {
	planet := make_test_planet()
	generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
	world: Field_World
	defer destroy_field_world(&world)
	for z in i32(0) ..= 1 {
		for y in i32(248) ..= 249 {
			for x in i32(0) ..= 1 {
				chunk := new(Field_Chunk)
				generate_field_chunk(TEST_PLANET_SEED, planet, 1000, {x, y, z}, chunk)
				field_world_insert_chunk(&world, chunk)
			}
		}
	}
	node := Field_Node{1, {0, 124, 0}}
	pure := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, pure)
	loaded := gather_coarse_field_grid(&world, node, context.temp_allocator)
	generate_field_grid(generation, node, loaded)
	compared, apart := 0, 0
	for index in 0 ..< FIELD_GRID_SAMPLE_COUNT {
		if !loaded.loaded[index] {
			continue
		}
		compared += 1
		if abs(i32(loaded.density[index]) - i32(pure.density[index])) > 1 {
			apart += 1
		}
	}
	testing.expect_value(t, compared, FIELD_GRID_CELLS * FIELD_GRID_CELLS * FIELD_GRID_CELLS)
	testing.expect_value(t, apart, 0)
	testing.expect(t, !field_grid_is_uniform(loaded), "the node holds the surface")
}

// A material's dig rate scales the brush's rate (0179), its fraction
// carried by the tick: 3 steps at 60 percent take 180 steps over 100
// ticks, never a truncated 100. A place and an edit without rates keep
// the brush's rate.
@(test)
test_the_dig_rate_scales_the_brush_per_material :: proc(t: ^testing.T) {
	total: i32 = 0
	for tick in u64(0) ..< 100 {
		step := scaled_dig_rate(3, 60, 1000 + tick)
		testing.expect(t, step == 1 || step == 2, "a step of 1.8 is 1 or 2")
		total += step
	}
	testing.expect_value(t, total, 180)
	testing.expect_value(t, scaled_dig_rate(3, 0, 7), 3)
	testing.expect_value(t, scaled_dig_rate(6, 150, 0) + scaled_dig_rate(6, 150, 1), 18)
	centre := sample_to_world_position({0, 0, 0}, 1000)
	dig := Field_Edit {
		mode     = .Dig,
		brush    = test_brush(.Sphere, 100, 10),
		centre   = centre,
		diggable = ~bit_set[Field_Material]{},
	}
	dig.dig_rate_percent[.Topsoil], dig.dig_rate_percent[.Deep_Stone] = 150, 60
	Dig_Case :: struct {
		material: Field_Material,
		expected: i8,
	}
	for dig_case in ([?]Dig_Case{{.Topsoil, MAXIMUM_DENSITY - 15}, {.Stone, MAXIMUM_DENSITY - 10}, {.Deep_Stone, MAXIMUM_DENSITY - 6}}) {
		world := make_uniform_test_field({MAXIMUM_DENSITY, dig_case.material, 0})
		apply_field_edit(&world, 1000, dig)
		density := field_world_get_sample(&world, {0, 0, 0}).density
		testing.expectf(t, density == dig_case.expected, "%v digs to %d, not %d", dig_case.material, dig_case.expected, density)
		destroy_field_world(&world)
	}
	place := dig
	place.mode, place.material, place.budget = .Place, .Deep_Stone, 1000
	world := make_uniform_test_field({-MAXIMUM_DENSITY, .Air, 0})
	defer destroy_field_world(&world)
	apply_field_edit(&world, 1000, place)
	testing.expect_value(t, field_world_get_sample(&world, {0, 0, 0}).density, -MAXIMUM_DENSITY + 10)
}
