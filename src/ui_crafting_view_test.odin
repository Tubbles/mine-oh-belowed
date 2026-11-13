package game

import "core:math"
import "core:slice"
import "core:testing"

// The crafting view (0277). The screen frames run at 1920 by 1080 pixels
// and UI scale 1 (screen_test_frame).

schematics_panel_test_id :: proc() -> Ui_Id {
	return ui_hash(0, "schematics", -1)
}

// A recipe's cell in the schematics grid.
schematic_cell_id :: proc(recipe: int) -> Ui_Id {
	return recipe_row_id(ui_hash(schematics_panel_test_id(), "schematics_grid", -1), recipe)
}

schematics_toggle_id :: proc() -> Ui_Id {
	return ui_hash(schematics_panel_test_id(), text("recipes_unlocked_only"), -1)
}

// The position of the recipe's tab in the view's tab list.
crafting_view_test_tab :: proc(recipes: Recipe_Registry, recipe: int) -> int {
	return crafting_tab_index(recipes, recipes.crafting_tabs[recipes.recipes[recipe].category])
}

// The panel of the focused widget of the last frame, 0 for none.
focused_widget_panel :: proc(state: Ui_State) -> Ui_Id {
	index := widget_index(state.widgets[:], state.focus)
	return index >= 0 ? state.widgets[index].panel : 0
}

// The crafting view open over the audit's site on the half, drawn twice
// so the focus settles.
open_crafting_view :: proc(audit: ^Ui_Audit, state: ^Ui_State, half: Crafting_Half) {
	state.theme = audit.theme
	state.crafting_half = half
	push_screen(&state.screens, .Inventory)
	screen_test_frame(audit, state, {})
	screen_test_frame(audit, state, {})
}

nearly :: proc(value, wanted: f32) -> bool {
	return math.abs(value - wanted) < 0.01
}

// The layout of the design's table: the panel content at 1080p, at
// 1280x800, at the Deck preset and at the smallest size. Side by side the
// toggle and the summary share the header row, stacked each takes a row
// of the half's width (0277's fix round).
@(test)
test_the_crafting_view_layout_at_the_audit_sizes :: proc(t: ^testing.T) {
	Layout_Case :: struct {
		content:       Ui_Rectangle,
		columns:       int,
		detail_width:  f32,
		detail_height: f32,
		stacked:       bool,
	}
	cases := [?]Layout_Case {
		{{0, 0, 1680, 880}, 5, 400, 688, false},
		{{0, 0, 1523.2, 880}, 4, 331.2, 688, false},
		{{0, 0, 1381.8, 791.6}, 2, 365.8, 599.6, false},
		{{0, 0, 1004.8, 556}, 2, 188.8, 116, true},
	}
	for layout_case in cases {
		layout := crafting_view_layout(layout_case.content)
		width := layout_case.content.width
		testing.expect_value(t, layout.inventory.width, 784)
		testing.expectf(t, nearly(layout.schematics.width, width - 816), "%v: the schematics half is %v wide", width, layout.schematics.width)
		testing.expectf(t, layout.columns == layout_case.columns, "%v: %d columns", width, layout.columns)
		testing.expectf(t, nearly(layout.detail.width, layout_case.detail_width), "%v: the detail is %v wide", width, layout.detail.width)
		testing.expectf(t, nearly(layout.detail.height, layout_case.detail_height), "%v: the detail is %v tall", width, layout.detail.height)
		testing.expect_value(t, layout.stacked, layout_case.stacked)
		if layout_case.stacked {
			testing.expect_value(t, layout.grid.height, slot_grid_height(CRAFTING_STACKED_GRID_ROWS))
			testing.expect(t, layout.detail.y > layout.grid.y + layout.grid.height)
			testing.expect_value(t, layout.toggle.width, layout.schematics.width)
			testing.expect_value(t, layout.summary.width, layout.schematics.width)
			testing.expect_value(t, layout.summary.y, layout.toggle.y + UI_ROW_HEIGHT + UI_GAP)
		} else {
			testing.expect_value(t, layout.grid.width, slot_grid_width(layout_case.columns))
			testing.expect(t, layout.detail.x > layout.grid.x + layout.grid.width)
			testing.expect_value(t, layout.summary.y, layout.toggle.y + UI_GAP)
		}
	}
}

