package game

import "core:fmt"
import "core:log"
import "core:mem/virtual"
import "core:slice"
import "core:strings"
import "core:testing"

// The UI bounds audit (work item 0046). Every screen and the HUD run
// headless over the save test's site with the shipped strings, at the
// couch and handheld screen sizes and UI scales, with keyboard and with
// gamepad glyphs, drawn with the shipped theme (data/ui/theme.sjson, work
// item 0071) and the focus outline's pulse at its thinnest with keyboard
// glyphs and at its thickest with gamepad glyphs. Each frame's draw list
// is checked: every command lies on
// the screen and inside the panel it was drawn in (clipped commands by
// their visible part), every panel lies in the safe area and clear of the
// glyph bar, and every text fits the rectangle it was given, measured with
// approximate_text_width. A failure names the case, the size, the scale,
// the glyphs, the frame and the command. Overlaps inside a panel, icon
// alignment and colours are left to the manual check list in the work
// item.

Ui_Audit_Size :: struct {
	pixels: [2]f32,
	scale:  f32,
}

UI_AUDIT_SIZES :: [?]Ui_Audit_Size {
	{{1920, 1080}, 1.0},
	{{1920, 1080}, 1.2},
	{{1920, 1080}, 1.5},
	{{1280, 800}, 1.0},
	{{1280, 800}, 1.2},
	{{1280, 800}, 1.5},
}

UI_AUDIT_TOLERANCE :: 1.0
// The Display tab's Resolution row lists the choices up to it.
UI_AUDIT_MONITOR_SIZE :: [2]int{3840, 2160}
// Plain frames after the tab steps, so the focus and the screens settle.
UI_AUDIT_SETTLE_FRAMES :: 2
// Problems logged one by one; the count covers them all.
UI_AUDIT_REPORT_LIMIT :: 200
UI_AUDIT_LONG_WORLD_NAME :: "Wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww"

Ui_Audit_Problem :: enum u8 {
	Off_Screen,
	Outside_Panel,
	Panel_Outside_Safe_Area,
	Text_Too_Wide,
	Text_Too_Tall,
	// A panel under the glyph bar's glyphs or labels.
	Panel_Under_Glyph_Bar,
}

// One screen stack to audit at every size.
Ui_Audit_Case :: struct {
	name:         string,
	screens:      []Screen,
	hud:          bool,
	// Frames with the right bumper before settling: the tab audited.
	tab_next:     int,
	machine:      Entity_Handle,
	selecting:    Entity_Handle,
	keyboard:     bool,
	radial:       bool,
	// String keys shown as toasts from the first frame.
	toasts:       []string,
	// Mission Control's panel with the longest line half typed and one
	// waiting, and the discovery card of the longest named item (work
	// item 0069).
	mission_control: bool,
	// Audit one more frame per widget with the focus and the info panel on it.
	walk_focus:   bool,
}

// Owns everything a Screen_Context points into.
Ui_Audit :: struct {
	strings:            String_Table,
	theme:              Ui_Theme,
	content:            Simulation_Content,
	simulation:         Simulation_State,
	settings:           Settings,
	// The screen context's display facts (work item 0084).
	window_scale:       [2]f32,
	wayland_display_set: bool,
	fonts:              Loaded_Fonts,
	bindings:           []Binding,
	title:              Title_State,
	browser:            Recipe_Browser,
	technology_browser: Technology_Browser,
	statistics_view:    Statistics_View,
	map_view:           Map_View,
	generator:          Generator,
	biome_banner:       Biome_Banner,
	recipe_names:       []string,
	recipe_order:       []int,
	item_sort_ranks:    []u16,
	notes:              Note_Registry,
	quit_requested:     bool,
	save_requested:     bool,
	show_diagnostics:   bool,
	show_world_overlay: bool,
	frame_arena:        virtual.Arena,
	reported:           map[string]bool,
	failures:           int,
}

