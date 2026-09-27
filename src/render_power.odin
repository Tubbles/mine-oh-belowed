package game

import rl "vendor:raylib"

// Placeholder power models: a small pole is a thin tall post, a power
// switch a box in green while on and red while off, a lamp a small box
// that glows while lit, and wires are lines between the tops of wired
// nodes. A pole's ghost shows its supply volume as a wire box. A pole,
// switch or lamp with a model (render_models.odin) is drawn with it; its
// glow lights up while the switch is on or the lamp lit.

POLE_COLOR :: rl.Color{120, 90, 60, 255}
POLE_WIDTH :: 0.2
WIRE_COLOR :: rl.Color{40, 30, 20, 255}
// Below the top of the pole, where the wire hangs.
WIRE_DROP :: 0.15
SWITCH_ON_COLOR :: rl.Color{70, 170, 80, 255}
SWITCH_OFF_COLOR :: rl.Color{180, 60, 50, 255}
SWITCH_SIZE :: 0.6
LAMP_OFF_COLOR :: rl.Color{90, 90, 80, 255}
LAMP_ON_COLOR :: rl.Color{255, 240, 170, 255}
LAMP_SIZE :: 0.4
SUPPLY_VOLUME_COLOR :: rl.Color{90, 170, 240, 200}

// Where a wire meets a node: near the top of a pole, the middle of a switch.
wire_anchor :: proc(node: Electric_Node, entities: ^Entities) -> [3]f32 {
	common := entity_common(entities, node.handle)
	height := f32(common.size.y)
	anchor := box_centre(node.origin, common.size)
	anchor.y = f32(node.origin.y) + (node.supply_size == {} ? height / 2 : height - WIRE_DROP)
	return anchor
}

draw_wires :: proc(world: ^World) {
	networks := &world.entities.electric_networks
	for wire in networks.wires {
		first := wire_anchor(networks.nodes[wire.first], &world.entities)
		second := wire_anchor(networks.nodes[wire.second], &world.entities)
		rl.DrawLine3D(first, second, WIRE_COLOR)
	}
}

draw_pole :: proc(pole: Pole, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	machine := machines.machines[pole.machine]
	if draw_machine_model(models, machines, pole.common, frame, machine.kind == .Power_Switch && pole.on) {
		return
	}
	centre := box_centre(pole.origin, pole.size)
	if machine.kind == .Power_Switch {
		color := pole.on ? SWITCH_ON_COLOR : SWITCH_OFF_COLOR
		rl.DrawCubeV(centre, {SWITCH_SIZE, SWITCH_SIZE, SWITCH_SIZE}, color)
		rl.DrawCubeWiresV(centre, {SWITCH_SIZE, SWITCH_SIZE, SWITCH_SIZE}, ENTITY_EDGE_COLOR)
		return
	}
	if pole.size.x > 1 || pole.size.z > 1 {
		draw_substation(pole, centre)
		return
	}
	rl.DrawCubeV(centre, {POLE_WIDTH, f32(pole.size.y), POLE_WIDTH}, POLE_COLOR)
}

// A pole wider than one block: a frame the size of its footprint around
// a post.
draw_substation :: proc(pole: Pole, centre: [3]f32) {
	extent := [3]f32{f32(pole.size.x), f32(pole.size.y), f32(pole.size.z)}
	rl.DrawCubeWiresV(centre, extent, POLE_COLOR)
	rl.DrawCubeV(centre, {POLE_WIDTH * 2, f32(pole.size.y), POLE_WIDTH * 2}, POLE_COLOR)
}

draw_lamp :: proc(lamp: Lamp, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	if draw_machine_model(models, machines, lamp.common, frame, lamp.lit) {
		return
	}
	centre := block_centre(lamp.origin)
	centre.y = f32(lamp.origin.y) + LAMP_SIZE / 2
	rl.DrawCubeV(centre, {LAMP_SIZE, LAMP_SIZE, LAMP_SIZE}, lamp.lit ? LAMP_ON_COLOR : LAMP_OFF_COLOR)
	rl.DrawCubeWiresV(centre, {LAMP_SIZE, LAMP_SIZE, LAMP_SIZE}, ENTITY_EDGE_COLOR)
}

// Between BeginMode3D and EndMode3D, after the chunks.
draw_power_entities :: proc(world: ^World, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	for pole in world.entities.poles.entries {
		if pole.alive {
			draw_pole(pole, machines, models, frame)
		}
	}
	for lamp in world.entities.lamps.entries {
		if lamp.alive {
			draw_lamp(lamp, machines, models, frame)
		}
	}
	draw_wires(world)
}

// The supply volume of a pole's ghost.
draw_supply_volume_ghost :: proc(placement: Placement, machines: Machine_Registry) {
	machine := machines.machines[placement.machine]
	if machine.kind != .Pole {
		return
	}
	origin := supply_volume_origin(placement.origin, placement.size, machine.supply_volume)
	extent := [3]f32{f32(machine.supply_volume.x), f32(machine.supply_volume.y), f32(machine.supply_volume.z)}
	rl.DrawCubeWiresV(box_centre(origin, machine.supply_volume), extent, SUPPLY_VOLUME_COLOR)
}
