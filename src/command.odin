package game

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// The command protocol (work item 0053, doc/commands.md): the lines the
// command socket (command_socket.odin) receives, parsed and executed on
// the main thread between two ticks. A line is words separated by spaces;
// a word in double quotes may hold spaces (\" and \\ inside), # starts a
// comment, an empty line is skipped. Every command answers ok, with text
// for queries, or error with the reason.
//
// Commands that change the simulation go through serve_developer_request
// (developer.odin), the path the Developer screen's requests take at the
// start of a tick, served here at once so the answer can say what
// happened. The frame loop owns what the simulation cannot do itself:
// running ticks fast (tick), holding them (pause), saving and screenshots;
// those commands set Command_Control, which the loop reads.

// The most ticks one tick command runs: a little over four and a half
// hours of game time at 60 ticks per second.
MAXIMUM_COMMAND_TICKS :: 1_000_000
DEFAULT_VEIN_QUERY_RADIUS :: 64
DEFAULT_ENTITY_QUERY_RADIUS :: 32
MAXIMUM_QUERY_RADIUS :: 4096
SCREENSHOT_DIRECTORY_NAME :: "screenshots"
MAXIMUM_SCREENSHOT_NAME_LENGTH :: 64

// What the commands ask of the frame loop. screenshot_path is owned
// (context.allocator); the loop captures the frame and clears it.
Command_Control :: struct {
	paused:          bool,
	// Ticks still to run fast, and how many the tick command asked for.
	pending_ticks:   int,
	requested_ticks: int,
	// The tick command waits for its answer until pending_ticks is 0.
	ticks_waiting:   bool,
	screenshot_path: string,
}

// simulation is nil without a world. content has the world's generator
// and technologies (frame_simulation_content).
Command_Context :: struct {
	simulation:           ^Simulation_State,
	content:              Simulation_Content,
	control:              ^Command_Control,
	// $XDG_STATE_HOME/mine-oh-belowed/screenshots, empty when unknown.
	screenshot_directory: string,
	// For a screenshot's default name.
	now:                  time.Time,
	// The session's forced weather kind (work item 0063), nil without a
	// world. Render only, so it is set here and not through a developer
	// request, and never saved.
	weather_override:     ^Maybe(Weather_Kind),
}

// text may hold several lines. deferred: the tick command answers once
// its ticks ran (finish_command_ticks).
Command_Response :: struct {
	ok:       bool,
	text:     string,
	deferred: bool,
}

Command_Usage :: struct {
	usage:   string,
	summary: string,
}

@(rodata)
command_usages := [?]Command_Usage {
	{"help", "list the commands"},
	{"give <item> <count>", "items into the inventory, the rest into the drop capsule"},
	{"take <item> <count>", "items out of the inventory"},
	{"kit <chapter>", "the chapter's developer kit (data/dev_kits.sjson)"},
	{"chapter <n>", "complete the quests before chapter n with their rewards"},
	{"quest finish", "complete the active quest with its rewards"},
	{"research <technology>", "mark researched, or one more level of an infinite technology"},
	{"unlock_all", "every recipe and technology"},
	{"teleport <x> <y> <z> | teleport pad", "feet into the block, or onto the landing pad"},
	{"time <dawn|noon|dusk|midnight>", "set the time of day"},
	{"weather <clear|overcast|rain|fog|auto>", "force a weather kind for screenshots, auto returns to the schedule"},
	{"fly <on|off>", "fly mode"},
	{"cheat_speed <on|off>", "fast movement and hand mining"},
	{"vein <type> <x> <z> [size_class]", "a new surface vein centred on the column"},
	{"place <machine> <x> <y> <z> <rotation>", "a machine by its minimum corner, by the player's rules, no item taken"},
	{"remove <x> <y> <z>", "the entity or block there, contents discarded"},
	{"block <block> <x> <y> <z>", "set a block"},
	{"insert <item> <count> <x> <y> <z>", "items into the entity there, as an inserter would"},
	{"blueprint <path>", "run the place, block, remove and insert commands of an SJSON file"},
	{"tick <n>", "run n ticks as fast as possible, answer when done"},
	{"pause | resume", "hold or release the simulation"},
	{"save", "save the world"},
	{"reload", "reload the content tables into the running world"},
	{"screenshot [name]", "a PNG of the next frame, the answer names the path"},
	{"query player|world|quests|contracts", "state as key value lines"},
	{"query veins [radius] | query entities [kind] [radius] | query stats <item>", "state around the player, or of an item"},
}

command_ok :: proc(format: string, arguments: ..any) -> Command_Response {
	return Command_Response{ok = true, text = fmt.tprintf(format, ..arguments)}
}

command_error :: proc(format: string, arguments: ..any) -> Command_Response {
	return Command_Response{ok = false, text = fmt.tprintf(format, ..arguments)}
}

// "ok[ text]" or "error text", the text's further lines, then a line
// holding only ".". In the temp allocator.
format_command_response :: proc(response: Command_Response) -> string {
	status := response.ok ? "ok" : "error"
	if response.text == "" {
		return fmt.tprintf("%s\n.\n", status)
	}
	return fmt.tprintf("%s %s\n.\n", status, response.text)
}

