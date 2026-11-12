package game

import "core:container/queue"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:testing"
import "render_frustum"

// The trees' draw (work items 0197, 0310 and 0346) without a GPU: the
// matrix and the instance, the tiles round the eyes, the near and the far
// selections, the views' held candidates against a fresh selection, the
// cache's changes, the felled trees and the workers' tiles.

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

// The selected candidates' keys sorted (tree_key_before) and their
// instances in that order (temp allocator).
sorted_tree_selection :: proc(candidates: []Tree_Candidate, selection: []u32) -> (keys: []Tree_Key, instances: []matrix[4, 4]f32) {
	chosen := make([]Tree_Candidate, len(selection), context.temp_allocator)
	for index, position in selection {
		chosen[position] = candidates[index]
	}
	slice.sort_by(chosen, proc(first, second: Tree_Candidate) -> bool {
		return tree_key_before(first.key, second.key)
	})
	keys = make([]Tree_Key, len(chosen), context.temp_allocator)
	instances = make([]matrix[4, 4]f32, len(chosen), context.temp_allocator)
	for candidate, position in chosen {
		keys[position], instances[position] = candidate.key, candidate.instance
	}
	return keys, instances
}

// A fresh near selection, as a scan of the tiles each frame would make
// it: a pass gathered at near_metres, then cut. Its keys sorted with
// their instances (temp allocator), the pass released.
fresh_near_trees :: proc(cache: ^Field_Tree_Cache, camera: [3]f32, frustum: render_frustum.Frustum, extent_metres: f32, felled: map[Tree_Key]struct{}, config: Field_Trees_Row, species_count: int) -> (keys: []Tree_Key, instances: []matrix[4, 4]f32, near_distance: f32) {
	pass: Tree_Pass
	defer release_tree_pass(&pass)
	gather_near_tree_candidates(&pass, cache, camera, f32(config.near_metres), felled, species_count)
	near_distance = cut_near_trees(&pass, camera, frustum, extent_metres, config)
	keys, instances = sorted_tree_selection(pass.candidates[:], pass.next[:])
	return keys, instances, near_distance
}

// One tile of tree_selection_test_forest: a tree every 2 m, 32 by 32,
// from the camera moved 64 m a tile in x and z, on the plane 1.6 m below
// it, each moved up to 0.8 m in x and z by a hash of its key, species
// cycling over 3, shade 1.
tree_selection_test_tile :: proc(camera: [3]f32, tile: Field_Tree_Tile) -> Field_Tree_Tile_Draw {
	EDGE :: 32
	keys := make([]Tree_Key, EDGE * EDGE)
	instances := make([]matrix[4, 4]f32, EDGE * EDGE)
	for column in 0 ..< EDGE {
		for row in 0 ..< EDGE {
			index := column * EDGE + row
			key := Tree_Key{64 * tile.x + i32(column), 0, 64 * tile.z + i32(row)}
			hash := u32(key.x) * 73856093 ~ u32(key.z) * 19349663
			jitter := [2]f32{f32(hash % 1601) / 1000 - 0.8, f32(hash / 1601 % 1601) / 1000 - 0.8}
			instance: matrix[4, 4]f32 = 1
			instance[0, 3] = camera.x + 64 * f32(tile.x) + 2 * f32(column) + jitter.x
			instance[1, 3] = camera.y - 1.6
			instance[2, 3] = camera.z + 64 * f32(tile.z) + 2 * f32(row) + jitter.y
			instance[3, 0] = f32(index % 3)
			instance[3, 1] = 1
			keys[index], instances[index] = key, instance
		}
	}
	return make_field_tree_tile_draw(keys, instances, nil)
}

