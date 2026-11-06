package game

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strconv"
import "core:strings"
import rl "shared:raylib"
import "platform"

// --relief-map (work item 0306, doc/build.md, The workbench): a shaded
// height map of a square round a latitude and longitude on the default
// planet, for tuning the relief without a window. The heights are the
// generation's integer relief with the crater baked; floats only place
// the pixels. The sea, contour lines every 10 m (bolder every 50 m), the
// home and the springs with the streams their water runs down. One PNG,
// lines on stdout, no window, no world.

RELIEF_MAP_PIXELS :: 800
RELIEF_MAP_MINIMUM_METRES :: 100
RELIEF_MAP_MAXIMUM_METRES :: 20_000
// A stream's trail is capped at this many steps of
// RELIEF_MAP_STREAM_STEP_METRES.
RELIEF_MAP_STREAM_STEPS :: 4000
RELIEF_MAP_STREAM_STEP_METRES :: 2
// A stream's steps try this many headings; a pit spills over the lowest
// of RELIEF_MAP_PIT_HEADINGS on rings out to RELIEF_MAP_PIT_METRES.
RELIEF_MAP_STREAM_HEADINGS :: 32
RELIEF_MAP_PIT_HEADINGS :: 64
RELIEF_MAP_PIT_RING_METRES :: 4
RELIEF_MAP_PIT_METRES :: 16

RELIEF_MAP_STREAM_COLOUR :: [4]u8{255, 40, 200, 255}
RELIEF_MAP_SPRING_COLOUR :: [4]u8{0, 200, 255, 255}
RELIEF_MAP_HOME_COLOUR :: [4]u8{255, 255, 255, 255}
RELIEF_MAP_OUTLINE_COLOUR :: [4]u8{0, 0, 0, 255}
RELIEF_MAP_COAST_COLOUR :: [3]f64{20, 20, 60}

Relief_Map_Request :: struct {
	latitude_degrees, longitude_degrees: f64,
	size_metres, radius_metres:          int,
}

// The map's centre and its east and north tangents, unit vectors laid out
// as planet_direction_at's.
Relief_Map_Frame :: struct {
	centre, east, north: [3]f64,
}

Relief_Map_Stream_End :: enum {
	Sea,
	Pit,
	Limit,
}

// The unit directions the water passed, the distance it ran, the height
// it lost in position units and why it stopped.
Relief_Map_Stream :: struct {
	trail:         [dynamic][3]i64,
	length_metres: int,
	drop:          i64,
	end:           Relief_Map_Stream_End,
}

RELIEF_MAP_ARGUMENT_FORM :: "<latitude>,<longitude>,<size_metres>[,<radius_metres>]"

// Three or four comma separated words: the latitude and the longitude in
// degrees, the square's edge in metres and the radius (0 or absent for
// the planet's default).
parse_relief_map_argument :: proc(argument: string) -> (request: Relief_Map_Request, problem: string) {
	words := strings.split(argument, ",", context.temp_allocator)
	if len(words) < 3 || len(words) > 4 {
		return {}, fmt.tprintf("expected %s", RELIEF_MAP_ARGUMENT_FORM)
	}
	latitude, latitude_parsed := strconv.parse_f64(words[0])
	if !latitude_parsed || !(latitude >= -90 && latitude <= 90) {
		return {}, fmt.tprintf("the latitude %q is not a number from -90 to 90", words[0])
	}
	longitude, longitude_parsed := strconv.parse_f64(words[1])
	if !longitude_parsed || !(longitude >= -180 && longitude <= 180) {
		return {}, fmt.tprintf("the longitude %q is not a number from -180 to 180", words[1])
	}
	size, size_parsed := parse_integer_word(words[2])
	if !size_parsed || size < RELIEF_MAP_MINIMUM_METRES || size > RELIEF_MAP_MAXIMUM_METRES {
		return {}, fmt.tprintf("the size %q is not a whole number of metres from %d to %d", words[2], RELIEF_MAP_MINIMUM_METRES, RELIEF_MAP_MAXIMUM_METRES)
	}
	radius: i32 = 0
	if len(words) == 4 {
		radius_parsed: bool
		radius, radius_parsed = parse_integer_word(words[3])
		if !radius_parsed || radius < 0 {
			return {}, fmt.tprintf("the radius %q is not a whole number of metres, 0 or more", words[3])
		}
	}
	return Relief_Map_Request{latitude, longitude, int(size), int(radius)}, ""
}

