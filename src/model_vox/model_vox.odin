package model_vox

import "core:encoding/endian"
import "core:fmt"
import "core:os"
import "../platform"

// MagicaVoxel .vox models (work item 0055), no raylib here: meshing is in
// model_mesh.odin and the upload in render_models.odin. A machine names
// its model by id in data/machines.sjson; the file is
// data/models/<id>.vox.
//
// The format: "VOX " and a version, then chunks of id (4 bytes), content
// size N and children size M (little endian i32), N content bytes and M
// children bytes. The MAIN chunk holds every other chunk as its children.
// Read here: SIZE (x, y, z voxels), XYZI (a count, then x, y, z and a
// palette index of one byte each per voxel) and RGBA (256 entries of r, g,
// b, a; entry i is palette index i + 1). Without RGBA the default palette
// applies. A file of several models has one SIZE and XYZI pair per model
// and a scene graph (nTRN, nGRP, nSHP) placing them: only the first model
// is read, without its transform; the scene graph and every other chunk
// (MATL, LAYR, rOBJ, ...) are skipped.
//
// MagicaVoxel is right handed with z up, the game right handed with y up:
// vox (x, y, z) is game (x, z, depth - 1 - y), depth being the model's vox
// y size, a turn about x that mirrors nothing. The model's minimum corner
// is the footprint's minimum corner.

MODELS_DIRECTORY :: "models"
MODEL_FILE_EXTENSION :: ".vox"
// MagicaVoxel's own limit per side.
MAXIMUM_MODEL_SIDE :: 256
VOX_PALETTE_SIZE :: 256
VOX_HEADER_SIZE :: 8
VOX_CHUNK_HEADER_SIZE :: 12
VOX_VOXEL_SIZE :: 4

// size is in game axes. cells holds a palette index per voxel (0 empty),
// at voxel_cell_index. palette[0] is unused.
Voxel_Model :: struct {
	size:        [3]i32,
	cells:       []u8,
	palette:     [VOX_PALETTE_SIZE][4]u8,
	// SIZE chunks in the file; only the first model is read.
	model_count: int,
}

Vox_Chunk :: struct {
	id:       string,
	content:  []byte,
	children: []byte,
}

