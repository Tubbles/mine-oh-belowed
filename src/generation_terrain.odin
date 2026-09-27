package game

import "core:math"
import "core:math/noise"

// Terrain shape. Every value here is a pure function of the world seed and
// a world position, so any chunk (or the spawn search) computes the same
// column without looking at loaded chunks.

SEA_LEVEL :: 32
// Blocks below this level are deep stone instead of stone.
DEEP_STONE_LEVEL :: -24
// Caves stop here. Chunks wholly below are solid deep stone, filled
// without any noise work.
CAVE_FLOOR :: -128
TERRAIN_MINIMUM_HEIGHT :: SEA_LEVEL - 24
TERRAIN_MAXIMUM_HEIGHT :: SEA_LEVEL + 64
// Tallest feature above the surface (trunk plus leaves). Chunks wholly
// above the terrain plus this are air, filled without any noise work.
FEATURE_MAXIMUM_HEIGHT :: 8
GENERATION_CEILING :: TERRAIN_MAXIMUM_HEIGHT + FEATURE_MAXIMUM_HEIGHT

MINIMUM_TOPSOIL_DEPTH :: 3
MAXIMUM_TOPSOIL_DEPTH :: 5

CONTINENTAL_WAVELENGTH :: 512.0
CONTINENTAL_AMPLITUDE :: 18.0
// Lifts the average surface above the sea so that most of the world is land.
LAND_OFFSET :: 8.0
HILL_WAVELENGTH :: 128.0
HILL_AMPLITUDE :: 40.0
DETAIL_WAVELENGTH :: 32.0
DETAIL_AMPLITUDE :: 2.5
MOISTURE_WAVELENGTH :: 400.0
// Rivers follow the zero line of a noise field: where its absolute value is
// small the surface is pulled down to the river bed.
RIVER_WAVELENGTH :: 320.0
RIVER_BED_HEIGHT :: SEA_LEVEL - 3
RIVER_EDGE :: 0.06
RIVER_CENTRE :: 0.015

// A cave needs this much rock above it, and more where water could reach
// it from the column or a face neighbour, so caves never open under water.
CAVE_ROOF :: 1
CAVE_ROOF_UNDER_WATER :: 4
CAVE_WAVELENGTH_HORIZONTAL :: 32.0
CAVE_WAVELENGTH_VERTICAL :: 16.0
CAVE_THRESHOLD :: 0.55
// 3D cave noise is sampled on a world aligned lattice and interpolated.
CAVE_GRID_STEP :: 4
CAVE_GRID_POINTS :: CHUNK_SIZE / CAVE_GRID_STEP + 1

Column_Sample :: struct {
	height:        i32,
	topsoil_depth: i32,
	biome:         int,
}

// A chunk's columns plus a one column border for the cave roof rule.
COLUMN_GRID_SIZE :: CHUNK_SIZE + 2
Column_Grid :: [COLUMN_GRID_SIZE * COLUMN_GRID_SIZE]Column_Sample
Cave_Grid :: [CAVE_GRID_POINTS * CAVE_GRID_POINTS * CAVE_GRID_POINTS]f32

noise_2d_at :: proc(seed: u64, x, z: i32, wavelength: f64) -> f64 {
	return f64(noise.noise_2d(i64(seed), {f64(x) / wavelength, f64(z) / wavelength}))
}

smoothstep :: proc(edge_start, edge_end, value: f64) -> f64 {
	t := clamp((value - edge_start) / (edge_end - edge_start), 0, 1)
	return t * t * (3 - 2 * t)
}

carve_river :: proc(seeds: Purpose_Seeds, x, z: i32, height: f64) -> f64 {
	river := abs(noise_2d_at(seeds[.Rivers], x, z, RIVER_WAVELENGTH))
	strength := smoothstep(RIVER_EDGE, RIVER_CENTRE, river)
	// Never raises ground that already lies below the river bed.
	return min(height, math.lerp(height, f64(RIVER_BED_HEIGHT), strength))
}

// Continental swell, hills only on higher ground, fine detail, then rivers.
terrain_height :: proc(seeds: Purpose_Seeds, x, z: i32) -> i32 {
	continental := noise_2d_at(seeds[.Continental_Height], x, z, CONTINENTAL_WAVELENGTH)
	hills := max(noise_2d_at(seeds[.Hill_Height], x, z, HILL_WAVELENGTH), 0)
	hill_mask := clamp((continental + 0.1) * 2, 0, 1)
	detail := noise_2d_at(seeds[.Detail_Height], x, z, DETAIL_WAVELENGTH)
	height := SEA_LEVEL + LAND_OFFSET + continental * CONTINENTAL_AMPLITUDE + hills * hills * HILL_AMPLITUDE * hill_mask + detail * DETAIL_AMPLITUDE
	height = carve_river(seeds, x, z, height)
	return clamp(i32(math.floor(height)), TERRAIN_MINIMUM_HEIGHT, TERRAIN_MAXIMUM_HEIGHT)
}

