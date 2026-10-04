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
	// Zero (every term off, the relief of before) in a file written
	// before it (0189).
	relief_shape:                                   Relief_Shape,
	springs:                                        []Planet_Spring,
	// The home spawn (0179); home_recorded is false in a file written
	// before it, which takes the data's home (resolve_world_planet).
	home:                                           Planet_Home,
	home_recorded:                                  bool,
	// The crater at the home (0199); crater_recorded is false in a file
	// written before it, which takes the data's crater
	// (resolve_world_planet).
	crater:                                         Planet_Crater,
	crater_recorded:                                bool,
	// The trees' placement and species count (0197); trees_recorded is
	// false in a file written before them, which takes the data's
	// (resolve_world_planet).
	trees:                                          Planet_Tree_Placement,
	trees_recorded:                                 bool,
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
		relief_shape = planet.relief_shape,
		springs = planet.springs,
		home = planet.home,
		home_recorded = true,
		crater = planet.crater,
		crater_recorded = true,
		trees = planet_tree_placement(planet.trees),
		trees_recorded = true,
	}
}

planet_generation_is_recorded :: proc(record: Planet_Generation_Record) -> bool {
	return record.radius_metres != 0
}

// The record's values over the data's planet, its palette repeated or cut
// to the recorded length so every generated tint has a colour, and its
// tree species likewise (recorded_tree_species). The id, the springs, the
// palette and the species with their strings are the result's own, in
// allocator (destroy_recorded_planet); the presets are left out.
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
	result.relief_shape = record.relief_shape
	result.springs = slice.clone(record.springs, allocator)
	if record.home_recorded {
		result.home = record.home
	}
	if record.crater_recorded {
		result.crater = record.crater
	}
	result.palette = make([][3]int, record.palette_length, allocator)
	for &color, index in result.palette {
		color = planet.palette[index % len(planet.palette)]
	}
	if record.trees_recorded {
		result.trees = recorded_trees(planet.trees, record.trees, allocator)
	} else {
		result.trees.species = clone_tree_species(planet.trees.species, len(planet.trees.species), allocator)
	}
	return result
}

// The recorded placement over the data's species, repeated or cut to the
// recorded count; no species (a count of 0 or a data list of 0) is no
// trees, so the grove share goes to 0.
recorded_trees :: proc(data: Planet_Trees, placement: Planet_Tree_Placement, allocator := context.allocator) -> Planet_Trees {
	trees := Planet_Trees {
		grove_spacing_metres  = placement.grove_spacing_metres,
		grove_share_percent   = placement.grove_share_percent,
		grove_radius_metres   = placement.grove_radius_metres,
		tree_spacing_metres   = placement.tree_spacing_metres,
		density_percent       = placement.density_percent,
		clearing_metres       = placement.clearing_metres,
		maximum_slope_percent = placement.maximum_slope_percent,
	}
	if placement.species_count <= 0 || len(data.species) == 0 {
		trees.grove_share_percent = 0
		return trees
	}
	trees.species = clone_tree_species(data.species, placement.species_count, allocator)
	return trees
}

// count species, entry index the source's index modulo its length, with
// their strings cloned, since the session's planet outlives the data it
// was made from (a content reload).
clone_tree_species :: proc(source: []Planet_Tree_Species, count: int, allocator := context.allocator) -> []Planet_Tree_Species {
	if count <= 0 || len(source) == 0 {
		return nil
	}
	species := make([]Planet_Tree_Species, count, allocator)
	for &entry, index in species {
		entry = source[index % len(source)]
		entry.id = strings.clone(entry.id, allocator)
		entry.machine = strings.clone(entry.machine, allocator)
		entry.item = strings.clone(entry.item, allocator)
	}
	return species
}

destroy_recorded_planet :: proc(planet: ^Planet) {
	delete(planet.id)
	delete(planet.springs)
	delete(planet.palette)
	for species in planet.trees.species {
		delete(species.id)
		delete(species.machine)
		delete(species.item)
	}
	delete(planet.trees.species)
	planet^ = {}
}

// A valid species for the stand in planet of
// planet_generation_record_problem, so a recorded placement passes
// trees_problem whatever the data's species.
PLANET_TREE_STAND_IN_SPECIES :: Planet_Tree_Species {
	id                       = "recorded",
	machine                  = "recorded",
	tint                     = {255, 255, 255},
	item                     = "recorded",
	count                    = 1,
	felling_milliseconds     = 1000,
	trunk_radius_millimetres = 100,
	trunk_height_millimetres = 1000,
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
	if record.trees.species_count < 0 || record.trees.species_count > MAXIMUM_TREE_SPECIES {
		return fmt.tprintf("trees.species_count %d is outside 0 to %d", record.trees.species_count, MAXIMUM_TREE_SPECIES)
	}
	stand_in := Planet {
		id      = "recorded",
		palette = {{0, 0, 0}},
		trees   = {species = {PLANET_TREE_STAND_IN_SPECIES}},
	}
	return planet_problem(make_recorded_planet(stand_in, record, context.temp_allocator))
}

