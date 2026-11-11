package game

import "core:testing"

// Work item 0361's placement and removal on the flat test site.

// The flat test site with the shipped machines and vessel parts and the
// foundation's pitch; no player yet.
make_vessel_test :: proc() -> (simulation: Simulation_State, content: Simulation_Content, items: Item_Registry) {
	simulation, content, items = make_pick_up_test()
	content.vessel_parts = make_test_vessel_parts(content.machines)
	return
}

// A vessel begun with the machine's piece at (x, 0, z) position units from
// the site, facing +x: the frame's x runs along -z, its z along +x.
start_test_vessel :: proc(simulation: ^Simulation_State, content: Simulation_Content, id: string, x, z: i64) -> (handle: Entity_Handle, frame: Frame) {
	frame_id: Frame_Id
	handle, frame_id = start_vessel(&simulation.world.entities, content.machines, test_machine(content.machines, id), test_site_point(x, 0, z), {UNIT_VECTOR_ONE, 0, 0}, content.field.foundation_pitch_millimetres, 0)
	frame, _ = find_frame(&simulation.world.entities.frames, frame_id)
	return
}

add_test_vessel_part :: proc(simulation: ^Simulation_State, content: Simulation_Content, id: string, frame: Frame_Id, origin: World_Coordinate) -> Entity_Handle {
	return add_entity(&simulation.world.entities, content.machines, test_machine(content.machines, id), origin, 0, frame)
}

// The player holds the part as update_field_held_tool sets it from the
// hotbar.
hold_test_vessel_part :: proc(player: ^Player, content: Simulation_Content, id: string) {
	player.field.tool = .Vessel_Part
	player.field.held_machine = test_machine(content.machines, id)
}

// Where the feet of a player hovering height_millimetres over the cell's
// top face are.
hover_test_feet :: proc(frame: Frame, cell: World_Coordinate, height_millimetres: int) -> World_Position {
	return frame_cell_centre(frame, cell) + World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 2 + millimetres_to_position_units(height_millimetres)))
}

// A flying player hovering over the cell, looking straight down, carrying
// the stacks; one tick aims it.
hover_test_player_over_cell :: proc(simulation: ^Simulation_State, content: Simulation_Content, items: Item_Registry, frame: Frame, cell: World_Coordinate, height_millimetres: int, stacks: ..Starting_Item) {
	add_test_miner(simulation, items, hover_test_feet(frame, cell, height_millimetres), ..stacks)
	simulation.players[len(simulation.players) - 1].field.flying = true
	tick_field_simulation(simulation, content, {})
}

press_test_place :: proc(simulation: ^Simulation_State, content: Simulation_Content) {
	place := [1]Field_Player_Input{{held = {.Place}, just_pressed = {.Place}}}
	tick_field_simulation(simulation, content, place[:])
}

// The pitch, looking ahead, at which player 0's reticle meets the cell's
// top face, raised a degree a tick from straight down.
aim_test_player_at_top :: proc(simulation: ^Simulation_State, content: Simulation_Content, frame: Frame_Id, cell: World_Coordinate) -> bool {
	player := &simulation.players[0]
	for degrees := -89; degrees <= 0; degrees += 1 {
		player.field.pitch = degrees_to_angle_units(degrees)
		tick_field_simulation(simulation, content, {})
		if target := player.field.frame_target; target.hit && target.frame == frame && target.cell == cell && target.adjacent == cell + UP {
			return true
		}
	}
	return false
}

// player 0's reticle on the cell, entered from the adjacent one, as the
// tick's aim would leave it.
set_test_frame_target :: proc(simulation: ^Simulation_State, frame: Frame_Id, cell, adjacent: World_Coordinate) {
	occupant, found := frame_occupant(&simulation.world.entities.frames, frame, cell)
	assert(found)
	simulation.players[0].field.frame_target = {hit = true, frame = frame, cell = cell, adjacent = adjacent, occupant = occupant}
}

// Place's press for player 0 as the tick queues it, then the drain.
place_test_vessel_part :: proc(simulation: ^Simulation_State, content: Simulation_Content) -> Field_Edit_Refusal {
	simulation.players[0].field_refusal = .None
	queue_vessel_placement(simulation, content, 0)
	refusal := simulation.players[0].field_refusal
	drain_field_placements(simulation, content)
	return refusal != .None ? refusal : simulation.players[0].field_refusal
}

