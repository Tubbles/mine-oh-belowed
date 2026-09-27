package game

import "core:fmt"

// Crafting machines (work items 0021 and 0026): one entity kind, the
// assembler pool, for every machine that makes recipes of one maker
// category. The machine entry names the category (assembler, crusher,
// washer, alloy furnace), the power (electric through power credit, or a
// fuel slot burning fuel power), optional fluid input ports, and the
// recipe choice:
//
// - chosen (the assembler): the player picks the recipe in the panel, and
//   the slots follow it, one input slot per ingredient in ingredient
//   order, then one output slot per product.
// - fixed (crusher, washer, alloy furnace): the machine entry sets the
//   input and output slot counts, and the machine makes the one recipe of
//   its category whose input items are exactly the items in its input
//   slots, like the stone furnace picks by its input. The loader refuses
//   a category where that could be ambiguous.
//
// - the recycler (recycler.odin): fixed, reversing the recipe that makes
//   the loaded item.
//
// Slots are laid out fuel slot (if any), inputs, outputs. A craft takes
// its ingredients when it starts, and starts only when every product
// would fit, so a finished craft always has room. In a world with lenient
// byproducts (World_Settings.byproducts_lenient) outputs a recipe flags
// as byproducts are left out of that check, and at completion what does
// not fit is voided. Fluid inputs are drawn
// from the input port buffers a share per progress tick, so a craft stalls
// (No_Fluid) rather than starts short. An electric machine works one tick
// per power credit step (power_machine.odin); a fuel burning one burns its
// fuel power on every tick it works.

MAXIMUM_ASSEMBLER_SLOTS :: 8

Recipe_Choice :: enum u8 {
	Chosen,
	Fixed,
}

@(rodata)
recipe_choice_names := [Recipe_Choice]string {
	.Chosen = "chosen",
	.Fixed  = "fixed",
}

Assembler_State :: enum u8 {
	No_Recipe,
	No_Power,
	Missing_Ingredients,
	Output_Full,
	Working,
	No_Fuel,
	No_Fluid,
}

@(rodata)
assembler_state_keys := [Assembler_State]string {
	.No_Recipe           = "machine_state_no_recipe",
	.No_Power            = "machine_state_unpowered",
	.Missing_Ingredients = "machine_state_missing_ingredients",
	.Output_Full         = "machine_state_output_full",
	.Working             = "machine_state_working",
	.No_Fuel             = "machine_state_no_fuel",
	.No_Fluid            = "machine_state_no_fluid",
}

// recipe is NO_RECIPE or a recipe index: the chosen one, or for a fixed
// choice the one the inputs match (kept while a craft runs).
// slots[:fuel_count] is the fuel slot, the next input_count slots the
// inputs and the next output_count slots the products. working is set
// from the start of a craft (ingredients taken) to its end. buffers and
// closed are per fluid port, like a fluid machine's.
Assembler :: struct {
	using common:     Entity_Common,
	recipe:           int,
	fuel_count:       int,
	input_count:      int,
	output_count:     int,
	slots:            [MAXIMUM_ASSEMBLER_SLOTS]Item_Stack,
	working:          bool,
	progress_ticks:   u32,
	state:            Assembler_State,
	power:            Power_State,
	fuel_joules:      u32,
	fuel_item_joules: u32,
	buffers:          [MAXIMUM_FLUID_PORTS]Fluid_Buffer,
	closed:           [MAXIMUM_FLUID_PORTS]bool,
}

// The zero machine is an electric assembler with a chosen recipe, which
// is what the unit tests build outside any world.
make_assembler :: proc(common: Entity_Common, machine := Machine{}) -> Assembler {
	assembler := Assembler {
		common     = common,
		recipe     = NO_RECIPE,
		fuel_count = min(machine.slot_count, 1),
	}
	if machine.recipe_choice == .Fixed {
		assembler.input_count, assembler.output_count = machine.input_slot_count, machine.output_slot_count
		assembler.state = .Missing_Ingredients
	}
	for &slot in assembler.slots {
		slot = EMPTY_STACK
	}
	for &buffer in assembler.buffers {
		buffer = EMPTY_FLUID_BUFFER
	}
	return assembler
}

crafting_machine_is_electric :: proc(machine: Machine) -> bool {
	return machine.electric_power_watts > 0
}