// The MagicaVoxel default palette, 0xAABBGGRR, used when a file has no
// RGBA chunk. Entry 0 is unused.
@(rodata)
vox_default_palette := [VOX_PALETTE_SIZE]u32 {
	0x00000000, 0xffffffff, 0xffccffff, 0xff99ffff, 0xff66ffff, 0xff33ffff, 0xff00ffff, 0xffffccff,
	0xffccccff, 0xff99ccff, 0xff66ccff, 0xff33ccff, 0xff00ccff, 0xffff99ff, 0xffcc99ff, 0xff9999ff,
	0xff6699ff, 0xff3399ff, 0xff0099ff, 0xffff66ff, 0xffcc66ff, 0xff9966ff, 0xff6666ff, 0xff3366ff,
	0xff0066ff, 0xffff33ff, 0xffcc33ff, 0xff9933ff, 0xff6633ff, 0xff3333ff, 0xff0033ff, 0xffff00ff,
	0xffcc00ff, 0xff9900ff, 0xff6600ff, 0xff3300ff, 0xff0000ff, 0xffffffcc, 0xffccffcc, 0xff99ffcc,
	0xff66ffcc, 0xff33ffcc, 0xff00ffcc, 0xffffcccc, 0xffcccccc, 0xff99cccc, 0xff66cccc, 0xff33cccc,
	0xff00cccc, 0xffff99cc, 0xffcc99cc, 0xff9999cc, 0xff6699cc, 0xff3399cc, 0xff0099cc, 0xffff66cc,
	0xffcc66cc, 0xff9966cc, 0xff6666cc, 0xff3366cc, 0xff0066cc, 0xffff33cc, 0xffcc33cc, 0xff9933cc,
	0xff6633cc, 0xff3333cc, 0xff0033cc, 0xffff00cc, 0xffcc00cc, 0xff9900cc, 0xff6600cc, 0xff3300cc,
	0xff0000cc, 0xffffff99, 0xffccff99, 0xff99ff99, 0xff66ff99, 0xff33ff99, 0xff00ff99, 0xffffcc99,
	0xffcccc99, 0xff99cc99, 0xff66cc99, 0xff33cc99, 0xff00cc99, 0xffff9999, 0xffcc9999, 0xff999999,
	0xff669999, 0xff339999, 0xff009999, 0xffff6699, 0xffcc6699, 0xff996699, 0xff666699, 0xff336699,
	0xff006699, 0xffff3399, 0xffcc3399, 0xff993399, 0xff663399, 0xff333399, 0xff003399, 0xffff0099,
	0xffcc0099, 0xff990099, 0xff660099, 0xff330099, 0xff000099, 0xffffff66, 0xffccff66, 0xff99ff66,
	0xff66ff66, 0xff33ff66, 0xff00ff66, 0xffffcc66, 0xffcccc66, 0xff99cc66, 0xff66cc66, 0xff33cc66,
	0xff00cc66, 0xffff9966, 0xffcc9966, 0xff999966, 0xff669966, 0xff339966, 0xff009966, 0xffff6666,
	0xffcc6666, 0xff996666, 0xff666666, 0xff336666, 0xff006666, 0xffff3366, 0xffcc3366, 0xff993366,
	0xff663366, 0xff333366, 0xff003366, 0xffff0066, 0xffcc0066, 0xff990066, 0xff660066, 0xff330066,
	0xff000066, 0xffffff33, 0xffccff33, 0xff99ff33, 0xff66ff33, 0xff33ff33, 0xff00ff33, 0xffffcc33,
	0xffcccc33, 0xff99cc33, 0xff66cc33, 0xff33cc33, 0xff00cc33, 0xffff9933, 0xffcc9933, 0xff999933,
	0xff669933, 0xff339933, 0xff009933, 0xffff6633, 0xffcc6633, 0xff996633, 0xff666633, 0xff336633,
	0xff006633, 0xffff3333, 0xffcc3333, 0xff993333, 0xff663333, 0xff333333, 0xff003333, 0xffff0033,
	0xffcc0033, 0xff990033, 0xff660033, 0xff330033, 0xff000033, 0xffffff00, 0xffccff00, 0xff99ff00,
	0xff66ff00, 0xff33ff00, 0xff00ff00, 0xffffcc00, 0xffcccc00, 0xff99cc00, 0xff66cc00, 0xff33cc00,
	0xff00cc00, 0xffff9900, 0xffcc9900, 0xff999900, 0xff669900, 0xff339900, 0xff009900, 0xffff6600,
	0xffcc6600, 0xff996600, 0xff666600, 0xff336600, 0xff006600, 0xffff3300, 0xffcc3300, 0xff993300,
	0xff663300, 0xff333300, 0xff003300, 0xffff0000, 0xffcc0000, 0xff990000, 0xff660000, 0xff330000,
	0xff0000ee, 0xff0000dd, 0xff0000bb, 0xff0000aa, 0xff000088, 0xff000077, 0xff000055, 0xff000044,
	0xff000022, 0xff000011, 0xff00ee00, 0xff00dd00, 0xff00bb00, 0xff00aa00, 0xff008800, 0xff007700,
	0xff005500, 0xff004400, 0xff002200, 0xff001100, 0xffee0000, 0xffdd0000, 0xffbb0000, 0xffaa0000,
	0xff880000, 0xff770000, 0xff550000, 0xff440000, 0xff220000, 0xff110000, 0xffeeeeee, 0xffdddddd,
	0xffbbbbbb, 0xffaaaaaa, 0xff888888, 0xff777777, 0xff555555, 0xff444444, 0xff222222, 0xff111111,
}

voxel_cell_index :: proc(size: [3]i32, position: [3]i32) -> int {
	return int(position.x + size.x * (position.y + size.y * position.z))
}