// A queued placement drained for player 0.
drain_test_vessel_placement :: proc(simulation: ^Simulation_State, content: Simulation_Content, placement: Vessel_Placement) -> Field_Edit_Refusal {
	simulation.players[0].field_refusal = .None
	append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = Field_Placement{kind = .Vessel_Part, vessel = placement}})
	drain_field_placements(simulation, content)
	return simulation.players[0].field_refusal
}

// The pick up command for player 0 on the cell, drained.
pick_up_test_cell :: proc(simulation: ^Simulation_State, content: Simulation_Content, frame: Frame_Id, cell: World_Coordinate) -> Field_Edit_Refusal {
	simulation.players[0].field_refusal = .None
	append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = Field_Placement{kind = .Pick_Up, frame = frame, cell = cell}})
	drain_field_placements(simulation, content)
	return simulation.players[0].field_refusal
}

// The vessel part at the cell and its machine's id, "" for none.
test_vessel_part_at :: proc(simulation: ^Simulation_State, content: Simulation_Content, frame: Frame_Id, cell: World_Coordinate) -> (part: Vessel_Part, id: string) {
	entities := &simulation.world.entities
	handle := entity_at(entities, cell, frame)
	if handle.kind != .Vessel_Part {
		return {}, ""
	}
	found := pool_get(&entities.vessel_parts, handle)
	if found == nil {
		return {}, ""
	}
	return found^, content.machines.machines[found.machine].id
}

// The face snap: rings stack aligned, a narrower piece follows the aimed
// cell and stays inside the aimed part, a wider one is centred with the
// odd cell on the high side, and a normal of either sign starts at the
// adjacent layer and grows away from the face.
@(test)
test_structure_face_origin_aligns_or_follows_the_aimed_cell :: proc(t: ^testing.T) {
	RING :: [3]i32{4, 2, 4}
	TRUSS :: [3]i32{1, 1, 1}
	DECK :: [3]i32{2, 1, 2}
	ring_origin := World_Coordinate{-1, 0, -1}
	for x in i32(-1) ..= 2 {
		testing.expect_value(t, structure_face_origin(ring_origin, RING, {x, 2, 2}, 1, 1, RING), World_Coordinate{-1, 2, -1})
		// A truss on the ring's -z side follows the aimed cell to each edge.
		for y in i32(0) ..= 1 {
			testing.expect_value(t, structure_face_origin(ring_origin, RING, {x, y, -2}, 2, -1, TRUSS), World_Coordinate{x, y, -2})
		}
	}
	// Three cells wide on four: centred on the aimed cell, clamped at
	// each edge.
	WIDE :: [3]i32{3, 1, 3}
	testing.expect_value(t, structure_face_origin(ring_origin, RING, {-1, 0, -2}, 2, -1, WIDE), World_Coordinate{-1, 0, -4})
	testing.expect_value(t, structure_face_origin(ring_origin, RING, {0, 0, -2}, 2, -1, WIDE), World_Coordinate{-1, 0, -4})
	testing.expect_value(t, structure_face_origin(ring_origin, RING, {1, 0, -2}, 2, -1, WIDE), World_Coordinate{0, 0, -4})
	testing.expect_value(t, structure_face_origin(ring_origin, RING, {2, 0, -2}, 2, -1, WIDE), World_Coordinate{0, 0, -4})
	// A deck plate on a truss's top, the wider: the odd cell on the high side.
	testing.expect_value(t, structure_face_origin({5, 0, 5}, TRUSS, {5, 1, 5}, 1, 1, DECK), World_Coordinate{5, 1, 5})
	// A ring on a deck plate's top: centred.
	testing.expect_value(t, structure_face_origin({0, 0, 0}, DECK, {1, 1, 0}, 1, 1, RING), World_Coordinate{-1, 1, -1})
	// Each sign of each normal.
	testing.expect_value(t, structure_face_origin(ring_origin, RING, {0, -1, 0}, 1, -1, RING), World_Coordinate{-1, -2, -1})
	testing.expect_value(t, structure_face_origin({0, 0, 0}, TRUSS, {1, 0, 0}, 0, 1, DECK), World_Coordinate{1, 0, 0})
	testing.expect_value(t, structure_face_origin({0, 0, 0}, TRUSS, {-1, 0, 0}, 0, -1, DECK), World_Coordinate{-2, 0, 0})
	testing.expect_value(t, structure_face_origin({0, 0, 0}, TRUSS, {0, 0, 1}, 2, 1, DECK), World_Coordinate{0, 0, 1})
	testing.expect_value(t, structure_face_origin({0, 0, 0}, TRUSS, {0, 0, -1}, 2, -1, DECK), World_Coordinate{0, 0, -2})
}

