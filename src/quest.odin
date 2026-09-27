package game

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// Quest chapters from data/quests/*.sjson (doc/quests.md), loaded in file
// name order after every other prototype table and the strings, resolved
// to indices. The runtime is in quest_runtime.odin.

QUESTS_DIRECTORY :: "quests"
QUEST_FILE_EXTENSION :: ".sjson"
MAXIMUM_QUEST_OBJECTIVES :: 8
MAXIMUM_QUEST_HINTS :: 8
NO_QUEST :: -1

// walk and counter are not in doc/quests.md's table: chapter 1's "get
// your bearings" needs walk, chapter 3's coal loop needs counter (the
// growth of a hint counter since the quest became active). produce_fluid
// (chapter 6) counts litres of a fluid produced since activation. ship
// (chapter 8) counts items rockets carried away since the game began, of
// one item or, without an item, of every item.
Objective_Type :: enum u8 {
	Obtain,
	Craft,
	Place,
	Sustain,
	Research,
	Deliver,
	Discover,
	Walk,
	Counter,
	Produce_Fluid,
	Ship,
}

@(rodata)
objective_type_names := [Objective_Type]string {
	.Obtain        = "obtain",
	.Craft         = "craft",
	.Place         = "place",
	.Sustain       = "sustain",
	.Research      = "research",
	.Deliver       = "deliver",
	.Discover      = "discover",
	.Walk          = "walk",
	.Counter       = "counter",
	.Produce_Fluid = "produce_fluid",
	.Ship          = "ship",
}

// The counters a hint can watch. Mining_Ticks is per block type.
Hint_Counter :: enum u8 {
	Blocks_Mined,
	Mining_Ticks,
	Distance_Walked,
	Furnace_Out_Of_Fuel,
	Furnace_Output_Full,
	Fuel_Burned,
	Inventory_Full_Ticks,
	Inserter_Out_Of_Fuel,
	Inserter_Waiting_For_Room,
	Inserter_Idle_Ticks,
	Drill_Out_Of_Fuel,
	Drill_Waiting_For_Room,
	Vein_Exhausted,
	Belt_Dead_End_Ticks,
	Inserter_Idle_A_Minute,
	Drill_Fuel_Burned,
	Brownout_Ticks,
	Unpowered_Machine_Ticks,
	Recycled,
	Mixing_Refusals,
	Flared_Litres,
	Generator_Gas_Litres,
	Schematics_Found,
	Veins_Assayed,
	Core_Samples_Taken,
	Seismic_Shots,
	Veins_Resolved,
	Bore_Drill_Units,
	Bore_Drill_No_Vein_Attempts,
	Turbine_Kilojoules,
	Turbine_Still_Water_Ticks,
	Rockets_Launched,
	Contracts_Completed,
	Contracts_Late,
	Credit_Earned,
	Surveys_Bought,
	Items_Shipped,
	Launch_Parts_Missing,
	Launch_Cargo_Empty,
}

@(rodata)
hint_counter_names := [Hint_Counter]string {
	.Blocks_Mined                = "blocks_mined",
	.Mining_Ticks                = "mining_ticks",
	.Distance_Walked             = "distance_walked",
	.Furnace_Out_Of_Fuel         = "furnace_out_of_fuel",
	.Furnace_Output_Full         = "furnace_output_full",
	.Fuel_Burned                 = "fuel_burned",
	.Inventory_Full_Ticks        = "inventory_full_ticks",
	.Inserter_Out_Of_Fuel        = "inserter_out_of_fuel",
	.Inserter_Waiting_For_Room   = "inserter_waiting_for_room",
	.Inserter_Idle_Ticks         = "inserter_idle_ticks",
	.Drill_Out_Of_Fuel           = "drill_out_of_fuel",
	.Drill_Waiting_For_Room      = "drill_waiting_for_room",
	.Vein_Exhausted              = "vein_exhausted",
	.Belt_Dead_End_Ticks         = "belt_dead_end_ticks",
	.Inserter_Idle_A_Minute      = "inserter_idle_a_minute",
	.Drill_Fuel_Burned           = "drill_fuel_burned",
	.Brownout_Ticks              = "brownout_ticks",
	.Unpowered_Machine_Ticks     = "unpowered_machine_ticks",
	.Recycled                    = "recycled",
	.Mixing_Refusals             = "mixing_refusals",
	.Flared_Litres               = "flared_litres",
	.Generator_Gas_Litres        = "generator_gas_litres",
	.Schematics_Found            = "schematics_found",
	.Veins_Assayed               = "veins_assayed",
	.Core_Samples_Taken          = "core_samples_taken",
	.Seismic_Shots               = "seismic_shots",
	.Veins_Resolved              = "veins_resolved",
	.Bore_Drill_Units            = "bore_drill_units",
	.Bore_Drill_No_Vein_Attempts = "bore_drill_no_vein_attempts",
	.Turbine_Kilojoules          = "turbine_kilojoules",
	.Turbine_Still_Water_Ticks   = "turbine_still_water_ticks",
	.Rockets_Launched            = "rockets_launched",
	.Contracts_Completed         = "contracts_completed",
	.Contracts_Late              = "contracts_late",
	.Credit_Earned               = "credit_earned",
	.Surveys_Bought              = "surveys_bought",
	.Items_Shipped               = "items_shipped",
	.Launch_Parts_Missing        = "launch_parts_missing",
	.Launch_Cargo_Empty          = "launch_cargo_empty",
}

