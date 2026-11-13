package game

import "core:math/linalg"
import rl "shared:raylib"

// The cables (work items 0368 and 0384, cable.odin): each through
// CABLE_CURVE_STEPS + 1 points of its curve, the integer sag of
// cable_curve_point, so the aim and the draw agree; the carried runs from
// their ports to the hand the same way. Every shown cable is lines; within
// CABLE_BOX_METRES of the eye each segment is also a box of the item's
// thickness, all of them one instanced draw of the unit cube from the
// viewport's cables buffer (Field_Instance_Buffers.cables), and the box
// hides the line by depth wherever it is a pixel wide or more. Without
// the buffer (the block world) or the model shader's instancing, lines
// only. Unlit and hazed through the model shader's flat modes
// (begin_flat_instances, begin_flat_batch), cast into no shadow map. Each
// cable's hash picks its colour value (13 steps) and its sag (21 steps),
// so two neighbours of one item rarely match in both. Floats are made
// here only.

CABLE_CURVE_STEPS :: 12
// The colour's value varies this many percent either way by the hash.
CABLE_COLOR_VARIATION_PERCENT :: 6
// Within this of the eye (the box round the points) a cable draws its
// boxes too.
CABLE_BOX_METRES :: 32

// view nil shows every cable; frames nil reads the frames from the
// entities (the block world); instances nil draws every cable as lines.
Cable_Draw :: struct {
	view:          ^Model_View,
	frames:        ^Frame_Matrix_Table,
	models:        Model_Renderer,
	instances:     ^Instance_Buffer,
	daylight_tint: [3]f32,
}

Cable_Draw_Points :: [CABLE_CURVE_STEPS + 1][3]f32

// A cable or a carried run as this frame draws it.
Cable_Look :: struct {
	points:           Cable_Draw_Points,
	thickness_metres: f32,
	color:            rl.Color,
}

cable_draw_frame :: proc(entities: ^Entities, frames: ^Frame_Matrix_Table, id: Frame_Id) -> (frame: Frame, found: bool) {
	if frames != nil {
		entry: Frame_Matrix_Entry
		entry, found = find_frame_matrix(frames^, id)
		return entry.frame, found
	}
	return find_frame(&entities.frames, id)
}

// The curve's points in metres, found false for a cable whose end is gone.
cable_draw_points :: proc(entities: ^Entities, machines: Machine_Registry, frames: ^Frame_Matrix_Table, cable: Cable) -> (points: Cable_Draw_Points, found: bool) {
	ends: [2]World_Position
	end_frames: [2]Frame
	for end, role in cable.ends {
		common := entity_common(entities, end.entity)
		if common == nil || !machine_port_is_power(machines.machines[common.machine], int(end.port)) {
			return {}, false
		}
		end_frames[role] = cable_draw_frame(entities, frames, common.frame) or_return
		ends[role] = port_point_on_frame(end_frames[role], common^, machines.machines[common.machine], int(end.port))
	}
	down, sag := cable_down_and_sag(cable, end_frames[0], end_frames[1], ends[0], ends[1])
	return cable_points_in_metres(ends[0], ends[1], down, sag), true
}

cable_points_in_metres :: proc(first, second: World_Position, down: [3]i64, sag_units: i64) -> (points: Cable_Draw_Points) {
	for &point, step in points {
		point = world_position_to_metres(cable_curve_point(first, second, down, sag_units, step, CABLE_CURVE_STEPS))
	}
	return points
}

// The item's colour with its value varied by the cable's hash, times the
// tint.
cable_draw_color :: proc(item: Item, cable: Cable, tint: [3]f32) -> rl.Color {
	offset := i64((cable_hash(cable) >> 16) % (2 * CABLE_COLOR_VARIATION_PERCENT + 1)) - CABLE_COLOR_VARIATION_PERCENT
	factor := f32(100 + offset) / 100
	color: rl.Color
	for channel in 0 ..< 3 {
		color[channel] = u8(clamp(f32(item.cable_color[channel]) * factor * tint[channel], 0, 255))
	}
	color.a = 255
	return color
}

cable_thickness_metres :: proc(item: Item) -> f32 {
	return f32(item.cable_thickness_millimetres) / MILLIMETRES_PER_METRE
}

