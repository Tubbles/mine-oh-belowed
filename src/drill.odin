package game

import "generation_seed"

// Mining drills (doc/logistics.md): a square entity placed with
// at least one footprint cell over a surface vein's footprint disc, mined
// outcrop or not (work item 0048). It taps the vein's
// reservoir, not the blocks: every cycle it draws one unit, picked by the
// vein type's output mix, and drops it into the cell in front of its
// arrow through the item transfer interface. With nowhere to drop it the
// drill holds the unit and waits, since there are no items on the ground.
// The direction is Entity_Common.rotation (0 is +x, like belts). A burner
// drill has a fuel slot; an electric drill (no fuel slot) mines at its
// power network's satisfaction through power credit (power_machine.odin).
// A bore drill (work item 0035, a machine with boring_seconds) taps a deep
// vein under its footprint's centre column instead of a surface one, and
// bores that long, in ticks of work, before its first cycle. A drill with
// a revival port keeps an exhausted finite vein producing at half rate
// while the port holds mining fluid (vein revival, DESIGN.md The world).
// Mining productivity levels (work item 0041) add their effect per mille
// to a drill's productivity credit for every unit drawn; each full 1000
// is one extra unit of the same item that costs the vein nothing and goes
// out after the drawn one.

DRILL_SLOT_COUNT :: 1
DRILL_FUEL_SLOT :: 0
// Keeps the draw stream apart from the generation purposes of the seed.
VEIN_DRAW_SALT :: u64(0x6472_696c_6c5f_7631)
// The grade roll hashes the draw hash once more, so it is independent of
// the output roll.
VEIN_GRADE_SALT :: u64(0x6772_6164_655f_7631)
// Ore grades (DESIGN.md, Automation and logistics): the low grade share in
// parts per million rises linearly from 10 percent at a full reservoir to
// 60 percent with 5 percent left, and stays there. Infinite veins stay at
// the start.
LOW_GRADE_START_PPM :: 100_000
LOW_GRADE_END_PPM :: 600_000
LOW_GRADE_END_REMAINING_PERCENT :: 5
PARTS_PER_MILLION :: 1_000_000
// Vein revival: a revived drill takes this many cycles per unit and this
// many litres of its revival port's fluid.
REVIVAL_CYCLE_FACTOR :: 2
REVIVAL_LITRES_PER_UNIT :: 10
// The revival port is a drill's only fluid port (machine_fluid_ports.odin).
REVIVAL_PORT :: 0

// No_Fuel first, so a freshly placed drill without fuel does not count as
// entering a stall.
Drill_State :: enum u8 {
	No_Fuel,
	Mining,
	Waiting_For_Room,
	Vein_Exhausted,
	Unpowered,
	Boring,
	Revived,
	// Nothing stands in the drop cell to take the held unit (couch test 1:
	// "waiting for room" hid that the cell was empty).
	No_Output,
	// What stands in the drop cell never takes the held unit's kind (a
	// drill fed gravel, couch test 1): waits like a full target, but says
	// which item is refused.
	Output_Refused,
}

// The state line of a drill: the refused item's name fills in the Output_Refused text.
drill_state_text :: proc(drill: Drill, items: Item_Registry) -> string {
	if drill.state == .Output_Refused {
		return format_message_text(text(drill_state_keys[drill.state]), item_name(items, drill.held.item))
	}
	return text(drill_state_keys[drill.state])
}

@(rodata)
drill_state_keys := [Drill_State]string {
	.No_Fuel          = "machine_state_no_fuel",
	.Mining           = "machine_state_mining",
	.Waiting_For_Room = "machine_state_waiting_for_room",
	.Vein_Exhausted   = "machine_state_vein_exhausted",
	.Unpowered        = "machine_state_unpowered",
	.Boring           = "machine_state_boring",
	.Revived          = "machine_state_revived",
	.No_Output        = "machine_state_no_output",
	.Output_Refused   = "machine_state_output_refused",
}