// As written in the files, before references are resolved.
Objective_Definition :: struct {
	type:                  string,
	item:                  string,
	entity:                string,
	recipe:                string,
	technology:            string,
	counter:               string,
	label_key:             string,
	fluid:                 string,
	count:                 int,
	litres:                int,
	rate_per_minute:       int,
	minutes:               int,
	hands_off:             bool,
	produced_since_active: bool,
}

// on_activation hints fire when their quest becomes active and name no
// counter or threshold.
Hint_Definition :: struct {
	counter:       string,
	block:         string,
	threshold:     int,
	text_key:      string,
	on_activation: bool,
}

// Exactly one of an item and a count, unlocks_recipe or
// unlocks_technology.
Reward_Definition :: struct {
	item:               string,
	count:              int,
	unlocks_recipe:     string,
	unlocks_technology: string,
}

Quest_Definition :: struct {
	id:           string,
	title_key:    string,
	text_key:     string,
	objectives:   []Objective_Definition,
	message_key:  string,
	complete_key: string,
	hints:        []Hint_Definition,
	rewards:      []Reward_Definition,
	main:         bool,
}

Chapter_File :: struct {
	id:        string,
	title_key: string,
	quests:    []Quest_Definition,
}

// count is items, placements, blocks walked, counter growth or litres of
// fluid. Unused references are NO_ITEM, NO_MACHINE, NO_RECIPE,
// NO_TECHNOLOGY, NO_FLUID. A place
// objective has a machine, or with NO_MACHINE the item whose blocks are
// counted. A ship objective with NO_ITEM counts every item shipped. counter and label_key (the journal's text for it) belong to
// counter objectives; produced_since_active makes a craft objective count
// from activation.
Objective :: struct {
	type:                  Objective_Type,
	item:                  Item_Id,
	machine:               Machine_Id,
	fluid:                 Fluid_Id,
	recipe:                int,
	technology:            int,
	counter:               Hint_Counter,
	label_key:             string,
	count:                 u64,
	rate_per_minute:       u64,
	minutes:               u64,
	hands_off:             bool,
	produced_since_active: bool,
}

// threshold counts from the value when the quest became active; 0 fires
// on activation.
Hint :: struct {
	counter:   Hint_Counter,
	block:     Block_Id,
	threshold: u64,
	text_key:  string,
}

Quest :: struct {
	id:                  string,
	chapter:             int,
	title_key:           string,
	text_key:            string,
	message_key:         string,
	complete_key:        string,
	objectives:          []Objective,
	hints:               []Hint,
	reward_items:        []Item_Stack,
	reward_recipes:      []int,
	reward_technologies: []int,
	main:                bool,
}

// A chapter's quests are quests[first_quest:][:quest_count].
Chapter :: struct {
	id:          string,
	title_key:   string,
	first_quest: int,
	quest_count: int,
}

// Quests of every chapter in play order.
Quest_Registry :: struct {
	chapters: []Chapter,
	quests:   []Quest,
}

// What quest data may refer to.
Quest_References :: struct {
	blocks:       Block_Registry,
	items:        Item_Registry,
	machines:     Machine_Registry,
	fluids:       Fluid_Registry,
	recipes:      Recipe_Registry,
	technologies: Technology_Registry,
	strings:      map[string]string,
}

