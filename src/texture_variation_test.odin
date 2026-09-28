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
// flagged blocks keep it.
@(test)
test_flagged_faces_keep_orientation_zero :: proc(t: ^testing.T) {
	for hash in u32(0) ..< 64 {
		turns, mirrored := face_tile_orientation(hash, true)
		testing.expect_value(t, turns, 0)
		testing.expect_value(t, mirrored, false)
		free_turns, free_mirrored := face_tile_orientation(hash, false)
		expected_turns, expected_mirrored := tile_orientation(hash)
		testing.expect_value(t, free_turns, expected_turns)
		testing.expect_value(t, free_mirrored, expected_mirrored)
	}
	testing.expect(t, face_keeps_orientation(true, .Side))
	testing.expect(t, !face_keeps_orientation(true, .Top))
	testing.expect(t, !face_keeps_orientation(true, .Bottom))
	testing.expect(t, !face_keeps_orientation(false, .Side))
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
