package game

import "core:fmt"
import "core:slice"
import "core:strings"

// The recipe browser (DESIGN.md, User interface): the inventory tab strip
// on the bumpers (ui_inventory.odin), the category tabs as a focusable
// row stepped with left and right, the "can craft now" and "unlocked only"
// toggles and the tag filter on the left, the
// recipes sorted by name in the middle with the letter wheel on the left
// pad (letter keys on the keyboard), and the focused recipe's detail on
// the right, whose "made by" and "used in" lists walk the recipe graph.
// Confirm on a recipe queues one hand craft, the context action five, the
// secondary action cancels the newest queued craft; queuing plans the
// missing hand craftable intermediates ahead (crafting.odin). Each row
// shows how many of its product the inventory holds. There is no search box.
// On touch a tap on a recipe selects it and the touch row's Craft, Craft
// 5 and Cancel last act on the selected recipe (0137).
//
// In the selection mode, opened from an assembler's panel, the list holds
// the available recipes an assembler makes, and Confirm sets the focused
// one on the assembler and goes back to its panel. It shows no inventory
// tab strip.

RECIPE_FILTER_COLUMN_WIDTH :: 380
RECIPE_LIST_COLUMN_WIDTH :: 560
// The most share of the panel the filter and the list columns take on a
// narrow screen (also the technology screen's), leaving the detail room.
FILTER_COLUMN_FRACTION :: 0.24
LIST_COLUMN_FRACTION :: 0.34
RECIPE_ICON_SIZE :: 40
// The room at a row's right end for the held count of its product.
RECIPE_HELD_COUNT_WIDTH :: 96
RECIPE_CRAFTABLE_MARK_WIDTH :: 6
RECIPE_CRAFT_MANY_COUNT :: 5
RECIPE_LETTER_WHEEL_RADIUS :: 320
RECIPE_LETTER_BOX_SIZE :: 52

// The icon before each category tab's label (work item 0071): the item
// category's where one matches.
@(rodata)
recipe_category_icons := [Recipe_Category]Ui_Icon {
	.Materials  = .Category_Raw,
	.Components = .Category_Intermediate,
	.Tools      = .Category_Tool,
	.Machines   = .Category_Machine,
	.Logistics  = .Category_Logistics,
	.Power      = .Category_Power,
	.Science    = .Category_Science,
}

// State of the browser across frames and openings. pending_focus is a
// recipe reached through the graph whose list row takes the focus on the
// next frame, once the filter shows it. selecting_for is the assembler
// whose recipe is being chosen, NO_ENTITY outside the selection mode.
// station is the crafting station whose panel the browser is (work item
// 0196, open_station_recipes), NO_ENTITY outside the station mode;
// filter_before_station is the filter it restores on leaving the mode
// (close_station_recipes).
// plans owns memory: destroy_recipe_browser.
Recipe_Browser :: struct {
	filter:         Recipe_Filter,
	focused_recipe: int,
	pending_focus:  int,
	letter_radial:  Radial_State,
	selecting_for:  Entity_Handle,
	station:        Entity_Handle,
	filter_before_station: Recipe_Filter,
	plans:          Recipe_Plans,
}

@(rodata)
recipe_change_refusal_keys := [Recipe_Change_Refusal]string {
	.None                = "",
	.Not_For_Assembler   = "recipe_change_refused_maker",
	.Contents_Do_Not_Fit = "recipe_change_refused_contents",
}

// Unlocked only is on by default (work item 0091).
make_recipe_browser :: proc() -> Recipe_Browser {
	return Recipe_Browser{filter = {available_only = true}, focused_recipe = NO_RECIPE, pending_focus = NO_RECIPE, station = NO_ENTITY, plans = {detail_recipe = NO_RECIPE}}
}

destroy_recipe_browser :: proc(browser: ^Recipe_Browser) {
	destroy_recipe_plans(&browser.plans)
}