// The default planet at the radius (0 for its default), which must be
// one of its presets, its home the one a new world of the seed takes.
relief_map_planet :: proc(planets: []Planet, seed: u64, radius_metres: int) -> (planet: Planet, problem: string) {
	planet = default_planet(planets)
	if radius_metres != 0 {
		if !slice.contains(planet.radius_presets_metres, radius_metres) {
			return {}, fmt.tprintf("the radius %d m is not one of the planet %q's presets %v", radius_metres, planet.id, planet.radius_presets_metres)
		}
		planet.radius_metres = radius_metres
	}
	planet.home = new_world_home(seed, planet)
	return planet, ""
}

relief_map_frame :: proc(request: Relief_Map_Request) -> Relief_Map_Frame {
	latitude, longitude := math.to_radians(request.latitude_degrees), math.to_radians(request.longitude_degrees)
	return Relief_Map_Frame {
		centre = {math.cos(latitude) * math.cos(longitude), math.sin(latitude), math.cos(latitude) * math.sin(longitude)},
		east = {-math.sin(longitude), 0, math.cos(longitude)},
		north = {-math.sin(latitude) * math.cos(longitude), math.cos(latitude), -math.sin(latitude) * math.sin(longitude)},
	}
}

// The point on the sphere of the radius under the plane's point east and
// north of the centre (the gnomonic projection), in position units.
relief_map_point :: proc(request: Relief_Map_Request, radius_metres: int, east_metres, north_metres: f64) -> [3]i64 {
	frame := relief_map_frame(request)
	radius := f64(radius_metres)
	plane := frame.centre * radius + frame.east * east_metres + frame.north * north_metres
	length := math.sqrt(plane.x * plane.x + plane.y * plane.y + plane.z * plane.z)
	point := plane * (radius / length) * POSITION_UNITS_PER_METRE
	return {i64(math.round(point.x)), i64(math.round(point.y)), i64(math.round(point.z))}
}

// The surface_relief at each pixel's centre, row major, north up.
relief_map_heights :: proc(generation: Planet_Generation, request: Relief_Map_Request, pixels: int, allocator := context.allocator) -> []i64 {
	heights := make([]i64, pixels * pixels, allocator)
	radius_metres := int(generation.radius / POSITION_UNITS_PER_METRE)
	metres_per_pixel := f64(request.size_metres) / f64(pixels)
	for row in 0 ..< pixels {
		for column in 0 ..< pixels {
			east := (f64(column) + 0.5 - f64(pixels) / 2) * metres_per_pixel
			north := (f64(pixels) / 2 - f64(row) - 0.5) * metres_per_pixel
			heights[row * pixels + column] = surface_relief(generation, relief_map_point(request, radius_metres, east, north))
		}
	}
	return heights
}

// The colour of a height over the sea in metres: blues under it, from
// sand through greens, browns and greys to snow over it.
relief_map_height_colour :: proc(over_sea: f64) -> [3]f64 {
	Stop :: struct {
		height: f64,
		colour: [3]f64,
	}
	under := [?]Stop{{-60, {20, 40, 90}}, {-20, {40, 80, 150}}, {0, {90, 140, 200}}}
	over := [?]Stop{{0, {196, 190, 140}}, {3, {120, 160, 90}}, {15, {90, 140, 70}}, {35, {150, 150, 90}}, {60, {140, 110, 80}}, {90, {170, 160, 150}}, {120, {240, 240, 240}}}
	stops := over_sea < 0 ? under[:] : over[:]
	if over_sea <= stops[0].height {
		return stops[0].colour
	}
	for index in 1 ..< len(stops) {
		if over_sea <= stops[index].height {
			first, second := stops[index - 1], stops[index]
			share := (over_sea - first.height) / (second.height - first.height)
			return first.colour + (second.colour - first.colour) * share
		}
	}
	return stops[len(stops) - 1].colour
}

