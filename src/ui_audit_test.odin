package game

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem/virtual"
import "core:slice"
import "core:strings"
import "core:testing"
import "platform"

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
// item. Every size also runs at the largest text scale (work item 0074):
// widths are measured at the scaled size, as the game draws them, while a
// text's height is checked at the size the layout named, since the rows
// keep their height and larger text grows into their padding. The Steam
// Deck preset's scales run once more at the Deck's size (work item 0076).

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
	// The laptop's panel under a 1.7 desktop scale on Wayland, in render
	// pixels (work item 0085): the window is 1694 by 1129 there, the UI
	// lays out in the framebuffer's 2880 by 1920.
	{{2880, 1920}, 1.0},
	// Split screen (work item 0178): a quarter of 1080p (three and four
	// players), the stacked half, and the side by side half at the scale
	// viewport_ui_scale gives it.
	{{960, 540}, 1.0},
	{{1920, 540}, 1.0},
	{{960, 1080}, 0.5},
}

// Each size runs at the default text size and at the largest (work item
// 0074).
UI_AUDIT_TEXT_SCALES :: [?]f32{1, TEXT_SCALE_RANGE.maximum}

// The Steam Deck's screen at the Deck preset's interface scale, run at the
// preset's text scale after the matrix (work item 0076).
UI_AUDIT_DECK_SIZE :: Ui_Audit_Size{{1280, 800}, DECK_PRESET_UI_SCALE}

UI_AUDIT_TOLERANCE :: 1.0
// The Display tab's Resolution row lists the choices up to it.
UI_AUDIT_MONITOR_SIZE :: [2]int{3840, 2160}
// Plain frames after the tab steps, so the focus and the screens settle.
UI_AUDIT_SETTLE_FRAMES :: 2
// Problems logged one by one; the count covers them all.
UI_AUDIT_REPORT_LIMIT :: 200
UI_AUDIT_LONG_WORLD_NAME :: "Wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww"
// A Syncthing folder on the phone's shared storage (work item 0131).
UI_AUDIT_LONG_EXPORT_DIRECTORY :: "/storage/emulated/0/Syncthing/mine-oh-belowed-exports/couch-and-phone"

Ui_Audit_Problem :: enum u8 {
	Off_Screen,
	Outside_Panel,
	Panel_Outside_Safe_Area,
	Text_Too_Wide,
	Text_Too_Tall,
	// A panel under the glyph bar's glyphs or labels.
	Panel_Under_Glyph_Bar,
	// A label of the touch row cut short (0137): the row takes the whole
	// safe width where the strip beside the HUD's hotbar would cut one.
	Button_Label_Cut,
	// A glyph or label of the HUD's glyph bar over a hotbar slot (0219).
	Glyph_Bar_Over_Hotbar,
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
	// The crafting station whose recipe browser is audited (0196).
	station:      Entity_Handle,
	keyboard:     bool,
	// The keyboard types through the system keyboard: no keys (0133).
	system_keyboard: bool,
	radial:       bool,
	// String keys shown as toasts from the first frame.
	toasts:       []string,
	// Mission Control's panel with the longest line half typed and one
	// waiting, and the discovery card of the longest named item (work
	// item 0069).
	mission_control: bool,
	// Audit one more frame per widget with the focus and the info panel on it.
	walk_focus:   bool,
	// The pointer is a finger (Ui_Input.pointer_is_touch): the screens
	// draw the touch row (0125, 0137).
	touch:        bool,
	// The screens of a split screen guest's viewport (0178), and of one
	// whose player has no entry yet.
	split_screen_guest: bool,
	waiting_for_player: bool,
	// The pause menu during a new world's fall before its hit, with Skip
	// arrival and without the rows that open screens (0200).
	arrival_falling: bool,
	// The notice of a viewport whose pad was lost (0178).
	notice:       string,
	// The item the configure pop-up configures (0202).
	configure_item: Item_Id,
	// The tools radial held and steered to the placement editor's entry
	// (0215).
	tools_radial: bool,
	// The placement editor's HUD with the stone furnace, refused for the
	// reason when not None; Anchored points the screen context at an
	// anchored editor, so the pause menu shows Cancel placement (0215).
	placement:         Placement_Editor_Mode,
	placement_refusal: Field_Edit_Refusal,
	// A field session: the HUD's field player holds the tool of the
	// selected hotbar stack, so the glyph bar shows the held hints (0219).
	field_session:     bool,
}

// Owns everything a Screen_Context points into.
Ui_Audit :: struct {
	strings:            String_Table,
	theme:              Ui_Theme,
	content:            Simulation_Content,
	simulation:         Simulation_State,
	settings:           Settings,
	// The screen context's display fact (work items 0084 and 0085).
	platform:           Window_Platform,
	fonts:              Loaded_Fonts,
	bindings:           []Binding,
	title:              Title_State,
	// The shipped planets of the New world screen, in the test's temp
	// allocator.
	planets:            []Planet,
	views:              Session_Views,
	generator:          Generator,
	biome_banner:       Biome_Banner,
	recipe_names:       []string,
	recipe_order:       []int,
	item_sort_ranks:    []u16,
	notes:              Note_Registry,
	requests:           Frame_Requests,
	save_requested:     bool,
	diagnostics_page:   Diagnostics_Page,
	show_world_overlay: bool,
	// The shipped procedural textures (work item 0100).
	texture_editor:     Texture_Editor,
	// The shipped data directory's tree, no overlay (work item 0129).
	data_browser:       Data_Browser,
	// The shipped touch layout as Default, no user layouts, and the
	// editor's draft of Default (work item 0121).
	default_touch_layout: Touch_Overlay_Layout,
	touch_layouts:        Touch_Layouts,
	touch_layout_editor:  Touch_Layout_Editor,
	// The editor the placement cases point the screen context at (0215).
	placement_editor:   Placement_Editor,
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
		case .Fill, .Outline, .Text, .Focus_Outline, .Clip_Begin, .Atlas_Tile, .Item_Tile, .Image, .Ui_Icon, .Circle, .Ring, .Arc:
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
	content := audit.content
	content.generator = &audit.generator
	return Screen_Context {
		settings = &audit.settings,
		monitor_size = UI_AUDIT_MONITOR_SIZE,
		platform = audit.platform,
		font_families = audit.fonts.families,
		bindings = audit.bindings,
		requests = &audit.requests,
		save_requested = &audit.save_requested,
		title = &audit.title,
		planets = audit.planets,
		content = content,
		notes = audit.notes,
		item_sort_ranks = audit.item_sort_ranks,
		recipe_names = audit.recipe_names,
		recipe_order = audit.recipe_order,
		player = &simulation.players[0],
		world = &simulation.world,
		records = &simulation.records,
		tick_rate = simulation.tick_rate,
		unlocks = &simulation.unlocks,
		quest_state = &simulation.quests,
		tick = simulation.tick,
		player_commands = &simulation.player_commands,
		landing_pad = SAVE_TEST_LANDING_PAD,
		views = &audit.views,
		developer = Developer_Context {
			enabled = true,
			chapter_count = len(audit.content.quests.chapters),
			diagnostics_page = &audit.diagnostics_page,
			show_world_overlay = &audit.show_world_overlay,
			texture_editor = &audit.texture_editor,
			data_browser = &audit.data_browser,
		},
		touch_layouts = &audit.touch_layouts,
		touch_layout_editor = &audit.touch_layout_editor,
		default_touch_layout = audit.default_touch_layout,
	}
}

// The HUD's derivations as make_hud_context builds them, the biome
// sampled under the player; no touch overlay.
audit_hud_context :: proc(audit: ^Ui_Audit) -> Hud_Context {
	position := audit.simulation.players[0].position
	column := sample_column(&audit.generator, i32(math.floor(position.x)), i32(math.floor(position.z)))
	return Hud_Context{biome_banner = &audit.biome_banner, biome = column.biome, biomes = audit.generator.biomes}
}

// One frame the way build_viewport_ui builds it, without the draw layer. The
// frame's temporary strings live in the audit's arena until it is checked.
audit_frame :: proc(audit: ^Ui_Audit, state: ^Ui_State, size: Ui_Audit_Size, audit_case: Ui_Audit_Case, input: Ui_Input, frame_name: string) {
	device := state.active_device
	context.temp_allocator = virtual.arena_allocator(&audit.frame_arena)
	defer free_all(context.temp_allocator)
	audit.simulation.players[0].open_machine = audit_case.machine
	if audit_case.selecting != NO_ENTITY {
		audit.views.recipe_browser.selecting_for = audit_case.selecting
	}
	if audit_case.station != NO_ENTITY {
		audit.views.recipe_browser.station = audit_case.station
	}
	frame_input := input
	frame_input.pointer_is_touch = audit_case.touch
	ui_begin(state, frame_input, size.pixels, 1.0 / 60, size.scale, 1, ui_accessibility(audit.settings))
	state.focus_pulse = device == .Gamepad ? 1 : 0
	screen_context := audit_screen_context(audit)
	hud := audit_hud_context(audit)
	// On touch the HUD's touch buttons (0134), rotate included, and the
	// placement editor's grid while it is anchored (0215).
	if audit_case.touch {
		hud.touch_hud_buttons = hud_touch_buttons_shown(true, audit_case.placement == .Anchored)
	}
	if audit_case.placement != .None {
		furnace, _ := find_machine_id(audit.content.machines, "stone_furnace")
		hud.placement = Placement_Editor_Hud{mode = audit_case.placement, machine = furnace, refusal = audit_case.placement_refusal}
		audit.placement_editor = Placement_Editor{on = true, anchored = audit_case.placement == .Anchored, machine = furnace}
		screen_context.placement_editor = &audit.placement_editor
	}
	if audit_case.field_session {
		audit_field_session_hud(audit, &hud)
	}
	if audit_case.hud {
		draw_hud(state, screen_context, hud)
	}
	screen_context.split_screen_guest = audit_case.split_screen_guest
	screen_context.waiting_for_player = audit_case.waiting_for_player
	screen_context.arrival_falling = audit_case.arrival_falling
	screen_context.arrival_skippable = audit_case.arrival_falling
	run_screens(state, screen_context)
	if audit_case.notice != "" {
		draw_loading_notice(state, text(audit_case.notice))
	}
	ui_resolve(state)
	ui_append_overlays(state)
	case_text := fmt.tprintf("%s, %.0fx%.0f at scale %.2f, text %.1f, %v glyphs", audit_case.name, size.pixels.x, size.pixels.y, size.scale, audit.settings.text_scale, device)
	audit_draw_list(audit, state, case_text, frame_name)
	if audit_case.hud && len(audit_case.screens) == 0 && !audit_case.touch {
		audit_glyph_bar_clear_of_hotbar(audit, state, audit.simulation.players[0].selected_hotbar_slot, case_text, frame_name)
	}
	if audit_case.touch {
		audit_touch_labels_whole(audit, state, case_text, frame_name)
	}
}