// The home's direction from the centre, a unit vector, as a spring's
// (planet_spring_direction): latitude 90 is +y, longitude 0 lies towards
// +x and 90 towards +z. Latitude 0, longitude 0 is a home like any other
// (+x, 0180).
planet_home_direction :: proc(home: Planet_Home) -> [3]i64 {
	return planet_spring_direction(Planet_Spring{latitude_degrees = home.latitude_degrees, longitude_degrees = home.longitude_degrees})
}

// How far a new world's home may move from the record's point to find dry
// ground, in degrees of arc (0180): about 350, 700 and 1400 m at 4, 8 and
// 16 km. Every wet seed of 1 to 400 found dry ground within it with the
// shipped record, the farthest move 177, 144 and 280 m.
HOME_SEARCH_DEGREES :: 5
// The crater floor under a dry home stands at least this above the sea
// level (0180): one sample at the coarsest spacing, so no air sample of
// the pod's cabin holds the sea's fill.
HOME_DRY_MARGIN_MILLIMETRES :: 1000

// The height above the radius the pod would stand on at the home: the
// crater's floor there, or the uncratered relief without a crater.
planet_home_floor_height :: proc(generation: Planet_Generation, crater: Planet_Crater, home: Planet_Home) -> i64 {
	direction := planet_home_direction(home)
	if crater == {} {
		return uncratered_relief(generation, fixed_scale(direction, generation.radius))
	}
	return make_crater_term(generation, crater, direction).floor_height
}

// The pod's floor at the home stands at least HOME_DRY_MARGIN_MILLIMETRES
// above the sea level.
planet_home_is_dry :: proc(generation: Planet_Generation, planet: Planet, home: Planet_Home) -> bool {
	sea := metres_to_position_units(i64(planet.sea_level_metres)) + millimetres_to_position_units(HOME_DRY_MARGIN_MILLIMETRES)
	return planet_home_floor_height(generation, planet.crater, home) >= sea
}

// The squared length of the difference of two vectors; for unit vectors
// of UNIT_VECTOR_ONE (2^24) at most 3 * 2^50, inside an i64.
squared_chord :: proc(first, second: [3]i64) -> i64 {
	difference := first - second
	return difference.x * difference.x + difference.y * difference.y + difference.z * difference.z
}

// The dry home nearest the record's point (0180): the record's home when
// it is dry (planet_home_is_dry), else the whole degree point within
// HOME_SEARCH_DEGREES of arc with the shortest chord to it. The search
// runs latitude then longitude ascending and keeps only a strictly nearer
// point, so a tie goes to the lower latitude, then the lower longitude, on
// every machine; the poles are visited once, at longitude 0. found is
// false when no point in reach is dry.
find_dry_planet_home :: proc(seed: u64, planet: Planet) -> (home: Planet_Home, found: bool) {
	generation := make_planet_generation(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	if planet_home_is_dry(generation, planet, planet.home) {
		return planet.home, true
	}
	origin := planet_home_direction(planet.home)
	reach := squared_chord(planet_home_direction({}), planet_home_direction({0, HOME_SEARCH_DEGREES}))
	best := reach + 1
	for latitude in max(-90, planet.home.latitude_degrees - HOME_SEARCH_DEGREES) ..= min(90, planet.home.latitude_degrees + HOME_SEARCH_DEGREES) {
		at_pole := latitude == 90 || latitude == -90
		for longitude in (at_pole ? 0 : -179) ..= (at_pole ? 0 : 180) {
			candidate := Planet_Home{latitude, longitude}
			chord := squared_chord(planet_home_direction(candidate), origin)
			if chord < best && planet_home_is_dry(generation, planet, candidate) {
				home, best, found = candidate, chord, true
			}
		}
	}
	return
}

// A new world's home: the nearest dry point (find_dry_planet_home), with a
// log line when it moves from the record's or when none is in reach (the
// pod then lands at the record's point).
new_world_home :: proc(seed: u64, planet: Planet) -> Planet_Home {
	home, found := find_dry_planet_home(seed, planet)
	if !found {
		platform.log_printf("world: no dry ground within %d degrees of the home at latitude %d, longitude %d with seed %d, the pod lands there", HOME_SEARCH_DEGREES, planet.home.latitude_degrees, planet.home.longitude_degrees, seed)
		return planet.home
	}
	if home != planet.home {
		platform.log_printf("world: the home at latitude %d, longitude %d lies under the sea with seed %d, the pod lands at latitude %d, longitude %d", planet.home.latitude_degrees, planet.home.longitude_degrees, seed, home.latitude_degrees, home.longitude_degrees)
	}
	return home
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
	if planet_generation_is_recorded(recorded) && !recorded.crater_recorded {
		platform.log_printf("world: the world file records no crater, it takes the crater of %q from %s", planet.id, PLANETS_FILE_NAME)
		record.crater, record.crater_recorded = planet.crater, true
	}
	if planet_generation_is_recorded(recorded) && !recorded.trees_recorded {
		platform.log_printf("world: the world file records no trees, it takes the trees of %q from %s", planet.id, PLANETS_FILE_NAME)
		record.trees, record.trees_recorded = planet_tree_placement(planet.trees), true
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
