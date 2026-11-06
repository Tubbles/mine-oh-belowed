package game

import "core:strings"
import "core:testing"

@(test)
test_shipped_game_config_parses_and_validates :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, config.name, "Mine oh Belowed")
	testing.expect_value(t, config.tick_rate, 60)
	testing.expect_value(t, config.day_length_seconds, 1200)
	testing.expect_value(t, validate_game_config(config), "")
	testing.expect_value(t, validate_starting_items(config.starting_items, make_test_items()), "")
	// The tech demo's kit (0291), validated like the starter kit.
	testing.expect_value(t, validate_starting_items(config.tech_demo_items, make_test_items(), "tech demo item"), "")
	testing.expect_value(t, len(config.tech_demo_items), 6)
}

@(test)
test_game_config_rejects_bad_values :: proc(t: ^testing.T) {
	testing.expect(t, validate_game_config(Game_Config{name = "x", tick_rate = 60, day_length_seconds = 0}) != "")
	unknown := [?]Starting_Item{{item = "no_such_item", count = 1}}
	testing.expect(t, validate_starting_items(unknown[:], make_test_items()) != "")
	testing.expect(t, strings.has_prefix(validate_starting_items(unknown[:], make_test_items(), "tech demo item"), "tech demo item"))
	empty := [?]Starting_Item{{item = "torch", count = 0}}
	testing.expect(t, validate_starting_items(empty[:], make_test_items()) != "")
}

@(test)
test_the_field_view_distances_rise_within_the_limit :: proc(t: ^testing.T) {
	config, _ := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, config.field_view.level_distances_metres, [FIELD_LEVEL_COUNT]int{64, 160, 384, 1024})
	testing.expect_value(t, field_view_problem({{64, 160, 384, 1024}}), "")
	testing.expect(t, field_view_problem({}) != "", "a missing field_view is refused")
	testing.expect(t, field_view_problem({{64, 64, 384, 1024}}) != "")
	testing.expect(t, field_view_problem({{64, 160, 384, MAXIMUM_FIELD_VIEW_DISTANCE_METRES + 1}}) != "")
	// The gaps are the diagonals of a 32, 64 and 128 m node, rounded up.
	testing.expect_value(t, [3]int{field_level_gap_metres(1), field_level_gap_metres(2), field_level_gap_metres(3)}, [3]int{56, 111, 222})
	testing.expect_value(t, field_view_problem({{64, 120, 231, 453}}), "")
	refused := [?][FIELD_LEVEL_COUNT]int{{64, 119, 384, 1024}, {64, 160, 270, 1024}, {64, 160, 384, 605}}
	for distances in refused {
		testing.expectf(t, field_view_problem({distances}) != "", "%v lets a node border one two levels coarser", distances)
	}
}

// The Android asset copy (work item 0114): the list build.sh writes and
// the stamp that skips the copy on a later start of the same build.
@(test)
test_android_asset_paths_skip_blank_lines :: proc(t: ^testing.T) {
	paths := android_asset_paths("data/game.sjson\n\ndata/strings/en.sjson\r\n  \n")
	testing.expect_value(t, len(paths), 2)
	testing.expect_value(t, paths[0], "data/game.sjson")
	testing.expect_value(t, paths[1], "data/strings/en.sjson")
	testing.expect_value(t, len(android_asset_paths("")), 0)
}

@(test)
test_android_assets_current_compares_the_build_stamp :: proc(t: ^testing.T) {
	testing.expect(t, android_assets_current("abc1234 2026-09-29T12:00Z", "abc1234 2026-09-29T12:00Z"))
	testing.expect(t, android_assets_current("abc1234 2026-09-29T12:00Z\n", "abc1234 2026-09-29T12:00Z"))
	testing.expect(t, !android_assets_current("abc1234 2026-09-29T12:00Z", "def5678 2026-09-29T13:00Z"))
	testing.expect(t, !android_assets_current("", "abc1234 2026-09-29T12:00Z"))
}

