package game

import "core:container/queue"

// Sky light and coloured block light, Minecraft style: 16 levels on each
// of four channels (sky, red, green, blue), stored as the four nibbles of
// Chunk.light. Light spreads to the six face neighbours that are not
// opaque and loses one level per block on every channel alike, except sky
// light at full strength, which falls straight down without loss. The
// channels never mix while spreading: a cell holds the brightest level
// that reaches it per channel, so two emitters of different colours mix by
// taking the larger level per channel (work item 0072).
//
// Generation workers compute a chunk's sky light from its own columns
// (world_light_sky.odin). Everything that crosses chunk borders or follows
// an edit runs here, on the main thread inside simulation_tick, through
// bounded queues: a removal queue that darkens what a removed source or a
// new opaque block used to light, and an addition queue that spreads light
// from its nodes. Removals run before additions, and the final values do
// not depend on the order the nodes are visited in.
//
// Besides blocks, entities can emit block light: World.entity_lights maps
// a cell to its colour (a lit lamp, power_machine.odin). A cell emits the
// brighter of its block and its entity light per channel.

MAXIMUM_LIGHT :: 15
// Nodes taken from the removal and addition queues per tick together, over
// all channels: a white emitter costs three times a single channel.
MAXIMUM_LIGHT_STEPS_PER_TICK :: 4096
// Newly loaded chunks whose borders are compared with their neighbours
// per tick. One comparison visits 2 * 6 * CHUNK_SIZE * CHUNK_SIZE cells.
MAXIMUM_LIGHT_CHUNK_SEEDS_PER_TICK :: 4

// The order is the nibble order of a packed light value, sky highest.
Light_Channel :: enum u8 {
	Sky,
	Red,
	Green,
	Blue,
}

BLOCK_LIGHT_CHANNELS :: bit_set[Light_Channel]{.Red, .Green, .Blue}
EVERY_LIGHT_CHANNEL :: bit_set[Light_Channel]{.Sky, .Red, .Green, .Blue}

// Block light emitted or held: red, green, blue, 0 to MAXIMUM_LIGHT each.
Light_Color :: [3]u8

// The three block light nibbles of a packed light value. Most cells hold
// no block light, and the hot loops skip those channels then.
BLOCK_LIGHT_MASK :: u16(0x0FFF)

// The channels worth visiting for a packed light value: the sky alone
// when it holds no block light.
held_light_channels :: proc(light: u16) -> bit_set[Light_Channel] {
	return light & BLOCK_LIGHT_MASK == 0 ? {.Sky} : EVERY_LIGHT_CHANNEL
}

// For removals, value is the level the cell had before it was cleared.
Light_Node :: struct {
	position: World_Coordinate,
	channel:  Light_Channel,
	value:    u8,
}

Lighting :: struct {
	removals:       queue.Queue(Light_Node),
	additions:      queue.Queue(Light_Node),
	arrived_chunks: queue.Queue(Chunk_Coordinate),
}

// A loaded cell, found once so that reading and writing it costs one map
// lookup.
World_Cell :: struct {
	chunk: ^Chunk,
	index: int,
}

destroy_lighting :: proc(lighting: ^Lighting) {
	queue.destroy(&lighting.removals)
	queue.destroy(&lighting.additions)
	queue.destroy(&lighting.arrived_chunks)
}

light_shift :: proc(channel: Light_Channel) -> u16 {
	return u16(3 - u8(channel)) * 4
}

light_level :: proc(light: u16, channel: Light_Channel) -> u8 {
	return u8(light >> light_shift(channel) & 0x0F)
}

with_light_level :: proc(light: u16, channel: Light_Channel, level: u8) -> u16 {
	shift := light_shift(channel)
	return light & ~(u16(0x0F) << shift) | u16(level) << shift
}

// A plain level as block, pack_light(sky, 9), is white light.
pack_light :: proc(sky: u8, block: Light_Color) -> u16 {
	return u16(sky) << 12 | u16(block.r) << 8 | u16(block.g) << 4 | u16(block.b)
}

unpack_block_light :: proc(light: u16) -> Light_Color {
	return {light_level(light, .Red), light_level(light, .Green), light_level(light, .Blue)}
}

