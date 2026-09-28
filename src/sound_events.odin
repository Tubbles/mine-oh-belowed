package game

import "core:fmt"
import "core:math"
import "core:math/linalg"

// What makes a sound (work item 0068): the frame's changes against the
// last frame's memory, the nearest working machine for the hum, and the
// biome and the weather for the ambience. Selection and the detectors are
// pure; play_frame_sounds reads the world, the mixer (audio.odin) plays.
// The memory is render state in Frame_State, reset with the session, and
// the first frame of a session only learns the counters, so a loaded
// world neither steps nor chimes.
//
// The sparse rule (DESIGN.md): nothing plays continuously but the biome
// ambience, the rain and one hum; effects are short and never layered
// beyond the mixer's gap rule.

// A step's pitch lies between these, from a hash of the step count.
FOOTSTEP_PITCH_MINIMUM :: 0.9
FOOTSTEP_PITCH_MAXIMUM :: 1.1
// The hum of the nearest working machine this close to the eye, falling
// to silence at the edge.
HUM_RANGE_BLOCKS :: 12.0
MINING_HIT_SOUND_PREFIX :: "mine_hit_"
FOOTSTEP_SOUND_PREFIX :: "footstep_"
AMBIENCE_SOUND_PREFIX :: "ambience_"
BLOCK_BREAK_SOUND :: "block_break"
BLOCK_PLACE_SOUND :: "block_place"
RAIN_SOUND :: "rain"
ROCKET_LAUNCH_SOUND :: "rocket_launch"
CAPSULE_LANDING_SOUND :: "capsule_landing"
DISCOVERY_SOUND :: "discovery_chime"

// A dig in quarters: 1 to 3 are the hits, 4 the break.
Mining_Sound_Memory :: struct {
	active:  bool,
	block:   World_Coordinate,
	entity:  Entity_Handle,
	quarter: int,
}

Sound_Memory :: struct {
	known:                bool,
	tick:                 u64,
	distance_millimetres: u64,
	step_count:           u64,
	placed_total:         u64,
	blocks_mined:         u64,
	mining:               Mining_Sound_Memory,
	launching_count:      int,
	descent_active:       bool,
	message_count:        int,
}

// What the frame reads from the world, for advance_sound_memory.
Sound_Observation :: struct {
	tick:                 u64,
	distance_millimetres: u64,
	placed_total:         u64,
	blocks_mined:         u64,
	mining:               Mining_Sound_Memory,
	launching_count:      int,
	descent_active:       bool,
	message_count:        int,
	// A message since the memory's count is a discovery.
	discovered:           bool,
}

// The effects the frame's changes ask for.
Sound_Cues :: struct {
	footstep:    bool,
	mining_hit:  bool,
	block_break: bool,
	block_place: bool,
	launch:      bool,
	landing:     bool,
	discovery:   bool,
}

Hum_Family :: enum u8 {
	Burner,
	Electric,
	Fluid,
}

@(rodata)
hum_sound_ids := [Hum_Family]string {
	.Burner   = "hum_burner",
	.Electric = "hum_electric",
	.Fluid    = "hum_fluid",
}

Hum_Source :: struct {
	position: [3]f32,
	family:   Hum_Family,
}

// Selection.

footstep_sound_id :: proc(material: string) -> string {
	return fmt.tprintf("%s%s", FOOTSTEP_SOUND_PREFIX, material)
}

// Empty for a biome without ambience.
ambience_sound_id :: proc(ambience: string) -> string {
	if ambience == "" {
		return ""
	}
	return fmt.tprintf("%s%s", AMBIENCE_SOUND_PREFIX, ambience)
}

biome_ambience_sound_id :: proc(biomes: []Biome, biome: int) -> string {
	if biome < 0 || biome >= len(biomes) {
		return ""
	}
	return ambience_sound_id(biomes[biome].definition.ambience)
}

