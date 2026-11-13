package game

import rl "shared:raylib"

// The cables (work item 0368, cable.odin): each drawn as lines through
// CABLE_CURVE_STEPS + 1 points of its curve, the integer sag of
// cable_curve_point, so the aim and the draw agree; the carried run from
// its port to the hand the same way. Unlit and hazed through the model
// shader's flat batch (begin_flat_batch), cast into no shadow map. Each
// cable's hash picks its colour value (13 steps) and its sag (21 steps),
// so two neighbours of one item rarely match in both. Floats are made
// here only.

CABLE_CURVE_STEPS :: 12
// The colour's value varies this many percent either way by the hash.
CABLE_COLOR_VARIATION_PERCENT :: 6

// view nil shows every cable; frames nil reads the frames from the
// entities (the block world).
Cable_Draw :: struct {
	view:          ^Model_View,
	frames:        ^Frame_Matrix_Table,
	models:        Model_Renderer,
	daylight_tint: [3]f32,
}

Cable_Draw_Points :: [CABLE_CURVE_STEPS + 1][3]f32

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

// The points' box widened by the thickness.
cable_draw_box :: proc(points: Cable_Draw_Points, thickness_metres: f32) -> (minimum, maximum: [3]f32) {
	minimum, maximum = points[0], points[0]
	for point in points {
		minimum = {min(minimum.x, point.x), min(minimum.y, point.y), min(minimum.z, point.z)}
		maximum = {max(maximum.x, point.x), max(maximum.y, point.y), max(maximum.z, point.z)}
	}
	return minimum - thickness_metres, maximum + thickness_metres
}

draw_cable_lines :: proc(points: Cable_Draw_Points, color: rl.Color) {
	for step in 0 ..< CABLE_CURVE_STEPS {
		rl.DrawLine3D(points[step], points[step + 1], color)
	}
}

// Inside BeginMode3D: every live cable the view shows.
draw_cables :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, draw: Cable_Draw) {
	if len(entities.cables.cables) == 0 {
		return
	}
	begin_flat_batch(draw.models)
	defer end_flat_batch(draw.models)
	for cable in entities.cables.cables {
		if !item_is_cable(items, cable.item) {
			continue
		}
		points, found := cable_draw_points(entities, machines, draw.frames, cable)
		if !found {
			continue
		}
		item := items.items[cable.item]
		if minimum, maximum := cable_draw_box(points, f32(item.cable_thickness_millimetres) / MILLIMETRES_PER_METRE); model_view_shows(draw.view, minimum, maximum) {
			draw_cable_lines(points, cable_draw_color(item, cable, draw.daylight_tint))
		}
	}
}

// A carried run from its first end's port to the hand (cable_hand_point),
// with the item's sag, in BELT_RUN_REFUSED_COLOR past the item's span.
draw_cable_run :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, body: Field_Player, tuning: Field_Player_Tuning, item: Item_Id, draw: Cable_Draw) {
	if !item_is_cable(items, item) {
		return
	}
	common := entity_common(entities, body.cable_start.entity)
	if common == nil || !machine_port_is_power(machines.machines[common.machine], int(body.cable_start.port)) {
		return
	}
	frame, found := cable_draw_frame(entities, draw.frames, common.frame)
	if !found {
		return
	}
	start := port_point_on_frame(frame, common^, machines.machines[common.machine], int(body.cable_start.port))
	hand := cable_hand_point(body, tuning)
	run := Cable{ends = {body.cable_start, {}}, item = item}
	down, sag := cable_down_and_sag(run, frame, frame, start, hand)
	points := cable_points_in_metres(start, hand, down, sag)
	color := cable_draw_color(items.items[item], run, draw.daylight_tint)
	if chord_metres(start, hand) > i64(items.items[item].cable_span_metres) {
		color = BELT_RUN_REFUSED_COLOR
	}
	begin_flat_batch(draw.models)
	draw_cable_lines(points, color)
	end_flat_batch(draw.models)
}
