package game

import "core:math"
import rl "vendor:raylib"

// Placeholder entity models: a coloured cube per footprint cell, with a
// brighter top layer on a burning furnace, for inserters a post with an
// arm that turns with the cycle, and for drills a darker top with a
// turning bar and the output arrow (brown burner, blue electric), for
// assemblers a teal body with a bright top while working, and for labs a
// white body with a blue top while researching. Real models come with the
// art pass.

CHEST_COLOR :: rl.Color{130, 88, 48, 255}
FURNACE_COLOR :: rl.Color{120, 120, 124, 255}
FURNACE_BURNING_TOP_COLOR :: rl.Color{240, 150, 60, 255}
CAPSULE_COLOR :: rl.Color{210, 212, 216, 255}
CAPSULE_TOP_COLOR :: rl.Color{200, 90, 40, 255}
ENTITY_EDGE_COLOR :: rl.Color{30, 30, 30, 255}
INSERTER_POST_COLOR :: rl.Color{70, 70, 76, 255}
BURNER_INSERTER_ARM_COLOR :: rl.Color{150, 110, 70, 255}
ELECTRIC_INSERTER_ARM_COLOR :: rl.Color{220, 190, 60, 255}
FILTER_INSERTER_ARM_COLOR :: rl.Color{150, 90, 190, 255}
INSERTER_POST_SIZE :: [3]f32{0.3, 0.4, 0.3}
INSERTER_PIVOT_HEIGHT :: 0.45
INSERTER_ARM_LENGTH :: 0.7
INSERTER_ARM_RADIUS :: 0.05
INSERTER_HELD_ITEM_SIZE :: 0.2
DRILL_COLOR :: rl.Color{150, 120, 70, 255}
DRILL_TOP_COLOR :: rl.Color{95, 75, 45, 255}
ELECTRIC_DRILL_COLOR :: rl.Color{80, 120, 150, 255}
ELECTRIC_DRILL_TOP_COLOR :: rl.Color{50, 75, 95, 255}
DRILL_BIT_COLOR :: rl.Color{200, 200, 205, 255}
DRILL_ARROW_COLOR :: rl.Color{240, 220, 80, 255}
DRILL_BIT_LENGTH :: 0.8
DRILL_BIT_RADIUS :: 0.08
ASSEMBLER_COLOR :: rl.Color{70, 130, 130, 255}
ASSEMBLER_WORKING_TOP_COLOR :: rl.Color{120, 220, 200, 255}
LAB_COLOR :: rl.Color{200, 204, 210, 255}
LAB_RESEARCHING_TOP_COLOR :: rl.Color{90, 150, 240, 255}
// Turns of the bit per drill cycle.
DRILL_BIT_TURNS_PER_CYCLE :: 4

box_centre :: proc(minimum: World_Coordinate, size: [3]i32) -> [3]f32 {
	return {f32(minimum.x) + f32(size.x) / 2, f32(minimum.y) + f32(size.y) / 2, f32(minimum.z) + f32(size.z) / 2}
}

draw_entity_cells :: proc(common: Entity_Common, machines: Machine_Registry, color, top_color: rl.Color) {
	top := common.origin.y + common.size.y - 1
	for cell in common_cells(common, machines) {
		rl.DrawCube(block_centre(cell), 1, 1, 1, cell.y == top ? top_color : color)
	}
	extent := [3]f32{f32(common.size.x), f32(common.size.y), f32(common.size.z)}
	rl.DrawCubeWiresV(box_centre(common.origin, common.size), extent, ENTITY_EDGE_COLOR)
}

inserter_arm_color :: proc(machine: Machine) -> rl.Color {
	switch {
	case inserter_has_filter(machine):
		return FILTER_INSERTER_ARM_COLOR
	case inserter_is_electric(machine):
		return ELECTRIC_INSERTER_ARM_COLOR
	}
	return BURNER_INSERTER_ARM_COLOR
}

// The arm turns about the post through the right hand side, from over the
// pickup cell (fraction 0) to over the drop cell (fraction 1).
inserter_arm_end :: proc(pivot: [3]f32, direction: u8, fraction: f32) -> [3]f32 {
	forward := belt_direction_vector(direction)
	right := belt_direction_vector(turn_right(direction))
	angle := math.PI * fraction
	return pivot + (right * math.sin(angle) - forward * math.cos(angle)) * INSERTER_ARM_LENGTH
}

