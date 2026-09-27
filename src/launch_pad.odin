package game

import "core:fmt"
import "core:slice"

// The launch pad and shipments (work item 0040, DESIGN.md phase 8). A pad
// holds one slot per rocket part (machines.sjson launch_parts, in slot
// order), a fuel input port and a cargo section of any items. Its states:
//
// - waiting for parts, or ready to assemble once every part slot holds a
//   rocket's count and the port its fuel;
// - assembling, started by the panel's Assemble button: the powered work
//   runs in ASSEMBLY_STAGES equal stages, and each stage takes its share
//   of the parts and the fuel when it starts, so assembly pauses where a
//   share is missing (the player took parts out) and goes on once it is
//   back;
// - rocket ready;
// - launching, started by the panel's Launch button or Interact while the
//   cargo holds something: the cargo is taken, a shipment {tick, items and
//   counts} is recorded on the world with the statistics, and the ascent
//   runs for launch_seconds before the pad waits for parts again.
//
// A launch is requested (launch_requested) and served after the entity
// tick by apply_launch_requests, which knows the tick for the shipment.
// Inserters put parts into their slots and anything else into the cargo
// section, never parts into the cargo; nothing is ever taken out by them.

LAUNCH_PAD_CARGO_SLOTS :: 8
MAXIMUM_LAUNCH_PARTS :: 3
LAUNCH_PAD_SLOT_COUNT :: MAXIMUM_LAUNCH_PARTS + LAUNCH_PAD_CARGO_SLOTS
LAUNCH_PAD_FUEL_PORT :: 0
ASSEMBLY_STAGES :: 10

Launch_Part_Definition :: struct {
	item:  string,
	count: int,
}

Launch_Pad_State :: enum u8 {
	Waiting_For_Parts,
	Ready_To_Assemble,
	Assembling,
	Rocket_Ready,
	Launching,
}

@(rodata)
launch_pad_state_keys := [Launch_Pad_State]string {
	.Waiting_For_Parts = "launch_pad_state_waiting_for_parts",
	.Ready_To_Assemble = "launch_pad_state_ready_to_assemble",
	.Assembling        = "launch_pad_state_assembling",
	.Rocket_Ready      = "launch_pad_state_rocket_ready",
	.Launching         = "launch_pad_state_launching",
}

// slots[:part_count] are the part slots, the next LAUNCH_PAD_CARGO_SLOTS
// the cargo. work_ticks counts the powered assembly ticks, stages_taken
// the stages whose share was taken, missing_parts is set while the next
// stage's share is not there, launch_ticks counts the ascent.
Launch_Pad :: struct {
	using common:     Entity_Common,
	part_count:       int,
	slots:            [LAUNCH_PAD_SLOT_COUNT]Item_Stack,
	state:            Launch_Pad_State,
	work_ticks:       u32,
	stages_taken:     u32,
	launch_ticks:     u32,
	missing_parts:    bool,
	launch_requested: bool,
	power:            Power_State,
	buffers:          [MAXIMUM_FLUID_PORTS]Fluid_Buffer,
	closed:           [MAXIMUM_FLUID_PORTS]bool,
}

Shipped_Item :: struct {
	item:  Item_Id,
	count: u32,
}

// cargo[:cargo_count] holds each shipped item once, in the order it first
// appeared in the cargo slots.
Shipment :: struct {
	tick:        u64,
	cargo:       [LAUNCH_PAD_CARGO_SLOTS]Shipped_Item,
	cargo_count: i32,
}

// Loading.

validate_launch_pad_definition :: proc(definition: Machine_Definition) -> string {
	positive := definition.electric_power_kilowatts > 0 && definition.assembly_seconds > 0 && definition.launch_seconds > 0 && definition.launch_fuel_litres > 0
	if !positive {
		return fmt.tprintf("launch pad %q needs a positive electric_power_kilowatts, assembly_seconds, launch_seconds and launch_fuel_litres", definition.id)
	}
	if definition.slots != LAUNCH_PAD_CARGO_SLOTS || definition.fuel_slots != 0 || definition.input_slots != 0 || definition.output_slots != 0 {
		return fmt.tprintf("launch pad %q must have %d cargo slots and no other slot fields", definition.id, LAUNCH_PAD_CARGO_SLOTS)
	}
	if len(definition.launch_parts) < 1 || len(definition.launch_parts) > MAXIMUM_LAUNCH_PARTS {
		return fmt.tprintf("launch pad %q needs 1 to %d launch_parts", definition.id, MAXIMUM_LAUNCH_PARTS)
	}
	return ""
}

