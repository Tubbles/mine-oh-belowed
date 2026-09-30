package model_vox

import "core:encoding/endian"
import "core:os"
import "core:strings"
import "core:testing"
import "../platform"

// .vox loader tests (work item 0055): the shipped placeholder the script
// wrote, and small files built here from bytes. The one test that writes
// a file uses a temporary directory it creates and removes.

append_vox_i32 :: proc(bytes: ^[dynamic]byte, value: i32) {
	buffer: [4]byte
	endian.put_i32(buffer[:], .Little, value)
	append(bytes, ..buffer[:])
}

append_vox_chunk :: proc(bytes: ^[dynamic]byte, id: string, content: []byte, children: []byte = nil) {
	append(bytes, id)
	append_vox_i32(bytes, i32(len(content)))
	append_vox_i32(bytes, i32(len(children)))
	append(bytes, ..content)
	append(bytes, ..children)
}

// A file of one model: SIZE, XYZI (vox axes, x y z and palette index) and
// an RGBA chunk when palette is given. In the temp allocator.
make_vox_file :: proc(size: [3]i32, voxels: [][4]u8, palette: [][4]u8 = nil) -> []byte {
	context.allocator = context.temp_allocator
	size_content := make([dynamic]byte)
	for side in size {
		append_vox_i32(&size_content, side)
	}
	voxel_content := make([dynamic]byte)
	append_vox_i32(&voxel_content, i32(len(voxels)))
	for voxel in voxels {
		append(&voxel_content, voxel[0], voxel[1], voxel[2], voxel[3])
	}
	children := make([dynamic]byte)
	append_vox_chunk(&children, "SIZE", size_content[:])
	append_vox_chunk(&children, "XYZI", voxel_content[:])
	if palette != nil {
		rgba := make([]byte, VOX_PALETTE_SIZE * 4)
		for &colour, index in palette {
			copy(rgba[index * 4:], colour[:])
		}
		append_vox_chunk(&children, "RGBA", rgba)
	}
	file := make([dynamic]byte)
	append(&file, "VOX ")
	append_vox_i32(&file, 150)
	append_vox_chunk(&file, "MAIN", nil, children[:])
	return file[:]
}

@(test)
test_the_shipped_chest_model_loads :: proc(t: ^testing.T) {
	model, problem := parse_voxel_model(#load("../../data/models/wooden_chest.vox"))
	defer delete(model.cells)
	testing.expect_value(t, problem, "")
	// 16 voxels per block for a machine one block across.
	testing.expect_value(t, model.size, [3]i32{16, 16, 16})
	testing.expect_value(t, model.model_count, 1)
	// The latch on the front (+x), metal grey; the corner column is empty.
	testing.expect_value(t, model.palette[voxel_at(model, {14, 7, 7})], [4]u8{170, 170, 176, 255})
	testing.expect_value(t, voxel_at(model, {0, 0, 0}), 0)
	// The lid line is the dark row at height 8.
	testing.expect_value(t, model.palette[voxel_at(model, {2, 8, 2})], [4]u8{70, 45, 25, 255})
}

@(test)
test_vox_z_up_becomes_the_game_y_up :: proc(t: ^testing.T) {
	voxels := [?][4]u8{{1, 2, 3, 5}}
	model, problem := parse_voxel_model(make_vox_file({2, 3, 4}, voxels[:]))
	defer delete(model.cells)
	testing.expect_value(t, problem, "")
	// Vox y runs away from the viewer, game z towards them: vox y 2 of 3
	// is game z 0, so the model turns about x and is not mirrored.
	testing.expect_value(t, model.size, [3]i32{2, 4, 3})
	testing.expect_value(t, voxel_at(model, {1, 3, 0}), 5)
	testing.expect_value(t, voxel_at(model, {1, 3, 2}), 0)
	testing.expect_value(t, voxel_at(model, {1, 2, 3}), 0)
}

@(test)
test_vox_palette_is_the_default_without_rgba :: proc(t: ^testing.T) {
	voxels := [?][4]u8{{0, 0, 0, 1}}
	model, problem := parse_voxel_model(make_vox_file({1, 1, 1}, voxels[:]))
	defer delete(model.cells)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, model.palette[1], [4]u8{255, 255, 255, 255})
	testing.expect_value(t, model.palette[216], [4]u8{0xee, 0, 0, 255})
	testing.expect_value(t, model.palette[255], [4]u8{0x11, 0x11, 0x11, 255})

	// RGBA entry 0 is palette index 1.
	palette := [?][4]u8{{10, 20, 30, 255}}
	with_palette, palette_problem := parse_voxel_model(make_vox_file({1, 1, 1}, voxels[:], palette[:]))
	defer delete(with_palette.cells)
	testing.expect_value(t, palette_problem, "")
	testing.expect_value(t, with_palette.palette[1], [4]u8{10, 20, 30, 255})
}

