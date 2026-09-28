package game

import "core:math"
import rl "shared:raylib"

// Particles and feedback (work item 0067): the emitters of a frame, read
// from the entity states and the players at render time, the memory of
// the last frame that turns a finished dig into a puff and a new shipment
// into a capsule descending under a parachute, a new orbital survey into
// the survey satellite's pass (work item 0069), and the drawing. The
// simulation never sees any of it. Selection, the memory and the descent
// path are pure procedures; only the disc upload and the draw calls touch
// raylib.

PARTICLE_DISC_SIZE :: 16
// Soft: the disc fades over a third of its radius.
PARTICLE_DISC_EDGE_TEXELS :: 3.0
FURNACE_SMOKE_RATE :: 6.0
BOILER_SMOKE_RATE :: 10.0
ENGINE_STEAM_RATE :: 12.0
GENERATOR_EXHAUST_RATE :: 4.0
FLARE_FLAME_RATE :: 30.0
ALLOY_SPARK_RATE :: 14.0
LAUNCH_EXHAUST_RATE :: 120.0
LAUNCH_SMOKE_RATE :: 40.0
// During the first quarter of the ascent the rates are this many times
// higher: the rocket still stands in its own cloud.
LAUNCH_EARLY_RATE_SCALE :: 3.0
LAUNCH_EARLY_SHARE :: 0.25
LAUNCH_SMOKE_SPREAD :: 3.0
// Debris per second at the start of a dig and added at its end.
DEBRIS_BASE_RATE :: 6.0
DEBRIS_FRACTION_RATE :: 18.0
// A dig past this fraction whose block is gone the next frame broke it.
BREAK_PUFF_MINIMUM_FRACTION :: 0.5
BREAK_PUFF_COUNT :: 24
BREAK_PUFF_SPREAD :: 0.4
// The capsule falls from this far above the landing capsule over this
// long, swaying sideways by up to CAPSULE_SWAY_BLOCKS.
CAPSULE_DESCENT_HEIGHT :: 60.0
CAPSULE_DESCENT_SECONDS :: 8.0
SATELLITE_PASS_SECONDS :: 6.0
CAPSULE_SWAY_BLOCKS :: 0.6
CAPSULE_SWAY_RATE :: 1.3
DESCENT_CAPSULE_SIZE :: 0.8
PARACHUTE_SIZE :: 2.6
PARACHUTE_HEIGHT :: 2.2
PARACHUTE_COLOR :: rl.Color{235, 120, 60, 255}
PARACHUTE_CORD_COLOR :: rl.Color{220, 220, 220, 255}
LANDING_PUFF_COLOR :: [4]u8{170, 160, 140, 220}
SMOKE_COLOR :: [4]u8{70, 70, 74, 190}
STEAM_COLOR :: [4]u8{235, 238, 242, 160}
GENERATOR_EXHAUST_COLOR :: [4]u8{120, 118, 115, 110}
FLARE_FLAME_COLOR :: [4]u8{255, 140, 40, 230}
SPARK_COLOR :: [4]u8{255, 205, 90, 255}
LAUNCH_EXHAUST_COLOR :: [4]u8{255, 190, 110, 220}
LAUNCH_SMOKE_COLOR :: [4]u8{200, 198, 194, 200}

// The last frame's dig of the local player, a block only.
Mining_Memory :: struct {
	cell:     World_Coordinate,
	block:    Block_Id,
	fraction: f32,
}

Capsule_Descent :: struct {
	active:  bool,
	seconds: f32,
}

// The survey satellite crossing the map and the sky after an orbital
// survey (work item 0069), over SATELLITE_PASS_SECONDS.
Satellite_Pass :: struct {
	active:  bool,
	seconds: f32,
}

// What the particles remember of the last frame, in Frame_State, reset
// with the session. frame_count is the particles' random source. The
// message count finds a new orbital survey in the quest log as the
// shipment count finds a new shipment.
Particle_Memory :: struct {
	frame_count:     u64,
	mining:          Mining_Memory,
	shipments_known: bool,
	shipment_count:  int,
	descent:         Capsule_Descent,
	messages_known:  bool,
	message_count:   int,
	satellite:       Satellite_Pass,
}

