package game

import "core:slice"

// Loose items (doc/logistics.md, Loose items): item stacks lying in world
// cells. Mining and pickups spill what does not fit into the inventory,
// the inventory's Drop puts a stack down, and a belt that ends over a drop
// lets its items fall off. Loose items are not machines: they live in
// their own list in Entities, never in the cell map, so they block
// nothing. Their state is integer: a stack falls one cell per
// LOOSE_ITEM_FALL_TICKS and counts its age in ticks.

LOOSE_ITEM_FALL_TICKS :: 6
// Loose_Item.dropping_player of a stack no player dropped.
NO_DROPPING_PLAYER :: u32(0)
// Spilling into a solid cell looks this many cells up for an open one.
LOOSE_ITEM_MAXIMUM_LIFT :: 64

Loose_Item :: struct {
	item:            Item_Id,
	count:           u16,
	cell:            World_Coordinate,
	// Where in the cell the stack lies on x and z, in quarter blocks from
	// the centre: a belt it lands on takes the lane on that side, so items
	// falling off a belt end keep their lane.
	offset:          [2]i8,
	// Ticks spent moving into the cell below; 0 while it rests.
	fall_ticks:      u32,
	age_ticks:       u32,
	// The player who dropped the stack, as its index into the players
	// plus one (dropping_player_value), or NO_DROPPING_PLAYER. That player
	// picks it up only after having been out of pickup range of it once
	// (work item 0128), since a drop lands inside the range.
	dropping_player: u32,
}

Loose_Items :: struct {
	// In the order they appeared, which the tick and the save keep.
	items:         [dynamic]Loose_Item,
	// Age at which a stack vanishes, 0 for never. From game.sjson's
	// loose_item_despawn_minutes (make_simulation); not saved.
	despawn_ticks: u64,
}

loose_item_despawn_ticks :: proc(minutes: int, tick_rate: int) -> u64 {
	return u64(max(minutes, 0)) * 60 * u64(max(tick_rate, 1))
}

// No solid block and no entity other than a belt: a stack may lie there.
cell_holds_loose_items :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> bool {
	if block_is_solid(registry, world_get_block(world, cell)) {
		return false
	}
	handle, occupied := world.entities.cells[cell]
	return !occupied || handle.kind == .Belt
}

// The cell itself, or the first cell above it a stack may lie in.
first_open_cell_above :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> World_Coordinate {
	result := cell
	for _ in 0 ..< LOOSE_ITEM_MAXIMUM_LIFT {
		if cell_holds_loose_items(world, registry, result) {
			return result
		}
		result.y += 1
	}
	return result
}

// A stack moves on into the cell below while both cells are dry and the
// one below is loaded and open. Water holds it at the surface, an
// unloaded chunk where it is.
loose_item_can_fall :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> bool {
	below := cell - UP
	if world_to_chunk_coordinate(below) not_in world.chunks {
		return false
	}
	if block_water_level(registry, world_get_block(world, cell)) > 0 || block_water_level(registry, world_get_block(world, below)) > 0 {
		return false
	}
	return cell_holds_loose_items(world, registry, below)
}

// Puts a stack at the cell, or at the first open cell above when the cell
// is solid or holds a machine. A stack in a belt's cell goes onto the belt
// as the belt has room (tick_loose_items).
spill_stack :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate, stack: Item_Stack, offset := [2]i8{}) {
	if stack_is_empty(stack) {
		return
	}
	loose := Loose_Item {
		item   = stack.item,
		count  = stack.count,
		cell   = first_open_cell_above(world, registry, cell),
		offset = offset,
	}
	append(&world.entities.loose_items.items, loose)
}

// The point the stack lies at, for the lane of a belt it lands on.
loose_item_point :: proc(loose: Loose_Item) -> [3]f32 {
	return block_centre(loose.cell) + {f32(loose.offset.x) / 4, 0, f32(loose.offset.y) / 4}
}