// A recipe an assembler can hold: made in an assembler, and its
// ingredients and products fit the slots.
recipe_fits_assembler :: proc(recipe: Recipe) -> bool {
	return .Assembler in recipe.made_in && len(recipe.inputs) + len(recipe.outputs) <= MAXIMUM_ASSEMBLER_SLOTS
}

validate_assembler_recipes :: proc(recipes: []Recipe) -> string {
	for recipe in recipes {
		if .Assembler in recipe.made_in && !recipe_fits_assembler(recipe) {
			return fmt.tprintf("assembler recipe %q has more than %d ingredients and products", recipe.id, MAXIMUM_ASSEMBLER_SLOTS)
		}
	}
	return ""
}

// A recipe the machine can make: of its category, and for a chosen
// recipe small enough for the slots next to the fuel slot.
recipe_fits_crafting_machine :: proc(recipe: Recipe, machine: Machine) -> bool {
	if machine.recipe_maker not_in recipe.made_in {
		return false
	}
	if machine.recipe_choice == .Fixed {
		return len(recipe.inputs) <= machine.input_slot_count && len(recipe.outputs) <= machine.output_slot_count
	}
	return machine.slot_count + len(recipe.inputs) + len(recipe.outputs) <= MAXIMUM_ASSEMBLER_SLOTS
}

// Speed, power (electric, or one fuel slot with fuel power), a crafting
// category, and slot counts only for a fixed recipe choice.
validate_crafting_machine_definition :: proc(definition: Machine_Definition) -> string {
	maker, maker_found := parse_named_enum(recipe_maker_names, definition.recipe_maker)
	if !maker_found || maker == .Hand || maker == .Furnace {
		return fmt.tprintf("crafting machine %q needs a recipe_maker of a crafting machine category", definition.id)
	}
	choice, choice_found := parse_named_enum(recipe_choice_names, definition.recipe_choice)
	if !choice_found || maker == .Recycler && choice != .Fixed {
		return fmt.tprintf("crafting machine %q needs recipe_choice chosen or fixed (fixed for the recycler)", definition.id)
	}
	burner := definition.fuel_slots == 1 && definition.fuel_power_kilowatts > 0 && definition.electric_power_kilowatts == 0
	electric := definition.fuel_slots == 0 && definition.fuel_power_kilowatts == 0 && definition.electric_power_kilowatts > 0
	if definition.speed <= 0 || (!burner && !electric) {
		return fmt.tprintf("crafting machine %q needs a positive speed and either electric_power_kilowatts or one fuel slot with fuel_power_kilowatts", definition.id)
	}
	if definition.slots != 0 {
		return fmt.tprintf("crafting machine %q may not list slots", definition.id)
	}
	if choice == .Chosen && (definition.input_slots != 0 || definition.output_slots != 0) {
		return fmt.tprintf("crafting machine %q with a chosen recipe takes its slots from the recipe", definition.id)
	}
	slot_total := definition.fuel_slots + definition.input_slots + definition.output_slots
	if choice == .Fixed && (definition.input_slots < 1 || definition.output_slots < 1 || slot_total > MAXIMUM_ASSEMBLER_SLOTS) {
		return fmt.tprintf("crafting machine %q with a fixed recipe needs input and output slots, at most %d slots in all", definition.id, MAXIMUM_ASSEMBLER_SLOTS)
	}
	return ""
}

// Whether every input item of first is also one of second.
recipe_inputs_within :: proc(first, second: Recipe) -> bool {
	for input in first.inputs {
		if !stacks_contain_item(second.inputs, input.item) {
			return false
		}
	}
	return true
}

// A fixed choice picks by the input items, so within one category no
// recipe's input items may be a subset of another's: with only those
// items loaded the machine could not tell which the player meant.
validate_fixed_category :: proc(recipes: []Recipe, maker: Recipe_Maker) -> string {
	for recipe, index in recipes {
		if maker not_in recipe.made_in {
			continue
		}
		for other, other_index in recipes {
			if other_index != index && maker in other.made_in && recipe_inputs_within(recipe, other) {
				return fmt.tprintf("recipes %q and %q of the fixed category %q cannot be told apart by their inputs", recipe.id, other.id, recipe_maker_names[maker])
			}
		}
	}
	return ""
}

