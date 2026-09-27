package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

// Developer mode (work item 0043): shortcuts that put a tester into a
// given game state from the couch. The Developer screen (ui_developer.odin,
// only with --dev) and the command line (--chapter, --give) queue
// Developer_Requests on the simulation; simulation_tick serves them before
// the players move, so the UI frame never changes simulation state itself.
//
// Chapter kits come from data/dev_kits.sjson: one kit per chapter, in
// chapter order, with the items a player typically holds at that
// chapter's start. What does not fit into the inventory waits for the
// drop capsule like a quest reward.

DEVELOPER_KITS_FILE_NAME :: "dev_kits.sjson"
// The most a single --give or kit entry may hand out.
MAXIMUM_DEVELOPER_GRANT_COUNT :: 10_000

Developer_Kit_Item_Definition :: struct {
	item:  string,
	count: int,
}

Developer_Kit_Definition :: struct {
	chapter: int,
	items:   []Developer_Kit_Item_Definition,
}

Developer_Kits_File :: struct {
	kits: []Developer_Kit_Definition,
}

Developer_Grant :: struct {
	item:  Item_Id,
	count: int,
}

// kits[chapter - 1] is the kit of that chapter.
Developer_Kits :: struct {
	kits: [][]Developer_Grant,
}

Developer_Action :: enum u8 {
	Toggle_Fly_Mode,
	Give_Kit,
	Give_Item,
	Complete_Quests_To_Chapter,
	Unlock_All,
	Set_Time_Of_Day,
	Teleport,
}

// The sun rises at dawn, peaks at noon, sets at dusk and is lowest at
// midnight (render_day.odin).
Time_Of_Day :: enum u8 {
	Dawn,
	Noon,
	Dusk,
	Midnight,
}

// chapter counts from 1 (Give_Kit, Complete_Quests_To_Chapter); grant is
// for Give_Item, time_of_day for Set_Time_Of_Day, position (the player's
// feet) for Teleport.
Developer_Request :: struct {
	action:      Developer_Action,
	chapter:     int,
	grant:       Developer_Grant,
	time_of_day: Time_Of_Day,
	position:    [3]f32,
}

// Kits file.