// The HUD of a field session as make_hud_context builds it: the field
// player holds the tool of the selected hotbar stack (0219).
audit_field_session_hud :: proc(audit: ^Ui_Audit, hud: ^Hud_Context) {
	player := &audit.simulation.players[0]
	stack := selected_hotbar_stack(player^)
	hud.field_session, hud.field_view_set = true, true
	hud.field_view = player.field
	hud.field_view.tool, _, hud.field_view.held_machine = field_tool_for_item(audit.content, stack_is_empty(stack) ? NO_ITEM : stack.item)
}

// The hotbar's slot boxes as drawn: the fills in the slot colour at the
// rectangles the hotbar lays out. In the temp allocator.
hotbar_slot_boxes_in_draw_list :: proc(commands: []Draw_Command, expected: [HOTBAR_SLOT_COUNT]Ui_Rectangle) -> [dynamic]Ui_Rectangle {
	boxes := make([dynamic]Ui_Rectangle, context.temp_allocator)
	for command in commands {
		if command.kind != .Fill || command.color != HUD_SLOT_COLOR {
			continue
		}
		for rectangle in expected {
			if rectangle_inside(command.rectangle, rectangle, UI_AUDIT_TOLERANCE) && rectangle_inside(rectangle, command.rectangle, UI_AUDIT_TOLERANCE) {
				append(&boxes, command.rectangle)
				break
			}
		}
	}
	return boxes
}

// No command of the HUD's glyph bar lies over a hotbar slot (0219).
audit_glyph_bar_clear_of_hotbar :: proc(audit: ^Ui_Audit, state: ^Ui_State, selected: int, case_text, frame_name: string) {
	slots := hotbar_slot_boxes_in_draw_list(state.draw_list[:], hud_hotbar_rectangles(ui_safe_area(state), selected))
	if len(slots) < HOTBAR_SLOT_COUNT {
		audit_report(audit, case_text, frame_name, .Glyph_Bar_Over_Hotbar, .Fill, {}, fmt.tprintf("%d of %d hotbar slots found", len(slots), HOTBAR_SLOT_COUNT))
	}
	for command in state.draw_list {
		if command.panel != UI_GLYPH_BAR_PANEL {
			continue
		}
		for slot in slots {
			if _, overlaps := rectangle_intersection(inset(command.rectangle, UI_AUDIT_TOLERANCE), slot); overlaps {
				audit_report(audit, case_text, frame_name, .Glyph_Bar_Over_Hotbar, command.kind, command.rectangle, command.text)
			}
		}
	}
}

// Every label of the touch row shows whole, never with an ellipsis.
audit_touch_labels_whole :: proc(audit: ^Ui_Audit, state: ^Ui_State, case_text, frame_name: string) {
	for command in state.draw_list {
		if command.panel == UI_GLYPH_BAR_PANEL && command.kind == .Text && strings.has_suffix(command.text, UI_ELLIPSIS) {
			audit_report(audit, case_text, frame_name, .Button_Label_Cut, .Text, command.rectangle, command.text)
		}
	}
}