parse_chapter_file :: proc(data: []byte, allocator := context.allocator) -> (file: Chapter_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

find_technology :: proc(registry: Technology_Registry, id: string) -> int {
	for technology, index in registry.technologies {
		if technology.id == id {
			return index
		}
	}
	return NO_TECHNOLOGY
}

check_string_key :: proc(references: Quest_References, owner, field, key: string, required: bool) -> string {
	if key == "" {
		return required ? fmt.tprintf("quest %q has no %s", owner, field) : ""
	}
	if key not_in references.strings {
		return fmt.tprintf("quest %q: %s %q is not in the string table", owner, field, key)
	}
	return ""
}

resolve_objective_item :: proc(objective: ^Objective, definition: Objective_Definition, references: Quest_References, quest_id: string) -> string {
	found: bool
	if objective.item, found = find_item_id(references.items, definition.item); !found {
		return fmt.tprintf("quest %q names unknown item %q", quest_id, definition.item)
	}
	return ""
}

resolve_objective_reference :: proc(objective: ^Objective, definition: Objective_Definition, references: Quest_References, quest_id: string) -> string {
	switch objective.type {
	case .Obtain, .Craft, .Deliver, .Sustain:
		return resolve_objective_item(objective, definition, references, quest_id)
	case .Place:
		return resolve_objective_placement(objective, definition, references, quest_id)
	case .Research:
		if objective.technology = find_technology(references.technologies, definition.technology); objective.technology == NO_TECHNOLOGY {
			return fmt.tprintf("quest %q names unknown technology %q", quest_id, definition.technology)
		}
	case .Discover:
		if objective.recipe = find_recipe(references.recipes, definition.recipe); objective.recipe == NO_RECIPE {
			return fmt.tprintf("quest %q names unknown recipe %q", quest_id, definition.recipe)
		}
	case .Counter:
		return resolve_objective_counter(objective, definition, references, quest_id)
	case .Produce_Fluid:
		return resolve_objective_fluid(objective, definition, references, quest_id)
	case .Ship:
		if definition.item != "" {
			return resolve_objective_item(objective, definition, references, quest_id)
		}
	case .Walk:
	}
	return ""
}

// A fluid and litres, never a count.
resolve_objective_fluid :: proc(objective: ^Objective, definition: Objective_Definition, references: Quest_References, quest_id: string) -> string {
	found: bool
	if objective.fluid, found = find_fluid_id(references.fluids, definition.fluid); !found {
		return fmt.tprintf("quest %q names unknown fluid %q", quest_id, definition.fluid)
	}
	if definition.litres < 1 || definition.count != 0 {
		return fmt.tprintf("quest %q has a produce_fluid objective without positive litres or with a count", quest_id)
	}
	return ""
}

// A machine (entity), or an item that places a block (item).
resolve_objective_placement :: proc(objective: ^Objective, definition: Objective_Definition, references: Quest_References, quest_id: string) -> string {
	if (definition.entity == "") == (definition.item == "") {
		return fmt.tprintf("quest %q has a place objective that is not exactly one of entity or item", quest_id)
	}
	if definition.item != "" {
		if problem := resolve_objective_item(objective, definition, references, quest_id); problem != "" {
			return problem
		}
		if item_places_block(references.items, objective.item) == AIR_BLOCK {
			return fmt.tprintf("quest %q places item %q, which places no block", quest_id, definition.item)
		}
		return ""
	}
	found: bool
	if objective.machine, found = find_machine_id(references.machines, definition.entity); !found {
		return fmt.tprintf("quest %q names unknown entity %q", quest_id, definition.entity)
	}
	return ""
}

// mining_ticks needs a block, which objectives do not name.
resolve_objective_counter :: proc(objective: ^Objective, definition: Objective_Definition, references: Quest_References, quest_id: string) -> string {
	found: bool
	if objective.counter, found = parse_named_enum(hint_counter_names, definition.counter); !found || objective.counter == .Mining_Ticks {
		return fmt.tprintf("quest %q has a counter objective on unsupported counter %q", quest_id, definition.counter)
	}
	objective.label_key = definition.label_key
	return check_string_key(references, quest_id, "objective label_key", definition.label_key, true)
}

objective_needs_count :: proc(type: Objective_Type) -> bool {
	#partial switch type {
	case .Sustain, .Research, .Discover, .Produce_Fluid:
		return false
	}
	return true
}

