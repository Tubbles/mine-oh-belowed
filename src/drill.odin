package game

// The burner mining drill (doc/logistics.md): a square entity placed with
// at least one footprint cell on a vein outcrop. It taps the vein's
// reservoir, not the blocks: every cycle it draws one unit, picked by the
// vein type's output mix, and drops it into the cell in front of its
// arrow through the item transfer interface. With nowhere to drop it the
// drill holds the unit and waits, since there are no items on the ground.
// The direction is Entity_Common.rotation (0 is +x, like belts).

DRILL_SLOT_COUNT :: 1
DRILL_FUEL_SLOT :: 0
// Keeps the draw stream apart from the generation purposes of the seed.
VEIN_DRAW_SALT :: u64(0x6472_696c_6c5f_7631)

// No_Fuel first, so a freshly placed drill without fuel does not count as
// entering a stall.
Drill_State :: enum u8 {
	No_Fuel,
	Mining,
	Waiting_For_Room,
	Vein_Exhausted,
}

@(rodata)
drill_state_keys := [Drill_State]string {
	.No_Fuel          = "machine_state_no_fuel",
	.Mining           = "machine_state_mining",
	.Waiting_For_Room = "machine_state_waiting_for_room",
	.Vein_Exhausted   = "machine_state_vein_exhausted",
}

// held is a drawn unit that found no room yet.
Drill :: struct {
	using common:     Entity_Common,
	slots:            [DRILL_SLOT_COUNT]Item_Stack,
	fuel_joules:      u32,
	fuel_item_joules: u32,
	vein:             Vein_Id,
	progress_ticks:   u32,
	held:             Item_Stack,
	state:            Drill_State,
}

make_drill :: proc(common: Entity_Common, vein: Vein_Id) -> Drill {
	return Drill{common = common, slots = {EMPTY_STACK}, vein = vein, held = EMPTY_STACK}
}

// 60 s times the tick rate times the reference ore share over the ore
// rate: 192 ticks for 15 ore per minute at 80 percent.
drill_cycle_ticks :: proc(machine: Machine, tick_rate: int) -> u32 {
	units := u64(tick_rate) * 60 * u64(machine.rate_reference_ore_percent)
	return max(u32(units / (100 * u64(max(machine.items_per_minute, 1)))), 1)
}

drill_units_per_minute :: proc(machine: Machine, tick_rate: int) -> f32 {
	return f32(tick_rate) * 60 / f32(drill_cycle_ticks(machine, tick_rate))
}

// The cell in front of the footprint's middle on the arrow side, at
// ground level. A side two cells wide has no middle cell, and the one on
// the arrow's left is taken.
drill_drop_cell :: proc(drill: Drill, machine: Machine) -> World_Coordinate {
	width, depth := machine.footprint.x, machine.footprint.z
	offset := rotate_footprint_cell({width, (depth - 1) / 2}, width, depth, drill.rotation)
	return drill.origin + {offset.x, 0, offset.y}
}

// The lane on the belt's side facing the drill. A belt running in line
// with the arrow has no such side and takes items on its right lane, like
// an inserter's drop.
drill_drop_lane :: proc(entities: ^Entities, drill: Drill, target: Entity_Handle) -> Belt_Lane {
	belt := pool_get(&entities.belts, target)
	if belt == nil || drill.rotation % 2 == belt.rotation % 2 {
		return .Right
	}
	return far_belt_lane(drill.rotation, belt.rotation) == .Left ? .Right : .Left
}

// Seeded by the world seed, the vein and its draw count, so a draw never
// depends on which drill or which tick takes it.
vein_draw_hash :: proc(seed: u64, vein: Vein) -> u64 {
	hash := hash_combine(hash_combine(seed, VEIN_DRAW_SALT), pack_pair(vein.id.region.x, vein.id.region.y))
	return hash_combine(hash_combine(hash, u64(vein.id.index)), vein.draws)
}

// Each output weighs its percent while it has units left; in an infinite
// vein every output always does. -1 when nothing is left.
choose_vein_output :: proc(vein: Vein, vein_type: Vein_Type_Content, infinite: bool, hash: u64) -> int {
	weights: [MAXIMUM_VEIN_OUTPUTS]i64
	total: i64
	for index in 0 ..< vein_type.output_count {
		if infinite || vein.remaining[index] > 0 {
			weights[index] = vein_type.percents[index]
			total += weights[index]
		}
	}
	if total == 0 {
		return -1
	}
	roll := hash_to_range(hash, 0, total - 1)
	for weight, index in weights {
		roll -= weight
		if roll < 0 {
			return index
		}
	}
	return -1
}

vein_is_exhausted :: proc(vein: Vein, infinite: bool) -> bool {
	if infinite {
		return false
	}
	for amount in vein.remaining {
		if amount > 0 {
			return false
		}
	}
	return true
}

