package game

import "core:math"
import "core:testing"

// The collision volumes' signed distances, sectors, turns, rays and
// scaling (work item 0230, world_frame_body.odin), in model units, which
// are position units at a pitch of 1000 mm.

// A definition through the reader's conversion (resolve_collision_volumes):
// one volume.
test_collision_volume :: proc(definition: Collision_Volume_Definition) -> Collision_Volume {
	volumes := resolve_collision_volumes([]Collision_Volume_Definition{definition}, context.temp_allocator)
	assert(len(volumes) == 1)
	return volumes[0]
}

// Units as the file's cells.
test_cells :: proc(units: f64) -> f64 {
	return units / COLLISION_UNITS_PER_CELL
}

test_round_definition :: proc(axis: string, from, to: [3]f64, radius_from, radius_to: f64, shell: f64 = 0, sector: []f64 = nil) -> Collision_Volume_Definition {
	return {kind = "round", axis = axis, from = from / COLLISION_UNITS_PER_CELL, to = to / COLLISION_UNITS_PER_CELL, radius_from = test_cells(radius_from), radius_to = test_cells(radius_to), shell = test_cells(shell), sector = sector}
}

// A unit vector within tolerance of the expected one in UNIT_VECTOR_ONE.
normal_near :: proc(normal: [3]i64, expected: [3]f64, tolerance: i64) -> bool {
	for axis in 0 ..< 3 {
		if abs(normal[axis] - i64(math.round(expected[axis] * UNIT_VECTOR_ONE))) > tolerance {
			return false
		}
	}
	return true
}

@(test)
test_a_box_volume_gives_its_distance_and_face_outside_and_inside :: proc(t: ^testing.T) {
	box := test_collision_volume({kind = "box", from = {0, 0, 0}, to = {test_cells(1000), test_cells(500), test_cells(2000)}})
	distance, normal := volume_signed_distance(box, {1500, 250, 1000})
	testing.expect_value(t, distance, 500)
	testing.expect_value(t, normal, [3]i64{UNIT_VECTOR_ONE, 0, 0})
	distance, normal = volume_signed_distance(box, {1100, 600, 1000})
	testing.expect_value(t, distance, 141)
	testing.expectf(t, normal_near(normal, {0.70710678, 0.70710678, 0}, UNIT_VECTOR_ONE >> 10), "the diagonal's normal %v", normal)
	distance, normal = volume_signed_distance(box, {100, 250, 1000})
	testing.expect_value(t, distance, -100)
	testing.expect_value(t, normal, [3]i64{-UNIT_VECTOR_ONE, 0, 0})
	cell := World_Coordinate{1, -1, 2}
	pitch := i64(2048)
	low := [3]i64{2048, -2048, 4096}
	for point in ([3][3]i64{{2100, -1000, 5000}, {-300, 0, 4100}, {9000, 9000, 9000}}) {
		cell_distance, cell_normal := cell_box_distance(point, cell, pitch)
		box_distance, box_normal := box_signed_distance(point, low, low + pitch)
		testing.expect_value(t, cell_distance, box_distance)
		testing.expect_value(t, cell_normal, box_normal)
	}
}

@(test)
test_a_round_volume_gives_its_distance_to_the_side_and_the_caps :: proc(t: ^testing.T) {
	cylinder := test_collision_volume(test_round_definition("y", {0, 0, 0}, {0, 1000, 0}, 500, 500))
	distance, normal := volume_signed_distance(cylinder, {800, 500, 0})
	testing.expect_value(t, distance, 300)
	testing.expect_value(t, normal, [3]i64{UNIT_VECTOR_ONE, 0, 0})
	distance, normal = volume_signed_distance(cylinder, {0, 1200, 0})
	testing.expect_value(t, distance, 200)
	testing.expect_value(t, normal, [3]i64{0, UNIT_VECTOR_ONE, 0})
	distance, normal = volume_signed_distance(cylinder, {100, 300, 0})
	testing.expect_value(t, distance, -300)
	testing.expect_value(t, normal, [3]i64{0, -UNIT_VECTOR_ONE, 0})
	cone := test_collision_volume(test_round_definition("y", {0, 0, 0}, {0, 1000, 0}, 1000, 500))
	distance, normal = volume_signed_distance(cone, {1000, 500, 0})
	testing.expect_value(t, distance, 223)
	testing.expectf(t, normal_near(normal, {0.89442719, 0.44721360, 0}, UNIT_VECTOR_ONE >> 10), "the cone's normal %v", normal)
	about_x := test_collision_volume(test_round_definition("x", {0, 0, 0}, {1000, 0, 0}, 1000, 500))
	about_z := test_collision_volume(test_round_definition("z", {0, 0, 0}, {0, 0, 1000}, 1000, 500))
	distance_x, _ := volume_signed_distance(about_x, {500, 1000, 0})
	distance_z, _ := volume_signed_distance(about_z, {1000, 0, 500})
	testing.expect_value(t, distance_x, 223)
	testing.expect_value(t, distance_z, 223)
}

