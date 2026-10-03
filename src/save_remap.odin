package game

import "core:fmt"
import "core:slice"
import "core:strings"
import "platform"

// Content tables and remapping (work item 0047). Saved values index the
// game data: blocks in chunks, items in stacks, machines of entities,
// recipes, technologies, quests, contracts, vein types and catalogue
// entries. The entities file carries the id tables of the build that
// wrote it, and loading maps every saved index to this build's index by
// id, so game data added, removed or reordered between builds keeps what
// each value refers to.
//
// Values of the distinct id types are remapped inside the codec
// (read_content_id). Plain integer indices and arrays indexed by an id are
// read into copies sized by the file's tables and remapped explicitly
// (the remap_ procedures here, called from save_state.odin). Chunk blocks
// are remapped in the region files' chunk palettes as the regions load
// (remap_chunk_palette), so the saved chunks hold this build's ids.
//
// An id that vanished becomes the none value (NO_ITEM, NO_FLUID,
// NO_MACHINE, air for blocks) or its entry is dropped: an item stack
// empties, a fluid buffer drains, a statistic or a quest's progress is
// dropped, a craft queue entry, a catalogue order or an open contract is
// removed, a queued technology dequeues, a crafting machine loses its
// recipe, an active quest gives way to the first quest not done. What
// cannot be dropped refuses the file with a problem naming the id: a
// placed machine, a registered vein's type, a block in a saved chunk.

Content_Table :: enum u8 {
	Blocks,
	Items,
	Fluids,
	Machines,
	Recipes,
	Technologies,
	Quests,
	Contracts,
	Vein_Types,
	Catalogue,
}

// The names in the file, so a table a later build adds or drops is
// skipped or read as empty.
@(rodata)
content_table_names := [Content_Table]string {
	.Blocks       = "blocks",
	.Items        = "items",
	.Fluids       = "fluids",
	.Machines     = "machines",
	.Recipes      = "recipes",
	.Technologies = "technologies",
	.Quests       = "quests",
	.Contracts    = "contracts",
	.Vein_Types   = "vein_types",
	.Catalogue    = "catalogue",
}

// Per table the ids in index order.
Content_Tables :: [Content_Table][]string

// The index a saved id has in this build, or CONTENT_GONE.
CONTENT_GONE :: -1

// Refuses a tables section longer than this before allocating for it.
MAXIMUM_CONTENT_TABLES_BYTES :: 16 * 1024 * 1024

Content_Remap :: struct {
	saved:            Content_Tables,
	current:          Content_Tables,
	// Indexed like saved: the index in current, or CONTENT_GONE.
	new_indices:      [Content_Table][]int,
	// Gone ids the codec met, and the first one per table.
	gone_count:       int,
	first_gone:       [Content_Table]string,
	// A block of a saved chunk this build has no more.
	gone_chunk_block: string,
	// Saved ids that are former ids of a current one (work item 0196), in
	// table order then saved order, in the temp allocator.
	renamed:          [dynamic]Content_Renamed_Id,
}

// A record that was renamed lists its old ids as former_ids (items,
// machines and recipes, work item 0196): a save naming the old id loads
// it as the record.
Content_Former_Id :: struct {
	former, current: string,
}

Content_Former_Ids :: [Content_Table][]Content_Former_Id

Content_Renamed_Id :: struct {
	table:           Content_Table,
	former, current: string,
}

// Tables of the game data.

// Catalogue entries have no id: the item and count, or the survey.
catalogue_entry_key :: proc(entry: Catalogue_Entry, items: Item_Registry) -> string {
	if entry.orbital_survey || int(entry.item) >= len(items.items) {
		return "orbital_survey"
	}
	return fmt.tprintf("%s x%d", items.items[entry.item].id, entry.count)
}

