package game

import "core:fmt"
import "core:slice"

// The power overview screen, the power lines of machine panels, the
// panels of junction boxes, power switches and lamps, the cables' loads
// on them and on the HUD (0369), and the HUD brownout warning. Energy is
// kept in joules per tick and shown as power.

POWER_AREA_WIDTH :: 480
// A junction box's or switch's panel with a line per power port (0369).
POWER_PORT_AREA_WIDTH :: 640
POWER_LIST_COLUMN_WIDTH :: 560
POWER_LIST_COLUMN_FRACTION :: 0.4
POWER_OVERVIEW_WIDTH :: 1400
POWER_TOP_CONSUMER_COUNT :: 5
POWER_GENERATOR_TYPE_COUNT :: 3
// The lead and the nickel battery (0383).
POWER_BATTERY_TYPE_COUNT :: 2
// The limiting cables behind the largest shortfall (0369).
POWER_CABLE_ROWS :: 3
// Network, supply, demand, satisfaction, the limiting cables', the
// generators', the batteries' and the consumers' headings, each with its
// lines.
POWER_DETAIL_ROWS :: 8 + POWER_CABLE_ROWS + POWER_GENERATOR_TYPE_COUNT + POWER_BATTERY_TYPE_COUNT + POWER_TOP_CONSUMER_COUNT

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

// "No cable" when no power port of the entity has a cable (0368); a
// consumer's draw, what it received of what it asked in the last tick;
// else "No power" outside every network, the network's satisfaction
// otherwise.
power_status_line :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, tick_rate: int) -> string {
	if !entity_has_cable(entities, machines, handle) {
		return text("power_no_cable")
	}
	networks := &entities.electric_networks
	if participant, found := entity_participant(networks, handle); found && !participant.generator {
		line := replace_message_mark(text("power_draw"), "{delivered}", format_joules_per_tick(participant.delivered, tick_rate))
		return replace_message_mark(line, "{demand}", format_joules_per_tick(participant.offered, tick_rate))
	}
	network := entity_network(networks, handle)
	if network < 0 || network >= len(networks.networks) {
		return text("power_no_network")
	}
	return fmt.tprintf("%s: %s", text("power_satisfaction"), format_satisfaction(networks.networks[network].satisfaction))
}

// A power port of the entity has a cable.
entity_has_cable :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	common := entity_common(entities, handle)
	if common == nil {
		return false
	}
	machine := machines.machines[common.machine]
	for port in 0 ..< machine.port_count {
		if machine_port_is_power(machine, port) && port_end_cable(&entities.cables, Port_End{entity = handle, port = u8(port)}) >= 0 {
			return true
		}
	}
	return false
}

// The last tick's participant on the entity's node.
entity_participant :: proc(networks: ^Electric_Networks, handle: Entity_Handle) -> (participant: Electric_Participant, found: bool) {
	node, has_node := networks.node_of_entity[handle]
	if !has_node || int(node) >= len(networks.participant_of_node) {
		return {}, false
	}
	index := networks.participant_of_node[node]
	if index < 0 || int(index) >= len(networks.participants) || networks.participants[index].handle != handle {
		return {}, false
	}
	return networks.participants[index], true
}

// A generator's output over the last tick.
generator_output_line :: proc(engine: Fluid_Machine, tick_rate: int) -> string {
	return fmt.tprintf("%s: %s", text("power_output"), format_joules_per_tick(u64(engine.generated_joules), tick_rate))
}

// The rows a junction box, switch or lamp panel shows under its name.
power_machine_rows :: proc(kind: Machine_Kind) -> int {
	#partial switch kind {
	case .Power_Switch:
		return 3
	}
	return 2
}

// A junction box's, cabinet's or switch's power ports, a line each on its
// panel (0369); a lamp's draw line is its cable's load, so it has none.
power_port_line_count :: proc(machine: Machine) -> int {
	if machine.kind != .Junction_Box && machine.kind != .Power_Switch {
		return 0
	}
	return machine_power_port_count(machine)
}

power_area_size :: proc(machine: Machine) -> [2]f32 {
	port_lines := power_port_line_count(machine)
	width := f32(port_lines > 0 ? POWER_PORT_AREA_WIDTH : POWER_AREA_WIDTH)
	return {width, UI_ROW_HEIGHT + f32(power_machine_rows(machine.kind)) * (UI_ROW_HEIGHT + UI_GAP) + f32(port_lines) * UI_LINE_HEIGHT}
}