// With Unlocked only off the Materials tab holds the components and the
// science packs too, in index order. On, the locked ones go.
@(test)
test_crafting_view_recipes_follow_the_tab_and_unlocked_only :: proc(t: ^testing.T) {
	test := make_browser_test()
	all := crafting_view_recipes(test.recipes, .Materials, false, test.unlocks.available, context.temp_allocator)
	for id in ([?]string{"plank", "iron_gear", "electronic_circuit", "science_pack_1"}) {
		testing.expectf(t, slice.contains(all, test_recipe(test.recipes, id)), "the Materials tab lacks %s", id)
	}
	testing.expect(t, slice.is_sorted(all))
	testing.expect(t, test_recipe(test.recipes, "plank") < test_recipe(test.recipes, "stick"))
	for recipe in all {
		testing.expect_value(t, test.recipes.crafting_tabs[test.recipes.recipes[recipe].category], Recipe_Category.Materials)
	}
	unlocked := crafting_view_recipes(test.recipes, .Materials, true, test.unlocks.available, context.temp_allocator)
	testing.expect(t, !slice.contains(unlocked, test_recipe(test.recipes, "electronic_circuit")))
	testing.expect(t, slice.contains(unlocked, test_recipe(test.recipes, "plank")))
	for recipe in unlocked {
		testing.expect(t, recipe_is_available(test.unlocks, recipe))
	}
}

// Right on the left panel's right column crosses to the right panel's
// left column in the same row, Left crosses back. A step with a neighbour
// in its own panel, Up and a widget that adjusts horizontally keep the
// default step. In the view the same holds for the slots, the hotbar,
// the grid's first column, and Down and Up wrap inside their half.
@(test)
test_the_focus_crosses_the_seam_and_wraps_inside_each_half :: proc(t: ^testing.T) {
	left, right := Ui_Id(100), Ui_Id(200)
	widgets := [?]Ui_Widget {
		{id = 1, panel = left, rectangle = {0, 0, 80, 80}},
		{id = 2, panel = left, rectangle = {88, 0, 80, 80}},
		{id = 3, panel = left, rectangle = {0, 88, 80, 80}},
		{id = 4, panel = left, rectangle = {88, 88, 80, 80}},
		{id = 5, panel = right, rectangle = {300, 0, 80, 80}},
		{id = 6, panel = right, rectangle = {388, 0, 80, 80}},
		{id = 7, panel = right, rectangle = {300, 88, 80, 80}},
		{id = 8, panel = right, rectangle = {388, 88, 80, 80}},
		{id = 9, panel = left, rectangle = {0, 200, 168, 56}, flags = {.Adjusts_Horizontally}},
	}
	testing.expect_value(t, crafting_seam_target(widgets[:], 2, .Right, left, right), 5)
	testing.expect_value(t, crafting_seam_target(widgets[:], 4, .Right, left, right), 7)
	testing.expect_value(t, crafting_seam_target(widgets[:], 5, .Left, left, right), 2)
	testing.expect_value(t, crafting_seam_target(widgets[:], 7, .Left, left, right), 4)
	testing.expect_value(t, crafting_seam_target(widgets[:], 1, .Right, left, right), 0)
	testing.expect_value(t, crafting_seam_target(widgets[:], 6, .Left, left, right), 0)
	testing.expect_value(t, crafting_seam_target(widgets[:], 3, .Up, left, right), 0)
	testing.expect_value(t, crafting_seam_target(widgets[:], 9, .Right, left, right), 0)
	testing.expect_value(t, crafting_seam_target(widgets[:], 6, .Right, left, right), 0)

	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	open_crafting_view(audit, &state, .Inventory)
	inventory := ui_hash(0, "inventory", -1)
	for slot in ([2]Ui_Id{inventory_slot_id("grid", 8), inventory_slot_id("hotbar", 7)}) {
		state.focus = slot
		screen_test_frame(audit, &state, {})
		testing.expect_value(t, state.crafting_half, Crafting_Half.Inventory)
		screen_test_frame(audit, &state, {navigation = .Right})
		testing.expectf(t, focused_widget_panel(state) == schematics_panel_test_id(), "Right from %v stays in panel %v", slot, focused_widget_panel(state))
		screen_test_frame(audit, &state, {})
		testing.expect_value(t, state.crafting_half, Crafting_Half.Schematics)
	}
	view := audit.views.crafting_view
	tabs, _ := crafting_tab_list(audit.content.recipes)
	cells := crafting_view_recipes(audit.content.recipes, tabs[view.tab], view.available_only, audit.simulation.unlocks.available, context.temp_allocator)
	if !testing.expect(t, len(cells) > 0) {
		return
	}
	state.focus = schematic_cell_id(cells[0])
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {navigation = .Left})
	testing.expect_value(t, focused_widget_panel(state), inventory)
	state.focus = inventory_slot_id("hotbar", 3)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {navigation = .Down})
	testing.expect_value(t, focused_widget_panel(state), inventory)
	state.focus = schematics_toggle_id()
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {navigation = .Up})
	testing.expect_value(t, focused_widget_panel(state), schematics_panel_test_id())
}

