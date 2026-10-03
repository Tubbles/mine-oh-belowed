package game

import "platform"

// Machines on bare ground (work item 0201, doc/architecture.md, Frames and
// Simulation; doc/content.md, Machines on bare ground). Place with a
// machine aimed at bare ground stands it on a new frame of its own, with
// no foundation, when the ground under its footprint is flat enough
// (bare_ground_is_flat); steeper ground refuses it with Too_Steep. A
// machine is founded when it stands on the block frame or every cell of
// its footprint's bottom row has a foundation right below it on its
// frame; the flag is set when the machine is added and again for the
// machines above a foundation added or removed (entity.odin), and
// derived again after loading. An unfounded machine counts its ticks of
// operation, the ticks its own tick advanced its work, and breaks down
// at its life (bare_ground_life_ticks): a broken machine does not tick,
// asks for and offers no power, and is torn down for a share of its
// recipe (machine_return_stacks). Records with stands_on_ground (poles,
// pipes, belts, the pod) never wear and are never refused for slope.

// The bounds of data/game.sjson's bare ground values (bare_ground_problem).
MAXIMUM_BARE_GROUND_FLATNESS_MILLIMETRES :: 2000
MAXIMUM_BARE_GROUND_LIFE_MINUTES :: 7 * 24 * 60
// The flatness probe starts this far above the new frame's base along its
// up and reaches as far below it: ground higher reads as this high, and
// no ground within reach is too steep. Above the largest flatness, so
// both read as too steep.
BARE_GROUND_PROBE_RISE_MILLIMETRES :: 4000
// The toast when a machine breaks down, "{name} broke down".
MACHINE_BROKE_DOWN_KEY :: "machine_broke_down"
// The panel's status line and the pick up hint on a broken machine.
MACHINE_BROKEN_DOWN_KEY :: "machine_broken_down"
// The tool line over flat bare ground, "On bare ground, wears out in
// {minutes} min".
FIELD_TOOL_BARE_GROUND_KEY :: "field_tool_bare_ground"

#assert(BARE_GROUND_PROBE_RISE_MILLIMETRES > MAXIMUM_BARE_GROUND_FLATNESS_MILLIMETRES)

// The values of data/game.sjson (Field_Content.bare_ground). The zero
// value, as the block world's tests make it, never wears a machine.
Bare_Ground_Tuning :: struct {
	flatness_millimetres: int,
	life_minutes:         int,
	salvage_percent:      int,
}

make_bare_ground_tuning :: proc(config: Game_Config) -> Bare_Ground_Tuning {
	return Bare_Ground_Tuning {
		flatness_millimetres = config.bare_ground_flatness_millimetres,
		life_minutes = config.bare_ground_life_minutes,
		salvage_percent = config.salvage_percent,
	}
}

// Placement.

// The surface heights under the corners and the centre of a footprint of
// size cells at cell (0, 0, 0) of frame lie within the flatness of each
// other, measured along the frame's up as a straight down ray from above
// each point (raycast_field), so a sample read is the field's surface as
// the free foundation's hit is.
bare_ground_is_flat :: proc(world: ^Field_World, spacing_millimetres: int, frame: Frame, size: [3]i32, flatness_millimetres: int) -> bool {
	pitch := frame_pitch_units(frame)
	width, depth := i64(size.x) * pitch, i64(size.z) * pitch
	points := [5][2]i64{{0, 0}, {width, 0}, {0, depth}, {width, depth}, {width / 2, depth / 2}}
	lowest, highest := max(i64), min(i64)
	for point in points {
		height, found := bare_ground_height(world, spacing_millimetres, frame, point)
		if !found {
			return false
		}
		lowest, highest = min(lowest, height), max(highest, height)
	}
	return highest - lowest <= millimetres_to_position_units(flatness_millimetres)
}

