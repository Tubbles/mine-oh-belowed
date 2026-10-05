package game

import "core:math/linalg"
import "core:slice"
import "core:testing"

// Work item 0274: the flicker and the embers stay in their range, never
// repeat within ten seconds at any lag, differ between salts, and stand
// at the mean under reduced motion; late in a long session they still
// hold their range.
@(test)
test_the_flame_flicker_has_no_period :: proc(t: ^testing.T) {
	SAMPLES :: 60 * 60
	LONGEST_LAG :: 600
	series: [2][SAMPLES]f32
	for salt in 0 ..< 2 {
		for index in 0 ..< SAMPLES {
			seconds := f64(index) / 60
			flicker := flame_flicker(seconds, u64(salt + 1), false)
			ember := flame_ember_glow(seconds, u64(salt + 1), false)
			testing.expectf(t, flicker >= 0.7 && flicker <= 1, "salt %d at %v s: flicker %v", salt + 1, seconds, flicker)
			testing.expectf(t, ember >= 0.7 && ember <= 1, "salt %d at %v s: ember %v", salt + 1, seconds, ember)
			testing.expect_value(t, flame_flicker(seconds, u64(salt + 1), true), FLAME_FLICKER_MEAN)
			testing.expect_value(t, flame_ember_glow(seconds, u64(salt + 1), true), FLAME_FLICKER_MEAN)
			series[salt][index] = flicker
		}
		testing.expectf(t, slice.max(series[salt][:]) - slice.min(series[salt][:]) > 0.1, "salt %d: the flicker barely moves", salt + 1)
		for lag in 1 ..= LONGEST_LAG {
			largest: f32
			for index in 0 ..< SAMPLES - lag {
				largest = max(largest, abs(series[salt][index] - series[salt][index + lag]))
			}
			testing.expectf(t, largest > 0.02, "salt %d repeats at a lag of %d samples", salt + 1, lag)
		}
	}
	apart: f32
	for index in 0 ..< SAMPLES {
		apart = max(apart, abs(series[0][index] - series[1][index]))
	}
	testing.expectf(t, apart > 0.02, "salts 1 and 2 flicker together")
	late := flame_flicker(36000.5, 1, false)
	testing.expectf(t, late >= 0.7 && late <= 1, "ten hours in: %v", late)
}

@(test)
test_flame_quad_corners_stand_on_their_base :: proc(t: ^testing.T) {
	corners := flame_quad_corners({1, 2, 0}, {0, 0, 1}, {0, 1, 0}, 2, 3)
	testing.expect_value(t, corners, [4][3]f32{{1, 2, -1}, {1, 2, 1}, {1, 5, 1}, {1, 5, -1}})
}

// Work item 0274: an idle furnace has neither flames nor its lamp; a
// burning one its four flames on its coal bed, inside its box, and the
// lamp at the record's colour times the flicker.
@(test)
test_the_furnace_burns_only_while_it_works :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	machine_id := test_machine(content.machines, "stone_furnace")
	machine := content.machines.machines[machine_id]
	handle := add_entity(&world.entities, content.machines, machine_id, {4, 1, 4}, 0)
	frame := Model_Frame{world = &world, tick_rate = TEST_TICK_RATE}
	lights := make([dynamic]Point_Light, context.temp_allocator)
	testing.expect_value(t, len(gather_machine_flames(&world.entities, content.machines, frame)), 0)
	gather_machine_lights(&lights, &world.entities, content.machines, Model_Renderer{}, frame)
	testing.expect_value(t, len(lights), 0)

	furnace := pool_get(&world.entities.furnaces, handle)
	furnace.slots[FURNACE_FUEL_SLOT] = Item_Stack{test_item(content.items, "coal"), 5}
	furnace.slots[FURNACE_INPUT_SLOT] = Item_Stack{test_item(content.items, "hematite"), 10}
	for _ in 0 ..< 10 {
		tick_entities_on_world(&world, &records, content, TEST_TICK_RATE)
	}
	furnace = pool_get(&world.entities.furnaces, handle)
	testing.expect_value(t, furnace.state, Furnace_State.Burning)
	frame.tick = 10
	draws := gather_machine_flames(&world.entities, content.machines, frame)
	testing.expect_value(t, len(draws), 4)
	body := entity_body_matrix(&world.entities, furnace.common)
	size := [3]f32{f32(machine.footprint.x), f32(machine.footprint.y), f32(machine.footprint.z)}
	low, high := transform_point(body, {-size.x / 2, 0, -size.z / 2}), transform_point(body, {size.x / 2, size.y, size.z / 2})
	low, high = linalg.min(low, high), linalg.max(low, high)
	for draw, index in draws {
		base := (draw.corners[0] + draw.corners[1]) / 2
		inside := base.x >= low.x && base.x <= high.x && base.y >= low.y && base.y <= high.y && base.z >= low.z && base.z <= high.z
		testing.expectf(t, inside, "flame %d's base %v is outside the furnace's box %v to %v", index, base, low, high)
	}
	gather_machine_lights(&lights, &world.entities, content.machines, Model_Renderer{}, frame)
	testing.expect_value(t, len(lights), 1)
	flicker := lights[0].color.r / machine.lights[0].color.r
	testing.expectf(t, flicker >= 0.7 && flicker <= 1, "the lamp's flicker %v", flicker)
	testing.expect(t, linalg.length(lights[0].color - machine.lights[0].color * flicker) < 1e-5, "the lamp keeps the record's hue")
	testing.expectf(t, abs(flicker - draws[0].flicker) < 1e-5, "the lamp flickers %v, its flames %v", flicker, draws[0].flicker)
}

