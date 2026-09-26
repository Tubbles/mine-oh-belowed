package game

Run :: struct {
	value: u16,
	count: u32,
}

run_length_encode :: proc(values: []u16, allocator := context.allocator) -> []Run {
	runs := make([dynamic]Run, 0, 0, allocator)
	for value in values {
		last_index := len(runs) - 1
		if last_index >= 0 && runs[last_index].value == value && runs[last_index].count < max(u32) {
			runs[last_index].count += 1
		} else {
			append(&runs, Run{value = value, count = 1})
		}
	}
	return runs[:]
}

run_length_decoded_length :: proc(runs: []Run) -> int {
	total := 0
	for run in runs {
		total += int(run.count)
	}
	return total
}

run_length_decode :: proc(runs: []Run, allocator := context.allocator) -> []u16 {
	values := make([]u16, run_length_decoded_length(runs), allocator)
	offset := 0
	for run in runs {
		for index in 0 ..< int(run.count) {
			values[offset + index] = run.value
		}
		offset += int(run.count)
	}
	return values
}
