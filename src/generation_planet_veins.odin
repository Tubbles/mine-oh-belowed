package game

import "core:fmt"
import "generation_seed"

// Veins on the sphere (work item 0179, doc/content.md, Veins on the
// sphere; DESIGN.md: ore veins are reservoirs, not voxels). A vein is a
// disc on the planet: a unit direction from the centre and a radius in
// metres along the sphere of the planet's radius. Its outcrop is the
// ground within the disc from the local surface down OUTCROP_DEPTH_METRES,
// which generation turns into the vein's ore material (planet_sample), so
// hand mining the outcrop yields ore through the material table; its
// reservoir is a Vein in the registry (register_planet_veins), which a
// drill standing over the disc taps.
//
// The slice places the three starter veins only, one per ore, round the
// home direction: each in its own third of the circle round the home, at
// PLANET_VEIN_MINIMUM_DISTANCE_METRES to PLANET_VEIN_MAXIMUM_DISTANCE_METRES,
// so all three are in sight of the pod. The rest of the sphere has none
// until M14 scatters veins. The discs are a function of the seed, the
// planet's radius and the home only, never of data/veins.sjson: they
// shape the ground, and a data edit must not reshape the unedited ground
// round saved chunks (the generation record, 0179). The reservoirs come
// from veins.sjson when the veins are registered, and are saved.

MAXIMUM_PLANET_VEINS :: 8
OUTCROP_DEPTH_METRES :: 2
PLANET_VEIN_MINIMUM_DISTANCE_METRES :: 30
PLANET_VEIN_MAXIMUM_DISTANCE_METRES :: 80
// The starter size class's footprint (veins.sjson, scattering).
PLANET_VEIN_MINIMUM_RADIUS_METRES :: 3
PLANET_VEIN_MAXIMUM_RADIUS_METRES :: 5
// The home's crater (0199, crater_relief) never reshapes an outcrop.
#assert(MAXIMUM_CRATER_REACH_METRES < PLANET_VEIN_MINIMUM_DISTANCE_METRES - PLANET_VEIN_MAXIMUM_RADIUS_METRES)
// The starter veins' ores, one vein each, in placement order. The
// material names the vein type: the spawn vein type whose outcrop block
// has the material's name (planet_vein_type).
PLANET_STARTER_VEIN_MATERIALS :: [3]Field_Material{.Hematite_Ore, .Chalcopyrite_Ore, .Coal_Ore}
// A vein's bearing turns by at most this share of its third either way,
// so neighbours stay half a third (a sixth of a turn) apart at least.
PLANET_VEIN_BEARING_SPREAD_DIVISOR :: 4
// The ids of the veins on the sphere: a region no block world vein
// reaches (block_to_region of an i32 block lies within 2^23).
PLANET_VEIN_REGION :: Region_Coordinate{max(i32), max(i32)}

// centre is the disc's centre on the sphere of the planet's radius, in
// position units; radius in position units along it. hash seeds the
// reservoir's size when the vein is registered.
Planet_Vein :: struct {
	material:  Field_Material,
	direction: [3]i64,
	centre:    [3]i64,
	radius:    i64,
	hash:      u64,
}

Planet_Veins :: struct {
	veins: [MAXIMUM_PLANET_VEINS]Planet_Vein,
	count: int,
}

// The tangent along a bearing at the home: 0 is the planet's north
// (frame_north_tangent), a quarter turn its cross with the home.
planet_home_tangent :: proc(home: [3]i64, bearing: i32) -> [3]i64 {
	north := frame_north_tangent(home)
	return fixed_scale(north, fixed_cosine(bearing)) + fixed_scale(fixed_cross(north, home), fixed_sine(bearing))
}

// The direction distance along the tangent from the home on the sphere of
// the radius. The chord from the home to it is shorter by about
// distance^3 / (3 radius^2): a centimetre at 80 m on a 4 km planet.
planet_direction_from_home :: proc(home, tangent: [3]i64, distance, radius: i64) -> [3]i64 {
	direction, ok := normalize_fixed(fixed_scale(home, radius) + fixed_scale(tangent, distance))
	return ok ? direction : home
}

// Vein number of count: its third of the turn from the seeded rotation,
// turned by up to a quarter of the third either way.
planet_vein_bearing :: proc(rotation: i32, number, count: int, hash: u64) -> i32 {
	sector := i64(ANGLE_UNITS_PER_TURN / count)
	spread := sector / PLANET_VEIN_BEARING_SPREAD_DIVISOR
	return rotation + i32(sector * i64(number) + generation_seed.hash_to_range(hash, -spread, spread))
}

plan_planet_vein :: proc(material: Field_Material, home: [3]i64, bearing: i32, radius: i64, hash: u64) -> Planet_Vein {
	distance := metres_to_position_units(generation_seed.hash_to_range(generation_seed.hash_combine(hash, 1), PLANET_VEIN_MINIMUM_DISTANCE_METRES, PLANET_VEIN_MAXIMUM_DISTANCE_METRES))
	disc := metres_to_position_units(generation_seed.hash_to_range(generation_seed.hash_combine(hash, 2), PLANET_VEIN_MINIMUM_RADIUS_METRES, PLANET_VEIN_MAXIMUM_RADIUS_METRES))
	direction := planet_direction_from_home(home, planet_home_tangent(home, bearing), distance, radius)
	return Planet_Vein{material = material, direction = direction, centre = fixed_scale(direction, radius), radius = disc, hash = generation_seed.hash_combine(hash, 3)}
}

