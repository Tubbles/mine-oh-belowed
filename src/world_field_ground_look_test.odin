package game

@(require) import "core:log"
import "core:math"
@(require) import "core:mem/virtual"
import "core:math/linalg"
import "core:testing"
@(require) import "core:time"

// Work item 0307: the ground's look per vertex.

// The test planet with the shipped climate and home.
ground_look_test_planet :: proc() -> Planet {
	planet := make_test_planet()
	planet.climate = SHIPPED_TEST_CLIMATE
	planet.home = {latitude_degrees = 83, longitude_degrees = 132}
	return planet
}

// The finest node whose chunk holds the surface ahead metres from the home
// along a tangent.
ground_look_test_node :: proc(generation: Planet_Generation, home: Planet_Home, ahead: i64) -> Field_Node {
	direction := planet_home_direction(home)
	forward := tangent_of(direction, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, direction)
	on_sphere := test_sphere_point(generation, direction, forward, right, ahead, 0)
	surface := on_sphere * (generation.radius + surface_relief(generation, on_sphere)) / generation.radius
	return field_chunk_node(sample_to_field_chunk_coordinate(world_position_to_sample(World_Position(surface), generation.spacing_millimetres)))
}

ground_look_test_grid :: proc(generation: Planet_Generation, node: Field_Node) -> ^Field_Grid {
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	return grid
}

// The mesh with the look on, its cuts measured, skirts on every face
// unless asked otherwise. Its positions are scaled from samples to metres
// in place (0381), since the look's tests read metres; times 1 at 1000 mm.
ground_look_test_mesh :: proc(grid: ^Field_Grid, generation: Planet_Generation, planet: Planet, skirt_faces := Field_Seam_Faces{flaps = EVERY_FIELD_FACE}) -> Field_Mesh_Data {
	look := make_field_ground_look(generation, planet)
	data := mesh_field_grid(grid, planet.palette, generation.spacing_millimetres, skirt_faces, context.temp_allocator, look, true)
	metres_per_sample := field_metres_per_sample(generation.spacing_millimetres)
	for &position in data.positions {
		position *= metres_per_sample
	}
	return data
}

// A vertex's snow, sand and natural share as bytes.
ground_look_test_cover :: proc(data: Field_Mesh_Data, index: int) -> [3]u8 {
	unpacked := unpack_test_bytes(data.looks[index].y) * 255
	return {u8(unpacked.x), u8(unpacked.y), u8(unpacked.z)}
}

// The vertex of the mesh nearest a point in metres from the node's origin.
ground_look_test_nearest :: proc(data: Field_Mesh_Data, point: [3]f32) -> int {
	nearest, best := 0, max(f32)
	for position, index in data.positions {
		if distance := linalg.length(position - point); distance < best {
			nearest, best = index, distance
		}
	}
	return nearest
}

@(test)
test_the_ground_look_is_off_without_a_climate :: proc(t: ^testing.T) {
	planet := make_test_planet()
	planet.home = {latitude_degrees = 83, longitude_degrees = 132}
	generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
	grid := ground_look_test_grid(generation, ground_look_test_node(generation, planet.home, 200))
	plain := mesh_field_grid(grid, planet.palette, 1000, {flaps = EVERY_FIELD_FACE}, context.temp_allocator)
	looked := ground_look_test_mesh(grid, generation, planet)
	testing.expect(t, len(plain.positions) > 0, "the node holds the surface")
	testing.expect(t, mesh_data_equal(plain, looked), "the look changes the mesh without a climate")
	for look in looked.looks {
		testing.expect_value(t, look, [2]f32{0, 0})
	}
}