// A colour's level on one channel, 0 on the sky channel.
color_channel_level :: proc(color: Light_Color, channel: Light_Channel) -> u8 {
	return channel == .Sky ? 0 : color[int(channel) - 1]
}

brighter_light_color :: proc(first, second: Light_Color) -> Light_Color {
	return {max(first.r, second.r), max(first.g, second.g), max(first.b, second.b)}
}

// A colour's largest channel, the one level that stands for it.
light_color_level :: proc(color: Light_Color) -> u8 {
	return max(color.r, color.g, color.b)
}

// Full sky light keeps its level going down, everything else loses one.
light_falls_straight :: proc(channel: Light_Channel, direction: Direction, level: u8) -> bool {
	return channel == .Sky && direction == .Negative_Y && level == MAXIMUM_LIGHT
}

spread_level :: proc(channel: Light_Channel, direction: Direction, level: u8) -> u8 {
	if light_falls_straight(channel, direction, level) {
		return level
	}
	return level > 0 ? level - 1 : 0
}

opposite_direction :: proc(direction: Direction) -> Direction {
	return Direction(u8(direction) ~ 1)
}

world_cell :: proc(world: ^World, position: World_Coordinate) -> (cell: World_Cell, loaded: bool) {
	chunk := world.chunks[world_to_chunk_coordinate(position)] or_else nil
	if chunk == nil {
		return {}, false
	}
	return World_Cell{chunk = chunk, index = local_to_index(world_to_local_coordinate(position))}, true
}

cell_light :: proc(cell: World_Cell, channel: Light_Channel) -> u8 {
	return light_level(cell.chunk.light[cell.index], channel)
}

cell_block :: proc(cell: World_Cell) -> Block_Id {
	return cell.chunk.blocks[cell.index]
}

// Missing chunks read as 0 on every channel.
world_get_light :: proc(world: ^World, position: World_Coordinate) -> u16 {
	cell, loaded := world_cell(world, position)
	if !loaded {
		return 0
	}
	return cell.chunk.light[cell.index]
}

set_cell_light :: proc(world: ^World, position: World_Coordinate, cell: World_Cell, channel: Light_Channel, level: u8) {
	cell.chunk.light[cell.index] = with_light_level(cell.chunk.light[cell.index], channel, level)
	mark_chunks_around_cell_dirty(world, cell.chunk, position)
}

push_removal :: proc(lighting: ^Lighting, position: World_Coordinate, channel: Light_Channel, value: u8) {
	queue.push_back(&lighting.removals, Light_Node{position = position, channel = channel, value = value})
}

push_addition :: proc(lighting: ^Lighting, position: World_Coordinate, channel: Light_Channel) {
	queue.push_back(&lighting.additions, Light_Node{position = position, channel = channel})
}

// Clears a cell's light on one channel and queues the removal of what it lit.
remove_cell_light :: proc(world: ^World, position: World_Coordinate, cell: World_Cell, channel: Light_Channel) {
	level := cell_light(cell, channel)
	if level == 0 {
		return
	}
	set_cell_light(world, position, cell, channel, 0)
	push_removal(&world.lighting, position, channel, level)
}

// Neighbours holding light on any of channels spread it into the cell again.
queue_lit_neighbours :: proc(world: ^World, position: World_Coordinate, channels: bit_set[Light_Channel]) {
	for direction in Direction {
		neighbour := position + World_Coordinate(direction_offsets[direction])
		cell := world_cell(world, neighbour) or_continue
		for channel in channels {
			if cell_light(cell, channel) > 0 {
				push_addition(&world.lighting, neighbour, channel)
			}
		}
	}
}

// Clears the cell's three block channels, queueing the removal of what
// they lit, and gives the cell its own emission back.
reset_cell_emission :: proc(world: ^World, position: World_Coordinate, cell: World_Cell, emission: Light_Color) {
	for channel in BLOCK_LIGHT_CHANNELS {
		remove_cell_light(world, position, cell, channel)
		if level := color_channel_level(emission, channel); level > 0 {
			set_cell_light(world, position, cell, channel, level)
			push_addition(&world.lighting, position, channel)
		}
	}
}