// The tiles (x, 0, z) for x and z from -2 to 1 round the camera but the
// skipped one, the keys' tiles 64 keys an edge so a felled key finds its
// tile.
tree_selection_test_forest :: proc(cache: ^Field_Tree_Cache, camera: [3]f32, skip: Field_Tree_Tile) {
	cache.cells = 64
	for x in -2 ..= 1 {
		for z in -2 ..= 1 {
			tile := Field_Tree_Tile{i32(x), 0, i32(z)}
			if tile != skip {
				cache.tiles[tile] = tree_selection_test_tile(camera, tile)
			}
		}
	}
}

// A 70 degree, 16:9 frustum from the eye along the yaw in the x, z plane,
// up +y.
tree_test_frustum :: proc(eye: [3]f32, yaw_degrees: f32) -> render_frustum.Frustum {
	yaw := yaw_degrees * math.RAD_PER_DEG
	view := linalg.matrix4_look_at_f32(eye, eye + {math.cos(yaw), 0, math.sin(yaw)}, {0, 1, 0})
	projection := linalg.matrix4_perspective_f32(70 * math.RAD_PER_DEG, 16.0 / 9.0, 0.1, 32000)
	return render_frustum.frustum_from_matrix(projection * view)
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
	_, trees, near_distance := fresh_near_trees(&cache, camera, render_frustum.Frustum{}, 4, felled, config, 1)
	testing.expect_value(t, len(trees), 299)
	testing.expect_value(t, near_distance, f32(96))
	config.near_limit = 100
	_, trees, near_distance = fresh_near_trees(&cache, camera, render_frustum.Frustum{}, 4, felled, config, 1)
	testing.expect_value(t, len(trees), 100)
	// The first cut is the 101st standing tree: offset 0.3 * 102 + 0.05.
	testing.expectf(t, abs(near_distance - 30.65) < 0.01, "near distance %v", near_distance)
	for tree in trees {
		base := tree_instance_base(tree)
		testing.expect(t, base.x - camera.x < near_distance, "every selected tree is nearer than the near distance")
		testing.expect(t, base.x - camera.x > 0.5, "the felled tree is left out")
	}
}

// Work item 0346: the view's near trees, gathered with a margin and cut
// each step, equal a fresh selection's at every step of a walk that turns,
// across a tile arriving and a tree felled.
@(test)
test_the_cached_near_trees_equal_a_fresh_cut_along_a_walk :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	start := [3]f32{0, 8000, 0}
	skipped := Field_Tree_Tile{1, 0, 0}
	tree_selection_test_forest(&cache, start, skipped)
	config := Field_Trees_Row{near_metres = 48, near_limit = 300, fade_metres = 12}
	cache.config = config
	felled := make(map[Tree_Key]struct{})
	defer delete(felled)
	view := &cache.views[0]
	capped := false
	for step in 0 ..< 240 {
		defer free_all(context.temp_allocator)
		camera := start + {0.25 * f32(step), 0, 0}
		frustum := tree_test_frustum(camera, 3 * f32(step))
		gathers_before := view.near.gathers
		if step == 80 {
			insert_field_tree_tile(&cache, skipped, tree_selection_test_tile(start, skipped))
		}
		felled_key := Tree_Key{-1000, -1000, -1000}
		if step == 120 {
			felled_key = view.near.candidates[view.near.selected[0]].key
			felled[felled_key] = {}
			apply_felled_field_trees(&cache, felled)
		}
		near_distance := update_near_trees(&cache, view, camera, frustum, 4, felled, 3)
		keys, instances, fresh_distance := fresh_near_trees(&cache, camera, frustum, 4, felled, config, 3)
		cached_keys, cached_instances := sorted_tree_selection(view.near.candidates[:], view.near.selected[:])
		testing.expectf(t, slice.equal(cached_keys, keys), "step %d: %d cached trees against %d fresh", step, len(cached_keys), len(keys))
		testing.expectf(t, slice.equal(cached_instances, instances), "step %d: the instances differ", step)
		testing.expectf(t, near_distance == fresh_distance, "step %d: near distance %v against %v", step, near_distance, fresh_distance)
		testing.expect_value(t, len(view.near.packed), len(view.near.selected))
		capped ||= near_distance < 48
		if step == 80 {
			testing.expect(t, view.near.gathers > gathers_before, "the arriving tile gathers again")
		}
		if step == 120 {
			_, still := slice.linear_search(cached_keys, felled_key)
			testing.expect(t, !still, "the felled tree is left out")
		}
	}
	testing.expect(t, capped, "the cap binds")
	testing.expectf(t, view.near.gathers < 16, "%d gathers in 240 steps", view.near.gathers)
}

