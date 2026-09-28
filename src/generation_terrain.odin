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
TERRAIN_MAXIMUM_HEIGHT :: SEA_LEVEL + 96
// Tallest feature above the surface: the tallest trunk plus the most a
// crown rises above it. Chunks wholly above the terrain plus this are
// air, filled without any noise work.
FEATURE_MAXIMUM_HEIGHT :: MAXIMUM_TRUNK_HEIGHT + MAXIMUM_CROWN_RADIUS
GENERATION_CEILING :: TERRAIN_MAXIMUM_HEIGHT + FEATURE_MAXIMUM_HEIGHT

MINIMUM_TOPSOIL_DEPTH :: 3
MAXIMUM_TOPSOIL_DEPTH :: 5

// The terrain before work item 0057 was version 1, the shaped terrain
// with the height and moisture biomes version 2, the climate biomes of
// work item 0058 version 3, the tree species of work item 0059 version
// 4, the ground cover of work item 0082 version 5, the trees without
// roots of work item 0083 version 6. A world saved by an older generator
// regenerates its unmodified chunks with this one.
GENERATOR_VERSION :: 6

// Continental swell: broad lowlands near sea level, and raised masses
// where the continental noise lies above RAISED_START, fully raised from
// RAISED_END on (a smoothstep, so the shores between stay gentle). The
// noise values spread almost evenly over -1 to 1, so a threshold of 0.35
// leaves about a third of the world raised.
CONTINENTAL_WAVELENGTH :: 512.0
LOWLAND_AMPLITUDE :: 12.0
// Lifts the average surface above the sea so that most of the world is land.
LAND_OFFSET :: 5.0
RAISED_START :: 0.35
RAISED_END :: 0.75
RAISED_HEIGHT :: 16.0
// Ranges: ridged noise (sharp crests where the noise crosses zero) on the
// raised masses only.
RANGE_WAVELENGTH :: 256.0
RANGE_AMPLITUDE :: 40.0
HILL_WAVELENGTH :: 128.0
HILL_AMPLITUDE :: 24.0
// The range and hill samples are taken at a position moved by two low
// frequency noises, which bends ridges and valleys.
WARP_WAVELENGTH :: 200.0
WARP_AMPLITUDE :: 30.0
// Plateaus: where the plateau mask exceeds the threshold the surface is
// pulled up to the next multiple of PLATEAU_STEP above sea level, with a
// cliff over the narrow band of the mask above the threshold. The detail
// noise keeps PLATEAU_DETAIL_SHARE of its amplitude on top.
PLATEAU_WAVELENGTH :: 300.0
PLATEAU_THRESHOLD :: 0.75
PLATEAU_CLIFF_WIDTH :: 0.03
PLATEAU_STEP :: 12
PLATEAU_DETAIL_SHARE :: 0.3
DETAIL_WAVELENGTH :: 32.0
DETAIL_AMPLITUDE :: 2.5
// The lowlands keep this share of the detail, so flat landing sites stay
// common.
LOWLAND_DETAIL_SHARE :: 0.6
MOISTURE_WAVELENGTH :: 400.0
// Climate (work item 0058): temperature runs from -1 (cold) to 1 (hot).
// It is a latitude band along z, plus noise, minus a lapse with height.
// The band is a cosine over TEMPERATURE_PERIOD blocks with its phase set
// so that the origin sits at ORIGIN_TEMPERATURE: a quarter period north
// (towards -z) it is cold, a quarter period south hot.
TEMPERATURE_PERIOD :: 6000.0
LATITUDE_AMPLITUDE :: 0.9
ORIGIN_TEMPERATURE :: 0.1
TEMPERATURE_WAVELENGTH :: 600.0
TEMPERATURE_NOISE_AMPLITUDE :: 0.35
// Per block of surface above sea level.
TEMPERATURE_LAPSE :: 0.006
// Rivers follow the zero line of a noise field: where its absolute value is
// small the surface is pulled down to the river bed. A wider band around
// it lowers the banks by up to VALLEY_DEPTH, so the valley slopes down to
// the water.
RIVER_WAVELENGTH :: 320.0
RIVER_BED_HEIGHT :: SEA_LEVEL - 3
RIVER_EDGE :: 0.06
RIVER_CENTRE :: 0.015
VALLEY_EDGE :: 0.16
VALLEY_DEPTH :: 6.0
// Valley walls rise at most this many blocks per unit of river noise from
// the bed, so a river through a range cuts a sloped valley, not a gorge.
VALLEY_WALL_RISE :: 300.0

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
	temperature:   f32,
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