Particle_Renderer :: struct {
	disc: rl.Texture2D,
}

// Over the centre of the machine's footprint, at the top of its model.
machine_top_centre :: proc(common: Entity_Common, models: Model_Renderer) -> [3]f32 {
	centre := box_centre(common.origin, common.size)
	return {centre.x, f32(common.origin.y) + machine_model_top(models, common), centre.z}
}

furnace_emitter :: proc(furnace: Furnace, models: Model_Renderer) -> (Emitter, bool) {
	if furnace.state != .Burning {
		return {}, false
	}
	return Emitter{position = machine_top_centre(furnace.common, models), kind = .Smoke, rate = FURNACE_SMOKE_RATE, color = SMOKE_COLOR, spread = 0.2}, true
}

// Told apart by the machine's kind, like advance_fluid_machine and
// generator_state. A steam engine produces, a combustion generator
// generates, a flare stack flares while it relieves with power.
fluid_machine_emitter :: proc(fluid_machine: Fluid_Machine, machine: Machine, models: Model_Renderer) -> (Emitter, bool) {
	top := machine_top_centre(fluid_machine.common, models)
	state := fluid_machine.state
	#partial switch machine.kind {
	case .Boiler:
		if state == .Producing {
			return Emitter{position = top, kind = .Smoke, rate = BOILER_SMOKE_RATE, color = SMOKE_COLOR, spread = 0.3}, true
		}
	case .Steam_Engine:
		if state == .Producing {
			return Emitter{position = top, kind = .Steam, rate = ENGINE_STEAM_RATE, color = STEAM_COLOR, spread = 0.25}, true
		}
	case .Combustion_Generator:
		if state == .Generating {
			return Emitter{position = top, kind = .Exhaust, rate = GENERATOR_EXHAUST_RATE, color = GENERATOR_EXHAUST_COLOR, spread = 0.15}, true
		}
	case .Flare_Stack:
		if state == .Flaring {
			return Emitter{position = top, kind = .Flame, rate = FLARE_FLAME_RATE, color = FLARE_FLAME_COLOR, spread = 0.2}, true
		}
	}
	return {}, false
}

crafting_machine_emitter :: proc(assembler: Assembler, machine: Machine, models: Model_Renderer) -> (Emitter, bool) {
	if machine.recipe_maker != .Alloy_Furnace || assembler.state != .Working {
		return {}, false
	}
	return Emitter{position = machine_top_centre(assembler.common, models), kind = .Spark, rate = ALLOY_SPARK_RATE, color = SPARK_COLOR, spread = 0.4}, true
}

// Exhaust from under the rising rocket (rocket_ascent), smoke over the
// whole platform, both thicker in the first quarter of the ascent.
launch_pad_emitters :: proc(pad: Launch_Pad, machine: Machine, tick_rate: int) -> (exhaust, smoke: Emitter, launching: bool) {
	if pad.state != .Launching {
		return {}, {}, false
	}
	fraction := launch_pad_progress(pad, machine, tick_rate)
	scale: f32 = fraction < LAUNCH_EARLY_SHARE ? LAUNCH_EARLY_RATE_SCALE : 1
	lift, _ := rocket_ascent(fraction)
	centre := box_centre(pad.origin, pad.size)
	platform := f32(pad.origin.y) + LAUNCH_PAD_PLATFORM_HEIGHT
	exhaust = Emitter{position = {centre.x, platform + lift, centre.z}, kind = .Exhaust, rate = LAUNCH_EXHAUST_RATE * scale, color = LAUNCH_EXHAUST_COLOR, spread = 0.6}
	smoke = Emitter{position = {centre.x, platform, centre.z}, kind = .Smoke, rate = LAUNCH_SMOKE_RATE * scale, color = LAUNCH_SMOKE_COLOR, spread = LAUNCH_SMOKE_SPREAD}
	return exhaust, smoke, true
}