// A tile of the trees at the distances (metres along +x from the camera)
// with the keys.
tree_keyed_test_tile :: proc(camera: [3]f32, distances: []f32, keys: []Tree_Key) -> Field_Tree_Tile_Draw {
	tile_keys := make([]Tree_Key, len(keys))
	instances := make([]matrix[4, 4]f32, len(keys))
	for key, index in keys {
		tile_keys[index] = key
		instances[index] = 1
		instances[index][0, 3], instances[index][1, 3], instances[index][2, 3] = camera.x + distances[index], camera.y, camera.z
	}
	return make_field_tree_tile_draw(tile_keys, instances, nil)
}

@(test)
test_the_near_cut_keeps_the_nearest_by_distance_then_key :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	camera := [3]f32{0, 8000, 0}
	// 10 at 3 m (keys 20 to 29), 10 at 5 m (keys 0 to 9, shuffled), 10 at
	// 7 m (keys 30 to 39), interleaved.
	shuffled := [10]i32{7, 2, 9, 4, 0, 5, 8, 1, 6, 3}
	distances: [30]f32
	keys: [30]Tree_Key
	for index in 0 ..< 10 {
		distances[3 * index], keys[3 * index] = 5, {shuffled[index], 0, 0}
		distances[3 * index + 1], keys[3 * index + 1] = 3, {20 + i32(index), 0, 0}
		distances[3 * index + 2], keys[3 * index + 2] = 7, {30 + i32(index), 0, 0}
	}
	cache.tiles[{0, 0, 0}] = tree_keyed_test_tile(camera, distances[:], keys[:])
	config := Field_Trees_Row{near_metres = 48, near_limit = 15}
	selected, _, near_distance := fresh_near_trees(&cache, camera, render_frustum.Frustum{}, 0, nil, config, 1)
	expected := [15]Tree_Key{{0, 0, 0}, {1, 0, 0}, {2, 0, 0}, {3, 0, 0}, {4, 0, 0}, {20, 0, 0}, {21, 0, 0}, {22, 0, 0}, {23, 0, 0}, {24, 0, 0}, {25, 0, 0}, {26, 0, 0}, {27, 0, 0}, {28, 0, 0}, {29, 0, 0}}
	testing.expectf(t, slice.equal(selected, expected[:]), "kept %v", selected)
	testing.expect_value(t, near_distance, f32(5))
	config.near_limit = 1
	selected, _, near_distance = fresh_near_trees(&cache, camera, render_frustum.Frustum{}, 0, nil, config, 1)
	testing.expectf(t, len(selected) == 1 && selected[0] == Tree_Key{20, 0, 0}, "kept %v", selected)
	testing.expect_value(t, near_distance, f32(3))
	config.near_limit = 30
	selected, _, near_distance = fresh_near_trees(&cache, camera, render_frustum.Frustum{}, 0, nil, config, 1)
	testing.expect_value(t, len(selected), 30)
	testing.expect_value(t, near_distance, f32(48))
}

// ranked's first count by key and the next entry match a full sort's.
expect_selected_like_a_sort :: proc(t: ^testing.T, ranked: []Tree_Ranked, count: int) {
	sorted := slice.clone(ranked, context.temp_allocator)
	slice.sort_by(sorted, tree_ranked_before)
	selected := slice.clone(ranked, context.temp_allocator)
	select_nearest_ranked(selected, count)
	by_key := proc(first, second: Tree_Ranked) -> bool {
		return tree_key_before(first.key, second.key)
	}
	slice.sort_by(sorted[:count], by_key)
	slice.sort_by(selected[:count], by_key)
	testing.expectf(t, slice.equal(selected[:count], sorted[:count]), "%d of %d: the first differ", count, len(ranked))
	testing.expectf(t, selected[count] == sorted[count], "%d of %d: %v next, expected %v", count, len(ranked), selected[count], sorted[count])
}

