package sjson_text

import "core:encoding/json"
import "core:strings"
import "core:testing"

// Work item 0130: the SJSON writer. json_values_equal is a copy of the
// game's test helper of the same name (data_browser_test.odin): test
// files of one package do not see another's.

// Two trees are equal, integers and floats told apart.
json_values_equal :: proc(first, second: json.Value) -> bool {
	#partial switch value in first {
	case json.Object:
		other, is_object := second.(json.Object)
		if !is_object || len(other) != len(value) {
			return false
		}
		for key, member in value {
			other_member, found := other[key]
			if !found || !json_values_equal(member, other_member) {
				return false
			}
		}
		return true
	case json.Array:
		other, is_array := second.(json.Array)
		if !is_array || len(other) != len(value) {
			return false
		}
		for element, index in value {
			if !json_values_equal(element, other[index]) {
				return false
			}
		}
		return true
	case json.Integer:
		other, is_integer := second.(json.Integer)
		return is_integer && other == value
	case json.Float:
		other, is_float := second.(json.Float)
		return is_float && other == value
	case json.Boolean:
		other, is_boolean := second.(json.Boolean)
		return is_boolean && other == value
	case json.String:
		other, is_string := second.(json.String)
		return is_string && other == value
	case json.Null:
		_, is_null := second.(json.Null)
		return is_null
	}
	return false
}

// The text written for a tree parses back to an equal tree, in the data
// files' style.
@(test)
test_sjson_text_parses_back_to_an_equal_tree :: proc(t: ^testing.T) {
	source := `
name = "Mine \"oh\" Belowed"
tick_rate = 60
speed = 16.0
share = 0.5
tiny = 0.00001
large = 2500000.0
below = -3
cold = -0.25
path = "C:\\data\ttab\nline"
"true" = 1
on = false
nothing = null
"odd key" = "{count} × {name}"
starting_items = [
	{item = "torch", count = 64}
]
made_in = ["hand", "assembler"]
nested = {deep = [[1, 2], []], empty = {}}
`
	value, error := json.parse_string(source, .SJSON, true, context.temp_allocator)
	testing.expect_value(t, error, json.Error.None)
	written := sjson_text(value, context.temp_allocator)
	parsed, parse_error := json.parse_string(written, .SJSON, true, context.temp_allocator)
	testing.expect_value(t, parse_error, json.Error.None)
	testing.expect(t, json_values_equal(value, parsed), written)
	for wanted in ([]string{"tick_rate = 60\n", "speed = 16.0\n", "share = 0.5\n", "starting_items = [\n\t{count = 64, item = \"torch\"}\n]\n", `made_in = ["hand", "assembler"]`, `"odd key" = "{count} × {name}"`, `name = "Mine \"oh\" Belowed"`, "\tempty = {}\n", "\t\t[1, 2]\n", "tiny = 1e-05\n", "large = 2.5e+06\n", "below = -3\n", "cold = -0.25\n", `path = "C:\\data\ttab\nline"`, `"true" = 1`}) {
		testing.expectf(t, strings.contains(written, wanted), "%q not in %s", wanted, written)
	}

}
