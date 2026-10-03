package game

import "core:encoding/json"
import "core:fmt"
import "platform"

// data/lighting.sjson (work item 0173, doc/content.md, Lighting): the
// field light's falloff curve, its dark threshold, its per tick budget and
// the emitters' levels. The world turns it into the per spacing steps
// (make_field_light_tuning, world_field_light.odin).

LIGHTING_FILE_NAME :: "lighting.sjson"
MAXIMUM_FIELD_LIGHT :: 255
MAXIMUM_FALLOFF_BANDS :: 16
MAXIMUM_LIGHT_STEPS_PER_TICK_SETTING :: 1 << 20
MAXIMUM_LIGHT_CHUNK_SEEDS_PER_TICK_SETTING :: 64

Lighting_Emitter :: struct {
	id:    string,
	level: int,
}

Lighting_File :: struct {
	falloff:              []int,
	dark_level:           int,
	steps_per_tick:       int,
	chunk_seeds_per_tick: int,
	emitters:             []Lighting_Emitter,
}

is_power_of_two :: proc(value: int) -> bool {
	return value > 0 && value & (value - 1) == 0
}

// Losses from 1 to 255, falling (or equal) from the darkest band on, so
// a brighter level never spreads dimmer than a darker one: the fill's
// result then does not depend on the order it visits the samples in.
falloff_problem :: proc(falloff: []int) -> string {
	if len(falloff) > MAXIMUM_FALLOFF_BANDS || !is_power_of_two(len(falloff)) {
		return fmt.tprintf("falloff has %d bands, not a power of two from 1 to %d", len(falloff), MAXIMUM_FALLOFF_BANDS)
	}
	for loss, band in falloff {
		if loss < 1 || loss > MAXIMUM_FIELD_LIGHT {
			return fmt.tprintf("falloff[%d] is %d, outside 1 to %d", band, loss, MAXIMUM_FIELD_LIGHT)
		}
		if band > 0 && loss > falloff[band - 1] {
			return fmt.tprintf("falloff[%d] (%d) is above falloff[%d] (%d); the losses fall towards the bright bands", band, loss, band - 1, falloff[band - 1])
		}
	}
	return ""
}

emitters_problem :: proc(emitters: []Lighting_Emitter) -> string {
	for emitter, index in emitters {
		if emitter.id == "" {
			return fmt.tprintf("emitters[%d] has an empty id", index)
		}
		if emitter.level < 1 || emitter.level > MAXIMUM_FIELD_LIGHT {
			return fmt.tprintf("emitters[%d] (%s) has level %d, outside 1 to %d", index, emitter.id, emitter.level, MAXIMUM_FIELD_LIGHT)
		}
		for earlier in emitters[:index] {
			if earlier.id == emitter.id {
				return fmt.tprintf("emitters[%d]: %s is listed twice", index, emitter.id)
			}
		}
	}
	return ""
}

// The emitters the game names: the torch and, until its machine record
// carries it (0179), the lamp.
REQUIRED_LIGHTING_EMITTERS :: [2]string{"torch", "lamp"}

lighting_problem :: proc(lighting: Lighting_File) -> string {
	switch {
	case lighting.dark_level < 0 || lighting.dark_level >= MAXIMUM_FIELD_LIGHT:
		return fmt.tprintf("dark_level %d is outside 0 to %d", lighting.dark_level, MAXIMUM_FIELD_LIGHT - 1)
	case lighting.steps_per_tick < 1 || lighting.steps_per_tick > MAXIMUM_LIGHT_STEPS_PER_TICK_SETTING:
		return fmt.tprintf("steps_per_tick %d is outside 1 to %d", lighting.steps_per_tick, MAXIMUM_LIGHT_STEPS_PER_TICK_SETTING)
	case lighting.chunk_seeds_per_tick < 1 || lighting.chunk_seeds_per_tick > MAXIMUM_LIGHT_CHUNK_SEEDS_PER_TICK_SETTING:
		return fmt.tprintf("chunk_seeds_per_tick %d is outside 1 to %d", lighting.chunk_seeds_per_tick, MAXIMUM_LIGHT_CHUNK_SEEDS_PER_TICK_SETTING)
	}
	if problem := falloff_problem(lighting.falloff); problem != "" {
		return problem
	}
	if problem := emitters_problem(lighting.emitters); problem != "" {
		return problem
	}
	for id in REQUIRED_LIGHTING_EMITTERS {
		if _, found := find_lighting_emitter(lighting, id); !found {
			return fmt.tprintf("emitters has no %s", id)
		}
	}
	return ""
}

missing_lighting_key_problem :: proc(tree: json.Object, source: string) -> string {
	if key, missing := missing_struct_key(Lighting_File, tree); missing {
		return fmt.tprintf("%s: missing key %s", source, key)
	}
	for record, index in tree["emitters"].(json.Array) {
		if key, missing := missing_struct_key(Lighting_Emitter, record.(json.Object)); missing {
			return fmt.tprintf("%s: emitters[%d] is missing %s", source, index, key)
		}
	}
	return ""
}

// Held to the configuration's strict keys, every key required. The slices
// and strings are temporary: the world keeps the tuning made from them
// (make_field_light_tuning) and the caller the levels it needs.
parse_lighting_file :: proc(data: []byte, source: string) -> (lighting: Lighting_File, problem: string) {
	tree, parse_problem := parse_configuration_layer(data, source, context.temp_allocator)
	if parse_problem != "" {
		return {}, parse_problem
	}
	provenance := make(Configuration_Provenance, context.temp_allocator)
	provenance[""] = source
	if problem = assign_configuration_value(any{&lighting, typeid_of(Lighting_File)}, json.Value(tree), "", provenance, context.temp_allocator); problem != "" {
		return {}, problem
	}
	if problem = missing_lighting_key_problem(tree, source); problem != "" {
		return {}, problem
	}
	if problem = lighting_problem(lighting); problem != "" {
		return {}, fmt.tprintf("%s: %s", source, problem)
	}
	return lighting, ""
}

load_lighting_file :: proc(data_directory: string) -> (lighting: Lighting_File, ok: bool) {
	data, path := read_logged_data_file(data_directory, LIGHTING_FILE_NAME) or_return
	problem: string
	if lighting, problem = parse_lighting_file(data, path); problem != "" {
		platform.log_printf("error: invalid %s", problem)
		return {}, false
	}
	return lighting, true
}

// The emitter's level, by id.
find_lighting_emitter :: proc(lighting: Lighting_File, id: string) -> (level: int, found: bool) {
	for emitter in lighting.emitters {
		if emitter.id == id {
			return emitter.level, true
		}
	}
	return 0, false
}
