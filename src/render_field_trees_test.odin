package game

import "core:container/queue"
import "core:math/linalg"
import "core:testing"
import "render_frustum"

// The trees' draw (work items 0197 and 0310) without a GPU: the matrix
// and the instance, the tiles round the eyes, the near and the far
// selections, the felled trees and the workers' tiles.

@(test)
test_the_tree_matrix_stands_the_model_on_its_base :: proc(t: ^testing.T) {
	up, _ := normalize_fixed({UNIT_VECTOR_ONE, 3 * UNIT_VECTOR_ONE, -UNIT_VECTOR_ONE})
	base := World_Position(fixed_scale(up, metres_to_position_units(8000)))
	tree := Planet_Tree{base = base, up = up, scale_percent = 110}
	matrix_value := tree_render_matrix(tree, 500)
	origin := (matrix_value * [4]f32{0, 0, 0, 1}).xyz
	testing.expect(t, linalg.length(origin - world_position_to_metres(base)) <= 0.001)
	top := (matrix_value * [4]f32{0, 1, 0, 1}).xyz
	expected := world_position_to_metres(base) + unit_vector_to_f32(up) * 0.5 * 1.1
	testing.expectf(t, linalg.length(top - expected) <= 0.001, "%v against %v", top, expected)
	turned := tree
	turned.yaw = ANGLE_UNITS_PER_QUARTER
	front := (matrix_value * [4]f32{1, 0, 0, 0}).xyz
	turned_front := (tree_render_matrix(turned, 500) * [4]f32{1, 0, 0, 0}).xyz
	testing.expect(t, abs(linalg.dot(linalg.normalize(front), linalg.normalize(turned_front))) <= 0.001, "a quarter turn apart")
}

@(test)
test_tree_instance_packs_species_and_shade :: proc(t: ^testing.T) {
	up, _ := normalize_fixed({UNIT_VECTOR_ONE, 3 * UNIT_VECTOR_ONE, -UNIT_VECTOR_ONE})
	tree := Planet_Tree{base = World_Position(fixed_scale(up, metres_to_position_units(8000))), up = up, scale_percent = 150, shade_percent = 104, species = 3}
	instance := tree_instance(tree, 500)
	render := tree_render_matrix(tree, 500)
	testing.expect_value(t, tree_instance_species(instance), 3)
	testing.expect_value(t, instance[3, 1], f32(1.04))
	testing.expect_value(t, instance[3, 2], f32(0))
	testing.expect_value(t, instance[3, 3], f32(1))
	for row in 0 ..< 3 {
		for column in 0 ..< 4 {
			testing.expect_value(t, instance[row, column], render[row, column])
		}
	}
	testing.expect(t, linalg.length(tree_instance_base(instance) - world_position_to_metres(tree.base)) <= 0.001)
	// tree.vs reads column 0's w as the species and column 1's as the
	// shade: the columns raylib sends as instanceTransform.
	columns := transmute([16]f32)instance
	testing.expect_value(t, columns[3], f32(3))
	testing.expect_value(t, columns[7], f32(1.04))
}

// A planet with the forest at a test size, its generation and an eye
// 60 m north of the home.
tree_draw_test_setup :: proc() -> (planet: Planet, generation: Planet_Generation, eye: World_Position) {
	planet = tree_test_planet()
	generation = tree_test_generation(planet)
	eye = World_Position(tree_test_point_from_home(generation, planet, 0, 60))
	return planet, generation, eye
}

