package game

import "core:container/queue"
import "core:fmt"
import "core:strings"
import rl "shared:raylib"
import "shared:raylib/rlgl"

DIAGNOSTICS_MARGIN :: 16
DIAGNOSTICS_TEXT_COLOR :: rl.Color{230, 230, 230, 255}
DIAGNOSTICS_ACTIVE_COLOR :: rl.Color{120, 230, 120, 255}
DIAGNOSTICS_BACKDROP_COLOR :: rl.Color{24, 24, 32, 220}

Diagnostics_Line :: struct {
	text:   string,
	active: bool,
}

// F3 steps through the pages and back to Off (work item 0086). Every page
// draws diagnostics_header_text first, then its columns.
Diagnostics_Page :: enum u8 {
	Off,
	Input,
	Render,
	World,
}

@(rodata)
diagnostics_page_keys := [Diagnostics_Page]string {
	.Off    = "diagnostics_page_off",
	.Input  = "diagnostics_page_input",
	.Render = "diagnostics_page_render",
	.World  = "diagnostics_page_world",
}

// The frame times of the Render page's average, newest at next - 1.
FRAME_TIME_RING_SIZE :: 256

Frame_Time_Ring :: struct {
	seconds: [FRAME_TIME_RING_SIZE]f32,
	next:    int,
	count:   int,
}

// What the Render page shows, filled by the frame loop (render_facts in
// loop.odin), so the lines need no raylib.
Render_Facts :: struct {
	build_stamp:            string,
	window_mode:            Window_Mode,
	monitor_size:           [2]int,
	window_size:            [2]int,
	render_size:            [2]int,
	window_scale:           [2]f32,
	platform:               Window_Platform,
	vsync:                  bool,
	// 0 is no cap.
	frame_rate_cap:         int,
	frames_per_second:      int,
	frame_milliseconds:     f32,
	tick_count:             int,
	accumulated_seconds:    f64,
	fog_start:              f32,
	fog_end:                f32,
	weather:                Weather,
	day_fraction:           f64,
	loaded_chunk_count:     int,
	drawn_chunk_count:      int,
	vertex_count:           int,
	// Mesh results taken from the workers this frame, stale ones included.
	uploaded_mesh_count:    int,
	pending_job_count:      int,
	drawn_water_mesh_count: int,
	live_particle_count:    int,
	weather_particle_count: int,
	flame_count:            int,
	block_atlas_size:       [2]int,
	item_atlas_size:        [2]int,
	ui_atlas_size:          [2]int,
	underwater:             bool,
}

// What the World page shows besides the F4 overlay's lines, filled by the
// frame loop (world_facts in loop.odin).
World_Facts :: struct {
	overlay_lines:    []Diagnostics_Line,
	tick:             u64,
	player_chunk:     Chunk_Coordinate,
	biome_name:       string,
	entity_counts:    [Entity_Kind]int,
	loose_item_count: int,
	belt_line_count:  int,
	belt_item_count:  int,
	leaf_decay_count: int,
}

// The entity kinds per line on the World page.
WORLD_PAGE_KINDS_PER_LINE :: 4

next_diagnostics_page :: proc(page: Diagnostics_Page) -> Diagnostics_Page {
	return Diagnostics_Page((int(page) + 1) % len(Diagnostics_Page))
}

// "Diagnostics 2/3 Render (F3 next)"; the pages count without Off.
diagnostics_header_text :: proc(page: Diagnostics_Page) -> string {
	return fmt.tprintf("Diagnostics %d/%d %s (F3 next)", int(page), len(Diagnostics_Page) - 1, text(diagnostics_page_keys[page]))
}

push_frame_time :: proc(ring: Frame_Time_Ring, seconds: f32) -> Frame_Time_Ring {
	result := ring
	result.seconds[result.next] = seconds
	result.next = (result.next + 1) % FRAME_TIME_RING_SIZE
	result.count = min(result.count + 1, FRAME_TIME_RING_SIZE)
	return result
}