// The highest mine_hit_<tier> listed at or below the tier, empty without
// one.
mining_hit_sound_id :: proc(table: Sound_Table, tool_tier: int) -> string {
	for tier := tool_tier; tier >= 0; tier -= 1 {
		if id := fmt.tprintf("%s%d", MINING_HIT_SOUND_PREFIX, tier); sound_listed(table, id) {
			return id
		}
	}
	return ""
}

// Wading, the water the feet stand in; else the block under them.
footstep_material :: proc(blocks: Block_Registry, feet, under: Block_Id) -> string {
	if int(feet) < len(blocks.definitions) && blocks.definitions[feet].water_level > 0 {
		return block_sound_material(blocks, feet)
	}
	return block_sound_material(blocks, under)
}

footstep_pitch :: proc(step_count: u64) -> f32 {
	hash := step_count * 0x9E3779B97F4A7C15
	hash ~= hash >> 29
	fraction := f32(hash % 1024) / 1023
	return FOOTSTEP_PITCH_MINIMUM + fraction * (FOOTSTEP_PITCH_MAXIMUM - FOOTSTEP_PITCH_MINIMUM)
}

// Fluid machines hum as fluid machines; the others by what drives them.
machine_hum_family :: proc(machine: Machine, fluid: bool) -> Hum_Family {
	if fluid {
		return .Fluid
	}
	return machine.electric_power_watts > 0 ? .Electric : .Burner
}

// Loudest at the eye, silent at HUM_RANGE_BLOCKS and beyond.
hum_volume :: proc(distance: f32) -> f32 {
	return clamp(1 - distance / HUM_RANGE_BLOCKS, 0, 1)
}

// The nearest source within HUM_RANGE_BLOCKS of the eye.
nearest_hum_source :: proc(sources: []Hum_Source, eye: [3]f32) -> (nearest: Hum_Source, distance: f32, found: bool) {
	distance = HUM_RANGE_BLOCKS
	for source in sources {
		if source_distance := linalg.distance(source.position, eye); source_distance < distance {
			nearest, distance, found = source, source_distance, true
		}
	}
	return nearest, distance, found
}

// Rain alone, as heavy as it falls and as open as the sky is; snow is
// silent.
rain_volume :: proc(precipitation: Precipitation, intensity, open_sky: f32) -> f32 {
	if precipitation != .Rain {
		return 0
	}
	return clamp(intensity * open_sky, 0, 1)
}

// Detectors.

mining_quarter :: proc(state: Mining_State) -> int {
	return clamp(int(mining_fraction(state) * 4), 0, 4)
}

mining_sound_memory_of :: proc(state: Mining_State) -> Mining_Sound_Memory {
	if !state.active {
		return {}
	}
	return Mining_Sound_Memory{active = true, block = state.block, entity = state.entity, quarter = mining_quarter(state)}
}

// The same dig crossed into quarter 1, 2 or 3 since the last frame; the
// fourth is the break, which has a sound of its own.
mining_hit_due :: proc(previous, current: Mining_Sound_Memory) -> bool {
	same_dig := previous.active && current.active && previous.block == current.block && previous.entity == current.entity
	return same_dig && current.quarter > previous.quarter && current.quarter < 4
}

// A new message since the count that is a discovery.
discovery_since :: proc(messages: []Quest_Message, count: int) -> bool {
	for message in messages[min(count, len(messages)):] {
		if message.text_key == ITEM_DISCOVERED_KEY {
			return true
		}
	}
	return false
}

