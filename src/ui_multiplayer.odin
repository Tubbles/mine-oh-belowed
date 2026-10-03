package game

import "core:fmt"
import "core:strings"
import "core:time"
import "platform"

// The title's Multiplayer screen (work item 0188): the games the LAN
// answered within LAN_GAME_LIFETIME (session_discovery.odin feeds the
// list between frames), Confirm on one joins it, a game of another build
// is greyed and marked since its host refuses the join; under the list a
// "Join by address" field for networks that drop broadcasts, the
// keyboard's one use here. A join asks the frame loop (.Join), which
// takes the --join path.

MULTIPLAYER_PANEL_WIDTH :: 1400
// Rows of the game list below its column headings.
MULTIPLAYER_LIST_ROWS :: 6
// An answer older than this drops out of the list.
LAN_GAME_LIFETIME :: 3 * time.Second
// The games the list holds at most; a flood of answers from many
// addresses cannot grow it further.
MAXIMUM_LAN_GAMES :: 64
// The longest address the field takes: a host name or an IP address and
// a port.
JOIN_ADDRESS_MAXIMUM_LENGTH :: 96
ADDRESS_FIELD_SHARE :: 0.75
// The host and build columns' shares of a row.
LAN_HOST_COLUMN_SHARE :: 0.22
LAN_BUILD_COLUMN_SHARE :: 0.3

// One game that answered. The texts are owned.
Lan_Game :: struct {
	// The host's IP address, the answer's source.
	address:     string,
	port:        int,
	world:       string,
	host:        string,
	build:       string,
	players:     int,
	same_build:  bool,
	last_answer: time.Tick,
}

Multiplayer_State :: struct {
	// In the order they first answered, so the rows stay put.
	games:   [dynamic]Lan_Game,
	address: Text_Field,
}

make_multiplayer_state :: proc() -> Multiplayer_State {
	return Multiplayer_State{address = make_text_field("", JOIN_ADDRESS_MAXIMUM_LENGTH)}
}

destroy_lan_game :: proc(game: Lan_Game) {
	delete(game.address)
	delete(game.world)
	delete(game.host)
	delete(game.build)
}

clear_lan_games :: proc(multiplayer: ^Multiplayer_State) {
	for game in multiplayer.games {
		destroy_lan_game(game)
	}
	clear(&multiplayer.games)
}

destroy_multiplayer_state :: proc(multiplayer: ^Multiplayer_State) {
	clear_lan_games(multiplayer)
	delete(multiplayer.games)
}

// The answer refreshes the game of its address and port, or adds one
// while the list has room.
add_lan_answer :: proc(multiplayer: ^Multiplayer_State, answer: platform.Discovery_Message, address: string, same_build: bool, now: time.Tick) {
	index := find_lan_game(multiplayer^, address, answer.port)
	if index < 0 && len(multiplayer.games) >= MAXIMUM_LAN_GAMES {
		return
	}
	game := Lan_Game {
		address     = strings.clone(address),
		port        = answer.port,
		world       = strings.clone(answer.world),
		host        = strings.clone(answer.host),
		build       = strings.clone(answer.build),
		players     = answer.players,
		same_build  = same_build,
		last_answer = now,
	}
	if index >= 0 {
		destroy_lan_game(multiplayer.games[index])
		multiplayer.games[index] = game
		return
	}
	append(&multiplayer.games, game)
}

find_lan_game :: proc(multiplayer: Multiplayer_State, address: string, port: int) -> int {
	for game, index in multiplayer.games {
		if game.address == address && game.port == port {
			return index
		}
	}
	return -1
}

// The games whose last answer is LAN_GAME_LIFETIME old go.
prune_lan_games :: proc(multiplayer: ^Multiplayer_State, now: time.Tick) {
	kept := 0
	for game in multiplayer.games {
		if time.tick_diff(game.last_answer, now) >= LAN_GAME_LIFETIME {
			destroy_lan_game(game)
			continue
		}
		multiplayer.games[kept] = game
		kept += 1
	}
	resize(&multiplayer.games, kept)
}

// The address --join takes for the game.
lan_game_join_address :: proc(game: Lan_Game) -> string {
	return fmt.tprintf("%s:%d", game.address, game.port)
}

// Asks the frame loop to join the address.
request_join :: proc(title: ^Title_State, address: string) {
	text_field_set(&title.join_address, address)
	title.request = {kind = .Join}
}

// The row's cells; marker is set for a game of another build.
Lan_Game_Cells :: struct {
	world:   string,
	marker:  string,
	host:    string,
	players: string,
	build:   string,
}

lan_game_cells :: proc(game: Lan_Game) -> Lan_Game_Cells {
	return Lan_Game_Cells {
		world = game.world,
		marker = game.same_build ? "" : text("multiplayer_other_build"),
		host = game.host,
		players = fmt.tprint(game.players),
		build = game.build,
	}
}

Lan_Game_Columns :: struct {
	world, host, players, build: Ui_Rectangle,
}

lan_game_columns :: proc(state: ^Ui_State, row: Ui_Rectangle) -> Lan_Game_Columns {
	content := inset(row, UI_PADDING)
	width := content.width
	columns: Lan_Game_Columns
	columns.build = cut_right(&content, width * LAN_BUILD_COLUMN_SHARE)
	columns.players = cut_right(&content, save_column_width(state, "00000", text("multiplayer_players")))
	columns.host = cut_right(&content, width * LAN_HOST_COLUMN_SHARE)
	columns.world = content
	return columns
}

