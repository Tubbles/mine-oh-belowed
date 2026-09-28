package game

import "core:testing"

// The shipped notes resolved against the shipped content and strings.
make_test_notes :: proc(quests: Quest_Registry) -> Note_Registry {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	assert(error == nil)
	file, parse_error := parse_notes_file(#load("../data/notes.sjson"), context.temp_allocator)
	assert(parse_error == nil)
	items := make_test_items()
	_, technologies := make_test_recipes(items)
	registry, problem := resolve_note_registry(file, items, technologies, quests, table.entries, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

@(test)
test_shipped_notes_resolve :: proc(t: ^testing.T) {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	notes := make_test_notes(make_test_quests(make_test_quest_references()))
	testing.expectf(t, len(notes.notes) >= 20 && len(notes.notes) <= 30, "%d notes, the item asks for twenty to thirty", len(notes.notes))
	kinds: bit_set[Note_Unlock_Kind]
	for note in notes.notes {
		testing.expectf(t, note.title_key in table.entries, "note %q: missing %q", note.id, note.title_key)
		testing.expectf(t, note.text_key in table.entries, "note %q: missing %q", note.id, note.text_key)
		kinds += {note.unlock_kind}
	}
	testing.expect_value(t, kinds, bit_set[Note_Unlock_Kind]{.Chapter, .Item, .Technology, .Quest})
}

resolve_test_note :: proc(unlock: Note_Unlock_Definition, key := "note_the_asset_title") -> string {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	assert(error == nil)
	items := make_test_items()
	_, technologies := make_test_recipes(items)
	quests := make_test_quests(make_test_quest_references())
	file := Notes_File{notes = {{id = "note", title_key = key, text_key = "note_the_asset_text", unlock = unlock}}}
	_, problem := resolve_note_registry(file, items, technologies, quests, table.entries, context.temp_allocator)
	return problem
}

@(test)
test_note_validation :: proc(t: ^testing.T) {
	testing.expect_value(t, resolve_test_note({chapter = 1}), "")
	testing.expect_value(t, resolve_test_note({item = "hematite"}), "")
	testing.expect_value(t, resolve_test_note({technology = "deep_mining"}), "")
	testing.expect_value(t, resolve_test_note({quest = "arrival"}), "")
	testing.expect_value(t, resolve_test_note({}), `note "note" needs exactly one unlock: chapter, item, technology or quest`)
	testing.expect_value(t, resolve_test_note({chapter = 1, item = "hematite"}), `note "note" needs exactly one unlock: chapter, item, technology or quest`)
	testing.expect_value(t, resolve_test_note({chapter = 99}), `note "note" unlocks with chapter 99, the chapters are 1 to 8`)
	testing.expect_value(t, resolve_test_note({item = "unobtainium"}), `note "note" unlocks with unknown item "unobtainium"`)
	testing.expect_value(t, resolve_test_note({technology = "warp_drive"}), `note "note" unlocks with unknown technology "warp_drive"`)
	testing.expect_value(t, resolve_test_note({quest = "no_such_quest"}), `note "note" unlocks with unknown quest "no_such_quest"`)
	testing.expect_value(t, resolve_test_note({chapter = 1}, "note_no_such_key"), `note "note": title_key "note_no_such_key" is not in the string table`)
}

// Two chapters of two quests each.
Note_Test_World :: struct {
	quests:     Quest_Registry,
	progress:   [4]Quest_Progress,
	obtained:   [3]bool,
	researched: [2]bool,
}

make_note_test_world :: proc(world: ^Note_Test_World) -> (quest_state: Quest_State, unlocks: Recipe_Unlocks) {
	chapters := make([]Chapter, 2, context.temp_allocator)
	chapters[0] = Chapter{id = "first", first_quest = 0, quest_count = 2}
	chapters[1] = Chapter{id = "second", first_quest = 2, quest_count = 2}
	world.quests = Quest_Registry{chapters = chapters, quests = make([]Quest, 4, context.temp_allocator)}
	return Quest_State{progress = world.progress[:], active = NO_QUEST}, Recipe_Unlocks{obtained = world.obtained[:], researched = world.researched[:]}
}

@(test)
test_note_unlock_rules :: proc(t: ^testing.T) {
	world: Note_Test_World
	quest_state, unlocks := make_note_test_world(&world)
	quests := world.quests
	first_chapter := Note{unlock_kind = .Chapter, target = 0}
	second_chapter := Note{unlock_kind = .Chapter, target = 1}
	item := Note{unlock_kind = .Item, target = 2}
	technology := Note{unlock_kind = .Technology, target = 1}
	quest := Note{unlock_kind = .Quest, target = 1}
	// Before the first tick every quest is locked.
	for note in ([?]Note{first_chapter, second_chapter, item, technology, quest}) {
		testing.expect(t, !note_is_unlocked(note, quests, quest_state, unlocks))
	}
	world.progress[0].status, world.progress[1].status = .Done, .Active
	testing.expect(t, note_is_unlocked(first_chapter, quests, quest_state, unlocks))
	testing.expect(t, !note_is_unlocked(second_chapter, quests, quest_state, unlocks))
	testing.expect(t, !note_is_unlocked(quest, quests, quest_state, unlocks))
	world.progress[1].status, world.progress[2].status = .Done, .Active
	testing.expect(t, note_is_unlocked(second_chapter, quests, quest_state, unlocks))
	testing.expect(t, note_is_unlocked(quest, quests, quest_state, unlocks))
	// Every quest done: every chapter stays reached.
	for &progress in world.progress {
		progress.status = .Done
	}
	testing.expect(t, note_is_unlocked(second_chapter, quests, quest_state, unlocks))
	world.obtained[2] = true
	testing.expect(t, note_is_unlocked(item, quests, quest_state, unlocks))
	testing.expect(t, !note_is_unlocked(technology, quests, quest_state, unlocks))
	world.researched[1] = true
	testing.expect(t, note_is_unlocked(technology, quests, quest_state, unlocks))
	// Targets outside the tables never unlock.
	testing.expect(t, !note_is_unlocked(Note{unlock_kind = .Chapter, target = 2}, quests, quest_state, unlocks))
	testing.expect(t, !note_is_unlocked(Note{unlock_kind = .Item, target = 3}, quests, quest_state, unlocks))
	testing.expect(t, !note_is_unlocked(Note{unlock_kind = .Quest, target = 4}, quests, quest_state, unlocks))
}

@(test)
test_unlocked_notes_are_newest_first :: proc(t: ^testing.T) {
	world: Note_Test_World
	quest_state, unlocks := make_note_test_world(&world)
	notes := []Note{{id = "a", unlock_kind = .Item, target = 0}, {id = "b", unlock_kind = .Item, target = 1}, {id = "c", unlock_kind = .Item, target = 2}}
	registry := Note_Registry{notes = notes}
	world.obtained[0], world.obtained[2] = true, true
	testing.expect_value(t, len(unlocked_notes(registry, world.quests, quest_state, unlocks)), 2)
	shown := unlocked_notes(registry, world.quests, quest_state, unlocks)
	testing.expect_value(t, shown[0], 2)
	testing.expect_value(t, shown[1], 0)
}
