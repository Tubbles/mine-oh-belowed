package game

// Inserters (doc/logistics.md): a 1 by 1 by 1 entity that picks one item
// from the cell behind it and drops it into the cell in front, only
// through the item transfer interface. The direction is
// Entity_Common.rotation (0 is +x, like belts).
//
// The cycle is a small state machine counted in ticks. Picking and
// dropping are instant; each swing takes half the cycle derived from the
// machine's items per minute, so with a source and a sink always ready an
// inserter moves exactly its rate. An arm that arrives at the drop and
// finds no room waits there with the item in hand. A burner inserter
// burns fuel only on the ticks its arm moves; electric ones stay
// unpowered until power exists (M4). A burner with an empty buffer and an
// empty fuel slot feeds itself: fuel it is about to pick, or fuel in its
// hand, goes into its own fuel slot instead of on to the target.

INSERTER_SLOT_COUNT :: 1
INSERTER_FUEL_SLOT :: 0

Inserter_Phase :: enum u8 {
	At_Pickup,
	Swinging_To_Drop,
	At_Drop,
	Swinging_Back,
}

Inserter_State :: enum u8 {
	Idle,
	Moving,
	No_Fuel,
	Waiting_For_Room,
	Unpowered,
	No_Filter,
}

// slot_count is 1 with a fuel slot (burner) and 0 otherwise. filter is an
// item id only, the filter slot holds no item.
Inserter :: struct {
	using common:     Entity_Common,
	slot_count:       int,
	slots:            [INSERTER_SLOT_COUNT]Item_Stack,
	fuel_joules:      u32,
	fuel_item_joules: u32,
	filter:           Item_Id,
	held:             Item_Stack,
	phase:            Inserter_Phase,
	phase_ticks:      u32,
	state:            Inserter_State,
	powered:          bool,
}

@(rodata)
inserter_state_keys := [Inserter_State]string {
	.Idle             = "machine_state_idle",
	.Moving           = "machine_state_moving",
	.No_Fuel          = "machine_state_no_fuel",
	.Waiting_For_Room = "machine_state_waiting_for_room",
	.Unpowered        = "machine_state_unpowered",
	.No_Filter        = "machine_state_no_filter",
}

make_inserter :: proc(common: Entity_Common, machine: Machine) -> Inserter {
	return Inserter{common = common, slot_count = machine.slot_count, slots = {EMPTY_STACK}, filter = NO_ITEM, held = EMPTY_STACK}
}

inserter_pickup_cell :: proc(inserter: Inserter) -> World_Coordinate {
	return inserter.origin - belt_direction_offset(inserter.rotation)
}

inserter_drop_cell :: proc(inserter: Inserter) -> World_Coordinate {
	return inserter.origin + belt_direction_offset(inserter.rotation)
}

inserter_is_electric :: proc(machine: Machine) -> bool {
	return machine.slot_count == 0
}

inserter_has_filter :: proc(machine: Machine) -> bool {
	return machine.filter_slot_count > 0
}

// 60 s times the tick rate over the rate: 100 ticks at 36 per minute.
inserter_cycle_ticks :: proc(machine: Machine, tick_rate: int) -> u32 {
	return max(u32(tick_rate) * 60 / max(machine.items_per_minute, 1), 2)
}

// The swing to the drop is the first half of the cycle, the swing back
// the rest.
inserter_swing_ticks :: proc(machine: Machine, tick_rate: int, phase: Inserter_Phase) -> u32 {
	cycle := inserter_cycle_ticks(machine, tick_rate)
	return phase == .Swinging_To_Drop ? cycle / 2 : cycle - cycle / 2
}

// The lane on the belt's side away from the inserter. A belt running
// straight towards or away from the inserter has no far side and takes
// items on its right lane.
far_belt_lane :: proc(inserter_direction, belt_direction: u8) -> Belt_Lane {
	if inserter_direction % 4 == turn_right(belt_direction, 3) {
		return .Left
	}
	return .Right
}

inserter_drop_lane :: proc(entities: ^Entities, inserter: Inserter, target: Entity_Handle) -> Belt_Lane {
	belt := pool_get(&entities.belts, target)
	if belt == nil {
		return .Left
	}
	return far_belt_lane(inserter.rotation, belt.rotation)
}