// A junction box: its network and that network's satisfaction, or no
// cable. A switch: the same plus its state and a button that turns it.
// Both then a line per power port (0369). A lamp: its draw and whether
// it shines.
power_panel_region :: proc(state: ^Ui_State, area: Ui_Rectangle, handle: Entity_Handle, screen_context: Screen_Context) {
	content := area
	entities := &screen_context.world.entities
	networks := &entities.electric_networks
	if lamp := pool_get(&entities.lamps, handle); lamp != nil {
		draw_text_fitted(state, cut_row(&content), power_status_line(entities, screen_context.machines, handle, screen_context.tick_rate), UI_BODY_TEXT_SIZE, .Left)
		draw_text_fitted(state, cut_row(&content), text(lamp.lit ? "lamp_lit" : "lamp_dark"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
		return
	}
	pole := pool_get(&entities.poles, handle)
	if pole == nil {
		return
	}
	network := entity_network(networks, handle)
	draw_text_fitted(state, cut_row(&content), network < 0 ? text("power_switch_open") : network_name(network), UI_BODY_TEXT_SIZE, .Left)
	draw_text_fitted(state, cut_row(&content), power_status_line(entities, screen_context.machines, handle, screen_context.tick_rate), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	if screen_context.machines.machines[pole.machine].kind == .Power_Switch {
		value := text(pole.on ? "power_switch_on" : "power_switch_off")
		if ui_choice(state, cut_row(&content), text("power_switch_state"), value) {
			queue_player_command(screen_context.player_commands, screen_context.player_index, Power_Switch_Command{switch_handle = handle})
		}
	}
	power_port_lines(state, &content, screen_context, handle)
}

// A line per power port in port order: dim while free, in the accent
// colour while its cable limits, else in the text colour.
power_port_lines :: proc(state: ^Ui_State, content: ^Ui_Rectangle, screen_context: Screen_Context, handle: Entity_Handle) {
	entities := &screen_context.world.entities
	common := entity_common(entities, handle)
	if common == nil {
		return
	}
	machine := screen_context.machines.machines[common.machine]
	for port in 0 ..< machine.port_count {
		if !machine_port_is_power(machine, port) {
			continue
		}
		line, cabled, limits := power_port_text(entities, screen_context.machines, screen_context.items, {handle, u8(port)}, screen_context.tick_rate)
		color := limits ? UI_ACCENT_COLOR : (cabled ? UI_TEXT_COLOR : UI_DIM_TEXT_COLOR)
		detail_line(state, content, line, color, UI_LINE_HEIGHT)
	}
}

// "Port b, limiting: 300.0 kW of 300.0 kW, Light cable to Junction box":
// the word after the port letter while the cable limits, "to" where power
// leaves the port or nothing flows, "from" where it enters; without a load
// the cable and its peer; "free" without a cable.
power_port_text :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, end: Port_End, tick_rate: int) -> (line: string, cabled, limits: bool) {
	port_id := machines.machines[entity_common(entities, end.entity).machine].ports[end.port].id
	index := port_end_cable(&entities.cables, end)
	if index < 0 {
		return replace_message_mark(text("power_port_free"), "{port}", port_id), false, false
	}
	cable := entities.cables.cables[index]
	template := "power_port_cable"
	load, found := cable_load(&entities.electric_networks, &entities.cables, index)
	if found {
		entering := load.joules_per_tick > 0 && cable.ends[load.source_end] != end
		template = entering ? "power_port_in" : "power_port_out"
		if load.limits {
			template = entering ? "power_port_in_limiting" : "power_port_out_limiting"
		}
	}
	peer := cable.ends[0] == end ? cable.ends[1] : cable.ends[0]
	line = replace_message_mark(text(template), "{port}", port_id)
	line = replace_message_mark(line, "{cable}", item_name(items, cable.item))
	line = replace_message_mark(line, "{peer}", port_end_machine_name(entities, machines, peer))
	return with_cable_load(line, load, tick_rate), true, found && load.limits
}

// The machine's name at a cable's end, empty for an entity that is gone.
port_end_machine_name :: proc(entities: ^Entities, machines: Machine_Registry, end: Port_End) -> string {
	common := entity_common(entities, end.entity)
	return common == nil ? "" : machine_name(machines, common.machine)
}

// {load} the cable's share, {capacity} its watts, {limiting} the word
// while it limits (data/strings/en.sjson, power_cable_load only).
with_cable_load :: proc(template: string, load: Cable_Load, tick_rate: int) -> string {
	line := replace_message_mark(template, "{load}", format_joules_per_tick(load.joules_per_tick, tick_rate))
	line = replace_message_mark(line, "{capacity}", format_power(f32(load.watts) / 1000))
	return replace_message_mark(line, "{limiting}", load.limits ? fmt.tprintf(", %s", text("power_cable_limiting")) : "")
}

// The HUD line for a junction box (its network), a switch (on or off) or
// a lamp.
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
	network := entity_network(&entities.electric_networks, handle)
	return fmt.tprintf("%s  %s", name, network < 0 ? text("power_switch_open") : network_name(network))
}

// The overview's three lists: a battery (0383) is a generator that is
// also a store, listed apart from the generators.
Participant_Side :: enum {
	Consumers,
	Generators,
	Batteries,
}

participant_side :: proc(participant: Electric_Participant) -> Participant_Side {
	switch {
	case participant.store:
		return .Batteries
	case participant.generator:
		return .Generators
	}
	return .Consumers
}

// Consumers, generators or batteries of one machine type in a network,
// for the overview: joules is the consumers' demand or what the
// generators and batteries gave in the last tick, taken what the
// batteries took.
Participant_Group :: struct {
	machine: Machine_Id,
	count:   int,
	joules:  u64,
	taken:   u64,
}

// What a participant adds to its group: a consumer's demand, a
// generator's or battery's delivered energy.
participant_group_joules :: proc(participant: Electric_Participant) -> u64 {
	return participant.generator ? participant.delivered : participant.offered
}

// One side of a network grouped by machine, largest first (what was given
// and taken, ties by machine id), at most `limit`. In the temp allocator.
largest_participant_groups :: proc(participants: []Electric_Participant, network: int, side: Participant_Side, limit: int) -> []Participant_Group {
	groups := make([dynamic]Participant_Group, context.temp_allocator)
	for participant in participants {
		if participant.network != network || participant_side(participant) != side {
			continue
		}
		index := participant_group_index(groups[:], participant.machine)
		if index < 0 {
			append(&groups, Participant_Group{machine = participant.machine})
			index = len(groups) - 1
		}
		groups[index].count += 1
		groups[index].joules += participant_group_joules(participant)
		groups[index].taken += participant.charged
	}
	slice.sort_by(groups[:], proc(first, second: Participant_Group) -> bool {
		if first.joules + first.taken != second.joules + second.taken {
			return first.joules + first.taken > second.joules + second.taken
		}
		return first.machine < second.machine
	})
	return groups[:min(limit, len(groups))]
}

// A group's power: what it gave, and what batteries took with a plus,
// as "+31 W"; what it gave when it neither gave nor took.
participant_group_power_text :: proc(group: Participant_Group, tick_rate: int) -> string {
	switch {
	case group.taken == 0:
		return format_joules_per_tick(group.joules, tick_rate)
	case group.joules == 0:
		return fmt.tprintf("+%s", format_joules_per_tick(group.taken, tick_rate))
	}
	return fmt.tprintf("%s  +%s", format_joules_per_tick(group.joules, tick_rate), format_joules_per_tick(group.taken, tick_rate))
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
// The window carousel's seventh window (0385).
power_overview_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	ui_backdrop(state)
	area := ui_panel_area(state)
	panel := fitted_panel(area, POWER_OVERVIEW_WIDTH, panel_height(1, f32(POWER_DETAIL_ROWS) * UI_LINE_HEIGHT))
	ui_panel_begin(state, "power", panel)
	content := inset(panel, UI_PADDING)
	ui_window_title_row(state, cut_top(&content, UI_ROW_HEIGHT))
	cut_top(&content, UI_GAP)
	power_overview_body(state, content, screen_context)
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Back, text("hint_close")}}
	ui_glyph_bar_or_back_row(state, hints[:])
}

