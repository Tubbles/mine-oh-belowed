package game

import "core:testing"

// A frame state without a window playing the debug terrain offline, its
// first viewport on pad 3 and the keyboard (work item 0178).
make_viewport_test_frame :: proc() -> ^Frame_State {
	state := new(Frame_State)
	state.config = test_game_config()
	state.content = Game_Content{simulation_content = make_save_test_content()}
	state.base_generator = make_test_generator(DEFAULT_WORLD_SEED)
	state.frame_seconds = 1.0 / f32(TEST_TICK_RATE)
	state.settings = DEFAULT_SETTINGS
	state.viewports[0] = Viewport{keyboard_mouse = true, gamepad = 3}
	state.viewport_count = 1
	plan := Session_Plan{debug_terrain = true, seed = DEFAULT_WORLD_SEED, settings = default_world_file_settings(state.config)}
	session, problem := start_session(plan, state.config, state.content, state.base_generator)
	assert(problem == "", problem)
	enter_session(state, session)
	place_viewports(state, {1920, 1080})
	return state
}

destroy_viewport_test_frame :: proc(state: ^Frame_State) {
	leave_session(state)
	destroy_viewport(&state.viewports[0])
	destroy_session_join(&state.joining)
	free(state)
}

// Frames of the session's update until the viewport's player has its
// entry (its join tick ran).
run_viewport_test_frames_until_ready :: proc(state: ^Frame_State, index: int) -> bool {
	for _ in 0 ..< 10 {
		if viewport_player_ready(state.session, state.viewports[index]) {
			return true
		}
		update_session(state, frame_simulation_content(state))
	}
	return viewport_player_ready(state.session, state.viewports[index])
}

@(test)
test_viewports_split_the_window_by_count_and_layout :: proc(t: ^testing.T) {
	screen := [2]int{1920, 1080}
	one := viewport_rectangles(1, screen, .Stacked)
	testing.expect_value(t, one[0], Pixel_Rectangle{0, 0, 1920, 1080})
	stacked := viewport_rectangles(2, screen, .Stacked)
	testing.expect_value(t, stacked[0], Pixel_Rectangle{0, 0, 1920, 540})
	testing.expect_value(t, stacked[1], Pixel_Rectangle{0, 540, 1920, 540})
	side := viewport_rectangles(2, {1921, 1080}, .Side_By_Side)
	testing.expect_value(t, side[0], Pixel_Rectangle{0, 0, 960, 1080})
	testing.expect_value(t, side[1], Pixel_Rectangle{960, 0, 961, 1080})
	for count in 3 ..= 4 {
		quarters := viewport_rectangles(count, screen, .Side_By_Side)
		testing.expect_value(t, quarters[0], Pixel_Rectangle{0, 0, 960, 540})
		testing.expect_value(t, quarters[3], Pixel_Rectangle{960, 540, 960, 540})
	}
	// Full screen keeps the setting; a half narrower than 16:9 fits the
	// 16:9 layout into its width, as the audit's side by side size does.
	testing.expect_value(t, viewport_ui_scale(1.2, {0, 0, 1280, 800}, 1), 1.2)
	testing.expect_value(t, viewport_ui_scale(1, quarters_of_1080p(), 4), 1)
	testing.expect_value(t, viewport_ui_scale(1, side[0], 2), f32(960) / 1080 / (16.0 / 9.0))
}

quarters_of_1080p :: proc() -> Pixel_Rectangle {
	return viewport_rectangles(4, {1920, 1080}, .Stacked)[1]
}

