package game

import "core:encoding/json"
import "core:fmt"
import "core:reflect"
import "core:slice"
import "platform"

// The planet records of data/planets.sjson (work item 0168,
// doc/content.md, Planets). Held to the configuration's strict keys, so an
// unknown key or a wrong type is an error naming the key, and every field
// is required: a record without one is refused with the field's name.

PLANETS_FILE_NAME :: "planets.sjson"
// Keeps the squared distances of generation (generation_planet.odin) far
// inside i64.
MAXIMUM_PLANET_RADIUS_METRES :: 100_000
// The radii a new world offers (work item 0179): 1 to this many, each a
// valid radius of the record, the record's radius_metres among them.
MAXIMUM_RADIUS_PRESET_COUNT :: 8
// World_Settings borrows the id; the world file writes it.
MAXIMUM_PLANET_ID_LENGTH :: 32
// The relief is three octaves of value noise (generation_planet.odin).
RELIEF_OCTAVE_COUNT :: 3
// The most the octaves' amplitudes, the ledges' amplitude and the
// basins' depth may add up to (0189): the local surface lies within this of the
// radius, which the generation's shortcuts, the field's level of detail
// and its light bound the relief by.
MAXIMUM_RELIEF_METRES :: 34
MAXIMUM_RELIEF_WAVELENGTH_METRES :: 100_000
// The ledges' profile raises 1 - |noise| to the sharpness (0189).
MAXIMUM_LEDGE_SHARPNESS :: 256
MAXIMUM_RELIEF_MILLIMETRES :: MAXIMUM_RELIEF_METRES * MILLIMETRES_PER_METRE
// A planet record may leave out the relief's shape (0189): its terms are
// off at zero, so a planet without it generates as before.
OPTIONAL_PLANET_KEY :: "relief_shape"
MAXIMUM_SURFACE_GRAVITY_CENTIMETRES_PER_SECOND_SQUARED :: 5000
MINIMUM_ROTATION_PERIOD_SECONDS :: 60
MAXIMUM_ROTATION_PERIOD_SECONDS :: 86_400
// Bedrock lies below every local surface's deep stone, so a valley at the
// lowest relief never shows bedrock in place of topsoil.
MINIMUM_BEDROCK_DEPTH_METRES :: int(MAXIMUM_RELIEF_METRES + DEEP_STONE_DEPTH_METRES)
MAXIMUM_PALETTE_LENGTH :: 256
MAXIMUM_SPRING_COUNT :: 64
// A sample's fill a minute (work item 0172), a whole sample at most.
MAXIMUM_RAIN_FILL_PER_MINUTE :: FIELD_WATER_FULL
MAXIMUM_COLOR_COMPONENT :: 255
// The crater's bounds (work item 0199, Planet_Crater). The reach stays
// inside the starter veins' nearest edge (generation_planet_veins.odin).
MINIMUM_CRATER_RADIUS_METRES :: 4
MAXIMUM_CRATER_RADIUS_METRES :: 24
MAXIMUM_CRATER_DEPTH_METRES :: 8
MAXIMUM_CRATER_RIM_METRES :: 4
MAXIMUM_CRATER_REACH_METRES :: 24
// The rim falls back to the surrounding relief over this many times its
// height outwards from the crest.
CRATER_RIM_FALL_PER_HEIGHT :: 6
// The trees' bounds (work item 0197, Planet_Trees). A grove's reach is
// at most its lattice's edge, so a point's groves lie in the 27 grove
// cubes round it; the slope at most the walkable angle of
// data/game.sjson (60 degrees).
MINIMUM_TREE_SPACING_METRES :: 2
MAXIMUM_TREE_SPACING_METRES :: 16
MAXIMUM_GROVE_SPACING_METRES :: 256
MAXIMUM_TREE_CLEARING_METRES :: 64
MAXIMUM_TREE_SLOPE_PERCENT :: 173
MAXIMUM_TREE_SPECIES :: 8
MAXIMUM_TREE_SPECIES_ID_LENGTH :: 32
MAXIMUM_TREE_LOGS :: 16
MINIMUM_FELLING_MILLISECONDS :: 100
MAXIMUM_FELLING_MILLISECONDS :: 60_000
MINIMUM_TRUNK_RADIUS_MILLIMETRES :: 50
MAXIMUM_TRUNK_RADIUS_MILLIMETRES :: 1000
MINIMUM_TRUNK_HEIGHT_MILLIMETRES :: 500
MAXIMUM_TRUNK_HEIGHT_MILLIMETRES :: 20_000

