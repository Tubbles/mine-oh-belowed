package game

import "core:math"

// Hand mining, placing and the selected hotbar slot. Progress counts whole ticks,
// so it stays integer like every accumulating simulation quantity.

Mining_State :: struct {
	active:         bool,
	block:          World_Coordinate,
	block_id:       Block_Id,
	progress_ticks: u32,
	required_ticks: u32,
}

// At least one tick, so a very soft block still takes a press.
mining_required_ticks :: proc(hardness_seconds: f32, tick_rate: int) -> u32 {
	return max(u32(math.round(hardness_seconds * f32(tick_rate))), 1)
}

// Progress starts over whenever the button is up or the target changes,
// including a different block appearing at the same position.
advance_mining :: proc(state: Mining_State, holding: bool, target: Raycast_Hit, block_id: Block_Id, required_ticks: u32) -> (next: Mining_State, broken: bool) {
	if !holding || !target.hit || required_ticks == 0 {
		return {}, false
	}
	next = state
	if !state.active || state.block != target.block || state.block_id != block_id {
		next = Mining_State{active = true, block = target.block, block_id = block_id, required_ticks = required_ticks}
	}
	next.progress_ticks += 1
	if next.progress_ticks >= next.required_ticks {
		return {}, true
	}
	return next, false
}

mining_fraction :: proc(state: Mining_State) -> f32 {
	if !state.active || state.required_ticks == 0 {
		return 0
	}
	return f32(state.progress_ticks) / f32(state.required_ticks)
}

required_ticks_for :: proc(registry: Block_Registry, block_id: Block_Id, tick_rate: int) -> u32 {
	if !block_is_minable(registry, block_id) {
		return 0
	}
	return mining_required_ticks(registry.definitions[block_id].hardness_seconds, tick_rate)
}

// The block's item goes into the inventory, hotbar first. With no room
// the block still breaks and the item is lost: there are no item drops in
// the world yet.
mine_with_player :: proc(world: ^World, registry: Block_Registry, items: Item_Registry, player: ^Player, holding: bool, tick_rate: int) -> Player_Events {
	block_id := world_get_block(world, player.target.block)
	required := required_ticks_for(registry, block_id, tick_rate)
	broken: bool
	player.mining, broken = advance_mining(player.mining, holding, player.target, block_id, required)
	if !broken || !world_set_block(world, player.target.block, AIR_BLOCK) {
		return {}
	}
	drop := block_drop(items, block_id)
	if drop != NO_ITEM && inventory_add(player.inventory, items, drop, 1) > 0 {
		return {.Inventory_Full}
	}
	return {}
}

// A block may go into a cell that is not solid and that no player's body
// overlaps.
placement_allowed :: proc(world: ^World, registry: Block_Registry, players: []Player, cell: World_Coordinate) -> bool {
	if block_is_solid(registry, world_get_block(world, cell)) {
		return false
	}
	for other in players {
		if boxes_overlap(player_box(other.position), block_box(cell)) {
			return false
		}
	}
	return true
}

selected_hotbar_stack :: proc(player: Player) -> Item_Stack {
	return inventory_hotbar(player.inventory)[player.selected_hotbar_slot]
}

// The block the selected hotbar slot would place, or air.
selected_placed_block :: proc(player: Player, items: Item_Registry) -> Block_Id {
	stack := selected_hotbar_stack(player)
	if stack_is_empty(stack) {
		return AIR_BLOCK
	}
	return item_places_block(items, stack.item)
}

place_with_player :: proc(world: ^World, registry: Block_Registry, items: Item_Registry, players: []Player, index: int, just_pressed: Action_Set) {
	player := &players[index]
	block := selected_placed_block(player^, items)
	if .Place not_in just_pressed || !player.target.hit || block == AIR_BLOCK {
		return
	}
	if !placement_allowed(world, registry, players, player.target.adjacent) {
		return
	}
	if world_set_block(world, player.target.adjacent, block) {
		take_from_slot(&inventory_hotbar(player.inventory)[player.selected_hotbar_slot], 1)
	}
}

// Steps through the hotbar slots, wrapping, empty slots included.
cycle_hotbar_slot :: proc(selected: int, just_pressed: Action_Set) -> int {
	result := selected
	if .Hotbar_Next in just_pressed {
		result += 1
	}
	if .Hotbar_Previous in just_pressed {
		result -= 1
	}
	return (result % HOTBAR_SLOT_COUNT + HOTBAR_SLOT_COUNT) % HOTBAR_SLOT_COUNT
}
