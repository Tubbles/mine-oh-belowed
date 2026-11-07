package game

import "core:testing"

// The Tech demo screen's rows (0291) step their choices over the default
// planet's presets and the two enums, and Start asks the loop for the
// demo session.
@(test)
test_the_tech_demo_screen_steps_its_rows_and_asks_the_loop :: proc(t: ^testing.T) {
	planets := shipped_test_planets()
	setup := DEFAULT_TECH_DEMO_SETUP
	testing.expect_value(t, tech_demo_radius_metres(setup, planets), 8000)
	testing.expect_value(t, tech_demo_radius_metres(setup, nil), 0)
	step_tech_demo_radius(&setup, planets)
	testing.expect_value(t, setup.planet_radius_metres, 16000)
	step_tech_demo_radius(&setup, planets)
	testing.expect_value(t, setup.planet_radius_metres, 4000)
	step_tech_demo_radius(&setup, planets)
	testing.expect_value(t, setup.planet_radius_metres, 8000)
	step_tech_demo_radius(&setup, nil)
	testing.expect_value(t, setup.planet_radius_metres, 8000)
	step_tech_demo_model(&setup)
	testing.expect_value(t, setup.water_model, Water_Model.Bodies)
	step_tech_demo_model(&setup)
	testing.expect_value(t, setup.water_model, Water_Model.Teleport)
	step_tech_demo_start(&setup)
	testing.expect_value(t, setup.start, Tech_Demo_Start.Home)
	step_tech_demo_start(&setup)
	testing.expect_value(t, setup.start, Tech_Demo_Start.Spring)

	title := audit_title_state()
	defer {
		destroy_save_summaries(&title.saves)
		delete(title.saves)
		destroy_multiplayer_state(&title.multiplayer)
	}
	testing.expect_value(t, title.request.kind, Session_Request_Kind.None)
	start_tech_demo(&title)
	testing.expect_value(t, title.request.kind, Session_Request_Kind.Tech_Demo)
}

title_button_id :: proc(key: string) -> Ui_Id {
	return ui_hash(ui_hash(0, "title", -1), text(key), -1)
}

tech_demos_button_id :: proc(key: string) -> Ui_Id {
	return ui_hash(ui_hash(0, "tech_demos", -1), text(key), -1)
}

// Work item 0302: the title's Tech demos button opens the list, the
// list's Water opens the water screen, and Back walks back to the title.
@(test) // slow
test_the_title_opens_the_tech_demos_list_and_the_water_screen :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Title)
	screen_test_frame(audit, &state, {})
	state.requested_focus = title_button_id("title_tech_demos")
	screen_test_frame(audit, &state, {device = .Gamepad, device_seen = true})
	testing.expect_value(t, state.focus, title_button_id("title_tech_demos"))
	screen_test_frame(audit, &state, {confirm = true, confirm_down = true, device = .Gamepad, device_seen = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Tech_Demos)
	testing.expect_value(t, state.screens.count, 2)

	state.requested_focus = tech_demos_button_id("tech_demos_water")
	screen_test_frame(audit, &state, {device = .Gamepad, device_seen = true})
	testing.expect_value(t, state.focus, tech_demos_button_id("tech_demos_water"))
	screen_test_frame(audit, &state, {confirm = true, confirm_down = true, device = .Gamepad, device_seen = true})
	testing.expect_value(t, state.screens.count, 3)
	testing.expect_value(t, state.screens.screens[0], Screen.Title)
	testing.expect_value(t, state.screens.screens[1], Screen.Tech_Demos)
	testing.expect_value(t, state.screens.screens[2], Screen.Tech_Demo)

	screen_test_frame(audit, &state, {back = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Tech_Demos)
	screen_test_frame(audit, &state, {back = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Title)
	testing.expect_value(t, state.screens.count, 1)
}

// The bare --tech-demo (0302) pushes the list and the water screen over
// the title, so Back walks the way it does from the title.
@(test)
test_the_bare_tech_demo_flag_opens_the_list_under_the_water_screen :: proc(t: ^testing.T) {
	screens: Screen_Stack
	push_screen(&screens, .Title)
	push_tech_demo_menu(&screens)
	testing.expect_value(t, screens.count, 3)
	testing.expect_value(t, screens.screens[0], Screen.Title)
	testing.expect_value(t, screens.screens[1], Screen.Tech_Demos)
	testing.expect_value(t, screens.screens[2], Screen.Tech_Demo)
}