// In the temp allocator.
content_tables :: proc(content: Simulation_Content) -> (tables: Content_Tables) {
	tables[.Blocks] = make([]string, len(content.blocks.definitions), context.temp_allocator)
	for definition, index in content.blocks.definitions {
		tables[.Blocks][index] = definition.id
	}
	tables[.Items] = make([]string, len(content.items.items), context.temp_allocator)
	for item, index in content.items.items {
		tables[.Items][index] = item.id
	}
	tables[.Fluids] = make([]string, len(content.fluids.fluids), context.temp_allocator)
	for fluid, index in content.fluids.fluids {
		tables[.Fluids][index] = fluid.id
	}
	tables[.Machines] = make([]string, len(content.machines.machines), context.temp_allocator)
	for machine, index in content.machines.machines {
		tables[.Machines][index] = machine.id
	}
	tables[.Recipes] = make([]string, len(content.recipes.recipes), context.temp_allocator)
	for recipe, index in content.recipes.recipes {
		tables[.Recipes][index] = recipe.id
	}
	tables[.Technologies] = make([]string, len(content.technologies.technologies), context.temp_allocator)
	for technology, index in content.technologies.technologies {
		tables[.Technologies][index] = technology.id
	}
	tables[.Quests] = make([]string, len(content.quests.quests), context.temp_allocator)
	for quest, index in content.quests.quests {
		tables[.Quests][index] = quest.id
	}
	tables[.Contracts] = make([]string, len(content.contracts.contracts), context.temp_allocator)
	for contract, index in content.contracts.contracts {
		tables[.Contracts][index] = contract.id
	}
	tables[.Vein_Types] = make([]string, len(content.veins.types), context.temp_allocator)
	for vein_type, index in content.veins.types {
		tables[.Vein_Types][index] = vein_type.id
	}
	tables[.Catalogue] = make([]string, len(content.contracts.catalogue), context.temp_allocator)
	for entry, index in content.contracts.catalogue {
		tables[.Catalogue][index] = catalogue_entry_key(entry, content.items)
	}
	return tables
}

// A u32 byte length, a u16 table count, then per table its name, a u32
// id count and the ids.
append_content_tables :: proc(bytes: ^[dynamic]byte, tables: Content_Tables) {
	length_offset := len(bytes)
	append_u32(bytes, 0)
	append_u16(bytes, u16(len(Content_Table)))
	for table in Content_Table {
		append_string(bytes, content_table_names[table])
		append_u32(bytes, u32(len(tables[table])))
		for id in tables[table] {
			append_string(bytes, id)
		}
	}
	patch_length(bytes, length_offset)
}

content_table_of_name :: proc(name: string) -> (table: Content_Table, found: bool) {
	for candidate in Content_Table {
		if content_table_names[candidate] == name {
			return candidate, true
		}
	}
	return {}, false
}

// The ids are views into the reader's data.
read_content_table :: proc(reader: ^Byte_Reader) -> (ids: []string, ok: bool) {
	count := int(read_u32(reader) or_return)
	if count > bytes_left(reader^) / size_of(u32) {
		return nil, false
	}
	ids = make([]string, count, context.temp_allocator)
	for &id in ids {
		id = read_string(reader) or_return
	}
	return ids, true
}

// The section append_content_tables wrote, in the temp allocator.
read_content_tables :: proc(reader: ^Byte_Reader) -> (tables: Content_Tables, ok: bool) {
	length := int(read_u32(reader) or_return)
	if length > bytes_left(reader^) {
		return {}, false
	}
	section := Byte_Reader {
		data = reader.data[reader.offset:][:length],
	}
	reader.offset += length
	count := int(read_u16(&section) or_return)
	for _ in 0 ..< count {
		name := read_string(&section) or_return
		ids := read_content_table(&section) or_return
		if table, found := content_table_of_name(name); found {
			tables[table] = ids
		}
	}
	return tables, bytes_left(section) == 0
}

// Former ids (work item 0196).

// The items', machines' and recipes' former ids, in the temp allocator.
content_former_ids :: proc(content: Simulation_Content) -> (former: Content_Former_Ids) {
	items := make([dynamic]Content_Former_Id, context.temp_allocator)
	for item in content.items.items {
		for id in item.former_ids {
			append(&items, Content_Former_Id{id, item.id})
		}
	}
	machines := make([dynamic]Content_Former_Id, context.temp_allocator)
	for machine in content.machines.machines {
		for id in machine.former_ids {
			append(&machines, Content_Former_Id{id, machine.id})
		}
	}
	recipes := make([dynamic]Content_Former_Id, context.temp_allocator)
	for recipe in content.recipes.recipes {
		for id in recipe.former_ids {
			append(&recipes, Content_Former_Id{id, recipe.id})
		}
	}
	former[.Items], former[.Machines], former[.Recipes] = items[:], machines[:], recipes[:]
	return former
}

