package game

import "core:fmt"
import "core:log"
import "core:math"
import "core:slice"
import "core:strings"
import "core:testing"
import "core:thread"

// Work item 0326: the waters over the whole planet in tiles of the cube's
// six gnomonic grids.

// The shipped home at a preset with the home a new world of the seed
// takes, its waters in tiles.
water_tiles_test_planet :: proc(radius_metres: int, seed := DEFAULT_WORLD_SEED) -> Planet {
	planet := shipped_test_home_at(radius_metres)
	planet.home = new_world_home(seed, planet)
	return planet
}

// The tech demo's start at 4 km with the default seed, a spring of the
// home's tiles (test_the_tech_demo_start_follows_the_longest_fall).
TECH_DEMO_TEST_START_4000 :: [2]f64{78.80, 46.64}

// Whether the direction is a spring of the home's 3 by 3 tiles' finals in
// the planet's cache; their counts logged.
water_tiles_test_home_spring :: proc(planet: Planet, direction: [3]i64) -> bool {
	keys := water_home_tile_keys(planet.water_tiles)
	lakes, springs := take_water_tile_finals(planet.water_tiles, keys[:])
	log.infof("0326: at %d m the home's 3 by 3 tiles hold %d lakes and %d springs", planet.radius_metres, len(lakes), len(springs))
	for spring in springs {
		if spring.direction == direction {
			return true
		}
	}
	return false
}

// Field by field and mask by mask, in order.
water_tiles_test_lakes_equal :: proc(first, second: []Planet_Lake) -> bool {
	if len(first) != len(second) {
		return false
	}
	for lake, index in first {
		other := second[index]
		same := lake.centre == other.centre && lake.east == other.east && lake.north == other.north && lake.origin == other.origin && lake.bound_centre == other.bound_centre && lake.level == other.level && lake.floor == other.floor && lake.bound_radius == other.bound_radius && lake.half == other.half && lake.cells == other.cells && lake.cell == other.cell
		if !same || !slice.equal(lake.mask, other.mask) {
			return false
		}
	}
	return true
}

// A tile's final as a reader copies it.
Water_Tiles_Test_Final :: struct {
	lakes:   []Planet_Lake,
	springs: []Planet_Water_Spring,
}

// Each key's final taken alone, in the keys' order.
water_tiles_test_finals :: proc(cache: ^Water_Tile_Cache, keys: []Water_Tile_Key) -> []Water_Tiles_Test_Final {
	finals := make([]Water_Tiles_Test_Final, len(keys), context.temp_allocator)
	for key, index in keys {
		finals[index].lakes, finals[index].springs = take_water_tile_finals(cache, []Water_Tile_Key{key})
	}
	return finals
}

water_tiles_test_finals_equal :: proc(first, second: []Water_Tiles_Test_Final) -> bool {
	if len(first) != len(second) {
		return false
	}
	for final, index in first {
		if !water_tiles_test_lakes_equal(final.lakes, second[index].lakes) || !slice.equal(final.springs, second[index].springs) {
			return false
		}
	}
	return true
}

// The tiles holding a state Found.
water_tiles_test_found_count :: proc(cache: ^Water_Tile_Cache) -> int {
	count := 0
	for _, tile in cache.tiles {
		if tile.analysis == .Found || tile.final == .Found {
			count += 1
		}
	}
	return count
}

@(test)
test_water_faces_own_every_cell_once :: proc(t: ^testing.T) {
	for face in i32(0) ..< WATER_FACE_COUNT {
		axis: [3]i64
		axis[face / 2] = face % 2 == 0 ? UNIT_VECTOR_ONE : -UNIT_VECTOR_ONE
		testing.expect_value(t, water_face_of(axis), face)
	}
	testing.expect_value(t, water_face_of({UNIT_VECTOR_ONE, UNIT_VECTOR_ONE, 0}), 0)
	testing.expect_value(t, water_face_of({0, -UNIT_VECTOR_ONE, -UNIT_VECTOR_ONE}), 3)
	cache := make_water_tile_cache(DEFAULT_WORLD_SEED, water_tiles_test_planet(8000))
	defer destroy_water_tile_cache(cache)
	testing.expect_value(t, cache.face_cells, 500)
	plane := water_face_plane(cache, 0)
	testing.expect(t, water_face_of(waters_plane_direction(plane, 500, 0)) == 0, "the face's edge cell is on it")
	testing.expect(t, water_face_of(waters_plane_direction(plane, 501, 0)) != 0, "the cell past the edge is not")
	for face in i32(0) ..< WATER_FACE_COUNT {
		for cell in ([4][2]i64{{501, 0}, {-501, 0}, {0, 501}, {0, -501}}) {
			owner := water_face_of(waters_plane_direction(water_face_plane(cache, face), cell[0], cell[1]))
			testing.expectf(t, owner / 2 != face / 2, "face %d's cell %v belongs to face %d, not a neighbour", face, cell, owner)
		}
	}
}