resolve_objective :: proc(definition: Objective_Definition, references: Quest_References, quest_id: string) -> (objective: Objective, problem: string) {
	found: bool
	if objective.type, found = parse_named_enum(objective_type_names, definition.type); !found {
		return {}, fmt.tprintf("quest %q has unknown objective type %q", quest_id, definition.type)
	}
	objective.item, objective.machine, objective.fluid = NO_ITEM, NO_MACHINE, NO_FLUID
	objective.recipe, objective.technology = NO_RECIPE, NO_TECHNOLOGY
	if problem = resolve_objective_reference(&objective, definition, references, quest_id); problem != "" {
		return {}, problem
	}
	if objective_needs_count(objective.type) && definition.count < 1 {
		return {}, fmt.tprintf("quest %q has a %s objective without a positive count", quest_id, definition.type)
	}
	if objective.type == .Sustain && (definition.rate_per_minute < 1 || definition.minutes < 1) {
		return {}, fmt.tprintf("quest %q has a sustain objective without a positive rate_per_minute and minutes", quest_id)
	}
	if definition.produced_since_active && objective.type != .Craft {
		return {}, fmt.tprintf("quest %q sets produced_since_active on a %s objective", quest_id, definition.type)
	}
	objective.count = u64(max(objective.type == .Produce_Fluid ? definition.litres : definition.count, 0))
	objective.rate_per_minute = u64(max(definition.rate_per_minute, 0))
	objective.minutes = u64(max(definition.minutes, 0))
	objective.hands_off = definition.hands_off
	objective.produced_since_active = definition.produced_since_active
	return objective, ""
}

// Any counter works for a threshold of 0, since counters never shrink.
resolve_activation_hint :: proc(definition: Hint_Definition, references: Quest_References, quest_id: string) -> (hint: Hint, problem: string) {
	if definition.counter != "" || definition.threshold != 0 {
		return {}, fmt.tprintf("quest %q has an on_activation hint with a counter or threshold", quest_id)
	}
	if problem = check_string_key(references, quest_id, "hint text_key", definition.text_key, true); problem != "" {
		return {}, problem
	}
	return Hint{counter = .Blocks_Mined, text_key = definition.text_key}, ""
}

resolve_hint :: proc(definition: Hint_Definition, references: Quest_References, quest_id: string) -> (hint: Hint, problem: string) {
	if definition.on_activation {
		return resolve_activation_hint(definition, references, quest_id)
	}
	found: bool
	if hint.counter, found = parse_named_enum(hint_counter_names, definition.counter); !found {
		return {}, fmt.tprintf("quest %q has a hint on unknown counter %q", quest_id, definition.counter)
	}
	if hint.counter == .Mining_Ticks {
		if hint.block, found = find_block_id(references.blocks, definition.block); !found {
			return {}, fmt.tprintf("quest %q has a mining_ticks hint on unknown block %q", quest_id, definition.block)
		}
	}
	if definition.threshold < 1 {
		return {}, fmt.tprintf("quest %q has a hint without a positive threshold", quest_id)
	}
	if problem = check_string_key(references, quest_id, "hint text_key", definition.text_key, true); problem != "" {
		return {}, problem
	}
	hint.threshold, hint.text_key = u64(definition.threshold), definition.text_key
	return hint, ""
}

resolve_reward_recipe :: proc(name: string, references: Quest_References, quest_id: string) -> (recipe: int, problem: string) {
	recipe = find_recipe(references.recipes, name)
	if recipe == NO_RECIPE {
		return NO_RECIPE, fmt.tprintf("quest %q unlocks unknown recipe %q", quest_id, name)
	}
	if references.recipes.recipes[recipe].channel != .Quest {
		return NO_RECIPE, fmt.tprintf("quest %q unlocks recipe %q, whose channel is not quest", quest_id, name)
	}
	return recipe, ""
}

resolve_reward_item :: proc(definition: Reward_Definition, references: Quest_References, quest_id: string) -> (stack: Item_Stack, problem: string) {
	item, found := find_item_id(references.items, definition.item)
	if !found {
		return EMPTY_STACK, fmt.tprintf("quest %q rewards unknown item %q", quest_id, definition.item)
	}
	if definition.count < 1 || definition.count > MAXIMUM_STACK_SIZE * CAPSULE_SLOT_COUNT {
		return EMPTY_STACK, fmt.tprintf("quest %q rewards %d of %q", quest_id, definition.count, definition.item)
	}
	return Item_Stack{item = item, count = u16(definition.count)}, ""
}