// The first viewport without a pad takes one at once; otherwise Start
// takes a viewport whose pad was lost, else adds one while there is room.
@(test)
test_a_free_pad_takes_or_adds_a_viewport :: proc(t: ^testing.T) {
	waiting := []Viewport{{keyboard_mouse = true}}
	claim, index := pad_claim(waiting, {}, false)
	testing.expect_value(t, claim, Pad_Claim.Take)
	testing.expect_value(t, index, 0)
	playing := []Viewport{{keyboard_mouse = true, gamepad = 3}}
	claim, _ = pad_claim(playing, {.Confirm}, true)
	testing.expect_value(t, claim, Pad_Claim.None)
	claim, _ = pad_claim(playing, {.Pause}, false)
	testing.expect_value(t, claim, Pad_Claim.None)
	claim, index = pad_claim(playing, {.Pause}, true)
	testing.expect_value(t, claim, Pad_Claim.Add)
	testing.expect_value(t, index, 1)
	lost := []Viewport{{keyboard_mouse = true, gamepad = 3}, {gamepad = 4, player = 1}}
	lose_viewport_pad(lost, 4)
	testing.expect(t, viewport_waits_for_pad(lost[1], len(lost)))
	claim, index = pad_claim(lost, {.Pause}, true)
	testing.expect_value(t, claim, Pad_Claim.Take)
	testing.expect_value(t, index, 1)
	full := []Viewport{{gamepad = 3}, {gamepad = 4}, {gamepad = 5}, {gamepad = 6}}
	claim, _ = pad_claim(full, {.Pause}, true)
	testing.expect_value(t, claim, Pad_Claim.None)
	// A keyboard first viewport without a pad does not take a free pad
	// silently while a guest waits for its own; Start gives it the guest.
	both_lost := []Viewport{{keyboard_mouse = true}, {player = 1, pad_lost = true}}
	claim, _ = pad_claim(both_lost, {}, true)
	testing.expect_value(t, claim, Pad_Claim.None)
	claim, index = pad_claim(both_lost, {.Pause}, true)
	testing.expect_value(t, claim, Pad_Claim.Take)
	testing.expect_value(t, index, 1)
}

// A guest whose player has no entry yet presses the inventory key: the
// screens that need the player stay shut, and a pause menu over a journal
// keeps only the pause menu, which draws without the world.
@(test)
test_a_joining_viewport_opens_no_screen_that_needs_its_player :: proc(t: ^testing.T) {
	state := make_viewport_test_frame()
	defer destroy_viewport_test_frame(state)
	add_viewport(state, 9, {})
	place_viewports(state, {1920, 1080})
	viewport := &state.viewports[1]
	testing.expect(t, !viewport_player_ready(state.session, viewport^))
	viewport.interaction.input = Input_Frame{pressed = {.Open_Inventory}, just_pressed = {.Open_Inventory}}
	build_viewport_ui(state, 1)
	viewport.interaction.previous_input = viewport.interaction.input
	build_viewport_ui(state, 1)
	testing.expect_value(t, viewport.interaction.ui.screens.count, 0)
	push_screen(&viewport.interaction.ui.screens, .Pause)
	push_screen(&viewport.interaction.ui.screens, .Journal)
	viewport.interaction.input, viewport.interaction.previous_input = {}, {}
	build_viewport_ui(state, 1)
	testing.expect_value(t, viewport.interaction.ui.screens.count, 1)
	testing.expect_value(t, top_screen(viewport.interaction.ui.screens), Screen.Pause)
	testing.expect(t, len(viewport.interaction.ui.draw_list) > 0)
	finish_ui_frame_without_window(state)
}

// A guest whose pad was lost keeps its player in the world: its records
// go on (an empty pad reads nothing), so the session never waits for it.
@(test)
test_a_lost_pads_viewport_keeps_stamping_while_the_session_advances :: proc(t: ^testing.T) {
	state := make_viewport_test_frame()
	defer destroy_viewport_test_frame(state)
	session := state.session
	add_viewport(state, 9, {})
	if !testing.expect(t, run_viewport_test_frames_until_ready(state, 1)) {
		return
	}
	lose_viewport_pad(active_viewports(state), 9)
	state.viewports[1].interaction.input = {}
	tick := session.simulation.tick
	for _ in 0 ..< 10 {
		update_session(state, frame_simulation_content(state))
	}
	testing.expect(t, session.simulation.tick >= tick + 9)
	testing.expect(t, state.viewports[1].pad_lost)
	testing.expect_value(t, session.lockstep.locals[1].next_tick, session.simulation.tick + 1)
}

