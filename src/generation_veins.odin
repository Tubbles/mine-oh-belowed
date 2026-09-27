package game

import "core:math"

// Vein placement per region of 8 by 8 chunk columns. Every footprint lies
// wholly inside its region, so the veins overlapping any column are found
// by generating the veins of that column's region alone.

REGION_SIZE_IN_CHUNKS :: 8
REGION_SIZE :: REGION_SIZE_IN_CHUNKS * CHUNK_SIZE
// Tries per vein to find a centre clear of the veins already placed in the
// region, after which the vein is skipped.
VEIN_PLACEMENT_ATTEMPTS :: 16
// Blocks kept free between two footprints of one region.
VEIN_SPACING :: 2

Region_Coordinate :: distinct [2]i32
// Chunk position in the horizontal plane: chunk x and chunk z.
Chunk_Column :: distinct [2]i32

// Stable across runs: the region and the placement order within it.
Vein_Id :: struct {
	region: Region_Coordinate,
	index:  i32,
}

// Remaining amounts are ore units, one per output of the vein type, in the
// type's output order. draws counts the units drills took, and seeds the
// next draw (drill.odin). exhausted is set once every remaining amount of
// a finite vein reached zero.
Vein :: struct {
	id:         Vein_Id,
	type:       int,
	size_class: int,
	centre:     World_Coordinate,
	radius:     i32,
	remaining:  [MAXIMUM_VEIN_OUTPUTS]i64,
	draws:      u64,
	exhausted:  bool,
}

// A surface block generation turned into a vein's outcrop block. The main
// thread keeps these, so an exhausted vein finds its outcrop again.
Outcrop_Cell :: struct {
	position: World_Coordinate,
	vein:     Vein_Id,
}

block_to_region :: proc(x, z: i32) -> Region_Coordinate {
	return {floor_divide(x, REGION_SIZE), floor_divide(z, REGION_SIZE)}
}

chunk_column_of :: proc(coordinate: Chunk_Coordinate) -> Chunk_Column {
	return {coordinate.x, coordinate.z}
}

region_origin :: proc(region: Region_Coordinate) -> [2]i32 {
	return (cast([2]i32)region) * REGION_SIZE
}

region_centre_distance :: proc(region: Region_Coordinate) -> f64 {
	centre := region_origin(region) + REGION_SIZE / 2
	return math.sqrt(f64(centre.x) * f64(centre.x) + f64(centre.y) * f64(centre.y))
}

discs_overlap :: proc(first_centre: World_Coordinate, first_radius: i32, second_centre: World_Coordinate, second_radius: i32) -> bool {
	dx := i64(first_centre.x - second_centre.x)
	dz := i64(first_centre.z - second_centre.z)
	reach := i64(first_radius + second_radius + VEIN_SPACING)
	return dx * dx + dz * dz <= reach * reach
}

disc_is_clear :: proc(veins: []Vein, centre: World_Coordinate, radius: i32) -> bool {
	for vein in veins {
		if discs_overlap(vein.centre, vein.radius, centre, radius) {
			return false
		}
	}
	return true
}

// The centre keeps radius plus one block from the region border.
candidate_vein_centre :: proc(hash: u64, region: Region_Coordinate, radius: i32) -> [2]i32 {
	margin := radius + 1
	span := i64(REGION_SIZE - 2 * margin - 1)
	origin := region_origin(region)
	x := origin.x + margin + i32(hash_to_range(hash, 0, span))
	z := origin.y + margin + i32(hash_to_range(hash_combine(hash, 1), 0, span))
	return {x, z}
}

vein_type_allowed :: proc(vein_type: Vein_Type, biome: int) -> bool {
	if len(vein_type.biomes) == 0 {
		return true
	}
	for allowed in vein_type.biomes {
		if allowed == biome {
			return true
		}
	}
	return false
}

// Weighted choice among the types allowed in the biome. Types without a
// biome list are allowed everywhere, so a data table that has none could
// leave nothing, and the first type is the fallback.
choose_vein_type :: proc(types: []Vein_Type, biome: int, hash: u64) -> int {
	total: i64 = 0
	for vein_type in types {
		if vein_type_allowed(vein_type, biome) {
			total += i64(vein_type.definition.weight)
		}
	}
	if total == 0 {
		return 0
	}
	roll := hash_to_range(hash, 0, total - 1)
	for vein_type, index in types {
		if !vein_type_allowed(vein_type, biome) {
			continue
		}
		roll -= i64(vein_type.definition.weight)
		if roll < 0 {
			return index
		}
	}
	return 0
}

vein_amounts :: proc(vein_type: Vein_Type, units: i64) -> [MAXIMUM_VEIN_OUTPUTS]i64 {
	amounts: [MAXIMUM_VEIN_OUTPUTS]i64
	for output, index in vein_type.definition.outputs {
		amounts[index] = units * output.percent / 100
	}
	return amounts
}

Region_Richness :: struct {
	units_factor:  f64,
	radius_growth: i32,
}

region_richness :: proc(tables: Vein_Tables, region: Region_Coordinate) -> Region_Richness {
	steps := region_centre_distance(region) / f64(tables.richness_distance)
	return Region_Richness{units_factor = 1 + steps, radius_growth = min(tables.maximum_radius_growth, i32(steps))}
}

