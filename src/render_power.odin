package game

import rl "shared:raylib"

// Placeholder power models: a junction box or cabinet, and a fluid
// junction (0374), is a box of its record's color a little inset across,
// a power switch a box in green while on and red while off, a lamp a
// small box that glows while lit. A
// switch or lamp with a model (render_models.odin) is drawn with it; its
// glow lights up while the switch is on or the lamp lit. The boxes,
// switches and lamps are draw_entities' on both worlds (0362), under
// their frames' matrices; the cables are render_cables.odin's.

SWITCH_ON_COLOR :: rl.Color{70, 170, 80, 255}
SWITCH_OFF_COLOR :: rl.Color{180, 60, 50, 255}
SWITCH_SIZE :: 0.6
LAMP_OFF_COLOR :: rl.Color{90, 90, 80, 255}
LAMP_ON_COLOR :: rl.Color{255, 240, 170, 255}
LAMP_SIZE :: 0.4
// A junction box's inset on each side across, in cells (0368).
JUNCTION_BOX_INSET :: 0.05

draw_pole :: proc(pole: Pole, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	machine := machines.machines[pole.machine]
	if draw_machine_model(models, machines, pole.common, frame, pole_model_working(pole, machine)) {
		return
	}
	low, high := entity_cell_box(pole.origin, pole.size)
	if !begin_entity_cells_draw(frame, pole.frame, low, high) {
		return
	}
	defer end_entity_cells_draw(pole.frame)
	centre := box_centre(pole.origin, pole.size)
	if machine.kind == .Power_Switch {
		color := pole.on ? SWITCH_ON_COLOR : SWITCH_OFF_COLOR
		rl.DrawCubeV(centre, {SWITCH_SIZE, SWITCH_SIZE, SWITCH_SIZE}, color)
		rl.DrawCubeWiresV(centre, {SWITCH_SIZE, SWITCH_SIZE, SWITCH_SIZE}, ENTITY_EDGE_COLOR)
		return
	}
	extent := [3]f32{f32(pole.size.x) - 2 * JUNCTION_BOX_INSET, f32(pole.size.y), f32(pole.size.z) - 2 * JUNCTION_BOX_INSET}
	color := machine.color
	rl.DrawCubeV(centre, extent, rl.Color{color[0], color[1], color[2], 255})
	rl.DrawCubeWiresV(centre, extent, ENTITY_EDGE_COLOR)
}

draw_lamp :: proc(lamp: Lamp, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	if draw_machine_model(models, machines, lamp.common, frame, lamp.lit) {
		return
	}
	low, high := entity_cell_box(lamp.origin, lamp.size)
	if !begin_entity_cells_draw(frame, lamp.frame, low, high) {
		return
	}
	defer end_entity_cells_draw(lamp.frame)
	centre := block_centre(lamp.origin)
	centre.y = f32(lamp.origin.y) + LAMP_SIZE / 2
	rl.DrawCubeV(centre, {LAMP_SIZE, LAMP_SIZE, LAMP_SIZE}, lamp.lit ? LAMP_ON_COLOR : LAMP_OFF_COLOR)
	rl.DrawCubeWiresV(centre, {LAMP_SIZE, LAMP_SIZE, LAMP_SIZE}, ENTITY_EDGE_COLOR)
}