@(test)
test_a_generated_node_meshes_natural_with_its_skirts :: proc(t: ^testing.T) {
	planet := ground_look_test_planet()
	for spacing in ([2]int{1000, 333}) {
		generation := make_planet_generation(TEST_PLANET_SEED, planet, spacing)
		grid := ground_look_test_grid(generation, ground_look_test_node(generation, planet.home, 200))
		data := ground_look_test_mesh(grid, generation, planet)
		natural := 0
		for index in 0 ..< len(data.positions) {
			natural += ground_look_test_cover(data, index).z == 255 ? 1 : 0
		}
		testing.expectf(t, len(data.positions) > 0 && natural * 100 >= 98 * len(data.positions), "at %d mm %d of %d vertices are natural", spacing, natural, len(data.positions))
	}
}

// How far a mesh vertex (metres from the grid's origin) lies off the
// generated surface along its radial, in metres, as field_natural_share
// measures it.
ground_look_test_off_metres :: proc(generation: Planet_Generation, grid: ^Field_Grid, position: [3]f32) -> f32 {
	world := sample_to_world_position(grid.origin, generation.spacing_millimetres)
	for axis in 0 ..< 3 {
		world[axis] += i64(math.round(position[axis] * POSITION_UNITS_PER_METRE))
	}
	distance := vector_length(([3]i64)(world))
	on_sphere := project_onto_sphere(world, distance, generation.radius)
	return f32(abs(distance - generation.radius - uncratered_relief(generation, on_sphere))) / POSITION_UNITS_PER_METRE
}

// A vertex's grass cover before the slope and the snow and the sand: its
// topsoil weight times its natural share, both as the shader interpolates
// them.
ground_look_test_grass_cover :: proc(data: Field_Mesh_Data, first, second: int) -> f32 {
	topsoil := (data.weights[first].x + data.weights[second].x) / 2
	natural := (f32(ground_look_test_cover(data, first).z) + f32(ground_look_test_cover(data, second).z)) / 2
	return topsoil * natural
}