@(test)
test_selecting_the_nearest_matches_a_full_sort :: proc(t: ^testing.T) {
	state := u32(12345)
	for size in ([5]int{2, 3, 17, 1000, 5000}) {
		ranked := make([]Tree_Ranked, size, context.temp_allocator)
		for &entry, index in ranked {
			state = state * 1664525 + 1013904223
			// 16 distances, so many tie. The keys are a permutation of
			// the indices (7919 is prime to every size).
			entry = Tree_Ranked{distance_squared = f32(state >> 28), key = {i32(index * 7919 % size), 0, 0}, index = u32(index)}
		}
		for count in ([4]int{0, 1, size / 2, size - 1}) {
			expect_selected_like_a_sort(t, ranked, count)
		}
	}
	ascending := make([]Tree_Ranked, 5000, context.temp_allocator)
	for &entry, index in ascending {
		entry = Tree_Ranked{distance_squared = f32(index / 4), key = {i32(index), 0, 0}, index = u32(index)}
	}
	descending := slice.clone(ascending, context.temp_allocator)
	slice.reverse(descending)
	for count in ([3]int{0, 2500, 4999}) {
		expect_selected_like_a_sort(t, ascending, count)
		expect_selected_like_a_sort(t, descending, count)
	}
}

@(test)
test_a_tree_pass_packs_by_species_and_goes_up_only_on_change :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	camera := [3]f32{0, 8000, 0}
	offsets := make([]f32, 30, context.temp_allocator)
	for &offset, index in offsets {
		offset = f32(index + 1)
	}
	tile := tree_draw_test_tile(camera, offsets, 0)
	for &instance, index in tile.instances {
		instance[3, 0] = f32(index % 3)
	}
	cache.tiles[{0, 0, 0}] = tile
	cache.config = Field_Trees_Row{near_metres = 48, near_limit = 100}
	view := &cache.views[0]
	update_near_trees(&cache, view, camera, render_frustum.Frustum{}, 4, nil, 3)
	pass := &view.near
	testing.expect_value(t, pass.group_count, 3)
	for group in 0 ..< 3 {
		range := pass.groups[group]
		testing.expect_value(t, range.count, 10)
		testing.expect_value(t, range.drawn_count, 10)
		for candidate in pass.candidates[range.first:][:range.count] {
			testing.expect_value(t, tree_instance_species(candidate.instance), group)
		}
		for instance in pass.packed[range.drawn_first:][:range.drawn_count] {
			testing.expect_value(t, tree_instance_species(instance), group)
		}
	}
	testing.expect(t, !pass.uploaded, "a new selection goes up")
	pass.uploaded = true
	update_near_trees(&cache, view, camera, render_frustum.Frustum{}, 4, nil, 3)
	testing.expect(t, pass.uploaded, "the same inputs upload nothing")
	testing.expect_value(t, pass.gathers, 1)
	moved := camera - {0.1, 0, 0}
	update_near_trees(&cache, view, moved, render_frustum.Frustum{}, 4, nil, 3)
	testing.expect_value(t, view.near_cut.camera, moved)
	testing.expect(t, pass.uploaded, "the same 30 trees upload nothing")
	cache.config.near_limit = 10
	update_near_trees(&cache, view, moved, render_frustum.Frustum{}, 4, nil, 3)
	testing.expect(t, !pass.uploaded, "a changed selection goes up")
	testing.expect_value(t, len(pass.packed), 10)

	Capacity_Case :: struct {
		capacity, count, expected: int,
		grow:                      bool,
	}
	cases := [?]Capacity_Case{{0, 0, 0, false}, {0, 1, 256, true}, {256, 256, 256, false}, {256, 257, 512, true}, {512, 3000, 4096, true}, {4096, 10, 4096, false}}
	for entry in cases {
		capacity, grow := instance_buffer_capacity(entry.capacity, entry.count)
		testing.expectf(t, capacity == entry.expected && grow == entry.grow, "%v gives %d, %v", entry, capacity, grow)
	}
}

