package game

import "core:strings"
import "core:testing"

// The codec's tolerance of changed types (work item 0047). Two versions
// of one struct cannot share a name in one build, so a value is written
// with one type and read into another: the top level struct's name is in
// no kind (only the fields' types are), which makes the read the same as
// a later build reading its own struct. Enum names this build lacks are
// made by patching the written name to another of the same length.

Save_Test_Written :: struct {
	kept:     u32,
	removed:  i16,
	stack:    Item_Stack,
	lane:     Belt_Lane,
	events:   Player_Events,
	per_lane: [Belt_Lane]i64,
	stacks:   [2]Item_Stack,
}

// kept and stack moved, removed is gone, added is new.
Save_Test_Read :: struct {
	lane:     Belt_Lane,
	added:    u64,
	per_lane: [Belt_Lane]i64,
	stacks:   [2]Item_Stack,
	stack:    Item_Stack,
	events:   Player_Events,
	kept:     u32,
}

Save_Test_Retyped :: struct {
	kept: u64,
}

save_test_written_value :: proc() -> Save_Test_Written {
	return Save_Test_Written {
		kept = 70_000,
		removed = -3,
		stack = {item = 12, count = 34},
		lane = .Right,
		events = {.Open_Machine, .Vein_Assayed},
		per_lane = {.Left = 5, .Right = -6},
		stacks = {{1, 2}, {3, 4}},
	}
}

save_test_written_bytes :: proc() -> [dynamic]byte {
	value := save_test_written_value()
	bytes := make([dynamic]byte, context.temp_allocator)
	write_value_of(&bytes, &value)
	return bytes
}

// Replaces the first occurrence of a name; both have the same length.
patch_saved_name :: proc(bytes: []byte, name, replacement: string) {
	at := strings.index(string(bytes), name)
	assert(at >= 0 && len(name) == len(replacement), name)
	copy(bytes[at:], replacement)
}

@(test)
test_struct_fields_match_by_name :: proc(t: ^testing.T) {
	bytes := save_test_written_bytes()
	written := save_test_written_value()
	read := Save_Test_Read {
		added = 77,
	}
	reader := Byte_Reader {
		data = bytes[:],
	}
	testing.expect(t, read_value_of(&reader, &read))
	testing.expect_value(t, bytes_left(reader), 0)
	testing.expect_value(t, read.kept, written.kept)
	testing.expect_value(t, read.stack, written.stack)
	testing.expect_value(t, read.lane, written.lane)
	testing.expect_value(t, read.events, written.events)
	testing.expect_value(t, read.per_lane, written.per_lane)
	testing.expect_value(t, read.stacks, written.stacks)
	testing.expect_value(t, read.added, 77)
}

@(test)
test_a_retyped_field_refuses_naming_it :: proc(t: ^testing.T) {
	bytes := save_test_written_bytes()
	retyped: Save_Test_Retyped
	reader := Byte_Reader {
		data = bytes[:],
	}
	testing.expect(t, !read_value_of(&reader, &retyped))
	testing.expect(t, strings.contains(reader.problem, "kept") && strings.contains(reader.problem, "Save_Test_Retyped"), reader.problem)
}

// An enum value, a bit set member and an enumerated array index whose
// names this build lacks read as zero, are dropped, and are skipped.
@(test)
test_enums_read_by_name :: proc(t: ^testing.T) {
	bytes := save_test_written_bytes()
	// The lane field writes the first Right, per_lane the second.
	patch_saved_name(bytes[:], "Right", "Rigxx")
	patch_saved_name(bytes[:], "Right", "Rigxx")
	patch_saved_name(bytes[:], "Vein_Assayed", "Vein_Assayxx")
	read := Save_Test_Read {
		lane = .Right,
	}
	reader := Byte_Reader {
		data = bytes[:],
	}
	testing.expect(t, read_value_of(&reader, &read))
	testing.expect_value(t, bytes_left(reader), 0)
	testing.expect_value(t, read.lane, Belt_Lane(0))
	testing.expect_value(t, read.events, Player_Events{.Open_Machine})
	testing.expect_value(t, read.per_lane, [Belt_Lane]i64{.Left = 5, .Right = 0})
	testing.expect_value(t, read.kept, 70_000)
}

Save_Test_Four :: struct {
	values: [4]i32,
	stacks: [4]Item_Stack,
}

Save_Test_Six :: struct {
	values: [6]i32,
	stacks: [6]Item_Stack,
}

Save_Test_Two :: struct {
	values: [2]i32,
	stacks: [2]Item_Stack,
}

// A longer array reads the saved elements and zeroes the rest; a shorter
// one refuses, naming the field and both counts.
@(test)
test_array_counts_may_grow_but_not_shrink :: proc(t: ^testing.T) {
	four := Save_Test_Four {
		values = {1, -2, 3, -4},
		stacks = {{1, 10}, {2, 20}, {3, 30}, {4, 40}},
	}
	bytes := make([dynamic]byte, context.temp_allocator)
	write_value_of(&bytes, &four)

	six := Save_Test_Six {
		values = {9, 9, 9, 9, 9, 9},
		stacks = {5 = {7, 7}},
	}
	reader := Byte_Reader {
		data = bytes[:],
	}
	testing.expect(t, read_value_of(&reader, &six))
	testing.expect_value(t, bytes_left(reader), 0)
	testing.expect_value(t, six.values, [6]i32{1, -2, 3, -4, 0, 0})
	testing.expect_value(t, six.stacks, [6]Item_Stack{{1, 10}, {2, 20}, {3, 30}, {4, 40}, {}, {}})

	two: Save_Test_Two
	reader = Byte_Reader {
		data = bytes[:],
	}
	testing.expect(t, !read_value_of(&reader, &two))
	testing.expect(t, strings.contains(reader.problem, "values of Save_Test_Two holds 4 saved elements, this build's array has 2"), reader.problem)
}

Save_Test_Without_Skipped :: struct {
	kept:  u32,
	other: i16,
}

Save_Test_With_Skipped :: struct {
	kept:    u32,
	skipped: u64 `save:"-"`,
	other:   i16,
}

// A field tagged save:"-" (Entity_Common.frame, 0174) leaves no trace: the
// struct encodes to the bytes of the struct without it, and reading leaves
// the field as it was.
@(test)
test_a_field_tagged_save_dash_is_left_out :: proc(t: ^testing.T) {
	without := Save_Test_Without_Skipped{kept = 7, other = -3}
	with := Save_Test_With_Skipped{kept = 7, skipped = 99, other = -3}
	without_bytes := make([dynamic]byte, context.temp_allocator)
	with_bytes := make([dynamic]byte, context.temp_allocator)
	write_value_of(&without_bytes, &without)
	write_value_of(&with_bytes, &with)
	testing.expect_value(t, string(with_bytes[:]), string(without_bytes[:]))
	read := Save_Test_With_Skipped{skipped = 5}
	reader := Byte_Reader{data = with_bytes[:]}
	testing.expect(t, read_value_of(&reader, &read))
	testing.expect_value(t, read, Save_Test_With_Skipped{kept = 7, skipped = 5, other = -3})
}