// The step follows the walked distance at tick granularity, like the
// animation (advance_player_animation_memory).
advance_sound_memory :: proc(memory: Sound_Memory, observation: Sound_Observation) -> (next: Sound_Memory, cues: Sound_Cues) {
	next = Sound_Memory {
		known                = true,
		tick                 = observation.tick,
		distance_millimetres = observation.distance_millimetres,
		step_count           = memory.step_count,
		placed_total         = observation.placed_total,
		blocks_mined         = observation.blocks_mined,
		mining               = observation.mining,
		launching_count      = observation.launching_count,
		descent_active       = observation.descent_active,
		message_count        = observation.message_count,
	}
	if !memory.known {
		return next, {}
	}
	if observation.tick != memory.tick {
		cues.footstep = footstep_due(memory.distance_millimetres, observation.distance_millimetres)
	} else {
		next.distance_millimetres = memory.distance_millimetres
	}
	if cues.footstep {
		next.step_count += 1
	}
	cues.mining_hit = mining_hit_due(memory.mining, observation.mining)
	cues.block_break = observation.blocks_mined > memory.blocks_mined
	cues.block_place = observation.placed_total > memory.placed_total
	cues.launch = observation.launching_count > memory.launching_count
	cues.landing = memory.descent_active && !observation.descent_active
	cues.discovery = observation.discovered
	return next, cues
}

// Reading the world.

launching_pad_count :: proc(world: ^World) -> int {
	count := 0
	for pad in world.entities.launch_pads.entries {
		if pad.alive && pad.state == .Launching {
			count += 1
		}
	}
	return count
}

observe_sounds :: proc(memory: Sound_Memory, world: ^World, player: Player, tick: u64, quests: ^Quest_State, particle_memory: Particle_Memory) -> Sound_Observation {
	return Sound_Observation {
		tick = tick,
		distance_millimetres = world.statistics.distance_walked_millimetres,
		placed_total = placed_total(world.statistics),
		blocks_mined = world.statistics.blocks_mined,
		mining = mining_sound_memory_of(player.mining),
		launching_count = launching_pad_count(world),
		descent_active = particle_memory.descent.active,
		message_count = len(quests.messages),
		discovered = discovery_since(quests.messages[:], memory.message_count),
	}
}

append_hum_source :: proc(sources: ^[dynamic]Hum_Source, common: Entity_Common, machines: Machine_Registry, working, fluid: bool) {
	if working {
		append(sources, Hum_Source{position = box_centre(common.origin, common.size), family = machine_hum_family(machines.machines[common.machine], fluid)})
	}
}

// Working as the bottleneck markers define it, in the temp allocator.
working_hum_sources :: proc(world: ^World, machines: Machine_Registry) -> []Hum_Source {
	sources := make([dynamic]Hum_Source, context.temp_allocator)
	entities := &world.entities
	for furnace in entities.furnaces.entries {
		if furnace.alive {
			append_hum_source(&sources, furnace.common, machines, marker_means_working(machine_marker_colour(furnace.state, furnace_has_fuel(furnace))), false)
		}
	}
	for assembler in entities.assemblers.entries {
		if assembler.alive {
			append_hum_source(&sources, assembler.common, machines, marker_means_working(machine_marker_colour(assembler.state, true)), false)
		}
	}
	for drill in entities.drills.entries {
		if drill.alive {
			append_hum_source(&sources, drill.common, machines, marker_means_working(machine_marker_colour(drill.state, true)), false)
		}
	}
	for lab in entities.labs.entries {
		if lab.alive {
			append_hum_source(&sources, lab.common, machines, marker_means_working(machine_marker_colour(lab.state, true)), false)
		}
	}
	for fluid_machine in entities.fluid_machines.entries {
		if fluid_machine.alive && fluid_machine_has_marker(machines.machines[fluid_machine.machine].kind) {
			append_hum_source(&sources, fluid_machine.common, machines, marker_means_working(machine_marker_colour(fluid_machine.state, true)), true)
		}
	}
	return sources[:]
}

// What play_frame_sounds reads.
Sound_Frame :: struct {
	world:           ^World,
	content:         Simulation_Content,
	generator:       ^Generator,
	player:          Player,
	tick:            u64,
	quests:          ^Quest_State,
	particle_memory: Particle_Memory,
	weather:         Weather,
	cheat_speed:     bool,
}