rectangle_inside :: proc(inner, outer: Ui_Rectangle, tolerance: f32) -> bool {
	return(
		inner.x >= outer.x - tolerance &&
		inner.y >= outer.y - tolerance &&
		inner.x + inner.width <= outer.x + outer.width + tolerance &&
		inner.y + inner.height <= outer.y + outer.height + tolerance \
	)
}

rectangle_intersection :: proc(first, second: Ui_Rectangle) -> (result: Ui_Rectangle, overlaps: bool) {
	left, top := max(first.x, second.x), max(first.y, second.y)
	right := min(first.x + first.width, second.x + second.width)
	bottom := min(first.y + first.height, second.y + second.height)
	if right <= left || bottom <= top {
		return {}, false
	}
	return {left, top, right - left, bottom - top}, true
}

audit_panel_rectangle :: proc(panels: []Ui_Panel, id: Ui_Id) -> (rectangle: Ui_Rectangle, found: bool) {
	for panel in panels {
		if panel.id == id {
			return panel.rectangle, true
		}
	}
	return {}, false
}

// The problems of one command, given the clip it is drawn under.
audit_command :: proc(state: ^Ui_State, command: Draw_Command, clip: Ui_Rectangle, clipped: bool) -> (problems: bit_set[Ui_Audit_Problem]) {
	visible := command.rectangle
	if clipped {
		overlap, overlaps := rectangle_intersection(visible, clip)
		if !overlaps {
			return
		}
		visible = overlap
	}
	screen := Ui_Rectangle{0, 0, state.screen_units.x, state.screen_units.y}
	if !rectangle_inside(visible, screen, UI_AUDIT_TOLERANCE) {
		problems += {.Off_Screen}
	}
	if panel, found := audit_panel_rectangle(state.panels[:], command.panel); found && !rectangle_inside(visible, panel, UI_AUDIT_TOLERANCE) {
		problems += {.Outside_Panel}
	}
	if command.kind == .Text && command.text != "" {
		if ui_text_width_in_weight(state, command.text, command.text_size, command.weight) > command.rectangle.width + UI_AUDIT_TOLERANCE {
			problems += {.Text_Too_Wide}
		}
		if command.rectangle.height + UI_AUDIT_TOLERANCE < command.text_size {
			problems += {.Text_Too_Tall}
		}
	}
	return
}

// Reported once per case, size, problem and command text; the message
// names the first frame it showed in.
audit_report :: proc(audit: ^Ui_Audit, case_text, frame_name: string, problem: Ui_Audit_Problem, kind: Draw_Command_Kind, rectangle: Ui_Rectangle, command_text: string) {
	key := fmt.tprintf("%s|%v|%v|%q", case_text, problem, kind, command_text)
	if key in audit.reported {
		return
	}
	audit.reported[strings.clone(key)] = true
	audit.failures += 1
	if audit.failures <= UI_AUDIT_REPORT_LIMIT {
		log.errorf("%s, %s: %v %v %v %q", case_text, frame_name, problem, kind, rectangle, command_text)
	}
}

audit_draw_list :: proc(audit: ^Ui_Audit, state: ^Ui_State, case_text, frame_name: string) {
	clip: Ui_Rectangle
	clipped := false
	for command in state.draw_list {
		switch command.kind {
		case .Clip_End:
			clipped = false
			continue
		case .Fill, .Outline, .Text, .Focus_Outline, .Clip_Begin, .Atlas_Tile, .Item_Tile, .Image, .Ui_Icon:
		}
		for problem in audit_command(state, command, clip, clipped) {
			audit_report(audit, case_text, frame_name, problem, command.kind, command.rectangle, command.text)
		}
		if command.kind == .Clip_Begin {
			clip, clipped = command.rectangle, true
		}
	}
	safe := ui_safe_area(state)
	for panel in state.panels {
		if !rectangle_inside(panel.rectangle, safe, UI_AUDIT_TOLERANCE) {
			audit_report(audit, case_text, frame_name, .Panel_Outside_Safe_Area, .Fill, panel.rectangle, "")
		}
		if panel.id != UI_GLYPH_BAR_PANEL && panel_under_glyph_bar(state.draw_list[:], panel.rectangle) {
			audit_report(audit, case_text, frame_name, .Panel_Under_Glyph_Bar, .Fill, panel.rectangle, "")
		}
	}
}