// The points' box widened by the thickness.
cable_draw_box :: proc(points: Cable_Draw_Points, thickness_metres: f32) -> (minimum, maximum: [3]f32) {
	minimum, maximum = points[0], points[0]
	for point in points {
		minimum = {min(minimum.x, point.x), min(minimum.y, point.y), min(minimum.z, point.z)}
		maximum = {max(maximum.x, point.x), max(maximum.y, point.y), max(maximum.z, point.z)}
	}
	return minimum - thickness_metres, maximum + thickness_metres
}

// The box under the view's transform within CABLE_BOX_METRES of its eye;
// never without a view.
cable_box_is_near :: proc(view: ^Model_View, minimum, maximum: [3]f32) -> bool {
	if view == nil {
		return false
	}
	low, high := transformed_box(view.transform, minimum, maximum)
	return box_distance_metres(low, high, view.eye) <= CABLE_BOX_METRES
}

// The box round the points, widened by the thickness, under the view
// (model_view_shows).
cable_points_shown :: proc(view: ^Model_View, points: Cable_Draw_Points, thickness_metres: f32) -> bool {
	minimum, maximum := cable_draw_box(points, thickness_metres)
	return model_view_shows(view, minimum, maximum)
}

// An axis a straight chord does not lie along.
cable_straight_side_axis :: proc(along: [3]f32) -> [3]f32 {
	return abs(along.y) < 0.9 ? [3]f32{0, 1, 0} : [3]f32{1, 0, 0}
}

// A curve whose middle lies less than this off its chord is straight.
CABLE_STRAIGHT_SAG_METRES :: 0.0001

// The normal of the plane the curve lies in, its chord crossed with its
// middle's offset from the chord's (the sag, cable_curve_point): one axis
// for every segment of a look, so each box's corners meet the next box's
// at their joint. A straight curve takes cable_straight_side_axis of its
// chord.
cable_side_axis :: proc(points: Cable_Draw_Points) -> [3]f32 {
	first, last := points[0], points[CABLE_CURVE_STEPS]
	chord := last - first
	normal := linalg.cross(chord, points[CABLE_CURVE_STEPS / 2] - (first + last) / 2)
	if linalg.length(normal) > CABLE_STRAIGHT_SAG_METRES * linalg.length(chord) {
		return linalg.normalize(normal)
	}
	return cable_straight_side_axis(linalg.normalize0(chord))
}

// The unit cube from first to second along its z, the thickness across
// its x and y with its y along side's part across the segment (the look's
// cable_side_axis), so its z faces' centres are the two points; the
// colour in the bottom row (instance_matrix_with_color).
cable_segment_instance :: proc(first, second, side: [3]f32, thickness_metres: f32, color: rl.Color) -> matrix[4, 4]f32 {
	segment := second - first
	along := linalg.normalize0(segment)
	across := linalg.normalize0(linalg.cross(along, side)) * thickness_metres
	beside := linalg.cross(along, across)
	middle := (first + second) / 2
	transform := matrix[4, 4]f32{
		across.x, beside.x, segment.x, middle.x,
		across.y, beside.y, segment.y, middle.y,
		across.z, beside.z, segment.z, middle.z,
		0, 0, 0, 1,
	}
	return instance_matrix_with_color(transform, color)
}

// One box a segment of the look's curve, all about one side axis.
append_cable_segment_instances :: proc(instances: ^[dynamic]matrix[4, 4]f32, look: Cable_Look) {
	side := cable_side_axis(look.points)
	for step in 0 ..< CABLE_CURVE_STEPS {
		append(instances, cable_segment_instance(look.points[step], look.points[step + 1], side, look.thickness_metres, look.color))
	}
}

// A live cable's look; found false for an item that is no cable, an end
// that is gone or a box the view does not show, the colour made only for
// a shown cable.
cable_look :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, draw: Cable_Draw, cable: Cable) -> (look: Cable_Look, found: bool) {
	if !item_is_cable(items, cable.item) {
		return {}, false
	}
	look.points = cable_draw_points(entities, machines, draw.frames, cable) or_return
	item := items.items[cable.item]
	look.thickness_metres = cable_thickness_metres(item)
	if !cable_points_shown(draw.view, look.points, look.thickness_metres) {
		return {}, false
	}
	look.color = cable_draw_color(item, cable, draw.daylight_tint)
	return look, true
}