// The machine has an input port for every fluid its recipes use.
machine_takes_fluid :: proc(machine: Machine, fluid: Fluid_Id) -> bool {
	for port in fluid_ports_of(machine) {
		if port.direction != .Output && (port.filter == NO_FLUID || port.filter == fluid) {
			return true
		}
	}
	return false
}

validate_crafting_machine_recipe :: proc(machine: Machine, recipe: Recipe) -> string {
	if !recipe_fits_crafting_machine(recipe, machine) {
		return fmt.tprintf("recipe %q does not fit the slots of machine %q", recipe.id, machine.id)
	}
	for fluid_input in recipe.fluid_inputs {
		if !machine_takes_fluid(machine, fluid_input.fluid) {
			return fmt.tprintf("recipe %q needs a fluid machine %q has no input port for", recipe.id, machine.id)
		}
	}
	return ""
}

// Runs once machines and recipes are both loaded: every recipe of a
// machine's category fits it, and fixed categories are unambiguous.
validate_crafting_machine_recipes :: proc(machines: Machine_Registry, recipes: Recipe_Registry) -> string {
	for machine in machines.machines {
		if machine.kind != .Crafting_Machine {
			continue
		}
		for recipe in recipes.recipes {
			if machine.recipe_maker not_in recipe.made_in {
				continue
			}
			if problem := validate_crafting_machine_recipe(machine, recipe); problem != "" {
				return problem
			}
		}
		if machine.recipe_choice == .Fixed {
			if problem := validate_fixed_category(recipes.recipes, machine.recipe_maker); problem != "" {
				return problem
			}
		}
		if machine.recipe_maker == .Recycler {
			if problem := validate_recycler_returns(machine, recipes); problem != "" {
				return problem
			}
		}
	}
	return ""
}

// Slot layout.

assembler_slot_count :: proc(assembler: Assembler) -> int {
	return assembler.fuel_count + assembler.input_count + assembler.output_count
}

assembler_first_input :: proc(assembler: Assembler) -> int {
	return assembler.fuel_count
}

assembler_first_output :: proc(assembler: Assembler) -> int {
	return assembler.fuel_count + assembler.input_count
}

assembler_input_slots :: proc(assembler: ^Assembler) -> []Item_Stack {
	return assembler.slots[assembler_first_input(assembler^):assembler_first_output(assembler^)]
}

assembler_output_slots :: proc(assembler: ^Assembler) -> []Item_Stack {
	return assembler.slots[assembler_first_output(assembler^):assembler_slot_count(assembler^)]
}

// A copy of the input slots in the temp allocator, for procedures that
// take the machine by value.
assembler_input_copy :: proc(assembler: Assembler) -> []Item_Stack {
	inputs := make([]Item_Stack, assembler.input_count, context.temp_allocator)
	for &input, index in inputs {
		input = assembler.slots[assembler_first_input(assembler) + index]
	}
	return inputs
}

// Inputs and outputs, without the fuel.
assembler_material_slots :: proc(assembler: ^Assembler) -> []Item_Stack {
	return assembler.slots[assembler_first_input(assembler^):assembler_slot_count(assembler^)]
}

// The input slot (an index into slots) the item goes to, or -1. A chosen
// recipe has one slot per ingredient. A fixed choice puts the item with
// its kind, or into an empty input slot while some recipe of the category
// uses it together with everything already loaded.
assembler_input_slot_of :: proc(assembler: Assembler, machine: Machine, recipes: Recipe_Registry, item: Item_Id) -> int {
	if machine.recipe_choice == .Chosen {
		if assembler.recipe == NO_RECIPE {
			return -1
		}
		for input, index in recipes.recipes[assembler.recipe].inputs {
			if input.item == item {
				return assembler_first_input(assembler) + index
			}
		}
		return -1
	}
	inputs := assembler_input_copy(assembler)
	for slot, index in inputs {
		if !stack_is_empty(slot) && slot.item == item {
			return assembler_first_input(assembler) + index
		}
	}
	if !category_recipe_accepts(recipes, machine.recipe_maker, inputs, item) {
		return -1
	}
	for slot, index in inputs {
		if stack_is_empty(slot) {
			return assembler_first_input(assembler) + index
		}
	}
	return -1
}