// The surface's height over the frame's origin along its up, under the
// point (right, forward) of the frame's base plane, in position units.
bare_ground_height :: proc(world: ^Field_World, spacing_millimetres: int, frame: Frame, point: [2]i64) -> (height: i64, found: bool) {
	up := frame.axes[FRAME_UP]
	rise := millimetres_to_position_units(BARE_GROUND_PROBE_RISE_MILLIMETRES)
	base := frame.origin + World_Position(fixed_scale(frame.axes[FRAME_RIGHT], point[0]) + fixed_scale(frame.axes[FRAME_FORWARD], point[1]))
	hit := raycast_field(world, spacing_millimetres, base + World_Position(fixed_scale(up, rise)), -up, 2 * rise)
	if !hit.hit {
		return 0, false
	}
	return fixed_dot(cast([3]i64)(hit.position - frame.origin), up), true
}

// A machine other than a foundation on a new frame of its own (a queued
// placement with new_frame): too steep unless the record stands on the
// ground, then the item, a drill's vein, another frame's occupied cells
// (new_frame_cells_meet_a_frame) and the players as for a snapped
// machine.
bare_ground_placement_refusal :: proc(state: ^Simulation_State, content: Simulation_Content, player: Player, placement: Field_Placement, frame: Frame) -> Field_Edit_Refusal {
	machine := content.machines.machines[placement.machine]
	size := rotated_footprint_size(machine.footprint, placement.rotation)
	switch {
	case !machine.stands_on_ground && !bare_ground_is_flat(&state.field.world, state.field.spacing_millimetres, frame, size, content.field.bare_ground.flatness_millimetres):
		return .Too_Steep
	case inventory_count(player.inventory, machine.item) == 0:
		return .Nothing_Held
	}
	if machine.kind == .Drill {
		if _, found := frame_drill_vein_under(frame, state.world.veins[:], machine, {}, placement.rotation); !found {
			return .No_Vein
		}
	}
	if new_frame_cells_meet_a_frame(&state.world.entities.frames, frame, footprint_cells({}, machine.footprint, placement.rotation)) {
		return .Frame_Cell_Taken
	}
	if field_footprint_buries_a_player(state, content, frame, placement, {}) {
		return .Would_Bury_Player
	}
	return .None
}

// A placement bare_ground_placement_refusal let through: a new frame
// standing on the hit (free_frame_at) with the machine at cell (0, 0,
// 0), a drill tapping the vein under it. The frame goes with its last
// entity (release_empty_frame).
place_on_bare_ground :: proc(state: ^Simulation_State, content: Simulation_Content, placement: Field_Placement) -> Entity_Handle {
	entities := &state.world.entities
	pitch := content.field.foundation_pitch_millimetres
	origin, axes := free_frame_at(placement.hit, placement.heading, pitch)
	frame := add_frame(&entities.frames, origin, axes, pitch)
	handle := add_entity(entities, content.machines, placement.machine, {}, placement.rotation, frame)
	if drill := pool_get(&entities.drills, handle); drill != nil {
		record, _ := find_frame(&entities.frames, frame)
		drill.vein, _ = frame_drill_vein_under(record, state.world.veins[:], content.machines.machines[placement.machine], {}, placement.rotation)
	}
	return handle
}

// What the tool line says with a machine held over bare ground.
Bare_Ground_Line :: enum u8 {
	None,
	// Flat enough: "On bare ground, wears out in N min".
	Wears_Out,
	// The refusal's text.
	Too_Steep,
}

// The viewer's bare ground placement (field_bare_ground_placement) read
// against the field: nothing for a record that stands on the ground.
bare_ground_line :: proc(state: ^Simulation_State, content: Simulation_Content, player: Field_Player) -> Bare_Ground_Line {
	if !state.field.enabled {
		return .None
	}
	placement, bare := field_bare_ground_placement(player, field_placed_machine(player, content))
	if !bare || content.machines.machines[placement.machine].stands_on_ground {
		return .None
	}
	frame, _, _ := field_placement_frame(&state.world.entities.frames, placement, content.field.foundation_pitch_millimetres)
	size := rotated_footprint_size(content.machines.machines[placement.machine].footprint, placement.rotation)
	if !bare_ground_is_flat(&state.field.world, state.field.spacing_millimetres, frame, size, content.field.bare_ground.flatness_millimetres) {
		return .Too_Steep
	}
	return .Wears_Out
}

