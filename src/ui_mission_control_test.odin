package game

import "core:testing"

@(test)
test_notices_are_presented_by_their_key :: proc(t: ^testing.T) {
	testing.expect_value(t, notice_presentation("mc_arrival"), Notice_Presentation.Mission_Control)
	testing.expect_value(t, notice_presentation("mc_contract_survey_fee"), Notice_Presentation.Mission_Control)
	testing.expect_value(t, notice_presentation(ITEM_DISCOVERED_KEY), Notice_Presentation.Discovery_Card)
	testing.expect_value(t, notice_presentation(RESEARCH_COMPLETE_KEY), Notice_Presentation.Toast)
	testing.expect_value(t, notice_presentation(CAPSULE_LANDED_KEY), Notice_Presentation.Toast)
	testing.expect_value(t, notice_presentation(ORBITAL_SURVEY_KEY), Notice_Presentation.Toast)
	testing.expect_value(t, notice_presentation("mission"), Notice_Presentation.Toast)
}

@(test)
test_a_line_reveals_at_its_rate_then_holds_and_fades :: proc(t: ^testing.T) {
	testing.expect_value(t, revealed_characters(0), 0)
	testing.expect_value(t, revealed_characters(-1), 0)
	testing.expect_value(t, revealed_characters(0.5), 20)
	testing.expect_value(t, revealed_characters(1), MISSION_CONTROL_CHARACTERS_PER_SECOND)
	testing.expect_value(t, mission_control_reveal_seconds(80), 2)
	testing.expect_value(t, mission_control_line_seconds(80), 2 + MISSION_CONTROL_HOLD_SECONDS + MISSION_CONTROL_FADE_SECONDS)
	line := Mission_Control_Line{character_count = 80, seconds = 1.9}
	testing.expect(t, mission_control_line_revealing(line))
	testing.expect_value(t, mission_control_line_alpha(line), 1)
	line.seconds = 2
	testing.expect(t, !mission_control_line_revealing(line))
	line.seconds = mission_control_line_seconds(80) - MISSION_CONTROL_FADE_SECONDS / 2
	testing.expect_value(t, mission_control_line_alpha(line), 0.5)
	testing.expect(t, mission_control_cursor_visible(0))
	testing.expect(t, !mission_control_cursor_visible(0.3))
	testing.expect(t, mission_control_cursor_visible(0.5))
}

@(test)
test_revealed_lines_follow_the_wrapped_text :: proc(t: ^testing.T) {
	lines := []string{"Start with", "timber."}
	testing.expect_value(t, len(revealed_lines(lines, 0)), 0)
	partial := revealed_lines(lines, 5)
	testing.expect_value(t, len(partial), 1)
	testing.expect_value(t, partial[0], "Start")
	// The break counts as the space it replaced.
	testing.expect_value(t, len(revealed_lines(lines, 11)), 1)
	second := revealed_lines(lines, 14)
	testing.expect_value(t, len(second), 2)
	testing.expect_value(t, second[1], "tim")
	whole := revealed_lines(lines, 100)
	testing.expect_value(t, whole[1], "timber.")
	testing.expect_value(t, rune_prefix("Zürich", 2), "Zü")
}

@(test)
test_the_queue_advances_by_time :: proc(t: ^testing.T) {
	state: Mission_Control_State
	defer destroy_mission_control(&state)
	testing.expect(t, push_mission_control_line(&state, "First line."))
	testing.expect(t, !push_mission_control_line(&state, "Second."))
	testing.expect_value(t, state.lines[0].character_count, 11)
	testing.expect_value(t, advance_mission_control(&state, 0.1), bit_set[Ui_Sound_Event]{})
	testing.expect_value(t, revealed_characters(state.lines[0].seconds), 4)
	// The first line runs its whole time, then the next starts with its
	// chime and runs its own.
	testing.expect_value(t, advance_mission_control(&state, mission_control_line_seconds(11) - 0.11), bit_set[Ui_Sound_Event]{})
	testing.expect_value(t, len(state.lines), 2)
	testing.expect_value(t, advance_mission_control(&state, 0.02), bit_set[Ui_Sound_Event]{.Mission_Control})
	testing.expect_value(t, len(state.lines), 1)
	testing.expect_value(t, state.lines[0].text, "Second.")
	testing.expect(t, state.lines[0].started)
	testing.expect_value(t, advance_mission_control(&state, mission_control_line_seconds(7) - 0.01), bit_set[Ui_Sound_Event]{})
	testing.expect_value(t, len(state.lines), 1)
	advance_mission_control(&state, 0.02)
	testing.expect_value(t, len(state.lines), 0)
	testing.expect_value(t, advance_mission_control(&state, 1), bit_set[Ui_Sound_Event]{})
}

@(test)
test_a_full_queue_drops_the_oldest_waiting_line :: proc(t: ^testing.T) {
	state: Mission_Control_State
	defer destroy_mission_control(&state)
	push_mission_control_line(&state, "shown")
	push_mission_control_line(&state, "oldest waiting")
	for _ in 2 ..< MISSION_CONTROL_QUEUE_CAPACITY {
		push_mission_control_line(&state, "waiting")
	}
	push_mission_control_line(&state, "newest")
	testing.expect_value(t, len(state.lines), MISSION_CONTROL_QUEUE_CAPACITY)
	testing.expect_value(t, state.lines[0].text, "shown")
	testing.expect_value(t, state.lines[1].text, "waiting")
	testing.expect_value(t, state.lines[MISSION_CONTROL_QUEUE_CAPACITY - 1].text, "newest")
}

