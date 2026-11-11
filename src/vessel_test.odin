package game

import "core:testing"

// Work item 0361: a field world's save carries a vessel of every part,
// its frame and its record, and the hash survives; the steel ring's hollow
// stays free. The same save cut before the vessels' table (one written
// before 0361) loads with no vessels.
@(test)
test_a_vessel_round_trips_a_save_and_an_older_save_loads_without_vessels :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	tick_field_test_simulation(state, simulation_content, {})
	entities := &state.world.entities
	machines := simulation_content.machines
	feet := state.players[0].field.position
	_, frame := start_vessel(entities, machines, test_machine(machines, "iron_fuselage_ring"), feet + {0, 0, 5 * POSITION_UNITS_PER_METRE}, {UNIT_VECTOR_ONE, 0, 0}, 500, 0)
	parts := [?]struct {
		id:   string,
		cell: World_Coordinate,
	} {
		{"iron_fuselage_ring", {-1, 0, -1}},
		{"steel_fuselage_ring", {-1, 2, -1}},
		{"iron_tank", {0, 0, 0}},
		{"lead_battery", {-2, 0, 0}},
		{"nickel_battery", {1, 0, -2}},
		{"control_unit", {3, 0, 1}},
		{"docking_connector", {0, 0, 3}},
		{"iron_truss", {-2, 1, 0}},
		{"iron_deck_plate", {3, 1, 0}},
	}
	for part in parts[1:] {
		add_entity(entities, machines, test_machine(machines, part.id), part.cell, 0, frame)
	}
	testing.expect_value(t, pool_alive_count(entities.vessel_parts), len(parts))
	hash := simulation_state_hash(state)
	files := encode_save_files(state, simulation_content, "vessel", 0)
	table := make([dynamic]byte, context.temp_allocator)
	write_vessel_tables(&table, entities)
	end_session(session)

	for older in ([2]bool{false, true}) {
		cut := files
		if older {
			cut.entities = files.entities[:len(files.entities) - len(table)]
		}
		loaded := load_test_field_save(config, content, &cut)
		defer end_session(loaded)
		restored := &loaded.simulation
		stage_cached_field_set(restored)
		testing.expect(t, restore_arrived_field_set(&restored.field), "the staged set restores")
		loaded_entities := &restored.world.entities
		if older {
			testing.expect_value(t, len(loaded_entities.vessels), 0)
			testing.expect_value(t, pool_alive_count(loaded_entities.vessel_parts), 0)
			continue
		}
		testing.expect_value(t, simulation_state_hash(restored), hash)
		testing.expect_value(t, len(loaded_entities.vessels), 1)
		testing.expect_value(t, vessel_index(loaded_entities, frame), 0)
		_, frame_found := find_frame(&loaded_entities.frames, frame)
		testing.expect(t, frame_found, "the vessel's frame loads")
		for part in parts {
			handle := entity_at(loaded_entities, part.cell, frame)
			loaded_part := pool_get(&loaded_entities.vessel_parts, handle)
			testing.expectf(t, handle.kind == .Vessel_Part && loaded_part != nil && machines.machines[loaded_part.machine].id == part.id && loaded_part.origin == part.cell, "%s at %v", part.id, part.cell)
		}
		testing.expect_value(t, entity_at(loaded_entities, {0, 3, 0}, frame), NO_ENTITY)
		testing.expect_value(t, entity_at(loaded_entities, {-1, 3, 0}, frame), entity_at(loaded_entities, {-1, 2, -1}, frame))
	}
}

// Two simulations building the same vessel through the same Place inputs
// hash the same, and a part's machine is in the hash.
@(test)
test_two_sessions_building_a_vessel_hash_the_same :: proc(t: ^testing.T) {
	hashes: [2]u64
	for index in 0 ..< 2 {
		simulation, content, items := make_vessel_test()
		defer destroy_simulation(&simulation)
		entities := &simulation.world.entities
		add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"iron_fuselage_ring", 1}, {"lead_battery", 1})
		player := &simulation.players[0]
		player.field.pitch = degrees_to_angle_units(-45)
		hold_test_vessel_part(player, content, "iron_fuselage_ring")
		tick_field_simulation(&simulation, content, {})
		press_test_place(&simulation, content)
		testing.expect_value(t, len(entities.vessels), 1)
		if len(entities.vessels) != 1 {
			return
		}
		battery := Vessel_Placement{kind = .Equipment, machine = test_machine(content.machines, "lead_battery"), frame = entities.vessels[0].frame, origin = {-2, 0, 0}}
		testing.expect_value(t, drain_test_vessel_placement(&simulation, content, battery), Field_Edit_Refusal.None)
		hashes[index] = simulation_state_hash(&simulation)
		entities.vessel_parts.entries[0].machine = test_machine(content.machines, "steel_fuselage_ring")
		testing.expect(t, simulation_state_hash(&simulation) != hashes[index], "a part's machine is hashed")
	}
	testing.expect_value(t, hashes[0], hashes[1])
}