// Some recipe of the category takes the item and every item loaded. The
// recycler takes any recyclable item into its one input slot.
category_recipe_accepts :: proc(recipes: Recipe_Registry, maker: Recipe_Maker, loaded: []Item_Stack, item: Item_Id) -> bool {
	if maker == .Recycler {
		return item_is_recyclable(recipes, item)
	}
	for recipe in recipes.recipes {
		if maker in recipe.made_in && stacks_contain_item(recipe.inputs, item) && loaded_items_within(loaded, recipe) {
			return true
		}
	}
	return false
}

loaded_items_within :: proc(loaded: []Item_Stack, recipe: Recipe) -> bool {
	for slot in loaded {
		if !stack_is_empty(slot) && !stacks_contain_item(recipe.inputs, slot.item) {
			return false
		}
	}
	return true
}

// Whether any recipe of the category uses the item, and the most of it
// one craft takes.
category_input_count :: proc(recipes: Recipe_Registry, maker: Recipe_Maker, item: Item_Id) -> int {
	if maker == .Recycler {
		recipe := recycle_recipe_of(recipes, item)
		return recipe == NO_RECIPE ? 0 : int(recycled_stack(recipes, recipe).count)
	}
	most := 0
	for recipe in recipes.recipes {
		if maker not_in recipe.made_in {
			continue
		}
		for input in recipe.inputs {
			if input.item == item {
				most = max(most, int(input.count))
			}
		}
	}
	return most
}

// The recipe of a fixed category whose input items are exactly the loaded
// ones, or NO_RECIPE.
fixed_recipe_for_inputs :: proc(recipes: Recipe_Registry, maker: Recipe_Maker, loaded: []Item_Stack) -> int {
	for recipe, index in recipes.recipes {
		if maker in recipe.made_in && loaded_items_within(loaded, recipe) && recipe_inputs_loaded(recipe, loaded) {
			return index
		}
	}
	return NO_RECIPE
}

recipe_inputs_loaded :: proc(recipe: Recipe, loaded: []Item_Stack) -> bool {
	for input in recipe.inputs {
		if loaded_count(loaded, input.item) == 0 {
			return false
		}
	}
	return true
}

loaded_count :: proc(loaded: []Item_Stack, item: Item_Id) -> int {
	total := 0
	for slot in loaded {
		if !stack_is_empty(slot) && slot.item == item {
			total += int(slot.count)
		}
	}
	return total
}

// Everything the player gets back on a recipe change: inputs, outputs and
// the ingredients of a craft in progress, in the temp allocator.
assembler_contents :: proc(assembler: ^Assembler, machine: Machine, recipes: Recipe_Registry) -> []Item_Stack {
	contents := make([dynamic]Item_Stack, context.temp_allocator)
	append(&contents, ..assembler_material_slots(assembler))
	append(&contents, ..assembler_held_stacks(assembler^, machine, recipes))
	return contents[:]
}

// The ingredients of the craft in progress (for the recycler the item it
// took), which come back on pick up and on a recipe change. In the temp
// allocator.
assembler_held_stacks :: proc(assembler: Assembler, machine: Machine, recipes: Recipe_Registry) -> []Item_Stack {
	if !assembler.working || assembler.recipe == NO_RECIPE {
		return nil
	}
	inputs := machine_craft(machine, recipes, assembler.recipe).inputs
	held := make([]Item_Stack, len(inputs), context.temp_allocator)
	copy(held, inputs)
	return held
}

// Empties the inputs and outputs and lays out the slots of the new recipe
// (or none); the fuel slot stays. The caller takes the contents first
// (assembler_contents).
set_assembler_recipe :: proc(assembler: ^Assembler, recipes: Recipe_Registry, recipe: int) {
	for &slot in assembler.slots[assembler.fuel_count:] {
		slot = EMPTY_STACK
	}
	assembler.recipe = recipe
	assembler.working, assembler.progress_ticks = false, 0
	assembler.input_count, assembler.output_count = 0, 0
	if recipe != NO_RECIPE {
		assembler.input_count = len(recipes.recipes[recipe].inputs)
		assembler.output_count = len(recipes.recipes[recipe].outputs)
	}
	assembler.state = recipe == NO_RECIPE ? .No_Recipe : .Missing_Ingredients
}