voxel_in_bounds :: proc(size: [3]i32, position: [3]i32) -> bool {
	return position.x >= 0 && position.y >= 0 && position.z >= 0 && position.x < size.x && position.y < size.y && position.z < size.z
}

// Empty outside the model.
voxel_at :: proc(model: Voxel_Model, position: [3]i32) -> u8 {
	if !voxel_in_bounds(model.size, position) {
		return 0
	}
	return model.cells[voxel_cell_index(model.size, position)]
}

// MagicaVoxel z up to the game's y up; vox_size is the SIZE as written.
vox_to_game :: proc(vox, vox_size: [3]i32) -> [3]i32 {
	return {vox.x, vox.z, vox_size.y - 1 - vox.y}
}

vox_size_to_game :: proc(vox_size: [3]i32) -> [3]i32 {
	return {vox_size.x, vox_size.z, vox_size.y}
}

unpack_vox_colour :: proc(colour: u32) -> [4]u8 {
	return {u8(colour), u8(colour >> 8), u8(colour >> 16), u8(colour >> 24)}
}

vox_default_palette_colours :: proc() -> (palette: [VOX_PALETTE_SIZE][4]u8) {
	for colour, index in vox_default_palette {
		palette[index] = unpack_vox_colour(colour)
	}
	return palette
}

read_vox_i32 :: proc(data: []byte, offset: int) -> i32 {
	value, _ := endian.get_i32(data[offset:offset + 4], .Little)
	return value
}

// The chunk at offset in data and the offset after it.
read_vox_chunk :: proc(data: []byte, offset: int) -> (chunk: Vox_Chunk, next: int, problem: string) {
	if len(data) - offset < VOX_CHUNK_HEADER_SIZE {
		return {}, 0, fmt.tprintf("a chunk header at byte %d is cut short", offset)
	}
	chunk.id = string(data[offset:offset + 4])
	content_size := int(read_vox_i32(data, offset + 4))
	children_size := int(read_vox_i32(data, offset + 8))
	start := offset + VOX_CHUNK_HEADER_SIZE
	if content_size < 0 || children_size < 0 || content_size > len(data) - start || children_size > len(data) - start - content_size {
		return {}, 0, fmt.tprintf("%s chunk: its sizes (%d and %d bytes) run past the end", chunk.id, content_size, children_size)
	}
	chunk.content = data[start:start + content_size]
	chunk.children = data[start + content_size:start + content_size + children_size]
	return chunk, start + content_size + children_size, ""
}

parse_vox_size :: proc(content: []byte) -> (size: [3]i32, problem: string) {
	if len(content) < 12 {
		return {}, "SIZE chunk: shorter than 12 bytes"
	}
	vox := [3]i32{read_vox_i32(content, 0), read_vox_i32(content, 4), read_vox_i32(content, 8)}
	for side in vox {
		if side < 1 || side > MAXIMUM_MODEL_SIDE {
			return {}, fmt.tprintf("SIZE chunk: a side of %d is outside 1 to %d", side, MAXIMUM_MODEL_SIDE)
		}
	}
	return vox_size_to_game(vox), ""
}

parse_vox_voxels :: proc(model: ^Voxel_Model, content: []byte) -> string {
	if len(content) < 4 {
		return "XYZI chunk: shorter than its voxel count"
	}
	vox_size := game_size_to_vox(model.size)
	count := int(read_vox_i32(content, 0))
	if count < 0 || count > (len(content) - 4) / VOX_VOXEL_SIZE {
		return fmt.tprintf("XYZI chunk: %d voxels do not fit in %d bytes", count, len(content))
	}
	for index in 0 ..< count {
		voxel := content[4 + index * VOX_VOXEL_SIZE:][:VOX_VOXEL_SIZE]
		vox := [3]i32{i32(voxel[0]), i32(voxel[1]), i32(voxel[2])}
		position := vox_to_game(vox, vox_size)
		if !voxel_in_bounds(model.size, position) {
			return fmt.tprintf("XYZI chunk: voxel %d at (%d, %d, %d) lies outside the SIZE", index, voxel[0], voxel[1], voxel[2])
		}
		if voxel[3] == 0 {
			return fmt.tprintf("XYZI chunk: voxel %d has palette index 0", index)
		}
		model.cells[voxel_cell_index(model.size, position)] = voxel[3]
	}
	return ""
}

