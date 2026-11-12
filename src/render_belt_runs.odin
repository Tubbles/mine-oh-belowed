package game

import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"

// Belt and pipe runs between poles (work item 0176, belt_run.odin): the
// belt's surface and its sides swept along the run's polyline, one quad
// per subdivision, each oriented along its segment with the endpoints' frame
// ups blended between the ends; the texture runs a cell of the start
// frame's pitch per repeat and scrolls with the belt's speed as the belt
// meshes do. Items stand at their distance along the line through
// belt_run_point_at, offset across the run to their lane. A pipe run is a
// tube of the pipe's colour per subdivision; a pole a post from its cell's
// bottom to its run end. The field's scene (0347, Belt_Run_Draw) draws a
// run, a pole and an item only where its view shows the box round it, and
// the items in one instanced draw; the runs and poles go through the
// model shader's flat batch, hazed (0360, begin_flat_batch). Floats are
// made here only.

BELT_RUN_POLE_COLOR :: rl.Color{120, 122, 128, 255}
BELT_RUN_POLE_RADIUS_METRES :: 0.06
BELT_RUN_POLE_SIDES :: 8
// A pipe run's radius as a share of the start frame's pitch.
PIPE_RUN_RADIUS_SHARE :: 0.25
PIPE_RUN_SIDES :: 8
// The belt's sides reach this share of the pitch below its surface.
BELT_RUN_SIDE_DEPTH_SHARE :: 0.2
BELT_RUN_SIDE_COLOR :: rl.Color{44, 44, 50, 255}
BELT_RUN_GHOST_COLOR :: rl.Color{240, 240, 240, 120}
BELT_RUN_REFUSED_COLOR :: rl.Color{230, 70, 60, 140}

// Where the surface passes a polyline point, in metres: the point, the
// unit vector across the run to its right and the surface's up.
Belt_Run_Section :: struct {
	centre: [3]f32,
	right:  [3]f32,
	up:     [3]f32,
}

Belt_Run_Sections :: [BELT_RUN_SUBDIVISIONS + 1]Belt_Run_Section

// The section at a polyline point: the up blended from the start's to the
// end's, the right across the tangent (the neighbours' difference).
belt_run_section :: proc(curve: Belt_Run_Curve, ups: [2][3]i64, step: int) -> Belt_Run_Section {
	before := curve.polyline[max(step - 1, 0)]
	after := curve.polyline[min(step + 1, BELT_RUN_SUBDIVISIONS)]
	tangent := linalg.normalize0(world_position_to_metres(after) - world_position_to_metres(before))
	share := f32(step) / BELT_RUN_SUBDIVISIONS
	blended := linalg.normalize0(unit_vector_to_f32(ups[BELT_RUN_START]) * (1 - share) + unit_vector_to_f32(ups[BELT_RUN_END]) * share)
	right := linalg.normalize0(linalg.cross(tangent, blended))
	return Belt_Run_Section{centre = world_position_to_metres(curve.polyline[step]), right = right, up = linalg.normalize0(linalg.cross(right, tangent))}
}

belt_run_sections :: proc(curve: Belt_Run_Curve, ups: [2][3]i64) -> Belt_Run_Sections {
	sections: Belt_Run_Sections
	for &section, step in sections {
		section = belt_run_section(curve, ups, step)
	}
	return sections
}

// The run's frame ups and its start's pitch in metres, found false when a
// frame is gone.
belt_run_frame_facts :: proc(entities: ^Entities, run: Belt_Run) -> (ups: [2][3]i64, pitch_metres: f32, found: bool) {
	for endpoint, role in run.endpoints {
		frame := find_frame(&entities.frames, endpoint.frame) or_return
		ups[role] = frame.axes[FRAME_UP]
		if role == BELT_RUN_START {
			pitch_metres = f32(frame.pitch_millimetres) / MILLIMETRES_PER_METRE
		}
	}
	return ups, pitch_metres, true
}

belt_run_vertex :: proc(position: [3]f32, u, v: f32) {
	rlgl.TexCoord2f(u, v)
	rlgl.Vertex3f(position.x, position.y, position.z)
}

