package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"

// Recipes from data/recipes.sjson, resolved to dense indices after the
// items. Technologies (technology.odin) are resolved after the recipes and
// fill in each research recipe's technology index.

RECIPES_FILE_NAME :: "recipes.sjson"
NO_RECIPE :: -1
NO_TECHNOLOGY :: -1
MAXIMUM_RECIPE_TAGS :: 128

// What can make a recipe. Every maker after the furnace is a crafting
// machine category (assembler.odin): a machine entry names the one it
// makes.
Recipe_Maker :: enum u8 {
	Hand,
	Furnace,
	Assembler,
	Crusher,
	Washer,
	Alloy_Furnace,
}

Recipe_Makers :: bit_set[Recipe_Maker]

@(rodata)
recipe_maker_names := [Recipe_Maker]string {
	.Hand          = "hand",
	.Furnace       = "furnace",
	.Assembler     = "assembler",
	.Crusher       = "crusher",
	.Washer        = "washer",
	.Alloy_Furnace = "alloy_furnace",
}

// The recipe browser tabs, in tab order.
Recipe_Category :: enum u8 {
	Materials,
	Components,
	Tools,
	Machines,
	Logistics,
	Power,
	Science,
}

@(rodata)
recipe_category_names := [Recipe_Category]string {
	.Materials  = "materials",
	.Components = "components",
	.Tools      = "tools",
	.Machines   = "machines",
	.Logistics  = "logistics",
	.Power      = "power",
	.Science    = "science",
}

// The three progression channels of DESIGN.md, plus the main quest gates.
Recipe_Channel :: enum u8 {
	Start,
	Discovery,
	Research,
	Quest,
}

@(rodata)
recipe_channel_names := [Recipe_Channel]string {
	.Start     = "start",
	.Discovery = "discovery",
	.Research  = "research",
	.Quest     = "quest",
}

// Indices into Recipe_Registry.tag_names.
Recipe_Tag_Set :: bit_set[0 ..< MAXIMUM_RECIPE_TAGS;u128]

// fluid is not allowed here: fluids go in fluid_inputs.
Recipe_Ingredient_Definition :: struct {
	item:  string,
	fluid: string,
	count: int,
}

// litres over the whole craft, drawn from the machine's input ports.
Recipe_Fluid_Definition :: struct {
	fluid:  string,
	litres: int,
}

Recipe_Fluid :: struct {
	fluid:  Fluid_Id,
	litres: i32,
}

// As written in the file, before references are resolved.
Recipe_Definition :: struct {
	id:         string,
	name_key:   string,
	inputs:     []Recipe_Ingredient_Definition,
	outputs:      []Recipe_Ingredient_Definition,
	fluid_inputs: []Recipe_Fluid_Definition,
	seconds:      f32,
	made_in:    []string,
	category:   string,
	tags:       []string,
	channel:    string,
	technology: string,
}

Recipes_File :: struct {
	recipes: []Recipe_Definition,
}

// name_key is the first output's name key when the file gives none. Time
// is kept in milliseconds so machines count ticks in integers.
// technology_id is the file's reference, technology its index once the
// technologies are resolved (NO_TECHNOLOGY otherwise).
Recipe :: struct {
	id:            string,
	name_key:      string,
	inputs:        []Item_Stack,
	outputs:       []Item_Stack,
	fluid_inputs:  []Recipe_Fluid,
	milliseconds:  u32,
	made_in:       Recipe_Makers,
	category:      Recipe_Category,
	tags:          Recipe_Tag_Set,
	channel:       Recipe_Channel,
	technology_id: string,
	technology:    int,
}

Recipe_Registry :: struct {
	recipes:   []Recipe,
	tag_names: []string,
}

