package game

import "core:fmt"
import "core:math"
import "core:testing"
import "core:time"
import "generation_seed"

// The trees on the sphere (work items 0197 and 0310): a pure function of
// the seed and the recorded planet, not of the spacing; none in the
// clearing, below the sea or on a steep slope. The groves: in groves, the
// density near its expectation. The forest: its share of the land, its
// interior's density, the gap, the meadow round the home, the species by
// the climate and their sizes.

TREE_TEST_RADIUS_METRES :: 8000

// The shipped home planet at the radius, with its forest.
tree_test_planet :: proc(radius_metres := TREE_TEST_RADIUS_METRES) -> Planet {
	planet := default_planet(shipped_test_planets())
	planet.radius_metres = radius_metres
	return planet
}

// The shipped home without its forest: the groves of 0197 at a spacing of
// 4 m and a density of 80%, as a world recorded before 0310 has them.
grove_test_planet :: proc(radius_metres := TREE_TEST_RADIUS_METRES) -> Planet {
	planet := tree_test_planet(radius_metres)
	planet.trees.forest = {}
	planet.trees.tree_spacing_metres = 4
	planet.trees.density_percent = 80
	return planet
}

// Both placements, the forest's first.
tree_test_planets :: proc() -> [2]Planet {
	return {tree_test_planet(), grove_test_planet()}
}

tree_test_generation :: proc(planet: Planet, seed := DEFAULT_WORLD_SEED, spacing_millimetres := 1000) -> Planet_Generation {
	return make_planet_generation(seed, planet, spacing_millimetres)
}

// The point on the sphere distance metres from the home along the
// bearing.
tree_test_point_from_home :: proc(generation: Planet_Generation, planet: Planet, bearing: i32, distance_metres: i64) -> [3]i64 {
	home := planet_home_direction(planet.home)
	direction := planet_direction_from_home(home, planet_home_tangent(home, bearing), metres_to_position_units(distance_metres), generation.radius)
	return fixed_scale(direction, generation.radius)
}

tree_test_box :: proc(centre: [3]i64, half_metres: i64) -> (minimum, maximum: [3]i64) {
	half := metres_to_position_units(half_metres)
	return centre - half, centre + half
}

// The tree's key's candidate on the sphere, exactly as the generation
// placed it.
tree_test_on_sphere :: proc(generation: Planet_Generation, tree: Planet_Tree) -> [3]i64 {
	on_sphere, _, _ := lattice_candidate(generation.trees.tree_seed, {i64(tree.key.x), i64(tree.key.y), i64(tree.key.z)}, generation.trees.spacing, generation.radius)
	return on_sphere
}

trees_equal :: proc(first, second: []Planet_Tree) -> bool {
	if len(first) != len(second) {
		return false
	}
	for tree, index in first {
		if tree != second[index] {
			return false
		}
	}
	return true
}

@(test)
test_the_same_seed_places_the_same_trees :: proc(t: ^testing.T) {
	for planet in tree_test_planets() {
		generation := tree_test_generation(planet)
		minimum, maximum := tree_test_box(tree_test_point_from_home(generation, planet, 0, 60), 48)
		first := planet_trees_in_box(&generation, minimum, maximum)
		second := planet_trees_in_box(&generation, minimum, maximum)
		testing.expect(t, trees_equal(first[:], second[:]))
		testing.expectf(t, len(first) >= 10, "%d trees in the box", len(first))
		for spacing in TEST_FIELD_SPACINGS {
			at_spacing := tree_test_generation(planet, spacing_millimetres = spacing)
			testing.expectf(t, trees_equal(planet_trees_in_box(&at_spacing, minimum, maximum)[:], first[:]), "the spacing %d mm moves no tree", spacing)
		}
		other := tree_test_generation(planet, seed = DEFAULT_WORLD_SEED + 1)
		testing.expect(t, !trees_equal(planet_trees_in_box(&other, minimum, maximum)[:], first[:]), "another seed grows other trees")
	}
}

@(test)
test_a_tree_key_regenerates_alone :: proc(t: ^testing.T) {
	for planet in tree_test_planets() {
		generation := tree_test_generation(planet)
		minimum, maximum := tree_test_box(tree_test_point_from_home(generation, planet, 0, 60), 48)
		trees := planet_trees_in_box(&generation, minimum, maximum)
		keys := make(map[Tree_Key]struct{}, context.temp_allocator)
		for tree in trees {
			alone, found := planet_tree_at_key(&generation, tree.key)
			testing.expect(t, found)
			testing.expect_value(t, alone, tree)
			keys[tree.key] = {}
		}
		empty_found := false
		first := minimum / generation.trees.spacing
		for x in first.x ..< first.x + 24 {
			key := Tree_Key{i32(x), i32(first.y), i32(first.z)}
			if key in keys {
				continue
			}
			_, found := planet_tree_at_key(&generation, key)
			if !found {
				empty_found = true
				break
			}
		}
		testing.expect(t, empty_found, "a cube without a tree finds none")
	}
}

@(test)
test_no_tree_stands_in_the_home_clearing :: proc(t: ^testing.T) {
	for radius in tree_test_planet().radius_presets_metres {
		for planet in ([2]Planet{tree_test_planet(radius), grove_test_planet(radius)}) {
			generation := tree_test_generation(planet)
			term := generation.trees
			minimum, maximum := tree_test_box(term.home, i64(planet.trees.clearing_metres) + 40)
			trees := planet_trees_in_box(&generation, minimum, maximum)
			testing.expectf(t, len(trees) > 0, "trees round the clearing at %d m", radius)
			for tree in trees {
				offset := tree_test_on_sphere(generation, tree) - term.home
				testing.expect(t, offset.x * offset.x + offset.y * offset.y + offset.z * offset.z > term.clearing * term.clearing)
			}
		}
	}
}