// held is a drawn unit that found no room yet. slot_count is 1 for a
// burner drill (its fuel slot) and 0 for an electric one. bored_ticks
// counts a bore drill's ticks of boring. buffers and closed are per fluid
// port like a fluid machine's; only the revival port is used.
// productivity_credit is the per mille credit of mining productivity,
// bonus_units the extra units still to go out after held.
Drill :: struct {
	using common:        Entity_Common,
	slot_count:          int,
	slots:               [DRILL_SLOT_COUNT]Item_Stack,
	fuel_joules:         u32,
	fuel_item_joules:    u32,
	vein:                Vein_Id,
	progress_ticks:      u32,
	held:                Item_Stack,
	state:               Drill_State,
	power:               Power_State,
	// Units output over the last minute, for the panel (statistics.odin).
	output_rate:         Machine_Output_Rate,
	bored_ticks:         u32,
	buffers:             [MAXIMUM_FLUID_PORTS]Fluid_Buffer,
	closed:              [MAXIMUM_FLUID_PORTS]bool,
	productivity_credit: u32,
	bonus_units:         u16,
}

make_drill :: proc(common: Entity_Common, vein: Vein_Id, slot_count: int) -> Drill {
	drill := Drill{common = common, slot_count = min(slot_count, DRILL_SLOT_COUNT), slots = {EMPTY_STACK}, vein = vein, held = EMPTY_STACK}
	for &buffer in drill.buffers {
		buffer = EMPTY_FLUID_BUFFER
	}
	return drill
}

drill_is_electric :: proc(drill: Drill) -> bool {
	return drill.slot_count == 0
}

// Pays for one tick of work (mining, boring or revived mining): a tick of
// fuel, or a step of power credit. False with the state set when it cannot
// work this tick; an electric drill in a brownout keeps working, only on
// fewer ticks.
drill_draws_energy :: proc(drill: ^Drill, machine: Machine, items: Item_Registry, tick_rate: int, working: Drill_State) -> bool {
	if drill_is_electric(drill^) {
		if !power_is_on(drill.power) {
			drill.state = .Unpowered
			return false
		}
		drill.state = working
		return take_power_step(&drill.power)
	}
	per_tick := fuel_joules_per_tick(machine, tick_rate)
	if !refuel_from_slot(&drill.fuel_joules, &drill.fuel_item_joules, &drill.slots[DRILL_FUEL_SLOT], items, per_tick) {
		drill.state = .No_Fuel
		return false
	}
	drill.fuel_joules -= per_tick
	drill.state = working
	return true
}

drill_is_bore :: proc(machine: Machine) -> bool {
	return machine.boring_seconds > 0
}

drill_boring_ticks :: proc(machine: Machine, tick_rate: int) -> u32 {
	return machine.boring_seconds * u32(tick_rate)
}

drill_is_boring :: proc(drill: Drill, machine: Machine, tick_rate: int) -> bool {
	return drill.bored_ticks < drill_boring_ticks(machine, tick_rate)
}

// The revival port holds at least a unit's worth of its fluid.
drill_can_revive :: proc(drill: Drill, machine: Machine) -> bool {
	if !machine.revival_port {
		return false
	}
	buffer := drill.buffers[REVIVAL_PORT]
	return buffer.fluid == machine.fluid_ports[REVIVAL_PORT].filter && buffer.level >= REVIVAL_LITRES_PER_UNIT
}

// What the drill would do this tick given energy: bore, mine, mine an
// exhausted vein through its revival port, or nothing (Vein_Exhausted,
// also for a drill without a registered vein).
drill_activity :: proc(drill: Drill, machine: Machine, vein: ^Vein, infinite: bool, tick_rate: int) -> Drill_State {
	switch {
	case vein == nil:
		return .Vein_Exhausted
	case drill_is_boring(drill, machine, tick_rate):
		return .Boring
	case !vein_is_exhausted(vein^, infinite):
		return .Mining
	case drill_can_revive(drill, machine):
		return .Revived
	}
	return .Vein_Exhausted
}