terrain_moisture :: proc(seeds: Purpose_Seeds, x, z: i32) -> f32 {
	return f32(noise_2d_at(seeds[.Moisture], x, z, MOISTURE_WAVELENGTH))
}

topsoil_depth :: proc(seeds: Purpose_Seeds, x, z: i32) -> i32 {
	return i32(hash_to_range(hash_column(seeds[.Topsoil], x, z), MINIMUM_TOPSOIL_DEPTH, MAXIMUM_TOPSOIL_DEPTH))
}

sample_column :: proc(generator: ^Generator, x, z: i32) -> Column_Sample {
	height := terrain_height(generator.seeds, x, z)
	moisture := terrain_moisture(generator.seeds, x, z)
	return Column_Sample {
		height = height,
		topsoil_depth = topsoil_depth(generator.seeds, x, z),
		biome = select_biome(generator.biomes, height - SEA_LEVEL, moisture),
	}
}

column_biome :: proc(generator: ^Generator, column: Column_Sample) -> Biome {
	return generator.biomes[column.biome]
}

// The block of a column at height y before caves, outcrops and features.
terrain_block :: proc(generator: ^Generator, column: Column_Sample, y: i32) -> Block_Id {
	switch {
	case y > column.height:
		return y <= SEA_LEVEL ? generator.blocks.water : AIR_BLOCK
	case y == column.height:
		return column_biome(generator, column).top_block
	case y > column.height - column.topsoil_depth:
		return column_biome(generator, column).filler_block
	case y < DEEP_STONE_LEVEL:
		return generator.blocks.deep_stone
	}
	return generator.blocks.stone
}

column_grid_index :: proc(x, z: i32) -> int {
	return int(x + 1) + int(z + 1) * COLUMN_GRID_SIZE
}

// x and z are local to the chunk, -1 to CHUNK_SIZE.
grid_column :: proc(grid: ^Column_Grid, x, z: i32) -> Column_Sample {
	return grid[column_grid_index(x, z)]
}

sample_column_grid :: proc(generator: ^Generator, coordinate: Chunk_Coordinate, grid: ^Column_Grid) {
	origin := chunk_origin(coordinate)
	for z in i32(-1) ..= CHUNK_SIZE {
		for x in i32(-1) ..= CHUNK_SIZE {
			grid[column_grid_index(x, z)] = sample_column(generator, origin.x + x, origin.z + z)
		}
	}
}

// Stands in for real columns in chunks so deep that no surface, topsoil or
// cave roof can reach them, which then need no height noise at all.
fill_underground_column_grid :: proc(grid: ^Column_Grid) {
	for &column in grid {
		column = Column_Sample {
			height        = TERRAIN_MINIMUM_HEIGHT,
			topsoil_depth = MAXIMUM_TOPSOIL_DEPTH,
		}
	}
}

chunk_is_underground :: proc(coordinate: Chunk_Coordinate) -> bool {
	top := chunk_origin(coordinate).y + CHUNK_SIZE - 1
	return top < TERRAIN_MINIMUM_HEIGHT - MAXIMUM_TOPSOIL_DEPTH - CAVE_ROOF_UNDER_WATER
}