// Work item 0274, the review's fix round: a frame's flames are cut to
// MAXIMUM_FLAME_DRAWS nearest the eye first, and a field torch past
// FLAME_DRAW_DISTANCE_METRES is left out.
@(test)
test_the_flame_gather_caps_sorts_and_leaves_far_torches_out :: proc(t: ^testing.T) {
	SPACING :: 500
	torches := make([dynamic]Field_Torch, context.temp_allocator)
	for x in i32(-10) ..< 10 {
		for z in i32(-7) ..< 8 {
			append(&torches, Field_Torch{sample = {x, 4000, z}})
		}
	}
	near_count := len(torches)
	append(&torches, Field_Torch{sample = {400, 4000, 0}})
	eye := [3]f32{0.2, 2001, 0.1}
	draws := make([dynamic]Flame_Draw, context.temp_allocator)
	append_field_torch_flames(&draws, torches[:], SPACING, eye, 10, false)
	testing.expect_value(t, len(draws), near_count)
	testing.expect(t, near_count > MAXIMUM_FLAME_DRAWS, "the test has more near torches than the cap")
	nearest := nearest_flame_draws(draws[:], eye)
	testing.expect_value(t, len(nearest), MAXIMUM_FLAME_DRAWS)
	for index in 1 ..< len(nearest) {
		testing.expectf(t, nearest[index - 1].distance_squared <= nearest[index].distance_squared, "draw %d is nearer than the one before it", index)
	}
	first_base := (nearest[0].corners[0] + nearest[0].corners[1]) / 2
	testing.expectf(t, abs(first_base.x) < 0.01 && abs(first_base.z) < 0.01, "the nearest flame stands on the torch under the eye, not at %v", first_base)
	for draw in nearest {
		testing.expect(t, draw.distance_squared <= FLAME_DRAW_DISTANCE_METRES * FLAME_DRAW_DISTANCE_METRES)
	}
}

// The quad's values survive the vertex colour as flame.vs decodes them.
@(test)
test_flame_vertex_color_carries_the_quad_values :: proc(t: ^testing.T) {
	color := flame_vertex_color(Flame_Draw{seed = 1.25, flicker = 0.85, aspect = 1.6})
	testing.expect_value(t, color, [4]u8{217, 64, 0, 160})
	wide := flame_vertex_color(Flame_Draw{seed = 9.5, flicker = 1, aspect = 120})
	testing.expect_value(t, int(wide.b) * 256 + int(wide.a), 12000)
	testing.expect_value(t, wide.g, 128)
	// Torches whose salts differ by one never share a flow pattern.
	for salt in u64(0) ..< 600 {
		first := flame_vertex_color(Flame_Draw{seed = flame_seed(salt)}).g
		second := flame_vertex_color(Flame_Draw{seed = flame_seed(salt + 1)}).g
		testing.expectf(t, first != second, "salts %d and %d share the seed byte %d", salt, salt + 1, first)
	}
}