// The height over the sea in metres at a pixel, the edges clamped.
relief_map_height_at :: proc(heights: []i64, sea_level: i64, pixels, row, column: int) -> f64 {
	return f64(heights[clamp(row, 0, pixels - 1) * pixels + clamp(column, 0, pixels - 1)] - sea_level) / POSITION_UNITS_PER_METRE
}

// The hill shade from central differences, lit from the north west 45
// degrees up: 0 facing away, 1 facing the light.
relief_map_shade :: proc(heights: []i64, sea_level: i64, metres_per_pixel: f64, pixels, row, column: int) -> f64 {
	east := (relief_map_height_at(heights, sea_level, pixels, row, column + 1) - relief_map_height_at(heights, sea_level, pixels, row, column - 1)) / (2 * metres_per_pixel)
	north := (relief_map_height_at(heights, sea_level, pixels, row - 1, column) - relief_map_height_at(heights, sea_level, pixels, row + 1, column)) / (2 * metres_per_pixel)
	length := math.sqrt(east * east + north * north + 1)
	light := [3]f64{-0.5, 0.5, 0.707}
	return clamp((-east * light.x - north * light.y + light.z) / length, 0, 1)
}

// The map's colours, row major: the height's colour, shaded (the sea
// less), darkened on the 10 m contours (more on the 50 m ones) and the
// coastline drawn.
relief_map_colours :: proc(heights: []i64, sea_level: i64, metres_per_pixel: f64, pixels: int, allocator := context.allocator) -> [][4]u8 {
	colours := make([][4]u8, pixels * pixels, allocator)
	for row in 0 ..< pixels {
		for column in 0 ..< pixels {
			height := relief_map_height_at(heights, sea_level, pixels, row, column)
			shade := relief_map_shade(heights, sea_level, metres_per_pixel, pixels, row, column)
			colour := relief_map_height_colour(height)
			colour *= height < 0 ? 0.75 + 0.25 * shade : 0.35 + 0.8 * shade
			for neighbour in ([2][2]int{{0, 1}, {1, 0}}) {
				other := relief_map_height_at(heights, sea_level, pixels, row + neighbour[0], column + neighbour[1])
				if height >= 0 && math.floor(height / 10) != math.floor(other / 10) {
					colour *= math.floor(height / 50) != math.floor(other / 50) ? 0.45 : 0.72
				}
				if (height < 0) != (other < 0) {
					colour = RELIEF_MAP_COAST_COLOUR
				}
			}
			colours[row * pixels + column] = {u8(clamp(colour.x, 0, 255)), u8(clamp(colour.y, 0, 255)), u8(clamp(colour.z, 0, 255)), 255}
		}
	}
	return colours
}

// The tangent plane at a unit direction: east the cross of +y (+x near
// the poles) with it, north the cross of it with east.
relief_map_tangents :: proc(direction: [3]i64) -> (east, north: [3]i64) {
	reference := [3]i64{0, UNIT_VECTOR_ONE, 0}
	if abs(direction.y) >= UNIT_VECTOR_ONE * 9 / 10 {
		reference = {UNIT_VECTOR_ONE, 0, 0}
	}
	east, _ = normalize_fixed(fixed_cross(reference, direction))
	north, _ = normalize_fixed(fixed_cross(direction, east))
	return
}

