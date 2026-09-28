package game

import "core:testing"

// Work item 0091: the cost line comes from the string table, sign and all.
@(test)
test_technology_cost_text :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	items := make_test_items()
	_, technologies := make_test_recipes(items)
	automation := technologies.technologies[test_technology(technologies, "automation")]
	testing.expect_value(t, technology_cost_text(automation, 10, items), "10 × 10 s  (Science pack 1)")
}
