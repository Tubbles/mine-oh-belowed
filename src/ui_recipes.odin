package game

import "core:fmt"
import "core:strings"

// The recipe browser (DESIGN.md, User interface): category tabs on the
// bumpers, the "can craft now" toggle and the tag filter on the left, the
// recipes sorted by name in the middle with the letter wheel on the left
// pad (letter keys on the keyboard), and the focused recipe's detail on
// the right, whose "made by" and "used in" lists walk the recipe graph.
// Confirm on a recipe queues one hand craft, the context action five, the
// secondary action cancels the newest queued craft. There is no search box.
//
// In the selection mode, opened from an assembler's panel, the list holds
// the available recipes an assembler makes, and Confirm sets the focused
// one on the assembler and goes back to its panel.

RECIPE_FILTER_COLUMN_WIDTH :: 380
RECIPE_LIST_COLUMN_WIDTH :: 560
RECIPE_ICON_SIZE :: 40
RECIPE_CRAFTABLE_MARK_WIDTH :: 6
RECIPE_CRAFT_MANY_COUNT :: 5
RECIPE_LETTER_WHEEL_RADIUS :: 320
RECIPE_LETTER_BOX_SIZE :: 52

// State of the browser across frames and openings. pending_focus is a
// recipe reached through the graph whose list row takes the focus on the
// next frame, once the filter shows it. selecting_for is the assembler
// whose recipe is being chosen, NO_ENTITY outside the selection mode.
Recipe_Browser :: struct {
	filter:         Recipe_Filter,
	focused_recipe: int,
	pending_focus:  int,
	letter_radial:  Radial_State,
	selecting_for:  Entity_Handle,
}

@(rodata)
recipe_change_refusal_keys := [Recipe_Change_Refusal]string {
	.None                = "",
	.Not_For_Assembler   = "recipe_change_refused_maker",
	.Contents_Do_Not_Fit = "recipe_change_refused_contents",
}

make_recipe_browser :: proc() -> Recipe_Browser {
	return Recipe_Browser{focused_recipe = NO_RECIPE, pending_focus = NO_RECIPE}
}

// A scrolling column of rows. The right stick and the wheel scroll it and
// a focused row keeps itself in view, like ui_list.
Scroll_List :: struct {
	id:           Ui_Id,
	area:         Ui_Rectangle,
	scroll:       f32,
	count:        int,
	focus_inside: bool,
}

scroll_list_begin :: proc(state: ^Ui_State, label: string, area: Ui_Rectangle, count: int) -> Scroll_List {
	id := ui_push_id(state, label)
	push_command(state, {kind = .Clip_Begin, rectangle = area})
	return Scroll_List{id = id, area = area, scroll = state.scroll_offsets[id], count = count}
}

scroll_list_row :: proc(list: Scroll_List, position: int) -> Ui_Rectangle {
	return {list.area.x, list.area.y + f32(position) * UI_ROW_HEIGHT - list.scroll, list.area.width, UI_ROW_HEIGHT}
}

scroll_list_keep_visible :: proc(list: ^Scroll_List, position: int) {
	list.focus_inside = true
	list.scroll = scroll_to_show(list.scroll, f32(position) * UI_ROW_HEIGHT, UI_ROW_HEIGHT, list.area.height)
}

scroll_list_end :: proc(state: ^Ui_State, list: ^Scroll_List) {
	push_command(state, {kind = .Clip_End})
	if list.focus_inside || ui_pointer_over(state, list.area) {
		list.scroll -= state.input.scroll_stick * UI_LIST_STICK_ROWS_PER_SECOND * UI_ROW_HEIGHT * state.frame_seconds
		list.scroll -= state.input.scroll_wheel * UI_ROW_HEIGHT
	}
	maximum_scroll := max(f32(list.count) * UI_ROW_HEIGHT - list.area.height, 0)
	state.scroll_offsets[list.id] = clamp(list.scroll, 0, maximum_scroll)
	ui_pop_id(state)
}

// The id of a recipe's row in the list, from outside the list's scope.
recipe_row_id :: proc(list_id: Ui_Id, recipe: int) -> Ui_Id {
	return ui_hash(list_id, "row", recipe)
}

silhouette_icon :: proc() -> Item_Icon {
	return Item_Icon{kind = .Lettered, color = UI_WIDGET_COLOR, letters = {'?', ' '}}
}