// The lowest of the headings distance out from the direction in the
// tangent plane, and found when it lies under the height.
relief_map_lowest_heading :: proc(generation: Planet_Generation, direction: [3]i64, height, distance: i64, headings: int) -> (lowest_direction: [3]i64, lowest: i64, found: bool) {
	east, north := relief_map_tangents(direction)
	lowest = height
	for heading in 0 ..< headings {
		angle := i32(heading * ANGLE_UNITS_PER_TURN / headings)
		offset := fixed_scale(east, distance * fixed_cosine(angle) / UNIT_VECTOR_ONE) + fixed_scale(north, distance * fixed_sine(angle) / UNIT_VECTOR_ONE)
		candidate, _ := normalize_fixed(fixed_scale(direction, generation.radius) + offset)
		relief := surface_relief(generation, fixed_scale(candidate, generation.radius))
		if relief < lowest {
			lowest_direction, lowest, found = candidate, relief, true
		}
	}
	return
}

// The steepest descent from the spring's direction in fixed point: each
// step the lowest of RELIEF_MAP_STREAM_HEADINGS headings
// RELIEF_MAP_STREAM_STEP_METRES out, while lower than here; a pit spills
// over the lowest point of the first ring out to RELIEF_MAP_PIT_METRES
// that holds one lower. It ends under the sea, in a pit nothing spills
// from, or at RELIEF_MAP_STREAM_STEPS steps.
relief_map_stream :: proc(generation: Planet_Generation, start_direction: [3]i64, allocator := context.allocator) -> Relief_Map_Stream {
	stream := Relief_Map_Stream {
		trail = make([dynamic][3]i64, 0, 64, allocator),
		end   = .Limit,
	}
	sea := generation.sea_radius - generation.radius
	direction := start_direction
	height := surface_relief(generation, fixed_scale(direction, generation.radius))
	start := height
	for _ in 0 ..< RELIEF_MAP_STREAM_STEPS {
		append(&stream.trail, direction)
		if height < sea {
			stream.end = .Sea
			break
		}
		next, lowest, found := relief_map_lowest_heading(generation, direction, height, metres_to_position_units(RELIEF_MAP_STREAM_STEP_METRES), RELIEF_MAP_STREAM_HEADINGS)
		moved := RELIEF_MAP_STREAM_STEP_METRES
		for ring := RELIEF_MAP_PIT_RING_METRES; !found && ring <= RELIEF_MAP_PIT_METRES; ring += RELIEF_MAP_PIT_RING_METRES {
			next, lowest, found = relief_map_lowest_heading(generation, direction, height, metres_to_position_units(i64(ring)), RELIEF_MAP_PIT_HEADINGS)
			moved = ring
		}
		if !found {
			stream.end = .Pit
			break
		}
		stream.length_metres += moved
		direction, height = next, lowest
	}
	stream.drop = start - height
	return stream
}

// A disc of the colour at the direction's place on the map, clipped to
// the image; nothing when the direction lies behind the centre.
relief_map_mark :: proc(colours: [][4]u8, pixels: int, request: Relief_Map_Request, radius_metres: int, metres_per_pixel: f64, direction: [3]i64, colour: [4]u8, size: int) {
	frame := relief_map_frame(request)
	unit := [3]f64{f64(direction.x), f64(direction.y), f64(direction.z)} / UNIT_VECTOR_ONE
	along := unit.x * frame.centre.x + unit.y * frame.centre.y + unit.z * frame.centre.z
	if along <= 0 {
		return
	}
	scale := f64(radius_metres) / along
	east := (unit.x * frame.east.x + unit.y * frame.east.y + unit.z * frame.east.z) * scale
	north := (unit.x * frame.north.x + unit.y * frame.north.y + unit.z * frame.north.z) * scale
	column := int(math.floor(east / metres_per_pixel + f64(pixels) / 2))
	row := int(math.floor(f64(pixels) / 2 - north / metres_per_pixel))
	for row_offset in -size ..= size {
		for column_offset in -size ..= size {
			at_row, at_column := row + row_offset, column + column_offset
			if row_offset * row_offset + column_offset * column_offset <= size * size && at_row >= 0 && at_row < pixels && at_column >= 0 && at_column < pixels {
				colours[at_row * pixels + at_column] = colour
			}
		}
	}
}