// The directions the reach test asks round: the home, three axes, three
// cube corners, six edge midpoints and three from a seeded hash.
water_tiles_test_directions :: proc(home: [3]i64) -> [16][3]i64 {
	one :: UNIT_VECTOR_ONE
	raw := [16][3]i64{home, {one, 0, 0}, {0, one, 0}, {0, 0, -one}, {one, one, one}, {one, -one, one}, {-one, one, -one}, {one, one, 0}, {one, 0, -one}, {0, one, one}, {-one, 0, one}, {0, -one, one}, {-one, -one, 0}, {}, {}, {}}
	for index in 13 ..< 16 {
		raw[index] = test_bound_direction(3260 + index)
	}
	for &direction in raw {
		direction, _ = normalize_fixed(direction)
	}
	return raw
}

// Every cell of a face's tiles (past its edge too) within reach of the
// direction has its tile among water_tiles_near's keys: per face in front
// of the whole disc, the cells of the bounding box of the disc's rim at 64
// headings, projected, and 3 cells more. Returns the cells checked and
// those missing.
water_tiles_test_reach_misses :: proc(cache: ^Water_Tile_Cache, direction: [3]i64, reach: i64) -> (checked, missing: int) {
	keys := make(map[Water_Tile_Key]struct{}, context.temp_allocator)
	water_tiles_near(cache, direction, reach, &keys)
	point := fixed_scale(direction, cache.radius)
	east, north := planet_tangents(direction)
	angle := 2 * math.asin(f64(reach) / (2 * f64(cache.radius)))
	unit := [3]f64{f64(direction.x), f64(direction.y), f64(direction.z)} / UNIT_VECTOR_ONE
	across := [3]f64{f64(east.x), f64(east.y), f64(east.z)} / UNIT_VECTOR_ONE
	up := [3]f64{f64(north.x), f64(north.y), f64(north.z)} / UNIT_VECTOR_ONE
	faces: for face in i32(0) ..< WATER_FACE_COUNT {
		plane := water_face_plane(cache, face)
		low := [2]i64{max(i64), max(i64)}
		high := [2]i64{min(i64), min(i64)}
		for heading in 0 ..< 64 {
			turn := f64(heading) * math.TAU / 64
			rim := unit * math.cos(angle) + (across * math.cos(turn) + up * math.sin(turn)) * math.sin(angle)
			rim_point := [3]i64{i64(rim.x * f64(cache.radius)), i64(rim.y * f64(cache.radius)), i64(rim.z * f64(cache.radius))}
			rim_east, rim_north, ok := waters_plane_coordinates(plane, rim_point)
			if !ok {
				continue faces
			}
			low = {min(low[0], rim_east), min(low[1], rim_north)}
			high = {max(high[0], rim_east), max(high[1], rim_north)}
		}
		first_cell := floor_divide_i64(-cache.face_cells, cache.tile_cells) * cache.tile_cells
		last_cell := (floor_divide_i64(cache.face_cells, cache.tile_cells) + 1) * cache.tile_cells - 1
		for row in max(low[1] / cache.step - 3, first_cell) ..= min(high[1] / cache.step + 3, last_cell) {
			for column in max(low[0] / cache.step - 3, first_cell) ..= min(high[0] / cache.step + 3, last_cell) {
				cell := waters_plane_direction(plane, column, row)
				if squared_chord(fixed_scale(cell, cache.radius), point) > reach * reach {
					continue
				}
				checked += 1
				if (Water_Tile_Key{face, i32(floor_divide_i64(column, cache.tile_cells)), i32(floor_divide_i64(row, cache.tile_cells))}) not_in keys {
					missing += 1
				}
			}
		}
	}
	return
}