// The mean of the newest frames up to the one that completes a second, in
// milliseconds; 0 without frames. Above FRAME_TIME_RING_SIZE frames per
// second the ring covers less than a second.
average_frame_milliseconds :: proc(ring: Frame_Time_Ring) -> f32 {
	total: f32
	frames := 0
	for frames < ring.count && total < 1 {
		index := (ring.next - 1 - frames + FRAME_TIME_RING_SIZE) % FRAME_TIME_RING_SIZE
		total += ring.seconds[index]
		frames += 1
	}
	if frames == 0 {
		return 0
	}
	return total / f32(frames) * 1000
}

render_page_lines :: proc(facts: Render_Facts) -> []Diagnostics_Line {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	append_line(&lines, false, "build %s", facts.build_stamp)
	append_line(&lines, false, "mode %v  monitor %d x %d  window %d x %d", facts.window_mode, facts.monitor_size.x, facts.monitor_size.y, facts.window_size.x, facts.window_size.y)
	append_line(&lines, false, "render %d x %d  scale %.2f x %.2f  session %s", facts.render_size.x, facts.render_size.y, facts.window_scale.x, facts.window_scale.y, window_platform_name(facts.platform))
	append_line(&lines, false, "vsync %s  frame rate cap %s", yes_no(facts.vsync), frame_rate_cap_text(facts.frame_rate_cap))
	append_line(&lines, false, "fps %d  frame %.2f ms (last second)", facts.frames_per_second, facts.frame_milliseconds)
	append_line(&lines, false, "ticks this frame %d  accumulator %.2f ms", facts.tick_count, facts.accumulated_seconds * 1000)
	append_line(&lines, false, "")
	append_line(&lines, facts.underwater, "fog %.1f to %.1f  under water %s", facts.fog_start, facts.fog_end, yes_no(facts.underwater))
	append_line(&lines, false, "weather %s %.2f  day %.3f", weather_kind_words[facts.weather.kind], facts.weather.intensity, facts.day_fraction)
	append_line(&lines, false, "")
	append_line(&lines, false, "chunks loaded %d  drawn %d  vertices %d", facts.loaded_chunk_count, facts.drawn_chunk_count, facts.vertex_count)
	append_line(&lines, facts.uploaded_mesh_count > 0, "meshes uploaded %d  pending jobs %d", facts.uploaded_mesh_count, facts.pending_job_count)
	append_line(&lines, false, "water meshes drawn %d  flames %d", facts.drawn_water_mesh_count, facts.flame_count)
	append_line(&lines, false, "particles %d  weather particles %d", facts.live_particle_count, facts.weather_particle_count)
	append_line(&lines, false, "")
	append_line(&lines, false, "atlas block %d x %d  item %d x %d  ui %d x %d", facts.block_atlas_size.x, facts.block_atlas_size.y, facts.item_atlas_size.x, facts.item_atlas_size.y, facts.ui_atlas_size.x, facts.ui_atlas_size.y)
	return lines[:]
}

world_page_lines :: proc(facts: World_Facts) -> []Diagnostics_Line {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	append(&lines, ..facts.overlay_lines)
	append_line(&lines, false, "")
	chunk := facts.player_chunk
	append_line(&lines, false, "tick %d  chunk %d %d %d  biome %s", facts.tick, chunk.x, chunk.y, chunk.z, facts.biome_name)
	append_entity_count_lines(&lines, facts.entity_counts)
	append_line(&lines, false, "loose items %d  belt lines %d  items on belts %d", facts.loose_item_count, facts.belt_line_count, facts.belt_item_count)
	append_line(&lines, facts.leaf_decay_count > 0, "leaf decay queued %d", facts.leaf_decay_count)
	return lines[:]
}

// WORLD_PAGE_KINDS_PER_LINE kinds per line, without None.
append_entity_count_lines :: proc(lines: ^[dynamic]Diagnostics_Line, counts: [Entity_Kind]int) {
	parts := make([dynamic]string, context.temp_allocator)
	for count, kind in counts {
		if kind == .None {
			continue
		}
		append(&parts, fmt.tprintf("%v %d", kind, count))
		if len(parts) == WORLD_PAGE_KINDS_PER_LINE {
			append_line(lines, false, "%s", strings.join(parts[:], "  ", context.temp_allocator))
			clear(&parts)
		}
	}
	if len(parts) > 0 {
		append_line(lines, false, "%s", strings.join(parts[:], "  ", context.temp_allocator))
	}
}

pool_alive_count :: proc(pool: Entity_Pool($T)) -> int {
	return len(pool.entries) - len(pool.free)
}

