package game

import "core:math"

// Hand mining, placing and the selected hotbar slot. Progress counts whole ticks,
// so it stays integer like every accumulating simulation quantity. Entity
// placement and pick up are in entity_placement.odin.

// block is the mined cell, or the entity's origin while picking up an
// entity. refused is set once a finished dig could not go into the
// inventory, so the toast shows once and progress stays full.
Mining_State :: struct {
	active:         bool,
	block:          World_Coordinate,
	block_id:       Block_Id,
	entity:         Entity_Handle,
	progress_ticks: u32,
	required_ticks: u32,
	refused:        bool,
}

// Holding Mine this long on an entity picks it up.
PICK_UP_SECONDS :: 0.6

// At least one tick, so a very soft block still takes a press.
mining_required_ticks :: proc(hardness_seconds: f32, tick_rate: int) -> u32 {
	return max(u32(math.round(hardness_seconds * f32(tick_rate))), 1)
}

// Progress starts over whenever the button is up or the target changes,
// including a different block appearing at the same position. It stops at
// the required ticks, where the dig is finished; the caller clears it once
// the block is broken.
advance_mining :: proc(state: Mining_State, holding: bool, target: Raycast_Hit, block_id: Block_Id, required_ticks: u32) -> (next: Mining_State, finished: bool) {
	if !holding || !target.hit || required_ticks == 0 {
		return {}, false
	}
	next = state
	if !state.active || state.block != target.block || state.block_id != block_id || state.entity != target.entity {
		next = Mining_State{active = true, block = target.block, block_id = block_id, entity = target.entity, required_ticks = required_ticks}
	}
	next.progress_ticks = min(next.progress_ticks + 1, next.required_ticks)
	return next, next.progress_ticks >= next.required_ticks
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

// A finished dig whose result does not fit keeps its full progress and
// reports the full inventory once, so freeing a slot lets it finish.
refuse_mining :: proc(player: ^Player, next: Mining_State) -> Player_Events {
	already_refused := player.mining.refused && player.mining.active && player.mining.block == next.block && player.mining.entity == next.entity
	player.mining = next
	player.mining.refused = true
	return already_refused ? {} : {.Inventory_Full}
}

// The block's item goes into the inventory, hotbar first. A block whose
// item does not fit is not broken.
mine_block :: proc(world: ^World, registry: Block_Registry, items: Item_Registry, player: ^Player, holding: bool, tick_rate: int) -> Player_Events {
	block_id := world_get_block(world, player.target.block)
	if holding && player.target.hit {
		record_mining_tick(&world.statistics, block_id)
	}
	next, finished := advance_mining(player.mining, holding, player.target, block_id, required_ticks_for(registry, block_id, tick_rate))
	if !finished {
		player.mining = next
		return {}
	}
	drop := block_drop(items, block_id)
	if drop != NO_ITEM && !inventory_fits_all(player.inventory, items, {Item_Stack{item = drop, count = 1}}) {
		return refuse_mining(player, next)
	}
	player.mining = {}
	if !world_set_block(world, player.target.block, AIR_BLOCK) {
		return {}
	}
	record_block_mined(&world.statistics)
	if drop != NO_ITEM {
		inventory_add(player.inventory, items, drop, 1)
	}
	return {}
}

// A long press of Mine on an entity picks it up with its contents.
mine_entity :: proc(world: ^World, content: Simulation_Content, player: ^Player, holding: bool, tick_rate: int) -> Player_Events {
	if !entity_can_be_picked_up(world, content.machines, player.target.entity) {
		player.mining = {}
		return {}
	}
	common := entity_common(&world.entities, player.target.entity)
	target := player.target
	target.block = common.origin
	next, finished := advance_mining(player.mining, holding, target, AIR_BLOCK, mining_required_ticks(PICK_UP_SECONDS, tick_rate))
	if !finished {
		player.mining = next
		return {}
	}
	if !pick_up_entity(world, content, player, player.target.entity) {
		return refuse_mining(player, next)
	}
	player.mining = {}
	return {}
}

mine_with_player :: proc(world: ^World, content: Simulation_Content, player: ^Player, holding: bool, tick_rate: int) -> Player_Events {
	if player.target.entity != NO_ENTITY {
		return mine_entity(world, content, player, holding, tick_rate)
	}
	return mine_block(world, content.blocks, content.items, player, holding, tick_rate)
}

// A block may go into a cell that is not solid, holds no entity and that
// no player's body overlaps.
placement_allowed :: proc(world: ^World, registry: Block_Registry, players: []Player, cell: World_Coordinate) -> bool {
	if cell_is_solid_or_entity(world, registry, cell) {
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

// pressed is the held state, for dragging belts.
place_with_player :: proc(world: ^World, content: Simulation_Content, players: []Player, index: int, just_pressed: Action_Set, pressed := Action_Set{}) {
	if selected_placed_machine(players[index], content.machines) != NO_MACHINE {
		place_entity_with_player(world, content, players, index, just_pressed, pressed)
		return
	}
	players[index].belt_drag = {}
	if .Rotate_Building in just_pressed && rotate_targeted_entity(world, content, &players[index]) {
		return
	}
	place_block_with_player(world, content.blocks, content.items, players, index, just_pressed)
}

place_block_with_player :: proc(world: ^World, registry: Block_Registry, items: Item_Registry, players: []Player, index: int, just_pressed: Action_Set) {
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
		record_world_action(&world.statistics)
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