// The SIZE as written in the file, from the game size.
game_size_to_vox :: proc(size: [3]i32) -> [3]i32 {
	return {size.x, size.z, size.y}
}

parse_vox_palette :: proc(model: ^Voxel_Model, content: []byte) -> string {
	if len(content) < VOX_PALETTE_SIZE * 4 {
		return fmt.tprintf("RGBA chunk: %d bytes, not %d", len(content), VOX_PALETTE_SIZE * 4)
	}
	for index in 0 ..< VOX_PALETTE_SIZE - 1 {
		entry := content[index * 4:][:4]
		model.palette[index + 1] = {entry[0], entry[1], entry[2], entry[3]}
	}
	return ""
}

// One child of MAIN. The first SIZE and the XYZI after it make the model.
parse_vox_child :: proc(model: ^Voxel_Model, chunk: Vox_Chunk, voxels_read: ^bool, allocator := context.allocator) -> string {
	switch chunk.id {
	case "SIZE":
		model.model_count += 1
		if model.model_count > 1 {
			return ""
		}
		size, problem := parse_vox_size(chunk.content)
		if problem != "" {
			return problem
		}
		model.size = size
		model.cells = make([]u8, int(size.x * size.y * size.z), allocator)
	case "XYZI":
		if model.model_count == 0 {
			return "XYZI chunk: comes before any SIZE chunk"
		}
		if voxels_read^ {
			return ""
		}
		voxels_read^ = true
		return parse_vox_voxels(model, chunk.content)
	case "RGBA":
		return parse_vox_palette(model, chunk.content)
	}
	return ""
}

// The problem names the chunk; load_voxel_model_file adds the file.
// cells is in allocator, also on a problem.
parse_voxel_model :: proc(data: []byte, allocator := context.allocator) -> (model: Voxel_Model, problem: string) {
	if len(data) < VOX_HEADER_SIZE || string(data[:4]) != "VOX " {
		return {}, "header: not a MagicaVoxel file (no \"VOX \" at the start)"
	}
	main_chunk, _, main_problem := read_vox_chunk(data, VOX_HEADER_SIZE)
	if main_problem != "" {
		return {}, main_problem
	}
	if main_chunk.id != "MAIN" {
		return {}, fmt.tprintf("%s chunk: the first chunk must be MAIN", main_chunk.id)
	}
	model.palette = vox_default_palette_colours()
	voxels_read := false
	for offset := 0; offset < len(main_chunk.children); {
		chunk: Vox_Chunk
		chunk, offset, problem = read_vox_chunk(main_chunk.children, offset)
		if problem == "" {
			problem = parse_vox_child(&model, chunk, &voxels_read, allocator)
		}
		if problem != "" {
			return model, problem
		}
	}
	if model.model_count == 0 {
		return model, "SIZE chunk: missing"
	}
	if !voxels_read {
		return model, "XYZI chunk: missing"
	}
	return model, ""
}

// In the temp allocator.
model_file_path :: proc(data_directory, id: string) -> string {
	return platform.join_path(data_directory, MODELS_DIRECTORY, fmt.tprintf("%s%s", id, MODEL_FILE_EXTENSION))
}

// The problem names the file and the chunk.
load_voxel_model_file :: proc(path: string, allocator := context.allocator) -> (model: Voxel_Model, problem: string) {
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		return {}, fmt.tprintf("cannot read %s: %v", path, read_error)
	}
	model, problem = parse_voxel_model(data, allocator)
	if problem != "" {
		delete(model.cells, allocator)
		return {}, fmt.tprintf("invalid model %s: %s", path, problem)
	}
	return model, ""
}