// A pit of the radius carved round the surface vertex nearest the node's
// centre 200 m from the home, at the spacing: the floor's vertices read
// cut ground, the stone ones under the 2 m of topsoil too, so no triangle
// of the floor or the topsoil's base interpolates grass onto it (cover is
// checked at the vertices and the edges' midpoints); the ground beyond the
// pit keeps its look. The meshes have no skirts: a skirt vertex hangs
// below its border vertex with that vertex's look. floor_meets_topsoil
// asks for a floor triangle with a topsoil and a stone corner, the case a
// stone vertex counted natural broke.
expect_a_dug_pit_floor_is_not_natural :: proc(t: ^testing.T, spacing: int, pit_radius_metres: f32, floor_holds_topsoil, floor_meets_topsoil: bool) {
	planet := ground_look_test_planet()
	generation := make_planet_generation(TEST_PLANET_SEED, planet, spacing)
	node := ground_look_test_node(generation, planet.home, 200)
	grid := ground_look_test_grid(generation, node)
	before := ground_look_test_mesh(grid, generation, planet, {})
	cell_metres := f32(spacing) / MILLIMETRES_PER_METRE
	centre := [3]f32{1, 1, 1} * f32(FIELD_GRID_CELLS) * cell_metres / 2
	pit := before.positions[ground_look_test_nearest(before, centre)]
	origin := field_node_origin_metres(node, spacing)
	up := linalg.normalize(origin + pit)
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				index := field_grid_index({x, y, z})
				distance := linalg.length([3]f32{f32(x), f32(y), f32(z)} * cell_metres - pit)
				carved := i8(clamp((distance - pit_radius_metres) / cell_metres * DENSITY_STEPS_PER_SAMPLE, -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
				if carved < grid.density[index] {
					grid.density[index] = carved
				}
				if grid.density[index] <= 0 {
					grid.material[index], grid.tint[index] = .Air, 0
				}
			}
		}
	}
	after := ground_look_test_mesh(grid, generation, planet, {})
	bottom := pit - up * pit_radius_metres
	floor := ground_look_test_nearest(after, bottom)
	testing.expectf(t, linalg.length(after.positions[floor] - bottom) < cell_metres, "at %d mm the floor's vertex lies %v m from the pit's bottom", spacing, linalg.length(after.positions[floor] - bottom))
	testing.expectf(t, (after.weights[floor].x > 0) == floor_holds_topsoil, "at %d mm the floor's topsoil weight is %v", spacing, after.weights[floor].x)
	testing.expect_value(t, ground_look_test_cover(after, floor).z, 0)
	// Past twice the tolerance off the generated surface, with a margin
	// for the positions' rounding to metres.
	cut_metres := 2 * max(f32(FIELD_CUT_TOLERANCE_MILLIMETRES), f32(spacing)) / MILLIMETRES_PER_METRE + 0.05
	cut := make([]bool, len(after.positions), context.temp_allocator)
	cut_count := 0
	for position, index in after.positions {
		if ground_look_test_off_metres(generation, grid, position) >= cut_metres {
			cut[index] = true
			cut_count += 1
			testing.expectf(t, ground_look_test_cover(after, index).z == 0, "at %d mm a vertex %v m off the surface reads natural %d", spacing, ground_look_test_off_metres(generation, grid, position), ground_look_test_cover(after, index).z)
		}
	}
	floor_triangles, mixed_triangles := 0, 0
	for triangle := 0; triangle + 2 < len(after.indices); triangle += 3 {
		corners := [3]int{int(after.indices[triangle]), int(after.indices[triangle + 1]), int(after.indices[triangle + 2])}
		if !cut[corners[0]] || !cut[corners[1]] || !cut[corners[2]] {
			continue
		}
		floor_triangles += 1
		topsoil_corners := 0
		for corner in corners {
			topsoil_corners += after.weights[corner].x > 0 ? 1 : 0
		}
		mixed_triangles += topsoil_corners > 0 && topsoil_corners < 3 ? 1 : 0
		for corner, index in corners {
			next := corners[(index + 1) % 3]
			testing.expectf(t, ground_look_test_grass_cover(after, corner, corner) == 0 && ground_look_test_grass_cover(after, corner, next) == 0, "at %d mm a floor triangle carries grass", spacing)
		}
	}
	testing.expectf(t, cut_count > 0 && floor_triangles > 0, "at %d mm the pit has %d cut vertices and %d floor triangles", spacing, cut_count, floor_triangles)
	testing.expectf(t, !floor_meets_topsoil || mixed_triangles > 0, "at %d mm no floor triangle meets the topsoil", spacing)
	before_natural := make(map[[3]f32]u8, context.temp_allocator)
	for position, index in before.positions {
		before_natural[position] = ground_look_test_cover(before, index).z
	}
	compared := 0
	for position, index in after.positions {
		if linalg.length(position - bottom) <= 6 {
			continue
		}
		if natural, found := before_natural[position]; found {
			testing.expect_value(t, ground_look_test_cover(after, index).z, natural)
			compared += 1
		}
	}
	testing.expectf(t, compared > 100, "at %d mm the ground beyond the pit was compared", spacing)
}

// The 2.5 m pit's floor lies in the stone under the 2 m of topsoil; the
// 1.6 m pit's at the finest spacing (tolerance 0.75 m) still in topsoil.
@(test)
test_a_dug_pit_floor_is_not_natural :: proc(t: ^testing.T) {
	expect_a_dug_pit_floor_is_not_natural(t, 1000, 2.5, false, false)
	expect_a_dug_pit_floor_is_not_natural(t, 333, 2.5, false, true)
	expect_a_dug_pit_floor_is_not_natural(t, 333, 1.6, true, false)
}