// A former id that is also a current id of its table, or listed twice in
// one table, would make a saved id ambiguous; "" when there is none.
content_former_id_problem :: proc(content: Game_Content) -> string {
	former := content_former_ids(content.simulation_content)
	current := content_tables(content.simulation_content)
	for table in Content_Table {
		for entry, index in former[table] {
			if slice.contains(current[table], entry.former) {
				return fmt.tprintf("%s: %s %q lists the former id %q, which is also an id", former_id_file_name(table), content_table_names[table], entry.current, entry.former)
			}
			for other in former[table][index + 1:] {
				if other.former == entry.former {
					return fmt.tprintf("%s: %s list the former id %q twice", former_id_file_name(table), content_table_names[table], entry.former)
				}
			}
		}
	}
	return ""
}

// The file of a table that has former ids, for the load's error line.
former_id_file_name :: proc(table: Content_Table) -> string {
	#partial switch table {
	case .Items:
		return ITEMS_FILE_NAME
	case .Recipes:
		return RECIPES_FILE_NAME
	}
	return MACHINES_FILE_NAME
}

// The current id a saved id was renamed to, or "".
former_id_current :: proc(former: []Content_Former_Id, id: string) -> string {
	for entry in former {
		if entry.former == id {
			return entry.current
		}
	}
	return ""
}

// "" without renames, else the one line the load logs.
renamed_content_line :: proc(remap: Content_Remap) -> string {
	if len(remap.renamed) == 0 {
		return ""
	}
	parts := make([dynamic]string, context.temp_allocator)
	last_table := Content_Table(len(Content_Table))
	for entry in remap.renamed {
		if entry.table != last_table {
			append(&parts, fmt.tprintf("%s %s as %s", content_table_names[entry.table], entry.former, entry.current))
		} else {
			append(&parts, fmt.tprintf("%s as %s", entry.former, entry.current))
		}
		last_table = entry.table
	}
	return fmt.tprintf("save: loaded under renamed ids: %s", strings.join(parts[:], ", ", context.temp_allocator))
}

// The remap.

// A saved id missing from the current table that is a former id maps to
// the record that lists it, noted in renamed.
make_content_remap :: proc(saved, current: Content_Tables, former: Content_Former_Ids = {}) -> Content_Remap {
	remap := Content_Remap {
		saved   = saved,
		current = current,
		renamed = make([dynamic]Content_Renamed_Id, context.temp_allocator),
	}
	for table in Content_Table {
		index_of_id := make(map[string]int, len(current[table]), context.temp_allocator)
		#reverse for id, index in current[table] {
			index_of_id[id] = index
		}
		remap.new_indices[table] = make([]int, len(saved[table]), context.temp_allocator)
		for id, old_index in saved[table] {
			new_index, found := index_of_id[id]
			renamed_to := found ? "" : former_id_current(former[table], id)
			if renamed_to != "" {
				new_index, found = index_of_id[renamed_to]
				if found {
					append(&remap.renamed, Content_Renamed_Id{table, id, renamed_to})
				}
			}
			remap.new_indices[table][old_index] = found ? new_index : CONTENT_GONE
		}
	}
	return remap
}

// The new index of a saved one, CONTENT_GONE for a vanished id, and
// whether the saved index lies in the saved table at all.
remapped_index :: proc(remap: Content_Remap, table: Content_Table, old_index: int) -> (new_index: int, in_range: bool) {
	if old_index < 0 || old_index >= len(remap.new_indices[table]) {
		return old_index, false
	}
	return remap.new_indices[table][old_index], true
}

// Whether this build has an id the saved table lacks.
content_table_grew :: proc(remap: Content_Remap, table: Content_Table) -> bool {
	kept := 0
	for new_index in remap.new_indices[table] {
		kept += new_index == CONTENT_GONE ? 0 : 1
	}
	return kept < len(remap.current[table])
}

content_gone_count :: proc(remap: ^Content_Remap) -> int {
	return remap == nil ? 0 : remap.gone_count
}

note_gone_id :: proc(remap: ^Content_Remap, table: Content_Table, old_index: int) {
	remap.gone_count += 1
	if remap.first_gone[table] == "" {
		remap.first_gone[table] = remap.saved[table][old_index]
	}
}