// The circles of the density and the sea tests: centres at four
// latitudes and four longitudes.
tree_test_circle_centres :: proc(generation: Planet_Generation) -> [16][3]i64 {
	centres: [16][3]i64
	latitudes := [4]int{-60, -20, 20, 60}
	longitudes := [4]int{-135, -45, 45, 135}
	for latitude, row in latitudes {
		for longitude, column in longitudes {
			centres[row * 4 + column] = fixed_scale(planet_spring_direction({latitude, longitude}), generation.radius)
		}
	}
	return centres
}

TREE_TEST_CIRCLE_METRES :: 100

// The trees whose candidate lies within the circle's radius of its
// centre on the sphere.
trees_in_test_circle :: proc(generation: ^Planet_Generation, centre: [3]i64) -> [dynamic]Planet_Tree {
	minimum, maximum := tree_test_box(centre, TREE_TEST_CIRCLE_METRES)
	inside := make([dynamic]Planet_Tree, context.temp_allocator)
	reach := metres_to_position_units(TREE_TEST_CIRCLE_METRES)
	for tree in planet_trees_in_box(generation, minimum, maximum) {
		offset := tree_test_on_sphere(generation^, tree) - centre
		if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= reach * reach {
			append(&inside, tree)
		}
	}
	return inside
}

@(test)
test_the_tree_density_stays_within_its_bounds :: proc(t: ^testing.T) {
	planet := grove_test_planet()
	generation := tree_test_generation(planet)
	expected := planet_tree_expected_count(planet.trees, TREE_TEST_CIRCLE_METRES)
	testing.expect_value(t, expected, 113)
	counted, total, largest := 0, 0, 0
	dry := generation.sea_radius - generation.radius + metres_to_position_units(2)
	for centre in tree_test_circle_centres(generation) {
		if surface_relief(generation, centre) < dry {
			continue
		}
		count := len(trees_in_test_circle(&generation, centre))
		counted += 1
		total += count
		largest = max(largest, count)
	}
	testing.expectf(t, counted >= 8, "%d circles above the sea", counted)
	mean := total / max(counted, 1)
	fmt.printfln("tree density: %d circles, mean %d trees (expected %d), largest %d", counted, mean, expected, largest)
	testing.expectf(t, mean * 100 >= expected * 75 && mean * 100 <= expected * 120, "the mean %d against %d expected", mean, expected)
	testing.expectf(t, largest <= 3 * expected, "the largest circle holds %d", largest)
}

// Every tree of the circles stands at least the margin above the sea on
// ground no steeper than the planet's slope (by the placement's own
// probes); a higher sea leaves fewer.
@(test) // slow
test_no_tree_stands_below_the_sea_or_on_a_steep_slope :: proc(t: ^testing.T) {
	for planet in tree_test_planets() {
		generation := tree_test_generation(planet)
		flooded_planet := planet
		flooded_planet.sea_level_metres = 8
		flooded := tree_test_generation(flooded_planet)
		total, flooded_total := 0, 0
		for centre in tree_test_circle_centres(generation) {
			for tree in trees_in_test_circle(&generation, centre) {
				on_sphere := tree_test_on_sphere(generation, tree)
				relief := surface_relief(generation, on_sphere)
				testing.expect(t, relief >= generation.sea_radius - generation.radius + metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES))
				if generation.trees.forest_on {
					testing.expect(t, forest_slope_percent(generation, on_sphere, tree.up, relief) < generation.trees.maximum_slope_percent)
				} else {
					testing.expect(t, planet_tree_slope_ok(generation, on_sphere, tree.up))
				}
				total += 1
			}
			for tree in trees_in_test_circle(&flooded, centre) {
				testing.expect(t, surface_relief(flooded, tree_test_on_sphere(flooded, tree)) >= flooded.sea_radius - flooded.radius + metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES))
				flooded_total += 1
			}
		}
		testing.expectf(t, flooded_total < total, "%d trees under a higher sea, %d under the shipped one", flooded_total, total)
	}
}

@(test)
test_trees_stand_in_groves_not_on_a_grid :: proc(t: ^testing.T) {
	planet := grove_test_planet()
	generation := tree_test_generation(planet)
	minimum, maximum := tree_test_box(tree_test_point_from_home(generation, planet, ANGLE_UNITS_PER_QUARTER, 300), 100)
	trees := planet_trees_in_box(&generation, minimum, maximum)
	offsets: [3]map[i64]struct{}
	for &values in offsets {
		values = make(map[i64]struct{}, context.temp_allocator)
	}
	yaws := make(map[i32]struct{}, context.temp_allocator)
	sub_boxes := make(map[[3]i64]int, context.temp_allocator)
	sub_edge := metres_to_position_units(40)
	for tree in trees {
		on_sphere := tree_test_on_sphere(generation, tree)
		for axis in 0 ..< 3 {
			corner := i64(tree.key[axis]) * generation.trees.spacing
			offsets[axis][(on_sphere[axis] - corner) * 100 / POSITION_UNITS_PER_METRE] = {}
		}
		yaws[tree.yaw] = {}
		sub_boxes[{floor_divide_i64(on_sphere.x, sub_edge), floor_divide_i64(on_sphere.y, sub_edge), floor_divide_i64(on_sphere.z, sub_edge)}] += 1
	}
	for values, axis in offsets {
		testing.expectf(t, len(values) >= 16, "%d offsets on axis %d", len(values), axis)
	}
	testing.expectf(t, len(yaws) >= 16, "%d yaws", len(yaws))
	empty, crowded := false, false
	first, last := [3]i64{floor_divide_i64(minimum.x, sub_edge), floor_divide_i64(minimum.y, sub_edge), floor_divide_i64(minimum.z, sub_edge)}, [3]i64{floor_divide_i64(maximum.x, sub_edge), floor_divide_i64(maximum.y, sub_edge), floor_divide_i64(maximum.z, sub_edge)}
	for x in first.x ..= last.x {
		for y in first.y ..= last.y {
			for z in first.z ..= last.z {
				box := [3]i64{x, y, z}
				if !cube_straddles_sphere(box * sub_edge, box * sub_edge + sub_edge, generation.radius) {
					continue
				}
				count := sub_boxes[box]
				empty ||= count == 0
				crowded ||= count >= 5
			}
		}
	}
	testing.expect(t, empty, "a 40 m box without a tree")
	testing.expect(t, crowded, "a 40 m box with a grove's five trees")
}