// The arrival's crater is not the generated relief (the look compares the
// relief without it), so its floor reads as cut ground.
@(test)
test_the_crater_reads_as_cut_ground :: proc(t: ^testing.T) {
	planet := ground_look_test_planet()
	planet.crater = {radius_metres = 12, depth_metres = 3, floor_radius_metres = 4, rim_metres = 1}
	generation := baked_planet_generation(make_planet_generation(TEST_PLANET_SEED, planet, 1000))
	node := ground_look_test_node(generation, planet.home, 0)
	data := ground_look_test_mesh(ground_look_test_grid(generation, node), generation, planet)
	home := world_position_to_metres(World_Position(fixed_scale(planet_home_direction(planet.home), generation.radius + generation.crater.floor_height))) - field_node_origin_metres(node, 1000)
	floor := 0
	for position, index in data.positions {
		if linalg.length(position - home) < 3 {
			testing.expect(t, data.weights[index].x > 0, "the crater's floor is topsoil")
			testing.expect_value(t, ground_look_test_cover(data, index).z, 0)
			floor += 1
		}
	}
	testing.expect(t, floor > 4, "the node holds the crater's floor")
}

@(test)
test_the_grass_colour_meets_the_anchors :: proc(t: ^testing.T) {
	climate := SHIPPED_TEST_CLIMATE
	cold, hot := f32(climate.grass_cold_celsius), f32(climate.grass_hot_celsius)
	anchor :: proc(climate: Planet_Climate, index: int) -> [3]f32 {
		return field_color_float(climate.grass_colors[index])
	}
	testing.expect_value(t, field_grass_color(climate, cold, 0), anchor(climate, 0))
	testing.expect_value(t, field_grass_color(climate, cold, 1), anchor(climate, 2))
	testing.expect_value(t, field_grass_color(climate, hot, 0), anchor(climate, 6))
	testing.expect_value(t, field_grass_color(climate, hot, 1), anchor(climate, 8))
	testing.expect_value(t, field_grass_color(climate, (cold + hot) / 2, 0.5), anchor(climate, 4))
	testing.expect_value(t, field_grass_color(climate, (cold + hot) / 2, 0), anchor(climate, 3))
	testing.expect_value(t, field_grass_color(climate, cold - 40, -1), anchor(climate, 0))
	testing.expect_value(t, field_grass_color(climate, hot + 40, 3), anchor(climate, 8))
	between := field_grass_color(climate, cold + (hot - cold) / 4, 0.25)
	expected := (anchor(climate, 0) + anchor(climate, 1) + anchor(climate, 3) + anchor(climate, 4)) / 4
	testing.expectf(t, linalg.length(between - expected) < 0.01, "between the anchors %v, expected %v", between, expected)
}

@(test)
test_the_snow_and_the_sand_fade_across_their_lines :: proc(t: ^testing.T) {
	climate := SHIPPED_TEST_CLIMATE
	testing.expect_value(t, field_snow_cover(climate, f32(climate.snow_celsius - 10)), 255)
	testing.expect_value(t, field_snow_cover(climate, f32(climate.snow_celsius + 10)), 0)
	testing.expect_value(t, field_sand_cover(climate, f32(climate.sand_metres - 10)), 255)
	testing.expect_value(t, field_sand_cover(climate, f32(climate.sand_metres + 10)), 0)
	previous_snow, previous_sand := u8(255), u8(255)
	partial_snow, partial_sand := 0, 0
	for step in -100 ..= 100 {
		snow := field_snow_cover(climate, f32(climate.snow_celsius) + f32(step) / 10)
		sand := field_sand_cover(climate, f32(climate.sand_metres) + f32(step) / 10)
		testing.expectf(t, snow <= previous_snow && sand <= previous_sand, "the cover rises at step %d", step)
		partial_snow += snow > 0 && snow < 255 ? 1 : 0
		partial_sand += sand > 0 && sand < 255 ? 1 : 0
		previous_snow, previous_sand = snow, sand
	}
	testing.expect(t, partial_snow > 10 && partial_sand > 10, "the covers fade rather than cut")
}