// At 4 km, the largest reach against the radius.
@(test)
test_water_tiles_near_holds_every_cell_in_reach :: proc(t: ^testing.T) {
	planet := water_tiles_test_planet(4000)
	cache := make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(cache)
	reach := metres_to_position_units(i64(water_query_reach_metres(planet.waters)))
	for direction, index in water_tiles_test_directions(cache.home) {
		checked, missing := water_tiles_test_reach_misses(cache, direction, reach)
		testing.expectf(t, checked > 0 && missing == 0, "direction %d: %d of %d cells in reach have no tile", index, missing, checked)
		free_all(context.temp_allocator)
	}
}

// The thread's cache and its order of the keys.
Water_Tiles_Test_Asker :: struct {
	cache: ^Water_Tile_Cache,
	keys:  []Water_Tile_Key,
	order: int,
}

// The keys one by one from the asker's own start, forward for an even
// order and backward for an odd one.
water_tiles_test_ask :: proc(asker: ^Water_Tiles_Test_Asker) {
	count := len(asker.keys)
	start := asker.order / 2 * count / 4
	for step in 0 ..< count {
		index := (start + (asker.order % 2 == 0 ? step : count - 1 - step)) % count
		_, _ = take_water_tile_finals(asker.cache, []Water_Tile_Key{asker.keys[index]})
		free_all(context.temp_allocator)
	}
}

// The item's Verify: the finals of the 3 by 3 round the home's tile at
// 8 km, asked row by row, in reverse, first through the lakes near nine
// points and by four threads each in its own order, are equal lake by lake
// and spring by spring. An eviction changes nothing: a cache keeping 4
// tiles finds the home's final, has it and the analyses it read evicted
// by four other tiles' analyses, and finds it again alike.
@(test) // slow
test_water_tiles_are_found_alike_in_any_order :: proc(t: ^testing.T) {
	planet := water_tiles_test_planet(8000)
	rows := make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(rows)
	keys := water_home_tile_keys(rows)
	testing.expect_value(t, len(keys), 9)
	for row in 0 ..< 3 {
		take_water_tile_finals(rows, keys[3 * row:][:3])
	}
	expected := water_tiles_test_finals(rows, keys[:])

	reverse := make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(reverse)
	reversed := slice.clone(keys[:], context.temp_allocator)
	slice.reverse(reversed)
	for key in reversed {
		take_water_tile_finals(reverse, []Water_Tile_Key{key})
	}
	testing.expect(t, water_tiles_test_finals_equal(water_tiles_test_finals(reverse, keys[:]), expected), "asked in reverse")

	near := make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(near)
	plane := water_face_plane(near, keys[0].face)
	for key in keys {
		middle := near.tile_cells / 2
		direction := waters_plane_direction(plane, i64(key.column) * near.tile_cells + middle, i64(key.row) * near.tile_cells + middle)
		water_tile_lakes_near(near, direction, near.lake_reach)
	}
	testing.expect(t, water_tiles_test_finals_equal(water_tiles_test_finals(near, keys[:]), expected), "asked first through the lakes near nine points")

	threaded := make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(threaded)
	askers: [4]Water_Tiles_Test_Asker
	threads: [4]^thread.Thread
	for &asker, index in askers {
		asker = {threaded, keys[:], index}
		threads[index] = thread.create_and_start_with_poly_data(&asker, water_tiles_test_ask)
	}
	for worker in threads {
		thread.join(worker)
		thread.destroy(worker)
	}
	testing.expect(t, water_tiles_test_finals_equal(water_tiles_test_finals(threaded, keys[:]), expected), "asked by four threads")

	small := make_water_tile_cache(DEFAULT_WORLD_SEED, planet, maximum_tiles = 4)
	defer destroy_water_tile_cache(small)
	home := keys[4]
	first := water_tiles_test_finals(small, []Water_Tile_Key{home})
	testing.expect(t, water_tiles_test_found_count(small) <= 4, "the small cache keeps to its bound")
	others := [4]Water_Tile_Key{{home.face, home.column + 3, home.row}, {home.face, home.column - 3, home.row}, {home.face, home.column, home.row + 3}, {home.face, home.column, home.row - 3}}
	take_water_tile_analyses(small, others[:])
	_, still := small.tiles[home]
	testing.expect(t, !still, "the home's tile was evicted")
	second := water_tiles_test_finals(small, []Water_Tile_Key{home})
	testing.expect(t, water_tiles_test_finals_equal(first, expected[4:5]) && water_tiles_test_finals_equal(second, expected[4:5]), "found again alike after an eviction")
	lakes, springs := 0, 0
	for final in expected {
		lakes += len(final.lakes)
		springs += len(final.springs)
	}
	log.infof("0326: the home's 3 by 3 tiles at 8 km hold %d lakes and %d springs", lakes, springs)
}