recipe_icon :: proc(screen_context: Screen_Context, recipe: int) -> Item_Icon {
	if !recipe_is_available(screen_context.unlocks^, recipe) {
		return silhouette_icon()
	}
	return item_icon(screen_context.items, screen_context.recipes.recipes[recipe].outputs[0].item)
}

icon_rectangle :: proc(row: Ui_Rectangle) -> Ui_Rectangle {
	return {row.x + UI_PADDING, row.y + (row.height - RECIPE_ICON_SIZE) / 2, RECIPE_ICON_SIZE, RECIPE_ICON_SIZE}
}

text_after_icon :: proc(row: Ui_Rectangle) -> Ui_Rectangle {
	offset := f32(UI_PADDING + RECIPE_ICON_SIZE + UI_GAP)
	return {row.x + offset, row.y, max(row.width - offset - UI_PADDING, 0), row.height}
}

// One recipe row: icon, name, and a mark when it can be crafted now.
// Silhouettes are dimmed and show no icon.
draw_recipe_row :: proc(state: ^Ui_State, row: Ui_Rectangle, screen_context: Screen_Context, recipe: int, craftable: bool) {
	if craftable {
		draw_fill(state, {row.x, row.y, RECIPE_CRAFTABLE_MARK_WIDTH, row.height}, UI_ACCENT_COLOR)
	}
	draw_item_icon(state, icon_rectangle(row), recipe_icon(screen_context, recipe))
	available := recipe_is_available(screen_context.unlocks^, recipe)
	color := available ? UI_TEXT_COLOR : UI_DIM_TEXT_COLOR
	draw_text(state, text_after_icon(row), screen_context.recipe_names[recipe], UI_BODY_TEXT_SIZE, .Left, color)
}