noise_2d_at_position :: proc(seed: u64, position: [2]f64, wavelength: f64) -> f64 {
	return f64(noise.noise_2d(i64(seed), position / wavelength))
}

// The absolute value of the river noise: zero on a river's centre line.
river_distance :: proc(seeds: Purpose_Seeds, x, z: i32) -> f64 {
	return abs(noise_2d_at(seeds[.Rivers], x, z, RIVER_WAVELENGTH))
}

// 1 on a river's centre, 0 outside the river.
river_strength :: proc(river: f64) -> f64 {
	return smoothstep(RIVER_EDGE, RIVER_CENTRE, river)
}

carve_river :: proc(river: f64, height: f64) -> f64 {
	// Never raises ground that already lies below the river bed.
	return min(height, math.lerp(height, f64(RIVER_BED_HEIGHT), river_strength(river)))
}

// Lowers the banks towards the river, down to sea level at most, and cuts
// the valley walls, never below the river bed.
carve_valley :: proc(river: f64, height: f64) -> f64 {
	banks := max(height - VALLEY_DEPTH * smoothstep(VALLEY_EDGE, RIVER_EDGE, river), SEA_LEVEL)
	walls := RIVER_BED_HEIGHT + VALLEY_WALL_RISE * max(river - RIVER_CENTRE, 0)
	return min(height, max(min(banks, walls), f64(RIVER_BED_HEIGHT)))
}

// One minus the absolute value, squared: crests where the noise crosses zero.
ridge :: proc(value: f64) -> f64 {
	crest := 1 - abs(value)
	return crest * crest
}

warped_position :: proc(seeds: Purpose_Seeds, x, z: i32) -> [2]f64 {
	offset := [2]f64{noise_2d_at(seeds[.Warp_X], x, z, WARP_WAVELENGTH), noise_2d_at(seeds[.Warp_Z], x, z, WARP_WAVELENGTH)}
	return {f64(x), f64(z)} + offset * WARP_AMPLITUDE
}

// Ranges and hills, before the raised mask scales them.
raised_relief :: proc(seeds: Purpose_Seeds, x, z: i32) -> f64 {
	position := warped_position(seeds, x, z)
	range := ridge(noise_2d_at_position(seeds[.Range_Height], position, RANGE_WAVELENGTH))
	hills := max(noise_2d_at_position(seeds[.Hill_Height], position, HILL_WAVELENGTH), 0)
	return range * RANGE_AMPLITUDE + hills * hills * HILL_AMPLITUDE
}

// Continental swell, raised masses, and ranges and hills on them. raised
// is 0 in the lowlands and 1 on the raised masses.
base_height :: proc(seeds: Purpose_Seeds, x, z: i32) -> (height, raised: f64) {
	continental := noise_2d_at(seeds[.Continental_Height], x, z, CONTINENTAL_WAVELENGTH)
	raised = smoothstep(RAISED_START, RAISED_END, continental)
	height = SEA_LEVEL + LAND_OFFSET + continental * LOWLAND_AMPLITUDE + raised * RAISED_HEIGHT
	if raised > 0 {
		height += raised * raised_relief(seeds, x, z)
	}
	return height, raised
}

// The next multiple of PLATEAU_STEP above sea level, over the height.
plateau_level :: proc(height: f64) -> f64 {
	return SEA_LEVEL + PLATEAU_STEP * (math.floor((height - SEA_LEVEL) / PLATEAU_STEP) + 1)
}