// The first item the source gives that the target ever takes, or NO_ITEM.
inserter_pickable_item :: proc(entities: ^Entities, content: Simulation_Content, source, target: Entity_Handle, filter: Item_Id) -> Item_Id {
	for item in entity_offered_items(entities, source, filter) {
		if entity_takes_item_kind(entities, content, target, item) {
			return item
		}
	}
	return NO_ITEM
}

// Fuel for one more tick of movement is in the buffer or the slot.
inserter_can_move :: proc(inserter: Inserter, machine: Machine, items: Item_Registry, tick_rate: int) -> bool {
	if inserter_is_electric(machine) {
		return inserter.powered
	}
	if inserter.fuel_joules >= fuel_joules_per_tick(machine, tick_rate) {
		return true
	}
	fuel := inserter.slots[INSERTER_FUEL_SLOT]
	return !stack_is_empty(fuel) && item_is_fuel(items, fuel.item)
}

burn_inserter_fuel :: proc(inserter: ^Inserter, machine: Machine, items: Item_Registry, tick_rate: int) -> bool {
	if inserter_is_electric(machine) {
		return inserter.powered
	}
	per_tick := fuel_joules_per_tick(machine, tick_rate)
	if !refuel_from_slot(&inserter.fuel_joules, &inserter.fuel_item_joules, &inserter.slots[INSERTER_FUEL_SLOT], items, per_tick) {
		return false
	}
	inserter.fuel_joules -= per_tick
	return true
}

// A burner out of fuel with an empty fuel slot may take a fuel item for
// itself.
inserter_can_feed_itself :: proc(inserter: Inserter, item: Item_Id, items: Item_Registry) -> bool {
	return inserter.slot_count > 0 && stack_is_empty(inserter.slots[INSERTER_FUEL_SLOT]) && item_is_fuel(items, item)
}

// The fuel item it was about to pick goes into its fuel slot.
feed_inserter_from_source :: proc(entities: ^Entities, content: Simulation_Content, inserter: ^Inserter, source: Entity_Handle, item: Item_Id) -> bool {
	if !inserter_can_feed_itself(inserter^, item, content.items) {
		return false
	}
	inserter.slots[INSERTER_FUEL_SLOT] = entity_extract(entities, content, source, item, 1)
	return !stack_is_empty(inserter.slots[INSERTER_FUEL_SLOT])
}

// The fuel item in its hand goes into its fuel slot; the arm then swings
// on empty handed.
feed_inserter_from_hand :: proc(inserter: ^Inserter, items: Item_Registry) -> bool {
	if stack_is_empty(inserter.held) || !inserter_can_feed_itself(inserter^, inserter.held.item, items) {
		return false
	}
	inserter.slots[INSERTER_FUEL_SLOT] = inserter.held
	inserter.held = EMPTY_STACK
	return true
}

// Nothing to pick leaves the arm idle over the pickup cell; with an item
// but no fuel it does not pick at all, unless it can feed itself.
pick_with_inserter :: proc(entities: ^Entities, content: Simulation_Content, inserter: ^Inserter, machine: Machine, tick_rate: int) {
	if inserter_has_filter(machine) && inserter.filter == NO_ITEM {
		inserter.state = .No_Filter
		return
	}
	source := entity_at(entities, inserter_pickup_cell(inserter^))
	target := entity_at(entities, inserter_drop_cell(inserter^))
	item := inserter_pickable_item(entities, content, source, target, inserter.filter)
	if item == NO_ITEM {
		inserter.state = .Idle
		return
	}
	if !inserter_can_move(inserter^, machine, content.items, tick_rate) {
		if !feed_inserter_from_source(entities, content, inserter, source, item) {
			inserter.state = .No_Fuel
			return
		}
		if item = inserter_pickable_item(entities, content, source, target, inserter.filter); item == NO_ITEM {
			inserter.state = .Idle
			return
		}
	}
	inserter.held = entity_extract(entities, content, source, item, 1)
	inserter.phase, inserter.phase_ticks, inserter.state = .Swinging_To_Drop, 0, .Moving
}

