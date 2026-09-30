package game

import "core:encoding/json"
import "core:fmt"
import "platform"

// Notes from data/notes.sjson (work item 0070): what the planet, the
// lease and the venture tell the player, collected in the journal's Notes
// tab. Each note unlocks with one milestone: a chapter reached, an item
// obtained, a technology researched or a quest done. The unlock is read
// from the simulation state every frame and nothing is saved, so a note
// shows as soon as its milestone holds, in a loaded world too.

NOTES_FILE_NAME :: "notes.sjson"

// Exactly one field is set. chapter counts from 1, the first chapter.
Note_Unlock_Definition :: struct {
	chapter:    int,
	item:       string,
	technology: string,
	quest:      string,
}

Note_Definition :: struct {
	id:        string,
	title_key: string,
	text_key:  string,
	unlock:    Note_Unlock_Definition,
}

Notes_File :: struct {
	notes: []Note_Definition,
}

Note_Unlock_Kind :: enum u8 {
	Chapter,
	Item,
	Technology,
	Quest,
}

// target is the chapter index (from 0), the Item_Id, the technology index
// or the quest index, by unlock_kind.
Note :: struct {
	id:          string,
	title_key:   string,
	text_key:    string,
	unlock_kind: Note_Unlock_Kind,
	target:      int,
}

// Notes in data order, which is the order of the milestones in play.
Note_Registry :: struct {
	notes: []Note,
}