parse_recipes_file :: proc(data: []byte, allocator := context.allocator) -> (file: Recipes_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

parse_named_enum :: proc(names: [$E]string, name: string) -> (value: E, found: bool) {
	for candidate in E {
		if names[candidate] == name {
			return candidate, true
		}
	}
	return {}, false
}

find_recipe_definition_index :: proc(definitions: []Recipe_Definition, id: string) -> int {
	for definition, index in definitions {
		if definition.id == id {
			return index
		}
	}
	return -1
}

validate_recipe_makers :: proc(definition: Recipe_Definition) -> string {
	if len(definition.made_in) == 0 {
		return fmt.tprintf("recipe %q has no made_in", definition.id)
	}
	for name in definition.made_in {
		if _, found := parse_named_enum(recipe_maker_names, name); !found {
			return fmt.tprintf("recipe %q is made in unknown %q", definition.id, name)
		}
	}
	return ""
}

validate_recipe_channel :: proc(definition: Recipe_Definition) -> string {
	channel, found := parse_named_enum(recipe_channel_names, definition.channel)
	if !found {
		return fmt.tprintf("recipe %q has unknown channel %q", definition.id, definition.channel)
	}
	if channel == .Research && definition.technology == "" {
		return fmt.tprintf("research recipe %q names no technology", definition.id)
	}
	if channel != .Research && definition.technology != "" {
		return fmt.tprintf("recipe %q names a technology but its channel is %q", definition.id, definition.channel)
	}
	return ""
}

// Checks the fields that need no item registry.
validate_recipe_definition :: proc(definitions: []Recipe_Definition, index: int) -> string {
	definition := definitions[index]
	switch {
	case definition.id == "":
		return fmt.tprintf("recipe %d has no id", index)
	case find_recipe_definition_index(definitions, definition.id) != index:
		return fmt.tprintf("recipe id %q is defined twice", definition.id)
	case len(definition.inputs) == 0:
		return fmt.tprintf("recipe %q has no inputs", definition.id)
	case len(definition.outputs) == 0:
		return fmt.tprintf("recipe %q has no outputs", definition.id)
	case definition.seconds <= 0:
		return fmt.tprintf("recipe %q needs positive seconds", definition.id)
	}
	if _, found := parse_named_enum(recipe_category_names, definition.category); !found {
		return fmt.tprintf("recipe %q has unknown category %q", definition.id, definition.category)
	}
	if problem := validate_recipe_makers(definition); problem != "" {
		return problem
	}
	return validate_recipe_channel(definition)
}

resolve_ingredient :: proc(recipe_id: string, ingredient: Recipe_Ingredient_Definition, items: Item_Registry) -> (stack: Item_Stack, problem: string) {
	if ingredient.fluid != "" {
		return EMPTY_STACK, fmt.tprintf("recipe %q lists fluid %q as an item, fluids go in fluid_inputs", recipe_id, ingredient.fluid)
	}
	item, found := find_item_id(items, ingredient.item)
	if !found {
		return EMPTY_STACK, fmt.tprintf("recipe %q names unknown item %q", recipe_id, ingredient.item)
	}
	if ingredient.count < 1 || ingredient.count > MAXIMUM_STACK_SIZE {
		return EMPTY_STACK, fmt.tprintf("recipe %q has count %d of %q outside 1 to %d", recipe_id, ingredient.count, ingredient.item, MAXIMUM_STACK_SIZE)
	}
	return Item_Stack{item = item, count = u16(ingredient.count)}, ""
}

// One stack per item: a list naming an item twice is an error.
resolve_ingredients :: proc(recipe_id: string, ingredients: []Recipe_Ingredient_Definition, items: Item_Registry, allocator := context.allocator) -> (stacks: []Item_Stack, problem: string) {
	stacks = make([]Item_Stack, len(ingredients), allocator)
	for ingredient, index in ingredients {
		stacks[index], problem = resolve_ingredient(recipe_id, ingredient, items)
		if problem == "" && stacks_contain_item(stacks[:index], stacks[index].item) {
			problem = fmt.tprintf("recipe %q lists %q twice", recipe_id, ingredient.item)
		}
		if problem != "" {
			delete(stacks, allocator)
			return nil, problem
		}
	}
	return stacks, ""
}

stacks_contain_item :: proc(stacks: []Item_Stack, item: Item_Id) -> bool {
	for stack in stacks {
		if stack.item == item {
			return true
		}
	}
	return false
}

// Returns the tag's index, adding it to the names when it is new.
intern_tag :: proc(tag_names: ^[dynamic]string, tag: string) -> (index: int, problem: string) {
	if found, ok := slice.linear_search(tag_names[:], tag); ok {
		return found, ""
	}
	if tag == "" {
		return -1, "a recipe has an empty tag"
	}
	if len(tag_names) == MAXIMUM_RECIPE_TAGS {
		return -1, fmt.tprintf("more than %d distinct recipe tags", MAXIMUM_RECIPE_TAGS)
	}
	append(tag_names, tag)
	return len(tag_names) - 1, ""
}

resolve_recipe_tags :: proc(tags: []string, tag_names: ^[dynamic]string) -> (set: Recipe_Tag_Set, problem: string) {
	for tag in tags {
		index: int
		if index, problem = intern_tag(tag_names, tag); problem != "" {
			return {}, problem
		}
		set += {index}
	}
	return set, ""
}

resolve_recipe_makers :: proc(names: []string) -> Recipe_Makers {
	makers: Recipe_Makers
	for name in names {
		maker, _ := parse_named_enum(recipe_maker_names, name)
		makers += {maker}
	}
	return makers
}

// Fluids come from a machine's ports, so neither the hand nor the stone
// furnace, which has none, makes a recipe with fluid inputs.
resolve_recipe_fluids :: proc(definition: Recipe_Definition, fluids: Fluid_Registry, allocator := context.allocator) -> (resolved: []Recipe_Fluid, problem: string) {
	if len(definition.fluid_inputs) == 0 {
		return nil, ""
	}
	makers := resolve_recipe_makers(definition.made_in)
	if .Hand in makers || .Furnace in makers {
		return nil, fmt.tprintf("recipe %q has fluid inputs but is made by hand or in a furnace", definition.id)
	}
	if len(definition.fluid_inputs) > MAXIMUM_FLUID_PORTS {
		return nil, fmt.tprintf("recipe %q has more than %d fluid inputs", definition.id, MAXIMUM_FLUID_PORTS)
	}
	resolved = make([]Recipe_Fluid, len(definition.fluid_inputs), allocator)
	for fluid_input, index in definition.fluid_inputs {
		fluid, found := find_fluid_id(fluids, fluid_input.fluid)
		if !found || fluid_input.litres < 1 {
			delete(resolved, allocator)
			return nil, fmt.tprintf("recipe %q has fluid input %q that is unknown or not a positive amount", definition.id, fluid_input.fluid)
		}
		resolved[index] = {fluid = fluid, litres = i32(fluid_input.litres)}
	}
	return resolved, ""
}

resolve_recipe :: proc(definition: Recipe_Definition, items: Item_Registry, fluids: Fluid_Registry, tag_names: ^[dynamic]string, allocator := context.allocator) -> (recipe: Recipe, problem: string) {
	recipe = Recipe {
		id            = definition.id,
		name_key      = definition.name_key,
		milliseconds  = u32(math.round(definition.seconds * 1000)),
		made_in       = resolve_recipe_makers(definition.made_in),
		technology_id = definition.technology,
		technology    = NO_TECHNOLOGY,
	}
	recipe.category, _ = parse_named_enum(recipe_category_names, definition.category)
	recipe.channel, _ = parse_named_enum(recipe_channel_names, definition.channel)
	if recipe.tags, problem = resolve_recipe_tags(definition.tags, tag_names); problem != "" {
		return {}, problem
	}
	if recipe.inputs, problem = resolve_ingredients(definition.id, definition.inputs, items, allocator); problem != "" {
		return {}, problem
	}
	if recipe.outputs, problem = resolve_ingredients(definition.id, definition.outputs, items, allocator); problem != "" {
		delete(recipe.inputs, allocator)
		return {}, problem
	}
	if recipe.fluid_inputs, problem = resolve_recipe_fluids(definition, fluids, allocator); problem != "" {
		delete(recipe.inputs, allocator)
		delete(recipe.outputs, allocator)
		return {}, problem
	}
	if recipe.name_key == "" {
		recipe.name_key = items.items[recipe.outputs[0].item].name_key
	}
	return recipe, ""
}

// The furnace has one input and one output slot, so it makes only recipes
// of that shape.
recipe_fits_furnace :: proc(recipe: Recipe) -> bool {
	return .Furnace in recipe.made_in && len(recipe.inputs) == 1 && len(recipe.outputs) == 1
}

// A furnace picks its recipe by the input item, which must be unambiguous.
// A furnace recipe of another shape is an error: two input alloys belong
// to the alloy furnace.
validate_furnace_recipes :: proc(recipes: []Recipe) -> string {
	for recipe, index in recipes {
		if .Furnace in recipe.made_in && !recipe_fits_furnace(recipe) {
			return fmt.tprintf("furnace recipe %q needs exactly one input and one output", recipe.id)
		}
		if !recipe_fits_furnace(recipe) {
			continue
		}
		for other in recipes[index + 1:] {
			if recipe_fits_furnace(other) && other.inputs[0].item == recipe.inputs[0].item {
				return fmt.tprintf("furnace recipes %q and %q share their input", recipe.id, other.id)
			}
		}
	}
	return ""
}

// Validates the file against the item registry and resolves every item
// reference. Technology references are resolved by
// resolve_technology_registry.
resolve_recipe_registry :: proc(file: Recipes_File, items: Item_Registry, fluids: Fluid_Registry, allocator := context.allocator) -> (registry: Recipe_Registry, problem: string) {
	registry.recipes = make([]Recipe, len(file.recipes), allocator)
	tag_names := make([dynamic]string, 0, 16, allocator)
	for definition, index in file.recipes {
		problem = validate_recipe_definition(file.recipes, index)
		if problem == "" {
			registry.recipes[index], problem = resolve_recipe(definition, items, fluids, &tag_names, allocator)
		}
		if problem != "" {
			registry.tag_names = tag_names[:]
			destroy_recipe_registry(registry, allocator)
			return {}, problem
		}
	}
	registry.tag_names = tag_names[:]
	if problem = validate_furnace_recipes(registry.recipes); problem != "" {
		destroy_recipe_registry(registry, allocator)
		return {}, problem
	}
	if problem = validate_assembler_recipes(registry.recipes); problem != "" {
		destroy_recipe_registry(registry, allocator)
		return {}, problem
	}
	return registry, ""
}

// Tag names are strings owned by the parsed file, so only the list goes.
destroy_recipe_registry :: proc(registry: Recipe_Registry, allocator := context.allocator) {
	for recipe in registry.recipes {
		delete(recipe.inputs, allocator)
		delete(recipe.outputs, allocator)
		delete(recipe.fluid_inputs, allocator)
	}
	delete(registry.recipes, allocator)
	delete(registry.tag_names, allocator)
}

find_recipe :: proc(registry: Recipe_Registry, id: string) -> int {
	for recipe, index in registry.recipes {
		if recipe.id == id {
			return index
		}
	}
	return NO_RECIPE
}

// Ticks of the recipe at a speed in percent, at least one.
recipe_ticks :: proc(recipe: Recipe, speed_percent: u32, tick_rate: int) -> u32 {
	ticks := u64(recipe.milliseconds) * u64(tick_rate) * 100 / (1000 * u64(max(speed_percent, 1)))
	return max(u32(ticks), 1)
}

// The furnace recipe for an input item, or NO_RECIPE.
furnace_recipe_for :: proc(registry: Recipe_Registry, item: Item_Id) -> int {
	for recipe, index in registry.recipes {
		if recipe_fits_furnace(recipe) && recipe.inputs[0].item == item {
			return index
		}
	}
	return NO_RECIPE
}

item_is_smeltable :: proc(registry: Recipe_Registry, item: Item_Id) -> bool {
	return furnace_recipe_for(registry, item) != NO_RECIPE
}

// The graph queries of the recipe browser, in recipe order.

recipes_making :: proc(registry: Recipe_Registry, item: Item_Id, allocator := context.allocator) -> []int {
	found := make([dynamic]int, allocator)
	for recipe, index in registry.recipes {
		if stacks_contain_item(recipe.outputs, item) {
			append(&found, index)
		}
	}
	return found[:]
}

recipes_using :: proc(registry: Recipe_Registry, item: Item_Id, allocator := context.allocator) -> []int {
	found := make([dynamic]int, allocator)
	for recipe, index in registry.recipes {
		if stacks_contain_item(recipe.inputs, item) {
			append(&found, index)
		}
	}
	return found[:]
}

recipe_name :: proc(registry: Recipe_Registry, recipe: int) -> string {
	if recipe < 0 || recipe >= len(registry.recipes) {
		return ""
	}
	return text(registry.recipes[recipe].name_key)
}

recipe_display_names :: proc(registry: Recipe_Registry, allocator := context.allocator) -> []string {
	names := make([]string, len(registry.recipes), allocator)
	for _, index in registry.recipes {
		names[index] = recipe_name(registry, index)
	}
	return names
}

Recipe_Name_Sort_Context :: struct {
	names: []string,
}

recipe_sorts_before :: proc(first, second: int, data: rawptr) -> bool {
	names := (^Recipe_Name_Sort_Context)(data).names
	if names[first] != names[second] {
		return names[first] < names[second]
	}
	return first < second
}

// Recipe indices ordered by display name, then by index.
recipe_name_order :: proc(names: []string, allocator := context.allocator) -> []int {
	order := make([]int, len(names), allocator)
	for &position, index in order {
		position = index
	}
	sort_context := Recipe_Name_Sort_Context{names}
	slice.sort_by_with_data(order, recipe_sorts_before, &sort_context)
	return order
}

recipe_tag_key :: proc(tag: string) -> string {
	return fmt.tprintf("recipe_tag_%s", tag)
}

recipe_category_key :: proc(category: Recipe_Category) -> string {
	return fmt.tprintf("recipe_category_%s", recipe_category_names[category])
}

recipe_maker_key :: proc(maker: Recipe_Maker) -> string {
	return fmt.tprintf("recipe_maker_%s", recipe_maker_names[maker])
}

load_recipe_registry :: proc(data_directory: string, items: Item_Registry, fluids: Fluid_Registry, allocator := context.allocator) -> (registry: Recipe_Registry, ok: bool) {
	path, join_error := os.join_path({data_directory, RECIPES_FILE_NAME}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		log_printf("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	file, parse_error := parse_recipes_file(data, allocator)
	if parse_error != nil {
		log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	registry, problem = resolve_recipe_registry(file, items, fluids, allocator)
	if problem != "" {
		log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}
