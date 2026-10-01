package game

import "core:testing"

PARTICLE_TEST_COMMON :: Entity_Common {
	origin = {2, 1, 3},
	size   = {1, 1, 1},
	alive  = true,
}

// A burning furnace smokes from the centre of its top; any other state
// does not.
@(test)
test_furnace_emitter_per_state :: proc(t: ^testing.T) {
	furnace := Furnace{common = PARTICLE_TEST_COMMON, state = .Burning}
	emitter, found := furnace_emitter(furnace, {})
	testing.expect(t, found, "burning smokes")
	testing.expect_value(t, emitter.kind, Particle_Kind.Smoke)
	testing.expect_value(t, emitter.position, [3]f32{2.5, 2, 3.5})
	for state in ([?]Furnace_State{.Idle, .No_Fuel, .Output_Full}) {
		furnace.state = state
		_, found = furnace_emitter(furnace, {})
		testing.expect(t, !found, "not burning")
	}
}

// Each fluid machine told apart by its kind: the boiler smokes, the
// engine steams, the generator gives exhaust, the flare stack a flame,
// each in its working state only.
@(test)
test_fluid_machine_emitter_per_state :: proc(t: ^testing.T) {
	Case :: struct {
		kind:    Machine_Kind,
		working: Fluid_Machine_State,
		emitted: Particle_Kind,
	}
	cases := [?]Case {
		{.Boiler, .Producing, .Smoke},
		{.Steam_Engine, .Producing, .Steam},
		{.Combustion_Generator, .Generating, .Exhaust},
		{.Flare_Stack, .Flaring, .Flame},
	}
	for test_case in cases {
		machine := Machine{kind = test_case.kind}
		fluid_machine := Fluid_Machine{common = PARTICLE_TEST_COMMON, state = test_case.working}
		emitter, found := fluid_machine_emitter(fluid_machine, machine, {})
		testing.expect(t, found, "working emits")
		testing.expect_value(t, emitter.kind, test_case.emitted)
		for state in ([?]Fluid_Machine_State{.Idle, .No_Fuel, .No_Water, .Unpowered, .Output_Full}) {
			fluid_machine.state = state
			_, found = fluid_machine_emitter(fluid_machine, machine, {})
			testing.expect(t, !found, "idle emits nothing")
		}
	}
	for kind in ([?]Machine_Kind{.Hydro_Turbine, .Offshore_Pump, .Pump, .Storage_Tank}) {
		_, found := fluid_machine_emitter(Fluid_Machine{common = PARTICLE_TEST_COMMON, state = .Generating}, Machine{kind = kind}, {})
		testing.expect(t, !found, "no particles for this kind")
		_, found = fluid_machine_emitter(Fluid_Machine{common = PARTICLE_TEST_COMMON, state = .Producing}, Machine{kind = kind}, {})
		testing.expect(t, !found, "no particles for this kind")
	}
}

@(test)
test_alloy_furnace_throws_sparks_while_working :: proc(t: ^testing.T) {
	alloy := Machine{kind = .Crafting_Machine, recipe_maker = .Alloy_Furnace}
	assembler := Assembler{common = PARTICLE_TEST_COMMON, state = .Working}
	emitter, found := crafting_machine_emitter(assembler, alloy, {})
	testing.expect(t, found, "working throws sparks")
	testing.expect_value(t, emitter.kind, Particle_Kind.Spark)
	assembler.state = .Missing_Ingredients
	_, found = crafting_machine_emitter(assembler, alloy, {})
	testing.expect(t, !found, "idle throws none")
	assembler.state = .Working
	_, found = crafting_machine_emitter(assembler, Machine{kind = .Crafting_Machine, recipe_maker = .Assembler}, {})
	testing.expect(t, !found, "an assembler throws none")
}

