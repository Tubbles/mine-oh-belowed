package game

import "core:fmt"
import "core:testing"
import "core:time"

// The trees on the sphere (work item 0197): a pure function of the seed
// and the recorded planet, not of the spacing; in groves, none in the
// clearing, below the sea or on a steep slope; the density near its
// expectation.

TREE_TEST_RADIUS_METRES :: 8000

// The shipped home planet at the radius.
tree_test_planet :: proc(radius_metres := TREE_TEST_RADIUS_METRES) -> Planet {
	planet := default_planet(shipped_test_planets())
	planet.radius_metres = radius_metres
	return planet
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
	planet := tree_test_planet()
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

@(test)
test_a_tree_key_regenerates_alone :: proc(t: ^testing.T) {
	planet := tree_test_planet()
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

@(test)
test_no_tree_stands_in_the_home_clearing :: proc(t: ^testing.T) {
	for radius in tree_test_planet().radius_presets_metres {
		planet := tree_test_planet(radius)
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
	planet := tree_test_planet()
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
// ground no steeper than the planet's slope; a higher sea leaves fewer.
@(test)
test_no_tree_stands_below_the_sea_or_on_a_steep_slope :: proc(t: ^testing.T) {
	planet := tree_test_planet()
	generation := tree_test_generation(planet)
	flooded_planet := planet
	flooded_planet.sea_level_metres = 8
	flooded := tree_test_generation(flooded_planet)
	total, flooded_total := 0, 0
	for centre in tree_test_circle_centres(generation) {
		for tree in trees_in_test_circle(&generation, centre) {
			on_sphere := tree_test_on_sphere(generation, tree)
			testing.expect(t, surface_relief(generation, on_sphere) >= generation.sea_radius - generation.radius + metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES))
			testing.expect(t, planet_tree_slope_ok(generation, on_sphere, tree.up))
			total += 1
		}
		for tree in trees_in_test_circle(&flooded, centre) {
			testing.expect(t, surface_relief(flooded, tree_test_on_sphere(flooded, tree)) >= flooded.sea_radius - flooded.radius + metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES))
			flooded_total += 1
		}
	}
	testing.expectf(t, flooded_total < total, "%d trees under a higher sea, %d under the shipped one", flooded_total, total)
}

@(test)
test_trees_stand_in_groves_not_on_a_grid :: proc(t: ^testing.T) {
	planet := tree_test_planet()
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
	bare := tree_test_planet()
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
// region, for the report.
@(test)
test_the_tree_query_cost_is_logged :: proc(t: ^testing.T) {
	planet := tree_test_planet()
	generation := tree_test_generation(planet)
	centre := tree_test_point_from_home(generation, planet, ANGLE_UNITS_PER_QUARTER, 300)
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
	fmt.printfln("tree query: a 10 m box %v, a 32 m region %v", query, region)
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
