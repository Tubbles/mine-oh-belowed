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
MAXIMUM_RECIPE_OUTPUTS :: 16

// What can make a recipe. Every maker after the furnace is a crafting
// machine category (assembler.odin): a machine entry names the one it
// makes. No recipe is made in the recycler, which reverses recipes
// (recycler.odin).
Recipe_Maker :: enum u8 {
	Hand,
	Furnace,
	Assembler,
	Crusher,
	Washer,
	Alloy_Furnace,
	Refinery,
	Cracking,
	Chemistry,
	Gasifier,
	Electrolysis,
	Recycler,
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
	.Refinery      = "refinery",
	.Cracking      = "cracking",
	.Chemistry     = "chemistry",
	.Gasifier      = "gasifier",
	.Electrolysis  = "electrolysis",
	.Recycler      = "recycler",
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

// The three progression channels of DESIGN.md, plus the main quest gates
// and the alternate recipes of cave schematics (work item 0036).
Recipe_Channel :: enum u8 {
	Start,
	Discovery,
	Research,
	Quest,
	Schematic,
}

@(rodata)
recipe_channel_names := [Recipe_Channel]string {
	.Start     = "start",
	.Discovery = "discovery",
	.Research  = "research",
	.Quest     = "quest",
	.Schematic = "schematic",
}

// Indices into Recipe_Registry.tag_names.
Recipe_Tag_Set :: bit_set[0 ..< MAXIMUM_RECIPE_TAGS;u128]

// Indices into Recipe.outputs.
Recipe_Output_Set :: bit_set[0 ..< MAXIMUM_RECIPE_OUTPUTS;u16]

// fluid is not allowed here: fluids go in fluid_inputs. byproduct only
// on outputs.
Recipe_Ingredient_Definition :: struct {
	item:      string,
	fluid:     string,
	count:     int,
	byproduct: bool,
}

// litres over the whole craft: fluid inputs are taken from the machine's
// input ports when the craft starts (all of them present, work item 0031),
// fluid outputs delivered into its output ports when it completes. byproduct only on fluid outputs.
Recipe_Fluid_Definition :: struct {
	fluid:     string,
	litres:    int,
	byproduct: bool,
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
	fluid_outputs: []Recipe_Fluid_Definition,
	seconds:      f32,
	made_in:    []string,
	category:   string,
	tags:       []string,
	channel:    string,
	technology: string,
	schematic:  string,
}

Recipes_File :: struct {
	recipes: []Recipe_Definition,
}

// name_key is the first output's name key when the file gives none. Time
// is kept in milliseconds so machines count ticks in integers.
// technology_id is the file's reference, technology its index once the
// technologies are resolved (NO_TECHNOLOGY otherwise). byproducts marks
// the outputs a lenient world voids when they do not fit, fluid_byproducts
// the fluid outputs. schematic is the usable item that unlocks a schematic
// channel recipe, NO_ITEM for every other channel.
Recipe :: struct {
	id:            string,
	name_key:      string,
	inputs:        []Item_Stack,
	outputs:       []Item_Stack,
	byproducts:    Recipe_Output_Set,
	fluid_inputs:  []Recipe_Fluid,
	fluid_outputs: []Recipe_Fluid,
	fluid_byproducts: Recipe_Output_Set,
	milliseconds:  u32,
	made_in:       Recipe_Makers,
	category:      Recipe_Category,
	tags:          Recipe_Tag_Set,
	channel:       Recipe_Channel,
	technology_id: string,
	technology:    int,
	schematic:     Item_Id,
}

Recipe_Registry :: struct {
	recipes:         []Recipe,
	tag_names:       []string,
	// Indexed by Item_Id: the recipe the recycler reverses for the item,
	// or NO_RECIPE (recycler.odin).
	recycle_recipes: []int,
	// Not a table: the session's Recipe_Unlocks.schematics_found, set on
	// the copy of the registry the simulation and the screens get
	// (with_schematics_found). Every machine path already receives the
	// registry, so this is how they skip schematic alternates not found
	// yet (recipe_runs_in_machines). Nil finds none.
	schematics_found: []bool,
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
		maker, found := parse_named_enum(recipe_maker_names, name)
		if !found || maker == .Recycler {
			return fmt.tprintf("recipe %q is made in unknown %q", definition.id, name)
		}
	}
	return ""
}