// The block's top face colour, as the atlas fallback draws it.
block_debris_color :: proc(blocks: Block_Registry, block: Block_Id) -> [4]u8 {
	if int(block) >= len(blocks.definitions) {
		return {128, 128, 128, 255}
	}
	top := face_group_color(blocks.definitions[block].texture, .Top)
	return {top.r, top.g, top.b, 255}
}

// Debris off the face the player digs at, more as the dig goes on; none
// while picking up an entity.
mining_emitter :: proc(player: Player, blocks: Block_Registry) -> (Emitter, bool) {
	mining := player.mining
	fraction := mining_fraction(mining)
	if fraction <= 0 || mining.entity != NO_ENTITY {
		return {}, false
	}
	face := player.target.block == mining.block ? player.target.face : .Positive_Y
	offset := direction_offsets[face]
	position := block_centre(mining.block) + [3]f32{f32(offset.x), f32(offset.y), f32(offset.z)} * 0.55
	rate := DEBRIS_BASE_RATE + DEBRIS_FRACTION_RATE * fraction
	return Emitter{position = position, kind = .Debris, rate = rate, color = block_debris_color(blocks, mining.block_id), spread = 0.3}, true
}

append_machine_emitters :: proc(emitters: ^[dynamic]Emitter, world: ^World, machines: Machine_Registry, models: Model_Renderer, tick_rate: int) {
	entities := &world.entities
	for furnace in entities.furnaces.entries {
		if !furnace.alive {
			continue
		}
		if emitter, found := furnace_emitter(furnace, models); found {
			append(emitters, emitter)
		}
	}
	for fluid_machine in entities.fluid_machines.entries {
		if !fluid_machine.alive {
			continue
		}
		if emitter, found := fluid_machine_emitter(fluid_machine, machines.machines[fluid_machine.machine], models); found {
			append(emitters, emitter)
		}
	}
	for assembler in entities.assemblers.entries {
		if !assembler.alive {
			continue
		}
		if emitter, found := crafting_machine_emitter(assembler, machines.machines[assembler.machine], models); found {
			append(emitters, emitter)
		}
	}
	for pad in entities.launch_pads.entries {
		if !pad.alive {
			continue
		}
		if exhaust, smoke, launching := launch_pad_emitters(pad, machines.machines[pad.machine], tick_rate); launching {
			append(emitters, exhaust, smoke)
		}
	}
}

// Every emitter of the frame, in the temp allocator.
emitters_for_frame :: proc(world: ^World, content: Simulation_Content, models: Model_Renderer, players: []Player, tick_rate: int) -> []Emitter {
	emitters := make([dynamic]Emitter, context.temp_allocator)
	append_machine_emitters(&emitters, world, content.machines, models, tick_rate)
	for player in players {
		if emitter, found := mining_emitter(player, content.blocks); found {
			append(&emitters, emitter)
		}
	}
	return emitters[:]
}

mining_memory_of :: proc(player: Player) -> Mining_Memory {
	if !player.mining.active || player.mining.entity != NO_ENTITY {
		return {}
	}
	return Mining_Memory{cell = player.mining.block, block = player.mining.block_id, fraction = mining_fraction(player.mining)}
}

// The dig was past half way last frame and its block is gone now.
break_puff_due :: proc(previous: Mining_Memory, block_now: Block_Id) -> bool {
	return previous.fraction > BREAK_PUFF_MINIMUM_FRACTION && block_now != previous.block
}

// A new shipment since the last frame; nothing on the first frame of a
// session, so a loaded world with shipments starts no descent.
shipment_starts_descent :: proc(memory: Particle_Memory, shipment_count: int) -> bool {
	return memory.shipments_known && shipment_count > memory.shipment_count
}

advance_capsule_descent :: proc(descent: Capsule_Descent, seconds: f32) -> (next: Capsule_Descent, landed: bool) {
	if !descent.active {
		return {}, false
	}
	next = descent
	next.seconds += seconds
	if next.seconds >= CAPSULE_DESCENT_SECONDS {
		return {}, true
	}
	return next, false
}