// The shipped palette's four warm greys, so the tint's index has whole
// entries away from the noise's zero. 2 km in 1 m steps: round this home
// the first kilometre's noise spans only -0.28 to 0.11, one entry.
@(test)
test_the_ground_tint_has_no_seam :: proc(t: ^testing.T) {
	planet := ground_look_test_planet()
	planet.palette = default_planet(shipped_test_planets()).palette
	generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
	direction := planet_home_direction(planet.home)
	forward := tangent_of(direction, {UNIT_VECTOR_ONE, 0, 0})
	right := fixed_cross(forward, direction)
	approached := make([]bool, len(planet.palette), context.temp_allocator)
	previous := field_ground_tint(generation, planet.palette, test_sphere_point(generation, direction, forward, right, 0, 0))
	for metre in i64(1) ..= 2000 {
		tint := field_ground_tint(generation, planet.palette, test_sphere_point(generation, direction, forward, right, metre, 0))
		for channel in 0 ..< 3 {
			testing.expectf(t, abs(int(tint[channel]) - int(previous[channel])) <= 2, "the tint steps from %v to %v at %d m", previous, tint, metre)
		}
		for color, index in planet.palette {
			distance := max(abs(int(tint.r) - color.r), abs(int(tint.g) - color.g), abs(int(tint.b) - color.b))
			approached[index] |= distance <= 2
		}
		previous = tint
	}
	count := 0
	for reached in approached {
		count += reached ? 1 : 0
	}
	testing.expectf(t, count > 1, "the tint approaches %d palette colours", count)
	// One colour is that colour everywhere.
	single := [][3]int{{12, 34, 56}}
	testing.expect_value(t, field_ground_tint(generation, single, direction), [3]u8{12, 34, 56})
}

// Work item 0311: a measured vertex keeps its distance from the
// generated surface (field_surface_offset) in millimetres and the varied
// climate its grass colour took; an unmeasured one keeps no offset.
@(test)
test_the_offset_is_kept_per_vertex :: proc(t: ^testing.T) {
	planet := ground_look_test_planet()
	generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
	grid := ground_look_test_grid(generation, ground_look_test_node(generation, planet.home, 200))
	look := make_field_ground_look(generation, planet)
	for measure_cuts in ([2]bool{true, false}) {
		surface := mesh_field_surface(grid, planet.palette, context.temp_allocator)
		write_field_ground_look(&surface, grid, look, 1000, measure_cuts)
		testing.expect(t, len(surface.vertices) > 0, "the node holds the surface")
		offsets := 0
		for vertex in surface.vertices {
			position := field_vertex_world_position(grid, vertex.position, 1000)
			distance := vector_length(([3]i64)(position))
			on_sphere := project_onto_sphere(position, distance, generation.radius)
			expected := measure_cuts ? field_offset_millimetres(field_surface_offset(generation, on_sphere, distance)) : 0
			testing.expect_value(t, vertex.look.offset_millimetres, expected)
			offsets += vertex.look.offset_millimetres > 0 ? 1 : 0
			climate := planet_climate(generation, on_sphere, distance - generation.sea_radius)
			testing.expectf(t, abs(vertex.look.celsius - f32(climate.temperature_millicelsius) / 1000) <= GROUND_VARIATION_CELSIUS + 1e-3, "the vertex's %v degrees are the climate's %d millidegrees varied", vertex.look.celsius, climate.temperature_millicelsius)
		}
		testing.expect(t, !measure_cuts || offsets > 0, "the measured vertices lie off the surface by their cells' rounding")
	}
}

// The look's cost on the mesh job (0307), single threaded and not a
// benchmark; the suite leaves it out:
// ./build.sh test quick game.test_report_the_ground_look_cost -define:GROUND_LOOK_COST=true
// or in ./build.sh nightly.
GROUND_LOOK_COST :: #config(GROUND_LOOK_COST, false)