audit_case_at_size :: proc(audit: ^Ui_Audit, audit_case: Ui_Audit_Case, size: Ui_Audit_Size, device: Input_Device) {
	state := Ui_State {
		theme         = audit.theme,
		active_device = device,
		bindings      = audit.bindings,
	}
	defer destroy_ui_state(&state)
	for screen in audit_case.screens {
		push_screen(&state.screens, screen)
	}
	state.configure.item = audit_case.configure_item
	if audit_case.keyboard {
		state.keyboard.field = 1
		state.keyboard.system = audit_case.system_keyboard
	}
	for toast in audit_case.toasts {
		ui_toast(&state, text(toast))
	}
	if audit_case.mission_control {
		audit_mission_control(audit, &state)
	}
	audit.views.recipe_browser.selecting_for = NO_ENTITY
	audit.views.recipe_browser.station = NO_ENTITY
	audit_frame(audit, &state, size, audit_case, {}, "first frame")
	for step in 0 ..< audit_case.tab_next {
		audit_frame(audit, &state, size, audit_case, {tab_next = true}, fmt.tprintf("tab step %d", step + 1))
	}
	for _ in 0 ..< UI_AUDIT_SETTLE_FRAMES {
		steer := audit_case.tools_radial ? [2]f32{0, TOOLS_RADIAL_STEER_PIXELS} : {}
		audit_frame(audit, &state, size, audit_case, {hotbar_radial_down = audit_case.radial, tools_radial_down = audit_case.tools_radial, look_delta = steer}, "settled")
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
	text_scale := audit.settings.text_scale
	defer audit.settings.text_scale = text_scale
	for scale in UI_AUDIT_TEXT_SCALES {
		audit.settings.text_scale = scale
		for size in UI_AUDIT_SIZES {
			for device in Input_Device {
				audit_case_at_size(audit, audit_case, size, device)
			}
		}
	}
	audit.settings.text_scale = DECK_PRESET_TEXT_SCALE
	for device in Input_Device {
		audit_case_at_size(audit, audit_case, UI_AUDIT_DECK_SIZE, device)
	}
}

// One of every machine the site lacks, away from it; panels only read them.
place_missing_machines :: proc(world: ^World, content: Simulation_Content) {
	present := make([]bool, len(content.machines.machines), context.temp_allocator)
	for _, occupant in world.entities.frames.occupants {
		if common := entity_common(&world.entities, entity_from_occupant(occupant.handle)); common != nil {
			present[common.machine] = true
		}
	}
	for machine, index in content.machines.machines {
		if present[index] || machine.kind == .Belt || machine.kind == .Schematic_Crate {
			continue
		}
		add_entity(&world.entities, content.machines, Machine_Id(index), {200 + i32(index) * MAXIMUM_FOOTPRINT_SIZE, 1, 200}, 0)
	}
}

// The first entity of every machine with a panel, in machine order.
machines_with_panels :: proc(world: ^World, content: Simulation_Content) -> []Entity_Handle {
	handles := make([]Entity_Handle, len(content.machines.machines), context.temp_allocator)
	for _, occupant in world.entities.frames.occupants {
		handle := entity_from_occupant(occupant.handle)
		common := entity_common(&world.entities, handle)
		// A crafting station's or bench's machine screen only forwards to
		// the recipe browser, audited as its own case.
		station := common != nil && machine_is_crafting_station(content.machines.machines[common.machine])
		if common != nil && !station && entity_has_panel(&world.entities, content.machines, handle) && handles[common.machine] == NO_ENTITY {
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
		multiplayer = make_multiplayer_state(),
	}
	text_field_set(&title.multiplayer.address, "192.168.100.200:47326")
	title.setup = make_world_setup(title.default_settings, shipped_test_planets(), UI_AUDIT_LONG_WORLD_NAME, 18_446_744_073_709_551_615)
	append(&title.saves, Save_Summary{directory_name = strings.clone("long"), name = strings.clone(UI_AUDIT_LONG_WORLD_NAME), seed = 18_446_744_073_709_551_615, tick = 60 * 60 * 60 * 123, last_played_unix_seconds = 1_790_000_000, loadable = true, load_problem = strings.clone("")})
	append(&title.saves, Save_Summary{directory_name = strings.clone("old"), name = strings.clone(UI_AUDIT_LONG_WORLD_NAME), seed = 20260927, tick = 60 * 60 * 7, last_played_unix_seconds = 1_780_000_000, loadable = false, load_problem = strings.clone("header")})
	return title
}

// Runs of several crafts (0138), twelve enough to wrap into rows beside
// the hotbar, the front one waiting for an item.
audit_craft_queue :: proc(recipes: Recipe_Registry, waiting_for: Item_Id, count := 12) -> Craft_Queue {
	queue := Craft_Queue{waiting_for = waiting_for}
	for recipe, index in recipes.recipes {
		if queue.count == count {
			break
		}
		if len(recipe.outputs) > 0 {
			queue.runs[queue.count] = {index, 1 + queue.count * 13}
			queue.count += 1
		}
	}
	return queue
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
	load_save_test_chunks(&simulation.world, &simulation.records, generator)
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
	player.crafting = audit_craft_queue(audit.content.recipes, longest_item)
	for &drill in simulation.world.entities.drills.entries {
		if drill.alive {
			player.target = Raycast_Hit{hit = true, entity = drill.handle}
			break
		}
	}
	audit.settings = DEFAULT_SETTINGS
	audit.settings.developer_mode = true
	audit.platform = .X11
	fonts_problem: string
	audit.fonts, fonts_problem = load_fonts(test_data_directory())
	assert(fonts_problem == "", fonts_problem)
	bindings, problem := parse_bindings_file(#load("../data/bindings.sjson"), "data/bindings.sjson", context.temp_allocator)
	assert(problem == "", problem)
	audit.bindings = bindings
	audit.planets = shipped_test_planets()
	audit.title = audit_title_state()
	audit.views = make_session_views()
	audit.recipe_names = recipe_display_names(audit.content.recipes, context.temp_allocator)
	audit.recipe_order = recipe_name_order(audit.recipe_names, context.temp_allocator)
	audit.item_sort_ranks = item_sort_ranks(audit.content.items, item_display_names(audit.content.items, context.temp_allocator), context.temp_allocator)
	// Every quest but one is done, so the chapter and quest notes show.
	audit.notes = make_test_notes(audit.content.quests)
	load_texture_editor(&audit.texture_editor, test_data_directory(), "", audit.content.blocks)
	audit.data_browser = make_data_browser()
	rebuild_data_tree(&audit.data_browser, list_data_files(test_data_directory(), ""))
	touch_layout, touch_layout_problem := parse_touch_overlay_file(#load("../data/touch_overlay.sjson"), "data/touch_overlay.sjson", context.temp_allocator)
	assert(touch_layout_problem == "", touch_layout_problem)
	audit.default_touch_layout = touch_layout
	start_touch_layout_draft(&audit.touch_layout_editor, DEFAULT_TOUCH_LAYOUT_NAME, touch_layout)
	return audit
}

destroy_ui_audit :: proc(audit: ^Ui_Audit) {
	thread_string_table = nil
	destroy_simulation(&audit.simulation)
	destroy_string_table(&audit.strings)
	destroy_arena(audit.fonts.arena)
	destroy_save_summaries(&audit.title.saves)
	delete(audit.title.saves)
	destroy_multiplayer_state(&audit.title.multiplayer)
	destroy_session_views(&audit.views)
	destroy_texture_editor(&audit.texture_editor)
	destroy_data_browser(&audit.data_browser)
	destroy_touch_layouts(&audit.touch_layouts)
	destroy_touch_layout_editor(&audit.touch_layout_editor)
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

// A broken furnace (0201): the panel's "Broken down, tear it down" line
// under the description, and the HUD's state line naming it, at every
// size. The furnace and the target are restored.
audit_broken_furnace :: proc(audit: ^Ui_Audit) {
	player := &audit.simulation.players[0]
	for &furnace in audit.simulation.world.entities.furnaces.entries {
		if !furnace.alive {
			continue
		}
		target := player.target
		furnace.broken, player.target = true, Raycast_Hit{hit = true, entity = furnace.handle}
		audit_case(audit, {name = "broken furnace", screens = {.Machine}, hud = true, machine = furnace.handle, walk_focus = true})
		furnace.broken, player.target = false, target
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
	audit.platform = .XWayland
	audit_case(audit, {name = "settings display desktop scaled", screens = {.Pause, .Settings}, walk_focus = true})
	audit.platform = .X11
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

// The touch layout editor (work item 0121) with nothing, a button and the
// stick selected, and its name entry, on GameNative's buttons (Default has
// none, 0134).
audit_touch_layout_editor :: proc(audit: ^Ui_Audit) {
	editor := &audit.touch_layout_editor
	start_touch_layout_draft(editor, DEFAULT_TOUCH_LAYOUT_NAME, gamenative_touch_layout())
	defer start_touch_layout_draft(editor, DEFAULT_TOUCH_LAYOUT_NAME, audit.default_touch_layout)
	selections := [?]int{-1, 0, zone_element(editor.draft, .Stick, .Left)}
	for selected in selections {
		editor.selected = selected
		audit_case(audit, {name = fmt.tprintf("touch layout editor, element %d selected", selected), screens = {.Pause, .Settings, .Touch_Layout}, walk_focus = true})
	}
	editor.selected = -1
	audit_case(audit, {name = "touch layout name entry", screens = {.Pause, .Settings, .Touch_Layout}, keyboard = true, walk_focus = true})
	audit_case(audit, {name = "touch layout name entry, system keyboard", screens = {.Pause, .Settings, .Touch_Layout}, keyboard = true, system_keyboard = true})
}

// The Data files screen (work item 0129): the tree with fonts, one font's
// directory, the quests and the shaders expanded and a chapter marked edited and selected, so the
// tag and a live Discard show; that chapter open with its first values
// expanded; a shader open line by line. Each also with the touch row.
// The browser is closed and collapsed again after.
audit_data_browser :: proc(audit: ^Ui_Audit) {
	browser := &audit.data_browser
	defer close_data_browser_file(browser)
	defer set_data_browser_selection(browser, -1, false)
	for path in ([]string{"fonts", "fonts/play", "quests", "shaders"}) {
		browser.expanded[find_data_tree_row(browser.rows, path)] = true
	}
	defer for &expanded in browser.expanded {
		expanded = false
	}
	chapter := find_data_tree_row(browser.rows, "quests/chapter_01.sjson")
	assert(chapter >= 0, "no quests/chapter_01.sjson in the data directory")
	set_data_browser_selection(browser, chapter, true)
	screens := []Screen{.Pause, .Developer, .Data_Files}
	audit_case(audit, {name = "data files", screens = screens, walk_focus = true})
	audit_case(audit, {name = "data files touch row", screens = screens, hud = true, touch = true})
	// Work item 0131: a long shared storage path in the export row with
	// Export on save on, and the directory under either keyboard.
	settings := audit.settings
	audit.settings.export_directory = UI_AUDIT_LONG_EXPORT_DIRECTORY
	audit.settings.export_on_save = true
	audit_case(audit, {name = "data files, an export directory", screens = screens, walk_focus = true})
	audit_case(audit, {name = "data files, an export directory, touch row", screens = screens, hud = true, touch = true})
	browser.editing_export_directory, browser.export_field = true, make_text_field(UI_AUDIT_LONG_EXPORT_DIRECTORY, TEXT_FIELD_CAPACITY)
	audit_case(audit, {name = "data files, the export directory under the keyboard", screens = screens, keyboard = true, walk_focus = true})
	audit_case(audit, {name = "data files, the export directory under the system keyboard", screens = screens, keyboard = true, system_keyboard = true})
	browser.editing_export_directory = false
	audit.settings = settings
	open_data_browser_file(browser, test_data_directory())
	expand_first_data_values(browser)
	audit_case(audit, {name = "data files, a chapter open", screens = screens, walk_focus = true})
	audit_case(audit, {name = "data files, a chapter open, touch row", screens = screens, hud = true, touch = true})
	// Work item 0130: both tags in the heading, Duplicate and Remove live
	// on a selected element, and a string under either keyboard.
	element := first_data_value_element(browser^)
	assert(element >= 0, "no array element in quests/chapter_01.sjson")
	browser.value_selected, browser.unsaved, browser.shows_overlay = element, true, true
	audit_case(audit, {name = "data files, a chapter edited", screens = screens, walk_focus = true})
	// A failed start load turned the data edits off: the notice over the
	// rows (the audit's own thread, so no other test sees it).
	data_edits_reading.off = true
	data_edits_reading.off_problem = "invalid /storage/emulated/0/Android/data/io.github.tubbles.mineohbelowed/files/state/mine-oh-belowed/data_edits/recipes.sjson: recipe \"plank\" has seconds 0"
	audit_case(audit, {name = "data files, data edits off", screens = screens, walk_focus = true})
	audit_case(audit, {name = "data files, data edits off, touch row", screens = screens, hud = true, touch = true})
	data_edits_reading = {}
	string_row := longest_editable_data_string(browser^)
	assert(string_row >= 0, "no editable string in quests/chapter_01.sjson")
	field_text, characters, _ := data_value_field_text(data_value_at_row(browser.value, browser.value_rows, string_row))
	browser.editing_row, browser.value_field = string_row, make_text_field(field_text, TEXT_FIELD_CAPACITY, characters)
	audit_case(audit, {name = "data files, a value under the keyboard", screens = screens, keyboard = true, walk_focus = true})
	audit_case(audit, {name = "data files, a value under the system keyboard", screens = screens, keyboard = true, system_keyboard = true})
	browser.editing_row, browser.value_selected, browser.unsaved, browser.shows_overlay = -1, -1, false, false
	set_data_browser_selection(browser, -1, false)
	browser.selected = find_data_tree_row(browser.rows, "shaders/chunk.fs")
	open_data_browser_file(browser, test_data_directory())
	audit_case(audit, {name = "data files, a shader open", screens = screens})
}

// Marks the chosen row edited (-1 clears every mark) and selects it.
set_data_browser_selection :: proc(browser: ^Data_Browser, row: int, edited: bool) {
	for &entry in browser.rows {
		entry.edited = false
	}
	if row >= 0 {
		browser.rows[row].edited = edited
	}
	browser.selected = row
}

// The first array element among the value rows, -1 for none.
first_data_value_element :: proc(browser: Data_Browser) -> int {
	for _, index in browser.value_rows {
		if data_value_row_is_element(browser.value_rows, index) {
			return index
		}
	}
	return -1
}

// The value row of the longest string the keyboard can edit, -1 for none.
longest_editable_data_string :: proc(browser: Data_Browser) -> int {
	longest, longest_length := -1, -1
	for row, index in browser.value_rows {
		if row.expandable {
			continue
		}
		value := data_value_at_row(browser.value, browser.value_rows, index)
		field_text, characters, editable := data_value_field_text(value)
		if editable && characters == .Printable && len(field_text) > longest_length {
			longest, longest_length = index, len(field_text)
		}
	}
	return longest
}

// The first object or array and the first one inside it.
expand_first_data_values :: proc(browser: ^Data_Browser) {
	expanded_count := 0
	for row, index in browser.value_rows {
		if row.expandable && expanded_count < 2 {
			browser.value_expanded[index] = true
			expanded_count += 1
		}
	}
}

// The touch row of every screen besides the slot screens (0137), with
// the HUD under it as in the game.
audit_touch_rows :: proc(audit: ^Ui_Audit) {
	Touch_Audit_Case :: struct {
		name:     string,
		screens:  []Screen,
		tab_next: int,
		keyboard: bool,
		system_keyboard: bool,
	}
	cases := [?]Touch_Audit_Case {
		{name = "title", screens = {.Title}},
		{name = "new world", screens = {.Title, .New_World}},
		{name = "on-screen keyboard", screens = {.Title, .New_World}, keyboard = true},
		{name = "system keyboard", screens = {.Title, .New_World}, keyboard = true, system_keyboard = true},
		{name = "load", screens = {.Title, .Load_World}},
		{name = "confirm delete", screens = {.Title, .Load_World, .Confirm_Delete}},
		{name = "multiplayer", screens = {.Title, .Multiplayer}},
		{name = "multiplayer address keyboard", screens = {.Title, .Multiplayer}, keyboard = true},
		{name = "pause", screens = {.Pause}},
		{name = "settings", screens = {.Pause, .Settings}},
		{name = "developer", screens = {.Pause, .Developer}},
		{name = "textures", screens = {.Pause, .Developer, .Textures}},
		{name = "touch layout editor", screens = {.Pause, .Settings, .Touch_Layout}},
		{name = "recipes", screens = {.Recipes}},
		{name = "technologies", screens = {.Technologies}},
		{name = "journal", screens = {.Journal}},
		{name = "journal notes", screens = {.Journal}, tab_next = len(audit.content.quests.chapters) + 1},
		{name = "power", screens = {.Power}},
		{name = "statistics", screens = {.Statistics}},
		{name = "map", screens = {.Map}},
	}
	for touch_case in cases {
		audit_case(audit, {name = fmt.tprintf("%s touch row", touch_case.name), screens = touch_case.screens, hud = touch_case.screens[0] != .Title, tab_next = touch_case.tab_next, keyboard = touch_case.keyboard, system_keyboard = touch_case.system_keyboard, touch = true})
	}
	audit_case(audit, {name = "hud touch", hud = true, touch = true})
	audit_case(audit, {name = "pause, split screen guest", screens = {.Pause}, split_screen_guest = true, walk_focus = true})
	audit_case(audit, {name = "pause, split screen guest joining", screens = {.Pause}, split_screen_guest = true, waiting_for_player = true, walk_focus = true})
	audit_case(audit, {name = "pause, arrival", screens = {.Pause}, arrival_falling = true, walk_focus = true})
	audit_case(audit, {name = "hud, split screen pad lost", hud = true, notice = "viewport_pad_lost"})
	simulation := &audit.simulation
	for &assembler in simulation.world.entities.assemblers.entries {
		if assembler.alive && audit.content.machines.machines[assembler.machine].recipe_choice != .Fixed {
			audit_case(audit, {name = "recipe selection touch row", screens = {.Machine, .Recipes}, hud = true, machine = assembler.handle, selecting = assembler.handle, touch = true})
			break
		}
	}
}

// The Multiplayer screen empty, with three games (the longest texts an
// answer carries, one of another build), and its address under either
// keyboard.
audit_multiplayer :: proc(audit: ^Ui_Audit) {
	audit_case(audit, {name = "multiplayer, no games", screens = {.Title, .Multiplayer}, walk_focus = true})
	multiplayer := &audit.title.multiplayer
	defer clear_lan_games(multiplayer)
	long_text := strings.repeat("W", platform.MAXIMUM_DISCOVERY_TEXT_SIZE, context.temp_allocator)
	for index in 0 ..< 3 {
		answer := platform.Discovery_Message{kind = .Answer, world = long_text, host = long_text, build = long_text, players = platform.MAXIMUM_DISCOVERY_PLAYERS, port = 47_326}
		add_lan_answer(multiplayer, answer, fmt.tprintf("192.168.100.%d", 200 + index), index != 1, {})
	}
	audit_case(audit, {name = "multiplayer, three games", screens = {.Title, .Multiplayer}, walk_focus = true})
	audit_case(audit, {name = "multiplayer, the address under the keyboard", screens = {.Title, .Multiplayer}, keyboard = true, walk_focus = true})
	audit_case(audit, {name = "multiplayer, the address under the system keyboard", screens = {.Title, .Multiplayer}, keyboard = true, system_keyboard = true})
}

UI_AUDIT_TOASTS :: [?]string{"mc_extraction_rights_done", "inventory_full", "developer_applies_on_resume"}

// The HUD with the front craft finished and its outputs waiting for room
// ("Crafting waits: inventory full").
audit_crafting_waits_on_a_full_inventory :: proc(audit: ^Ui_Audit) {
	crafting := &audit.simulation.players[0].crafting
	saved := crafting^
	defer crafting^ = saved
	crafting.started, crafting.waiting = true, true
	audit_case(audit, {name = "hud crafting waits on a full inventory", hud = true})
}

audit_every_case :: proc(audit: ^Ui_Audit) {
	toasts := UI_AUDIT_TOASTS
	audit_case(audit, {name = "title", screens = {.Title}, walk_focus = true})
	audit_case(audit, {name = "new world", screens = {.Title, .New_World}, walk_focus = true})
	audit_case(audit, {name = "on-screen keyboard", screens = {.Title, .New_World}, keyboard = true, walk_focus = true})
	audit_case(audit, {name = "system keyboard", screens = {.Title, .New_World}, keyboard = true, system_keyboard = true})
	audit_case(audit, {name = "load", screens = {.Title, .Load_World}, walk_focus = true})
	audit_case(audit, {name = "confirm delete", screens = {.Title, .Load_World, .Confirm_Delete}, walk_focus = true})
	audit_multiplayer(audit)
	audit_case(audit, {name = "hud", hud = true, toasts = toasts[:]})
	audit_crafting_waits_on_a_full_inventory(audit)
	audit_case(audit, {name = "hud radial", hud = true, radial = true})
	// The placement editor and the tools radial (0215).
	audit_case(audit, {name = "hud tools radial", hud = true, tools_radial = true})
	audit_case(audit, {name = "hud placement outline", hud = true, placement = .Outline})
	audit_case(audit, {name = "hud placement outline refused", hud = true, placement = .Outline, placement_refusal = .Too_Steep})
	audit_case(audit, {name = "hud placement editor", hud = true, placement = .Anchored})
	audit_case(audit, {name = "hud placement editor touch", hud = true, touch = true, placement = .Anchored})
	audit_case(audit, {name = "pause, placement editor", screens = {.Pause}, placement = .Anchored, walk_focus = true})
	audit_case(audit, {name = "hud mission control", hud = true, toasts = toasts[:], mission_control = true})
	// The field's refusals as the HUD toasts them (Field_Refused, 0179).
	field_refusals := make([dynamic]string, context.temp_allocator)
	for key in field_refusal_keys {
		if key != "" {
			append(&field_refusals, key)
		}
	}
	audit_case(audit, {name = "hud field refusals", hud = true, toasts = field_refusals[:]})
	audit_case(audit, {name = "pause", screens = {.Pause}, walk_focus = true})
	for tab in 0 ..< 5 {
		audit_case(audit, {name = fmt.tprintf("settings tab %d", tab), screens = {.Pause, .Settings}, tab_next = tab, walk_focus = true})
	}
	audit_windowed_display(audit)
	audit_desktop_scaled_display(audit)
	audit_case(audit, {name = "developer", screens = {.Pause, .Developer}, walk_focus = true})
	audit_case(audit, {name = "textures", screens = {.Pause, .Developer, .Textures}, walk_focus = true})
	audit_data_browser(audit)
	audit_touch_layout_editor(audit)
	audit_case(audit, {name = "inventory", screens = {.Inventory}, walk_focus = true})
	audit_case(audit, {name = "inventory touch row", screens = {.Inventory}, hud = true, touch = true})
	simulation := &audit.simulation
	for handle in machines_with_panels(&simulation.world, audit.content) {
		machine := audit.content.machines.machines[entity_common(&simulation.world.entities, handle).machine]
		tabs := machine.kind == .Launch_Pad ? 3 : 1
		for tab in 0 ..< tabs {
			name := fmt.tprintf("machine %s tab %d", machine.id, tab)
			audit_case(audit, {name = name, screens = {.Machine}, machine = handle, tab_next = tab, walk_focus = true})
		}
		audit_case(audit, {name = fmt.tprintf("machine %s touch row", machine.id), screens = {.Machine}, machine = handle, hud = true, touch = true})
	}
	audit_waiting_inserter(audit)
	audit_broken_furnace(audit)
	audit_case(audit, {name = "recipes", screens = {.Recipes}, walk_focus = true})
	audit_recipe_ingredient_states(audit)
	for &assembler in simulation.world.entities.assemblers.entries {
		if assembler.alive && audit.content.machines.machines[assembler.machine].recipe_choice != .Fixed {
			audit_case(audit, {name = "recipe selection", screens = {.Machine, .Recipes}, machine = assembler.handle, selecting = assembler.handle, walk_focus = true})
			break
		}
	}
	// The stone cutting table's panel: the browser in the station mode.
	for foundation in simulation.world.entities.foundations.entries {
		if foundation.alive && audit.content.machines.machines[foundation.machine].kind == .Crafting_Station {
			audit_case(audit, {name = "crafting station", screens = {.Machine, .Recipes}, machine = foundation.handle, station = foundation.handle, walk_focus = true})
			audit_case(audit, {name = "crafting station touch row", screens = {.Machine, .Recipes}, hud = true, machine = foundation.handle, station = foundation.handle, touch = true})
			break
		}
	}
	// The pod's crafting bench (0198): the station mode with the hand maker.
	for foundation in simulation.world.entities.foundations.entries {
		if foundation.alive && audit.content.machines.machines[foundation.machine].kind == .Crafting_Bench {
			audit_case(audit, {name = "crafting bench", screens = {.Machine, .Recipes}, machine = foundation.handle, station = foundation.handle, walk_focus = true})
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
	audit_touch_rows(audit)
	// Last, since it changes the hotbar: a selected magnetometer shows its
	// dial and the Use_Item hint.
	player := &simulation.players[0]
	inventory_hotbar(player.inventory)[player.selected_hotbar_slot] = Item_Stack{test_item(audit.content.items, "magnetometer"), 1}
	player.magnetometer.found = true
	audit_case(audit, {name = "hud magnetometer", hud = true, toasts = toasts[:]})
	// The world's glyph bar with a machine held on the field and with
	// nothing held, beside or above the hotbar (0219).
	inventory_hotbar(player.inventory)[player.selected_hotbar_slot] = Item_Stack{test_item(audit.content.items, "stone_furnace"), 1}
	audit_case(audit, {name = "hud field furnace held", hud = true, field_session = true})
	inventory_hotbar(player.inventory)[player.selected_hotbar_slot] = EMPTY_STACK
	audit_case(audit, {name = "hud field nothing held", hud = true, field_session = true})
	// The configure pop-up of a foundation over the inventory (0202),
	// checked at every size down to the smallest, and the inventory's
	// touch row with Configure in Sort's place.
	with_audit_foundation_blocks(audit)
	foundation := audit.content.machines.machines[audit.content.field.pad_foundation].item
	inventory_hotbar(player.inventory)[player.selected_hotbar_slot] = Item_Stack{foundation, 1}
	audit_case(audit, {name = "configure foundation block", screens = {.Inventory, .Configure}, configure_item = foundation, walk_focus = true})
	audit_case(audit, {name = "configure foundation block touch row", screens = {.Inventory, .Configure}, configure_item = foundation, hud = true, touch = true})
	audit_case(audit, {name = "inventory foundation touch row", screens = {.Inventory}, hud = true, touch = true})
}

@(test)
test_every_screen_stays_inside_the_screen :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	audit_every_case(audit)
	testing.expectf(t, audit.failures == 0, "%d UI bounds problems", audit.failures)
}

// The screens of work item 0094 with the shipped content: the strip on
// the three screens and none on the recipe picker, the pause menu without
// Recipes and Research, and the inventory and a machine panel opening on
// the selected hotbar slot.
@(test)
test_inventory_strip_pause_menu_and_initial_focus :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	for screen, index in inventory_tab_screens {
		state := Ui_State{theme = audit.theme}
		push_screen(&state.screens, screen)
		screen_test_frame(audit, &state, {tab_next = true})
		next := inventory_tab_screens[(index + 1) % len(inventory_tab_screens)]
		testing.expect_value(t, top_screen(state.screens), next)
		testing.expect_value(t, state.screens.count, 1)
		destroy_ui_state(&state)
	}
	// The picker: no strip, and the bumpers change neither the screen nor
	// the category.
	simulation := &audit.simulation
	for &assembler in simulation.world.entities.assemblers.entries {
		if !assembler.alive || audit.content.machines.machines[assembler.machine].recipe_choice == .Fixed {
			continue
		}
		state := Ui_State{theme = audit.theme}
		push_screen(&state.screens, .Machine)
		push_screen(&state.screens, .Recipes)
		audit.views.recipe_browser.selecting_for = assembler.handle
		simulation.players[0].open_machine = assembler.handle
		category := audit.views.recipe_browser.filter.category
		screen_test_frame(audit, &state, {tab_next = true})
		testing.expect_value(t, top_screen(state.screens), Screen.Recipes)
		testing.expect_value(t, state.screens.count, 2)
		testing.expect_value(t, audit.views.recipe_browser.filter.category, category)
		testing.expect(t, !draw_list_has_text(state.draw_list[:], text("inventory_tab_technologies")))
		destroy_ui_state(&state)
		break
	}
	pause := Ui_State{theme = audit.theme}
	push_screen(&pause.screens, .Pause)
	screen_test_frame(audit, &pause, {})
	testing.expect(t, draw_list_has_text(pause.draw_list[:], text("pause_journal")))
	testing.expect(t, !draw_list_has_text(pause.draw_list[:], text("inventory_tab_recipes")))
	testing.expect(t, !draw_list_has_text(pause.draw_list[:], text("inventory_tab_technologies")))
	destroy_ui_state(&pause)
	player := &simulation.players[0]
	player.selected_hotbar_slot = 3
	inventory := Ui_State{theme = audit.theme, focus = 12345}
	// A focus kept from an earlier screen goes on a frame in the world.
	screen_test_frame(audit, &inventory, {})
	push_screen(&inventory.screens, .Inventory)
	screen_test_frame(audit, &inventory, {})
	testing.expect_value(t, inventory.focus, ui_hash(ui_hash(ui_hash(0, "inventory", -1), "hotbar", -1), "slot", 3))
	destroy_ui_state(&inventory)
	machine := Ui_State{theme = audit.theme}
	handle := machines_with_panels(&simulation.world, audit.content)[0]
	push_screen(&machine.screens, .Machine)
	simulation.players[0].open_machine = handle
	screen_test_frame(audit, &machine, {})
	testing.expect_value(t, machine.focus, ui_hash(ui_hash(ui_hash(0, "machine", -1), "hotbar", -1), "slot", 3))
	destroy_ui_state(&machine)
}

// Work item 0138: the HUD draws a box per run with its crafts in the
// corner, and says what the front run waits for.
@(test)
test_hud_draws_craft_runs_and_the_wait :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	crafting := &audit.simulation.players[0].crafting
	crafting.waiting_for = test_item(audit.content.items, "log")
	queue := crafting^
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	ui_begin(&state, {}, {1920, 1080}, 1.0 / 60, 1, 1, ui_accessibility(audit.settings))
	draw_hud(&state, audit_screen_context(audit), audit_hud_context(audit))
	ui_resolve(&state)
	for run in queue.runs[1:queue.count] {
		testing.expectf(t, draw_list_has_text(state.draw_list[:], fmt.tprint(run.count)), "no count %d", run.count)
	}
	testing.expect(t, draw_list_has_text(state.draw_list[:], "Waiting for Log"))
}

// A full queue of 64 runs, waiting for an ingredient and waiting on a full
// inventory, keeps its boxes, the bar and the waiting lines inside the
// safe area at every audited size, the narrowest included (0138).
@(test)
test_a_full_craft_queue_stays_inside_the_safe_area :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	player := &audit.simulation.players[0]
	full := audit_craft_queue(audit.content.recipes, longest_named_item(audit.content.items), HAND_CRAFT_QUEUE_RUNS)
	testing.expect_value(t, full.count, HAND_CRAFT_QUEUE_RUNS)
	queues := [2]Craft_Queue{full, full}
	queues[1].started, queues[1].waiting = true, true
	audit_sizes := UI_AUDIT_SIZES
	sizes := make([dynamic]Ui_Audit_Size, context.temp_allocator)
	append(&sizes, ..audit_sizes[:])
	append(&sizes, UI_AUDIT_DECK_SIZE)
	for queue in queues {
		for size in sizes {
			for text_scale in UI_AUDIT_TEXT_SCALES {
				player.crafting = queue
				audit.settings.text_scale = text_scale
				state := Ui_State{theme = audit.theme}
				ui_begin(&state, {}, size.pixels, 1.0 / 60, size.scale, 1, ui_accessibility(audit.settings))
				draw_craft_queue(&state, player^, audit_screen_context(audit))
				ui_resolve(&state)
				safe := ui_safe_area(&state)
				for command in state.draw_list {
					testing.expectf(t, rectangle_inside(command.rectangle, safe, UI_AUDIT_TOLERANCE), "%v scale %.1f text %.1f: %v %q at %v outside %v", size.pixels, size.scale, text_scale, command.kind, command.text, command.rectangle, safe)
				}
				destroy_ui_state(&state)
			}
		}
	}
}

draw_list_has_text :: proc(commands: []Draw_Command, wanted: string) -> bool {
	for command in commands {
		if command.kind == .Text && command.text == wanted {
			return true
		}
	}
	return false
}

// One frame of the screens over the audit's site, without the bounds
// check: the draw list's texts stay valid after it.
screen_test_frame :: proc(audit: ^Ui_Audit, state: ^Ui_State, input: Ui_Input) {
	ui_begin(state, input, {1920, 1080}, 1.0 / 60, 1, 1, ui_accessibility(audit.settings))
	run_screens(state, audit_screen_context(audit))
	ui_resolve(state)
}

// A screen frame and the start of the next tick, which applies what the
// frame queued (the slot commands, 0179).
slot_test_frame :: proc(audit: ^Ui_Audit, state: ^Ui_State, input: Ui_Input) {
	screen_test_frame(audit, state, input)
	apply_player_commands(&audit.simulation, audit.content)
}

// Work item 0090: in the inventory screen R2 moves the focused hotbar
// stack into the backpack and the right stick click drops it, without a
// Drop button.
@(test)
test_inventory_screen_quick_move_and_drop :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	player := &audit.simulation.players[0]
	coal := test_item(audit.content.items, "coal")
	stone := test_item(audit.content.items, "stone")
	for &slot in player.inventory.slots {
		slot = EMPTY_STACK
	}
	player.held = EMPTY_HELD_STACK
	player.selected_hotbar_slot = 3
	player.inventory.slots[3] = {coal, 5}
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Inventory)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {quick_move = true})
	// The move waits for the tick (0179).
	testing.expect_value(t, player.inventory.slots[3], Item_Stack{coal, 5})
	apply_player_commands(&audit.simulation, audit.content)
	testing.expect_value(t, player.held, EMPTY_HELD_STACK)
	testing.expect_value(t, player.inventory.slots[3], EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], Item_Stack{coal, 5})
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
	player.inventory.slots[3] = {stone, 2}
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("hint_drop")))
	slot_test_frame(audit, &state, {drop = true})
	testing.expect_value(t, player.inventory.slots[3], EMPTY_STACK)
}

