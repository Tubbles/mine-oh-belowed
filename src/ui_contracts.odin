package game

import "core:fmt"
import "core:strings"

// The venture on screen (work item 0041): the launch pad panel's
// Contracts and Catalogue tabs, the journal's Contracts tab and the HUD
// line for the oldest open contract. The simulation side is venture.odin.

// "Electronic circuit 120 / 300"
contract_request_line :: proc(open: Open_Contract, contract: Contract, index: int, items: Item_Registry) -> string {
	request := contract.requests[index]
	delivered := min(open.delivered[index], u32(request.count))
	return fmt.tprintf("%s %d / %d", item_name(items, request.item), delivered, request.count)
}

// "Time left 12:30", or "Late" past the deadline.
contract_time_left_text :: proc(open: Open_Contract, contract: Contract, tick: u64, tick_rate: int) -> string {
	if contract_is_late(open, contract, tick, tick_rate) {
		return text("contract_late")
	}
	left := contract_deadline_tick(open, contract, tick_rate) - tick
	return fmt.tprintf("%s %s", text("contract_time_left"), format_game_time(left, tick_rate))
}

// "Reward: 60 × Silicon, 40 × Aluminium plate", or the survey.
contract_reward_text :: proc(contract: Contract, items: Item_Registry) -> string {
	if contract.orbital_survey {
		return fmt.tprintf("%s: %s", text("contract_reward"), text("contract_reward_survey"))
	}
	parts := make([dynamic]string, context.temp_allocator)
	rewards := contract.rewards
	for stack in rewards[:contract.reward_count] {
		append(&parts, stack_line(stack, items))
	}
	return fmt.tprintf("%s: %s", text("contract_reward"), strings.join(parts[:], ", ", context.temp_allocator))
}

// "Late share 50 %"
contract_late_share_text :: proc(contract: Contract) -> string {
	return fmt.tprintf("%s %d %%", text("contract_late_share"), contract.late_percent)
}

venture_credit_text :: proc(venture_credit: u64) -> string {
	return fmt.tprintf("%s: %d", text("venture_credit"), venture_credit)
}

// Name, requests with deliveries, time left, late share and reward.
draw_open_contract :: proc(state: ^Ui_State, content: ^Ui_Rectangle, open: Open_Contract, screen_context: Screen_Context) {
	contract := screen_context.contracts.contracts[open.contract]
	items := screen_context.items
	detail_line(state, content, text(contract.name_key), UI_ACCENT_COLOR)
	for index in 0 ..< contract.request_count {
		detail_line(state, content, contract_request_line(open, contract, index, items))
	}
	late := contract_is_late(open, contract, screen_context.tick, screen_context.tick_rate)
	detail_line(state, content, contract_time_left_text(open, contract, screen_context.tick, screen_context.tick_rate), late ? UI_ACCENT_COLOR : UI_DIM_TEXT_COLOR)
	detail_line(state, content, contract_late_share_text(contract), UI_DIM_TEXT_COLOR)
	detail_line(state, content, contract_reward_text(contract, items), UI_DIM_TEXT_COLOR)
	cut_top(content, UI_GAP)
}

// The open contracts, oldest first, as many as fit.
draw_open_contracts :: proc(state: ^Ui_State, content: ^Ui_Rectangle, screen_context: Screen_Context) {
	records := screen_context.records
	if records.contracts.open_count == 0 {
		started := venture_started(records.statistics, screen_context.machines)
		detail_line(state, content, text(started ? "contracts_none_open" : "contracts_not_started"), UI_DIM_TEXT_COLOR)
		return
	}
	for open in open_contracts(&records.contracts) {
		contract := screen_context.contracts.contracts[open.contract]
		if content.height < f32(contract.request_count + 4) * UI_ROW_HEIGHT {
			return
		}
		draw_open_contract(state, content, open, screen_context)
	}
}

// The pad panel's Contracts tab.
launch_pad_contracts_tab :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	content := area
	detail_line(state, &content, venture_credit_text(screen_context.records.venture_credit))
	draw_open_contracts(state, &content, screen_context)
}

// "50 × Silicon  600 credit"
catalogue_entry_label :: proc(entry: Catalogue_Entry, items: Item_Registry) -> string {
	name := entry.orbital_survey ? text(CATALOGUE_SURVEY_NAME_KEY) : stack_line(Item_Stack{item = entry.item, count = entry.count}, items)
	return fmt.tprintf("%s  %d %s", name, entry.price, text("catalogue_price"))
}

// The pad panel's Catalogue tab: a button per entry; an order the credit
// does not cover is refused with a toast.
launch_pad_catalogue_tab :: proc(state: ^Ui_State, area: Ui_Rectangle, pad: ^Launch_Pad, screen_context: Screen_Context) {
	content := area
	records := screen_context.records
	detail_line(state, &content, venture_credit_text(records.venture_credit))
	for entry, index in screen_context.contracts.catalogue {
		ui_push_id(state, "catalogue", index)
		clicked := ui_button(state, cut_row(&content), catalogue_entry_label(entry, screen_context.items))
		ui_pop_id(state)
		if clicked && !order_from_catalogue(records, screen_context.contracts, index, launch_pad_centre(pad^)) {
			ui_toast(state, text("catalogue_not_enough_credit"))
		}
	}
}

// The journal's Contracts tab: credit, the tally, the open contracts.
journal_contracts_section :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	content := area
	statistics := screen_context.records.statistics
	detail_line(state, &content, venture_credit_text(screen_context.records.venture_credit))
	tally := fmt.tprintf("%s: %d, %d %s", text("contracts_completed"), statistics.contracts_completed, statistics.contracts_late, text("contracts_completed_late"))
	detail_line(state, &content, tally, UI_DIM_TEXT_COLOR)
	cut_top(&content, UI_GAP)
	draw_open_contracts(state, &content, screen_context)
}

// The HUD objective line for the oldest open contract: its name, then
// its requests and time left on one line. found is false without an open
// contract. Chapter 8 (work item 0042) shows it once every quest is done.
contract_objective_lines :: proc(contracts: Contract_State, registry: Contract_Registry, items: Item_Registry, tick: u64, tick_rate: int) -> (title, detail: string, found: bool) {
	if contracts.open_count == 0 {
		return "", "", false
	}
	open := contracts.open[0]
	contract := registry.contracts[open.contract]
	parts := make([dynamic]string, context.temp_allocator)
	for index in 0 ..< contract.request_count {
		append(&parts, contract_request_line(open, contract, index, items))
	}
	append(&parts, contract_time_left_text(open, contract, tick, tick_rate))
	return text(contract.name_key), strings.join(parts[:], "  ", context.temp_allocator), true
}
