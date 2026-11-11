package game

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:reflect"
import "core:slice"
import "core:sync"
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
// basins' depth may add up to (0189), and the relief's bound both ways on
// a planet without landforms (0306, relief_bounds).
OCTAVE_RELIEF_LIMIT_METRES :: 34
MAXIMUM_RELIEF_WAVELENGTH_METRES :: 100_000
// The ledges' profile raises 1 - |noise| to the sharpness (0189).
MAXIMUM_LEDGE_SHARPNESS :: 256
OCTAVE_RELIEF_LIMIT_MILLIMETRES :: OCTAVE_RELIEF_LIMIT_METRES * MILLIMETRES_PER_METRE
// The most any planet's relief reaches below and above its radius (0306):
// the caps of a planet's own bound (relief_bounds), which the
// generation's shortcuts, the field's level of detail, its light, the
// globe and the edits bound the relief by.
MAXIMUM_RELIEF_DEPTH_METRES :: 128
MAXIMUM_RELIEF_HEIGHT_METRES :: 256
// The landforms' bounds (0306, Planet_Landforms): the knots of the
// region's curves, the warp's reach and the edge of the wild ground.
LANDFORM_KNOT_COUNT :: 9
MAXIMUM_LANDFORM_WARP_METRES :: 10_000
MAXIMUM_LANDFORM_WILD_METRES :: 8192
// The landmarks' bounds (0323, Planet_Landmarks): a site's or a mesa
// tier's height and a site's radius, a butte's stretch along its axis and
// a site outline's wobble. A spire's, a sinkhole's, a grotto's and a
// mushroom rock's most stretch are fixed (0324), so the spacing's least
// (landmark_widest_site_metres) reads them.
MAXIMUM_LANDMARK_METRES :: 128
MAXIMUM_LANDMARK_STRETCH_PERCENT :: 400
MAXIMUM_LANDMARK_WOBBLE_PERCENT :: 90
SPIRE_STRETCH_PERCENT :: 130
SINKHOLE_STRETCH_PERCENT :: 140
GROTTO_STRETCH_PERCENT :: 115
MUSHROOM_STRETCH_PERCENT :: 115
// A planet record may leave these out: the relief's shape (0189), the
// landforms (0306), the landmarks (0323), the climate (0307), the
// waters (0312) and the ground cover (0311), each off at zero, so a
// planet without them generates and looks as before.
OPTIONAL_PLANET_KEYS :: [6]string{"relief_shape", "landforms", "landmarks", "climate", "waters", "cover"}
// The waters' bounds (0312, Planet_Waters). The finder's reach round the
// home in metres, least and most.
MINIMUM_WATERS_REACH_METRES :: 256
MAXIMUM_WATERS_REACH_METRES :: 8192
// The finder's grid holds at most this many cells either side of the home.
MAXIMUM_WATERS_GRID_HALF_CELLS :: 512
// The lakes and the derived springs a planet holds at most.
MAXIMUM_PLANET_LAKES :: 128
MAXIMUM_DERIVED_SPRINGS :: 128
// A lake's refine grid's cell (0312, refine_planet_lake).
LAKE_CELL_METRES :: 2
// The waters' tiles' edge (0326, Planet_Waters.tile_metres), least and
// most, with tiles on.
MINIMUM_WATER_TILE_METRES :: 256
MAXIMUM_WATER_TILE_METRES :: 4096
// A spring's catchment with tiles, in grid cells: a tile's margin stays at
// most 66 cells.
MAXIMUM_TILE_CATCHMENT_CELLS :: 64
// The tiles a cache keeps found; the least recently asked past it are
// freed and found again alike.
MAXIMUM_WATER_TILES :: 1024
// Twice the largest half diagonal of a box that asks for lakes: a coarsest
// node's with its margin at the widest spacing, 472 m.
WATER_QUERY_BOX_METRES :: 512
// The space diagonal of the shipped simulated set (a radius of 2 and a
// margin of 1, 7 chunks of 32 m at 1 m spacing) is 388 m: a player's set
// holds at most one derived spring. At the data's bounds (a radius of 3
// and a margin of 2, 11 chunks) it is 610 m, which holds two.
MINIMUM_SPRING_SPACING_METRES :: 400
// The climate's bounds (0307, Planet_Climate).
MINIMUM_CLIMATE_WAVELENGTH_METRES :: 64
MAXIMUM_CLIMATE_CELSIUS :: 100
MAXIMUM_LAPSE_MILLICELSIUS_PER_METRE :: 1000
MAXIMUM_SNOW_FADE_CELSIUS :: 50
MAXIMUM_SAND_METRES :: 64
MAXIMUM_SURFACE_GRAVITY_CENTIMETRES_PER_SECOND_SQUARED :: 5000
MINIMUM_ROTATION_PERIOD_SECONDS :: 60
MAXIMUM_ROTATION_PERIOD_SECONDS :: 86_400
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
// The forest's bounds (work item 0310, Planet_Forest): a tree's scale is
// the u8 of Planet_Tree.scale_percent.
MAXIMUM_TREE_SCALE_PERCENT :: 250
MINIMUM_TREE_SCALE_PERCENT :: 10
MAXIMUM_FOREST_MEADOW_METRES :: 512
MAXIMUM_TREE_HEIGHT_METRES :: 4000
// The ground cover's bounds (work item 0311, Planet_Cover).
MAXIMUM_COVER_KINDS :: 12
MAXIMUM_COVER_COLORS :: 8
MAXIMUM_COVER_PARTS :: 16
MAXIMUM_COVER_PER_HUNDRED_SQUARE_METRES :: 5000
MAXIMUM_COVER_SIZE_MILLIMETRES :: 4000
MAXIMUM_COVER_FAR_METRES :: 256
MAXIMUM_COVER_KIND_ID_LENGTH :: 32

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

// The landforms (work item 0306, generation_planet_landforms.odin), off
// at the zero value: a region noise of region_wavelength_metres, its input
// warped by up to warp_metres by a noise of warp_wavelength_metres, read
// through three curves of LANDFORM_KNOT_COUNT knots at the noise's -0.6 to
// 0.6: the ground's height over the radius, the share of the ranges and
// the share of the hills there. The ranges are ridges of range_metres
// along the zero lines of a noise of range_wavelength_metres, notched by
// spurs of spur_wavelength_metres by spur_percent; the hills a noise of
// hill_wavelength_metres and hill_metres. Within calm_metres of the home
// the ground is home_metres high, the terms fading in out to wild_metres.
// Fixed arrays, so the zero value compares with {} and a world records
// them without allocation.
Planet_Landforms :: struct {
	warp_wavelength_metres:   int,
	warp_metres:              int,
	region_wavelength_metres: int,
	region_heights_metres:    [LANDFORM_KNOT_COUNT]int,
	region_ranges_percent:    [LANDFORM_KNOT_COUNT]int,
	region_hills_percent:     [LANDFORM_KNOT_COUNT]int,
	range_wavelength_metres:  int,
	range_metres:             int,
	spur_wavelength_metres:   int,
	spur_percent:             int,
	hill_wavelength_metres:   int,
	hill_metres:              int,
	home_metres:              int,
	calm_metres:              int,
	wild_metres:              int,
}

// The landmarks (work item 0323, generation_planet_landmarks.odin), off
// at the zero value and needing the landforms: gorges where the
// landforms' first warp noise lies below minus gorge_mask_percent, mesas
// where it lies above mesa_mask_percent, each fading in over
// mask_fade_percent, their shares at the landforms' region knots. A gorge
// runs along the zero lines of a noise of gorge_wavelength_metres read at
// the landforms' warped point, meandering with the hills by
// gorge_meander_percent, gorge_width_permille of the noise's range wide
// with a flat floor of gorge_floor_percent of it, gorge_metres deep, its
// floor at least dry_metres over the sea. The mesas are two tiers of
// mesa_metres where a noise of mesa_wavelength_metres roughened by the
// hills by mesa_rough_percent passes mesa_threshold_percent and that plus
// mesa_tier_percent, each edge rising over mesa_edge_permille of the
// noise's range. The sites lie one per cube of site_spacing_metres at
// most, a spire, a butte, a sinkhole, an arch, a grotto or a mushroom
// rock by the shares, the rest of the cubes empty; a site's radius and
// height lie between its pair's values (least and most), a butte
// stretched up to butte_stretch_percent along a drawn axis, the outline
// wobbling by wobble_percent. The last three (0324) are carved under
// their raise: an arch is a fin of arch_length_metres with an opening
// through it, a grotto a knoll with a chamber and a tunnel out, a
// mushroom rock a cap on a stem.
Planet_Landmarks :: struct {
	gorge_mask_percent:      int,
	mesa_mask_percent:       int,
	mask_fade_percent:       int,
	region_gorges_percent:   [LANDFORM_KNOT_COUNT]int,
	region_mesas_percent:    [LANDFORM_KNOT_COUNT]int,
	gorge_wavelength_metres: int,
	gorge_meander_percent:   int,
	gorge_width_permille:    int,
	gorge_floor_percent:     int,
	gorge_metres:            int,
	dry_metres:              int,
	mesa_wavelength_metres:  int,
	mesa_rough_percent:      int,
	mesa_threshold_percent:  int,
	mesa_tier_percent:       int,
	mesa_edge_permille:      int,
	mesa_metres:             int,
	site_spacing_metres:     int,
	spire_percent:           int,
	butte_percent:           int,
	sinkhole_percent:        int,
	spire_radius_metres:     [2]int,
	spire_metres:            [2]int,
	butte_radius_metres:     [2]int,
	butte_metres:            [2]int,
	butte_stretch_percent:   int,
	sinkhole_radius_metres:  [2]int,
	sinkhole_metres:         [2]int,
	wobble_percent:          int,
	arch_percent:            int,
	grotto_percent:          int,
	mushroom_percent:        int,
	arch_length_metres:      [2]int,
	arch_metres:             [2]int,
	grotto_radius_metres:    [2]int,
	grotto_metres:           [2]int,
	mushroom_radius_metres:  [2]int,
	mushroom_metres:         [2]int,
}

