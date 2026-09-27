package game

import "core:fmt"
import "core:strings"

// The quest journal (J, or the pause menu) and the HUD's active objective.
// The journal shows one chapter per tab: its quests on the left (active,
// then done, then locked ones as silhouettes with only the title), the
// focused quest's objectives with their progress on the right, and Mission
// Control's lines below, newest first, with the game time they arrived.
// A last tab shows the venture's contracts (ui_contracts.odin). Once every
// quest is done the last chapter's list starts with "Contracts continue",
// where the active quest would be, and the HUD shows the oldest open
// contract instead (hud.odin).

JOURNAL_LIST_COLUMN_WIDTH :: 560
// The list column's most share of the panel on a narrow screen.
JOURNAL_LIST_COLUMN_FRACTION :: 0.4
JOURNAL_LOG_HEIGHT_FRACTION :: 0.45
HUD_OBJECTIVE_WIDTH :: 620
// At most this share of the safe area, so toasts on the left keep theirs
// (UI_TOAST_WIDTH_FRACTION).
HUD_OBJECTIVE_WIDTH_FRACTION :: 0.4
SECONDS_PER_MINUTE :: 60
SECONDS_PER_HOUR :: 3600

@(rodata)
objective_verb_keys := [Objective_Type]string {
	.Obtain        = "objective_obtain",
	.Craft         = "objective_craft",
	.Place         = "objective_place",
	.Sustain       = "objective_sustain",
	.Research      = "objective_research",
	.Deliver       = "objective_deliver",
	.Discover      = "objective_discover",
	.Walk          = "objective_walk",
	.Counter       = "objective_counter",
	.Produce_Fluid = "objective_produce_fluid",
	.Ship          = "objective_ship",
}

@(rodata)
quest_status_keys := [Quest_Status]string {
	.Locked = "journal_status_locked",
	.Active = "journal_status_active",
	.Done   = "journal_status_done",
}

// m:ss, or h:mm:ss from the first hour.
format_game_time :: proc(tick: u64, tick_rate: int) -> string {
	seconds := tick / u64(max(tick_rate, 1))
	if seconds >= SECONDS_PER_HOUR {
		return fmt.tprintf("%d:%02d:%02d", seconds / SECONDS_PER_HOUR, seconds % SECONDS_PER_HOUR / SECONDS_PER_MINUTE, seconds % SECONDS_PER_MINUTE)
	}
	return fmt.tprintf("%d:%02d", seconds / SECONDS_PER_MINUTE, seconds % SECONDS_PER_MINUTE)
}

// Greedy word wrap to a width in UI units, in the temp allocator. A word
// longer than the width gets a line of its own.
wrap_text :: proc(state: ^Ui_State, value: string, size, width: f32) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	line := ""
	for word in strings.fields(value, context.temp_allocator) {
		candidate := line == "" ? word : strings.concatenate({line, " ", word}, context.temp_allocator)
		if line != "" && ui_text_width(state, candidate, size) > width {
			append(&lines, line)
			candidate = word
		}
		line = candidate
	}
	if line != "" {
		append(&lines, line)
	}
	return lines[:]
}

// The quests of a chapter in journal order: active first, then done,
// then locked, each group in play order.
journal_quest_order :: proc(quest_state: Quest_State, chapter: Chapter, allocator := context.temp_allocator) -> []int {
	order := make([dynamic]int, 0, chapter.quest_count, allocator)
	for status in ([3]Quest_Status{.Active, .Done, .Locked}) {
		for index in chapter.first_quest ..< chapter.first_quest + chapter.quest_count {
			if quest_state.progress[index].status == status {
				append(&order, index)
			}
		}
	}
	return order[:]
}

// Every quest is done and the tab is the last chapter's, where the
// active quest would have been.
journal_shows_contracts_continue :: proc(quest_state: Quest_State, tab, chapter_count: int) -> bool {
	return quest_state.active == NO_QUEST && chapter_count > 0 && tab == chapter_count - 1
}

journal_quest_view :: proc(screen_context: Screen_Context) -> Quest_View {
	return Quest_View {
		statistics = screen_context.world.statistics,
		unlocks = screen_context.unlocks^,
		capsule_slots = entity_slots(&screen_context.world.entities, screen_context.quest_state.capsule),
		tick_rate = screen_context.tick_rate,
	}
}

