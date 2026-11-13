package game

import "core:testing"

// The carousel's order (0385), written out so the tests do not read it
// from window_carousel.
// The Inventory is the crafting view (0277).
CAROUSEL_TEST_ORDER :: [?]Screen{.Inventory, .Journal, .Technologies, .Map, .Statistics, .Power}

@(test)
test_the_window_carousel_steps_in_order_and_wraps :: proc(t: ^testing.T) {
	order := CAROUSEL_TEST_ORDER
	count := len(order)
	for window, index in order {
		testing.expect_value(t, step_window_carousel(window, 1), order[(index + 1) % count])
		testing.expect_value(t, step_window_carousel(window, -1), order[(index + count - 1) % count])
		testing.expect_value(t, step_window_carousel(window, 7), order[(index + 1) % count])
		testing.expect(t, window_in_carousel(window))
	}
	testing.expect_value(t, step_window_carousel(.Power, 1), Screen.Inventory)
	testing.expect_value(t, step_window_carousel(.Inventory, -1), Screen.Power)
	testing.expect_value(t, step_window_carousel(.Pause, 1), Screen.Pause)
	testing.expect_value(t, step_window_carousel(.Machine, -1), Screen.Machine)
	for screen in ([?]Screen{.Machine, .Configure, .Settings, .Pause, .Recipes}) {
		testing.expect(t, !window_in_carousel(screen))
	}
}

// The first entity of a machine kind with a panel in the audit's site.
audit_panel_of_kind :: proc(audit: ^Ui_Audit, kind: Machine_Kind) -> Entity_Handle {
	for handle in machines_with_panels(&audit.simulation.world, audit.content) {
		common := entity_common(&audit.simulation.world.entities, handle)
		if audit.content.machines.machines[common.machine].kind == kind {
			return handle
		}
	}
	return NO_ENTITY
}

// An assembler whose recipe the player chooses (the picker's machine).
audit_assembler_with_a_choice :: proc(audit: ^Ui_Audit) -> Entity_Handle {
	for assembler in audit.simulation.world.entities.assemblers.entries {
		if assembler.alive && audit.content.machines.machines[assembler.machine].recipe_choice != .Fixed {
			return assembler.handle
		}
	}
	return NO_ENTITY
}

// The stone cutting table, whose panel is the browser's station mode.
audit_crafting_station :: proc(audit: ^Ui_Audit) -> Entity_Handle {
	for foundation in audit.simulation.world.entities.foundations.entries {
		if foundation.alive && audit.content.machines.machines[foundation.machine].kind == .Crafting_Station {
			return foundation.handle
		}
	}
	return NO_ENTITY
}

// A stack to start a carousel test from: the screens, the open machine
// (the panel under them) and the recipe browser's modes.
Carousel_Test_Stack :: struct {
	screens:   []Screen,
	machine:   Entity_Handle,
	selecting: Entity_Handle,
	station:   Entity_Handle,
	// The item the configure pop-up configures.
	configure: Item_Id,
}

carousel_test_state :: proc(audit: ^Ui_Audit, stack: Carousel_Test_Stack) -> Ui_State {
	state := Ui_State{theme = audit.theme}
	for screen in stack.screens {
		push_screen(&state.screens, screen)
	}
	state.configure.item = stack.configure
	audit.simulation.players[0].open_machine = stack.machine
	audit.views.recipe_browser.selecting_for = stack.selecting
	audit.views.recipe_browser.station = stack.station
	return state
}

// The stack holds the screens, bottom first.
expect_screens :: proc(t: ^testing.T, state: ^Ui_State, wanted: []Screen, loc := #caller_location) {
	testing.expect_value(t, state.screens.count, len(wanted), loc = loc)
	for screen, index in wanted {
		if index < state.screens.count {
			testing.expect_value(t, state.screens.screens[index], screen, loc = loc)
		}
	}
}