entity_counts :: proc(entities: ^Entities) -> [Entity_Kind]int {
	return [Entity_Kind]int {
		.None = 0,
		.Chest = pool_alive_count(entities.chests),
		.Furnace = pool_alive_count(entities.furnaces),
		.Capsule = pool_alive_count(entities.capsules),
		.Belt = pool_alive_count(entities.belts),
		.Inserter = pool_alive_count(entities.inserters),
		.Drill = pool_alive_count(entities.drills),
		.Splitter = pool_alive_count(entities.splitters),
		.Pipe = pool_alive_count(entities.pipes),
		.Fluid_Machine = pool_alive_count(entities.fluid_machines),
		.Pole = pool_alive_count(entities.poles),
		.Lamp = pool_alive_count(entities.lamps),
		.Assembler = pool_alive_count(entities.assemblers),
		.Lab = pool_alive_count(entities.labs),
		.Schematic_Crate = pool_alive_count(entities.schematic_crates),
		.Core_Sample_Drill = pool_alive_count(entities.core_sample_drills),
		.Launch_Pad = pool_alive_count(entities.launch_pads),
	}
}

belt_item_count :: proc(network: Belt_Network) -> int {
	count := 0
	for line in network.lines {
		for lane in line.lanes {
			count += len(lane)
		}
	}
	return count
}

flame_count :: proc(renderer: Chunk_Renderer) -> int {
	count := 0
	for _, chunk_render in renderer.chunk_meshes {
		count += len(chunk_render.flames)
	}
	return count
}

// The water meshes the water pass draws, by its frustum test
// (draw_water_chunks). Must run between BeginMode3D and EndMode3D.
water_meshes_in_view :: proc(renderer: Chunk_Renderer, camera: rl.Camera3D) -> int {
	view_projection := rlgl.GetMatrixProjection() * rl.GetCameraMatrix(camera)
	frustum := frustum_from_matrix(cast(matrix[4, 4]f32)view_projection)
	count := 0
	for coordinate, chunk_render in renderer.chunk_meshes {
		if len(chunk_render.water_meshes) > 0 && chunk_in_frustum(frustum, coordinate) {
			count += len(chunk_render.water_meshes)
		}
	}
	return count
}

texture_size :: proc(texture: rl.Texture2D) -> [2]int {
	return {int(texture.width), int(texture.height)}
}

enum_label :: proc(value: $T) -> string {
	return fmt.tprint(value)
}

// 20 pixels at 720 lines, 30 at 1080, so the text stays readable from the couch.
diagnostics_font_size :: proc(screen_height: i32) -> i32 {
	return max(20, screen_height / 36)
}

append_line :: proc(lines: ^[dynamic]Diagnostics_Line, active: bool, format: string, arguments: ..any) {
	append(lines, Diagnostics_Line{text = fmt.tprintf(format, ..arguments), active = active})
}

mapped_lines :: proc(state: Frame_State, config: Game_Config) -> []Diagnostics_Line {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	input := state.input
	append_line(&lines, false, "%s  controller diagnostics", config.name)
	append_line(&lines, false, "tick %d  fps %d  alpha %.2f", state.session.simulation.tick, rl.GetFPS(), interpolation_alpha(state.session.accumulator))
	append_line(&lines, false, "backend %v", input.raw.backend)
	append_line(&lines, false, "%s", world_statistics_text(state))
	append_line(&lines, false, "%s", streaming_statistics_text(state))
	append_line(&lines, false, "%s", light_statistics_text(state))
	append_player_lines(&lines, state)
	append_line(&lines, false, "")
	append_line(&lines, input.move != {}, "move        % .3f % .3f", input.move.x, input.move.y)
	append_line(&lines, input.look != {}, "look        % .3f % .3f", input.look.x, input.look.y)
	append_line(&lines, input.look_delta != {}, "look delta  % .1f % .1f", input.look_delta.x, input.look_delta.y)
	append_line(&lines, false, "")
	for action in Action {
		append_line(&lines, action in input.pressed, "%-16v %s", action, action_state_label(action, input))
	}
	return lines[:]
}

action_state_label :: proc(action: Action, input: Input_Frame) -> string {
	if action in input.just_pressed {
		return "just pressed"
	}
	if action in input.pressed {
		return "down"
	}
	return "-"
}

