package game

import "core:math"

// The frame's cues (work item 0162): one memory of the last frame's
// counters and one pure step, detect_cues, that turns this frame's
// counters into the events the player animation, the particles and the
// sounds react to. The counters are read once a frame by
// observe_cue_counters. The memory is render state in Frame_State, reset
// with the session, and the first frame of a session only learns the
// counters, so a loaded world neither steps, swings, chimes nor drops a
// capsule.
//
// The walk is followed at tick granularity: a frame without a new tick
// keeps the distance, the cadence and whether the player moves, so a
// display faster than the tick rate neither stops the walk nor steps
// twice. The cadence distance counts each tick's walk divided by the
// cheat speed factor (work item 0087), so cheat speed steps at the
// normal rate (DESIGN.md, no perceivable repetition).
//
// The landing is not a counter: the capsule descent a shipment starts
// ends in render time (render_particles.odin), and the frame adds it to
// the cues after the particles (draw_session_world).

// A dig past this fraction whose block is gone the next frame broke it.
DIG_BREAK_MINIMUM_FRACTION :: 0.5

Cue :: enum u8 {
	// The cadence distance crossed a half walk cycle.
	Footstep,
	// The placed counters (placed_total) grew.
	Place,
	// The blocks mined statistic grew.
	Block_Break,
	// The local player's block dig, past DIG_BREAK_MINIMUM_FRACTION last
	// frame, has its block gone.
	Dig_Break,
	// The same dig crossed into quarter 1, 2 or 3.
	Dig_Quarter,
	// More launch pads launching than last frame.
	Launch,
	// A new shipment in the records.
	Shipment,
	// A new item discovered message in the quest log.
	Discovery,
	// A new orbital survey message in the quest log.
	Survey,
	// The capsule descent ended (added after the particles).
	Landing,
}

// The frame's cues and what they carry.
Frame_Cues :: struct {
	fired:               bit_set[Cue],
	// The walk the animation's phase follows.
	cadence_millimetres: u64,
	moving:              bool,
	// Footstep: the blocks at and just under the feet.
	feet_block:          Block_Id,
	under_block:         Block_Id,
	// Dig_Break: the dug cell and the block it held.
	broken_cell:         World_Coordinate,
	broken_block:        Block_Id,
}

// What the frame reads from the simulation.
Cue_Counters :: struct {
	tick:                 u64,
	distance_millimetres: u64,
	cheat_speed:          bool,
	placed_total:         u64,
	blocks_mined:         u64,
	// The local player's dig, and the block now at the last frame's dig
	// cell.
	dig:                  Mining_State,
	block_at_last_dig:    Block_Id,
	feet_block:           Block_Id,
	under_block:          Block_Id,
	launching_count:      int,
	shipment_count:       int,
	messages:             []Quest_Message,
}

Cue_Memory :: struct {
	known:                bool,
	tick:                 u64,
	distance_millimetres: u64,
	cadence_millimetres:  u64,
	moving:               bool,
	placed_total:         u64,
	blocks_mined:         u64,
	dig:                  Mining_State,
	launching_count:      int,
	shipment_count:       int,
	message_count:        int,
}

// The cadence distance after a tick walked from previous_distance to
// distance: under cheat speed the tick's walk counts divided by the cheat
// speed factor, rounded like the statistics round a tick's walk.
advance_cadence_millimetres :: proc(cadence, previous_distance, distance: u64, cheat_speed: bool) -> u64 {
	if distance <= previous_distance {
		return cadence
	}
	return cadence + u64(math.round(f64(distance - previous_distance) / f64(cheat_speed_factor(cheat_speed))))
}

// A foot comes down each half cycle: true when the distance crossed one.
footstep_due :: proc(previous_millimetres, millimetres: u64) -> bool {
	half := u64(WALK_CYCLE_MILLIMETRES / 2)
	return millimetres / half > previous_millimetres / half
}

// Machines and blocks placed so far, by any player.
placed_total :: proc(statistics: Statistics) -> u64 {
	total: u64
	for count in statistics.placed {
		total += count
	}
	for count in statistics.blocks_placed {
		total += count
	}
	return total
}

// A dig in quarters: 1 to 3 are the hits, 4 the break.
mining_quarter :: proc(state: Mining_State) -> int {
	return clamp(int(mining_fraction(state) * 4), 0, 4)
}

// The same dig crossed into quarter 1, 2 or 3 since the last frame; the
// fourth is the break.
dig_quarter_crossed :: proc(previous, current: Mining_State) -> bool {
	same_dig := previous.active && current.active && previous.block == current.block && previous.entity == current.entity
	quarter := mining_quarter(current)
	return same_dig && quarter > mining_quarter(previous) && quarter < 4
}

// The block dig was past DIG_BREAK_MINIMUM_FRACTION last frame and its
// block is gone now; an entity pick up never breaks a block.
dig_broke_block :: proc(previous: Mining_State, block_now: Block_Id) -> bool {
	block_dig := previous.active && previous.entity == NO_ENTITY
	return block_dig && mining_fraction(previous) > DIG_BREAK_MINIMUM_FRACTION && block_now != previous.block_id
}

