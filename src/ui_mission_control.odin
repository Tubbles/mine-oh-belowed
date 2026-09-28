package game

import "core:math"
import "core:strings"
import "core:unicode/utf8"

// Mission Control on screen (work item 0069). Quest notices are sorted by
// their key (notice_presentation): Mission Control's lines (keys with the
// mc_ prefix) queue for the HUD panel at the top left, a discovery (work
// item 0052) shows a small card at the top centre, everything else stays
// a toast. A line types itself out at MISSION_CONTROL_CHARACTERS_PER_SECOND
// with a blinking cursor, holds for MISSION_CONTROL_HOLD_SECONDS, then
// fades; the next queued line follows. No button acts on a line: in the
// world Confirm is also Jump and Mine, and the journal keeps every line.
// The timing and the queue are pure; ui_begin advances them with the frame
// time like the toasts, and the HUD draws them (hud.odin).

MISSION_CONTROL_KEY_PREFIX :: "mc_"
MISSION_CONTROL_CHARACTERS_PER_SECOND :: 40
MISSION_CONTROL_HOLD_SECONDS :: 4
MISSION_CONTROL_FADE_SECONDS :: 0.5
// Lines waiting behind the one shown; the oldest waiting one gives way.
MISSION_CONTROL_QUEUE_CAPACITY :: 8
MISSION_CONTROL_CURSOR_BLINKS_PER_SECOND :: 2
MISSION_CONTROL_PANEL_WIDTH :: 640
// The panel's text keeps at most this share of the safe area's height.
MISSION_CONTROL_HEIGHT_FRACTION :: 0.5
MISSION_CONTROL_BORDER_WIDTH :: UI_FOCUS_BORDER
MISSION_CONTROL_MARK_SIZE :: 24
// The venture's mark: a chevron of two arms, each a staircase of this
// many steps, since the draw list has no triangles.
MISSION_CONTROL_MARK_STEPS :: 6
MISSION_CONTROL_CURSOR_WIDTH :: 10
DISCOVERY_CARD_SECONDS :: 3
DISCOVERY_CARD_ICON_SIZE :: 40

Notice_Presentation :: enum u8 {
	Toast,
	Mission_Control,
	Discovery_Card,
}

// The text is owned.
Mission_Control_Line :: struct {
	text:            string,
	character_count: int,
	seconds:         f32,
	started:         bool,
}

// The name is owned. item is nil when the notice carried none.
Discovery_Card :: struct {
	active:  bool,
	item:    Maybe(Item_Id),
	name:    string,
	seconds: f32,
}

// In Ui_State: the line shown first, then the waiting ones.
Mission_Control_State :: struct {
	lines:     [dynamic]Mission_Control_Line,
	discovery: Discovery_Card,
}

is_mission_control_key :: proc(text_key: string) -> bool {
	return strings.has_prefix(text_key, MISSION_CONTROL_KEY_PREFIX)
}

notice_presentation :: proc(text_key: string) -> Notice_Presentation {
	switch {
	case is_mission_control_key(text_key):
		return .Mission_Control
	case text_key == ITEM_DISCOVERED_KEY:
		return .Discovery_Card
	}
	return .Toast
}

// Timing.

revealed_characters :: proc(seconds: f32) -> int {
	return int(math.floor(max(seconds, 0) * MISSION_CONTROL_CHARACTERS_PER_SECOND))
}

mission_control_reveal_seconds :: proc(character_count: int) -> f32 {
	return f32(character_count) / MISSION_CONTROL_CHARACTERS_PER_SECOND
}

// Typing, holding and fading.
mission_control_line_seconds :: proc(character_count: int) -> f32 {
	return mission_control_reveal_seconds(character_count) + MISSION_CONTROL_HOLD_SECONDS + MISSION_CONTROL_FADE_SECONDS
}

mission_control_line_revealing :: proc(line: Mission_Control_Line) -> bool {
	return line.seconds < mission_control_reveal_seconds(line.character_count)
}