@(test)
test_tree_tiles_cover_the_far_distance :: proc(t: ^testing.T) {
	planet, generation, eye := tree_draw_test_setup()
	eyes := [1]World_Position{eye}
	FAR :: 384
	tiles := field_tree_tiles_around(&generation, eyes[:], FAR)
	wanted := make(map[Field_Tree_Tile]struct{}, context.temp_allocator)
	for tile in tiles {
		wanted[tile] = {}
	}
	edge := field_tree_tile_edge(&generation)
	testing.expect_value(t, edge, metres_to_position_units(FIELD_TREE_TILE_METRES))
	testing.expect_value(t, len(wanted), len(tiles))
	points := field_tree_eye_points(&generation, eyes[:])
	for index in 1 ..< len(tiles) {
		testing.expect(t, field_tree_tile_distance(tiles[index - 1], edge, points) <= field_tree_tile_distance(tiles[index], edge, points), "nearest first")
	}
	// Every point of the sphere within the distance lies in a wanted tile,
	// at 8 bearings out to the distance.
	missing := 0
	for bearing in 0 ..< 8 {
		for distance := i64(0); distance <= FAR - 4; distance += 20 {
			point := tree_test_point_from_home(generation, planet, i32(bearing) * ANGLE_UNITS_PER_TURN / 8, 60 + distance)
			offset := point - points[0]
			if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z > metres_to_position_units(FAR - 2) * metres_to_position_units(FAR - 2) {
				continue
			}
			tile := Field_Tree_Tile{i32(floor_divide_i64(point.x, edge)), i32(floor_divide_i64(point.y, edge)), i32(floor_divide_i64(point.z, edge))}
			if tile not_in wanted {
				missing += 1
			}
		}
	}
	testing.expectf(t, missing == 0, "%d points within the distance lie in no wanted tile", missing)
}

// A tile of the instances at the offsets (metres along +x from the
// camera at 8 km up +y), keys from the first.
tree_draw_test_tile :: proc(camera: [3]f32, offsets: []f32, first_key: i32) -> Field_Tree_Tile_Draw {
	keys := make([]Tree_Key, len(offsets))
	instances := make([]matrix[4, 4]f32, len(offsets))
	for offset, index in offsets {
		keys[index] = {first_key + i32(index), 0, 0}
		instances[index] = 1
		instances[index][0, 3], instances[index][1, 3], instances[index][2, 3] = camera.x + offset, camera.y, camera.z
	}
	tile := make_field_tree_tile_draw(keys, instances, nil)
	tile.count = len(instances)
	tile.dirty = false
	return tile
}

@(test)
test_the_near_selection_caps_and_pulls_in :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	camera := [3]f32{0, 8000, 0}
	offsets := make([]f32, 300, context.temp_allocator)
	for &offset, index in offsets {
		offset = 0.3 * f32(index + 1) + 0.05
	}
	cache.tiles[{0, 0, 0}] = tree_draw_test_tile(camera, offsets, 0)
	far := [1]f32{97}
	cache.tiles[{1, 0, 0}] = tree_draw_test_tile(camera, far[:], 1000)
	felled := make(map[Tree_Key]struct{}, context.temp_allocator)
	felled[{0, 0, 0}] = {}
	config := Field_Trees_Row{near_metres = 96, near_limit = 1000}
	trees, near_distance := select_near_trees(&cache, camera, render_frustum.Frustum{}, 4, felled, config)
	testing.expect_value(t, len(trees), 299)
	testing.expect_value(t, near_distance, f32(96))
	config.near_limit = 100
	trees, near_distance = select_near_trees(&cache, camera, render_frustum.Frustum{}, 4, felled, config)
	testing.expect_value(t, len(trees), 100)
	// The first cut is the 101st standing tree: offset 0.3 * 102 + 0.05.
	testing.expectf(t, abs(near_distance - 30.65) < 0.01, "near distance %v", near_distance)
	for tree in trees {
		base := tree_instance_base(tree.instance)
		testing.expect(t, base.x - camera.x < near_distance, "every selected tree is nearer than the near distance")
		testing.expect(t, base.x - camera.x > 0.5, "the felled tree is left out")
	}
}

