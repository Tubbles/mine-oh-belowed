package game

import "core:math"

// Starter veins (work item 0045): one small vein of each spawn vein type
// (data/veins.sjson spawn_vein_types) at STARTER_VEIN_MINIMUM_DISTANCE to
// STARTER_VEIN_MAXIMUM_DISTANCE blocks from the landing pad centre, in
// directions spread evenly around the pad with a seeded rotation. They are
// a function of the seed and the pad, and layer_veins lists them as
// ordinary surface veins of the region their centre lies in, so drills,
// assays, the map, the survey and outcrops see them like any other vein.
// Like a natural vein, a starter vein keeps its footprint inside its
// region and clear of the other starter veins. It also sits on dry land and
// ignores the biome limits of its type. Natural veins whose footprint
// overlaps a starter vein are left out.

// Directions tried per starter vein, alternating to either side of its
// preferred direction within its share of the circle, before it is
// skipped.
STARTER_VEIN_PLACEMENT_ATTEMPTS :: 16
// Size classes are listed smallest first: the scattering.
STARTER_VEIN_SIZE_CLASS :: 0

// The margin of candidate_vein_centre: radius plus one block from the
// region border.
footprint_inside_region :: proc(centre: [2]i32, radius: i32) -> bool {
	origin := region_origin(block_to_region(centre.x, centre.y))
	low := origin + radius + 1
	high := origin + REGION_SIZE - radius - 2
	return centre.x >= low.x && centre.x <= high.x && centre.y >= low.y && centre.y <= high.y
}

starter_distance_ok :: proc(pad, position: [2]i32) -> bool {
	offset := position - pad
	distance_squared := offset.x * offset.x + offset.y * offset.y
	return distance_squared >= STARTER_VEIN_MINIMUM_DISTANCE * STARTER_VEIN_MINIMUM_DISTANCE && distance_squared <= STARTER_VEIN_MAXIMUM_DISTANCE * STARTER_VEIN_MAXIMUM_DISTANCE
}

starter_vein_position :: proc(pad: [2]i32, angle: f64, distance: i32) -> [2]i32 {
	return pad + {i32(math.round(math.cos(angle) * f64(distance))), i32(math.round(math.sin(angle) * f64(distance)))}
}

// Attempt 0 keeps the preferred direction, later ones turn to alternate
// sides, at most half the sector away.
starter_attempt_turn :: proc(attempt: int, sector: f64) -> f64 {
	side := attempt % 2 == 1 ? 1.0 : -1.0
	return side * f64((attempt + 1) / 2) * sector / STARTER_VEIN_PLACEMENT_ATTEMPTS
}

place_starter_vein :: proc(generator: ^Generator, placed: []Vein, type_index: int, direction, sector: f64, hash: u64) -> (vein: Vein, ok: bool) {
	pad := [2]i32{generator.landing_pad.centre.x, generator.landing_pad.centre.z}
	size_class := generator.veins.size_classes[STARTER_VEIN_SIZE_CLASS]
	for attempt in 0 ..< STARTER_VEIN_PLACEMENT_ATTEMPTS {
		attempt_hash := hash_combine(hash, u64(attempt))
		distance := i32(hash_to_range(attempt_hash, STARTER_VEIN_MINIMUM_DISTANCE, STARTER_VEIN_MAXIMUM_DISTANCE))
		position := starter_vein_position(pad, direction + starter_attempt_turn(attempt, sector), distance)
		richness := region_richness(generator.veins, block_to_region(position.x, position.y))
		radius := vein_radius(size_class, richness, hash_combine(attempt_hash, 1))
		if !starter_distance_ok(pad, position) || !footprint_inside_region(position, radius) {
			continue
		}
		centre := World_Coordinate{position.x, sample_column(generator, position.x, position.y).height, position.y}
		if centre.y < SEA_LEVEL || !disc_is_clear(placed, centre, radius) {
			continue
		}
		units := vein_units(generator, size_class, richness, hash_combine(attempt_hash, 2))
		vein = Vein {
			type       = type_index,
			size_class = STARTER_VEIN_SIZE_CLASS,
			centre     = centre,
			radius     = radius,
			remaining  = vein_amounts(generator.veins.types[type_index], units),
		}
		return vein, true
	}
	return {}, false
}

// The starter veins around the landing pad, without ids.
starter_veins :: proc(generator: ^Generator, allocator := context.allocator) -> [dynamic]Vein {
	veins := make([dynamic]Vein, allocator)
	pad := generator.landing_pad.centre
	hash := hash_column(generator.seeds[.Starter_Veins], pad.x, pad.z)
	rotation := hash_to_unit(hash) * math.TAU
	sector := math.TAU / f64(len(generator.veins.spawn_types))
	for type_index, number in generator.veins.spawn_types {
		direction := rotation + sector * f64(number)
		if vein, placed := place_starter_vein(generator, veins[:], type_index, direction, sector, hash_combine(hash, u64(number) + 1)); placed {
			append(&veins, vein)
		}
	}
	return veins
}

remove_veins_overlapping :: proc(veins: ^[dynamic]Vein, starter: Vein) {
	for index := len(veins) - 1; index >= 0; index -= 1 {
		if discs_overlap(veins[index].centre, veins[index].radius, starter.centre, starter.radius) {
			ordered_remove(veins, index)
		}
	}
}

// Appends the starter veins whose centre lies in the region, with the
// indices after the region's natural veins, and leaves out the natural
// veins they overlap. Starter veins never overlap each other.
add_starter_veins :: proc(generator: ^Generator, region: Region_Coordinate, veins: ^[dynamic]Vein) {
	next_index := i32(len(veins))
	for starter in starter_veins(generator, context.temp_allocator) {
		if block_to_region(starter.centre.x, starter.centre.z) != region {
			continue
		}
		remove_veins_overlapping(veins, starter)
		vein := starter
		vein.id = Vein_Id{region = region, index = next_index, layer = .Surface}
		append(veins, vein)
		next_index += 1
	}
}