@(test)
test_tree_axes_turn_with_the_yaw :: proc(t: ^testing.T) {
	up, _ := normalize_fixed({3 * UNIT_VECTOR_ONE, 5 * UNIT_VECTOR_ONE, -2 * UNIT_VECTOR_ONE})
	tolerance := i64(UNIT_VECTOR_ONE / 1000)
	north := frame_north_tangent(up)
	for yaw in ([3]i32{0, ANGLE_UNITS_PER_QUARTER, 12345}) {
		axes := tree_axes(up, yaw)
		testing.expect_value(t, axes[1], up)
		for first in 0 ..< 3 {
			testing.expect(t, abs(vector_length(axes[first]) - UNIT_VECTOR_ONE) <= tolerance)
			for second in first + 1 ..< 3 {
				testing.expect(t, abs(fixed_dot(axes[first], axes[second])) <= tolerance)
			}
		}
	}
	testing.expect(t, fixed_dot(tree_axes(up, 0)[2], north) >= UNIT_VECTOR_ONE - tolerance, "yaw 0 points north")
	testing.expect(t, fixed_dot(tree_axes(up, ANGLE_UNITS_PER_QUARTER)[2], fixed_cross(north, up)) >= UNIT_VECTOR_ONE - tolerance, "a quarter turn points along north cross up")
}

@(test)
test_the_zero_tree_term_places_nothing :: proc(t: ^testing.T) {
	bare := grove_test_planet()
	bare.trees.grove_share_percent = 0
	built := make_test_planet()
	for planet in ([2]Planet{bare, built}) {
		generation := tree_test_generation(planet)
		testing.expect_value(t, generation.trees, Planet_Tree_Term{})
		minimum, maximum := tree_test_box(tree_test_point_from_home(generation, planet, 0, 60), 48)
		testing.expect_value(t, len(planet_trees_in_box(&generation, minimum, maximum)), 0)
		_, found := planet_tree_at_key(&generation, {1, 2, 3})
		testing.expect(t, !found)
	}
}

// Not a benchmark: the cost of the player's query box and of a draw
// region, for the report, on the groves and in the forest's interior
// (0310).
@(test)
test_the_tree_query_cost_is_logged :: proc(t: ^testing.T) {
	for planet in tree_test_planets() {
		generation := tree_test_generation(planet)
		centre := tree_test_point_from_home(generation, planet, ANGLE_UNITS_PER_QUARTER, 300)
		if generation.trees.forest_on {
			centre = forest_test_interior(generation)
		}
		query_minimum, query_maximum := tree_test_box(centre, 5)
		region_minimum, region_maximum := tree_test_box(centre, 16)
		REPEATS :: 20
		start := time.tick_now()
		for _ in 0 ..< REPEATS {
			planet_trees_in_box(&generation, query_minimum, query_maximum)
		}
		query := time.tick_since(start) / REPEATS
		start = time.tick_now()
		for _ in 0 ..< REPEATS {
			planet_trees_in_box(&generation, region_minimum, region_maximum)
		}
		region := time.tick_since(start) / REPEATS
		fmt.printfln("tree query (%s): a 10 m box %v, a 32 m region %v", generation.trees.forest_on ? "forest interior" : "groves", query, region)
	}
	testing.expect(t, true)
}

// The trees expected in a circle of the radius: groves per square
// metre, times a grove's trees (its density over the integral of the
// falling chance, half its disc), times the circle's area; pi as 355 /
// 113. That counts axis aligned lattices; a lattice cube projected onto
// the tilted sphere keeps about seven eighths of its points in the cube
// (a Monte Carlo over the test's 16 circle normals: 0.85 to 0.91), so
// the two lattices in series keep three quarters.
planet_tree_expected_count :: proc(trees: Planet_Trees, circle_radius_metres: int) -> int {
	grove_radius := i64(trees.grove_radius_metres)
	circle := i64(circle_radius_metres)
	numerator := 3 * i64(trees.grove_share_percent) * i64(trees.density_percent) * 355 * grove_radius * grove_radius * 355 * circle * circle
	grove_area := i64(trees.grove_spacing_metres) * i64(trees.grove_spacing_metres)
	tree_area := i64(trees.tree_spacing_metres) * i64(trees.tree_spacing_metres)
	denominator := 4 * 100 * 100 * 2 * 113 * 113 * grove_area * tree_area
	if denominator == 0 {
		return 0
	}
	return int(numerator / denominator)
}

// The forest (0310).

