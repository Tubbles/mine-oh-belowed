package game

import "core:testing"

// The low three bits pick the orientation, so eight consecutive hashes
// give all eight, and a field of blocks shows all eight too.
@(test)
test_tile_orientation_covers_the_eight_cases :: proc(t: ^testing.T) {
	seen: [TILE_ORIENTATION_COUNT]bool
	for hash in u32(0) ..< TILE_ORIENTATION_COUNT {
		turns, mirrored := tile_orientation(hash)
		testing.expect(t, turns >= 0 && turns < 4)
		seen[turns + 4 * int(mirrored)] = true
	}
	testing.expect_value(t, seen, [TILE_ORIENTATION_COUNT]bool{true, true, true, true, true, true, true, true})
	field_counts: [TILE_ORIENTATION_COUNT]int
	for z in i32(-8) ..< 8 {
		for x in i32(-8) ..< 8 {
			turns, mirrored := tile_orientation(texture_variation_hash({x, 64, z}))
			field_counts[turns + 4 * int(mirrored)] += 1
		}
	}
	for count, orientation in field_counts {
		testing.expectf(t, count > 0, "orientation %d occurs in a 16 by 16 field", orientation)
	}
}

// A face that keeps its orientation is always upright; only side faces of
// flagged blocks keep it. A framed face turns like a free one.
@(test)
test_flagged_faces_keep_orientation_zero :: proc(t: ^testing.T) {
	for hash in u32(0) ..< 64 {
		turns, mirrored := face_tile_orientation(hash, .Keep)
		testing.expect_value(t, turns, 0)
		testing.expect_value(t, mirrored, false)
		expected_turns, expected_mirrored := tile_orientation(hash)
		for variation in ([2]Tile_Variation{.Full, .Turn}) {
			free_turns, free_mirrored := face_tile_orientation(hash, variation)
			testing.expect_value(t, free_turns, expected_turns)
			testing.expect_value(t, free_mirrored, expected_mirrored)
		}
	}
}

// keep_orientation holds the side faces, framed every other face of the
// block; a block with neither varies fully.
@(test)
test_face_tile_variation_per_flag_and_group :: proc(t: ^testing.T) {
	Case :: struct {
		keep_orientation, framed: bool,
		group:                    Face_Group,
		expected:                 Tile_Variation,
	}
	cases := [?]Case {
		{false, false, .Side, .Full},
		{false, false, .Top, .Full},
		{true, false, .Side, .Keep},
		{true, false, .Top, .Full},
		{true, false, .Bottom, .Full},
		{false, true, .Side, .Turn},
		{false, true, .Top, .Turn},
		{true, true, .Side, .Keep},
		{true, true, .Top, .Turn},
		{true, true, .Bottom, .Turn},
	}
	for test_case in cases {
		testing.expect_value(t, face_tile_variation(test_case.keep_orientation, test_case.framed, test_case.group), test_case.expected)
	}
}

// The eight orientations are the eight symmetries of the square: each
// sends the tile's corner texcoord (0.25, 0.125) somewhere else, and none
// leaves the tile.
@(test)
test_orient_tile_texcoord_gives_eight_distinct_symmetries :: proc(t: ^testing.T) {
	probe := [2]f32{0.25, 0.125}
	images: [TILE_ORIENTATION_COUNT][2]f32
	for orientation in 0 ..< TILE_ORIENTATION_COUNT {
		images[orientation] = orient_tile_texcoord(probe, orientation % 4, orientation >= 4)
		for axis in 0 ..< 2 {
			testing.expect(t, images[orientation][axis] >= 0 && images[orientation][axis] <= 1)
		}
		for earlier in 0 ..< orientation {
			testing.expectf(t, images[earlier] != images[orientation], "orientations %d and %d agree", earlier, orientation)
		}
	}
	testing.expect_value(t, images[0], probe)
	testing.expect_value(t, orient_tile_texcoord(probe, 1, false), [2]f32{0.875, 0.25})
}

// The brightness stays within the jitter and uses the whole range.
@(test)
test_texture_variation_brightness_stays_within_the_jitter :: proc(t: ^testing.T) {
	lowest, highest: f32 = 2, 0
	for z in i32(-16) ..< 16 {
		for x in i32(-16) ..< 16 {
			brightness := texture_variation_brightness(texture_variation_hash({x, -3, z}))
			lowest = min(lowest, brightness)
			highest = max(highest, brightness)
		}
	}
	testing.expect(t, lowest >= 1 - TEXTURE_BRIGHTNESS_JITTER && highest <= 1 + TEXTURE_BRIGHTNESS_JITTER)
	testing.expect(t, lowest < 0.97 && highest > 1.03, "the jitter spreads over its range")
	testing.expect_value(t, texture_variation_brightness(0), 1 - TEXTURE_BRIGHTNESS_JITTER)
	testing.expect_value(t, texture_variation_brightness(255 << 8), 1 + TEXTURE_BRIGHTNESS_JITTER)
}