resolve_reward_technology :: proc(name: string, references: Quest_References, quest_id: string) -> (technology: int, problem: string) {
	technology = find_technology(references.technologies, name)
	if technology == NO_TECHNOLOGY {
		return NO_TECHNOLOGY, fmt.tprintf("quest %q unlocks unknown technology %q", quest_id, name)
	}
	return technology, ""
}

reward_kind_count :: proc(definition: Reward_Definition) -> int {
	count := 0
	for field in ([3]string{definition.item, definition.unlocks_recipe, definition.unlocks_technology}) {
		count += field != "" ? 1 : 0
	}
	return count
}

Reward_Lists :: struct {
	items:        [dynamic]Item_Stack,
	recipes:      [dynamic]int,
	technologies: [dynamic]int,
}

append_reward :: proc(lists: ^Reward_Lists, definition: Reward_Definition, references: Quest_References, quest_id: string) -> (problem: string) {
	switch {
	case definition.item != "":
		stack: Item_Stack
		if stack, problem = resolve_reward_item(definition, references, quest_id); problem == "" {
			append(&lists.items, stack)
		}
	case definition.unlocks_recipe != "":
		recipe: int
		if recipe, problem = resolve_reward_recipe(definition.unlocks_recipe, references, quest_id); problem == "" {
			append(&lists.recipes, recipe)
		}
	case:
		technology: int
		if technology, problem = resolve_reward_technology(definition.unlocks_technology, references, quest_id); problem == "" {
			append(&lists.technologies, technology)
		}
	}
	return problem
}

resolve_rewards :: proc(quest: ^Quest, definitions: []Reward_Definition, references: Quest_References, allocator := context.allocator) -> string {
	lists := Reward_Lists {
		items        = make([dynamic]Item_Stack, allocator),
		recipes      = make([dynamic]int, allocator),
		technologies = make([dynamic]int, allocator),
	}
	defer quest.reward_items, quest.reward_recipes, quest.reward_technologies = lists.items[:], lists.recipes[:], lists.technologies[:]
	for definition in definitions {
		if reward_kind_count(definition) != 1 {
			return fmt.tprintf("quest %q has a reward that is not exactly one of item, unlocks_recipe or unlocks_technology", quest.id)
		}
		if problem := append_reward(&lists, definition, references, quest.id); problem != "" {
			return problem
		}
	}
	return ""
}

check_quest_keys :: proc(definition: Quest_Definition, references: Quest_References) -> string {
	keys := [4]string{definition.title_key, definition.text_key, definition.message_key, definition.complete_key}
	fields := [4]string{"title_key", "text_key", "message_key", "complete_key"}
	for key, index in keys {
		if problem := check_string_key(references, definition.id, fields[index], key, index < 2); problem != "" {
			return problem
		}
	}
	return ""
}

resolve_quest_lists :: proc(quest: ^Quest, definition: Quest_Definition, references: Quest_References, allocator := context.allocator) -> string {
	if len(definition.objectives) > MAXIMUM_QUEST_OBJECTIVES || len(definition.hints) > MAXIMUM_QUEST_HINTS {
		return fmt.tprintf("quest %q has more than %d objectives or %d hints", definition.id, MAXIMUM_QUEST_OBJECTIVES, MAXIMUM_QUEST_HINTS)
	}
	quest.objectives = make([]Objective, len(definition.objectives), allocator)
	quest.hints = make([]Hint, len(definition.hints), allocator)
	problem: string
	for objective_definition, index in definition.objectives {
		if quest.objectives[index], problem = resolve_objective(objective_definition, references, definition.id); problem != "" {
			return problem
		}
	}
	for hint_definition, index in definition.hints {
		if quest.hints[index], problem = resolve_hint(hint_definition, references, definition.id); problem != "" {
			return problem
		}
	}
	return resolve_rewards(quest, definition.rewards, references, allocator)
}

