package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"

// Technologies from data/technologies.sjson, resolved after the recipes:
// an id, a name, a cost in units of science packs, the research recipes it
// unlocks and the technologies it needs first. Labs research them
// (lab.odin).

TECHNOLOGIES_FILE_NAME :: "technologies.sjson"

Technology_Definition :: struct {
	id:            string,
	name_key:      string,
	unlocks:       []string,
	packs:         int,
	seconds:       f32,
	science_packs: []string,
	prerequisites: []string,
	placeholder:   bool,
}

Technologies_File :: struct {
	technologies: []Technology_Definition,
}

// unlocks holds recipe indices, prerequisites technology indices (all
// lower than this one's). A unit consumes one of each science pack item
// and takes milliseconds_per_pack in a speed 1 lab; pack_count units
// complete the technology.
Technology :: struct {
	id:                    string,
	name_key:              string,
	unlocks:               []int,
	pack_count:            int,
	milliseconds_per_pack: u32,
	science_packs:         []Item_Id,
	prerequisites:         []int,
	placeholder:           bool,
}

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
	case len(definition.unlocks) == 0 && !definition.placeholder:
		return fmt.tprintf("technology %q unlocks nothing; mark it placeholder = true if that is intended", definition.id)
	case len(definition.science_packs) == 0:
		return fmt.tprintf("technology %q names no science_packs", definition.id)
	}
	return validate_technology_prerequisites(definitions, index)
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
		id                    = definition.id,
		name_key              = definition.name_key,
		pack_count            = definition.packs,
		milliseconds_per_pack = u32(math.round(definition.seconds * 1000)),
		placeholder           = definition.placeholder,
	}
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

load_technology_registry :: proc(data_directory: string, items: Item_Registry, recipes: Recipe_Registry, allocator := context.allocator) -> (registry: Technology_Registry, ok: bool) {
	path, join_error := os.join_path({data_directory, TECHNOLOGIES_FILE_NAME}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	file, parse_error := parse_technologies_file(data, allocator)
	if parse_error != nil {
		fmt.eprintfln("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	registry, problem = resolve_technology_registry(file, items, recipes, allocator)
	if problem != "" {
		fmt.eprintfln("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}