// Incremental update after the block at position changed from previous.
// Only opacity and emission matter to light, so water flowing through air
// costs nothing here.
light_block_changed :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate, previous: Block_Id) {
	cell, loaded := world_cell(world, position)
	if !loaded {
		return
	}
	block := cell_block(cell)
	opaque := block_is_opaque(registry, block)
	emission := block_light_color(registry, block)
	if opaque == block_is_opaque(registry, previous) && emission == block_light_color(registry, previous) {
		return
	}
	reset_cell_emission(world, position, cell, emission)
	if opaque {
		remove_cell_light(world, position, cell, .Sky)
		return
	}
	queue_lit_neighbours(world, position, EVERY_LIGHT_CHANNEL)
}

cell_emission :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate, cell: World_Cell) -> Light_Color {
	return brighter_light_color(block_light_color(registry, cell_block(cell)), world.entity_lights[position] or_else {})
}

// Turns an entity light source at position on (a colour above black), off
// or to another colour: what it lit goes through the removal queue, and
// the cell's own emission comes back through the addition queue.
set_entity_light :: proc(world: ^World, position: World_Coordinate, color: Light_Color) {
	if (world.entity_lights[position] or_else {}) == color {
		return
	}
	if color == {} {
		delete_key(&world.entity_lights, position)
	} else {
		world.entity_lights[position] = color
	}
	cell, loaded := world_cell(world, position)
	if !loaded {
		return
	}
	reset_cell_emission(world, position, cell, color)
	queue_lit_neighbours(world, position, BLOCK_LIGHT_CHANNELS)
}

// A cleared cell that emits light on channel gets its own light back and
// spreads it.
restore_emission :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate, cell: World_Cell, channel: Light_Channel) {
	if channel == .Sky {
		return
	}
	level := color_channel_level(cell_emission(world, registry, position, cell), channel)
	if level > 0 {
		set_cell_light(world, position, cell, channel, level)
		push_addition(&world.lighting, position, channel)
	}
}

// Neighbours dimmer than the removed level got their light from it and are
// cleared in turn. Brighter ones have another source and spread it back.
light_removal_step :: proc(world: ^World, registry: Block_Registry, node: Light_Node) {
	for direction in Direction {
		neighbour := node.position + World_Coordinate(direction_offsets[direction])
		cell := world_cell(world, neighbour) or_continue
		level := cell_light(cell, node.channel)
		switch {
		case level == 0:
		case level < node.value || light_falls_straight(node.channel, direction, node.value) && level == MAXIMUM_LIGHT:
			set_cell_light(world, neighbour, cell, node.channel, 0)
			push_removal(&world.lighting, neighbour, node.channel, level)
			restore_emission(world, registry, neighbour, cell, node.channel)
		case:
			push_addition(&world.lighting, neighbour, node.channel)
		}
	}
}

light_addition_step :: proc(world: ^World, registry: Block_Registry, node: Light_Node) {
	cell, loaded := world_cell(world, node.position)
	level := loaded ? cell_light(cell, node.channel) : 0
	if level == 0 {
		return
	}
	for direction in Direction {
		spread := spread_level(node.channel, direction, level)
		neighbour := node.position + World_Coordinate(direction_offsets[direction])
		target := world_cell(world, neighbour) or_continue
		if spread > cell_light(target, node.channel) && !block_is_opaque(registry, cell_block(target)) {
			set_cell_light(world, neighbour, target, node.channel, spread)
			push_addition(&world.lighting, neighbour, node.channel)
		}
	}
}

// Runs at most maximum_steps queue nodes, removals first. Returns the
// number run.
propagate_light :: proc(world: ^World, registry: Block_Registry, maximum_steps: int) -> int {
	lighting := &world.lighting
	for steps in 0 ..< maximum_steps {
		switch {
		case queue.len(lighting.removals) > 0:
			light_removal_step(world, registry, queue.pop_front(&lighting.removals))
		case queue.len(lighting.additions) > 0:
			light_addition_step(world, registry, queue.pop_front(&lighting.additions))
		case:
			return steps
		}
	}
	return maximum_steps
}

