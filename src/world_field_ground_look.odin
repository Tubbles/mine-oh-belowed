package game

import "core:math"
import "generation_seed"

// The ground's look per vertex (work item 0307, doc/presentation.md, Field
// meshes): with a climate (Planet.climate) the mesher gives every vertex
// the strata's tint from a smooth field along the palette, in place of the
// palette's 256 m cubes, the grass colour of its climate, its snow and
// sand cover and whether it lies on the generated surface (natural, so a
// dug pit's floor and a mound show bare topsoil). The field shader blends
// grass, sand, snow and the steep face's rock over the topsoil by them.
// They are looks, not materials: a dug sample is the topsoil it was. A
// pure function of the vertex's position, so neighbouring nodes and
// levels give a shared place the same look. Floats are fine here: nothing
// of it reaches the simulation.

// The variation: a noise of this wavelength and a second octave at these
// thousandths of it, stretched so it spans the range, moves the climate,
// the grass's brightness and the sand line a little, so no two places of
// one climate look alike.
GROUND_VARIATION_WAVELENGTH_METRES :: 48
GROUND_VARIATION_SECOND_PERMILLE :: 277
// Also the strata tint's stretch (field_ground_tint).
GROUND_VARIATION_STRETCH :: 1.6
GROUND_VARIATION_CELSIUS :: 1.0
GROUND_VARIATION_MOISTURE :: 0.14
GROUND_VARIATION_BRIGHTNESS :: 0.07
GROUND_VARIATION_SAND_METRES :: 0.8
// The strata tint's wavelength, the old tint cubes' edge.
GROUND_TINT_WAVELENGTH_METRES :: 256
// A vertex within the larger of this and a grid cell of the generated
// surface is natural ground, past twice that a cut or a fill.
FIELD_CUT_TOLERANCE_MILLIMETRES :: 750

// The look's part of a vertex: the grass colour at full light, the snow's
// and the sand's cover and the natural share, 0 to 255 each.
Field_Vertex_Look :: struct {
	grass:   [3]u8,
	snow:    u8,
	sand:    u8,
	natural: u8,
}

// What the mesher reads for the look; on is whether the planet has a
// climate. The palette is the planet's, which the streaming keeps.
Field_Ground_Look :: struct {
	on:         bool,
	generation: Planet_Generation,
	climate:    Planet_Climate,
	palette:    [][3]int,
}

make_field_ground_look :: proc(generation: Planet_Generation, planet: Planet) -> Field_Ground_Look {
	return Field_Ground_Look{on = planet.climate != {}, generation = generation, climate = planet.climate, palette = planet.palette}
}

// From -1 to 1.
ground_variation :: proc(generation: Planet_Generation, on_sphere: [3]i64) -> f32 {
	wavelength := metres_to_position_units(GROUND_VARIATION_WAVELENGTH_METRES)
	first := value_noise(generation_seed.hash_combine(generation.ground_look_seed, 0), on_sphere, wavelength)
	second := value_noise(generation_seed.hash_combine(generation.ground_look_seed, 1), on_sphere, wavelength * GROUND_VARIATION_SECOND_PERMILLE / 1000)
	return clamp(f32(2 * first + second) / (3 * NOISE_ONE) * GROUND_VARIATION_STRETCH, -1, 1)
}

// The strata's tint with a climate: a noise of GROUND_TINT_WAVELENGTH_METRES
// read as a continuous index along the palette, linear between its
// entries, so the tint never steps. Also the arrival debris' tint.
field_ground_tint :: proc(generation: Planet_Generation, palette: [][3]int, on_sphere: [3]i64) -> [3]u8 {
	if len(palette) == 1 {
		return field_color_bytes({f32(palette[0].r), f32(palette[0].g), f32(palette[0].b)})
	}
	noise := value_noise(generation_seed.hash_combine(generation.ground_look_seed, 2), on_sphere, metres_to_position_units(GROUND_TINT_WAVELENGTH_METRES))
	position := clamp((f32(noise) * GROUND_VARIATION_STRETCH / NOISE_ONE + 1) / 2, 0, 1) * f32(len(palette) - 1)
	index := min(int(position), len(palette) - 2)
	share := position - f32(index)
	low, high := palette[index], palette[index + 1]
	return field_color_bytes(field_color_float(low) + (field_color_float(high) - field_color_float(low)) * share)
}

field_color_float :: proc(color: [3]int) -> [3]f32 {
	return {f32(color.r), f32(color.g), f32(color.b)}
}

// Rounded and clamped to bytes.
field_color_bytes :: proc(color: [3]f32) -> [3]u8 {
	return {u8(clamp(math.round(color.r), 0, 255)), u8(clamp(math.round(color.g), 0, 255)), u8(clamp(math.round(color.b), 0, 255))}
}

