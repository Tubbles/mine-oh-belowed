package game

import "core:encoding/json"
import "core:fmt"
import "platform"

// Digging and placing the terrain field by hand and the item yield (work
// item 0171, doc/architecture.md, The terrain field's brushes; doc/
// content.md, Field materials). The field's share of the simulation state
// (Simulation_State.field, 0179): the field world, the edit queue, the
// placements and the torches; the players' credit and refusals are on
// Player.
//
// The one rule of writes inside the tick: a player's tick (and later a
// drill's) queues its brush edit, and the edits are drained at the end of
// the tick in the order queued (drain_field_edits), so no system reads a
// half edited field. The queue is filled and emptied inside one tick, so
// it is always empty between ticks, where a save runs: it is not saved,
// and a save loses no edit (test_the_edit_queue_is_empty_between_ticks).
//
// The yield: a dig's density steps per material (world_field_edit.odin)
// become volume and credit the material's item from data/materials.sjson,
// a cubic metre an item whatever the spacing; the volume short of a whole
// item, and the items the inventory had no room for, stay in the player's
// credit per material, as take_power_step keeps its credit, so no volume
// is lost. A place takes its volume from the credit and the held item the
// same way.

FIELD_MATERIALS_FILE_NAME :: "materials.sjson"
// One item, a cubic metre, in the credit's unit: a cubic millimetre times
// MAXIMUM_DENSITY, so one density step of a sample (its volume over
// MAXIMUM_DENSITY) is the spacing cubed in whole units.
FIELD_ITEM_VOLUME :: i64(MILLIMETRES_PER_METRE) * MILLIMETRES_PER_METRE * MILLIMETRES_PER_METRE * MAXIMUM_DENSITY

Field_Material_Definition :: struct {
	id:        string,
	// An items.sjson id; empty for a material that cannot be dug or placed.
	item:      string,
	// The tool_role that digs it (0265): shovel or pickaxe with an item,
	// empty without one.
	dug_with:  string,
	// The tier of the dug_with tool the material needs.
	tool_tier: int,
	// The brush's rate on this material in percent (0179).
	dig_rate_percent: int,
}

Field_Materials_File :: struct {
	materials: []Field_Material_Definition,
}

Field_Material_Record :: struct {
	// NO_ITEM: the material cannot be dug or placed (air, bedrock).
	item:      Item_Id,
	dug_with:  Item_Tool_Role,
	tool_tier: int,
	dig_rate_percent: int,
}

Field_Material_Table :: [Field_Material]Field_Material_Record

// Why the hand tool's latest edit did less than asked.
Field_Edit_Refusal :: enum u8 {
	None,
	// The ground's material needs a better tool than the one selected.
	Tool_Tier,
	// The material yields no item (bedrock).
	Undiggable,
	// No held material in the inventory or the credit.
	Nothing_Held,
	// The raised volume would overlap a player's capsule.
	Would_Bury_Player,
	// A foundation's cell is taken (0174).
	Frame_Cell_Taken,
	// The frame a foundation snaps to is gone.
	Unknown_Frame,
	// A belt or pipe run was refused (0176): the reason is the player's
	// field_run_refusal.
	Run_Refused,
	// A torch's sample holds a torch already or turned to ground (0179).
	Torch_Blocked,
	// A torch taken back finds no room in the inventory and stays (0179).
	Inventory_Full,
	// A drill on a frame stands off every vein's disc (0179).
	No_Vein,
	// A machine other than a foundation aimed at bare ground too steep to
	// stand on without one (0201, bare_ground_is_flat).
	Too_Steep,
	// A foundation block needs more foundations than are held (0193); the
	// event carries both counts (record_refused_foundation_counts).
	Too_Few_Foundations,
	// A pick up of an entity that holds something up (0195,
	// field_entity_is_held_up).
	Something_Stands_On_It,
	// A placement's cell meets a tree's trunk (0197,
	// placement_cells_meet_a_trunk).
	Tree_In_The_Way,
	// The raised volume would overlap the capsule of the pod's spawn,
	// where the next joiner stands (0180, field_place_buries_a_player).
	Would_Bury_Spawn,
	// The ground's material is dug with a shovel or a pickaxe, not the
	// tool selected (0265).
	Needs_Shovel,
	Needs_Pickaxe,
	// A tree larger than the hand fells (0265, field_felling_ticks).
	Needs_Axe,
}