// C from the world opens the view on a schematic, the inventory binding
// on the selected hotbar slot. C on the view closes it, and a window step
// to the journal and back keeps the half.
@(test)
test_c_and_the_inventory_binding_open_the_crafting_view_on_their_half :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	browser := &audit.views.recipe_browser
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	screen_test_frame(audit, &state, {open_recipes = true})
	expect_screens(t, &state, {.Inventory})
	testing.expect_value(t, state.crafting_half, Crafting_Half.Schematics)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {})
	testing.expect(t, browser.focused_recipe != NO_RECIPE)
	testing.expect_value(t, state.focus, schematic_cell_id(browser.focused_recipe))
	screen_test_frame(audit, &state, {open_recipes = true})
	expect_screens(t, &state, {})
	audit.simulation.players[0].selected_hotbar_slot = 2
	screen_test_frame(audit, &state, {open_inventory = true})
	expect_screens(t, &state, {.Inventory})
	testing.expect_value(t, state.crafting_half, Crafting_Half.Inventory)
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, state.focus, inventory_slot_id("hotbar", 2))
	screen_test_frame(audit, &state, {back = true})
	expect_screens(t, &state, {})
	// On the schematics, a step to the journal and back.
	screen_test_frame(audit, &state, {open_recipes = true})
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {window_next = true})
	expect_screens(t, &state, {.Journal})
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {window_previous = true})
	expect_screens(t, &state, {.Inventory})
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, state.crafting_half, Crafting_Half.Schematics)
	testing.expect_value(t, focused_widget_panel(state), schematics_panel_test_id())
}

// The tab step moves a focus on a cell to the new tab's first cell and
// makes that recipe the focused one, from the grid's top. On the toggle
// and on a slot the focus stays while the focused recipe follows. The
// step wraps.
@(test)
test_a_tab_step_moves_the_schematics_focus_to_the_new_tab :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	view := &audit.views.crafting_view
	browser := &audit.views.recipe_browser
	recipes := audit.content.recipes
	tabs, count := crafting_tab_list(recipes)
	tab_recipes :: proc(audit: ^Ui_Audit, category: Recipe_Category) -> []int {
		view := audit.views.crafting_view
		return crafting_view_recipes(audit.content.recipes, category, view.available_only, audit.simulation.unlocks.available, context.temp_allocator)
	}
	first_of :: proc(recipes: []int) -> int {
		return len(recipes) > 0 ? recipes[0] : NO_RECIPE
	}
	state: Ui_State
	defer destroy_ui_state(&state)
	open_crafting_view(audit, &state, .Schematics)
	testing.expect_value(t, view.tab, 0)
	testing.expect_value(t, focused_widget_panel(state), schematics_panel_test_id())
	grid := ui_hash(schematics_panel_test_id(), "schematics_grid", -1)
	state.scroll_offsets[grid] = 50
	screen_test_frame(audit, &state, {tab_next = true})
	testing.expect_value(t, view.tab, 1)
	second := tab_recipes(audit, tabs[1])
	if !testing.expect(t, len(second) > 0) {
		return
	}
	testing.expect_value(t, browser.focused_recipe, second[0])
	testing.expect_value(t, state.scroll_offsets[grid], 0)
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, state.focus, schematic_cell_id(second[0]))
	// On the toggle.
	state.focus = schematics_toggle_id()
	screen_test_frame(audit, &state, {tab_next = true})
	testing.expect_value(t, view.tab, 2)
	testing.expect_value(t, state.focus, schematics_toggle_id())
	testing.expect_value(t, browser.focused_recipe, first_of(tab_recipes(audit, tabs[2])))
	// On a slot.
	state.focus = inventory_slot_id("hotbar", 0)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {tab_next = true})
	testing.expect_value(t, view.tab, 3)
	testing.expect_value(t, state.focus, inventory_slot_id("hotbar", 0))
	testing.expect_value(t, browser.focused_recipe, first_of(tab_recipes(audit, tabs[3])))
	// Back from the first tab to the last.
	view.tab = 0
	screen_test_frame(audit, &state, {tab_previous = true})
	testing.expect_value(t, view.tab, count - 1)
}

