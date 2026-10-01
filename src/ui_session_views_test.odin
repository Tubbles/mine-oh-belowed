package game

import "core:testing"

// What a content reload clears: the browsers start over, the statistics
// lose focus, the map's surfaces are collected again from the explored
// records and its image is painted again.
@(test)
test_session_views_reset_for_a_reloaded_world :: proc(t: ^testing.T) {
	simulation, _ := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	views := make_session_views()
	defer destroy_session_views(&views)
	views.recipe_browser.filter.craftable_only = true
	views.recipe_browser.filter.available_only = false
	views.recipe_browser.focused_recipe = 0
	views.technology_browser.focused = 0
	views.technology_browser.filter.hide_researched = true
	views.statistics_view.has_focus = true
	views.statistics_view.fluid_has_focus = true
	stale_column := Chunk_Column{1000, 1000}
	views.map_view.surfaces[stale_column] = {}
	views.map_view.painted_frame = {size = 8, blocks_per_pixel = 1}
	reset_session_views(&views, &simulation)
	testing.expect_value(t, views.recipe_browser.filter, make_recipe_browser().filter)
	testing.expect_value(t, views.recipe_browser.focused_recipe, NO_RECIPE)
	testing.expect_value(t, views.technology_browser, make_technology_browser())
	testing.expect(t, !views.statistics_view.has_focus)
	testing.expect(t, !views.statistics_view.fluid_has_focus)
	testing.expect(t, stale_column not_in views.map_view.surfaces)
	testing.expect_value(t, len(views.map_view.surfaces), len(simulation.records.explored))
	testing.expect_value(t, views.map_view.painted_frame, Map_Frame{})
}
