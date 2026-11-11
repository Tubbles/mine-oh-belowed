package game

import "core:fmt"
import "core:strings"
import "core:testing"

// The diagnostics pages (work item 0086): the F3 cycle, the header, the
// Render and World lines from fixed facts, and the frame time average.

@(test)
test_diagnostics_pages_cycle_back_to_off :: proc(t: ^testing.T) {
	testing.expect_value(t, next_diagnostics_page(.Off), Diagnostics_Page.Input)
	testing.expect_value(t, next_diagnostics_page(.Input), Diagnostics_Page.Render)
	testing.expect_value(t, next_diagnostics_page(.Render), Diagnostics_Page.World)
	testing.expect_value(t, next_diagnostics_page(.World), Diagnostics_Page.Off)
}

@(test)
test_diagnostics_header_numbers_the_pages_without_off :: proc(t: ^testing.T) {
	testing.expect_value(t, diagnostics_header_text(.Input), fmt.tprintf("Diagnostics 1/3 %s (F3 next)", text("diagnostics_page_input")))
	testing.expect_value(t, diagnostics_header_text(.Render), fmt.tprintf("Diagnostics 2/3 %s (F3 next)", text("diagnostics_page_render")))
	testing.expect_value(t, diagnostics_header_text(.World), fmt.tprintf("Diagnostics 3/3 %s (F3 next)", text("diagnostics_page_world")))
}

@(test)
test_frame_time_average_covers_the_last_second :: proc(t: ^testing.T) {
	ring: Frame_Time_Ring
	testing.expect_value(t, average_frame_milliseconds(ring), 0)
	// Two slow frames, then a second and more of 10 ms frames: the slow
	// ones fall out of the average.
	ring = push_frame_time(ring, 0.5)
	ring = push_frame_time(ring, 0.5)
	for _ in 0 ..< 120 {
		ring = push_frame_time(ring, 0.01)
	}
	testing.expect(t, abs(average_frame_milliseconds(ring) - 10) < 0.01)
	short: Frame_Time_Ring
	short = push_frame_time(short, 0.02)
	short = push_frame_time(short, 0.04)
	testing.expect(t, abs(average_frame_milliseconds(short) - 30) < 0.01)
}

@(test)
test_frame_time_ring_wraps :: proc(t: ^testing.T) {
	ring: Frame_Time_Ring
	for _ in 0 ..< FRAME_TIME_RING_SIZE + 10 {
		ring = push_frame_time(ring, 0.001)
	}
	testing.expect_value(t, ring.count, FRAME_TIME_RING_SIZE)
	testing.expect_value(t, ring.next, 10)
	testing.expect(t, abs(average_frame_milliseconds(ring) - 1) < 0.01)
}

line_texts :: proc(lines: []Diagnostics_Line) -> []string {
	texts := make([]string, len(lines), context.temp_allocator)
	for line, index in lines {
		texts[index] = line.text
	}
	return texts
}

contains_line :: proc(lines: []Diagnostics_Line, wanted: string) -> bool {
	for line in lines {
		if line.text == wanted {
			return true
		}
	}
	return false
}

@(test)
test_render_page_lines_from_facts :: proc(t: ^testing.T) {
	facts := Render_Facts {
		build_stamp = "0.1 abc1234",
		window_mode = .Borderless,
		monitor_size = {1694, 1129},
		window_size = {1694, 1129},
		render_size = {1694, 1129},
		window_scale = {1, 1},
		platform = .XWayland,
		vsync = true,
		frame_rate_cap = 0,
		frames_per_second = 60,
		frame_milliseconds = 16.67,
		tick_count = 1,
		accumulated_seconds = 0.004,
		fog_start = 48,
		fog_end = 80,
		weather = Weather{kind = .Rain, intensity = 0.5},
		day_fraction = 0.25,
		loaded_chunk_count = 400,
		drawn_chunk_count = 120,
		vertex_count = 300000,
		uploaded_mesh_count = 2,
		pending_job_count = 5,
		drawn_water_mesh_count = 7,
		live_particle_count = 30,
		weather_particle_count = 900,
		flame_count = 3,
		block_atlas_size = {256, 256},
		item_atlas_size = {512, 256},
		ui_atlas_size = {128, 128},
	}
	lines := render_page_lines(facts)
	expected := [?]string {
		"build 0.1 abc1234",
		"mode Borderless  monitor 1694 x 1129  window 1694 x 1129",
		"render 1694 x 1129  scale 1.00 x 1.00  session xwayland",
		fmt.tprintf("vsync yes  frame rate cap %s", text("settings_frame_rate_cap_off")),
		"fps 60  frame 16.67 ms (last second)",
		"ticks this frame 1  accumulator 4.00 ms",
		"fog 48.0 to 80.0  under water no",
		"weather rain 0.50  day 0.250",
		"chunks loaded 400  drawn 120  vertices 300000",
		"meshes uploaded 2  pending jobs 5",
		"water meshes drawn 7  flames 3  particles 30  weather particles 900",
		"atlas block 256 x 256  item 512 x 256  ui 128 x 128",
	}
	for wanted in expected {
		testing.expectf(t, contains_line(lines, wanted), "missing %q in %v", wanted, line_texts(lines))
	}
}