// Highest block a cave may carve in this column: below the lowest surface
// among the column and its four face neighbours, so a cave never touches
// the water standing on any of them.
cave_ceiling :: proc(grid: ^Column_Grid, x, z: i32) -> i32 {
	lowest := grid_column(grid, x, z).height
	for offset in ([4][2]i32{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
		lowest = min(lowest, grid_column(grid, x + offset.x, z + offset.y).height)
	}
	roof := lowest < SEA_LEVEL ? i32(CAVE_ROOF_UNDER_WATER) : i32(CAVE_ROOF)
	return lowest - roof
}

cave_grid_index :: proc(x, y, z: int) -> int {
	return x + CAVE_GRID_POINTS * (z + CAVE_GRID_POINTS * y)
}

cave_noise :: proc(seed: u64, position: World_Coordinate) -> f32 {
	scaled := [3]f64 {
		f64(position.x) / CAVE_WAVELENGTH_HORIZONTAL,
		f64(position.y) / CAVE_WAVELENGTH_VERTICAL,
		f64(position.z) / CAVE_WAVELENGTH_HORIZONTAL,
	}
	return noise.noise_3d_improve_xz(i64(seed), scaled)
}

sample_cave_grid :: proc(seed: u64, coordinate: Chunk_Coordinate, grid: ^Cave_Grid) {
	origin := chunk_origin(coordinate)
	for y in 0 ..< CAVE_GRID_POINTS {
		for z in 0 ..< CAVE_GRID_POINTS {
			for x in 0 ..< CAVE_GRID_POINTS {
				offset := World_Coordinate{i32(x), i32(y), i32(z)} * CAVE_GRID_STEP
				grid[cave_grid_index(x, y, z)] = cave_noise(seed, origin + offset)
			}
		}
	}
}

// Trilinear interpolation between the eight lattice points around a block.
cave_density :: proc(grid: ^Cave_Grid, local: Local_Coordinate) -> f32 {
	cell := [3]int{int(local.x), int(local.y), int(local.z)} / CAVE_GRID_STEP
	fraction := [3]f32{f32(local.x), f32(local.y), f32(local.z)} / CAVE_GRID_STEP - [3]f32{f32(cell.x), f32(cell.y), f32(cell.z)}
	corners: [8]f32
	for &value, corner in corners {
		step := cave_corner_step(corner)
		value = grid[cave_grid_index(cell.x + step.x, cell.y + step.y, cell.z + step.z)]
	}
	return interpolate_cave_corners(corners, fraction)
}

cave_corner_step :: proc(corner: int) -> [3]int {
	return {corner & 1, corner >> 1 & 1, corner >> 2 & 1}
}

// Shared by the chunk grid and the per block lookup (generation_caves.odin),
// in one order of operations, so both give the same bits.
interpolate_cave_corners :: proc(corners: [8]f32, fraction: [3]f32) -> f32 {
	result: f32 = 0
	for value, corner in corners {
		step := cave_corner_step(corner)
		weight: f32 = 1
		for axis in 0 ..< 3 {
			weight *= step[axis] == 1 ? fraction[axis] : 1 - fraction[axis]
		}
		result += weight * value
	}
	return result
}

chunk_needs_caves :: proc(coordinate: Chunk_Coordinate) -> bool {
	origin := chunk_origin(coordinate)
	return origin.y + CHUNK_SIZE > CAVE_FLOOR && origin.y < TERRAIN_MAXIMUM_HEIGHT
}

Terrain_Input :: struct {
	generator: ^Generator,
	columns:   ^Column_Grid,
	caves:     ^Cave_Grid,
	has_caves: bool,
}

carved_by_cave :: proc(input: Terrain_Input, local: Local_Coordinate, y, ceiling: i32) -> bool {
	if !input.has_caves || y > ceiling || y < CAVE_FLOOR {
		return false
	}
	return cave_density(input.caves, local) > CAVE_THRESHOLD
}

// A low spot of a biome with pits: low enough, and no face neighbour
// lower. Pure in the column grid, so neighbouring chunks agree.
column_is_pit :: proc(generator: ^Generator, grid: ^Column_Grid, x, z: i32) -> bool {
	column := grid_column(grid, x, z)
	biome := column_biome(generator, column)
	if biome.pit_block == AIR_BLOCK || column.height - SEA_LEVEL > biome.definition.pit_maximum_height {
		return false
	}
	for offset in ([4][2]i32{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
		if grid_column(grid, x + offset.x, z + offset.y).height < column.height {
			return false
		}
	}
	return true
}

fill_terrain_column :: proc(chunk: ^Chunk, input: Terrain_Input, x, z: i32) {
	column := grid_column(input.columns, x, z)
	ceiling := cave_ceiling(input.columns, x, z)
	origin_y := chunk_origin(chunk.coordinate).y
	pit := column_is_pit(input.generator, input.columns, x, z)
	for local_y in i32(0) ..< CHUNK_SIZE {
		local := Local_Coordinate{x, local_y, z}
		y := origin_y + local_y
		block := terrain_block(input.generator, column, y)
		if pit && y == column.height {
			block = column_biome(input.generator, column).pit_block
		}
		if carved_by_cave(input, local, y, ceiling) {
			block = AIR_BLOCK
		}
		chunk.blocks[local_to_index(local)] = block
	}
}

fill_terrain :: proc(chunk: ^Chunk, input: Terrain_Input) {
	for z in i32(0) ..< CHUNK_SIZE {
		for x in i32(0) ..< CHUNK_SIZE {
			fill_terrain_column(chunk, input, x, z)
		}
	}
}

fill_chunk_with :: proc(chunk: ^Chunk, block: Block_Id) {
	for &value in chunk.blocks {
		value = block
	}
}