// On a focused schematic A crafts one, with R1 five and with L1 the most
// the planner accepts. With a run queued the context action clears the
// queue on the gamepad and on the keyboard alike, as the bar says. On a
// backpack stack it sorts. Without materials L1 with A queues nothing and
// toasts.
@(test)
test_modifiers_with_a_on_a_schematic :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	player := &audit.simulation.players[0]
	plank := test_recipe(audit.content.recipes, "plank")
	player.crafting = {}
	slice.fill(player.inventory.slots, EMPTY_STACK)
	player.inventory.slots[3] = {test_item(audit.content.items, "log"), 20}
	clear(&audit.simulation.player_commands)
	audit.views.crafting_view.tab = crafting_view_test_tab(audit.content.recipes, plank)
	audit.views.recipe_browser.focused_recipe = plank
	state: Ui_State
	defer destroy_ui_state(&state)
	open_crafting_view(audit, &state, .Schematics)
	testing.expect_value(t, state.focus, schematic_cell_id(plank))
	screen_context := audit_screen_context(audit)
	most := planned_craft_count(player.crafting, player.inventory, audit.content.recipes, screen_context.unlocks^, plank, screen_craft_makers(screen_context), screen_context.free_crafting)
	testing.expectf(t, most > RECIPE_CRAFT_MANY_COUNT, "the planner accepts %d", most)
	presses := [?]struct {
		input: Ui_Input,
		count: int,
	}{{{confirm = true}, 1}, {{confirm = true, modifier_five = true}, RECIPE_CRAFT_MANY_COUNT}, {{confirm = true, modifier_most = true}, most}}
	for press in presses {
		screen_test_frame(audit, &state, press.input)
		testing.expectf(t, len(audit.simulation.player_commands) == 1, "count %d: %d commands", press.count, len(audit.simulation.player_commands))
		craft, crafts := last_queued_command(audit).(Craft_Command)
		testing.expectf(t, crafts && craft == Craft_Command{recipe = plank, count = press.count}, "%v", last_queued_command(audit))
		clear(&audit.simulation.player_commands)
	}
	screen_test_frame(audit, &state, {confirm = true})
	apply_player_commands(&audit.simulation, audit.content)
	testing.expect_value(t, player.crafting.count, 1)
	for device in Input_Device {
		screen_test_frame(audit, &state, {context_action = true, device = device, device_seen = true})
		_, clears := last_queued_command(audit).(Clear_Craft_Queue_Command)
		testing.expectf(t, clears && len(audit.simulation.player_commands) == 1, "%v: %v", device, last_queued_command(audit))
		testing.expectf(t, draw_list_has_text(state.draw_list[:], text("hint_clear_craft_queue")), "%v: no Clear queue hint", device)
		clear(&audit.simulation.player_commands)
	}
	// A backpack stack: the gamepad's X sorts.
	player.inventory.slots[HOTBAR_SLOT_COUNT] = {test_item(audit.content.items, "stone"), 3}
	state.focus = inventory_slot_id("grid", 0)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {context_action = true, device = .Gamepad, device_seen = true})
	_, sorts := last_queued_command(audit).(Slot_Sort_Command)
	testing.expectf(t, sorts, "%v", last_queued_command(audit))
	// Nothing to craft from: L1 with A queues nothing and toasts.
	player.crafting = {}
	slice.fill(player.inventory.slots, EMPTY_STACK)
	clear(&audit.simulation.player_commands)
	state.focus = schematic_cell_id(plank)
	screen_test_frame(audit, &state, {})
	toasts := len(state.toasts)
	screen_test_frame(audit, &state, {confirm = true, modifier_most = true})
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	testing.expect_value(t, len(state.toasts), toasts + 1)
}

