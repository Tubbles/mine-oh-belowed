package game

import "core:math"

// Hand mining, placing and the selected hotbar slot. Progress counts whole ticks,
// so it stays integer like every accumulating simulation quantity. Entity
// placement and pick up are in entity_placement.odin.

// The world's cell raycast (world_raycast.odin) with the occupant
// unpacked: the entity occupying the hit cell, or NO_ENTITY for a block.
Raycast_Hit :: struct {
	hit:      bool,
	block:    World_Coordinate,
	// The face of the hit block the ray entered through.
	face:     Direction,
	// The cell in front of that face, where a placed block goes.
	adjacent: World_Coordinate,
	distance: f32,
	entity:   Entity_Handle,
}

// Finds the first targetable block or entity cell along a normalised
// direction within reach (raycast_cells).
raycast_blocks :: proc(world: ^World, registry: Block_Registry, origin, direction: [3]f32, reach: f32) -> Raycast_Hit {
	hit := raycast_cells(world, registry, origin, direction, reach)
	entity := NO_ENTITY
	if hit.occupant != NO_OCCUPANT {
		entity = entity_from_occupant(hit.occupant)
	}
	return Raycast_Hit{hit = hit.hit, block = hit.block, face = hit.face, adjacent = hit.adjacent, distance = hit.distance, entity = entity}
}