// The arrival's values (0200, 0269): the shipped ones pass; a start too
// far from the crater, a start at the atmosphere's top, a hit that
// glows, an atmosphere hazing the ground's sky, real seconds longer than
// the curve and a fall too short for its hit fail naming their key; no
// fall passes.
@(test)
test_arrival_values_are_bounded :: proc(t: ^testing.T) {
	config, _ := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, arrival_problem(config), "")
	far := config
	far.arrival_start_metres = 2000
	testing.expect(t, strings.contains(arrival_problem(far), "starts"), "a start 2000 m up names the start's distance")
	low := config
	low.arrival_start_metres = config.atmosphere.top_metres
	testing.expect(t, strings.contains(arrival_problem(low), "atmosphere.top_metres"), "a start at the top names the top")
	glowing := config
	glowing.arrival_heat_threshold_percent = 0
	testing.expect(t, strings.contains(arrival_problem(glowing), "heat at the hit"), "threshold 0 glows at the hit")
	thick := config
	thick.atmosphere.scale_height_metres = 400
	testing.expect(t, strings.contains(arrival_problem(thick), "two scale heights"), "a scale height of 400 m hazes the ground's sky")
	long := config
	long.arrival_real_seconds = 59
	testing.expect(t, strings.contains(arrival_problem(long), "natural seconds"), "real seconds longer than the curve")
	brief := config
	brief.arrival_ticks = 360
	testing.expect(t, strings.contains(arrival_problem(brief), "descent"), "real seconds longer than a 300 tick descent")
	short := config
	short.arrival_ticks = 60
	testing.expect(t, strings.contains(arrival_problem(short), "arrival_ticks"), "60 ticks cannot hold the hit")
	none := config
	none.arrival_ticks = 0
	testing.expect_value(t, arrival_problem(none), "")
	tipped := config
	tipped.arrival_rest_tilt_degrees = MAXIMUM_ARRIVAL_REST_TILT_DEGREES + 1
	testing.expect(t, strings.contains(arrival_problem(tipped), "arrival_rest_tilt_degrees"), "a lean of 26 degrees is named")
	tipped.arrival_rest_tilt_degrees = 0
	testing.expect_value(t, arrival_problem(tipped), "")
	tipped.arrival_rest_tilt_degrees = MAXIMUM_ARRIVAL_REST_TILT_DEGREES
	testing.expect_value(t, arrival_problem(tipped), "")
	// Work items 0272 and 0304: the debris' keys and the wake's opacity one
	// past each bound are named.
	debris := [?]struct {
		change: proc(config: ^Game_Config),
		key:    string,
	} {
		{proc(config: ^Game_Config) {config.arrival_debris_pieces = MAXIMUM_ARRIVAL_DEBRIS_PIECES + 1}, "arrival_debris_pieces"},
		{proc(config: ^Game_Config) {config.arrival_debris_rest_seconds = MAXIMUM_ARRIVAL_DEBRIS_REST_SECONDS + 1}, "arrival_debris_rest_seconds"},
		{proc(config: ^Game_Config) {config.arrival_debris_angle_degrees = MINIMUM_ARRIVAL_DEBRIS_ANGLE_DEGREES - 1}, "arrival_debris_angle_degrees"},
		{proc(config: ^Game_Config) {config.arrival_debris_angle_degrees = MAXIMUM_ARRIVAL_DEBRIS_ANGLE_DEGREES + 1}, "arrival_debris_angle_degrees"},
		{proc(config: ^Game_Config) {config.arrival_flakes_per_second = MAXIMUM_ARRIVAL_FLAKES_PER_SECOND + 1}, "arrival_flakes_per_second"},
		{proc(config: ^Game_Config) {config.arrival_plasma.wake_opacity_percent = MINIMUM_ARRIVAL_WAKE_OPACITY_PERCENT - 1}, "arrival_plasma.wake_opacity_percent"},
		{proc(config: ^Game_Config) {config.arrival_plasma.wake_opacity_percent = MAXIMUM_ARRIVAL_WAKE_OPACITY_PERCENT + 1}, "arrival_plasma.wake_opacity_percent"},
	}
	for entry in debris {
		changed := config
		entry.change(&changed)
		testing.expectf(t, strings.contains(arrival_problem(changed), entry.key), "%s past its bound is named", entry.key)
	}
	// Work item 0273: the plasma's colours and soot.
	bright := config
	bright.arrival_plasma.haze_color[1] = 256
	testing.expect(t, strings.contains(arrival_problem(bright), "arrival_plasma.haze_color"), "a channel of 256 is named")
	black := config
	black.arrival_plasma.ablator_color = {0, 0, 0}
	testing.expect(t, strings.contains(arrival_problem(black), "is black"), "a black colour is named")
	// Work item 0305: the core colour, bounded and never black as the
	// others.
	hot := config
	hot.arrival_plasma.core_color[2] = 256
	testing.expect(t, strings.contains(arrival_problem(hot), "arrival_plasma.core_color"), "a core channel of 256 is named")
	unlit := config
	unlit.arrival_plasma.core_color = {0, 0, 0}
	testing.expect(t, strings.contains(arrival_problem(unlit), "arrival_plasma.core_color is black"), "a black core colour is named")
	sooty := config
	sooty.arrival_plasma.soot_percent = MAXIMUM_ARRIVAL_SOOT_PERCENT + 1
	testing.expect(t, strings.contains(arrival_problem(sooty), "arrival_plasma.soot_percent"), "soot of 61 percent is named")
	sooty.arrival_plasma.soot_percent = 0
	testing.expect_value(t, arrival_problem(sooty), "")
}