// The string keys of the refusals the HUD toasts (Field_Refused, 0179).
@(rodata)
field_refusal_keys := [Field_Edit_Refusal]string {
	.None              = "",
	.Tool_Tier         = "field_refused_tool_tier",
	.Undiggable        = "field_refused_undiggable",
	.Nothing_Held      = "field_refused_nothing_held",
	.Would_Bury_Player = "field_refused_would_bury_player",
	.Frame_Cell_Taken  = "field_refused_frame_cell_taken",
	.Unknown_Frame     = "field_refused_unknown_frame",
	.Run_Refused       = "field_refused_run",
	.Torch_Blocked     = "field_refused_torch_blocked",
	.Inventory_Full    = "field_refused_inventory_full",
	.No_Vein           = "field_refused_no_vein",
	.Too_Steep         = "field_refused_too_steep",
	.Too_Few_Foundations = "field_refused_too_few_foundations",
	.Something_Stands_On_It = "field_refused_something_stands_on_it",
	.Tree_In_The_Way   = "field_refused_tree_in_the_way",
	.Would_Bury_Spawn  = "field_refused_would_bury_spawn",
	.Needs_Shovel      = "field_refused_needs_shovel",
	.Needs_Pickaxe     = "field_refused_needs_pickaxe",
	.Needs_Axe         = "field_refused_needs_axe",
}

Queued_Field_Edit :: struct {
	player: int,
	edit:   Field_Edit,
}

// A torch on the field (0179): an emitter of data/lighting.sjson at the
// air sample, placed with the torch item and taken back by Dig.
Field_Torch :: struct {
	sample: Sample_Coordinate,
}

// The field's share of the simulation state (0179): the simulated chunks
// of the terrain field (simulation_field_chunk_set.odin), the per tick
// queues and the torches. The players' field state is on Player (field,
// field_credit, the refusal fields); the foundations, frames, poles and
// runs are World.entities. enabled is set for a field session; a block
// world of the tests leaves it false and the tick skips the field.
Field_Simulation :: struct {
	enabled:             bool,
	world:               Field_World,
	spacing_millimetres: int,
	// The edit queue: filled by the players' ticks, drained at the end of
	// the tick in order. Not saved; empty between ticks.
	edits:               [dynamic]Queued_Field_Edit,
	// The place commands (foundations, machines, runs), drained after the
	// edits; empty between ticks.
	placements:          [dynamic]Queued_Field_Placement,
	// Per player index, the needed and held counts of its latest
	// Too_Few_Foundations refusal (0193), read when the tick tells it.
	// Not saved.
	refused_foundation_counts: [dynamic][2]int,
	torches:             [dynamic]Field_Torch,
	chunk_set:           Field_Chunk_Set,
	// Generated chunks waiting for the set to take them, as the block
	// world's arrived_chunks. Not saved: they differ per machine and the
	// tick reads none of them.
	arrived_chunks:      map[Field_Chunk_Coordinate]^Field_Chunk,
	// The chunks outside the set whose terrain or water differs from their
	// generation, taken again when a chunk enters the set.
	saved_chunks:        map[Field_Chunk_Coordinate]Field_Saved_Chunk,
	// The trees felled (0197, field_trees.odin), saved in their table;
	// the standing ones are the generation's. felled_trees_recorded is
	// false (not saved) while a save written before the trees has not had
	// the trees in its frames cleared (clear_trees_of_an_old_save).
	felled_trees:          map[Tree_Key]struct{},
	felled_trees_recorded: bool,
	// A new world's fall (0200, simulation_arrival.odin), saved in its
	// table, hashed.
	arrival:               Field_Arrival,
}

// A chunk kept outside the set: its codec bytes (encode_field_chunk) and
// its field_chunk_state_hash, computed once when it is kept, since the
// bytes never change while it is away.
Field_Saved_Chunk :: struct {
	bytes:      []byte,
	state_hash: u64,
}