// The network list and the focused network's detail.
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
	power_cable_lines(state, &content, screen_context, index)
	detail_line(state, &content, fmt.tprintf("%s: %d", text("power_generators"), network.generator_count), UI_DIM_TEXT_COLOR, UI_LINE_HEIGHT)
	participant_group_lines(state, &content, screen_context, index, .Generators, POWER_GENERATOR_TYPE_COUNT)
	detail_line(state, &content, fmt.tprintf("%s: %d", text("power_overview_batteries"), network.store_count), UI_DIM_TEXT_COLOR, UI_LINE_HEIGHT)
	participant_group_lines(state, &content, screen_context, index, .Batteries, POWER_BATTERY_TYPE_COUNT)
	detail_line(state, &content, text("power_largest_consumers"), UI_DIM_TEXT_COLOR, UI_LINE_HEIGHT)
	participant_group_lines(state, &content, screen_context, index, .Consumers, POWER_TOP_CONSUMER_COUNT)
}

// A limiting cable of a network and its load, for the overview (0369).
Network_Cable :: struct {
	index: int,
	load:  Cable_Load,
}

// The larger shortfall first, then the lower index.
cable_ranks_before :: proc(first, second: Network_Cable) -> bool {
	if first.load.shortfall != second.load.shortfall {
		return first.load.shortfall > second.load.shortfall
	}
	return first.index < second.index
}