objective_subject :: proc(objective: Objective, screen_context: Screen_Context) -> string {
	switch objective.type {
	case .Obtain, .Craft, .Deliver, .Sustain:
		return item_name(screen_context.items, objective.item)
	case .Place:
		if objective.machine == NO_MACHINE {
			return item_name(screen_context.items, objective.item)
		}
		return machine_name(screen_context.machines, objective.machine)
	case .Research:
		return technology_name(screen_context.technologies, objective.technology)
	case .Discover:
		return recipe_name(screen_context.recipes, objective.recipe)
	case .Produce_Fluid:
		return fluid_name(screen_context.fluids, objective.fluid)
	case .Ship:
		return objective.item == NO_ITEM ? text("objective_ship_any_item") : item_name(screen_context.items, objective.item)
	case .Walk, .Counter:
		return ""
	}
	return ""
}

objective_label :: proc(objective: Objective, screen_context: Screen_Context) -> string {
	if objective.type == .Counter {
		return text(objective.label_key)
	}
	subject := objective_subject(objective, screen_context)
	if subject == "" {
		return text(objective_verb_keys[objective.type])
	}
	return fmt.tprintf("%s %s", text(objective_verb_keys[objective.type]), subject)
}

sustain_progress_text :: proc(objective: Objective, value: Objective_Progress, screen_context: Screen_Context) -> string {
	rate := production_rate_per_minute(screen_context.world.statistics, objective.item)
	held := format_game_time(value.current, screen_context.tick_rate)
	target := format_game_time(value.required, screen_context.tick_rate)
	return fmt.tprintf("%s / %s   %s / %s", format_per_minute(f32(rate)), format_per_minute(f32(objective.rate_per_minute)), held, target)
}

objective_progress_text :: proc(objective: Objective, value: Objective_Progress, screen_context: Screen_Context) -> string {
	#partial switch objective.type {
	case .Sustain:
		return sustain_progress_text(objective, value, screen_context)
	case .Walk:
		return fmt.tprintf("%d / %s", min(value.current, value.required), format_blocks(int(value.required)))
	case .Produce_Fluid:
		return fmt.tprintf("%d / %d L", min(value.current, value.required), value.required)
	}
	return fmt.tprintf("%d / %d", min(value.current, value.required), value.required)
}

objective_line :: proc(quest: Quest, index: int, progress: Quest_Progress, screen_context: Screen_Context) -> (label, progress_text: string, done: bool) {
	objective := quest.objectives[index]
	value := objective_progress(objective, index, progress, journal_quest_view(screen_context))
	return objective_label(objective, screen_context), objective_progress_text(objective, value, screen_context), objective_done(value)
}

// The top right column the HUD objective is drawn in.
hud_objective_area :: proc(state: ^Ui_State) -> Ui_Rectangle {
	safe := ui_safe_area(state)
	width := min(f32(HUD_OBJECTIVE_WIDTH), safe.width * HUD_OBJECTIVE_WIDTH_FRACTION)
	return Ui_Rectangle{safe.x + safe.width - width, safe.y, width, safe.height}
}

// The active objective, top right: the quest title, its objective text
// and one progress line per objective.
draw_quest_objective :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	quest_state := screen_context.quest_state
	if quest_state == nil || quest_state.active == NO_QUEST {
		return
	}
	quest := screen_context.quests.quests[quest_state.active]
	progress := quest_state.progress[quest_state.active]
	area := hud_objective_area(state)
	width := area.width
	draw_text_fitted(state, cut_top(&area, UI_ROW_HEIGHT), text(quest.title_key), UI_BODY_TEXT_SIZE, .Right, UI_ACCENT_COLOR)
	for line in wrap_text(state, text(quest.text_key), UI_BODY_TEXT_SIZE, width) {
		draw_text(state, cut_top(&area, UI_LINE_HEIGHT), line, UI_BODY_TEXT_SIZE, .Right)
	}
	for _, index in quest.objectives {
		label, progress_text, done := objective_line(quest, index, progress, screen_context)
		for line in wrap_text(state, fmt.tprintf("%s  %s", label, progress_text), UI_BODY_TEXT_SIZE, width) {
			draw_text(state, cut_top(&area, UI_LINE_HEIGHT), line, UI_BODY_TEXT_SIZE, .Right, done ? UI_DIM_TEXT_COLOR : UI_TEXT_COLOR)
		}
	}
}