gamepad_axis_label :: proc(backend: Input_Backend, index: int) -> string {
	switch backend {
	case .Raylib:
		return raylib_gamepad_axis_label(index)
	case .Sdl3:
		return sdl3_gamepad_axis_label(index)
	}
	return ""
}

gamepad_button_label :: proc(backend: Input_Backend, index: int) -> string {
	switch backend {
	case .Raylib:
		return raylib_gamepad_button_label(index)
	case .Sdl3:
		return sdl3_gamepad_button_label(index)
	}
	return ""
}

// Keyboard and mouse always come from raylib, which owns the window.
mouse_button_label :: proc(index: int) -> string {
	return raylib_mouse_button_label(index)
}

key_label :: proc(code: i32) -> string {
	return raylib_key_label(code)
}

gamepad_button_lines :: proc(raw: Raw_Input) -> []Diagnostics_Line {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	gamepad := raw.gamepad
	if !gamepad.connected {
		append_line(&lines, false, "gamepad: none connected")
		return lines[:]
	}
	append_line(&lines, false, "gamepad %d: %s", gamepad.index, gamepad.name)
	for index in 0 ..< gamepad.button_count {
		down := gamepad.button_down[index]
		append_line(&lines, down, "%-16s %s", gamepad_button_label(raw.backend, index), down ? "down" : "-")
	}
	return lines[:]
}

yes_no :: proc(value: bool) -> string {
	return value ? "yes" : "no"
}

append_touchpad_lines :: proc(lines: ^[dynamic]Diagnostics_Line, touchpad_index: int, touchpad: Raw_Touchpad) {
	for finger_index in 0 ..< touchpad.finger_count {
		finger := touchpad.fingers[finger_index]
		append_line(lines, finger.down, "touchpad %d finger %d %s", touchpad_index, finger_index, finger.down ? "down" : "up")
		append_line(lines, finger.down, "  x %.3f y %.3f p %.2f", finger.position.x, finger.position.y, finger.pressure)
	}
}

append_sensor_lines :: proc(lines: ^[dynamic]Diagnostics_Line, label: string, sensor: Raw_Sensor) {
	append_line(lines, false, "%s has %s on %s %.0f Hz", label, yes_no(sensor.available), yes_no(sensor.enabled), sensor.data_rate)
	append_line(lines, sensor.values != {}, "  % .2f % .2f % .2f", sensor.values.x, sensor.values.y, sensor.values.z)
}

append_touch_sense_lines :: proc(lines: ^[dynamic]Diagnostics_Line, touch_sense: Raw_Touch_Sense) {
	append_line(lines, false, "touch sense %s", touch_sense.available ? "available" : "not reported")
	append_line(lines, touch_sense.left_stick_touched, "left stick touched   %s", yes_no(touch_sense.left_stick_touched))
	append_line(lines, touch_sense.right_stick_touched, "right stick touched  %s", yes_no(touch_sense.right_stick_touched))
	append_line(lines, touch_sense.left_grip_touched, "left grip touched    %s", yes_no(touch_sense.left_grip_touched))
	append_line(lines, touch_sense.right_grip_touched, "right grip touched   %s", yes_no(touch_sense.right_grip_touched))
}

gamepad_analog_lines :: proc(raw: Raw_Input) -> []Diagnostics_Line {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	gamepad := raw.gamepad
	if !gamepad.connected {
		return lines[:]
	}
	for index in 0 ..< gamepad.axis_count {
		value := gamepad.axis_values[index]
		append_line(&lines, value != 0, "%-16s % .3f", gamepad_axis_label(raw.backend, index), value)
	}
	append_line(&lines, false, "touchpads %d", gamepad.touchpad_count)
	for index in 0 ..< gamepad.touchpad_count {
		append_touchpad_lines(&lines, index, gamepad.touchpads[index])
	}
	append_sensor_lines(&lines, "gyro rad/s", gamepad.motion.gyro)
	gyro := gamepad.motion.gyro
	append_line(&lines, gyro.settled, "  bias % .2f % .2f % .2f %s  corrected % .2f % .2f % .2f", gyro.bias.x, gyro.bias.y, gyro.bias.z, gyro.settled ? "settled" : "learning", gyro.corrected.x, gyro.corrected.y, gyro.corrected.z)
	append_line(&lines, gamepad.motion.gyro_source == .Steam, "  view gyro from %s", gamepad.motion.gyro_source == .Steam ? "Steam's layout (mouse)" : "SDL")
	append_sensor_lines(&lines, "accel m/s2", gamepad.motion.accelerometer)
	append_touch_sense_lines(&lines, gamepad.touch_sense)
	return lines[:]
}

