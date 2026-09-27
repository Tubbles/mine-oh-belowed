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

// walk is not in doc/quests.md's table; chapter 1's "get your bearings"
// needs it.
Objective_Type :: enum u8 {
	Obtain,
	Craft,
	Place,
	Sustain,
	Research,
	Deliver,
	Discover,
	Walk,
}

@(rodata)
objective_type_names := [Objective_Type]string {
	.Obtain   = "obtain",
	.Craft    = "craft",
	.Place    = "place",
	.Sustain  = "sustain",
	.Research = "research",
	.Deliver  = "deliver",
	.Discover = "discover",
	.Walk     = "walk",
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
}

@(rodata)
hint_counter_names := [Hint_Counter]string {
	.Blocks_Mined         = "blocks_mined",
	.Mining_Ticks         = "mining_ticks",
	.Distance_Walked      = "distance_walked",
	.Furnace_Out_Of_Fuel  = "furnace_out_of_fuel",
	.Furnace_Output_Full  = "furnace_output_full",
	.Fuel_Burned          = "fuel_burned",
	.Inventory_Full_Ticks = "inventory_full_ticks",
}

// As written in the files, before references are resolved.
Objective_Definition :: struct {
	type:            string,
	item:            string,
	entity:          string,
	recipe:          string,
	technology:      string,
	count:           int,
	rate_per_minute: int,
	minutes:         int,
	hands_off:       bool,
}

Hint_Definition :: struct {
	counter:   string,
	block:     string,
	threshold: int,
	text_key:  string,
}

// Either an item and a count, or unlocks_recipe.
Reward_Definition :: struct {
	item:           string,
	count:          int,
	unlocks_recipe: string,
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

// count is items, placements or blocks walked. Unused references are
// NO_ITEM, NO_MACHINE, NO_RECIPE, NO_TECHNOLOGY.
Objective :: struct {
	type:            Objective_Type,
	item:            Item_Id,
	machine:         Machine_Id,
	recipe:          int,
	technology:      int,
	count:           u64,
	rate_per_minute: u64,
	minutes:         u64,
	hands_off:       bool,
}

// threshold counts from the value when the quest became active.
Hint :: struct {
	counter:   Hint_Counter,
	block:     Block_Id,
	threshold: u64,
	text_key:  string,
}

Quest :: struct {
	id:             string,
	chapter:        int,
	title_key:      string,
	text_key:       string,
	message_key:    string,
	complete_key:   string,
	objectives:     []Objective,
	hints:          []Hint,
	reward_items:   []Item_Stack,
	reward_recipes: []int,
	main:           bool,
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
		found: bool
		if objective.machine, found = find_machine_id(references.machines, definition.entity); !found {
			return fmt.tprintf("quest %q names unknown entity %q", quest_id, definition.entity)
		}
	case .Research:
		if objective.technology = find_technology(references.technologies, definition.technology); objective.technology == NO_TECHNOLOGY {
			return fmt.tprintf("quest %q names unknown technology %q", quest_id, definition.technology)
		}
	case .Discover:
		if objective.recipe = find_recipe(references.recipes, definition.recipe); objective.recipe == NO_RECIPE {
			return fmt.tprintf("quest %q names unknown recipe %q", quest_id, definition.recipe)
		}
	case .Walk:
	}
	return ""
}

objective_needs_count :: proc(type: Objective_Type) -> bool {
	#partial switch type {
	case .Sustain, .Research, .Discover:
		return false
	}
	return true
}

resolve_objective :: proc(definition: Objective_Definition, references: Quest_References, quest_id: string) -> (objective: Objective, problem: string) {
	found: bool
	if objective.type, found = parse_named_enum(objective_type_names, definition.type); !found {
		return {}, fmt.tprintf("quest %q has unknown objective type %q", quest_id, definition.type)
	}
	objective.item, objective.machine = NO_ITEM, NO_MACHINE
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
	objective.count = u64(max(definition.count, 0))
	objective.rate_per_minute = u64(max(definition.rate_per_minute, 0))
	objective.minutes = u64(max(definition.minutes, 0))
	objective.hands_off = definition.hands_off
	return objective, ""
}

resolve_hint :: proc(definition: Hint_Definition, references: Quest_References, quest_id: string) -> (hint: Hint, problem: string) {
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

resolve_rewards :: proc(quest: ^Quest, definitions: []Reward_Definition, references: Quest_References, allocator := context.allocator) -> string {
	items := make([dynamic]Item_Stack, allocator)
	recipes := make([dynamic]int, allocator)
	quest.reward_items, quest.reward_recipes = items[:], recipes[:]
	for definition in definitions {
		if (definition.item == "") == (definition.unlocks_recipe == "") {
			return fmt.tprintf("quest %q has a reward that is not exactly one of item or unlocks_recipe", quest.id)
		}
		if definition.item != "" {
			stack, problem := resolve_reward_item(definition, references, quest.id)
			if problem != "" {
				return problem
			}
			append(&items, stack)
		} else {
			recipe, problem := resolve_reward_recipe(definition.unlocks_recipe, references, quest.id)
			if problem != "" {
				return problem
			}
			append(&recipes, recipe)
		}
		quest.reward_items, quest.reward_recipes = items[:], recipes[:]
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
		fmt.eprintfln("error: cannot read %s: %v", directory, error)
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
		fmt.eprintfln("error: cannot parse %s: %v", path, parse_error)
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
		fmt.eprintfln("error: invalid quest data in %s: %s", directory, problem)
		return {}, false
	}
	return registry, true
}
