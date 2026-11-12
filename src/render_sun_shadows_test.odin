package game

import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:testing"
import rl "shared:raylib"

// Work item 0328: the sun's shadow cascade, its casters and the shaders'
// comparisons, mirrored on the CPU over maps filled by ray from the
// cascade's basis.

// The shipped desktop row.
sun_shadows_test_row :: proc() -> Sun_Shadows_Row {
	return Sun_Shadows_Row{on = true, map_texels = 2048, radius_metres = 64, caster_reach_metres = 96, tree_limit = 2048}
}

// The point in the light's clip space.
sun_shadow_test_clip :: proc(cascade: Sun_Shadow_Cascade, point: [3]f32) -> [3]f32 {
	return (cascade.view_projection * [4]f32{point.x, point.y, point.z, 1}).xyz
}

// The centre's step in metres as sun_shadow_cascade works it out in f64
// (the cascade's texel_metres is its f32 rounding).
sun_shadow_test_step :: proc(row: Sun_Shadows_Row) -> f64 {
	return SUN_SHADOW_SNAP_TEXELS * 2 * f64(row.radius_metres) / f64(row.map_texels - 2 * SUN_SHADOW_MARGIN_TEXELS - SUN_SHADOW_SNAP_TEXELS)
}

// The light's axes as sun_shadow_cascade builds them in f64: right, up
// and towards the sun.
sun_shadow_test_axes :: proc(toward_sun, path_axis: [3]f32) -> [3][3]f64 {
	sun := linalg.normalize(linalg.array_cast(toward_sun, f64))
	right := linalg.normalize(linalg.cross(-sun, linalg.array_cast(path_axis, f64)))
	return {right, linalg.cross(right, -sun), sun}
}

// The point moved by the distances along the three axes, in f32.
sun_shadow_test_moved :: proc(point: [3]f64, axes: [3][3]f64, distances: [3]f64) -> [3]f32 {
	moved := point
	for axis, index in axes {
		moved += axis * distances[index]
	}
	return linalg.array_cast(moved, f32)
}

// Work item 0348: the eye anywhere in its step, half a step off the
// centre along all three axes at once, keeps the sphere of the radius
// round it SUN_SHADOW_MARGIN_TEXELS texels inside the map, the centre
// stepped from the origin or from an anchor off the lattice.
@(test)
test_the_cascade_covers_the_radius :: proc(t: ^testing.T) {
	row := sun_shadows_test_row()
	texel := 2 * f32(row.radius_metres) / f32(row.map_texels - 2 * SUN_SHADOW_MARGIN_TEXELS - SUN_SHADOW_SNAP_TEXELS)
	step := sun_shadow_test_step(row)
	// A twentieth of a texel, 3 mm, for f32 at 8 km.
	clear_share := (f32(SUN_SHADOW_MARGIN_TEXELS) - 0.05) / (f32(row.map_texels) / 2)
	for up in ([2][3]f32{{0, 1, 0}, linalg.normalize([3]f32{1, 2, 3})}) {
		for fraction in ([3]f64{0.1, 0.25, 0.4}) {
			sun, path := field_sun_world_direction(fraction, up), field_sun_path_world_axis(up)
			axes := sun_shadow_test_axes(sun, path)
			start := up * 8000
			for anchor in ([2][3]f64{{}, linalg.array_cast(start + {0.3, -0.7, 1.1}, f64)}) {
				lattice := sun_shadow_cascade(start, sun, path, row, anchor).precise_centre
				for corner in 0 ..< 8 {
					sides := [3]f64{corner & 1 == 0 ? -1 : 1, corner & 2 == 0 ? -1 : 1, corner & 4 == 0 ? -1 : 1}
					eye := sun_shadow_test_moved(lattice, axes, sides * 0.499 * step)
					cascade := sun_shadow_cascade(eye, sun, path, row, anchor)
					testing.expectf(t, abs(cascade.texel_metres - texel) < 1e-6, "texel %v, expected %v", cascade.texel_metres, texel)
					testing.expectf(t, abs(cascade.half_size - f32(row.map_texels) * texel / 2) < 1e-4, "half size %v", cascade.half_size)
					testing.expectf(t, linalg.length(cascade.precise_centre - lattice) < 1e-9, "the eye's step moved off the lattice point by %v", cascade.precise_centre - lattice)
					for axis in ([3][3]f32{cascade.right, cascade.up, cascade.toward_sun}) {
						for side in ([2]f32{-1, 1}) {
							clip := sun_shadow_test_clip(cascade, eye + axis * (side * f32(row.radius_metres)))
							for component in 0 ..< 3 {
								testing.expectf(t, abs(clip[component]) <= 1 - clear_share, "up %v fraction %v corner %d: %v lands at %v", up, fraction, corner, axis * side, clip)
							}
						}
					}
				}
			}
		}
	}
}

@(test)
test_the_cascade_moves_in_whole_steps_from_its_anchor :: proc(t: ^testing.T) {
	row := sun_shadows_test_row()
	up := linalg.normalize([3]f32{1, 2, 3})
	sun, path := field_sun_world_direction(0.15, up), field_sun_path_world_axis(up)
	axes := sun_shadow_test_axes(sun, path)
	start := up * 8000
	for anchor in ([2][3]f64{linalg.array_cast(start, f64), {}}) {
		first := sun_shadow_cascade(start, sun, path, row, anchor)
		centre := first.precise_centre
		step := sun_shadow_test_step(row)
		nudged := sun_shadow_cascade(sun_shadow_test_moved(centre, axes, {0.4 * step, 0, 0}), sun, path, row, anchor)
		testing.expectf(t, linalg.length(nudged.precise_centre - centre) < 1e-9, "0.4 step moved the centre by %v", nudged.precise_centre - centre)
		for column in 0 ..< 4 {
			for line in 0 ..< 4 {
				testing.expectf(t, abs(nudged.view_projection[line, column] - first.view_projection[line, column]) < 1e-5, "0.4 step moved the view projection")
			}
		}
		stepped := sun_shadow_cascade(sun_shadow_test_moved(centre, axes, {0.6 * step, 0, 0}), sun, path, row, anchor)
		testing.expectf(t, linalg.length(stepped.precise_centre - (centre + axes[0] * step)) < 1e-9, "0.6 step moved the centre by %v", stepped.precise_centre - centre)
		along := sun_shadow_cascade(sun_shadow_test_moved(centre, axes, {0, 0, 5}), sun, path, row, anchor)
		expected := centre + axes[2] * (math.round(5 / step) * step)
		testing.expectf(t, linalg.length(along.precise_centre - expected) < 1e-9, "5 m along the sun moved the centre by %v", along.precise_centre - centre)
		for index in 0 ..< 100 {
			// A fixed spread of eyes within 50 m of the start.
			offset := [3]f32{f32((index * 37) % 101) - 50, f32((index * 61) % 97) - 48, f32((index * 13) % 89) - 44} * 0.5
			eye := start + offset
			cascade := sun_shadow_cascade(eye, sun, path, row, anchor)
			for axis in axes {
				along_axis := linalg.dot(cascade.precise_centre - anchor, axis)
				testing.expectf(t, abs(along_axis - math.round(along_axis / step) * step) < 1e-9, "eye %v: %v m from the anchor along an axis is no whole step", eye, along_axis)
			}
			testing.expectf(t, sun_shadow_eye_in_step(cascade, eye), "eye %v is outside its step", eye)
		}
	}
}