// The direct placement limit (0215): the shipped one loads, each side
// outside 1 to 16 is named.
@(test)
test_direct_placement_limit_is_range_checked :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, config.direct_placement_limit, Placement_Limit_Config{width = 2, depth = 2, height = 3})
	testing.expect_value(t, direct_placement_limit_problem(config.direct_placement_limit), "")
	narrow := config.direct_placement_limit
	narrow.width = 0
	testing.expect(t, strings.has_prefix(direct_placement_limit_problem(narrow), "direct_placement_limit.width "))
	tall := config.direct_placement_limit
	tall.height = MAXIMUM_DIRECT_PLACEMENT_LIMIT_CELLS + 1
	testing.expect(t, strings.has_prefix(direct_placement_limit_problem(tall), "direct_placement_limit.height "))
	config.direct_placement_limit = tall
	testing.expect(t, strings.has_prefix(validate_game_config(config), "direct_placement_limit.height "))
}

// The pod's airlock (0222, 0231): the shipped reach loads, a reach
// outside its bound is named.
@(test)
test_the_pod_airlock_config_is_bounded :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, config.pod_airlock, Pod_Airlock_Config{reach_millimetres = 150})
	testing.expect_value(t, pod_airlock_problem(config.pod_airlock), "")
	cases := [?]struct {
		airlock: Pod_Airlock_Config,
		key:     string,
	} {
		{{40}, "pod_airlock.reach_millimetres "},
		{{301}, "pod_airlock.reach_millimetres "},
	}
	for entry in cases {
		problem := pod_airlock_problem(entry.airlock)
		testing.expectf(t, strings.has_prefix(problem, entry.key), "%v: %q", entry.airlock, problem)
	}
}

// Work item 0292: the pressure keys of field_water are bounded and a
// value outside its bound is named.
@(test)
test_field_water_pressure_values_are_bounded :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	water := config.field_water
	testing.expect_value(t, water.pressure, true)
	testing.expect_value(t, water.pressure_visit_budget, 128)
	testing.expect_value(t, water.pressure_visit_budget_per_tick, 20000)
	testing.expect_value(t, water.minimum_head, 4)
	testing.expect_value(t, field_water_problem(water), "")
	cases := [?]struct {
		change: proc(water: ^Field_Water_Config),
		key:    string,
	} {
		{proc(water: ^Field_Water_Config) {water.pressure_visit_budget = 0}, "field_water.pressure_visit_budget "},
		{proc(water: ^Field_Water_Config) {water.pressure_visit_budget = 4097}, "field_water.pressure_visit_budget "},
		{proc(water: ^Field_Water_Config) {water.pressure_visit_budget_per_tick = 0}, "field_water.pressure_visit_budget_per_tick "},
		{proc(water: ^Field_Water_Config) {water.minimum_head = 65}, "field_water.minimum_head "},
	}
	for entry in cases {
		changed := water
		entry.change(&changed)
		problem := field_water_problem(changed)
		testing.expectf(t, strings.has_prefix(problem, entry.key), "%q: %q", entry.key, problem)
	}
}

