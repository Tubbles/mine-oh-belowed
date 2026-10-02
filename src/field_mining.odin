package game

import "core:encoding/json"
import "core:fmt"
import "platform"

// Digging and placing the terrain field by hand and the item yield (work
// item 0171, doc/architecture.md, The terrain field's brushes; doc/
// content.md, Field materials). The field's share of the simulation until
// the slice (0179) puts it on Simulation_State: the field world, its
// players with their inventories, and the edit queue.
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
	tool_tier: int,
}

Field_Materials_File :: struct {
	materials: []Field_Material_Definition,
}

Field_Material_Record :: struct {
	// NO_ITEM: the material cannot be dug or placed (air, bedrock).
	item:      Item_Id,
	tool_tier: int,
}

Field_Material_Table :: [Field_Material]Field_Material_Record

// Why the hand tool's latest edit did less than asked.
Field_Edit_Refusal :: enum u8 {
	None,
	// The ground's material needs a better pickaxe than any carried.
	Tool_Tier,
	// The material yields no item (bedrock).
	Undiggable,
	// No held material in the inventory or the credit.
	Nothing_Held,
	// The raised volume would overlap a player's capsule.
	Would_Bury_Player,
}

Field_Miner :: struct {
	body:             Field_Player,
	inventory:        Inventory,
	// Volume short of a whole item per material, in the unit of
	// FIELD_ITEM_VOLUME.
	credit:           [Field_Material]i64,
	refusal:          Field_Edit_Refusal,
	refused_material: Field_Material,
}

Queued_Field_Edit :: struct {
	player: int,
	edit:   Field_Edit,
}

Field_Simulation :: struct {
	world:               Field_World,
	spacing_millimetres: int,
	players:             [dynamic]Field_Miner,
	// The edit queue: filled by the players' ticks, drained at the end of
	// the tick in order. Not saved; empty between ticks.
	edits:               [dynamic]Queued_Field_Edit,
	tick:                u64,
}

Field_Simulation_Content :: struct {
	items:     Item_Registry,
	materials: Field_Material_Table,
	brushes:   []Field_Brush,
	tuning:    Field_Player_Tuning,
}