// The climate's field (work item 0307, generation_planet_climate.odin),
// the keys a world records: a temperature at the sea level of
// sea_level_celsius, moved by a noise of temperature_wavelength_metres by
// up to temperature_spread_celsius either side and cooled by
// lapse_millicelsius_per_metre over the sea (warmed below it), and a
// moisture of moisture_percent moved by a noise of
// moisture_wavelength_metres by up to moisture_spread_percent. Off at the
// zero value.
Planet_Climate_Field :: struct {
	temperature_wavelength_metres: int,
	moisture_wavelength_metres:    int,
	sea_level_celsius:             int,
	temperature_spread_celsius:    int,
	lapse_millicelsius_per_metre:  int,
	moisture_percent:              int,
	moisture_spread_percent:       int,
}

// The climate (work item 0307): the field's keys, which a world records,
// and the ground's look, which is the data's in every world (the
// mesher's world_field_ground_look.odin, the field shader). grass_colors
// are the grass at full light, rows cold, temperate and hot (at
// grass_cold_celsius, their mean and grass_hot_celsius), each dry,
// moderate and wet, index row times 3 plus column. Snow lies below
// snow_celsius, fading over snow_fade_celsius; sand within sand_metres of
// the sea level and below it, fading over sand_fade_metres. Off at the
// zero value: the ground keeps the look without a climate.
Planet_Climate :: struct {
	temperature_wavelength_metres: int,
	moisture_wavelength_metres:    int,
	sea_level_celsius:             int,
	temperature_spread_celsius:    int,
	lapse_millicelsius_per_metre:  int,
	moisture_percent:              int,
	moisture_spread_percent:       int,
	grass_colors:                  [9][3]int,
	grass_cold_celsius:            int,
	grass_hot_celsius:             int,
	snow_celsius:                  int,
	snow_fade_celsius:             int,
	snow_color:                    [3]int,
	sand_metres:                   int,
	sand_fade_metres:              int,
	sand_color:                    [3]int,
}

// The waters (work item 0312, generation_planet_waters.odin): springs at
// the valley heads of the highlands and lakes in their basins, found on
// cells of grid_metres in tiles of tile_metres over the whole planet as
// the ground is wanted (0326, generation_planet_water_tiles.odin), or
// without tiles once per session within reach_metres of the home (at most
// half the radius), none within clearing_metres of it. A spring heads
// a channel draining spring_catchment_square_metres, stands
// spring_minimum_metres over the sea at least and spring_spacing_metres
// from every other; a lake is a basin at least lake_minimum_depth
// deep and lake_minimum_area wide, within a window of lake_maximum_metres,
// filled to its pour point less lake_margin. Off at the zero value.
Planet_Waters :: struct {
	reach_metres:                    int,
	grid_metres:                     int,
	clearing_metres:                 int,
	spring_catchment_square_metres:  int,
	spring_minimum_metres:           int,
	spring_spacing_metres:           int,
	lake_minimum_depth_millimetres:  int,
	lake_minimum_area_square_metres: int,
	lake_maximum_metres:             int,
	lake_margin_millimetres:         int,
	// The tiles' edge on the cube faces' grids (0326); 0 keeps 0312's
	// finder round the home only, as a world recorded before it does.
	tile_metres:                     int,
}

// A derived spring (0312): the unit direction of its grid cell, its
// relief over the radius and the fall to its outlet (to the sea level when
// to_sea, else to the grid's border cell), in position units.
Planet_Water_Spring :: struct {
	direction:    [3]i64,
	height, drop: i64,
	to_sea:       bool,
}

// A lake (0312): the pit's unit direction and its tangents (the plane its
// mask lies on, find_planet_lakes), origin the refined pit on the sphere
// of the radius, the level and the floor over the radius, the mask's half
// width in LAKE_CELL_METRES cells (side 2 half + 1, bit (v + half) side +
// u + half), the water cells before the dilation, and the sphere holding
// every water sample (bound_centre, bound_radius). Position units.
Planet_Lake :: struct {
	centre, east, north, origin, bound_centre: [3]i64,
	level, floor, bound_radius, half:          i64,
	cells:                                     i32,
	mask:                                      []u64,
	// Its pit's face, column and row on the cube's grid (0326); zero from
	// 0312's finder.
	cell:                                      [3]i32,
}

// A head of the tiles' drainage (0326): its spring, drop its height over
// the sea and to_sea false, and its cell (face, column, row).
Water_Spring_Candidate :: struct {
	spring: Planet_Water_Spring,
	cell:   [3]i32,
}

// A tile of a cube face's grid (0326): cells column * tile_cells to
// column * tile_cells + tile_cells - 1, rows alike.
Water_Tile_Key :: struct {
	face, column, row: i32,
}

Water_Tile_State :: enum u8 {
	Absent,
	Finding,
	Found,
}

// A tile's analysis (its lakes and heads) and its final (kept, indices
// into lakes, and the springs), each with its state, and the clock of
// its last ask (0326).
Water_Tile :: struct {
	analysis, final: Water_Tile_State,
	lakes:           []Planet_Lake,
	candidates:      []Water_Spring_Candidate,
	kept:            []i32,
	springs:         []Planet_Water_Spring,
	used:            u64,
}

// The tiles of one session's planet (0326, make_water_tile_cache), shared
// by every thread under the mutex: planet the session's, shallow, with
// water_tiles nil (the analyses' generation); faces[f] the face's centre,
// east and north; the geometry in position units and cells, set once.
Water_Tile_Cache :: struct {
	mutex:                    sync.Mutex,
	changed:                  sync.Cond,
	seed:                     u64,
	planet:                   Planet,
	radius, step, sea:        i64,
	face_cells, tile_cells:   i64,
	margin, escape_reach:     i64,
	lake_reach:               i64,
	catchment_cells:          i32,
	home:                     [3]i64,
	faces:                    [6][3][3]i64,
	maximum_tiles:            int,
	tiles:                    map[Water_Tile_Key]^Water_Tile,
	clock:                    u64,
	allocator:                runtime.Allocator,
}

// What the session finds from the seed and the record
// (make_planet_water_features): the derived springs, the lakes and the
// tech demo's start, the spring whose water falls furthest to the sea.
Planet_Water_Features :: struct {
	springs:   []Planet_Water_Spring,
	lakes:     []Planet_Lake,
	start:     [3]i64,
	has_start: bool,
}

// Deletes every mask and both slices, and zeroes the features.
destroy_planet_water_features :: proc(features: ^Planet_Water_Features) {
	for lake in features.lakes {
		delete(lake.mask)
	}
	delete(features.lakes)
	delete(features.springs)
	features^ = {}
}

// A planet's relief bound (0306, relief_bounds): the lowest and the
// highest local surface, in position units from the radius.
Relief_Bounds :: struct {
	lowest, highest: i64,
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
// the aim and the placements meet. In a forest (0310) the species stands
// where the temperature (celsius), the moisture (percent), the height over
// the sea (metres) and the forest's cover (percent) lie in its ranges,
// least first, fading out past them over the forest's fades, by its
// weight_percent among the others there, at a scale between its
// scale_percent pair; a forest's yield and felling time scale with the
// tree. The placement keys are required in the file and read only while
// the forest is on.
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
	temperature_celsius:      [2]int,
	moisture_percent:         [2]int,
	height_metres:            [2]int,
	cover_percent:            [2]int,
	scale_percent:            [2]int,
	weight_percent:           int,
}

// A species' placement keys (0310), which a world records
// (Planet_Tree_Placement.species).
Planet_Tree_Species_Placement :: struct {
	temperature_celsius: [2]int,
	moisture_percent:    [2]int,
	height_metres:       [2]int,
	cover_percent:       [2]int,
	scale_percent:       [2]int,
	weight_percent:      int,
}

// The forest (work item 0310, generation_planet_trees.odin), off at the
// zero value (a cover wavelength of 0): a cover from a noise of
// cover_wavelength_metres mixed with clearing_percent of a noise of
// clearing_wavelength_metres and moved by moisture_cover_percent of the
// moisture's distance from the middle, rising from 0 at
// cover_threshold_percent of the noise's range to full over
// edge_percent, 0 within meadow_metres of the home and fading in to twice
// it; at least scatter_percent everywhere, the meadow too, for lone
// trees. A candidate of the
// tree lattice stands by the cover times the trees' density_percent and
// the species' climate weights there, none nearer than
// minimum_gap_millimetres to a neighbour's, thinning from
// full_slope_percent to none at the trees' maximum_slope_percent. Each
// species' weight moves by stand_percent of a noise of
// stand_wavelength_metres, so a species gathers in stands; the species'
// ranges fade over the species_fade_ keys. Needs the climate.
Planet_Forest :: struct {
	cover_wavelength_metres:       int,
	clearing_wavelength_metres:    int,
	clearing_percent:              int,
	cover_threshold_percent:       int,
	edge_percent:                  int,
	moisture_cover_percent:        int,
	scatter_percent:               int,
	meadow_metres:                 int,
	minimum_gap_millimetres:       int,
	full_slope_percent:            int,
	stand_wavelength_metres:       int,
	stand_percent:                 int,
	species_fade_celsius:          int,
	species_fade_moisture_percent: int,
	species_fade_metres:           int,
	species_fade_cover_percent:    int,
}