// Whether a kept lake near the lake holds its refined pit or is held at
// its own; another kept lake than itself when apart.
water_tiles_test_lake_covered :: proc(cache: ^Water_Tile_Cache, lake: Planet_Lake, apart: bool) -> bool {
	for other in water_tile_lakes_near(cache, lake.centre, 2 * cache.lake_reach) {
		if apart && other.cell == lake.cell {
			continue
		}
		if planet_lake_holds(other, lake.origin, cache.radius) || planet_lake_holds(lake, other.origin, cache.radius) {
			return true
		}
	}
	return false
}

// The heads the final keeps (dry, and no dry head near it before it within
// the spacing) and those of them with no kept spring within the spacing,
// from the analyses and the finals of the tiles round the heads.
water_tiles_test_heads_lost :: proc(cache: ^Water_Tile_Cache, heads: []Water_Spring_Candidate) -> (kept, lost: int) {
	spacing := metres_to_position_units(i64(cache.planet.waters.spring_spacing_metres))
	near := make(map[Water_Tile_Key]struct{}, context.temp_allocator)
	for head in heads {
		water_tiles_near(cache, head.spring.direction, spacing + cache.lake_reach, &near)
	}
	keys := water_tile_keys_sorted(near)
	near_lakes, near_candidates := take_water_tile_analyses(cache, keys)
	_, near_springs := take_water_tile_finals(cache, keys)
	candidates: for head in heads {
		point := fixed_scale(head.spring.direction, cache.radius)
		if !water_head_is_dry(head, near_lakes, cache.radius) {
			continue
		}
		for other in near_candidates {
			if other.cell != head.cell && water_candidate_before(other, head) && squared_chord(point, fixed_scale(other.spring.direction, cache.radius)) < spacing * spacing && water_head_is_dry(other, near_lakes, cache.radius) {
				continue candidates
			}
		}
		kept += 1
		covered := false
		for spring in near_springs {
			covered ||= squared_chord(point, fixed_scale(spring.direction, cache.radius)) < spacing * spacing
		}
		if !covered {
			lost += 1
			log.infof("0326: the head of %v has no kept spring within the spacing", head.cell)
		}
	}
	return
}

// Work item 0326: the seams at 8 km. A basin or a valley head over a seam
// is found from each face whose tiles hold its first cell, past the face's
// edge too, and the final keeps one: over the tiles round two lakes and
// those of two springs lost while a face kept only the cells whose
// direction is its own (each face's first cell of them lay on the other's
// ground) and the +x face's whole edge at column 7, every lake of the
// analyses, those from cells past the edge among them, has a kept lake
// over it, no two kept lakes hold each other's pit, and every dry head
// with no dry head before it within the spacing has a kept spring within
// the spacing.
@(test) // slow
test_water_tiles_keep_the_waters_across_the_seams :: proc(t: ^testing.T) {
	planet := water_tiles_test_planet(8000)
	cache := make_water_tile_cache(DEFAULT_WORLD_SEED, planet, maximum_tiles = 4096)
	defer destroy_water_tile_cache(cache)
	first := floor_divide_i64(-cache.face_cells, cache.tile_cells)
	last := floor_divide_i64(cache.face_cells, cache.tile_cells)
	near := make(map[Water_Tile_Key]struct{})
	defer delete(near)
	for cell, index in ([4][3]i64{{5, -503, 6}, {2, 503, -413}, {1, -507, -231}, {5, 369, -502}}) {
		column, row := floor_divide_i64(cell[1], cache.tile_cells), floor_divide_i64(cell[2], cache.tile_cells)
		round := index < 2 ? i64(1) : 0
		for next_row in max(row - round, first) ..= min(row + round, last) {
			for next_column in max(column - round, first) ..= min(column + round, last) {
				near[Water_Tile_Key{i32(cell[0]), i32(next_column), i32(next_row)}] = {}
			}
		}
	}
	for row in first ..= last {
		near[Water_Tile_Key{0, i32(last), i32(row)}] = {}
	}
	keys := slice.clone(water_tile_keys_sorted(near), context.allocator)
	defer delete(keys)
	past_lakes, past_heads, uncovered, twice, springs, lost := 0, 0, 0, 0, 0, 0
	for key in keys {
		plane := water_face_plane(cache, key.face)
		lakes, heads := take_water_tile_analyses(cache, []Water_Tile_Key{key})
		for lake in lakes {
			past_lakes += water_face_of(waters_plane_direction(plane, i64(lake.cell[1]), i64(lake.cell[2]))) != key.face ? 1 : 0
			if !water_tiles_test_lake_covered(cache, lake, false) {
				uncovered += 1
				log.infof("0326: the lake of %v has no kept lake over it", lake.cell)
			}
		}
		kept, _ := take_water_tile_finals(cache, []Water_Tile_Key{key})
		for lake in kept {
			if water_tiles_test_lake_covered(cache, lake, true) {
				twice += 1
				log.infof("0326: the kept lake of %v overlaps another kept lake", lake.cell)
			}
		}
		for head in heads {
			past_heads += water_face_of(head.spring.direction) != key.face ? 1 : 0
		}
		kept_heads, lost_heads := water_tiles_test_heads_lost(cache, heads)
		springs += kept_heads
		lost += lost_heads
		free_all(context.temp_allocator)
	}
	log.infof("0326: the %d seam tiles' analyses hold %d lakes and %d heads past their faces' edges; %d lakes uncovered, %d kept twice, %d of %d heads kept as springs lost", len(keys), past_lakes, past_heads, uncovered, twice, lost, springs)
	testing.expect(t, past_lakes > 0 && past_heads > 0, "the tiles find lakes and heads past their faces' edges")
	testing.expectf(t, uncovered == 0, "%d lakes have no kept lake over them", uncovered)
	testing.expectf(t, twice == 0, "%d kept lakes overlap another", twice)
	testing.expectf(t, lost == 0, "%d heads have no kept spring within the spacing", lost)
}