// The point on the sphere of the radius at the latitude and longitude in
// degrees, moved east and north on the tangent plane there by the metres
// (the prototype's frame, tmp/0310/proto), in position units.
forest_test_point :: proc(radius_metres: int, latitude, longitude: f64, east_metres: f64 = 0, north_metres: f64 = 0) -> [3]i64 {
	la, lo := math.to_radians(latitude), math.to_radians(longitude)
	centre := [3]f64{math.cos(la) * math.cos(lo), math.sin(la), math.cos(la) * math.sin(lo)}
	east := [3]f64{-math.sin(lo), 0, math.cos(lo)}
	north := [3]f64{-math.sin(la) * math.cos(lo), math.cos(la), -math.sin(la) * math.sin(lo)}
	radius := f64(radius_metres)
	point := centre * radius + east * east_metres + north * north_metres
	point *= radius / math.sqrt(point.x * point.x + point.y * point.y + point.z * point.z) * POSITION_UNITS_PER_METRE
	return {i64(math.round(point.x)), i64(math.round(point.y)), i64(math.round(point.z))}
}

// The interior the measurements name: 80.6 N 132 E, 335 m south of the
// home at 8 km.
forest_test_interior :: proc(generation: Planet_Generation) -> [3]i64 {
	return forest_test_point(int(generation.radius / POSITION_UNITS_PER_METRE), 80.6, 132)
}

// The trees whose candidate lies within the radius of the centre on the
// sphere (temp allocator).
forest_trees_within :: proc(generation: ^Planet_Generation, centre: [3]i64, radius_metres: i64) -> [dynamic]Planet_Tree {
	minimum, maximum := tree_test_box(centre, radius_metres + 1)
	inside := make([dynamic]Planet_Tree, context.temp_allocator)
	reach := metres_to_position_units(radius_metres)
	for tree in planet_trees_in_box(generation, minimum, maximum) {
		offset := tree_test_on_sphere(generation^, tree) - centre
		if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= reach * reach {
			append(&inside, tree)
		}
	}
	return inside
}

// The shares of the land (planet_tree_ground) on a 16 m grid over the
// 4 km square round the home at 8 km: interior at least 60% of the full
// density, edge 20 to 60%, open below (0310's measure, 42.1, 19.3 and
// 38.6% on an 8 m grid).
@(test) // slow
test_the_forest_share_of_the_land_holds :: proc(t: ^testing.T) {
	planet := tree_test_planet()
	generation := tree_test_generation(planet)
	full := generation.trees.forest_density
	land, interior, edge := 0, 0, 0
	STEP :: 16.0
	SIDE :: 4000.0
	count := int(SIDE / STEP)
	for row in 0 ..< count {
		for column in 0 ..< count {
			east := (f64(column) + 0.5) * STEP - SIDE / 2
			north := (f64(row) + 0.5) * STEP - SIDE / 2
			point := forest_test_point(planet.radius_metres, f64(planet.home.latitude_degrees), f64(planet.home.longitude_degrees), east, north)
			density, is_land := forest_density_at(generation, point)
			if !is_land {
				continue
			}
			land += 1
			switch {
			case density * 10 >= full * 6:
				interior += 1
			case density * 10 >= full * 2:
				edge += 1
			}
		}
	}
	interior_percent := 100 * f64(interior) / f64(max(land, 1))
	edge_percent := 100 * f64(edge) / f64(max(land, 1))
	open_percent := 100 - interior_percent - edge_percent
	fmt.printfln("forest share of the land: %d points, interior %.1f%%, edge %.1f%%, open %.1f%%", land, interior_percent, edge_percent, open_percent)
	testing.expectf(t, interior_percent >= 35 && interior_percent <= 50, "interior %.1f%%", interior_percent)
	testing.expectf(t, open_percent >= 30 && open_percent <= 48, "open %.1f%%", open_percent)
}

@(test)
test_the_forest_interior_is_dense :: proc(t: ^testing.T) {
	generation := tree_test_generation(tree_test_planet())
	RADIUS :: 30
	trees := forest_trees_within(&generation, forest_test_interior(generation), RADIUS)
	hectare := f64(len(trees)) / (math.PI * RADIUS * RADIUS / 10000)
	fmt.printfln("forest interior: %d trees within %d m, %.0f a hectare", len(trees), RADIUS, hectare)
	testing.expectf(t, hectare >= 1300 && hectare <= 2400, "%.0f trees a hectare", hectare)
}

