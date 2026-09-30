package game

import "generation_seed"

// Felling (work item 0059). Mining a log block drops every log straight
// above it as loose items (loose_item.odin) and queues the leaves around
// the felled column for decay. A queued leaves block decays once its due
// tick has come if no log lies within LEAF_SUPPORT_DISTANCE (Manhattan) of
// it: it turns to air, sometimes drops leaf litter or a sapling, and
// queues its leaves neighbours in turn. A supported leaf stays. Only a
// felling queues decay, so leaves the player places stay unless a log near
// them is felled. Decay runs on the main thread in tick_world, bounded per
// tick, in the order the updates were queued, so it is deterministic.

LEAF_SUPPORT_DISTANCE :: 4
// 1 to 4 seconds at 60 ticks per second.
LEAF_DECAY_MINIMUM_DELAY_TICKS :: 60
LEAF_DECAY_MAXIMUM_DELAY_TICKS :: 240
MAXIMUM_LEAF_DECAYS_PER_TICK :: 64
// One decaying leaf in LEAF_LITTER_CHANCE drops the leaves block's item,
// one in SAPLING_CHANCE a sapling.
LEAF_LITTER_CHANCE :: 8
SAPLING_CHANCE :: 20

Leaf_Decay_Update :: struct {
	due_tick: u64,
	position: World_Coordinate,
}

// felled holds the leaves cells fellings found since the last tick_world,
// which gives them their due ticks, so it is empty whenever the world is
// saved. updates is in the order queued. scheduled holds every position in
// updates and felled, so a cell is queued once.
Leaf_Decay :: struct {
	updates:   [dynamic]Leaf_Decay_Update,
	felled:    [dynamic]World_Coordinate,
	scheduled: map[World_Coordinate]struct{},
}

// What felling and decay read from the content. sapling is NO_ITEM when
// the items lack the generator's sapling_item. Empty blocks turn felling
// off (a simulation without a generator).
Tree_Felling :: struct {
	blocks:  Tree_Blocks,
	items:   Item_Registry,
	sapling: Item_Id,
}

destroy_leaf_decay :: proc(decay: ^Leaf_Decay) {
	delete(decay.updates)
	delete(decay.felled)
	delete(decay.scheduled)
}

clear_leaf_decay :: proc(decay: ^Leaf_Decay) {
	clear(&decay.updates)
	clear(&decay.felled)
	clear(&decay.scheduled)
}

simulation_tree_felling :: proc(content: Simulation_Content) -> Tree_Felling {
	if content.generator == nil {
		return {}
	}
	sapling, found := find_item_id(content.items, content.generator.sapling_item)
	return Tree_Felling{blocks = content.generator.tree_blocks, items = content.items, sapling = found ? sapling : NO_ITEM}
}

// After the log at position was mined.
fell_tree :: proc(world: ^World, registry: Block_Registry, felling: Tree_Felling, position: World_Coordinate) {
	top := drop_logs_above(world, registry, felling, position)
	queue_felled_leaves(world, felling.blocks, position, top)
}

// Every log straight above position, up to FEATURE_MAXIMUM_HEIGHT, turns
// into a loose item at its cell. Returns the height of the highest cell
// felled, position's own when there was none.
drop_logs_above :: proc(world: ^World, registry: Block_Registry, felling: Tree_Felling, position: World_Coordinate) -> i32 {
	top := position.y
	for height in i32(1) ..= FEATURE_MAXIMUM_HEIGHT {
		cell := position + {0, height, 0}
		block := world_get_block(world, cell)
		if !block_is_tree_log(felling.blocks, block) || !world_set_block(world, cell, AIR_BLOCK) {
			break
		}
		spill_stack(world, registry, cell, Item_Stack{item = block_drop(felling.items, block), count = 1})
		top = cell.y
	}
	return top
}

// Every leaves block within LEAF_REACH of the felled column horizontally,
// from LEAF_SUPPORT_DISTANCE below the mined block to LEAF_REACH above the
// highest felled log.
queue_felled_leaves :: proc(world: ^World, blocks: Tree_Blocks, position: World_Coordinate, top: i32) {
	for y in position.y - LEAF_SUPPORT_DISTANCE ..= top + LEAF_REACH {
		for dz in i32(-LEAF_REACH) ..= LEAF_REACH {
			for dx in i32(-LEAF_REACH) ..= LEAF_REACH {
				cell := World_Coordinate{position.x + dx, y, position.z + dz}
				if block_is_tree_leaves(blocks, world_get_block(world, cell)) && cell not_in world.leaf_decay.scheduled {
					world.leaf_decay.scheduled[cell] = {}
					append(&world.leaf_decay.felled, cell)
				}
			}
		}
	}
}