// The surface as textured quads, both windings, BELT_SURFACE_HEIGHT of a
// cell over the polyline; v counts cells along the run less the scroll.
draw_belt_run_surface :: proc(texture: rl.Texture2D, textured: bool, sections: Belt_Run_Sections, pitch_metres, scroll: f32, color: rl.Color) {
	if textured {
		rlgl.SetTexture(texture.id)
	}
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	half, lift := pitch_metres / 2, pitch_metres * BELT_SURFACE_HEIGHT
	v := -scroll
	for step in 0 ..< BELT_RUN_SUBDIVISIONS {
		first, second := sections[step], sections[step + 1]
		next_v := v + linalg.length(second.centre - first.centre) / pitch_metres
		corners := [4][3]f32{first.centre - first.right * half + first.up * lift, first.centre + first.right * half + first.up * lift, second.centre + second.right * half + second.up * lift, second.centre - second.right * half + second.up * lift}
		texcoords := [4][2]f32{{0, v}, {1, v}, {1, next_v}, {0, next_v}}
		for index in ([8]int{0, 1, 2, 3, 0, 3, 2, 1}) {
			belt_run_vertex(corners[index], texcoords[index].x, texcoords[index].y)
		}
		v = next_v
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// The belt's sides: a band down from each edge of the surface, both
// windings, so the run reads as a belt seen edge on.
draw_belt_run_sides :: proc(sections: Belt_Run_Sections, pitch_metres: f32, color: rl.Color) {
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	half, lift, depth := pitch_metres / 2, pitch_metres * BELT_SURFACE_HEIGHT, pitch_metres * BELT_RUN_SIDE_DEPTH_SHARE
	for step in 0 ..< BELT_RUN_SUBDIVISIONS {
		first, second := sections[step], sections[step + 1]
		for side in ([2]f32{-1, 1}) {
			top_first := first.centre + first.right * (half * side) + first.up * lift
			top_second := second.centre + second.right * (half * side) + second.up * lift
			corners := [4][3]f32{top_first, top_second, top_second - second.up * depth, top_first - first.up * depth}
			for index in ([8]int{0, 1, 2, 3, 0, 3, 2, 1}) {
				rlgl.Vertex3f(corners[index].x, corners[index].y, corners[index].z)
			}
		}
	}
	rlgl.End()
}

draw_pipe_run :: proc(sections: Belt_Run_Sections, pitch_metres: f32) {
	radius := pitch_metres * PIPE_RUN_RADIUS_SHARE
	for step in 0 ..< BELT_RUN_SUBDIVISIONS {
		first, second := sections[step], sections[step + 1]
		rl.DrawCylinderEx(first.centre + first.up * radius, second.centre + second.up * radius, radius, radius, PIPE_RUN_SIDES, PIPE_COLOR)
	}
}

// A run's frame facts read once a pass (belt_run_facts) and whether the
// pass's view shows its box (0347).
Belt_Run_View :: struct {
	shown, found: bool,
	ups:          [2][3]i64,
	pitch_metres: f32,
}

// What draw_belt_runs culls and instances with (0347): the scene's view
// (nil draws everything), the pass's frame table (nil scans the frames),
// the models (their unit cube and the model shader) and the viewport's
// items buffer (nil draws the items one by one). Zero is the draw of
// before.
Belt_Run_Draw :: struct {
	view:   ^Model_View,
	frames: ^Frame_Matrix_Table,
	models: Model_Renderer,
	items:  ^Instance_Buffer,
}

// The polyline's points in metres widened by a pitch: everything drawn
// lies within 0.71 of a pitch of its section's point (half a pitch across,
// the tube's top half a pitch up, an item 0.35 across and 0.23 up).
belt_run_box :: proc(curve: Belt_Run_Curve, pitch_metres: f32) -> (minimum, maximum: [3]f32) {
	minimum, maximum = world_position_to_metres(curve.polyline[0]), world_position_to_metres(curve.polyline[0])
	for point in curve.polyline {
		metres := world_position_to_metres(point)
		for axis in 0 ..< 3 {
			minimum[axis] = min(minimum[axis], metres[axis])
			maximum[axis] = max(maximum[axis], metres[axis])
		}
	}
	return minimum - pitch_metres, maximum + pitch_metres
}

belt_pole_box :: proc(bottom, top: [3]f32) -> (minimum, maximum: [3]f32) {
	for axis in 0 ..< 3 {
		minimum[axis] = min(bottom[axis], top[axis])
		maximum[axis] = max(bottom[axis], top[axis])
	}
	return minimum - BELT_RUN_POLE_RADIUS_METRES, maximum + BELT_RUN_POLE_RADIUS_METRES
}

// belt_run_frame_facts, through the pass's table when there is one.
belt_run_facts :: proc(table: ^Frame_Matrix_Table, entities: ^Entities, run: Belt_Run) -> (ups: [2][3]i64, pitch_metres: f32, found: bool) {
	if table == nil {
		return belt_run_frame_facts(entities, run)
	}
	for endpoint, role in run.endpoints {
		entry := find_frame_matrix(table^, endpoint.frame) or_return
		ups[role] = entry.frame.axes[FRAME_UP]
		if role == BELT_RUN_START {
			pitch_metres = f32(entry.frame.pitch_millimetres) / MILLIMETRES_PER_METRE
		}
	}
	return ups, pitch_metres, true
}

// By the runs pool's index: each alive run's facts and whether the view
// shows its box.
belt_run_views :: proc(entities: ^Entities, draw: Belt_Run_Draw, allocator := context.temp_allocator) -> []Belt_Run_View {
	views := make([]Belt_Run_View, len(entities.belt_runs.entries), allocator)
	for run, index in entities.belt_runs.entries {
		if !run.alive {
			continue
		}
		view := &views[index]
		view.ups, view.pitch_metres, view.found = belt_run_facts(draw.frames, entities, run)
		if view.found {
			minimum, maximum := belt_run_box(run.curve, view.pitch_metres)
			view.shown = model_view_shows(draw.view, minimum, maximum)
		}
	}
	return views
}

// The item's cube at its distance along its run through
// belt_run_point_at, offset to its lane: its centre, its size and its
// colour; found false on a run not shown.
belt_run_item_cube :: proc(entities: ^Entities, items: Item_Registry, views: []Belt_Run_View, line: Belt_Line, lane: Belt_Lane, entry: Lane_Item) -> (centre: [3]f32, size: f32, color: rl.Color, found: bool) {
	segment := belt_line_segment_at(line, entry.position)
	handle := line.belts[segment]
	run := pool_get(&entities.belt_runs, handle)
	if run == nil || int(handle.index) >= len(views) || !views[handle.index].shown {
		return
	}
	view := views[handle.index]
	point, step := belt_run_point_at(run^, entry.position - belt_line_segment_start(line, segment))
	section := belt_run_section(run.curve, view.ups, step)
	side := lane == .Right ? f32(BELT_LANE_OFFSET) : -f32(BELT_LANE_OFFSET)
	size = BELT_ITEM_SIZE * view.pitch_metres
	centre = world_position_to_metres(point) + section.right * side * view.pitch_metres + section.up * (BELT_SURFACE_HEIGHT * view.pitch_metres + size / 2)
	return centre, size, item_cube_color(items, entry.item), true
}

// The unit cube to the centre scaled by the size, the colour in the
// bottom row.
belt_item_instance :: proc(centre: [3]f32, size: f32, color: rl.Color) -> matrix[4, 4]f32 {
	transform := matrix[4, 4]f32{
		size, 0, 0, centre.x,
		0, size, 0, centre.y,
		0, 0, size, centre.z,
		0, 0, 0, 1,
	}
	return instance_matrix_with_color(transform, color)
}

// The items of every line on its shown runs' segments
// (belt_run_item_cube): one instanced draw of the unit cube unlit, each
// item's colour its own, with the model shader's instancing and the items
// buffer; else a cube each.
draw_belt_run_items :: proc(entities: ^Entities, items: Item_Registry, views: []Belt_Run_View, draw: Belt_Run_Draw) {
	instanced := draw.models.instancing_ready && draw.items != nil
	instances := make([dynamic]matrix[4, 4]f32, context.temp_allocator)
	for line in entities.belt_network.lines {
		if len(line.segment_starts) == 0 {
			continue
		}
		for lane in Belt_Lane {
			for entry in line.lanes[lane] {
				centre, size, color, found := belt_run_item_cube(entities, items, views, line, lane, entry)
				switch {
				case !found:
				case instanced:
					append(&instances, belt_item_instance(centre, size, color))
				case:
					rl.DrawCube(centre, size, size, size, color)
				}
			}
		}
	}
	if len(instances) == 0 {
		return
	}
	upload_instances_in_place(&draw.items.buffer, &draw.items.capacity, instances[:])
	begin_flat_instances(draw.models, true)
	draw_mesh_instances(draw.models.unit_cube, draw.items.buffer, 0, len(instances))
	end_flat_instances(draw.models)
}

// Each alive pole on a known frame whose box the view shows.
draw_belt_poles :: proc(entities: ^Entities, machines: Machine_Registry, draw: Belt_Run_Draw) {
	for pole in entities.belt_poles.entries {
		if !pole.alive {
			continue
		}
		frame: Frame
		found: bool
		if draw.frames != nil {
			entry: Frame_Matrix_Entry
			entry, found = find_frame_matrix(draw.frames^, pole.frame)
			frame = entry.frame
		} else {
			frame, found = find_frame(&entities.frames, pole.frame)
		}
		if !found {
			continue
		}
		bottom := world_position_to_metres(frame_cell_bottom(frame, pole.origin))
		top := world_position_to_metres(belt_pole_top(frame, pole.origin, int(machines.machines[pole.machine].height_millimetres)))
		if minimum, maximum := belt_pole_box(bottom, top); model_view_shows(draw.view, minimum, maximum) {
			rl.DrawCylinderEx(bottom, top, BELT_RUN_POLE_RADIUS_METRES, BELT_RUN_POLE_RADIUS_METRES, BELT_RUN_POLE_SIDES, BELT_RUN_POLE_COLOR)
		}
	}
}

// Inside BeginMode3D: the poles, the runs and the items on them, each run
// and pole only where the view shows its box (0347). The belts' texture
// scrolls per run at its belt's speed.
draw_belt_runs :: proc(renderer: ^Belt_Renderer, entities: ^Entities, machines: Machine_Registry, items: Item_Registry, tick: u64, tick_rate: int, draw: Belt_Run_Draw) {
	views := belt_run_views(entities, draw)
	begin_flat_batch(draw.models)
	draw_belt_poles(entities, machines, draw)
	for run, index in entities.belt_runs.entries {
		if !run.alive || !views[index].found || !views[index].shown {
			continue
		}
		ups, pitch_metres := views[index].ups, views[index].pitch_metres
		sections := belt_run_sections(run.curve, ups)
		switch run.kind {
		case .Belt:
			units_per_tick := machines.machines[run.machine].belt_speed_units_per_second / u32(max(tick_rate, 1))
			draw_belt_run_surface(renderer.texture, renderer.ready, sections, pitch_metres, belt_scroll_offset(tick, 0, units_per_tick), rl.WHITE)
			draw_belt_run_sides(sections, pitch_metres, BELT_RUN_SIDE_COLOR)
		case .Pipe:
			draw_pipe_run(sections, pitch_metres)
		}
	}
	// Before the items, whose instanced draw sets the switches itself.
	end_flat_batch(draw.models)
	draw_belt_run_items(entities, items, views, draw)
}

// The run Place would lay, see-through, red when it would be refused.
draw_belt_run_ghost :: proc(curve: Belt_Run_Curve, geometry: Belt_Run_Geometry, allowed: bool) {
	sections := belt_run_sections(curve, geometry.ups)
	pitch_metres := f32(geometry.pitch_millimetres) / MILLIMETRES_PER_METRE
	draw_belt_run_surface({}, false, sections, pitch_metres, 0, allowed ? BELT_RUN_GHOST_COLOR : BELT_RUN_REFUSED_COLOR)
}