// World (with the marker right aligned in its column), host, players and
// build, each ending with an ellipsis where it does not fit.
draw_lan_game_row :: proc(state: ^Ui_State, row: Ui_Rectangle, cells: Lan_Game_Cells, color := UI_TEXT_COLOR) {
	columns := lan_game_columns(state, row)
	world := columns.world
	if cells.marker != "" {
		marker := fit_text(state, cells.marker, UI_BODY_TEXT_SIZE, world.width * SAVE_MARKER_SHARE)
		draw_text(state, world, marker, UI_BODY_TEXT_SIZE, .Right, UI_ACCENT_COLOR)
		world.width -= ui_text_width(state, marker, UI_BODY_TEXT_SIZE) + UI_PADDING
	}
	draw_text_fitted(state, world, cells.world, UI_BODY_TEXT_SIZE, .Left, color)
	draw_text_fitted(state, columns.host, cells.host, UI_BODY_TEXT_SIZE, .Left, color)
	draw_text_fitted(state, columns.players, cells.players, UI_BODY_TEXT_SIZE, .Right, color)
	draw_text_fitted(state, columns.build, cells.build, UI_BODY_TEXT_SIZE, .Right, color)
}

// The games as rows; ids match ui_list's. Returns the activated game or
// -1.
lan_game_list :: proc(state: ^Ui_State, area: Ui_Rectangle, multiplayer: ^Multiplayer_State) -> int {
	activated := -1
	list := scroll_list_begin(state, "lan_games", area, len(multiplayer.games))
	for game, index in multiplayer.games {
		row := scroll_list_row(list, index)
		id := ui_id(state, "item", index)
		interaction := ui_interact(state, id, row)
		if interaction.focused {
			scroll_list_keep_visible(&list, index)
		}
		if interaction.activated {
			activated = index
		}
		widget_background(state, row, id, interaction)
		draw_lan_game_row(state, row, lan_game_cells(game), game.same_build ? UI_TEXT_COLOR : UI_DIM_TEXT_COLOR)
	}
	scroll_list_end(state, &list)
	return activated
}

// A game of this build joins; another build's host would refuse it.
join_lan_game :: proc(state: ^Ui_State, title: ^Title_State, game: Lan_Game) {
	if !game.same_build {
		ui_toast(state, text("multiplayer_other_build_refused"))
		return
	}
	request_join(title, lan_game_join_address(game))
}

// The field's address joins once it is not blank.
join_typed_address :: proc(state: ^Ui_State, title: ^Title_State) {
	address := strings.trim_space(text_field_text(&title.multiplayer.address))
	if address == "" {
		ui_toast(state, text("multiplayer_address_empty"))
		return
	}
	request_join(title, address)
}

multiplayer_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	title := screen_context.title
	multiplayer := &title.multiplayer
	ui_backdrop(state)
	area := ui_panel_area(state)
	address_label := text("multiplayer_address")
	address_id := ui_id(state, address_label)
	// The address is the screen's one field.
	if state.keyboard.field != 0 {
		panel := fitted_panel(area, MULTIPLAYER_PANEL_WIDTH, panel_height(2, keyboard_keys_height(state.keyboard)))
		ui_panel_begin(state, "multiplayer", panel)
		content := inset(panel, UI_PADDING)
		field_row := cut_row(&content)
		draw_text_field_content(state, field_row, address_label, &multiplayer.address, true)
		if ui_on_screen_keyboard(state, field_row, {content.x + (content.width - KEYBOARD_WIDTH) / 2, content.y}, &multiplayer.address) {
			state.keyboard = Keyboard_State {
				return_focus = state.keyboard.field,
			}
		}
		ui_panel_end(state)
		keyboard_glyph_bar(state)
		return
	}
	if state.keyboard.return_focus != 0 {
		state.requested_focus, state.keyboard.return_focus = state.keyboard.return_focus, 0
	}
	// The heading, the column headings, the list, the address row and the
	// button row.
	panel := fitted_panel(area, MULTIPLAYER_PANEL_WIDTH, panel_height(MULTIPLAYER_LIST_ROWS + 4, -UI_GAP))
	ui_panel_begin(state, "multiplayer", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_row(&content), text("multiplayer_title"), UI_HEADING_TEXT_SIZE, .Centre)
	back_row := cut_bottom(&content, UI_ROW_HEIGHT)
	cut_bottom(&content, UI_GAP)
	address_row := cut_bottom(&content, UI_ROW_HEIGHT)
	cut_bottom(&content, UI_GAP)
	headings := Lan_Game_Cells {
		world   = text("multiplayer_world"),
		host    = text("multiplayer_host"),
		players = text("multiplayer_players"),
		build   = text("multiplayer_build"),
	}
	draw_lan_game_row(state, cut_top(&content, UI_ROW_HEIGHT), headings, UI_DIM_TEXT_COLOR)
	if len(multiplayer.games) == 0 {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("multiplayer_searching"), UI_BODY_TEXT_SIZE, .Centre, UI_DIM_TEXT_COLOR)
	}
	if activated := lan_game_list(state, content, multiplayer); activated >= 0 {
		join_lan_game(state, title, multiplayer.games[activated])
	}
	if ui_text_field(state, cut_left(&address_row, address_row.width * ADDRESS_FIELD_SHARE), address_label, &multiplayer.address) {
		open_keyboard(state, address_id)
	}
	cut_left(&address_row, UI_GAP)
	if ui_button(state, address_row, text("multiplayer_join")) {
		join_typed_address(state, title)
	}
	if ui_button(state, back_row, text("multiplayer_back")) {
		pop_screen(&state.screens)
	}
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_join")}, {.Back, text("hint_back")}}
	ui_glyph_bar_or_back_row(state, hints[:])
}