// The codec's side.

content_id_table :: proc(id: typeid) -> (table: Content_Table, is_id: bool) {
	switch id {
	case Block_Id:
		return .Blocks, true
	case Item_Id:
		return .Items, true
	case Fluid_Id:
		return .Fluids, true
	case Machine_Id:
		return .Machines, true
	}
	return {}, false
}

// What a vanished id reads as: the none value, air for blocks.
gone_content_id :: proc(table: Content_Table, size: int) -> u64 {
	return table == .Blocks ? u64(AIR_BLOCK) : enum_value_mask(size)
}

// The none value (all bits set) stays. Without a remap ids read as
// written.
read_content_id :: proc(reader: ^Byte_Reader, pointer: rawptr, size: int, table: Content_Table) -> bool {
	stored := read_unsigned(reader, size) or_return
	if reader.remap == nil || stored == enum_value_mask(size) {
		store_unsigned(pointer, size, stored)
		return true
	}
	new_index, in_range := remapped_index(reader.remap^, table, int(stored))
	if !in_range {
		return false
	}
	if new_index == CONTENT_GONE {
		note_gone_id(reader.remap, table, int(stored))
		store_unsigned(pointer, size, gone_content_id(table, size))
		return true
	}
	store_unsigned(pointer, size, u64(new_index))
	return true
}

// A value that met a vanished id while it was read: a stack of a gone
// item empties, a buffer of a gone fluid drains.
empty_value_of_gone_content :: proc(pointer: rawptr, id: typeid) {
	switch id {
	case Item_Stack:
		stack := (^Item_Stack)(pointer)
		if stack.item == NO_ITEM {
			stack.count = 0
		}
	case Fluid_Buffer:
		buffer := (^Fluid_Buffer)(pointer)
		if buffer.fluid == NO_FLUID {
			buffer^ = Fluid_Buffer {
				fluid = NO_FLUID,
			}
		}
	}
}

// Chunk palettes: after the u16 format version and the u16 palette
// length, the palette's u16 block ids (world_serialize.odin). The bytes
// must have passed deserialize_chunk_blocks.
remap_chunk_palette :: proc(bytes: []byte, remap: ^Content_Remap) -> bool {
	if remap == nil {
		return true
	}
	length := int(u16(bytes[2]) | u16(bytes[3]) << 8)
	for index in 0 ..< length {
		offset := 4 + 2 * index
		old_index := int(u16(bytes[offset]) | u16(bytes[offset + 1]) << 8)
		new_index, in_range := remapped_index(remap^, .Blocks, old_index)
		if !in_range {
			return false
		}
		if new_index == CONTENT_GONE {
			remap.gone_chunk_block = remap.saved[.Blocks][old_index]
			return false
		}
		bytes[offset], bytes[offset + 1] = byte(new_index), byte(new_index >> 8)
	}
	return true
}

// Arrays indexed by an id.

// Copies each saved entry of stride values to its new index; the target
// is zeroed first, so new ids start at zero and gone ones are dropped.
reindexed :: proc(target, source: []$T, new_indices: []int, stride: int) -> []T {
	for &value in target {
		value = {}
	}
	for new_index, old_index in new_indices {
		if new_index == CONTENT_GONE || (old_index + 1) * stride > len(source) || (new_index + 1) * stride > len(target) {
			continue
		}
		copy(target[new_index * stride:][:stride], source[old_index * stride:][:stride])
	}
	return target
}

reindexed_rings :: proc(target, source: Item_Rate_Rings, new_indices: []int) -> Item_Rate_Rings {
	return Item_Rate_Rings {
		per_second = reindexed(target.per_second, source.per_second, new_indices, RATE_BUCKET_COUNT),
		per_ten_seconds = reindexed(target.per_ten_seconds, source.per_ten_seconds, new_indices, RATE_BUCKET_COUNT),
		per_minute = reindexed(target.per_minute, source.per_minute, new_indices, RATE_BUCKET_COUNT),
	}
}

// Sized by the file's tables, in the temp allocator, for the codec to
// read into.
saved_statistics :: proc(remap: Content_Remap) -> Statistics {
	statistics := make_statistics(len(remap.saved[.Items]), len(remap.saved[.Machines]), len(remap.saved[.Blocks]), context.temp_allocator)
	statistics.fluids = make_fluid_statistics(len(remap.saved[.Fluids]), context.temp_allocator)
	return statistics
}

