package game

import "core:fmt"
import "core:slice"
import "core:strings"
import "platform"

// --model-check (work item 0207, doc/build.md, The workbench): the checks
// of model_check.odin over the selected machines on stdout: first the
// reference models' counts line (0275), then per OBJ model its counts
// line with its caps and per machine one line per problem, last a
// summary. Exit 1 on any problem. No window, no raylib.

// A machine id the workbench names a file after: [a-z0-9_]+, so the
// file stays in its directory.
is_workbench_machine_id :: proc(id: string) -> bool {
	if id == "" {
		return false
	}
	for character in id {
		if !(character >= 'a' && character <= 'z' || character >= '0' && character <= '9' || character == '_') {
			return false
		}
	}
	return true
}

// all (when allowed): every machine with a model, in registry order;
// otherwise the comma separated ids. In the temp allocator. Shared with
// the preview.
model_workbench_selection :: proc(machines: Machine_Registry, list: string, allow_all: bool) -> (selected: []Machine_Id, problem: string) {
	chosen := make([dynamic]Machine_Id, context.temp_allocator)
	if list == "" {
		return nil, "no machine named"
	}
	if allow_all && list == "all" {
		for machine, index in machines.machines {
			if machine.model != "" {
				append(&chosen, Machine_Id(index))
			}
		}
		return chosen[:], ""
	}
	for id in strings.split(list, ",", context.temp_allocator) {
		if !is_workbench_machine_id(id) {
			return nil, fmt.tprintf("machine id %q is not [a-z0-9_]+", id)
		}
		machine, found := find_machine_id(machines, id)
		if !found {
			return nil, fmt.tprintf("unknown machine %q", id)
		}
		if machines.machines[machine].model == "" {
			return nil, fmt.tprintf("machine %q has no model", id)
		}
		append(&chosen, machine)
	}
	return chosen[:], ""
}

// 2 for a bad selection, 1 for any problem, 0 otherwise. Under all a
// voxel model is counted and skipped.
run_model_check :: proc(selection: string, machines: Machine_Registry, pitch_millimetres: int, data_directory: string) -> int {
	selected, problem := model_workbench_selection(machines, selection, true)
	if problem != "" {
		platform.log_printf("error: --model-check=%s: %s", selection, problem)
		return 2
	}
	// Out of the temp allocator, which is freed after each machine.
	selected = slice.clone(selected)
	defer delete(selected)
	fmt.println(model_references_line(model_reference_counts(data_directory, machines)))
	free_all(context.temp_allocator)
	counts: [Model_Check_Subject]int
	problem_count := 0
	for machine_id in selected {
		machine := machines.machines[machine_id]
		subject := model_check_subject(data_directory, machine)
		counts[subject] += 1
		if subject == .Voxel && selection == "all" {
			continue
		}
		if subject == .Obj {
			if model_counts, counts_problem := obj_model_counts(data_directory, machine); counts_problem == "" {
				fmt.println(model_counts_line(machine.id, model_counts, model_body_triangles_cap(machine.kind)))
			}
		}
		for found in check_machine_model(data_directory, machines.machines, machine, pitch_millimetres) {
			fmt.println(model_check_report_line(machine.id, found))
			problem_count += 1
		}
		free_all(context.temp_allocator)
	}
	checked := counts[.Obj] + counts[.Arm]
	skipped := selection == "all" ? counts[.Voxel] : 0
	fmt.printfln("model check: %d checked (%d obj, %d arm), %d voxel models skipped, %d problems", checked, counts[.Obj], counts[.Arm], skipped, problem_count)
	return problem_count > 0 ? 1 : 0
}
