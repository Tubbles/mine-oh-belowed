package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:slice"
import "platform"

// Item prototypes from data/items.sjson, resolved to a dense Item_Id at
// startup like the blocks. The inventory, mining drops and placing all go
// through this one table.

ITEMS_FILE_NAME :: "items.sjson"
MAXIMUM_STACK_SIZE :: 1000
MAXIMUM_TOOL_TIER :: 15

// Dense index into Item_Registry.items.
Item_Id :: distinct u16

// No item: a block without a drop.
NO_ITEM :: Item_Id(max(u16))

// The inventory sorts in this order.
Item_Category :: enum u8 {
	Raw,
	Intermediate,
	Tool,
	Machine,
	Block,
}

@(rodata)
item_category_names := [Item_Category]string {
	.Raw          = "raw",
	.Intermediate = "intermediate",
	.Tool         = "tool",
	.Machine      = "machine",
	.Block        = "block",
}

// What Use_Item does with a usable item (work item 0038): read a
// schematic, assay the targeted outcrop's vein, record a magnetometer
// reading, or fire a seismic shot at the targeted ground.
Item_Use :: enum u8 {
	Read,
	Assay,
	Magnetometer,
	Seismic_Shot,
}

@(rodata)
item_use_names := [Item_Use]string {
	.Read         = "read",
	.Assay        = "assay",
	.Magnetometer = "magnetometer",
	.Seismic_Shot = "seismic_shot",
}

// What the inventory view's configure pop-up (0202) sets for every item
// of a kind: nothing, or the foundation block's size and height (0193).
// The pop-up's content is chosen by this value, so a later configurable
// item adds a value and a case, not a mechanism.
Item_Configuration :: enum u8 {
	None,
	Foundation_Block,
}

@(rodata)
item_configuration_names := [Item_Configuration]string {
	.None             = "",
	.Foundation_Block = "foundation_block",
}

// Which work a tool does on the terrain field (0265): a shovel digs
// soil, a pickaxe stone and ore, an axe fells trees. None for every
// other item, a role-less tool (the geologist's hammer) included.
Item_Tool_Role :: enum u8 {
	None,
	Shovel,
	Pickaxe,
	Axe,
}

@(rodata)
item_tool_role_names := [Item_Tool_Role]string {
	.None    = "",
	.Shovel  = "shovel",
	.Pickaxe = "pickaxe",
	.Axe     = "axe",
}

// As written in the file, before references are resolved.
Item_Definition :: struct {
	id:              string,
	name_key:        string,
	description_key: string,
	category:        string,
	stack_size:      int,
	places_block:    string,
	mined_from:      []string,
	fuel_megajoules: f32,
	cannot_recycle:  bool,
	also_mined_from: []string,
	usable:          bool,
	use:             string,
	detects:         string,
	use_range:       int,
	price:           int,
	tool_tier:       int,
	tool_role:       string,
	configurable:    string,
	former_ids:      []string,
}

Items_File :: struct {
	items: []Item_Definition,
}

// places_block is AIR_BLOCK for items that place nothing. Fuel is kept in
// whole kilojoules so machines burn it with integer arithmetic.
// cannot_recycle keeps the recycler from taking the item (recycler.odin).
// A usable item is read with the Use_Item action (schematics, work item
// 0036) and never places anything. use says what Use_Item does with it;
// a magnetometer finds veins yielding detects within use_range blocks, a
// seismic shot images deep veins within use_range blocks. price is the
// venture credit one item fetches as free trade (work item 0041).
// tool_tier is the highest block tool_tier the tool mines by hand, 0 for
// every item but the tools (work item 0051), at most MAXIMUM_TOOL_TIER.
// tool_role is the field work the tool does (0265), which needs category
// tool and a tool_tier of 1 or more. description_key is the
// string shown under the facts in the recipe browser, "" for none (work
// item 0070). configurable is what the configure pop-up sets (0202).
// former_ids are the ids the item had in an older build, which a save
// may still name (save_remap.odin, work item 0196).
Item :: struct {
	id:              string,
	name_key:        string,
	description_key: string,
	category:        Item_Category,
	stack_size:      u16,
	places_block:    Block_Id,
	fuel_kilojoules: u32,
	cannot_recycle:  bool,
	usable:          bool,
	use:             Item_Use,
	detects:         Item_Id,
	use_range:       i32,
	price:           u64,
	tool_tier:       int,
	tool_role:       Item_Tool_Role,
	configurable:    Item_Configuration,
	former_ids:      []string,
}