parse_notes_file :: proc(data: []byte, allocator := context.allocator) -> (file: Notes_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

check_note_key :: proc(strings: map[string]string, owner, field, key: string) -> string {
	if key == "" || key not_in strings {
		return fmt.tprintf("note %q: %s %q is not in the string table", owner, field, key)
	}
	return ""
}

note_unlock_count :: proc(unlock: Note_Unlock_Definition) -> int {
	count := 0
	count += unlock.chapter != 0 ? 1 : 0
	count += unlock.item != "" ? 1 : 0
	count += unlock.technology != "" ? 1 : 0
	count += unlock.quest != "" ? 1 : 0
	return count
}

validate_note_definition :: proc(definitions: []Note_Definition, index: int, strings: map[string]string) -> string {
	definition := definitions[index]
	if definition.id == "" {
		return fmt.tprintf("note %d has no id", index)
	}
	for other in definitions[:index] {
		if other.id == definition.id {
			return fmt.tprintf("note id %q is defined twice", definition.id)
		}
	}
	if note_unlock_count(definition.unlock) != 1 {
		return fmt.tprintf("note %q needs exactly one unlock: chapter, item, technology or quest", definition.id)
	}
	if problem := check_note_key(strings, definition.id, "title_key", definition.title_key); problem != "" {
		return problem
	}
	return check_note_key(strings, definition.id, "text_key", definition.text_key)
}

find_quest_index :: proc(quests: Quest_Registry, id: string) -> int {
	for quest, index in quests.quests {
		if quest.id == id {
			return index
		}
	}
	return NO_QUEST
}

// The unlock's kind and target, or the problem when the target does not
// exist.
resolve_note_unlock :: proc(definition: Note_Definition, items: Item_Registry, technologies: Technology_Registry, quests: Quest_Registry) -> (kind: Note_Unlock_Kind, target: int, problem: string) {
	unlock := definition.unlock
	switch {
	case unlock.chapter != 0:
		if unlock.chapter < 1 || unlock.chapter > len(quests.chapters) {
			return .Chapter, 0, fmt.tprintf("note %q unlocks with chapter %d, the chapters are 1 to %d", definition.id, unlock.chapter, len(quests.chapters))
		}
		return .Chapter, unlock.chapter - 1, ""
	case unlock.item != "":
		item, found := find_item_id(items, unlock.item)
		if !found {
			return .Item, 0, fmt.tprintf("note %q unlocks with unknown item %q", definition.id, unlock.item)
		}
		return .Item, int(item), ""
	case unlock.technology != "":
		technology := find_technology(technologies, unlock.technology)
		if technology == NO_TECHNOLOGY {
			return .Technology, 0, fmt.tprintf("note %q unlocks with unknown technology %q", definition.id, unlock.technology)
		}
		return .Technology, technology, ""
	}
	quest := find_quest_index(quests, unlock.quest)
	if quest == NO_QUEST {
		return .Quest, 0, fmt.tprintf("note %q unlocks with unknown quest %q", definition.id, unlock.quest)
	}
	return .Quest, quest, ""
}

resolve_note_registry :: proc(file: Notes_File, items: Item_Registry, technologies: Technology_Registry, quests: Quest_Registry, strings: map[string]string, allocator := context.allocator) -> (registry: Note_Registry, problem: string) {
	registry.notes = make([]Note, len(file.notes), allocator)
	for definition, index in file.notes {
		note := Note{id = definition.id, title_key = definition.title_key, text_key = definition.text_key}
		problem = validate_note_definition(file.notes, index, strings)
		if problem == "" {
			note.unlock_kind, note.target, problem = resolve_note_unlock(definition, items, technologies, quests)
		}
		if problem != "" {
			delete(registry.notes, allocator)
			return {}, problem
		}
		registry.notes[index] = note
	}
	return registry, ""
}

load_note_registry :: proc(data_directory: string, items: Item_Registry, technologies: Technology_Registry, quests: Quest_Registry, strings: map[string]string, allocator := context.allocator) -> (registry: Note_Registry, ok: bool) {
	data, path := read_logged_data_file(data_directory, NOTES_FILE_NAME) or_return
	file, parse_error := parse_notes_file(data, allocator)
	if parse_error != nil {
		platform.log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	registry, problem = resolve_note_registry(file, items, technologies, quests, strings, allocator)
	if problem != "" {
		platform.log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}

// The unlock rules.

// A chapter is reached once any quest of it or of a later chapter is no
// longer locked: the active quest's chapter and every one before it, or
// every chapter once all quests are done.
chapter_reached :: proc(quests: Quest_Registry, quest_state: Quest_State, chapter: int) -> bool {
	if chapter < 0 || chapter >= len(quests.chapters) {
		return false
	}
	for progress in quest_state.progress[min(quests.chapters[chapter].first_quest, len(quest_state.progress)):] {
		if progress.status != .Locked {
			return true
		}
	}
	return false
}

quest_done :: proc(quest_state: Quest_State, quest: int) -> bool {
	return quest >= 0 && quest < len(quest_state.progress) && quest_state.progress[quest].status == .Done
}

technology_researched :: proc(unlocks: Recipe_Unlocks, technology: int) -> bool {
	return technology >= 0 && technology < len(unlocks.researched) && unlocks.researched[technology]
}

note_is_unlocked :: proc(note: Note, quests: Quest_Registry, quest_state: Quest_State, unlocks: Recipe_Unlocks) -> bool {
	switch note.unlock_kind {
	case .Chapter:
		return chapter_reached(quests, quest_state, note.target)
	case .Item:
		return item_is_obtained(unlocks.obtained, Item_Id(note.target))
	case .Technology:
		return technology_researched(unlocks, note.target)
	case .Quest:
		return quest_done(quest_state, note.target)
	}
	return false
}

// The unlocked notes for the journal, newest first: the milestones come
// in data order, so the list is that order reversed. In the temp
// allocator.
unlocked_notes :: proc(registry: Note_Registry, quests: Quest_Registry, quest_state: Quest_State, unlocks: Recipe_Unlocks) -> []int {
	result := make([dynamic]int, context.temp_allocator)
	#reverse for note, index in registry.notes {
		if note_is_unlocked(note, quests, quest_state, unlocks) {
			append(&result, index)
		}
	}
	return result[:]
}