// Founded.

// The block frame's machines, and a machine whose bottom row has a
// foundation in the cell right below each of its cells.
machine_is_founded :: proc(entities: ^Entities, machines: Machine_Registry, common: Entity_Common) -> bool {
	if common.frame == BLOCK_FRAME {
		return true
	}
	for cell in common_cells(common, machines) {
		if cell.y != common.origin.y {
			continue
		}
		below := entity_common(entities, entity_at(entities, cell - UP, common.frame))
		if below == nil || machines.machines[below.machine].kind != .Foundation {
			return false
		}
	}
	return true
}

refresh_founded :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) {
	if common := entity_common(entities, handle); common != nil {
		common.founded = machine_is_founded(entities, machines, common^)
	}
}

// The machines standing on the cells of a foundation just added or
// removed (its common data, kept after the removal).
refresh_founded_above :: proc(entities: ^Entities, machines: Machine_Registry, foundation: Entity_Common) {
	for cell in common_cells(foundation, machines) {
		refresh_founded(entities, machines, entity_at(entities, cell + UP, foundation.frame))
	}
}

// After loading, once the occupant index is rebuilt.
refresh_all_founded :: proc(entities: ^Entities, machines: Machine_Registry) {
	for kind in Entity_Kind {
		for index in 0 ..< entity_pool_length(entities, kind) {
			if common := entity_common_at(entities, kind, index); common != nil && common.alive {
				common.founded = machine_is_founded(entities, machines, common^)
			}
		}
	}
}

// Wear.

// The machine's life on bare ground in minutes: its record's, else the
// game's.
bare_ground_life_minutes :: proc(machine: Machine, tuning: Bare_Ground_Tuning) -> int {
	return machine.bare_ground_life_minutes > 0 ? machine.bare_ground_life_minutes : tuning.life_minutes
}

// In ticks; 0 (a tuning without values) never breaks.
bare_ground_life_ticks :: proc(machine: Machine, tuning: Bare_Ground_Tuning, tick_rate: int) -> u32 {
	return u32(bare_ground_life_minutes(machine, tuning) * 60 * tick_rate)
}

machine_wears :: proc(common: Entity_Common, machine: Machine) -> bool {
	return !common.founded && !common.broken && !machine.stands_on_ground && machine.kind != .Foundation && machine.kind != .Pod
}

// One tick of operation: the counter and the breakdown after it.
wear_after_operation :: proc(common: Entity_Common, machine: Machine, life_ticks: u32) -> (wear_ticks: u32, broken: bool) {
	if !machine_wears(common, machine) || life_ticks == 0 {
		return common.wear_ticks, common.broken
	}
	wear_ticks = common.wear_ticks + 1
	return wear_ticks, wear_ticks >= life_ticks
}

// Counts a tick in which the machine's own tick advanced its work; a
// breakdown is listed for the toast (log_machine_breakdowns).
record_operation :: proc(entities: ^Entities, common: ^Entity_Common, machine: Machine, tuning: Bare_Ground_Tuning, tick_rate: int) {
	was_broken := common.broken
	common.wear_ticks, common.broken = wear_after_operation(common^, machine, bare_ground_life_ticks(machine, tuning, tick_rate))
	if common.broken && !was_broken {
		append(&entities.breakdowns, common.machine)
	}
}

// The machines that broke down this tick as toasts, through the message
// log as a finished technology is told. The list is emptied.
log_machine_breakdowns :: proc(state: ^Simulation_State, content: Simulation_Content) {
	for machine in state.world.entities.breakdowns {
		log_quest_message(&state.quests, state.tick, MACHINE_BROKE_DOWN_KEY, content.machines.machines[machine].name_key)
	}
	clear(&state.world.entities.breakdowns)
}

// An assembler's tick advanced its craft: its progress moved, or a craft
// finished (which resets it).
assembler_operated :: proc(before, after: Assembler, crafted: bool) -> bool {
	return after.state == .Working && (crafted || after.progress_ticks != before.progress_ticks)
}