exhaust_vein :: proc(world: ^World, vein: ^Vein) {
	vein.exhausted = true
	world.statistics.veins_exhausted += 1
	queue_spent_outcrops(world, vein.id)
}

// Takes one unit from the vein. The last unit of a finite vein exhausts
// it, and its outcrop turns to spent rock at the end of the tick.
draw_from_vein :: proc(world: ^World, veins: Vein_Content, vein: ^Vein) -> Item_Id {
	if vein.type >= len(veins.types) {
		return NO_ITEM
	}
	vein_type := veins.types[vein.type]
	infinite := world.settings.veins_infinite
	output := choose_vein_output(vein^, vein_type, infinite, vein_draw_hash(world.settings.seed, vein^))
	if output < 0 {
		return NO_ITEM
	}
	vein.draws += 1
	if !infinite {
		vein.remaining[output] -= 1
		if vein_is_exhausted(vein^, false) {
			exhaust_vein(world, vein)
		}
	}
	return vein_type.outputs[output]
}

// Into whatever entity stands in the drop cell. Nothing there, or no room,
// keeps the unit held. Output leaving the drill counts as produced.
output_drill_item :: proc(world: ^World, content: Simulation_Content, drill: ^Drill, machine: Machine) -> bool {
	target := entity_at(&world.entities, drill_drop_cell(drill^, machine))
	if target == NO_ENTITY {
		return false
	}
	leftover := entity_insert(&world.entities, content, target, drill.held, drill_drop_lane(&world.entities, drill^, target))
	if !stack_is_empty(leftover) {
		return false
	}
	record_produced(&world.statistics, drill.held.item, int(drill.held.count))
	drill.held = EMPTY_STACK
	return true
}

// One tick. A held unit has to go out before anything else happens; fuel
// burns and progress counts only while the drill mines. Veins are never
// unregistered, so a missing vein only happens to a drill placed without
// one, and it reads as exhausted.
advance_drill :: proc(world: ^World, content: Simulation_Content, drill: ^Drill, tick_rate: int) {
	machine := content.machines.machines[drill.machine]
	if !stack_is_empty(drill.held) && !output_drill_item(world, content, drill, machine) {
		drill.state = .Waiting_For_Room
		return
	}
	vein := registered_vein(world, drill.vein)
	if vein == nil || vein_is_exhausted(vein^, world.settings.veins_infinite) {
		drill.state = .Vein_Exhausted
		return
	}
	per_tick := fuel_joules_per_tick(machine, tick_rate)
	if !refuel_from_slot(&drill.fuel_joules, &drill.fuel_item_joules, &drill.slots[DRILL_FUEL_SLOT], content.items, per_tick) {
		drill.state = .No_Fuel
		return
	}
	drill.fuel_joules -= per_tick
	drill.state = .Mining
	drill.progress_ticks += 1
	if drill.progress_ticks < drill_cycle_ticks(machine, tick_rate) {
		return
	}
	drill.progress_ticks = 0
	item := draw_from_vein(world, content.veins, vein)
	if item == NO_ITEM {
		return
	}
	drill.held = Item_Stack{item = item, count = 1}
	if !output_drill_item(world, content, drill, machine) {
		drill.state = .Waiting_For_Room
	}
}

drill_progress_fraction :: proc(drill: Drill, machine: Machine, tick_rate: int) -> f32 {
	return f32(drill.progress_ticks) / f32(drill_cycle_ticks(machine, tick_rate))
}

drill_burn_fraction :: proc(drill: Drill) -> f32 {
	if drill.fuel_item_joules == 0 {
		return 0
	}
	return f32(drill.fuel_joules) / f32(drill.fuel_item_joules)
}

// What picking the drill up returns besides its fuel: the unit it holds.
drill_held_stacks :: proc(entities: ^Entities, handle: Entity_Handle) -> []Item_Stack {
	drill := pool_get(&entities.drills, handle)
	if drill == nil || stack_is_empty(drill.held) {
		return nil
	}
	return slice_of_one(drill.held)
}

// A drill needs a vein outcrop under at least one footprint cell. The
// first found, in footprint order, is the vein it taps.
drill_vein_under :: proc(world: ^World, veins: Vein_Content, cells: []World_Coordinate, bottom: i32) -> (vein: Vein_Id, found: bool) {
	for cell in cells {
		if cell.y != bottom {
			continue
		}
		if vein, found = outcrop_vein_at(world, veins, cell + {0, -1, 0}); found {
			return
		}
	}
	return {}, false
}

vein_remaining_total :: proc(vein: Vein) -> i64 {
	total: i64
	for amount in vein.remaining {
		total += amount
	}
	return total
}