@(test)
test_malformed_vox_files_are_refused_naming_the_chunk :: proc(t: ^testing.T) {
	outside := [?][4]u8{{2, 0, 0, 1}}
	index_zero := [?][4]u8{{0, 0, 0, 0}}
	truncated := make_vox_file({2, 2, 2}, nil)
	cases := [?]struct {
		data:  []byte,
		chunk: string,
	} {
		{transmute([]byte)string("PNG  and more bytes"), "header"},
		{truncated[:len(truncated) - 3], "MAIN chunk"},
		{make_vox_file({2, 2, 2}, outside[:]), "XYZI chunk"},
		{make_vox_file({2, 2, 2}, index_zero[:]), "XYZI chunk"},
		{make_vox_file({0, 2, 2}, nil), "SIZE chunk"},
		{make_vox_file({2, 2, 2}, nil)[:VOX_HEADER_SIZE + VOX_CHUNK_HEADER_SIZE], "MAIN chunk"},
	}
	for entry in cases {
		model, problem := parse_voxel_model(entry.data)
		delete(model.cells)
		testing.expectf(t, strings.has_prefix(problem, entry.chunk), "%q does not start with %q", problem, entry.chunk)
	}
}

@(test)
test_a_model_file_problem_names_the_file_and_the_chunk :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-model-test-*", context.temp_allocator)
	assert(error == nil)
	defer os.remove_all(directory)
	outside := [?][4]u8{{0, 0, 9, 1}}
	path := platform.join_path(directory, "broken.vox")
	assert(os.write_entire_file(path, make_vox_file({2, 2, 2}, outside[:])) == nil)
	model, problem := load_voxel_model_file(path)
	testing.expect(t, model.cells == nil)
	testing.expect(t, strings.contains(problem, path), problem)
	testing.expect(t, strings.contains(problem, "XYZI chunk"), problem)

	_, problem = load_voxel_model_file(platform.join_path(directory, "missing.vox"))
	testing.expect(t, strings.contains(problem, "missing.vox"), problem)
}

@(test)
test_a_file_of_several_models_reads_the_first :: proc(t: ^testing.T) {
	first := [?][4]u8{{0, 0, 0, 1}}
	file := make([dynamic]byte, context.temp_allocator)
	append(&file, ..make_vox_file({1, 1, 1}, first[:]))
	// A second SIZE and XYZI pair at the end of MAIN's children.
	second := make_vox_file({3, 3, 3}, first[:])
	second_children := second[VOX_HEADER_SIZE + VOX_CHUNK_HEADER_SIZE:]
	append(&file, ..second_children)
	endian.put_i32(file[VOX_HEADER_SIZE + 8:][:4], .Little, i32(len(file) - VOX_HEADER_SIZE - VOX_CHUNK_HEADER_SIZE))
	model, problem := parse_voxel_model(file[:])
	defer delete(model.cells)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, model.model_count, 2)
	testing.expect_value(t, model.size, [3]i32{1, 1, 1})
}