reset_recipe_browser :: proc(browser: ^Recipe_Browser) {
	destroy_recipe_browser(browser)
	browser^ = make_recipe_browser()
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
	definition := screen_context.recipes.recipes[recipe]
	if len(definition.outputs) == 0 {
		return fluid_recipe_icon(screen_context.fluids, definition)
	}
	return item_icon(screen_context.items, definition.outputs[0].item)
}

// A recipe with fluid outputs only (refining, cracking): its letters in
// the colour of its first fluid output.
fluid_recipe_icon :: proc(fluids: Fluid_Registry, recipe: Recipe) -> Item_Icon {
	color := UI_WIDGET_COLOR
	if len(recipe.fluid_outputs) > 0 && int(recipe.fluid_outputs[0].fluid) < len(fluids.fluids) {
		rgb := fluids.fluids[recipe.fluid_outputs[0].fluid].color
		color = {rgb.r, rgb.g, rgb.b, 255}
	}
	return Item_Icon{kind = .Lettered, color = color, letters = item_letters(recipe.id)}
}

icon_rectangle :: proc(row: Ui_Rectangle) -> Ui_Rectangle {
	return {row.x + UI_PADDING, row.y + (row.height - RECIPE_ICON_SIZE) / 2, RECIPE_ICON_SIZE, RECIPE_ICON_SIZE}
}

text_after_icon :: proc(row: Ui_Rectangle) -> Ui_Rectangle {
	offset := f32(UI_PADDING + RECIPE_ICON_SIZE + UI_GAP)
	return {row.x + offset, row.y, max(row.width - offset - UI_PADDING, 0), row.height}
}

// One recipe row: icon, name, a mark when it can be crafted now, and
// at the right end how many of its first product the inventory holds
// (0138, dim at 0). Silhouettes are dimmed and show no icon and no count.
draw_recipe_row :: proc(state: ^Ui_State, row: Ui_Rectangle, screen_context: Screen_Context, recipe: int, craftable: bool) {
	if craftable {
		draw_fill(state, {row.x, row.y, RECIPE_CRAFTABLE_MARK_WIDTH, row.height}, UI_ACCENT_COLOR)
	}
	draw_item_icon(state, icon_rectangle(row), recipe_icon(screen_context, recipe))
	available := recipe_is_available(screen_context.unlocks^, recipe)
	color := available ? UI_TEXT_COLOR : UI_DIM_TEXT_COLOR
	name_area := text_after_icon(row)
	if held, has_product := recipe_held_count(screen_context.player.inventory, screen_context.recipes.recipes[recipe]); available && has_product {
		count_area := cut_right(&name_area, RECIPE_HELD_COUNT_WIDTH)
		draw_text_fitted(state, count_area, fmt.tprint(held), UI_BODY_TEXT_SIZE, .Right, held > 0 ? UI_TEXT_COLOR : UI_DIM_TEXT_COLOR)
	}
	draw_text_fitted(state, name_area, screen_context.recipe_names[recipe], UI_BODY_TEXT_SIZE, .Left, color)
}

// How many of the recipe's first product the inventory (hotbar and main
// grid) holds; has_product is false for a recipe making only fluids.
recipe_held_count :: proc(inventory: Inventory, recipe: Recipe) -> (held: int, has_product: bool) {
	if len(recipe.outputs) == 0 {
		return 0, false
	}
	return inventory_count(inventory, recipe.outputs[0].item), true
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
			screen_context.views.recipe_browser.focused_recipe = recipe
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
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), text(label), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	if len(recipes) == 0 {
		draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), text("recipes_link_none"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
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

// A focusable row: left and right switch the category while it holds the
// focus (the bumpers belong to the inventory tab strip). Switching drops
// the tag filter, since tags belong to the recipes of one category. Only
// the shown categories get a tab (a station's, 0196).
recipe_category_tabs :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, browser: ^Recipe_Browser, shown := ~Recipe_Categories{}) {
	labels: [len(Recipe_Category)]string
	icons: [len(Recipe_Category)]Ui_Icon
	categories: [len(Recipe_Category)]Recipe_Category
	count, selected := 0, 0
	for category in Recipe_Category {
		if category not_in shown {
			continue
		}
		selected = category == browser.filter.category ? count : selected
		labels[count], icons[count], categories[count] = text(recipe_category_key(category)), recipe_category_icons[category], category
		count += 1
	}
	if count == 0 {
		return
	}
	state.selections[ui_id(state, "recipe_tabs")] = selected
	category := categories[ui_tabs(state, rectangle, "recipe_tabs", labels[:count], icons[:count], .Focus)]
	if category != browser.filter.category {
		browser.filter.category = category
		browser.filter.tags = {}
	}
}