// Queues `from` on every channel where its light would raise `to`, the cell
// one step away in direction.
seed_light_across :: proc(lighting: ^Lighting, registry: Block_Registry, from, to: World_Cell, from_position: World_Coordinate, direction: Direction) {
	if block_is_opaque(registry, cell_block(to)) {
		return
	}
	from_light, to_light := from.chunk.light[from.index], to.chunk.light[to.index]
	for channel in held_light_channels(from_light) {
		if spread_level(channel, direction, light_level(from_light, channel)) > light_level(to_light, channel) {
			push_addition(lighting, from_position, channel)
		}
	}
}

// Generation lights a chunk from its own columns only, which never makes a
// cell brighter than it should be. Comparing each border cell with the cell
// across the border finds where light has to flow in or out.
seed_chunk_border_light :: proc(world: ^World, registry: Block_Registry, coordinate: Chunk_Coordinate) {
	chunk := world.chunks[coordinate] or_else nil
	if chunk == nil {
		return
	}
	for neighbour, direction in chunk_neighbours(world, coordinate) {
		if neighbour == nil {
			continue
		}
		axis := direction_axis(direction)
		inside_layer := direction_is_positive(direction) ? CHUNK_SIZE - 1 : 0
		for v in 0 ..< CHUNK_SIZE {
			for u in 0 ..< CHUNK_SIZE {
				inside_local := slice_local(axis, inside_layer, u, v)
				outside_local := slice_local(axis, CHUNK_SIZE - 1 - inside_layer, u, v)
				inside := World_Cell{chunk = chunk, index = local_to_index(inside_local)}
				outside := World_Cell{chunk = neighbour, index = local_to_index(outside_local)}
				inside_position := local_to_world_coordinate(coordinate, inside_local)
				outside_position := local_to_world_coordinate(neighbour.coordinate, outside_local)
				seed_light_across(&world.lighting, registry, inside, outside, inside_position, direction)
				seed_light_across(&world.lighting, registry, outside, inside, outside_position, opposite_direction(direction))
			}
		}
	}
}

seed_arrived_chunks :: proc(world: ^World, registry: Block_Registry, maximum_chunks: int) {
	for _ in 0 ..< maximum_chunks {
		coordinate := queue.pop_front_safe(&world.lighting.arrived_chunks) or_break
		seed_chunk_border_light(world, registry, coordinate)
	}
}

pending_light_nodes :: proc(lighting: Lighting) -> int {
	return queue.len(lighting.removals) + queue.len(lighting.additions)
}

// A cell that emits light gets its emission and spreads it, like a torch
// placed there, on every channel where it is brighter than what the cell
// holds. For chunks that arrive with emitters in them.
seed_emitter :: proc(world: ^World, registry: Block_Registry, position: World_Coordinate) {
	cell, loaded := world_cell(world, position)
	if !loaded {
		return
	}
	emission := cell_emission(world, registry, position, cell)
	for channel in BLOCK_LIGHT_CHANNELS {
		level := color_channel_level(emission, channel)
		if level > cell_light(cell, channel) {
			set_cell_light(world, position, cell, channel, level)
			push_addition(&world.lighting, position, channel)
		}
	}
}

// Light is not saved, so a chunk with saved blocks relights its light
// emitting blocks when it arrives.
seed_block_emitters_in_chunk :: proc(world: ^World, registry: Block_Registry, chunk: ^Chunk) {
	for block, index in chunk.blocks {
		if block_light_emission(registry, block) > 0 {
			seed_emitter(world, registry, local_to_world_coordinate(chunk.coordinate, index_to_local(index)))
		}
	}
}

// Entity lights (lit lamps) stay registered while their chunk is away and
// shine again when it arrives. Emission does not depend on the registry
// for entity light, so an empty one is fine here.
seed_entity_lights_in_chunk :: proc(world: ^World, chunk: ^Chunk) {
	for position in world.entity_lights {
		if world_to_chunk_coordinate(position) == chunk.coordinate {
			seed_emitter(world, {}, position)
		}
	}
}