// Place with a ring held on the flat site's ground starts a vessel: one
// frame, one record, the ring on cell (0, 0, 0) of it as
// field_footprint_origin centres it, one ring spent.
@(test)
test_a_structure_piece_aimed_at_the_ground_starts_a_vessel :: proc(t: ^testing.T) {
	simulation, content, items := make_vessel_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"iron_fuselage_ring", 2})
	player := &simulation.players[0]
	player.field.pitch = degrees_to_angle_units(-45)
	hold_test_vessel_part(player, content, "iron_fuselage_ring")
	tick_field_simulation(&simulation, content, {})
	testing.expect(t, player.field.target.hit && !player.field.frame_target.hit, "the reticle meets the ground")
	press_test_place(&simulation, content)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, len(entities.frames.frames), 1)
	testing.expect_value(t, len(entities.vessels), 1)
	if len(entities.vessels) != 1 {
		return
	}
	frame := entities.vessels[0].frame
	testing.expect_value(t, frame, entities.frames.frames[0].id)
	testing.expect_value(t, pool_alive_count(entities.vessel_parts), 1)
	ring := test_machine(content.machines, "iron_fuselage_ring")
	origin := field_footprint_origin({}, content.machines.machines[ring].footprint, 0)
	testing.expect_value(t, origin, World_Coordinate{-1, 0, -1})
	part, id := test_vessel_part_at(&simulation, content, frame, origin)
	testing.expect_value(t, id, "iron_fuselage_ring")
	testing.expect_value(t, part.origin, origin)
	testing.expect_value(t, frame_cell_count(&entities.frames, frame), 24)
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "iron_fuselage_ring")), 1)
}

// A second ring aimed at the first one's top stacks on it aligned. A ring
// on a deck plate touches it only through its hollow and is refused
// Needs_Vessel_Structure; a ring aimed at the first ring's inner face would
// overlap its walls (Frame_Cell_Taken); a ring aimed at a foundation is
// refused Needs_Vessel_Structure.
@(test)
test_structure_joins_the_aimed_face_and_must_touch_it :: proc(t: ^testing.T) {
	simulation, content, items := make_vessel_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	_, frame := start_test_vessel(&simulation, content, "iron_fuselage_ring", metres_to_position_units(2), 0)
	add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"iron_fuselage_ring", 3})
	player := &simulation.players[0]
	ring_item := test_item(items, "iron_fuselage_ring")
	hold_test_vessel_part(player, content, "iron_fuselage_ring")
	testing.expect(t, aim_test_player_at_top(&simulation, content, frame.id, {0, 1, -1}), "the reticle meets the ring's top")
	press_test_place(&simulation, content)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	second, id := test_vessel_part_at(&simulation, content, frame.id, {-1, 2, -1})
	testing.expect_value(t, id, "iron_fuselage_ring")
	testing.expect_value(t, second.origin, World_Coordinate{-1, 2, -1})
	testing.expect_value(t, inventory_count(player.inventory, ring_item), 2)
	testing.expect_value(t, len(entities.vessels), 1)

	_, deck := start_test_vessel(&simulation, content, "iron_deck_plate", metres_to_position_units(-10), 0)
	set_test_frame_target(&simulation, deck.id, {1, 0, 0}, {1, 1, 0})
	testing.expect_value(t, place_test_vessel_part(&simulation, content), Field_Edit_Refusal.Needs_Vessel_Structure)
	testing.expect_value(t, frame_cell_count(&entities.frames, deck.id), 4)

	set_test_frame_target(&simulation, frame.id, {0, 0, -1}, {0, 0, 0})
	testing.expect_value(t, place_test_vessel_part(&simulation, content), Field_Edit_Refusal.Frame_Cell_Taken)

	pad := lay_test_pad(entities, content.machines, metres_to_position_units(-20), 0, {0, 0, 0}, {0, 0, 0})
	set_test_frame_target(&simulation, pad.id, {0, 0, 0}, {0, 1, 0})
	testing.expect_value(t, place_test_vessel_part(&simulation, content), Field_Edit_Refusal.Needs_Vessel_Structure)
	testing.expect_value(t, inventory_count(player.inventory, ring_item), 2)
	testing.expect_value(t, pool_alive_count(entities.vessel_parts), 3)
}