// A message with the key since the count.
quest_message_since :: proc(messages: []Quest_Message, count: int, text_key: string) -> bool {
	for message in messages[min(count, len(messages)):] {
		if message.text_key == text_key {
			return true
		}
	}
	return false
}

// The walk of a new tick; a frame without one keeps the memory's walk.
advance_walk :: proc(memory: Cue_Memory, counters: Cue_Counters) -> (next: Cue_Memory, footstep: bool) {
	next = memory
	if counters.tick == memory.tick {
		return next, false
	}
	next.moving = counters.distance_millimetres != memory.distance_millimetres
	next.cadence_millimetres = advance_cadence_millimetres(memory.cadence_millimetres, memory.distance_millimetres, counters.distance_millimetres, counters.cheat_speed)
	next.tick, next.distance_millimetres = counters.tick, counters.distance_millimetres
	return next, footstep_due(memory.cadence_millimetres, next.cadence_millimetres)
}

// The cues of the counters that only grow.
counter_cues :: proc(memory: Cue_Memory, counters: Cue_Counters) -> (fired: bit_set[Cue]) {
	if counters.placed_total > memory.placed_total {
		fired += {.Place}
	}
	if counters.blocks_mined > memory.blocks_mined {
		fired += {.Block_Break}
	}
	if counters.launching_count > memory.launching_count {
		fired += {.Launch}
	}
	if counters.shipment_count > memory.shipment_count {
		fired += {.Shipment}
	}
	if quest_message_since(counters.messages, memory.message_count, ITEM_DISCOVERED_KEY) {
		fired += {.Discovery}
	}
	if quest_message_since(counters.messages, memory.message_count, ORBITAL_SURVEY_KEY) {
		fired += {.Survey}
	}
	return fired
}

// The counters as the next frame compares against them; the walk is
// advance_walk's.
remember_counters :: proc(memory: Cue_Memory, counters: Cue_Counters) -> Cue_Memory {
	next := memory
	next.known = true
	next.placed_total, next.blocks_mined = counters.placed_total, counters.blocks_mined
	next.dig = counters.dig
	next.launching_count, next.shipment_count = counters.launching_count, counters.shipment_count
	next.message_count = len(counters.messages)
	return next
}

// The first frame of a session learns the counters and the walk.
first_cue_memory :: proc(counters: Cue_Counters) -> Cue_Memory {
	memory := remember_counters({}, counters)
	memory.tick, memory.distance_millimetres, memory.cadence_millimetres = counters.tick, counters.distance_millimetres, counters.distance_millimetres
	return memory
}

// Once a frame: the frame's cues from the counters against the last
// frame's memory, and the memory for the next frame.
detect_cues :: proc(memory: Cue_Memory, counters: Cue_Counters) -> (cues: Frame_Cues, next: Cue_Memory) {
	if !memory.known {
		next = first_cue_memory(counters)
		return Frame_Cues{cadence_millimetres = next.cadence_millimetres}, next
	}
	footstep: bool
	next, footstep = advance_walk(memory, counters)
	next = remember_counters(next, counters)
	cues = Frame_Cues {
		fired               = counter_cues(memory, counters),
		cadence_millimetres = next.cadence_millimetres,
		moving              = next.moving,
		feet_block          = counters.feet_block,
		under_block         = counters.under_block,
	}
	if footstep {
		cues.fired += {.Footstep}
	}
	if dig_quarter_crossed(memory.dig, counters.dig) {
		cues.fired += {.Dig_Quarter}
	}
	if dig_broke_block(memory.dig, counters.block_at_last_dig) {
		cues.fired += {.Dig_Break}
		cues.broken_cell, cues.broken_block = memory.dig.block, memory.dig.block_id
	}
	return cues, next
}

// Reading the simulation.

launching_pad_count :: proc(world: ^World) -> int {
	count := 0
	for pad in world.entities.launch_pads.entries {
		if pad.alive && pad.state == .Launching {
			count += 1
		}
	}
	return count
}

// The counters of the frame for the local player; the memory names the
// cell of the last frame's dig.
observe_cue_counters :: proc(memory: Cue_Memory, simulation: ^Simulation_State, local_player: int) -> Cue_Counters {
	world := &simulation.world
	player := simulation.players[local_player]
	statistics := simulation.records.statistics
	return Cue_Counters {
		tick = simulation.tick,
		distance_millimetres = statistics.distance_walked_millimetres,
		cheat_speed = simulation.cheat_speed,
		placed_total = placed_total(statistics),
		blocks_mined = statistics.blocks_mined,
		dig = player.mining,
		block_at_last_dig = world_get_block(world, memory.dig.block),
		feet_block = world_get_block(world, camera_world_coordinate(player.position + {0, COLLISION_EPSILON, 0})),
		under_block = world_get_block(world, camera_world_coordinate(player.position - {0, COLLISION_EPSILON, 0})),
		launching_count = launching_pad_count(world),
		shipment_count = len(simulation.records.shipments),
		messages = simulation.quests.messages[:],
	}
}