// One octave of the relief's value noise: its lattice spacing and the
// most it raises or lowers the surface.
Relief_Octave :: struct {
	wavelength_metres: int,
	amplitude_metres:  int,
}

// The relief's shape (work item 0189, generation_planet.odin), every
// term off at zero. The ledges are one more octave of value noise read
// through 1 - (1 - |noise|) raised to the sharpness with the noise's sign,
// so the ground steps by up to twice the amplitude along the noise's zero
// lines and stays flat between them. The basin deepens the first octave where
// its noise lies below the threshold (a percentage of the noise's range,
// -100 to 100) by up to the depth, growing with the square of the
// distance below the threshold. The terrace breaks the first octave and
// the basins into steps of the rise, each step's riser the given share (in
// thousandths) of its span and the rest a flat tread.
Relief_Shape :: struct {
	ledge_wavelength_metres:     int,
	ledge_amplitude_millimetres: int,
	ledge_sharpness:             int,
	terrace_rise_millimetres:    int,
	terrace_riser_permille:      int,
	basin_depth_metres:          int,
	basin_threshold_percent:     int,
}

// A spring of the water field (work item 0172): the generator makes the
// first air sample above the surface under the point a source. Latitude
// 90 is the pole on +y; longitude 0 lies towards +x, 90 towards +z.
Planet_Spring :: struct {
	latitude_degrees:  int,
	longitude_degrees: int,
}

// Where a field session's players spawn (work item 0179): the surface
// under the point, in whole degrees as a spring's.
Planet_Home :: struct {
	latitude_degrees:  int,
	longitude_degrees: int,
}

// The impact crater the pod lies in (work item 0199, generation_planet.odin,
// crater_relief), heights along the distance from the home: a flat floor
// out to floor_radius_metres at depth_metres below the home's uncratered
// relief, a smooth bowl rising to the crest at radius_metres, a rim
// rim_metres high there falling back to the surrounding relief over
// CRATER_RIM_FALL_PER_HEIGHT times its height. All zero is no crater.
Planet_Crater :: struct {
	radius_metres:       int,
	depth_metres:        int,
	floor_radius_metres: int,
	rim_metres:          int,
}

// A kind of tree the planet grows (work item 0197, doc/content.md,
// Trees): the machine record of kind tree that holds its model, the tint
// that multiplies the model's colours, the count of the item Mine held on
// the trunk yields, the felling times (0265): a tree of at most
// hand_felling_scale_percent falls to the hand in
// hand_felling_milliseconds, any tree to the wooden, stone and iron axe
// in axe_felling_milliseconds; and the trunk's capsule, which the walk,
// the aim and the placements meet.
Planet_Tree_Species :: struct {
	id:                       string,
	machine:                  string,
	tint:                     [3]int,
	item:                     string,
	count:                    int,
	hand_felling_scale_percent: int,
	hand_felling_milliseconds:  int,
	axe_felling_milliseconds:   [3]int,
	trunk_radius_millimetres: int,
	trunk_height_millimetres: int,
}

// The trees' placement (work item 0197, generation_planet_trees.odin):
// grove centres on a lattice of grove_spacing_metres, grove_share_percent
// of its cubes holding one, and trees on a lattice of
// tree_spacing_metres kept with density_percent at a grove's centre,
// falling with the square of the distance to none at grove_radius_metres.
// None within clearing_metres of the home, below the sea or where the
// ground rises more than maximum_slope_percent. A grove share of 0 is no
// trees.
Planet_Trees :: struct {
	grove_spacing_metres:  int,
	grove_share_percent:   int,
	grove_radius_metres:   int,
	tree_spacing_metres:   int,
	density_percent:       int,
	clearing_metres:       int,
	maximum_slope_percent: int,
	species:               []Planet_Tree_Species,
}