// Every part item exists once, and a rocket's count fits one stack.
// Other kinds may not list parts.
resolve_launch_parts :: proc(machine: ^Machine, definition: Machine_Definition, items: Item_Registry) -> string {
	if machine.kind != .Launch_Pad {
		return len(definition.launch_parts) == 0 ? "" : fmt.tprintf("machine %q is no launch pad and may not list launch_parts", definition.id)
	}
	for part, index in definition.launch_parts {
		item, found := find_item_id(items, part.item)
		switch {
		case !found:
			return fmt.tprintf("launch pad %q needs unknown part %q", definition.id, part.item)
		case part.count < 1 || part.count > int(item_stack_size(items, item)):
			return fmt.tprintf("launch pad %q part %q needs a count from 1 to its stack size", definition.id, part.item)
		case launch_part_slot(machine^, item) >= 0:
			return fmt.tprintf("launch pad %q lists part %q twice", definition.id, part.item)
		}
		machine.launch_parts[index] = Item_Stack{item = item, count = u16(part.count)}
		machine.launch_part_count = index + 1
	}
	return ""
}

make_launch_pad :: proc(common: Entity_Common, machine: Machine) -> Launch_Pad {
	pad := Launch_Pad{common = common, part_count = machine.launch_part_count}
	for &slot in pad.slots {
		slot = EMPTY_STACK
	}
	for &buffer in pad.buffers {
		buffer = EMPTY_FLUID_BUFFER
	}
	return pad
}

// Slots and the transfer interface.

launch_pad_slot_count :: proc(pad: Launch_Pad) -> int {
	return pad.part_count + LAUNCH_PAD_CARGO_SLOTS
}

launch_pad_cargo :: proc(pad: ^Launch_Pad) -> []Item_Stack {
	return pad.slots[pad.part_count:][:LAUNCH_PAD_CARGO_SLOTS]
}

// The part slot of an item, or -1 for an item that is no part.
launch_part_slot :: proc(machine: Machine, item: Item_Id) -> int {
	for index in 0 ..< machine.launch_part_count {
		if machine.launch_parts[index].item == item {
			return index
		}
	}
	return -1
}

// A part goes to its slot while that holds less than a rocket takes,
// anything else to the cargo section.
launch_pad_accepting_slot :: proc(pad: ^Launch_Pad, machine: Machine, items: Item_Registry, item: Item_Id) -> (slot: int, ok: bool) {
	slots := pad.slots[:launch_pad_slot_count(pad^)]
	if part := launch_part_slot(machine, item); part >= 0 {
		return limited_accepting_slot(slots, part, item, items, int(machine.launch_parts[part].count))
	}
	cargo, found := first_accepting_slot(slots[pad.part_count:], item, item_stack_size(items, item))
	if !found {
		return -1, false
	}
	return pad.part_count + cargo, true
}

// The player's slot rules in the panel: each part slot takes its part,
// the cargo anything.
launch_pad_slot_filters :: proc(pad: Launch_Pad, machine: Machine) -> []Slot_Filter {
	filters := make([]Slot_Filter, launch_pad_slot_count(pad), context.temp_allocator)
	for index in 0 ..< pad.part_count {
		filters[index] = {kind = .Item, item = machine.launch_parts[index].item}
	}
	return filters
}

// Assembly.

assembly_ticks :: proc(machine: Machine, tick_rate: int) -> u32 {
	return max(machine.assembly_seconds * u32(tick_rate), 1)
}

// How much of total the first `stages` stages take together.
stage_share :: proc(total, stages: u32) -> u32 {
	return total * stages / ASSEMBLY_STAGES
}

// How much of total stage number `stage` (from 0) takes.
stage_amount :: proc(total, stage: u32) -> u32 {
	return stage_share(total, stage + 1) - stage_share(total, stage)
}

fuel_port_litres :: proc(pad: Launch_Pad, machine: Machine) -> i32 {
	fuel := pad.buffers[LAUNCH_PAD_FUEL_PORT]
	return fuel.fluid == machine.fluid_ports[LAUNCH_PAD_FUEL_PORT].filter ? fuel.level : 0
}