@(test)
test_a_shell_holds_a_point_inside_by_its_inner_surface :: proc(t: ^testing.T) {
	shell := test_collision_volume(test_round_definition("y", {0, 0, 0}, {0, 1000, 0}, 1000, 1000, 200))
	distance, normal := volume_signed_distance(shell, {500, 500, 0})
	testing.expect_value(t, distance, 300)
	testing.expect_value(t, normal, [3]i64{-UNIT_VECTOR_ONE, 0, 0})
	distance, normal = volume_signed_distance(shell, {850, 500, 0})
	testing.expect_value(t, distance, -50)
	testing.expect_value(t, normal, [3]i64{-UNIT_VECTOR_ONE, 0, 0})
	distance, normal = volume_signed_distance(shell, {0, 500, 0})
	testing.expect_value(t, distance, 800)
	testing.expectf(t, abs(normal.y) < UNIT_VECTOR_ONE >> 10 && abs(vector_length(normal) - UNIT_VECTOR_ONE) < UNIT_VECTOR_ONE >> 10, "the normal on the axis %v", normal)
	solid := test_collision_volume(test_round_definition("y", {0, 0, 0}, {0, 1000, 0}, 500, 500))
	distance, _ = volume_signed_distance(solid, {10, 500, 0})
	testing.expect_value(t, distance, -490)
}

// A point at angle (degrees about y from +z towards +x), radius and
// height.
test_point_about_y :: proc(degrees, radius, height: f64) -> [3]i64 {
	angle := degrees * math.RAD_PER_DEG
	return {i64(math.round(radius * math.sin(angle))), i64(math.round(height)), i64(math.round(radius * math.cos(angle)))}
}

@(test)
test_a_sector_leaves_its_gap_open_and_closes_its_ends :: proc(t: ^testing.T) {
	shell := test_collision_volume(test_round_definition("y", {0, 0, 0}, {0, 1000, 0}, 1000, 1000, 200, []f64{30, 330}))
	testing.expect(t, shell.sector.partial && shell.sector.wide)
	distance, normal := volume_signed_distance(shell, test_point_about_y(0, 900, 500))
	testing.expectf(t, distance >= 400, "the gap's middle is %d out", distance)
	distance, _ = volume_signed_distance(shell, test_point_about_y(180, 900, 500))
	testing.expectf(t, distance < 0, "the wall opposite the gap is %d", distance)
	outward := [3]f64{math.cos(30 * math.RAD_PER_DEG) * -1, 0, math.sin(30 * math.RAD_PER_DEG)}
	distance, normal = volume_signed_distance(shell, test_point_about_y(25, 900, 500))
	testing.expectf(t, abs(distance - 78) <= 2, "beside the start face %d", distance)
	testing.expectf(t, normal_near(normal, outward, UNIT_VECTOR_ONE >> 8), "the start face's normal %v", normal)
	distance, normal = volume_signed_distance(shell, test_point_about_y(31, 900, 500))
	testing.expectf(t, abs(distance + 16) <= 2, "inside the wall by the start face %d", distance)
	testing.expectf(t, normal_near(normal, outward, UNIT_VECTOR_ONE >> 8), "the start face's normal inside %v", normal)
	narrow := collision_sector([]f64{60, 120})
	testing.expect(t, !narrow.wide)
	testing.expect(t, sector_contains(narrow, {0, 1000}))
	testing.expect(t, !sector_contains(narrow, {1000, 0}))
	wide := collision_sector([]f64{100, 80})
	testing.expect(t, wide.wide)
	testing.expect(t, sector_contains(wide, {1000, 0}))
	testing.expect(t, sector_contains(wide, {-1000, 0}))
	testing.expect(t, !sector_contains(wide, {0, 1000}))
}