// Words.

// Splits a line into words; quoted words keep their spaces. In the temp
// allocator.
split_command_words :: proc(line: string) -> (words: []string, problem: string) {
	result := make([dynamic]string, context.temp_allocator)
	index := 0
	for index < len(line) {
		character := line[index]
		switch {
		case character == ' ' || character == '\t' || character == '\r':
			index += 1
		case character == '#':
			return result[:], ""
		case character == '"':
			word, next, quote_problem := read_quoted_word(line, index + 1)
			if quote_problem != "" {
				return nil, quote_problem
			}
			append(&result, word)
			index = next
		case:
			start := index
			for index < len(line) && !strings.contains_rune(" \t\r#\"", rune(line[index])) {
				index += 1
			}
			append(&result, line[start:index])
		}
	}
	return result[:], ""
}

// From just past the opening quote: the word and the index past the
// closing quote, which must end the word.
read_quoted_word :: proc(line: string, start: int) -> (word: string, next: int, problem: string) {
	builder := strings.builder_make(context.temp_allocator)
	index := start
	for index < len(line) {
		character := line[index]
		switch {
		case character == '\\' && index + 1 < len(line) && (line[index + 1] == '"' || line[index + 1] == '\\'):
			strings.write_byte(&builder, line[index + 1])
			index += 2
		case character == '"':
			if index + 1 < len(line) && !strings.contains_rune(" \t\r#", rune(line[index + 1])) {
				return "", 0, "a quoted word must end at a space"
			}
			return strings.to_string(builder), index + 1, ""
		case:
			strings.write_byte(&builder, character)
			index += 1
		}
	}
	return "", 0, "a quoted word has no closing quote"
}

// An optional minus and decimal digits within the i32 range.
parse_integer_word :: proc(word: string) -> (value: i32, ok: bool) {
	negative := strings.has_prefix(word, "-")
	magnitude, parsed := parse_seed(negative ? word[1:] : word)
	if !parsed || magnitude > u64(max(i32)) {
		return 0, false
	}
	return negative ? -i32(magnitude) : i32(magnitude), true
}

parse_coordinate_words :: proc(words: []string) -> (cell: World_Coordinate, ok: bool) {
	if len(words) != 3 {
		return {}, false
	}
	for word, axis in words {
		cell[axis] = parse_integer_word(word) or_return
	}
	return cell, true
}

parse_switch_word :: proc(word: string) -> (on: bool, ok: bool) {
	switch word {
	case "on":
		return true, true
	case "off":
		return false, true
	}
	return false, false
}

usage_error :: proc(usage: string) -> Command_Response {
	return command_error("usage: %s", usage)
}

// Execution.

// The response to a line; empty is true for a blank or comment line,
// which gets no response.
execute_command_line :: proc(command_context: Command_Context, line: string) -> (response: Command_Response, empty: bool) {
	words, problem := split_command_words(line)
	if problem != "" {
		return command_error("%s", problem), false
	}
	if len(words) == 0 {
		return {}, true
	}
	return execute_command(command_context, words), false
}

// The content with the found schematics, as simulation_tick serves
// developer requests.
command_content :: proc(command_context: Command_Context) -> Simulation_Content {
	content := command_context.content
	content.recipes = with_schematics_found(content.recipes, command_context.simulation.unlocks.schematics_found)
	return content
}

serve_command_request :: proc(command_context: Command_Context, request: Developer_Request) -> (problem: string) {
	return serve_developer_request(command_context.simulation, command_content(command_context), request)
}

execute_command :: proc(command_context: Command_Context, words: []string) -> Command_Response {
	name, arguments := words[0], words[1:]
	switch name {
	case "help":
		return command_help()
	case "reload":
		return command_error("reload runs only in the game")
	case "save":
		return command_error("save runs only in the game")
	case "screenshot":
		return command_screenshot(command_context, arguments)
	case "pause", "resume":
		command_context.control.paused = name == "pause"
		return command_ok("%s", name == "pause" ? "paused" : "resumed")
	}
	if command_context.simulation == nil || len(command_context.simulation.players) == 0 {
		return command_error("no world is loaded")
	}
	return execute_world_command(command_context, name, arguments)
}

execute_world_command :: proc(command_context: Command_Context, name: string, arguments: []string) -> Command_Response {
	switch name {
	case "give", "take":
		return command_give_or_take(command_context, name, arguments)
	case "kit":
		return command_kit(command_context, arguments)
	case "chapter":
		return command_chapter(command_context, arguments)
	case "quest":
		return command_quest(command_context, arguments)
	case "research":
		return command_research(command_context, arguments)
	case "unlock_all":
		serve_command_request(command_context, Developer_Request{action = .Unlock_All})
		return command_ok("every recipe and technology unlocked")
	case "teleport":
		return command_teleport(command_context, arguments)
	case "time":
		return command_time(command_context, arguments)
	case "weather":
		return command_weather(command_context, arguments)
	case "fly", "cheat_speed":
		return command_toggle(command_context, name, arguments)
	case "vein":
		return command_vein(command_context, arguments)
	case "place":
		return command_place(command_context, arguments)
	case "remove":
		return command_cell_request(command_context, arguments, "remove <x> <y> <z>", Developer_Request{action = .Remove_At})
	case "block":
		return command_block(command_context, arguments)
	case "insert":
		return command_insert(command_context, arguments)
	case "blueprint":
		return command_blueprint(command_context, arguments)
	case "tick":
		return command_tick(command_context, arguments)
	case "query":
		return command_query(command_context, arguments)
	}
	return command_error("unknown command %q (try help)", name)
}