// 1 until the fade, then down to 0 at the end.
mission_control_line_alpha :: proc(line: Mission_Control_Line) -> f32 {
	remaining := mission_control_line_seconds(line.character_count) - line.seconds
	return clamp(remaining / MISSION_CONTROL_FADE_SECONDS, 0, 1)
}

mission_control_cursor_visible :: proc(seconds: f32) -> bool {
	return int(math.floor(max(seconds, 0) * 2 * MISSION_CONTROL_CURSOR_BLINKS_PER_SECOND)) % 2 == 0
}

// The first count characters (runes) of the value.
rune_prefix :: proc(value: string, count: int) -> string {
	seen := 0
	for _, offset in value {
		if seen == count {
			return value[:offset]
		}
		seen += 1
	}
	return value
}

// The wrapped lines as far as count characters reach, the break between
// two lines counting as the space it replaced. In the temp allocator.
revealed_lines :: proc(lines: []string, count: int) -> []string {
	result := make([dynamic]string, context.temp_allocator)
	left := count
	for line in lines {
		if left <= 0 {
			break
		}
		append(&result, rune_prefix(line, left))
		left -= utf8.rune_count_in_string(line) + 1
	}
	return result[:]
}

// The queue.

advance_mission_control_line :: proc(line: Mission_Control_Line, seconds: f32) -> (next: Mission_Control_Line, finished: bool) {
	next = line
	next.seconds += max(seconds, 0)
	return next, next.seconds >= mission_control_line_seconds(line.character_count)
}

// Marks the first line started; true when it just started, which is when
// its chime plays.
start_mission_control_line :: proc(lines: []Mission_Control_Line) -> bool {
	if len(lines) == 0 || lines[0].started {
		return false
	}
	lines[0].started = true
	return true
}

remove_first_mission_control_line :: proc(lines: ^[dynamic]Mission_Control_Line) {
	delete(lines[0].text)
	ordered_remove(lines, 0)
}

// The text is copied. Returns whether the line started at once.
push_mission_control_line :: proc(state: ^Mission_Control_State, text: string) -> bool {
	if len(state.lines) == MISSION_CONTROL_QUEUE_CAPACITY {
		delete(state.lines[1].text)
		ordered_remove(&state.lines, 1)
	}
	append(&state.lines, Mission_Control_Line{text = strings.clone(text), character_count = utf8.rune_count_in_string(text)})
	return start_mission_control_line(state.lines[:])
}

// A new discovery replaces the card shown. The name is copied.
show_discovery_card :: proc(state: ^Mission_Control_State, item: Maybe(Item_Id), name: string) {
	delete(state.discovery.name)
	state.discovery = Discovery_Card{active = true, item = item, name = strings.clone(name)}
}

advance_discovery_card :: proc(card: ^Discovery_Card, seconds: f32) {
	if !card.active {
		return
	}
	card.seconds += max(seconds, 0)
	if card.seconds >= DISCOVERY_CARD_SECONDS {
		delete(card.name)
		card^ = {}
	}
}

// Reduced motion shows the line whole at once: its time starts past the
// typing, so the hold and the fade keep their length.
instant_reveal :: proc(line: Mission_Control_Line) -> Mission_Control_Line {
	next := line
	next.seconds = max(line.seconds, mission_control_reveal_seconds(line.character_count))
	return next
}

// The frame's step: the time on the line shown, the next line started
// once it is gone. Returns the chimes due.
advance_mission_control :: proc(state: ^Mission_Control_State, seconds: f32, reduced_motion := false) -> bit_set[Ui_Sound_Event] {
	advance_discovery_card(&state.discovery, seconds)
	if len(state.lines) == 0 {
		return {}
	}
	if reduced_motion {
		state.lines[0] = instant_reveal(state.lines[0])
	}
	finished: bool
	state.lines[0], finished = advance_mission_control_line(state.lines[0], seconds)
	if finished {
		remove_first_mission_control_line(&state.lines)
	}
	return start_mission_control_line(state.lines[:]) ? {.Mission_Control} : {}
}