// "Crafting  20": the crafts queued over every run.
queue_summary_text :: proc(queue: Craft_Queue) -> string {
	return fmt.tprintf("%s  %d", text("crafting_queue"), queued_craft_count(queue))
}

// The craftable and unlocked toggles, one toggle per tag of the category, and the queue
// length at the bottom. Tags that do not fit are left out.
recipe_filter_column :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	browser := &screen_context.views.recipe_browser
	content := area
	if browser.selecting_for == NO_ENTITY {
		queue := screen_context.player.crafting
		queue_row := cut_bottom(&content, UI_ROW_HEIGHT)
		waits := queue.waiting || craft_queue_waits_for_input(queue)
		draw_text_fitted(state, queue_row, queue_summary_text(queue), UI_BODY_TEXT_SIZE, .Left, waits ? UI_ACCENT_COLOR : UI_DIM_TEXT_COLOR)
		ui_toggle(state, cut_row(&content), text("recipes_can_craft"), &browser.filter.craftable_only)
		// A station shows only unlocked recipes (station_filter).
		if browser.station == NO_ENTITY {
			ui_toggle(state, cut_row(&content), text("recipes_unlocked_only"), &browser.filter.available_only)
		}
	}
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), text("recipes_tags"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	tags := category_tags(screen_context.recipes, browser.filter.category)
	for name, index in screen_context.recipes.tag_names {
		if index not_in tags || content.height < UI_ROW_HEIGHT {
			continue
		}
		selected := index in browser.filter.tags
		if ui_toggle(state, cut_row(&content), text(recipe_tag_key(name)), &selected) {
			browser.filter.tags ~= {index}
		}
	}
}

// "5 × Stone". The sign lives in the string table, so every font loads its
// glyph (collect_code_points).
stack_line :: proc(stack: Item_Stack, items: Item_Registry) -> string {
	line := replace_message_mark(text("recipes_stack_line"), "{count}", fmt.tprint(stack.count))
	return replace_message_mark(line, "{name}", item_name(items, stack.item))
}

// "4 × Plank, 12 held": a product and how many the inventory holds.
product_held_line :: proc(stack: Item_Stack, held: int, items: Item_Registry) -> string {
	line := replace_message_mark(text("recipes_product_held_line"), "{count}", fmt.tprint(stack.count))
	line = replace_message_mark(line, "{held}", fmt.tprint(held))
	return replace_message_mark(line, "{name}", item_name(items, stack.item))
}

// "13 / 5 Stone": what the queue leaves for the recipe (0156), what one
// craft needs; an ingredient the queue would craft says so.
ingredient_line :: proc(need: int, name: string, planned: Planned_Input) -> string {
	key := planned.state == .Craftable ? "recipes_ingredient_line_craftable" : "recipes_ingredient_line"
	line := replace_message_mark(text(key), "{have}", fmt.tprint(planned.available))
	line = replace_message_mark(line, "{need}", fmt.tprint(need))
	return replace_message_mark(line, "{name}", name)
}

@(rodata)
planned_input_colors := [Planned_Input_State]Ui_Theme_Color {
	.Held      = .Accent,
	.Craftable = .Text_Dim,
	.Missing   = .Danger,
}

// "Can craft 2".
can_craft_text :: proc(count: int) -> string {
	return replace_message_mark(text("recipes_can_craft_count"), "{count}", fmt.tprint(count))
}