// Each window alone and over a lab's panel: RT puts the next window in
// its place and LT the previous one, wrapping, and the depth and the
// panel under it stay.
@(test) // slow
test_the_triggers_step_every_window_and_wrap :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	lab := audit_panel_of_kind(audit, .Lab)
	testing.expect(t, lab != NO_ENTITY)
	order := CAROUSEL_TEST_ORDER
	count := len(order)
	for under_lab in ([2]bool{false, true}) {
		for window, index in order {
			for input in ([2]Ui_Input{{window_next = true}, {window_previous = true}}) {
				screens := under_lab ? []Screen{.Machine, window} : []Screen{window}
				state := carousel_test_state(audit, {screens = screens, machine = under_lab ? lab : NO_ENTITY})
				screen_test_frame(audit, &state, input)
				stepped := order[(index + (input.window_next ? 1 : count - 1)) % count]
				expect_screens(t, &state, under_lab ? []Screen{.Machine, stepped} : []Screen{stepped})
				destroy_ui_state(&state)
			}
		}
	}
}

// The picker over an assembler's panel, the crafting station's browser, a
// chest's panel, the configure pop-up over the inventory and the
// settings over the pause menu lie outside the carousel: the window step
// leaves the stack as it was.
@(test)
test_the_picker_station_and_panels_ignore_the_window_step :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	with_audit_foundation_blocks(audit)
	assembler := audit_assembler_with_a_choice(audit)
	station := audit_crafting_station(audit)
	chest := audit_panel_of_kind(audit, .Chest)
	foundation := audit.content.machines.machines[audit.content.field.pad_foundation].item
	testing.expect(t, assembler != NO_ENTITY && station != NO_ENTITY && chest != NO_ENTITY)
	stacks := [?]Carousel_Test_Stack {
		{screens = {.Machine, .Recipes}, machine = assembler, selecting = assembler},
		{screens = {.Machine, .Recipes}, machine = station, station = station},
		{screens = {.Machine}, machine = chest},
		{screens = {.Inventory, .Configure}, configure = foundation},
		{screens = {.Pause, .Settings}},
	}
	for stack in stacks {
		for input in ([2]Ui_Input{{window_next = true}, {window_previous = true}}) {
			state := carousel_test_state(audit, stack)
			screen_test_frame(audit, &state, input)
			expect_screens(t, &state, stack.screens)
			destroy_ui_state(&state)
		}
	}
}

// B, Menu and a window's own key pop one level: a window opened from the
// world closes to it, research from a lab's panel returns to the panel,
// also after a step, and the dialogs return to what opened them. An open
// info panel takes the first B alone.
@(test) // slow
test_back_pops_one_level_of_the_stack :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	with_audit_foundation_blocks(audit)
	order := CAROUSEL_TEST_ORDER
	own_keys := [?]Ui_Input{{open_inventory = true}, {open_journal = true}, {open_technologies = true}, {open_map = true}, {open_statistics = true}, {open_power = true}}
	for window, index in order {
		for input in ([?]Ui_Input{{back = true}, {pause = true}, own_keys[index]}) {
			state := carousel_test_state(audit, {screens = {window}})
			screen_test_frame(audit, &state, input)
			expect_screens(t, &state, {})
			destroy_ui_state(&state)
		}
	}
	// C pops the crafting view too, the inventory binding's window.
	crafting := carousel_test_state(audit, {screens = {.Inventory}})
	screen_test_frame(audit, &crafting, {open_recipes = true})
	expect_screens(t, &crafting, {})
	destroy_ui_state(&crafting)
	lab := audit_panel_of_kind(audit, .Lab)
	research := carousel_test_state(audit, {screens = {.Machine, .Technologies}, machine = lab})
	screen_test_frame(audit, &research, {back = true})
	expect_screens(t, &research, {.Machine})
	destroy_ui_state(&research)
	research = carousel_test_state(audit, {screens = {.Machine, .Technologies}, machine = lab})
	screen_test_frame(audit, &research, {window_next = true})
	expect_screens(t, &research, {.Machine, .Map})
	screen_test_frame(audit, &research, {back = true})
	expect_screens(t, &research, {.Machine})
	destroy_ui_state(&research)
	// The info panel closes first, then the window.
	journal := carousel_test_state(audit, {screens = {.Journal}})
	journal.tooltip_open = true
	screen_test_frame(audit, &journal, {back = true})
	testing.expect(t, !journal.tooltip_open)
	expect_screens(t, &journal, {.Journal})
	screen_test_frame(audit, &journal, {back = true})
	expect_screens(t, &journal, {})
	destroy_ui_state(&journal)
	assembler := audit_assembler_with_a_choice(audit)
	foundation := audit.content.machines.machines[audit.content.field.pad_foundation].item
	Dialog :: struct {
		stack: Carousel_Test_Stack,
		after: []Screen,
	}
	dialogs := [?]Dialog {
		{{screens = {.Machine, .Recipes}, machine = assembler, selecting = assembler}, {.Machine}},
		{{screens = {.Inventory, .Configure}, configure = foundation}, {.Inventory}},
		{{screens = {.Pause, .Settings}}, {.Pause}},
	}
	for dialog in dialogs {
		state := carousel_test_state(audit, dialog.stack)
		screen_test_frame(audit, &state, {back = true})
		expect_screens(t, &state, dialog.after)
		destroy_ui_state(&state)
	}
}

