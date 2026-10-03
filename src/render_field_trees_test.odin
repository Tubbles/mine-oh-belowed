package game

import "core:math/linalg"
import "core:testing"
import "render_frustum"

// The trees' draw (work item 0197) without a GPU: the matrix, the grow
// in, the region cache and the cap.

@(test)
test_the_tree_matrix_stands_the_model_on_its_base :: proc(t: ^testing.T) {
	up, _ := normalize_fixed({UNIT_VECTOR_ONE, 3 * UNIT_VECTOR_ONE, -UNIT_VECTOR_ONE})
	base := World_Position(fixed_scale(up, metres_to_position_units(8000)))
	tree := Planet_Tree{base = base, up = up, scale_percent = 110}
	matrix_value := tree_render_matrix(tree, 500, 1)
	origin := (matrix_value * [4]f32{0, 0, 0, 1}).xyz
	testing.expect(t, linalg.length(origin - world_position_to_metres(base)) <= 0.001)
	top := (matrix_value * [4]f32{0, 1, 0, 1}).xyz
	expected := world_position_to_metres(base) + unit_vector_to_f32(up) * 0.5 * 1.1
	testing.expectf(t, linalg.length(top - expected) <= 0.001, "%v against %v", top, expected)
	turned := tree
	turned.yaw = ANGLE_UNITS_PER_QUARTER
	front := (matrix_value * [4]f32{1, 0, 0, 0}).xyz
	turned_front := (tree_render_matrix(turned, 500, 1) * [4]f32{1, 0, 0, 0}).xyz
	testing.expect(t, abs(linalg.dot(linalg.normalize(front), linalg.normalize(turned_front))) <= 0.001, "a quarter turn apart")
}

@(test)
test_trees_grow_in_at_the_draw_distance :: proc(t: ^testing.T) {
	testing.expect_value(t, tree_grow_factor(0), 1)
	testing.expect_value(t, tree_grow_factor(112), 1)
	testing.expect_value(t, tree_grow_factor(120), 0.5)
	testing.expect_value(t, tree_grow_factor(128), 0)
	testing.expect_value(t, tree_grow_factor(500), 0)
}

@(test)
test_the_tree_cache_fills_nearest_first_and_evicts :: proc(t: ^testing.T) {
	planet := tree_test_planet()
	generation := tree_test_generation(planet)
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	eye := World_Position(tree_test_point_from_home(generation, planet, 0, 60))
	eyes := [1]World_Position{eye}
	update_field_tree_cache(&cache, &generation, eyes[:])
	testing.expect_value(t, len(cache.regions), FIELD_TREE_REGIONS_PER_FRAME)
	edge := field_tree_region_edge(&generation)
	own := Field_Tree_Region{i32(floor_divide_i64(eye.x, edge)), i32(floor_divide_i64(eye.y, edge)), i32(floor_divide_i64(eye.z, edge))}
	testing.expect(t, own in cache.regions, "the eye's own region comes first")
	testing.expect(t, !field_tree_cache_settled(&cache, &generation, eyes[:]))
	updates := 1
	for ; updates < 1000 && !field_tree_cache_settled(&cache, &generation, eyes[:]); updates += 1 {
		update_field_tree_cache(&cache, &generation, eyes[:])
	}
	testing.expect(t, field_tree_cache_settled(&cache, &generation, eyes[:]))
	trees := 0
	for _, region in cache.regions {
		trees += len(region)
	}
	testing.expectf(t, trees > 0, "%d trees in %d regions after %d updates", trees, len(cache.regions), updates)
	old := make([dynamic]Field_Tree_Region, context.temp_allocator)
	for region in cache.regions {
		append(&old, region)
	}
	far := [1]World_Position{World_Position(tree_test_point_from_home(generation, planet, 0, 1060))}
	update_field_tree_cache(&cache, &generation, far[:])
	for region in old {
		testing.expect(t, region not_in cache.regions, "an old region is evicted")
	}
}

@(test)
test_visible_trees_are_capped_nearest_first :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	up := [3]i64{0, UNIT_VECTOR_ONE, 0}
	camera := World_Position{0, metres_to_position_units(8000), 0}
	trees := make([dynamic]Planet_Tree)
	for index in 0 ..< 300 {
		offset := millimetres_to_position_units(400 * (index + 1))
		append(&trees, Planet_Tree{key = {i32(index), 0, 0}, base = camera + {offset, 0, 0}, up = up, scale_percent = 100})
	}
	append(&trees, Planet_Tree{key = {-1, 0, 0}, base = camera + {metres_to_position_units(129), 0, 0}, up = up, scale_percent = 100})
	cache.regions[{0, 0, 0}] = trees
	felled := make(map[Tree_Key]struct{}, context.temp_allocator)
	felled[{0, 0, 0}] = {}
	visible := field_visible_trees(&cache, felled, world_position_to_metres(camera), render_frustum.Frustum{}, 4)
	testing.expect_value(t, len(visible), FIELD_TREE_DRAW_LIMIT)
	keys := make(map[Tree_Key]struct{}, context.temp_allocator)
	for entry in visible {
		keys[entry.tree.key] = {}
	}
	testing.expect(t, Tree_Key{0, 0, 0} not_in keys, "the felled tree is left out")
	testing.expect(t, Tree_Key{-1, 0, 0} not_in keys, "the tree past the draw distance is left out")
	for index in 1 ..= FIELD_TREE_DRAW_LIMIT {
		testing.expectf(t, Tree_Key{i32(index), 0, 0} in keys, "the near tree %d is drawn", index)
	}
}