Recipe_Change_Refusal :: enum u8 {
	None,
	Not_For_Assembler,
	Contents_Do_Not_Fit,
}

// A recipe change from the panel: the contents go to the player's
// inventory, and when they do not fit nothing changes. A fixed choice
// machine takes no recipe from the panel.
change_assembler_recipe :: proc(assembler: ^Assembler, machine: Machine, inventory: Inventory, items: Item_Registry, recipes: Recipe_Registry, recipe: int) -> Recipe_Change_Refusal {
	if recipe == assembler.recipe {
		return .None
	}
	if machine.recipe_choice == .Fixed || recipe != NO_RECIPE && !recipe_fits_crafting_machine(recipes.recipes[recipe], machine) {
		return .Not_For_Assembler
	}
	contents := assembler_contents(assembler, machine, recipes)
	if !inventory_fits_all(inventory, items, contents) {
		return .Contents_Do_Not_Fit
	}
	for stack in contents {
		if !stack_is_empty(stack) {
			inventory_add(inventory, items, stack.item, int(stack.count))
		}
	}
	set_assembler_recipe(assembler, recipes, recipe)
	return .None
}

// Crafting.

// What one craft of a machine takes and gives: the recipe as written, or
// for the recycler the recipe reversed (recycler.odin), whose returns go
// into any fitting output slot instead of one slot per product.
Craft :: struct {
	inputs:       []Item_Stack,
	outputs:      []Item_Stack,
	byproducts:   Recipe_Output_Set,
	fluid_inputs: []Recipe_Fluid,
	returns:      bool,
}

machine_craft :: proc(machine: Machine, recipes: Recipe_Registry, recipe: int) -> Craft {
	definition := recipes.recipes[recipe]
	if machine.recipe_maker != .Recycler {
		return Craft{inputs = definition.inputs, outputs = definition.outputs, byproducts = definition.byproducts, fluid_inputs = definition.fluid_inputs}
	}
	inputs := make([]Item_Stack, 1, context.temp_allocator)
	inputs[0] = recycled_stack(recipes, recipe)
	return Craft{inputs = inputs, outputs = recycling_returns(definition), returns = true}
}

assembler_inputs_ready :: proc(assembler: Assembler, craft: Craft) -> bool {
	inputs := assembler_input_copy(assembler)
	for input in craft.inputs {
		if loaded_count(inputs, input.item) < int(input.count) {
			return false
		}
	}
	return true
}

stack_fits_slot :: proc(slot, product: Item_Stack, items: Item_Registry) -> bool {
	if stack_is_empty(slot) {
		return true
	}
	return slot.item == product.item && int(slot.count) + int(product.count) <= int(item_stack_size(items, product.item))
}

// Room for every product, byproducts left out when a lenient world voids
// them.
assembler_outputs_fit :: proc(assembler: Assembler, craft: Craft, items: Item_Registry, byproducts_lenient: bool) -> bool {
	probe := assembler
	outputs := assembler_output_slots(&probe)
	if craft.returns {
		return returns_fit(outputs, craft.outputs, items)
	}
	for output, index in craft.outputs {
		if byproducts_lenient && index in craft.byproducts {
			continue
		}
		if !stack_fits_slot(outputs[index], output, items) {
			return false
		}
	}
	return true
}

// The recipe the next craft would make: the chosen one, the one the
// loaded inputs match, or for the recycler the one it reverses.
assembler_next_recipe :: proc(assembler: Assembler, machine: Machine, recipes: Recipe_Registry) -> int {
	switch {
	case machine.recipe_choice == .Chosen:
		return assembler.recipe
	case machine.recipe_maker == .Recycler:
		return recycler_recipe_for_inputs(recipes, assembler_input_copy(assembler))
	}
	return fixed_recipe_for_inputs(recipes, machine.recipe_maker, assembler_input_copy(assembler))
}