// The burner mining drill focused over nine iron plates and an empty
// queue (0156): its plates held, its gears craftable from them, its stone
// furnace missing. Returns what restore_recipe_ingredient_states puts back.
set_recipe_ingredient_states :: proc(audit: ^Ui_Audit) -> (slots: []Item_Stack, queue: Craft_Queue, browser: Recipe_Browser) {
	player := &audit.simulation.players[0]
	slots, queue, browser = slice.clone(player.inventory.slots, context.temp_allocator), player.crafting, audit.views.recipe_browser
	slice.fill(player.inventory.slots, EMPTY_STACK)
	inventory_add(player.inventory, audit.content.items, test_item(audit.content.items, "iron_plate"), 9)
	player.crafting = make_craft_queue()
	audit.views.recipe_browser.filter = {category = .Machines, available_only = true}
	audit.views.recipe_browser.focused_recipe = test_recipe(audit.content.recipes, "burner_mining_drill")
	return slots, queue, browser
}

restore_recipe_ingredient_states :: proc(audit: ^Ui_Audit, slots: []Item_Stack, queue: Craft_Queue, browser: Recipe_Browser) {
	player := &audit.simulation.players[0]
	copy(player.inventory.slots, slots)
	player.crafting = queue
	audit.views.recipe_browser.filter, audit.views.recipe_browser.focused_recipe = browser.filter, browser.focused_recipe
}

