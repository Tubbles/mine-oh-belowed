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
	// The arrival's hit digs the crater (0271); false in a file written
	// before it, whose generation bakes the crater as before.
	crater_at_impact:                               bool,
	// The trees' placement and species count (0197); trees_recorded is
	// false in a file written before them, which takes the data's
	// (resolve_world_planet).
	trees:                                          Planet_Tree_Placement,
	trees_recorded:                                 bool,
	// Zero in a file written before them (0306): the relief of before.
	landforms:                                      Planet_Landforms,
	// Zero in a file written before them (0323): the relief of before.
	landmarks:                                      Planet_Landmarks,
	// The climate's field (0307); zero in a file written before it, whose
	// ground keeps the look without a climate (make_recorded_planet).
	climate:                                        Planet_Climate_Field,
	// Zero in a file written before it (0312): no derived springs, no
	// lakes.
	waters:                                         Planet_Waters,
	// Zero in a file written before them (0327): no caves and no
	// undercuts.
	caves:                                          Planet_Caves,
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
		crater_at_impact = planet.crater_at_impact,
		trees = planet_tree_placement(planet.trees),
		trees_recorded = true,
		landforms = planet.landforms,
		landmarks = planet.landmarks,
		climate = planet_climate_field(planet.climate),
		waters = planet.waters,
		caves = planet.caves,
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
	// Set even when zero: the data's landforms never reach an old world.
	result.landforms = record.landforms
	// Set even when zero: the data's landmarks never reach an old world.
	result.landmarks = record.landmarks
	// The recorded field with the data's look, both on; a world recorded
	// without a climate, or a planet whose data has none, keeps the look
	// without one.
	result.climate = {}
	if record.climate != {} && planet.climate != {} {
		result.climate = with_climate_field(planet.climate, record.climate)
	}
	// Set even when zero: the data's waters never reach an old world. The
	// features and the tiles are the session's (make_planet_water_features,
	// make_water_tile_cache).
	result.waters = record.waters
	result.water_features = {}
	result.water_tiles = nil
	// Set even when zero: the data's caves never reach an old world.
	result.caves = record.caves
	result.springs = slice.clone(record.springs, allocator)
	if record.home_recorded {
		result.home = record.home
	}
	if record.crater_recorded {
		result.crater = record.crater
	}
	result.crater_at_impact = record.crater_at_impact
	result.palette = make([][3]int, record.palette_length, allocator)
	for &color, index in result.palette {
		color = planet.palette[index % len(planet.palette)]
	}
	if record.trees_recorded {
		result.trees = recorded_trees(planet.trees, record.trees, allocator)
	} else {
		result.trees.species = clone_tree_species(planet.trees.species, len(planet.trees.species), allocator)
	}
	// The data's cover in every world (0311): presentation, never
	// recorded; without a climate its table is off.
	result.cover = clone_planet_cover(planet.cover, allocator)
	return result
}

// The kinds with their strings and colours cloned, as the species are.
clone_planet_cover :: proc(cover: Planet_Cover, allocator := context.allocator) -> Planet_Cover {
	if len(cover.kinds) == 0 {
		return {}
	}
	kinds := make([]Planet_Cover_Kind, len(cover.kinds), allocator)
	for &kind, index in kinds {
		kind = cover.kinds[index]
		kind.id = strings.clone(kind.id, allocator)
		kind.shape = strings.clone(kind.shape, allocator)
		kind.color_from = strings.clone(kind.color_from, allocator)
		kind.colors = slice.clone(kind.colors, allocator)
	}
	return Planet_Cover{kinds = kinds}
}

destroy_planet_cover :: proc(cover: ^Planet_Cover) {
	for kind in cover.kinds {
		delete(kind.id)
		delete(kind.shape)
		delete(kind.color_from)
		delete(kind.colors)
	}
	delete(cover.kinds)
	cover^ = {}
}