panel_under_glyph_bar :: proc(commands: []Draw_Command, panel: Ui_Rectangle) -> bool {
	for command in commands {
		if command.panel != UI_GLYPH_BAR_PANEL {
			continue
		}
		if _, overlaps := rectangle_intersection(inset(command.rectangle, UI_AUDIT_TOLERANCE), panel); overlaps {
			return true
		}
	}
	return false
}

audit_screen_context :: proc(audit: ^Ui_Audit) -> Screen_Context {
	simulation := &audit.simulation
	return Screen_Context {
		settings = &audit.settings,
		monitor_size = UI_AUDIT_MONITOR_SIZE,
		window_scale = audit.window_scale,
		wayland_display_set = audit.wayland_display_set,
		font_families = audit.fonts.families,
		bindings = audit.bindings,
		quit_requested = &audit.quit_requested,
		save_requested = &audit.save_requested,
		title = &audit.title,
		player = &simulation.players[0],
		items = audit.content.items,
		blocks = audit.content.blocks,
		item_sort_ranks = audit.item_sort_ranks,
		world = &simulation.world,
		machines = audit.content.machines,
		fluids = audit.content.fluids,
		veins = audit.content.veins,
		tick_rate = simulation.tick_rate,
		recipes = audit.content.recipes,
		technologies = audit.content.technologies,
		unlocks = &simulation.unlocks,
		quests = audit.content.quests,
		quest_state = &simulation.quests,
		contracts = audit.content.contracts,
		notes = audit.notes,
		tick = simulation.tick,
		recipe_names = audit.recipe_names,
		recipe_order = audit.recipe_order,
		browser = &audit.browser,
		technology_browser = &audit.technology_browser,
		statistics_view = &audit.statistics_view,
		map_view = &audit.map_view,
		generator = &audit.generator,
		biome_banner = &audit.biome_banner,
		developer_mode = true,
		show_diagnostics = &audit.show_diagnostics,
		show_world_overlay = &audit.show_world_overlay,
		developer_requests = &simulation.developer_requests,
		developer_chapter_count = len(audit.content.quests.chapters),
		landing_pad = SAVE_TEST_LANDING_PAD,
	}
}

// One frame the way run_ui_frame builds it, without the draw layer. The
// frame's temporary strings live in the audit's arena until it is checked.
audit_frame :: proc(audit: ^Ui_Audit, state: ^Ui_State, size: Ui_Audit_Size, audit_case: Ui_Audit_Case, input: Ui_Input, frame_name: string) {
	device := state.active_device
	context.temp_allocator = virtual.arena_allocator(&audit.frame_arena)
	defer free_all(context.temp_allocator)
	audit.simulation.players[0].open_machine = audit_case.machine
	if audit_case.selecting != NO_ENTITY {
		audit.browser.selecting_for = audit_case.selecting
	}
	ui_begin(state, input, size.pixels, 1.0 / 60, size.scale, 1)
	state.focus_pulse = device == .Gamepad ? 1 : 0
	screen_context := audit_screen_context(audit)
	if audit_case.hud {
		draw_hud(state, screen_context)
	}
	run_screens(state, screen_context)
	ui_resolve(state)
	ui_append_overlays(state)
	case_text := fmt.tprintf("%s, %.0fx%.0f at scale %.2f, %v glyphs", audit_case.name, size.pixels.x, size.pixels.y, size.scale, device)
	audit_draw_list(audit, state, case_text, frame_name)
}