// The label and a row per product with the count held, as many as fit.
draw_product_rows :: proc(state: ^Ui_State, content: ^Ui_Rectangle, label: string, stacks: []Item_Stack, items: Item_Registry, inventory: Inventory) {
	detail_line(state, content, text(label), UI_DIM_TEXT_COLOR)
	for stack in stacks {
		row := take_line(content, UI_ROW_HEIGHT) or_break
		draw_item_icon(state, icon_rectangle(row), item_icon(items, stack.item))
		draw_text_fitted(state, text_after_icon(row), product_held_line(stack, inventory_count(inventory, stack.item), items), UI_BODY_TEXT_SIZE, .Left)
	}
}

// The label and a have and need row per ingredient, as many as fit, in
// the colour of how the queue gets it (planned, one per stack).
draw_ingredient_rows :: proc(state: ^Ui_State, content: ^Ui_Rectangle, label: string, stacks: []Item_Stack, planned: []Planned_Input, items: Item_Registry) {
	detail_line(state, content, text(label), UI_DIM_TEXT_COLOR)
	for stack, index in stacks {
		row := take_line(content, UI_ROW_HEIGHT) or_break
		line := ingredient_line(int(stack.count), item_name(items, stack.item), planned[index])
		draw_item_icon(state, icon_rectangle(row), item_icon(items, stack.item))
		draw_text_fitted(state, text_after_icon(row), line, UI_BODY_TEXT_SIZE, .Left, theme_color(state, planned_input_colors[planned[index].state]))
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
	case .Schematic:
		return text("recipes_locked_schematic")
	}
	return ""
}

// The item whose description the detail panel shows (work item 0070):
// the recipe's first output item, NO_ITEM for a recipe making only
// fluids.
recipe_description_item :: proc(recipe: Recipe) -> Item_Id {
	return len(recipe.outputs) > 0 ? recipe.outputs[0].item : NO_ITEM
}

// The focused recipe. Returns a recipe reached through the graph lists,
// or NO_RECIPE.
recipe_detail_panel :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context, craftable: []bool) -> int {
	recipe := screen_context.views.recipe_browser.focused_recipe
	content := area
	if recipe == NO_RECIPE {
		return NO_RECIPE
	}
	definition := screen_context.recipes.recipes[recipe]
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), screen_context.recipe_names[recipe], UI_HEADING_TEXT_SIZE, .Left)
	detail_line(state, &content, text(recipe_category_key(definition.category)), UI_DIM_TEXT_COLOR)
	detail := recipe_detail(screen_context.recipes, screen_context.unlocks^, recipe, context.temp_allocator)
	if !detail.revealed {
		draw_wrapped(state, &content, locked_recipe_text(definition, screen_context.technologies), UI_ACCENT_COLOR)
		return NO_RECIPE
	}
	draw_wrapped(state, &content, recipe_facts_text(definition))
	if description := item_description(screen_context.items, recipe_description_item(definition)); description != "" {
		cut_top(&content, UI_GAP)
		draw_wrapped(state, &content, description, UI_DIM_TEXT_COLOR)
	}
	cut_top(&content, UI_GAP)
	inventory := screen_context.player.inventory
	plans := &screen_context.views.recipe_browser.plans
	refresh_recipe_detail_plan(plans, screen_context.recipes, screen_context.unlocks^, inventory, screen_context.player.crafting, recipe, screen_craft_makers(screen_context), screen_context.free_crafting)
	draw_ingredient_rows(state, &content, "recipes_inputs", detail.inputs, plans.detail_inputs[:], screen_context.items)
	detail_line(state, &content, can_craft_text(plans.detail_count), plans.detail_count >= 1 ? UI_ACCENT_COLOR : UI_DIM_TEXT_COLOR)
	draw_product_rows(state, &content, "recipes_outputs", detail.outputs, screen_context.items, inventory)
	cut_top(&content, UI_GAP)
	// The graph lists need their label and a row.
	if content.height < 2 * UI_ROW_HEIGHT {
		return NO_RECIPE
	}
	made_by := recipe_link_list(state, column_rectangle(content, 2, 0, UI_GAP), "recipes_made_by", detail.made_by, screen_context, craftable)
	used_in := recipe_link_list(state, column_rectangle(content, 2, 1, UI_GAP), "recipes_used_in", detail.used_in, screen_context, craftable)
	return made_by != NO_RECIPE ? made_by : used_in
}