command_help :: proc() -> Command_Response {
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "commands")
	for entry in command_usages {
		fmt.sbprintf(&builder, "\n%s: %s", entry.usage, entry.summary)
	}
	return Command_Response{ok = true, text = strings.to_string(builder)}
}

command_give_or_take :: proc(command_context: Command_Context, name: string, arguments: []string) -> Command_Response {
	if len(arguments) != 2 {
		return usage_error(fmt.tprintf("%s <item> <count>", name))
	}
	count, count_ok := parse_integer_word(arguments[1])
	if !count_ok {
		return usage_error(fmt.tprintf("%s <item> <count>", name))
	}
	grant, problem := resolve_developer_grant(arguments[0], int(count), command_context.content.items)
	if problem != "" {
		return command_error("%s", problem)
	}
	if name == "give" {
		serve_command_request(command_context, Developer_Request{action = .Give_Item, grant = grant})
		return command_ok("gave %d %s", grant.count, arguments[0])
	}
	held := inventory_count(command_context.simulation.players[0].inventory, grant.item)
	serve_command_request(command_context, Developer_Request{action = .Take_Item, grant = grant})
	return command_ok("took %d %s", min(held, grant.count), arguments[0])
}

// A number word within minimum to maximum, or the problem.
parse_ranged_word :: proc(word: string, minimum, maximum: int, what: string) -> (value: int, problem: string) {
	parsed, ok := parse_integer_word(word)
	if !ok || int(parsed) < minimum || int(parsed) > maximum {
		return 0, fmt.tprintf("%s must be a number from %d to %d", what, minimum, maximum)
	}
	return int(parsed), ""
}

command_kit :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	if len(arguments) != 1 {
		return usage_error("kit <chapter>")
	}
	chapter, problem := parse_ranged_word(arguments[0], 1, len(command_context.content.developer_kits.kits), "the chapter")
	if problem != "" {
		return command_error("%s", problem)
	}
	serve_command_request(command_context, Developer_Request{action = .Give_Kit, chapter = chapter})
	return command_ok("gave the kit of chapter %d", chapter)
}

// Chapter n completes the quests before it; one past the last chapter
// completes every quest.
command_chapter :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	if len(arguments) != 1 {
		return usage_error("chapter <n>")
	}
	quests := command_context.content.quests
	chapter, problem := parse_ranged_word(arguments[0], 1, len(quests.chapters) + 1, "the chapter")
	if problem != "" {
		return command_error("%s", problem)
	}
	serve_command_request(command_context, Developer_Request{action = .Complete_Quests_To_Chapter, chapter = chapter})
	active := command_context.simulation.quests.active
	if active == NO_QUEST {
		return command_ok("every quest done")
	}
	return command_ok("active quest %s (chapter %d)", quests.quests[active].id, quests.quests[active].chapter + 1)
}

// quest finish completes the active quest like the Developer screen's
// button (work item 0098).
command_quest :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	if len(arguments) != 1 || arguments[0] != "finish" {
		return usage_error("quest finish")
	}
	quests := command_context.content.quests
	if command_context.simulation.quests.active == NO_QUEST {
		return command_error("every quest is already done")
	}
	serve_command_request(command_context, Developer_Request{action = .Finish_Active_Quest})
	active := command_context.simulation.quests.active
	if active == NO_QUEST {
		return command_ok("every quest done")
	}
	return command_ok("active quest %s (chapter %d)", quests.quests[active].id, quests.quests[active].chapter + 1)
}

command_research :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	if len(arguments) != 1 {
		return usage_error("research <technology>")
	}
	technologies := command_context.content.technologies
	technology := find_technology(technologies, arguments[0])
	if technology == NO_TECHNOLOGY {
		return command_error("unknown technology %q", arguments[0])
	}
	simulation := command_context.simulation
	infinite := technologies.technologies[technology].infinite
	if !infinite && simulation.unlocks.researched[technology] {
		return command_ok("%s is researched already", arguments[0])
	}
	serve_command_request(command_context, Developer_Request{action = .Research_Technology, technology = technology})
	if infinite {
		return command_ok("%s level %d", arguments[0], simulation.world.research.levels[technology])
	}
	return command_ok("researched %s", arguments[0])
}

// The feet go into the block, at its centre.
command_teleport :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	position: [3]f32
	if len(arguments) == 1 && arguments[0] == "pad" {
		position = landing_pad_standing_position(command_context.simulation.landing_pad)
	} else if cell, ok := parse_coordinate_words(arguments); ok {
		position = {f32(cell.x) + 0.5, f32(cell.y), f32(cell.z) + 0.5}
	} else {
		return usage_error("teleport <x> <y> <z> | teleport pad")
	}
	serve_command_request(command_context, Developer_Request{action = .Teleport, position = position})
	return command_ok("at %.2f %.2f %.2f", position.x, position.y, position.z)
}