// The recorded placement over the data's species, repeated or cut to the
// recorded count, each with its recorded placement keys (0310), so a data
// edit never moves a saved forest; no species (a count of 0 or a data
// list of 0) is no trees, so the grove share and the forest go to 0.
recorded_trees :: proc(data: Planet_Trees, placement: Planet_Tree_Placement, allocator := context.allocator) -> Planet_Trees {
	trees := Planet_Trees {
		grove_spacing_metres  = placement.grove_spacing_metres,
		grove_share_percent   = placement.grove_share_percent,
		grove_radius_metres   = placement.grove_radius_metres,
		tree_spacing_metres   = placement.tree_spacing_metres,
		density_percent       = placement.density_percent,
		clearing_metres       = placement.clearing_metres,
		maximum_slope_percent = placement.maximum_slope_percent,
		forest                = placement.forest,
	}
	if placement.species_count <= 0 || len(data.species) == 0 {
		trees.grove_share_percent = 0
		trees.forest = {}
		return trees
	}
	trees.species = clone_tree_species(data.species, placement.species_count, allocator)
	for &species, index in trees.species[:min(len(trees.species), MAXIMUM_TREE_SPECIES)] {
		species = with_tree_species_placement(species, placement.species[index])
	}
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
	destroy_water_tile_cache(planet.water_tiles)
	destroy_planet_water_features(&planet.water_features)
	delete(planet.id)
	delete(planet.springs)
	delete(planet.palette)
	for species in planet.trees.species {
		delete(species.id)
		delete(species.machine)
		delete(species.item)
	}
	delete(planet.trees.species)
	destroy_planet_cover(&planet.cover)
	planet^ = {}
}

// A valid species for the stand in planet of
// planet_generation_record_problem, so a recorded placement passes
// trees_problem whatever the data's species; its placement keys are the
// record's (recorded_trees).
PLANET_TREE_STAND_IN_SPECIES :: Planet_Tree_Species {
	id                       = "recorded",
	machine                  = "recorded",
	tint                     = {255, 255, 255},
	item                     = "recorded",
	count                    = 1,
	hand_felling_scale_percent = 100,
	hand_felling_milliseconds  = 1000,
	axe_felling_milliseconds   = {1000, 1000, 1000},
	trunk_radius_millimetres = 100,
	trunk_height_millimetres = 1000,
}

// A valid look for the stand in planet (0310), so a recorded climate
// field reaches planet_problem with it and a recorded forest is checked
// against the record's climate.
PLANET_CLIMATE_STAND_IN :: Planet_Climate {
	grass_hot_celsius = 1,
	snow_fade_celsius = 1,
	sand_fade_metres  = 1,
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
		climate = PLANET_CLIMATE_STAND_IN,
	}
	if problem := planet_problem(make_recorded_planet(stand_in, record, context.temp_allocator)); problem != "" {
		return problem
	}
	return climate_field_problem(record.climate)
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

// The log line of a world file recorded before the landforms (0306) on a
// planet whose data has them, or "": zero is off, so nothing is remapped
// and the world keeps the relief it was made with.
recorded_landforms_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string {
	if !planet_generation_is_recorded(recorded) || recorded.landforms != {} || planet.landforms == {} {
		return ""
	}
	return "world: the world file records no landforms, it keeps the relief it was made with"
}

// The log line of a world file recorded with the landforms but before
// the landmarks (0323) on a planet whose data has them, or "": zero is
// off, so the world keeps the relief it was made with. A file from before
// the landforms already logs their line.
recorded_landmarks_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string {
	if !planet_generation_is_recorded(recorded) || recorded.landforms == {} || recorded.landmarks != {} || planet.landmarks == {} {
		return ""
	}
	return "world: the world file records no landmarks, it keeps the relief it was made with"
}

// The log line of a world file recorded with the landmarks but before
// the carving kinds (0324) on a planet whose data has them, or "": their
// shares read as 0, so the world keeps the ground it was made with.
recorded_carving_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string {
	landmarks := recorded.landmarks
	data := planet.landmarks
	if !planet_generation_is_recorded(recorded) || landmarks.site_spacing_metres == 0 || landmarks.arch_percent + landmarks.grotto_percent + landmarks.mushroom_percent != 0 || data.arch_percent + data.grotto_percent + data.mushroom_percent == 0 {
		return ""
	}
	return "world: the world file records no arches, grottos or mushroom rocks, it keeps the ground it was made with"
}