// The recipes of the filter. Returns the activated recipe or NO_RECIPE,
// and whether a row holds the focus.
recipe_list :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context, visible: []int, craftable: []bool) -> (activated: int, focused: bool) {
	activated = NO_RECIPE
	if len(visible) == 0 {
		ui_label(state, {area.x, area.y, area.width, UI_ROW_HEIGHT}, text("recipes_none"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	list := scroll_list_begin(state, "recipe_list", area, len(visible))
	for recipe, position in visible {
		row := scroll_list_row(list, position)
		id := ui_id(state, "row", recipe)
		interaction := ui_interact(state, id, row)
		if interaction.focused {
			scroll_list_keep_visible(&list, position)
			screen_context.browser.focused_recipe = recipe
			focused = true
		}
		if interaction.activated {
			activated = recipe
		}
		widget_background(state, row, id, interaction)
		draw_recipe_row(state, row, screen_context, recipe, craftable[recipe])
	}
	scroll_list_end(state, &list)
	return activated, focused
}

// Recipe names that navigate the graph when activated. Returns the
// activated recipe or NO_RECIPE.
recipe_link_list :: proc(state: ^Ui_State, area: Ui_Rectangle, label: string, recipes: []int, screen_context: Screen_Context, craftable: []bool) -> int {
	content := area
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(label), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	if len(recipes) == 0 {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("recipes_link_none"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
		return NO_RECIPE
	}
	activated := NO_RECIPE
	list := scroll_list_begin(state, label, content, len(recipes))
	for recipe, position in recipes {
		row := scroll_list_row(list, position)
		id := ui_id(state, "row", recipe)
		interaction := ui_interact(state, id, row)
		if interaction.focused {
			scroll_list_keep_visible(&list, position)
		}
		if interaction.activated {
			activated = recipe
		}
		widget_background(state, row, id, interaction)
		draw_recipe_row(state, row, screen_context, recipe, craftable[recipe])
	}
	scroll_list_end(state, &list)
	return activated
}

// Bumpers switch the category; switching drops the tag filter, since tags
// belong to the recipes of one category.
recipe_category_tabs :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, browser: ^Recipe_Browser) {
	labels: [len(Recipe_Category)]string
	for category in Recipe_Category {
		labels[int(category)] = text(recipe_category_key(category))
	}
	state.selections[ui_id(state, "recipe_tabs")] = int(browser.filter.category)
	category := Recipe_Category(ui_tabs(state, rectangle, "recipe_tabs", labels[:]))
	if category != browser.filter.category {
		browser.filter.category = category
		browser.filter.tags = {}
	}
}

queue_summary_text :: proc(queue: Craft_Queue) -> string {
	return fmt.tprintf("%s  %d / %d", text("crafting_queue"), queue.count, HAND_CRAFT_QUEUE_CAPACITY)
}

// The craftable toggle, one toggle per tag of the category, and the queue
// length at the bottom. Tags that do not fit are left out.
recipe_filter_column :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	browser := screen_context.browser
	content := area
	if browser.selecting_for == NO_ENTITY {
		queue := screen_context.player.crafting
		queue_row := cut_bottom(&content, UI_ROW_HEIGHT)
		ui_label(state, queue_row, queue_summary_text(queue), UI_BODY_TEXT_SIZE, .Left, queue.waiting ? UI_ACCENT_COLOR : UI_DIM_TEXT_COLOR)
		ui_toggle(state, settings_row(&content), text("recipes_can_craft"), &browser.filter.craftable_only)
	}
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("recipes_tags"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	tags := category_tags(screen_context.recipes, browser.filter.category)
	for name, index in screen_context.recipes.tag_names {
		if index not_in tags || content.height < UI_ROW_HEIGHT {
			continue
		}
		selected := index in browser.filter.tags
		if ui_toggle(state, settings_row(&content), text(recipe_tag_key(name)), &selected) {
			browser.filter.tags ~= {index}
		}
	}
}

stack_line :: proc(stack: Item_Stack, items: Item_Registry) -> string {
	return fmt.tprintf("%d × %s", stack.count, item_name(items, stack.item))
}

draw_stack_rows :: proc(state: ^Ui_State, content: ^Ui_Rectangle, label: string, stacks: []Item_Stack, items: Item_Registry) {
	ui_label(state, cut_top(content, UI_ROW_HEIGHT), text(label), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	for stack in stacks {
		row := cut_top(content, UI_ROW_HEIGHT)
		draw_item_icon(state, icon_rectangle(row), item_icon(items, stack.item))
		draw_text(state, text_after_icon(row), stack_line(stack, items), UI_BODY_TEXT_SIZE, .Left)
	}
}

makers_text :: proc(makers: Recipe_Makers) -> string {
	names := make([dynamic]string, context.temp_allocator)
	for maker in makers {
		append(&names, text(recipe_maker_key(maker)))
	}
	return strings.join(names[:], ", ", context.temp_allocator)
}

recipe_facts_text :: proc(recipe: Recipe) -> string {
	seconds := f32(recipe.milliseconds) / 1000
	return fmt.tprintf("%s %.1f s    %s %s", text("recipes_time"), seconds, text("recipes_made_in"), makers_text(recipe.made_in))
}

// What unlocks a silhouette, without naming its ingredients.
locked_recipe_text :: proc(recipe: Recipe, technologies: Technology_Registry) -> string {
	#partial switch recipe.channel {
	case .Discovery:
		return text("recipes_locked_discovery")
	case .Research:
		return fmt.tprintf("%s %s", text("recipes_locked_research"), technology_name(technologies, recipe.technology))
	case .Quest:
		return text("recipes_locked_quest")
	}
	return ""
}

// The focused recipe. Returns a recipe reached through the graph lists,
// or NO_RECIPE.
recipe_detail_panel :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context, craftable: []bool) -> int {
	recipe := screen_context.browser.focused_recipe
	content := area
	if recipe == NO_RECIPE {
		return NO_RECIPE
	}
	definition := screen_context.recipes.recipes[recipe]
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), screen_context.recipe_names[recipe], UI_HEADING_TEXT_SIZE, .Left)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(recipe_category_key(definition.category)), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	detail := recipe_detail(screen_context.recipes, screen_context.unlocks^, recipe, context.temp_allocator)
	if !detail.revealed {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), locked_recipe_text(definition, screen_context.technologies), UI_BODY_TEXT_SIZE, .Left, UI_ACCENT_COLOR)
		return NO_RECIPE
	}
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), recipe_facts_text(definition), UI_BODY_TEXT_SIZE, .Left)
	draw_stack_rows(state, &content, "recipes_inputs", detail.inputs, screen_context.items)
	draw_stack_rows(state, &content, "recipes_outputs", detail.outputs, screen_context.items)
	cut_top(&content, UI_GAP)
	made_by := recipe_link_list(state, column(content, 2, 0, UI_GAP), "recipes_made_by", detail.made_by, screen_context, craftable)
	used_in := recipe_link_list(state, column(content, 2, 1, UI_GAP), "recipes_used_in", detail.used_in, screen_context, craftable)
	return made_by != NO_RECIPE ? made_by : used_in
}

