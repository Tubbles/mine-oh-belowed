package game

import "core:math"

// Hand mining, placing and the selected block. Progress counts whole ticks,
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

mine_with_player :: proc(world: ^World, registry: Block_Registry, player: ^Player, holding: bool, tick_rate: int) {
	block_id := world_get_block(world, player.target.block)
	required := required_ticks_for(registry, block_id, tick_rate)
	broken: bool
	player.mining, broken = advance_mining(player.mining, holding, player.target, block_id, required)
	if broken && world_set_block(world, player.target.block, AIR_BLOCK) {
		player.owned_blocks[block_id] += 1
		ensure_selected_block_owned(player)
	}
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

player_owns :: proc(player: Player, block_id: Block_Id) -> bool {
	return block_id != AIR_BLOCK && int(block_id) < len(player.owned_blocks) && player.owned_blocks[block_id] > 0
}

place_with_player :: proc(world: ^World, registry: Block_Registry, players: []Player, index: int, just_pressed: Action_Set) {
	player := &players[index]
	if .Place not_in just_pressed || !player.target.hit || !player_owns(player^, player.selected_block) {
		return
	}
	if !placement_allowed(world, registry, players, player.target.adjacent) {
		return
	}
	if world_set_block(world, player.target.adjacent, player.selected_block) {
		player.owned_blocks[player.selected_block] -= 1
		ensure_selected_block_owned(player)
	}
}

// The next owned block id after `from` in direction +1 or -1, wrapping,
// or air when nothing is owned. Air (id 0) is never selected.
next_owned_block :: proc(owned_blocks: []u32, from: Block_Id, direction: int) -> Block_Id {
	count := len(owned_blocks)
	for step in 1 ..= count {
		candidate := ((int(from) + direction * step) % count + count) % count
		if candidate != int(AIR_BLOCK) && owned_blocks[candidate] > 0 {
			return Block_Id(candidate)
		}
	}
	return AIR_BLOCK
}

// Keeps the selection on an owned block: the first block mined gets
// selected, and running out of one moves on to the next.
ensure_selected_block_owned :: proc(player: ^Player) {
	if !player_owns(player^, player.selected_block) {
		player.selected_block = next_owned_block(player.owned_blocks, player.selected_block, 1)
	}
}

cycle_selected_block :: proc(player: ^Player, just_pressed: Action_Set) {
	if .Hotbar_Next in just_pressed {
		player.selected_block = next_owned_block(player.owned_blocks, player.selected_block, 1)
	}
	if .Hotbar_Previous in just_pressed {
		player.selected_block = next_owned_block(player.owned_blocks, player.selected_block, -1)
	}
}