// The field's content (0179, folded into Simulation_Content as its field
// member): the material table and the tuning of one planet, spacing and
// tick rate (make_field_content). The items and machines are the
// simulation content's own.
Field_Content :: struct {
	materials:  Field_Material_Table,
	brushes:    []Field_Brush,
	tuning:     Field_Player_Tuning,
	water:      Field_Water_Tuning,
	light:      Field_Light_Tuning,
	// The content's pad foundation (0196, read through
	// field_pad_foundation): the benchmark's pad; Place puts down the
	// held foundation. And the pitch of a new frame
	// (data/game.sjson).
	pad_foundation: Machine_Id,
	foundation_pitch_millimetres: int,
	// The block sizes and heights a held foundation cycles (0193,
	// field_foundation_block); empty lists place one cell.
	foundation_sizes:   []int,
	foundation_heights: []int,
	// The largest footprint Place puts down in one press while the
	// placement editor is on (0215, data/game.sjson), x the width, y the
	// height, z the depth as a footprint; only the presentation reads it.
	direct_placement_limit: [3]i32,
	// The run tools (0176, belt_run_placement.odin): the pole a new
	// endpoint places, the belt a belt run moves at, the pipe a pipe run
	// looks like (each read through field_content_machine) and the
	// constraints of data/game.sjson.
	belt_pole: Machine_Id,
	run_belt:  Machine_Id,
	run_pipe:  Machine_Id,
	belt_runs: Belt_Run_Constraints,
	// The torch (0179): its item (NO_ITEM without one) and the level of
	// the torch emitter of data/lighting.sjson.
	torch_item:  Item_Id,
	torch_level: u8,
	// The starter kit a joining player gets (data/game.sjson).
	starting_items: []Starting_Item,
	// Machines on bare ground (0201, machine_wear.odin).
	bare_ground: Bare_Ground_Tuning,
	// The pod's airlock (0222, entity_pod_airlock.odin).
	pod_airlock: Pod_Airlock_Tuning,
	// The pod's rest at the arrival's hit (0270, rest_field_pod).
	pod_rest: Pod_Rest_Tuning,
	// The planet's tree species (0197, field_trees.odin), in allocator.
	tree_species: []Field_Tree_Species,
}

// The lists make_field_content made.
destroy_field_content :: proc(content: ^Field_Content) {
	delete(content.brushes)
	delete(content.tree_species)
	content.brushes, content.tree_species = nil, nil
}

destroy_field_simulation :: proc(simulation: ^Field_Simulation) {
	delete(simulation.edits)
	delete(simulation.placements)
	delete(simulation.refused_foundation_counts)
	delete(simulation.torches)
	destroy_field_chunk_set(&simulation.chunk_set)
	for _, chunk in simulation.arrived_chunks {
		free(chunk)
	}
	delete(simulation.arrived_chunks)
	for _, saved in simulation.saved_chunks {
		delete(saved.bytes)
	}
	delete(simulation.saved_chunks)
	delete(simulation.felled_trees)
	destroy_field_world(&simulation.world)
	simulation^ = {}
}

// The material table.

find_field_material :: proc(id: string) -> (material: Field_Material, found: bool) {
	for candidate in Field_Material {
		if candidate != .Air && field_material_name(candidate) == id {
			return candidate, true
		}
	}
	return .Air, false
}

missing_field_material_key_problem :: proc(tree: json.Object, source: string) -> string {
	if key, missing := missing_struct_key(Field_Materials_File, tree); missing {
		return fmt.tprintf("%s: missing key %s", source, key)
	}
	for record, index in tree["materials"].(json.Array) {
		if key, missing := missing_struct_key(Field_Material_Definition, record.(json.Object)); missing {
			return fmt.tprintf("%s: materials[%d] is missing %s", source, index, key)
		}
	}
	return ""
}

field_material_record :: proc(definition: Field_Material_Definition, items: Item_Registry) -> (record: Field_Material_Record, problem: string) {
	record = {item = NO_ITEM, tool_tier = definition.tool_tier, dig_rate_percent = definition.dig_rate_percent}
	if definition.dig_rate_percent < MINIMUM_DIG_RATE_PERCENT || definition.dig_rate_percent > MAXIMUM_DIG_RATE_PERCENT {
		return {}, fmt.tprintf("dig_rate_percent %d is outside %d to %d", definition.dig_rate_percent, MINIMUM_DIG_RATE_PERCENT, MAXIMUM_DIG_RATE_PERCENT)
	}
	if definition.item != "" {
		found: bool
		if record.item, found = find_item_id(items, definition.item); !found {
			return {}, fmt.tprintf("item %q is not in items.sjson", definition.item)
		}
	}
	found: bool
	if record.dug_with, found = parse_named_enum(item_tool_role_names, definition.dug_with); !found || record.dug_with == .Axe {
		return {}, fmt.tprintf("dug_with %q is not shovel, pickaxe or empty", definition.dug_with)
	}
	if (record.item == NO_ITEM) != (record.dug_with == .None) {
		return {}, fmt.tprintf("dug_with %q needs an item, and an item needs dug_with", definition.dug_with)
	}
	minimum_tier := record.dug_with == .None ? 0 : 1
	maximum_tier := record.dug_with == .None ? 0 : highest_tool_tier(items.items)
	if definition.tool_tier < minimum_tier || definition.tool_tier > maximum_tier {
		return {}, fmt.tprintf("tool_tier %d is outside %d to %d", definition.tool_tier, minimum_tier, maximum_tier)
	}
	return record, ""
}