// "Missing 4 Iron plate", "Stick is made from itself", or the plain
// refusal.
craft_refusal_text :: proc(refusal: Craft_Refusal, shortage: Craft_Shortage, items: Item_Registry) -> string {
	line := text(craft_refusal_keys[refusal])
	if refusal == .Missing_Ingredients || refusal == .Recipe_Cycle || refusal == .Plan_Too_Deep {
		line = replace_message_mark(line, "{count}", fmt.tprint(shortage.count))
		line = replace_message_mark(line, "{name}", item_name(items, shortage.item))
	}
	return line
}

toast_craft_refusal :: proc(state: ^Ui_State, refusal: Craft_Refusal, shortage: Craft_Shortage, items: Item_Registry) {
	if refusal != .None {
		ui_toast(state, craft_refusal_text(refusal, shortage, items))
	}
}

// Confirm on a row queues one craft, the context action five of the
// focused recipe, the secondary action cancels the newest craft; the
// touch row's Craft and Craft 5 act on the selected recipe (the focused
// one before the tap moved the focus to the button) while the list shows
// it, as the context action needs the list's focus; Cancel last as the
// secondary action.
apply_recipe_craft_input :: proc(state: ^Ui_State, screen_context: Screen_Context, activated: int, list_focused, selected_shown: bool, button: Touch_Button) {
	player := screen_context.player
	recipes := screen_context.recipes
	selected := screen_context.views.recipe_browser.focused_recipe
	crafted := activated
	if button == .Craft && selected_shown {
		crafted = selected
	}
	if crafted != NO_RECIPE {
		queue_checked_crafts(state, screen_context, crafted, 1)
	}
	if (state.input.context_action && list_focused) || (button == .Craft_Five && selected_shown) {
		queue_checked_crafts(state, screen_context, selected, RECIPE_CRAFT_MANY_COUNT)
	}
	cancels := state.input.secondary || button == .Cancel_Craft
	if cancels && player.crafting.count > 0 {
		if last_craft_cancels(player.crafting, player.inventory, recipes, screen_context.items) {
			queue_player_command(screen_context.player_commands, screen_context.player_index, Cancel_Craft_Command{})
		} else {
			ui_toast(state, text("inventory_full"))
		}
	}
}