@(test)
test_the_ui_routes_lines_and_cards_with_their_chimes :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	ui_mission_control_line(&state, "Hello.")
	testing.expect_value(t, state.sound_events, bit_set[Ui_Sound_Event]{.Mission_Control})
	state.sound_events = {}
	ui_mission_control_line(&state, "Again.")
	testing.expect_value(t, state.sound_events, bit_set[Ui_Sound_Event]{})
	ui_discovery_card(&state, Item_Id(3), "Hematite")
	testing.expect_value(t, state.sound_events, bit_set[Ui_Sound_Event]{.Discovery})
}

@(test)
test_the_discovery_card_shows_for_its_time :: proc(t: ^testing.T) {
	state: Mission_Control_State
	defer destroy_mission_control(&state)
	show_discovery_card(&state, Item_Id(2), "Coal")
	show_discovery_card(&state, Item_Id(5), "Hematite")
	testing.expect(t, state.discovery.active)
	testing.expect_value(t, state.discovery.name, "Hematite")
	testing.expect_value(t, state.discovery.item.?, Item_Id(5))
	advance_mission_control(&state, DISCOVERY_CARD_SECONDS - 0.1)
	testing.expect(t, state.discovery.active)
	advance_mission_control(&state, 0.2)
	testing.expect(t, !state.discovery.active)
}

@(test)
test_the_discovery_message_carries_its_item :: proc(t: ^testing.T) {
	content := make_test_content()
	quests: Quest_State
	defer destroy_quest_state(quests)
	hematite := test_item(content.items, "hematite")
	newly := []Item_Id{hematite}
	log_discoveries(&quests, content.blocks, content.items, newly, 7)
	testing.expect_value(t, len(quests.notices), 1)
	testing.expect_value(t, quests.notices[0].item.?, hematite)
	log_quest_message(&quests, 8, "mc_arrival")
	_, has_item := quests.notices[1].item.?
	testing.expect(t, !has_item)
}

@(test)
test_the_mark_stays_inside_its_square :: proc(t: ^testing.T) {
	area := Ui_Rectangle{100, 50, MISSION_CONTROL_MARK_SIZE, MISSION_CONTROL_MARK_SIZE}
	blocks := mission_control_mark_rectangles(area)
	for block in blocks {
		testing.expect(t, block.x >= area.x - 0.01 && block.x + block.width <= area.x + area.width + 0.01, "a block leaves the mark sideways")
		testing.expect(t, block.y >= area.y && block.y + block.height <= area.y + area.height + 0.01, "a block leaves the mark vertically")
	}
	// The apex is at the top centre, the arms end at the bottom corners.
	testing.expect_value(t, blocks[0], blocks[1])
	last := blocks[len(blocks) - 1]
	testing.expect(t, last.x > blocks[0].x)
}

@(test)
test_an_orbital_survey_starts_one_satellite_pass :: proc(t: ^testing.T) {
	memory: Particle_Memory
	messages := [dynamic]Quest_Message{}
	defer delete(messages)
	append(&messages, Quest_Message{text_key = ORBITAL_SURVEY_KEY})
	// A loaded world's survey starts nothing.
	update_satellite_pass(&memory, messages[:], 0.016)
	testing.expect(t, !memory.satellite.active)
	append(&messages, Quest_Message{text_key = "mc_arrival"})
	update_satellite_pass(&memory, messages[:], 0.016)
	testing.expect(t, !memory.satellite.active)
	append(&messages, Quest_Message{text_key = ORBITAL_SURVEY_KEY})
	update_satellite_pass(&memory, messages[:], 0.016)
	testing.expect(t, memory.satellite.active)
	testing.expect_value(t, memory.satellite.seconds, 0)
	// Steps a binary fraction long, so the sum is exact.
	for _ in 0 ..< 95 {
		update_satellite_pass(&memory, messages[:], 0.0625)
	}
	testing.expect(t, memory.satellite.active)
	update_satellite_pass(&memory, messages[:], 0.0625)
	testing.expect(t, !memory.satellite.active)
}

@(test)
test_the_satellite_crosses_the_map_through_the_pad :: proc(t: ^testing.T) {
	frame := map_frame_for({10, 20}, 1)
	span := f32(frame.size * frame.blocks_per_pixel)
	pad := [2]f32{10.5, 20.5}
	start := satellite_map_position(frame, pad, {active = true})
	middle := satellite_map_position(frame, pad, {active = true, seconds = SATELLITE_PASS_SECONDS / 2})
	end := satellite_map_position(frame, pad, {active = true, seconds = SATELLITE_PASS_SECONDS})
	testing.expect_value(t, start, [2]f32{pad.x - span / 2, pad.y})
	testing.expect_value(t, middle, pad)
	testing.expect_value(t, end, [2]f32{pad.x + span / 2, pad.y})
	// In the sky: from the western horizon over the top to the eastern one.
	west := satellite_sky_direction({active = true})
	top := satellite_sky_direction({active = true, seconds = SATELLITE_PASS_SECONDS / 2})
	east := satellite_sky_direction({active = true, seconds = SATELLITE_PASS_SECONDS})
	testing.expect(t, west.x < -0.99 && abs(west.y) < 0.01, "the pass starts on the western horizon")
	testing.expect(t, top.y > 0.9, "the pass crosses high in the sky")
	testing.expect(t, east.x > 0.99 && abs(east.y) < 0.01, "the pass ends on the eastern horizon")
}