Item_Registry :: struct {
	items:          []Item,
	// Indexed by Block_Id: the item mining the block yields, or NO_ITEM.
	drop_for_block: []Item_Id,
	// Indexed by Block_Id: a second item the block yields besides its
	// drop (gold quartz gives quartz and gold ore), or NO_ITEM.
	extra_drop_for_block: []Item_Id,
	// Indexed by Item_Id: the item atlas holds a tile from the item's icon
	// file (render_icons.odin). Empty until the atlas is built, and in
	// tests that build none; it points into the atlas.
	icon_loaded:          []bool,
}

parse_items_file :: proc(data: []byte, allocator := context.allocator) -> (file: Items_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

parse_item_category :: proc(name: string) -> (category: Item_Category, found: bool) {
	for candidate in Item_Category {
		if item_category_names[candidate] == name {
			return candidate, true
		}
	}
	return .Raw, false
}

// Checks the fields that need no block registry.
validate_item_definition :: proc(definitions: []Item_Definition, index: int) -> string {
	definition := definitions[index]
	if definition.id == "" {
		return fmt.tprintf("item %d has no id", index)
	}
	if find_definition_index(definitions, definition.id) != index {
		return fmt.tprintf("item id %q is defined twice", definition.id)
	}
	if definition.name_key == "" {
		return fmt.tprintf("item %q has no name_key", definition.id)
	}
	if _, found := parse_item_category(definition.category); !found {
		return fmt.tprintf("item %q has unknown category %q", definition.id, definition.category)
	}
	if definition.stack_size < 1 || definition.stack_size > MAXIMUM_STACK_SIZE {
		return fmt.tprintf("item %q has stack_size %d outside 1 to %d", definition.id, definition.stack_size, MAXIMUM_STACK_SIZE)
	}
	if definition.fuel_megajoules < 0 {
		return fmt.tprintf("item %q has a negative fuel_megajoules", definition.id)
	}
	if definition.price < 1 {
		return fmt.tprintf("item %q needs a positive price", definition.id)
	}
	if definition.tool_tier < 0 || (definition.tool_tier > 0 && definition.category != item_category_names[.Tool]) {
		return fmt.tprintf("item %q has tool_tier %d, only a tool may have a positive one", definition.id, definition.tool_tier)
	}
	if definition.tool_tier > MAXIMUM_TOOL_TIER {
		return fmt.tprintf("item %q has tool_tier %d outside 0 to %d", definition.id, definition.tool_tier, MAXIMUM_TOOL_TIER)
	}
	if problem := validate_item_tool_role(definition); problem != "" {
		return problem
	}
	if definition.usable && definition.places_block != "" {
		return fmt.tprintf("usable item %q cannot place a block", definition.id)
	}
	if _, found := parse_named_enum(item_configuration_names, definition.configurable); !found {
		return fmt.tprintf("item %q has unknown configurable %q", definition.id, definition.configurable)
	}
	return validate_item_use(definition)
}

// A tool role names a known role, on a tool of tier 1 or more.
validate_item_tool_role :: proc(definition: Item_Definition) -> string {
	role, found := parse_named_enum(item_tool_role_names, definition.tool_role)
	switch {
	case !found:
		return fmt.tprintf("item %q has unknown tool_role %q", definition.id, definition.tool_role)
	case role != .None && definition.category != item_category_names[.Tool]:
		return fmt.tprintf("item %q has tool_role %q but is not a tool", definition.id, definition.tool_role)
	case role != .None && definition.tool_tier < 1:
		return fmt.tprintf("item %q has tool_role %q at tool_tier %d, a role needs 1 or more", definition.id, definition.tool_role, definition.tool_tier)
	}
	return ""
}

// A use needs a usable item; a magnetometer names what it detects and
// both range uses a positive range.
validate_item_use :: proc(definition: Item_Definition) -> string {
	if definition.use == "" {
		return definition.detects == "" && definition.use_range == 0 ? "" : fmt.tprintf("item %q has detects or use_range without a use", definition.id)
	}
	use, found := parse_named_enum(item_use_names, definition.use)
	switch {
	case !found:
		return fmt.tprintf("item %q has unknown use %q", definition.id, definition.use)
	case !definition.usable:
		return fmt.tprintf("item %q has a use but is not usable", definition.id)
	case use == .Magnetometer && definition.detects == "":
		return fmt.tprintf("magnetometer %q needs detects", definition.id)
	case (use == .Magnetometer || use == .Seismic_Shot) && definition.use_range <= 0:
		return fmt.tprintf("item %q needs a positive use_range", definition.id)
	}
	return ""
}

// A placed block must be a real block other than air.
resolve_placed_block :: proc(definition: Item_Definition, blocks: Block_Registry) -> (block: Block_Id, problem: string) {
	if definition.places_block == "" {
		return AIR_BLOCK, ""
	}
	found: bool
	block, found = find_block_id(blocks, definition.places_block)
	if !found || block == AIR_BLOCK {
		return AIR_BLOCK, fmt.tprintf("item %q places unknown block %q", definition.id, definition.places_block)
	}
	return block, ""
}

// Records that mining the block yields the item; each block yields one item.
assign_drop :: proc(drops: []Item_Id, blocks: Block_Registry, block_name: string, item: Item_Id, item_name: string) -> string {
	block, found := find_block_id(blocks, block_name)
	if !found || !block_is_minable(blocks, block) {
		return fmt.tprintf("item %q drops from %q, which is not a block that can be mined", item_name, block_name)
	}
	if drops[block] != NO_ITEM {
		return fmt.tprintf("block %q yields more than one item", block_name)
	}
	drops[block] = item
	return ""
}

resolve_item :: proc(definition: Item_Definition, blocks: Block_Registry) -> (item: Item, problem: string) {
	category, _ := parse_item_category(definition.category)
	use, _ := parse_named_enum(item_use_names, definition.use)
	configurable, _ := parse_named_enum(item_configuration_names, definition.configurable)
	tool_role, _ := parse_named_enum(item_tool_role_names, definition.tool_role)
	placed_block: Block_Id
	if placed_block, problem = resolve_placed_block(definition, blocks); problem != "" {
		return {}, problem
	}
	item = Item {
		id              = definition.id,
		name_key        = definition.name_key,
		description_key = definition.description_key,
		category        = category,
		stack_size      = u16(definition.stack_size),
		places_block    = placed_block,
		fuel_kilojoules = u32(math.round(definition.fuel_megajoules * 1000)),
		cannot_recycle  = definition.cannot_recycle,
		usable          = definition.usable,
		use             = use,
		detects         = NO_ITEM,
		use_range       = i32(definition.use_range),
		price           = u64(definition.price),
		tool_tier       = definition.tool_tier,
		tool_role       = tool_role,
		configurable    = configurable,
		former_ids      = definition.former_ids,
	}
	return item, ""
}

// The item a magnetometer detects must exist.
resolve_item_detects :: proc(definitions: []Item_Definition, registry: Item_Registry) -> string {
	for definition, index in definitions {
		if definition.detects == "" {
			continue
		}
		item, found := find_item_id(registry, definition.detects)
		if !found {
			return fmt.tprintf("item %q detects unknown item %q", definition.id, definition.detects)
		}
		registry.items[index].detects = item
	}
	return ""
}

// A block yields at most one extra item, and only besides a main drop.
assign_extra_drop :: proc(registry: Item_Registry, blocks: Block_Registry, block_name: string, item: Item_Id, item_name: string) -> string {
	block, found := find_block_id(blocks, block_name)
	if !found || registry.drop_for_block[block] == NO_ITEM || registry.drop_for_block[block] == item {
		return fmt.tprintf("item %q is also mined from %q, which yields no other item", item_name, block_name)
	}
	if registry.extra_drop_for_block[block] != NO_ITEM {
		return fmt.tprintf("block %q yields more than one extra item", block_name)
	}
	registry.extra_drop_for_block[block] = item
	return ""
}

resolve_extra_drops :: proc(definitions: []Item_Definition, registry: Item_Registry, blocks: Block_Registry) -> string {
	for definition, index in definitions {
		for block_name in definition.also_mined_from {
			if problem := assign_extra_drop(registry, blocks, block_name, Item_Id(index), definition.id); problem != "" {
				return problem
			}
		}
	}
	return ""
}

resolve_item_drops :: proc(definitions: []Item_Definition, items: []Item, blocks: Block_Registry, drops: []Item_Id) -> string {
	for definition, index in definitions {
		if items[index].places_block != AIR_BLOCK {
			if problem := assign_drop(drops, blocks, definition.places_block, Item_Id(index), definition.id); problem != "" {
				return problem
			}
		}
		for block_name in definition.mined_from {
			if problem := assign_drop(drops, blocks, block_name, Item_Id(index), definition.id); problem != "" {
				return problem
			}
		}
	}
	for drop, block in drops {
		if drop == NO_ITEM && block_is_minable(blocks, Block_Id(block)) {
			return fmt.tprintf("block %q can be mined but yields no item", blocks.definitions[block].id)
		}
	}
	return ""
}

// A discoverable block reads "Unknown ore" until its drop is obtained, so
// it needs one (work item 0052).
validate_discoverable_drops :: proc(drops: []Item_Id, blocks: Block_Registry) -> string {
	for drop, block in drops {
		if drop == NO_ITEM && block_is_discoverable(blocks, Block_Id(block)) {
			return fmt.tprintf("block %q is discoverable but yields no item", blocks.definitions[block].id)
		}
	}
	return ""
}

highest_tool_tier :: proc(items: []Item) -> int {
	highest := 0
	for item in items {
		highest = max(highest, item.tool_tier)
	}
	return highest
}

// Every block that can be mined needs a tool that reaches its tier.
validate_block_tool_tiers :: proc(items: []Item, blocks: Block_Registry) -> string {
	highest := highest_tool_tier(items)
	for definition, block in blocks.definitions {
		if block_is_minable(blocks, Block_Id(block)) && definition.tool_tier > highest {
			return fmt.tprintf("block %q needs tool_tier %d, no tool goes above %d", definition.id, definition.tool_tier, highest)
		}
	}
	return ""
}

// Validates the file against the block registry and resolves every
// reference. Unknown references are errors.
resolve_item_registry :: proc(file: Items_File, blocks: Block_Registry, allocator := context.allocator) -> (registry: Item_Registry, problem: string) {
	if len(file.items) >= int(NO_ITEM) {
		return {}, fmt.tprintf("%d items exceed the limit of %d", len(file.items), int(NO_ITEM) - 1)
	}
	items := make([]Item, len(file.items), allocator)
	drops := make([]Item_Id, len(blocks.definitions), allocator)
	slice.fill(drops, NO_ITEM)
	extra_drops := make([]Item_Id, len(blocks.definitions), allocator)
	slice.fill(extra_drops, NO_ITEM)
	registry = Item_Registry{items = items, drop_for_block = drops, extra_drop_for_block = extra_drops}
	for definition, index in file.items {
		problem = validate_item_definition(file.items, index)
		if problem == "" {
			items[index], problem = resolve_item(definition, blocks)
		}
		if problem != "" {
			destroy_item_registry(registry, allocator)
			return {}, problem
		}
	}
	if problem = resolve_item_drops(file.items, items, blocks, drops); problem != "" {
		destroy_item_registry(registry, allocator)
		return {}, problem
	}
	if problem = resolve_extra_drops(file.items, registry, blocks); problem != "" {
		destroy_item_registry(registry, allocator)
		return {}, problem
	}
	if problem = validate_discoverable_drops(drops, blocks); problem != "" {
		destroy_item_registry(registry, allocator)
		return {}, problem
	}
	if problem = resolve_item_detects(file.items, registry); problem != "" {
		destroy_item_registry(registry, allocator)
		return {}, problem
	}
	if problem = validate_block_tool_tiers(items, blocks); problem != "" {
		destroy_item_registry(registry, allocator)
		return {}, problem
	}
	return registry, ""
}

destroy_item_registry :: proc(registry: Item_Registry, allocator := context.allocator) {
	delete(registry.items, allocator)
	delete(registry.drop_for_block, allocator)
	delete(registry.extra_drop_for_block, allocator)
}

find_item_id :: proc(registry: Item_Registry, id: string) -> (item: Item_Id, found: bool) {
	for candidate, index in registry.items {
		if candidate.id == id {
			return Item_Id(index), true
		}
	}
	return NO_ITEM, false
}

item_stack_size :: proc(registry: Item_Registry, item: Item_Id) -> u16 {
	if int(item) >= len(registry.items) {
		return 0
	}
	return registry.items[item].stack_size
}

// Ids outside the table (NO_ITEM included) place nothing.
item_places_block :: proc(registry: Item_Registry, item: Item_Id) -> Block_Id {
	if int(item) >= len(registry.items) {
		return AIR_BLOCK
	}
	return registry.items[item].places_block
}

block_drop :: proc(registry: Item_Registry, block: Block_Id) -> Item_Id {
	if int(block) >= len(registry.drop_for_block) {
		return NO_ITEM
	}
	return registry.drop_for_block[block]
}

block_extra_drop :: proc(registry: Item_Registry, block: Block_Id) -> Item_Id {
	if int(block) >= len(registry.extra_drop_for_block) {
		return NO_ITEM
	}
	return registry.extra_drop_for_block[block]
}

item_is_usable :: proc(registry: Item_Registry, item: Item_Id) -> bool {
	return int(item) < len(registry.items) && registry.items[item].usable
}

// False for an item that is not usable.
item_has_use :: proc(registry: Item_Registry, item: Item_Id, use: Item_Use) -> bool {
	return item_is_usable(registry, item) && registry.items[item].use == use
}

Item_Sort_Context :: struct {
	items: []Item,
	names: []string,
}

// Category, then display name, then id order, so equal names still sort
// the same way every time.
item_sorts_before :: proc(first, second: int, data: rawptr) -> bool {
	sort_context := (^Item_Sort_Context)(data)
	first_item, second_item := sort_context.items[first], sort_context.items[second]
	if first_item.category != second_item.category {
		return first_item.category < second_item.category
	}
	if sort_context.names[first] != sort_context.names[second] {
		return sort_context.names[first] < sort_context.names[second]
	}
	return first < second
}

// Sort position of every item. The display names come from the string
// table, so the ranks are computed once after it is loaded.
item_sort_ranks :: proc(registry: Item_Registry, names: []string, allocator := context.allocator) -> []u16 {
	order := make([]int, len(registry.items), context.temp_allocator)
	for &position, index in order {
		position = index
	}
	sort_context := Item_Sort_Context{registry.items, names}
	slice.sort_by_with_data(order, item_sorts_before, &sort_context)
	ranks := make([]u16, len(registry.items), allocator)
	for item, rank in order {
		ranks[item] = u16(rank)
	}
	return ranks
}

item_display_names :: proc(registry: Item_Registry, allocator := context.allocator) -> []string {
	names := make([]string, len(registry.items), allocator)
	for item, index in registry.items {
		names[index] = text(item.name_key)
	}
	return names
}

load_item_registry :: proc(data_directory: string, blocks: Block_Registry, allocator := context.allocator) -> (registry: Item_Registry, ok: bool) {
	data, path := read_logged_data_file(data_directory, ITEMS_FILE_NAME) or_return
	file, parse_error := parse_items_file(data, allocator)
	if parse_error != nil {
		platform.log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	registry, problem = resolve_item_registry(file, blocks, allocator)
	if problem != "" {
		platform.log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}

// Item icons from doc/ui.md: the item atlas tile from the item's icon
// file, else the placed block's atlas tile, else a coloured square with
// two letters. A pure description; ui_draw.odin draws it.
Item_Icon_Kind :: enum u8 {
	// tile is the block atlas tile.
	Block_Tile,
	Lettered,
	// tile is the item atlas tile, the Item_Id.
	Item_Tile,
}

Item_Icon :: struct {
	kind:    Item_Icon_Kind,
	tile:    int,
	color:   Ui_Color,
	letters: [2]u8,
}

@(rodata)
item_category_colors := [Item_Category]Ui_Color {
	.Raw          = {128, 96, 64, 255},
	.Intermediate = {70, 104, 150, 255},
	.Tool         = {176, 110, 40, 255},
	.Machine      = {64, 128, 84, 255},
	.Block        = {110, 110, 110, 255},
}

to_upper_ascii :: proc(character: u8) -> u8 {
	return character >= 'a' && character <= 'z' ? character - 32 : character
}

// The first letters of the first two words of the id, or the first two
// letters of a one word id: iron_plate gives IP, coal gives CO.
item_letters :: proc(id: string) -> [2]u8 {
	letters: [2]u8 = ' '
	if len(id) == 0 {
		return letters
	}
	letters[0] = to_upper_ascii(id[0])
	for character, index in transmute([]u8)id {
		if character == '_' && index + 1 < len(id) {
			letters[1] = to_upper_ascii(id[index + 1])
			return letters
		}
	}
	if len(id) > 1 {
		letters[1] = to_upper_ascii(id[1])
	}
	return letters
}

item_icon :: proc(registry: Item_Registry, item: Item_Id) -> Item_Icon {
	if int(item) >= len(registry.items) {
		return Item_Icon{kind = .Lettered, color = UI_WIDGET_COLOR, letters = '?'}
	}
	if int(item) < len(registry.icon_loaded) && registry.icon_loaded[item] {
		return Item_Icon{kind = .Item_Tile, tile = int(item)}
	}
	definition := registry.items[item]
	if definition.places_block != AIR_BLOCK {
		return Item_Icon{kind = .Block_Tile, tile = atlas_tile_index(definition.places_block, .Side)}
	}
	return Item_Icon{kind = .Lettered, color = item_category_colors[definition.category], letters = item_letters(definition.id)}
}

// A description key is optional, and one that is set must be in the
// string table (work item 0070). The loaders know no strings, so the
// content load checks every table with these after they are resolved.
description_key_problem :: proc(strings: map[string]string, owner, id, key: string) -> string {
	if key != "" && key not_in strings {
		return fmt.tprintf("%s %q: description_key %q is not in the string table", owner, id, key)
	}
	return ""
}

validate_item_description_keys :: proc(registry: Item_Registry, strings: map[string]string) -> string {
	for item in registry.items {
		if problem := description_key_problem(strings, "item", item.id, item.description_key); problem != "" {
			return problem
		}
	}
	return ""
}

// The item's description, "" for none.
item_description :: proc(registry: Item_Registry, item: Item_Id) -> string {
	if int(item) >= len(registry.items) || registry.items[item].description_key == "" {
		return ""
	}
	return text(registry.items[item].description_key)
}

item_category_key :: proc(category: Item_Category) -> string {
	return fmt.tprintf("item_category_%s", item_category_names[category])
}

item_name :: proc(registry: Item_Registry, item: Item_Id) -> string {
	if int(item) >= len(registry.items) {
		return ""
	}
	return text(registry.items[item].name_key)
}

// The tool with the lowest tool_tier that reaches tier, or NO_ITEM.
tool_item_for_tier :: proc(registry: Item_Registry, tier: int) -> Item_Id {
	best := NO_ITEM
	for item, index in registry.items {
		if item.tool_tier >= tier && (best == NO_ITEM || item.tool_tier < registry.items[best].tool_tier) {
			best = Item_Id(index)
		}
	}
	return best
}

// The venture credit one item fetches, 0 outside the table.
item_price :: proc(registry: Item_Registry, item: Item_Id) -> u64 {
	if int(item) >= len(registry.items) {
		return 0
	}
	return registry.items[item].price
}
