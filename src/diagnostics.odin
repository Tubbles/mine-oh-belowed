package game

import "core:container/queue"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

DIAGNOSTICS_MARGIN :: 16
DIAGNOSTICS_TEXT_COLOR :: rl.Color{230, 230, 230, 255}
DIAGNOSTICS_ACTIVE_COLOR :: rl.Color{120, 230, 120, 255}
DIAGNOSTICS_BACKDROP_COLOR :: rl.Color{24, 24, 32, 220}

Diagnostics_Line :: struct {
	text:   string,
	active: bool,
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
	append_line(&lines, false, "tick %d  fps %d  alpha %.2f", state.simulation.tick, rl.GetFPS(), interpolation_alpha(state.accumulator))
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

draw_lines :: proc(lines: []Diagnostics_Line, x, y, font_size: i32) -> i32 {
	line_y := y
	for line in lines {
		color := line.active ? DIAGNOSTICS_ACTIVE_COLOR : DIAGNOSTICS_TEXT_COLOR
		rl.DrawText(strings.clone_to_cstring(line.text, context.temp_allocator), x, line_y, font_size, color)
		line_y += font_size + font_size / 5
	}
	return line_y
}

draw_diagnostics :: proc(state: Frame_State, config: Game_Config) {
	font_size := diagnostics_font_size(rl.GetScreenHeight())
	screen_width := rl.GetScreenWidth()
	button_column_x := screen_width * 35 / 100
	analog_column_x := screen_width * 64 / 100
	left_bottom := draw_lines(mapped_lines(state, config), DIAGNOSTICS_MARGIN, DIAGNOSTICS_MARGIN, font_size)
	draw_lines(keyboard_mouse_lines(state.input.raw), DIAGNOSTICS_MARGIN, left_bottom + font_size, font_size)
	draw_lines(gamepad_button_lines(state.input.raw), button_column_x, DIAGNOSTICS_MARGIN, font_size)
	draw_lines(gamepad_analog_lines(state.input.raw), analog_column_x, DIAGNOSTICS_MARGIN, font_size)
}

world_statistics_text :: proc(state: Frame_State) -> string {
	return fmt.tprintf(
		"chunks %d  drawn %d  vertices %d",
		len(state.simulation.world.chunks),
		state.renderer.drawn_chunk_count,
		state.renderer.vertex_count,
	)
}

// Light of the cell in front of the targeted face: the targeted block
// itself is usually opaque and holds no light.
light_statistics_text :: proc(state: Frame_State) -> string {
	simulation := state.simulation
	world := simulation.world
	player := simulation.players[0]
	light := player.target.hit ? world_get_light(&world, player.target.adjacent) : 0
	return fmt.tprintf(
		"light sky %d block %d  day %.2f  queued light %d chunks %d water %d",
		light_level(light, .Sky),
		light_level(light, .Block),
		day_factor(daylight_blend(simulation.tick, simulation.day_length_ticks)),
		pending_light_nodes(world.lighting),
		queue.len(world.lighting.arrived_chunks),
		queue.len(world.water.updates),
	)
}

streaming_statistics_text :: proc(state: Frame_State) -> string {
	return fmt.tprintf("pending jobs %d  veins %d  seed %d", state.streaming.pending_jobs, len(state.simulation.world.veins), state.generator.seed)
}

// Keeps the diagnostics readable over the bright sky.
draw_diagnostics_backdrop :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), DIAGNOSTICS_BACKDROP_COLOR)
}

// Shown while the diagnostics screen is off.
draw_world_overlay :: proc(state: Frame_State) {
	lines := make([dynamic]Diagnostics_Line, context.temp_allocator)
	append_line(&lines, false, "fps %d  tick %d", rl.GetFPS(), state.simulation.tick)
	append_line(&lines, false, "%s", world_statistics_text(state))
	append_line(&lines, false, "%s", streaming_statistics_text(state))
	append_line(&lines, false, "%s", light_statistics_text(state))
	append_player_lines(&lines, state)
	append_line(&lines, false, "F3 diagnostics  F5 remove block  F6 fly  V camera")
	font_size := diagnostics_font_size(rl.GetScreenHeight())
	backdrop_height := i32(len(lines)) * (font_size + font_size / 5) + DIAGNOSTICS_MARGIN
	rl.DrawRectangle(0, 0, font_size * 24, backdrop_height + DIAGNOSTICS_MARGIN, DIAGNOSTICS_BACKDROP_COLOR)
	draw_lines(lines[:], DIAGNOSTICS_MARGIN, DIAGNOSTICS_MARGIN, font_size)
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
	player, registry, world := state.simulation.players[0], state.registry, state.simulation.world
	position, velocity := player.position, player.velocity
	append_line(lines, false, "player % .2f % .2f % .2f  velocity % .2f % .2f % .2f", position.x, position.y, position.z, velocity.x, velocity.y, velocity.z)
	append_line(lines, false, "on ground %s  camera %v  flying %s", yes_no(player.on_ground), player.camera_mode, yes_no(player.flying))
	append_line(lines, player.mining.active, "%s  mining %.0f%%", target_text(registry, &world, player.target), mining_fraction(player.mining) * 100)
	items := state.items
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
	unlocks := state.simulation.unlocks
	append_line(
		lines,
		player.crafting.count > 0,
		"recipes available %d of %d  items discovered %d  craft queue %d%s",
		available_recipe_count(unlocks),
		len(unlocks.available),
		obtained_item_count(unlocks),
		player.crafting.count,
		player.crafting.waiting ? " waiting" : "",
	)
}