// Every part slot and the fuel port hold at least the given stages' share
// of a rocket (ASSEMBLY_STAGES for a whole rocket).
stage_parts_present :: proc(pad: Launch_Pad, machine: Machine, stage: u32, stage_count: u32) -> bool {
	for index in 0 ..< machine.launch_part_count {
		part := machine.launch_parts[index]
		needed := stage_share(u32(part.count), stage + stage_count) - stage_share(u32(part.count), stage)
		if needed > 0 && (pad.slots[index].item != part.item || u32(pad.slots[index].count) < needed) {
			return false
		}
	}
	fuel := stage_share(u32(machine.launch_fuel_litres), stage + stage_count) - stage_share(u32(machine.launch_fuel_litres), stage)
	return u32(fuel_port_litres(pad, machine)) >= fuel
}

launch_parts_present :: proc(pad: Launch_Pad, machine: Machine) -> bool {
	return stage_parts_present(pad, machine, 0, ASSEMBLY_STAGES)
}

// Takes one stage's share of the parts and the fuel, counted as consumed.
take_stage_share :: proc(pad: ^Launch_Pad, machine: Machine, statistics: ^Statistics, stage: u32) {
	for index in 0 ..< machine.launch_part_count {
		amount := int(stage_amount(u32(machine.launch_parts[index].count), stage))
		taken := take_from_slot(&pad.slots[index], amount)
		record_consumed(statistics, machine.launch_parts[index].item, taken)
	}
	fuel := &pad.buffers[LAUNCH_PAD_FUEL_PORT]
	litres := i32(stage_amount(u32(machine.launch_fuel_litres), stage))
	fuel.level -= litres
	record_fluid_consumed(statistics, fuel.fluid, int(litres))
	if fuel.level == 0 {
		fuel.fluid = NO_FLUID
	}
}

idle_launch_pad_state :: proc(pad: Launch_Pad, machine: Machine) -> Launch_Pad_State {
	return launch_parts_present(pad, machine) ? .Ready_To_Assemble : .Waiting_For_Parts
}

// The stage the next work tick belongs to.
current_stage :: proc(pad: Launch_Pad, machine: Machine, tick_rate: int) -> u32 {
	return pad.work_ticks * ASSEMBLY_STAGES / assembly_ticks(machine, tick_rate)
}

// Assembling, with the current stage's share taken or there to take.
launch_pad_wants_power :: proc(pad: Launch_Pad, machine: Machine, tick_rate: int) -> bool {
	if pad.state != .Assembling {
		return false
	}
	stage := current_stage(pad, machine, tick_rate)
	return pad.stages_taken > stage || stage_parts_present(pad, machine, stage, 1)
}

// The Assemble button: only with every part and the fuel there.
start_assembly :: proc(pad: ^Launch_Pad, machine: Machine) -> bool {
	if (pad.state != .Waiting_For_Parts && pad.state != .Ready_To_Assemble) || !launch_parts_present(pad^, machine) {
		return false
	}
	pad.state = .Assembling
	pad.work_ticks, pad.stages_taken, pad.missing_parts = 0, 0, false
	return true
}

advance_assembly :: proc(pad: ^Launch_Pad, machine: Machine, statistics: ^Statistics, tick_rate: int) {
	stage := current_stage(pad^, machine, tick_rate)
	if pad.stages_taken <= stage {
		pad.missing_parts = !stage_parts_present(pad^, machine, stage, 1)
		if pad.missing_parts {
			return
		}
		take_stage_share(pad, machine, statistics, stage)
		pad.stages_taken = stage + 1
	}
	if !take_power_step(&pad.power) {
		return
	}
	pad.work_ticks += 1
	if pad.work_ticks >= assembly_ticks(machine, tick_rate) {
		pad.state = .Rocket_Ready
	}
}

advance_launch_pad :: proc(pad: ^Launch_Pad, machine: Machine, statistics: ^Statistics, tick_rate: int) {
	switch pad.state {
	case .Waiting_For_Parts, .Ready_To_Assemble:
		pad.state = idle_launch_pad_state(pad^, machine)
	case .Assembling:
		advance_assembly(pad, machine, statistics, tick_rate)
	case .Rocket_Ready:
	case .Launching:
		pad.launch_ticks += 1
		if pad.launch_ticks >= machine.launch_seconds * u32(tick_rate) {
			pad.launch_ticks = 0
			pad.state = idle_launch_pad_state(pad^, machine)
		}
	}
}

tick_launch_pads :: proc(world: ^World, content: Simulation_Content, tick_rate: int) {
	for &pad in world.entities.launch_pads.entries {
		if pad.alive {
			advance_launch_pad(&pad, content.machines.machines[pad.machine], &world.statistics, tick_rate)
		}
	}
}

