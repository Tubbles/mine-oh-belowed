package game

import "core:math"
import rl "shared:raylib"

// The collision volumes as wireframes (work item 0230, doc/build.md, The
// workbench): the model preview's _collision shots draw a machine's
// volumes over its model. Presentation only, floats, in cells of the
// model's frame.

// A full ring's segments.
COLLISION_WIRE_SEGMENTS :: 24
COLLISION_WIRE_COLOR :: rl.Color{255, 64, 200, 255}

collision_wire_point :: proc(point: [3]i64) -> [3]f32 {
	return [3]f32{f32(point.x), f32(point.y), f32(point.z)} / COLLISION_UNITS_PER_CELL
}

// The box's 12 edges: along each axis, the four edges at the corners of
// the other two.
collision_box_wire_lines :: proc(minimum, maximum: [3]f32, lines: ^[dynamic][2][3]f32) {
	extent := [2][3]f32{minimum, maximum}
	for axis in 0 ..< 3 {
		first, second := collision_perpendicular_axes(axis)
		for corner in 0 ..< 4 {
			start, end: [3]f32
			start[axis], end[axis] = minimum[axis], maximum[axis]
			start[first], end[first] = extent[corner & 1][first], extent[corner & 1][first]
			start[second], end[second] = extent[corner >> 1][second], extent[corner >> 1][second]
			append(lines, [2][3]f32{start, end})
		}
	}
}

// The point at radius and angle (radians from the first perpendicular
// towards the second) about the volume's axis, at height along it.
collision_round_point :: proc(volume: Collision_Volume, radius, angle, height: f32) -> [3]f32 {
	first, second := collision_perpendicular_axes(volume.axis)
	centre := collision_wire_point(volume.from)
	point := centre
	point[first] += radius * math.cos(angle)
	point[second] += radius * math.sin(angle)
	point[volume.axis] = height
	return point
}

// The sector's start angle and span in radians; the full turn from 0.
collision_sector_angles :: proc(sector: Collision_Sector) -> (start, span: f32) {
	if !sector.partial {
		return 0, 2 * math.PI
	}
	start = math.atan2(f32(sector.start.y), f32(sector.start.x))
	end := math.atan2(f32(sector.end.y), f32(sector.end.x))
	span = math.mod(end - start, 2 * math.PI)
	if span <= 0 {
		span += 2 * math.PI
	}
	return start, span
}

// An arc of segments at radius and height over the sector.
collision_arc_wire_lines :: proc(volume: Collision_Volume, radius, height, start, span: f32, segments: int, lines: ^[dynamic][2][3]f32) {
	for index in 0 ..< segments {
		from := start + span * f32(index) / f32(segments)
		to := start + span * f32(index + 1) / f32(segments)
		append(lines, [2][3]f32{collision_round_point(volume, radius, from, height), collision_round_point(volume, radius, to, height)})
	}
}

// A round's outline: an arc per end and surface (the outer, and the inner
// of a shell); a full turn's 4 lines along the axis on the outer surface;
// a sector's edges along the axis on the outer and the inner surface (or
// the axis) and its radial lines at each end.
collision_round_wire_lines :: proc(volume: Collision_Volume, lines: ^[dynamic][2][3]f32) {
	start, span := collision_sector_angles(volume.sector)
	segments := COLLISION_WIRE_SEGMENTS
	if volume.sector.partial {
		segments = max(1, int(math.ceil(f32(COLLISION_WIRE_SEGMENTS) * span / (2 * math.PI))))
	}
	heights := [2]f32{f32(volume.from[volume.axis]), f32(volume.to[volume.axis])} / COLLISION_UNITS_PER_CELL
	outer := [2]f32{f32(volume.radius_from), f32(volume.radius_to)} / COLLISION_UNITS_PER_CELL
	inner := [2]f32{f32(volume.radius_from - volume.shell), f32(volume.radius_to - volume.shell)} / COLLISION_UNITS_PER_CELL
	if volume.shell == 0 {
		inner = {}
	}
	for end in 0 ..< 2 {
		collision_arc_wire_lines(volume, outer[end], heights[end], start, span, segments, lines)
		if volume.shell > 0 {
			collision_arc_wire_lines(volume, inner[end], heights[end], start, span, segments, lines)
		}
	}
	if !volume.sector.partial {
		for quarter in 0 ..< 4 {
			angle := f32(quarter) * math.PI / 2
			append(lines, [2][3]f32{collision_round_point(volume, outer[0], angle, heights[0]), collision_round_point(volume, outer[1], angle, heights[1])})
		}
		return
	}
	for angle in ([2]f32{start, start + span}) {
		append(lines, [2][3]f32{collision_round_point(volume, outer[0], angle, heights[0]), collision_round_point(volume, outer[1], angle, heights[1])})
		append(lines, [2][3]f32{collision_round_point(volume, inner[0], angle, heights[0]), collision_round_point(volume, inner[1], angle, heights[1])})
		for end in 0 ..< 2 {
			append(lines, [2][3]f32{collision_round_point(volume, inner[end], angle, heights[end]), collision_round_point(volume, outer[end], angle, heights[end])})
		}
	}
}

// The volume's outline in cells of the model's frame. Counts: a box 12, a
// full solid round 52, a full shell 100, a shell over half a turn 56.
collision_volume_wire_lines :: proc(volume: Collision_Volume, allocator := context.temp_allocator) -> [][2][3]f32 {
	lines := make([dynamic][2][3]f32, allocator)
	if volume.kind == .Box {
		collision_box_wire_lines(collision_wire_point(volume.from), collision_wire_point(volume.to), &lines)
	} else {
		collision_round_wire_lines(volume, &lines)
	}
	return lines[:]
}

// Inside the caller's matrix (cells of the model's frame).
draw_collision_volume_wires :: proc(volumes: []Collision_Volume) {
	for volume in volumes {
		for line in collision_volume_wire_lines(volume) {
			rl.DrawLine3D(line[0], line[1], COLLISION_WIRE_COLOR)
		}
	}
}
