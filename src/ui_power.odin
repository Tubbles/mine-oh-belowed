package game

import "core:fmt"
import "core:slice"

// The power overview screen, the power lines of machine panels, the
// panels of poles, power switches and lamps, and the HUD brownout
// warning. Energy is kept in joules per tick and shown as power.

POWER_AREA_WIDTH :: 480
POWER_LIST_COLUMN_WIDTH :: 560
POWER_LIST_COLUMN_FRACTION :: 0.4
POWER_OVERVIEW_WIDTH :: 1400
POWER_TOP_CONSUMER_COUNT :: 5
POWER_GENERATOR_TYPE_COUNT :: 3
// Network, supply, demand, satisfaction, the generators' heading and its
// lines, the consumers' heading and its lines.
POWER_DETAIL_ROWS :: 6 + POWER_GENERATOR_TYPE_COUNT + POWER_TOP_CONSUMER_COUNT

// Joules per tick as kW.
joules_per_tick_kilowatts :: proc(joules: u64, tick_rate: int) -> f32 {
	return f32(joules) * f32(tick_rate) / 1000
}

format_joules_per_tick :: proc(joules: u64, tick_rate: int) -> string {
	return format_power(joules_per_tick_kilowatts(joules, tick_rate))
}

format_satisfaction :: proc(satisfaction: u32) -> string {
	return fmt.tprintf("%d%%", satisfaction / 10)
}

network_name :: proc(network: int) -> string {
	return fmt.tprintf("%s %d", text("power_network"), network + 1)
}

// "No power" outside every network, the network's satisfaction otherwise.
power_status_line :: proc(networks: ^Electric_Networks, handle: Entity_Handle) -> string {
	network := entity_network(networks, handle)
	if network < 0 || network >= len(networks.networks) {
		return text("power_no_network")
	}
	return fmt.tprintf("%s: %s", text("power_satisfaction"), format_satisfaction(networks.networks[network].satisfaction))
}

// A generator's output over the last tick.
generator_output_line :: proc(engine: Fluid_Machine, tick_rate: int) -> string {
	return fmt.tprintf("%s: %s", text("power_output"), format_joules_per_tick(u64(engine.generated_joules), tick_rate))
}

// The rows a pole, switch or lamp panel shows under its name.
power_machine_rows :: proc(kind: Machine_Kind) -> int {
	#partial switch kind {
	case .Power_Switch:
		return 3
	}
	return 2
}

power_area_size :: proc(machine: Machine) -> [2]f32 {
	return {POWER_AREA_WIDTH, UI_ROW_HEIGHT + f32(power_machine_rows(machine.kind)) * (UI_ROW_HEIGHT + UI_GAP)}
}

// A pole: its network and that network's satisfaction. A switch: the
// same plus its state and a button that turns it. A lamp: its power and
// whether it shines.
power_panel_region :: proc(state: ^Ui_State, area: Ui_Rectangle, handle: Entity_Handle, screen_context: Screen_Context) {
	content := area
	entities := &screen_context.world.entities
	networks := &entities.electric_networks
	if lamp := pool_get(&entities.lamps, handle); lamp != nil {
		draw_text_fitted(state, cut_row(&content), power_status_line(networks, handle), UI_BODY_TEXT_SIZE, .Left)
		draw_text_fitted(state, cut_row(&content), text(lamp.lit ? "lamp_lit" : "lamp_dark"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
		return
	}
	pole := pool_get(&entities.poles, handle)
	if pole == nil {
		return
	}
	network := entity_network(networks, handle)
	draw_text_fitted(state, cut_row(&content), network < 0 ? text("power_switch_open") : network_name(network), UI_BODY_TEXT_SIZE, .Left)
	draw_text_fitted(state, cut_row(&content), power_status_line(networks, handle), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	if screen_context.machines.machines[pole.machine].kind != .Power_Switch {
		return
	}
	value := text(pole.on ? "power_switch_on" : "power_switch_off")
	if ui_choice(state, cut_row(&content), text("power_switch_state"), value) {
		toggle_power_switch(entities, screen_context.machines, handle)
	}
}

// The HUD line for a pole (its network), a switch (on or off) or a lamp.
power_entity_status_text :: proc(world: ^World, machines: Machine_Registry, handle: Entity_Handle, name: string) -> string {
	entities := &world.entities
	if lamp := pool_get(&entities.lamps, handle); lamp != nil {
		return fmt.tprintf("%s  %s", name, text(lamp.lit ? "lamp_lit" : "lamp_dark"))
	}
	pole := pool_get(&entities.poles, handle)
	if pole == nil {
		return name
	}
	if machines.machines[pole.machine].kind == .Power_Switch {
		return fmt.tprintf("%s  %s", name, text(pole.on ? "power_switch_on" : "power_switch_off"))
	}
	return fmt.tprintf("%s  %s", name, network_name(entity_network(&entities.electric_networks, handle)))
}

// Consumers or generators of one machine type in a network, for the
// overview: joules is the consumers' demand or the generators' output in
// the last tick.
Participant_Group :: struct {
	machine: Machine_Id,
	count:   int,
	joules:  u64,
}

// What a participant adds to its group: a consumer's demand, a
// generator's delivered energy.
participant_group_joules :: proc(participant: Electric_Participant) -> u64 {
	return participant.generator ? participant.delivered : participant.offered
}

// The consumers (or the generators) of a network grouped by machine,
// largest first (ties by machine id), at most `limit`. In the temp
// allocator.
largest_participant_groups :: proc(participants: []Electric_Participant, network: int, generators: bool, limit: int) -> []Participant_Group {
	groups := make([dynamic]Participant_Group, context.temp_allocator)
	for participant in participants {
		if participant.network != network || participant.generator != generators {
			continue
		}
		index := participant_group_index(groups[:], participant.machine)
		if index < 0 {
			append(&groups, Participant_Group{machine = participant.machine})
			index = len(groups) - 1
		}
		groups[index].count += 1
		groups[index].joules += participant_group_joules(participant)
	}
	slice.sort_by(groups[:], proc(first, second: Participant_Group) -> bool {
		if first.joules != second.joules {
			return first.joules > second.joules
		}
		return first.machine < second.machine
	})
	return groups[:min(limit, len(groups))]
}

participant_group_index :: proc(groups: []Participant_Group, machine: Machine_Id) -> int {
	for group, index in groups {
		if group.machine == machine {
			return index
		}
	}
	return -1
}

// Opened with Open_Power_Overview or from the pause menu, and does not
// pause: the network list on the left, the focused network on the right.
power_overview_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	ui_backdrop(state)
	area := ui_panel_area(state)
	panel := fitted_panel(area, POWER_OVERVIEW_WIDTH, panel_height(1, f32(POWER_DETAIL_ROWS) * UI_LINE_HEIGHT))
	ui_panel_begin(state, "power", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("power_overview_title"), UI_HEADING_TEXT_SIZE, .Centre)
	cut_top(&content, UI_GAP)
	power_overview_body(state, content, screen_context)
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Back, text("hint_close")}}
	ui_glyph_bar_or_back_row(state, hints[:])
}

