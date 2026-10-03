package game

import "core:fmt"
import "core:strings"

// The terrain field (work item 0168, doc/architecture.md, World storage):
// samples on a grid aligned with the planet's axes, the planet's centre at
// the origin, in chunks of FIELD_CHUNK_SIZE cubed. A sample holds a
// density (positive inside the ground, the surface where it crosses zero,
// DENSITY_STEPS_PER_SAMPLE steps per sample spacing), a material and a
// tint (an index into the planet's palette). The field world lives beside
// the block world until the slice switches the session to it (0179).

FIELD_CHUNK_SIZE :: 32
FIELD_CHUNK_SAMPLE_COUNT :: FIELD_CHUNK_SIZE * FIELD_CHUNK_SIZE * FIELD_CHUNK_SIZE
// World positions are in this fraction of a metre.
POSITION_UNITS_PER_METRE :: 4096
MILLIMETRES_PER_METRE :: 1000
// The world setting "sample spacing" (DESIGN.md, The world).
SAMPLE_SPACING_CHOICES_MILLIMETRES :: [3]int{333, 500, 1000}
DEFAULT_SAMPLE_SPACING_MILLIMETRES :: 1000
#assert(SAMPLE_SPACING_CHOICES_MILLIMETRES[len(SAMPLE_SPACING_CHOICES_MILLIMETRES) - 1] == WIDEST_SAMPLE_SPACING_MILLIMETRES, "field_player_problem checks the step at the widest spacing")
// The surface to 1/128 of a sample spacing (0167); a density saturates
// one spacing away from the surface.
DENSITY_STEPS_PER_SAMPLE :: 128
MAXIMUM_DENSITY :: 127

// Chunk position in chunk units: the sample coordinate floor divided by
// FIELD_CHUNK_SIZE.
Field_Chunk_Coordinate :: distinct [3]i32
// Sample index in the world; its position is the index times the spacing.
Sample_Coordinate :: distinct [3]i32
// Fixed point, 1/POSITION_UNITS_PER_METRE metre, from the planet's centre.
World_Position :: distinct [3]i64

// The generator's fixed roles until the material table replaces them (0167,
// What changes per cluster).
Field_Material :: enum u8 {
	Air,
	Topsoil,
	Stone,
	Deep_Stone,
	Bedrock,
}

// The material's id in the data files: its name in lower case.
field_material_name :: proc(material: Field_Material) -> string {
	return strings.to_lower(fmt.tprintf("%v", material), context.temp_allocator)
}

Field_Sample :: struct {
	density:  i8,
	material: Field_Material,
	tint:     u8,
}

FIELD_AIR_SAMPLE :: Field_Sample {
	density  = -MAXIMUM_DENSITY,
	material = .Air,
}

// Parallel arrays instead of an array of Field_Sample: the mesher reads
// the densities alone, and the save codec run length encodes each array on
// its own, where materials and tints run far longer than the bytes
// interleaved would. The water field (0172, world_field_water.odin) is
// addressed like the terrain: a fill per sample (0 empty to
// FIELD_WATER_FULL), the ticks it has been still, the fill that moved out
// of it in the last tick (flow, for hydro; not saved), and one bit per
// sample for awake and for source. The field light (0173,
// world_field_light.odin) is two more bytes per sample, block light and
// sky light.
Field_Chunk :: struct {
	coordinate:   Field_Chunk_Coordinate,
	density:      [FIELD_CHUNK_SAMPLE_COUNT]i8,
	material:     [FIELD_CHUNK_SAMPLE_COUNT]Field_Material,
	tint:         [FIELD_CHUNK_SAMPLE_COUNT]u8,
	water:        [FIELD_CHUNK_SAMPLE_COUNT]u8,
	water_still:  [FIELD_CHUNK_SAMPLE_COUNT]u8,
	water_flow:   [FIELD_CHUNK_SAMPLE_COUNT]u8,
	water_awake:  Field_Sample_Bits,
	water_source: Field_Sample_Bits,
	block_light:  [FIELD_CHUNK_SAMPLE_COUNT]u8,
	sky_light:    [FIELD_CHUNK_SAMPLE_COUNT]u8,
	dirty:        bool,
}