parse_developer_kits_file :: proc(data: []byte, allocator := context.allocator) -> (file: Developer_Kits_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

resolve_developer_grant :: proc(item_name: string, count: int, items: Item_Registry) -> (grant: Developer_Grant, problem: string) {
	item, found := find_item_id(items, item_name)
	switch {
	case !found:
		return {}, fmt.tprintf("unknown item %q", item_name)
	case count < 1 || count > MAXIMUM_DEVELOPER_GRANT_COUNT:
		return {}, fmt.tprintf("item %q needs a count from 1 to %d", item_name, MAXIMUM_DEVELOPER_GRANT_COUNT)
	}
	return Developer_Grant{item = item, count = count}, ""
}

resolve_developer_kit :: proc(definition: Developer_Kit_Definition, items: Item_Registry, allocator := context.allocator) -> (kit: []Developer_Grant, problem: string) {
	kit = make([]Developer_Grant, len(definition.items), allocator)
	for entry, index in definition.items {
		if kit[index], problem = resolve_developer_grant(entry.item, entry.count, items); problem != "" {
			delete(kit, allocator)
			return nil, fmt.tprintf("kit of chapter %d: %s", definition.chapter, problem)
		}
	}
	return kit, ""
}

// Kits for chapters 1, 2, 3 and so on, in that order, each naming known
// items.
resolve_developer_kits :: proc(file: Developer_Kits_File, items: Item_Registry, allocator := context.allocator) -> (kits: Developer_Kits, problem: string) {
	kits.kits = make([][]Developer_Grant, len(file.kits), allocator)
	for definition, index in file.kits {
		if definition.chapter != index + 1 {
			problem = fmt.tprintf("kit %d is for chapter %d, expected chapter %d", index + 1, definition.chapter, index + 1)
		} else {
			kits.kits[index], problem = resolve_developer_kit(definition, items, allocator)
		}
		if problem != "" {
			destroy_developer_kits(kits, allocator)
			return {}, problem
		}
	}
	return kits, ""
}

destroy_developer_kits :: proc(kits: Developer_Kits, allocator := context.allocator) {
	for kit in kits.kits {
		delete(kit, allocator)
	}
	delete(kits.kits, allocator)
}

load_developer_kits :: proc(data_directory: string, items: Item_Registry, allocator := context.allocator) -> (kits: Developer_Kits, ok: bool) {
	path, join_error := os.join_path({data_directory, DEVELOPER_KITS_FILE_NAME}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		log_printf("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	file, parse_error := parse_developer_kits_file(data, context.temp_allocator)
	if parse_error != nil {
		log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	if kits, problem = resolve_developer_kits(file, items, allocator); problem != "" {
		log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return kits, true
}

// Command line.

// "<item>:<count>" with a decimal count (digits only, parse_seed); the item is checked against the
// data later (resolve_give_arguments).
parse_give_argument :: proc(value: string) -> (item_name: string, count: int, ok: bool) {
	separator := strings.last_index_byte(value, ':')
	if separator <= 0 {
		return "", 0, false
	}
	parsed, parsed_ok := parse_seed(value[separator + 1:])
	if !parsed_ok || parsed < 1 || parsed > MAXIMUM_DEVELOPER_GRANT_COUNT {
		return "", 0, false
	}
	return value[:separator], int(parsed), true
}

// The shape of every --give, before any data is loaded.
give_arguments_problem :: proc(arguments: []string) -> string {
	for argument in arguments {
		if _, _, ok := parse_give_argument(argument); !ok {
			return fmt.tprintf("invalid --give=%s (expected <item>:<count> with a count from 1 to %d, for example --give=iron_plate:50)", argument, MAXIMUM_DEVELOPER_GRANT_COUNT)
		}
	}
	return ""
}

// Every --give resolved against the items. In the temp allocator.
resolve_give_arguments :: proc(arguments: []string, items: Item_Registry) -> (grants: []Developer_Grant, problem: string) {
	grants = make([]Developer_Grant, len(arguments), context.temp_allocator)
	for argument, index in arguments {
		item_name, count, ok := parse_give_argument(argument)
		if !ok {
			return nil, give_arguments_problem(arguments[index:index + 1])
		}
		if grants[index], problem = resolve_developer_grant(item_name, count, items); problem != "" {
			return nil, fmt.tprintf("invalid --give=%s: %s", argument, problem)
		}
	}
	return grants, ""
}

// --chapter=<n>: complete the quests before chapter n and give its kit.
chapter_requests :: proc(requests: ^[dynamic]Developer_Request, chapter: int) {
	append(requests, Developer_Request{action = .Complete_Quests_To_Chapter, chapter = chapter})
	append(requests, Developer_Request{action = .Give_Kit, chapter = chapter})
}

give_requests :: proc(requests: ^[dynamic]Developer_Request, grants: []Developer_Grant) {
	for grant in grants {
		append(requests, Developer_Request{action = .Give_Item, grant = grant})
	}
}

// Serving requests.

// Into the inventory as far as it fits, the rest into the capsule's
// pending rewards in stacks.
give_to_player :: proc(player: ^Player, pending_rewards: ^[dynamic]Item_Stack, items: Item_Registry, grant: Developer_Grant) {
	leftover := inventory_add(player.inventory, items, grant.item, grant.count)
	stack_size := max(int(item_stack_size(items, grant.item)), 1)
	for leftover > 0 {
		count := min(leftover, stack_size)
		append(pending_rewards, Item_Stack{item = grant.item, count = u16(count)})
		leftover -= count
	}
}

give_kit :: proc(player: ^Player, pending_rewards: ^[dynamic]Item_Stack, items: Item_Registry, kits: Developer_Kits, chapter: int) {
	if chapter < 1 || chapter > len(kits.kits) {
		return
	}
	for grant in kits.kits[chapter - 1] {
		give_to_player(player, pending_rewards, items, grant)
	}
}

// The first quest of the chapter, or one past the last quest when the
// chapter has no quests in the data (chapter 8 has none yet).
first_quest_of_chapter :: proc(registry: Quest_Registry, chapter: int) -> int {
	if chapter >= 1 && chapter <= len(registry.chapters) {
		return registry.chapters[chapter - 1].first_quest
	}
	return chapter < 1 ? 0 : len(registry.quests)
}

// Walks the active quest forward through the quests before chapter's
// first as if each were completed: marked done, rewards queued (items
// for the capsule, recipes and technologies unlocked), the next one
// activated. Deliveries are not taken. Only the final activation's
// message stays in the log, so the journal and toasts are not flooded.
// A quest at or past the chapter stays as it is.
complete_quests_to_chapter :: proc(state: ^Quest_State, registry: Quest_Registry, unlocks: ^Recipe_Unlocks, recipes: Recipe_Registry, statistics: Statistics, tick: u64, chapter: int) {
	target := first_quest_of_chapter(registry, chapter)
	messages_before, notices_before := len(state.messages), len(state.notices)
	advanced := false
	for state.active != NO_QUEST && state.active < target {
		index := state.active
		state.progress[index].status = .Done
		queue_rewards(state, registry.quests[index], unlocks, recipes)
		activate_quest(state, registry, next_quest(registry, index), statistics, tick)
		advanced = true
	}
	if !advanced {
		return
	}
	resize(&state.messages, messages_before)
	resize(&state.notices, notices_before)
	if state.active != NO_QUEST {
		log_quest_message(state, tick, registry.quests[state.active].message_key)
	}
}

// What --unlock-all does at the start, applied to a running world. Saved
// with the world like the setting.
unlock_everything :: proc(unlocks: ^Recipe_Unlocks, recipes: Recipe_Registry) {
	mark_everything_unlocked(unlocks)
	refresh_available_recipes(unlocks, recipes)
}

// The day fraction the sun is at for each time of day, in quarter days.
time_of_day_quarter :: proc(time_of_day: Time_Of_Day) -> u64 {
	switch time_of_day {
	case .Dawn:
		return 0
	case .Noon:
		return 1
	case .Dusk:
		return 2
	case .Midnight:
		return 3
	}
	return 0
}

// The day tick (tick plus offset, modulo the day) at which daylight_blend
// shows that time of day.
time_of_day_day_ticks :: proc(time_of_day: Time_Of_Day, day_length_ticks: u64) -> u64 {
	start_ticks := u64(math.round(DAY_START_FRACTION * f64(day_length_ticks)))
	return (time_of_day_quarter(time_of_day) * day_length_ticks / 4 + day_length_ticks - start_ticks % day_length_ticks) % day_length_ticks
}

// The offset that makes tick fall on the given day tick.
day_offset_for :: proc(tick, day_ticks, day_length_ticks: u64) -> u64 {
	if day_length_ticks == 0 {
		return 0
	}
	return (day_ticks % day_length_ticks + day_length_ticks - tick % day_length_ticks) % day_length_ticks
}

teleport_player :: proc(player: ^Player, position: [3]f32) {
	player.position = position
	player.previous_position = position
	player.velocity = {}
	player.on_ground = false
}

// Where Teleport puts the player: standing on the pad's centre block.
landing_pad_standing_position :: proc(site: Landing_Pad_Site) -> [3]f32 {
	return player_start_on(site.centre).position
}

serve_developer_request :: proc(state: ^Simulation_State, content: Simulation_Content, request: Developer_Request) {
	player := &state.players[0]
	switch request.action {
	case .Toggle_Fly_Mode:
		apply_player_toggles(player, {.Toggle_Fly_Mode})
	case .Give_Kit:
		give_kit(player, &state.quests.pending_rewards, content.items, content.developer_kits, request.chapter)
	case .Give_Item:
		give_to_player(player, &state.quests.pending_rewards, content.items, request.grant)
	case .Complete_Quests_To_Chapter:
		complete_quests_to_chapter(&state.quests, content.quests, &state.unlocks, content.recipes, state.world.statistics, state.tick, request.chapter)
	case .Unlock_All:
		unlock_everything(&state.unlocks, content.recipes)
	case .Set_Time_Of_Day:
		state.day_offset_ticks = day_offset_for(state.tick, time_of_day_day_ticks(request.time_of_day, state.day_length_ticks), state.day_length_ticks)
	case .Teleport:
		teleport_player(player, request.position)
	}
}

// At the start of a tick, oldest first. Without a player nothing is
// served.
serve_developer_requests :: proc(state: ^Simulation_State, content: Simulation_Content) {
	if len(state.players) > 0 {
		for request in state.developer_requests {
			serve_developer_request(state, content, request)
		}
	}
	clear(&state.developer_requests)
}