// What a world records of the trees (Planet_Generation_Record.trees): the
// placement keys and the species count; the species themselves come from
// the data (make_recorded_planet).
Planet_Tree_Placement :: struct {
	grove_spacing_metres:  int,
	grove_share_percent:   int,
	grove_radius_metres:   int,
	tree_spacing_metres:   int,
	density_percent:       int,
	clearing_metres:       int,
	maximum_slope_percent: int,
	species_count:         int,
}

Planet :: struct {
	id:                                             string,
	radius_metres:                                  int,
	// The radii a new world offers (0179); radius_metres is the default.
	radius_presets_metres:                          []int,
	surface_gravity_centimetres_per_second_squared: int,
	// Below the radius (the mean surface), where bedrock starts.
	bedrock_depth_metres:                           int,
	// Above the radius; negative lies below it.
	sea_level_metres:                               int,
	springs:                                        []Planet_Spring,
	home:                                           Planet_Home,
	// The crater at the home (0199).
	crater:                                         Planet_Crater,
	// The trees (0197).
	trees:                                          Planet_Trees,
	// Fill per surface sample per minute; read and bounded, applied by
	// nothing until the weather (M15).
	rain_fill_per_minute:                           int,
	rotation_period_seconds:                        int,
	// The surface is the radius plus their sum, read on the sphere.
	relief_octaves:                                 [RELIEF_OCTAVE_COUNT]Relief_Octave,
	// Optional in the file (OPTIONAL_PLANET_KEY), off at zero (0189).
	relief_shape:                                   Relief_Shape,
	// Red, green, blue from 0 to 255; a sample's tint is an index into it.
	palette:                                        [][3]int,
	// The arrival's hit digs the crater (0271): set only by
	// make_recorded_planet from the world's record, never by the data.
	crater_at_impact:                               bool `json:"-"`,
}

Planets_File :: struct {
	planets: []Planet,
}