keyboard_mouse_lines :: proc(raw: Raw_Input) -> []Diagnostics_Line {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	mouse := raw.mouse
	append_line(&lines, false, "mouse position % .0f % .0f", mouse.position.x, mouse.position.y)
	append_line(&lines, mouse.delta != {}, "mouse delta    % .1f % .1f", mouse.delta.x, mouse.delta.y)
	append_line(&lines, mouse.wheel != {}, "mouse wheel    % .1f % .1f", mouse.wheel.x, mouse.wheel.y)
	for index in 0 ..< mouse.button_count {
		if mouse.button_down[index] {
			append_line(&lines, true, "mouse %s down", mouse_button_label(index))
		}
	}
	append_line(&lines, raw.keyboard.key_count > 0, "keys down: %s", keys_down_text(raw))
	return lines[:]
}

keys_down_text :: proc(raw: Raw_Input) -> string {
	keyboard := raw.keyboard
	labels := make([]string, keyboard.key_count, context.temp_allocator)
	for index in 0 ..< keyboard.key_count {
		labels[index] = key_label(keyboard.keys_down[index])
	}
	text := strings.join(labels, " ", context.temp_allocator)
	if keyboard.keys_truncated {
		return fmt.tprintf("%s ...", text)
	}
	return text
}

// In the monospace family (ui_font.odin).
draw_lines :: proc(fonts: ^Font_Cache, lines: []Diagnostics_Line, x, y, font_size: i32) -> i32 {
	line_y := y
	for line in lines {
		color := line.active ? DIAGNOSTICS_ACTIVE_COLOR : DIAGNOSTICS_TEXT_COLOR
		draw_monospace_text(fonts, line.text, x, line_y, font_size, color)
		line_y += font_size + font_size / 5
	}
	return line_y
}

// The Input page's columns, from top down.
draw_diagnostics :: proc(state: Frame_State, config: Game_Config, top: i32) {
	font_size := diagnostics_font_size(rl.GetRenderHeight())
	screen_width := rl.GetRenderWidth()
	button_column_x := screen_width * 35 / 100
	analog_column_x := screen_width * 64 / 100
	fonts := state.ui.fonts
	left_bottom := draw_lines(fonts, mapped_lines(state, config), DIAGNOSTICS_MARGIN, top, font_size)
	draw_lines(fonts, keyboard_mouse_lines(state.input.raw), DIAGNOSTICS_MARGIN, left_bottom + font_size, font_size)
	draw_lines(fonts, gamepad_button_lines(state.input.raw), button_column_x, top, font_size)
	draw_lines(fonts, gamepad_analog_lines(state.input.raw), analog_column_x, top, font_size)
}

// Over the backdrop: the header line, then the page. render and world are
// read only on their pages.
draw_diagnostics_page :: proc(state: Frame_State, config: Game_Config, render: Render_Facts, world: World_Facts) {
	draw_diagnostics_backdrop()
	font_size := diagnostics_font_size(rl.GetRenderHeight())
	header := [?]Diagnostics_Line{{text = diagnostics_header_text(state.diagnostics_page), active = true}}
	top := draw_lines(state.ui.fonts, header[:], DIAGNOSTICS_MARGIN, DIAGNOSTICS_MARGIN, font_size)
	switch state.diagnostics_page {
	case .Off:
	case .Input:
		draw_diagnostics(state, config, top)
	case .Render:
		draw_lines(state.ui.fonts, render_page_lines(render), DIAGNOSTICS_MARGIN, top, font_size)
	case .World:
		draw_lines(state.ui.fonts, world_page_lines(world), DIAGNOSTICS_MARGIN, top, font_size)
	}
}

world_statistics_text :: proc(state: Frame_State) -> string {
	return fmt.tprintf(
		"chunks %d  drawn %d  vertices %d",
		len(state.session.simulation.world.chunks),
		state.renderer.drawn_chunk_count,
		state.renderer.vertex_count,
	)
}

