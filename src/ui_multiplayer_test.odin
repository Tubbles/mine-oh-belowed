package game

import "core:fmt"
import "core:testing"
import "core:time"
import "platform"

lan_test_answer :: proc(world: string, port: int) -> platform.Discovery_Message {
	return platform.Discovery_Message{kind = .Answer, world = world, host = "machine", build = BUILD_STAMP, players = 1, port = port}
}

// The screen lists the games from the answers; an answer refreshes its
// game, and a game whose last answer is three seconds old drops out
// between frames, after which the next frame's draw list reads only the
// games left.
@(test)
test_the_multiplayer_list_draws_its_games_and_drops_a_stale_one :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	multiplayer := &audit.title.multiplayer
	start := time.Tick{_nsec = 1_000_000_000}
	add_lan_answer(multiplayer, lan_test_answer("Alpha", 47_317), "192.168.1.20", true, start)
	add_lan_answer(multiplayer, lan_test_answer("Beta", 47_317), "192.168.1.21", true, start)
	add_lan_answer(multiplayer, lan_test_answer("Gamma", 47_318), "192.168.1.20", true, start)
	two_seconds_later := time.tick_add(start, 2 * time.Second)
	add_lan_answer(multiplayer, lan_test_answer("Beta renamed", 47_317), "192.168.1.21", true, two_seconds_later)
	testing.expect_value(t, len(multiplayer.games), 3)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Title)
	push_screen(&state.screens, .Multiplayer)
	screen_test_frame(audit, &state, {})
	for world in ([?]string{"Alpha", "Beta renamed", "Gamma"}) {
		testing.expectf(t, draw_list_has_text(state.draw_list[:], world), "%s not drawn", world)
	}
	prune_lan_games(multiplayer, time.tick_add(start, LAN_GAME_LIFETIME))
	testing.expect_value(t, len(multiplayer.games), 1)
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_has_text(state.draw_list[:], "Beta renamed"))
	testing.expect(t, !draw_list_has_text(state.draw_list[:], "Alpha"))
	testing.expect(t, !draw_list_has_text(state.draw_list[:], text("multiplayer_searching")))
	prune_lan_games(multiplayer, time.tick_add(two_seconds_later, LAN_GAME_LIFETIME))
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("multiplayer_searching")))
}

// A game of this build joins through the .Join request; another build's
// is refused with a toast, since its host would refuse it; the field's
// address joins trimmed, a blank one does not.
@(test)
test_a_join_from_the_screen_asks_the_loop :: proc(t: ^testing.T) {
	title := Title_State{multiplayer = make_multiplayer_state(), join_address = make_text_field("", TEXT_FIELD_CAPACITY)}
	defer destroy_multiplayer_state(&title.multiplayer)
	state: Ui_State
	defer destroy_ui_state(&state)
	add_lan_answer(&title.multiplayer, lan_test_answer("Other", 47_319), "10.0.0.5", false, {})
	join_lan_game(&state, &title, title.multiplayer.games[0])
	testing.expect_value(t, title.request.kind, Session_Request_Kind.None)
	testing.expect_value(t, len(state.toasts), 1)
	add_lan_answer(&title.multiplayer, lan_test_answer("Same", 47_318), "10.0.0.4", true, {})
	join_lan_game(&state, &title, title.multiplayer.games[1])
	testing.expect_value(t, title.request.kind, Session_Request_Kind.Join)
	testing.expect_value(t, text_field_text(&title.join_address), "10.0.0.4:47318")
	title.request = {}
	text_field_set(&title.multiplayer.address, "   ")
	join_typed_address(&state, &title)
	testing.expect_value(t, title.request.kind, Session_Request_Kind.None)
	text_field_set(&title.multiplayer.address, " 192.168.1.30:47320 ")
	join_typed_address(&state, &title)
	testing.expect_value(t, title.request.kind, Session_Request_Kind.Join)
	testing.expect_value(t, text_field_text(&title.join_address), "192.168.1.30:47320")
}

// Answers from more addresses than the list holds stop at its cap; a
// known game still refreshes.
@(test)
test_the_lan_game_list_is_capped :: proc(t: ^testing.T) {
	multiplayer := make_multiplayer_state()
	defer destroy_multiplayer_state(&multiplayer)
	for index in 0 ..< MAXIMUM_LAN_GAMES + 10 {
		add_lan_answer(&multiplayer, lan_test_answer("Flood", 47_317), fmt.tprintf("10.0.%d.%d", index / 256, index % 256), true, {})
	}
	testing.expect_value(t, len(multiplayer.games), MAXIMUM_LAN_GAMES)
	add_lan_answer(&multiplayer, lan_test_answer("Renamed", 47_317), "10.0.0.0", true, {})
	testing.expect_value(t, multiplayer.games[0].world, "Renamed")
}
