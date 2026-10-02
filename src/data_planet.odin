package game

import "core:encoding/json"
import "core:fmt"
import "core:reflect"
import "platform"

// The planet records of data/planets.sjson (work item 0168,
// doc/content.md, Planets). Held to the configuration's strict keys, so an
// unknown key or a wrong type is an error naming the key, and every field
// is required: a record without one is refused with the field's name.

PLANETS_FILE_NAME :: "planets.sjson"
// Keeps the squared distances of generation (generation_planet.odin) far
// inside i64.
MAXIMUM_PLANET_RADIUS_METRES :: 100_000
MAXIMUM_SURFACE_GRAVITY_CENTIMETRES_PER_SECOND_SQUARED :: 5000
MINIMUM_ROTATION_PERIOD_SECONDS :: 60
MAXIMUM_ROTATION_PERIOD_SECONDS :: 86_400
// Bedrock lies below every local surface's deep stone, so a valley at the
// lowest relief never shows bedrock in place of topsoil.
MINIMUM_BEDROCK_DEPTH_METRES :: int(MAXIMUM_RELIEF_METRES + DEEP_STONE_DEPTH_METRES)
MAXIMUM_PALETTE_LENGTH :: 256
MAXIMUM_COLOR_COMPONENT :: 255

Planet :: struct {
	id:                                             string,
	radius_metres:                                  int,
	surface_gravity_centimetres_per_second_squared: int,
	// Below the radius (the mean surface), where bedrock starts.
	bedrock_depth_metres:                           int,
	// Above the radius; negative lies below it.
	sea_level_metres:                               int,
	rotation_period_seconds:                        int,
	// Red, green, blue from 0 to 255; a sample's tint is an index into it.
	palette:                                        [][3]int,
}

Planets_File :: struct {
	planets: []Planet,
}

// The first of type's keys that object lacks.
missing_struct_key :: proc(type: typeid, object: json.Object) -> (key: string, missing: bool) {
	for index in 0 ..< reflect.struct_field_count(type) {
		field := reflect.struct_field_at(type, index)
		key = configuration_key(field.name, field.tag)
		if key not_in object {
			return key, true
		}
	}
	return "", false
}

// The tree passed the typed assignment, so planets is an array.
missing_planet_key_problem :: proc(tree: json.Object, source: string) -> string {
	if key, missing := missing_struct_key(Planets_File, tree); missing {
		return fmt.tprintf("%s: missing key %s", source, key)
	}
	for record, index in tree["planets"].(json.Array) {
		if key, missing := missing_struct_key(Planet, record.(json.Object)); missing {
			return fmt.tprintf("%s: planets[%d] is missing %s", source, index, key)
		}
	}
	return ""
}

palette_problem :: proc(palette: [][3]int) -> string {
	if len(palette) < 1 || len(palette) > MAXIMUM_PALETTE_LENGTH {
		return fmt.tprintf("palette has %d colours, not 1 to %d", len(palette), MAXIMUM_PALETTE_LENGTH)
	}
	for color, index in palette {
		for component in color {
			if component < 0 || component > MAXIMUM_COLOR_COMPONENT {
				return fmt.tprintf("palette[%d] has %d, outside 0 to %d", index, component, MAXIMUM_COLOR_COMPONENT)
			}
		}
	}
	return ""
}

planet_problem :: proc(planet: Planet) -> string {
	switch {
	case planet.id == "":
		return "id is empty"
	case planet.radius_metres < 1 || planet.radius_metres > MAXIMUM_PLANET_RADIUS_METRES:
		return fmt.tprintf("radius_metres %d is outside 1 to %d", planet.radius_metres, MAXIMUM_PLANET_RADIUS_METRES)
	case planet.surface_gravity_centimetres_per_second_squared < 1 || planet.surface_gravity_centimetres_per_second_squared > MAXIMUM_SURFACE_GRAVITY_CENTIMETRES_PER_SECOND_SQUARED:
		return fmt.tprintf("surface_gravity_centimetres_per_second_squared %d is outside 1 to %d", planet.surface_gravity_centimetres_per_second_squared, MAXIMUM_SURFACE_GRAVITY_CENTIMETRES_PER_SECOND_SQUARED)
	case planet.bedrock_depth_metres < MINIMUM_BEDROCK_DEPTH_METRES || planet.bedrock_depth_metres >= planet.radius_metres:
		return fmt.tprintf("bedrock_depth_metres %d is outside %d to %d", planet.bedrock_depth_metres, MINIMUM_BEDROCK_DEPTH_METRES, planet.radius_metres - 1)
	case abs(planet.sea_level_metres) >= planet.radius_metres:
		return fmt.tprintf("sea_level_metres %d is not within the radius %d", planet.sea_level_metres, planet.radius_metres)
	case planet.rotation_period_seconds < MINIMUM_ROTATION_PERIOD_SECONDS || planet.rotation_period_seconds > MAXIMUM_ROTATION_PERIOD_SECONDS:
		return fmt.tprintf("rotation_period_seconds %d is outside %d to %d", planet.rotation_period_seconds, MINIMUM_ROTATION_PERIOD_SECONDS, MAXIMUM_ROTATION_PERIOD_SECONDS)
	}
	return palette_problem(planet.palette)
}

planets_problem :: proc(planets: []Planet) -> string {
	if len(planets) == 0 {
		return "planets is empty"
	}
	for planet, index in planets {
		if problem := planet_problem(planet); problem != "" {
			return fmt.tprintf("planets[%d] (%q): %s", index, planet.id, problem)
		}
		if _, found := find_planet(planets[:index], planet.id); found {
			return fmt.tprintf("planets[%d]: id %q is used twice", index, planet.id)
		}
	}
	return ""
}

// source names the file in the problem. The ids and palettes go into
// allocator.
parse_planets_file :: proc(data: []byte, source: string, allocator := context.allocator) -> (planets: []Planet, problem: string) {
	tree, parse_problem := parse_configuration_layer(data, source, context.temp_allocator)
	if parse_problem != "" {
		return nil, parse_problem
	}
	provenance := make(Configuration_Provenance, context.temp_allocator)
	provenance[""] = source
	file: Planets_File
	if problem = assign_configuration_value(any{&file, typeid_of(Planets_File)}, json.Value(tree), "", provenance, allocator); problem != "" {
		return nil, problem
	}
	if problem = missing_planet_key_problem(tree, source); problem != "" {
		return nil, problem
	}
	if problem = planets_problem(file.planets); problem != "" {
		return nil, fmt.tprintf("%s: %s", source, problem)
	}
	return file.planets, ""
}

load_planets :: proc(data_directory: string, allocator := context.allocator) -> (planets: []Planet, ok: bool) {
	data, path := read_logged_data_file(data_directory, PLANETS_FILE_NAME) or_return
	problem: string
	if planets, problem = parse_planets_file(data, path, allocator); problem != "" {
		platform.log_printf("error: invalid %s", problem)
		return nil, false
	}
	return planets, true
}

find_planet :: proc(planets: []Planet, id: string) -> (planet: Planet, found: bool) {
	for candidate in planets {
		if candidate.id == id {
			return candidate, true
		}
	}
	return {}, false
}