audit_case_at_size :: proc(audit: ^Ui_Audit, audit_case: Ui_Audit_Case, size: Ui_Audit_Size, device: Input_Device) {
	state := Ui_State {
		theme         = audit.theme,
		active_device = device,
	}
	defer destroy_ui_state(&state)
	for screen in audit_case.screens {
		push_screen(&state.screens, screen)
	}
	if audit_case.keyboard {
		state.keyboard.field = 1
	}
	for toast in audit_case.toasts {
		ui_toast(&state, text(toast))
	}
	if audit_case.mission_control {
		audit_mission_control(audit, &state)
	}
	audit.browser.selecting_for = NO_ENTITY
	audit_frame(audit, &state, size, audit_case, {}, "first frame")
	for step in 0 ..< audit_case.tab_next {
		audit_frame(audit, &state, size, audit_case, {tab_next = true}, fmt.tprintf("tab step %d", step + 1))
	}
	for _ in 0 ..< UI_AUDIT_SETTLE_FRAMES {
		audit_frame(audit, &state, size, audit_case, {hotbar_radial_down = audit_case.radial}, "settled")
	}
	if !audit_case.walk_focus {
		return
	}
	widgets := slice.clone(state.widgets[:])
	defer delete(widgets)
	state.tooltip_open = true
	for widget, index in widgets {
		state.focus = widget.id
		audit_frame(audit, &state, size, audit_case, {}, fmt.tprintf("focus on widget %d", index))
	}
}

UI_AUDIT_MISSION_CONTROL_LONGEST_KEY :: "mc_extraction_rights_done"

audit_mission_control :: proc(audit: ^Ui_Audit, state: ^Ui_State) {
	ui_mission_control_line(state, text(UI_AUDIT_MISSION_CONTROL_LONGEST_KEY))
	ui_mission_control_line(state, text("mc_first_contract_done"))
	line := &state.mission_control.lines[0]
	line.seconds = mission_control_reveal_seconds(line.character_count) / 2
	item := longest_named_item(audit.content.items)
	ui_discovery_card(state, item, item_name(audit.content.items, item))
}

audit_case :: proc(audit: ^Ui_Audit, audit_case: Ui_Audit_Case) {
	for size in UI_AUDIT_SIZES {
		for device in Input_Device {
			audit_case_at_size(audit, audit_case, size, device)
		}
	}
}

// One of every machine the site lacks, away from it; panels only read them.
place_missing_machines :: proc(world: ^World, content: Simulation_Content) {
	present := make([]bool, len(content.machines.machines), context.temp_allocator)
	for _, handle in world.entities.cells {
		if common := entity_common(&world.entities, handle); common != nil {
			present[common.machine] = true
		}
	}
	for machine, index in content.machines.machines {
		if present[index] || machine.kind == .Belt || machine.kind == .Schematic_Crate {
			continue
		}
		add_entity(&world.entities, content.machines, Machine_Id(index), {200 + i32(index) * 8, 1, 200}, 0)
	}
}

// The first entity of every machine with a panel, in machine order.
machines_with_panels :: proc(world: ^World, content: Simulation_Content) -> []Entity_Handle {
	handles := make([]Entity_Handle, len(content.machines.machines), context.temp_allocator)
	for _, handle in world.entities.cells {
		common := entity_common(&world.entities, handle)
		if common != nil && entity_has_panel(&world.entities, handle) && handles[common.machine] == NO_ENTITY {
			handles[common.machine] = handle
		}
	}
	result := make([dynamic]Entity_Handle, context.temp_allocator)
	for handle in handles {
		if handle != NO_ENTITY {
			append(&result, handle)
		}
	}
	return result[:]
}

// The quest with the longest objective text, active; every other quest
// done, so the journal shows every quest's detail.
activate_longest_quest :: proc(quest_state: ^Quest_State, quests: Quest_Registry) {
	longest := 0
	for quest, index in quests.quests {
		if len(text(quest.text_key)) > len(text(quests.quests[longest].text_key)) {
			longest = index
		}
	}
	for &progress, index in quest_state.progress {
		progress.status = index == longest ? .Active : .Done
	}
	quest_state.active = longest
}

UI_AUDIT_MESSAGE_KEYS :: [?]string{"mc_first_research", "mc_first_contract_done", "mc_extraction_rights_done", "mc_contract_survey_fee"}