@(test)
test_no_two_trees_stand_closer_than_the_gap :: proc(t: ^testing.T) {
	generation := tree_test_generation(tree_test_planet())
	minimum, maximum := tree_test_box(forest_test_interior(generation), 32)
	trees := planet_trees_in_box(&generation, minimum, maximum)
	testing.expectf(t, len(trees) > 200, "%d trees in the box", len(trees))
	points := make([][3]i64, len(trees), context.temp_allocator)
	for tree, index in trees {
		points[index] = tree_test_on_sphere(generation, tree)
	}
	gap := millimetres_to_position_units(900)
	nearest := i64(max(i64))
	for first in 0 ..< len(points) {
		for second in first + 1 ..< len(points) {
			offset := points[first] - points[second]
			nearest = min(nearest, offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
		}
	}
	testing.expectf(t, nearest >= gap * gap, "two trees %d mm apart", i64(math.sqrt(f64(nearest))) * MILLIMETRES_PER_METRE / POSITION_UNITS_PER_METRE)
}

@(test)
test_overlapping_boxes_agree_on_their_trees :: proc(t: ^testing.T) {
	generation := tree_test_generation(tree_test_planet())
	centre := forest_test_interior(generation)
	first_minimum, first_maximum := tree_test_box(centre, 16)
	shift := metres_to_position_units(7)
	second_minimum, second_maximum := first_minimum + shift, first_maximum + shift
	first := planet_trees_in_box(&generation, first_minimum, first_maximum)
	second := planet_trees_in_box(&generation, second_minimum, second_maximum)
	in_box :: proc(tree: Planet_Tree, spacing: i64, minimum, maximum: [3]i64) -> bool {
		for axis in 0 ..< 3 {
			if i64(tree.key[axis]) < floor_divide_i64(minimum[axis], spacing) || i64(tree.key[axis]) > floor_divide_i64(maximum[axis], spacing) {
				return false
			}
		}
		return true
	}
	spacing := generation.trees.spacing
	from_first := make(map[Tree_Key]Planet_Tree, context.temp_allocator)
	for tree in first {
		if in_box(tree, spacing, second_minimum, second_maximum) {
			from_first[tree.key] = tree
		}
	}
	shared := 0
	for tree in second {
		if !in_box(tree, spacing, first_minimum, first_maximum) {
			continue
		}
		other, found := from_first[tree.key]
		testing.expectf(t, found && other == tree, "the key %v differs between the boxes", tree.key)
		shared += 1
	}
	testing.expect_value(t, shared, len(from_first))
	testing.expectf(t, shared > 50, "%d trees in the overlap", shared)
	for tree in first {
		alone, found := planet_tree_at_key(&generation, tree.key)
		testing.expect(t, found && alone == tree, "a key regenerates alone")
	}
}

// Each species fells for logs by the hand at most at its hand scale.
forest_test_hand_fells_for_logs :: proc(planet: Planet, tree: Planet_Tree) -> bool {
	species := planet.trees.species[int(tree.species) % len(planet.trees.species)]
	return species.item == "log" && int(tree.scale_percent) <= species.hand_felling_scale_percent
}

@(test) // slow
test_the_meadow_round_the_home_is_open :: proc(t: ^testing.T) {
	for radius in tree_test_planet().radius_presets_metres {
		planet := tree_test_planet(radius)
		generation := tree_test_generation(planet)
		home := generation.trees.home
		within_meadow := len(forest_trees_within(&generation, home, 56))
		around := forest_trees_within(&generation, home, 96)
		hand := 0
		for tree in around {
			if forest_test_hand_fells_for_logs(planet, tree) {
				hand += 1
			}
		}
		fmt.printfln("the meadow at %d m: %d trees within 56 m, %d within 96 m, %d of them the hand fells for logs", radius, within_meadow, len(around), hand)
		testing.expectf(t, within_meadow <= 100, "%d trees within 56 m at %d m", within_meadow, radius)
		testing.expectf(t, len(around) >= 200, "%d trees within 96 m at %d m", len(around), radius)
		testing.expectf(t, hand >= 10, "%d trees the hand fells for logs at %d m", hand, radius)
	}
}

// The shipped species by name (the data's order).
forest_test_species_index :: proc(planet: Planet, id: string) -> int {
	for species, index in planet.trees.species {
		if species.id == id {
			return index
		}
	}
	return -1
}

// The species weighed above 0 at the climate, by id.
forest_test_weighed :: proc(planet: Planet, term: Planet_Tree_Term, celsius, moisture_percent, height_metres: i64) -> map[string]bool {
	weights, _ := species_climate_weights(term, celsius * 1000, moisture_percent * 10, metres_to_position_units(height_metres), NOISE_ONE)
	weighed := make(map[string]bool, context.temp_allocator)
	for species, index in planet.trees.species {
		weighed[species.id] = weights[index] > 0
	}
	return weighed
}

@(test)
test_species_follow_the_climate :: proc(t: ^testing.T) {
	planet := tree_test_planet()
	term := tree_test_generation(planet).trees
	warm := forest_test_weighed(planet, term, 25, 80, 0)
	testing.expect(t, warm["broadleaf"] && !warm["pine"], "25 degrees, moist, at the sea: broadleaf, no pine")
	cold := forest_test_weighed(planet, term, -5, 50, 0)
	for id, weighed in cold {
		testing.expectf(t, weighed == (id == "pine" || id == "snag"), "-5 degrees: %s weighed %v", id, weighed)
	}
	dry := forest_test_weighed(planet, term, 10, 5, 0)
	for id, weighed in dry {
		testing.expectf(t, weighed == (id == "snag"), "5%% moisture: %s weighed %v", id, weighed)
	}
	high := forest_test_weighed(planet, term, 10, 80, 100)
	testing.expect(t, !high["broadleaf"], "100 m over the sea: no broadleaf")
	testing.expect(t, high["pine"], "100 m over the sea: pine")
}

// The species' shares over the tiles round the home within 500 m: every
// species stands there (at least 0.2%, the snag measures 0.53%), pine and
// broadleaf make at least 60%.
@(test) // slow
test_the_shipped_forest_mixes_species :: proc(t: ^testing.T) {
	planet := tree_test_planet()
	generation := tree_test_generation(planet)
	eyes := [1]World_Position{World_Position(generation.trees.home)}
	edge := field_tree_tile_edge(&generation)
	counts: [MAXIMUM_TREE_SPECIES]int
	total := 0
	for tile in field_tree_tiles_around(&generation, eyes[:], 500) {
		minimum, maximum := field_tree_tile_box(tile, edge)
		for tree in planet_trees_in_box(&generation, minimum, maximum) {
			counts[tree.species] += 1
			total += 1
		}
	}
	pine, broadleaf := forest_test_species_index(planet, "pine"), forest_test_species_index(planet, "broadleaf")
	for species, index in planet.trees.species {
		share := 100 * f64(counts[index]) / f64(max(total, 1))
		fmt.printfln("species %s: %d trees, %.1f%%", species.id, counts[index], share)
		testing.expectf(t, share >= 0.2, "%s %.2f%%", species.id, share)
	}
	testing.expectf(t, (counts[pine] + counts[broadleaf]) * 100 >= total * 60, "pine and broadleaf %d of %d", counts[pine] + counts[broadleaf], total)
}

@(test)
test_the_forest_scale_is_triangular :: proc(t: ^testing.T) {
	least, most := 40, 160
	sum := 0
	in_middle := 0
	for index in 0 ..< 10000 {
		scale := int(forest_scale_percent(generation_seed.hash_u64(u64(index)), least, most))
		testing.expect(t, scale >= least && scale <= most)
		sum += scale
		if scale >= least + (most - least) / 4 && scale <= most - (most - least) / 4 {
			in_middle += 1
		}
	}
	mean := f64(sum) / 10000
	middle := f64(least + most) / 2
	testing.expectf(t, abs(mean - middle) <= middle * 0.02, "mean %.2f against %.1f", mean, middle)
	// A triangle holds three quarters of its draws in the middle half.
	testing.expectf(t, in_middle >= 7000 && in_middle <= 8000, "%d in the middle half", in_middle)
}

@(test)
test_tree_sizes_span_saplings_to_giants :: proc(t: ^testing.T) {
	planet := tree_test_planet()
	generation := tree_test_generation(planet)
	minimum, maximum := tree_test_box(forest_test_interior(generation), 32)
	trees := planet_trees_in_box(&generation, minimum, maximum)
	smallest, largest: [MAXIMUM_TREE_SPECIES]int
	counts: [MAXIMUM_TREE_SPECIES]int
	for &value in smallest {
		value = 1000
	}
	for tree in trees {
		smallest[tree.species] = min(smallest[tree.species], int(tree.scale_percent))
		largest[tree.species] = max(largest[tree.species], int(tree.scale_percent))
		counts[tree.species] += 1
	}
	checked := 0
	for species, index in planet.trees.species {
		if counts[index] < 20 {
			continue
		}
		least, most := species.scale_percent[0], species.scale_percent[1]
		third := (most - least) / 3
		testing.expectf(t, smallest[index] < least + third, "%s: the smallest of %d at %d%%", species.id, counts[index], smallest[index])
		testing.expectf(t, largest[index] > most - third, "%s: the largest of %d at %d%%", species.id, counts[index], largest[index])
		checked += 1
	}
	testing.expectf(t, checked >= 2, "%d species with 20 trees in the box", checked)
}

@(test)
test_the_forest_reads_the_same_ground_rules :: proc(t: ^testing.T) {
	generation := tree_test_generation(tree_test_planet())
	sea := generation.sea_radius - generation.radius
	found := false
	for centre in tree_test_circle_centres(generation) {
		if surface_relief(generation, centre) >= sea - metres_to_position_units(4) {
			continue
		}
		found = true
		_, ground := planet_tree_ground(generation, centre)
		testing.expect(t, !ground, "no ground under the sea")
		density, land := forest_density_at(generation, centre)
		testing.expect(t, !land && density == 0, "no forest under the sea")
		minimum, maximum := tree_test_box(centre, 2)
		for tree in planet_trees_in_box(&generation, minimum, maximum) {
			testing.expect(t, surface_relief(generation, tree_test_on_sphere(generation, tree)) >= sea + metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES), "a tree stands above the sea")
		}
		cell := [3]i64{floor_divide_i64(centre.x, generation.trees.spacing), floor_divide_i64(centre.y, generation.trees.spacing), floor_divide_i64(centre.z, generation.trees.spacing)}
		if on_sphere, hash, ok := lattice_candidate(generation.trees.tree_seed, cell, generation.trees.spacing, generation.radius); ok && surface_relief(generation, on_sphere) < sea {
			_, kept := forest_tree_from_candidate(generation, cell, on_sphere, hash)
			testing.expect(t, !kept, "the forest path refuses the sea")
		}
	}
	testing.expect(t, found, "a circle centre lies under the sea")
}