@(test)
test_a_turn_keeps_the_texel_corner_at_the_anchor :: proc(t: ^testing.T) {
	row := sun_shadows_test_row()
	up := [3]f32{0, 1, 0}
	eye := [3]f32{3.25, 8001.5, -2.75}
	anchor := linalg.array_cast(eye, f64)
	sun, path := field_sun_world_direction(0.15, up), field_sun_path_world_axis(up)
	turned := sun_shadow_test_turned(sun, path, 1.5e-3 * math.DEG_PER_RAD)
	before := sun_shadow_cascade(eye, sun, path, row, anchor)
	after := sun_shadow_cascade(eye, turned, path, row, anchor)
	testing.expectf(t, linalg.length(before.precise_centre - anchor) < 1e-9, "the centre left the anchor by %v", before.precise_centre - anchor)
	testing.expectf(t, linalg.length(after.precise_centre - anchor) < 1e-9, "the turned centre left the anchor by %v", after.precise_centre - anchor)
	testing.expect(t, after.toward_sun != before.toward_sun, "the turn turned the light")
}

@(test)
test_the_turn_limit_holds_a_steps_hop_to_a_quarter_texel :: proc(t: ^testing.T) {
	row := sun_shadows_test_row()
	up := [3]f32{0, 1, 0}
	texel := sun_shadow_cascade({0, 8000, 0}, up, {0, 0, 1}, row).texel_metres
	for degrees in 1 ..= 89 {
		elevation := f64(degrees) * math.RAD_PER_DEG
		sun := [3]f32{f32(math.cos(elevation)), f32(math.sin(elevation)), 0}
		sine := f64(sun.y) / linalg.length(linalg.array_cast(sun, f64))
		hop := SUN_SHADOW_STEP_CASTER_METRES / sine * sun_shadow_turn_limit(sun, up, texel)
		testing.expectf(t, abs(hop - SUN_SHADOW_STEP_TEXELS * f64(texel)) < 1e-9, "%d degrees: a step's hop is %v m", degrees, hop)
	}
	testing.expect_value(t, sun_shadow_turn_limit({1, 0, 0}, up, texel), 0)
	below := f64(-5) * math.RAD_PER_DEG
	testing.expect_value(t, sun_shadow_turn_limit({f32(math.cos(below)), f32(math.sin(below)), 0}, up, texel), 0)
	tick := math.TAU / 72000
	noon := sun_shadow_turn_limit(sun_direction(NOON_FRACTION), up, texel) / tick
	testing.expectf(t, noon > 17 && noon < 18, "noon turns the map every %v ticks", noon)
	low := f64(10) * math.RAD_PER_DEG
	evening := sun_shadow_turn_limit({f32(math.cos(low)), f32(math.sin(low)), 0}, up, texel) / tick
	testing.expectf(t, evening > 3 && evening < 4, "a 10 degree sun turns the map every %v ticks", evening)
}

@(test)
test_the_turn_angle_measures_small_turns :: proc(t: ^testing.T) {
	for angle in ([4]f64{1e-5, 1e-4, 1.5e-3, 0.1}) {
		turned := [3]f32{f32(math.cos(angle)), f32(math.sin(angle)), 0}
		measured := sun_shadow_turn_angle({1, 0, 0}, turned)
		testing.expectf(t, abs(measured - angle) < 2e-7, "a turn of %v measures %v", angle, measured)
	}
	same := linalg.normalize([3]f32{1, 2, 3})
	testing.expect_value(t, sun_shadow_turn_angle(same, same), 0)
}

// A kept map drawn at noon round an eye 8 km up, and a view that offers
// it nothing new.
sun_shadow_test_kept :: proc() -> (kept: Sun_Shadow_Kept, view: Sun_Shadow_View) {
	row := sun_shadows_test_row()
	up := [3]f32{0, 1, 0}
	view = Sun_Shadow_View {
		eye         = {0.5, 8001.7, -0.25},
		toward_sun  = field_sun_world_direction(0.15, up),
		path_axis   = field_sun_path_world_axis(up),
		up          = up,
		row         = row,
		trees_drawn = true,
		revisions   = {meshes = 3, selection = 5, trees = 7, frames = 11, models = 13},
	}
	key := Sun_Shadow_Kept_Key {
		cascade     = sun_shadow_cascade(view.eye, view.toward_sun, view.path_axis, row, linalg.array_cast(view.eye, f64)),
		toward_sun  = view.toward_sun,
		path_axis   = view.path_axis,
		row         = row,
		trees_drawn = true,
		revisions   = view.revisions,
	}
	return Sun_Shadow_Kept{state = .Ready, drawn = true, key = key}, view
}

// The view's eye moved along the kept cascade's axes by the steps.
sun_shadow_test_eye_in_steps :: proc(kept: Sun_Shadow_Kept, steps: [3]f64) -> [3]f32 {
	step := sun_shadow_test_step(kept.key.row)
	return sun_shadow_test_moved(kept.key.cascade.precise_centre, sun_shadow_test_axes(kept.key.toward_sun, kept.key.path_axis), steps * step)
}

