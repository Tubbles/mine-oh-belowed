package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"

// Technologies from data/technologies.sjson, resolved after the recipes:
// an id, a name, a cost in units of science packs, the research recipes it
// unlocks and the technologies it needs first. Labs research them
// (lab.odin).

TECHNOLOGIES_FILE_NAME :: "technologies.sjson"
// The research state keeps every technology's progress in a fixed array,
// so the world needs no allocation for it.
MAXIMUM_TECHNOLOGIES :: 64

Technology_Definition :: struct {
	id:                        string,
	name_key:                  string,
	description_key:           string,
	unlocks:                   []string,
	packs:                     int,
	seconds:                   f32,
	science_packs:             []string,
	prerequisites:             []string,
	placeholder:               bool,
	quest_gate:                bool,
	// Work item 0041: a repeatable technology with an effect per level.
	infinite:                  bool,
	level_cost_growth_percent: int,
	effect:                    string,
	effect_percent:            int,
}

Technologies_File :: struct {
	technologies: []Technology_Definition,
}

// unlocks holds recipe indices, prerequisites technology indices (all
// lower than this one's). A unit consumes one of each science pack item
// and takes milliseconds_per_pack in a speed 1 lab; pack_count units
// complete the technology. A quest_gate technology is only ever marked
// researched by a main quest reward; labs refuse it. An infinite
// technology is researched level after level (Research_State.levels):
// level n costs pack_count times level_cost_growth_percent to the power n
// minus one, and every level adds effect_percent to its effect.
// description_key is the string the technology screen shows under the
// cost, "" for none (work item 0070).
Technology :: struct {
	id:                        string,
	name_key:                  string,
	description_key:           string,
	unlocks:                   []int,
	pack_count:                int,
	milliseconds_per_pack:     u32,
	science_packs:             []Item_Id,
	prerequisites:             []int,
	placeholder:               bool,
	quest_gate:                bool,
	infinite:                  bool,
	level_cost_growth_percent: u32,
	effect:                    Technology_Effect,
	effect_percent:            u32,
}

// What a level of an infinite technology improves: every drill's output
// (drill.odin) or every lab's speed (lab.odin).
Technology_Effect :: enum u8 {
	None,
	Mining_Productivity,
	Research_Speed,
}

@(rodata)
technology_effect_names := [Technology_Effect]string {
	.None                = "",
	.Mining_Productivity = "mining_productivity",
	.Research_Speed      = "research_speed",
}

// A level cost stops growing here, so the arithmetic never overflows.
MAXIMUM_LEVEL_COST :: 1_000_000_000
LEVEL_COST_RESCALE :: u128(1) << 64
LEVEL_COST_RESCALE_STEP :: u128(1) << 32

// science_packs is every distinct pack item any technology consumes, in
// order of first appearance: the lab's slots.
Technology_Registry :: struct {
	technologies:  []Technology,
	science_packs: []Item_Id,
}