@(test)
test_a_world_without_a_forest_keeps_its_groves :: proc(t: ^testing.T) {
	data := tree_test_planet()
	groves := grove_test_planet()
	record := planet_generation_record(groves)
	testing.expect_value(t, record.trees.forest, Planet_Forest{})
	recorded := make_recorded_planet(data, record, context.temp_allocator)
	testing.expect(t, !planet_forest_on(recorded.trees.forest), "the record's zero forest is off")
	recorded_generation := tree_test_generation(recorded)
	grove_generation := tree_test_generation(groves)
	forest_generation := tree_test_generation(data)
	minimum, maximum := tree_test_box(tree_test_point_from_home(grove_generation, groves, 0, 60), 48)
	kept := planet_trees_in_box(&recorded_generation, minimum, maximum)
	testing.expect(t, len(kept) > 0)
	testing.expect(t, trees_equal(kept[:], planet_trees_in_box(&grove_generation, minimum, maximum)[:]), "the recorded world's trees are the groves'")
	testing.expect(t, !trees_equal(kept[:], planet_trees_in_box(&forest_generation, minimum, maximum)[:]), "the data's forest does not reach it")
}

// Work item 0337: the cube windows and the tile's sea boxes keep every
// tree of 0310's loop over every cube.

// The shipped home at a preset with the home and the waters a new world
// of the seed takes (waters_test_planet and its features); the caller
// frees the features (destroy_planet_water_features).
tree_test_watered_planet :: proc(radius_metres: int, seed := DEFAULT_WORLD_SEED) -> Planet {
	planet := waters_test_planet(radius_metres, seed)
	planet.water_features = make_planet_water_features(seed, planet)
	return planet
}