toast_craft_refusal :: proc(state: ^Ui_State, refusal: Craft_Refusal) {
	if refusal != .None {
		ui_toast(state, text(craft_refusal_keys[refusal]))
	}
}

// Confirm on a row queues one craft, the context action five of the
// focused recipe, the secondary action cancels the newest craft.
apply_recipe_craft_input :: proc(state: ^Ui_State, screen_context: Screen_Context, activated: int, list_focused: bool) {
	player := screen_context.player
	recipes, unlocks := screen_context.recipes, screen_context.unlocks^
	if activated != NO_RECIPE {
		toast_craft_refusal(state, queue_craft(&player.crafting, player.inventory, recipes, unlocks, activated))
	}
	if state.input.context_action && list_focused {
		_, refusal := queue_crafts(&player.crafting, player.inventory, recipes, unlocks, screen_context.browser.focused_recipe, RECIPE_CRAFT_MANY_COUNT)
		toast_craft_refusal(state, refusal)
	}
	if state.input.secondary && player.crafting.count > 0 && !cancel_last_craft(&player.crafting, player.inventory, recipes, screen_context.items) {
		ui_toast(state, text("inventory_full"))
	}
}

letter_radial_source :: proc(input: Ui_Input) -> Radial_Source {
	return input.left_touchpad.down ? .Touchpad : .Held_Button
}

// The letter chosen this frame on the wheel or the keyboard, 0 for none.
letter_input :: proc(state: ^Ui_State, radial: ^Radial_State) -> rune {
	source := letter_radial_source(state.input)
	touching, position := radial_input(state.input, source)
	result: Radial_Result
	radial^, result = advance_radial(radial^, touching, position, source, LETTER_WHEEL_COUNT)
	if result.closed && result.selected >= 0 {
		return letter_for_wheel_slot(result.selected)
	}
	if letter_jumps_on_keyboard(state.input.typed_letter) {
		return state.input.typed_letter
	}
	return 0
}

draw_letter_wheel :: proc(state: ^Ui_State, radial: Radial_State) {
	if !radial.open {
		return
	}
	centre := state.screen_units / 2
	half := f32(RECIPE_LETTER_BOX_SIZE / 2)
	for slot in 0 ..< LETTER_WHEEL_COUNT {
		point := radial_slot_offset(slot, LETTER_WHEEL_COUNT) * RECIPE_LETTER_WHEEL_RADIUS + centre
		box := Ui_Rectangle{point.x - half, point.y - half, RECIPE_LETTER_BOX_SIZE, RECIPE_LETTER_BOX_SIZE}
		highlighted := slot == radial.highlight
		draw_fill(state, box, highlighted ? UI_ACCENT_COLOR : UI_PANEL_COLOR)
		draw_outline(state, box, UI_PANEL_BORDER_COLOR)
		letter := fmt.tprintf("%c", to_upper_ascii(u8(letter_for_wheel_slot(slot))))
		draw_text(state, box, letter, UI_BODY_TEXT_SIZE, .Centre, highlighted ? UI_PANEL_COLOR : UI_TEXT_COLOR)
	}
}

// Moves the focus to a recipe's row, if the list shows it this frame.
focus_recipe_row :: proc(state: ^Ui_State, browser: ^Recipe_Browser, list_id: Ui_Id, recipe: int) -> bool {
	id := recipe_row_id(list_id, recipe)
	if widget_index(state.widgets[:], id) < 0 {
		return false
	}
	state.requested_focus = id
	browser.focused_recipe = recipe
	return true
}

// A graph step from the last frame lands now that the filter shows it;
// a focus that belongs to no widget of this screen (just opened, or the
// category changed) goes to the focused recipe or the first row.
settle_recipe_focus :: proc(state: ^Ui_State, browser: ^Recipe_Browser, list_id: Ui_Id, visible: []int) {
	if browser.pending_focus != NO_RECIPE {
		focus_recipe_row(state, browser, list_id, browser.pending_focus)
		browser.pending_focus = NO_RECIPE
		return
	}
	if state.requested_focus != 0 || widget_index(state.widgets[:], state.focus) >= 0 || len(visible) == 0 {
		return
	}
	if !focus_recipe_row(state, browser, list_id, browser.focused_recipe) {
		focus_recipe_row(state, browser, list_id, visible[0])
	}
}