// Light of the cell in front of the targeted face: the targeted block
// itself is usually opaque and holds no light.
light_statistics_text :: proc(state: Frame_State) -> string {
	simulation := state.session.simulation
	world := simulation.world
	player := simulation.players[0]
	light := player.target.hit ? world_get_light(&world, player.target.adjacent) : 0
	return fmt.tprintf(
		"light sky %d block %d %d %d  day %.2f  queued light %d chunks %d water %d",
		light_level(light, .Sky),
		light_level(light, .Red),
		light_level(light, .Green),
		light_level(light, .Blue),
		day_factor(daylight_blend(simulation_day_ticks(simulation), simulation.day_length_ticks)),
		pending_light_nodes(world.lighting),
		queue.len(world.lighting.arrived_chunks),
		queue.len(world.water.updates),
	)
}

streaming_statistics_text :: proc(state: Frame_State) -> string {
	return fmt.tprintf("pending jobs %d  veins %d  seed %d", state.session.streaming.pending_jobs, len(state.session.simulation.world.veins), state.session.generator.seed)
}

// Keeps the diagnostics readable over the bright sky.
draw_diagnostics_backdrop :: proc() {
	rl.DrawRectangle(0, 0, rl.GetRenderWidth(), rl.GetRenderHeight(), DIAGNOSTICS_BACKDROP_COLOR)
}

// The F4 overlay's world, streaming, light and player lines, which the
// World page shows too.
world_overlay_statistics_lines :: proc(state: Frame_State) -> []Diagnostics_Line {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	append_line(&lines, false, "%s", world_statistics_text(state))
	append_line(&lines, false, "%s", streaming_statistics_text(state))
	append_line(&lines, false, "%s", light_statistics_text(state))
	append_player_lines(&lines, state)
	return lines[:]
}

// Shown while the diagnostics pages are off and the overlay is on (F4 or
// the Developer screen).
draw_world_overlay :: proc(state: Frame_State) {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	append_line(&lines, false, "fps %d  tick %d", rl.GetFPS(), state.session.simulation.tick)
	append(&lines, ..world_overlay_statistics_lines(state))
	append_line(&lines, state.settings.bottleneck_overlay, "bottleneck overlay %s", yes_no(state.settings.bottleneck_overlay))
	append_line(&lines, false, "F3 diagnostics  F4 statistics  F5 remove block  F6 fly  V camera  O bottlenecks")
	font_size := diagnostics_font_size(rl.GetRenderHeight())
	backdrop_height := i32(len(lines)) * (font_size + font_size / 5) + DIAGNOSTICS_MARGIN
	rl.DrawRectangle(0, 0, font_size * 24, backdrop_height + DIAGNOSTICS_MARGIN, DIAGNOSTICS_BACKDROP_COLOR)
	draw_lines(state.ui.fonts, lines[:], DIAGNOSTICS_MARGIN, DIAGNOSTICS_MARGIN, font_size)
}

block_name :: proc(registry: Block_Registry, block: Block_Id) -> string {
	if int(block) >= len(registry.definitions) {
		return "?"
	}
	return registry.definitions[block].id
}

target_text :: proc(registry: Block_Registry, world: ^World, target: Raycast_Hit) -> string {
	if !target.hit {
		return "target none"
	}
	block := target.block
	if target.entity != NO_ENTITY {
		return fmt.tprintf("target entity %v %d gen %d at %d %d %d face %v", target.entity.kind, target.entity.index, target.entity.generation, block.x, block.y, block.z, target.face)
	}
	return fmt.tprintf("target %s at %d %d %d face %v", block_name(registry, world_get_block(world, block)), block.x, block.y, block.z, target.face)
}

item_id_text :: proc(items: Item_Registry, item: Item_Id) -> string {
	if int(item) >= len(items.items) {
		return "?"
	}
	return items.items[item].id
}

stack_text :: proc(items: Item_Registry, stack: Item_Stack) -> string {
	if stack_is_empty(stack) {
		return "empty"
	}
	return fmt.tprintf("%s %d", item_id_text(items, stack.item), stack.count)
}

occupied_slot_count :: proc(inventory: Inventory) -> int {
	count := 0
	for slot in inventory.slots {
		count += stack_is_empty(slot) ? 0 : 1
	}
	return count
}