// The trees' placement (work item 0197, generation_planet_trees.odin):
// grove centres on a lattice of grove_spacing_metres, grove_share_percent
// of its cubes holding one, and trees on a lattice of
// tree_spacing_metres kept with density_percent at a grove's centre,
// falling with the square of the distance to none at grove_radius_metres.
// None within clearing_metres of the home, below the sea or where the
// ground rises more than maximum_slope_percent. A grove share of 0 is no
// trees. With the forest on (0310, optional in the file) the forest
// places the trees and the grove keys go unread.
Planet_Trees :: struct {
	grove_spacing_metres:  int,
	grove_share_percent:   int,
	grove_radius_metres:   int,
	tree_spacing_metres:   int,
	density_percent:       int,
	clearing_metres:       int,
	maximum_slope_percent: int,
	forest:                Planet_Forest,
	species:               []Planet_Tree_Species,
}

// What a world records of the trees (Planet_Generation_Record.trees): the
// placement keys, the species count, the forest and each species'
// placement keys (0310, zero in a file written before them: the forest
// off); the rest of the species comes from the data (make_recorded_planet).
Planet_Tree_Placement :: struct {
	grove_spacing_metres:  int,
	grove_share_percent:   int,
	grove_radius_metres:   int,
	tree_spacing_metres:   int,
	density_percent:       int,
	clearing_metres:       int,
	maximum_slope_percent: int,
	species_count:         int,
	forest:                Planet_Forest,
	species:               [MAXIMUM_TREE_SPECIES]Planet_Tree_Species_Placement,
}

// The ground cover (work item 0311, world_field_cover.odin): kinds of
// tufts, flowers, ferns and stones scattered on the finest meshes near the
// eye, presentation only. A kind stands at per_hundred_square_metres of
// surface where the temperature, the moisture (the look's, varied) and
// the slope lie in its ranges, fading out past them over the fades, on
// the surfaces its shares weigh (percent each), more where its own
// surfaces meet others by boundary_percent, in patches of a noise of
// patch_wavelength_metres (0 none) above patch_threshold_percent of its
// range, full over patch_edge_percent. An instance is width and height
// millimetres between the pairs, sunk sink_percent of its height, of
// parts blades, flowers or fronds (0 for a stone), coloured from the
// grass, the ground or its colors (color_from), and drawn out to
// far_metres, thinning from near_metres.
Planet_Cover_Kind :: struct {
	id:                        string,
	shape:                     string,
	parts:                     int,
	per_hundred_square_metres: int,
	temperature_celsius:       [2]int,
	temperature_fade_celsius:  int,
	moisture_percent:          [2]int,
	moisture_fade_percent:     int,
	slope_degrees:             [2]int,
	slope_fade_degrees:        int,
	surfaces:                  Planet_Cover_Surfaces,
	boundary_percent:          int,
	patch_wavelength_metres:   int,
	patch_threshold_percent:   int,
	patch_edge_percent:        int,
	width_millimetres:         [2]int,
	height_millimetres:        [2]int,
	sink_percent:              int,
	color_from:                string,
	colors:                    [][3]int,
	near_metres:               int,
	far_metres:                int,
}

// The share of each surface a kind grows on, percent: the topsoil's looks
// as field.fs splits it, the stones and the three ores.
Planet_Cover_Surfaces :: struct {
	grass:        int,
	sand:         int,
	snow:         int,
	rock:         int,
	stone:        int,
	hematite:     int,
	chalcopyrite: int,
	coal:         int,
}

Planet_Cover :: struct {
	kinds: []Planet_Cover_Kind,
}

Cover_Shape :: enum u8 {
	Blades,
	Flower,
	Fern,
	Pebble,
	Crystal,
}

cover_shape_names := [Cover_Shape]string {
	.Blades  = "blades",
	.Flower  = "flower",
	.Fern    = "fern",
	.Pebble  = "pebble",
	.Crystal = "crystal",
}

// Where an instance's colour comes from: the grass under it, the ground's
// strata tint, or one of the kind's colours by hash.
Cover_Color_Source :: enum u8 {
	Grass,
	Ground,
	Colors,
}

cover_color_source_names := [Cover_Color_Source]string {
	.Grass  = "grass",
	.Ground = "ground",
	.Colors = "colors",
}

// Blades, flowers and ferns are foliage: parts, both faces, a lean.
cover_shape_is_foliage :: proc(shape: Cover_Shape) -> bool {
	return shape == .Blades || shape == .Flower || shape == .Fern
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
	// Optional in the file (OPTIONAL_PLANET_KEYS), off at zero (0189).
	relief_shape:                                   Relief_Shape,
	// Optional in the file, off at zero (0306).
	landforms:                                      Planet_Landforms,
	// Optional in the file, off at zero (0323), needs the landforms.
	landmarks:                                      Planet_Landmarks,
	// Optional in the file, off at zero (0307).
	climate:                                        Planet_Climate,
	// Optional in the file, off at zero (0312).
	waters:                                         Planet_Waters,
	// Optional in the file, off without kinds (0311); needs the climate;
	// presentation only, never recorded.
	cover:                                          Planet_Cover,
	// Red, green, blue from 0 to 255; a sample's tint is an index into it.
	palette:                                        [][3]int,
	// The arrival's hit digs the crater (0271): set only by
	// make_recorded_planet from the world's record, never by the data.
	crater_at_impact:                               bool `json:"-"`,
	// Set by the session from the seed and the record
	// (make_planet_water_features), never by the data.
	water_features:                                 Planet_Water_Features `json:"-"`,
	// The waters' tiles (0326), set by the session when the record has
	// tile_metres (make_water_tile_cache), never by the data.
	water_tiles:                                    ^Water_Tile_Cache `json:"-"`,
}

Planets_File :: struct {
	planets: []Planet,
}