// Every other field comes as saved. A new slice indexed by an id in
// Statistics must be added here, or it loads as zero.
remap_statistics :: proc(target: ^Statistics, saved: Statistics, remap: Content_Remap) {
	items, machines, blocks := remap.new_indices[.Items], remap.new_indices[.Machines], remap.new_indices[.Blocks]
	result := saved
	result.produced = reindexed(target.produced, saved.produced, items, 1)
	result.obtained = reindexed(target.obtained, saved.obtained, items, 1)
	result.delivered = reindexed(target.delivered, saved.delivered, items, 1)
	result.voided = reindexed(target.voided, saved.voided, items, 1)
	result.consumed = reindexed(target.consumed, saved.consumed, items, 1)
	result.shipped = reindexed(target.shipped, saved.shipped, items, 1)
	result.blocks_placed = reindexed(target.blocks_placed, saved.blocks_placed, items, 1)
	result.held_totals = reindexed(target.held_totals, saved.held_totals, items, 1)
	result.capsule_totals = reindexed(target.capsule_totals, saved.capsule_totals, items, 1)
	result.placed = reindexed(target.placed, saved.placed, machines, 1)
	result.mining_ticks = reindexed(target.mining_ticks, saved.mining_ticks, blocks, 1)
	result.produced_rates = reindexed_rings(target.produced_rates, saved.produced_rates, items)
	result.consumed_rates = reindexed_rings(target.consumed_rates, saved.consumed_rates, items)
	result.fluids = remapped_fluid_statistics(target.fluids, saved.fluids, remap.new_indices[.Fluids])
	target^ = result
}

remapped_fluid_statistics :: proc(target, saved: Fluid_Statistics, fluids: []int) -> Fluid_Statistics {
	return Fluid_Statistics {
		produced = reindexed(target.produced, saved.produced, fluids, 1),
		consumed = reindexed(target.consumed, saved.consumed, fluids, 1),
		voided = reindexed(target.voided, saved.voided, fluids, 1),
		produced_rates = reindexed_rings(target.produced_rates, saved.produced_rates, fluids),
		consumed_rates = reindexed_rings(target.consumed_rates, saved.consumed_rates, fluids),
		voided_rates = reindexed_rings(target.voided_rates, saved.voided_rates, fluids),
	}
}

// Sized by the file's tables, in the temp allocator.
saved_recipe_unlocks :: proc(remap: Content_Remap) -> Recipe_Unlocks {
	recipe_count := len(remap.saved[.Recipes])
	return Recipe_Unlocks {
		obtained = make([]bool, len(remap.saved[.Items]), context.temp_allocator),
		researched = make([]bool, len(remap.saved[.Technologies]), context.temp_allocator),
		quest_unlocked = make([]bool, recipe_count, context.temp_allocator),
		schematics_found = make([]bool, recipe_count, context.temp_allocator),
		available = make([]bool, recipe_count, context.temp_allocator),
	}
}

// Availability is recomputed, so recipes this build added are available
// when their conditions hold.
remap_recipe_unlocks :: proc(target: ^Recipe_Unlocks, saved: Recipe_Unlocks, remap: Content_Remap, recipes: Recipe_Registry) {
	recipe_indices := remap.new_indices[.Recipes]
	reindexed(target.obtained, saved.obtained, remap.new_indices[.Items], 1)
	reindexed(target.researched, saved.researched, remap.new_indices[.Technologies], 1)
	reindexed(target.quest_unlocked, saved.quest_unlocked, recipe_indices, 1)
	reindexed(target.schematics_found, saved.schematics_found, recipe_indices, 1)
	reindexed(target.available, saved.available, recipe_indices, 1)
	target.unlock_all = saved.unlock_all
	if target.unlock_all {
		mark_everything_unlocked(target)
	}
	refresh_available_recipes(target, recipes)
}