@(test)
test_crafting_view_queue_act_follows_the_context_action_and_the_button :: proc(t: ^testing.T) {
	testing.expect_value(t, crafting_view_queue_act(true, .None), Craft_Queue_Act.Clear)
	testing.expect_value(t, crafting_view_queue_act(false, .Clear_Craft_Queue), Craft_Queue_Act.Clear)
	testing.expect_value(t, crafting_view_queue_act(false, .Cancel_Craft), Craft_Queue_Act.Cancel_Last)
	testing.expect_value(t, crafting_view_queue_act(false, .Craft), Craft_Queue_Act.None)
	testing.expect_value(t, crafting_view_queue_act(false, .Back), Craft_Queue_Act.None)
	testing.expect_value(t, crafting_view_queue_act(false, .None), Craft_Queue_Act.None)
}

// A finger dragged up on a cell scrolls the grid by the drag and keeps
// the focus and the screen.
@(test)
test_a_drag_scrolls_the_schematics_grid :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	audit.views.crafting_view = {tab = crafting_tab_index(audit.content.recipes, .Materials), available_only = false}
	state: Ui_State
	defer destroy_ui_state(&state)
	open_crafting_view(audit, &state, .Schematics)
	grid := ui_hash(schematics_panel_test_id(), "schematics_grid", -1)
	at := widget_centre(state, state.focus)
	before := state.scroll_offsets[grid]
	screen_test_frame(audit, &state, touch_input(at, true, pressed = true))
	focus := state.focus
	screen_test_frame(audit, &state, touch_input(at - {0, 100}, true))
	screen_test_frame(audit, &state, touch_input(at - {0, 100}, false, moved = false))
	testing.expect_value(t, state.scroll_offsets[grid], before + 100)
	testing.expect_value(t, state.focus, focus)
	expect_screens(t, &state, {.Inventory})
}

// A graph step takes the view to the recipe's tab, Unlocked only off for
// a locked recipe. In the view a step from the gear's Used in list lands
// on the drill's cell.
@(test)
test_a_graph_step_in_the_crafting_view_opens_the_recipes_tab :: proc(t: ^testing.T) {
	test := make_browser_test()
	browser := make_recipe_browser()
	defer destroy_recipe_browser(&browser)
	machines := crafting_tab_index(test.recipes, .Machines)
	materials := crafting_tab_index(test.recipes, .Materials)
	circuit := test_recipe(test.recipes, "electronic_circuit")
	view := Crafting_View{tab = machines, available_only = true}
	navigate_crafting_view(&view, &browser, test.recipes, test.unlocks, circuit)
	testing.expect_value(t, view, Crafting_View{tab = materials, available_only = false})
	testing.expect_value(t, browser.pending_focus, circuit)
	testing.expect_value(t, browser.focused_recipe, circuit)
	plank := test_recipe(test.recipes, "plank")
	view = {tab = machines, available_only = true}
	navigate_crafting_view(&view, &browser, test.recipes, test.unlocks, plank)
	testing.expect_value(t, view, Crafting_View{tab = materials, available_only = true})

	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	gear := test_recipe(audit.content.recipes, "iron_gear")
	drill := test_recipe(audit.content.recipes, "burner_mining_drill")
	audit.views.crafting_view = {tab = crafting_view_test_tab(audit.content.recipes, gear), available_only = false}
	audit.views.recipe_browser.focused_recipe = gear
	state: Ui_State
	defer destroy_ui_state(&state)
	open_crafting_view(audit, &state, .Schematics)
	testing.expect_value(t, state.focus, schematic_cell_id(gear))
	used_in := recipe_row_id(ui_hash(schematics_panel_test_id(), "recipes_used_in", -1), drill)
	if !testing.expect(t, widget_index(state.widgets[:], used_in) >= 0) {
		return
	}
	state.focus = used_in
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect_value(t, audit.views.crafting_view.tab, crafting_view_test_tab(audit.content.recipes, drill))
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, state.focus, schematic_cell_id(drill))
}