// The first of type's keys that object lacks, but the optional ones and a
// field tagged json:"-", which no file sets.
missing_struct_key :: proc(type: typeid, object: json.Object, optional: []string = nil) -> (key: string, missing: bool) {
	for index in 0 ..< reflect.struct_field_count(type) {
		field := reflect.struct_field_at(type, index)
		key = configuration_key(field.name, field.tag)
		if key not_in object && !slice.contains(optional, key) && key != "-" {
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
	optional := OPTIONAL_PLANET_KEYS
	for record, index in tree["planets"].(json.Array) {
		if key, missing := missing_struct_key(Planet, record.(json.Object), optional[:]); missing {
			return fmt.tprintf("%s: planets[%d] is missing %s", source, index, key)
		}
		if shape, is_object := record.(json.Object)["relief_shape"].(json.Object); is_object {
			if key, missing := missing_struct_key(Relief_Shape, shape); missing {
				return fmt.tprintf("%s: planets[%d].relief_shape is missing %s", source, index, key)
			}
		}
		if landforms, is_object := record.(json.Object)["landforms"].(json.Object); is_object {
			if key, missing := missing_struct_key(Planet_Landforms, landforms); missing {
				return fmt.tprintf("%s: planets[%d].landforms is missing %s", source, index, key)
			}
		}
		if landmarks, is_object := record.(json.Object)["landmarks"].(json.Object); is_object {
			if key, missing := missing_struct_key(Planet_Landmarks, landmarks); missing {
				return fmt.tprintf("%s: planets[%d].landmarks is missing %s", source, index, key)
			}
		}
		if climate, is_object := record.(json.Object)["climate"].(json.Object); is_object {
			if key, missing := missing_struct_key(Planet_Climate, climate); missing {
				return fmt.tprintf("%s: planets[%d].climate is missing %s", source, index, key)
			}
		}
		if waters, is_object := record.(json.Object)["waters"].(json.Object); is_object {
			if key, missing := missing_struct_key(Planet_Waters, waters); missing {
				return fmt.tprintf("%s: planets[%d].waters is missing %s", source, index, key)
			}
		}
		if problem := missing_cover_key_problem(record.(json.Object), index, source); problem != "" {
			return problem
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

// The trees object and each species hold every key; the forest (0310)
// is optional and holds every key when present.
missing_trees_key_problem :: proc(record: json.Object, index: int, source: string) -> string {
	trees, is_object := record["trees"].(json.Object)
	if !is_object {
		return ""
	}
	if key, missing := missing_struct_key(Planet_Trees, trees, {"forest"}); missing {
		return fmt.tprintf("%s: planets[%d].trees is missing %s", source, index, key)
	}
	if forest, forest_is_object := trees["forest"].(json.Object); forest_is_object {
		if key, missing := missing_struct_key(Planet_Forest, forest); missing {
			return fmt.tprintf("%s: planets[%d].trees.forest is missing %s", source, index, key)
		}
	}
	for species, species_index in trees["species"].(json.Array) {
		if key, missing := missing_struct_key(Planet_Tree_Species, species.(json.Object)); missing {
			return fmt.tprintf("%s: planets[%d].trees.species[%d] is missing %s", source, index, species_index, key)
		}
	}
	return ""
}

// A cover object holds its kinds, each kind every key and its surfaces
// every surface (0311).
missing_cover_key_problem :: proc(record: json.Object, index: int, source: string) -> string {
	cover, is_object := record["cover"].(json.Object)
	if !is_object {
		return ""
	}
	if key, missing := missing_struct_key(Planet_Cover, cover); missing {
		return fmt.tprintf("%s: planets[%d].cover is missing %s", source, index, key)
	}
	for kind, kind_index in cover["kinds"].(json.Array) {
		if key, missing := missing_struct_key(Planet_Cover_Kind, kind.(json.Object)); missing {
			return fmt.tprintf("%s: planets[%d].cover.kinds[%d] is missing %s", source, index, kind_index, key)
		}
		if surfaces, surfaces_is_object := kind.(json.Object)["surfaces"].(json.Object); surfaces_is_object {
			if key, missing := missing_struct_key(Planet_Cover_Surfaces, surfaces); missing {
				return fmt.tprintf("%s: planets[%d].cover.kinds[%d].surfaces is missing %s", source, index, kind_index, key)
			}
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
		if octave.amplitude_metres < 0 || octave.amplitude_metres > OCTAVE_RELIEF_LIMIT_METRES {
			return fmt.tprintf("relief_octaves[%d].amplitude_metres %d is outside 0 to %d", index, octave.amplitude_metres, OCTAVE_RELIEF_LIMIT_METRES)
		}
		total += octave.amplitude_metres * MILLIMETRES_PER_METRE
	}
	if total > OCTAVE_RELIEF_LIMIT_MILLIMETRES {
		return fmt.tprintf("relief_octaves with the ledges and the basins add up to %d mm, more than %d", total, OCTAVE_RELIEF_LIMIT_MILLIMETRES)
	}
	return ""
}

// A term's other keys are checked only while the term is on, so the zero
// shape (a planet or a world file without it) passes.
relief_shape_problem :: proc(shape: Relief_Shape) -> string {
	switch {
	case shape.ledge_amplitude_millimetres < 0 || shape.ledge_amplitude_millimetres > OCTAVE_RELIEF_LIMIT_MILLIMETRES:
		return fmt.tprintf("relief_shape.ledge_amplitude_millimetres %d is outside 0 to %d", shape.ledge_amplitude_millimetres, OCTAVE_RELIEF_LIMIT_MILLIMETRES)
	case shape.ledge_amplitude_millimetres > 0 && (shape.ledge_wavelength_metres < 1 || shape.ledge_wavelength_metres > MAXIMUM_RELIEF_WAVELENGTH_METRES):
		return fmt.tprintf("relief_shape.ledge_wavelength_metres %d is outside 1 to %d", shape.ledge_wavelength_metres, MAXIMUM_RELIEF_WAVELENGTH_METRES)
	case shape.ledge_amplitude_millimetres > 0 && (shape.ledge_sharpness < 1 || shape.ledge_sharpness > MAXIMUM_LEDGE_SHARPNESS):
		return fmt.tprintf("relief_shape.ledge_sharpness %d is outside 1 to %d", shape.ledge_sharpness, MAXIMUM_LEDGE_SHARPNESS)
	case shape.terrace_rise_millimetres < 0 || shape.terrace_rise_millimetres > OCTAVE_RELIEF_LIMIT_MILLIMETRES:
		return fmt.tprintf("relief_shape.terrace_rise_millimetres %d is outside 0 to %d", shape.terrace_rise_millimetres, OCTAVE_RELIEF_LIMIT_MILLIMETRES)
	case shape.terrace_rise_millimetres > 0 && (shape.terrace_riser_permille < 1 || shape.terrace_riser_permille > 1000):
		return fmt.tprintf("relief_shape.terrace_riser_permille %d is outside 1 to 1000", shape.terrace_riser_permille)
	case shape.basin_depth_metres < 0 || shape.basin_depth_metres > OCTAVE_RELIEF_LIMIT_METRES:
		return fmt.tprintf("relief_shape.basin_depth_metres %d is outside 0 to %d", shape.basin_depth_metres, OCTAVE_RELIEF_LIMIT_METRES)
	case shape.basin_depth_metres > 0 && (shape.basin_threshold_percent < -99 || shape.basin_threshold_percent > 100):
		return fmt.tprintf("relief_shape.basin_threshold_percent %d is outside -99 to 100", shape.basin_threshold_percent)
	}
	return ""
}

// The zero value (off: a planet or a world file without them) passes;
// otherwise every key within its bound, a knot named with its index.
landforms_problem :: proc(landforms: Planet_Landforms) -> string {
	if landforms == {} {
		return ""
	}
	bounds := [?]Config_Bound {
		{"warp_wavelength_metres", landforms.warp_wavelength_metres, 1, MAXIMUM_RELIEF_WAVELENGTH_METRES},
		{"warp_metres", landforms.warp_metres, 0, MAXIMUM_LANDFORM_WARP_METRES},
		{"region_wavelength_metres", landforms.region_wavelength_metres, 1, MAXIMUM_RELIEF_WAVELENGTH_METRES},
		{"range_wavelength_metres", landforms.range_wavelength_metres, 1, MAXIMUM_RELIEF_WAVELENGTH_METRES},
		{"range_metres", landforms.range_metres, 0, MAXIMUM_RELIEF_HEIGHT_METRES},
		{"spur_wavelength_metres", landforms.spur_wavelength_metres, 1, MAXIMUM_RELIEF_WAVELENGTH_METRES},
		{"spur_percent", landforms.spur_percent, 0, 100},
		{"hill_wavelength_metres", landforms.hill_wavelength_metres, 1, MAXIMUM_RELIEF_WAVELENGTH_METRES},
		{"hill_metres", landforms.hill_metres, 0, MAXIMUM_RELIEF_HEIGHT_METRES},
		{"home_metres", landforms.home_metres, -MAXIMUM_RELIEF_DEPTH_METRES, MAXIMUM_RELIEF_HEIGHT_METRES},
		{"wild_metres", landforms.wild_metres, 1, MAXIMUM_LANDFORM_WILD_METRES},
		{"calm_metres", landforms.calm_metres, 0, landforms.wild_metres - 1},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("landforms.%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	curves := [?]struct {
		name:             string,
		knots:            [LANDFORM_KNOT_COUNT]int,
		minimum, maximum: int,
	} {
		{"region_heights_metres", landforms.region_heights_metres, -MAXIMUM_RELIEF_DEPTH_METRES, MAXIMUM_RELIEF_HEIGHT_METRES},
		{"region_ranges_percent", landforms.region_ranges_percent, 0, 100},
		{"region_hills_percent", landforms.region_hills_percent, 0, 100},
	}
	for curve in curves {
		for knot, index in curve.knots {
			if knot < curve.minimum || knot > curve.maximum {
				return fmt.tprintf("landforms.%s[%d] %d is outside %d to %d", curve.name, index, knot, curve.minimum, curve.maximum)
			}
		}
	}
	return ""
}

// The zero value (off: a planet or a world file without them) passes;
// otherwise they need the landforms, and every key lies within its bound:
// a feature's own keys only while it is on (the gorges while gorge_metres
// and gorge_width_permille are above 0, the mesas while mesa_metres is, a
// site kind while its share is), so a later kind's keys may be absent
// from a world recorded before it; the masks, the fade, the switches, the
// shares, the wobble and the spacing always.
landmarks_problem :: proc(landmarks: Planet_Landmarks, landforms: Planet_Landforms) -> string {
	if landmarks == {} {
		return ""
	}
	if landforms == {} {
		return "landmarks need landforms"
	}
	always := [?]Config_Bound {
		{"gorge_mask_percent", landmarks.gorge_mask_percent, 0, 100},
		{"mesa_mask_percent", landmarks.mesa_mask_percent, 0, 100},
		{"mask_fade_percent", landmarks.mask_fade_percent, 1, 100},
		{"gorge_width_permille", landmarks.gorge_width_permille, 0, 1000},
		{"gorge_metres", landmarks.gorge_metres, 0, MAXIMUM_RELIEF_DEPTH_METRES},
		{"dry_metres", landmarks.dry_metres, 0, MAXIMUM_RELIEF_HEIGHT_METRES},
		{"mesa_metres", landmarks.mesa_metres, 0, MAXIMUM_LANDMARK_METRES},
		{"spire_percent", landmarks.spire_percent, 0, 100},
		{"butte_percent", landmarks.butte_percent, 0, 100},
		{"sinkhole_percent", landmarks.sinkhole_percent, 0, 100},
		{"arch_percent", landmarks.arch_percent, 0, 100},
		{"grotto_percent", landmarks.grotto_percent, 0, 100},
		{"mushroom_percent", landmarks.mushroom_percent, 0, 100},
		{"wobble_percent", landmarks.wobble_percent, 0, MAXIMUM_LANDMARK_WOBBLE_PERCENT},
	}
	if problem := landmark_bounds_problem(always[:]); problem != "" {
		return problem
	}
	if landmarks.gorge_metres > 0 && landmarks.gorge_width_permille > 0 {
		if problem := landmark_gorges_problem(landmarks); problem != "" {
			return problem
		}
	}
	if landmarks.mesa_metres > 0 {
		if problem := landmark_mesas_problem(landmarks); problem != "" {
			return problem
		}
	}
	return landmark_sites_problem(landmarks)
}

landmark_gorges_problem :: proc(landmarks: Planet_Landmarks) -> string {
	bounds := [?]Config_Bound {
		{"gorge_wavelength_metres", landmarks.gorge_wavelength_metres, 1, MAXIMUM_RELIEF_WAVELENGTH_METRES},
		{"gorge_meander_percent", landmarks.gorge_meander_percent, 0, 100},
		{"gorge_floor_percent", landmarks.gorge_floor_percent, 0, 99},
	}
	if problem := landmark_bounds_problem(bounds[:]); problem != "" {
		return problem
	}
	return landmark_curve_problem("region_gorges_percent", landmarks.region_gorges_percent)
}

landmark_mesas_problem :: proc(landmarks: Planet_Landmarks) -> string {
	bounds := [?]Config_Bound {
		{"mesa_wavelength_metres", landmarks.mesa_wavelength_metres, 1, MAXIMUM_RELIEF_WAVELENGTH_METRES},
		{"mesa_rough_percent", landmarks.mesa_rough_percent, 0, 100},
		{"mesa_threshold_percent", landmarks.mesa_threshold_percent, 0, 100},
		{"mesa_tier_percent", landmarks.mesa_tier_percent, 0, 100},
		{"mesa_edge_permille", landmarks.mesa_edge_permille, 1, 1000},
	}
	if problem := landmark_bounds_problem(bounds[:]); problem != "" {
		return problem
	}
	return landmark_curve_problem("region_mesas_percent", landmarks.region_mesas_percent)
}

// The shares together, each kind's pairs (and the butte's stretch) while
// it is on, then the spacing, which holds two of the widest site.
landmark_sites_problem :: proc(landmarks: Planet_Landmarks) -> string {
	shares := landmarks.spire_percent + landmarks.butte_percent + landmarks.sinkhole_percent + landmarks.arch_percent + landmarks.grotto_percent + landmarks.mushroom_percent
	if shares > 100 {
		return fmt.tprintf("landmarks' site shares add up to %d, more than 100", shares)
	}
	if landmarks.spire_percent > 0 {
		if problem := landmark_kind_problem("spire", landmarks.spire_radius_metres, landmarks.spire_metres); problem != "" {
			return problem
		}
	}
	if landmarks.butte_percent > 0 {
		if problem := landmark_kind_problem("butte", landmarks.butte_radius_metres, landmarks.butte_metres); problem != "" {
			return problem
		}
		stretch := [?]Config_Bound{{"butte_stretch_percent", landmarks.butte_stretch_percent, 100, MAXIMUM_LANDMARK_STRETCH_PERCENT}}
		if problem := landmark_bounds_problem(stretch[:]); problem != "" {
			return problem
		}
	}
	if landmarks.sinkhole_percent > 0 {
		if problem := landmark_kind_problem("sinkhole", landmarks.sinkhole_radius_metres, landmarks.sinkhole_metres); problem != "" {
			return problem
		}
	}
	if landmarks.arch_percent > 0 {
		if problem := landmark_pair_problem("arch_length_metres", landmarks.arch_length_metres); problem != "" {
			return problem
		}
		if problem := landmark_pair_problem("arch_metres", landmarks.arch_metres); problem != "" {
			return problem
		}
	}
	if landmarks.grotto_percent > 0 {
		if problem := landmark_kind_problem("grotto", landmarks.grotto_radius_metres, landmarks.grotto_metres); problem != "" {
			return problem
		}
	}
	if landmarks.mushroom_percent > 0 {
		if problem := landmark_kind_problem("mushroom", landmarks.mushroom_radius_metres, landmarks.mushroom_metres); problem != "" {
			return problem
		}
	}
	spacing := [?]Config_Bound{{"site_spacing_metres", landmarks.site_spacing_metres, 2 * landmark_widest_site_metres(landmarks) + 2, MAXIMUM_LANDFORM_WILD_METRES}}
	return landmark_bounds_problem(spacing[:])
}

// A site kind's radius and height pairs (<kind>_radius_metres,
// <kind>_metres).
landmark_kind_problem :: proc(kind: string, radius, height: [2]int) -> string {
	if problem := landmark_pair_problem(fmt.tprintf("%s_radius_metres", kind), radius); problem != "" {
		return problem
	}
	return landmark_pair_problem(fmt.tprintf("%s_metres", kind), height)
}

// Each value 1 to MAXIMUM_LANDMARK_METRES, the least at most the most.
landmark_pair_problem :: proc(name: string, pair: [2]int) -> string {
	for value, index in pair {
		if value < 1 || value > MAXIMUM_LANDMARK_METRES {
			return fmt.tprintf("landmarks.%s[%d] %d is outside 1 to %d", name, index, value, MAXIMUM_LANDMARK_METRES)
		}
	}
	if pair[0] > pair[1] {
		return fmt.tprintf("landmarks.%s [%d, %d] runs backwards", name, pair[0], pair[1])
	}
	return ""
}

landmark_curve_problem :: proc(name: string, knots: [LANDFORM_KNOT_COUNT]int) -> string {
	for knot, index in knots {
		if knot < 0 || knot > 100 {
			return fmt.tprintf("landmarks.%s[%d] %d is outside 0 to 100", name, index, knot)
		}
	}
	return ""
}

landmark_bounds_problem :: proc(bounds: []Config_Bound) -> string {
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("landmarks.%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	return ""
}

// The farthest any site that is on reaches from its centre, in whole
// metres rounded up: its kind's most radius times its most stretch, an
// arch's half its most length.
landmark_widest_site_metres :: proc(landmarks: Planet_Landmarks) -> int {
	widest := 0
	if landmarks.spire_percent > 0 {
		widest = max(widest, (landmarks.spire_radius_metres[1] * SPIRE_STRETCH_PERCENT + 99) / 100)
	}
	if landmarks.butte_percent > 0 {
		widest = max(widest, (landmarks.butte_radius_metres[1] * landmarks.butte_stretch_percent + 99) / 100)
	}
	if landmarks.sinkhole_percent > 0 {
		widest = max(widest, (landmarks.sinkhole_radius_metres[1] * SINKHOLE_STRETCH_PERCENT + 99) / 100)
	}
	if landmarks.arch_percent > 0 {
		widest = max(widest, (landmarks.arch_length_metres[1] + 1) / 2)
	}
	if landmarks.grotto_percent > 0 {
		widest = max(widest, (landmarks.grotto_radius_metres[1] * GROTTO_STRETCH_PERCENT + 99) / 100)
	}
	if landmarks.mushroom_percent > 0 {
		widest = max(widest, (landmarks.mushroom_radius_metres[1] * MUSHROOM_STRETCH_PERCENT + 99) / 100)
	}
	return widest
}

// The zero value (off: a planet without one) passes; otherwise the field
// (climate_field_bounds_problem, a zero field too, since a present climate
// is on) and every look key within its bound.
climate_problem :: proc(climate: Planet_Climate) -> string {
	if climate == {} {
		return ""
	}
	if problem := climate_field_bounds_problem(planet_climate_field(climate)); problem != "" {
		return problem
	}
	bounds := [?]Config_Bound {
		{"grass_cold_celsius", climate.grass_cold_celsius, -MAXIMUM_CLIMATE_CELSIUS, MAXIMUM_CLIMATE_CELSIUS},
		{"grass_hot_celsius", climate.grass_hot_celsius, -MAXIMUM_CLIMATE_CELSIUS, MAXIMUM_CLIMATE_CELSIUS},
		{"snow_celsius", climate.snow_celsius, -MAXIMUM_CLIMATE_CELSIUS, MAXIMUM_CLIMATE_CELSIUS},
		{"snow_fade_celsius", climate.snow_fade_celsius, 1, MAXIMUM_SNOW_FADE_CELSIUS},
		{"sand_metres", climate.sand_metres, -MAXIMUM_SAND_METRES, MAXIMUM_SAND_METRES},
		{"sand_fade_metres", climate.sand_fade_metres, 1, MAXIMUM_SAND_METRES},
	}
	if problem := climate_bounds_problem(bounds[:]); problem != "" {
		return problem
	}
	if climate.grass_hot_celsius <= climate.grass_cold_celsius {
		return fmt.tprintf("climate.grass_hot_celsius %d is not above grass_cold_celsius %d", climate.grass_hot_celsius, climate.grass_cold_celsius)
	}
	for color, index in climate.grass_colors {
		if problem := climate_color_problem(fmt.tprintf("grass_colors[%d]", index), color); problem != "" {
			return problem
		}
	}
	if problem := climate_color_problem("snow_color", climate.snow_color); problem != "" {
		return problem
	}
	return climate_color_problem("sand_color", climate.sand_color)
}

// The zero value (off: a world file written before the climate) passes;
// otherwise every key within its bound.
climate_field_problem :: proc(field: Planet_Climate_Field) -> string {
	if field == {} {
		return ""
	}
	return climate_field_bounds_problem(field)
}

// Every key within its bound, the zero value too: a planet's climate is
// on whenever it is present (climate_problem).
climate_field_bounds_problem :: proc(field: Planet_Climate_Field) -> string {
	bounds := [?]Config_Bound {
		{"temperature_wavelength_metres", field.temperature_wavelength_metres, MINIMUM_CLIMATE_WAVELENGTH_METRES, MAXIMUM_RELIEF_WAVELENGTH_METRES},
		{"moisture_wavelength_metres", field.moisture_wavelength_metres, MINIMUM_CLIMATE_WAVELENGTH_METRES, MAXIMUM_RELIEF_WAVELENGTH_METRES},
		{"sea_level_celsius", field.sea_level_celsius, -MAXIMUM_CLIMATE_CELSIUS, MAXIMUM_CLIMATE_CELSIUS},
		{"temperature_spread_celsius", field.temperature_spread_celsius, 0, MAXIMUM_CLIMATE_CELSIUS},
		{"lapse_millicelsius_per_metre", field.lapse_millicelsius_per_metre, 0, MAXIMUM_LAPSE_MILLICELSIUS_PER_METRE},
		{"moisture_percent", field.moisture_percent, 0, 100},
		{"moisture_spread_percent", field.moisture_spread_percent, 0, 100},
	}
	return climate_bounds_problem(bounds[:])
}

climate_bounds_problem :: proc(bounds: []Config_Bound) -> string {
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("climate.%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	return ""
}

climate_color_problem :: proc(name: string, color: [3]int) -> string {
	for component in color {
		if component < 0 || component > MAXIMUM_COLOR_COMPONENT {
			return fmt.tprintf("climate.%s has %d, outside 0 to %d", name, component, MAXIMUM_COLOR_COMPONENT)
		}
	}
	return ""
}

// The zero value (off: a planet or a world file without them) passes;
// otherwise every key within its bound, the grid no more than
// MAXIMUM_WATERS_GRID_HALF_CELLS cells either side of the home.
waters_problem :: proc(waters: Planet_Waters) -> string {
	if waters == {} {
		return ""
	}
	bounds := [?]Config_Bound {
		{"reach_metres", waters.reach_metres, MINIMUM_WATERS_REACH_METRES, MAXIMUM_WATERS_REACH_METRES},
		{"grid_metres", waters.grid_metres, 4, 64},
		{"clearing_metres", waters.clearing_metres, 0, waters.reach_metres},
		{"spring_catchment_square_metres", waters.spring_catchment_square_metres, waters.grid_metres * waters.grid_metres, 4_000_000},
		{"spring_minimum_metres", waters.spring_minimum_metres, 0, MAXIMUM_RELIEF_HEIGHT_METRES},
		{"spring_spacing_metres", waters.spring_spacing_metres, MINIMUM_SPRING_SPACING_METRES, 10_000},
		{"lake_minimum_depth_millimetres", waters.lake_minimum_depth_millimetres, 100, 64_000},
		{"lake_minimum_area_square_metres", waters.lake_minimum_area_square_metres, 4, 1_000_000},
		{"lake_maximum_metres", waters.lake_maximum_metres, 16, 1024},
		{"lake_margin_millimetres", waters.lake_margin_millimetres, 0, 4000},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("waters.%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	if cells := waters.reach_metres / waters.grid_metres; cells > MAXIMUM_WATERS_GRID_HALF_CELLS {
		return fmt.tprintf("waters.reach_metres %d is %d cells of grid_metres %d, more than %d", waters.reach_metres, cells, waters.grid_metres, MAXIMUM_WATERS_GRID_HALF_CELLS)
	}
	if waters.tile_metres == 0 {
		return ""
	}
	if waters.tile_metres < MINIMUM_WATER_TILE_METRES || waters.tile_metres > MAXIMUM_WATER_TILE_METRES {
		return fmt.tprintf("waters.tile_metres %d is outside %d to %d", waters.tile_metres, MINIMUM_WATER_TILE_METRES, MAXIMUM_WATER_TILE_METRES)
	}
	if waters.tile_metres % waters.grid_metres != 0 {
		return fmt.tprintf("waters.tile_metres %d is not a multiple of grid_metres %d", waters.tile_metres, waters.grid_metres)
	}
	if cells := waters.spring_catchment_square_metres / (waters.grid_metres * waters.grid_metres); cells > MAXIMUM_TILE_CATCHMENT_CELLS {
		return fmt.tprintf("waters.spring_catchment_square_metres %d is %d cells of grid_metres %d, more than %d with tiles", waters.spring_catchment_square_metres, cells, waters.grid_metres, MAXIMUM_TILE_CATCHMENT_CELLS)
	}
	return ""
}

// The farthest a lake's mask holds a point from its pit, in metres: the
// refine window's half diagonal (3/2 over the square root of 2).
water_lake_reach_metres :: proc(waters: Planet_Waters) -> int {
	return (waters.lake_maximum_metres / (2 * LAKE_CELL_METRES) + 1) * LAKE_CELL_METRES * 3 / 2
}

// The farthest round a point the tiles are asked (0326): a spring's
// spacing and a lake's reach, two lakes' reach, a lake's reach and a box
// that asks for lakes.
water_query_reach_metres :: proc(waters: Planet_Waters) -> int {
	lake := water_lake_reach_metres(waters)
	return max(waters.spring_spacing_metres + lake, 2 * lake, lake + WATER_QUERY_BOX_METRES)
}

// With tiles, the reach round a point at most 21 percent of the radius,
// which keeps water_tiles_near's test of a face by its corners exact: a
// scan found tiles skipped from 22 percent (0326's second review).
waters_planet_problem :: proc(planet: Planet) -> string {
	if planet.waters.tile_metres == 0 {
		return ""
	}
	if reach := water_query_reach_metres(planet.waters); 100 * reach > 21 * planet.radius_metres {
		return fmt.tprintf("waters reach %d m round a point, more than 21 percent of the radius %d m", reach, planet.radius_metres)
	}
	return ""
}

// The cover (0311): none passes; kinds need the climate, at most
// MAXIMUM_COVER_KINDS of them, each with a unique id and every key within
// its bound (cover_kind_problem).
cover_problem :: proc(cover: Planet_Cover, climate: Planet_Climate) -> string {
	if len(cover.kinds) == 0 {
		return ""
	}
	if climate == {} {
		return "cover needs the climate"
	}
	if len(cover.kinds) > MAXIMUM_COVER_KINDS {
		return fmt.tprintf("cover has %d kinds, more than %d", len(cover.kinds), MAXIMUM_COVER_KINDS)
	}
	for kind, index in cover.kinds {
		if problem := cover_kind_problem(kind, index); problem != "" {
			return problem
		}
		for earlier in cover.kinds[:index] {
			if earlier.id == kind.id {
				return fmt.tprintf("cover.kinds[%d].id %q is used twice", index, kind.id)
			}
		}
	}
	return ""
}

// One kind's keys, the message naming the key with the kind's index.
cover_kind_problem :: proc(kind: Planet_Cover_Kind, index: int) -> string {
	if kind.id == "" || len(kind.id) > MAXIMUM_COVER_KIND_ID_LENGTH {
		return fmt.tprintf("cover.kinds[%d].id %q is not 1 to %d bytes", index, kind.id, MAXIMUM_COVER_KIND_ID_LENGTH)
	}
	shape, shape_found := parse_named_enum(cover_shape_names, kind.shape)
	if !shape_found {
		return fmt.tprintf("cover.kinds[%d].shape %q is not blades, flower, fern, pebble or crystal", index, kind.shape)
	}
	if _, source_found := parse_named_enum(cover_color_source_names, kind.color_from); !source_found {
		return fmt.tprintf("cover.kinds[%d].color_from %q is not grass, ground or colors", index, kind.color_from)
	}
	parts_least, parts_most := 1, MAXIMUM_COVER_PARTS
	if !cover_shape_is_foliage(shape) {
		parts_least, parts_most = 0, 0
	}
	ranges := [?]Cover_Range_Bound {
		{"temperature_celsius", kind.temperature_celsius, -MAXIMUM_CLIMATE_CELSIUS, MAXIMUM_CLIMATE_CELSIUS},
		{"moisture_percent", kind.moisture_percent, 0, 100},
		{"slope_degrees", kind.slope_degrees, 0, 90},
		{"width_millimetres", kind.width_millimetres, 10, MAXIMUM_COVER_SIZE_MILLIMETRES},
		{"height_millimetres", kind.height_millimetres, 10, MAXIMUM_COVER_SIZE_MILLIMETRES},
	}
	if problem := cover_ranges_problem(ranges[:], index); problem != "" {
		return problem
	}
	surfaces := kind.surfaces
	bounds := [?]Config_Bound {
		{"parts", kind.parts, parts_least, parts_most},
		{"per_hundred_square_metres", kind.per_hundred_square_metres, 0, MAXIMUM_COVER_PER_HUNDRED_SQUARE_METRES},
		{"temperature_fade_celsius", kind.temperature_fade_celsius, 1, 50},
		{"moisture_fade_percent", kind.moisture_fade_percent, 1, 100},
		{"slope_fade_degrees", kind.slope_fade_degrees, 1, 90},
		{"surfaces.grass", surfaces.grass, 0, 100},
		{"surfaces.sand", surfaces.sand, 0, 100},
		{"surfaces.snow", surfaces.snow, 0, 100},
		{"surfaces.rock", surfaces.rock, 0, 100},
		{"surfaces.stone", surfaces.stone, 0, 100},
		{"surfaces.hematite", surfaces.hematite, 0, 100},
		{"surfaces.chalcopyrite", surfaces.chalcopyrite, 0, 100},
		{"surfaces.coal", surfaces.coal, 0, 100},
		{"boundary_percent", kind.boundary_percent, 0, 100},
		{"patch_threshold_percent", kind.patch_threshold_percent, -100, 100},
		{"patch_edge_percent", kind.patch_edge_percent, 1, 200},
		{"sink_percent", kind.sink_percent, 0, 90},
		{"far_metres", kind.far_metres, 1, MAXIMUM_COVER_FAR_METRES},
		{"near_metres", kind.near_metres, 0, kind.far_metres},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("cover.kinds[%d].%s %d is outside %d to %d", index, bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	if wavelength := kind.patch_wavelength_metres; wavelength != 0 && (wavelength < 2 || wavelength > 512) {
		return fmt.tprintf("cover.kinds[%d].patch_wavelength_metres %d is neither 0 nor 2 to 512", index, wavelength)
	}
	if len(kind.colors) < 1 || len(kind.colors) > MAXIMUM_COVER_COLORS {
		return fmt.tprintf("cover.kinds[%d].colors has %d colours, not 1 to %d", index, len(kind.colors), MAXIMUM_COVER_COLORS)
	}
	for color, color_index in kind.colors {
		for component in color {
			if component < 0 || component > MAXIMUM_COLOR_COMPONENT {
				return fmt.tprintf("cover.kinds[%d].colors[%d] has %d, outside 0 to %d", index, color_index, component, MAXIMUM_COLOR_COMPONENT)
			}
		}
	}
	return ""
}


// A least and most pair of a cover kind and the bounds of both.
Cover_Range_Bound :: struct {
	name:             string,
	value:            [2]int,
	minimum, maximum: int,
}

// Each pair within its bounds and least first.
cover_ranges_problem :: proc(ranges: []Cover_Range_Bound, index: int) -> string {
	for range in ranges {
		for value in range.value {
			if value < range.minimum || value > range.maximum {
				return fmt.tprintf("cover.kinds[%d].%s has %d, outside %d to %d", index, range.name, value, range.minimum, range.maximum)
			}
		}
		if range.value[0] > range.value[1] {
			return fmt.tprintf("cover.kinds[%d].%s [%d, %d] runs backwards", index, range.name, range.value[0], range.value[1])
		}
	}
	return ""
}

// The keys a world records (Planet_Generation_Record.climate).
planet_climate_field :: proc(climate: Planet_Climate) -> Planet_Climate_Field {
	return Planet_Climate_Field {
		temperature_wavelength_metres = climate.temperature_wavelength_metres,
		moisture_wavelength_metres = climate.moisture_wavelength_metres,
		sea_level_celsius = climate.sea_level_celsius,
		temperature_spread_celsius = climate.temperature_spread_celsius,
		lapse_millicelsius_per_metre = climate.lapse_millicelsius_per_metre,
		moisture_percent = climate.moisture_percent,
		moisture_spread_percent = climate.moisture_spread_percent,
	}
}

// The climate with the field's keys replaced, its look kept.
with_climate_field :: proc(climate: Planet_Climate, field: Planet_Climate_Field) -> Planet_Climate {
	result := climate
	result.temperature_wavelength_metres = field.temperature_wavelength_metres
	result.moisture_wavelength_metres = field.moisture_wavelength_metres
	result.sea_level_celsius = field.sea_level_celsius
	result.temperature_spread_celsius = field.temperature_spread_celsius
	result.lapse_millicelsius_per_metre = field.lapse_millicelsius_per_metre
	result.moisture_percent = field.moisture_percent
	result.moisture_spread_percent = field.moisture_spread_percent
	return result
}

// A planet with landforms keeps its bound within the caps, the crater on
// the calm plain and the home's crater floor dry for every seed (the
// region blends to home_metres there, so only the detail below it varies),
// so find_dry_planet_home keeps the record's home and the landforms'
// centre is the home the world records.
landforms_planet_problem :: proc(planet: Planet) -> string {
	landforms := planet.landforms
	if landforms == {} {
		return ""
	}
	bounds := planet_relief_bounds(planet)
	reach := crater_reach_metres(planet.crater)
	floor := metres_to_position_units(i64(landforms.home_metres)) - relief_detail_below(planet.relief_octaves, planet.relief_shape) - metres_to_position_units(i64(planet.crater.depth_metres))
	dry := metres_to_position_units(i64(planet.sea_level_metres)) + millimetres_to_position_units(HOME_DRY_MARGIN_MILLIMETRES)
	switch {
	case -bounds.lowest > metres_to_position_units(MAXIMUM_RELIEF_DEPTH_METRES):
		return fmt.tprintf("the relief with the landforms reaches %d m below the radius, more than %d", relief_depth_metres(bounds), MAXIMUM_RELIEF_DEPTH_METRES)
	case bounds.highest > metres_to_position_units(MAXIMUM_RELIEF_HEIGHT_METRES):
		return fmt.tprintf("the relief with the landforms reaches %d m above the radius, more than %d", ceiling_divide_i64(bounds.highest, POSITION_UNITS_PER_METRE), MAXIMUM_RELIEF_HEIGHT_METRES)
	case landforms.calm_metres < reach:
		return fmt.tprintf("landforms.calm_metres %d is inside the crater's reach of %d m", landforms.calm_metres, reach)
	case floor < dry:
		return fmt.tprintf("landforms.home_metres %d can put the crater's floor %d mm under the sea level's dry margin", landforms.home_metres, (dry - floor) * MILLIMETRES_PER_METRE / POSITION_UNITS_PER_METRE)
	}
	return ""
}

// The most the octaves and the ledges raise the ground (0306), in
// position units: each amplitude truncated no further than the term's own
// bound, so no relief leaves it.
relief_detail_above :: proc(octaves: [RELIEF_OCTAVE_COUNT]Relief_Octave, shape: Relief_Shape) -> i64 {
	above := millimetres_to_position_units(shape.ledge_amplitude_millimetres)
	for octave in octaves {
		above += metres_to_position_units(i64(octave.amplitude_metres))
	}
	return above
}

// The most the octaves, the ledges and the basins lower the ground.
relief_detail_below :: proc(octaves: [RELIEF_OCTAVE_COUNT]Relief_Octave, shape: Relief_Shape) -> i64 {
	return relief_detail_above(octaves, shape) + metres_to_position_units(i64(shape.basin_depth_metres))
}

// The relief's bound (0306): without landforms OCTAVE_RELIEF_LIMIT_METRES
// both ways, whatever the octaves add up to, so an old world's shortcuts
// and crater clamps stay bit for bit; with them the knots' extremes, the
// strongest ranges and hills and the detail, each truncated toward zero no
// further than its term (landform_relief), so no relief leaves it.
relief_bounds :: proc(octaves: [RELIEF_OCTAVE_COUNT]Relief_Octave, shape: Relief_Shape, landforms: Planet_Landforms) -> Relief_Bounds {
	if landforms == {} {
		limit := metres_to_position_units(OCTAVE_RELIEF_LIMIT_METRES)
		return {-limit, limit}
	}
	lowest, highest := landforms.home_metres, landforms.home_metres
	most_ranges, most_hills := 0, 0
	for index in 0 ..< LANDFORM_KNOT_COUNT {
		lowest = min(lowest, landforms.region_heights_metres[index])
		highest = max(highest, landforms.region_heights_metres[index])
		most_ranges = max(most_ranges, landforms.region_ranges_percent[index])
		most_hills = max(most_hills, landforms.region_hills_percent[index])
	}
	hills := metres_to_position_units(i64(landforms.hill_metres)) * i64(most_hills) / 100
	ranges := metres_to_position_units(i64(landforms.range_metres)) * i64(most_ranges) / 100
	return Relief_Bounds {
		lowest = metres_to_position_units(i64(lowest)) - hills - relief_detail_below(octaves, shape),
		highest = metres_to_position_units(i64(highest)) + ranges + hills + relief_detail_above(octaves, shape),
	}
}

planet_relief_bounds :: proc(planet: Planet) -> Relief_Bounds {
	return relief_bounds(planet.relief_octaves, planet.relief_shape, planet.landforms)
}

// The bound's depth below the radius in whole metres, rounded up, for the
// readers in metres (the globe, the bedrock's minimum).
relief_depth_metres :: proc(bounds: Relief_Bounds) -> int {
	return int(ceiling_divide_i64(-bounds.lowest, POSITION_UNITS_PER_METRE))
}

// Below every local surface's deep stone (planet_problem).
minimum_bedrock_depth_metres :: proc(planet: Planet) -> int {
	return relief_depth_metres(planet_relief_bounds(planet)) + DEEP_STONE_DEPTH_METRES
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
	if problem := trees_problem(planet.trees, planet.crater, planet_climate_field(planet.climate)); problem != "" {
		return problem
	}
	if problem := relief_problem(planet.relief_octaves, planet.relief_shape); problem != "" {
		return problem
	}
	if problem := landforms_problem(planet.landforms); problem != "" {
		return problem
	}
	if problem := landforms_planet_problem(planet); problem != "" {
		return problem
	}
	if problem := landmarks_problem(planet.landmarks, planet.landforms); problem != "" {
		return problem
	}
	if problem := climate_problem(planet.climate); problem != "" {
		return problem
	}
	if problem := waters_problem(planet.waters); problem != "" {
		return problem
	}
	if problem := waters_planet_problem(planet); problem != "" {
		return problem
	}
	if problem := cover_problem(planet.cover, planet.climate); problem != "" {
		return problem
	}
	// Bedrock lies below every local surface's deep stone, so a valley at
	// the lowest relief never shows bedrock in place of topsoil.
	minimum_bedrock := minimum_bedrock_depth_metres(planet)
	if planet.bedrock_depth_metres < minimum_bedrock || planet.bedrock_depth_metres >= planet.radius_metres {
		return fmt.tprintf("bedrock_depth_metres %d is outside %d to %d", planet.bedrock_depth_metres, minimum_bedrock, planet.radius_metres - 1)
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

// The forest is on (0310): a cover wavelength other than 0.
planet_forest_on :: proc(forest: Planet_Forest) -> bool {
	return forest.cover_wavelength_metres != 0
}

// A grove share of 0 with the forest off is no trees and skips the rest;
// otherwise every key within its bounds (the grove keys only with a grove
// share above 0), the clearing at least the crater's reach, each species
// (tree_species_problem) and, with the forest on (0310), the forest
// (forest_problem) and each species' placement
// (tree_species_placement_problem).
trees_problem :: proc(trees: Planet_Trees, crater: Planet_Crater, climate: Planet_Climate_Field) -> string {
	forest_on := planet_forest_on(trees.forest)
	if trees.grove_share_percent == 0 && !forest_on {
		return ""
	}
	switch {
	case trees.grove_share_percent < 0 || trees.grove_share_percent > 100:
		return fmt.tprintf("trees.grove_share_percent %d is outside 0 to 100", trees.grove_share_percent)
	case trees.tree_spacing_metres < MINIMUM_TREE_SPACING_METRES || trees.tree_spacing_metres > MAXIMUM_TREE_SPACING_METRES:
		return fmt.tprintf("trees.tree_spacing_metres %d is outside %d to %d", trees.tree_spacing_metres, MINIMUM_TREE_SPACING_METRES, MAXIMUM_TREE_SPACING_METRES)
	case trees.grove_share_percent > 0 && (trees.grove_spacing_metres < 2 * trees.tree_spacing_metres || trees.grove_spacing_metres > MAXIMUM_GROVE_SPACING_METRES):
		return fmt.tprintf("trees.grove_spacing_metres %d is outside %d to %d", trees.grove_spacing_metres, 2 * trees.tree_spacing_metres, MAXIMUM_GROVE_SPACING_METRES)
	case trees.grove_share_percent > 0 && (trees.grove_radius_metres < trees.tree_spacing_metres || trees.grove_radius_metres > trees.grove_spacing_metres):
		return fmt.tprintf("trees.grove_radius_metres %d is outside %d to %d", trees.grove_radius_metres, trees.tree_spacing_metres, trees.grove_spacing_metres)
	}
	reach := crater_reach_metres(crater)
	switch {
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
	if !forest_on {
		return ""
	}
	if problem := forest_problem(trees.forest, trees, climate); problem != "" {
		return problem
	}
	for species, index in trees.species {
		if problem := tree_species_placement_problem(tree_species_placement(species), index); problem != "" {
			return problem
		}
	}
	return ""
}

// Every forest key within its bound (0310), the gap within the tree
// spacing (it reads only the neighbour cubes), the full slope within the
// trees' maximum, a climate to read and some species above weight 0.
forest_problem :: proc(forest: Planet_Forest, trees: Planet_Trees, climate: Planet_Climate_Field) -> string {
	if climate.temperature_wavelength_metres <= 0 {
		return "trees.forest needs the climate"
	}
	bounds := [?]Config_Bound {
		{"cover_wavelength_metres", forest.cover_wavelength_metres, 64, 4096},
		{"clearing_wavelength_metres", forest.clearing_wavelength_metres, 16, 1024},
		{"clearing_percent", forest.clearing_percent, 0, 100},
		{"cover_threshold_percent", forest.cover_threshold_percent, -100, 100},
		{"edge_percent", forest.edge_percent, 1, 100},
		{"moisture_cover_percent", forest.moisture_cover_percent, 0, 100},
		{"scatter_percent", forest.scatter_percent, 0, 100},
		{"meadow_metres", forest.meadow_metres, 0, MAXIMUM_FOREST_MEADOW_METRES},
		{"minimum_gap_millimetres", forest.minimum_gap_millimetres, 0, trees.tree_spacing_metres * MILLIMETRES_PER_METRE},
		{"full_slope_percent", forest.full_slope_percent, 0, trees.maximum_slope_percent},
		{"stand_wavelength_metres", forest.stand_wavelength_metres, 16, 1024},
		{"stand_percent", forest.stand_percent, 0, 100},
		{"species_fade_celsius", forest.species_fade_celsius, 1, 50},
		{"species_fade_moisture_percent", forest.species_fade_moisture_percent, 1, 100},
		{"species_fade_metres", forest.species_fade_metres, 1, 1000},
		{"species_fade_cover_percent", forest.species_fade_cover_percent, 1, 100},
	}
	for bound in bounds {
		if bound.value < bound.minimum || bound.value > bound.maximum {
			return fmt.tprintf("trees.forest.%s %d is outside %d to %d", bound.name, bound.value, bound.minimum, bound.maximum)
		}
	}
	for species in trees.species {
		if species.weight_percent > 0 {
			return ""
		}
	}
	return "trees.forest has no species above weight_percent 0"
}

// A species' placement keys (0310).
tree_species_placement :: proc(species: Planet_Tree_Species) -> Planet_Tree_Species_Placement {
	return Planet_Tree_Species_Placement {
		temperature_celsius = species.temperature_celsius,
		moisture_percent = species.moisture_percent,
		height_metres = species.height_metres,
		cover_percent = species.cover_percent,
		scale_percent = species.scale_percent,
		weight_percent = species.weight_percent,
	}
}

// The species with its placement keys replaced (0310).
with_tree_species_placement :: proc(species: Planet_Tree_Species, placement: Planet_Tree_Species_Placement) -> Planet_Tree_Species {
	result := species
	result.temperature_celsius = placement.temperature_celsius
	result.moisture_percent = placement.moisture_percent
	result.height_metres = placement.height_metres
	result.cover_percent = placement.cover_percent
	result.scale_percent = placement.scale_percent
	result.weight_percent = placement.weight_percent
	return result
}

// Each range within its bounds, least first (0310), and the weight.
tree_species_placement_problem :: proc(species: Planet_Tree_Species_Placement, index: int) -> string {
	Range_Bound :: struct {
		name:             string,
		value:            [2]int,
		minimum, maximum: int,
	}
	ranges := [?]Range_Bound {
		{"temperature_celsius", species.temperature_celsius, -MAXIMUM_CLIMATE_CELSIUS, MAXIMUM_CLIMATE_CELSIUS},
		{"moisture_percent", species.moisture_percent, 0, 100},
		{"height_metres", species.height_metres, -MAXIMUM_TREE_HEIGHT_METRES, MAXIMUM_TREE_HEIGHT_METRES},
		{"cover_percent", species.cover_percent, 0, 100},
		{"scale_percent", species.scale_percent, MINIMUM_TREE_SCALE_PERCENT, MAXIMUM_TREE_SCALE_PERCENT},
	}
	for range in ranges {
		for value in range.value {
			if value < range.minimum || value > range.maximum {
				return fmt.tprintf("trees.species[%d].%s has %d, outside %d to %d", index, range.name, value, range.minimum, range.maximum)
			}
		}
		if range.value[0] > range.value[1] {
			return fmt.tprintf("trees.species[%d].%s %d is above its most %d", index, range.name, range.value[0], range.value[1])
		}
	}
	if species.weight_percent < 0 || species.weight_percent > 100 {
		return fmt.tprintf("trees.species[%d].weight_percent %d is outside 0 to 100", index, species.weight_percent)
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
	case species.hand_felling_scale_percent < 0 || species.hand_felling_scale_percent > MAXIMUM_TREE_SCALE_PERCENT:
		return fmt.tprintf("trees.species[%d].hand_felling_scale_percent %d is outside 0 to %d", index, species.hand_felling_scale_percent, MAXIMUM_TREE_SCALE_PERCENT)
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

// The keys a world records (Planet_Generation_Record.trees), the forest
// and the species' placement keys with them (0310).
planet_tree_placement :: proc(trees: Planet_Trees) -> Planet_Tree_Placement {
	placement := Planet_Tree_Placement {
		grove_spacing_metres = trees.grove_spacing_metres,
		grove_share_percent = trees.grove_share_percent,
		grove_radius_metres = trees.grove_radius_metres,
		tree_spacing_metres = trees.tree_spacing_metres,
		density_percent = trees.density_percent,
		clearing_metres = trees.clearing_metres,
		maximum_slope_percent = trees.maximum_slope_percent,
		species_count = len(trees.species),
		forest = trees.forest,
	}
	for species, index in trees.species[:min(len(trees.species), MAXIMUM_TREE_SPECIES)] {
		placement.species[index] = tree_species_placement(species)
	}
	return placement
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
