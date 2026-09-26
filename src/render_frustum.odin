package game

// View frustum as six planes (normal xyz, distance w), normals pointing
// inwards, extracted from a view projection matrix in the column vector
// convention (clip = projection * view * position), as raylib uses.

Frustum :: [6][4]f32

matrix_row :: proc(view_projection: matrix[4, 4]f32, row: int) -> [4]f32 {
	return {view_projection[row, 0], view_projection[row, 1], view_projection[row, 2], view_projection[row, 3]}
}

// Gribb and Hartmann: a point is inside when -w <= x, y, z <= w in clip space.
frustum_from_matrix :: proc(view_projection: matrix[4, 4]f32) -> Frustum {
	w := matrix_row(view_projection, 3)
	x := matrix_row(view_projection, 0)
	y := matrix_row(view_projection, 1)
	z := matrix_row(view_projection, 2)
	return {w + x, w - x, w + y, w - y, w + z, w - z}
}

// Conservative: tests the box corner furthest along each plane normal, so a
// box is only rejected when it is entirely behind one plane.
frustum_contains_box :: proc(frustum: Frustum, minimum, maximum: [3]f32) -> bool {
	for plane in frustum {
		furthest: [3]f32
		for axis in 0 ..< 3 {
			furthest[axis] = plane[axis] >= 0 ? maximum[axis] : minimum[axis]
		}
		if plane.x * furthest.x + plane.y * furthest.y + plane.z * furthest.z + plane.w < 0 {
			return false
		}
	}
	return true
}