clear_mission_control :: proc(state: ^Mission_Control_State) {
	for line in state.lines {
		delete(line.text)
	}
	clear(&state.lines)
	delete(state.discovery.name)
	state.discovery = {}
}

destroy_mission_control :: proc(state: ^Mission_Control_State) {
	clear_mission_control(state)
	delete(state.lines)
}

// Routing, from the frame loop.

ui_mission_control_line :: proc(state: ^Ui_State, text: string) {
	if push_mission_control_line(&state.mission_control, text) {
		state.sound_events += {.Mission_Control}
	}
}

ui_discovery_card :: proc(state: ^Ui_State, item: Maybe(Item_Id), name: string) {
	show_discovery_card(&state.mission_control, item, name)
	state.sound_events += {.Discovery}
}

// Drawing, in the HUD's style: the panel colour, an accent border on the
// left, dim text for labels.

faded_color :: proc(color: Ui_Color, alpha: f32) -> Ui_Color {
	result := color
	result.a = u8(f32(color.a) * clamp(alpha, 0, 1))
	return result
}

// The chevron: two arms from the apex at the top centre of the square
// area down to its bottom corners, each MISSION_CONTROL_MARK_STEPS blocks.
mission_control_mark_rectangles :: proc(area: Ui_Rectangle) -> (blocks: [2 * MISSION_CONTROL_MARK_STEPS]Ui_Rectangle) {
	size := min(area.width, area.height)
	step := size / MISSION_CONTROL_MARK_STEPS
	half_step := size / 2 / MISSION_CONTROL_MARK_STEPS
	centre := area.x + area.width / 2
	for row in 0 ..< MISSION_CONTROL_MARK_STEPS {
		offset := f32(row) * half_step
		y := area.y + f32(row) * step
		blocks[2 * row] = {centre - offset - step / 2, y, step, step}
		blocks[2 * row + 1] = {centre + offset - step / 2, y, step, step}
	}
	return
}

draw_mission_control_mark :: proc(state: ^Ui_State, area: Ui_Rectangle, color: Ui_Color) {
	for block in mission_control_mark_rectangles(area) {
		draw_fill(state, block, color)
	}
}

// A row of the panel or the journal: the accent border down its left and
// the mark beside the first text line. Returns the area left for the
// text, padding off its top and bottom.
draw_mission_control_frame :: proc(state: ^Ui_State, row: Ui_Rectangle, padding, alpha: f32) -> Ui_Rectangle {
	content := row
	draw_fill(state, cut_left(&content, MISSION_CONTROL_BORDER_WIDTH), faded_color(UI_ACCENT_COLOR, alpha))
	cut_left(&content, UI_GAP)
	mark := cut_left(&content, MISSION_CONTROL_MARK_SIZE)
	mark_top := row.y + padding + (UI_LINE_HEIGHT - MISSION_CONTROL_MARK_SIZE) / 2
	draw_mission_control_mark(state, {mark.x, mark_top, MISSION_CONTROL_MARK_SIZE, MISSION_CONTROL_MARK_SIZE}, faded_color(UI_ACCENT_COLOR, alpha))
	cut_left(&content, UI_GAP)
	content.y += padding
	content.height = max(content.height - 2 * padding, 0)
	return content
}

// The width the frame leaves for the text.
MISSION_CONTROL_FRAME_INDENT :: MISSION_CONTROL_BORDER_WIDTH + UI_GAP + MISSION_CONTROL_MARK_SIZE + UI_GAP