schematics_grid_test_id :: proc() -> Ui_Id {
	return ui_hash(schematics_panel_test_id(), "schematics_grid", -1)
}

// The recipe whose cell lies under the point, clipped or not, NO_RECIPE
// for none.
schematic_cell_at :: proc(state: Ui_State, recipes: Recipe_Registry, point: [2]f32) -> int {
	for recipe in 0 ..< len(recipes.recipes) {
		index := widget_index(state.widgets[:], schematic_cell_id(recipe))
		if index >= 0 && rectangle_contains(state.widgets[index].rectangle, point) {
			return recipe
		}
	}
	return NO_RECIPE
}

// The Materials tab with Unlocked only off on the schematics half.
open_every_material :: proc(audit: ^Ui_Audit, state: ^Ui_State) {
	audit.views.crafting_view = {tab = crafting_tab_index(audit.content.recipes, .Materials), available_only = false}
	open_crafting_view(audit, state, .Schematics)
}

// The review's touch probe (0277's fix round): with the grid dragged up
// 130 a cell lies clipped under "Unlocked only", and a tap there flips the
// toggle and selects no recipe.
@(test) // slow
test_a_tap_on_the_toggle_over_the_scrolled_grid_flips_it :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	open_every_material(audit, &state)
	clear(&audit.simulation.player_commands)
	at := widget_centre(state, state.focus)
	screen_test_frame(audit, &state, touch_input(at, true, pressed = true))
	screen_test_frame(audit, &state, touch_input(at - {0, 130}, true))
	screen_test_frame(audit, &state, touch_input(at - {0, 130}, false, moved = false))
	testing.expect_value(t, state.scroll_offsets[schematics_grid_test_id()], 130)
	toggle := schematics_toggle_id()
	toggle_centre := widget_centre(state, toggle)
	if !testing.expect(t, schematic_cell_at(state, audit.content.recipes, toggle_centre) != NO_RECIPE, "no cell under the toggle") {
		return
	}
	testing.expect_value(t, widget_under(state.widgets[:], toggle_centre), toggle)
	screen_test_frame(audit, &state, touch_input(toggle_centre, true, pressed = true))
	screen_test_frame(audit, &state, touch_input(toggle_centre, false, moved = false))
	testing.expect(t, audit.views.crafting_view.available_only)
	testing.expect_value(t, state.focus, toggle)
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
}

// The review's mouse probe: the grid scrolled 88, the cell clipped under
// the toggle craftable, and a click on the toggle flips it and queues
// nothing.
@(test) // slow
test_a_click_on_the_toggle_over_the_scrolled_grid_queues_nothing :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	open_every_material(audit, &state)
	toggle := schematics_toggle_id()
	// The focus off the grid, so the grid keeps the offset.
	state.focus = toggle
	state.scroll_offsets[schematics_grid_test_id()] = 88
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, state.scroll_offsets[schematics_grid_test_id()], 88)
	toggle_centre := widget_centre(state, toggle)
	hidden := schematic_cell_at(state, audit.content.recipes, toggle_centre)
	if !testing.expect(t, hidden != NO_RECIPE, "no cell under the toggle") {
		return
	}
	player := &audit.simulation.players[0]
	player.crafting = {}
	slice.fill(player.inventory.slots, EMPTY_STACK)
	for input in audit.content.recipes.recipes[hidden].inputs {
		inventory_add(player.inventory, audit.content.items, input.item, 10 * int(input.count))
	}
	clear(&audit.simulation.player_commands)
	toasts := len(state.toasts)
	screen_test_frame(audit, &state, pointer_input(toggle_centre, false))
	screen_test_frame(audit, &state, pointer_input(toggle_centre, true, pressed = true))
	screen_test_frame(audit, &state, pointer_input(toggle_centre, false, moved = false))
	testing.expect(t, audit.views.crafting_view.available_only)
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	testing.expect_value(t, len(state.toasts), toasts)
	testing.expect_value(t, state.focus, toggle)
}