// From the home on 32 bearings in steps of 16 m to 1024 m, bearing by
// bearing, the first point on the sphere whose relief lies more than 2 m
// under the trees' sea floor: at 4 km the first point under it lies on a
// shore whose tiles' boxes all reach over it.
tree_test_coast :: proc(generation: Planet_Generation, planet: Planet) -> (point: [3]i64, found: bool) {
	for bearing in 0 ..< 32 {
		for distance: i64 = 16; distance <= 1024; distance += 16 {
			point = tree_test_point_from_home(generation, planet, i32(bearing * ANGLE_UNITS_PER_TURN / 32), distance)
			if surface_relief(generation, point) < planet_tree_sea_floor(generation) - metres_to_position_units(2) {
				return point, true
			}
		}
	}
	return {}, false
}

// 0310's forest_tree_from_candidate as it stood before 0337, with 0327's
// ground: the oracle the new rules are held to.
forest_tree_reference :: proc(generation: Planet_Generation, cell, on_sphere: [3]i64, hash: u64) -> (tree: Planet_Tree, ok: bool) {
	term := generation.trees
	if planet_tree_in_clearing(term, on_sphere) {
		return {}, false
	}
	draw := i64(generation_seed.hash_combine(hash, 1) % NOISE_ONE)
	moisture := planet_moisture(generation, on_sphere)
	cover := forest_cover(term, on_sphere, moisture) * forest_meadow_share(term, on_sphere) / NOISE_ONE
	upper := max(cover, term.scatter) * term.forest_density / NOISE_ONE
	if draw >= upper {
		return {}, false
	}
	if !forest_gap_keeps(term, generation.radius, cell, on_sphere, hash) {
		return {}, false
	}
	relief := planet_tree_ground(generation, on_sphere) or_return
	height := relief - (generation.sea_radius - generation.radius)
	weights, total := species_climate_weights(term, planet_temperature(generation, on_sphere, height), moisture, height, cover)
	exact := upper * min(total / 100, NOISE_ONE) / NOISE_ONE
	if draw >= exact {
		return {}, false
	}
	up, _ := normalize_fixed(on_sphere)
	if draw >= exact * forest_slope_share(term, forest_slope_percent(generation, on_sphere, up, relief)) / NOISE_ONE {
		return {}, false
	}
	stand_total := forest_stand_weights(term, on_sphere, &weights)
	species := forest_species_pick(weights, i64(generation_seed.hash_combine(hash, 4) % u64(max(stand_total, 1))))
	scale := term.species[species].scale_percent
	return planet_tree_at(cell, on_sphere, up, relief, hash, forest_scale_percent(generation_seed.hash_combine(hash, 3), scale[0], scale[1]), species), true
}

// planet_trees_in_box as it stood before 0337 (with 0326's lake list):
// every cube x, then y, then z, the forest's oracle or the groves' rule.
trees_by_every_cube :: proc(generation: ^Planet_Generation, minimum, maximum: [3]i64) -> [dynamic]Planet_Tree {
	trees := make([dynamic]Planet_Tree, context.temp_allocator)
	term := generation.trees
	groves: [][3]i64
	if !term.forest_on {
		groves = planet_groves_near(term, generation.radius, minimum, maximum)
	}
	first, last: [3]i64
	for axis in 0 ..< 3 {
		first[axis] = floor_divide_i64(minimum[axis], term.spacing)
		last[axis] = floor_divide_i64(maximum[axis], term.spacing)
	}
	cubes := generation^
	if generation.water_tiles != nil {
		cubes.lakes = generation_lakes_near_sphere_box(generation^, first * term.spacing, (last + 1) * term.spacing)
		cubes.water_tiles = nil
	}
	for x in first.x ..= last.x {
		for y in first.y ..= last.y {
			for z in first.z ..= last.z {
				cell := [3]i64{x, y, z}
				if !cube_straddles_sphere(cell * term.spacing, cell * term.spacing + term.spacing, cubes.radius) {
					continue
				}
				on_sphere, hash, ok := lattice_candidate(term.tree_seed, cell, term.spacing, cubes.radius)
				if !ok {
					continue
				}
				tree: Planet_Tree
				kept := false
				if term.forest_on {
					tree, kept = forest_tree_reference(cubes, cell, on_sphere, hash)
				} else if strength := grove_strength(groves, term.grove_radius, on_sphere); strength > 0 {
					tree, kept = planet_tree_from_candidate(cubes, cell, on_sphere, hash, strength)
				}
				if kept {
					append(&trees, tree)
				}
			}
		}
	}
	return trees
}

// The 26 directions of a cube's faces, edges and corners and 8 hashed
// ones.
tree_test_window_directions :: proc() -> [34][3]i64 {
	directions: [34][3]i64
	count := 0
	for x in i64(-1) ..= 1 {
		for y in i64(-1) ..= 1 {
			for z in i64(-1) ..= 1 {
				if x != 0 || y != 0 || z != 0 {
					directions[count] = {x, y, z}
					count += 1
				}
			}
		}
	}
	for index in 0 ..< 8 {
		hash := generation_seed.hash_combine(0x0337, u64(index))
		directions[count] = {i64(hash & 0xFFFF) - 0x8000, i64(hash >> 16 & 0xFFFF) - 0x8000, i64(hash >> 32 & 0xFFFF) - 0x8000}
		count += 1
	}
	return directions
}