// Encoded as PNG without a window and written through
// write_file_replacing; the problem, or "".
write_relief_map_png :: proc(colours: [][4]u8, pixels: int, path: string) -> string {
	image := rl.Image {
		data    = raw_data(colours),
		width   = i32(pixels),
		height  = i32(pixels),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	size: i32
	data := rl.ExportImageToMemory(image, ".png", &size)
	if data == nil {
		return "cannot encode the map"
	}
	defer rl.MemFree(data)
	return platform.write_file_replacing(path, ([^]byte)(data)[:size])
}

relief_map_stream_end_name :: proc(end: Relief_Map_Stream_End) -> string {
	switch end {
	case .Sea:
		return "sea"
	case .Pit:
		return "pit"
	case .Limit:
		return "limit"
	}
	return ""
}

// 2 for a bad argument or radius, 1 when the map cannot be written, 0
// otherwise.
run_relief_map :: proc(argument, path: string, seed: u64, planets: []Planet) -> int {
	request, problem := parse_relief_map_argument(argument)
	planet: Planet
	if problem == "" {
		planet, problem = relief_map_planet(planets, seed, request.radius_metres)
	}
	if problem != "" {
		platform.log_printf("error: --relief-map=%s: %s", argument, problem)
		return 2
	}
	generation := baked_planet_generation(make_planet_generation(seed, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES))
	sea := generation.sea_radius - generation.radius
	pixels := RELIEF_MAP_PIXELS
	metres_per_pixel := f64(request.size_metres) / f64(pixels)
	heights := relief_map_heights(generation, request, pixels)
	defer delete(heights)
	colours := relief_map_colours(heights, sea, metres_per_pixel, pixels)
	defer delete(colours)
	fmt.printfln("relief map: seed %d, radius %d m, relief %.1f to %.1f m from the radius, home at latitude %d, longitude %d, crater floor %.1f m over the sea", seed, planet.radius_metres, f64(generation.relief_lowest) / POSITION_UNITS_PER_METRE, f64(generation.relief_highest) / POSITION_UNITS_PER_METRE, planet.home.latitude_degrees, planet.home.longitude_degrees, f64(generation.crater.floor_height - sea) / POSITION_UNITS_PER_METRE)
	for spring, index in planet.springs {
		direction := planet_spring_direction(spring)
		stream := relief_map_stream(generation, direction)
		defer delete(stream.trail)
		for point in stream.trail {
			relief_map_mark(colours, pixels, request, planet.radius_metres, metres_per_pixel, point, RELIEF_MAP_STREAM_COLOUR, 1)
		}
		ground := surface_relief(generation, fixed_scale(direction, generation.radius)) - sea
		fmt.printfln("relief map: spring %d at latitude %d, longitude %d: %.1f m over the sea, stream %d m, drop %.1f m, ends at %s", index, spring.latitude_degrees, spring.longitude_degrees, f64(ground) / POSITION_UNITS_PER_METRE, stream.length_metres, f64(stream.drop) / POSITION_UNITS_PER_METRE, relief_map_stream_end_name(stream.end))
	}
	for spring in planet.springs {
		relief_map_mark(colours, pixels, request, planet.radius_metres, metres_per_pixel, planet_spring_direction(spring), RELIEF_MAP_OUTLINE_COLOUR, 5)
		relief_map_mark(colours, pixels, request, planet.radius_metres, metres_per_pixel, planet_spring_direction(spring), RELIEF_MAP_SPRING_COLOUR, 3)
	}
	home := planet_home_direction(planet.home)
	relief_map_mark(colours, pixels, request, planet.radius_metres, metres_per_pixel, home, RELIEF_MAP_OUTLINE_COLOUR, 5)
	relief_map_mark(colours, pixels, request, planet.radius_metres, metres_per_pixel, home, RELIEF_MAP_HOME_COLOUR, 3)
	if problem = write_relief_map_png(colours, pixels, path); problem != "" {
		platform.log_printf("error: --relief-map-file=%s: %s", path, problem)
		return 1
	}
	return 0
}