// The recipe a craft would start with, or why none can start.
assembler_start_state :: proc(assembler: Assembler, machine: Machine, recipes: Recipe_Registry, items: Item_Registry, byproducts_lenient: bool) -> (recipe: int, state: Assembler_State, blocked: bool) {
	recipe = assembler_next_recipe(assembler, machine, recipes)
	if recipe == NO_RECIPE {
		return recipe, machine.recipe_choice == .Chosen ? .No_Recipe : .Missing_Ingredients, true
	}
	craft := machine_craft(machine, recipes, recipe)
	switch {
	case !assembler_inputs_ready(assembler, craft):
		return recipe, .Missing_Ingredients, true
	case !assembler_outputs_fit(assembler, craft, items, byproducts_lenient):
		return recipe, .Output_Full, true
	}
	return recipe, .Working, false
}

// Litres of a fluid input due on the progress tick after `progress`, so
// the craft's draws add up to exactly its litres.
fluid_litres_for_step :: proc(litres: i32, progress, total: u32) -> i32 {
	due_after := i64(litres) * i64(progress + 1) / i64(max(total, 1))
	due_before := i64(litres) * i64(progress) / i64(max(total, 1))
	return i32(due_after - due_before)
}

// The input port buffer holding the fluid, or -1.
assembler_fluid_buffer_of :: proc(assembler: ^Assembler, fluid: Fluid_Id) -> int {
	for buffer, index in assembler.buffers {
		if buffer.level > 0 && buffer.fluid == fluid {
			return index
		}
	}
	return -1
}

// A step due no litre still needs the fluid present, so a craft never
// starts dry.
assembler_fluid_ready :: proc(assembler: ^Assembler, fluid_inputs: []Recipe_Fluid, progress, total: u32) -> bool {
	for fluid_input in fluid_inputs {
		needed := max(fluid_litres_for_step(fluid_input.litres, progress, total), 1)
		index := assembler_fluid_buffer_of(assembler, fluid_input.fluid)
		if index < 0 || assembler.buffers[index].level < needed {
			return false
		}
	}
	return true
}

draw_assembler_fluids :: proc(assembler: ^Assembler, fluid_inputs: []Recipe_Fluid, progress, total: u32) {
	for fluid_input in fluid_inputs {
		needed := fluid_litres_for_step(fluid_input.litres, progress, total)
		if index := assembler_fluid_buffer_of(assembler, fluid_input.fluid); index >= 0 && needed > 0 {
			assembler.buffers[index].level -= needed
		}
	}
}

assembler_has_fuel :: proc(assembler: Assembler, needed: u32, items: Item_Registry) -> bool {
	fuel := assembler.slots[0]
	return assembler.fuel_joules >= needed || !stack_is_empty(fuel) && item_is_fuel(items, fuel.item)
}

// Whether the machine could work this tick, and the state when not.
assembler_energy_state :: proc(assembler: Assembler, machine: Machine, items: Item_Registry, tick_rate: int) -> (state: Assembler_State, ready: bool) {
	if crafting_machine_is_electric(machine) {
		return .No_Power, power_is_on(assembler.power)
	}
	return .No_Fuel, assembler_has_fuel(assembler, fuel_joules_per_tick(machine, tick_rate), items)
}

// Pays for this tick: a power credit step, or a tick of fuel. True when
// a tick of work is paid for.
pay_assembler_energy :: proc(assembler: ^Assembler, machine: Machine, items: Item_Registry, tick_rate: int) -> bool {
	if crafting_machine_is_electric(machine) {
		return take_power_step(&assembler.power)
	}
	per_tick := fuel_joules_per_tick(machine, tick_rate)
	if !refuel_from_slot(&assembler.fuel_joules, &assembler.fuel_item_joules, &assembler.slots[0], items, per_tick) {
		return false
	}
	assembler.fuel_joules -= per_tick
	return true
}

// Ingredients present, room for the products, and the fluid for the
// first step.
assembler_can_start :: proc(assembler: ^Assembler, machine: Machine, recipes: Recipe_Registry, items: Item_Registry, tick_rate: int, byproducts_lenient: bool) -> bool {
	recipe, _, blocked := assembler_start_state(assembler^, machine, recipes, items, byproducts_lenient)
	if blocked {
		return false
	}
	fluid_inputs := machine_craft(machine, recipes, recipe).fluid_inputs
	return assembler_fluid_ready(assembler, fluid_inputs, 0, recipe_ticks(recipes.recipes[recipe], machine.speed_percent, tick_rate))
}

