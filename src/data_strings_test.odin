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
	sources := [?]string{#load("ui_screens.odin", string), #load("hud.odin", string)}
	key_count := 0
	for source in sources {
		for key in text_keys_in_source(source) {
			testing.expectf(t, key in table.entries, "key %q is used but not in en.sjson", key)
			key_count += 1
		}
	}
	testing.expect(t, key_count > 10)
	for device in Input_Device {
		for button in Glyph_Button {
			key := glyph_key(device, button)
			testing.expectf(t, key in table.entries, "glyph key %q is not in en.sjson", key)
		}
	}
	for key in ([?]string{"settings_stick_sensitivity", "settings_gyro_sensitivity", "settings_trackpad_sensitivity", "unit_block", "unit_blocks"}) {
		testing.expectf(t, key in table.entries, "key %q is not in en.sjson", key)
	}
}