navigate_to_recipe :: proc(browser: ^Recipe_Browser, recipes: Recipe_Registry, recipe: int, craftable: []bool) {
	browser.filter = filter_showing_recipe(browser.filter, recipes.recipes[recipe], craftable[recipe])
	browser.pending_focus = recipe
	browser.focused_recipe = recipe
}

// Selection mode: sets the chosen recipe on the assembler, handing its
// contents to the player, and goes back to its panel.
choose_assembler_recipe :: proc(state: ^Ui_State, screen_context: Screen_Context, recipe: int) {
	browser := screen_context.browser
	assembler := pool_get(&screen_context.world.entities.assemblers, browser.selecting_for)
	if assembler == nil {
		pop_screen(&state.screens)
		return
	}
	inventory := screen_context.player.inventory
	refusal := change_assembler_recipe(assembler, inventory, screen_context.items, screen_context.recipes, recipe)
	if refusal != .None {
		ui_toast(state, text(recipe_change_refusal_keys[refusal]))
		return
	}
	browser.selecting_for = NO_ENTITY
	pop_screen(&state.screens)
}

// Opens the browser in the selection mode for an assembler.
open_recipe_selection :: proc(state: ^Ui_State, browser: ^Recipe_Browser, assembler: Entity_Handle) {
	browser.selecting_for = assembler
	browser.filter.tags = {}
	push_screen(&state.screens, .Recipes)
}

recipe_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	browser := screen_context.browser
	selecting := browser.selecting_for != NO_ENTITY
	craftable := craftable_recipes(screen_context.recipes, screen_context.unlocks^, screen_context.player.inventory, context.temp_allocator)
	ui_backdrop(state)
	panel := ui_safe_area(state)
	cut_bottom(&panel, UI_GLYPH_TEXT_SIZE + 4 * UI_GAP)
	ui_panel_begin(state, "recipes", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(selecting ? "recipes_choose_title" : "recipes_title"), UI_HEADING_TEXT_SIZE, .Centre)
	recipe_category_tabs(state, cut_top(&content, UI_ROW_HEIGHT), browser)
	cut_top(&content, UI_GAP)
	recipe_filter_column(state, cut_left(&content, RECIPE_FILTER_COLUMN_WIDTH), screen_context)
	cut_left(&content, 2 * UI_PADDING)
	list_area := cut_left(&content, RECIPE_LIST_COLUMN_WIDTH)
	cut_left(&content, 2 * UI_PADDING)
	filter := selecting ? selection_filter(browser.filter, .Assembler) : browser.filter
	visible := filter_recipes(screen_context.recipes, screen_context.recipe_order, filter, craftable, screen_context.unlocks.available, context.temp_allocator)
	list_id := ui_id(state, "recipe_list")
	letter := letter_input(state, &browser.letter_radial)
	activated, list_focused := recipe_list(state, list_area, screen_context, visible, craftable)
	reached := recipe_detail_panel(state, content, screen_context, craftable)
	ui_panel_end(state)
	settle_recipe_focus(state, browser, list_id, visible)
	if position := recipe_position_for_letter(screen_context.recipe_names, visible, letter); letter != 0 && position >= 0 {
		focus_recipe_row(state, browser, list_id, visible[position])
	}
	if reached != NO_RECIPE {
		navigate_to_recipe(browser, screen_context.recipes, reached, craftable)
	}
	draw_letter_wheel(state, browser.letter_radial)
	if selecting {
		if activated != NO_RECIPE {
			choose_assembler_recipe(state, screen_context, activated)
		}
		recipe_selection_glyph_bar(state)
		return
	}
	apply_recipe_craft_input(state, screen_context, activated, list_focused)
	recipe_glyph_bar(state)
}

recipe_selection_glyph_bar :: proc(state: ^Ui_State) {
	hints := [?]Glyph_Hint{{.Confirm, text("hint_choose_recipe")}, {.Tab_Previous, ""}, {.Tab_Next, text("hint_categories")}, {.Back, text("hint_back")}}
	ui_glyph_bar(state, hints[:])
}

recipe_glyph_bar :: proc(state: ^Ui_State) {
	hints := [?]Glyph_Hint {
		{.Confirm, text("hint_craft")},
		{.Context_Action, text("hint_craft_five")},
		{.Secondary, text("hint_cancel_craft")},
		{.Tab_Previous, ""},
		{.Tab_Next, text("hint_categories")},
		{.Back, text("hint_close")},
	}
	ui_glyph_bar(state, hints[:])
}