// Once a frame in a session, after the particles.
play_frame_sounds :: proc(mixer: ^Audio_Mixer, memory: ^Sound_Memory, frame: Sound_Frame) {
	cues: Sound_Cues
	memory^, cues = advance_sound_memory(memory^, observe_sounds(memory^, frame.world, frame.player, frame.tick, frame.quests, frame.particle_memory))
	play_sound_cues(mixer, memory^, cues, frame)
	eye := player_eye(frame.player.position)
	set_hum_target(mixer, frame, eye)
	set_ambience_targets(mixer, frame, eye)
}

play_sound_cues :: proc(mixer: ^Audio_Mixer, memory: Sound_Memory, cues: Sound_Cues, frame: Sound_Frame) {
	player, blocks := frame.player, frame.content.blocks
	if cues.footstep {
		feet := world_get_block(frame.world, camera_world_coordinate(player.position + {0, COLLISION_EPSILON, 0}))
		under := world_get_block(frame.world, camera_world_coordinate(player.position - {0, COLLISION_EPSILON, 0}))
		wading := int(feet) < len(blocks.definitions) && blocks.definitions[feet].water_level > 0
		if player.on_ground || wading {
			play_effect(mixer, footstep_sound_id(footstep_material(blocks, feet, under)), 1, footstep_pitch(memory.step_count))
		}
	}
	if cues.mining_hit {
		play_effect(mixer, mining_hit_sound_id(mixer.table, effective_tool_tier(player, frame.content.items, frame.cheat_speed)))
	}
	if cues.block_break {
		play_effect(mixer, BLOCK_BREAK_SOUND)
	}
	if cues.block_place {
		play_effect(mixer, BLOCK_PLACE_SOUND)
	}
	if cues.launch {
		play_effect(mixer, ROCKET_LAUNCH_SOUND)
	}
	if cues.landing {
		play_effect(mixer, CAPSULE_LANDING_SOUND)
	}
	if cues.discovery {
		play_effect(mixer, DISCOVERY_SOUND)
	}
}

set_hum_target :: proc(mixer: ^Audio_Mixer, frame: Sound_Frame, eye: [3]f32) {
	if source, distance, found := nearest_hum_source(working_hum_sources(frame.world, frame.content.machines), eye); found {
		set_loop_target(mixer, hum_sound_ids[source.family], hum_volume(distance))
	}
}

// The biome under the player, as the banner samples it, and the rain at
// the eye, as the weather draws it.
set_ambience_targets :: proc(mixer: ^Audio_Mixer, frame: Sound_Frame, eye: [3]f32) {
	generator := frame.generator
	position := frame.player.position
	biome := sample_column(generator, i32(math.floor(position.x)), i32(math.floor(position.z))).biome
	if id := biome_ambience_sound_id(generator.biomes, biome); id != "" {
		set_loop_target(mixer, id, 1)
	}
	cell := camera_world_coordinate(eye)
	temperature := terrain_temperature(generator.seeds, cell.x, cell.z, terrain_height(generator.seeds, cell.x, cell.z))
	open_sky := f32(light_level(world_get_light(frame.world, cell), .Sky)) / MAXIMUM_LIGHT
	set_loop_target(mixer, RAIN_SOUND, rain_volume(weather_precipitation(frame.weather, temperature), frame.weather.intensity, open_sky))
}

// The discovery card's chime is the one
// play_frame_sounds also asks for when the message is logged; both land in
// the same frame, so the mixer's gap rule plays it once.
@(rodata)
ui_sound_ids := [Ui_Sound_Event]string {
	.Move            = "ui_move",
	.Confirm         = "ui_confirm",
	.Back            = "ui_back",
	.Mission_Control = "mission_control_chime",
	.Discovery       = DISCOVERY_SOUND,
}

// The UI's sounds of the frame, drained.
play_ui_sounds :: proc(mixer: ^Audio_Mixer, ui: ^Ui_State) {
	for event in ui.sound_events {
		play_effect(mixer, ui_sound_ids[event])
	}
	ui.sound_events = {}
}