// 60 s times the tick rate times the reference ore share over the ore
// rate: 192 ticks for 15 ore per minute at 80 percent.
drill_cycle_ticks :: proc(machine: Machine, tick_rate: int) -> u32 {
	units := u64(tick_rate) * 60 * u64(machine.rate_reference_ore_percent)
	return max(u32(units / (100 * u64(max(machine.items_per_minute, 1)))), 1)
}

// A revived drill takes REVIVAL_CYCLE_FACTOR cycles per unit.
drill_active_cycle_ticks :: proc(machine: Machine, revived: bool, tick_rate: int) -> u32 {
	ticks := drill_cycle_ticks(machine, tick_rate)
	return revived ? ticks * REVIVAL_CYCLE_FACTOR : ticks
}

drill_units_per_minute :: proc(machine: Machine, tick_rate: int, revived := false) -> f32 {
	return f32(tick_rate) * 60 / f32(drill_active_cycle_ticks(machine, revived, tick_rate))
}

// The cell in front of the footprint's middle on the arrow side, at
// ground level. A side two cells wide has no middle cell, and the one on
// the arrow's left is taken.
drill_drop_cell :: proc(drill: Drill, machine: Machine) -> World_Coordinate {
	return drill_drop_cell_at(drill.origin, drill.rotation, machine)
}

// The drop cell of a drill at origin with rotation, for placed drills and
// the placement ghost alike.
drill_drop_cell_at :: proc(origin: World_Coordinate, rotation: u8, machine: Machine) -> World_Coordinate {
	width, depth := machine.footprint.x, machine.footprint.z
	offset := rotate_footprint_cell({width, (depth - 1) / 2}, width, depth, rotation)
	return origin + {offset.x, 0, offset.y}
}