@(test)
test_a_kept_map_is_kept_while_nothing_changed :: proc(t: ^testing.T) {
	kept, view := sun_shadow_test_kept()
	testing.expect_value(t, sun_shadow_kept_step(kept, view), Sun_Shadow_Kept_Step.Keep)
	limit := sun_shadow_turn_limit(view.toward_sun, view.up, kept.key.cascade.texel_metres)
	view.toward_sun = sun_shadow_test_turned(view.toward_sun, view.path_axis, f32(0.9 * limit * math.DEG_PER_RAD))
	view.eye = sun_shadow_test_eye_in_steps(kept, {0.45, -0.45, 0.45})
	testing.expect_value(t, sun_shadow_kept_step(kept, view), Sun_Shadow_Kept_Step.Keep)
}

@(test)
test_a_kept_map_never_drawn_is_turned :: proc(t: ^testing.T) {
	kept, view := sun_shadow_test_kept()
	kept.drawn = false
	testing.expect_value(t, sun_shadow_kept_step(kept, view), Sun_Shadow_Kept_Step.Turn)
}

@(test)
test_a_changed_row_turns_the_kept_map :: proc(t: ^testing.T) {
	changes := [4]proc(row: ^Sun_Shadows_Row) {
		proc(row: ^Sun_Shadows_Row) {row.map_texels = 1024},
		proc(row: ^Sun_Shadows_Row) {row.radius_metres = 48},
		proc(row: ^Sun_Shadows_Row) {row.caster_reach_metres = 64},
		proc(row: ^Sun_Shadows_Row) {row.tree_limit = 512},
	}
	for change, index in changes {
		kept, view := sun_shadow_test_kept()
		change(&view.row)
		testing.expectf(t, sun_shadow_kept_step(kept, view) == .Turn, "change %d did not turn the map", index)
	}
}

@(test)
test_the_sun_past_the_turn_limit_turns_the_kept_map :: proc(t: ^testing.T) {
	kept, view := sun_shadow_test_kept()
	limit := sun_shadow_turn_limit(view.toward_sun, view.up, kept.key.cascade.texel_metres)
	turned := view
	turned.toward_sun = sun_shadow_test_turned(view.toward_sun, view.path_axis, f32(1.1 * limit * math.DEG_PER_RAD))
	testing.expect_value(t, sun_shadow_kept_step(kept, turned), Sun_Shadow_Kept_Step.Turn)
	// A walk across the planet turns the up, and the sky with it, about an
	// axis square to the up and the sun, so the world's sun turns as much.
	pivot := linalg.normalize(linalg.cross(view.up, view.toward_sun))
	walked := view
	walked.up = sun_shadow_test_turned(view.up, pivot, f32(1.1 * limit * math.DEG_PER_RAD))
	walked.toward_sun = field_sun_world_direction(0.15, walked.up)
	walked.path_axis = field_sun_path_world_axis(walked.up)
	turn := sun_shadow_turn_angle(view.toward_sun, walked.toward_sun)
	testing.expectf(t, abs(turn / limit - 1.1) < 0.01, "the walk turned the sun %v limits", turn / limit)
	testing.expect_value(t, sun_shadow_kept_step(kept, walked), Sun_Shadow_Kept_Step.Turn)
}

@(test)
test_an_eye_past_half_a_step_recentres_the_kept_map :: proc(t: ^testing.T) {
	for axis in 0 ..< 3 {
		kept, view := sun_shadow_test_kept()
		steps: [3]f64
		steps[axis] = 0.51
		view.eye = sun_shadow_test_eye_in_steps(kept, steps)
		testing.expectf(t, sun_shadow_kept_step(kept, view) == .Recentre, "0.51 step along axis %d did not recentre the map", axis)
	}
}

@(test)
test_a_frame_table_change_recentres_the_kept_map :: proc(t: ^testing.T) {
	kept, view := sun_shadow_test_kept()
	view.revisions.frames += 1
	testing.expect_value(t, sun_shadow_kept_step(kept, view), Sun_Shadow_Kept_Step.Recentre)
}

@(test)
test_a_model_reload_recentres_the_kept_map :: proc(t: ^testing.T) {
	kept, view := sun_shadow_test_kept()
	view.revisions.models += 1
	testing.expect_value(t, sun_shadow_kept_step(kept, view), Sun_Shadow_Kept_Step.Recentre)
}

@(test)
test_trees_turned_on_or_off_recentre_the_kept_map :: proc(t: ^testing.T) {
	kept, view := sun_shadow_test_kept()
	view.trees_drawn = false
	testing.expect_value(t, sun_shadow_kept_step(kept, view), Sun_Shadow_Kept_Step.Recentre)
	kept.key.trees_drawn = false
	view.trees_drawn = true
	testing.expect_value(t, sun_shadow_kept_step(kept, view), Sun_Shadow_Kept_Step.Recentre)
}

@(test)
test_moved_meshes_selection_or_trees_compare_the_fingerprints :: proc(t: ^testing.T) {
	for counter in 0 ..< 3 {
		kept, view := sun_shadow_test_kept()
		switch counter {
		case 0:
			view.revisions.meshes += 1
		case 1:
			view.revisions.selection ~= 0xFFFF
		case 2:
			view.revisions.trees += 1
		}
		testing.expectf(t, sun_shadow_kept_step(kept, view) == .Compare, "counter %d did not ask for the fingerprints", counter)
	}
}

@(test)
test_the_kept_cascade_turns_on_the_view_and_recentres_on_the_held :: proc(t: ^testing.T) {
	kept, view := sun_shadow_test_kept()
	step := sun_shadow_test_step(view.row)
	limit := sun_shadow_turn_limit(view.toward_sun, view.up, kept.key.cascade.texel_metres)
	view.toward_sun = sun_shadow_test_turned(view.toward_sun, view.path_axis, f32(2 * limit * math.DEG_PER_RAD))
	view.eye = sun_shadow_test_eye_in_steps(kept, {1.6, -0.2, 2.7})
	turned := sun_shadow_kept_cascade(kept, view, .Turn)
	fresh := sun_shadow_cascade(view.eye, view.toward_sun, view.path_axis, view.row, kept.key.cascade.precise_centre)
	testing.expect_value(t, turned.toward_sun, fresh.toward_sun)
	testing.expect(t, turned.toward_sun != kept.key.cascade.toward_sun, "a Turn takes the frame's sun")
	recentred := sun_shadow_kept_cascade(kept, view, .Recentre)
	testing.expect_value(t, recentred.right, kept.key.cascade.right)
	testing.expect_value(t, recentred.up, kept.key.cascade.up)
	testing.expect_value(t, recentred.toward_sun, kept.key.cascade.toward_sun)
	axes := sun_shadow_test_axes(kept.key.toward_sun, kept.key.path_axis)
	moved := recentred.precise_centre - kept.key.cascade.precise_centre
	for axis, index in axes {
		along := linalg.dot(moved, axis) / step
		testing.expectf(t, abs(along - math.round(along)) < 1e-9, "the recentre moved %v steps along axis %d", along, index)
	}
	testing.expectf(t, abs(linalg.dot(moved, axes[0]) / step - 2) < 1e-9, "the recentre moved %v steps along the right", linalg.dot(moved, axes[0]) / step)
	kept.drawn = false
	undrawn := sun_shadow_kept_cascade(kept, view, .Turn)
	testing.expect_value(t, undrawn.precise_centre, linalg.array_cast(view.eye, f64))
}

