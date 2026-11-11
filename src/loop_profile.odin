package game

import rl "shared:raylib"

// The frame profile's commands (work item 0342, doc/commands.md, Frame
// profile): profile, viewport and query profile need the frame, so the
// loop serves them like save (execute_queued_command). profile and
// viewport answer later, from answer_profile_wait once a frame.

// A view is settled once this many frames in a row had every selected
// node meshed and the trees' tiles up.
PROFILE_SETTLED_FRAMES :: 30

// The GPU is timed while the Render page shows or a sample runs.
frame_gpu_wanted :: proc(state: ^Frame_State) -> bool {
	return state.developer.diagnostics_page == .Render || state.developer.frame_profile.sampling
}

profile_display :: proc(state: ^Frame_State) -> Profile_Display {
	return Profile_Display {
		render = render_size(),
		window = {int(rl.GetScreenWidth()), int(rl.GetScreenHeight())},
		viewports = state.viewport_count,
		vsync = state.settings.vsync,
		frame_rate_cap = state.settings.frame_rate_cap,
	}
}

// profile, viewport and query profile: the lines the loop serves here.
profile_line :: proc(words: []string) -> bool {
	switch {
	case len(words) == 0:
		return false
	case words[0] == "profile" || words[0] == "viewport":
		return true
	}
	return words[0] == "query" && len(words) > 1 && words[1] == "profile"
}

execute_profile_line :: proc(state: ^Frame_State, client: u64, words: []string) -> Command_Response {
	if state.session == nil {
		return command_error("no world is loaded")
	}
	switch words[0] {
	case "profile":
		return command_profile(state, client, words[1:])
	case "viewport":
		return command_viewport(state, client, words[1:])
	}
	if len(words) != 2 {
		return usage_error("query profile")
	}
	profile := &state.developer.frame_profile
	if profile.sampling || len(profile.sample.records) == 0 {
		return command_error("no profile sample: run profile sample <frames> first")
	}
	sample := profile.sample
	return profile_report_response(frame_profile_report(sample.records[:], sample.gpu[:], sample.gpu_dropped, sample.display))
}

// profile settle [frames] or profile sample <frames>: the wait set, a
// sample started; answered by answer_profile_wait.
command_profile :: proc(state: ^Frame_State, client: u64, arguments: []string) -> Command_Response {
	wait, frames, problem := parse_profile_command(arguments)
	if problem != "" {
		return command_error("%s", problem)
	}
	if wait == .Settle && !state.session.simulation.field.enabled {
		return command_error(NO_FIELD_WORLD_PROBLEM)
	}
	control := &state.developer.command_control
	control.profile_wait, control.profile_client = wait, client
	control.profile_frames_left, control.profile_frames_waited, control.profile_settled_frames = frames, 0, 0
	if wait == .Sample {
		start_frame_sample(&state.developer.frame_profile, frames)
	}
	return Command_Response{ok = true, deferred = true}
}

// The new player's entry comes with a tick, so a viewport add under held
// ticks would wait, and hold every later line, forever.
VIEWPORT_ADD_HELD_PROBLEM :: "viewport add needs the ticks running"

// viewport add: a viewport with a new local player and no pad, answered
// once the player has its entry, refused while the ticks are held.
// viewport remove: every viewport but the first asked to leave through
// Remove_Viewport, which the loop serves after the draw, answered once one
// is left.
command_viewport :: proc(state: ^Frame_State, client: u64, arguments: []string) -> Command_Response {
	add, problem := parse_viewport_command(arguments)
	if problem != "" {
		return command_error("%s", problem)
	}
	control := &state.developer.command_control
	if add {
		if session_ticks_held(state) {
			return command_error(VIEWPORT_ADD_HELD_PROBLEM)
		}
		if state.viewport_count >= MAXIMUM_VIEWPORTS {
			return command_error("%d viewports already", MAXIMUM_VIEWPORTS)
		}
		add_viewport(state, 0, {})
		control.profile_wait, control.profile_client, control.profile_viewport = .Viewport_Added, client, state.viewport_count - 1
		return Command_Response{ok = true, deferred = true}
	}
	if state.viewport_count == 1 {
		return command_ok("viewports 1")
	}
	for index in 1 ..< state.viewport_count {
		state.viewports[index].requests += {.Remove_Viewport}
	}
	control.profile_wait, control.profile_client = .Viewports_Removed, client
	return Command_Response{ok = true, deferred = true}
}

// Once a frame: answers the waiting profile or viewport command when its
// wait is over. A settle or viewport wait ends with an error when the
// world closes, and a viewport add's when the ticks are held before its
// player has its entry; a sample completes regardless.
answer_profile_wait :: proc(state: ^Frame_State) {
	control := &state.developer.command_control
	if control.profile_wait == .None {
		return
	}
	response, answered := profile_wait_response(state)
	if !answered {
		return
	}
	send_logged_response(state, control.profile_client, "a waiting profile line", response)
	control.profile_wait, control.profile_client = .None, 0
}

profile_wait_response :: proc(state: ^Frame_State) -> (response: Command_Response, answered: bool) {
	control := &state.developer.command_control
	if control.profile_wait != .Sample && state.session == nil {
		return command_error("the world was closed"), true
	}
	switch control.profile_wait {
	case .None:
	case .Settle:
		return settle_wait_response(state)
	case .Sample:
		profile := &state.developer.frame_profile
		if !frame_sample_complete(profile^) {
			return {}, false
		}
		profile.sample.display = profile_display(state)
		profile.sampling = false
		return command_ok("sampled %d frames", len(profile.sample.records)), true
	case .Viewport_Added:
		if control.profile_viewport >= state.viewport_count {
			return command_error("the viewport was removed"), true
		}
		viewport := state.viewports[control.profile_viewport]
		if !viewport_player_ready(state.session, viewport) {
			if session_ticks_held(state) {
				return command_error(VIEWPORT_ADD_HELD_PROBLEM), true
			}
			return {}, false
		}
		return command_ok("viewport %d of %d, player %d", control.profile_viewport + 1, state.viewport_count, viewport.player), true
	case .Viewports_Removed:
		if state.viewport_count > 1 {
			return {}, false
		}
		return command_ok("viewports 1"), true
	}
	return {}, false
}

// One frame of a settle: settled after PROFILE_SETTLED_FRAMES in a row
// with no selected node unmeshed and the trees' tiles up, refused at the
// limit.
settle_wait_response :: proc(state: ^Frame_State) -> (response: Command_Response, answered: bool) {
	control := &state.developer.command_control
	session := state.session
	renderer := &state.presentation.field_renderer
	unmeshed := field_view_unmeshed_nodes(&session.field_streaming, renderer, frame_field_selection(state))
	trees_settled := field_tree_cache_settled(&renderer.trees, field_tree_generation(&session.simulation.field), field_viewport_eyes(state))
	control.profile_frames_waited += 1
	control.profile_frames_left -= 1
	control.profile_settled_frames = unmeshed == 0 && trees_settled ? control.profile_settled_frames + 1 : 0
	switch {
	case control.profile_settled_frames >= PROFILE_SETTLED_FRAMES:
		return command_ok("settled after %d frames", control.profile_frames_waited), true
	case control.profile_frames_left <= 0:
		return command_error("not settled after %d frames: %d nodes unmeshed, trees %s", control.profile_frames_waited, unmeshed, trees_settled ? "settled" : "loading"), true
	}
	return {}, false
}