@(rodata)
time_of_day_words := [Time_Of_Day]string {
	.Dawn     = "dawn",
	.Noon     = "noon",
	.Dusk     = "dusk",
	.Midnight = "midnight",
}

command_time :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	if len(arguments) == 1 {
		for word, time_of_day in time_of_day_words {
			if word == arguments[0] {
				serve_command_request(command_context, Developer_Request{action = .Set_Time_Of_Day, time_of_day = time_of_day})
				return command_ok("%s", word)
			}
		}
	}
	return usage_error("time <dawn|noon|dusk|midnight>")
}

command_weather :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	if command_context.weather_override == nil {
		return command_error("no world is loaded")
	}
	if len(arguments) == 1 && arguments[0] == "auto" {
		command_context.weather_override^ = nil
		return command_ok("weather auto")
	}
	if len(arguments) == 1 {
		if kind, found := parse_named_enum(weather_kind_words, arguments[0]); found {
			command_context.weather_override^ = kind
			return command_ok("weather %s", arguments[0])
		}
	}
	return usage_error("weather <clear|overcast|rain|fog|auto>")
}

// Toggles only when the state differs, so the command sets it.
command_toggle :: proc(command_context: Command_Context, name: string, arguments: []string) -> Command_Response {
	wanted, ok := parse_switch_word(len(arguments) == 1 ? arguments[0] : "")
	if !ok {
		return usage_error(fmt.tprintf("%s <on|off>", name))
	}
	simulation := command_context.simulation
	current := name == "fly" ? simulation.players[0].flying : simulation.cheat_speed
	if current != wanted {
		action := name == "fly" ? Developer_Action.Toggle_Fly_Mode : Developer_Action.Toggle_Cheat_Speed
		serve_command_request(command_context, Developer_Request{action = action})
	}
	return command_ok("%s %s", name, arguments[0])
}

find_vein_type :: proc(veins: Vein_Content, id: string) -> int {
	for vein_type, index in veins.types {
		if vein_type.id == id {
			return index
		}
	}
	return -1
}

find_size_class :: proc(veins: Vein_Content, id: string) -> int {
	for size_class_id, index in veins.size_class_ids {
		if size_class_id == id {
			return index
		}
	}
	return -1
}

// The smallest size class (listed first) unless one is named.
command_vein :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	usage :: "vein <type> <x> <z> [size_class]"
	if len(arguments) != 3 && len(arguments) != 4 {
		return usage_error(usage)
	}
	veins := command_context.content.veins
	type_index := find_vein_type(veins, arguments[0])
	if type_index < 0 {
		return command_error("unknown vein type %q", arguments[0])
	}
	x, x_ok := parse_integer_word(arguments[1])
	z, z_ok := parse_integer_word(arguments[2])
	if !x_ok || !z_ok {
		return usage_error(usage)
	}
	size_class := 0
	if len(arguments) == 4 {
		if size_class = find_size_class(veins, arguments[3]); size_class < 0 {
			return command_error("unknown size class %q", arguments[3])
		}
	}
	request := Developer_Request{action = .Add_Vein, vein_type = type_index, size_class = size_class, cell = {x, 0, z}}
	if problem := serve_command_request(command_context, request); problem != "" {
		return command_error("%s", problem)
	}
	world := &command_context.simulation.world
	vein := world.veins[len(world.veins) - 1]
	return command_ok("%s vein %d in region %d %d, centre %d %d %d, radius %d", arguments[0], vein.id.index, vein.id.region.x, vein.id.region.y, vein.centre.x, vein.centre.y, vein.centre.z, vein.radius)
}

// Rotations 0 to 3 turn a quarter each (0 points to +x, 1 to +z); a
// belt lift takes 4 to 7 for going down.
command_place :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	usage :: "place <machine> <x> <y> <z> <rotation>"
	if len(arguments) != 5 {
		return usage_error(usage)
	}
	machines := command_context.content.machines
	machine, found := find_machine_id(machines, arguments[0])
	if !found {
		return command_error("unknown machine %q", arguments[0])
	}
	cell, cell_ok := parse_coordinate_words(arguments[1:4])
	if !cell_ok {
		return usage_error(usage)
	}
	definition := machines.machines[machine]
	lift := definition.kind == .Belt && definition.belt_shape == .Lift
	rotation, problem := parse_ranged_word(arguments[4], 0, lift ? LIFT_ROTATION_COUNT - 1 : 3, "the rotation")
	if problem != "" {
		return command_error("%s", problem)
	}
	request := Developer_Request{action = .Place_Machine, machine = machine, cell = cell, rotation = u8(rotation)}
	if problem = serve_command_request(command_context, request); problem != "" {
		return command_error("%s", problem)
	}
	return command_ok("placed %s at %d %d %d", arguments[0], cell.x, cell.y, cell.z)
}