// A carried run from its first end's port to the hand (cable_hand_point),
// with the item's sag, in BELT_RUN_REFUSED_COLOR past the item's span;
// found false as cable_look's.
cable_run_look :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, body: Field_Player, tuning: Field_Player_Tuning, item: Item_Id, draw: Cable_Draw) -> (look: Cable_Look, found: bool) {
	if !item_is_cable(items, item) {
		return {}, false
	}
	common := entity_common(entities, body.cable_start.entity)
	if common == nil || !machine_port_is_power(machines.machines[common.machine], int(body.cable_start.port)) {
		return {}, false
	}
	frame := cable_draw_frame(entities, draw.frames, common.frame) or_return
	start := port_point_on_frame(frame, common^, machines.machines[common.machine], int(body.cable_start.port))
	hand := cable_hand_point(body, tuning)
	run := Cable{ends = {body.cable_start, {}}, item = item}
	down, sag := cable_down_and_sag(run, frame, frame, start, hand)
	look.points = cable_points_in_metres(start, hand, down, sag)
	look.thickness_metres = cable_thickness_metres(items.items[item])
	if !cable_points_shown(draw.view, look.points, look.thickness_metres) {
		return {}, false
	}
	look.color = cable_draw_color(items.items[item], run, draw.daylight_tint)
	if chord_metres(start, hand) > i64(items.items[item].cable_span_metres) {
		look.color = BELT_RUN_REFUSED_COLOR
	}
	return look, true
}

draw_cable_lines :: proc(points: Cable_Draw_Points, color: rl.Color) {
	for step in 0 ..< CABLE_CURVE_STEPS {
		rl.DrawLine3D(points[step], points[step + 1], color)
	}
}

// The boxes up into the viewport's cables buffer, then one instanced draw
// of the unit cube unlit and hazed, each box's colour its own. Nothing for
// none.
draw_cable_segment_instances :: proc(segments: []matrix[4, 4]f32, draw: Cable_Draw) {
	if len(segments) == 0 {
		return
	}
	upload_instances_in_place(&draw.instances.buffer, &draw.instances.capacity, segments)
	begin_flat_instances(draw.models, true)
	draw_mesh_instances(draw.models.unit_cube, draw.instances.buffer, 0, len(segments))
	end_flat_instances(draw.models)
}

// Every look (shown, cable_look) as lines in the flat batch; one near the
// eye collected as boxes too, drawn after the batch. A box thinner than a
// pixel (a light cable past about 9 m at 1080p) would break into dashes
// without multisampling, so the line stays under it; where the box is a
// pixel wide or more it hides the line by depth.
draw_cable_looks :: proc(looks: []Cable_Look, draw: Cable_Draw) {
	instanced := draw.models.instancing_ready && draw.instances != nil
	segments: [dynamic]matrix[4, 4]f32
	if instanced {
		segments = make([dynamic]matrix[4, 4]f32, 0, CABLE_CURVE_STEPS * len(looks), context.temp_allocator)
	}
	begin_flat_batch(draw.models)
	for look in looks {
		draw_cable_lines(look.points, look.color)
		if !instanced {
			continue
		}
		if minimum, maximum := cable_draw_box(look.points, look.thickness_metres); cable_box_is_near(draw.view, minimum, maximum) {
			append_cable_segment_instances(&segments, look)
		}
	}
	// Before the boxes, whose instanced draw sets the switches itself (0360).
	end_flat_batch(draw.models)
	draw_cable_segment_instances(segments[:], draw)
}

// Inside BeginMode3D: every live cable and the carried runs (runs,
// cable_run_look) the view shows, in one flat batch and one instanced draw.
draw_cables :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, draw: Cable_Draw, runs: []Cable_Look = nil) {
	if len(entities.cables.cables) == 0 && len(runs) == 0 {
		return
	}
	looks := make([dynamic]Cable_Look, 0, len(entities.cables.cables) + len(runs), context.temp_allocator)
	for cable in entities.cables.cables {
		if look, found := cable_look(entities, machines, items, draw, cable); found {
			append(&looks, look)
		}
	}
	append(&looks, ..runs)
	draw_cable_looks(looks[:], draw)
}