// One item per tick onto the belt in the stack's cell, on the lane on the
// stack's side; the rest waits on top while the belt has no room.
put_loose_item_on_belt :: proc(entities: ^Entities, loose: ^Loose_Item, handle: Entity_Handle) {
	belt := pool_get(&entities.belts, handle)
	if belt == nil {
		return
	}
	if belt_insert_item(entities, handle, belt_near_lane(belt^, loose_item_point(loose^)), loose.item) {
		loose.count -= 1
	}
}

// A block or a machine put into the stack's cell pushes it up a cell per
// tick; in a belt's cell it goes onto the belt; otherwise it falls.
advance_loose_item :: proc(world: ^World, registry: Block_Registry, loose: ^Loose_Item) {
	loose.age_ticks += 1
	if !cell_holds_loose_items(world, registry, loose.cell) {
		loose.cell.y += 1
		loose.fall_ticks = 0
		return
	}
	if handle := entity_at(&world.entities, loose.cell); handle.kind == .Belt {
		loose.fall_ticks = 0
		put_loose_item_on_belt(&world.entities, loose, handle)
		return
	}
	if !loose_item_can_fall(world, registry, loose.cell) {
		loose.fall_ticks = 0
		return
	}
	loose.fall_ticks += 1
	if loose.fall_ticks >= LOOSE_ITEM_FALL_TICKS {
		loose.cell.y -= 1
		loose.fall_ticks = 0
	}
}

// A later stack of the same item at the same place in a cell (cell and
// offset, so the two lanes falling off a belt stay apart) moves into the
// earlier one up to the stack size. The merged stack keeps the younger age, so a
// merge never brings a despawn forward, and the dropping player
// (merged_dropping_player).
merge_loose_items :: proc(items: []Loose_Item, registry: Item_Registry) {
	for &later, index in items {
		for &earlier in items[:index] {
			if later.count == 0 || earlier.count == 0 || earlier.item != later.item || earlier.cell != later.cell || earlier.offset != later.offset {
				continue
			}
			moved := min(int(later.count), max(int(item_stack_size(registry, later.item)) - int(earlier.count), 0))
			if moved > 0 {
				earlier.count += u16(moved)
				later.count -= u16(moved)
				earlier.age_ticks = min(earlier.age_ticks, later.age_ticks)
				earlier.dropping_player = merged_dropping_player(earlier.dropping_player, later.dropping_player)
			}
		}
	}
}

dropping_player_value :: proc(player_index: int) -> u32 {
	return u32(player_index) + 1
}

// The dropper of the stack merged in wins when it has one, so a fresh
// drop onto an older stack still waits for its player.
merged_dropping_player :: proc(existing, merged_in: u32) -> u32 {
	return merged_in != NO_DROPPING_PLAYER ? merged_in : existing
}

loose_item_expired :: proc(loose: Loose_Item, despawn_ticks: u64) -> bool {
	return despawn_ticks > 0 && u64(loose.age_ticks) >= despawn_ticks
}

// Keeps the order of the rest.
remove_spent_loose_items :: proc(loose_items: ^Loose_Items) {
	kept := 0
	for loose in loose_items.items {
		if loose.count > 0 && loose.item != NO_ITEM && !loose_item_expired(loose, loose_items.despawn_ticks) {
			loose_items.items[kept] = loose
			kept += 1
		}
	}
	resize(&loose_items.items, kept)
}

// After the belts, so a stack that fell off a belt end this tick starts
// falling at once.
tick_loose_items :: proc(world: ^World, content: Simulation_Content) {
	loose_items := &world.entities.loose_items
	for &loose in loose_items.items {
		advance_loose_item(world, content.blocks, &loose)
	}
	merge_loose_items(loose_items.items[:], content.items)
	remove_spent_loose_items(loose_items)
}

// A machine placed over stacks lifts them onto its top.
lift_loose_items_out_of :: proc(loose_items: ^Loose_Items, cells: []World_Coordinate, top: i32) {
	for &loose in loose_items.items {
		if slice.contains(cells, loose.cell) {
			loose.cell.y = top
			loose.fall_ticks = 0
		}
	}
}