audit_recipe_ingredient_states :: proc(audit: ^Ui_Audit) {
	slots, queue, browser := set_recipe_ingredient_states(audit)
	defer restore_recipe_ingredient_states(audit, slots, queue, browser)
	audit_case(audit, {name = "recipes, ingredients held, craftable and missing", screens = {.Recipes}})
}

// The colour of the first text command reading wanted.
draw_list_text_color :: proc(commands: []Draw_Command, wanted: string) -> (color: Ui_Color, found: bool) {
	for command in commands {
		if command.kind == .Text && command.text == wanted {
			return command.color, true
		}
	}
	return {}, false
}

// Work item 0156: the detail paints each ingredient by how the queue gets
// it and counts the crafts the planner makes.
@(test)
test_recipe_detail_shows_how_the_queue_gets_each_ingredient :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	slots, queue, browser := set_recipe_ingredient_states(audit)
	defer restore_recipe_ingredient_states(audit, slots, queue, browser)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Recipes)
	screen_test_frame(audit, &state, {})
	items := audit.content.items
	Expected_Row :: struct {
		line:  string,
		color: Ui_Theme_Color,
	}
	// The plates read the three the gears leave, not the nine held.
	rows := [?]Expected_Row {
		{"0 / 3 Iron gear, craftable", .Text_Dim},
		{"3 / 3 Iron plate", .Accent},
		{"0 / 1 Stone furnace", .Danger},
	}
	testing.expect_value(t, inventory_count(audit.simulation.players[0].inventory, test_item(items, "iron_plate")), 9)
	testing.expect(t, !draw_list_has_text(state.draw_list[:], "9 / 3 Iron plate"))
	for row in rows {
		line := row.line
		color, found := draw_list_text_color(state.draw_list[:], line)
		testing.expectf(t, found, "no row %q", line)
		testing.expectf(t, color == theme_color(&state, row.color), "%q in %v", line, color)
	}
	testing.expect(t, draw_list_has_text(state.draw_list[:], can_craft_text(0)))
}