// What one column of a tile breaks of the windows' rules: a straddling
// cube outside them, windows out of order, overlapping or out of the
// tile, or longer than the straddling cubes and 8.
tree_test_column_faults :: proc(x, y, first_z, last_z, spacing, radius: i64) -> int {
	windows, count := tree_cube_z_windows(x, y, first_z, last_z, spacing, radius)
	faults, length := 0, i64(0)
	for window, index in windows[:count] {
		if window[0] > window[1] || window[0] < first_z || window[1] > last_z || (index > 0 && window[0] <= windows[index - 1][1]) {
			faults += 1
		}
		length += window[1] - window[0] + 1
	}
	straddling: i64 = 0
	for z in first_z ..= last_z {
		cell := [3]i64{x, y, z}
		if !cube_straddles_sphere(cell * spacing, cell * spacing + spacing, radius) {
			continue
		}
		straddling += 1
		inside := false
		for window in windows[:count] {
			inside ||= window[0] <= z && z <= window[1]
		}
		faults += inside ? 0 : 1
	}
	return faults + (length > straddling + 8 ? 1 : 0)
}

@(test) // slow
test_the_cube_windows_hold_every_straddling_cube :: proc(t: ^testing.T) {
	for radius_metres in ([4]i64{1000, 4000, 8000, 16000}) {
		radius := metres_to_position_units(radius_metres)
		for spacing_metres in ([2]i64{2, 4}) {
			spacing := metres_to_position_units(spacing_metres)
			cells := field_tree_tile_cells(spacing)
			for direction in tree_test_window_directions() {
				unit, _ := normalize_fixed(direction)
				point := fixed_scale(unit, radius)
				first: [3]i64
				for axis in 0 ..< 3 {
					first[axis] = floor_divide_i64(point[axis], cells * spacing) * cells
				}
				faults := 0
				for x in first.x ..< first.x + cells {
					for y in first.y ..< first.y + cells {
						faults += tree_test_column_faults(x, y, first.z, first.z + cells - 1, spacing, radius)
					}
				}
				testing.expectf(t, faults == 0, "radius %d m, spacing %d m, direction %v: %d faults", radius_metres, spacing_metres, direction, faults)
			}
		}
	}
}

// The tiles within 64 m of the point: per tile planet_trees_in_box with
// the tile's sea boxes, without them and trees_by_every_cube agree.
// Returns the trees and whether a sea box was marked under the sea.
tree_test_match_tiles :: proc(t: ^testing.T, generation: ^Planet_Generation, point: [3]i64, place: string) -> (trees: int, sea_marked: bool) {
	cells := field_tree_tile_cells(generation.trees.spacing)
	tiles := field_tree_tiles_around(generation, []World_Position{World_Position(point)}, 64)
	testing.expectf(t, len(tiles) > 0, "%s: tiles within 64 m", place)
	for tile in tiles {
		minimum, maximum := field_tree_tile_box(tile, cells * generation.trees.spacing)
		sea := make_tree_sea_boxes(generation.trees, minimum, maximum)
		windowed := planet_trees_in_box(generation, minimum, maximum, sea = &sea)
		plain := planet_trees_in_box(generation, minimum, maximum)
		every := trees_by_every_cube(generation, minimum, maximum)
		testing.expectf(t, trees_equal(windowed[:], every[:]), "%s, tile %v: %d trees with the sea boxes, %d by every cube", place, tile, len(windowed), len(every))
		testing.expectf(t, trees_equal(plain[:], every[:]), "%s, tile %v: %d trees without the sea boxes, %d by every cube", place, tile, len(plain), len(every))
		trees += len(every)
		for box in sea.boxes {
			sea_marked ||= box == .Sea
		}
	}
	return
}

@(test) // slow
test_the_tile_trees_match_every_cube :: proc(t: ^testing.T) {
	for radius in ([3]int{4000, 8000, 16000}) {
		planet := tree_test_watered_planet(radius)
		defer destroy_planet_water_features(&planet.water_features)
		generation := tree_test_generation(planet)
		home := fixed_scale(planet_home_direction(planet.home), generation.radius)
		trees, _ := tree_test_match_tiles(t, &generation, home, fmt.tprintf("%d m home", radius))
		testing.expectf(t, trees > 0, "%d m home: trees in its tiles", radius)
		coast, found := tree_test_coast(generation, planet)
		testing.expectf(t, found, "%d m: a coast within 1024 m of the home", radius)
		if !found {
			continue
		}
		coast_trees, sea_marked := tree_test_match_tiles(t, &generation, coast, fmt.tprintf("%d m coast", radius))
		testing.expectf(t, coast_trees > 0 && sea_marked, "%d m coast: %d trees and a sea box under the sea (%v)", radius, coast_trees, sea_marked)
	}
	other := tree_test_watered_planet(8000, DEFAULT_WORLD_SEED + 1)
	defer destroy_planet_water_features(&other.water_features)
	other_generation := tree_test_generation(other, DEFAULT_WORLD_SEED + 1)
	other_trees, _ := tree_test_match_tiles(t, &other_generation, fixed_scale(planet_home_direction(other.home), other_generation.radius), "8000 m home of the next seed")
	testing.expect(t, other_trees > 0, "the next seed's home tiles hold trees")
	groves := grove_test_planet()
	grove_generation := tree_test_generation(groves)
	grove_trees, _ := tree_test_match_tiles(t, &grove_generation, fixed_scale(planet_home_direction(groves.home), grove_generation.radius), "groves' home")
	testing.expect(t, grove_trees > 0, "the groves' home tiles hold trees")
}