// A queued technology that vanished dequeues, a finished one that did is
// forgotten. Indices outside the saved table (the unqueued default) stay.
remapped_research :: proc(saved: Research_State, remap: Content_Remap) -> Research_State {
	saved := saved
	technologies := remap.new_indices[.Technologies]
	result := saved
	reindexed(result.units_kept[:], saved.units_kept[:], technologies, 1)
	reindexed(result.levels[:], saved.levels[:], technologies, 1)
	if technology, in_range := remapped_index(remap, .Technologies, saved.technology); in_range {
		result.technology = technology
		if technology == CONTENT_GONE {
			result.queued, result.technology, result.units_done = false, 0, 0
		}
	}
	if technology, in_range := remapped_index(remap, .Technologies, saved.finished_technology); in_range {
		result.finished_technology = technology
		if technology == CONTENT_GONE {
			result.finished, result.finished_technology = false, 0
		}
	}
	return result
}

// Open contracts of a vanished contract free their slot, the others keep
// their order.
remapped_contracts :: proc(saved: Contract_State, remap: Content_Remap) -> (result: Contract_State, ok: bool) {
	saved := saved
	if saved.open_count < 0 || saved.open_count > MAXIMUM_OPEN_CONTRACTS {
		return {}, false
	}
	for open in saved.open[:saved.open_count] {
		contract := remapped_index(remap, .Contracts, int(open.contract)) or_return
		if contract != CONTENT_GONE {
			result.open[result.open_count] = open
			result.open[result.open_count].contract = i32(contract)
			result.open_count += 1
		}
	}
	reindexed(result.offer_counts[:], saved.offer_counts[:], remap.new_indices[.Contracts], 1)
	return result, true
}

// Orders of a vanished catalogue entry are dropped.
remap_catalogue_orders :: proc(orders: ^[dynamic]Catalogue_Order, remap: Content_Remap) -> bool {
	kept := 0
	for order in orders {
		entry := remapped_index(remap, .Catalogue, int(order.entry)) or_return
		if entry != CONTENT_GONE {
			orders[kept] = order
			orders[kept].entry = i32(entry)
			kept += 1
		}
	}
	resize(orders, kept)
	return true
}

// NO_RECIPE stays; a vanished recipe becomes NO_RECIPE.
remapped_recipe :: proc(remap: Content_Remap, recipe: int) -> (new_recipe: int, ok: bool) {
	if recipe == NO_RECIPE {
		return NO_RECIPE, true
	}
	new_recipe = remapped_index(remap, .Recipes, recipe) or_return
	return new_recipe == CONTENT_GONE ? NO_RECIPE : new_recipe, true
}

// A furnace smelting a vanished recipe stops, an assembler set to one
// loses the recipe and what its recipe slots held.
remap_machine_recipes :: proc(entities: ^Entities, remap: Content_Remap, recipes: Recipe_Registry) -> bool {
	for &furnace in entities.furnaces.entries {
		saved := furnace.recipe
		furnace.recipe = remapped_recipe(remap, saved) or_return
		if furnace.recipe == NO_RECIPE && saved != NO_RECIPE {
			furnace.progress_ticks = 0
		}
	}
	for &assembler in entities.assemblers.entries {
		saved := assembler.recipe
		assembler.recipe = remapped_recipe(remap, saved) or_return
		if assembler.recipe == NO_RECIPE && saved != NO_RECIPE {
			set_assembler_recipe(&assembler, recipes, NO_RECIPE)
		}
	}
	return true
}

// Runs of a vanished recipe leave the queue; the ingredients a craft in
// progress took are lost with it. A queue saved before work item 0138
// counted single crafts in count and held them in a field this build
// lacks, so it reads as runs of no crafts: it comes back empty, with one
// log line (the ingredients those crafts took when queued are lost).
remap_craft_queue :: proc(queue: ^Craft_Queue, remap: Content_Remap) -> bool {
	if queue.count < 0 || queue.count > HAND_CRAFT_QUEUE_RUNS {
		return false
	}
	if craft_queue_has_empty_runs(queue^) {
		platform.log_printf("save: dropped a hand crafting queue of %d crafts saved in the layout before work item 0138", queue.count)
		queue^ = make_craft_queue()
		return true
	}
	saved := queue^
	queue.count = 0
	for run, position in saved.runs[:saved.count] {
		new_recipe := remapped_index(remap, .Recipes, run.recipe) or_return
		if new_recipe == CONTENT_GONE {
			if position == 0 {
				reset_front_craft(queue)
			}
			continue
		}
		queue.runs[queue.count] = {new_recipe, run.count}
		queue.count += 1
	}
	if queue.count == 0 {
		reset_front_craft(queue)
	}
	return true
}