destroy_field_simulation :: proc(simulation: ^Field_Simulation) {
	for player in simulation.players {
		destroy_inventory(player.inventory)
	}
	delete(simulation.players)
	delete(simulation.edits)
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
	record = {item = NO_ITEM, tool_tier = definition.tool_tier}
	if definition.item != "" {
		found: bool
		if record.item, found = find_item_id(items, definition.item); !found {
			return {}, fmt.tprintf("item %q is not in items.sjson", definition.item)
		}
	}
	if highest := highest_tool_tier(items.items); definition.tool_tier < 0 || definition.tool_tier > highest {
		return {}, fmt.tprintf("tool_tier %d is outside 0 to %d", definition.tool_tier, highest)
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

// The materials the tier digs.
field_diggable_materials :: proc(table: Field_Material_Table, tool_tier: int) -> bit_set[Field_Material] {
	diggable: bit_set[Field_Material]
	for record, material in table {
		if record.item != NO_ITEM && record.tool_tier <= tool_tier {
			diggable += {material}
		}
	}
	return diggable
}

// The material after current that has an item, round the table; Air when
// none has.
next_placeable_field_material :: proc(table: Field_Material_Table, current: Field_Material) -> Field_Material {
	count := len(Field_Material)
	for offset in 1 ..= count {
		candidate := Field_Material((int(current) + offset) % count)
		if table[candidate].item != NO_ITEM {
			return candidate
		}
	}
	return .Air
}

// The best tool_tier carried, 0 for bare hands, as player_tool_tier.
field_tool_tier :: proc(inventory: Inventory, items: Item_Registry) -> int {
	tier := 0
	for stack in inventory.slots {
		tier = max(tier, stack_tool_tier(stack, items))
	}
	return tier
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

field_player_capsule :: proc(tuning: Field_Player_Tuning, player: Field_Player) -> Field_Capsule {
	return Field_Capsule {
		bottom = player.position + World_Position(fixed_scale(player.up, tuning.capsule_radius)),
		up = player.up,
		length = tuning.capsule_height - 2 * tuning.capsule_radius,
		radius = tuning.capsule_radius,
	}
}

// A place that would raise a sample within its trilinear support of any
// field player's capsule (field_place_meets_capsule).
field_place_buries_a_player :: proc(simulation: ^Field_Simulation, tuning: Field_Player_Tuning, edit: Field_Edit) -> bool {
	for player in simulation.players {
		if field_place_meets_capsule(&simulation.world, simulation.spacing_millimetres, edit, field_player_capsule(tuning, player.body)) {
			return true
		}
	}
	return false
}

// The brush edit the player's tool asks for this tick: Dig or Place held
// with the ground in reach. The tool tier and the place's budget are read
// when the queue drains.
field_player_edit :: proc(world: ^Field_World, spacing_millimetres: int, player: Field_Player, input: Field_Player_Input, brushes: []Field_Brush) -> (edit: Field_Edit, wanted: bool) {
	mode: Field_Edit_Mode
	switch {
	case .Dig in input.held:
		mode = .Dig
	case .Place in input.held:
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

// The brush and held material keys.
update_field_tool :: proc(player: ^Field_Player, input: Field_Player_Input, content: Field_Simulation_Content) {
	if .Next_Brush in input.just_pressed && len(content.brushes) > 0 {
		player.brush = u8((int(player.brush) + 1) % len(content.brushes))
	}
	if .Next_Material in input.just_pressed {
		player.held_material = next_placeable_field_material(content.materials, player.held_material)
	}
}

// The first blocked material reported: Undiggable when it has no item,
// Tool_Tier otherwise.
report_blocked_dig :: proc(player: ^Field_Miner, table: Field_Material_Table, blocked: bit_set[Field_Material]) {
	for material in Field_Material {
		if material in blocked {
			player.refusal = table[material].item == NO_ITEM ? .Undiggable : .Tool_Tier
			player.refused_material = material
			return
		}
	}
}

drain_field_dig :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content, player: ^Field_Miner, edit: Field_Edit) {
	dig := edit
	dig.diggable = field_diggable_materials(content.materials, field_tool_tier(player.inventory, content.items))
	result := apply_field_edit(&simulation.world, simulation.spacing_millimetres, dig)
	for steps, material in result.steps {
		if steps > 0 {
			volume := field_steps_to_volume(steps, simulation.spacing_millimetres)
			credit_field_volume(player.inventory, content.items, content.materials[material].item, &player.credit[material], volume)
		}
	}
	report_blocked_dig(player, content.materials, result.blocked)
}

drain_field_place :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content, player: ^Field_Miner, edit: Field_Edit) {
	material := edit.material
	item := content.materials[material].item
	place := edit
	if item != NO_ITEM {
		place.budget = field_place_volume_available(player.inventory, item, player.credit[material]) / field_steps_to_volume(1, simulation.spacing_millimetres)
	}
	switch {
	case place.budget <= 0:
		player.refusal, player.refused_material = .Nothing_Held, material
		return
	case field_place_buries_a_player(simulation, content.tuning, place):
		player.refusal, player.refused_material = .Would_Bury_Player, material
		return
	}
	result := apply_field_edit(&simulation.world, simulation.spacing_millimetres, place)
	debit_field_volume(player.inventory, item, &player.credit[material], field_steps_to_volume(result.steps[material], simulation.spacing_millimetres))
}

// The end of the tick: every queued edit in order, then the queue is
// empty. The edited chunks are marked dirty by the world's set and
// remesh on the next revision.
drain_field_edits :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content) {
	for queued in simulation.edits {
		player := &simulation.players[queued.player]
		player.refusal, player.refused_material = .None, .Air
		switch queued.edit.mode {
		case .Dig:
			drain_field_dig(simulation, content, player, queued.edit)
		case .Place:
			drain_field_place(simulation, content, player, queued.edit)
		}
	}
	clear(&simulation.edits)
}

// Each player moves and queues its brush edit; nothing edits the field
// yet. inputs[index] is players[index]'s; a missing one is no input.
queue_field_player_edits :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content, inputs: []Field_Player_Input) {
	for &player, index in simulation.players {
		input := index < len(inputs) ? inputs[index] : Field_Player_Input{}
		player.refusal, player.refused_material = .None, .Air
		tick_field_player(&simulation.world, content.tuning, &player.body, input)
		update_field_tool(&player.body, input, content)
		if edit, wanted := field_player_edit(&simulation.world, simulation.spacing_millimetres, player.body, input, content.brushes); wanted {
			append(&simulation.edits, Queued_Field_Edit{player = index, edit = edit})
		}
	}
}

tick_field_simulation :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content, inputs: []Field_Player_Input) {
	simulation.tick += 1
	queue_field_player_edits(simulation, content, inputs)
	drain_field_edits(simulation, content)
}
