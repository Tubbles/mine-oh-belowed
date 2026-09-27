package game

import rl "vendor:raylib"

// Placeholder entity models: a coloured cube per footprint cell, with a
// brighter top layer on a burning furnace. Real models come with the art pass.

CHEST_COLOR :: rl.Color{130, 88, 48, 255}
FURNACE_COLOR :: rl.Color{120, 120, 124, 255}
FURNACE_BURNING_TOP_COLOR :: rl.Color{240, 150, 60, 255}
CAPSULE_COLOR :: rl.Color{210, 212, 216, 255}
CAPSULE_TOP_COLOR :: rl.Color{200, 90, 40, 255}
ENTITY_EDGE_COLOR :: rl.Color{30, 30, 30, 255}

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

// Between BeginMode3D and EndMode3D, after the chunks.
draw_entities :: proc(world: ^World, machines: Machine_Registry) {
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
}