@(test)
test_casters_toward_the_sun_cast_within_the_reach :: proc(t: ^testing.T) {
	row := sun_shadows_test_row()
	up := [3]f32{0, 1, 0}
	cascade := sun_shadow_cascade(up * 8000, field_sun_world_direction(0.05, up), field_sun_path_world_axis(up), row)
	box_at := proc(cascade: Sun_Shadow_Cascade, middle: [3]f32) -> bool {
		return sun_shadow_box_casts(cascade, middle - 1, middle + 1)
	}
	sun, radius, half, reach := cascade.toward_sun, cascade.radius_metres, cascade.half_size, cascade.reach_metres
	testing.expect(t, box_at(cascade, cascade.centre), "the eye's box casts")
	testing.expect(t, box_at(cascade, cascade.centre + sun * (radius + 50)), "a box 50 m sunward of the sphere casts")
	testing.expect(t, !box_at(cascade, cascade.centre + sun * (half + reach + 10)), "a box past the reach does not cast")
	testing.expect(t, !box_at(cascade, cascade.centre - sun * (half + 10)), "a box behind the far side does not cast")
	testing.expect(t, !box_at(cascade, cascade.centre + cascade.right * (half + 10)), "a box beside the map does not cast")
	testing.expect(t, !box_at(cascade, cascade.centre - cascade.up * (half + 10)), "a box below the map does not cast")
	testing.expect(t, box_at(cascade, cascade.centre + cascade.right * half), "a box straddling the side casts")
}

// A fresh casting selection, as a scan of the tiles each frame would make
// it: a pass gathered in the cascade itself, then cut. Its keys sorted
// with their instances (temp allocator), the pass released.
fresh_shadow_trees :: proc(cache: ^Field_Tree_Cache, cascade: Sun_Shadow_Cascade, eye: [3]f32, extent_metres: f32, felled: map[Tree_Key]struct{}, limit, species_count: int) -> (keys: []Tree_Key, instances: []matrix[4, 4]f32) {
	pass: Tree_Pass
	defer release_tree_pass(&pass)
	gather_shadow_tree_candidates(&pass, cache, grown_sun_shadow_cascade(cascade, 0), extent_metres, felled, species_count)
	cut_shadow_trees(&pass, cascade, eye, extent_metres, limit)
	return sorted_tree_selection(pass.candidates[:], pass.next[:])
}

@(test)
test_shadow_trees_are_the_nearest_inside_the_casters_box :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	camera := [3]f32{0, 8000, 0}
	near := make([]f32, 40, context.temp_allocator)
	for &offset, index in near {
		offset = f32(index + 1)
	}
	cache.tiles[{0, 0, 0}] = tree_draw_test_tile(camera, near, 0)
	far := [2]f32{300, 301}
	cache.tiles[{1, 0, 0}] = tree_draw_test_tile(camera, far[:], 1000)
	felled := make(map[Tree_Key]struct{}, context.temp_allocator)
	felled[{0, 0, 0}] = {}
	up := [3]f32{0, 1, 0}
	cascade := sun_shadow_cascade(camera, field_sun_world_direction(0.25, up), field_sun_path_world_axis(up), sun_shadows_test_row())
	_, trees := fresh_shadow_trees(&cache, cascade, camera, 4, felled, 1000, 1)
	testing.expect_value(t, len(trees), 39)
	for tree in trees {
		offset := tree_instance_base(tree).x - camera.x
		testing.expect(t, offset > 1.5, "the felled tree is left out")
		testing.expect(t, offset < 100, "no tree past the casters' box")
	}
	_, trees = fresh_shadow_trees(&cache, cascade, camera, 4, felled, 10, 1)
	testing.expect_value(t, len(trees), 10)
	for tree in trees {
		offset := tree_instance_base(tree).x - camera.x
		testing.expectf(t, offset > 1.5 && offset < 11.5, "the cut keeps the nearest, not %v m", offset)
	}
	_, trees = fresh_shadow_trees(&cache, cascade, camera, 4, felled, 0, 1)
	testing.expect_value(t, len(trees), 0)
}

// Work item 0346: the view's casting trees, gathered in a grown box and
// cut each step, equal a fresh selection's at every step of a walk under
// a sun turning faster than the day's, across a tree felled.
@(test) // slow
test_the_cached_shadow_trees_equal_a_fresh_cut_along_a_walk_under_a_turning_sun :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	start := [3]f32{0, 8000, 0}
	tree_selection_test_forest(&cache, start, {99, 99, 99})
	cache.config = Field_Trees_Row{near_metres = 48}
	row := sun_shadows_test_row()
	row.tree_limit = 400
	up := [3]f32{0, 1, 0}
	axis := field_sun_path_world_axis(up)
	felled := make(map[Tree_Key]struct{})
	defer delete(felled)
	view := &cache.views[0]
	capped := false
	for step in 0 ..< 240 {
		defer free_all(context.temp_allocator)
		eye := start + {0.25 * f32(step), 0, 0}
		cascade := sun_shadow_cascade(eye, field_sun_world_direction(0.1 + 0.0004 * f64(step), up), axis, row)
		felled_key := Tree_Key{-1000, -1000, -1000}
		if step == 120 {
			felled_key = view.shadow.candidates[view.shadow.selected[0]].key
			felled[felled_key] = {}
			apply_felled_field_trees(&cache, felled)
		}
		update_shadow_trees(&cache, view, cascade, eye, 4, felled, row.tree_limit, 3)
		keys, instances := fresh_shadow_trees(&cache, cascade, eye, 4, felled, row.tree_limit, 3)
		cached_keys, cached_instances := sorted_tree_selection(view.shadow.candidates[:], view.shadow.selected[:])
		testing.expectf(t, slice.equal(cached_keys, keys), "step %d: %d cached trees against %d fresh", step, len(cached_keys), len(keys))
		testing.expectf(t, slice.equal(cached_instances, instances), "step %d: the instances differ", step)
		capped ||= len(view.shadow.selected) == row.tree_limit
		if step == 120 {
			_, still := slice.linear_search(cached_keys, felled_key)
			testing.expect(t, !still, "the felled tree is left out")
		}
	}
	testing.expect(t, capped, "the cap binds")
	testing.expectf(t, view.shadow.gathers > 1 && view.shadow.gathers < 40, "%d gathers in 240 steps", view.shadow.gathers)
}

