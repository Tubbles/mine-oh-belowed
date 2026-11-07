package game

import "core:math"
import "core:math/linalg"
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

// The offset's parts across the right and the up.
sun_shadow_test_in_plane :: proc(cascade: Sun_Shadow_Cascade, offset: [3]f32) -> [2]f32 {
	return {linalg.dot(offset, cascade.right), linalg.dot(offset, cascade.up)}
}

@(test)
test_the_cascade_covers_the_radius :: proc(t: ^testing.T) {
	row := sun_shadows_test_row()
	texel := 2 * f32(row.radius_metres) / f32(row.map_texels - 2 * SUN_SHADOW_MARGIN_TEXELS)
	// The eye lies up to half a texel off the snapped centre along each
	// axis, so at least the margin less one texel stays clear.
	clear_share := f32(SUN_SHADOW_MARGIN_TEXELS - 1) / (f32(row.map_texels) / 2)
	for up in ([2][3]f32{{0, 1, 0}, linalg.normalize([3]f32{1, 2, 3})}) {
		for fraction in ([3]f64{0.1, 0.25, 0.4}) {
			eye := up * 8000
			cascade := sun_shadow_cascade(eye, field_sun_world_direction(fraction, up), field_sun_path_world_axis(up), row)
			testing.expectf(t, abs(cascade.texel_metres - texel) < 1e-6, "texel %v, expected %v", cascade.texel_metres, texel)
			testing.expectf(t, abs(cascade.half_size - f32(row.map_texels) * texel / 2) < 1e-4, "half size %v", cascade.half_size)
			for axis in ([3][3]f32{cascade.right, cascade.up, cascade.toward_sun}) {
				for side in ([2]f32{-1, 1}) {
					clip := sun_shadow_test_clip(cascade, eye + axis * (side * f32(row.radius_metres)))
					for component in 0 ..< 3 {
						testing.expectf(t, abs(clip[component]) <= 1 - clear_share, "up %v fraction %v: %v lands at %v", up, fraction, axis * side, clip)
					}
				}
			}
		}
	}
}

@(test)
test_the_cascade_snaps_to_whole_texels :: proc(t: ^testing.T) {
	row := sun_shadows_test_row()
	up := linalg.normalize([3]f32{1, 2, 3})
	sun, axis := field_sun_world_direction(0.15, up), field_sun_path_world_axis(up)
	first := sun_shadow_cascade(up * 8000, sun, axis, row)
	texel := first.texel_metres
	// f32 at 8 km holds a point to about a millimetre, a sixtieth of a
	// texel.
	tolerance := 0.05 * texel
	probe := first.centre + first.right * 3 + first.up * 5
	nudged := sun_shadow_cascade(first.centre + first.right * (0.25 * texel), sun, axis, row)
	kept := sun_shadow_test_in_plane(first, nudged.centre - first.centre)
	testing.expectf(t, abs(kept.x) < tolerance && abs(kept.y) < tolerance, "a quarter texel moved the centre by %v", kept)
	drift := sun_shadow_test_clip(nudged, probe).xy - sun_shadow_test_clip(first, probe).xy
	testing.expectf(t, abs(drift.x) < 1e-5 && abs(drift.y) < 1e-5, "a quarter texel moved the map's grid by %v", drift)
	stepped := sun_shadow_cascade(first.centre + first.right * texel, sun, axis, row)
	moved := sun_shadow_test_in_plane(first, stepped.centre - first.centre)
	testing.expectf(t, abs(moved.x - texel) < tolerance && abs(moved.y) < tolerance, "a texel moved the centre by %v", moved)
	along := sun_shadow_cascade(up * 8000 + sun * 5, sun, axis, row)
	sideways := sun_shadow_test_in_plane(first, along.centre - first.centre)
	testing.expectf(t, abs(sideways.x) < tolerance && abs(sideways.y) < tolerance, "5 m along the sun moved the centre across by %v", sideways)
	testing.expectf(t, abs(linalg.dot(along.centre - first.centre, sun) - 5) < 0.01, "5 m along the sun moved the centre %v along it", linalg.dot(along.centre - first.centre, sun))
	for step in 0 ..< 50 {
		eye := up * 8000 + first.right * (0.137 * f32(step)) + first.up * (0.291 * f32(step))
		cascade := sun_shadow_cascade(eye, sun, axis, row)
		offset := sun_shadow_test_in_plane(cascade, eye - cascade.centre)
		testing.expectf(t, linalg.length(offset) <= 0.71 * texel, "the eye %v texels off the centre", linalg.length(offset) / texel)
	}
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
	trees := select_shadow_trees(&cache, cascade, camera, 4, felled, 1000)
	testing.expect_value(t, len(trees), 39)
	for tree in trees {
		offset := tree_instance_base(tree.instance).x - camera.x
		testing.expect(t, offset > 1.5, "the felled tree is left out")
		testing.expect(t, offset < 100, "no tree past the casters' box")
	}
	trees = select_shadow_trees(&cache, cascade, camera, 4, felled, 10)
	testing.expect_value(t, len(trees), 10)
	for tree in trees {
		offset := tree_instance_base(tree.instance).x - camera.x
		testing.expectf(t, offset > 1.5 && offset < 11.5, "the cut keeps the nearest, not %v m", offset)
	}
	testing.expect_value(t, len(select_shadow_trees(&cache, cascade, camera, 4, felled, 0)), 0)
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