// An electric machine asks its network for power only while it can work.
assembler_wants_power :: proc(assembler: Assembler, machine: Machine, recipes: Recipe_Registry, items: Item_Registry, tick_rate: int, byproducts_lenient := false) -> bool {
	probe := assembler
	if !assembler.working {
		return assembler_can_start(&probe, machine, recipes, items, tick_rate, byproducts_lenient)
	}
	fluid_inputs := machine_craft(machine, recipes, assembler.recipe).fluid_inputs
	return assembler_fluid_ready(&probe, fluid_inputs, assembler.progress_ticks, recipe_ticks(recipes.recipes[assembler.recipe], machine.speed_percent, tick_rate))
}

start_assembler_craft :: proc(assembler: ^Assembler, craft: Craft) {
	inputs := assembler_input_slots(assembler)
	for input in craft.inputs {
		remaining := int(input.count)
		for &slot in inputs {
			if remaining > 0 && !stack_is_empty(slot) && slot.item == input.item {
				remaining -= take_from_slot(&slot, remaining)
			}
		}
	}
	assembler.working, assembler.progress_ticks = true, 0
}

// Products go into their slots as far as there is room: a strict craft
// only started with room for everything, and what does not fit under
// lenient byproducts is voided (tick_assemblers counts it).
finish_assembler_craft :: proc(assembler: ^Assembler, craft: Craft, items: Item_Registry) {
	outputs := assembler_output_slots(assembler)
	if craft.returns {
		place_returns(outputs, craft.outputs, items)
	} else {
		for output, index in craft.outputs {
			fill_slot(&outputs[index], output.item, int(output.count), item_stack_size(items, output.item))
		}
	}
	assembler.working, assembler.progress_ticks = false, 0
}

// Picks the recipe and checks the ingredients and the room for a new
// craft. False with the state set when none can start.
prepare_assembler_craft :: proc(assembler: ^Assembler, machine: Machine, recipes: Recipe_Registry, items: Item_Registry, byproducts_lenient: bool) -> bool {
	recipe, state, blocked := assembler_start_state(assembler^, machine, recipes, items, byproducts_lenient)
	if machine.recipe_choice == .Fixed {
		assembler.recipe = recipe
	}
	assembler.state = state
	return !blocked
}

// One tick. Returns whether a craft finished, for the statistics.
// byproducts_lenient is the world setting, read at every start and
// completion.
advance_assembler :: proc(assembler: ^Assembler, machine: Machine, items: Item_Registry, recipes: Recipe_Registry, tick_rate: int, byproducts_lenient := false) -> (crafted: bool) {
	if !assembler.working && !prepare_assembler_craft(assembler, machine, recipes, items, byproducts_lenient) {
		return false
	}
	if state, ready := assembler_energy_state(assembler^, machine, items, tick_rate); !ready {
		assembler.state = state
		return false
	}
	craft := machine_craft(machine, recipes, assembler.recipe)
	total := recipe_ticks(recipes.recipes[assembler.recipe], machine.speed_percent, tick_rate)
	if !assembler_fluid_ready(assembler, craft.fluid_inputs, assembler.progress_ticks, total) {
		assembler.state = .No_Fluid
		return false
	}
	if !assembler.working {
		start_assembler_craft(assembler, craft)
	}
	assembler.state = .Working
	if pay_assembler_energy(assembler, machine, items, tick_rate) {
		draw_assembler_fluids(assembler, craft.fluid_inputs, assembler.progress_ticks, total)
		assembler.progress_ticks += 1
	}
	if assembler.progress_ticks < total {
		return false
	}
	finish_assembler_craft(assembler, craft, items)
	return true
}

assembler_progress_fraction :: proc(assembler: Assembler, machine: Machine, recipes: Recipe_Registry, tick_rate: int) -> f32 {
	if !assembler.working || assembler.recipe == NO_RECIPE {
		return 0
	}
	return f32(assembler.progress_ticks) / f32(recipe_ticks(recipes.recipes[assembler.recipe], machine.speed_percent, tick_rate))
}

assembler_burn_fraction :: proc(assembler: Assembler) -> f32 {
	if assembler.fuel_item_joules == 0 {
		return 0
	}
	return f32(assembler.fuel_joules) / f32(assembler.fuel_item_joules)
}