// Every material but air once; air yields nothing.
resolve_field_material_table :: proc(definitions: []Field_Material_Definition, items: Item_Registry) -> (table: Field_Material_Table, problem: string) {
	table[.Air] = {item = NO_ITEM}
	seen: bit_set[Field_Material]
	for definition, index in definitions {
		material, found := find_field_material(definition.id)
		switch {
		case !found:
			return {}, fmt.tprintf("materials[%d]: unknown material %q", index, definition.id)
		case material in seen:
			return {}, fmt.tprintf("materials[%d]: %s is listed twice", index, definition.id)
		}
		seen += {material}
		if table[material], problem = field_material_record(definition, items); problem != "" {
			return {}, fmt.tprintf("materials[%d] (%s): %s", index, definition.id, problem)
		}
	}
	for material in Field_Material {
		if material != .Air && material not_in seen {
			return {}, fmt.tprintf("material %s is missing", field_material_name(material))
		}
	}
	return table, ""
}

// Held to the configuration's strict keys, every key required.
parse_field_material_table :: proc(data: []byte, source: string, items: Item_Registry) -> (table: Field_Material_Table, problem: string) {
	tree, parse_problem := parse_configuration_layer(data, source, context.temp_allocator)
	if parse_problem != "" {
		return {}, parse_problem
	}
	provenance := make(Configuration_Provenance, context.temp_allocator)
	provenance[""] = source
	file: Field_Materials_File
	if problem = assign_configuration_value(any{&file, typeid_of(Field_Materials_File)}, json.Value(tree), "", provenance, context.temp_allocator); problem != "" {
		return {}, problem
	}
	if problem = missing_field_material_key_problem(tree, source); problem != "" {
		return {}, problem
	}
	if table, problem = resolve_field_material_table(file.materials, items); problem != "" {
		return {}, fmt.tprintf("%s: %s", source, problem)
	}
	return table, ""
}

load_field_material_table :: proc(data_directory: string, items: Item_Registry) -> (table: Field_Material_Table, ok: bool) {
	data, path := read_logged_data_file(data_directory, FIELD_MATERIALS_FILE_NAME) or_return
	problem: string
	if table, problem = parse_field_material_table(data, path, items); problem != "" {
		platform.log_printf("error: invalid %s", problem)
		return {}, false
	}
	return table, true
}

// The materials the tool of this role and tier digs (0265).
field_diggable_materials :: proc(table: Field_Material_Table, role: Item_Tool_Role, tool_tier: int) -> bit_set[Field_Material] {
	diggable: bit_set[Field_Material]
	for record, material in table {
		if record.item != NO_ITEM && record.dug_with == role && record.tool_tier <= tool_tier {
			diggable += {material}
		}
	}
	return diggable
}

// The yield.

field_steps_to_volume :: proc(steps: i64, spacing_millimetres: int) -> i64 {
	spacing := i64(spacing_millimetres)
	return steps * spacing * spacing * spacing
}

// Adds the volume to the credit and moves its whole items into the
// inventory; what does not fit stays in the credit.
credit_field_volume :: proc(inventory: Inventory, items: Item_Registry, item: Item_Id, credit: ^i64, volume: i64) {
	credit^ += volume
	whole := credit^ / FIELD_ITEM_VOLUME
	if whole == 0 {
		return
	}
	leftover := inventory_add_picked_up(inventory, items, item, int(whole))
	credit^ -= (whole - i64(leftover)) * FIELD_ITEM_VOLUME
}

// The volume of the held items and the credit.
field_place_volume_available :: proc(inventory: Inventory, item: Item_Id, credit: i64) -> i64 {
	return i64(inventory_count(inventory, item)) * FIELD_ITEM_VOLUME + credit
}

// Takes the volume from the credit, and from the held items as whole
// items when the credit falls short; the change stays in the credit.
debit_field_volume :: proc(inventory: Inventory, item: Item_Id, credit: ^i64, volume: i64) {
	if credit^ >= volume {
		credit^ -= volume
		return
	}
	needed := (volume - credit^ + FIELD_ITEM_VOLUME - 1) / FIELD_ITEM_VOLUME
	removed := inventory_remove(inventory, item, int(needed))
	credit^ += i64(removed) * FIELD_ITEM_VOLUME - volume
}