// The log line of a world file whose recorded climate (0307) and the
// data's disagree on being on, or "": either way its ground keeps the
// look without a climate (make_recorded_planet).
recorded_climate_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string {
	switch {
	case !planet_generation_is_recorded(recorded):
		return ""
	case recorded.climate == {} && planet.climate != {}:
		return "world: the world file records no climate, its ground keeps the look without one"
	case recorded.climate != {} && planet.climate == {}:
		return fmt.tprintf("world: the world file records a climate but %q in %s has none, its ground keeps the look without one", planet.id, PLANETS_FILE_NAME)
	}
	return ""
}

// The log line of a world file recorded before the waters (0312) on a
// planet whose data has them, or "": zero is off, so the world keeps its
// springs and has no lakes. One recorded with the waters but before their
// tiles (0326) on a planet whose data has them reads tile_metres as 0 and
// keeps 0312's waters round its home, none past them.
recorded_waters_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string {
	switch {
	case !planet_generation_is_recorded(recorded) || planet.waters == {}:
		return ""
	case recorded.waters == {}:
		return "world: the world file records no waters, it keeps its springs and has no lakes"
	case recorded.waters.tile_metres == 0 && planet.waters.tile_metres > 0:
		return "world: the world file records the waters round the home only, it keeps them and has none past them"
	}
	return ""
}

// The log line of a world file recorded before the caves (0327) on a
// planet whose data has them, or "": zero is off, so nothing is remapped
// and the world keeps the ground it was made with.
recorded_caves_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string {
	if !planet_generation_is_recorded(recorded) || recorded.caves != {} || planet.caves == {} {
		return ""
	}
	return "world: the world file records no caves, it keeps the ground it was made with"
}

// The log line of a world file without a forest (0310) on a planet whose
// data has one, or "": trees recorded before the forest (zero is off, so
// the world keeps the groves of its record), or trees taken from the data
// by a record without a climate for a forest to read (resolve_world_planet
// takes the data's groves without the forest).
recorded_forest_note :: proc(recorded: Planet_Generation_Record, planet: Planet) -> string {
	if !planet_generation_is_recorded(recorded) || planet.trees.forest == {} {
		return ""
	}
	without_forest := recorded.trees_recorded ? recorded.trees.forest == {} : !record_has_climate(recorded)
	if !without_forest {
		return ""
	}
	return "world: the world file records no forest, its trees keep the groves"
}

// The record's climate field is on (0307); a forest reads it (0310).
record_has_climate :: proc(recorded: Planet_Generation_Record) -> bool {
	return recorded.climate.temperature_wavelength_metres > 0
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
	if note := recorded_landforms_note(recorded, planet); note != "" {
		platform.log_printf("%s", note)
	}
	if note := recorded_landmarks_note(recorded, planet); note != "" {
		platform.log_printf("%s", note)
	}
	if note := recorded_carving_note(recorded, planet); note != "" {
		platform.log_printf("%s", note)
	}
	if note := recorded_climate_note(recorded, planet); note != "" {
		platform.log_printf("%s", note)
	}
	if note := recorded_waters_note(recorded, planet); note != "" {
		platform.log_printf("%s", note)
	}
	if note := recorded_caves_note(recorded, planet); note != "" {
		platform.log_printf("%s", note)
	}
	if note := recorded_forest_note(recorded, planet); note != "" {
		platform.log_printf("%s", note)
	}
	if planet_generation_is_recorded(recorded) && !recorded.trees_recorded {
		platform.log_printf("world: the world file records no trees, it takes the trees of %q from %s", planet.id, PLANETS_FILE_NAME)
		record.trees, record.trees_recorded = planet_tree_placement(planet.trees), true
		// A forest needs the climate (0310): a record without one takes
		// the data's groves.
		if !record_has_climate(recorded) {
			record.trees.forest = {}
		}
	}
	if !planet_generation_is_recorded(recorded) {
		if loading {
			platform.log_printf("world: the world file records no planet generation, it takes the values of %q from %s", planet.id, PLANETS_FILE_NAME)
		}
		record = planet_generation_record(planet)
		record.radius_metres = planet_preset_radius(planet, settings.planet_radius_metres)
		// A new world's hit digs its crater (0271); a file from before
		// the record bakes it.
		record.crater_at_impact = !loading
	}
	resolved.planet_radius_metres = record.radius_metres
	return
}