// 0 to 1 over the assembly or the ascent, 1 with a rocket ready.
launch_pad_progress :: proc(pad: Launch_Pad, machine: Machine, tick_rate: int) -> f32 {
	#partial switch pad.state {
	case .Assembling:
		return f32(pad.work_ticks) / f32(assembly_ticks(machine, tick_rate))
	case .Rocket_Ready:
		return 1
	case .Launching:
		return f32(pad.launch_ticks) / f32(max(machine.launch_seconds * u32(tick_rate), 1))
	}
	return 0
}

// The parts already built into the rocket, given back when the pad is
// picked up; the fuel is lost.
launch_pad_held_stacks :: proc(pad: Launch_Pad, machine: Machine) -> []Item_Stack {
	stacks := make([dynamic]Item_Stack, context.temp_allocator)
	if pad.state != .Assembling && pad.state != .Rocket_Ready {
		return stacks[:]
	}
	for index in 0 ..< machine.launch_part_count {
		part := machine.launch_parts[index]
		taken := stage_share(u32(part.count), pad.stages_taken)
		if taken > 0 {
			append(&stacks, Item_Stack{item = part.item, count = u16(taken)})
		}
	}
	return stacks[:]
}

// Launching.

cargo_is_empty :: proc(pad: ^Launch_Pad) -> bool {
	for slot in launch_pad_cargo(pad) {
		if !stack_is_empty(slot) {
			return false
		}
	}
	return true
}

launch_pad_can_launch :: proc(pad: ^Launch_Pad) -> bool {
	return pad.state == .Rocket_Ready && !cargo_is_empty(pad)
}

// The cargo with each item once, in the order of the slots.
make_shipment :: proc(cargo: []Item_Stack, tick: u64) -> Shipment {
	shipment := Shipment{tick = tick}
	for slot in cargo {
		if stack_is_empty(slot) {
			continue
		}
		index := shipped_item_index(shipment, slot.item)
		if index < 0 {
			index = int(shipment.cargo_count)
			shipment.cargo[index] = {item = slot.item}
			shipment.cargo_count += 1
		}
		shipment.cargo[index].count += u32(slot.count)
	}
	return shipment
}

shipped_item_index :: proc(shipment: Shipment, item: Item_Id) -> int {
	for index in 0 ..< int(shipment.cargo_count) {
		if shipment.cargo[index].item == item {
			return index
		}
	}
	return -1
}

record_shipment :: proc(statistics: ^Statistics, shipment: Shipment) {
	statistics.rockets_launched += 1
	for index in 0 ..< int(shipment.cargo_count) {
		shipped := shipment.cargo[index]
		if int(shipped.item) < len(statistics.shipped) {
			statistics.shipped[shipped.item] += u64(shipped.count)
		}
	}
}

// Takes the rocket and the cargo, records the shipment and starts the
// ascent. False without a rocket or without cargo.
launch_rocket :: proc(world: ^World, pad: ^Launch_Pad, tick: u64) -> bool {
	if !launch_pad_can_launch(pad) {
		return false
	}
	shipment := make_shipment(launch_pad_cargo(pad), tick)
	append(&world.shipments, shipment)
	record_shipment(&world.statistics, shipment)
	for &slot in launch_pad_cargo(pad) {
		slot = EMPTY_STACK
	}
	pad.state = .Launching
	pad.launch_ticks, pad.work_ticks, pad.stages_taken = 0, 0, 0
	return true
}

// The Launch button and Interact: served by apply_launch_requests.
request_launch :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	pad := pool_get(&entities.launch_pads, handle)
	if pad == nil || !launch_pad_can_launch(pad) {
		return false
	}
	pad.launch_requested = true
	return true
}

apply_launch_requests :: proc(world: ^World, tick: u64) {
	for &pad in world.entities.launch_pads.entries {
		if pad.alive && pad.launch_requested {
			pad.launch_requested = false
			launch_rocket(world, &pad, tick)
		}
	}
}

// The statistics screen's totals: every item ever shipped, most first,
// then in item order. In the temp allocator.
Shipped_Total :: struct {
	item:  Item_Id,
	count: u64,
}

shipped_totals :: proc(shipped: []u64) -> []Shipped_Total {
	totals := make([dynamic]Shipped_Total, context.temp_allocator)
	for count, item in shipped {
		if count > 0 {
			append(&totals, Shipped_Total{item = Item_Id(item), count = count})
		}
	}
	slice.stable_sort_by(totals[:], proc(first, second: Shipped_Total) -> bool {
		return first.count > second.count
	})
	return totals[:]
}