// The tick.

// The crouched body while crouching (0218).
field_player_capsule :: proc(tuning: Field_Player_Tuning, player: Field_Player) -> Field_Capsule {
	posture := field_posture_tuning(tuning, player.crouching)
	return Field_Capsule {
		bottom = player.position + World_Position(fixed_scale(player.up, posture.capsule_radius)),
		up = player.up,
		length = posture.capsule_height - 2 * posture.capsule_radius,
		radius = posture.capsule_radius,
	}
}

// A place that would raise a sample within its trilinear support of any
// field player's capsule (field_place_meets_capsule), Would_Bury_Player,
// or of the pod spawn's capsule, where the next joiner stands,
// Would_Bury_Spawn (0180); None when it buries neither. Without a pod
// there is no spawn capsule.
field_place_buries_a_player :: proc(state: ^Simulation_State, content: Simulation_Content, edit: Field_Edit) -> Field_Edit_Refusal {
	for player in state.players {
		if field_place_meets_capsule(&state.field.world, state.field.spacing_millimetres, edit, field_player_capsule(content.field.tuning, player.field)) {
			return .Would_Bury_Player
		}
	}
	spawn, found := field_pod_spawn(&state.world.entities, content.machines)
	if found && field_place_meets_capsule(&state.field.world, state.field.spacing_millimetres, edit, field_player_capsule(content.field.tuning, spawn)) {
		return .Would_Bury_Spawn
	}
	return .None
}

// The selected tool digs the ground (0265): a shovel or a pickaxe. The
// hand and any other item dig nothing, and no refusal is told, since it
// would fire under every resting thumb.
field_player_digs :: proc(player: Field_Player) -> bool {
	return player.tool == .Tool && (player.held_tool_role == .Shovel || player.held_tool_role == .Pickaxe)
}

// The brush edit the player's tool asks for this tick: Dig held with a
// digging tool selected, or Place held, with the ground in reach. The
// tool tier and the place's budget are read when the queue drains.
field_player_edit :: proc(world: ^Field_World, spacing_millimetres: int, player: Field_Player, input: Field_Player_Input, brushes: []Field_Brush) -> (edit: Field_Edit, wanted: bool) {
	mode: Field_Edit_Mode
	switch {
	case .Dig in input.held && field_player_digs(player):
		mode = .Dig
	case .Place in input.held && player.tool == .Material:
		mode = .Place
	case:
		return {}, false
	}
	if !player.target.hit || len(brushes) == 0 {
		return {}, false
	}
	return Field_Edit {
			mode = mode,
			brush = brushes[int(player.brush) % len(brushes)],
			centre = player.target.position,
			up = player.up,
			material = player.held_material,
			tint = field_ground_sample_at(world, spacing_millimetres, player.target.position).tint,
		},
		true
}

// The first blocked material reported: Undiggable when it has no item,
// Needs_Shovel or Needs_Pickaxe when another role digs it, Tool_Tier
// otherwise.
report_blocked_dig :: proc(player: ^Player, table: Field_Material_Table, blocked: bit_set[Field_Material], role: Item_Tool_Role) {
	for material in Field_Material {
		if material in blocked {
			player.field_refusal = blocked_dig_refusal(table[material], role)
			player.field_refused_material = material
			return
		}
	}
}

blocked_dig_refusal :: proc(record: Field_Material_Record, role: Item_Tool_Role) -> Field_Edit_Refusal {
	switch {
	case record.item == NO_ITEM:
		return .Undiggable
	case record.dug_with != role:
		return record.dug_with == .Shovel ? .Needs_Shovel : .Needs_Pickaxe
	}
	return .Tool_Tier
}

// The material table's dig rates, as the edit carries them.
field_dig_rates :: proc(table: Field_Material_Table) -> [Field_Material]i32 {
	rates: [Field_Material]i32
	for record, material in table {
		rates[material] = i32(record.dig_rate_percent)
	}
	return rates
}