leaf_decay_hash :: proc(position: World_Coordinate, tick: u64) -> u64 {
	return generation_seed.hash_combine(generation_seed.hash_column(u64(u32(position.y)), position.x, position.z), tick)
}

leaf_decay_delay :: proc(hash: u64) -> u64 {
	return u64(generation_seed.hash_to_range(hash, LEAF_DECAY_MINIMUM_DELAY_TICKS, LEAF_DECAY_MAXIMUM_DELAY_TICKS))
}

leaf_decay_due_tick :: proc(position: World_Coordinate, tick: u64) -> u64 {
	return tick + leaf_decay_delay(leaf_decay_hash(position, tick))
}

schedule_leaf_decay :: proc(decay: ^Leaf_Decay, position: World_Coordinate, due_tick: u64) {
	if position in decay.scheduled {
		return
	}
	decay.scheduled[position] = {}
	append(&decay.updates, Leaf_Decay_Update{due_tick = due_tick, position = position})
}

// Whether a decaying leaf drops its litter and a sapling, both from one hash.
leaf_litter_drops :: proc(hash: u64) -> (litter, sapling: bool) {
	return hash % LEAF_LITTER_CHANCE == 0, hash / LEAF_LITTER_CHANCE % SAPLING_CHANCE == 0
}

leaf_is_supported :: proc(world: ^World, blocks: Tree_Blocks, position: World_Coordinate) -> bool {
	for dy in i32(-LEAF_SUPPORT_DISTANCE) ..= LEAF_SUPPORT_DISTANCE {
		rest := LEAF_SUPPORT_DISTANCE - abs(dy)
		for dz in -rest ..= rest {
			reach := rest - abs(dz)
			for dx in -reach ..= reach {
				if block_is_tree_log(blocks, world_get_block(world, position + {dx, dy, dz})) {
					return true
				}
			}
		}
	}
	return false
}

decay_leaf :: proc(world: ^World, registry: Block_Registry, felling: Tree_Felling, position: World_Coordinate, tick: u64) {
	block := world_get_block(world, position)
	if !block_is_tree_leaves(felling.blocks, block) || leaf_is_supported(world, felling.blocks, position) {
		return
	}
	if !world_set_block(world, position, AIR_BLOCK) {
		return
	}
	litter, sapling := leaf_litter_drops(leaf_decay_hash(position, tick))
	if litter {
		spill_stack(world, registry, position, Item_Stack{item = block_drop(felling.items, block), count = 1})
	}
	if sapling && felling.sapling != NO_ITEM {
		spill_stack(world, registry, position, Item_Stack{item = felling.sapling, count = 1})
	}
	for offset in direction_offsets {
		neighbour := position + World_Coordinate(offset)
		if block_is_tree_leaves(felling.blocks, world_get_block(world, neighbour)) {
			schedule_leaf_decay(&world.leaf_decay, neighbour, leaf_decay_due_tick(neighbour, tick))
		}
	}
}

// Up to maximum due updates, in the order queued, taken out of the queue.
take_due_leaf_decays :: proc(decay: ^Leaf_Decay, tick: u64, maximum: int) -> []World_Coordinate {
	due := make([dynamic]World_Coordinate, context.temp_allocator)
	kept := 0
	for update in decay.updates {
		if update.due_tick <= tick && len(due) < maximum {
			append(&due, update.position)
		} else {
			decay.updates[kept] = update
			kept += 1
		}
	}
	resize(&decay.updates, kept)
	return due[:]
}

// Gives this tick's felled leaves their due ticks, then decays the due
// ones. Returns how many updates ran.
run_leaf_decay :: proc(world: ^World, registry: Block_Registry, felling: Tree_Felling, tick: u64, maximum_decays: int) -> int {
	decay := &world.leaf_decay
	for position in decay.felled {
		append(&decay.updates, Leaf_Decay_Update{due_tick = leaf_decay_due_tick(position, tick), position = position})
	}
	clear(&decay.felled)
	if len(decay.updates) == 0 {
		return 0
	}
	due := take_due_leaf_decays(decay, tick, maximum_decays)
	for position in due {
		delete_key(&decay.scheduled, position)
		decay_leaf(world, registry, felling, position, tick)
	}
	return len(due)
}