// Whether the lake's mask holds a water cell (under the level by a metre)
// in another tile than its pit's, and one such point and one in the pit's
// tile, on the sphere of the radius.
water_tiles_test_crossing :: proc(cache: ^Water_Tile_Cache, generation: Planet_Generation, lake: Planet_Lake) -> (inside, outside: [3]i64, crosses: bool) {
	home := Water_Tile_Key{lake.cell[0], i32(floor_divide_i64(i64(lake.cell[1]), cache.tile_cells)), i32(floor_divide_i64(i64(lake.cell[2]), cache.tile_cells))}
	plane := planet_lake_plane(lake, generation.radius, metres_to_position_units(LAKE_CELL_METRES))
	found_inside := false
	for v in -lake.half ..= lake.half {
		for u in -lake.half ..= lake.half {
			if !planet_lake_mask_bit(lake, u, v) {
				continue
			}
			direction := waters_plane_direction(plane, u, v)
			if uncratered_relief(generation, fixed_scale(direction, generation.radius)) >= lake.level - metres_to_position_units(1) {
				continue
			}
			if water_tile_key_of(cache, direction) == home {
				inside, found_inside = fixed_scale(direction, generation.radius), true
			} else if !crosses {
				outside, crosses = fixed_scale(direction, generation.radius), true
			}
			if found_inside && crosses {
				return
			}
		}
	}
	crosses = crosses && found_inside
	return
}

// The chunk at 1 m holding the point on the sphere raised to a metre under
// the lake's level: the air samples the lake holds under its level, the
// first listed lake there being this one, hold its fill. Returns the
// samples filled and those that differ.
water_tiles_test_lake_chunk :: proc(planet: Planet, generation: Planet_Generation, lake: Planet_Lake, on_sphere: [3]i64) -> (filled, differing: int) {
	up, _ := normalize_fixed(on_sphere)
	point := World_Position(fixed_scale(up, generation.radius + lake.level - metres_to_position_units(1)))
	chunk := new(Field_Chunk, context.temp_allocator)
	generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, sample_to_field_chunk_coordinate(world_position_to_sample(point, 1000)), chunk)
	origin := field_chunk_origin(chunk.coordinate)
	minimum := cast([3]i64)sample_to_world_position(origin, 1000)
	maximum := cast([3]i64)sample_to_world_position(origin + FIELD_CHUNK_SIZE - 1, 1000)
	listed := generation_lakes_meeting_box(generation, minimum, maximum)
	fill_level := planet_lake_fill_level(generation, lake)
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		if chunk.density[index] > 0 {
			continue
		}
		sample := origin + Sample_Coordinate(field_index_to_local(index))
		position := sample_to_world_position(sample, 1000)
		distance := vector_length(cast([3]i64)position)
		sphere := project_onto_sphere(position, distance, generation.radius)
		fill := field_sea_fill(fill_level, field_water_span(sample))
		level, found := planet_lake_level_at(listed, sphere, generation.radius)
		if !found || level != lake.level || !planet_lake_holds(lake, sphere, generation.radius) || fill == 0 || column_carves(surface_column(generation, sphere), distance - generation.radius, 1000) {
			continue
		}
		filled += 1
		if i32(chunk.water[index]) != fill || chunk.water_owner[index] != WATER_OWNER_NONE {
			differing += 1
		}
	}
	return
}