// Start on a free pad adds a viewport whose player joins at the start
// position (the pod), through a join's add player path.
@(test)
test_a_pad_press_adds_a_viewport_and_a_player_at_the_start :: proc(t: ^testing.T) {
	state := make_viewport_test_frame()
	defer destroy_viewport_test_frame(state)
	session := state.session
	claim, index := pad_claim(active_viewports(state), {.Pause}, true)
	testing.expect_value(t, claim, Pad_Claim.Add)
	testing.expect(t, add_viewport(state, 9, {.Pause}))
	testing.expect_value(t, state.viewport_count, 2)
	viewport := state.viewports[index]
	testing.expect_value(t, viewport.gamepad, u32(9))
	testing.expect_value(t, viewport.player, 1)
	testing.expect_value(t, len(session.lockstep.locals), 2)
	// The held Start is no fresh press in the new viewport.
	testing.expect(t, .Pause in viewport.interaction.input.pressed)
	if !testing.expect(t, run_viewport_test_frames_until_ready(state, 1)) {
		return
	}
	testing.expect_value(t, len(session.simulation.players), 2)
	start_player := make_player(session.start.player)
	defer destroy_player(start_player)
	testing.expect_value(t, session.simulation.players[1].position, start_player.position)
}

// Two viewports, one simulation: each camera follows its own player, and
// each UI pass draws its own draw list from its own player.
@(test)
test_two_viewports_draw_two_draw_lists_with_different_cameras :: proc(t: ^testing.T) {
	state := make_viewport_test_frame()
	defer destroy_viewport_test_frame(state)
	session := state.session
	add_viewport(state, 9, {})
	if !testing.expect(t, run_viewport_test_frames_until_ready(state, 1)) {
		return
	}
	place_viewports(state, {1920, 1080})
	session.simulation.players[1].position += {12, 0, 5}
	session.simulation.players[1].previous_position = session.simulation.players[1].position
	session.simulation.players[1].selected_hotbar_slot = 4
	content := frame_simulation_content(state)
	cameras: [2]Camera_Position
	for index in 0 ..< 2 {
		viewport := &state.viewports[index]
		player := lockstep_view_player(&session.lockstep, &session.simulation, viewport.player)
		animation := player_animation_state(viewport.presentation.player_animation, player, interpolate_player_pose(player, 0).pitch, 0)
		camera, _ := viewport_camera(state, viewport, content, player, animation, 0)
		cameras[index] = camera.position
		testing.expect_value(t, viewport.presentation.camera.position, camera.position)
		build_viewport_ui(state, index)
		testing.expect(t, len(viewport.interaction.ui.draw_list) > 0)
		testing.expect_value(t, viewport.interaction.ui.screen_units.y, 1080)
	}
	testing.expect(t, cameras[0] != cameras[1])
	first, second := state.viewports[0].interaction.ui.draw_list[:], state.viewports[1].interaction.ui.draw_list[:]
	differ := len(first) != len(second)
	for index in 0 ..< min(len(first), len(second)) {
		differ ||= first[index].rectangle != second[index].rectangle || first[index].color != second[index].color || first[index].text != second[index].text
	}
	testing.expect(t, differ)
	finish_ui_frame_without_window(state)
}

Camera_Position :: [3]f32

// finish_ui_frame's part that needs no window.
finish_ui_frame_without_window :: proc(state: ^Frame_State) {
	clear(&state.session.simulation.events)
	clear(&state.session.simulation.quests.notices)
	collect_global_requests(state)
}

// A screenshot asked for in the second viewport toasts there, not in the
// first. No state directory in the test: the screenshot fails and says
// so in the asking viewport.
@(test)
test_a_screen_request_from_the_second_viewport_serves_its_screen :: proc(t: ^testing.T) {
	state := make_viewport_test_frame()
	defer destroy_viewport_test_frame(state)
	add_viewport(state, 9, {})
	state.viewports[1].requests += {.Take_Screenshot}
	for index in 0 ..< state.viewport_count {
		queue_requested_screenshot(state, index)
	}
	testing.expect_value(t, len(state.viewports[0].interaction.ui.toasts), 0)
	testing.expect_value(t, len(state.viewports[1].interaction.ui.toasts), 1)
	testing.expect(t, .Take_Screenshot not_in state.viewports[1].requests)
	testing.expect_value(t, state.developer.command_control.screenshot_path, "")
}