@(test)
test_the_far_tiles_stop_at_the_card_limit :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	camera := [3]f32{0, 8000, 0}
	ten := make([]f32, 10, context.temp_allocator)
	for distance, index in ([4]f32{100, 300, 500, 700}) {
		for &offset, slot in ten {
			offset = distance + f32(slot)
		}
		cache.tiles[{i32(index), 0, 0}] = tree_draw_test_tile(camera, ten, i32(index) * 100)
	}
	config := Field_Trees_Row{far_metres = 1024, far_limit = 25}
	tiles, far_distance := select_far_tiles(&cache, camera, render_frustum.Frustum{}, 2, config)
	testing.expect_value(t, len(tiles), 2)
	testing.expectf(t, abs(far_distance - 498) < 0.01, "the far distance %v is the third tile's box", far_distance)
	testing.expect(t, tiles[0].distance < tiles[1].distance, "nearest first")
	config.far_limit = 1000
	tiles, far_distance = select_far_tiles(&cache, camera, render_frustum.Frustum{}, 2, config)
	testing.expect_value(t, len(tiles), 4)
	testing.expect_value(t, far_distance, f32(1024))
	config.far_metres = 400
	tiles, far_distance = select_far_tiles(&cache, camera, render_frustum.Frustum{}, 2, config)
	testing.expect_value(t, len(tiles), 2)
	testing.expect_value(t, far_distance, f32(400))
	config.far_limit = 0
	tiles, _ = select_far_tiles(&cache, camera, render_frustum.Frustum{}, 2, config)
	testing.expect_value(t, len(tiles), 0)
}

@(test)
test_a_felled_tree_rebuilds_its_tile :: proc(t: ^testing.T) {
	_, generation, eye := tree_draw_test_setup()
	streaming := start_field_streaming(DEFAULT_WORLD_SEED, tree_test_planet(), 1000, 0)
	defer stop_field_streaming(&streaming)
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	eyes := [1]World_Position{eye}
	config := Field_Trees_Row{near_metres = 96, near_limit = 1024, far_metres = 128, far_limit = 1000, fade_metres = 12, far_fade_metres = 32}
	felled := make(map[Tree_Key]struct{}, context.temp_allocator)
	update_field_tree_cache(&cache, &streaming, &generation, eyes[:], felled, config, 500)
	testing.expect(t, len(cache.pending) > 0 && len(cache.pending) <= FIELD_TREE_TILES_PENDING_LIMIT, "tiles go to the workers")
	testing.expect_value(t, len(cache.tiles), 0)
	// No worker threads: run the queued jobs here, as a worker would.
	run_queued_field_tree_jobs(&streaming)
	update_field_tree_cache(&cache, &streaming, &generation, eyes[:], felled, config, 500)
	testing.expect(t, len(cache.tiles) > 0 && len(cache.tiles) <= FIELD_TREE_UPLOADS_PER_FRAME, "at most the uploads a frame are taken")
	tile: Field_Tree_Tile
	key: Tree_Key
	found := false
	for candidate, draw in cache.tiles {
		testing.expect(t, draw.dirty, "a taken tile waits to go up")
		if len(draw.keys) > 0 && !found {
			tile, key, found = candidate, draw.keys[0], true
		}
	}
	testing.expect(t, found, "a tile with trees")
	before := len(cache.tiles[tile].keys)
	cache.tiles[tile] = mark_field_tree_tile_uploaded(cache.tiles[tile])
	felled[key] = {}
	update_field_tree_cache(&cache, &streaming, &generation, eyes[:], felled, config, 500)
	after := cache.tiles[tile]
	testing.expect_value(t, len(after.keys), before - 1)
	testing.expect(t, after.dirty, "the tile goes up again")
	for remaining in after.keys {
		testing.expect(t, remaining != key, "the felled key is dropped")
	}
	// A shorter felled table rebuilds every tile.
	delete_key(&felled, key)
	update_field_tree_cache(&cache, &streaming, &generation, eyes[:], felled, config, 500)
	testing.expect(t, tile not_in cache.tiles, "the tiles are generated again")
}