// Work item 0293: the water bodies' keys of field_water are bounded and
// a value outside its bound is named.
@(test)
test_field_water_body_values_are_bounded :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	water := config.field_water
	testing.expect_value(t, water.weir_rate_per_head, 51)
	testing.expect_value(t, water.weir_cap, 63)
	testing.expect_value(t, water.weir_floor, 15)
	testing.expect_value(t, water.weir_dead_band, 8)
	testing.expect_value(t, water.flood_visit_budget, 4000)
	testing.expect_value(t, water.flood_rise_samples, 64)
	testing.expect_value(t, field_water_problem(water), "")
	cases := [?]struct {
		change: proc(water: ^Field_Water_Config),
		key:    string,
	} {
		{proc(water: ^Field_Water_Config) {water.weir_rate_per_head = 0}, "field_water.weir_rate_per_head "},
		{proc(water: ^Field_Water_Config) {water.weir_rate_per_head = 4065}, "field_water.weir_rate_per_head "},
		{proc(water: ^Field_Water_Config) {water.weir_cap = 255}, "field_water.weir_cap "},
		{proc(water: ^Field_Water_Config) {water.weir_floor = 0}, "field_water.weir_floor "},
		{proc(water: ^Field_Water_Config) {water.weir_dead_band = 255}, "field_water.weir_dead_band "},
		{proc(water: ^Field_Water_Config) {water.flood_visit_budget = 0}, "field_water.flood_visit_budget "},
		{proc(water: ^Field_Water_Config) {water.flood_rise_samples = 257}, "field_water.flood_rise_samples "},
	}
	for entry in cases {
		changed := water
		entry.change(&changed)
		problem := field_water_problem(changed)
		testing.expectf(t, strings.has_prefix(problem, entry.key), "%q: %q", entry.key, problem)
	}
}

// Work item 0295: the demo's bucket keys of field_water are bounded and a
// value outside its bound is named; the shipped block passes.
@(test)
test_field_water_bucket_values_are_bounded :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	water := config.field_water
	testing.expect_value(t, water.bucket_fill_per_press, 254)
	testing.expect_value(t, water.bucket_repeat_ticks, 6)
	testing.expect_value(t, field_water_problem(water), "")
	cases := [?]struct {
		change: proc(water: ^Field_Water_Config),
		key:    string,
	} {
		{proc(water: ^Field_Water_Config) {water.bucket_fill_per_press = 0}, "field_water.bucket_fill_per_press "},
		{proc(water: ^Field_Water_Config) {water.bucket_fill_per_press = 16257}, "field_water.bucket_fill_per_press "},
		{proc(water: ^Field_Water_Config) {water.bucket_repeat_ticks = 0}, "field_water.bucket_repeat_ticks "},
		{proc(water: ^Field_Water_Config) {water.bucket_repeat_ticks = 256}, "field_water.bucket_repeat_ticks "},
	}
	for entry in cases {
		changed := water
		entry.change(&changed)
		problem := field_water_problem(changed)
		testing.expectf(t, strings.has_prefix(problem, entry.key), "%q: %q", entry.key, problem)
	}
}

// Work item 0228: the state copy first, the edits directory's second,
// none while the overlay is off.
@(test)
test_data_edits_directories_put_the_state_copy_first :: proc(t: ^testing.T) {
	testing.expect_value(t, data_edits_directories("/s", "/r", false, false), [2]string{"/s", "/r"})
	testing.expect_value(t, data_edits_directories("/s", "/r", false, true), [2]string{"/s", ""})
	testing.expect_value(t, data_edits_directories("/s", "/r", true, false), [2]string{"", ""})
	testing.expect_value(t, data_edits_directories("", "/r", false, false), [2]string{"", "/r"})
}