// A plane the test map is filled from: infinite, or a rectangle of
// half_size round point along across and along.
Sun_Shadow_Test_Plane :: struct {
	point, normal, across, along: [3]f64,
	half_size:                    f64,
}

// The map the cast pass would draw of the planes: per texel centre the
// ray from the near plane along -toward_sun, its depth the distance to
// the nearest hit over the box's depth, clamped to 0 to 1 (pressed onto
// the near plane), 1 where nothing is hit.
fill_sun_shadow_test_map :: proc(cascade: Sun_Shadow_Cascade, texels: int, planes: []Sun_Shadow_Test_Plane, allocator := context.allocator) -> []f32 {
	depths := make([]f32, texels * texels, allocator)
	half := f64(cascade.half_size)
	sun := linalg.array_cast(cascade.toward_sun, f64)
	right, up := linalg.array_cast(cascade.right, f64), linalg.array_cast(cascade.up, f64)
	near := linalg.array_cast(cascade.centre, f64) + sun * half
	for row in 0 ..< texels {
		for column in 0 ..< texels {
			x := ((f64(column) + 0.5) / f64(texels) * 2 - 1) * half
			y := ((f64(row) + 0.5) / f64(texels) * 2 - 1) * half
			origin := near + right * x + up * y
			nearest := 2 * half
			for plane in planes {
				facing := -linalg.dot(sun, plane.normal)
				if abs(facing) < 1e-9 {
					continue
				}
				distance := linalg.dot(plane.point - origin, plane.normal) / facing
				hit := origin - sun * distance - plane.point
				if plane.half_size > 0 && (abs(linalg.dot(hit, plane.across)) > plane.half_size || abs(linalg.dot(hit, plane.along)) > plane.half_size) {
					continue
				}
				nearest = min(nearest, distance)
			}
			depths[row * texels + column] = f32(clamp(nearest / (2 * half), 0, 1))
		}
	}
	return depths
}

sun_shadow_test_tap_weight :: proc(index: int, fraction: f32) -> f32 {
	if index == 0 {
		return 1 - fraction
	}
	return index == 3 ? fraction : 1
}

// A test only mirror of sun_shadow_light's comparisons (field.fs and the
// others): 1 for a face turned from the sun, else the receiver moved along
// its normal, through the matrix, biased in depth, and the 4 by 4 taps'
// weighted share lit, texel indices clamped to the map as the clamped
// sampler reads them.
sun_shadow_lit_share :: proc(depths: []f32, frame: Sun_Shadow_Frame, toward_sun, position, normal: [3]f32) -> f32 {
	if linalg.dot(normal, toward_sun) <= 0 {
		return 1
	}
	texels := int(frame.shape.x)
	moved := position + normal * (frame.shape.y * SUN_SHADOW_NORMAL_OFFSET_TEXELS)
	coordinate := (frame.view_projection * [4]f32{moved.x, moved.y, moved.z, 1}).xyz * 0.5 + 0.5
	depth := coordinate.z - SUN_SHADOW_DEPTH_BIAS_TEXELS / frame.shape.x
	texel_position := coordinate.xy * frame.shape.x - 0.5
	base := [2]f32{math.floor(texel_position.x), math.floor(texel_position.y)}
	fraction := texel_position - base
	lit: f32 = 0
	for row in 0 ..< 4 {
		for column in 0 ..< 4 {
			x := clamp(int(base.x) + column - 1, 0, texels - 1)
			y := clamp(int(base.y) + row - 1, 0, texels - 1)
			if depth <= depths[y * texels + x] {
				lit += sun_shadow_test_tap_weight(column, fraction.x) * sun_shadow_test_tap_weight(row, fraction.y)
			}
		}
	}
	return lit / 9
}

// The vector turned by the angle about the unit axis.
sun_shadow_test_turned :: proc(vector, axis: [3]f32, degrees: f32) -> [3]f32 {
	return linalg.quaternion128_mul_vector3(linalg.quaternion_angle_axis_f32(degrees * math.RAD_PER_DEG, axis), vector)
}

@(test) // slow
test_a_lit_slope_does_not_shadow_itself :: proc(t: ^testing.T) {
	row := sun_shadows_test_row()
	up := [3]f32{0, 1, 0}
	eye := up * 8000
	sun := field_sun_world_direction(0.12, up)
	cascade := sun_shadow_cascade(eye, sun, field_sun_path_world_axis(up), row)
	frame := sun_shadow_frame(cascade, 70, row.map_texels, 1)
	radius := f32(row.radius_metres)
	for degrees in ([4]f32{0, 45, 75, 85}) {
		// The face turned from the sun about the light's up.
		normal := sun_shadow_test_turned(sun, cascade.up, degrees)
		across := linalg.normalize(linalg.cross(normal, cascade.up))
		along := linalg.cross(normal, across)
		plane := [1]Sun_Shadow_Test_Plane{{point = linalg.array_cast(eye, f64), normal = linalg.array_cast(normal, f64)}}
		depths := fill_sun_shadow_test_map(cascade, row.map_texels, plane[:])
		defer delete(depths)
		lowest: f32 = 1
		for tilt in ([3]f32{-10, 0, 10}) {
			shading := sun_shadow_test_turned(normal, cascade.up, tilt)
			for u: f32 = -radius; u <= radius; u += 0.73 {
				for v: f32 = -radius; v <= radius; v += 0.79 {
					if u * u + v * v > radius * radius {
						continue
					}
					lowest = min(lowest, sun_shadow_lit_share(depths, frame, sun, eye + across * u + along * v, shading))
				}
			}
		}
		testing.expectf(t, lowest >= 0.98, "a plane %v degrees from the sun reads %v lit at worst", degrees, lowest)
	}
}