// Chunks are heap allocated, as the block world's are, so growing the map
// never moves a 200 KiB chunk.
Field_World :: struct {
	chunks:             map[Field_Chunk_Coordinate]^Field_Chunk,
	// Chunks a set changed since the streaming last took them, so the
	// coarser levels of detail over them mesh again
	// (mark_edited_coarse_nodes).
	edited_chunks:      map[Field_Chunk_Coordinate]struct{},
	// Chunks with an awake water sample, which the water step visits in
	// coordinate order (step_field_water).
	water_awake_chunks: map[Field_Chunk_Coordinate]struct{},
	// Water a terrain place displaced and no neighbour had room for
	// (displace_field_water).
	water_dropped:      i64,
	// The planet as the water and the light's sky march read it, set by
	// the world's owner (make_field_water_planet); zero is a world with no
	// sea and no sky march.
	water_planet:       Field_Water_Planet,
	// The light's queues and emitters (0173).
	light:              Field_Lighting,
}

sample_spacing_is_valid :: proc(millimetres: int) -> bool {
	for choice in SAMPLE_SPACING_CHOICES_MILLIMETRES {
		if choice == millimetres {
			return true
		}
	}
	return false
}

// For a positive divisor.
floor_divide_i64 :: proc(value, divisor: i64) -> i64 {
	return (value - value %% divisor) / divisor
}

ceiling_divide_i64 :: proc(value, divisor: i64) -> i64 {
	return -floor_divide_i64(-value, divisor)
}

metres_to_position_units :: proc(metres: i64) -> i64 {
	return metres * POSITION_UNITS_PER_METRE
}

millimetres_to_position_units :: proc(millimetres: int) -> i64 {
	return i64(millimetres) * POSITION_UNITS_PER_METRE / MILLIMETRES_PER_METRE
}

// One sample's index times the spacing, rounded up to the position unit,
// so world_position_to_sample gives the index back.
sample_axis_to_position :: proc(index: i32, spacing_millimetres: int) -> i64 {
	return ceiling_divide_i64(i64(index) * i64(spacing_millimetres) * POSITION_UNITS_PER_METRE, MILLIMETRES_PER_METRE)
}

// The sample at or below the position on the axis.
position_axis_to_sample :: proc(position: i64, spacing_millimetres: int) -> i32 {
	return i32(floor_divide_i64(position * MILLIMETRES_PER_METRE, i64(spacing_millimetres) * POSITION_UNITS_PER_METRE))
}

sample_to_world_position :: proc(sample: Sample_Coordinate, spacing_millimetres: int) -> World_Position {
	position: World_Position
	for axis in 0 ..< 3 {
		position[axis] = sample_axis_to_position(sample[axis], spacing_millimetres)
	}
	return position
}

world_position_to_sample :: proc(position: World_Position, spacing_millimetres: int) -> Sample_Coordinate {
	sample: Sample_Coordinate
	for axis in 0 ..< 3 {
		sample[axis] = position_axis_to_sample(position[axis], spacing_millimetres)
	}
	return sample
}

sample_to_field_chunk_coordinate :: proc(sample: Sample_Coordinate) -> Field_Chunk_Coordinate {
	return {floor_divide(sample.x, FIELD_CHUNK_SIZE), floor_divide(sample.y, FIELD_CHUNK_SIZE), floor_divide(sample.z, FIELD_CHUNK_SIZE)}
}

field_chunk_origin :: proc(coordinate: Field_Chunk_Coordinate) -> Sample_Coordinate {
	return Sample_Coordinate(coordinate * FIELD_CHUNK_SIZE)
}

// x fastest, then y, then z.
field_local_to_index :: proc(local: [3]i32) -> int {
	return int(local.x) + FIELD_CHUNK_SIZE * (int(local.y) + FIELD_CHUNK_SIZE * int(local.z))
}

field_index_to_local :: proc(index: int) -> [3]i32 {
	return {i32(index % FIELD_CHUNK_SIZE), i32(index / FIELD_CHUNK_SIZE % FIELD_CHUNK_SIZE), i32(index / (FIELD_CHUNK_SIZE * FIELD_CHUNK_SIZE))}
}