// A player hovering over a ring and looking down its hollow with a truss
// held aims at the ground inside it: refused Inside_A_Vessel, the ghost's
// refusal too, one vessel, the truss kept. One cell past the ring's
// extent (its outside slot at x -2) a new vessel starts.
@(test)
test_a_new_vessel_is_refused_inside_another_vessel :: proc(t: ^testing.T) {
	simulation, content, items := make_vessel_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	_, frame := start_test_vessel(&simulation, content, "iron_fuselage_ring", 0, 0)
	extent, found := vessel_extent(entities, content.machines, frame.id)
	testing.expect(t, found)
	testing.expect_value(t, extent, Cell_Box{from = {-2, 0, -2}, to = {3, 1, 3}})
	hover_test_player_over_cell(&simulation, content, items, frame, {0, 1, 0}, 1000, {"iron_truss", 2})
	player := &simulation.players[0]
	truss := test_item(items, "iron_truss")
	hold_test_vessel_part(player, content, "iron_truss")
	tick_field_simulation(&simulation, content, {})
	placement, refusal := field_vessel_placement(entities, content, player.field)
	testing.expect_value(t, refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, placement.kind, Vessel_Placement_Kind.New_Vessel)
	testing.expect_value(t, vessel_placement_refusal(&simulation, content, player^, placement), Field_Edit_Refusal.Inside_A_Vessel)
	press_test_place(&simulation, content)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Inside_A_Vessel)
	testing.expect_value(t, len(entities.vessels), 1)
	testing.expect_value(t, inventory_count(player.inventory, truss), 2)

	player.field.position = hover_test_feet(frame, {-3, 0, 0}, 1000)
	tick_field_simulation(&simulation, content, {})
	press_test_place(&simulation, content)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
	testing.expect_value(t, len(entities.vessels), 2)
	testing.expect_value(t, inventory_count(player.inventory, truss), 1)
}