// Two viewports asking for the content reload in one frame reload once:
// the game's requests move to the frame's set. A join in progress refuses
// the reload with one toast, so nothing loads.
@(test)
test_a_global_request_serves_once :: proc(t: ^testing.T) {
	state := make_viewport_test_frame()
	defer destroy_viewport_test_frame(state)
	add_viewport(state, 9, {})
	state.viewports[0].requests += {.Reload_Data}
	state.viewports[1].requests += {.Reload_Data, .Take_Screenshot}
	collect_global_requests(state)
	testing.expect_value(t, state.requests, Frame_Requests{.Reload_Data})
	testing.expect_value(t, state.viewports[0].requests, Frame_Requests{})
	testing.expect_value(t, state.viewports[1].requests, Frame_Requests{.Take_Screenshot})
	state.joining.network.role = .Client
	apply_reload_request(state)
	apply_reload_request(state)
	testing.expect_value(t, len(primary_ui(state).toasts), 1)
	testing.expect_value(t, len(state.viewports[1].interaction.ui.toasts), 0)
	testing.expect_value(t, state.requests, Frame_Requests{})
}

// Four viewports feed one tick a frame: each stamps one record for its
// player, the tick runs once and adds the three joined players.
@(test)
test_the_frame_with_four_viewports_runs_the_tick_once :: proc(t: ^testing.T) {
	state := make_viewport_test_frame()
	defer destroy_viewport_test_frame(state)
	session := state.session
	for gamepad in u32(5) ..= 7 {
		testing.expect(t, add_viewport(state, gamepad, {}))
	}
	testing.expect(t, !add_viewport(state, 8, {}))
	testing.expect_value(t, state.viewport_count, MAXIMUM_VIEWPORTS)
	tick := session.simulation.tick
	next_ticks: [MAXIMUM_VIEWPORTS]u64
	for local, index in session.lockstep.locals {
		next_ticks[index] = local.next_tick
	}
	state.frame_seconds = 1.5 / f32(TEST_TICK_RATE)
	update_session(state, frame_simulation_content(state))
	testing.expect_value(t, session.simulation.tick, tick + 1)
	testing.expect_value(t, state.frame_tick_count, 1)
	testing.expect_value(t, len(session.simulation.players), MAXIMUM_VIEWPORTS)
	for local, index in session.lockstep.locals {
		testing.expect_value(t, local.next_tick, next_ticks[index] + 1)
	}
	for viewport in active_viewports(state) {
		testing.expect(t, viewport_player_ready(session, viewport))
	}
}

// A guest viewport removed between frames: its player leaves from its
// next tick and keeps its entry, and a later Start takes that entry.
@(test)
test_a_removed_viewport_leaves_and_its_entry_is_taken_again :: proc(t: ^testing.T) {
	state := make_viewport_test_frame()
	defer destroy_viewport_test_frame(state)
	session := state.session
	add_viewport(state, 9, {})
	if !testing.expect(t, run_viewport_test_frames_until_ready(state, 1)) {
		return
	}
	// The guest's frame drew its pause menu; its leaving frees that UI
	// only after the draw.
	push_screen(&state.viewports[1].interaction.ui.screens, .Pause)
	build_viewport_ui(state, 1)
	testing.expect(t, len(state.viewports[1].interaction.ui.draw_list) > 0)
	state.viewports[1].requests += {.Remove_Viewport}
	serve_viewport_removals(state)
	testing.expect_value(t, state.viewport_count, 1)
	testing.expect_value(t, len(session.lockstep.locals), 1)
	testing.expect(t, session.lockstep.members[1].left_tick != NEVER_TICK)
	for _ in 0 ..< 3 {
		update_session(state, frame_simulation_content(state))
	}
	testing.expect_value(t, len(session.simulation.players), 2)
	add_viewport(state, 10, {})
	testing.expect_value(t, state.viewports[1].player, 1)
	testing.expect(t, run_viewport_test_frames_until_ready(state, 1))
	testing.expect_value(t, len(session.simulation.players), 2)
}