sample_to_field_index :: proc(sample: Sample_Coordinate) -> int {
	return field_local_to_index({sample.x %% FIELD_CHUNK_SIZE, sample.y %% FIELD_CHUNK_SIZE, sample.z %% FIELD_CHUNK_SIZE})
}

field_chunk_get_sample :: proc(chunk: ^Field_Chunk, index: int) -> Field_Sample {
	return {chunk.density[index], chunk.material[index], chunk.tint[index]}
}

field_chunk_set_sample :: proc(chunk: ^Field_Chunk, index: int, sample: Field_Sample) {
	chunk.density[index] = sample.density
	chunk.material[index] = sample.material
	chunk.tint[index] = sample.tint
	chunk.dirty = true
}

// Missing chunks read as air.
field_world_get_sample :: proc(world: ^Field_World, sample: Sample_Coordinate) -> Field_Sample {
	chunk := world.chunks[sample_to_field_chunk_coordinate(sample)] or_else nil
	if chunk == nil {
		return FIELD_AIR_SAMPLE
	}
	return field_chunk_get_sample(chunk, sample_to_field_index(sample))
}

// Sets a sample in a loaded chunk and marks every chunk whose mesh can
// read it dirty. Returns false when the chunk is not loaded.
field_world_set_sample :: proc(world: ^Field_World, sample: Sample_Coordinate, value: Field_Sample) -> bool {
	chunk := world.chunks[sample_to_field_chunk_coordinate(sample)] or_else nil
	if chunk == nil {
		return false
	}
	index := sample_to_field_index(sample)
	was_ground := chunk.density[index] > 0
	field_chunk_set_sample(chunk, index, value)
	mark_field_chunks_around_sample_dirty(world, chunk.coordinate, sample)
	world.edited_chunks[chunk.coordinate] = {}
	follow_field_terrain_with_water(world, chunk, index, sample)
	follow_field_terrain_with_light(world, chunk, index, sample, was_ground)
	return true
}

// -1 at 0, +1 at FIELD_CHUNK_SIZE - 1, none inside.
field_border_reach :: proc(local: i32) -> (low, high: i32) {
	return local == 0 ? -1 : 0, local == FIELD_CHUNK_SIZE - 1 ? 1 : 0
}

// A mesh cell spans neighbouring samples, so a border sample also changes
// the face, edge and corner neighbours beside it.
mark_field_chunks_around_sample_dirty :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate, sample: Sample_Coordinate) {
	low, high: [3]i32
	for axis in 0 ..< 3 {
		low[axis], high[axis] = field_border_reach(sample[axis] %% FIELD_CHUNK_SIZE)
	}
	for z in low.z ..= high.z {
		for y in low.y ..= high.y {
			for x in low.x ..= high.x {
				if neighbour := world.chunks[coordinate + {x, y, z}] or_else nil; neighbour != nil {
					neighbour.dirty = true
				}
			}
		}
	}
}

// Takes ownership of a chunk made with new; it starts dirty so the mesher
// meshes it once. The water beside it wakes (wake_field_water_facing), so
// water held by the missing chunk flows on, and the light's tick compares
// its borders with its neighbours' (seed_field_chunk_light).
field_world_insert_chunk :: proc(world: ^Field_World, chunk: ^Field_Chunk) {
	chunk.dirty = true
	if old := world.chunks[chunk.coordinate] or_else nil; old != nil {
		free(old)
	}
	world.chunks[chunk.coordinate] = chunk
	if field_sample_bits_any(&chunk.water_awake) {
		world.water_awake_chunks[chunk.coordinate] = {}
	}
	wake_field_water_facing(world, chunk.coordinate)
	world.light.arrived_chunks[chunk.coordinate] = {}
}

destroy_field_world :: proc(world: ^Field_World) {
	for _, chunk in world.chunks {
		free(chunk)
	}
	delete(world.chunks)
	delete(world.edited_chunks)
	delete(world.water_awake_chunks)
	destroy_field_lighting(&world.light)
	world^ = {}
}
