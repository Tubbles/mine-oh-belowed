package game

import "core:math"

// Per block texture variation (work item 0088), done in the chunk and
// water fragment shaders (data/shaders/chunk.fs and water.fs) and
// mirrored here so the choice can be tested. A hash of the block's
// integer world position picks one of eight orientations of the tile
// inside the block (a mirror of x, then zero to three quarter turns), an
// offset of whole texels that slides the periodic tile inside the block
// (work item 0101) and a brightness within TEXTURE_BRIGHTNESS_JITTER
// either way. How much of it a face takes is its Tile_Variation
// (face_tile_variation): the side faces of blocks with keep_orientation
// take neither the turn nor the offset, the other faces of framed blocks
// (the log ends, a picture rather than a periodic tile) the turn only;
// the mesher tells the chunk shader through the vertex colour's green
// channel (orientation_flag_green). Water takes the jitter only, in its
// own shader.

TEXTURE_BRIGHTNESS_JITTER :: 0.04
TILE_ORIENTATION_COUNT :: 8
// The shader's largest_tile_texcoord: keeps a varied texcoord inside the
// tile's last texel.
LARGEST_TILE_TEXCOORD :: 0.9999

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

// What the shader does to a face's tile: Full turns, mirrors and slides
// it, Turn only turns and mirrors it, Keep leaves it upright in place.
Tile_Variation :: enum u8 {
	Full,
	Turn,
	Keep,
}

// keep_orientation holds the side faces only: tops and bottoms (log
// rings, the grass top) have no up and still turn. framed holds the
// faces that turn: a picture with a centre never slides.
face_tile_variation :: proc(keep_orientation, framed: bool, group: Face_Group) -> Tile_Variation {
	if keep_orientation && group == .Side {
		return .Keep
	}
	if framed {
		return .Turn
	}
	return .Full
}

// Orientation 0 for a face that keeps its tile upright.
face_tile_orientation :: proc(hash: u32, variation: Tile_Variation) -> (turns: int, mirrored: bool) {
	if variation == .Keep {
		return 0, false
	}
	return tile_orientation(hash)
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

// Bits 3 to 6 for x and 7 to 10 for y, whole texels, 0 to
// ATLAS_TILE_SIZE - 1 each, as the shader's tile_offset.
tile_offset :: proc(hash: u32) -> [2]int {
	return {int((hash >> 3) & 15), int((hash >> 7) & 15)}
}

// Offset 0 unless the face varies fully.
face_tile_offset :: proc(hash: u32, variation: Tile_Variation) -> [2]int {
	if variation != .Full {
		return {}
	}
	return tile_offset(hash)
}

// A texcoord inside the tile slid by offset texels and wrapped inside
// the tile, 0 to 1 on both axes.
shift_tile_texcoord :: proc(texcoord: [2]f32, offset: [2]int) -> [2]f32 {
	shifted := texcoord + [2]f32{f32(offset.x), f32(offset.y)} / ATLAS_TILE_SIZE
	return shifted - {math.floor(shifted.x), math.floor(shifted.y)}
}

// The chunk shader's texcoord inside the tile: texcoord (0 to 1) as the
// face's own axes give it, mirrored and turned, clamped to the last
// texel, slid by the offset (none for Turn) and clamped again. A face
// that keeps its orientation keeps the texcoord.
varied_tile_texcoord :: proc(texcoord: [2]f32, hash: u32, variation: Tile_Variation) -> [2]f32 {
	if variation == .Keep {
		return texcoord
	}
	turns, mirrored := tile_orientation(hash)
	oriented := orient_tile_texcoord(texcoord, turns, mirrored)
	oriented = {min(oriented.x, LARGEST_TILE_TEXCOORD), min(oriented.y, LARGEST_TILE_TEXCOORD)}
	shifted := shift_tile_texcoord(oriented, face_tile_offset(hash, variation))
	return {min(shifted.x, LARGEST_TILE_TEXCOORD), min(shifted.y, LARGEST_TILE_TEXCOORD)}
}

// Bits 8 to 15 spread over 1 - TEXTURE_BRIGHTNESS_JITTER to
// 1 + TEXTURE_BRIGHTNESS_JITTER.
texture_variation_brightness :: proc(hash: u32) -> f32 {
	return 1 + TEXTURE_BRIGHTNESS_JITTER * (f32((hash >> 8) & 255) / 127.5 - 1)
}