// A run of no crafts, which only a queue of the older layout has.
craft_queue_has_empty_runs :: proc(queue: Craft_Queue) -> bool {
	queue := queue
	for run in queue.runs[:queue.count] {
		if run.count <= 0 {
			return true
		}
	}
	return false
}

// A registered vein of a vanished type cannot be dropped (drills and
// outcrops name it), so it refuses the file. Prospecting records of one
// are dropped.
remap_vein_types :: proc(world: ^World, records: ^Game_Records, remap: Content_Remap) -> (problem: string, ok: bool) {
	for &vein in world.veins {
		saved := vein.type
		vein.type = remapped_index(remap, .Vein_Types, saved) or_return
		if vein.type == CONTENT_GONE {
			return fmt.tprintf("the save has veins of type %s, which this build's game data no longer has", remap.saved[.Vein_Types][saved]), false
		}
	}
	kept := 0
	for assayed in records.assayed_veins {
		type := remapped_index(remap, .Vein_Types, assayed.type) or_return
		if type != CONTENT_GONE {
			records.assayed_veins[kept] = assayed
			records.assayed_veins[kept].type = type
			kept += 1
		}
	}
	resize(&records.assayed_veins, kept)
	for &sample in records.core_samples {
		if !sample.vein_found {
			continue
		}
		sample.vein_type = remapped_index(remap, .Vein_Types, sample.vein_type) or_return
		if sample.vein_type == CONTENT_GONE {
			sample.vein_found, sample.vein, sample.vein_type = false, {}, 0
		}
	}
	return "", true
}

// Placed entities of a vanished machine cannot be dropped (their cells,
// networks and contents), so they refuse the file. Freed slots of one
// take machine 0, which the consistency check accepts.
settle_gone_machines :: proc(pool: ^Entity_Pool($T), reader: ^Byte_Reader) -> bool {
	if reader.remap == nil {
		return true
	}
	for &entry in pool.entries {
		if entry.machine != NO_MACHINE {
			continue
		}
		if entry.alive {
			reader.problem = fmt.tprintf("the save has placed %s machines, which this build's game data no longer has", reader.remap.first_gone[.Machines])
			return false
		}
		entry.machine = 0
	}
	return true
}

// Cargo of a vanished item leaves the shipment record.
remap_shipments :: proc(shipments: []Shipment) {
	for &shipment in shipments {
		kept: i32
		for cargo in shipment.cargo[:shipment.cargo_count] {
			if cargo.item != NO_ITEM {
				shipment.cargo[kept] = cargo
				kept += 1
			}
		}
		for &cargo in shipment.cargo[kept:shipment.cargo_count] {
			cargo = {}
		}
		shipment.cargo_count = kept
	}
}

drop_gone_belt_items :: proc(items: ^[dynamic]Belt_Cell_Item) {
	kept := 0
	for item in items {
		if item.item != NO_ITEM {
			items[kept] = item
			kept += 1
		}
	}
	resize(items, kept)
}

// Stacks of a vanished item leave a list (pending quest rewards).
drop_gone_item_stacks :: proc(stacks: ^[dynamic]Item_Stack) {
	kept := 0
	for stack in stacks {
		if stack.item != NO_ITEM {
			stacks[kept] = stack
			kept += 1
		}
	}
	resize(stacks, kept)
}

// The active quest by its new index. When it vanished, or when every
// saved quest was done and this build added quests, the first quest not
// done becomes active.
settle_active_quest :: proc(quests: ^Quest_State, saved_active: int, remap: Content_Remap, registry: Quest_Registry, statistics: Statistics, tick: u64) -> bool {
	active := NO_QUEST
	if saved_active != NO_QUEST {
		active = remapped_index(remap, .Quests, saved_active) or_return
	}
	quests.active = active
	if active == CONTENT_GONE || (saved_active == NO_QUEST && content_table_grew(remap, .Quests)) {
		activate_quest(quests, registry, first_quest_not_done(quests.progress), statistics, tick)
	}
	return true
}

first_quest_not_done :: proc(progress: []Quest_Progress) -> int {
	for entry, index in progress {
		if entry.status != .Done {
			return index
		}
	}
	return NO_QUEST
}