// Keeps top in rank order and at most limit long.
insert_ranked_cable :: proc(top: ^[dynamic]Network_Cable, candidate: Network_Cable, limit: int) {
	position := len(top)
	for entry, index in top {
		if cable_ranks_before(candidate, entry) {
			position = index
			break
		}
	}
	if position >= limit {
		return
	}
	inject_at(top, position, candidate)
	if len(top) > limit {
		pop(top)
	}
}

// Every cable of the network that limits, counted, and the limit first
// in rank order; not found before the first balance after a rebuild. In
// the temp allocator.
network_limiting_cables :: proc(networks: ^Electric_Networks, table: ^Cable_Table, network, limit: int) -> (top: []Network_Cable, count: int, found: bool) {
	if !networks.balance_current {
		return nil, 0, false
	}
	ranked := make([dynamic]Network_Cable, 0, limit + 1, context.temp_allocator)
	for index in 0 ..< len(table.cables) {
		load, has_load := cable_load(networks, table, index)
		if has_load && load.network == network && load.limits {
			count += 1
			insert_ranked_cable(&ranked, {index, load}, limit)
		}
	}
	return ranked[:], count, true
}

// "Light cable, Junction box to Junction box: 300.0 kW of 300.0 kW", from
// the end power came from.
power_cable_text :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, cable: Network_Cable, tick_rate: int) -> string {
	ends := entities.cables.cables[cable.index].ends
	line := replace_message_mark(text("power_cable_line"), "{cable}", item_name(items, entities.cables.cables[cable.index].item))
	line = replace_message_mark(line, "{from}", port_end_machine_name(entities, machines, ends[cable.load.source_end]))
	line = replace_message_mark(line, "{to}", port_end_machine_name(entities, machines, ends[1 - cable.load.source_end]))
	return with_cable_load(line, cable.load, tick_rate)
}

// The HUD's line for an aimed cable: "Light cable: 300.0 kW of 300.0 kW",
// or the item's name without a load.
cable_status_text :: proc(entities: ^Entities, items: Item_Registry, index: int, tick_rate: int) -> (line: string, limits: bool) {
	name := item_name(items, entities.cables.cables[index].item)
	load, found := cable_load(&entities.electric_networks, &entities.cables, index)
	if !found {
		return name, false
	}
	return with_cable_load(replace_message_mark(text("power_cable_load"), "{cable}", name), load, tick_rate), load.limits
}

// "Limiting cables: N" dim, then the first POWER_CABLE_ROWS in the accent
// colour; nothing before the first balance after a rebuild.
power_cable_lines :: proc(state: ^Ui_State, content: ^Ui_Rectangle, screen_context: Screen_Context, network: int) {
	entities := &screen_context.world.entities
	top, count, found := network_limiting_cables(&entities.electric_networks, &entities.cables, network, POWER_CABLE_ROWS)
	if !found {
		return
	}
	detail_line(state, content, fmt.tprintf("%s: %d", text("power_limiting_cables"), count), UI_DIM_TEXT_COLOR, UI_LINE_HEIGHT)
	for cable in top {
		detail_line(state, content, power_cable_text(entities, screen_context.machines, screen_context.items, cable, screen_context.tick_rate), UI_ACCENT_COLOR, UI_LINE_HEIGHT)
	}
}

participant_group_lines :: proc(state: ^Ui_State, content: ^Ui_Rectangle, screen_context: Screen_Context, network: int, side: Participant_Side, limit: int) {
	participants := screen_context.world.entities.electric_networks.participants[:]
	for group in largest_participant_groups(participants, network, side, limit) {
		name := machine_name(screen_context.machines, group.machine)
		detail_line(state, content, fmt.tprintf("%s x%d  %s", name, group.count, participant_group_power_text(group, screen_context.tick_rate)), UI_TEXT_COLOR, UI_LINE_HEIGHT)
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