draw_inserter :: proc(inserter: Inserter, machine: Machine, items: Item_Registry, tick_rate: int) {
	centre := block_centre(inserter.origin)
	bottom := f32(inserter.origin.y)
	rl.DrawCubeV({centre.x, bottom + INSERTER_POST_SIZE.y / 2, centre.z}, INSERTER_POST_SIZE, INSERTER_POST_COLOR)
	pivot := [3]f32{centre.x, bottom + INSERTER_PIVOT_HEIGHT, centre.z}
	end := inserter_arm_end(pivot, inserter.rotation, inserter_arm_fraction(inserter, machine, tick_rate))
	rl.DrawCylinderEx(pivot, end, INSERTER_ARM_RADIUS, INSERTER_ARM_RADIUS, 6, inserter_arm_color(machine))
	if !stack_is_empty(inserter.held) {
		size := f32(INSERTER_HELD_ITEM_SIZE)
		rl.DrawCube(end - {0, size / 2, 0}, size, size, size, item_cube_color(items, inserter.held.item))
	}
}

// A bar across the top that turns with the cycle while the drill mines,
// and the output arrow on the top face.
draw_drill :: proc(drill: Drill, machine: Machine, machines: Machine_Registry, tick_rate: int) {
	if drill_is_electric(drill) {
		draw_entity_cells(drill.common, machines, ELECTRIC_DRILL_COLOR, ELECTRIC_DRILL_TOP_COLOR)
	} else {
		draw_entity_cells(drill.common, machines, DRILL_COLOR, DRILL_TOP_COLOR)
	}
	centre := box_centre(drill.origin, drill.size)
	top := centre + {0, f32(drill.size.y) / 2 + 0.02, 0}
	angle := drill_progress_fraction(drill, machine, tick_rate) * DRILL_BIT_TURNS_PER_CYCLE * 2 * math.PI
	half := [3]f32{math.cos(angle), 0, math.sin(angle)} * DRILL_BIT_LENGTH / 2
	rl.DrawCylinderEx(top - half, top + half, DRILL_BIT_RADIUS, DRILL_BIT_RADIUS, 6, DRILL_BIT_COLOR)
	draw_drill_arrow(drill.origin, drill.size, drill.rotation, top.y, DRILL_ARROW_COLOR)
}

// From the footprint's centre to the side the output drops from, with a
// small cube at the tip.
draw_drill_arrow :: proc(origin: World_Coordinate, size: [3]i32, rotation: u8, height: f32, color: rl.Color) {
	centre := box_centre(origin, size)
	centre.y = height
	forward := belt_direction_vector(rotation)
	tip := centre + forward * (f32(size.x) / 2)
	rl.DrawLine3D(centre, tip, color)
	rl.DrawCubeV(tip, {0.12, 0.12, 0.12}, color)
}

// Between BeginMode3D and EndMode3D, after the chunks.
draw_entities :: proc(world: ^World, machines: Machine_Registry, items: Item_Registry, tick_rate: int) {
	for chest in world.entities.chests.entries {
		if chest.alive {
			draw_entity_cells(chest.common, machines, CHEST_COLOR, CHEST_COLOR)
		}
	}
	for furnace in world.entities.furnaces.entries {
		if furnace.alive {
			top := furnace.state == .Burning ? FURNACE_BURNING_TOP_COLOR : FURNACE_COLOR
			draw_entity_cells(furnace.common, machines, FURNACE_COLOR, top)
		}
	}
	for capsule in world.entities.capsules.entries {
		if capsule.alive {
			draw_entity_cells(capsule.common, machines, CAPSULE_COLOR, CAPSULE_TOP_COLOR)
		}
	}
	for inserter in world.entities.inserters.entries {
		if inserter.alive {
			draw_inserter(inserter, machines.machines[inserter.machine], items, tick_rate)
		}
	}
	for drill in world.entities.drills.entries {
		if drill.alive {
			draw_drill(drill, machines.machines[drill.machine], machines, tick_rate)
		}
	}
	for assembler in world.entities.assemblers.entries {
		if assembler.alive {
			top := assembler.state == .Working ? ASSEMBLER_WORKING_TOP_COLOR : ASSEMBLER_COLOR
			draw_entity_cells(assembler.common, machines, ASSEMBLER_COLOR, top)
		}
	}
	for lab in world.entities.labs.entries {
		if lab.alive {
			draw_entity_cells(lab.common, machines, LAB_COLOR, lab.state == .Researching ? LAB_RESEARCHING_TOP_COLOR : LAB_COLOR)
		}
	}
}