when GROUND_LOOK_COST {
	@(test)
	test_report_the_ground_look_cost :: proc(t: ^testing.T) {
		planet := shipped_test_home_at(8000)
		generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
		levels := test_field_game_config().field_view.level_distances_metres
		home := planet_home_direction(planet.home)
		spring := planet_direction_at(degrees_to_angle_units(79), degrees_to_angle_units(151))
		for direction, place in ([2][3]i64{home, spring}) {
			camera := World_Position(fixed_scale(direction, generation.radius + surface_relief(generation, fixed_scale(direction, generation.radius)) + metres_to_position_units(2)))
			nodes := select_field_nodes(make_field_view(camera, planet, 1000, levels), context.temp_allocator)
			testing.expect(t, len(nodes) > 0, "a view selects nodes")
			report_ground_look_cost(generation, planet, nodes, place == 0 ? "the home" : "(79, 151)")
		}
	}

	// Over the view's first 48 nodes holding a surface, each grid
	// generated once: the wall time of generating them, of meshing them
	// without the look, with it and with it measuring the cuts (a grid
	// holding loaded samples), each mesh three times.
	report_ground_look_cost :: proc(generation: Planet_Generation, planet: Planet, nodes: []Field_Node, place: string) {
		look := make_field_ground_look(generation, planet)
		grids := make([dynamic]^Field_Grid, context.temp_allocator)
		generating: time.Duration
		for node in nodes {
			if len(grids) >= 48 {
				break
			}
			grid := new(Field_Grid, context.temp_allocator)
			begin := time.tick_now()
			generate_field_grid(generation, node, grid)
			elapsed := time.tick_since(begin)
			if field_grid_is_uniform(grid) {
				continue
			}
			generating += elapsed
			append(&grids, grid)
		}
		// The meshes' scratch, freed after each, so the grids and the
		// planet in the temp allocator stay.
		scratch: virtual.Arena
		_ = virtual.arena_init_growing(&scratch)
		defer virtual.arena_destroy(&scratch)
		context.temp_allocator = virtual.arena_allocator(&scratch)
		// Per grid the three meshes in turn, five times, the fastest of
		// each kept, so a pause of the machine does not skew one of them.
		durations: [3]time.Duration
		vertices := 0
		for grid in grids {
			fastest := [3]time.Duration{max(time.Duration), max(time.Duration), max(time.Duration)}
			for _ in 0 ..< 5 {
				for pass in 0 ..< 3 {
					begin := time.tick_now()
					data := mesh_field_grid(grid, planet.palette, generation.spacing_millimetres, {flaps = EVERY_FIELD_FACE}, context.temp_allocator, pass == 0 ? {} : look, pass == 2)
					fastest[pass] = min(fastest[pass], time.tick_since(begin))
					vertices += pass == 0 ? len(data.positions) : 0
					free_all(context.temp_allocator)
				}
			}
			durations += fastest
		}
		milliseconds :: proc(duration: time.Duration, count: int) -> f64 {
			return time.duration_milliseconds(duration) / f64(count)
		}
		jobs := len(grids)
		vertices /= 5
		log.infof("ground look cost at %s: %d grids, %d vertices a grid, %.2f ms a grid to generate", place, len(grids), vertices / max(jobs, 1), milliseconds(generating, len(grids)))
		log.infof("ground look cost at %s: a mesh %.2f ms without the look, %.2f ms with it (%.2f times), %.2f ms with it measuring the cuts (%.2f times)", place, milliseconds(durations[0], jobs), milliseconds(durations[1], jobs), f64(durations[1]) / f64(durations[0]), milliseconds(durations[2], jobs), f64(durations[2]) / f64(durations[0]))
		job := f64(generating) / f64(len(grids))
		log.infof("ground look cost at %s: a generated job (grid and mesh) %.2f times without the look", place, (job + f64(durations[1]) / f64(jobs)) / (job + f64(durations[0]) / f64(jobs)))
	}
}