resolve_quest :: proc(definition: Quest_Definition, chapter: int, references: Quest_References, allocator := context.allocator) -> (quest: Quest, problem: string) {
	if definition.id == "" {
		return {}, fmt.tprintf("a quest of chapter %d has no id", chapter + 1)
	}
	if problem = check_quest_keys(definition, references); problem != "" {
		return {}, problem
	}
	quest = Quest {
		id           = definition.id,
		chapter      = chapter,
		title_key    = definition.title_key,
		text_key     = definition.text_key,
		message_key  = definition.message_key,
		complete_key = definition.complete_key,
		main         = definition.main,
	}
	problem = resolve_quest_lists(&quest, definition, references, allocator)
	return quest, problem
}

validate_chapter_file :: proc(file: Chapter_File, references: Quest_References) -> string {
	if file.id == "" {
		return "a quest chapter has no id"
	}
	if problem := check_string_key(references, file.id, "title_key", file.title_key, true); problem != "" {
		return problem
	}
	if len(file.quests) == 0 {
		return fmt.tprintf("quest chapter %q has no quests", file.id)
	}
	main_count := 0
	for quest in file.quests {
		main_count += quest.main ? 1 : 0
	}
	if main_count > 1 {
		return fmt.tprintf("quest chapter %q has %d main quests", file.id, main_count)
	}
	return ""
}

quest_id_taken :: proc(quests: []Quest, id: string) -> bool {
	for quest in quests {
		if quest.id == id {
			return true
		}
	}
	return false
}

append_chapter :: proc(chapters: ^[dynamic]Chapter, quests: ^[dynamic]Quest, file: Chapter_File, references: Quest_References, allocator := context.allocator) -> string {
	if problem := validate_chapter_file(file, references); problem != "" {
		return problem
	}
	chapter := len(chapters)
	append(chapters, Chapter{id = file.id, title_key = file.title_key, first_quest = len(quests), quest_count = len(file.quests)})
	for definition in file.quests {
		if quest_id_taken(quests[:], definition.id) {
			return fmt.tprintf("quest id %q is defined twice", definition.id)
		}
		quest, problem := resolve_quest(definition, chapter, references, allocator)
		if problem != "" {
			return problem
		}
		append(quests, quest)
	}
	return ""
}

// Chapters play in the order given. Nothing is freed on failure: loading
// failure ends the game, and tests use the temp allocator.
resolve_quest_registry :: proc(files: []Chapter_File, references: Quest_References, allocator := context.allocator) -> (registry: Quest_Registry, problem: string) {
	chapters := make([dynamic]Chapter, allocator)
	quests := make([dynamic]Quest, allocator)
	for file in files {
		if problem = append_chapter(&chapters, &quests, file, references, allocator); problem != "" {
			return {}, problem
		}
	}
	return Quest_Registry{chapters = chapters[:], quests = quests[:]}, ""
}

quest_file_names :: proc(directory: string, allocator := context.allocator) -> (names: []string, ok: bool) {
	entries, error := os.read_all_directory_by_path(directory, context.temp_allocator)
	if error != nil {
		log_printf("error: cannot read %s: %v", directory, error)
		return nil, false
	}
	found := make([dynamic]string, allocator)
	for entry in entries {
		if entry.type == .Regular && strings.has_suffix(entry.name, QUEST_FILE_EXTENSION) {
			append(&found, strings.clone(entry.name, allocator))
		}
	}
	slice.sort(found[:])
	return found[:], true
}

load_chapter_file :: proc(directory, name: string, allocator := context.allocator) -> (file: Chapter_File, ok: bool) {
	data, path := read_data_file(directory, name) or_return
	parse_error: json.Unmarshal_Error
	file, parse_error = parse_chapter_file(data, allocator)
	if parse_error != nil {
		log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	return file, true
}

load_quest_registry :: proc(data_directory: string, references: Quest_References, allocator := context.allocator) -> (registry: Quest_Registry, ok: bool) {
	directory, join_error := os.join_path({data_directory, QUESTS_DIRECTORY}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	names := quest_file_names(directory, context.temp_allocator) or_return
	files := make([]Chapter_File, len(names), allocator)
	for name, index in names {
		files[index] = load_chapter_file(directory, name, allocator) or_return
	}
	problem: string
	if registry, problem = resolve_quest_registry(files, references, allocator); problem != "" {
		log_printf("error: invalid quest data in %s: %s", directory, problem)
		return {}, false
	}
	return registry, true
}
