package game

// Per block texture variation (work item 0088), done in the chunk and
// water fragment shaders (data/shaders/chunk.fs and water.fs) and
// mirrored here so the choice can be tested. A hash of the block's
// integer world position picks one of eight orientations of the tile
// inside the block (a mirror of x, then zero to three quarter turns) and
// a brightness within TEXTURE_BRIGHTNESS_JITTER either way. Water keeps
// its orientation, as do the side faces of blocks with keep_orientation
// (face_keeps_orientation); the mesher tells the shader through the
// vertex colour's green channel (orientation_flag_green).

TEXTURE_BRIGHTNESS_JITTER :: 0.04
TILE_ORIENTATION_COUNT :: 8

// The coordinates mixed, then the lowbias32 finaliser. u32 arithmetic
// wraps, as the shader's uint does.
texture_variation_hash :: proc(cell: [3]i32) -> u32 {
	hash := u32(cell.x) * 73856093 ~ u32(cell.y) * 19349663 ~ u32(cell.z) * 83492791
	hash ~= hash >> 16
	hash *= 0x7feb352d
	hash ~= hash >> 15
	hash *= 0x846ca68b
	hash ~= hash >> 16
	return hash
}

// Bits 0 and 1 are the quarter turns, bit 2 the mirror.
tile_orientation :: proc(hash: u32) -> (turns: int, mirrored: bool) {
	return int(hash & 3), hash & 4 != 0
}

// Orientation 0 for a face that keeps its tile upright.
face_tile_orientation :: proc(hash: u32, keeps_orientation: bool) -> (turns: int, mirrored: bool) {
	if keeps_orientation {
		return 0, false
	}
	return tile_orientation(hash)
}

// keep_orientation holds the side faces only: tops and bottoms (log
// rings, the grass top) have no up and still vary.
face_keeps_orientation :: proc(keep_orientation: bool, group: Face_Group) -> bool {
	return keep_orientation && group == .Side
}

// A texcoord inside the tile, 0 to 1 on both axes, mirrored then turned
// as the shader's oriented_tile_texcoord (without its clamp to the last
// texel).
orient_tile_texcoord :: proc(texcoord: [2]f32, turns: int, mirrored: bool) -> [2]f32 {
	oriented := texcoord
	if mirrored {
		oriented.x = 1 - oriented.x
	}
	switch turns {
	case 1:
		return {1 - oriented.y, oriented.x}
	case 2:
		return {1 - oriented.x, 1 - oriented.y}
	case 3:
		return {oriented.y, 1 - oriented.x}
	}
	return oriented
}

// Bits 8 to 15 spread over 1 - TEXTURE_BRIGHTNESS_JITTER to
// 1 + TEXTURE_BRIGHTNESS_JITTER.
texture_variation_brightness :: proc(hash: u32) -> f32 {
	return 1 + TEXTURE_BRIGHTNESS_JITTER * (f32((hash >> 8) & 255) / 127.5 - 1)
}
