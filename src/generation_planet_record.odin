package game

import "core:fmt"
import "core:slice"
import "core:strings"
import "platform"

// The generation values a world was made with (work item 0179,
// doc/architecture.md, Save format and World generation). world.sjson
// records them and a loaded world generates from them, not from
// data/planets.sjson, so a later edit of the data cannot reshape the
// unedited ground around the saved chunks. They are what generation reads
// off a planet record (make_planet_generation, fill_field_chunk_sea,
// mark_field_chunk_springs) and the gravity and the rotation, which the
// player and the day read.
Planet_Generation_Record :: struct {
	// Zero in a world file written before the record.
	radius_metres:                                  int,
	surface_gravity_centimetres_per_second_squared: int,
	bedrock_depth_metres:                           int,
	sea_level_metres:                               int,
	rotation_period_seconds:                        int,
	// A tint is a hash modulo it; the colours stay the data's.
	palette_length:                                 int,
	relief_octaves:                                 [RELIEF_OCTAVE_COUNT]Relief_Octave,
	springs:                                        []Planet_Spring,
	// The home spawn (0179); home_recorded is false in a file written
	// before it, which takes the data's home (resolve_world_planet).
	home:                                           Planet_Home,
	home_recorded:                                  bool,
}

// Borrows the planet's springs.
planet_generation_record :: proc(planet: Planet) -> Planet_Generation_Record {
	return Planet_Generation_Record {
		radius_metres = planet.radius_metres,
		surface_gravity_centimetres_per_second_squared = planet.surface_gravity_centimetres_per_second_squared,
		bedrock_depth_metres = planet.bedrock_depth_metres,
		sea_level_metres = planet.sea_level_metres,
		rotation_period_seconds = planet.rotation_period_seconds,
		palette_length = len(planet.palette),
		relief_octaves = planet.relief_octaves,
		springs = planet.springs,
		home = planet.home,
		home_recorded = true,
	}
}

planet_generation_is_recorded :: proc(record: Planet_Generation_Record) -> bool {
	return record.radius_metres != 0
}

// The record's values over the data's planet, its palette repeated or cut
// to the recorded length so every generated tint has a colour. The id, the
// springs and the palette are the result's own, in allocator
// (destroy_recorded_planet); the presets are left out.
make_recorded_planet :: proc(planet: Planet, record: Planet_Generation_Record, allocator := context.allocator) -> Planet {
	result := planet
	result.id = strings.clone(planet.id, allocator)
	result.radius_presets_metres = nil
	result.radius_metres = record.radius_metres
	result.surface_gravity_centimetres_per_second_squared = record.surface_gravity_centimetres_per_second_squared
	result.bedrock_depth_metres = record.bedrock_depth_metres
	result.sea_level_metres = record.sea_level_metres
	result.rotation_period_seconds = record.rotation_period_seconds
	result.relief_octaves = record.relief_octaves
	result.springs = slice.clone(record.springs, allocator)
	if record.home_recorded {
		result.home = record.home
	}
	result.palette = make([][3]int, record.palette_length, allocator)
	for &color, index in result.palette {
		color = planet.palette[index % len(planet.palette)]
	}
	return result
}

destroy_recorded_planet :: proc(planet: ^Planet) {
	delete(planet.id)
	delete(planet.springs)
	delete(planet.palette)
	planet^ = {}
}

// Empty for an absent record (a file written before it) and for one
// planet_problem accepts as a planet of one colour per palette entry.
planet_generation_record_problem :: proc(record: Planet_Generation_Record) -> string {
	if !planet_generation_is_recorded(record) {
		return ""
	}
	if record.palette_length < 1 || record.palette_length > MAXIMUM_PALETTE_LENGTH {
		return fmt.tprintf("palette_length %d is outside 1 to %d", record.palette_length, MAXIMUM_PALETTE_LENGTH)
	}
	stand_in := Planet {
		id      = "recorded",
		palette = {{0, 0, 0}},
	}
	return planet_problem(make_recorded_planet(stand_in, record, context.temp_allocator))
}

// The home's direction from the centre, a unit vector, as a spring's
// (planet_spring_direction): latitude 90 is +y, longitude 0 lies towards
// +x and 90 towards +z.
planet_home_direction :: proc(home: Planet_Home) -> [3]i64 {
	return planet_spring_direction(Planet_Spring{latitude_degrees = home.latitude_degrees, longitude_degrees = home.longitude_degrees})
}

// A preset of the planet, or the planet's default radius for zero (a new
// world without a choice, a file before the setting) and, with a log
// line, for a radius the data no longer offers.
planet_preset_radius :: proc(planet: Planet, radius_metres: int) -> int {
	switch {
	case radius_metres == 0:
		return planet.radius_metres
	case !slice.contains(planet.radius_presets_metres, radius_metres):
		platform.log_printf("world: %d m is not a radius preset of the planet %q, the world takes %d m", radius_metres, planet.id, planet.radius_metres)
		return planet.radius_metres
	}
	return radius_metres
}

// The planet a world generates on, against the data's planets: the
// settings' planet, or with a log line the default one when the data has
// no planet of that id (a loaded world keeps its id in the settings, so
// its save does too, and takes the default's palette and rain); the
// recorded generation when the file has one,
// else the data's values at the settings' radius preset, with a log line
// when a loaded file lacks the record. The settings come back with the
// planet's id (the file's kept, above) and the generation's radius.
// Without planet data (tests of the block world) everything stays as
// given.
resolve_world_planet :: proc(settings: World_File_Settings, recorded: Planet_Generation_Record, planets: []Planet, loading: bool) -> (resolved: World_File_Settings, planet: Planet, record: Planet_Generation_Record) {
	resolved, record = settings, recorded
	if len(planets) == 0 {
		return
	}
	found: bool
	planet, found = find_planet(planets, settings.planet_id)
	switch {
	case found:
		resolved.planet_id = planet.id
	case loading:
		planet = default_planet(planets)
		platform.log_printf("world: the planet %q is not in %s, the world keeps its id and takes the palette and the rain of %q", settings.planet_id, PLANETS_FILE_NAME, planet.id)
	case:
		planet = default_planet(planets)
		resolved.planet_id = planet.id
		platform.log_printf("world: the planet %q is not in %s, the world takes %q", settings.planet_id, PLANETS_FILE_NAME, planet.id)
	}
	if planet_generation_is_recorded(recorded) && !recorded.home_recorded {
		platform.log_printf("world: the world file records no home, it takes the home of %q from %s", planet.id, PLANETS_FILE_NAME)
		record.home, record.home_recorded = planet.home, true
	}
	if !planet_generation_is_recorded(recorded) {
		if loading {
			platform.log_printf("world: the world file records no planet generation, it takes the values of %q from %s", planet.id, PLANETS_FILE_NAME)
		}
		record = planet_generation_record(planet)
		record.radius_metres = planet_preset_radius(planet, settings.planet_radius_metres)
	}
	resolved.planet_radius_metres = record.radius_metres
	return
}