// Work item 0091: a focused unlocked recipe's ingredients read have and
// need, and the filter column offers the unlocked only toggle.
@(test)
test_recipe_screen_shows_have_and_need :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	player := &audit.simulation.players[0]
	plank := test_recipe(audit.content.recipes, "plank")
	log_item := test_item(audit.content.items, "log")
	audit.views.recipe_browser.focused_recipe = plank
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Recipes)
	screen_test_frame(audit, &state, {})
	planned := planned_crafts(player.crafting, player.inventory, audit.content.recipes, audit.simulation.unlocks, plank, HAND_MAKERS, context.temp_allocator)
	line := ingredient_line(1, item_name(audit.content.items, log_item), planned.inputs[0])
	testing.expectf(t, draw_list_has_text(state.draw_list[:], line), "no row %q", line)
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("recipes_unlocked_only")))
	testing.expect(t, draw_list_has_text(state.draw_list[:], can_craft_text(planned.count)))
	// 0138: the product line with the count held, the queue summary.
	product := audit.content.recipes.recipes[plank].outputs[0]
	held_line := product_held_line(product, inventory_count(player.inventory, product.item), audit.content.items)
	testing.expectf(t, draw_list_has_text(state.draw_list[:], held_line), "no row %q", held_line)
	testing.expect(t, draw_list_has_text(state.draw_list[:], queue_summary_text(player.crafting)))
}

// The audit's content as a field session's for the foundation block
// widget (0193): its foundation and the shipped lists of data/game.sjson.
with_audit_foundation_blocks :: proc(audit: ^Ui_Audit) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	assert(error == nil)
	audit.content.field.pad_foundation = find_foundation_machine(audit.content.machines)
	audit.content.field.foundation_sizes = config.foundation_sizes
	audit.content.field.foundation_heights = config.foundation_heights
}

// The draw list's text's centre in pixels, for a click on it.
draw_list_text_pixels :: proc(state: ^Ui_State, wanted: string) -> (pixels: [2]f32, found: bool) {
	for command in state.draw_list {
		if command.kind == .Text && command.text == wanted {
			return rectangle_centre(command.rectangle) * state.pixels_per_unit, true
		}
	}
	return {}, false
}

// An inventory view over the audit's site for the configure pop-up
// (0202): a field session's foundation lists, an empty hand, a
// foundation in the selected hotbar slot and a furnace beside it. The
// view's first frames settle the focus on the selected slot.
Configure_Test :: struct {
	foundation: Item_Id,
	furnace:    Item_Id,
}

make_configure_test :: proc(audit: ^Ui_Audit, state: ^Ui_State) -> Configure_Test {
	with_audit_foundation_blocks(audit)
	player := &audit.simulation.players[0]
	player.held = EMPTY_HELD_STACK
	test := Configure_Test {
		foundation = audit.content.machines.machines[audit.content.field.pad_foundation].item,
		furnace    = audit.content.machines.machines[test_machine(audit.content.machines, "stone_furnace")].item,
	}
	hotbar := inventory_hotbar(player.inventory)
	player.selected_hotbar_slot = 0
	hotbar[0] = Item_Stack{test.foundation, 10}
	hotbar[1] = Item_Stack{test.furnace, 1}
	state.theme = audit.theme
	push_screen(&state.screens, .Inventory)
	screen_test_frame(audit, state, {})
	screen_test_frame(audit, state, {})
	return test
}

last_queued_command :: proc(audit: ^Ui_Audit) -> Player_Command {
	commands := audit.simulation.player_commands
	return len(commands) > 0 ? commands[len(commands) - 1].command : nil
}

// With a foundation highlighted the hint reads Configure and the
// context action opens the pop-up instead of sorting; with a furnace
// highlighted it reads Sort and sorts. The 0193 rows are gone from the
// view.
@(test)
test_the_context_action_configures_a_foundation :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	test := make_configure_test(audit, &state)
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("hint_configure")))
	testing.expect(t, !draw_list_has_text(state.draw_list[:], text("hint_sort")))
	testing.expect(t, !draw_list_has_text(state.draw_list[:], text("inventory_foundation_size")))
	testing.expect(t, !draw_list_has_text(state.draw_list[:], "10x10"))
	clear(&audit.simulation.player_commands)
	screen_test_frame(audit, &state, {context_action = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Configure)
	testing.expect_value(t, state.configure.item, test.foundation)
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	// The furnace: Sort, and the press sorts.
	pop_screen(&state.screens)
	state.configure, state.focus = {}, 0
	audit.simulation.players[0].selected_hotbar_slot = 1
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("hint_sort")))
	testing.expect(t, !draw_list_has_text(state.draw_list[:], text("hint_configure")))
	screen_test_frame(audit, &state, {context_action = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
	_, sorts := last_queued_command(audit).(Slot_Sort_Command)
	testing.expect(t, sorts)
}

// The pop-up: titled after the item with both strips; a click on 5x5,
// a step and Confirm on the focused strips each queue the command with
// the picked indices; Back closes it onto the view with the focus where
// it was.
@(test)
test_the_configure_popup_picks_the_foundation_block :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	make_configure_test(audit, &state)
	focus_before := state.focus
	screen_test_frame(audit, &state, {context_action = true})
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("configure_title_foundation_block")))
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("inventory_foundation_size")))
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("hint_pick")))
	testing.expect(t, !draw_list_has_text(state.draw_list[:], text("inventory_hotbar")))
	pixels, found := draw_list_text_pixels(&state, "5x5")
	testing.expect(t, found)
	screen_test_frame(audit, &state, {mouse_position = pixels, mouse_moved = true, mouse_pressed = true, mouse_down = true})
	testing.expect_value(t, last_queued_command(audit).(Foundation_Block_Command), Foundation_Block_Command{size_index = 2, height_index = 0})
	apply_player_commands(&audit.simulation, audit.content)
	testing.expect_value(t, audit.simulation.players[0].field.foundation_size_index, 2)
	screen_test_frame(audit, &state, {mouse_position = pixels})
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	// The gamepad: the size strip holds the focus first; right steps it,
	// down reaches the height strip, Confirm steps that.
	state.focus = 0
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {navigation = .Right})
	testing.expect_value(t, last_queued_command(audit).(Foundation_Block_Command), Foundation_Block_Command{size_index = 3, height_index = 0})
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {navigation = .Down})
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect_value(t, last_queued_command(audit).(Foundation_Block_Command), Foundation_Block_Command{size_index = 3, height_index = 1})
	testing.expect_value(t, top_screen(state.screens), Screen.Configure)
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("hint_pick")))
	// Down to Close: Confirm reads Close there.
	screen_test_frame(audit, &state, {navigation = .Down})
	screen_test_frame(audit, &state, {})
	testing.expect(t, !draw_list_has_text(state.draw_list[:], text("hint_pick")))
	// Back closes it; the view focuses the slot that opened it.
	screen_test_frame(audit, &state, {back = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, state.focus, focus_before)
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("hint_configure")))
	// Only once: after a tab step to Recipes and back the view focuses the
	// selected hotbar slot, not the slot that opened the pop-up.
	audit.simulation.players[0].selected_hotbar_slot = 1
	screen_test_frame(audit, &state, {tab_next = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Recipes)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {tab_previous = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, state.focus, inventory_hotbar_slot_test_id(1))
}