@(test)
test_reachable_data_edits_refusal_cases :: proc(t: ^testing.T) {
	testing.expect_value(t, reachable_data_edits_refusal("", true, true), Reachable_Data_Edits_Refusal.Not_Set)
	testing.expect_value(t, reachable_data_edits_refusal("Download", true, true), Reachable_Data_Edits_Refusal.Not_Absolute)
	testing.expect_value(t, reachable_data_edits_refusal("~/Download", true, true), Reachable_Data_Edits_Refusal.Not_Absolute)
	testing.expect_value(t, reachable_data_edits_refusal("/storage/emulated/0/Download", false, true), Reachable_Data_Edits_Refusal.No_Access)
	testing.expect_value(t, reachable_data_edits_refusal("/storage/emulated/0/Download", true, false), Reachable_Data_Edits_Refusal.Not_A_Directory)
	testing.expect_value(t, reachable_data_edits_refusal("/storage/emulated/0/Download", true, true), Reachable_Data_Edits_Refusal.None)
}

// The sun and the torchlight (0297): the shipped table loads, the cones
// must be ordered, every key is bounded.
@(test)
test_sun_and_torchlight_is_range_checked :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, config.sun_and_torchlight, Sun_And_Torchlight_Config{sky_ambient_percent = 35, sun_strength_percent = 100, torchlight_strength_percent = 100, torchlight_inner_cone_degrees = 28, torchlight_outer_cone_degrees = 36, torchlight_range_metres = 40})
	testing.expect_value(t, sun_and_torchlight_problem(config.sun_and_torchlight), "")
	flat := config.sun_and_torchlight
	flat.torchlight_outer_cone_degrees = 28
	testing.expect(t, strings.has_prefix(sun_and_torchlight_problem(flat), "sun_and_torchlight.torchlight_outer_cone_degrees "))
	short := config.sun_and_torchlight
	short.torchlight_range_metres = 0
	testing.expect(t, strings.has_prefix(sun_and_torchlight_problem(short), "sun_and_torchlight.torchlight_range_metres "))
	bright := config.sun_and_torchlight
	bright.sky_ambient_percent = 101
	testing.expect(t, strings.has_prefix(sun_and_torchlight_problem(bright), "sun_and_torchlight.sky_ambient_percent "))
	config.sun_and_torchlight = bright
	testing.expect(t, strings.has_prefix(validate_game_config(config), "sun_and_torchlight.sky_ambient_percent "))
	testing.expect(t, sun_and_torchlight_problem({}) != "", "a missing table fails")
}

// The water's look (0294): the shipped table passes, and each percent
// past its bound is refused by name.
@(test)
test_water_look_values_are_bounded :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, config.water_look, SHIPPED_WATER_LOOK)
	testing.expect_value(t, water_look_problem(config.water_look), "")
	fast := config.water_look
	fast.wave_speed_percent = 51
	testing.expect(t, strings.has_prefix(water_look_problem(fast), "water_look.wave_speed_percent "))
	endless := config.water_look
	endless.wave_damping_percent = 100
	testing.expect(t, strings.has_prefix(water_look_problem(endless), "water_look.wave_damping_percent "))
	flat := config.water_look
	flat.wave_clamp_percent = 0
	testing.expect(t, strings.has_prefix(water_look_problem(flat), "water_look.wave_clamp_percent "))
	hard := config.water_look
	hard.wave_kick_percent = 101
	testing.expect(t, strings.has_prefix(water_look_problem(hard), "water_look.wave_kick_percent "))
	config.water_look = hard
	testing.expect(t, strings.has_prefix(validate_game_config(config), "water_look.wave_kick_percent "))
	testing.expect(t, water_look_problem({}) != "", "a missing table fails")
}