// The touch ring's point (0195): a block's centre in the block world; for
// a pick up on a frame, the mined cell's centre on its frame in metres;
// for a felling (0197), the aimed point of the trunk.
@(test)
test_the_mining_ring_sits_on_a_frame_cell :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	handle, frame_id := place_free_foundation(&entities, machines, test_foundation(machines), TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
	frame, _ := find_frame(&entities.frames, frame_id)
	tuning: Field_Player_Tuning
	on_frame := Player{mining = Mining_State{active = true, entity = handle}}
	testing.expect_value(t, mining_ring_point(&entities, on_frame, tuning), world_position_to_metres(frame_cell_centre(frame, {})))
	block := Player{mining = Mining_State{active = true, block = {3, 4, 5}}}
	testing.expect_value(t, mining_ring_point(&entities, block, tuning), block_centre({3, 4, 5}))
	felling := Player{mining = Mining_State{active = true, tree = true}}
	felling.field = make_field_player(World_Position{0, 8000 * POSITION_UNITS_PER_METRE, 0}, {UNIT_VECTOR_ONE, 0, 0})
	felling.field.tree_target = {hit = true, distance = 2 * POSITION_UNITS_PER_METRE}
	testing.expect_value(t, mining_ring_point(&entities, felling, tuning), [3]f32{2, 8000, 0})
}

// Work item 0194: one frame with the inventory binding pressed while the
// first player aims at target, its ticks and its UI pass.
press_open_inventory_frame :: proc(state: ^Frame_State, target: Entity_Handle) {
	session := state.session
	session.simulation.players[0].target = Raycast_Hit{hit = target != NO_ENTITY, entity = target}
	viewport := &state.viewports[0]
	viewport.interaction.previous_input = {}
	viewport.interaction.input = Input_Frame{pressed = {.Open_Inventory}, just_pressed = {.Open_Inventory}}
	state.frame_seconds = 1.5 / f32(TEST_TICK_RATE)
	tick := session.simulation.tick
	update_frame_world(state)
	// The tick the press rode in ran this frame.
	assert(session.simulation.tick > tick)
	build_viewport_ui(state, 0)
}

frame_has_event :: proc(state: ^Frame_State, kind: Player_Event) -> bool {
	for event in state.session.simulation.events {
		if event.player == 0 && event.kind == kind {
			return true
		}
	}
	return false
}

// The inventory binding aimed at a furnace in reach opens its panel
// through the simulation and no inventory screen.
@(test)
test_the_inventory_binding_aimed_at_a_furnace_opens_its_panel :: proc(t: ^testing.T) {
	state := make_viewport_test_frame()
	defer destroy_viewport_test_frame(state)
	if !testing.expect(t, run_viewport_test_frames_until_ready(state, 0)) {
		return
	}
	simulation := &state.session.simulation
	content := frame_simulation_content(state)
	cell := camera_world_coordinate(simulation.players[0].position) + {2, 0, 0}
	furnace := add_entity(&simulation.world.entities, content.machines, test_machine(content.machines, "steel_furnace"), cell, 0)
	clear(&simulation.events)
	press_open_inventory_frame(state, furnace)
	testing.expect(t, frame_has_event(state, .Open_Machine))
	testing.expect_value(t, simulation.players[0].open_machine, furnace)
	screens := state.viewports[0].interaction.ui.screens
	testing.expect_value(t, screens.count, 1)
	testing.expect_value(t, top_screen(screens), Screen.Machine)
}

// Aimed at the ground the same press opens the inventory, and the
// simulation sees no open.
@(test)
test_the_inventory_binding_aimed_at_the_ground_opens_the_inventory :: proc(t: ^testing.T) {
	state := make_viewport_test_frame()
	defer destroy_viewport_test_frame(state)
	if !testing.expect(t, run_viewport_test_frames_until_ready(state, 0)) {
		return
	}
	simulation := &state.session.simulation
	clear(&simulation.events)
	press_open_inventory_frame(state, NO_ENTITY)
	testing.expect(t, !frame_has_event(state, .Open_Machine))
	testing.expect_value(t, simulation.players[0].open_machine, NO_ENTITY)
	screens := state.viewports[0].interaction.ui.screens
	testing.expect_value(t, screens.count, 1)
	testing.expect_value(t, top_screen(screens), Screen.Inventory)
}