// Byproduct flags only on outputs, and at least one main output, an item
// or a fluid.
validate_recipe_byproducts :: proc(definition: Recipe_Definition) -> string {
	for input in definition.inputs {
		if input.byproduct {
			return fmt.tprintf("recipe %q flags an input as a byproduct", definition.id)
		}
	}
	for input in definition.fluid_inputs {
		if input.byproduct {
			return fmt.tprintf("recipe %q flags a fluid input as a byproduct", definition.id)
		}
	}
	for output in definition.outputs {
		if !output.byproduct {
			return ""
		}
	}
	for output in definition.fluid_outputs {
		if !output.byproduct {
			return ""
		}
	}
	return fmt.tprintf("recipe %q has only byproduct outputs", definition.id)
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
	if (channel == .Schematic) != (definition.schematic != "") {
		return fmt.tprintf("recipe %q needs a schematic exactly when its channel is schematic", definition.id)
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
	case len(definition.inputs) == 0 && len(definition.fluid_inputs) == 0:
		return fmt.tprintf("recipe %q has no inputs", definition.id)
	case len(definition.outputs) + len(definition.fluid_outputs) == 0 || len(definition.outputs) > MAXIMUM_RECIPE_OUTPUTS:
		return fmt.tprintf("recipe %q needs 1 to %d outputs", definition.id, MAXIMUM_RECIPE_OUTPUTS)
	case len(definition.outputs) == 0 && definition.name_key == "":
		return fmt.tprintf("recipe %q has no item output to be named after and needs a name_key", definition.id)
	case definition.seconds <= 0:
		return fmt.tprintf("recipe %q needs positive seconds", definition.id)
	}
	if _, found := parse_named_enum(recipe_category_names, definition.category); !found {
		return fmt.tprintf("recipe %q has unknown category %q", definition.id, definition.category)
	}
	if problem := validate_recipe_makers(definition); problem != "" {
		return problem
	}
	if problem := validate_recipe_byproducts(definition); problem != "" {
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

resolve_recipe_byproducts :: proc(outputs: []Recipe_Ingredient_Definition) -> Recipe_Output_Set {
	byproducts: Recipe_Output_Set
	for output, index in outputs {
		if output.byproduct {
			byproducts += {index}
		}
	}
	return byproducts
}

resolve_recipe_makers :: proc(names: []string) -> Recipe_Makers {
	makers: Recipe_Makers
	for name in names {
		maker, _ := parse_named_enum(recipe_maker_names, name)
		makers += {maker}
	}
	return makers
}

// Fluids come from and go to a machine's ports, so neither the hand nor
// the stone furnace, which has none, makes a recipe with fluids. A fluid
// appears once per list.
resolve_recipe_fluids :: proc(definition: Recipe_Definition, list: []Recipe_Fluid_Definition, fluids: Fluid_Registry, allocator := context.allocator) -> (resolved: []Recipe_Fluid, problem: string) {
	if len(list) == 0 {
		return nil, ""
	}
	makers := resolve_recipe_makers(definition.made_in)
	if .Hand in makers || .Furnace in makers {
		return nil, fmt.tprintf("recipe %q has fluids but is made by hand or in a furnace", definition.id)
	}
	if len(list) > MAXIMUM_FLUID_PORTS {
		return nil, fmt.tprintf("recipe %q has more than %d fluid inputs or outputs", definition.id, MAXIMUM_FLUID_PORTS)
	}
	resolved = make([]Recipe_Fluid, len(list), allocator)
	for entry, index in list {
		fluid, found := find_fluid_id(fluids, entry.fluid)
		if !found || entry.litres < 1 || recipe_fluids_contain(resolved[:index], fluid) {
			delete(resolved, allocator)
			return nil, fmt.tprintf("recipe %q has fluid %q that is unknown, listed twice or not a positive amount", definition.id, entry.fluid)
		}
		resolved[index] = {fluid = fluid, litres = i32(entry.litres)}
	}
	return resolved, ""
}

recipe_fluids_contain :: proc(list: []Recipe_Fluid, fluid: Fluid_Id) -> bool {
	for entry in list {
		if entry.fluid == fluid {
			return true
		}
	}
	return false
}

resolve_fluid_byproducts :: proc(outputs: []Recipe_Fluid_Definition) -> Recipe_Output_Set {
	byproducts: Recipe_Output_Set
	for output, index in outputs {
		if output.byproduct {
			byproducts += {index}
		}
	}
	return byproducts
}

resolve_recipe :: proc(definition: Recipe_Definition, items: Item_Registry, fluids: Fluid_Registry, tag_names: ^[dynamic]string, allocator := context.allocator) -> (recipe: Recipe, problem: string) {
	recipe = Recipe {
		id            = definition.id,
		name_key      = definition.name_key,
		milliseconds  = u32(math.round(definition.seconds * 1000)),
		made_in       = resolve_recipe_makers(definition.made_in),
		byproducts    = resolve_recipe_byproducts(definition.outputs),
		fluid_byproducts = resolve_fluid_byproducts(definition.fluid_outputs),
		technology_id = definition.technology,
		technology    = NO_TECHNOLOGY,
		schematic     = NO_ITEM,
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
	if recipe.fluid_inputs, problem = resolve_recipe_fluids(definition, definition.fluid_inputs, fluids, allocator); problem != "" {
		delete(recipe.inputs, allocator)
		delete(recipe.outputs, allocator)
		return {}, problem
	}
	if recipe.fluid_outputs, problem = resolve_recipe_fluids(definition, definition.fluid_outputs, fluids, allocator); problem != "" {
		delete(recipe.inputs, allocator)
		delete(recipe.outputs, allocator)
		delete(recipe.fluid_inputs, allocator)
		return {}, problem
	}
	if recipe.name_key == "" {
		recipe.name_key = items.items[recipe.outputs[0].item].name_key
	}
	if recipe.schematic, problem = resolve_schematic_item(definition, items); problem != "" {
		delete(recipe.inputs, allocator)
		delete(recipe.outputs, allocator)
		delete(recipe.fluid_inputs, allocator)
		delete(recipe.fluid_outputs, allocator)
		return {}, problem
	}
	return recipe, ""
}

// A schematic is a usable item.
resolve_schematic_item :: proc(definition: Recipe_Definition, items: Item_Registry) -> (item: Item_Id, problem: string) {
	if definition.schematic == "" {
		return NO_ITEM, ""
	}
	found: bool
	if item, found = find_item_id(items, definition.schematic); !found || !item_is_usable(items, item) {
		return NO_ITEM, fmt.tprintf("recipe %q names schematic %q, which is not a usable item", definition.id, definition.schematic)
	}
	return item, ""
}

// One recipe per schematic item.
validate_schematic_recipes :: proc(recipes: []Recipe) -> string {
	for recipe, index in recipes {
		for other in recipes[index + 1:] {
			if recipe.schematic != NO_ITEM && other.schematic == recipe.schematic {
				return fmt.tprintf("recipes %q and %q share their schematic", recipe.id, other.id)
			}
		}
	}
	return ""
}

// The furnace has one input slot, one output slot and a byproduct slot
// for slag, so it makes only recipes of that shape.
recipe_fits_furnace :: proc(recipe: Recipe) -> bool {
	if .Furnace not_in recipe.made_in || len(recipe.inputs) != 1 || 0 in recipe.byproducts {
		return false
	}
	return len(recipe.outputs) == 1 || len(recipe.outputs) == 2 && 1 in recipe.byproducts
}

// A furnace picks its recipe by the input item, which must be unambiguous.
// A furnace recipe of another shape is an error: two input alloys belong
// to the alloy furnace.
validate_furnace_recipes :: proc(recipes: []Recipe) -> string {
	for recipe, index in recipes {
		if .Furnace in recipe.made_in && !recipe_fits_furnace(recipe) {
			return fmt.tprintf("furnace recipe %q needs exactly one input, one main output and at most one byproduct", recipe.id)
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
	registry.recycle_recipes = resolve_recycle_recipes(registry.recipes, items, allocator)
	if problem = validate_furnace_recipes(registry.recipes); problem != "" {
		destroy_recipe_registry(registry, allocator)
		return {}, problem
	}
	if problem = validate_assembler_recipes(registry.recipes); problem != "" {
		destroy_recipe_registry(registry, allocator)
		return {}, problem
	}
	if problem = validate_schematic_recipes(registry.recipes); problem != "" {
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
		delete(recipe.fluid_outputs, allocator)
	}
	delete(registry.recipes, allocator)
	delete(registry.tag_names, allocator)
	delete(registry.recycle_recipes, allocator)
}

// The registry as the session sees it, with its found schematics.
with_schematics_found :: proc(registry: Recipe_Registry, schematics_found: []bool) -> Recipe_Registry {
	result := registry
	result.schematics_found = schematics_found
	return result
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

// The furnace recipe for an input item, or NO_RECIPE. A schematic recipe
// not found yet is skipped.
furnace_recipe_for :: proc(registry: Recipe_Registry, item: Item_Id) -> int {
	for recipe, index in registry.recipes {
		if recipe_fits_furnace(recipe) && recipe.inputs[0].item == item && recipe_runs_in_machines(registry, index) {
			return index
		}
	}
	return NO_RECIPE
}

item_is_smeltable :: proc(registry: Recipe_Registry, item: Item_Id) -> bool {
	return furnace_recipe_for(registry, item) != NO_RECIPE
}

// Machines pick their recipe by what they hold and never check unlocks,
// except for schematic alternates: their inputs are common, so a machine
// makes one only once its schematic was found.
recipe_runs_in_machines :: proc(registry: Recipe_Registry, index: int) -> bool {
	found := registry.schematics_found
	return registry.recipes[index].channel != .Schematic || index < len(found) && found[index]
}

// The schematic recipe a usable item unlocks, or NO_RECIPE.
schematic_recipe_for :: proc(registry: Recipe_Registry, item: Item_Id) -> int {
	for recipe, index in registry.recipes {
		if recipe.schematic != NO_ITEM && recipe.schematic == item {
			return index
		}
	}
	return NO_RECIPE
}

// Every schematic item in recipe order, in the temp allocator.
schematic_items :: proc(registry: Recipe_Registry) -> []Item_Id {
	found := make([dynamic]Item_Id, context.temp_allocator)
	for recipe in registry.recipes {
		if recipe.schematic != NO_ITEM {
			append(&found, recipe.schematic)
		}
	}
	return found[:]
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