// Equipment goes into the free slot of its size the view ray meets: a
// battery beside the ring's wall into the outside slot there, a tank into
// the hollow; a second battery aimed at the first meets no free slot; a
// crouched player standing in a deck plate's top slot does not catch it,
// standing up does (and the drain refuses to bury the player); the sky
// holds no slot.
@(test)
test_equipment_goes_into_the_aimed_free_slot :: proc(t: ^testing.T) {
	{
		simulation, content, items := make_vessel_test()
		defer destroy_simulation(&simulation)
		entities := &simulation.world.entities
		_, frame := start_test_vessel(&simulation, content, "iron_fuselage_ring", 0, 0)
		hover_test_player_over_cell(&simulation, content, items, frame, {-2, 0, 0}, 1000, {"lead_battery", 2}, {"iron_tank", 1})
		player := &simulation.players[0]
		hold_test_vessel_part(player, content, "lead_battery")
		placement, refusal := field_vessel_placement(entities, content, player.field)
		testing.expect_value(t, refusal, Field_Edit_Refusal.None)
		testing.expect_value(t, placement.kind, Vessel_Placement_Kind.Equipment)
		testing.expect_value(t, placement.origin, World_Coordinate{-2, 0, 0})
		press_test_place(&simulation, content)
		testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
		_, id := test_vessel_part_at(&simulation, content, frame.id, {-2, 0, 0})
		testing.expect_value(t, id, "lead_battery")

		press_test_place(&simulation, content)
		testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.No_Free_Slot)
		testing.expect_value(t, inventory_count(player.inventory, test_item(items, "lead_battery")), 1)
		testing.expect_value(t, pool_alive_count(entities.vessel_parts), 2)

		player.field.position = hover_test_feet(frame, {0, 1, 0}, 1000)
		hold_test_vessel_part(player, content, "iron_tank")
		tick_field_simulation(&simulation, content, {})
		press_test_place(&simulation, content)
		testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.None)
		tank, tank_id := test_vessel_part_at(&simulation, content, frame.id, {1, 1, 1})
		testing.expect_value(t, tank_id, "iron_tank")
		testing.expect_value(t, tank.origin, World_Coordinate{0, 0, 0})
	}
	{
		simulation, content, items := make_vessel_test()
		defer destroy_simulation(&simulation)
		entities := &simulation.world.entities
		_, frame := start_test_vessel(&simulation, content, "iron_deck_plate", 0, 0)
		stand_test_player_on_cell(&simulation, content, items, frame, {0, 0, 0}, {"iron_tank", 1})
		player := &simulation.players[0]
		hold_test_vessel_part(player, content, "iron_tank")
		player.field.crouch_held = true
		tick_field_simulation(&simulation, content, {})
		testing.expect(t, player.field.crouching, "the player crouches on the deck")
		_, refusal := field_vessel_placement(entities, content, player.field)
		testing.expect_value(t, refusal, Field_Edit_Refusal.No_Free_Slot)
		player.field.crouch_held = false
		tick_field_simulation(&simulation, content, {})
		testing.expect(t, !player.field.crouching, "the player stands up")
		placement: Vessel_Placement
		placement, refusal = field_vessel_placement(entities, content, player.field)
		testing.expect_value(t, refusal, Field_Edit_Refusal.None)
		testing.expect_value(t, placement.origin, World_Coordinate{0, 1, 0})
		press_test_place(&simulation, content)
		testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Would_Bury_Player)
		testing.expect_value(t, pool_alive_count(entities.vessel_parts), 1)
	}
	{
		simulation, content, items := make_vessel_test()
		defer destroy_simulation(&simulation)
		start_test_vessel(&simulation, content, "iron_fuselage_ring", metres_to_position_units(2), 0)
		add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"lead_battery", 1})
		player := &simulation.players[0]
		player.field.pitch = degrees_to_angle_units(30)
		hold_test_vessel_part(player, content, "lead_battery")
		press_test_place(&simulation, content)
		testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.No_Free_Slot)
		testing.expect_value(t, pool_alive_count(simulation.world.entities.vessel_parts), 1)
	}
}

// A furnace and a foundation aimed at a ring are refused Vessel_Parts_Only,
// a second control unit One_Control_Unit, and a belt pole on the vessel's
// frame is frame_placement_refusal's Vessel_Frame.
@(test)
test_a_vessel_takes_vessel_parts_only_and_one_control_unit :: proc(t: ^testing.T) {
	simulation, content, items := make_vessel_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	_, frame := start_test_vessel(&simulation, content, "iron_fuselage_ring", 0, 0)
	add_test_miner(&simulation, items, FAR_FEET, {"stone_furnace", 1}, {"wooden_foundation", 1}, {"control_unit", 2})
	player := &simulation.players[0]
	above := World_Coordinate{-1, 2, -1}
	furnace := Field_Placement{machine = test_machine(content.machines, "stone_furnace"), frame = frame.id, cell = above}
	foundation := Field_Placement{machine = content.field.pad_foundation, frame = frame.id, cell = above, normal = UP, size = 1, height = 1}
	for placement in ([2]Field_Placement{furnace, foundation}) {
		player.field_refusal = .None
		append(&simulation.field.placements, Queued_Field_Placement{player = 0, placement = placement})
		drain_field_placements(&simulation, content)
		testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Vessel_Parts_Only)
		testing.expect_value(t, entity_at(entities, above, frame.id), NO_ENTITY)
	}
	control := test_machine(content.machines, "control_unit")
	first := Vessel_Placement{kind = .Equipment, machine = control, frame = frame.id, origin = {-2, 0, 0}}
	testing.expect_value(t, drain_test_vessel_placement(&simulation, content, first), Field_Edit_Refusal.None)
	second := first
	second.origin = {1, 0, -2}
	testing.expect_value(t, drain_test_vessel_placement(&simulation, content, second), Field_Edit_Refusal.One_Control_Unit)
	testing.expect_value(t, vessel_control_unit_count(entities, content.machines, frame.id), 1)
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "control_unit")), 1)
	pole := find_machine_of_kind(content.machines, .Belt_Pole)
	testing.expect_value(t, frame_placement_refusal(entities, content.machines, pole, frame.id, above, 0), Frame_Placement_Refusal.Vessel_Frame)
}

