package game

import "generation_seed"

// Schematic crate sites in cave pockets (work item 0036). A region of
// REGION_SIZE blocks holds at most one crate. A hash of the region decides
// whether it has one and lists candidate columns; the first candidate
// with a cave pocket (an open cave cell over solid floor) at least
// CRATE_MINIMUM_DEPTH below the surface and enough rock walls around it
// takes the crate, and a few of those walls turn to gold quartz. Everything
// is a pure function of the seed and the region, so every chunk the site
// touches finds the same site whatever order chunks load in.
//
// Open cave cells are found with the chunk generator's own noise lattice
// and interpolation (interpolate_cave_corners), and the roof rule reads
// the terrain heights directly, so a cell open here is air in the chunk.

// About one crate per four regions: the chance a region tries, and how
// many columns it tries before giving up.
CRATE_REGION_CHANCE :: 0.25
CRATE_CANDIDATE_COLUMNS :: 16
CRATE_MINIMUM_DEPTH :: 20
// Every candidate column is tried for a pocket down to this depth before
// any column is searched deeper, so most crates sit a short dig down.
CRATE_SHALLOW_MAXIMUM_DEPTH :: 40
// Deeper than any column reaches, so the fallback search stops at the floor.
CRATE_ANY_DEPTH :: 1 << 16
// How far from the crate a wall may stand, along each horizontal axis.
CRATE_WALL_REACH :: 3
MINIMUM_GOLD_QUARTZ_WALLS :: 2
MAXIMUM_GOLD_QUARTZ_WALLS :: 3
// Wall candidates: the four horizontal directions at the crate's level
// and one above.
CRATE_WALL_CANDIDATES :: 8

// position is the open cave cell the crate stands in. choice picks the
// schematic (schematic_for_choice). walls are the gold quartz cells, the
// first wall_count of them. placed is set once the crate entity exists
// (schematic.odin); generation leaves it false.
Crate_Site :: struct {
	region:     Region_Coordinate,
	position:   World_Coordinate,
	choice:     u64,
	walls:      [MAXIMUM_GOLD_QUARTZ_WALLS]World_Coordinate,
	wall_count: i32,
	placed:     bool,
}

// Cave noise at lattice points, so a scan down a column samples each
// point once. In the temp allocator.
Cave_Noise_Cache :: map[World_Coordinate]f32

region_crate_hash :: proc(generator: ^Generator, region: Region_Coordinate) -> u64 {
	return generation_seed.hash_combine(generator.seeds[.Cave_Crates], generation_seed.pack_pair(region.x, region.y))
}

region_tries_crate :: proc(region_hash: u64) -> bool {
	return generation_seed.hash_to_unit(generation_seed.hash_combine(region_hash, 0)) < CRATE_REGION_CHANCE
}

// Candidate columns keep the walls inside the region, so a chunk only
// ever looks at its own region's site.
crate_candidate_column :: proc(region_hash: u64, region: Region_Coordinate, candidate: int) -> [2]i32 {
	hash := generation_seed.hash_combine(region_hash, u64(candidate) + 1)
	margin := i32(CRATE_WALL_REACH + 1)
	span := i64(REGION_SIZE - 2 * margin - 1)
	origin := region_origin(region)
	return {origin.x + margin + i32(generation_seed.hash_to_range(hash, 0, span)), origin.y + margin + i32(generation_seed.hash_to_range(generation_seed.hash_combine(hash, 1), 0, span))}
}

cave_roof_height :: proc(lowest_surface: i32) -> i32 {
	return lowest_surface < SEA_LEVEL ? i32(CAVE_ROOF_UNDER_WATER) : i32(CAVE_ROOF)
}

