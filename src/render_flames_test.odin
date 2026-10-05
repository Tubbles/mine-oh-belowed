package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:testing"

// Work item 0274, since 0284 the embers only (fire_flicker has its own
// test): the ember glow stays in its range, never repeats at a lag of
// one to ten seconds (a slow pulse barely moves within a second),
// differs between salts, and stands at the mean under reduced motion;
// late in a long session it still holds its range.
@(test)
test_the_ember_glow_has_no_period :: proc(t: ^testing.T) {
	SAMPLES :: 60 * 60
	SHORTEST_LAG :: 60
	LONGEST_LAG :: 600
	series: [2][SAMPLES]f32
	for salt in 0 ..< 2 {
		for index in 0 ..< SAMPLES {
			seconds := f64(index) / 60
			ember := flame_ember_glow(seconds, u64(salt + 1), false)
			testing.expectf(t, ember >= 0.7 && ember <= 1, "salt %d at %v s: ember %v", salt + 1, seconds, ember)
			testing.expect_value(t, flame_ember_glow(seconds, u64(salt + 1), true), FIRE_FLICKER_MEAN)
			series[salt][index] = ember
		}
		testing.expectf(t, slice.max(series[salt][:]) - slice.min(series[salt][:]) > 0.1, "salt %d: the ember glow barely moves", salt + 1)
		for lag in SHORTEST_LAG ..= LONGEST_LAG {
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
	testing.expectf(t, apart > 0.02, "salts 1 and 2 glow together")
	late := flame_ember_glow(36000.5, 1, false)
	testing.expectf(t, late >= 0.7 && late <= 1, "ten hours in: %v", late)
}

@(test)
test_flame_quad_corners_stand_on_their_base :: proc(t: ^testing.T) {
	corners := flame_quad_corners({1, 2, 0}, {0, 0, 1}, {0, 1, 0}, 2, 3)
	testing.expect_value(t, corners, [4][3]f32{{1, 2, -1}, {1, 2, 1}, {1, 5, 1}, {1, 5, -1}})
}

// Work item 0274: an idle furnace has neither flames nor its lamp; a
// burning one its four flames on its coal bed, inside its box, each at
// the fire flicker's bounds, and the lamp at the record's colour times
// the flames' flicker as a point light takes it (0284).
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
		testing.expectf(t, draw.flicker >= FIRE_FLICKER_LOWEST && draw.flicker <= FIRE_FLICKER_HIGHEST, "flame %d's flicker %v", index, draw.flicker)
	}
	gather_machine_lights(&lights, &world.entities, content.machines, Model_Renderer{}, frame)
	testing.expect_value(t, len(lights), 1)
	flicker := lights[0].color.r / machine.lights[0].color.r
	lowest, highest := fire_point_light_flicker(FIRE_FLICKER_LOWEST), fire_point_light_flicker(FIRE_FLICKER_HIGHEST)
	testing.expectf(t, flicker >= lowest - 1e-5 && flicker <= highest + 1e-5, "the lamp's flicker %v", flicker)
	testing.expect(t, linalg.length(lights[0].color - machine.lights[0].color * flicker) < 1e-5, "the lamp keeps the record's hue")
	expected := fire_point_light_flicker(draws[0].flicker)
	testing.expectf(t, abs(flicker - expected) < 1e-5, "the lamp flickers %v, its flames' %v as a light %v", flicker, draws[0].flicker, expected)
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

// The quad's values survive the vertex colour as flame.vs decodes them:
// the flicker over FIRE_FLICKER_HIGHEST (0284), clamped to the byte.
@(test)
test_flame_vertex_color_carries_the_quad_values :: proc(t: ^testing.T) {
	color := flame_vertex_color(Flame_Draw{seed = 1.25, flicker = 0.85, aspect = 1.6})
	testing.expect_value(t, [3]u8{color.g, color.b, color.a}, [3]u8{64, 0, 160})
	decoded := f32(color.r) / 255 * FIRE_FLICKER_HIGHEST
	testing.expectf(t, abs(decoded - 0.85) <= FIRE_FLICKER_HIGHEST / 255, "0.85 decodes as %v", decoded)
	testing.expect_value(t, flame_vertex_color(Flame_Draw{flicker = 1.5}).r, 255)
	testing.expect_value(t, flame_vertex_color(Flame_Draw{flicker = 3}).r, 255)
	testing.expect_value(t, flame_vertex_color(Flame_Draw{flicker = 0}).r, 0)
	testing.expect_value(t, flame_vertex_color(Flame_Draw{flicker = 0.4}).r, 68)
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

// Work item 0284: a field torch within reach gives one light, above its
// box, of the torch colour times its flame's flicker as a point light
// takes it, at the same seconds; a torch past FLAME_DRAW_DISTANCE_METRES
// gives none; under reduced motion the colour holds at the mean.
@(test)
test_a_field_torch_lights_with_its_flames_flicker :: proc(t: ^testing.T) {
	SPACING :: 500
	torch := Field_Torch{sample = {1, 4000, 2}}
	far := Field_Torch{sample = {400, 4000, 0}}
	eye := [3]f32{0.2, 2001, 0.1}
	centre := world_position_to_metres(sample_to_world_position(torch.sample, SPACING))
	up := linalg.normalize(centre)
	for seconds in ([2]f64{10.25, 3600.5}) {
		lights := make([dynamic]Point_Light, context.temp_allocator)
		append_field_torch_lights(&lights, {torch, far}, SPACING, eye, seconds, false)
		testing.expect_value(t, len(lights), 1)
		flame := field_torch_flame_draw(torch, SPACING, eye, seconds, false)
		testing.expect_value(t, lights[0].color, FIELD_TORCH_LIGHT_COLOR * fire_point_light_flicker(flame.flicker))
		testing.expect_value(t, lights[0].radius, FIELD_TORCH_LIGHT_RADIUS_METRES)
		_, clipped := lights[0].clip_box.?
		testing.expect(t, !clipped, "a field torch's light is not clipped")
		height := linalg.dot(lights[0].position - centre, up)
		testing.expectf(t, height > FIELD_TORCH_SIZE_METRES / 2, "the light stands %v m above the box's centre", height)
	}
	calm := field_torch_point_light(torch, SPACING, 10.25, true)
	testing.expect_value(t, calm.color, FIELD_TORCH_LIGHT_COLOR * FIRE_FLICKER_MEAN)
}

// Work item 0284: the field torches share the eight point light slots
// with the window lights, nearest the eye first; the window lights come
// back moved by the pod's transform and the torches' lights unmoved.
@(test)
test_field_torch_lights_share_the_eight_slots_unmoved :: proc(t: ^testing.T) {
	SPACING :: 500
	eye := [3]f32{0.2, 2001, 0.1}
	state: Simulation_State
	state.field.spacing_millimetres = SPACING
	state.field.torches = make([dynamic]Field_Torch, context.temp_allocator)
	for x in i32(-2) ..< 2 {
		for z in i32(-1) ..< 2 {
			append(&state.field.torches, Field_Torch{sample = {x, 4000, z}})
		}
	}
	testing.expect_value(t, len(state.field.torches), 12)
	shift := [3]f32{0, 0, 0.5}
	transform := matrix[4, 4]f32{
		1, 0, 0, shift.x,
		0, 1, 0, shift.y,
		0, 0, 1, shift.z,
		0, 0, 0, 1,
	}
	window_lights := []Point_Light{{position = eye + {0, -0.1, 0} - shift, color = {1, 0.5, 0.2}, radius = 2}, {position = eye + {0.1, 0, 0} - shift, color = {1, 0.5, 0.2}, radius = 2}}
	frame := Model_Frame{tick = 600, tick_rate = 60}
	scene := Field_Scene{state = &state, frame = frame, pod_transform = transform, window_lights = window_lights}
	nearest, count := gather_field_scene_point_lights(scene, eye)
	testing.expect_value(t, count, MAXIMUM_POINT_LIGHTS)
	for index in 1 ..< count {
		testing.expectf(t, linalg.length2(nearest[index - 1].position - eye) <= linalg.length2(nearest[index].position - eye), "light %d is nearer than the one before it", index)
	}
	for window in window_lights {
		moved := window.position + shift
		found := false
		for light in nearest[:count] {
			found ||= linalg.length(light.position - moved) < 1e-4
		}
		testing.expectf(t, found, "the window light at %v is not back moved to %v", window.position, moved)
	}
	torch_lights := 0
	for light in nearest[:count] {
		for torch in state.field.torches {
			expected := field_torch_point_light(torch, SPACING, model_frame_seconds(frame), false)
			if light.position == expected.position {
				torch_lights += 1
				testing.expect_value(t, light.color, expected.color)
			}
		}
	}
	testing.expect_value(t, torch_lights, count - len(window_lights))
}

// Work item 0284: a block torch's light flickers with its flame, within
// the factor's bounds, with no period, and apart from its neighbour's.
@(test)
test_the_block_torch_light_flickers_with_its_flame_and_has_no_period :: proc(t: ^testing.T) {
	TICKS :: 1860
	cells := [2]World_Coordinate{{3, 64, 5}, {4, 64, 5}}
	eye := [3]f32{0, 66, 0}
	lowest, highest := block_torch_light_factor(FIRE_FLICKER_LOWEST), block_torch_light_factor(FIRE_FLICKER_HIGHEST)
	series: [2][]f32
	for cell, index in cells {
		series[index] = make([]f32, TICKS, context.temp_allocator)
		for tick in 0 ..< TICKS {
			seconds := f64(tick) / 60
			flicker := block_torch_flicker(cell, seconds, false)
			testing.expectf(t, flicker == torch_flame_draw(cell, eye, seconds, false).flicker, "cell %v at tick %d flickers apart from its flame", cell, tick)
			factor := block_torch_light_factor(flicker)
			testing.expectf(t, factor >= lowest && factor <= highest, "cell %v at tick %d: factor %v", cell, tick, factor)
			series[index][tick] = factor
		}
	}
	statistics := flicker_statistics(series[0])
	testing.expectf(t, statistics.worst_lag_ratio >= 0.7, "worst lag ratio %v", statistics.worst_lag_ratio)
	apart: f64
	for tick in 0 ..< TICKS {
		apart += f64(abs(series[0][tick] - series[1][tick]))
	}
	apart /= TICKS
	pairs := mean_pair_difference(series[0])
	testing.expectf(t, f32(apart) >= 0.6 * pairs, "the neighbours differ by %v, the first's pairs by %v", apart, pairs)
}

// Work item 0284: the block shaders take the MAXIMUM_BLOCK_TORCH_FLICKERS
// torches nearest the eye, nearest first, each its centre and its light
// factor; unused slots stay zero.
@(test)
test_the_block_torch_flickers_are_capped_nearest_first :: proc(t: ^testing.T) {
	SECONDS :: 12.25
	eye := [3]f32{3.7, 11.2, 2.1}
	cells := make([dynamic]World_Coordinate, context.temp_allocator)
	for x in i32(0) ..< 8 {
		for z in i32(0) ..< 5 {
			append(&cells, World_Coordinate{x, 10, z})
		}
	}
	testing.expect_value(t, len(cells), 40)
	torches, count := block_torch_flicker_uniform(cells[:], eye, SECONDS, false)
	testing.expect_value(t, count, MAXIMUM_BLOCK_TORCH_FLICKERS)
	farthest_listed := linalg.length2(torches[count - 1].xyz - eye)
	for index in 1 ..< count {
		testing.expectf(t, linalg.length2(torches[index - 1].xyz - eye) <= linalg.length2(torches[index].xyz - eye), "slot %d is nearer than the one before it", index)
	}
	for cell in cells {
		centre := block_centre(cell)
		listed := false
		for torch in torches[:count] {
			if torch.xyz == centre {
				listed = true
				testing.expect_value(t, torch.w, block_torch_light_factor(block_torch_flicker(cell, SECONDS, false)))
			}
		}
		if !listed {
			testing.expectf(t, linalg.length2(centre - eye) >= farthest_listed, "cell %v is nearer than a listed one but left out", cell)
		}
	}
	few, few_count := block_torch_flicker_uniform(cells[:3], eye, SECONDS, false)
	testing.expect_value(t, few_count, 3)
	for index in 3 ..< MAXIMUM_BLOCK_TORCH_FLICKERS {
		testing.expect_value(t, few[index], [4]f32{})
	}
}

// The fire flicker's statistics over a series at 60 Hz (0286): its
// range, mean and deviation, the mean change between ticks and the
// shares of the changes above 0.05 and 0.1, the flares a second (onsets
// of a rise above 0.15 over two ticks) and the worst lag ratio (the least
// mean difference at a lag of half a second to half the series, over the
// mean difference of all pairs: near 0 for a series that repeats).
Flicker_Statistics :: struct {
	lowest:              f32,
	highest:             f32,
	mean:                f32,
	deviation:           f32,
	mean_step:           f32,
	step_share_above_5:  f32,
	step_share_above_10: f32,
	flares_per_second:   f32,
	worst_lag_ratio:     f32,
}

// The mean absolute difference of all pairs of the series, from a sorted
// copy.
mean_pair_difference :: proc(series: []f32) -> f32 {
	sorted := slice.clone(series, context.temp_allocator)
	slice.sort(sorted)
	count := len(sorted)
	total: f64
	for value, index in sorted {
		total += f64(value) * f64(2 * index - count + 1)
	}
	return f32(2 * total / (f64(count) * f64(count - 1)))
}

// The mean absolute difference between the series and itself lag ticks
// later.
mean_lag_difference :: proc(series: []f32, lag: int) -> f32 {
	total: f64
	for index in 0 ..< len(series) - lag {
		total += f64(abs(series[index] - series[index + lag]))
	}
	return f32(total / f64(len(series) - lag))
}

flicker_statistics :: proc(series: []f32) -> (statistics: Flicker_Statistics) {
	count := len(series)
	statistics.lowest, statistics.highest = slice.min(series), slice.max(series)
	total, squares: f64
	for value in series {
		total += f64(value)
	}
	mean := total / f64(count)
	for value in series {
		squares += (f64(value) - mean) * (f64(value) - mean)
	}
	statistics.mean, statistics.deviation = f32(mean), f32(math.sqrt(squares / f64(count)))
	steps, above_5, above_10: f64
	for index in 0 ..< count - 1 {
		step := abs(series[index + 1] - series[index])
		steps += f64(step)
		above_5 += step > 0.05 ? 1 : 0
		above_10 += step > 0.1 ? 1 : 0
	}
	statistics.mean_step = f32(steps / f64(count - 1))
	statistics.step_share_above_5, statistics.step_share_above_10 = f32(above_5 / f64(count - 1)), f32(above_10 / f64(count - 1))
	onsets := 0
	rising := false
	for index in 0 ..< count - 2 {
		qualifies := series[index + 2] - series[index] > 0.15
		onsets += qualifies && !rising ? 1 : 0
		rising = qualifies
	}
	statistics.flares_per_second = f32(onsets) / (f32(count) / 60)
	pairs := mean_pair_difference(series)
	statistics.worst_lag_ratio = math.F32_MAX
	for lag in 30 ..= count / 2 {
		statistics.worst_lag_ratio = min(statistics.worst_lag_ratio, mean_lag_difference(series, lag) / pairs)
	}
	return
}

// The fire flicker at 60 Hz over count ticks from 0 s.
fire_flicker_series :: proc(salt: u64, count: int) -> []f32 {
	series := make([]f32, count, context.temp_allocator)
	for &value, tick in series {
		value = fire_flicker(f64(tick) / 60, salt, false)
	}
	return series
}

// Work item 0286: the fire flicker stays in its bounds, dances (it
// reaches far, changes fast between ticks, flares a few times a second),
// repeats at no lag over the entry's length, differs between salts,
// holds its mean under reduced motion and its bounds late in a long
// session.
@(test)
test_the_fire_flicker_dances_without_period :: proc(t: ^testing.T) {
	TICKS :: 1860
	series: [8][]f32
	for index in 0 ..< 8 {
		salt := DEFAULT_WORLD_SEED + 7919 * u64(index)
		series[index] = fire_flicker_series(salt, TICKS)
		for value, tick in series[index] {
			testing.expectf(t, value >= FIRE_FLICKER_LOWEST && value <= FIRE_FLICKER_HIGHEST, "salt %d at tick %d: flicker %v", index, tick, value)
			testing.expectf(t, fire_flicker(f64(tick) / 60, salt, true) == FIRE_FLICKER_MEAN, "salt %d at tick %d: not the mean under reduced motion", index, tick)
		}
		statistics := flicker_statistics(series[index])
		testing.expectf(t, statistics.lowest <= 0.62, "salt %d: lowest %v", index, statistics.lowest)
		testing.expectf(t, statistics.highest >= 1.25, "salt %d: highest %v", index, statistics.highest)
		testing.expectf(t, statistics.deviation >= 0.10, "salt %d: deviation %v", index, statistics.deviation)
		testing.expectf(t, statistics.mean_step >= 0.028, "salt %d: mean step %v", index, statistics.mean_step)
		testing.expectf(t, statistics.step_share_above_5 >= 0.16, "salt %d: share of steps above 0.05 %v", index, statistics.step_share_above_5)
		testing.expectf(t, statistics.step_share_above_10 >= 0.03, "salt %d: share of steps above 0.1 %v", index, statistics.step_share_above_10)
		testing.expectf(t, statistics.flares_per_second >= 0.8 && statistics.flares_per_second <= 3.5, "salt %d: flares a second %v", index, statistics.flares_per_second)
		testing.expectf(t, statistics.worst_lag_ratio >= 0.7, "salt %d: worst lag ratio %v", index, statistics.worst_lag_ratio)
		late := fire_flicker(36000.5, salt, false)
		testing.expectf(t, !math.is_nan(late) && !math.is_inf(late) && late >= FIRE_FLICKER_LOWEST && late <= FIRE_FLICKER_HIGHEST, "salt %d at 36000.5 s: flicker %v", index, late)
	}
	apart: f64
	for tick in 0 ..< TICKS {
		apart += f64(abs(series[0][tick] - series[1][tick]))
	}
	apart /= TICKS
	pairs := mean_pair_difference(series[0])
	testing.expectf(t, f32(apart) >= 0.6 * pairs, "salts 0 and 1 differ by %v, the first's pairs by %v", apart, pairs)
}

// Work item 0286: the statistics catch the 0273 wave, a 1 Hz sine of
// amplitude 0.1 about 0.85: its lag ratio is low and its steps small.
@(test)
test_the_flicker_statistics_catch_a_wave :: proc(t: ^testing.T) {
	series := make([]f32, 1860, context.temp_allocator)
	for &value, tick in series {
		value = 0.85 + 0.1 * math.sin(math.TAU * f32(tick) / 60)
	}
	statistics := flicker_statistics(series)
	testing.expectf(t, statistics.worst_lag_ratio < 0.4, "the wave's worst lag ratio is %v", statistics.worst_lag_ratio)
	testing.expectf(t, statistics.mean_step < 0.012, "the wave's mean step is %v", statistics.mean_step)
}

FIRE_FLICKER_DUMP :: #config(FIRE_FLICKER_DUMP, false)

// Work item 0286, a judging tool: with -define:FIRE_FLICKER_DUMP=true it
// prints the shipped fall's window flickers as CSV lines and one line of
// statistics per window. It writes no file and is a no-op without the
// define.
@(test)
test_print_the_window_flicker_series :: proc(t: ^testing.T) {
	if !FIRE_FLICKER_DUMP {
		return
	}
	ticks := shipped_arrival_config().arrival_ticks
	windows: [5][]f32
	for &series in windows {
		series = make([]f32, ticks, context.temp_allocator)
	}
	fmt.println("tick,window_0,window_1,window_2,window_3,window_4")
	for tick in 0 ..< ticks {
		for &series, window in windows {
			series[tick] = arrival_window_flicker(f32(tick) / 60, window, DEFAULT_WORLD_SEED, false)
		}
		fmt.printfln("%d,%.4f,%.4f,%.4f,%.4f,%.4f", tick, windows[0][tick], windows[1][tick], windows[2][tick], windows[3][tick], windows[4][tick])
	}
	for series, window in windows {
		fmt.printfln("window %d: %v", window, flicker_statistics(series))
	}
}
