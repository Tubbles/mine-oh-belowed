package game

import "core:container/queue"

// Flowing water, Minecraft style cellular flow. Source blocks (from
// generation) never change by themselves and never run dry. Every other
// cell that is air or flowing water holds the level its neighbours give it:
// WATER_FALLING_LEVEL under any water, otherwise one less than the highest
// horizontal neighbour that can spread sideways, or nothing. Water spreads
// sideways only from a source or from water resting on solid ground or on
// a source, so it falls first and spreads where it lands. When a source
// goes, the levels around it drop by at least one per update round until
// the water is gone.
//
// Updates are scheduled for a cell and its six neighbours whenever a block
// changes next to water, run WATER_FLOW_DELAY_TICKS later in the order
// they were scheduled, and are bounded per tick. Everything runs on the
// main thread inside simulation_tick, so the order is deterministic for
// the same edits and the same loaded chunks.

WATER_SOURCE_LEVEL :: 8
// One below a source: a waterfall spreads one block less far than a
// source where it lands. Flowing water has eight block ids, so a separate
// falling state would need a ninth.
WATER_FALLING_LEVEL :: WATER_SOURCE_LEVEL - 1
// Six blocks per second at 60 ticks per second.
WATER_FLOW_DELAY_TICKS :: 10
MAXIMUM_WATER_UPDATES_PER_TICK :: 256

Water_Update :: struct {
	due_tick: u64,
	position: World_Coordinate,
}

// scheduled holds every position in updates, so a cell is queued once.
Water_Flow :: struct {
	updates:   queue.Queue(Water_Update),
	scheduled: map[World_Coordinate]struct{},
}

@(rodata)
horizontal_directions := [4]Direction{.Negative_X, .Positive_X, .Negative_Z, .Positive_Z}

destroy_water_flow :: proc(flow: ^Water_Flow) {
	queue.destroy(&flow.updates)
	delete(flow.scheduled)
}

world_water_level :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate) -> int {
	return block_water_level(registry, world_get_block(world, position))
}

water_spreads_sideways :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate, level: int) -> bool {
	if level == WATER_SOURCE_LEVEL {
		return true
	}
	below := world_get_block(world, position + {0, -1, 0})
	return block_is_solid(registry, below) || block_water_level(registry, below) == WATER_SOURCE_LEVEL
}

// The level a cell that is air or flowing water should hold, 0 for none.
desired_water_level :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate) -> int {
	if world_water_level(world, registry, position + {0, 1, 0}) > 0 {
		return WATER_FALLING_LEVEL
	}
	best := 0
	for direction in horizontal_directions {
		neighbour := position + World_Coordinate(direction_offsets[direction])
		level := world_water_level(world, registry, neighbour)
		if level > 1 && water_spreads_sideways(world, registry, neighbour, level) {
			best = max(best, level - 1)
		}
	}
	return best
}

// Only air and flowing water change. Sources, solid blocks and other
// blocks that are not solid (a torch) stay.
update_water_cell :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate) {
	if world_to_chunk_coordinate(position) not_in world.chunks {
		return
	}
	// Entity cells are air in the chunk data but a machine stands there,
	// except in a hydro turbine, which water flows through.
	if handle, found := world.entities.cells[position]; found && !entity_lets_water_through(&world.entities, handle) {
		return
	}
	block := world_get_block(world, position)
	level := block_water_level(registry, block)
	if level == WATER_SOURCE_LEVEL || block != AIR_BLOCK && level == 0 {
		return
	}
	desired := desired_water_level(world, registry, position)
	if desired == level {
		return
	}
	next := AIR_BLOCK
	if desired > 0 {
		found: bool
		next, found = water_block_for_level(registry, desired)
		if !found {
			return
		}
	}
	world_set_block(world, position, next)
}

entity_lets_water_through :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	fluid_machine := pool_get(&entities.fluid_machines, handle)
	return fluid_machine != nil && fluid_machine.lets_water_through
}

schedule_water_update :: proc(flow: ^Water_Flow, position: World_Coordinate, due_tick: u64) {
	if position in flow.scheduled {
		return
	}
	flow.scheduled[position] = {}
	queue.push_back(&flow.updates, Water_Update{due_tick = due_tick, position = position})
}

cell_touches_water :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate) -> bool {
	if world_water_level(world, registry, position) > 0 {
		return true
	}
	for offset in direction_offsets {
		if world_water_level(world, registry, position + World_Coordinate(offset)) > 0 {
			return true
		}
	}
	return false
}

// A change at position can only move water in it and its six neighbours.
schedule_water_around :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate, tick: u64) {
	if !cell_touches_water(world, registry, position) {
		return
	}
	due := tick + WATER_FLOW_DELAY_TICKS
	schedule_water_update(&world.water, position, due)
	for offset in direction_offsets {
		schedule_water_update(&world.water, position + World_Coordinate(offset), due)
	}
}

// The delay is the same for every update, so the queue is in due order.
run_water_updates :: proc(world: ^World, registry: Block_Registry, tick: u64, maximum_updates: int) -> int {
	flow := &world.water
	for updates in 0 ..< maximum_updates {
		if queue.len(flow.updates) == 0 || queue.front(&flow.updates).due_tick > tick {
			return updates
		}
		update := queue.pop_front(&flow.updates)
		delete_key(&flow.scheduled, update.position)
		update_water_cell(world, registry, update.position)
	}
	return maximum_updates
}