// A request whose only argument is the cell.
command_cell_request :: proc(command_context: Command_Context, arguments: []string, usage: string, request_template: Developer_Request) -> Command_Response {
	cell, ok := parse_coordinate_words(arguments)
	if !ok {
		return usage_error(usage)
	}
	request := request_template
	request.cell = cell
	if problem := serve_command_request(command_context, request); problem != "" {
		return command_error("%s", problem)
	}
	return command_ok("%d %d %d", cell.x, cell.y, cell.z)
}

command_block :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	usage :: "block <block> <x> <y> <z>"
	if len(arguments) != 4 {
		return usage_error(usage)
	}
	block, found := find_block_id(command_context.content.blocks, arguments[0])
	if !found {
		return command_error("unknown block %q", arguments[0])
	}
	return command_cell_request(command_context, arguments[1:], usage, Developer_Request{action = .Set_Block, block = block})
}

command_insert :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	usage :: "insert <item> <count> <x> <y> <z>"
	if len(arguments) != 5 {
		return usage_error(usage)
	}
	count, count_ok := parse_integer_word(arguments[1])
	if !count_ok {
		return usage_error(usage)
	}
	grant, problem := resolve_developer_grant(arguments[0], int(count), command_context.content.items)
	if problem != "" {
		return command_error("%s", problem)
	}
	return command_cell_request(command_context, arguments[2:], usage, Developer_Request{action = .Insert_Items, grant = grant})
}

command_tick :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	if len(arguments) != 1 {
		return usage_error("tick <n>")
	}
	count, problem := parse_ranged_word(arguments[0], 1, MAXIMUM_COMMAND_TICKS, "the tick count")
	if problem != "" {
		return command_error("%s", problem)
	}
	control := command_context.control
	control.pending_ticks, control.requested_ticks, control.ticks_waiting = count, count, true
	return Command_Response{ok = true, deferred = true}
}

// One tick of a tick command, with no player input.
run_command_tick :: proc(simulation: ^Simulation_State, content: Simulation_Content, control: ^Command_Control) {
	simulation_tick(simulation, content, {})
	control.pending_ticks -= 1
}

// The tick command's answer once its ticks ran.
finish_command_ticks :: proc(control: ^Command_Control, tick: u64) -> (response: Command_Response, finished: bool) {
	if !control.ticks_waiting || control.pending_ticks > 0 {
		return {}, false
	}
	control.ticks_waiting = false
	return command_ok("ran %d ticks, now at tick %d", control.requested_ticks, tick), true
}

// Screenshots.

// Letters, digits, dot, dash and underscore, not starting with a dot, so
// the name stays inside the screenshot directory.
screenshot_name_valid :: proc(name: string) -> bool {
	if name == "" || len(name) > MAXIMUM_SCREENSHOT_NAME_LENGTH || name[0] == '.' {
		return false
	}
	for character in transmute([]u8)name {
		letter := (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z')
		if !letter && !(character >= '0' && character <= '9') && !strings.contains_rune("._-", rune(character)) {
			return false
		}
	}
	return true
}

// The UTC time without colons, which some file systems refuse.
screenshot_default_name :: proc(now: time.Time) -> string {
	date_time, _ := time.time_to_datetime(now)
	return fmt.tprintf("%04d-%02d-%02dT%02d-%02d-%02dZ", date_time.year, date_time.month, date_time.day, date_time.hour, date_time.minute, date_time.second)
}

// The path the next frame's picture goes to, with the directory made.
// Replaces a screenshot still waiting. In the temp allocator.
queue_screenshot :: proc(control: ^Command_Control, directory, name: string, now: time.Time) -> (path: string, problem: string) {
	file_name := name == "" ? screenshot_default_name(now) : name
	switch {
	case directory == "":
		return "", "no state directory (set XDG_STATE_HOME or HOME)"
	case !screenshot_name_valid(file_name):
		return "", "a screenshot name holds letters, digits, dot, dash and underscore, up to 64, not starting with a dot"
	}
	if !strings.has_suffix(file_name, ".png") {
		file_name = fmt.tprintf("%s.png", file_name)
	}
	if error := os.make_directory_all(directory); error != nil && error != .Exist {
		return "", fmt.tprintf("cannot make %s: %v", directory, error)
	}
	joined, _ := os.join_path({directory, file_name}, context.temp_allocator)
	delete(control.screenshot_path)
	control.screenshot_path = strings.clone(joined)
	return joined, ""
}

command_screenshot :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	if len(arguments) > 1 {
		return usage_error("screenshot [name]")
	}
	path, problem := queue_screenshot(command_context.control, command_context.screenshot_directory, len(arguments) == 1 ? arguments[0] : "", command_context.now)
	if problem != "" {
		return command_error("%s", problem)
	}
	return command_ok("%s", path)
}

// Blueprints.

Blueprint_Origin_Kind :: enum u8 {
	Pad,
	Cell,
	Vein,
}

// origin = "pad" | [x, y, z] | {vein = "<type>"}; commands are place,
// block, remove and insert lines with coordinates relative to the origin.
// In the temp allocator.
Blueprint :: struct {
	origin_kind: Blueprint_Origin_Kind,
	cell:        World_Coordinate,
	vein_type:   string,
	commands:    []string,
}