// cave_ceiling from the terrain heights instead of a chunk's column grid.
cave_ceiling_at :: proc(seeds: generation_seed.Purpose_Seeds, x, z: i32) -> i32 {
	lowest := terrain_height(seeds, x, z)
	for offset in ([4][2]i32{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
		lowest = min(lowest, terrain_height(seeds, x + offset.x, z + offset.y))
	}
	return lowest - cave_roof_height(lowest)
}

cached_cave_noise :: proc(cache: ^Cave_Noise_Cache, seed: u64, point: World_Coordinate) -> f32 {
	if value, found := cache[point]; found {
		return value
	}
	value := cave_noise(seed, point)
	cache[point] = value
	return value
}

// cave_density for any block, from the world aligned lattice.
cave_density_at :: proc(cache: ^Cave_Noise_Cache, seed: u64, position: World_Coordinate) -> f32 {
	base := World_Coordinate{floor_divide(position.x, CAVE_GRID_STEP), floor_divide(position.y, CAVE_GRID_STEP), floor_divide(position.z, CAVE_GRID_STEP)} * CAVE_GRID_STEP
	offset := position - base
	fraction := [3]f32{f32(offset.x), f32(offset.y), f32(offset.z)} / CAVE_GRID_STEP
	corners: [8]f32
	for &value, corner in corners {
		step := cave_corner_step(corner)
		value = cached_cave_noise(cache, seed, base + World_Coordinate{i32(step.x), i32(step.y), i32(step.z)} * CAVE_GRID_STEP)
	}
	return interpolate_cave_corners(corners, fraction)
}

// Carved by a cave, as fill_terrain decides it. ceiling is
// cave_ceiling_at of the column.
cave_cell_is_open :: proc(generator: ^Generator, cache: ^Cave_Noise_Cache, position: World_Coordinate, ceiling: i32) -> bool {
	if position.y < CAVE_FLOOR || position.y > ceiling || position.y >= TERRAIN_MAXIMUM_HEIGHT {
		return false
	}
	return cave_density_at(cache, generator.seeds[.Caves], position) > CAVE_THRESHOLD
}

cell_is_open_cave :: proc(generator: ^Generator, cache: ^Cave_Noise_Cache, position: World_Coordinate) -> bool {
	return cave_cell_is_open(generator, cache, position, cave_ceiling_at(generator.seeds, position.x, position.z))
}

// Stone or deep stone for certain: solid, not carved, and below the
// deepest topsoil of its column, so no outcrop or feature reaches it.
cell_is_cave_rock :: proc(generator: ^Generator, cache: ^Cave_Noise_Cache, position: World_Coordinate) -> bool {
	surface := terrain_height(generator.seeds, position.x, position.z)
	return position.y <= surface - MAXIMUM_TOPSOIL_DEPTH && position.y >= CAVE_FLOOR && !cell_is_open_cave(generator, cache, position)
}

@(rodata)
crate_wall_directions := [4]World_Coordinate{{1, 0, 0}, {0, 0, 1}, {-1, 0, 0}, {0, 0, -1}}

// Walking from the pocket cell along a direction, the first rock cell
// within reach, when every cell before it is open.
pocket_wall_along :: proc(generator: ^Generator, cache: ^Cave_Noise_Cache, start, direction: World_Coordinate) -> (wall: World_Coordinate, found: bool) {
	for distance in i32(1) ..= CRATE_WALL_REACH + 1 {
		cell := start + direction * distance
		if cell_is_cave_rock(generator, cache, cell) {
			return cell, true
		}
		if !cell_is_open_cave(generator, cache, cell) {
			return {}, false
		}
	}
	return {}, false
}

// Up to count walls of the pocket around the crate cell, the candidates
// taken in a hashed rotation so the gold quartz is not always east.
pocket_walls :: proc(generator: ^Generator, cache: ^Cave_Noise_Cache, crate: World_Coordinate, count: i32, rotation: u64) -> (walls: [MAXIMUM_GOLD_QUARTZ_WALLS]World_Coordinate, found: i32) {
	for step in 0 ..< CRATE_WALL_CANDIDATES {
		candidate := (int(rotation % CRATE_WALL_CANDIDATES) + step) % CRATE_WALL_CANDIDATES
		start := crate + {0, i32(candidate / 4), 0}
		if candidate >= 4 && !cell_is_open_cave(generator, cache, start) {
			continue
		}
		if wall, ok := pocket_wall_along(generator, cache, start, crate_wall_directions[candidate % 4]); ok && found < count {
			walls[found] = wall
			found += 1
		}
	}
	return
}

// The highest pocket of the column at least CRATE_MINIMUM_DEPTH and at
// most maximum_depth below the surface with enough walls, never lower than
// just above the cave floor.
column_crate_site :: proc(generator: ^Generator, cache: ^Cave_Noise_Cache, column: [2]i32, region_hash: u64, maximum_depth: i32) -> (site: Crate_Site, found: bool) {
	ceiling := cave_ceiling_at(generator.seeds, column.x, column.y)
	surface := terrain_height(generator.seeds, column.x, column.y)
	top := min(surface - CRATE_MINIMUM_DEPTH, ceiling)
	bottom := max(CAVE_FLOOR, surface - maximum_depth - 1)
	wall_count := i32(generation_seed.hash_to_range(generation_seed.hash_combine(region_hash, 1001), MINIMUM_GOLD_QUARTZ_WALLS, MAXIMUM_GOLD_QUARTZ_WALLS))
	below_open := cave_cell_is_open(generator, cache, {column.x, top, column.y}, ceiling)
	for y := top; y > bottom; y -= 1 {
		open := below_open
		below_open = cave_cell_is_open(generator, cache, {column.x, y - 1, column.y}, ceiling)
		if !open || below_open {
			continue
		}
		crate := World_Coordinate{column.x, y, column.y}
		walls, count := pocket_walls(generator, cache, crate, wall_count, generation_seed.hash_combine(region_hash, 1002))
		if count >= MINIMUM_GOLD_QUARTZ_WALLS {
			return Crate_Site{position = crate, choice = generation_seed.hash_combine(region_hash, 1000), walls = walls, wall_count = count}, true
		}
	}
	return {}, false
}

// The region's crate site, if it has one: the first candidate column with
// a shallow pocket, or failing that the first with any pocket.
region_crate_site :: proc(generator: ^Generator, region: Region_Coordinate) -> (site: Crate_Site, found: bool) {
	region_hash := region_crate_hash(generator, region)
	if !region_tries_crate(region_hash) {
		return {}, false
	}
	cache := make(Cave_Noise_Cache, context.temp_allocator)
	for maximum_depth in ([2]i32{CRATE_SHALLOW_MAXIMUM_DEPTH, CRATE_ANY_DEPTH}) {
		for candidate in 0 ..< CRATE_CANDIDATE_COLUMNS {
			column := crate_candidate_column(region_hash, region, candidate)
			if site, found = column_crate_site(generator, &cache, column, region_hash, maximum_depth); found {
				site.region = region
				return site, true
			}
		}
	}
	return {}, false
}

// Cheap test before the scan: could the region's site reach into the
// chunk? Only chunks near a candidate column and within the depths a
// crate and its walls can have.
chunk_may_hold_crate_site :: proc(generator: ^Generator, coordinate: Chunk_Coordinate) -> bool {
	origin := chunk_origin(coordinate)
	if origin.y + CHUNK_SIZE <= CAVE_FLOOR || origin.y > TERRAIN_MAXIMUM_HEIGHT - CRATE_MINIMUM_DEPTH + 1 {
		return false
	}
	region := block_to_region(origin.x, origin.z)
	region_hash := region_crate_hash(generator, region)
	if !region_tries_crate(region_hash) {
		return false
	}
	reach := i32(CRATE_WALL_REACH + 1)
	for candidate in 0 ..< CRATE_CANDIDATE_COLUMNS {
		column := crate_candidate_column(region_hash, region, candidate)
		if column.x + reach >= origin.x && column.x - reach < origin.x + CHUNK_SIZE && column.y + reach >= origin.z && column.y - reach < origin.z + CHUNK_SIZE {
			return true
		}
	}
	return false
}

block_in_chunk :: proc(position: World_Coordinate, coordinate: Chunk_Coordinate) -> bool {
	return world_to_chunk_coordinate(position) == coordinate
}

// Writes the site's gold quartz walls inside the chunk, and lists the
// site when its crate cell lies in the chunk.
apply_crate_site :: proc(generator: ^Generator, chunk: ^Chunk, crates: ^[dynamic]Crate_Site) {
	if crates == nil || !chunk_may_hold_crate_site(generator, chunk.coordinate) {
		return
	}
	origin := chunk_origin(chunk.coordinate)
	site, found := region_crate_site(generator, block_to_region(origin.x, origin.z))
	if !found {
		return
	}
	for wall in site.walls[:site.wall_count] {
		if block_in_chunk(wall, chunk.coordinate) {
			chunk.blocks[local_to_index(Local_Coordinate(wall - origin))] = generator.blocks.gold_quartz
		}
	}
	if block_in_chunk(site.position, chunk.coordinate) {
		append(crates, site)
	}
}
