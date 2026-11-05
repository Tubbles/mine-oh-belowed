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