// Pool order; products that reach their slots count as produced, the
// rest as voided, and stalls and fuel like the furnace's.
tick_assemblers :: proc(world: ^World, content: Simulation_Content, tick_rate: int) {
	lenient := world.settings.byproducts_lenient
	for &assembler in world.entities.assemblers.entries {
		if !assembler.alive {
			continue
		}
		machine := content.machines.machines[assembler.machine]
		before := assembler
		if advance_assembler(&assembler, machine, content.items, content.recipes, tick_rate, lenient) {
			record_craft_outputs(&world.statistics, machine_craft(machine, content.recipes, assembler.recipe), before, assembler)
		}
		record_crafting_machine_tick(&world.statistics, before, assembler)
	}
}

// What the player may drop into each slot: fuel into the fuel slot, a
// chosen recipe's inputs only their ingredient, a fixed choice's inputs
// any input of the category, outputs nothing. In the temp allocator.
assembler_slot_filters :: proc(assembler: Assembler, machine: Machine, recipes: Recipe_Registry) -> []Slot_Filter {
	filters := make([]Slot_Filter, assembler_slot_count(assembler), context.temp_allocator)
	first_input, first_output := assembler_first_input(assembler), assembler_first_output(assembler)
	for &filter, index in filters {
		switch {
		case index < first_input:
			filter = {kind = .Fuel}
		case index >= first_output:
			filter = {kind = .Output}
		case machine.recipe_choice == .Fixed:
			filter = {kind = .Crafting_Input, maker = machine.recipe_maker}
		case:
			filter = {kind = .Item, item = recipes.recipes[assembler.recipe].inputs[index - first_input].item}
		}
	}
	return filters
}

// The slot an inserter puts an item into, or none. A fuel item goes into
// an input slot of a fixed choice fuel burner only while another
// ingredient it completes a recipe with is loaded (coal with iron plate
// for steel), and otherwise into the fuel slot, so coal meant as fuel
// never blocks the inputs of an alloy furnace making bronze. An electric
// machine (the recycler taking planks) has no fuel slot to prefer.
assembler_accepting_slot :: proc(assembler: ^Assembler, machine: Machine, content: Simulation_Content, item: Item_Id) -> (slot: int, ok: bool) {
	slots := assembler.slots[:assembler_slot_count(assembler^)]
	fuel := item_is_fuel(content.items, item)
	input := assembler_input_slot_of(assembler^, machine, content.recipes, item)
	if input >= 0 && fuel && assembler.fuel_count > 0 && machine.recipe_choice == .Fixed && !other_input_loaded(assembler, item) {
		input = -1
	}
	if input >= 0 {
		if slot, ok = limited_accepting_slot(slots, input, item, content.items, assembler_insertion_limit(assembler^, machine, content.recipes, item)); ok {
			return
		}
	}
	if assembler.fuel_count > 0 && fuel {
		return fixed_accepting_slot(slots, 0, item, content.items)
	}
	return -1, false
}

other_input_loaded :: proc(assembler: ^Assembler, item: Item_Id) -> bool {
	for slot in assembler_input_slots(assembler) {
		if !stack_is_empty(slot) && slot.item != item {
			return true
		}
	}
	return false
}

// Twice the most of the item one craft takes.
assembler_insertion_limit :: proc(assembler: Assembler, machine: Machine, recipes: Recipe_Registry, item: Item_Id) -> int {
	if machine.recipe_choice == .Fixed {
		return INSERTION_LIMIT_CRAFTS * category_input_count(recipes, machine.recipe_maker, item)
	}
	if assembler.recipe == NO_RECIPE {
		return 0
	}
	for input in recipes.recipes[assembler.recipe].inputs {
		if input.item == item {
			return INSERTION_LIMIT_CRAFTS * int(input.count)
		}
	}
	return 0
}

// Whether an inserter should ever bring the item: an ingredient the
// machine could take, or fuel for its fuel slot.
assembler_takes_item_kind :: proc(assembler: Assembler, machine: Machine, content: Simulation_Content, item: Item_Id) -> bool {
	if assembler.fuel_count > 0 && item_is_fuel(content.items, item) {
		return true
	}
	if machine.recipe_choice == .Fixed {
		return category_input_count(content.recipes, machine.recipe_maker, item) > 0
	}
	return assembler_input_slot_of(assembler, machine, content.recipes, item) >= 0
}