@(test) // slow
test_an_occluder_shadows_the_ground_under_it :: proc(t: ^testing.T) {
	row := sun_shadows_test_row()
	ground := [3]f32{0, 8000, 0}
	eye := ground + {0, 1.7, 0}
	height := f32(60 * math.RAD_PER_DEG)
	sun := [3]f32{math.cos(height), math.sin(height), 0}
	cascade := sun_shadow_cascade(eye, sun, {0, 0, 1}, row)
	frame := sun_shadow_frame(cascade, 70, row.map_texels, 1)
	plate := ground + {10, 10, 0}
	planes := [2]Sun_Shadow_Test_Plane {
		{point = linalg.array_cast(ground, f64), normal = {0, 1, 0}},
		{point = linalg.array_cast(plate, f64), normal = {0, 1, 0}, across = {1, 0, 0}, along = {0, 0, 1}, half_size = 5},
	}
	depths := fill_sun_shadow_test_map(cascade, row.map_texels, planes[:])
	defer delete(depths)
	// The plate's shadow: the plate moved down 10 m along -sun.
	shadow := plate - sun * (10 / sun.y)
	share := sun_shadow_lit_share(depths, frame, sun, shadow, {0, 1, 0})
	testing.expectf(t, share <= 0.01, "the ground under the plate's shadow reads %v lit", share)
	for offset in ([4][3]f32{{6, 0, 0}, {-6, 0, 0}, {0, 0, 6}, {0, 0, -6}}) {
		share = sun_shadow_lit_share(depths, frame, sun, shadow + offset, {0, 1, 0})
		testing.expectf(t, share >= 0.99, "the ground a metre past the shadow's edge at %v reads %v lit", offset, share)
	}
}

@(test)
test_the_shadow_map_is_released_when_off_or_resized :: proc(t: ^testing.T) {
	for state in Sun_Shadow_State {
		shadows := Sun_Shadow_Renderer{state = state, texels = 2048}
		expected := state != .Unloaded
		testing.expect(t, !sun_shadow_map_stale(shadows, true, 2048), "a map on at its size stays")
		testing.expect_value(t, sun_shadow_map_stale(shadows, false, 2048), expected)
		testing.expect_value(t, sun_shadow_map_stale(shadows, true, 1024), expected)
	}
}

@(test)
test_the_shadow_slot_follows_the_map :: proc(t: ^testing.T) {
	first, second: [rl.MaterialMapIndex]rl.MaterialMap
	first[.ALBEDO].texture.id, second[.ALBEDO].texture.id = 7, 8
	materials := [3]rl.Material{{maps = &first[.ALBEDO]}, {}, {maps = &second[.ALBEDO]}}
	set_sun_shadow_map_slot(materials[:], rl.Texture2D{id = 42, width = 2048, height = 2048})
	testing.expect_value(t, first[SUN_SHADOW_MAP_SLOT].texture.id, 42)
	testing.expect_value(t, second[SUN_SHADOW_MAP_SLOT].texture.id, 42)
	testing.expect_value(t, first[.ALBEDO].texture.id, 7)
	testing.expect_value(t, second[.ALBEDO].texture.id, 8)
	set_sun_shadow_map_slot(materials[:], {})
	testing.expect_value(t, first[SUN_SHADOW_MAP_SLOT].texture.id, 0)
	testing.expect_value(t, second[SUN_SHADOW_MAP_SLOT].texture.id, 0)
	testing.expect_value(t, first[.ALBEDO].texture.id, 7)
	testing.expect_value(t, SUN_SHADOW_SAMPLER_LOCATION, int(rl.ShaderLocationIndex.MAP_NORMAL))
}

@(test)
test_the_shadow_frame_carries_the_fade :: proc(t: ^testing.T) {
	up := [3]f32{0, 1, 0}
	cascade := sun_shadow_cascade(up * 8000, field_sun_world_direction(0.25, up), field_sun_path_world_axis(up), sun_shadows_test_row())
	frame := sun_shadow_frame(cascade, 70, 2048, 5)
	testing.expect_value(t, frame.shape, [4]f32{2048, cascade.texel_metres, 48, 64})
	testing.expect_value(t, frame.strength, f32(0.7))
	testing.expect_value(t, frame.texture, u32(5))
	testing.expect_value(t, frame.view_projection, cascade.view_projection)
}

// Decision 3 of the item: the cast pass draws only the entities whose box
// (the footprint up to the model's top, a cell wider each way) meets the
// casters' box, under the pod's transform; the scene's draw keeps every
// one.
@(test)
test_the_cast_pass_leaves_out_entities_outside_the_casters_box :: proc(t: ^testing.T) {
	minimum, maximum := sun_shadow_entity_box(1, {0, 0, 0}, {2, 1, 3}, 2.5)
	testing.expect_value(t, minimum, [3]f32{-1, -1, -1})
	testing.expect_value(t, maximum, [3]f32{3, 3.5, 4})
	// A quarter turn about the up at half a metre a cell, moved.
	turned := matrix[4, 4]f32{
		0, 0, 0.5, 10,
		0, 0.5, 0, 20,
		-0.5, 0, 0, 30,
		0, 0, 0, 1,
	}
	minimum, maximum = sun_shadow_entity_box(turned, {0, 0, 0}, {2, 1, 3}, 1)
	testing.expect_value(t, minimum, [3]f32{9.5, 19.5, 28.5})
	testing.expect_value(t, maximum, [3]f32{12, 21, 30.5})

	eye := [3]f32{0, 8000, 0}
	casters := Sun_Shadow_Casters {
		cascade   = sun_shadow_cascade(eye, {0, 1, 0}, {0, 0, 1}, sun_shadows_test_row()),
		transform = linalg.matrix4_translate_f32(eye),
	}
	entities: Entities
	common := Entity_Common{frame = BLOCK_FRAME, size = {1, 1, 1}}
	frame := Model_Frame{}
	testing.expect(t, model_frame_draws_entity(frame, &entities, {}, common), "the scene's draw keeps every entity")
	common.origin = {500, 0, 0}
	testing.expect(t, model_frame_draws_entity(frame, &entities, {}, common), "the scene's draw keeps a far entity")
	frame.casters = &casters
	testing.expect(t, !model_frame_draws_entity(frame, &entities, {}, common), "the cast pass leaves out an entity 500 m off")
	common.origin = {0, 0, 0}
	testing.expect(t, model_frame_draws_entity(frame, &entities, {}, common), "the cast pass draws the entity at the eye")
	common.origin = {64, 0, 0}
	testing.expect(t, model_frame_draws_entity(frame, &entities, {}, common), "the cast pass draws an entity straddling the map's side")
	common.origin = {67, 0, 0}
	testing.expect(t, !model_frame_draws_entity(frame, &entities, {}, common), "the cast pass leaves out an entity past the map's side")
}