// Bilinear over the climate's 3 by 3 grass colours: the temperature from
// the cold row to the hot one, the moisture (0 to 1) from the dry column
// to the wet one, clamped outside.
field_grass_color :: proc(climate: Planet_Climate, celsius, moisture: f32) -> [3]f32 {
	across := clamp((celsius - f32(climate.grass_cold_celsius)) / f32(climate.grass_hot_celsius - climate.grass_cold_celsius), 0, 1) * 2
	wetness := clamp(moisture, 0, 1) * 2
	row, column := min(int(across), 1), min(int(wetness), 1)
	row_share, column_share := across - f32(row), wetness - f32(column)
	at :: proc(climate: Planet_Climate, row, column: int) -> [3]f32 {
		return field_color_float(climate.grass_colors[row * 3 + column])
	}
	low := math.lerp(at(climate, row, column), at(climate, row, column + 1), column_share)
	high := math.lerp(at(climate, row + 1, column), at(climate, row + 1, column + 1), column_share)
	return math.lerp(low, high, row_share)
}

// A share from 0 to 1 as a byte, rounded.
field_share_byte :: proc(share: f32) -> u8 {
	return u8(math.round(255 * clamp(share, 0, 1)))
}

// Full below the snow line's temperature by half the fade, none above it
// by half the fade.
field_snow_cover :: proc(climate: Planet_Climate, celsius: f32) -> u8 {
	return field_share_byte((f32(climate.snow_celsius) - celsius) / f32(climate.snow_fade_celsius) + 0.5)
}

// Full below the sand line's height over the sea by half the fade, none
// above it by half the fade.
field_sand_cover :: proc(climate: Planet_Climate, height_metres: f32) -> u8 {
	return field_share_byte((f32(climate.sand_metres) - height_metres) / f32(climate.sand_fade_metres) + 0.5)
}

// How natural the ground at a vertex is: 255 within the tolerance (the
// larger of FIELD_CUT_TOLERANCE_MILLIMETRES and the grid's cell) of the
// generated surface along its radial, 0 past twice it, linear between.
// The surface is the relief without the crater, so the arrival's crater
// reads as cut ground.
field_natural_share :: proc(generation: Planet_Generation, on_sphere: [3]i64, distance, cell: i64) -> u8 {
	off := abs(distance - generation.radius - uncratered_relief(generation, on_sphere))
	tolerance := max(millimetres_to_position_units(FIELD_CUT_TOLERANCE_MILLIMETRES), cell)
	switch {
	case off <= tolerance:
		return 255
	case off >= 2 * tolerance:
		return 0
	}
	return u8(255 * (2 * tolerance - off) / tolerance)
}

// A surface vertex's position in the world: the grid's origin plus the
// vertex's 1/FIELD_MESH_POSITION_UNITS of a grid cell.
field_vertex_world_position :: proc(grid: ^Field_Grid, position: [3]i32, spacing_millimetres: int) -> World_Position {
	result := sample_to_world_position(grid.origin, spacing_millimetres)
	for axis in 0 ..< 3 {
		result[axis] += floor_divide_i64(i64(position[axis]) * i64(grid.step) * i64(spacing_millimetres) * POSITION_UNITS_PER_METRE, FIELD_MESH_POSITION_UNITS * MILLIMETRES_PER_METRE)
	}
	return result
}

// The strata tint and the look of a vertex at the position. cell is the
// grid's cell in position units; the natural share is measured with
// measure_cuts at every vertex, the stone ones too: a cut topsoil vertex
// beside a stone one counted natural would interpolate grass onto a mined
// floor. Without measure_cuts every vertex is natural.
field_vertex_ground_look :: proc(look: Field_Ground_Look, position: World_Position, cell: i64, measure_cuts: bool) -> (tint: [3]u8, vertex: Field_Vertex_Look) {
	generation := look.generation
	distance := vector_length(([3]i64)(position))
	on_sphere := project_onto_sphere(position, distance, generation.radius)
	height := distance - generation.sea_radius
	climate := planet_climate(generation, on_sphere, height)
	variation := ground_variation(generation, on_sphere)
	celsius := f32(climate.temperature_millicelsius) / 1000 + variation * GROUND_VARIATION_CELSIUS
	moisture := f32(climate.moisture_permille) / 1000 + variation * GROUND_VARIATION_MOISTURE
	vertex.grass = field_color_bytes(field_grass_color(look.climate, celsius, moisture) * (1 + variation * GROUND_VARIATION_BRIGHTNESS))
	vertex.snow = field_snow_cover(look.climate, celsius)
	vertex.sand = field_sand_cover(look.climate, f32(height) / POSITION_UNITS_PER_METRE + variation * GROUND_VARIATION_SAND_METRES)
	vertex.natural = measure_cuts ? field_natural_share(generation, on_sphere, distance, cell) : 255
	return field_ground_tint(generation, look.palette, on_sphere), vertex
}

// Every vertex's tint and look; nothing without a climate. It runs before
// the skirts (append_field_skirts), which copy their border vertex: a
// skirt's lower vertices would otherwise read as cut and show bare seams.
// measure_cuts is whether the grid holds loaded samples, which an edit
// can have moved off the generated surface.
write_field_ground_look :: proc(surface: ^Field_Surface, grid: ^Field_Grid, look: Field_Ground_Look, spacing_millimetres: int, measure_cuts: bool) {
	if !look.on {
		return
	}
	cell := sample_axis_to_position(grid.step, spacing_millimetres)
	for &vertex in surface.vertices {
		position := field_vertex_world_position(grid, vertex.position, spacing_millimetres)
		vertex.color, vertex.look = field_vertex_ground_look(look, position, cell, measure_cuts)
	}
}