parse_technologies_file :: proc(data: []byte, allocator := context.allocator) -> (file: Technologies_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

find_technology_definition_index :: proc(definitions: []Technology_Definition, id: string) -> int {
	for definition, index in definitions {
		if definition.id == id {
			return index
		}
	}
	return -1
}

validate_technology_definition :: proc(definitions: []Technology_Definition, index: int) -> string {
	definition := definitions[index]
	switch {
	case definition.id == "":
		return fmt.tprintf("technology %d has no id", index)
	case find_technology_definition_index(definitions, definition.id) != index:
		return fmt.tprintf("technology id %q is defined twice", definition.id)
	case definition.name_key == "":
		return fmt.tprintf("technology %q has no name_key", definition.id)
	case definition.packs < 1 || definition.seconds <= 0:
		return fmt.tprintf("technology %q needs positive packs and seconds", definition.id)
	case len(definition.unlocks) == 0 && !definition.placeholder && !definition.infinite:
		return fmt.tprintf("technology %q unlocks nothing; mark it placeholder = true if that is intended", definition.id)
	case len(definition.science_packs) == 0:
		return fmt.tprintf("technology %q names no science_packs", definition.id)
	}
	if problem := validate_technology_levels(definition); problem != "" {
		return problem
	}
	return validate_technology_prerequisites(definitions, index)
}

// An infinite technology grows its cost by at least 100 percent a level
// and has an effect; any other names neither.
validate_technology_levels :: proc(definition: Technology_Definition) -> string {
	effect, found := parse_named_enum(technology_effect_names, definition.effect)
	if !definition.infinite {
		if definition.level_cost_growth_percent != 0 || definition.effect != "" || definition.effect_percent != 0 {
			return fmt.tprintf("technology %q is not infinite and may not name level_cost_growth_percent, effect or effect_percent", definition.id)
		}
		return ""
	}
	switch {
	case definition.placeholder || definition.quest_gate:
		return fmt.tprintf("infinite technology %q cannot be a placeholder or a quest gate", definition.id)
	case definition.level_cost_growth_percent < 100:
		return fmt.tprintf("infinite technology %q needs level_cost_growth_percent of at least 100", definition.id)
	case !found || effect == .None:
		return fmt.tprintf("infinite technology %q has unknown effect %q", definition.id, definition.effect)
	case definition.effect_percent < 1:
		return fmt.tprintf("infinite technology %q needs a positive effect_percent", definition.id)
	}
	return ""
}

// Every prerequisite is listed earlier in the file, so the graph has no
// cycles.
validate_technology_prerequisites :: proc(definitions: []Technology_Definition, index: int) -> string {
	definition := definitions[index]
	for prerequisite in definition.prerequisites {
		found := find_technology_definition_index(definitions, prerequisite)
		switch {
		case found < 0:
			return fmt.tprintf("technology %q needs unknown technology %q", definition.id, prerequisite)
		case found >= index:
			return fmt.tprintf("technology %q needs %q, which must be listed before it", definition.id, prerequisite)
		}
	}
	return ""
}

resolve_technology_prerequisites :: proc(definitions: []Technology_Definition, definition: Technology_Definition, allocator := context.allocator) -> []int {
	prerequisites := make([]int, len(definition.prerequisites), allocator)
	for prerequisite, index in definition.prerequisites {
		prerequisites[index] = find_technology_definition_index(definitions, prerequisite)
	}
	return prerequisites
}

resolve_science_packs :: proc(definition: Technology_Definition, items: Item_Registry, allocator := context.allocator) -> (packs: []Item_Id, problem: string) {
	packs = make([]Item_Id, len(definition.science_packs), allocator)
	for name, index in definition.science_packs {
		item, found := find_item_id(items, name)
		switch {
		case !found:
			problem = fmt.tprintf("technology %q consumes unknown item %q", definition.id, name)
		case slice_contains_item(packs[:index], item):
			problem = fmt.tprintf("technology %q lists %q twice", definition.id, name)
		}
		if problem != "" {
			delete(packs, allocator)
			return nil, problem
		}
		packs[index] = item
	}
	return packs, ""
}

// The lab slots: distinct pack items in order of first appearance.
collect_science_packs :: proc(technologies: []Technology, allocator := context.allocator) -> (packs: []Item_Id, problem: string) {
	found := make([dynamic]Item_Id, allocator)
	for technology in technologies {
		for pack in technology.science_packs {
			if !slice_contains_item(found[:], pack) {
				append(&found, pack)
			}
		}
	}
	if len(found) > MAXIMUM_LAB_SLOTS {
		delete(found)
		return nil, fmt.tprintf("technologies use %d science pack items, a lab has %d slots", len(found), MAXIMUM_LAB_SLOTS)
	}
	return found[:], ""
}

// Each unlocked recipe must be a research recipe that names this technology.
resolve_technology_unlocks :: proc(definition: Technology_Definition, recipes: Recipe_Registry, allocator := context.allocator) -> (unlocks: []int, problem: string) {
	unlocks = make([]int, len(definition.unlocks), allocator)
	for recipe_id, index in definition.unlocks {
		recipe := find_recipe(recipes, recipe_id)
		switch {
		case recipe == NO_RECIPE:
			problem = fmt.tprintf("technology %q unlocks unknown recipe %q", definition.id, recipe_id)
		case recipes.recipes[recipe].technology_id != definition.id:
			problem = fmt.tprintf("technology %q unlocks %q, which does not name it as its research technology", definition.id, recipe_id)
		}
		if problem != "" {
			delete(unlocks, allocator)
			return nil, problem
		}
		unlocks[index] = recipe
	}
	return unlocks, ""
}

// Fills in the technology index of every research recipe; a research
// recipe that no technology lists is an error.
link_recipe_technologies :: proc(recipes: Recipe_Registry, technologies: []Technology) -> string {
	for &recipe in recipes.recipes {
		recipe.technology = NO_TECHNOLOGY
	}
	for technology, technology_index in technologies {
		for recipe in technology.unlocks {
			recipes.recipes[recipe].technology = technology_index
		}
	}
	for recipe in recipes.recipes {
		if recipe.channel == .Research && recipe.technology == NO_TECHNOLOGY {
			return fmt.tprintf("research recipe %q names technology %q, which does not list it", recipe.id, recipe.technology_id)
		}
	}
	return ""
}

resolve_technology :: proc(definitions: []Technology_Definition, index: int, items: Item_Registry, recipes: Recipe_Registry, allocator := context.allocator) -> (technology: Technology, problem: string) {
	definition := definitions[index]
	if problem = validate_technology_definition(definitions, index); problem != "" {
		return {}, problem
	}
	technology = Technology {
		id                        = definition.id,
		name_key                  = definition.name_key,
		description_key           = definition.description_key,
		pack_count                = definition.packs,
		milliseconds_per_pack     = u32(math.round(definition.seconds * 1000)),
		placeholder               = definition.placeholder,
		quest_gate                = definition.quest_gate,
		infinite                  = definition.infinite,
		level_cost_growth_percent = u32(definition.level_cost_growth_percent),
		effect_percent            = u32(definition.effect_percent),
	}
	technology.effect, _ = parse_named_enum(technology_effect_names, definition.effect)
	if technology.unlocks, problem = resolve_technology_unlocks(definition, recipes, allocator); problem != "" {
		return {}, problem
	}
	if technology.science_packs, problem = resolve_science_packs(definition, items, allocator); problem != "" {
		delete(technology.unlocks, allocator)
		return {}, problem
	}
	technology.prerequisites = resolve_technology_prerequisites(definitions, definition, allocator)
	return technology, ""
}

// Validates the file against the items and recipes and links the recipes
// both ways. Changes the recipes' technology indices.
resolve_technology_registry :: proc(file: Technologies_File, items: Item_Registry, recipes: Recipe_Registry, allocator := context.allocator) -> (registry: Technology_Registry, problem: string) {
	if len(file.technologies) > MAXIMUM_TECHNOLOGIES {
		return {}, fmt.tprintf("%d technologies, at most %d are supported", len(file.technologies), MAXIMUM_TECHNOLOGIES)
	}
	registry.technologies = make([]Technology, len(file.technologies), allocator)
	for _, index in file.technologies {
		if registry.technologies[index], problem = resolve_technology(file.technologies, index, items, recipes, allocator); problem != "" {
			destroy_technology_registry(registry, allocator)
			return {}, problem
		}
	}
	if registry.science_packs, problem = collect_science_packs(registry.technologies, allocator); problem != "" {
		destroy_technology_registry(registry, allocator)
		return {}, problem
	}
	if problem = link_recipe_technologies(recipes, registry.technologies); problem != "" {
		destroy_technology_registry(registry, allocator)
		return {}, problem
	}
	return registry, ""
}

destroy_technology_registry :: proc(registry: Technology_Registry, allocator := context.allocator) {
	for technology in registry.technologies {
		delete(technology.unlocks, allocator)
		delete(technology.science_packs, allocator)
		delete(technology.prerequisites, allocator)
	}
	delete(registry.technologies, allocator)
	delete(registry.science_packs, allocator)
}

technology_name :: proc(registry: Technology_Registry, technology: int) -> string {
	if technology < 0 || technology >= len(registry.technologies) {
		return ""
	}
	return text(registry.technologies[technology].name_key)
}

validate_technology_description_keys :: proc(registry: Technology_Registry, strings: map[string]string) -> string {
	for technology in registry.technologies {
		if problem := description_key_problem(strings, "technology", technology.id, technology.description_key); problem != "" {
			return problem
		}
	}
	return ""
}

// The technology's description, "" for none.
technology_description :: proc(registry: Technology_Registry, technology: int) -> string {
	if technology < 0 || technology >= len(registry.technologies) || registry.technologies[technology].description_key == "" {
		return ""
	}
	return text(registry.technologies[technology].description_key)
}

load_technology_registry :: proc(data_directory: string, items: Item_Registry, recipes: Recipe_Registry, allocator := context.allocator) -> (registry: Technology_Registry, ok: bool) {
	path, join_error := os.join_path({data_directory, TECHNOLOGIES_FILE_NAME}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		log_printf("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	file, parse_error := parse_technologies_file(data, allocator)
	if parse_error != nil {
		log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	registry, problem = resolve_technology_registry(file, items, recipes, allocator)
	if problem != "" {
		log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}

// The world setting "research cost multiplier": a pack count times the
// percent, rounded up, and at least one.
scaled_pack_count :: proc(pack_count, percent: int) -> int {
	return max((pack_count * percent + 99) / 100, 1)
}

// A copy of the registry with every pack count scaled, for one world. The
// other slices are shared with the base registry; only the technologies
// slice is new.
scaled_technology_registry :: proc(base: Technology_Registry, percent: int, allocator := context.allocator) -> Technology_Registry {
	registry := base
	registry.technologies = slice.clone(base.technologies, allocator)
	for &technology in registry.technologies {
		technology.pack_count = scaled_pack_count(technology.pack_count, percent)
	}
	return registry
}

greatest_common_divisor :: proc(first, second: u64) -> u64 {
	a, b := first, second
	for b != 0 {
		a, b = b, a % b
	}
	return a
}

// Level n of an infinite technology costs pack_count times the growth to
// the power n minus one, rounded down and capped at MAXIMUM_LEVEL_COST.
// The growth is reduced to a fraction first (150 percent is 3 over 2), so
// the powers stay small; the result is exact while the denominator's
// power fits 64 bits and approximate beyond, which only a growth with a
// large reduced denominator reaches before the cap. A technology that is
// not infinite always costs pack_count.
technology_level_cost :: proc(technology: Technology, level: u32) -> int {
	if !technology.infinite || level <= 1 {
		return technology.pack_count
	}
	divisor := greatest_common_divisor(u64(technology.level_cost_growth_percent), 100)
	numerator, denominator := u128(technology.level_cost_growth_percent) / u128(divisor), u128(100) / u128(divisor)
	cost, scale := u128(technology.pack_count), u128(1)
	for _ in 1 ..< level {
		cost *= numerator
		scale *= denominator
		if scale > LEVEL_COST_RESCALE {
			cost, scale = cost / LEVEL_COST_RESCALE_STEP, scale / LEVEL_COST_RESCALE_STEP
		}
		if cost / scale >= MAXIMUM_LEVEL_COST {
			return MAXIMUM_LEVEL_COST
		}
	}
	return int(cost / scale)
}

// The units the next research of a technology takes: its cost, or for an
// infinite one the cost of the level after those done.
technology_next_cost :: proc(technology: Technology, levels: [MAXIMUM_TECHNOLOGIES]u32, index: int) -> int {
	return technology_level_cost(technology, levels[index] + 1)
}

// The sum of every infinite technology's effect per level times its
// levels, in per mille (10 percent is 100).
technology_effect_per_mille :: proc(technologies: Technology_Registry, levels: [MAXIMUM_TECHNOLOGIES]u32, effect: Technology_Effect) -> u32 {
	total: u32
	for technology, index in technologies.technologies {
		if technology.infinite && technology.effect == effect {
			total += levels[index] * technology.effect_percent * 10
		}
	}
	return total
}