// A straight line down from CAPSULE_DESCENT_HEIGHT above the landing
// point to it, with a sway that starts and ends at zero.
capsule_descent_position :: proc(landing: [3]f32, seconds: f32) -> [3]f32 {
	fraction := clamp(seconds / CAPSULE_DESCENT_SECONDS, 0, 1)
	sway := CAPSULE_SWAY_BLOCKS * (1 - fraction)
	return landing + {math.sin(seconds * CAPSULE_SWAY_RATE) * sway, CAPSULE_DESCENT_HEIGHT * (1 - fraction), math.sin(seconds * CAPSULE_SWAY_RATE * 0.7) * sway}
}

// The top of the drop capsule on the landing pad, if the world has one.
capsule_landing_point :: proc(world: ^World, models: Model_Renderer) -> ([3]f32, bool) {
	for capsule in world.entities.capsules.entries {
		if capsule.alive {
			return machine_top_centre(capsule.common, models), true
		}
	}
	return {}, false
}

particle_burst :: proc(system: ^Particle_System, memory: Particle_Memory, position: [3]f32, color: [4]u8) {
	emitter := Emitter{position = position, kind = .Puff, color = color, spread = BREAK_PUFF_SPREAD}
	spawn_particle_count(system, emitter, BREAK_PUFF_COUNT, emitter_random_key(memory.frame_count, emitter))
}

update_break_puff :: proc(system: ^Particle_System, memory: ^Particle_Memory, world: ^World, blocks: Block_Registry, players: []Player) {
	previous := memory.mining
	memory.mining = len(players) > 0 ? mining_memory_of(players[0]) : {}
	if break_puff_due(previous, world_get_block(world, previous.cell)) {
		particle_burst(system, memory^, block_centre(previous.cell), block_debris_color(blocks, previous.block))
	}
}

// A puff where the capsule lands; no descent without a capsule to land on.
update_capsule_descent :: proc(system: ^Particle_System, memory: ^Particle_Memory, world: ^World, models: Model_Renderer, seconds: f32) {
	count := len(world.shipments)
	if shipment_starts_descent(memory^, count) {
		memory.descent = {active = true}
	}
	memory.shipments_known, memory.shipment_count = true, count
	landing, found := capsule_landing_point(world, models)
	landed: bool
	memory.descent, landed = advance_capsule_descent(memory.descent, seconds)
	if !found {
		memory.descent = {}
	} else if landed {
		particle_burst(system, memory^, landing, LANDING_PUFF_COLOR)
	}
}

// A new orbital survey message since the count.
orbital_survey_since :: proc(messages: []Quest_Message, count: int) -> bool {
	for message in messages[min(count, len(messages)):] {
		if message.text_key == ORBITAL_SURVEY_KEY {
			return true
		}
	}
	return false
}

advance_satellite_pass :: proc(pass: Satellite_Pass, seconds: f32) -> Satellite_Pass {
	if !pass.active {
		return {}
	}
	next := pass
	next.seconds += max(seconds, 0)
	if next.seconds >= SATELLITE_PASS_SECONDS {
		return {}
	}
	return next
}

// 0 as the pass starts, 1 as it ends.
satellite_pass_fraction :: proc(pass: Satellite_Pass) -> f32 {
	return clamp(pass.seconds / SATELLITE_PASS_SECONDS, 0, 1)
}

// A survey since the last frame starts a pass; nothing on the first frame
// of a session, so a loaded world starts none.
update_satellite_pass :: proc(memory: ^Particle_Memory, messages: []Quest_Message, frame_seconds: f32) {
	surveyed := memory.messages_known && orbital_survey_since(messages, memory.message_count)
	memory.messages_known, memory.message_count = true, len(messages)
	if surveyed {
		memory.satellite = {active = true}
		return
	}
	memory.satellite = advance_satellite_pass(memory.satellite, clamp(frame_seconds, 0, PARTICLE_MAXIMUM_FRAME_SECONDS))
}