// A node's render as the renderer would hold it, without meshes, its
// draw box and its terrain box (0349) its cube at 1000 mm.
sun_shadow_test_render :: proc(node: Field_Node, terrain_hash: u64, has_mesh := true) -> Field_Node_Render {
	origin := field_node_origin_metres(node, 1000)
	far := origin + f32(field_node_samples(node.level))
	return Field_Node_Render{has_mesh = has_mesh, origin = origin, terrain_hash = terrain_hash, minimum = origin, maximum = far, terrain_minimum = origin, terrain_maximum = far}
}

// Work item 0348: the terrain's fingerprint moves with what the cascade's
// casters draw and with nothing else.
@(test)
test_the_terrain_fingerprint_follows_the_casting_nodes :: proc(t: ^testing.T) {
	renderer := Field_Renderer{spacing_millimetres = 1000}
	defer delete(renderer.meshes)
	// A holds the eye 8 km up y, B lies 2 km along x, W beside A has no
	// terrain mesh.
	a := Field_Node{level = 0, coordinate = {0, 250, 0}}
	b := Field_Node{level = 0, coordinate = {62, 250, 0}}
	w := Field_Node{level = 0, coordinate = {1, 250, 0}}
	renderer.meshes[a] = sun_shadow_test_render(a, 101)
	renderer.meshes[b] = sun_shadow_test_render(b, 202)
	renderer.meshes[w] = sun_shadow_test_render(w, 303, false)
	up := [3]f32{0, 1, 0}
	cascade := sun_shadow_cascade({16, 8016, 16}, field_sun_world_direction(NOON_FRACTION, up), field_sun_path_world_axis(up), sun_shadows_test_row())
	selection := [3]Field_Node{a, b, w}
	start := sun_shadow_terrain_fingerprint(&renderer, cascade, selection[:])
	reordered := [3]Field_Node{w, b, a}
	testing.expect_value(t, sun_shadow_selection_hash(nil), 0)
	testing.expect(t, sun_shadow_selection_hash(reordered[:]) != sun_shadow_selection_hash(selection[:]), "a reordered selection asks for the fingerprint")
	testing.expect_value(t, sun_shadow_terrain_fingerprint(&renderer, cascade, reordered[:]), start)
	renderer.meshes[b] = sun_shadow_test_render(b, 999)
	testing.expect_value(t, sun_shadow_terrain_fingerprint(&renderer, cascade, selection[:]), start)
	delete_key(&renderer.meshes, b)
	testing.expect_value(t, sun_shadow_terrain_fingerprint(&renderer, cascade, selection[:]), start)
	renderer.meshes[w] = sun_shadow_test_render(w, 404, false)
	testing.expect_value(t, sun_shadow_terrain_fingerprint(&renderer, cascade, selection[:]), start)
	// A wave remesh: the node set again with the same terrain hash.
	renderer.meshes[a] = sun_shadow_test_render(a, 101)
	testing.expect_value(t, sun_shadow_terrain_fingerprint(&renderer, cascade, selection[:]), start)
	renderer.meshes[a] = sun_shadow_test_render(a, 102)
	testing.expect(t, sun_shadow_terrain_fingerprint(&renderer, cascade, selection[:]) != start, "an edit of the eye's node changes it")
	renderer.meshes[a] = sun_shadow_test_render(a, 101)
	without := [2]Field_Node{b, w}
	testing.expect(t, sun_shadow_terrain_fingerprint(&renderer, cascade, without[:]) != start, "the eye's node out of the selection changes it")
	delete_key(&renderer.meshes, a)
	testing.expect(t, sun_shadow_terrain_fingerprint(&renderer, cascade, selection[:]) != start, "the eye's node unloaded changes it")
}

// Work item 0349: a node casts by its terrain box, not by its draw box,
// so a water or a cover remesh moving only the draw box neither adds nor
// drops a caster.
@(test)
test_the_casters_read_the_terrain_box :: proc(t: ^testing.T) {
	renderer := Field_Renderer{spacing_millimetres = 1000}
	defer delete(renderer.meshes)
	// A holds the eye 8 km up y, B lies 2 km along x.
	a := Field_Node{level = 0, coordinate = {0, 250, 0}}
	b := Field_Node{level = 0, coordinate = {62, 250, 0}}
	renderer.meshes[a] = sun_shadow_test_render(a, 101)
	renderer.meshes[b] = sun_shadow_test_render(b, 202)
	up := [3]f32{0, 1, 0}
	cascade := sun_shadow_cascade({16, 8016, 16}, field_sun_world_direction(NOON_FRACTION, up), field_sun_path_world_axis(up), sun_shadows_test_row())
	selection := [2]Field_Node{a, b}
	cube := sun_shadow_terrain_fingerprint(&renderer, cascade, selection[:])
	_, casts := sun_shadow_node_casts(&renderer, cascade, a)
	testing.expect(t, casts, "the eye's node casts")
	// B's water or cover reaching the eye: its draw box from A's origin to
	// its own far corner.
	reaching := renderer.meshes[b]
	reaching.minimum = renderer.meshes[a].origin
	renderer.meshes[b] = reaching
	_, casts = sun_shadow_node_casts(&renderer, cascade, b)
	testing.expect(t, !casts, "B's draw box reaching the eye adds no caster")
	testing.expect_value(t, sun_shadow_terrain_fingerprint(&renderer, cascade, selection[:]), cube)
	moved := renderer.meshes[a]
	moved.terrain_minimum += {2000, 0, 0}
	moved.terrain_maximum += {2000, 0, 0}
	renderer.meshes[a] = moved
	_, casts = sun_shadow_node_casts(&renderer, cascade, a)
	testing.expect(t, !casts, "A's terrain box 2 km off casts nothing, its draw box holding the eye")
}

