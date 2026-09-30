package game

import "core:fmt"
import "core:math"

// The prospecting parts of the HUD and the panels (work item 0038): the
// core sample drill's panel with its report, the magnetometer's needle
// and strength, and the Use_Item hint of each usable item.

CORE_SAMPLE_AREA_WIDTH :: 620
// State, progress, the bands, the deep vein and its mix.
CORE_SAMPLE_ROWS :: 2 + CORE_SAMPLE_BAND_COUNT + 2
MAGNETOMETER_DIAL_SIZE :: 120.0
MAGNETOMETER_NEEDLE_DOTS :: 8
MAGNETOMETER_DOT_SIZE :: 8.0
MAGNETOMETER_COLOR :: Ui_Color{225, 80, 60, 255}

core_sample_area_size :: proc() -> [2]f32 {
	return {CORE_SAMPLE_AREA_WIDTH, UI_ROW_HEIGHT + f32(CORE_SAMPLE_ROWS) * UI_ROW_HEIGHT}
}

// Report, sampling, or waiting for power.
core_sample_state_text :: proc(world: ^World, drill: Core_Sample_Drill) -> string {
	switch {
	case core_sample_of(world, drill) != nil:
		return text("core_sample_reported")
	case !power_is_on(drill.power):
		return text("power_no_network")
	}
	return text("core_sample_sampling")
}

core_sample_fraction :: proc(drill: Core_Sample_Drill, machine: Machine, tick_rate: int) -> f32 {
	total := core_sample_ticks(machine, tick_rate)
	if drill.sample >= 0 || total == 0 {
		return 1
	}
	return f32(drill.work_ticks) / f32(total)
}

// "16 to 32: Stone"
core_sample_band_line :: proc(blocks: Block_Registry, sample: Core_Sample, band: int) -> string {
	top := band * CORE_SAMPLE_BAND_DEPTH
	if i32(band) >= sample.band_count {
		return fmt.tprintf("%d %s %d: %s", top, text("core_sample_to"), top + CORE_SAMPLE_BAND_DEPTH, text("core_sample_unknown"))
	}
	return fmt.tprintf("%d %s %d: %s", top, text("core_sample_to"), top + CORE_SAMPLE_BAND_DEPTH, block_display_name(blocks, sample.bands[band]))
}

// The outputs of a vein type with their percents: "Hematite 90%  Gravel 10%".
vein_mix_text :: proc(veins: Vein_Content, items: Item_Registry, type: int) -> string {
	if type < 0 || type >= len(veins.types) {
		return ""
	}
	vein_type := veins.types[type]
	line := ""
	for output, index in vein_type.outputs[:vein_type.output_count] {
		separator := index == 0 ? "" : "  "
		line = fmt.tprintf("%s%s%s %d%%", line, separator, item_name(items, output), vein_type.percents[index])
	}
	return line
}

core_sample_vein_lines :: proc(sample: Core_Sample, veins: Vein_Content, items: Item_Registry) -> (vein_line, mix_line: string) {
	if !sample.vein_found || sample.vein_type >= len(veins.types) {
		return text("core_sample_no_deep_vein"), ""
	}
	name := text(veins.types[sample.vein_type].name_key)
	return fmt.tprintf("%s  %d %s", name, sample.vein_depth, text("core_sample_blocks_down")), vein_mix_text(veins, items, sample.vein_type)
}

core_sample_panel_region :: proc(state: ^Ui_State, area: Ui_Rectangle, drill: Core_Sample_Drill, screen_context: Screen_Context) {
	content := area
	world := screen_context.world
	machine := screen_context.machines.machines[drill.machine]
	detail_line(state, &content, core_sample_state_text(world, drill), UI_DIM_TEXT_COLOR)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), core_sample_fraction(drill, machine, screen_context.tick_rate))
	sample := core_sample_of(world, drill)
	if sample == nil {
		return
	}
	for band in 0 ..< CORE_SAMPLE_BAND_COUNT {
		detail_line(state, &content, core_sample_band_line(screen_context.blocks, sample^, band))
	}
	vein_line, mix_line := core_sample_vein_lines(sample^, screen_context.veins, screen_context.items)
	detail_line(state, &content, vein_line, UI_ACCENT_COLOR)
	detail_line(state, &content, mix_line)
}

// The magnetometer.

// The needle's angle on screen in radians, clockwise from straight up:
// the direction to the vein relative to where the player looks. Yaw 0
// looks along +x and positive yaw turns towards +z (player.odin).
magnetometer_needle_angle :: proc(reading: Magnetometer_Reading, yaw_degrees: f32) -> f32 {
	world_angle := math.atan2(f32(reading.offset.y), f32(reading.offset.x))
	return world_angle - yaw_degrees * math.RAD_PER_DEG
}

// A dial right of the crosshair: the needle as a row of dots from its
// centre, the strength under it.
draw_magnetometer :: proc(state: ^Ui_State, player: Player) {
	reading := player.magnetometer
	centre := state.screen_units / 2 + {state.screen_units.y * 0.3, 0}
	dial := Ui_Rectangle{centre.x - MAGNETOMETER_DIAL_SIZE / 2, centre.y - MAGNETOMETER_DIAL_SIZE / 2, MAGNETOMETER_DIAL_SIZE, MAGNETOMETER_DIAL_SIZE}
	draw_fill(state, dial, HUD_SLOT_COLOR)
	draw_outline(state, dial, UI_PANEL_BORDER_COLOR)
	if reading.found {
		angle := magnetometer_needle_angle(reading, player.yaw)
		direction := [2]f32{math.sin(angle), -math.cos(angle)}
		for dot in 1 ..= MAGNETOMETER_NEEDLE_DOTS {
			point := centre + direction * (f32(dot) / MAGNETOMETER_NEEDLE_DOTS) * (MAGNETOMETER_DIAL_SIZE / 2 - MAGNETOMETER_DOT_SIZE)
			draw_fill(state, {point.x - MAGNETOMETER_DOT_SIZE / 2, point.y - MAGNETOMETER_DOT_SIZE / 2, MAGNETOMETER_DOT_SIZE, MAGNETOMETER_DOT_SIZE}, MAGNETOMETER_COLOR)
		}
	}
	strength := fmt.tprintf("%s %d%%", text("magnetometer_strength"), int(reading.strength) * 100 / MAGNETOMETER_FULL)
	draw_text(state, {dial.x - MAGNETOMETER_DIAL_SIZE, dial.y + dial.height + UI_GAP, 3 * MAGNETOMETER_DIAL_SIZE, UI_ROW_HEIGHT}, strength, UI_BODY_TEXT_SIZE, .Centre)
}

// The glyph bar label of Use_Item for a usable item.
@(rodata)
item_use_hint_keys := [Item_Use]string {
	.Read         = "hint_read_schematic",
	.Assay        = "hint_assay",
	.Magnetometer = "hint_record_reading",
	.Seismic_Shot = "hint_fire_charge",
}

// The rumble the SDL3 backend plays this frame (on Android the vibrator):
// the magnetometer's strength while the world is shown, nothing otherwise.
haptic_request_for :: proc(player: Player, world_shown: bool) -> Haptic_Request {
	if !world_shown || !player.magnetometer.found {
		return {}
	}
	return {strength = f32(player.magnetometer.strength) / MAGNETOMETER_FULL}
}