// The planner's refusal toasts now; an accepted craft queues for the tick
// (Craft_Command).
queue_checked_crafts :: proc(state: ^Ui_State, screen_context: Screen_Context, recipe, count: int) {
	player := screen_context.player
	_, _, refusal, shortage := plan_queue_crafts(player.crafting, player.inventory, screen_context.recipes, screen_context.unlocks^, recipe, count, screen_craft_makers(screen_context), screen_context.free_crafting)
	if refusal != .None {
		toast_craft_refusal(state, refusal, shortage, screen_context.items)
		return
	}
	queue_player_command(screen_context.player_commands, screen_context.player_index, Craft_Command{recipe = recipe, count = count})
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

navigate_to_recipe :: proc(browser: ^Recipe_Browser, recipes: Recipe_Registry, unlocks: Recipe_Unlocks, recipe: int, craftable: []bool) {
	browser.filter = filter_showing_recipe(browser.filter, recipes.recipes[recipe], craftable[recipe], recipe_is_available(unlocks, recipe))
	browser.pending_focus = recipe
	browser.focused_recipe = recipe
}

// Selection mode: sets the chosen recipe on the assembler, handing its
// contents to the player, and goes back to its panel.
choose_assembler_recipe :: proc(state: ^Ui_State, screen_context: Screen_Context, recipe: int) {
	browser := &screen_context.views.recipe_browser
	assembler := pool_get(&screen_context.world.entities.assemblers, browser.selecting_for)
	if assembler == nil {
		pop_screen(&state.screens)
		return
	}
	inventory := screen_context.player.inventory
	machine := screen_context.machines.machines[assembler.machine]
	refusal := recipe_change_refusal(assembler, machine, inventory, screen_context.items, screen_context.recipes, recipe)
	if refusal != .None {
		ui_toast(state, text(recipe_change_refusal_keys[refusal]))
		return
	}
	queue_player_command(screen_context.player_commands, screen_context.player_index, Assembler_Recipe_Command{assembler = browser.selecting_for, recipe = recipe})
	browser.selecting_for = NO_ENTITY
	pop_screen(&state.screens)
}

// The makers the tick queues the player's crafts with
// (player_craft_makers), so what the browser offers is what it accepts.
screen_craft_makers :: proc(screen_context: Screen_Context) -> Recipe_Makers {
	return player_craft_makers(&screen_context.world.entities, screen_context.machines, screen_context.player^)
}

// The machine screen of a crafting station (work item 0196) forwards to
// the browser in the station mode: on its first frame the browser opens
// on the station's recipes; once the browser is closed (Back) and the
// machine screen runs again, it closes too, so close_slot_screens closes
// the panel as for any machine.
open_station_recipes :: proc(state: ^Ui_State, browser: ^Recipe_Browser, station: Entity_Handle, category: Recipe_Category) {
	if browser.station != station {
		close_station_recipes(browser)
		browser.station = station
		browser.filter_before_station = browser.filter
		browser.filter.tags = {}
		browser.filter.category = category
		push_screen(&state.screens, .Recipes)
		return
	}
	close_station_recipes(browser)
	pop_screen(&state.screens)
}

// Leaves the station mode, giving the browser back the filter it had
// before (Back, the pause menu's Resume, the station gone). Nothing
// outside the mode.
close_station_recipes :: proc(browser: ^Recipe_Browser) {
	if browser.station == NO_ENTITY {
		return
	}
	browser.filter = browser.filter_before_station
	browser.station = NO_ENTITY
}

// The station whose panel the browser is, with its machine; ok is false
// outside the station mode or once the station is gone.
browser_station_machine :: proc(screen_context: Screen_Context) -> (machine: Machine, ok: bool) {
	common := entity_common(&screen_context.world.entities, screen_context.views.recipe_browser.station)
	if common == nil || int(common.machine) >= len(screen_context.machines.machines) {
		return {}, false
	}
	machine = screen_context.machines.machines[common.machine]
	return machine, machine_is_crafting_station(machine)
}

// Opens the browser in the selection mode for an assembler.
open_recipe_selection :: proc(state: ^Ui_State, browser: ^Recipe_Browser, assembler: Entity_Handle) {
	browser.selecting_for = assembler
	browser.filter.tags = {}
	push_screen(&state.screens, .Recipes)
}

// The first two columns of a filter, list and detail screen: their
// widths, or their share of a narrow panel.
three_column_widths :: proc(content: Ui_Rectangle, filter_width, list_width: f32) -> (filter, list: f32) {
	return min(filter_width, content.width * FILTER_COLUMN_FRACTION), min(list_width, content.width * LIST_COLUMN_FRACTION)
}

recipe_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	browser := &screen_context.views.recipe_browser
	selecting := browser.selecting_for != NO_ENTITY
	station, at_station := browser_station_machine(screen_context)
	// The station vanished under its browser: close the browser, the
	// machine screen under it closes next.
	if browser.station != NO_ENTITY && !at_station {
		close_station_recipes(browser)
		pop_screen(&state.screens)
		return
	}
	at_station = at_station && !selecting
	makers := screen_craft_makers(screen_context)
	refresh_craftable_recipes(&browser.plans, screen_context.recipes, screen_context.unlocks^, screen_context.player.inventory, screen_context.player.crafting, makers, screen_context.free_crafting)
	craftable := browser.plans.craftable[:]
	ui_backdrop(state)
	panel := ui_panel_area(state)
	ui_panel_begin(state, "recipes", panel)
	content := inset(panel, UI_PADDING)
	if !selecting && !at_station {
		inventory_tabs(state, cut_top(&content, UI_ROW_HEIGHT))
		cut_top(&content, UI_GAP)
	}
	title := text(selecting ? "recipes_choose_title" : "recipes_title")
	if at_station {
		title = text(station.name_key)
	}
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), title, UI_HEADING_TEXT_SIZE, .Centre)
	shown := at_station ? station_categories(screen_context.recipes, station.recipe_maker) : ~Recipe_Categories{}
	recipe_category_tabs(state, cut_top(&content, UI_ROW_HEIGHT), browser, shown)
	cut_top(&content, UI_GAP)
	filter_width, list_width := three_column_widths(content, RECIPE_FILTER_COLUMN_WIDTH, RECIPE_LIST_COLUMN_WIDTH)
	recipe_filter_column(state, cut_left(&content, filter_width), screen_context)
	cut_left(&content, 2 * UI_PADDING)
	list_area := cut_left(&content, list_width)
	cut_left(&content, 2 * UI_PADDING)
	filter := browser.filter
	switch {
	case selecting:
		filter = selection_filter(browser.filter, .Assembler)
	case at_station:
		filter = station_filter(browser.filter, station.recipe_maker)
	}
	visible := filter_recipes(screen_context.recipes, screen_context.recipe_order, filter, craftable, screen_context.unlocks.available, context.temp_allocator)
	list_id := ui_id(state, "recipe_list")
	letter := letter_input(state, &browser.letter_radial)
	activated, list_focused := recipe_list(state, list_area, screen_context, visible, craftable)
	reached := recipe_detail_panel(state, content, screen_context, craftable)
	ui_panel_end(state)
	// Before the focus settles: a focus on the row's button belongs to
	// the screen, so the selection stays.
	touch := touch_row_shows(state)
	button := touch ? ui_touch_row(state, recipe_touch_buttons(selecting)) : .None
	// On touch a tap on a row selects the recipe; the row's buttons commit.
	if activated != NO_RECIPE && tap_selects_only(state) {
		focus_recipe_row(state, browser, list_id, activated)
		activated = NO_RECIPE
	}
	settle_recipe_focus(state, browser, list_id, visible)
	if position := recipe_position_for_letter(screen_context.recipe_names, visible, letter); letter != 0 && position >= 0 {
		focus_recipe_row(state, browser, list_id, visible[position])
	}
	if reached != NO_RECIPE {
		navigate_to_recipe(browser, screen_context.recipes, screen_context.unlocks^, reached, craftable)
	}
	draw_letter_wheel(state, browser.letter_radial)
	// The row acts on the selected recipe only while the list shows it.
	selected_shown := slice.contains(visible, browser.focused_recipe)
	if selecting {
		if button == .Choose_Recipe && selected_shown {
			activated = browser.focused_recipe
		}
		if activated != NO_RECIPE {
			choose_assembler_recipe(state, screen_context, activated)
		}
		if !touch {
			recipe_selection_glyph_bar(state)
		}
		return
	}
	apply_recipe_craft_input(state, screen_context, activated, list_focused, selected_shown, button)
	if !touch {
		recipe_glyph_bar(state)
	}
}

// The touch row (0137): what the glyphs name, on the selected recipe.
recipe_touch_buttons :: proc(selecting: bool) -> Touch_Buttons {
	if selecting {
		return {.Choose_Recipe, .Back}
	}
	return {.Craft, .Craft_Five, .Cancel_Craft, .Back}
}

recipe_selection_glyph_bar :: proc(state: ^Ui_State) {
	hints := [?]Glyph_Hint{{.Confirm, text("hint_choose_recipe")}, {.Back, text("hint_back")}}
	ui_glyph_bar(state, hints[:])
}

recipe_glyph_bar :: proc(state: ^Ui_State) {
	hints := [?]Glyph_Hint {
		{.Confirm, text("hint_craft")},
		{.Context_Action, text("hint_craft_five")},
		{.Secondary, text("hint_cancel_craft")},
		{.Tab_Previous, ""},
		{.Tab_Next, text("hint_tabs")},
		{.Back, text("hint_close")},
	}
	ui_glyph_bar(state, hints[:])
}