// A fluid machine of tick_fluids moved its fluid this tick.
fluid_machine_operated :: proc(state: Fluid_Machine_State) -> bool {
	#partial switch state {
	case .Producing, .Pumping, .Flaring:
		return true
	}
	return false
}

// The broken case first: a broken machine's marker is red whatever its
// state says, and it does not animate (marker_means_working).
entity_marker_colour :: proc(common: Entity_Common, colour: Marker_Colour) -> Marker_Colour {
	return common.broken ? .Red : colour
}

// Salvage.

// A worn or broken machine's salvage: salvage_percent of each direct input
// of the first hand recipe whose first product is its item, per item
// made, rounded down; an unworn one, or one no hand recipe makes, returns
// its item. In the temp allocator.
machine_return_stacks :: proc(content: Simulation_Content, common: Entity_Common) -> []Item_Stack {
	returned := make([dynamic]Item_Stack, context.temp_allocator)
	item := content.machines.machines[common.machine].item
	recipe := salvage_recipe(content.recipes, item)
	if (common.wear_ticks == 0 && !common.broken) || recipe == NO_RECIPE {
		append(&returned, Item_Stack{item = item, count = 1})
		return returned[:]
	}
	made := max(int(content.recipes.recipes[recipe].outputs[0].count), 1)
	for input in content.recipes.recipes[recipe].inputs {
		if count := salvaged_count(int(input.count), made, content.field.bare_ground.salvage_percent); count > 0 {
			append(&returned, Item_Stack{item = input.item, count = u16(count)})
		}
	}
	return returned[:]
}

// The share of an input per item made, rounded down, never below zero.
salvaged_count :: proc(input_count, made, percent: int) -> int {
	return max(input_count * percent / (100 * max(made, 1)), 0)
}

// The first hand recipe in registry order whose first product is the item,
// whether unlocked or not, as the recipe book finds it.
salvage_recipe :: proc(recipes: Recipe_Registry, item: Item_Id) -> int {
	for recipe, index in recipes.recipes {
		if len(recipe.outputs) > 0 && recipe.outputs[0].item == item && recipe_is_hand_craftable(recipe) {
			return index
		}
	}
	return NO_RECIPE
}

// The save (write_later_tables' successor in a field world).

// A machine with wear: the counter and the breakdown.
Machine_Wear_Record :: struct {
	handle:     Entity_Handle,
	wear_ticks: u32,
	broken:     bool,
}

// Every live entity with wear, in pool order.
machine_wear_records :: proc(entities: ^Entities) -> []Machine_Wear_Record {
	records := make([dynamic]Machine_Wear_Record, context.temp_allocator)
	for kind in Entity_Kind {
		for index in 0 ..< entity_pool_length(entities, kind) {
			common := entity_common_at(entities, kind, index)
			if common != nil && common.alive && (common.wear_ticks > 0 || common.broken) {
				append(&records, Machine_Wear_Record{handle = common.handle, wear_ticks = common.wear_ticks, broken = common.broken})
			}
		}
	}
	return records[:]
}

// After the field tables of a field world, always, so a save without it
// is one from before 0201 (read_machine_wear_table).
write_machine_wear_table :: proc(bytes: ^[dynamic]byte, entities: ^Entities) {
	write_list(bytes, machine_wear_records(entities))
}

// A save from before 0201 ends before the table: every machine starts
// unworn, said in one log line. False for a record naming no live entity.
read_machine_wear_table :: proc(reader: ^Byte_Reader, entities: ^Entities) -> bool {
	if bytes_left(reader^) == 0 {
		platform.log_printf("save: written before machine wear (0201), every machine starts unworn")
		return true
	}
	records := make([dynamic]Machine_Wear_Record, context.temp_allocator)
	read_list(reader, &records) or_return
	for record in records {
		common := entity_common(entities, record.handle)
		if common == nil {
			return false
		}
		common.wear_ticks, common.broken = record.wear_ticks, record.broken
	}
	return true
}