parse_blueprint :: proc(data: []byte) -> (blueprint: Blueprint, problem: string) {
	value, error := json.parse(data, .SJSON, true, context.temp_allocator)
	if error != nil {
		return {}, fmt.tprintf("not SJSON: %v", error)
	}
	object, is_object := value.(json.Object)
	if !is_object {
		return {}, "expected origin and commands"
	}
	for key in object {
		if key != "origin" && key != "commands" {
			return {}, fmt.tprintf("unknown key %q (expected origin and commands)", key)
		}
	}
	if problem = parse_blueprint_origin(object["origin"], &blueprint); problem != "" {
		return {}, problem
	}
	blueprint.commands, problem = parse_blueprint_commands(object["commands"])
	return blueprint, problem
}

parse_blueprint_origin :: proc(value: json.Value, blueprint: ^Blueprint) -> string {
	#partial switch origin in value {
	case json.String:
		if origin == "pad" {
			blueprint.origin_kind = .Pad
			return ""
		}
	case json.Array:
		if len(origin) == 3 {
			blueprint.origin_kind = .Cell
			for element, axis in origin {
				number, is_integer := element.(json.Integer)
				if !is_integer {
					return "origin coordinates must be integers"
				}
				blueprint.cell[axis] = i32(number)
			}
			return ""
		}
	case json.Object:
		vein, is_string := origin["vein"].(json.String)
		if is_string && len(origin) == 1 {
			blueprint.origin_kind, blueprint.vein_type = .Vein, vein
			return ""
		}
	}
	return "origin must be \"pad\", [x, y, z] or {vein = \"<type>\"}"
}

parse_blueprint_commands :: proc(value: json.Value) -> (commands: []string, problem: string) {
	array, is_array := value.(json.Array)
	if !is_array {
		return nil, "commands must be a list of strings"
	}
	commands = make([]string, len(array), context.temp_allocator)
	for element, index in array {
		command, is_string := element.(json.String)
		if !is_string {
			return nil, "commands must be a list of strings"
		}
		commands[index] = command
	}
	return commands, ""
}

// The registered surface vein of the type whose centre is nearest the
// landing pad's (a starter vein, once its chunks loaded).
nearest_vein_of_type :: proc(world: ^World, type_index: int, target: World_Coordinate) -> (vein: Vein, found: bool) {
	best: i64 = max(i64)
	for candidate in world.veins {
		if candidate.type != type_index || vein_is_deep(candidate) {
			continue
		}
		dx, dz := i64(candidate.centre.x - target.x), i64(candidate.centre.z - target.z)
		if dx * dx + dz * dz < best {
			best, vein, found = dx * dx + dz * dz, candidate, true
		}
	}
	return
}

// The cell the relative coordinates count from: above the pad's centre
// or the vein's centre (both surface blocks), or the given cell.
blueprint_origin :: proc(command_context: Command_Context, blueprint: Blueprint) -> (origin: World_Coordinate, problem: string) {
	simulation := command_context.simulation
	switch blueprint.origin_kind {
	case .Pad:
		return simulation.landing_pad.centre + {0, 1, 0}, ""
	case .Cell:
		return blueprint.cell, ""
	case .Vein:
		type_index := find_vein_type(command_context.content.veins, blueprint.vein_type)
		if type_index < 0 {
			return {}, fmt.tprintf("unknown vein type %q", blueprint.vein_type)
		}
		vein, found := nearest_vein_of_type(&simulation.world, type_index, simulation.landing_pad.centre)
		if !found {
			return {}, fmt.tprintf("no %s vein is registered yet (its chunks load near the player)", blueprint.vein_type)
		}
		return vein.centre + {0, 1, 0}, ""
	}
	return {}, ""
}

// The index of the first coordinate word of a blueprint command, or -1
// for a command a blueprint may not hold.
blueprint_coordinate_index :: proc(name: string) -> int {
	switch name {
	case "remove":
		return 1
	case "place", "block":
		return 2
	case "insert":
		return 3
	}
	return -1
}

// The command's words with its coordinates moved by the origin.
expand_blueprint_command :: proc(command: string, origin: World_Coordinate) -> (words: []string, problem: string) {
	words, problem = split_command_words(command)
	if problem != "" || len(words) == 0 {
		return nil, problem != "" ? problem : "empty command"
	}
	first := blueprint_coordinate_index(words[0])
	if first < 0 {
		return nil, "a blueprint holds only place, block, remove and insert"
	}
	if len(words) < first + 3 {
		return nil, "missing coordinates"
	}
	cell, ok := parse_coordinate_words(words[first:first + 3])
	if !ok {
		return nil, "coordinates must be integers"
	}
	moved := slice.clone(words, context.temp_allocator)
	for axis in 0 ..< 3 {
		moved[first + axis] = fmt.tprintf("%d", cell[axis] + origin[axis])
	}
	return moved, ""
}

// Runs the commands in order and stops at the first that fails, naming
// it by its number (from 1). What ran before stays.
run_blueprint :: proc(command_context: Command_Context, blueprint: Blueprint) -> Command_Response {
	origin, problem := blueprint_origin(command_context, blueprint)
	if problem != "" {
		return command_error("%s", problem)
	}
	for command, index in blueprint.commands {
		words, expand_problem := expand_blueprint_command(command, origin)
		if expand_problem != "" {
			return command_error("blueprint command %d (%s): %s", index + 1, command, expand_problem)
		}
		if response := execute_command(command_context, words); !response.ok {
			return command_error("blueprint command %d (%s): %s", index + 1, command, response.text)
		}
	}
	return command_ok("ran %d commands from %d %d %d", len(blueprint.commands), origin.x, origin.y, origin.z)
}