// The frame's spawning, memory and movement, with the frame time capped.
update_particles :: proc(system: ^Particle_System, memory: ^Particle_Memory, world: ^World, content: Simulation_Content, models: Model_Renderer, players: []Player, tick_rate: int, frame_seconds: f32) {
	seconds := clamp(frame_seconds, 0, PARTICLE_MAXIMUM_FRAME_SECONDS)
	memory.frame_count += 1
	for emitter in emitters_for_frame(world, content, models, players, tick_rate) {
		spawn_particles(system, emitter, seconds, emitter_random_key(memory.frame_count, emitter))
	}
	update_break_puff(system, memory, world, content.blocks, players)
	update_capsule_descent(system, memory, world, models, seconds)
	advance_particles(system, seconds)
}

// The particle's colour in the frame: its alpha faded, darkened by the
// sky light unless its kind glows.
particle_draw_color :: proc(particle: Particle, light: [3]f32) -> rl.Color {
	tint := particle_behaviours[particle.kind].glows ? [3]f32{1, 1, 1} : [3]f32{clamp(light.r, 0, 1), clamp(light.g, 0, 1), clamp(light.b, 0, 1)}
	color := particle.color
	return rl.Color {
		u8(f32(color.r) * tint.r),
		u8(f32(color.g) * tint.g),
		u8(f32(color.b) * tint.b),
		u8(f32(color.a) * particle_alpha(particle)),
	}
}

init_particle_renderer :: proc() -> Particle_Renderer {
	return Particle_Renderer{disc = upload_disc_texture(PARTICLE_DISC_SIZE, PARTICLE_DISC_EDGE_TEXELS)}
}

destroy_particle_renderer :: proc(renderer: ^Particle_Renderer) {
	rl.UnloadTexture(renderer.disc)
}

// The capsule under its parachute: the body and the cords with depth
// writes, the canopy a disc drawn with the particles.
descending_capsule_bottom :: proc(memory: Particle_Memory, world: ^World, models: Model_Renderer) -> ([3]f32, bool) {
	landing, found := capsule_landing_point(world, models)
	if !memory.descent.active || !found {
		return {}, false
	}
	return capsule_descent_position(landing, memory.descent.seconds), true
}

parachute_centre :: proc(bottom: [3]f32) -> [3]f32 {
	return bottom + {0, PARACHUTE_HEIGHT + DESCENT_CAPSULE_SIZE, 0}
}

draw_descending_capsule :: proc(bottom: [3]f32) {
	capsule := bottom + {0, DESCENT_CAPSULE_SIZE / 2, 0}
	rl.DrawCubeV(capsule, DESCENT_CAPSULE_SIZE, CAPSULE_COLOR)
	for side in ([2]f32{-1, 1}) {
		rl.DrawLine3D(capsule + {0, DESCENT_CAPSULE_SIZE / 2, 0}, parachute_centre(bottom) + {side * PARACHUTE_SIZE / 2.5, 0, 0}, PARACHUTE_CORD_COLOR)
	}
}

// After the water pass and before the weather: the descending capsule,
// then with depth test on and depth writes off like the weather, debris
// as tiny cubes and the rest as soft discs facing the camera.
draw_particles :: proc(renderer: ^Particle_Renderer, camera: rl.Camera3D, system: ^Particle_System, memory: Particle_Memory, world: ^World, models: Model_Renderer, light: [3]f32) {
	bottom, descending := descending_capsule_bottom(memory, world, models)
	if descending {
		draw_descending_capsule(bottom)
	}
	begin_item_billboards()
	defer end_item_billboards()
	for particle in system.particles {
		if particle_is_live(particle) && particle.kind == .Debris {
			size := particle_draw_size(particle)
			rl.DrawCubeV(particle.position, {size, size, size}, particle_draw_color(particle, light))
		}
	}
	for particle in system.particles {
		if particle_is_live(particle) && particle.kind != .Debris {
			size := particle_draw_size(particle)
			rl.DrawBillboardRec(camera, renderer.disc, {0, 0, PARTICLE_DISC_SIZE, PARTICLE_DISC_SIZE}, particle.position, {size, size}, particle_draw_color(particle, light))
		}
	}
	if descending {
		rl.DrawBillboard(camera, renderer.disc, parachute_centre(bottom), PARACHUTE_SIZE, PARACHUTE_COLOR)
	}
}