@(test)
test_the_body_turns_points_by_its_quarter_turns :: proc(t: ^testing.T) {
	vectors := [3][3]i64{{1, 2, 3}, {-5, 0, 7}, {UNIT_VECTOR_ONE, -4, 0}}
	for rotation in u8(0) ..< 4 {
		for vector in vectors {
			testing.expect_value(t, body_direction_from_frame(rotation, body_direction_to_frame(rotation, vector)), vector)
		}
	}
	testing.expect_value(t, body_direction_to_frame(1, {1, 0, 0}), [3]i64{0, 0, 1})
	frame := Frame{id = 1, axes = block_frame().axes, pitch_millimetres = 500}
	body := make_frame_body(frame, {}, {-5, 0, -5}, {12, 8, 12}, 1, nil)
	testing.expect_value(t, body.centre, [3]i64{2048, 0, 2048})
}

// One box from (-1000, 0, -1000) to (1000, 2000, 1000) round the origin
// of a 1000 mm frame at the world's origin.
test_box_body :: proc() -> Frame_Body {
	box := test_collision_volume({kind = "box", from = {test_cells(-1000), 0, test_cells(-1000)}, to = {test_cells(1000), test_cells(2000), test_cells(1000)}})
	frame := Frame{id = 1, axes = block_frame().axes, pitch_millimetres = 1000}
	return make_frame_body(frame, {handle = 7, flags = {.Solid, .Shaped}}, {-1, 0, -1}, {2, 2, 2}, 0, []Collision_Volume{box})
}

@(test)
test_a_ray_stops_at_a_volume_and_passes_beside_it :: proc(t: ^testing.T) {
	body := test_box_body()
	reach := metres_to_position_units(3)
	along := [3]i64{UNIT_VECTOR_ONE, 0, 0}
	origin := World_Position{-1000 - metres_to_position_units(2), 1000, 0}
	distance, normal, hit := raycast_frame_body(body, origin, along, reach)
	truth := metres_to_position_units(2)
	testing.expectf(t, hit && distance <= truth && distance >= truth - COLLISION_RAY_HIT_UNITS - 1, "the ray hit %v at %d", hit, distance)
	testing.expect_value(t, normal, [3]i64{-UNIT_VECTOR_ONE, 0, 0})
	testing.expect_value(t, face_of_frame_normal(normal), Direction.Negative_X)
	_, _, beside := raycast_frame_body(body, origin + {0, 1010, 0}, along, reach)
	testing.expect(t, !beside, "a ray 10 units over the top hits")
	inside, _, inside_hit := raycast_frame_body(body, {0, 1000, 0}, along, reach)
	testing.expect(t, inside_hit && inside == 0)
	result := frame_body_hit(body, origin, along, distance, normal)
	testing.expect(t, result.hit && result.occupant.handle == 7 && result.face == .Negative_X)
	pitch := frame_pitch_units(body.frame)
	point := [3]i64{-1000 + pitch / 4, 1000, 0}
	testing.expectf(t, i64(result.cell.x) * pitch <= point.x - 2 * COLLISION_RAY_HIT_UNITS && point.x <= (i64(result.cell.x) + 1) * pitch, "the cell %v holds the point moved into the box", result.cell)
	testing.expect_value(t, result.adjacent, result.cell + World_Coordinate(direction_offsets[.Negative_X]))
}

@(test)
test_scaling_a_volume_follows_the_pitch :: proc(t: ^testing.T) {
	volume := test_collision_volume(test_round_definition("y", {0, 0, 0}, {0, 4096, 0}, 4096, 4096, 0, []f64{10, 200}))
	half := scale_collision_volume(volume, millimetres_to_position_units(500))
	whole := scale_collision_volume(volume, millimetres_to_position_units(1000))
	testing.expect_value(t, half.to.y, 2048)
	testing.expect_value(t, half.radius_from, 2048)
	testing.expect_value(t, whole.to.y, 4096)
	testing.expect_value(t, whole.radius_to, 4096)
	testing.expect_value(t, half.sector, volume.sector)
}
