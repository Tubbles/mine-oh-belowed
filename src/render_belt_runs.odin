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
// bottom to its run end. Floats are made here only.

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

// The items of every line on its runs' segments, each at its distance
// through belt_run_point_at and offset to its lane.
draw_belt_run_items :: proc(entities: ^Entities, items: Item_Registry) {
	for line in entities.belt_network.lines {
		if len(line.segment_starts) == 0 {
			continue
		}
		for lane in Belt_Lane {
			for entry in line.lanes[lane] {
				draw_belt_run_item(entities, items, line, lane, entry)
			}
		}
	}
}

draw_belt_run_item :: proc(entities: ^Entities, items: Item_Registry, line: Belt_Line, lane: Belt_Lane, entry: Lane_Item) {
	segment := belt_line_segment_at(line, entry.position)
	run := pool_get(&entities.belt_runs, line.belts[segment])
	if run == nil {
		return
	}
	ups, pitch_metres, found := belt_run_frame_facts(entities, run^)
	if !found {
		return
	}
	point, step := belt_run_point_at(run^, entry.position - belt_line_segment_start(line, segment))
	section := belt_run_section(run.curve, ups, step)
	side := lane == .Right ? f32(BELT_LANE_OFFSET) : -f32(BELT_LANE_OFFSET)
	size := BELT_ITEM_SIZE * pitch_metres
	centre := world_position_to_metres(point) + section.right * side * pitch_metres + section.up * (BELT_SURFACE_HEIGHT * pitch_metres + size / 2)
	rl.DrawCube(centre, size, size, size, item_cube_color(items, entry.item))
}

draw_belt_poles :: proc(entities: ^Entities, machines: Machine_Registry) {
	for pole in entities.belt_poles.entries {
		frame, found := find_frame(&entities.frames, pole.frame)
		if !pole.alive || !found {
			continue
		}
		bottom := world_position_to_metres(frame_cell_bottom(frame, pole.origin))
		top := world_position_to_metres(belt_pole_top(frame, pole.origin, int(machines.machines[pole.machine].height_millimetres)))
		rl.DrawCylinderEx(bottom, top, BELT_RUN_POLE_RADIUS_METRES, BELT_RUN_POLE_RADIUS_METRES, BELT_RUN_POLE_SIDES, BELT_RUN_POLE_COLOR)
	}
}

// Inside BeginMode3D: the poles, the runs and the items on them. The
// belts' texture scrolls per run at its belt's speed.
draw_belt_runs :: proc(renderer: ^Belt_Renderer, entities: ^Entities, machines: Machine_Registry, items: Item_Registry, tick: u64, tick_rate: int) {
	draw_belt_poles(entities, machines)
	for run in entities.belt_runs.entries {
		ups, pitch_metres, found := belt_run_frame_facts(entities, run)
		if !run.alive || !found {
			continue
		}
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
	draw_belt_run_items(entities, items)
}

// The run Place would lay, see-through, red when it would be refused.
draw_belt_run_ghost :: proc(curve: Belt_Run_Curve, geometry: Belt_Run_Geometry, allowed: bool) {
	sections := belt_run_sections(curve, geometry.ups)
	pitch_metres := f32(geometry.pitch_millimetres) / MILLIMETRES_PER_METRE
	draw_belt_run_surface({}, false, sections, pitch_metres, 0, allowed ? BELT_RUN_GHOST_COLOR : BELT_RUN_REFUSED_COLOR)
}