// A ring hosting a battery refuses Holds_Equipment (Mine held gets no
// progress), until a second ring offers the battery's box; the middle of
// three trusses refuses Holds_The_Vessel_Together while an end comes off;
// the last part takes the frame and the record with it.
@(test)
test_removal_keeps_equipment_on_a_slot_and_the_vessel_whole :: proc(t: ^testing.T) {
	simulation, content, items := make_vessel_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	ring, frame := start_test_vessel(&simulation, content, "iron_fuselage_ring", 0, 0)
	battery := add_test_vessel_part(&simulation, content, "lead_battery", frame.id, {-2, 0, 0})
	stand_test_player_on_cell(&simulation, content, items, frame, {0, 1, -1})
	player := &simulation.players[0]
	testing.expect_value(t, vessel_part_removal_refusal(entities, content, ring), Field_Edit_Refusal.Holds_Equipment)
	testing.expect_value(t, vessel_part_removal_refusal(entities, content, battery), Field_Edit_Refusal.None)
	hold_test_mine(&simulation, content, PICK_UP_TEST_TICKS + 4)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.Holds_Equipment)
	testing.expect(t, !player.mining.active)
	testing.expect_value(t, pick_up_test_cell(&simulation, content, frame.id, {-1, 0, -1}), Field_Edit_Refusal.Holds_Equipment)
	testing.expect(t, pool_get(&entities.vessel_parts, ring) != nil, "the ring stays")

	// A ring whose +x outside slot is the battery's box, joined to the
	// first by a truss over the battery.
	add_test_vessel_part(&simulation, content, "iron_fuselage_ring", frame.id, {-6, 0, -2})
	add_test_vessel_part(&simulation, content, "iron_truss", frame.id, {-2, 1, 0})
	testing.expect_value(t, pick_up_test_cell(&simulation, content, frame.id, {-1, 0, -1}), Field_Edit_Refusal.None)
	testing.expect(t, pool_get(&entities.vessel_parts, ring) == nil, "the first ring comes off")
	testing.expect(t, pool_get(&entities.vessel_parts, battery) != nil, "the battery stays")
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "iron_fuselage_ring")), 1)

	_, trusses := start_test_vessel(&simulation, content, "iron_truss", metres_to_position_units(20), 0)
	add_test_vessel_part(&simulation, content, "iron_truss", trusses.id, {1, 0, 0})
	add_test_vessel_part(&simulation, content, "iron_truss", trusses.id, {2, 0, 0})
	testing.expect_value(t, len(entities.vessels), 2)
	testing.expect_value(t, pick_up_test_cell(&simulation, content, trusses.id, {1, 0, 0}), Field_Edit_Refusal.Holds_The_Vessel_Together)
	testing.expect(t, entity_at(entities, {1, 0, 0}, trusses.id) != NO_ENTITY, "the middle truss stays")
	for cell in ([?]World_Coordinate{{2, 0, 0}, {1, 0, 0}, {0, 0, 0}}) {
		testing.expect_value(t, pick_up_test_cell(&simulation, content, trusses.id, cell), Field_Edit_Refusal.None)
		testing.expect_value(t, entity_at(entities, cell, trusses.id), NO_ENTITY)
	}
	_, frame_found := find_frame(&entities.frames, trusses.id)
	testing.expect(t, !frame_found, "the last truss takes the frame")
	testing.expect_value(t, vessel_index(entities, trusses.id), -1)
	testing.expect_value(t, len(entities.vessels), 1)
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "iron_truss")), 3)
}