// The profile's lines at their widest (0342): every statistic at 99.99
// ms, the counters at 9999999, GPU frames. With the header the page fits
// 28 lines (1280 by 720, the start window, at 20 px) of 94 characters
// (1280 by 800, the audits' smallest window, at 22 px).
@(test)
test_the_render_page_fits_with_the_profile :: proc(t: ^testing.T) {
	widest := Section_Statistics{99.99, 99.99, 99.99, 99.99}
	report := Profile_Report{frames = FRAME_PROFILE_RECENT_FRAMES, gpu_frames = FRAME_PROFILE_RECENT_FRAMES, work = widest, wall = widest, gpu = widest, tick_mean = 99.99, tick_worst = 99.99}
	for section in Frame_Section {
		report.cpu[section], report.gpu_sections[section] = widest, widest
		report.draws_mean[section] = 99.9
	}
	for &milliseconds in report.tick_sections {
		milliseconds = 99.99
	}
	for &count in report.counters_mean {
		count = 9999999
	}
	facts := Render_Facts {
		build_stamp = "abc1234+dirty 2026-11-11T03:00Z",
		window_mode = .Borderless,
		monitor_size = {3840, 2160},
		window_size = {3840, 2160},
		render_size = {3840, 2160},
		window_scale = {1, 1},
		platform = .XWayland,
		frames_per_second = 999,
		frame_milliseconds = 99.99,
		tick_count = 9,
		accumulated_seconds = 0.016,
		weather = Weather{kind = .Overcast, intensity = 1},
		field_session = true,
		loaded_chunk_count = 9999999,
		drawn_chunk_count = 9999999,
		vertex_count = 9999999,
		uploaded_mesh_count = 9999999,
		pending_job_count = 9999999,
		drawn_water_mesh_count = 9999999,
		live_particle_count = 9999999,
		weather_particle_count = 9999999,
		flame_count = 9999999,
		block_atlas_size = {4096, 4096},
		item_atlas_size = {4096, 4096},
		ui_atlas_size = {4096, 4096},
		profile = report,
		profile_gpu = .Ready,
	}
	lines := render_page_lines(facts)
	testing.expectf(t, len(lines) + 1 <= 28, "%d lines and the header", len(lines))
	testing.expect(t, contains_line(lines, "field nodes meshed 9999999  drawn 9999999  vertices 9999999"))
	for line in lines {
		testing.expectf(t, len(line.text) <= 94, "%d characters: %q", len(line.text), line.text)
	}
	testing.expect(t, contains_line(lines, "profile 64 frames  work 99.99 ms  gpu 99.99 ms  present 99.99 ms  draws 2398"))
	testing.expect(t, contains_line(lines, "requests 99.99  prepare 99.99/99.99  sky 99.99/99.99  shadow terrain 99.99/99.99"))
}

@(test)
test_world_page_lines_from_facts :: proc(t: ^testing.T) {
	overlay := [?]Diagnostics_Line{{text = "chunks 4  drawn 2  vertices 10"}}
	counts: [Entity_Kind]int
	counts[.Chest] = 2
	counts[.Belt] = 9
	facts := World_Facts {
		overlay_lines = overlay[:],
		tick = 1234,
		player_chunk = {1, -1, 2},
		biome_name = "Meadow",
		entity_counts = counts,
		loose_item_count = 3,
		belt_line_count = 4,
		belt_item_count = 11,
		leaf_decay_count = 6,
	}
	lines := world_page_lines(facts)
	testing.expect_value(t, lines[0].text, "chunks 4  drawn 2  vertices 10")
	expected := [?]string {
		"tick 1234  chunk 1 -1 2  biome Meadow",
		"Chest 2  Furnace 0  Capsule 0  Belt 9",
		"Inserter 0  Drill 0  Splitter 0  Pipe 0",
		"Fluid_Machine 0  Pole 0  Lamp 0  Assembler 0",
		"Lab 0  Schematic_Crate 0  Core_Sample_Drill 0  Launch_Pad 0",
		"loose items 3  belt lines 4  items on belts 11",
		"leaf decay queued 6",
	}
	for wanted in expected {
		testing.expectf(t, contains_line(lines, wanted), "missing %q in %v", wanted, line_texts(lines))
	}
}

