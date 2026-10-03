package game

import "core:testing"

// The workbench's selection (work item 0207), shared by --model-check and
// --model-preview.
@(test)
test_the_workbench_selection :: proc(t: ^testing.T) {
	machines := []Machine{{id = "a", model = "a"}, {id = "plain"}, {id = "b", model = "b"}}
	registry := Machine_Registry{machines = machines}
	all, all_problem := model_workbench_selection(registry, "all", true)
	testing.expect_value(t, all_problem, "")
	testing.expect_value(t, len(all), 2)
	if len(all) == 2 {
		testing.expect_value(t, all[0], Machine_Id(0))
		testing.expect_value(t, all[1], Machine_Id(2))
	}
	_, refused_all := model_workbench_selection(registry, "all", false)
	testing.expect_value(t, refused_all, `unknown machine "all"`)
	pair, pair_problem := model_workbench_selection(registry, "b,a", false)
	testing.expect_value(t, pair_problem, "")
	testing.expect_value(t, len(pair), 2)
	if len(pair) == 2 {
		testing.expect_value(t, pair[0], Machine_Id(2))
		testing.expect_value(t, pair[1], Machine_Id(0))
	}
	_, unknown := model_workbench_selection(registry, "c", false)
	testing.expect_value(t, unknown, `unknown machine "c"`)
	_, plain := model_workbench_selection(registry, "plain", false)
	testing.expect_value(t, plain, `machine "plain" has no model`)
	_, path := model_workbench_selection(registry, "a/b", false)
	testing.expect_value(t, path, `machine id "a/b" is not [a-z0-9_]+`)
	_, empty := model_workbench_selection(registry, "", true)
	testing.expect_value(t, empty, "no machine named")
}