audit_title_state :: proc() -> Title_State {
	title := Title_State {
		saves_found = true,
		default_settings = default_world_file_settings(test_game_config()),
		delete_index = 0,
	}
	title.setup = make_world_setup(title.default_settings, UI_AUDIT_LONG_WORLD_NAME, 18_446_744_073_709_551_615)
	append(&title.saves, Save_Summary{directory_name = strings.clone("long"), name = strings.clone(UI_AUDIT_LONG_WORLD_NAME), seed = 18_446_744_073_709_551_615, tick = 60 * 60 * 60 * 123, last_played_unix_seconds = 1_790_000_000, loadable = true, load_problem = strings.clone("")})
	append(&title.saves, Save_Summary{directory_name = strings.clone("old"), name = strings.clone(UI_AUDIT_LONG_WORLD_NAME), seed = 20260927, tick = 60 * 60 * 7, last_played_unix_seconds = 1_780_000_000, loadable = false, load_problem = strings.clone("header")})
	return title
}

make_ui_audit :: proc() -> ^Ui_Audit {
	audit := new(Ui_Audit)
	table, error := parse_string_table(#load("../data/strings/en.sjson"))
	assert(error == nil)
	audit.strings = table
	thread_string_table = &audit.strings
	theme, theme_problem := parse_ui_theme(#load("../data/ui/theme.sjson"), "data/ui/theme.sjson")
	assert(theme_problem == "", theme_problem)
	audit.theme = theme
	audit.content = make_save_test_content()
	// Slots draw the shipped icon files, as in the game.
	audit.content.items.icon_loaded = generate_item_icon_pixels(audit.content.items, test_data_directory(), context.temp_allocator).loaded
	audit.generator = make_test_generator(DEFAULT_WORLD_SEED)
	generator := &audit.generator
	audit.simulation = make_save_test_simulation(generator, audit.content)
	simulation := &audit.simulation
	load_save_test_chunks(&simulation.world, generator)
	// The HUD cases show the biome banner at full strength.
	plains := find_biome_index(generator.biomes, "plains")
	audit.biome_banner = Biome_Banner{settled = plains, candidate = plains, shown = plains, shown_seconds = 1, showing = true}
	build_save_test_site(simulation, audit.content)
	run_save_test_ticks(simulation, audit.content, 0, 120)
	place_missing_machines(&simulation.world, audit.content)
	activate_longest_quest(&simulation.quests, audit.content.quests)
	for key, index in UI_AUDIT_MESSAGE_KEYS {
		append(&simulation.quests.messages, Quest_Message{tick = u64(index + 1) * 60 * 60 * 61, text_key = key})
	}
	// A plain row between Mission Control's framed ones (work item 0069).
	longest_item := longest_named_item(audit.content.items)
	append(&simulation.quests.messages, Quest_Message{tick = 60 * 60 * 62, text_key = ITEM_DISCOVERED_KEY, argument_key = audit.content.items.items[longest_item].name_key, item = longest_item})
	player := &simulation.players[0]
	player.crafting = Craft_Queue{recipes = {0, 1, 2, 3, 4, 5, 6, 7}, count = HAND_CRAFT_QUEUE_CAPACITY, waiting = true}
	for &drill in simulation.world.entities.drills.entries {
		if drill.alive {
			player.target = Raycast_Hit{hit = true, entity = drill.handle}
			break
		}
	}
	audit.settings = DEFAULT_SETTINGS
	audit.settings.developer_mode = true
	audit.window_scale = {1, 1}
	fonts_problem: string
	audit.fonts, fonts_problem = load_fonts(test_data_directory())
	assert(fonts_problem == "", fonts_problem)
	bindings, problem := parse_bindings_file(#load("../data/bindings.sjson"), "data/bindings.sjson", context.temp_allocator)
	assert(problem == "", problem)
	audit.bindings = bindings
	audit.title = audit_title_state()
	audit.browser = make_recipe_browser()
	audit.technology_browser = make_technology_browser()
	audit.recipe_names = recipe_display_names(audit.content.recipes, context.temp_allocator)
	audit.recipe_order = recipe_name_order(audit.recipe_names, context.temp_allocator)
	audit.item_sort_ranks = item_sort_ranks(audit.content.items, item_display_names(audit.content.items, context.temp_allocator), context.temp_allocator)
	// Every quest but one is done, so the chapter and quest notes show.
	audit.notes = make_test_notes(audit.content.quests)
	return audit
}

destroy_ui_audit :: proc(audit: ^Ui_Audit) {
	thread_string_table = nil
	destroy_simulation(&audit.simulation)
	destroy_string_table(&audit.strings)
	destroy_arena(audit.fonts.arena)
	destroy_save_summaries(&audit.title.saves)
	delete(audit.title.saves)
	destroy_map_view(&audit.map_view)
	virtual.arena_destroy(&audit.frame_arena)
	for message in audit.reported {
		delete(message)
	}
	delete(audit.reported)
	free(audit)
}

// The item with the longest name in the shipped strings.
longest_named_item :: proc(items: Item_Registry) -> Item_Id {
	longest := Item_Id(0)
	for _, index in items.items {
		if len(item_name(items, Item_Id(index))) > len(item_name(items, longest)) {
			longest = Item_Id(index)
		}
	}
	return longest
}

// An inserter waiting for room with the longest item name in its hand
// (work item 0079): the hand slot, and the state line naming the item in
// the panel and in the HUD. The inserter and the target are restored.
audit_waiting_inserter :: proc(audit: ^Ui_Audit) {
	simulation := &audit.simulation
	player := &simulation.players[0]
	for &inserter in simulation.world.entities.inserters.entries {
		if !inserter.alive {
			continue
		}
		held, inserter_state, target := inserter.held, inserter.state, player.target
		inserter.held, inserter.state = Item_Stack{longest_named_item(audit.content.items), 1}, .Waiting_For_Room
		player.target = Raycast_Hit{hit = true, entity = inserter.handle}
		audit_case(audit, {name = "inserter waiting with an item in hand", screens = {.Machine}, hud = true, machine = inserter.handle, walk_focus = true})
		inserter.held, inserter.state, player.target = held, inserter_state, target
		return
	}
}

// The Display tab with the Resolution row live (not borderless) at a
// configured size outside the choices and the widest cap (work item 0080).
// The settings are restored.
audit_windowed_display :: proc(audit: ^Ui_Audit) {
	settings := audit.settings
	audit.settings.window_mode = .Fullscreen
	audit.settings.resolution = {7680, 4320}
	audit.settings.frame_rate_cap = 480
	audit_case(audit, {name = "settings display fullscreen", screens = {.Pause, .Settings}, walk_focus = true})
	audit.settings = settings
}

// The Display tab in borderless on a desktop scaled XWayland session: the
// Resolution row's value carries the note (work item 0084). The settings
// and the display facts are restored.
audit_desktop_scaled_display :: proc(audit: ^Ui_Audit) {
	settings := audit.settings
	audit.settings.window_mode = .Borderless
	audit.window_scale, audit.wayland_display_set = {1.7, 1.7}, true
	audit_case(audit, {name = "settings display desktop scaled", screens = {.Pause, .Settings}, walk_focus = true})
	audit.window_scale, audit.wayland_display_set = {1, 1}, false
	audit.settings = settings
}

// The Notes tab with every note unlocked, so each note's text is audited
// (work item 0070). The unlocks are restored.
audit_every_note :: proc(audit: ^Ui_Audit) {
	unlocks := &audit.simulation.unlocks
	obtained := slice.clone(unlocks.obtained, context.temp_allocator)
	researched := slice.clone(unlocks.researched, context.temp_allocator)
	slice.fill(unlocks.obtained, true)
	slice.fill(unlocks.researched, true)
	audit_case(audit, {name = "journal notes, every note", screens = {.Journal}, tab_next = len(audit.content.quests.chapters) + 1, walk_focus = true})
	copy(unlocks.obtained, obtained)
	copy(unlocks.researched, researched)
}

UI_AUDIT_TOASTS :: [?]string{"mc_extraction_rights_done", "inventory_full", "developer_applies_on_resume"}

audit_every_case :: proc(audit: ^Ui_Audit) {
	toasts := UI_AUDIT_TOASTS
	audit_case(audit, {name = "title", screens = {.Title}, walk_focus = true})
	audit_case(audit, {name = "new world", screens = {.Title, .New_World}, walk_focus = true})
	audit_case(audit, {name = "on-screen keyboard", screens = {.Title, .New_World}, keyboard = true, walk_focus = true})
	audit_case(audit, {name = "load", screens = {.Title, .Load_World}, walk_focus = true})
	audit_case(audit, {name = "confirm delete", screens = {.Title, .Load_World, .Confirm_Delete}, walk_focus = true})
	audit_case(audit, {name = "hud", hud = true, toasts = toasts[:]})
	audit_case(audit, {name = "hud radial", hud = true, radial = true})
	audit_case(audit, {name = "hud mission control", hud = true, toasts = toasts[:], mission_control = true})
	audit_case(audit, {name = "pause", screens = {.Pause}, walk_focus = true})
	for tab in 0 ..< 4 {
		audit_case(audit, {name = fmt.tprintf("settings tab %d", tab), screens = {.Pause, .Settings}, tab_next = tab, walk_focus = true})
	}
	audit_windowed_display(audit)
	audit_desktop_scaled_display(audit)
	audit_case(audit, {name = "developer", screens = {.Pause, .Developer}, walk_focus = true})
	audit_case(audit, {name = "inventory", screens = {.Inventory}, walk_focus = true})
	simulation := &audit.simulation
	for handle in machines_with_panels(&simulation.world, audit.content) {
		machine := audit.content.machines.machines[entity_common(&simulation.world.entities, handle).machine]
		tabs := machine.kind == .Launch_Pad ? 3 : 1
		for tab in 0 ..< tabs {
			name := fmt.tprintf("machine %s tab %d", machine.id, tab)
			audit_case(audit, {name = name, screens = {.Machine}, machine = handle, tab_next = tab, walk_focus = true})
		}
	}
	audit_waiting_inserter(audit)
	audit_case(audit, {name = "recipes", screens = {.Recipes}, walk_focus = true})
	for &assembler in simulation.world.entities.assemblers.entries {
		if assembler.alive && audit.content.machines.machines[assembler.machine].recipe_choice != .Fixed {
			audit_case(audit, {name = "recipe selection", screens = {.Machine, .Recipes}, machine = assembler.handle, selecting = assembler.handle, walk_focus = true})
			break
		}
	}
	audit_case(audit, {name = "technologies", screens = {.Technologies}, walk_focus = true})
	// The chapters, the contracts and the notes (work item 0070).
	for tab in 0 ..= len(audit.content.quests.chapters) + 1 {
		audit_case(audit, {name = fmt.tprintf("journal tab %d", tab), screens = {.Journal}, tab_next = tab, walk_focus = true})
	}
	audit_every_note(audit)
	for tab in 0 ..< 3 {
		audit_case(audit, {name = fmt.tprintf("statistics tab %d", tab), screens = {.Statistics}, tab_next = tab, walk_focus = true})
	}
	audit_case(audit, {name = "power", screens = {.Power}, walk_focus = true})
	audit_case(audit, {name = "map", screens = {.Map}})
	// Last, since it changes the hotbar: a selected magnetometer shows its
	// dial and the Use_Item hint.
	player := &simulation.players[0]
	inventory_hotbar(player.inventory)[player.selected_hotbar_slot] = Item_Stack{test_item(audit.content.items, "magnetometer"), 1}
	player.magnetometer.found = true
	audit_case(audit, {name = "hud magnetometer", hud = true, toasts = toasts[:]})
}

@(test)
test_every_screen_stays_inside_the_screen :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	audit_every_case(audit)
	testing.expectf(t, audit.failures == 0, "%d UI bounds problems", audit.failures)
}