// The network list and the focused network's detail, also the Power tab
// of the statistics screen.
power_overview_body :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	content := area
	networks := &screen_context.world.entities.electric_networks
	if len(networks.networks) == 0 {
		detail_line(state, &content, text("power_no_networks"), UI_DIM_TEXT_COLOR)
		return
	}
	list_area := cut_left(&content, min(f32(POWER_LIST_COLUMN_WIDTH), content.width * POWER_LIST_COLUMN_FRACTION))
	cut_left(&content, 2 * UI_PADDING)
	focused := power_network_list(state, list_area, networks)
	power_network_detail(state, content, screen_context, max(focused, 0))
}

// Returns the focused network, or -1.
power_network_list :: proc(state: ^Ui_State, area: Ui_Rectangle, networks: ^Electric_Networks) -> int {
	focused := -1
	list := scroll_list_begin(state, "power_networks", area, len(networks.networks))
	for network, index in networks.networks {
		row := scroll_list_row(list, index)
		id := ui_id(state, "network", index)
		interaction := ui_interact(state, id, row)
		if interaction.focused {
			scroll_list_keep_visible(&list, index)
			focused = index
		}
		widget_background(state, row, id, interaction)
		color := network_is_in_brownout(network) ? UI_ACCENT_COLOR : UI_TEXT_COLOR
		row_content := inset(row, UI_PADDING)
		draw_text(state, row_content, format_satisfaction(network.satisfaction), UI_BODY_TEXT_SIZE, .Right, color)
		draw_text(state, row_content, network_name(index), UI_BODY_TEXT_SIZE, .Left, color)
	}
	scroll_list_end(state, &list)
	return focused
}

power_network_detail :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context, index: int) {
	content := area
	networks := &screen_context.world.entities.electric_networks
	network := networks.networks[index]
	tick_rate := screen_context.tick_rate
	detail_line(state, &content, network_name(index), UI_ACCENT_COLOR, UI_LINE_HEIGHT)
	detail_line(state, &content, fmt.tprintf("%s: %s", text("power_supply"), format_joules_per_tick(network.supply, tick_rate)), UI_TEXT_COLOR, UI_LINE_HEIGHT)
	detail_line(state, &content, fmt.tprintf("%s: %s", text("power_demand"), format_joules_per_tick(network.demand, tick_rate)), UI_TEXT_COLOR, UI_LINE_HEIGHT)
	detail_line(state, &content, fmt.tprintf("%s: %s", text("power_satisfaction"), format_satisfaction(network.satisfaction)), UI_TEXT_COLOR, UI_LINE_HEIGHT)
	detail_line(state, &content, fmt.tprintf("%s: %d", text("power_generators"), network.generator_count), UI_DIM_TEXT_COLOR, UI_LINE_HEIGHT)
	participant_group_lines(state, &content, screen_context, index, true, POWER_GENERATOR_TYPE_COUNT)
	detail_line(state, &content, text("power_largest_consumers"), UI_DIM_TEXT_COLOR, UI_LINE_HEIGHT)
	participant_group_lines(state, &content, screen_context, index, false, POWER_TOP_CONSUMER_COUNT)
}

participant_group_lines :: proc(state: ^Ui_State, content: ^Ui_Rectangle, screen_context: Screen_Context, network: int, generators: bool, limit: int) {
	participants := screen_context.world.entities.electric_networks.participants[:]
	for group in largest_participant_groups(participants, network, generators, limit) {
		name := machine_name(screen_context.machines, group.machine)
		detail_line(state, content, fmt.tprintf("%s x%d  %s", name, group.count, format_joules_per_tick(group.joules, screen_context.tick_rate)), UI_TEXT_COLOR, UI_LINE_HEIGHT)
	}
}

// Top centre while any network is short of power.
draw_brownout_warning :: proc(state: ^Ui_State, world: ^World) {
	if !any_network_in_brownout(&world.entities.electric_networks) {
		return
	}
	safe := ui_safe_area(state)
	draw_text(state, {safe.x, safe.y + UI_ROW_HEIGHT, safe.width, UI_ROW_HEIGHT}, text("power_brownout"), UI_BODY_TEXT_SIZE, .Centre, UI_ACCENT_COLOR)
}