// 0 off a plateau, 1 on its top, the cliff between.
plateau_blend :: proc(seeds: Purpose_Seeds, x, z: i32) -> f64 {
	mask := noise_2d_at(seeds[.Plateau_Mask], x, z, PLATEAU_WAVELENGTH)
	return smoothstep(PLATEAU_THRESHOLD, PLATEAU_THRESHOLD + PLATEAU_CLIFF_WIDTH, mask)
}

// The share of DETAIL_AMPLITUDE a column gets: less in the lowlands and
// on plateau tops.
detail_share :: proc(raised, plateau: f64) -> f64 {
	return math.lerp(LOWLAND_DETAIL_SHARE, 1.0, raised) * math.lerp(1.0, PLATEAU_DETAIL_SHARE, plateau)
}

// Layers: base height, plateaus, fine detail, valleys, then rivers.
terrain_height :: proc(seeds: Purpose_Seeds, x, z: i32) -> i32 {
	height, raised := base_height(seeds, x, z)
	plateau := plateau_blend(seeds, x, z)
	height = math.lerp(height, plateau_level(height), plateau)
	detail := noise_2d_at(seeds[.Detail_Height], x, z, DETAIL_WAVELENGTH)
	height += detail * DETAIL_AMPLITUDE * detail_share(raised, plateau)
	river := river_distance(seeds, x, z)
	height = carve_river(river, carve_valley(river, height))
	return clamp(i32(math.floor(height)), TERRAIN_MINIMUM_HEIGHT, TERRAIN_MAXIMUM_HEIGHT)
}

terrain_moisture :: proc(seeds: Purpose_Seeds, x, z: i32) -> f32 {
	return f32(noise_2d_at(seeds[.Moisture], x, z, MOISTURE_WAVELENGTH))
}

// The latitude band alone: ORIGIN_TEMPERATURE at z = 0, falling towards
// -z and rising towards +z.
latitude_temperature :: proc(z: i32) -> f64 {
	phase := math.acos(ORIGIN_TEMPERATURE / LATITUDE_AMPLITUDE)
	return LATITUDE_AMPLITUDE * math.cos(2 * math.PI * f64(z) / TEMPERATURE_PERIOD - phase)
}

// height is the column's surface height.
terrain_temperature :: proc(seeds: Purpose_Seeds, x, z, height: i32) -> f32 {
	noise_part := noise_2d_at(seeds[.Temperature], x, z, TEMPERATURE_WAVELENGTH) * TEMPERATURE_NOISE_AMPLITUDE
	lapse := f64(max(height - SEA_LEVEL, 0)) * TEMPERATURE_LAPSE
	return f32(clamp(latitude_temperature(z) + noise_part - lapse, -1, 1))
}

topsoil_depth :: proc(seeds: Purpose_Seeds, x, z: i32) -> i32 {
	return i32(hash_to_range(hash_column(seeds[.Topsoil], x, z), MINIMUM_TOPSOIL_DEPTH, MAXIMUM_TOPSOIL_DEPTH))
}

sample_column :: proc(generator: ^Generator, x, z: i32) -> Column_Sample {
	height := terrain_height(generator.seeds, x, z)
	climate := Climate {
		relative_height = height - SEA_LEVEL,
		moisture        = terrain_moisture(generator.seeds, x, z),
		temperature     = terrain_temperature(generator.seeds, x, z, height),
	}
	return Column_Sample {
		height = height,
		topsoil_depth = topsoil_depth(generator.seeds, x, z),
		temperature = climate.temperature,
		biome = select_biome(generator.biomes, climate),
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
		return filler_block_at(column_biome(generator, column), y)
	case y < DEEP_STONE_LEVEL:
		return generator.blocks.deep_stone
	}
	return generator.blocks.stone
}

// The filler, or with a layer block the filler and the layer block in
// bands of layer_thickness blocks of absolute height (badlands).
filler_block_at :: proc(biome: Biome, y: i32) -> Block_Id {
	if biome.layer_block == AIR_BLOCK || floor_divide(y, biome.definition.layer_thickness) %% 2 == 0 {
		return biome.filler_block
	}
	return biome.layer_block
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