// block is the mined cell, or the entity's origin while picking up an
// entity, or a tree's key while felling it on the field (tree, 0197).
Mining_State :: struct {
	active:         bool,
	block:          World_Coordinate,
	block_id:       Block_Id,
	entity:         Entity_Handle,
	progress_ticks: u32,
	required_ticks: u32,
	tree:           bool,
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
// full inventory is reported once for the block. A log fells the tree
// above it (tree_felling.odin).
mine_block :: proc(world: ^World, records: ^Game_Records, registry: Block_Registry, items: Item_Registry, felling: Tree_Felling, player: ^Player, holding: bool, tick_rate: int, cheat_speed: bool) -> Player_Events {
	block_id := world_get_block(world, player.target.block)
	if holding && player.target.hit {
		record_mining_tick(&records.statistics, block_id)
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
	record_block_mined(&records.statistics)
	if block_is_tree_log(felling.blocks, block_id) {
		fell_tree(world, &records.leaf_decay, registry, felling, player.target.block)
	}
	drop_unsupported_cover(world, registry, items, player.target.block + UP)
	spilled := false
	for drop in block_drop_stacks(items, block_id) {
		if leftover := inventory_add_picked_up(player.inventory, items, drop.item, 1); leftover > 0 {
			spill_stack(world, registry, player.target.block, Item_Stack{item = drop.item, count = u16(leftover)})
			spilled = true
		}
	}
	return spilled ? {.Inventory_Full} : {}
}

// Ground cover stands on the block below it (work item 0082): with that
// block mined, the cover in cell turns to air and spills its item there.
drop_unsupported_cover :: proc(world: ^World, registry: Block_Registry, items: Item_Registry, cell: World_Coordinate) {
	cover := world_get_block(world, cell)
	if block_shape(registry, cover) != .Cross {
		return
	}
	world_set_block(world, cell, AIR_BLOCK)
	for drop in block_drop_stacks(items, cover) {
		spill_stack(world, registry, cell, drop)
	}
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
mine_entity :: proc(world: ^World, statistics: ^Statistics, content: Simulation_Content, player: ^Player, holding: bool, tick_rate: int, tick: u64) -> Player_Events {
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
	spills := !inventory_fits_all_picked_up(player.inventory, content.items, entity_pickup_stacks(world, content, player.target.entity))
	if !pick_up_entity(world, statistics, content, player, player.target.entity, tick) || !spills {
		return {}
	}
	return {.Inventory_Full}
}

// cheat_speed shortens digging blocks, not picking up entities. An
// outcrop block mined away is checked for the spent outcrop (work item
// 0096).
mine_with_player :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, player: ^Player, holding: bool, tick_rate: int, tick: u64, cheat_speed: bool) -> Player_Events {
	if player.target.entity != NO_ENTITY {
		return mine_entity(world, &records.statistics, content, player, holding, tick_rate, tick)
	}
	cell := player.target.block
	vein, on_outcrop := registered_outcrop_vein_at(world, content.veins, cell)
	events := mine_block(world, records, content.blocks, content.items, simulation_tree_felling(content), player, holding, tick_rate, cheat_speed)
	if on_outcrop {
		note_outcrop_block_gone(world, records, content.veins, cell, vein)
	}
	return events
}

// Once the cell holds no outcrop block any more and it was the vein's
// last, the vein becomes known and Mission Control says so, once per
// vein (record_spent_outcrop, announce_spent_outcrops).
note_outcrop_block_gone :: proc(world: ^World, records: ^Game_Records, veins: Vein_Content, cell: World_Coordinate, vein: Vein_Id) {
	if _, still_outcrop := registered_outcrop_vein_at(world, veins, cell); still_outcrop {
		return
	}
	if outcrop_spent_with_units_left(world, veins, vein) {
		record_spent_outcrop(world, records, vein)
	}
}

// A block may go into a cell that is not solid (air, water, ground
// cover), holds no entity and that no player's body overlaps.
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

// The selected hotbar slot holds what Rotate_Building turns before it is
// placed (place_with_player): a machine or a stairs block.
selected_placement_rotates :: proc(player: Player, machines: Machine_Registry, blocks: Block_Registry, items: Item_Registry) -> bool {
	return selected_placed_machine(player, machines) != NO_MACHINE || block_shape(blocks, selected_placed_block(player, items)) == .Stairs
}

// pressed is the held state, for dragging belts.
place_with_player :: proc(world: ^World, statistics: ^Statistics, content: Simulation_Content, players: []Player, index: int, just_pressed: Action_Set, pressed := Action_Set{}) {
	if selected_placed_machine(players[index], content.machines) != NO_MACHINE {
		record_drill_no_vein_attempt(world, statistics, content, players, index, just_pressed)
		place_entity_with_player(world, statistics, content, players, index, just_pressed, pressed)
		return
	}
	players[index].belt_drag = {}
	if .Rotate_Building in just_pressed && block_shape(content.blocks, selected_placed_block(players[index], content.items)) == .Stairs {
		players[index].placement_rotation = (players[index].placement_rotation + 1) % 4
		return
	}
	if .Rotate_Building in just_pressed && rotate_targeted_entity(world, statistics, content, &players[index]) {
		return
	}
	place_block_with_player(world, statistics, content.blocks, content.items, players, index, just_pressed)
}

// A pressed Place of a surface drill refused only because no vein lies
// under its footprint, which is otherwise valid (work item 0096, chapter
// 2's drill hint). Like bore_drill_no_vein_attempts it is counted on the
// press, not in placement_at, which runs every frame for the ghost.
record_drill_no_vein_attempt :: proc(world: ^World, statistics: ^Statistics, content: Simulation_Content, players: []Player, index: int, just_pressed: Action_Set) {
	machine := selected_placed_machine(players[index], content.machines)
	if .Place not_in just_pressed || content.machines.machines[machine].kind != .Drill || drill_is_bore(content.machines.machines[machine]) {
		return
	}
	placement := placement_for_player(world, content, players, index)
	if !placement.shown || placement.valid {
		return
	}
	cells := footprint_cells(placement.origin, content.machines.machines[machine].footprint, placement.rotation)
	if footprint_is_valid(world, content.blocks, players, cells, placement.origin.y) {
		statistics.drill_no_vein_attempts += 1
	}
}

place_block_with_player :: proc(world: ^World, statistics: ^Statistics, registry: Block_Registry, items: Item_Registry, players: []Player, index: int, just_pressed: Action_Set) {
	player := &players[index]
	block := selected_placed_block(player^, items)
	if .Place not_in just_pressed || !player.target.hit || block == AIR_BLOCK {
		return
	}
	target := placement_target(registry, world_get_block(world, player.target.block), player.target)
	if !placement_allowed(world, registry, players, target.adjacent) {
		return
	}
	item := selected_hotbar_stack(player^).item
	hit_point := player_eye(player.position) + player.target_direction * player.target.distance
	block = placed_block_variant(registry, block, target, hit_point, player.yaw, player.placement_rotation)
	if world_set_block(world, target.adjacent, block) {
		take_from_slot(&inventory_hotbar(player.inventory)[player.selected_hotbar_slot], 1)
		record_block_placed(statistics, item)
	}
}

// The target a placement goes by: aimed at ground cover (work item 0082),
// whose bounds fill its cell, the placement takes the cover's own cell and
// replaces the cover; otherwise the cell in front of the targeted face.
// targeted is the block in target.block.
placement_target :: proc(registry: Block_Registry, targeted: Block_Id, target: Raycast_Hit) -> Raycast_Hit {
	if block_shape(registry, targeted) != .Cross {
		return target
	}
	replaced := target
	replaced.adjacent = target.block
	return replaced
}

// A slab goes into the upper half of its cell when placed against the
// underside of a block or high up on a side face, else into the lower
// half.
slab_goes_upper :: proc(target: Raycast_Hit, hit_point: [3]f32) -> bool {
	if target.face == .Negative_Y {
		return true
	}
	return direction_axis(target.face) != 1 && hit_point.y - f32(target.adjacent.y) > 0.5
}

// The variant of block the player places at target: the slab half from
// where the ray hit, stairs rising away from the player (yaw_direction)
// and turned by Rotate_Building (rotation). Any other block is itself.
placed_block_variant :: proc(registry: Block_Registry, block: Block_Id, target: Raycast_Hit, hit_point: [3]f32, yaw: f32, rotation: u8) -> Block_Id {
	#partial switch block_shape(registry, block) {
	case .Slab:
		return oriented_block(registry, block, Block_Orientation{upper = slab_goes_upper(target, hit_point)})
	case .Stairs:
		return oriented_block(registry, block, Block_Orientation{rotation = turn_right(yaw_direction(yaw), rotation % 4)})
	}
	return block
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