// The starter veins round the home, any non-zero vector along it (a unit
// vector or a position); the zero vector takes the north pole. radius is
// the planet's in position units.
plan_planet_veins :: proc(seed: u64, home_vector: [3]i64, radius: i64) -> (planned: Planet_Veins) {
	home, ok := normalize_fixed(home_vector)
	if !ok {
		home = FRAME_NORTH
	}
	hash := generation_seed.derive_purpose_seeds(seed)[.Planet_Veins]
	rotation := i32(generation_seed.hash_to_range(hash, 0, ANGLE_UNITS_PER_TURN - 1))
	materials := PLANET_STARTER_VEIN_MATERIALS
	for material, number in materials {
		vein_hash := generation_seed.hash_combine(hash, u64(number) + 1)
		bearing := planet_vein_bearing(rotation, number, len(materials), vein_hash)
		planned.veins[number] = plan_planet_vein(material, home, bearing, radius, generation_seed.hash_combine(vein_hash, 1))
	}
	planned.count = len(materials)
	return planned
}

// The point (on the sphere of the planet's radius) lies on the disc.
point_in_planet_vein :: proc(vein: Planet_Vein, point: [3]i64) -> bool {
	offset := point - vein.centre
	for axis in 0 ..< 3 {
		if abs(offset[axis]) > vein.radius {
			return false
		}
	}
	return offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= vein.radius * vein.radius
}

// The ore of the first vein whose disc holds the point on the sphere.
planet_vein_material :: proc(veins: Planet_Veins, point: [3]i64) -> (material: Field_Material, found: bool) {
	for index in 0 ..< veins.count {
		if vein := veins.veins[index]; point_in_planet_vein(vein, point) {
			return vein.material, true
		}
	}
	return .Air, false
}

// A stratum within the outcrop depth turns to the ore of a disc it lies
// in; bedrock stays.
planet_outcrop_material :: proc(veins: Planet_Veins, stratum: Field_Material, depth: i64, point: [3]i64) -> Field_Material {
	if stratum == .Bedrock || depth >= metres_to_position_units(OUTCROP_DEPTH_METRES) {
		return stratum
	}
	if material, found := planet_vein_material(veins, point); found {
		return material
	}
	return stratum
}

// The registry.

planet_vein_id :: proc(number: int) -> Vein_Id {
	return Vein_Id{region = PLANET_VEIN_REGION, index = i32(number), layer = .Surface}
}

// The spawn vein type whose outcrop block has the material's name, -1
// when none has.
planet_vein_type :: proc(tables: Vein_Tables, material: Field_Material) -> int {
	name := field_material_name(material)
	for type_index in tables.spawn_types {
		for outcrop in tables.types[type_index].definition.outcrop_blocks {
			if outcrop == name {
				return type_index
			}
		}
	}
	return -1
}

// A reservoir of the starter size class (generation_starter_veins.odin)
// and the type's output mix, with the planned disc as its footprint.
make_planet_vein_record :: proc(tables: Vein_Tables, planned: Planet_Vein, type_index, number: int) -> Vein {
	size_class := tables.size_classes[STARTER_VEIN_SIZE_CLASS]
	units := generation_seed.hash_to_range(planned.hash, size_class.minimum_units, size_class.maximum_units)
	return Vein {
		id = planet_vein_id(number),
		type = type_index,
		size_class = STARTER_VEIN_SIZE_CLASS,
		remaining = vein_amounts(tables.types[type_index], units),
		sphere_centre = planned.centre,
		sphere_radius = planned.radius,
	}
}

// One Vein per planet vein of the generation. A vein already registered
// (from a loaded save) keeps its reservoir and takes its disc again, which
// the save leaves out. problem names an ore no spawn vein type has as its
// outcrop (data/veins.sjson); then nothing is registered.
register_planet_veins :: proc(veins: ^[dynamic]Vein, vein_indices: ^map[Vein_Id]int, generation: Planet_Generation, tables: Vein_Tables) -> (problem: string) {
	for number in 0 ..< generation.veins.count {
		if material := generation.veins.veins[number].material; planet_vein_type(tables, material) < 0 {
			return fmt.tprintf("no spawn vein type of veins.sjson has the outcrop %s", field_material_name(material))
		}
	}
	for number in 0 ..< generation.veins.count {
		planned := generation.veins.veins[number]
		if index, found := vein_indices[planet_vein_id(number)]; found {
			veins[index].sphere_centre, veins[index].sphere_radius = planned.centre, planned.radius
			continue
		}
		vein_indices[planet_vein_id(number)] = len(veins)
		append(veins, make_planet_vein_record(tables, planned, planet_vein_type(tables, planned.material), number))
	}
	return ""
}