// Exhaust under the rocket and smoke on the pad while launching, three
// times as thick in the first quarter of the ascent; nothing otherwise.
@(test)
test_launch_pad_emitters_per_state :: proc(t: ^testing.T) {
	machine := Machine{kind = .Launch_Pad, launch_seconds = 5}
	pad := Launch_Pad{common = Entity_Common{origin = {0, 1, 0}, size = {9, 2, 9}, alive = true}, state = .Launching}
	exhaust, smoke, launching := launch_pad_emitters(pad, machine, TEST_TICK_RATE)
	testing.expect(t, launching, "launching")
	testing.expect_value(t, exhaust.kind, Particle_Kind.Exhaust)
	testing.expect_value(t, smoke.kind, Particle_Kind.Smoke)
	testing.expect_value(t, exhaust.rate, LAUNCH_EXHAUST_RATE * LAUNCH_EARLY_RATE_SCALE)
	testing.expect_value(t, smoke.position, [3]f32{4.5, 1 + LAUNCH_PAD_PLATFORM_HEIGHT, 4.5})
	pad.launch_ticks = 4 * TEST_TICK_RATE
	exhaust, smoke, launching = launch_pad_emitters(pad, machine, TEST_TICK_RATE)
	testing.expect_value(t, exhaust.rate, LAUNCH_EXHAUST_RATE)
	testing.expect_value(t, smoke.rate, LAUNCH_SMOKE_RATE)
	testing.expect(t, exhaust.position.y > smoke.position.y, "the exhaust follows the rocket")
	for state in ([?]Launch_Pad_State{.Waiting_For_Parts, .Ready_To_Assemble, .Assembling, .Rocket_Ready}) {
		pad.state = state
		_, _, launching = launch_pad_emitters(pad, machine, TEST_TICK_RATE)
		testing.expect(t, !launching, "not launching")
	}
}

// Debris in the block's top colour off the face dug at, more as the dig
// goes on; none while picking up an entity or not digging.
@(test)
test_mining_debris_in_the_block_colour :: proc(t: ^testing.T) {
	blocks := make_test_registry()
	grass := test_block(blocks, "grass")
	player: Player
	player.target = Raycast_Hit{hit = true, block = {4, 5, 6}, face = .Positive_Y}
	player.mining = Mining_State{active = true, block = {4, 5, 6}, block_id = grass, progress_ticks = 5, required_ticks = 10}
	emitter, found := mining_emitter(player, blocks)
	testing.expect(t, found, "digging throws debris")
	testing.expect_value(t, emitter.kind, Particle_Kind.Debris)
	testing.expect_value(t, emitter.color, [4]u8{106, 170, 64, 255})
	testing.expect(t, emitter.position.y > 6, "over the top face")
	testing.expect_value(t, emitter.rate, DEBRIS_BASE_RATE + DEBRIS_FRACTION_RATE * 0.5)
	player.mining.entity = Entity_Handle{index = 1, generation = 1}
	_, found = mining_emitter(player, blocks)
	testing.expect(t, !found, "picking up throws none")
	player.mining = {}
	_, found = mining_emitter(player, blocks)
	testing.expect(t, !found, "not digging")
}

// A burning furnace and a working alloy furnace emit, an idle boiler does
// not.
@(test)
test_emitters_for_frame_from_the_world :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	furnace := place_test_entity(&world, content, "stone_furnace", {0, 1, 0})
	alloy := place_test_entity(&world, content, "alloy_furnace", {4, 1, 0})
	place_test_entity(&world, content, "boiler", {10, 1, 0})
	pool_get(&world.entities.furnaces, furnace).state = .Burning
	pool_get(&world.entities.assemblers, alloy).state = .Working
	emitters := emitters_for_frame(&world, content, {}, nil, TEST_TICK_RATE)
	testing.expect_value(t, len(emitters), 2)
	testing.expect_value(t, emitters[0].kind, Particle_Kind.Smoke)
	testing.expect_value(t, emitters[1].kind, Particle_Kind.Spark)
	pool_get(&world.entities.furnaces, furnace).state = .Idle
	pool_get(&world.entities.assemblers, alloy).state = .Missing_Ingredients
	testing.expect_value(t, len(emitters_for_frame(&world, content, {}, nil, TEST_TICK_RATE)), 0)
}