// One tab per chapter and a last one for the contracts (work item 0041).
chapter_tabs :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, screen_context: Screen_Context) -> int {
	chapters := screen_context.quests.chapters
	labels := make([]string, len(chapters) + 1, context.temp_allocator)
	for chapter, index in chapters {
		labels[index] = text(chapter.title_key)
	}
	labels[len(chapters)] = text("journal_contracts")
	return ui_tabs(state, rectangle, "journal_chapters", labels)
}

// One row per quest; returns the focused quest or NO_QUEST.
journal_quest_list :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context, order: []int) -> int {
	focused := NO_QUEST
	list := scroll_list_begin(state, "journal_quests", area, len(order))
	for quest_index, position in order {
		row := scroll_list_row(list, position)
		id := ui_id(state, "quest", quest_index)
		interaction := ui_interact(state, id, row)
		if interaction.focused {
			scroll_list_keep_visible(&list, position)
			focused = quest_index
		}
		widget_background(state, row, id, interaction)
		draw_quest_row(state, row, screen_context, quest_index)
	}
	scroll_list_end(state, &list)
	return focused
}

draw_quest_row :: proc(state: ^Ui_State, row: Ui_Rectangle, screen_context: Screen_Context, quest_index: int) {
	quest := screen_context.quests.quests[quest_index]
	status := screen_context.quest_state.progress[quest_index].status
	color := status == .Active ? UI_ACCENT_COLOR : (status == .Done ? UI_TEXT_COLOR : UI_DIM_TEXT_COLOR)
	content := inset(row, UI_PADDING)
	status_text := text(quest_status_keys[status])
	status_width := ui_text_width(state, status_text, UI_BODY_TEXT_SIZE)
	draw_text(state, content, status_text, UI_BODY_TEXT_SIZE, .Right, UI_DIM_TEXT_COLOR)
	content.width = max(content.width - status_width - UI_GAP, 0)
	draw_text_fitted(state, content, text(quest.title_key), UI_BODY_TEXT_SIZE, .Left, color)
}

// A strip off the top of the content, or false when less is left.
take_line :: proc(content: ^Ui_Rectangle, height: f32) -> (line: Ui_Rectangle, fits: bool) {
	if content.height < height {
		return {}, false
	}
	return cut_top(content, height), true
}

// Wrapped lines from the top of the content, as many as fit.
draw_wrapped :: proc(state: ^Ui_State, content: ^Ui_Rectangle, value: string, color := UI_TEXT_COLOR) {
	for line in wrap_text(state, value, UI_BODY_TEXT_SIZE, content.width) {
		row := take_line(content, UI_LINE_HEIGHT) or_break
		ui_label(state, row, line, UI_BODY_TEXT_SIZE, .Left, color)
	}
}

rewards_text :: proc(quest: Quest, screen_context: Screen_Context) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	for stack in quest.reward_items {
		append(&parts, stack_line(stack, screen_context.items))
	}
	for recipe in quest.reward_recipes {
		append(&parts, recipe_name(screen_context.recipes, recipe))
	}
	for technology in quest.reward_technologies {
		append(&parts, technology_name(screen_context.technologies, technology))
	}
	return strings.join(parts[:], ", ", context.temp_allocator)
}