// Work item 0326: the finals within 1500 m of the shipped home at 8 km keep
// 0312's bounds, the densities the design's probe found (1.64 lakes and
// 0.53 springs a square kilometre), a lake crossing a tile's edge fills
// the chunks on both sides of it, a spring's chunk holds its source, no
// tree stands in the largest lake and its level 1 grid shows it.
@(test) // slow
test_water_tiles_round_the_shipped_home :: proc(t: ^testing.T) {
	planet := water_tiles_test_planet(8000)
	planet.water_tiles = make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(planet.water_tiles)
	cache := planet.water_tiles
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	sea := generation.sea_radius - generation.radius
	near := make(map[Water_Tile_Key]struct{}, context.temp_allocator)
	water_tiles_near(cache, cache.home, metres_to_position_units(1500), &near)
	keys := water_tile_keys_sorted(near)
	lakes, springs := take_water_tile_finals(cache, keys)
	slice.sort_by(lakes, water_lake_before)
	area := f64(len(keys)) * f64(planet.waters.tile_metres) * f64(planet.waters.tile_metres) / 1_000_000
	log.infof("0326: at 8 km the %d tiles within 1500 m of the home (%.1f km2) hold %d lakes and %d springs", len(keys), area, len(lakes), len(springs))
	testing.expectf(t, f64(len(lakes)) >= 1.2 * area && f64(len(lakes)) <= 2.2 * area, "%d lakes on %.1f km2", len(lakes), area)
	testing.expectf(t, f64(len(springs)) >= 0.3 * area && f64(len(springs)) <= 0.8 * area, "%d springs on %.1f km2", len(springs), area)
	home := fixed_scale(cache.home, generation.radius)
	clearing := metres_to_position_units(i64(planet.waters.clearing_metres))
	for lake, index in lakes {
		testing.expectf(t, lake.level - lake.floor >= millimetres_to_position_units(planet.waters.lake_minimum_depth_millimetres), "lake %d is %d deep", index, lake.level - lake.floor)
		testing.expectf(t, int(lake.cells) * 4 >= planet.waters.lake_minimum_area_square_metres, "lake %d holds %d cells", index, lake.cells)
		testing.expectf(t, lake.floor - sea >= millimetres_to_position_units(WIDEST_SAMPLE_SPACING_MILLIMETRES), "lake %d's floor lies a sample over the sea", index)
		testing.expectf(t, squared_chord(lake.origin, home) >= clearing * clearing, "lake %d lies outside the clearing", index)
		testing.expectf(t, lake_leaks(generation, lake) == 0, "lake %d leaks", index)
		for other, other_index in lakes {
			if other_index != index {
				testing.expectf(t, !planet_lake_holds(other, lake.origin, generation.radius), "lake %d holds lake %d's pit", other_index, index)
			}
		}
	}
	spacing := metres_to_position_units(i64(planet.waters.spring_spacing_metres))
	for spring, index in springs {
		point := fixed_scale(spring.direction, generation.radius)
		testing.expectf(t, spring.height - sea >= metres_to_position_units(i64(planet.waters.spring_minimum_metres)), "spring %d stands %d over the sea", index, spring.height - sea)
		testing.expectf(t, squared_chord(point, home) >= clearing * clearing, "spring %d lies outside the clearing", index)
		for record in planet.springs {
			testing.expectf(t, squared_chord(point, fixed_scale(planet_spring_direction(record), generation.radius)) >= spacing * spacing, "spring %d keeps from the record's", index)
		}
		for other, other_index in springs {
			if other_index != index {
				testing.expectf(t, squared_chord(point, fixed_scale(other.direction, generation.radius)) >= spacing * spacing, "springs %d and %d keep apart", index, other_index)
			}
		}
		if level, found := planet_lake_level_at(lakes, point, generation.radius); found {
			testing.expectf(t, spring.height >= level, "spring %d lies under a lake", index)
		}
	}
	if len(lakes) == 0 || len(springs) == 0 {
		return
	}
	// A lake crossing its tile's edge fills the chunks on both sides.
	crossing := 0
	checked := false
	for lake in lakes {
		inside, outside, crosses := water_tiles_test_crossing(cache, generation, lake)
		if !crosses {
			continue
		}
		crossing += 1
		if checked {
			continue
		}
		checked = true
		inside_filled, inside_differing := water_tiles_test_lake_chunk(planet, generation, lake, inside)
		outside_filled, outside_differing := water_tiles_test_lake_chunk(planet, generation, lake, outside)
		testing.expectf(t, inside_filled > 0 && outside_filled > 0 && inside_differing == 0 && outside_differing == 0, "a crossing lake fills %d and %d samples, %d and %d differ", inside_filled, outside_filled, inside_differing, outside_differing)
	}
	testing.expectf(t, crossing > 0, "a lake crosses its tile's edge")
	// A spring's chunk holds its source.
	spring_sample, spring_found := planet_spring_sample_at(generation, springs[0].direction)
	testing.expect(t, spring_found, "the first spring finds air")
	if spring_found {
		spring_chunk := new(Field_Chunk, context.temp_allocator)
		generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, sample_to_field_chunk_coordinate(spring_sample), spring_chunk)
		testing.expect(t, field_sample_bit(&spring_chunk.water_source, sample_to_field_index(spring_sample)), "the first spring is a source")
	}
	// The trees' listing holds every lake at its refined pit on the sphere
	// of the radius, however high its level stands over it.
	highest := min(i64)
	for lake in lakes {
		highest = max(highest, lake.level)
		listed := generation_lakes_near_sphere_box(generation, lake.origin - metres_to_position_units(1), lake.origin + metres_to_position_units(1))
		held := false
		for other in listed {
			held ||= other.cell == lake.cell
		}
		testing.expectf(t, held, "the trees' listing at lake %v's pit holds it", lake.cell)
	}
	log.infof("0326: the highest lake stands %.1f m over the radius", f64(highest) / POSITION_UNITS_PER_METRE)
	// No tree stands in the largest lake. The box goes in quarters along
	// each axis, within PLANET_TREE_BOX_CELL_LIMIT at the forest's spacing.
	largest := lakes[0]
	tree_generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	half := min(largest.bound_radius, metres_to_position_units(120))
	quarter := half / 2
	margin := metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES)
	trees := 0
	for x in i64(0) ..< 4 {
		for y in i64(0) ..< 4 {
			for z in i64(0) ..< 4 {
				minimum := largest.origin - half + [3]i64{x, y, z} * quarter
				for tree in planet_trees_in_box(&tree_generation, minimum, minimum + quarter - 1) {
					trees += 1
					on_sphere := tree_test_on_sphere(tree_generation, tree)
					if planet_lake_holds(largest, on_sphere, generation.radius) {
						testing.expectf(t, surface_column(tree_generation, on_sphere).relief >= largest.level + margin, "the tree %v stands in a lake", tree.key)
					}
				}
			}
		}
	}
	// The coarse grid shows the largest lake where no chunk is loaded.
	lake_point := World_Position(fixed_scale(largest.centre, generation.radius + largest.level - metres_to_position_units(1)))
	node := test_surface_node(lake_point, 1000, 1)
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	coarse := field_grid_generation(generation, grid.step)
	lake_water := 0
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				index := field_grid_index({x, y, z})
				position := sample_to_world_position(grid.origin + Sample_Coordinate([3]i32{x, y, z} * grid.step), 1000)
				if grid.water[index] > planet_sea_density(coarse, position, grid.density[index]) {
					lake_water += 1
				}
			}
		}
	}
	testing.expectf(t, lake_water > 0, "the level 1 grid %v shows the lake", node)
	log.infof("0326: %d lakes cross their tile's edge, %d trees round the largest, its level 1 grid %d lake samples", crossing, trees, lake_water)
}