// The path is read as given; tools/moc sends it absolute.
command_blueprint :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	if len(arguments) != 1 {
		return usage_error("blueprint <path>")
	}
	data, error := os.read_entire_file(arguments[0], context.temp_allocator)
	if error != nil {
		return command_error("cannot read %s: %v", arguments[0], error)
	}
	blueprint, problem := parse_blueprint(data)
	if problem != "" {
		return command_error("%s: %s", arguments[0], problem)
	}
	return run_blueprint(command_context, blueprint)
}

// Queries.

command_query :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	subject := len(arguments) > 0 ? arguments[0] : ""
	rest := len(arguments) > 0 ? arguments[1:] : nil
	switch subject {
	case "player":
		return query_player(command_context)
	case "world":
		return query_world(command_context)
	case "veins":
		return query_veins(command_context, rest)
	case "entities":
		return query_entities(command_context, rest)
	case "quests":
		return query_quests(command_context)
	case "contracts":
		return query_contracts(command_context)
	case "stats":
		return query_stats(command_context, rest)
	}
	return usage_error("query player|world|veins|entities|quests|contracts|stats")
}

query_response :: proc(builder: ^strings.Builder) -> Command_Response {
	return Command_Response{ok = true, text = strings.to_string(builder^)}
}

query_player :: proc(command_context: Command_Context) -> Command_Response {
	simulation := command_context.simulation
	player := simulation.players[0]
	items := command_context.content.items
	builder := strings.builder_make(context.temp_allocator)
	cell := camera_world_coordinate(player.position)
	fmt.sbprintf(&builder, "player\nposition %.2f %.2f %.2f\nblock %d %d %d", player.position.x, player.position.y, player.position.z, cell.x, cell.y, cell.z)
	fmt.sbprintf(&builder, "\nyaw %.1f\npitch %.1f\nflying %v\non_ground %v\ncheat_speed %v", player.yaw, player.pitch, player.flying, player.on_ground, simulation.cheat_speed)
	for item, index in items.items {
		if count := inventory_count(player.inventory, Item_Id(index)); count > 0 {
			fmt.sbprintf(&builder, "\nitem %s %d", item.id, count)
		}
	}
	for stack in simulation.quests.pending_rewards {
		fmt.sbprintf(&builder, "\npending_reward %s %d", items.items[stack.item].id, stack.count)
	}
	return query_response(&builder)
}

query_world :: proc(command_context: Command_Context) -> Command_Response {
	simulation := command_context.simulation
	world := &simulation.world
	day_ticks := simulation.day_length_ticks > 0 ? simulation_day_ticks(simulation^) % simulation.day_length_ticks : 0
	pad := simulation.landing_pad.centre
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "world\nseed %d\ntick %d\nday_ticks %d\nday_length_ticks %d", world.settings.seed, simulation.tick, day_ticks, simulation.day_length_ticks)
	fmt.sbprintf(&builder, "\npad %d %d %d\nloaded_chunks %d\nregistered_veins %d\npaused %v", pad.x, pad.y, pad.z, len(world.chunks), len(world.veins), command_context.control.paused)
	return query_response(&builder)
}

// An optional radius word within 1 to MAXIMUM_QUERY_RADIUS.
query_radius :: proc(arguments: []string, default_radius: int) -> (radius: int, problem: string) {
	if len(arguments) == 0 {
		return default_radius, ""
	}
	if len(arguments) > 1 {
		return 0, "too many arguments"
	}
	return parse_ranged_word(arguments[0], 1, MAXIMUM_QUERY_RADIUS, "the radius")
}

horizontal_distance_within :: proc(from, to: World_Coordinate, radius: int) -> bool {
	dx, dz := i64(to.x - from.x), i64(to.z - from.z)
	return dx * dx + dz * dz <= i64(radius) * i64(radius)
}

// Registered veins (those of loaded columns and added ones) whose centre
// lies within the radius of the player's column.
query_veins :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	radius, problem := query_radius(arguments, DEFAULT_VEIN_QUERY_RADIUS)
	if problem != "" {
		return usage_error("query veins [radius]")
	}
	simulation := command_context.simulation
	veins := command_context.content.veins
	centre := camera_world_coordinate(simulation.players[0].position)
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "veins")
	for vein in simulation.world.veins {
		if !horizontal_distance_within(centre, vein.centre, radius) || vein.type >= len(veins.types) {
			continue
		}
		size := vein.size_class < len(veins.size_class_ids) ? veins.size_class_ids[vein.size_class] : "?"
		layer := vein_is_deep(vein) ? "deep" : "surface"
		fmt.sbprintf(&builder, "\nvein %s size %s layer %s centre %d %d %d radius %d remaining %d", veins.types[vein.type].id, size, layer, vein.centre.x, vein.centre.y, vein.centre.z, vein.radius, vein_remaining_total(vein))
		fmt.sbprintf(&builder, " id %d %d %d added %v exhausted %v", vein.id.region.x, vein.id.region.y, vein.id.index, vein.added, vein.exhausted)
	}
	return query_response(&builder)
}