// The line shown, at the top left of the safe area. Returns the height it
// takes, 0 when no line shows.
draw_mission_control_panel :: proc(state: ^Ui_State) -> f32 {
	if len(state.mission_control.lines) == 0 {
		return 0
	}
	line := state.mission_control.lines[0]
	alpha := mission_control_line_alpha(line)
	safe := ui_safe_area(state)
	width := min(f32(MISSION_CONTROL_PANEL_WIDTH), safe.width * UI_TOAST_WIDTH_FRACTION)
	text_width := width - MISSION_CONTROL_FRAME_INDENT - UI_PADDING
	lines := wrap_text(state, line.text, UI_BODY_TEXT_SIZE, text_width)
	maximum_lines := max(int(safe.height * MISSION_CONTROL_HEIGHT_FRACTION / UI_LINE_HEIGHT) - 1, 1)
	lines = lines[:min(len(lines), maximum_lines)]
	box := Ui_Rectangle{safe.x, safe.y, width, f32(len(lines) + 1) * UI_LINE_HEIGHT + 2 * UI_GAP}
	draw_fill(state, box, faded_color(UI_PANEL_COLOR, alpha))
	content := draw_mission_control_frame(state, box, UI_GAP, alpha)
	content.width -= UI_PADDING
	draw_text_fitted(state, cut_top(&content, UI_LINE_HEIGHT), text("mission_control_header"), UI_BODY_TEXT_SIZE, .Left, faded_color(UI_ACCENT_COLOR, alpha), emphasis = true)
	shown := revealed_lines(lines, revealed_characters(line.seconds))
	for shown_line in shown {
		draw_text(state, cut_top(&content, UI_LINE_HEIGHT), shown_line, UI_BODY_TEXT_SIZE, .Left, faded_color(UI_TEXT_COLOR, alpha))
	}
	if mission_control_line_revealing(line) && mission_control_cursor_visible(line.seconds) {
		draw_mission_control_cursor(state, content, shown)
	}
	return box.height
}

// After the last revealed character, or at the start of the first line.
draw_mission_control_cursor :: proc(state: ^Ui_State, below_text: Ui_Rectangle, shown: []string) {
	last := len(shown) > 0 ? shown[len(shown) - 1] : ""
	row_y := len(shown) > 0 ? below_text.y - UI_LINE_HEIGHT : below_text.y
	x := min(below_text.x + ui_text_width(state, last, UI_BODY_TEXT_SIZE), below_text.x + below_text.width - MISSION_CONTROL_CURSOR_WIDTH)
	height := f32(UI_BODY_TEXT_SIZE) * 0.8
	draw_fill(state, {x, row_y + (UI_LINE_HEIGHT - height) / 2, MISSION_CONTROL_CURSOR_WIDTH, height}, UI_ACCENT_COLOR)
}

// Centred under the top edge of the safe area: the item's icon,
// "Discovered" dim and the name.
draw_discovery_card :: proc(state: ^Ui_State, items: Item_Registry) {
	card := state.mission_control.discovery
	if !card.active {
		return
	}
	safe := ui_safe_area(state)
	title := text("discovery_card_title")
	title_width := ui_text_width(state, title, UI_BODY_TEXT_SIZE)
	name_width := ui_text_width(state, card.name, UI_BODY_TEXT_SIZE, emphasis = true)
	_, has_item := card.item.?
	icon_width := has_item ? f32(DISCOVERY_CARD_ICON_SIZE + UI_GAP) : 0
	width := min(icon_width + title_width + UI_GAP + name_width + 2 * UI_PADDING, safe.width)
	box := Ui_Rectangle{safe.x + (safe.width - width) / 2, safe.y, width, UI_ROW_HEIGHT}
	draw_fill(state, box, UI_PANEL_COLOR)
	draw_outline(state, box, UI_ACCENT_COLOR)
	content := inset(box, UI_PADDING)
	content.y, content.height = box.y, box.height
	if item, found := card.item.?; found {
		icon := cut_left(&content, DISCOVERY_CARD_ICON_SIZE)
		draw_item_icon(state, {icon.x, box.y + (box.height - DISCOVERY_CARD_ICON_SIZE) / 2, DISCOVERY_CARD_ICON_SIZE, DISCOVERY_CARD_ICON_SIZE}, item_icon(items, item))
		cut_left(&content, UI_GAP)
	}
	draw_text_fitted(state, cut_left(&content, title_width), title, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	cut_left(&content, UI_GAP)
	draw_text_fitted(state, content, card.name, UI_BODY_TEXT_SIZE, .Left, emphasis = true)
}