@(test)
test_tree_changes_name_what_reaches_a_view :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	camera := [3]f32{0, 8000, 0}
	tree_selection_test_forest(&cache, camera, {99, 99, 99})
	gather := Near_Tree_Gather{built = true, eye = camera, near_metres = 48, margin_metres = 6, radius_metres = 54.25, species_count = 3, revision = cache.revision}
	testing.expect(t, !near_tree_candidates_stale(&cache, gather, camera, 48, 3), "a fresh gather holds")
	forty := [1]f32{40}
	insert_field_tree_tile(&cache, {5, 0, 0}, tree_draw_test_tile(camera, forty[:], 5000))
	changes, complete := field_tree_changes_since(&cache, gather.revision)
	testing.expect(t, complete && len(changes) == 1, "one change")
	testing.expect(t, near_tree_candidates_stale(&cache, gather, camera, 48, 3), "a tile 40 m away reaches")
	gather.revision = cache.revision
	testing.expect(t, !near_tree_candidates_stale(&cache, gather, camera, 48, 3), "gathered again it holds")
	evict_field_tree_tile(&cache, {-2, 0, -2})
	changes, complete = field_tree_changes_since(&cache, gather.revision)
	testing.expect(t, complete && len(changes) == 1, "one change")
	testing.expect(t, !near_tree_candidates_stale(&cache, gather, camera, 48, 3), "the corner tile 90 m away does not reach")
	far := [1]f32{200}
	for index in 0 ..< 65 {
		insert_field_tree_tile(&cache, {10 + i32(index), 0, 0}, tree_draw_test_tile(camera, far[:], 6000 + i32(index)))
	}
	_, complete = field_tree_changes_since(&cache, gather.revision)
	testing.expect(t, !complete, "65 changes overrun the ring")
	testing.expect(t, near_tree_candidates_stale(&cache, gather, camera, 48, 3), "an overrun ring gathers again")
	gather.revision = cache.revision
	testing.expect(t, !near_tree_candidates_stale(&cache, gather, camera, 48, 3), "gathered again it holds")
	clear_field_tree_tiles(&cache)
	testing.expect(t, near_tree_candidates_stale(&cache, gather, camera, 48, 3), "every tile gone gathers again")
}

// Work item 0348: the sun's kept shadow maps compare their trees when the
// cache's revision moved, so every felling of a cached tree moves it.
@(test)
test_tree_cache_changes_move_its_revision :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	cache.cells = 1000
	camera := [3]f32{0, 8000, 0}
	near := [3]f32{1, 2, 3}
	cache.tiles[{0, 0, 0}] = tree_draw_test_tile(camera, near[:], 0)
	revision := cache.revision
	testing.expect(t, drop_field_tree_key(&cache, {0, 0, 0}), "the key drops")
	testing.expect_value(t, cache.revision, revision + 1)
	felled := make(map[Tree_Key]struct{}, context.temp_allocator)
	felled[{1, 0, 0}] = {}
	apply_felled_field_trees(&cache, felled)
	testing.expect_value(t, cache.revision, revision + 2)
	felled[{5000, 0, 0}] = {}
	apply_felled_field_trees(&cache, felled)
	testing.expect_value(t, cache.revision, revision + 2)
	clear_field_tree_tiles(&cache)
	testing.expect_value(t, cache.revision, revision + 3)
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
	revision := cache.revision
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
	testing.expect(t, cache.revision > revision, "the update that takes tiles moves the cache's revision")
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
