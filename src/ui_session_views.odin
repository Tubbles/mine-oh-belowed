package game

// The UI state that lives as long as a played world: the recipe and
// technology browsers, the statistics and the map. The loop keeps it beside
// the session (Frame_Interaction), not in it; enter_session makes it,
// leave_session destroys it and a content reload resets it, all between
// frames.
Session_Views :: struct {
	recipe_browser:     Recipe_Browser,
	// The crafting view's tab and Unlocked only (0277). Its focused recipe
	// and plans are the recipe browser's.
	crafting_view:      Crafting_View,
	technology_browser: Technology_Browser,
	statistics_view:    Statistics_View,
	map_view:           Map_View,
}

make_session_views :: proc() -> Session_Views {
	return Session_Views{recipe_browser = make_recipe_browser(), crafting_view = make_crafting_view(), technology_browser = make_technology_browser()}
}

// The technology browser and the statistics view own no memory.
destroy_session_views :: proc(views: ^Session_Views) {
	destroy_map_view(&views.map_view)
	destroy_recipe_browser(&views.recipe_browser)
}

// After a content reload: the views that hold content indices start over,
// and the map collects its surfaces again from the reloaded world.
reset_session_views :: proc(views: ^Session_Views, simulation: ^Simulation_State) {
	reset_recipe_browser(&views.recipe_browser)
	views.crafting_view = make_crafting_view()
	views.technology_browser = make_technology_browser()
	views.statistics_view.has_focus = false
	views.statistics_view.fluid_has_focus = false
	collect_explored_surfaces(&simulation.world, simulation.records.explored, &views.map_view.surfaces)
	views.map_view.painted_frame = {}
}