// One frame of the screens at the size in pixels, UI scale 1.
crafting_view_frame_at :: proc(audit: ^Ui_Audit, state: ^Ui_State, pixels: [2]f32) {
	ui_begin(state, {}, pixels, 1.0 / 60, 1, 1, ui_accessibility(audit.settings))
	run_screens(state, audit_screen_context(audit))
	ui_resolve(state)
}

// A backpack slot's info panel docks beside the view's panel, not beside
// its half (0277's fix round). At 1080p the view leaves no room beside it,
// so tooltip_rectangle puts the box under the slot, clear of the
// schematics half. On the 1920x540 split screen half, 3840 units wide, it
// docks beside the view, clear of both halves.
@(test) // slow
test_a_slot_tooltip_docks_beside_the_crafting_view :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	for pixels in ([?][2]f32{{1920, 1080}, {1920, 540}}) {
		state := Ui_State{theme = audit.theme}
		push_screen(&state.screens, .Inventory)
		crafting_view_frame_at(audit, &state, pixels)
		crafting_view_frame_at(audit, &state, pixels)
		slot := widget_index(state.widgets[:], inventory_slot_id("grid", 0))
		view, found := audit_panel_rectangle(state.panels[:], ui_hash(0, "crafting_view", -1))
		if !testing.expect(t, slot >= 0 && found) {
			destroy_ui_state(&state)
			return
		}
		widget := state.widgets[slot]
		testing.expect_value(t, tooltip_dock_rectangle(state.panels[:], widget), view)
		box := tooltip_rectangle(tooltip_dock_rectangle(state.panels[:], widget), widget.rectangle, ui_safe_area(&state), 4 * UI_LINE_HEIGHT + 2 * UI_PADDING)
		layout := crafting_view_layout(inset(view, UI_PADDING))
		_, over_schematics := rectangle_intersection(box, layout.schematics)
		_, over_inventory := rectangle_intersection(box, layout.inventory)
		testing.expectf(t, !over_schematics, "%v: the box %v covers the schematics half %v", pixels, box, layout.schematics)
		testing.expectf(t, pixels.y == 1080 || !over_inventory, "%v: the box %v covers the inventory half %v", pixels, box, layout.inventory)
		destroy_ui_state(&state)
	}
}

// Unlocked only turned on moves the detail off a recipe the grid now
// hides to the first shown cell, and with nothing shown to the empty
// state (0277's fix round).
@(test) // slow
test_unlocked_only_moves_the_detail_off_a_hidden_recipe :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	recipes, unlocks := audit.content.recipes, audit.simulation.unlocks
	locked := NO_RECIPE
	for recipe in crafting_view_recipes(recipes, .Materials, false, unlocks.available, context.temp_allocator) {
		if !recipe_is_available(unlocks, recipe) {
			locked = recipe
			break
		}
	}
	shown := crafting_view_recipes(recipes, .Materials, true, unlocks.available, context.temp_allocator)
	if !testing.expect(t, locked != NO_RECIPE && len(shown) > 0) {
		return
	}
	state: Ui_State
	defer destroy_ui_state(&state)
	open_every_material(audit, &state)
	browser := &audit.views.recipe_browser
	browser.focused_recipe = locked
	state.focus = schematics_toggle_id()
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, browser.focused_recipe, locked)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, audit.views.crafting_view.available_only)
	testing.expect_value(t, browser.focused_recipe, shown[0])
	// Nothing unlocked: the grid and the detail empty.
	available := audit.simulation.unlocks.available
	saved := slice.clone(available, context.temp_allocator)
	defer copy(available, saved)
	slice.fill(available, false)
	audit.views.crafting_view.available_only = false
	browser.focused_recipe = locked
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, audit.views.crafting_view.available_only)
	testing.expect_value(t, browser.focused_recipe, NO_RECIPE)
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("recipes_none")))
}
