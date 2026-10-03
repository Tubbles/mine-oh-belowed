package game

import "core:strings"
import "core:testing"

@(test)
test_string_lookup_reports_missing_key_once :: proc(t: ^testing.T) {
	table, error := parse_string_table(transmute([]byte)string(`hello = "Hi"`))
	defer destroy_string_table(&table)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, lookup_text(&table, "hello"), "Hi")
	testing.expect_value(t, lookup_text(&table, "no_such_key"), "no_such_key")
	testing.expect_value(t, lookup_text(&table, "no_such_key"), "no_such_key")
	testing.expect_value(t, len(table.reported_missing), 1)
}

// Every key a screen passes to text() literally, found by scanning the source.
text_keys_in_source :: proc(source: string) -> []string {
	keys := make([dynamic]string, context.temp_allocator)
	rest := source
	for {
		start := strings.index(rest, `text("`)
		if start < 0 {
			break
		}
		rest = rest[start + len(`text("`):]
		end := strings.index_byte(rest, '"')
		append(&keys, rest[:end])
		rest = rest[end:]
	}
	return keys[:]
}

@(test)
test_shipped_strings_cover_the_ui :: proc(t: ^testing.T) {
	table, error := parse_string_table(#load("../data/strings/en.sjson"))
	defer destroy_string_table(&table)
	testing.expect_value(t, error, nil)
	sources := [?]string {
		#load("ui_screens.odin", string),
		#load("ui_widgets.odin", string),
		#load("hud.odin", string),
		#load("ui_journal.odin", string),
		#load("ui_technologies.odin", string),
		#load("ui_crafting_machines.odin", string),
		#load("ui_recipes.odin", string),
		#load("ui_inventory.odin", string),
		#load("ui_machine.odin", string),
		#load("ui_developer.odin", string),
		#load("hot_reload.odin", string),
	}
	key_count := 0
	for source in sources {
		for key in text_keys_in_source(source) {
			testing.expectf(t, key in table.entries, "key %q is used but not in en.sjson", key)
			key_count += 1
		}
	}
	testing.expect(t, key_count > 10)
	for entry in control_label_keys {
		testing.expectf(t, entry.key in table.entries, "glyph key %q is not in en.sjson", entry.key)
	}
	state_keys := make([dynamic]string, context.temp_allocator)
	for key in assembler_state_keys {
		append(&state_keys, key)
	}
	for key in lab_state_keys {
		append(&state_keys, key)
	}
	for key in technology_status_keys {
		append(&state_keys, key)
	}
	for key in research_refusal_keys {
		append(&state_keys, key)
	}
	for key in recipe_change_refusal_keys {
		append(&state_keys, key)
	}
	for key in field_refusal_keys {
		append(&state_keys, key)
	}
	for key in state_keys {
		testing.expectf(t, key == "" || key in table.entries, "key %q is not in en.sjson", key)
	}
	for key in ([?]string{"settings_stick_sensitivity", "settings_gyro_sensitivity", "settings_trackpad_sensitivity", "unit_block", "unit_blocks", REWARD_TARGET_CAPSULE_KEY, REWARD_TARGET_LOCKER_KEY, LOCKER_STOCKED_KEY, CAPSULE_LANDED_KEY}) {
		testing.expectf(t, key in table.entries, "key %q is not in en.sjson", key)
	}
}

// Work item 0070: every shipped item, machine and technology has a
// description, and its key is in the string table.
@(test)
test_shipped_descriptions_exist :: proc(t: ^testing.T) {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	items := make_test_items()
	_, technologies := make_test_recipes(items)
	keys := make([dynamic]string, context.temp_allocator)
	for item in items.items {
		testing.expectf(t, item.description_key != "", "item %q has no description_key", item.id)
		append(&keys, item.description_key)
	}
	for machine in make_test_machines().machines {
		testing.expectf(t, machine.description_key != "", "machine %q has no description_key", machine.id)
		append(&keys, machine.description_key)
	}
	for technology in technologies.technologies {
		testing.expectf(t, technology.description_key != "", "technology %q has no description_key", technology.id)
		append(&keys, technology.description_key)
	}
	for key in keys {
		testing.expectf(t, key == "" || key in table.entries, "description key %q is not in en.sjson", key)
	}
	testing.expect_value(t, validate_item_description_keys(items, table.entries), "")
	testing.expect_value(t, validate_machine_description_keys(make_test_machines(), table.entries), "")
	testing.expect_value(t, validate_technology_description_keys(technologies, table.entries), "")
}

@(test)
test_description_key_is_optional_but_must_resolve :: proc(t: ^testing.T) {
	table, error := parse_string_table(transmute([]byte)string(`describe_item_log = "Wood."`), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, description_key_problem(table.entries, "item", "log", ""), "")
	testing.expect_value(t, description_key_problem(table.entries, "item", "log", "describe_item_log"), "")
	testing.expect_value(t, description_key_problem(table.entries, "item", "log", "describe_item_nothing"), `item "log": description_key "describe_item_nothing" is not in the string table`)
}
