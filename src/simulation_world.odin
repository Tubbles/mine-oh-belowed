package game

// The world's part of simulation_tick, after the players: block changes
// since the last tick become light and water updates, then bounded
// amounts of water flow, leaf decay (tree_felling.odin) and light
// propagation run. Water and leaf changes made in this tick are recorded
// and reach light and water scheduling next tick.

// The prototype tables the simulation reads, loaded once at startup.
// generator, when set, is the session's world generator, which the
// orbital survey asks for veins in chunks never loaded (venture.odin); it
// is only read.
Simulation_Content :: struct {
	blocks:       Block_Registry,
	items:        Item_Registry,
	machines:     Machine_Registry,
	fluids:       Fluid_Registry,
	recipes:      Recipe_Registry,
	technologies: Technology_Registry,
	quests:       Quest_Registry,
	veins:        Vein_Content,
	contracts:    Contract_Registry,
	// Chapter kits for the developer menu and --chapter.
	developer_kits: Developer_Kits,
	generator:    ^Generator,
}

apply_block_changes :: proc(world: ^World, registry: Block_Registry, tick: u64) {
	for change in world.block_changes {
		light_block_changed(world, registry, change.position, change.previous)
		schedule_water_around(world, registry, change.position, tick)
	}
	clear(&world.block_changes)
}

// felling is empty in tests without trees, which turns leaf decay off.
tick_world :: proc(world: ^World, registry: Block_Registry, tick: u64, felling := Tree_Felling{}) {
	apply_block_changes(world, registry, tick)
	run_water_updates(world, registry, tick, MAXIMUM_WATER_UPDATES_PER_TICK)
	run_leaf_decay(world, registry, felling, tick, MAXIMUM_LEAF_DECAYS_PER_TICK)
	seed_arrived_chunks(world, registry, MAXIMUM_LIGHT_CHUNK_SEEDS_PER_TICK)
	propagate_light(world, registry, MAXIMUM_LIGHT_STEPS_PER_TICK)
}