drop_with_inserter :: proc(entities: ^Entities, content: Simulation_Content, inserter: ^Inserter) {
	target := entity_at(entities, inserter_drop_cell(inserter^))
	leftover := entity_insert(entities, content, target, inserter.held, inserter_drop_lane(entities, inserter^, target))
	if !stack_is_empty(leftover) {
		inserter.state = .Waiting_For_Room
		return
	}
	inserter.held = EMPTY_STACK
	inserter.phase, inserter.phase_ticks, inserter.state = .Swinging_Back, 0, .Moving
}

// One tick of movement; out of fuel the arm stops where it is. Arriving
// at either end picks or drops in the same tick.
swing_inserter :: proc(entities: ^Entities, content: Simulation_Content, inserter: ^Inserter, machine: Machine, tick_rate: int) {
	burned := burn_inserter_fuel(inserter, machine, content.items, tick_rate)
	if !burned && feed_inserter_from_hand(inserter, content.items) {
		burned = burn_inserter_fuel(inserter, machine, content.items, tick_rate)
	}
	if !burned {
		inserter.state = .No_Fuel
		return
	}
	inserter.state = .Moving
	inserter.phase_ticks += 1
	if inserter.phase_ticks < inserter_swing_ticks(machine, tick_rate, inserter.phase) {
		return
	}
	inserter.phase_ticks = 0
	if inserter.phase == .Swinging_To_Drop {
		inserter.phase = .At_Drop
		drop_with_inserter(entities, content, inserter)
	} else {
		inserter.phase = .At_Pickup
		pick_with_inserter(entities, content, inserter, machine, tick_rate)
	}
}

advance_inserter :: proc(entities: ^Entities, content: Simulation_Content, inserter: ^Inserter, tick_rate: int) {
	machine := content.machines.machines[inserter.machine]
	if inserter_is_electric(machine) && !inserter.powered {
		inserter.state = .Unpowered
		return
	}
	switch inserter.phase {
	case .At_Pickup:
		pick_with_inserter(entities, content, inserter, machine, tick_rate)
	case .At_Drop:
		drop_with_inserter(entities, content, inserter)
	case .Swinging_To_Drop, .Swinging_Back:
		swing_inserter(entities, content, inserter, machine, tick_rate)
	}
}

// 0 with the arm over the pickup cell, 1 over the drop cell.
inserter_arm_fraction :: proc(inserter: Inserter, machine: Machine, tick_rate: int) -> f32 {
	swing := f32(inserter_swing_ticks(machine, tick_rate, inserter.phase))
	switch inserter.phase {
	case .At_Pickup:
		return 0
	case .Swinging_To_Drop:
		return f32(inserter.phase_ticks) / swing
	case .At_Drop:
		return 1
	case .Swinging_Back:
		return 1 - f32(inserter.phase_ticks) / swing
	}
	return 0
}

// How far through the whole cycle the arm is, for the panel.
inserter_cycle_fraction :: proc(inserter: Inserter, machine: Machine, tick_rate: int) -> f32 {
	cycle := inserter_cycle_ticks(machine, tick_rate)
	to_drop := inserter_swing_ticks(machine, tick_rate, .Swinging_To_Drop)
	switch inserter.phase {
	case .At_Pickup:
		return 0
	case .Swinging_To_Drop:
		return f32(inserter.phase_ticks) / f32(cycle)
	case .At_Drop:
		return f32(to_drop) / f32(cycle)
	case .Swinging_Back:
		return f32(to_drop + inserter.phase_ticks) / f32(cycle)
	}
	return 0
}

// What picking the inserter up returns besides its fuel: the item in hand.
inserter_held_stacks :: proc(entities: ^Entities, handle: Entity_Handle) -> []Item_Stack {
	inserter := pool_get(&entities.inserters, handle)
	if inserter == nil || stack_is_empty(inserter.held) {
		return nil
	}
	return slice_of_one(inserter.held)
}

slice_of_one :: proc(stack: Item_Stack) -> []Item_Stack {
	stacks := make([]Item_Stack, 1, context.temp_allocator)
	stacks[0] = stack
	return stacks
}

inserter_burn_fraction :: proc(inserter: Inserter) -> f32 {
	if inserter.fuel_item_joules == 0 {
		return 0
	}
	return f32(inserter.fuel_joules) / f32(inserter.fuel_item_joules)
}
