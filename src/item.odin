package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"

// Item prototypes from data/items.sjson, resolved to a dense Item_Id at
// startup like the blocks. The inventory, mining drops and placing all go
// through this one table.

ITEMS_FILE_NAME :: "items.sjson"
MAXIMUM_STACK_SIZE :: 1000

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

// As written in the file, before references are resolved.
Item_Definition :: struct {
	id:              string,
	name_key:        string,
	category:        string,
	stack_size:      int,
	places_block:    string,
	mined_from:      []string,
	fuel_megajoules: f32,
}

Items_File :: struct {
	items: []Item_Definition,
}

// places_block is AIR_BLOCK for items that place nothing. Fuel is kept in
// whole kilojoules so machines burn it with integer arithmetic.
Item :: struct {
	id:              string,
	name_key:        string,
	category:        Item_Category,
	stack_size:      u16,
	places_block:    Block_Id,
	fuel_kilojoules: u32,
}

Item_Registry :: struct {
	items:          []Item,
	// Indexed by Block_Id: the item mining the block yields, or NO_ITEM.
	drop_for_block: []Item_Id,
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

find_item_definition_index :: proc(definitions: []Item_Definition, id: string) -> int {
	for definition, index in definitions {
		if definition.id == id {
			return index
		}
	}
	return -1
}

// Checks the fields that need no block registry.
validate_item_definition :: proc(definitions: []Item_Definition, index: int) -> string {
	definition := definitions[index]
	if definition.id == "" {
		return fmt.tprintf("item %d has no id", index)
	}
	if find_item_definition_index(definitions, definition.id) != index {
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
	placed_block: Block_Id
	if placed_block, problem = resolve_placed_block(definition, blocks); problem != "" {
		return {}, problem
	}
	item = Item {
		id              = definition.id,
		name_key        = definition.name_key,
		category        = category,
		stack_size      = u16(definition.stack_size),
		places_block    = placed_block,
		fuel_kilojoules = u32(math.round(definition.fuel_megajoules * 1000)),
	}
	return item, ""
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

// Validates the file against the block registry and resolves every
// reference. Unknown references are errors.
resolve_item_registry :: proc(file: Items_File, blocks: Block_Registry, allocator := context.allocator) -> (registry: Item_Registry, problem: string) {
	if len(file.items) >= int(NO_ITEM) {
		return {}, fmt.tprintf("%d items exceed the limit of %d", len(file.items), int(NO_ITEM) - 1)
	}
	items := make([]Item, len(file.items), allocator)
	drops := make([]Item_Id, len(blocks.definitions), allocator)
	slice.fill(drops, NO_ITEM)
	registry = Item_Registry{items = items, drop_for_block = drops}
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
	return registry, ""
}

destroy_item_registry :: proc(registry: Item_Registry, allocator := context.allocator) {
	delete(registry.items, allocator)
	delete(registry.drop_for_block, allocator)
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
	path, join_error := os.join_path({data_directory, ITEMS_FILE_NAME}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	file, parse_error := parse_items_file(data, allocator)
	if parse_error != nil {
		fmt.eprintfln("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	registry, problem = resolve_item_registry(file, blocks, allocator)
	if problem != "" {
		fmt.eprintfln("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}

// Placeholder icons from doc/ui.md: the placed block's atlas tile, or a
// coloured square with two letters. A pure description; ui_draw.odin draws it.
Item_Icon_Kind :: enum u8 {
	Block_Tile,
	Lettered,
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
	definition := registry.items[item]
	if definition.places_block != AIR_BLOCK {
		return Item_Icon{kind = .Block_Tile, tile = atlas_tile_index(definition.places_block, .Side)}
	}
	return Item_Icon{kind = .Lettered, color = item_category_colors[definition.category], letters = item_letters(definition.id)}
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