// Work item 0343: a cache holding every tile out to 1024 m, updated at a
// 256 m view, keeps exactly the tiles within 256 m and two tile edges and
// sends nothing to the workers.
@(test)
test_a_shorter_view_evicts_the_far_tree_tiles :: proc(t: ^testing.T) {
	planet, generation, eye := tree_draw_test_setup()
	streaming := start_field_streaming(DEFAULT_WORLD_SEED, planet, 1000, 0)
	defer stop_field_streaming(&streaming)
	config, _ := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	eyes := [1]World_Position{eye}
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	cache.cells = field_tree_tile_cells(generation.trees.spacing)
	before := field_tree_tiles_around(&generation, eyes[:], 1024)
	for tile in before {
		cache.tiles[tile] = {}
	}
	felled := make(map[Tree_Key]struct{}, context.temp_allocator)
	update_field_tree_cache(&cache, &streaming, &generation, eyes[:], felled, field_trees_view_row(config.field_trees.desktop, 256), 500)
	testing.expect_value(t, cache.config.far_metres, 256)
	edge := field_tree_tile_edge(&generation)
	points := field_tree_eye_points(&generation, eyes[:])
	keep := metres_to_position_units(256) + FIELD_TREE_KEEP_TILES * edge
	for tile in cache.tiles {
		testing.expectf(t, field_tree_tile_distance(tile, edge, points) <= keep * keep, "%v is kept past the view", tile)
	}
	for tile in before {
		if field_tree_tile_distance(tile, edge, points) <= keep * keep {
			testing.expectf(t, tile in cache.tiles, "%v within the view is evicted", tile)
		}
	}
	testing.expect(t, len(cache.tiles) < len(before), "tiles are evicted")
	testing.expect_value(t, len(cache.pending), 0)
}

// The tile as upload_field_tree_tiles leaves it, without the GPU.
mark_field_tree_tile_uploaded :: proc(tile: Field_Tree_Tile_Draw) -> Field_Tree_Tile_Draw {
	uploaded := tile
	uploaded.count = len(tile.instances)
	uploaded.dirty = false
	return uploaded
}

// Every queued tree job run on this thread, its result queued as a
// worker's.
run_queued_field_tree_jobs :: proc(streaming: ^Field_Streaming) {
	for {
		job, ok := pop_field_tree_job_for_test(streaming.shared)
		if !ok {
			return
		}
		push_field_result(streaming.shared, run_field_job(streaming.shared, job))
	}
}

pop_field_tree_job_for_test :: proc(shared: ^Field_Worker_Shared) -> (job: Field_Job, ok: bool) {
	if queue.len(shared.tree_jobs) == 0 {
		return {}, false
	}
	return queue.pop_front(&shared.tree_jobs), true
}

@(test)
test_a_worker_tile_equals_the_simulations_trees :: proc(t: ^testing.T) {
	planet, _, eye := tree_draw_test_setup()
	streaming := start_field_streaming(DEFAULT_WORLD_SEED, planet, 1000, 0)
	defer stop_field_streaming(&streaming)
	simulation := make_field_water_planet(DEFAULT_WORLD_SEED, planet, 1000).generation
	edge := field_tree_tile_edge(&simulation)
	cells := field_tree_tile_cells(simulation.trees.spacing)
	tile := Field_Tree_Tile{i32(floor_divide_i64(eye.x, edge)), i32(floor_divide_i64(eye.y, edge)), i32(floor_divide_i64(eye.z, edge))}
	result := run_field_job(streaming.shared, Field_Job{kind = .Trees, tree_tile = tile, tree_cells = cells, tree_pitch_millimetres = 500})
	defer free_field_job_result(result)
	minimum, maximum := field_tree_tile_box(tile, edge)
	trees := planet_trees_in_box(&simulation, minimum, maximum)
	testing.expect_value(t, result.tree_tile, tile)
	testing.expect_value(t, len(result.tree_keys), len(trees))
	testing.expectf(t, len(trees) > 100, "%d trees in the tile", len(trees))
	for tree, index in trees {
		if index >= len(result.tree_keys) {
			break
		}
		testing.expect_value(t, result.tree_keys[index], tree.key)
		testing.expect_value(t, result.tree_instances[index], tree_instance(tree, 500))
	}
}
