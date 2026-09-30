package platform

import "core:os"
import "core:strings"
import "core:testing"

// make_directory_path (work item 0117): mkdir -p that starts at the first
// missing directory instead of at /.
@(test)
test_make_directory_path_makes_missing_levels_and_tolerates_existing :: proc(t: ^testing.T) {
	base, error := os.make_directory_temp("", "mine-oh-belowed-directories-test-*", context.temp_allocator)
	testing.expect(t, error == nil)
	defer os.remove_all(base)
	nested, _ := os.join_path({base, "one", "two", "three"}, context.temp_allocator)
	testing.expect_value(t, make_directory_path(nested), nil)
	testing.expect(t, os.is_dir(nested))
	testing.expect_value(t, make_directory_path(nested), nil)
	sibling, _ := os.join_path({base, "one", "sibling"}, context.temp_allocator)
	testing.expect_value(t, make_directory_path(sibling), nil)
	testing.expect(t, os.is_dir(sibling))
	trailing, _ := os.join_path({base, "trailing", "slash"}, context.temp_allocator)
	testing.expect_value(t, make_directory_path(strings.concatenate({trailing, "/"}, context.temp_allocator)), nil)
	testing.expect(t, os.is_dir(trailing))
}

@(test)
test_trim_trailing_separators_keeps_the_root :: proc(t: ^testing.T) {
	testing.expect_value(t, trim_trailing_separators("/a/b//"), "/a/b")
	testing.expect_value(t, trim_trailing_separators("/a/b"), "/a/b")
	testing.expect_value(t, trim_trailing_separators("/"), "/")
}
