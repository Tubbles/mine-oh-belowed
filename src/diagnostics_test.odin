package game

import "core:fmt"
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
		wayland_display_set = true,
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
		"water meshes drawn 7  flames 3",
		"particles 30  weather particles 900",
		"atlas block 256 x 256  item 512 x 256  ui 128 x 128",
	}
	for wanted in expected {
		testing.expectf(t, contains_line(lines, wanted), "missing %q in %v", wanted, line_texts(lines))
	}
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