// Work item 0198: in a field session the World page says whether the
// feet are in the pod's sealed room; a block world says nothing of it.
@(test)
test_the_world_page_tells_the_sealed_room :: proc(t: ^testing.T) {
	inside := World_Facts{field_session = true, sealed_room_inside = true}
	testing.expect(t, contains_line(world_page_lines(inside), "sealed room: inside the pod"))
	outside := World_Facts{field_session = true}
	testing.expect(t, contains_line(world_page_lines(outside), "sealed room: outside"))
	for line in world_page_lines(World_Facts{}) {
		testing.expect(t, !strings.has_prefix(line.text, "sealed room"), line.text)
	}
	// 0262: the chunk and the biome are the block world's, so a field
	// session's page names neither.
	for line in world_page_lines(World_Facts{field_session = true, biome_name = "Lake"}) {
		testing.expect(t, !strings.contains(line.text, "biome"), line.text)
	}
}

// Work item 0292: in a field session the World page counts the water's
// awake chunks and the pressure pull's teleports, visits and failures.
@(test)
test_the_world_page_counts_the_water_pressure :: proc(t: ^testing.T) {
	facts := World_Facts{field_session = true, water_awake_chunk_count = 1, water_teleports = 3, water_visits = 400, water_failures = 2}
	testing.expect(t, contains_line(world_page_lines(facts), "water awake chunks 1  teleports 3  visits 400  failed 2"))
	for line in world_page_lines(World_Facts{}) {
		testing.expect(t, !strings.has_prefix(line.text, "water awake"), line.text)
	}
}

// Work item 0293: under the bodies model the World page counts the
// bodies, the front, the flood's visits and the sea's inflow.
@(test)
test_the_world_page_counts_the_water_bodies :: proc(t: ^testing.T) {
	facts := World_Facts{field_session = true, water_bodies = true, water_body_count = 2, water_front_count = 17, water_flood_visits = 1856, water_to_sea = 9}
	testing.expect(t, contains_line(world_page_lines(facts), "water bodies 2  front 17  flood visits 1856  to sea 9"))
	for line in world_page_lines(World_Facts{field_session = true}) {
		testing.expect(t, !strings.has_prefix(line.text, "water bodies"), line.text)
	}
}

@(test)
test_belt_items_count_every_lane :: proc(t: ^testing.T) {
	network: Belt_Network
	line: Belt_Line
	append(&line.lanes[.Left], Lane_Item{}, Lane_Item{})
	append(&line.lanes[.Right], Lane_Item{})
	append(&network.lines, line)
	defer {
		delete(line.lanes[.Left])
		delete(line.lanes[.Right])
		delete(network.lines)
	}
	testing.expect_value(t, belt_item_count(network), 3)
}

@(test)
test_diagnostics_lines_print_the_context :: proc(t: ^testing.T) {
	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	diagnostics := Diagnostics_Context {
		simulation        = &simulation,
		technologies      = content.technologies,
		blocks            = content.blocks,
		items             = content.items,
		quests            = content.quests,
		pending_job_count = 7,
		seed              = 42,
		drawn_chunk_count = 3,
		vertex_count      = 9,
	}
	overlay := world_overlay_statistics_lines(diagnostics)
	testing.expect(t, strings.has_prefix(overlay[0].text, "chunks 0  drawn 3  vertices 9"), overlay[0].text)
	testing.expect(t, strings.has_prefix(overlay[1].text, "pending jobs 7"), overlay[1].text)
	testing.expect(t, strings.has_suffix(overlay[1].text, "seed 42"), overlay[1].text)
	mapped := mapped_lines(diagnostics, test_game_config())
	testing.expect(t, strings.has_prefix(mapped[1].text, "tick 0"), mapped[1].text)
}

// In a field session the player lines give the feet's latitude,
// longitude and height and the sample under them (0187).
@(test) // slow
test_diagnostics_lines_print_the_field_feet :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	tick_field_test_simulation(state, simulation_content, {})
	diagnostics := Diagnostics_Context {
		simulation   = state,
		technologies = simulation_content.technologies,
		blocks       = simulation_content.blocks,
		items        = simulation_content.items,
		quests       = simulation_content.quests,
	}
	lines := world_overlay_statistics_lines(diagnostics)
	feet, under := "", ""
	for line in lines {
		if strings.has_prefix(line.text, "feet latitude") {
			feet = line.text
		}
		if strings.has_prefix(line.text, "under the feet sample") {
			under = line.text
		}
		testing.expect(t, !strings.has_prefix(line.text, "player "), line.text)
	}
	testing.expect(t, strings.contains(feet, " m"), feet)
	testing.expect(t, under != "", "the sample line shows")
	testing.expect(t, !strings.contains(under, "air"), under)
}