// The focused quest: a silhouette shows only its title. Lines that do
// not fit the area are left out. Returns the height used.
journal_quest_detail :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context, quest_index: int) -> f32 {
	if quest_index == NO_QUEST {
		return 0
	}
	content := area
	quest := screen_context.quests.quests[quest_index]
	progress := screen_context.quest_state.progress[quest_index]
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), text(quest.title_key), UI_HEADING_TEXT_SIZE, .Left)
	if progress.status == .Locked {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("journal_locked"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
		return area.height - content.height
	}
	if quest.main {
		if row, fits := take_line(&content, UI_LINE_HEIGHT); fits {
			ui_label(state, row, text("journal_main_quest"), UI_BODY_TEXT_SIZE, .Left, UI_ACCENT_COLOR)
		}
	}
	draw_wrapped(state, &content, text(quest.text_key))
	cut_top(&content, UI_GAP)
	for _, index in quest.objectives {
		label, progress_text, done := objective_line(quest, index, progress, screen_context)
		row := take_line(&content, UI_LINE_HEIGHT) or_break
		color := done ? UI_DIM_TEXT_COLOR : UI_TEXT_COLOR
		draw_text(state, row, progress_text, UI_BODY_TEXT_SIZE, .Right, color)
		row.width = max(row.width - ui_text_width(state, progress_text, UI_BODY_TEXT_SIZE) - UI_PADDING, 0)
		draw_text_fitted(state, row, label, UI_BODY_TEXT_SIZE, .Left, color)
	}
	if rewards := rewards_text(quest, screen_context); rewards != "" {
		cut_top(&content, UI_GAP)
		draw_wrapped(state, &content, fmt.tprintf("%s %s", text("journal_rewards"), rewards), UI_DIM_TEXT_COLOR)
	}
	return area.height - content.height
}

// Mission Control's lines, newest first, as many as fit.
journal_message_log :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	content := area
	if content.height < UI_ROW_HEIGHT + UI_LINE_HEIGHT {
		return
	}
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("journal_messages"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	messages := screen_context.quest_state.messages[:]
	#reverse for message in messages {
		line := fmt.tprintf("%s  %s", format_game_time(message.tick, screen_context.tick_rate), quest_message_text(message, screen_context.world.shipments[:], screen_context.items))
		wrapped := wrap_text(state, line, UI_BODY_TEXT_SIZE, content.width)
		if f32(len(wrapped)) * UI_LINE_HEIGHT > content.height {
			return
		}
		draw_wrapped(state, &content, line)
		cut_top(&content, UI_GAP)
	}
}

journal_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	ui_backdrop(state)
	panel := ui_panel_area(state)
	ui_panel_begin(state, "journal", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("journal_title"), UI_HEADING_TEXT_SIZE, .Centre)
	if len(screen_context.quests.chapters) == 0 {
		ui_panel_end(state)
		return
	}
	tab := chapter_tabs(state, cut_top(&content, UI_ROW_HEIGHT), screen_context)
	cut_top(&content, UI_GAP)
	// The contracts tab has no quest detail: the contracts take half the
	// width and the log the other half.
	if tab == len(screen_context.quests.chapters) {
		contracts_area := cut_left(&content, content.width / 2)
		cut_left(&content, 2 * UI_PADDING)
		journal_contracts_section(state, contracts_area, screen_context)
		journal_message_log(state, content, screen_context)
		ui_panel_end(state)
		journal_glyph_bar(state)
		return
	}
	list_area := cut_left(&content, min(f32(JOURNAL_LIST_COLUMN_WIDTH), content.width * JOURNAL_LIST_COLUMN_FRACTION))
	cut_left(&content, 2 * UI_PADDING)
	if journal_shows_contracts_continue(screen_context.quest_state^, tab, len(screen_context.quests.chapters)) {
		row := inset(cut_top(&list_area, UI_ROW_HEIGHT), UI_PADDING)
		draw_text_fitted(state, row, text("journal_contracts_continue"), UI_BODY_TEXT_SIZE, .Left, UI_ACCENT_COLOR)
	}
	chapter := screen_context.quests.chapters[tab]
	order := journal_quest_order(screen_context.quest_state^, chapter)
	focused := journal_quest_list(state, list_area, screen_context, order)
	if focused == NO_QUEST && len(order) > 0 {
		focused = order[0]
	}
	// The detail takes what it needs, leaving the log at least its share;
	// the log gets the rest.
	detail_area := content
	detail_area.height -= content.height * JOURNAL_LOG_HEIGHT_FRACTION
	cut_top(&content, journal_quest_detail(state, detail_area, screen_context, focused) + UI_GAP)
	journal_message_log(state, content, screen_context)
	ui_panel_end(state)
	journal_glyph_bar(state)
}

journal_glyph_bar :: proc(state: ^Ui_State) {
	hints := [?]Glyph_Hint{{.Tab_Previous, ""}, {.Tab_Next, text("hint_chapters")}, {.Back, text("hint_close")}}
	ui_glyph_bar(state, hints[:])
}