// Walking near stacks picks them up as far as they fit
// (inventory_add_picked_up); a full inventory leaves them lying.
LOOSE_ITEM_PICKUP_RANGE :: 1

// A stack whose cell centre lies within LOOSE_ITEM_PICKUP_RANGE blocks of
// the player's position on x and z, in the feet's cell layer or the one
// below it.
loose_item_in_pickup_range :: proc(cell, feet: World_Coordinate, position: [3]f32) -> bool {
	if cell.y != feet.y && cell.y != feet.y - 1 {
		return false
	}
	centre := block_centre(cell)
	distance := [2]f32{centre.x - position.x, centre.z - position.z}
	return distance.x * distance.x + distance.y * distance.y <= LOOSE_ITEM_PICKUP_RANGE * LOOSE_ITEM_PICKUP_RANGE
}

// A stack the player dropped waits for that player to leave its pickup
// range once; other players may take it at once.
loose_item_waits_for_player :: proc(loose: Loose_Item, player_index: int) -> bool {
	return loose.dropping_player == dropping_player_value(player_index)
}

// A tick out of range of the player who dropped the stack clears the
// dropper.
dropping_player_out_of_range :: proc(dropping_player: u32, player_index: int) -> u32 {
	return dropping_player == dropping_player_value(player_index) ? NO_DROPPING_PLAYER : dropping_player
}

pick_up_loose_items :: proc(world: ^World, items: Item_Registry, player: ^Player, player_index: int) {
	feet := camera_world_coordinate(player.position + {0, COLLISION_EPSILON, 0})
	loose_items := &world.entities.loose_items
	picked := false
	for &loose in loose_items.items {
		if loose.count == 0 {
			continue
		}
		if !loose_item_in_pickup_range(loose.cell, feet, player.position) {
			loose.dropping_player = dropping_player_out_of_range(loose.dropping_player, player_index)
		} else if !loose_item_waits_for_player(loose, player_index) {
			leftover := inventory_add_picked_up(player.inventory, items, loose.item, int(loose.count))
			picked ||= leftover < int(loose.count)
			loose.count = u16(leftover)
		}
	}
	if picked {
		remove_spent_loose_items(loose_items)
	}
}

// The cell in front of the player at feet height, along the quarter the
// player faces, so a dropped stack never lies in the player's own cell.
player_drop_cell :: proc(player: Player) -> World_Coordinate {
	return camera_world_coordinate(player.position) + belt_direction_offset(yaw_direction(player.yaw))
}

// The inventory's Drop: the cursor's stack, or with nothing held the
// focused slot's (-1 for none), goes onto the ground in front of the
// player, where that player picks it up only after leaving its pickup
// range once. Returns whether anything was dropped.
drop_player_stack :: proc(world: ^World, statistics: ^Statistics, registry: Block_Registry, player: ^Player, player_index: int, focused: int) -> bool {
	stack := player.held.stack
	switch {
	case !stack_is_empty(stack):
		player.held = EMPTY_HELD_STACK
	case focused >= 0 && focused < len(player.inventory.slots) && !stack_is_empty(player.inventory.slots[focused]):
		stack = player.inventory.slots[focused]
		player.inventory.slots[focused] = EMPTY_STACK
	case:
		return false
	}
	spill_stack(world, registry, player_drop_cell(player^), stack)
	dropped := &world.entities.loose_items.items[len(world.entities.loose_items.items) - 1]
	dropped.dropping_player = dropping_player_value(player_index)
	record_world_action(statistics)
	return true
}

// Stacks of an item the game data no longer has leave the list.
drop_gone_loose_items :: proc(items: ^[dynamic]Loose_Item) {
	kept := 0
	for loose in items {
		if loose.item != NO_ITEM {
			items[kept] = loose
			kept += 1
		}
	}
	resize(items, kept)
}