// The id the inventory view gives a hotbar slot (selected_hotbar_slot_id
// inside the "inventory" panel).
inventory_hotbar_slot_test_id :: proc(slot: int) -> Ui_Id {
	return ui_hash(ui_hash(ui_hash(0, "inventory", -1), "hotbar", -1), "slot", slot)
}

// Touch: with the tapped slot on a foundation the row's Configure takes
// Sort's place and opens the pop-up; a tap off the panel closes it.
@(test)
test_the_touch_row_configures_a_foundation :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	make_configure_test(audit, &state)
	screen_test_frame(audit, &state, {pointer_is_touch = true})
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("touch_button_configure")))
	testing.expect(t, !draw_list_has_text(state.draw_list[:], text("slot_button_sort")))
	pixels, found := draw_list_text_pixels(&state, text("touch_button_configure"))
	testing.expect(t, found)
	screen_test_frame(audit, &state, {pointer_is_touch = true, mouse_position = pixels, mouse_moved = true, mouse_pressed = true, mouse_down = true})
	screen_test_frame(audit, &state, {pointer_is_touch = true, mouse_position = pixels})
	testing.expect_value(t, top_screen(state.screens), Screen.Configure)
	tap_screen_at(audit, &state, {40, 400})
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
}


// The glyph the glyph bar draws beside a hint's label: the icon pushed
// right after the label's text, and the key cap's text after it.
glyph_beside_label :: proc(commands: []Draw_Command, label: string) -> (shown: Glyph, found: bool) {
	for command, index in commands {
		if command.kind != .Text || command.text != label || command.panel != UI_GLYPH_BAR_PANEL || index + 1 >= len(commands) {
			continue
		}
		icon := commands[index + 1]
		if icon.kind != .Ui_Icon {
			continue
		}
		shown.icon = Ui_Icon(icon.tile)
		if shown.icon == .Key && index + 2 < len(commands) {
			shown.label = commands[index + 2].text
		}
		return shown, true
	}
	return {}, false
}

// Work item 0194: the hint beside a machine with a panel (the audit's
// HUD case aims at a drill) shows the inventory binding's glyph with
// Open; beside a power switch Interact turns it. With the keyboard the
// inventory binding (E) also opens the switch, so Open shows beside Turn;
// on the gamepad Interact and Inventory share X and the press is
// Interact's there, so Turn shows alone (0233).
@(test)
test_the_hint_beside_a_machine_shows_the_inventory_glyph :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	player := &audit.simulation.players[0]
	switch_handle := NO_ENTITY
	for pole in audit.simulation.world.entities.poles.entries {
		if pole.alive && entity_is_power_switch(&audit.simulation.world.entities, audit.content.machines, pole.handle) {
			switch_handle = pole.handle
		}
	}
	testing.expect(t, switch_handle != NO_ENTITY, "the audit's site has a power switch")
	drill := player.target
	for device in ([2]Input_Device{.Keyboard_Mouse, .Gamepad}) {
		for target in ([2]Entity_Handle{drill.entity, switch_handle}) {
			player.target = Raycast_Hit{hit = true, entity = target}
			state := Ui_State{theme = audit.theme, active_device = device, bindings = shipped_default_bindings(t)}
			ui_begin(&state, {}, {1920, 1080}, 1.0 / 60, 1, 1, ui_accessibility(audit.settings))
			state.active_device = device
			draw_hud(&state, audit_screen_context(audit), audit_hud_context(audit))
			ui_resolve(&state)
			is_switch := target == switch_handle
			shared := glyph(&state, .Interact) == glyph(&state, .Inventory)
			testing.expectf(t, shared == (device == .Gamepad), "%v: Interact and Inventory share a glyph %v", device, shared)
			open, found := glyph_beside_label(state.draw_list[:], text("hint_open"))
			open_shown := !(is_switch && shared)
			testing.expectf(t, found == open_shown, "%v %v: Open shown %v", device, target.kind, found)
			if open_shown {
				testing.expectf(t, open == glyph(&state, .Inventory), "%v %v: Open beside %v, wanted %v", device, target.kind, open, glyph(&state, .Inventory))
			}
			turn, turn_found := glyph_beside_label(state.draw_list[:], text("hint_toggle"))
			testing.expectf(t, turn_found == is_switch, "%v %v: Turn shown %v", device, target.kind, turn_found)
			if is_switch {
				testing.expect_value(t, turn, glyph(&state, .Interact))
			}
			destroy_ui_state(&state)
		}
	}
	// The switch's Turn and Open fit the glyph bar at every audited size and
	// text scale, the smallest included, with the keyboard, where both show.
	// Pause is not asserted: the world's bar sheds it first (0219). Then
	// one gamepad pass at 1280 by 800 scale 1.5 with the largest text, the
	// tightest bar, shows Turn alone.
	player.target = Raycast_Hit{hit = true, entity = switch_handle}
	text_scale_before := audit.settings.text_scale
	audit_sizes := UI_AUDIT_SIZES
	sizes := make([dynamic]Ui_Audit_Size, context.temp_allocator)
	append(&sizes, ..audit_sizes[:])
	append(&sizes, UI_AUDIT_DECK_SIZE)
	for size in sizes {
		for text_scale in UI_AUDIT_TEXT_SCALES {
			audit.settings.text_scale = text_scale
			state := Ui_State{theme = audit.theme, active_device = .Keyboard_Mouse, bindings = shipped_default_bindings(t)}
			ui_begin(&state, {}, size.pixels, 1.0 / 60, size.scale, 1, ui_accessibility(audit.settings))
			state.active_device = .Keyboard_Mouse
			draw_hud(&state, audit_screen_context(audit), audit_hud_context(audit))
			ui_resolve(&state)
			for label in ([2]string{text("hint_toggle"), text("hint_open")}) {
				_, found := glyph_beside_label(state.draw_list[:], label)
				testing.expectf(t, found, "%v scale %.1f text %.1f: %q missing", size.pixels, size.scale, text_scale, label)
			}
			safe := ui_safe_area(&state)
			for command in state.draw_list {
				if command.panel == UI_GLYPH_BAR_PANEL {
					testing.expectf(t, rectangle_inside(command.rectangle, safe, UI_AUDIT_TOLERANCE), "%v scale %.1f text %.1f: %v %q outside %v", size.pixels, size.scale, text_scale, command.kind, command.text, safe)
				}
			}
			destroy_ui_state(&state)
		}
	}
	audit.settings.text_scale = TEXT_SCALE_RANGE.maximum
	state := Ui_State{theme = audit.theme, active_device = .Gamepad, bindings = shipped_default_bindings(t)}
	ui_begin(&state, {}, {1280, 800}, 1.0 / 60, 1.5, 1, ui_accessibility(audit.settings))
	state.active_device = .Gamepad
	draw_hud(&state, audit_screen_context(audit), audit_hud_context(audit))
	ui_resolve(&state)
	_, turn_found := glyph_beside_label(state.draw_list[:], text("hint_toggle"))
	_, open_found := glyph_beside_label(state.draw_list[:], text("hint_open"))
	testing.expect(t, turn_found, "the gamepad's Turn at the tightest size")
	testing.expect(t, !open_found, "the gamepad's Open beside Turn")
	safe := ui_safe_area(&state)
	for command in state.draw_list {
		if command.panel == UI_GLYPH_BAR_PANEL {
			testing.expectf(t, rectangle_inside(command.rectangle, safe, UI_AUDIT_TOLERANCE), "gamepad: %v %q outside %v", command.kind, command.text, safe)
		}
	}
	destroy_ui_state(&state)
	audit.settings.text_scale = text_scale_before
	player.target = drill
}

// The bars the glyph bar tests draw (0219): the placement editor's four,
// the world's with the stone furnace held on the field, and the world's
// with nothing held and no target.
Glyph_Bar_Test_Bar :: enum u8 {
	Editor,
	Furnace_Held,
	Nothing_Held,
}

// The audit's player set up for the bar: no target and standing still,
// the selected slot holding the furnace or nothing.
set_glyph_bar_test_player :: proc(audit: ^Ui_Audit, bar: Glyph_Bar_Test_Bar) {
	player := &audit.simulation.players[0]
	player.target = Raycast_Hit{entity = NO_ENTITY}
	player.velocity = {}
	stack := bar == .Furnace_Held ? Item_Stack{test_item(audit.content.items, "stone_furnace"), 1} : EMPTY_STACK
	inventory_hotbar(player.inventory)[player.selected_hotbar_slot] = stack
}