drain_field_dig :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, edit: Field_Edit) {
	field := &state.field
	dig := edit
	dig.diggable = field_diggable_materials(content.field.materials, player.field.held_tool_role, int(player.field.held_tool_tier))
	dig.dig_rate_percent = field_dig_rates(content.field.materials)
	dig.tick = state.tick
	result := apply_field_edit(&field.world, field.spacing_millimetres, dig)
	for steps, material in result.steps {
		if steps > 0 {
			volume := field_steps_to_volume(steps, field.spacing_millimetres)
			credit_field_volume(player.inventory, content.items, content.field.materials[material].item, &player.field_credit[material], volume)
		}
	}
	report_blocked_dig(player, content.field.materials, result.blocked, player.field.held_tool_role)
	fell_trees_over_dug_ground(state, content, dig)
}

drain_field_place :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, edit: Field_Edit) {
	field := &state.field
	material := edit.material
	item := content.field.materials[material].item
	place := edit
	if item != NO_ITEM {
		place.budget = field_place_volume_available(player.inventory, item, player.field_credit[material]) / field_steps_to_volume(1, field.spacing_millimetres)
	}
	if place.budget <= 0 {
		player.field_refusal, player.field_refused_material = .Nothing_Held, material
		return
	}
	if buried := field_place_buries_a_player(state, content, place); buried != .None {
		player.field_refusal, player.field_refused_material = buried, material
		return
	}
	result := apply_field_edit(&field.world, field.spacing_millimetres, place)
	debit_field_volume(player.inventory, item, &player.field_credit[material], field_steps_to_volume(result.steps[material], field.spacing_millimetres))
}

// The end of the tick: every queued edit in order, then the queue is
// empty, then the sky of the edits' shadows marches on the final field
// (update_field_sky_after_edits). The edited chunks are marked dirty by
// the world's set and remesh on the next revision.
drain_field_edits :: proc(state: ^Simulation_State, content: Simulation_Content) {
	for queued in state.field.edits {
		player := &state.players[queued.player]
		player.field_refusal, player.field_refused_material = .None, .Air
		switch queued.edit.mode {
		case .Dig:
			drain_field_dig(state, content, player, queued.edit)
		case .Place:
			drain_field_place(state, content, player, queued.edit)
		}
	}
	clear(&state.field.edits)
	update_field_sky_after_edits(&state.field.world)
}

// One player moves and queues its brush edit, its placements and a
// finished pick up (advance_field_pick_up) or, aimed at a trunk, a
// finished felling (advance_field_felling, 0197); nothing edits the field
// yet. The tool follows the hotbar (simulation_field.odin) before this
// runs. The move counts for the walk counter unless the player flies, as
// the block world's (0187).
queue_field_player_edit :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, input: Field_Player_Input) {
	field := &state.field
	player := &state.players[index]
	entities := &state.world.entities
	player.field_refusal, player.field_refused_material = .None, .Air
	walk_start := player.field.position
	move_and_aim_field_player(field, &entities.frames, content.field, &player.field, input)
	if !player.field.flying {
		record_field_walked(&state.records.statistics, walk_start, player.field.position, player.field.up)
	}
	if player.field.tree_target.hit {
		if felling, finished := advance_field_felling(state, content, player, input); finished {
			append(&field.placements, Queued_Field_Placement{player = index, placement = felling})
		}
	} else if pick_up, finished := advance_field_pick_up(state, content, player, input); finished {
		append(&field.placements, Queued_Field_Placement{player = index, placement = pick_up})
	}
	if edit, wanted := field_player_edit(&field.world, field.spacing_millimetres, player.field, input, content.field.brushes); wanted {
		append(&field.edits, Queued_Field_Edit{player = index, edit = edit})
	}
	machine := field_placed_machine(player.field, content)
	if placement, wanted := field_player_placement(player.field, machine, content); wanted && .Place in input.just_pressed {
		append(&field.placements, Queued_Field_Placement{player = index, placement = placement})
	}
	if placement, bare := field_bare_ground_placement(player.field, machine, content.machines); bare && .Place in input.just_pressed {
		append(&field.placements, Queued_Field_Placement{player = index, placement = placement})
	}
	if placement, wanted := update_field_run_tool(&player.field, entities, content, input); wanted {
		append(&field.placements, Queued_Field_Placement{player = index, placement = placement})
	}
}

// The edits, the placements, then the water (0172), so a hole dug this
// tick floods on the next, then the light (0173) within its budget. Runs
// after every player queued its edits (simulation_field.odin).
finish_field_tick :: proc(state: ^Simulation_State, content: Simulation_Content) {
	drain_field_edits(state, content)
	drain_field_placements(state, content)
	step_field_water(&state.field.world, content.field.water, state.tick)
	tick_field_light(&state.field.world, content.field.light)
}