// The keyboard's E is Open_Inventory and Window_Next: on a window it
// steps, on a machine panel and on the picker it pops one level.
@(test)
test_the_keyboard_window_step_wins_over_open_inventory :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	lab := audit_panel_of_kind(audit, .Lab)
	chest := audit_panel_of_kind(audit, .Chest)
	assembler := audit_assembler_with_a_choice(audit)
	testing.expect(t, lab != NO_ENTITY && chest != NO_ENTITY && assembler != NO_ENTITY)
	Case :: struct {
		stack: Carousel_Test_Stack,
		after: []Screen,
	}
	cases := [?]Case {
		{{screens = {.Inventory}}, {.Journal}},
		{{screens = {.Machine, .Technologies}, machine = lab}, {.Machine, .Map}},
		{{screens = {.Machine}, machine = chest}, {}},
		{{screens = {.Machine, .Recipes}, machine = assembler, selecting = assembler}, {.Machine}},
	}
	for keyboard_case in cases {
		state := carousel_test_state(audit, keyboard_case.stack)
		screen_test_frame(audit, &state, {open_inventory = true, window_next = true})
		expect_screens(t, &state, keyboard_case.after)
		destroy_ui_state(&state)
	}
}

// The draw command of a UI icon, found false without one.
draw_list_icon :: proc(commands: []Draw_Command, icon: Ui_Icon) -> (command: Draw_Command, found: bool) {
	for candidate in commands {
		if candidate.kind == .Ui_Icon && candidate.tile == int(icon) {
			return candidate, true
		}
	}
	return {}, false
}

// Every window names itself in its title row between the arrows, with
// the triggers' glyphs on the gamepad and without them on touch; a press
// on the right arrow steps to the next window, with the mouse and on
// touch.
@(test) // slow
test_the_title_row_names_the_window_and_its_arrows_step :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	order := CAROUSEL_TEST_ORDER
	for window, index in order {
		next := []Screen{order[(index + 1) % len(order)]}
		state := carousel_test_state(audit, {screens = {window}})
		state.bindings, state.active_device = audit.bindings, .Gamepad
		screen_test_frame(audit, &state, {})
		testing.expect(t, draw_list_has_text(state.draw_list[:], text(window_title_key(window))))
		for icon in ([?]Ui_Icon{.Arrow_Left, .Arrow_Right, .Trigger_Left, .Trigger_Right}) {
			_, found := draw_list_icon(state.draw_list[:], icon)
			testing.expectf(t, found, "%v draws no %v", window, icon)
		}
		arrow, found := draw_list_icon(state.draw_list[:], .Arrow_Right)
		screen_test_frame(audit, &state, pointer_input(rectangle_centre(arrow.rectangle) * state.pixels_per_unit, down = true, pressed = true))
		expect_screens(t, &state, next)
		destroy_ui_state(&state)
		touch := carousel_test_state(audit, {screens = {window}})
		touch.bindings, touch.active_device = audit.bindings, .Gamepad
		screen_test_frame(audit, &touch, {pointer_is_touch = true})
		for icon in ([?]Ui_Icon{.Trigger_Left, .Trigger_Right}) {
			_, shown := draw_list_icon(touch.draw_list[:], icon)
			testing.expectf(t, !shown, "%v draws %v on touch", window, icon)
		}
		arrow, found = draw_list_icon(touch.draw_list[:], .Arrow_Right)
		testing.expect(t, found)
		press := pointer_input(rectangle_centre(arrow.rectangle) * touch.pixels_per_unit, down = true, pressed = true)
		press.pointer_is_touch = true
		screen_test_frame(audit, &touch, press)
		expect_screens(t, &touch, next)
		destroy_ui_state(&touch)
	}
}