// One HUD frame of the bar at the size with the shipped bindings, as
// audit_frame draws it. The caller destroys the state.
glyph_bar_test_frame :: proc(t: ^testing.T, audit: ^Ui_Audit, bar: Glyph_Bar_Test_Bar, size: Ui_Audit_Size, device: Input_Device) -> Ui_State {
	state := Ui_State{theme = audit.theme, active_device = device, bindings = shipped_default_bindings(t)}
	ui_begin(&state, {}, size.pixels, 1.0 / 60, size.scale, 1, ui_accessibility(audit.settings))
	state.active_device = device
	screen_context := audit_screen_context(audit)
	hud := audit_hud_context(audit)
	if bar == .Editor {
		furnace, _ := find_machine_id(audit.content.machines, "stone_furnace")
		hud.placement = Placement_Editor_Hud{mode = .Anchored, machine = furnace}
		audit.placement_editor = Placement_Editor{on = true, anchored = true, machine = furnace}
		screen_context.placement_editor = &audit.placement_editor
	} else {
		audit_field_session_hud(audit, &hud)
	}
	draw_hud(&state, screen_context, hud)
	ui_resolve(&state)
	return state
}

// Work item 0219: on the field with the stone furnace held the world's
// glyph bar names Place, Tools and Turn with the keyboard's Right mouse,
// Q and R and the pad's L2, D-pad Up and Y; with nothing held only
// Inventory and Pause; a foundation held has no Turn.
@(test)
test_the_worlds_hints_name_the_held_machines_controls :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	set_glyph_bar_test_player(audit, .Furnace_Held)
	hud := audit_hud_context(audit)
	audit_field_session_hud(audit, &hud)
	hints, kept := world_glyph_hints(audit_screen_context(audit), hud)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Use_Item, .Tools, .Rotate, .Inventory, .Pause}), "Place, Tools, Turn, Inventory, Pause")
	testing.expect_value(t, kept, 3)
	expected := [Input_Device][3]Glyph {
		.Keyboard_Mouse = {{.Key, "Right mouse"}, {.Key, "Q"}, {.Key, "R"}},
		.Gamepad        = {{.Trigger_Left, ""}, {.Dpad, ""}, {.Button_North, ""}},
	}
	for device in Input_Device {
		state := glyph_bar_test_frame(t, audit, .Furnace_Held, UI_AUDIT_SIZES[0], device)
		for label, index in ([3]string{text("hint_place"), text("hint_tools"), text("hint_turn")}) {
			shown, found := glyph_beside_label(state.draw_list[:], label)
			testing.expectf(t, found && shown == expected[device][index], "%v %q: %v", device, label, shown)
		}
		destroy_ui_state(&state)
	}
	set_glyph_bar_test_player(audit, .Nothing_Held)
	audit_field_session_hud(audit, &hud)
	hints, kept = world_glyph_hints(audit_screen_context(audit), hud)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Inventory, .Pause}), "Inventory, Pause")
	testing.expect_value(t, kept, 0)
	player := &audit.simulation.players[0]
	foundation := audit.content.machines.machines[find_foundation_machine(audit.content.machines)].item
	inventory_hotbar(player.inventory)[player.selected_hotbar_slot] = Item_Stack{foundation, 1}
	audit_field_session_hud(audit, &hud)
	hints, kept = world_glyph_hints(audit_screen_context(audit), hud)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Use_Item, .Tools, .Inventory, .Pause}), "Place, Tools, Inventory, Pause")
	testing.expect_value(t, kept, 2)
}

// Where one frame's glyph bar stands: its distinct row tops and its
// extent, from the commands of UI_GLYPH_BAR_PANEL.
Glyph_Bar_Extent :: struct {
	rows:   int,
	top:    f32,
	bottom: f32,
	left:   f32,
}

glyph_bar_extent :: proc(commands: []Draw_Command) -> Glyph_Bar_Extent {
	extent := Glyph_Bar_Extent{top = math.F32_MAX, left = math.F32_MAX}
	tops := make([dynamic]f32, context.temp_allocator)
	for command in commands {
		if command.panel != UI_GLYPH_BAR_PANEL {
			continue
		}
		if !slice.contains(tops[:], command.rectangle.y) {
			append(&tops, command.rectangle.y)
		}
		extent.top, extent.bottom = min(extent.top, command.rectangle.y), max(extent.bottom, command.rectangle.y + command.rectangle.height)
		extent.left = min(extent.left, command.rectangle.x)
	}
	extent.rows = len(tops)
	return extent
}

// The bar's commands lie in the safe area and clear of every hotbar slot,
// all eight of which are found in the draw list.
expect_glyph_bar_clear_of_hotbar :: proc(t: ^testing.T, state: ^Ui_State, selected: int, case_text: string) {
	safe := ui_safe_area(state)
	slots := hotbar_slot_boxes_in_draw_list(state.draw_list[:], hud_hotbar_rectangles(safe, selected))
	testing.expectf(t, len(slots) == HOTBAR_SLOT_COUNT, "%s: %d slots found", case_text, len(slots))
	for command in state.draw_list {
		if command.panel != UI_GLYPH_BAR_PANEL {
			continue
		}
		testing.expectf(t, rectangle_inside(command.rectangle, safe, UI_AUDIT_TOLERANCE), "%s: %v %q outside the safe area", case_text, command.kind, command.text)
		for box in slots {
			_, overlaps := rectangle_intersection(inset(command.rectangle, UI_AUDIT_TOLERANCE), box)
			testing.expectf(t, !overlaps, "%s: %v %q over a hotbar slot", case_text, command.kind, command.text)
		}
	}
}

expect_glyph_labels :: proc(t: ^testing.T, commands: []Draw_Command, labels: []string, case_text: string) {
	for label in labels {
		_, found := glyph_beside_label(commands, label)
		testing.expectf(t, found, "%s: %q missing", case_text, label)
	}
}

// Work item 0219: the HUD's glyph bar never covers a hotbar slot and
// stays in the safe area at every audited size, text scale and device.
// The held furnace's Place, Tools and Turn and the editor's four show at
// every size. Above the hotbar the world's bars never rise into the
// target lines' band (hud_glyph_bar_above_rows); the editor's bar may
// (decision 6), and at 1280 by 800 scale 1.5 with the largest text it
// wraps into two rows above the hotbar. At 1920 by 1080 the nothing held
// bar stands beside the hotbar, right of its last slot.
@(test)
test_the_glyph_bar_never_covers_the_hotbar :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	player := &audit.simulation.players[0]
	audit_sizes := UI_AUDIT_SIZES
	sizes := make([dynamic]Ui_Audit_Size, context.temp_allocator)
	append(&sizes, ..audit_sizes[:])
	append(&sizes, UI_AUDIT_DECK_SIZE)
	editor_labels := [4]string{text("hint_placement_nudge"), text("hint_placement_rotate"), text("hint_placement_commit"), text("hint_placement_cancel")}
	held_labels := [3]string{text("hint_place"), text("hint_tools"), text("hint_turn")}
	text_scale_before := audit.settings.text_scale
	defer audit.settings.text_scale = text_scale_before
	for bar in Glyph_Bar_Test_Bar {
		set_glyph_bar_test_player(audit, bar)
		for size in sizes {
			for text_scale in UI_AUDIT_TEXT_SCALES {
				audit.settings.text_scale = text_scale
				for device in Input_Device {
					state := glyph_bar_test_frame(t, audit, bar, size, device)
					defer destroy_ui_state(&state)
					case_text := fmt.tprintf("%v %v scale %.1f text %.1f %v", bar, size.pixels, size.scale, text_scale, device)
					expect_glyph_bar_clear_of_hotbar(t, &state, player.selected_hotbar_slot, case_text)
					safe := ui_safe_area(&state)
					hotbar := hud_hotbar_rectangles(safe, player.selected_hotbar_slot)
					extent := glyph_bar_extent(state.draw_list[:])
					above := extent.bottom <= hotbar[player.selected_hotbar_slot].y + UI_AUDIT_TOLERANCE
					above_rows := hud_glyph_bar_above_rows(state.screen_units, hud_glyph_bar_above_bottom(safe))
					band_bottom := hud_target_line_top(state.screen_units, HUD_TARGET_LINE_COUNT)
					if above && bar != .Editor {
						testing.expectf(t, extent.rows <= above_rows, "%s: %d rows above, %d allowed", case_text, extent.rows, above_rows)
						testing.expectf(t, extent.rows == 1 || extent.top >= band_bottom - UI_AUDIT_TOLERANCE, "%s: the bar reaches %v over the target lines' %v", case_text, extent.top, band_bottom)
					}
					switch bar {
					case .Editor:
						expect_glyph_labels(t, state.draw_list[:], editor_labels[:], case_text)
					case .Furnace_Held:
						expect_glyph_labels(t, state.draw_list[:], held_labels[:], case_text)
					case .Nothing_Held:
					}
					smallest := size == Ui_Audit_Size{{1280, 800}, 1.5} && text_scale == TEXT_SCALE_RANGE.maximum
					if bar == .Editor && smallest && device == .Keyboard_Mouse {
						testing.expectf(t, above && extent.rows == 2, "%s: above %v in %d rows", case_text, above, extent.rows)
					}
					if bar == .Nothing_Held && size == UI_AUDIT_SIZES[0] && text_scale == 1 && device == .Gamepad {
						last := hotbar[HOTBAR_SLOT_COUNT - 1]
						testing.expectf(t, extent.left >= last.x + last.width + 3 * UI_GAP - UI_AUDIT_TOLERANCE, "%s: the bar starts at %v", case_text, extent.left)
					}
				}
			}
		}
	}
}