// A machine id, or an entity kind in lower case (drill, belt).
entity_matches_kind :: proc(handle: Entity_Handle, machine: Machine, kind: string) -> bool {
	return kind == "" || machine.id == kind || strings.to_lower(fmt.tprint(handle.kind), context.temp_allocator) == kind
}

Entity_Listing :: struct {
	machine:  string,
	origin:   World_Coordinate,
	rotation: u8,
}

entity_listing_before :: proc(first, second: Entity_Listing) -> bool {
	return coordinate_before(first.origin, second.origin)
}

// Entities with a cell within the radius of the player's column, by
// origin.
query_entities :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	kind := ""
	rest := arguments
	if len(rest) > 0 {
		if _, is_number := parse_integer_word(rest[0]); !is_number {
			kind, rest = rest[0], rest[1:]
		}
	}
	radius, problem := query_radius(rest, DEFAULT_ENTITY_QUERY_RADIUS)
	if problem != "" {
		return usage_error("query entities [kind] [radius]")
	}
	world := &command_context.simulation.world
	machines := command_context.content.machines
	centre := camera_world_coordinate(command_context.simulation.players[0].position)
	seen := make(map[Entity_Handle]bool, context.temp_allocator)
	listings := make([dynamic]Entity_Listing, context.temp_allocator)
	for cell, handle in world.entities.cells {
		if handle in seen || !horizontal_distance_within(centre, cell, radius) {
			continue
		}
		seen[handle] = true
		common := entity_common(&world.entities, handle)
		if common != nil && entity_matches_kind(handle, machines.machines[common.machine], kind) {
			append(&listings, Entity_Listing{machine = machines.machines[common.machine].id, origin = common.origin, rotation = common.rotation})
		}
	}
	slice.sort_by(listings[:], entity_listing_before)
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "entities %d", len(listings))
	for listing in listings {
		fmt.sbprintf(&builder, "\nentity %s %d %d %d rotation %d", listing.machine, listing.origin.x, listing.origin.y, listing.origin.z, listing.rotation)
	}
	return query_response(&builder)
}

query_quests :: proc(command_context: Command_Context) -> Command_Response {
	simulation := command_context.simulation
	state := &simulation.quests
	registry := command_context.content.quests
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "quests")
	if state.active == NO_QUEST {
		strings.write_string(&builder, "\nactive none")
	} else {
		quest := registry.quests[state.active]
		fmt.sbprintf(&builder, "\nactive %s chapter %d", quest.id, quest.chapter + 1)
		view := Quest_View {
			statistics    = simulation.world.statistics,
			unlocks       = simulation.unlocks,
			capsule_slots = entity_slots(&simulation.world.entities, state.capsule),
			tick_rate     = simulation.tick_rate,
		}
		for objective, index in quest.objectives {
			progress := objective_progress(objective, index, state.progress[state.active], view)
			fmt.sbprintf(&builder, "\nobjective %d %d/%d", index + 1, progress.current, progress.required)
		}
	}
	done := 0
	for progress in state.progress {
		done += progress.status == .Done ? 1 : 0
	}
	fmt.sbprintf(&builder, "\ndone %d of %d\npending_rewards %d", done, len(registry.quests), len(state.pending_rewards))
	return query_response(&builder)
}

query_contracts :: proc(command_context: Command_Context) -> Command_Response {
	world := &command_context.simulation.world
	contracts := command_context.content.contracts
	items := command_context.content.items
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "contracts\ncredit %d", world.venture_credit)
	for open in open_contracts(&world.contracts) {
		contract := contracts.contracts[open.contract]
		fmt.sbprintf(&builder, "\ncontract %s tier %d offered_tick %d", contract.id, contract.tier, open.offered_tick)
		for request, index in contract.requests[:contract.request_count] {
			fmt.sbprintf(&builder, "\nrequest %s %d/%d", items.items[request.item].id, open.delivered[index], request.count)
		}
	}
	return query_response(&builder)
}

query_stats :: proc(command_context: Command_Context, arguments: []string) -> Command_Response {
	if len(arguments) != 1 {
		return usage_error("query stats <item>")
	}
	item, found := find_item_id(command_context.content.items, arguments[0])
	if !found {
		return command_error("unknown item %q", arguments[0])
	}
	simulation := command_context.simulation
	statistics := simulation.world.statistics
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "stats %s\nproduced %d\nconsumed %d", arguments[0], item_counter(statistics.produced, item), item_counter(statistics.consumed, item))
	fmt.sbprintf(&builder, "\nobtained %d\ndelivered %d\nvoided %d", item_counter(statistics.obtained, item), item_counter(statistics.delivered, item), item_counter(statistics.voided, item))
	fmt.sbprintf(&builder, "\nrate_per_minute %d\ninventory %d", production_rate_per_minute(statistics, item), inventory_count(simulation.players[0].inventory, item))
	return query_response(&builder)
}