// A dig past half way whose block is gone the next frame puffs once; a
// dig given up does not.
@(test)
test_break_puff_fires_once :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	stone := test_block(content.blocks, "stone")
	system := new(Particle_System, context.temp_allocator)
	memory: Particle_Memory
	players := make([]Player, 1)
	players[0].mining = Mining_State{active = true, block = {0, 0, 0}, block_id = stone, progress_ticks = 8, required_ticks = 10}
	update_break_puff(system, &memory, &world, content.blocks, players)
	testing.expect_value(t, live_particle_count(system), 0)
	world_set_block(&world, {0, 0, 0}, AIR_BLOCK)
	players[0].mining = {}
	update_break_puff(system, &memory, &world, content.blocks, players)
	testing.expect_value(t, live_particle_count(system), BREAK_PUFF_COUNT)
	testing.expect_value(t, system.particles[0].color, [4]u8{128, 128, 128, 255})
	update_break_puff(system, &memory, &world, content.blocks, players)
	testing.expect_value(t, live_particle_count(system), BREAK_PUFF_COUNT)
	testing.expect(t, !break_puff_due(Mining_Memory{cell = {1, 0, 0}, block = stone, fraction = 0.3}, AIR_BLOCK), "given up early")
	testing.expect(t, !break_puff_due(Mining_Memory{cell = {1, 0, 0}, block = stone, fraction = 0.9}, stone), "still there")
}

// From 60 blocks above the landing point down onto it in 8 seconds.
@(test)
test_capsule_descent_path :: proc(t: ^testing.T) {
	landing := [3]f32{2.5, 12, -3.5}
	testing.expect_value(t, capsule_descent_position(landing, 0), landing + {0, CAPSULE_DESCENT_HEIGHT, 0})
	testing.expect_value(t, capsule_descent_position(landing, CAPSULE_DESCENT_SECONDS), landing)
	halfway := capsule_descent_position(landing, CAPSULE_DESCENT_SECONDS / 2)
	testing.expect_value(t, halfway.y, landing.y + CAPSULE_DESCENT_HEIGHT / 2)
	descent := Capsule_Descent{active = true}
	landed: bool
	for _ in 0 ..< 15 {
		descent, landed = advance_capsule_descent(descent, 0.5)
		testing.expect(t, descent.active && !landed, "still falling")
	}
	descent, landed = advance_capsule_descent(descent, 0.5)
	testing.expect(t, landed && !descent.active, "landed at 8 seconds")
}

// A shipment during the session starts a descent that ends in a puff on
// the capsule; the shipments a loaded world starts with do not.
@(test)
test_shipment_starts_a_descent :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	records.shipments = make([dynamic]Shipment)
	append(&records.shipments, Shipment{})
	place_test_entity(&world, content, "drop_capsule", {0, 1, 0})
	system := new(Particle_System, context.temp_allocator)
	memory: Particle_Memory
	update_capsule_descent(system, &memory, &world, records.shipments[:], {}, 0.1)
	testing.expect(t, !memory.descent.active, "loaded shipments start nothing")
	append(&records.shipments, Shipment{})
	update_capsule_descent(system, &memory, &world, records.shipments[:], {}, 0.1)
	testing.expect(t, memory.descent.active, "a new shipment starts a descent")
	for _ in 0 ..< 80 {
		update_capsule_descent(system, &memory, &world, records.shipments[:], {}, 0.1)
	}
	testing.expect(t, !memory.descent.active, "landed")
	testing.expect_value(t, live_particle_count(system), BREAK_PUFF_COUNT)
}