@(test) // slow
test_water_tiles_keep_to_their_bound :: proc(t: ^testing.T) {
	cache := make_water_tile_cache(DEFAULT_WORLD_SEED, water_tiles_test_planet(8000), maximum_tiles = 4)
	defer destroy_water_tile_cache(cache)
	home := water_tile_key_of(cache, cache.home)
	keys := make([dynamic]Water_Tile_Key, context.temp_allocator)
	for row in i32(-2) ..< 2 {
		for column in i32(-2) ..< 2 {
			append(&keys, Water_Tile_Key{home.face, home.column + column, home.row + row})
		}
	}
	for key in keys {
		take_water_tile_analyses(cache, []Water_Tile_Key{key})
		testing.expect(t, water_tiles_test_found_count(cache) <= 4, "the cache keeps at most 4 tiles found")
	}
	testing.expect_value(t, water_tiles_test_found_count(cache), 4)
}

@(test)
test_the_waters_tile_problems :: proc(t: ^testing.T) {
	shipped := default_planet(shipped_test_planets()).waters
	testing.expect_value(t, shipped.tile_metres, 1024)
	waters := shipped
	for entry in ([3][2]int{{255, 0}, {4097, 0}, {1000, 1}}) {
		waters.tile_metres = entry[0]
		problem := waters_problem(waters)
		expected := entry[1] == 0 ? "waters.tile_metres %d is outside" : "waters.tile_metres %d is not a multiple of grid_metres"
		testing.expectf(t, strings.has_prefix(problem, fmt.tprintf(expected, entry[0])), "tile_metres %d: %q", entry[0], problem)
	}
	waters.tile_metres = 0
	testing.expect_value(t, waters_problem(waters), "")
	waters = shipped
	waters.spring_catchment_square_metres = 65 * shipped.grid_metres * shipped.grid_metres
	testing.expect_value(t, waters_problem(waters), "waters.spring_catchment_square_metres 16640 is 65 cells of grid_metres 16, more than 64 with tiles")
	waters.tile_metres = 0
	testing.expect_value(t, waters_problem(waters), "")
	planet := shipped_test_home_at(3000)
	testing.expect_value(t, waters_planet_problem(planet), "waters reach 803 m round a point, more than 21 percent of the radius 3000 m")
	planet.waters.tile_metres = 0
	testing.expect_value(t, waters_planet_problem(planet), "")
	testing.expect_value(t, waters_planet_problem(shipped_test_home_at(4000)), "")
}