// Tries to place one vein of a size class. The hash decides everything.
place_vein :: proc(generator: ^Generator, veins: []Vein, region: Region_Coordinate, size_class_index: int, hash: u64) -> (vein: Vein, placed: bool) {
	size_class := generator.veins.size_classes[size_class_index]
	richness := region_richness(generator.veins, region)
	radius := i32(hash_to_range(hash, i64(size_class.minimum_radius), i64(size_class.maximum_radius))) + richness.radius_growth
	for attempt in 0 ..< VEIN_PLACEMENT_ATTEMPTS {
		position := candidate_vein_centre(hash_combine(hash, u64(attempt) + 2), region, radius)
		column := sample_column(generator, position.x, position.y)
		centre := World_Coordinate{position.x, column.height, position.y}
		if !disc_is_clear(veins, centre, radius) {
			continue
		}
		type_index := choose_vein_type(generator.veins.types, column.biome, hash_combine(hash, 100))
		base_units := hash_to_range(hash_combine(hash, 101), size_class.minimum_units, size_class.maximum_units)
		units := i64(f64(base_units) * richness.units_factor) * i64(generator.vein_richness_percent) / 100
		vein = Vein {
			type       = type_index,
			size_class = size_class_index,
			centre     = centre,
			radius     = radius,
			remaining  = vein_amounts(generator.veins.types[type_index], units),
		}
		return vein, true
	}
	return {}, false
}

region_class_count :: proc(size_class: Vein_Size_Class, region: Region_Coordinate, hash: u64) -> i32 {
	if region_centre_distance(region) < f64(size_class.minimum_distance) {
		return 0
	}
	return i32(hash_to_range(hash, i64(size_class.minimum_per_region), i64(size_class.maximum_per_region)))
}

// All veins of a region, largest classes last, ids in placement order.
region_veins :: proc(generator: ^Generator, region: Region_Coordinate, allocator := context.allocator) -> [dynamic]Vein {
	veins := make([dynamic]Vein, allocator)
	region_hash := hash_combine(generator.seeds[.Veins], pack_pair(region.x, region.y))
	for size_class, class_index in generator.veins.size_classes {
		class_hash := hash_combine(region_hash, u64(class_index))
		count := region_class_count(size_class, region, class_hash)
		for number in 0 ..< count {
			vein, placed := place_vein(generator, veins[:], region, class_index, hash_combine(class_hash, u64(number) + 1))
			if placed {
				vein.id = Vein_Id{region, i32(len(veins))}
				append(&veins, vein)
			}
		}
	}
	return veins
}

// Veins of every region that touches the box, minimum and maximum
// inclusive in block x and z.
veins_near_box :: proc(generator: ^Generator, minimum, maximum: [2]i32, allocator := context.allocator) -> [dynamic]Vein {
	veins := make([dynamic]Vein, allocator)
	first := block_to_region(minimum.x, minimum.y)
	last := block_to_region(maximum.x, maximum.y)
	for region_z in first.y ..= last.y {
		for region_x in first.x ..= last.x {
			found := region_veins(generator, {region_x, region_z}, context.temp_allocator)
			append(&veins, ..found[:])
		}
	}
	return veins
}

column_in_disc :: proc(centre: World_Coordinate, radius: i32, x, z: i32) -> bool {
	dx := i64(x - centre.x)
	dz := i64(z - centre.z)
	return dx * dx + dz * dz <= i64(radius) * i64(radius)
}

column_in_vein_footprint :: proc(veins: []Vein, x, z: i32) -> bool {
	for vein in veins {
		if column_in_disc(vein.centre, vein.radius, x, z) {
			return true
		}
	}
	return false
}

// True when the footprint disc reaches into the chunk column's square.
vein_overlaps_column :: proc(vein: Vein, column: Chunk_Column) -> bool {
	minimum := (cast([2]i32)column) * CHUNK_SIZE
	nearest_x := clamp(vein.centre.x, minimum.x, minimum.x + CHUNK_SIZE - 1)
	nearest_z := clamp(vein.centre.z, minimum.y, minimum.y + CHUNK_SIZE - 1)
	return column_in_disc(vein.centre, vein.radius, nearest_x, nearest_z)
}

column_veins :: proc(generator: ^Generator, column: Chunk_Column, allocator := context.allocator) -> [dynamic]Vein {
	veins := make([dynamic]Vein, allocator)
	origin := (cast([2]i32)column) * CHUNK_SIZE
	for vein in region_veins(generator, block_to_region(origin.x, origin.y), context.temp_allocator) {
		if vein_overlaps_column(vein, column) {
			append(&veins, vein)
		}
	}
	return veins
}

// Mixed veins alternate their outcrop blocks in a checkerboard.
outcrop_block :: proc(generator: ^Generator, vein: Vein, x, z: i32) -> Block_Id {
	blocks := generator.veins.types[vein.type].outcrop_blocks
	return blocks[(x + z) %% i32(len(blocks))]
}

// Turns the surface block of every footprint column inside the chunk into
// the vein's outcrop block, under water as well, and lists those cells.
apply_outcrops :: proc(generator: ^Generator, chunk: ^Chunk, columns: ^Column_Grid, veins: []Vein, outcrops: ^[dynamic]Outcrop_Cell) {
	origin := chunk_origin(chunk.coordinate)
	for z in i32(0) ..< CHUNK_SIZE {
		for x in i32(0) ..< CHUNK_SIZE {
			world_x, world_z := origin.x + x, origin.z + z
			for vein in veins {
				local_y := grid_column(columns, x, z).height - origin.y
				if column_in_disc(vein.centre, vein.radius, world_x, world_z) && local_y >= 0 && local_y < CHUNK_SIZE {
					chunk.blocks[local_to_index({x, local_y, z})] = outcrop_block(generator, vein, world_x, world_z)
					append(outcrops, Outcrop_Cell{position = origin + {x, local_y, z}, vein = vein.id})
				}
			}
		}
	}
}
