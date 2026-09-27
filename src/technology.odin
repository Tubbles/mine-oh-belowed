package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"

// Technologies from data/technologies.sjson, resolved after the recipes.
// Labs come with M4, so for now a technology is only an id, a name, a cost
// and the research recipes it unlocks.

TECHNOLOGIES_FILE_NAME :: "technologies.sjson"

Technology_Definition :: struct {
	id:       string,
	name_key: string,
	unlocks:  []string,
	packs:    int,
	seconds:  f32,
}

Technologies_File :: struct {
	technologies: []Technology_Definition,
}

// unlocks holds recipe indices. Time per pack in milliseconds.
Technology :: struct {
	id:                    string,
	name_key:              string,
	unlocks:               []int,
	pack_count:            int,
	milliseconds_per_pack: u32,
}

Technology_Registry :: struct {
	technologies: []Technology,
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
	}
	return ""
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

// Validates the file against the recipes and links both ways. Changes the
// recipes' technology indices.
resolve_technology_registry :: proc(file: Technologies_File, recipes: Recipe_Registry, allocator := context.allocator) -> (registry: Technology_Registry, problem: string) {
	registry.technologies = make([]Technology, len(file.technologies), allocator)
	for definition, index in file.technologies {
		problem = validate_technology_definition(file.technologies, index)
		unlocks: []int
		if problem == "" {
			unlocks, problem = resolve_technology_unlocks(definition, recipes, allocator)
		}
		if problem != "" {
			destroy_technology_registry(registry, allocator)
			return {}, problem
		}
		registry.technologies[index] = Technology {
			id                    = definition.id,
			name_key              = definition.name_key,
			unlocks               = unlocks,
			pack_count            = definition.packs,
			milliseconds_per_pack = u32(math.round(definition.seconds * 1000)),
		}
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
	}
	delete(registry.technologies, allocator)
}

technology_name :: proc(registry: Technology_Registry, technology: int) -> string {
	if technology < 0 || technology >= len(registry.technologies) {
		return ""
	}
	return text(registry.technologies[technology].name_key)
}

load_technology_registry :: proc(data_directory: string, recipes: Recipe_Registry, allocator := context.allocator) -> (registry: Technology_Registry, ok: bool) {
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
	registry, problem = resolve_technology_registry(file, recipes, allocator)
	if problem != "" {
		fmt.eprintfln("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}