// Neighbouring blocks get different hashes, so the variation changes from
// block to block; the hash is a pure function of the position.
@(test)
test_texture_variation_hash_differs_between_neighbours :: proc(t: ^testing.T) {
	testing.expect_value(t, texture_variation_hash({3, -7, 11}), texture_variation_hash({3, -7, 11}))
	centre := texture_variation_hash({0, 0, 0})
	for offset in direction_offsets {
		testing.expect(t, texture_variation_hash({offset.x, offset.y, offset.z}) != centre)
	}
}

// The offset takes its own bits: sixteen values on each axis, all 256
// pairs over the hashes of those bits, and a field of blocks spreads over
// every value on both axes.
@(test)
test_tile_offset_spreads_over_the_tile :: proc(t: ^testing.T) {
	seen: [ATLAS_TILE_SIZE * ATLAS_TILE_SIZE]bool
	for bits in u32(0) ..< ATLAS_TILE_SIZE * ATLAS_TILE_SIZE {
		// Every other bit set, so only bits 3 to 10 move the offset.
		offset := tile_offset(bits << 3 | 0xffff_f807)
		testing.expect(t, offset.x >= 0 && offset.x < ATLAS_TILE_SIZE && offset.y >= 0 && offset.y < ATLAS_TILE_SIZE)
		seen[offset.y * ATLAS_TILE_SIZE + offset.x] = true
	}
	for value, index in seen {
		testing.expectf(t, value, "offset %v occurs", [2]int{index % ATLAS_TILE_SIZE, index / ATLAS_TILE_SIZE})
	}
	testing.expect_value(t, tile_offset(0b1010_0110 << 3), [2]int{0b0110, 0b1010})
	x_counts, y_counts: [ATLAS_TILE_SIZE]int
	for z in i32(-16) ..< 16 {
		for x in i32(-16) ..< 16 {
			offset := tile_offset(texture_variation_hash({x, 12, z}))
			x_counts[offset.x] += 1
			y_counts[offset.y] += 1
		}
	}
	for value in 0 ..< ATLAS_TILE_SIZE {
		testing.expectf(t, x_counts[value] > 0 && y_counts[value] > 0, "offset %d occurs on both axes in a 32 by 32 field", value)
	}
}

// Only a face that varies fully slides: a framed face turns in place, a
// kept face keeps its texcoord.
@(test)
test_kept_faces_get_no_offset :: proc(t: ^testing.T) {
	probe := [2]f32{0.3, 0.8}
	for hash in u32(0) ..< 4096 {
		testing.expect_value(t, face_tile_offset(hash, .Keep), [2]int{})
		testing.expect_value(t, face_tile_offset(hash, .Turn), [2]int{})
		testing.expect_value(t, face_tile_offset(hash, .Full), tile_offset(hash))
		testing.expect_value(t, varied_tile_texcoord(probe, hash, .Keep), probe)
		turns, mirrored := tile_orientation(hash)
		testing.expect_value(t, varied_tile_texcoord(probe, hash, .Turn), orient_tile_texcoord(probe, turns, mirrored))
	}
}

// The varied texcoord is the oriented texel moved by the offset, wrapped
// inside the tile: texel centres land on texel centres, and the tile's
// last texel stays inside it.
@(test)
test_varied_tile_texcoord_shifts_whole_texels :: proc(t: ^testing.T) {
	for hash in u32(0) ..< 2048 {
		turns, mirrored := tile_orientation(hash)
		offset := tile_offset(hash)
		for y in 0 ..< ATLAS_TILE_SIZE {
			for x in 0 ..< ATLAS_TILE_SIZE {
				centre := ([2]f32{f32(x), f32(y)} + 0.5) / ATLAS_TILE_SIZE
				oriented := orient_tile_texcoord(centre, turns, mirrored) * ATLAS_TILE_SIZE
				expected := [2]int{(int(oriented.x) + offset.x) % ATLAS_TILE_SIZE, (int(oriented.y) + offset.y) % ATLAS_TILE_SIZE}
				varied := varied_tile_texcoord(centre, hash, .Full) * ATLAS_TILE_SIZE
				testing.expect_value(t, [2]int{int(varied.x), int(varied.y)}, expected)
			}
		}
		for corner in ([4][2]f32{{0, 0}, {1, 0}, {0, 1}, {1, 1}}) {
			varied := varied_tile_texcoord(corner, hash, .Full)
			testing.expect(t, varied.x >= 0 && varied.x < 1 && varied.y >= 0 && varied.y < 1)
		}
	}
}