append_player_lines :: proc(lines: ^[dynamic]Diagnostics_Line, state: Frame_State) {
	player, registry, world := state.session.simulation.players[0], state.content.blocks, state.session.simulation.world
	position, velocity := player.position, player.velocity
	append_line(lines, false, "player % .2f % .2f % .2f  velocity % .2f % .2f % .2f", position.x, position.y, position.z, velocity.x, velocity.y, velocity.z)
	cheat_speed := state.session.simulation.cheat_speed
	append_line(lines, cheat_speed, "on ground %s  camera %v  flying %s  no clip %s  sprinting %s%s", yes_no(player.on_ground), player.camera_mode, yes_no(player.flying), yes_no(player.no_clip), yes_no(player.sprinting), cheat_speed ? "  cheat speed" : "")
	append_line(lines, player.mining.active, "%s  mining %.0f%%", target_text(registry, &world, player.target), mining_fraction(player.mining) * 100)
	items := state.content.items
	append_line(
		lines,
		false,
		"hotbar slot %d %s  places %s  held %s  slots used %d of %d",
		player.selected_hotbar_slot,
		stack_text(items, selected_hotbar_stack(player)),
		block_name(registry, selected_placed_block(player, items)),
		stack_text(items, player.held.stack),
		occupied_slot_count(player.inventory),
		len(player.inventory.slots),
	)
	unlocks := state.session.simulation.unlocks
	append_line(
		lines,
		player.crafting.count > 0,
		"recipes available %d of %d  items discovered %d  craft queue %d runs %d crafts%s%s",
		available_recipe_count(unlocks),
		len(unlocks.available),
		obtained_item_count(unlocks),
		player.crafting.count,
		queued_craft_count(player.crafting),
		player.crafting.waiting ? " waiting" : "",
		craft_queue_waits_for_input(player.crafting) ? " waiting for input" : "",
	)
	append_line(lines, false, "%s", research_diagnostics_text(state))
	append_line(lines, false, "%s", quest_diagnostics_text(state))
	append_line(lines, false, "%s", objective_counters_text(state))
}

research_diagnostics_text :: proc(state: Frame_State) -> string {
	research := state.session.simulation.world.research
	labs := len(state.session.simulation.world.entities.labs.entries) - len(state.session.simulation.world.entities.labs.free)
	if !research.queued {
		return fmt.tprintf("research none queued  labs %d", labs)
	}
	technology := state.session.technologies.technologies[research.technology]
	return fmt.tprintf("research %s %d of %d units  labs %d", technology.id, research.units_done, queued_research_cost(research, state.session.technologies), labs)
}

quest_diagnostics_text :: proc(state: Frame_State) -> string {
	quests := state.session.simulation.quests
	if quests.active == NO_QUEST {
		return fmt.tprintf("quest none active  hints fired %d  rewards waiting %d", quests.hints_fired, len(quests.pending_rewards))
	}
	return fmt.tprintf(
		"quest %s (%d of %d)  hints fired %d  rewards waiting %d",
		state.content.quests.quests[quests.active].id,
		quests.active + 1,
		len(state.content.quests.quests),
		quests.hints_fired,
		len(quests.pending_rewards),
	)
}

// The counters of the active quest's first item objective.
objective_counters_text :: proc(state: Frame_State) -> string {
	quests := state.session.simulation.quests
	statistics := state.session.simulation.world.statistics
	if quests.active == NO_QUEST {
		return fmt.tprintf("walked %d mm  world actions %d", statistics.distance_walked_millimetres, statistics.world_actions)
	}
	for objective in state.content.quests.quests[quests.active].objectives {
		if objective.item != NO_ITEM {
			item := objective.item
			return fmt.tprintf(
				"%s produced %d obtained %d delivered %d rate %d/min",
				item_id_text(state.content.items, item),
				item_counter(statistics.produced, item),
				item_counter(statistics.obtained, item),
				item_counter(statistics.delivered, item),
				production_rate_per_minute(statistics, item),
			)
		}
	}
	return fmt.tprintf("walked %d mm  blocks mined %d  world actions %d", statistics.distance_walked_millimetres, statistics.blocks_mined, statistics.world_actions)
}
