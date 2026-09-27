package game

import "core:math"

// Hand mining, placing and the selected hotbar slot. Progress counts whole ticks,
// so it stays integer like every accumulating simulation quantity. Entity
// placement and pick up are in entity_placement.odin.

// block is the mined cell, or the entity's origin while picking up an
// entity.
Mining_State :: struct {
	active:         bool,
	block:          World_Coordinate,
	block_id:       Block_Id,
	entity:         Entity_Handle,
	progress_ticks: u32,
	required_ticks: u32,
}

// Holding Mine this long on an entity picks it up.
PICK_UP_SECONDS :: 0.6

// At least one tick, so a very soft block still takes a press.
mining_required_ticks :: proc(hardness_seconds: f32, tick_rate: int) -> u32 {
	return max(u32(math.round(hardness_seconds * f32(tick_rate))), 1)
}

// The developer cheat speed (0044) divides hand mining ticks.
CHEAT_MINING_TICK_DIVISOR :: 10

// A tenth of the ticks, at least one, under cheat speed. Zero (a block
// that cannot be mined) stays zero.
cheat_mining_ticks :: proc(required_ticks: u32, cheat_speed: bool) -> u32 {
	if !cheat_speed || required_ticks == 0 {
		return required_ticks
	}
	return max(required_ticks / CHEAT_MINING_TICK_DIVISOR, 1)
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

// Zero, so digging never starts, for a block that cannot be mined or
// whose tool_tier is above the player's best pickaxe (work item 0051).
required_ticks_for :: proc(registry: Block_Registry, block_id: Block_Id, tool_tier: int, tick_rate: int) -> u32 {
	if !block_is_minable(registry, block_id) || block_tool_tier(registry, block_id) > tool_tier {
		return 0
	}
	return mining_required_ticks(registry.definitions[block_id].hardness_seconds, tick_rate)
}

// The tier hand mining works with: the best pickaxe carried, or every tier
// under the developer cheat speed (0044), which is for reaching a game
// state fast.
effective_tool_tier :: proc(player: Player, items: Item_Registry, cheat_speed: bool) -> int {
	return cheat_speed ? highest_tool_tier(items.items) : player_tool_tier(player, items)
}

// The best tool_tier in the inventory or on the cursor, 0 for bare hands.
// Any slot counts, so the pickaxe need not be selected.
player_tool_tier :: proc(player: Player, items: Item_Registry) -> int {
	tier := stack_tool_tier(player.held.stack, items)
	for stack in player.inventory.slots {
		tier = max(tier, stack_tool_tier(stack, items))
	}
	return tier
}

stack_tool_tier :: proc(stack: Item_Stack, items: Item_Registry) -> int {
	if stack_is_empty(stack) || int(stack.item) >= len(items.items) {
		return 0
	}
	return items.items[stack.item].tool_tier
}

// The HUD line naming the tool the block needs, or empty when the player
// can mine it or nothing can.
mining_tool_line :: proc(blocks: Block_Registry, items: Item_Registry, block: Block_Id, tool_tier: int) -> string {
	needed := block_tool_tier(blocks, block)
	if !block_is_minable(blocks, block) || needed <= tool_tier {
		return ""
	}
	return format_message_text(text("mining_needs_tool"), item_name(items, tool_item_for_tier(items, needed)))
}

// The block's items go into the inventory, hotbar first: its drop and an
// extra drop (gold quartz gives quartz and gold ore). What does not fit
// spills at the block's cell as loose items (loose_item.odin), and the
// full inventory is reported once for the block.
mine_block :: proc(world: ^World, registry: Block_Registry, items: Item_Registry, player: ^Player, holding: bool, tick_rate: int, cheat_speed: bool) -> Player_Events {
	block_id := world_get_block(world, player.target.block)
	if holding && player.target.hit {
		record_mining_tick(&world.statistics, block_id)
	}
	next, finished := advance_mining(player.mining, holding, player.target, block_id, cheat_mining_ticks(required_ticks_for(registry, block_id, effective_tool_tier(player^, items, cheat_speed), tick_rate), cheat_speed))
	if !finished {
		player.mining = next
		return {}
	}
	player.mining = {}
	if !world_set_block(world, player.target.block, AIR_BLOCK) {
		return {}
	}
	record_block_mined(&world.statistics)
	spilled := false
	for drop in block_drop_stacks(items, block_id) {
		if leftover := inventory_add(player.inventory, items, drop.item, 1); leftover > 0 {
			spill_stack(world, registry, player.target.block, Item_Stack{item = drop.item, count = u16(leftover)})
			spilled = true
		}
	}
	return spilled ? {.Inventory_Full} : {}
}

// One of each item mining the block yields, in the temp allocator.
block_drop_stacks :: proc(items: Item_Registry, block: Block_Id) -> []Item_Stack {
	stacks := make([dynamic]Item_Stack, 0, 2, context.temp_allocator)
	for drop in ([2]Item_Id{block_drop(items, block), block_extra_drop(items, block)}) {
		if drop != NO_ITEM {
			append(&stacks, Item_Stack{item = drop, count = 1})
		}
	}
	return stacks[:]
}

// A long press of Mine on an entity picks it up with its contents; what
// does not fit spills (pick_up_entity) and reports the full inventory.
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
	player.mining = {}
	spills := !inventory_fits_all(player.inventory, content.items, entity_pickup_stacks(world, content, player.target.entity))
	if !pick_up_entity(world, content, player, player.target.entity) || !spills {
		return {}
	}
	return {.Inventory_Full}
}

// cheat_speed shortens digging blocks, not picking up entities.
mine_with_player :: proc(world: ^World, content: Simulation_Content, player: ^Player, holding: bool, tick_rate: int, cheat_speed: bool) -> Player_Events {
	if player.target.entity != NO_ENTITY {
		return mine_entity(world, content, player, holding, tick_rate)
	}
	return mine_block(world, content.blocks, content.items, player, holding, tick_rate, cheat_speed)
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
	item := selected_hotbar_stack(player^).item
	if world_set_block(world, player.target.adjacent, block) {
		take_from_slot(&inventory_hotbar(player.inventory)[player.selected_hotbar_slot], 1)
		record_block_placed(&world.statistics, item)
	}
}

HOTBAR_SLOT_ACTIONS :: [HOTBAR_SLOT_COUNT]Action{.Hotbar_Slot_1, .Hotbar_Slot_2, .Hotbar_Slot_3, .Hotbar_Slot_4, .Hotbar_Slot_5, .Hotbar_Slot_6, .Hotbar_Slot_7, .Hotbar_Slot_8}

// A number key selects its slot directly; otherwise steps through the
// hotbar slots, wrapping, empty slots included.
cycle_hotbar_slot :: proc(selected: int, just_pressed: Action_Set) -> int {
	slot_actions := HOTBAR_SLOT_ACTIONS
	for action, slot in slot_actions {
		if action in just_pressed {
			return slot
		}
	}
	result := selected
	if .Hotbar_Next in just_pressed {
		result += 1
	}
	if .Hotbar_Previous in just_pressed {
		result -= 1
	}
	return (result % HOTBAR_SLOT_COUNT + HOTBAR_SLOT_COUNT) % HOTBAR_SLOT_COUNT
}