// The first of type's keys that object lacks, but the optional one and a
// field tagged json:"-", which no file sets.
missing_struct_key :: proc(type: typeid, object: json.Object, optional := "") -> (key: string, missing: bool) {
	for index in 0 ..< reflect.struct_field_count(type) {
		field := reflect.struct_field_at(type, index)
		key = configuration_key(field.name, field.tag)
		if key not_in object && key != optional && key != "-" {
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
		if key, missing := missing_struct_key(Planet, record.(json.Object), OPTIONAL_PLANET_KEY); missing {
			return fmt.tprintf("%s: planets[%d] is missing %s", source, index, key)
		}
		if shape, is_object := record.(json.Object)[OPTIONAL_PLANET_KEY].(json.Object); is_object {
			if key, missing := missing_struct_key(Relief_Shape, shape); missing {
				return fmt.tprintf("%s: planets[%d].relief_shape is missing %s", source, index, key)
			}
		}
		for spring, spring_index in record.(json.Object)["springs"].(json.Array) {
			if key, missing := missing_struct_key(Planet_Spring, spring.(json.Object)); missing {
				return fmt.tprintf("%s: planets[%d].springs[%d] is missing %s", source, index, spring_index, key)
			}
		}
		if home, is_object := record.(json.Object)["home"].(json.Object); is_object {
			if key, missing := missing_struct_key(Planet_Home, home); missing {
				return fmt.tprintf("%s: planets[%d].home is missing %s", source, index, key)
			}
		}
		if crater, is_object := record.(json.Object)["crater"].(json.Object); is_object {
			if key, missing := missing_struct_key(Planet_Crater, crater); missing {
				return fmt.tprintf("%s: planets[%d].crater is missing %s", source, index, key)
			}
		}
		if problem := missing_trees_key_problem(record.(json.Object), index, source); problem != "" {
			return problem
		}
		for octave, octave_index in record.(json.Object)["relief_octaves"].(json.Array) {
			if key, missing := missing_struct_key(Relief_Octave, octave.(json.Object)); missing {
				return fmt.tprintf("%s: planets[%d].relief_octaves[%d] is missing %s", source, index, octave_index, key)
			}
		}
	}
	return ""
}

// The trees object and each species hold every key.
missing_trees_key_problem :: proc(record: json.Object, index: int, source: string) -> string {
	trees, is_object := record["trees"].(json.Object)
	if !is_object {
		return ""
	}
	if key, missing := missing_struct_key(Planet_Trees, trees); missing {
		return fmt.tprintf("%s: planets[%d].trees is missing %s", source, index, key)
	}
	for species, species_index in trees["species"].(json.Array) {
		if key, missing := missing_struct_key(Planet_Tree_Species, species.(json.Object)); missing {
			return fmt.tprintf("%s: planets[%d].trees.species[%d] is missing %s", source, index, species_index, key)
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

relief_problem :: proc(octaves: [RELIEF_OCTAVE_COUNT]Relief_Octave, shape: Relief_Shape) -> string {
	if problem := relief_shape_problem(shape); problem != "" {
		return problem
	}
	total := shape.ledge_amplitude_millimetres + shape.basin_depth_metres * MILLIMETRES_PER_METRE
	for octave, index in octaves {
		if octave.wavelength_metres < 1 || octave.wavelength_metres > MAXIMUM_RELIEF_WAVELENGTH_METRES {
			return fmt.tprintf("relief_octaves[%d].wavelength_metres %d is outside 1 to %d", index, octave.wavelength_metres, MAXIMUM_RELIEF_WAVELENGTH_METRES)
		}
		if octave.amplitude_metres < 0 || octave.amplitude_metres > MAXIMUM_RELIEF_METRES {
			return fmt.tprintf("relief_octaves[%d].amplitude_metres %d is outside 0 to %d", index, octave.amplitude_metres, MAXIMUM_RELIEF_METRES)
		}
		total += octave.amplitude_metres * MILLIMETRES_PER_METRE
	}
	if total > MAXIMUM_RELIEF_MILLIMETRES {
		return fmt.tprintf("relief_octaves with the ledges and the basins add up to %d mm, more than %d", total, MAXIMUM_RELIEF_MILLIMETRES)
	}
	return ""
}

// A term's other keys are checked only while the term is on, so the zero
// shape (a planet or a world file without it) passes.
relief_shape_problem :: proc(shape: Relief_Shape) -> string {
	switch {
	case shape.ledge_amplitude_millimetres < 0 || shape.ledge_amplitude_millimetres > MAXIMUM_RELIEF_MILLIMETRES:
		return fmt.tprintf("relief_shape.ledge_amplitude_millimetres %d is outside 0 to %d", shape.ledge_amplitude_millimetres, MAXIMUM_RELIEF_MILLIMETRES)
	case shape.ledge_amplitude_millimetres > 0 && (shape.ledge_wavelength_metres < 1 || shape.ledge_wavelength_metres > MAXIMUM_RELIEF_WAVELENGTH_METRES):
		return fmt.tprintf("relief_shape.ledge_wavelength_metres %d is outside 1 to %d", shape.ledge_wavelength_metres, MAXIMUM_RELIEF_WAVELENGTH_METRES)
	case shape.ledge_amplitude_millimetres > 0 && (shape.ledge_sharpness < 1 || shape.ledge_sharpness > MAXIMUM_LEDGE_SHARPNESS):
		return fmt.tprintf("relief_shape.ledge_sharpness %d is outside 1 to %d", shape.ledge_sharpness, MAXIMUM_LEDGE_SHARPNESS)
	case shape.terrace_rise_millimetres < 0 || shape.terrace_rise_millimetres > MAXIMUM_RELIEF_MILLIMETRES:
		return fmt.tprintf("relief_shape.terrace_rise_millimetres %d is outside 0 to %d", shape.terrace_rise_millimetres, MAXIMUM_RELIEF_MILLIMETRES)
	case shape.terrace_rise_millimetres > 0 && (shape.terrace_riser_permille < 1 || shape.terrace_riser_permille > 1000):
		return fmt.tprintf("relief_shape.terrace_riser_permille %d is outside 1 to 1000", shape.terrace_riser_permille)
	case shape.basin_depth_metres < 0 || shape.basin_depth_metres > MAXIMUM_RELIEF_METRES:
		return fmt.tprintf("relief_shape.basin_depth_metres %d is outside 0 to %d", shape.basin_depth_metres, MAXIMUM_RELIEF_METRES)
	case shape.basin_depth_metres > 0 && (shape.basin_threshold_percent < -99 || shape.basin_threshold_percent > 100):
		return fmt.tprintf("relief_shape.basin_threshold_percent %d is outside -99 to 100", shape.basin_threshold_percent)
	}
	return ""
}

// Each preset must make a valid record (the bedrock and the sea inside
// it), and the record's own radius is the default among them.
radius_presets_problem :: proc(planet: Planet) -> string {
	if len(planet.radius_presets_metres) < 1 || len(planet.radius_presets_metres) > MAXIMUM_RADIUS_PRESET_COUNT {
		return fmt.tprintf("radius_presets_metres has %d entries, not 1 to %d", len(planet.radius_presets_metres), MAXIMUM_RADIUS_PRESET_COUNT)
	}
	at_preset := planet
	for preset, index in planet.radius_presets_metres {
		at_preset.radius_metres = preset
		if problem := planet_problem(at_preset); problem != "" {
			return fmt.tprintf("radius_presets_metres[%d]: %s", index, problem)
		}
	}
	if !slice.contains(planet.radius_presets_metres, planet.radius_metres) {
		return fmt.tprintf("radius_metres %d is not among radius_presets_metres %v", planet.radius_metres, planet.radius_presets_metres)
	}
	return ""
}

// The values one radius makes a planet of; the presets are checked
// apart (radius_presets_problem), so a world file's recorded planet
// passes without them.
planet_problem :: proc(planet: Planet) -> string {
	switch {
	case planet.id == "":
		return "id is empty"
	case len(planet.id) > MAXIMUM_PLANET_ID_LENGTH:
		return fmt.tprintf("id is longer than %d bytes", MAXIMUM_PLANET_ID_LENGTH)
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
	if problem := springs_problem(planet.springs); problem != "" {
		return problem
	}
	if problem := home_problem(planet.home); problem != "" {
		return problem
	}
	if problem := crater_problem(planet.crater); problem != "" {
		return problem
	}
	if problem := trees_problem(planet.trees, planet.crater); problem != "" {
		return problem
	}
	if problem := relief_problem(planet.relief_octaves, planet.relief_shape); problem != "" {
		return problem
	}
	if planet.rain_fill_per_minute < 0 || planet.rain_fill_per_minute > MAXIMUM_RAIN_FILL_PER_MINUTE {
		return fmt.tprintf("rain_fill_per_minute %d is outside 0 to %d", planet.rain_fill_per_minute, MAXIMUM_RAIN_FILL_PER_MINUTE)
	}
	return palette_problem(planet.palette)
}

springs_problem :: proc(springs: []Planet_Spring) -> string {
	if len(springs) > MAXIMUM_SPRING_COUNT {
		return fmt.tprintf("springs has %d springs, more than %d", len(springs), MAXIMUM_SPRING_COUNT)
	}
	for spring, index in springs {
		if spring.latitude_degrees < -90 || spring.latitude_degrees > 90 {
			return fmt.tprintf("springs[%d].latitude_degrees %d is outside -90 to 90", index, spring.latitude_degrees)
		}
		if spring.longitude_degrees < -180 || spring.longitude_degrees > 180 {
			return fmt.tprintf("springs[%d].longitude_degrees %d is outside -180 to 180", index, spring.longitude_degrees)
		}
	}
	return ""
}

home_problem :: proc(home: Planet_Home) -> string {
	if home.latitude_degrees < -90 || home.latitude_degrees > 90 {
		return fmt.tprintf("home.latitude_degrees %d is outside -90 to 90", home.latitude_degrees)
	}
	if home.longitude_degrees < -180 || home.longitude_degrees > 180 {
		return fmt.tprintf("home.longitude_degrees %d is outside -180 to 180", home.longitude_degrees)
	}
	return ""
}

// The zero crater is none; any other keeps every key in its bounds, the
// reach inside MAXIMUM_CRATER_REACH_METRES and the bowl's steepest slope,
// 1.5 times its mean for the smoothstep, at most 45 degrees.
crater_problem :: proc(crater: Planet_Crater) -> string {
	if crater == {} {
		return ""
	}
	reach := crater.radius_metres + CRATER_RIM_FALL_PER_HEIGHT * crater.rim_metres
	switch {
	case crater.radius_metres < MINIMUM_CRATER_RADIUS_METRES || crater.radius_metres > MAXIMUM_CRATER_RADIUS_METRES:
		return fmt.tprintf("crater.radius_metres %d is outside %d to %d", crater.radius_metres, MINIMUM_CRATER_RADIUS_METRES, MAXIMUM_CRATER_RADIUS_METRES)
	case crater.depth_metres < 1 || crater.depth_metres > MAXIMUM_CRATER_DEPTH_METRES:
		return fmt.tprintf("crater.depth_metres %d is outside 1 to %d", crater.depth_metres, MAXIMUM_CRATER_DEPTH_METRES)
	case crater.floor_radius_metres < 2 || crater.floor_radius_metres > crater.radius_metres - 2:
		return fmt.tprintf("crater.floor_radius_metres %d is outside 2 to %d", crater.floor_radius_metres, crater.radius_metres - 2)
	case crater.rim_metres < 0 || crater.rim_metres > MAXIMUM_CRATER_RIM_METRES:
		return fmt.tprintf("crater.rim_metres %d is outside 0 to %d", crater.rim_metres, MAXIMUM_CRATER_RIM_METRES)
	case reach > MAXIMUM_CRATER_REACH_METRES:
		return fmt.tprintf("crater reaches %d m, more than %d", reach, MAXIMUM_CRATER_REACH_METRES)
	case 3 * (crater.depth_metres + crater.rim_metres) > 2 * (crater.radius_metres - crater.floor_radius_metres):
		return fmt.tprintf("crater bowl of %d m over %d m is steeper than 45 degrees", crater.depth_metres + crater.rim_metres, crater.radius_metres - crater.floor_radius_metres)
	}
	return ""
}

// The crater's reach from the home in metres, 0 for no crater.
crater_reach_metres :: proc(crater: Planet_Crater) -> int {
	if crater == {} {
		return 0
	}
	return crater.radius_metres + CRATER_RIM_FALL_PER_HEIGHT * crater.rim_metres
}

// A grove share of 0 is no trees and skips the rest; otherwise every key
// within its bounds, the clearing at least the crater's reach, and each
// species (tree_species_problem).
trees_problem :: proc(trees: Planet_Trees, crater: Planet_Crater) -> string {
	if trees.grove_share_percent == 0 {
		return ""
	}
	reach := crater_reach_metres(crater)
	switch {
	case trees.grove_share_percent < 0 || trees.grove_share_percent > 100:
		return fmt.tprintf("trees.grove_share_percent %d is outside 0 to 100", trees.grove_share_percent)
	case trees.tree_spacing_metres < MINIMUM_TREE_SPACING_METRES || trees.tree_spacing_metres > MAXIMUM_TREE_SPACING_METRES:
		return fmt.tprintf("trees.tree_spacing_metres %d is outside %d to %d", trees.tree_spacing_metres, MINIMUM_TREE_SPACING_METRES, MAXIMUM_TREE_SPACING_METRES)
	case trees.grove_spacing_metres < 2 * trees.tree_spacing_metres || trees.grove_spacing_metres > MAXIMUM_GROVE_SPACING_METRES:
		return fmt.tprintf("trees.grove_spacing_metres %d is outside %d to %d", trees.grove_spacing_metres, 2 * trees.tree_spacing_metres, MAXIMUM_GROVE_SPACING_METRES)
	case trees.grove_radius_metres < trees.tree_spacing_metres || trees.grove_radius_metres > trees.grove_spacing_metres:
		return fmt.tprintf("trees.grove_radius_metres %d is outside %d to %d", trees.grove_radius_metres, trees.tree_spacing_metres, trees.grove_spacing_metres)
	case trees.density_percent < 1 || trees.density_percent > 100:
		return fmt.tprintf("trees.density_percent %d is outside 1 to 100", trees.density_percent)
	case trees.clearing_metres < 0 || trees.clearing_metres > MAXIMUM_TREE_CLEARING_METRES:
		return fmt.tprintf("trees.clearing_metres %d is outside 0 to %d", trees.clearing_metres, MAXIMUM_TREE_CLEARING_METRES)
	case trees.clearing_metres < reach:
		return fmt.tprintf("trees.clearing_metres %d is inside the crater's reach of %d m", trees.clearing_metres, reach)
	case trees.maximum_slope_percent < 1 || trees.maximum_slope_percent > MAXIMUM_TREE_SLOPE_PERCENT:
		return fmt.tprintf("trees.maximum_slope_percent %d is outside 1 to %d", trees.maximum_slope_percent, MAXIMUM_TREE_SLOPE_PERCENT)
	case len(trees.species) < 1 || len(trees.species) > MAXIMUM_TREE_SPECIES:
		return fmt.tprintf("trees.species has %d entries, not 1 to %d", len(trees.species), MAXIMUM_TREE_SPECIES)
	}
	for species, index in trees.species {
		if problem := tree_species_problem(species, index); problem != "" {
			return problem
		}
	}
	return ""
}

// A species id is used once in the data; a world's recorded species
// repeat the data's (recorded_trees), so the record leaves it unchecked.
tree_species_ids_problem :: proc(trees: Planet_Trees) -> string {
	for species, index in trees.species {
		for earlier in trees.species[:index] {
			if earlier.id == species.id {
				return fmt.tprintf("trees.species[%d].id %q is used twice", index, species.id)
			}
		}
	}
	return ""
}

// 1 to 32 bytes of a to z, 0 to 9 and underscores.
is_tree_species_id :: proc(id: string) -> bool {
	for character in id {
		if !(character >= 'a' && character <= 'z' || character >= '0' && character <= '9' || character == '_') {
			return false
		}
	}
	return id != "" && len(id) <= MAXIMUM_TREE_SPECIES_ID_LENGTH
}

tree_species_problem :: proc(species: Planet_Tree_Species, index: int) -> string {
	switch {
	case !is_tree_species_id(species.id):
		return fmt.tprintf("trees.species[%d].id %q is not 1 to %d bytes of a to z, 0 to 9 and _", index, species.id, MAXIMUM_TREE_SPECIES_ID_LENGTH)
	case species.machine == "":
		return fmt.tprintf("trees.species[%d].machine is empty", index)
	case species.item == "":
		return fmt.tprintf("trees.species[%d].item is empty", index)
	case species.count < 1 || species.count > MAXIMUM_TREE_LOGS:
		return fmt.tprintf("trees.species[%d].count %d is outside 1 to %d", index, species.count, MAXIMUM_TREE_LOGS)
	case species.hand_felling_scale_percent < 0 || species.hand_felling_scale_percent > PLANET_TREE_MAXIMUM_SCALE_PERCENT:
		return fmt.tprintf("trees.species[%d].hand_felling_scale_percent %d is outside 0 to %d", index, species.hand_felling_scale_percent, PLANET_TREE_MAXIMUM_SCALE_PERCENT)
	case !felling_milliseconds_in_bounds(species.hand_felling_milliseconds):
		return fmt.tprintf("trees.species[%d].hand_felling_milliseconds %d is outside %d to %d", index, species.hand_felling_milliseconds, MINIMUM_FELLING_MILLISECONDS, MAXIMUM_FELLING_MILLISECONDS)
	case species.trunk_radius_millimetres < MINIMUM_TRUNK_RADIUS_MILLIMETRES || species.trunk_radius_millimetres > MAXIMUM_TRUNK_RADIUS_MILLIMETRES:
		return fmt.tprintf("trees.species[%d].trunk_radius_millimetres %d is outside %d to %d", index, species.trunk_radius_millimetres, MINIMUM_TRUNK_RADIUS_MILLIMETRES, MAXIMUM_TRUNK_RADIUS_MILLIMETRES)
	case species.trunk_height_millimetres < MINIMUM_TRUNK_HEIGHT_MILLIMETRES || species.trunk_height_millimetres > MAXIMUM_TRUNK_HEIGHT_MILLIMETRES:
		return fmt.tprintf("trees.species[%d].trunk_height_millimetres %d is outside %d to %d", index, species.trunk_height_millimetres, MINIMUM_TRUNK_HEIGHT_MILLIMETRES, MAXIMUM_TRUNK_HEIGHT_MILLIMETRES)
	}
	for component in species.tint {
		if component < 0 || component > MAXIMUM_COLOR_COMPONENT {
			return fmt.tprintf("trees.species[%d].tint has %d, outside 0 to %d", index, component, MAXIMUM_COLOR_COMPONENT)
		}
	}
	for milliseconds, tier in species.axe_felling_milliseconds {
		if !felling_milliseconds_in_bounds(milliseconds) {
			return fmt.tprintf("trees.species[%d].axe_felling_milliseconds[%d] %d is outside %d to %d", index, tier, milliseconds, MINIMUM_FELLING_MILLISECONDS, MAXIMUM_FELLING_MILLISECONDS)
		}
	}
	return ""
}

felling_milliseconds_in_bounds :: proc(milliseconds: int) -> bool {
	return milliseconds >= MINIMUM_FELLING_MILLISECONDS && milliseconds <= MAXIMUM_FELLING_MILLISECONDS
}

// The keys a world records (Planet_Generation_Record.trees).
planet_tree_placement :: proc(trees: Planet_Trees) -> Planet_Tree_Placement {
	return Planet_Tree_Placement {
		grove_spacing_metres = trees.grove_spacing_metres,
		grove_share_percent = trees.grove_share_percent,
		grove_radius_metres = trees.grove_radius_metres,
		tree_spacing_metres = trees.tree_spacing_metres,
		density_percent = trees.density_percent,
		clearing_metres = trees.clearing_metres,
		maximum_slope_percent = trees.maximum_slope_percent,
		species_count = len(trees.species),
	}
}

planets_problem :: proc(planets: []Planet) -> string {
	if len(planets) == 0 {
		return "planets is empty"
	}
	for planet, index in planets {
		problem := planet_problem(planet)
		if problem == "" {
			problem = radius_presets_problem(planet)
		}
		if problem == "" {
			problem = tree_species_ids_problem(planet.trees)
		}
		if problem != "" {
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

DEFAULT_PLANET_ID :: "home"

// The planet a new world starts on and a world whose planet the data no
// longer has falls back to: home, or the first record without one.
default_planet :: proc(planets: []Planet) -> Planet {
	if planet, found := find_planet(planets, DEFAULT_PLANET_ID); found {
		return planet
	}
	return planets[0]
}

find_planet :: proc(planets: []Planet, id: string) -> (planet: Planet, found: bool) {
	for candidate in planets {
		if candidate.id == id {
			return candidate, true
		}
	}
	return {}, false
}