// A world file whose record has 0312's waters without tile_metres keeps
// them round its home: one log line, tile_metres 0, no tiles, and the
// features 0312's finder finds for the record's planet.
@(test) // slow
test_an_old_world_keeps_the_waters_round_its_home :: proc(t: ^testing.T) {
	planets := shipped_test_planets()
	planet := default_planet(planets)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = planet.id},
		planet_generation = planet_generation_record(planet),
	}
	text := string(encode_world_file(file, context.temp_allocator))
	testing.expect(t, strings.contains(text, "tile_metres"), "the world file records the tiles")
	older, removed := strings.replace(text, "tile_metres: 1024", "", 1, context.temp_allocator)
	testing.expect(t, removed, "the record's tile_metres is removed")
	parsed, problem := parse_world_file(transmute([]byte)older, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.planet_generation.waters.tile_metres, 0)
	testing.expect(t, strings.contains(recorded_waters_note(parsed.planet_generation, planet), "round the home only"), "the old file's note")
	testing.expect_value(t, recorded_waters_note(planet_generation_record(planet), planet), "")
	session: Session
	plan := Session_Plan {
		loading = true,
		seed = DEFAULT_WORLD_SEED,
		settings = parsed.settings,
		file = parsed,
	}
	resolve_session_planet(plan, planets, &session)
	defer destroy_recorded_planet(&session.planet)
	testing.expect_value(t, session.planet.waters.tile_metres, 0)
	testing.expect(t, session.planet.water_tiles == nil, "no tiles")
	_, resolved_planet, record := resolve_world_planet(parsed.settings, parsed.planet_generation, planets, true)
	recorded := make_recorded_planet(resolved_planet, record, context.temp_allocator)
	features := make_planet_water_features(DEFAULT_WORLD_SEED, recorded)
	defer destroy_planet_water_features(&features)
	testing.expect(t, len(features.lakes) > 0 && waters_features_equal(session.planet.water_features, features), "the features round the home are 0312's")
}

@(test)
test_a_new_world_records_its_tiles :: proc(t: ^testing.T) {
	planet := default_planet(shipped_test_planets())
	record := planet_generation_record(planet)
	testing.expect_value(t, record.waters.tile_metres, 1024)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = {day_length_seconds = 1200, planet_id = planet.id},
		planet_generation = record,
	}
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.planet_generation.waters.tile_metres, 1024)
}