// Work item 0348 on 0346's views: the casting trees updated on a held
// cascade (as a kept map's Compare updates them) gather again, which asks
// the kept map to be drawn again, only for a change of the tiles in the
// casters' box grown by the margin.
@(test)
test_the_kept_trees_gather_again_only_for_a_change_in_the_casters_box :: proc(t: ^testing.T) {
	cache: Field_Tree_Cache
	defer destroy_field_tree_cache(&cache)
	cache.cells = 1000
	cache.config = Field_Trees_Row{near_metres = 48}
	camera := [3]f32{0, 8000, 0}
	near := make([]f32, 40, context.temp_allocator)
	for &offset, index in near {
		offset = f32(index + 1)
	}
	far := [1]f32{3000}
	cache.tiles[{0, 0, 0}] = tree_draw_test_tile(camera, near, 0)
	cache.tiles[{1, 0, 0}] = tree_draw_test_tile(camera, far[:], 1000)
	up := [3]f32{0, 1, 0}
	cascade := sun_shadow_cascade(camera, field_sun_world_direction(NOON_FRACTION, up), field_sun_path_world_axis(up), sun_shadows_test_row())
	update := proc(cache: ^Field_Tree_Cache, cascade: Sun_Shadow_Cascade) -> int {
		update_shadow_trees(cache, &cache.views[0], cascade, cascade.centre, 4, nil, 2048, 1)
		return cache.views[0].shadow.gathers
	}
	gathers := update(&cache, cascade)
	testing.expect_value(t, len(cache.views[0].shadow.selected), 40)
	revision := cache.revision
	testing.expect(t, drop_field_tree_key(&cache, {1000, 0, 0}), "the far key drops")
	testing.expect(t, cache.revision != revision, "a drop moves the cache's revision")
	testing.expect_value(t, update(&cache, cascade), gathers)
	insert_field_tree_tile(&cache, {3, 0, 0}, tree_draw_test_tile(camera, far[:], 3000))
	testing.expect_value(t, update(&cache, cascade), gathers)
	revision = cache.revision
	insert_field_tree_tile(&cache, {0, 0, 1}, tree_draw_test_tile(camera, nil, 4000))
	testing.expect_value(t, cache.revision, revision)
	testing.expect_value(t, update(&cache, cascade), gathers)
	testing.expect(t, drop_field_tree_key(&cache, {5, 0, 0}), "a key 6 m off drops")
	dropped := update(&cache, cascade)
	testing.expect(t, dropped > gathers, "a felled tree in the box gathers again")
	testing.expect_value(t, len(cache.views[0].shadow.selected), 39)
	evict_field_tree_tile(&cache, {0, 0, 0})
	testing.expect(t, update(&cache, cascade) > dropped, "the eye's tile leaving gathers again")
	testing.expect_value(t, len(cache.views[0].shadow.selected), 0)
}

@(test)
test_machines_split_into_still_and_moving_casters :: proc(t: ^testing.T) {
	chest := Machine{kind = .Chest}
	furnace := Machine{kind = .Furnace}
	furnace.motion.kind = .Glow
	assembler := Machine{kind = .Crafting_Machine}
	assembler.motion.kind = .Spin
	hatch := Machine{kind = .Hatch}
	hatch.motion.kind = .Slide
	testing.expect(t, !sun_shadow_entity_moves(.Chest, chest), "a chest stands still")
	testing.expect(t, !sun_shadow_entity_moves(.Furnace, furnace), "a furnace's glow moves nothing")
	testing.expect(t, sun_shadow_entity_moves(.Assembler, assembler), "a spinning part moves")
	testing.expect(t, sun_shadow_entity_moves(.Foundation, hatch), "a hatch's door moves")
	for kind in ([3]Entity_Kind{.Inserter, .Drill, .Launch_Pad}) {
		testing.expectf(t, sun_shadow_entity_moves(kind, chest), "%v moves whatever its motion", kind)
	}
	machines := [2]Machine{chest, Machine{kind = .Inserter}}
	eye := [3]f32{0, 8000, 0}
	casters := Sun_Shadow_Casters {
		cascade   = sun_shadow_cascade(eye, {0, 1, 0}, {0, 0, 1}, sun_shadows_test_row()),
		transform = linalg.matrix4_translate_f32(eye),
		machines  = Machine_Registry{machines = machines[:]},
	}
	entities: Entities
	still := Entity_Common{handle = {kind = .Chest}, machine = 0, frame = BLOCK_FRAME, size = {1, 1, 1}}
	moving := Entity_Common{handle = {kind = .Inserter}, machine = 1, frame = BLOCK_FRAME, size = {1, 1, 1}}
	frame := Model_Frame{casters = &casters}
	for part in Sun_Shadow_Part {
		casters.part = part
		testing.expectf(t, model_frame_draws_entity(frame, &entities, {}, still) == (part != .Moving), "%v: the chest", part)
		testing.expectf(t, model_frame_draws_entity(frame, &entities, {}, moving) == (part != .Still), "%v: the inserter", part)
	}
}

@(test)
test_kept_maps_past_the_viewports_are_released :: proc(t: ^testing.T) {
	shadows: Sun_Shadow_Renderer
	for slot in 0 ..< 3 {
		shadows.kept[slot].state = .Failed
	}
	serve_sun_shadows(&shadows, nil, true, 2048, 1)
	testing.expect_value(t, shadows.kept[0].state, Sun_Shadow_State.Failed)
	testing.expect_value(t, shadows.kept[1].state, Sun_Shadow_State.Unloaded)
	testing.expect_value(t, shadows.kept[2].state, Sun_Shadow_State.Unloaded)
	shadows.state = .Failed
	shadows.texels = 2048
	shadows.kept[2].state = .Failed
	serve_sun_shadows(&shadows, nil, false, 2048, 4)
	testing.expect_value(t, shadows.state, Sun_Shadow_State.Unloaded)
	for kept in shadows.kept {
		testing.expect_value(t, kept.state, Sun_Shadow_State.Unloaded)
	}
}

@(test)
test_unloading_the_models_moves_their_revision :: proc(t: ^testing.T) {
	renderer: Model_Renderer
	unload_model_meshes(&renderer)
	testing.expect_value(t, renderer.revision, u64(1))
}