// Why a held unit did not go out: nothing stands in the drop cell, what
// stands there never takes the item's kind, or it has no room right now.
drill_blocked_state :: proc(entities: ^Entities, content: Simulation_Content, drill: Drill, machine: Machine) -> Drill_State {
	target := entity_at(entities, drill_drop_cell(drill, machine))
	switch {
	case target == NO_ENTITY:
		return .No_Output
	case !entity_takes_item_kind(entities, content, target, drill.held.item):
		return .Output_Refused
	}
	return .Waiting_For_Room
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
// depends on which drill or which tick takes it. A deep vein mixes in its
// layer, so it never shares a stream with the surface vein of the same
// region and index. Surface veins mix in no layer, so they keep their own
// draw stream and an existing world draws the same units from them.
vein_draw_hash :: proc(seed: u64, vein: Vein) -> u64 {
	hash := generation_seed.hash_combine(generation_seed.hash_combine(seed, VEIN_DRAW_SALT), generation_seed.pack_pair(vein.id.region.x, vein.id.region.y))
	hash = generation_seed.hash_combine(generation_seed.hash_combine(hash, u64(vein.id.index)), vein.draws)
	if vein_is_deep(vein) {
		hash = generation_seed.hash_combine(hash, u64(vein.id.layer))
	}
	return hash
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
	roll := generation_seed.hash_to_range(hash, 0, total - 1)
	for weight, index in weights {
		roll -= weight
		if roll < 0 {
			return index
		}
	}
	return -1
}

// The low grade share of the next draw in parts per million. A finite
// vein's size at generation is what is left plus what was drawn, since
// every draw takes one unit.
low_grade_share_ppm :: proc(vein: Vein, infinite: bool) -> i64 {
	remaining := vein_remaining_total(vein)
	initial := remaining + i64(vein.draws)
	if infinite || initial <= 0 {
		return LOW_GRADE_START_PPM
	}
	depleted := initial - remaining
	span := initial * (100 - LOW_GRADE_END_REMAINING_PERCENT)
	rise := i64(LOW_GRADE_END_PPM - LOW_GRADE_START_PPM) * depleted * 100 / span
	return min(LOW_GRADE_START_PPM + rise, LOW_GRADE_END_PPM)
}

// The item a drawn output yields: its low grade twin when the grade roll
// falls under the share (parts per million), otherwise the ore itself.
graded_output :: proc(vein_type: Vein_Type_Content, output: int, low_grade_ppm: i64, draw_hash: u64) -> Item_Id {
	low_grade := vein_type.low_grades[output]
	if low_grade == NO_ITEM {
		return vein_type.outputs[output]
	}
	roll := generation_seed.hash_to_range(generation_seed.hash_combine(draw_hash, VEIN_GRADE_SALT), 0, PARTS_PER_MILLION - 1)
	return roll < low_grade_ppm ? low_grade : vein_type.outputs[output]
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

exhaust_vein :: proc(world: ^World, statistics: ^Statistics, vein: ^Vein) {
	vein.exhausted = true
	statistics.veins_exhausted += 1
	queue_spent_outcrops(world, vein.id)
}

// Takes one unit from the vein. The last unit of a finite vein exhausts
// it, and its outcrop turns to spent rock at the end of the tick.
draw_from_vein :: proc(world: ^World, statistics: ^Statistics, veins: Vein_Content, vein: ^Vein) -> Item_Id {
	infinite := world.settings.veins_infinite
	return draw_vein_unit(world, statistics, veins, vein, infinite, low_grade_share_ppm(vein^, infinite))
}

// A unit of an exhausted vein through a drill's revival port: by the vein
// type's full mix, taking nothing from it, for REVIVAL_LITRES_PER_UNIT of
// the port's fluid. The grade stays at the depleted end share, since the
// reservoir is spent.
draw_revived_unit :: proc(world: ^World, statistics: ^Statistics, veins: Vein_Content, vein: ^Vein, port: ^Fluid_Buffer) -> Item_Id {
	port.level -= REVIVAL_LITRES_PER_UNIT
	return draw_vein_unit(world, statistics, veins, vein, true, LOW_GRADE_END_PPM)
}

// full draws by the whole mix and takes nothing from the reservoir (an
// infinite or a revived vein). The draw count always grows, since it
// seeds the next draw.
draw_vein_unit :: proc(world: ^World, statistics: ^Statistics, veins: Vein_Content, vein: ^Vein, full: bool, low_grade_ppm: i64) -> Item_Id {
	if vein.type >= len(veins.types) {
		return NO_ITEM
	}
	vein_type := veins.types[vein.type]
	draw_hash := vein_draw_hash(world.settings.seed, vein^)
	output := choose_vein_output(vein^, vein_type, full, draw_hash)
	if output < 0 {
		return NO_ITEM
	}
	item := graded_output(vein_type, output, low_grade_ppm, draw_hash)
	vein.draws += 1
	if !full {
		vein.remaining[output] -= 1
		if vein_is_exhausted(vein^, false) {
			exhaust_vein(world, statistics, vein)
		}
	}
	return item
}

// Into whatever entity stands in the drop cell. Nothing there, or no room,
// keeps the unit held. Output leaving the drill counts as produced, and
// for a bore drill as bore drill units.
output_drill_item :: proc(world: ^World, statistics: ^Statistics, content: Simulation_Content, drill: ^Drill, machine: Machine) -> bool {
	target := entity_at(&world.entities, drill_drop_cell(drill^, machine))
	if target == NO_ENTITY {
		return false
	}
	leftover := entity_insert(&world.entities, content, target, drill.held, drill_drop_lane(&world.entities, drill^, target))
	if !stack_is_empty(leftover) {
		return false
	}
	record_produced(statistics, drill.held.item, int(drill.held.count))
	if drill_is_bore(machine) {
		statistics.bore_drill_units += u64(drill.held.count)
	}
	record_machine_output(&drill.output_rate, statistics.current_second, int(drill.held.count))
	drill.held = next_held_unit(drill, drill.held.item)
	return true
}

// After a unit went out: the next bonus unit of the same item, if any.
next_held_unit :: proc(drill: ^Drill, item: Item_Id) -> Item_Stack {
	if drill.bonus_units == 0 {
		return EMPTY_STACK
	}
	drill.bonus_units -= 1
	return Item_Stack{item = item, count = 1}
}

// Adds the mining productivity of one drawn unit to the credit and turns
// every full 1000 into a bonus unit.
add_productivity :: proc(drill: ^Drill, bonus_per_mille: u32) {
	drill.productivity_credit += bonus_per_mille
	drill.bonus_units += u16(drill.productivity_credit / 1000)
	drill.productivity_credit %= 1000
}

// One tick. A held unit has to go out before anything else happens; fuel
// burns (or power is drawn) and progress counts only while the drill
// works. Veins are never unregistered, so a missing vein only happens to
// a drill placed without one, and it reads as exhausted.
advance_drill :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, drill: ^Drill, tick_rate: int) {
	machine := content.machines.machines[drill.machine]
	if !stack_is_empty(drill.held) && !output_drill_item(world, &records.statistics, content, drill, machine) {
		drill.state = drill_blocked_state(&world.entities, content, drill^, machine)
		return
	}
	vein := registered_vein(world, drill.vein)
	activity := drill_activity(drill^, machine, vein, world.settings.veins_infinite, tick_rate)
	if activity == .Vein_Exhausted {
		drill.state = activity
		return
	}
	if !drill_draws_energy(drill, machine, content.items, tick_rate, activity) {
		return
	}
	if activity == .Boring {
		drill.bored_ticks += 1
		return
	}
	drill.progress_ticks += 1
	if drill.progress_ticks < drill_active_cycle_ticks(machine, activity == .Revived, tick_rate) {
		return
	}
	drill.progress_ticks = 0
	item := activity == .Revived ? draw_revived_unit(world, &records.statistics, content.veins, vein, &drill.buffers[REVIVAL_PORT]) : draw_from_vein(world, &records.statistics, content.veins, vein)
	if item == NO_ITEM {
		return
	}
	drill.held = Item_Stack{item = item, count = 1}
	add_productivity(drill, technology_effect_per_mille(content.technologies, records.research.levels, .Mining_Productivity))
	if !output_drill_item(world, &records.statistics, content, drill, machine) {
		drill.state = drill_blocked_state(&world.entities, content, drill^, machine)
	}
}

// The boring progress while a bore drill bores, else the cycle's.
drill_progress_fraction :: proc(drill: Drill, machine: Machine, tick_rate: int) -> f32 {
	if drill_is_boring(drill, machine, tick_rate) {
		return f32(drill.bored_ticks) / f32(drill_boring_ticks(machine, tick_rate))
	}
	return f32(drill.progress_ticks) / f32(drill_active_cycle_ticks(machine, drill.state == .Revived, tick_rate))
}

drill_burn_fraction :: proc(drill: Drill) -> f32 {
	if drill.fuel_item_joules == 0 {
		return 0
	}
	return f32(drill.fuel_joules) / f32(drill.fuel_item_joules)
}

// What picking the drill up returns besides its fuel: the unit it holds
// and the bonus units after it.
drill_held_stacks :: proc(entities: ^Entities, handle: Entity_Handle) -> []Item_Stack {
	drill := pool_get(&entities.drills, handle)
	if drill == nil || stack_is_empty(drill.held) {
		return nil
	}
	return slice_of_one(Item_Stack{item = drill.held.item, count = drill.held.count + drill.bonus_units})
}

// A drill needs at least one footprint cell over a surface vein's
// footprint disc, whatever block is left there (work item 0048). The
// first found, in footprint order, is the vein it taps.
drill_vein_under :: proc(world: ^World, cells: []World_Coordinate, bottom: i32) -> (vein: Vein_Id, found: bool) {
	for cell in cells {
		if cell.y != bottom {
			continue
		}
		if vein, found = vein_at_column(world, cell.x, cell.z); found {
			return
		}
	}
	return {}, false
}

// A bore drill taps the deep vein whose disc holds its footprint's centre
// column (for an even side, the column just past the middle).
bore_drill_vein_under :: proc(world: ^World, origin: World_Coordinate, size: [3]i32) -> (vein: Vein_Id, found: bool) {
	return deep_vein_at_column(world, origin.x + size.x / 2, origin.z + size.z / 2)
}

vein_remaining_total :: proc(vein: Vein) -> i64 {
	total: i64
	for amount in vein.remaining {
		total += amount
	}
	return total
}
