package game

import "core:testing"

// Work item 0101: the chunk shader slides every varying tile by a per
// block offset and wraps it inside the tile, so a varying tile must be
// periodic: its seam across the wrap (column 15 beside column 0, row 15
// beside row 0) no rougher than the edges between its interior texels.
// Framed blocks (the log ends) are left out: their faces are a picture
// with a centre, not periodic by design, and the shader turns them but
// never slides them.
// The factor was settled by measuring (2026-09-28 log): a periodic tile
// shifted cyclically, so that each of its interior lines of edges takes a
// turn as the wrap, reaches ratios up to 2.3 (tar pit, whose rare glossy
// texels weigh on a line of 16 edges), and the brick's wrap lies on a
// mortar line (2.0). A seam shows where the interior is smooth and the
// wrap jumps, and there the ratio runs far higher.
TILE_WRAP_ROUGHNESS_FACTOR :: 2.5

// Mean absolute channel difference, red, green and blue.
texel_difference :: proc(first, second: [4]u8) -> f32 {
	total: f32
	for channel in 0 ..< 3 {
		total += abs(f32(first[channel]) - f32(second[channel]))
	}
	return total / 3
}

// The mean texel difference across the edges between neighbouring texels
// inside the tile, and across the wrap edge.
tile_edge_roughness :: proc(tile: Tile_Pixels) -> (interior, wrap: f32) {
	last := ATLAS_TILE_SIZE - 1
	for row in 0 ..< ATLAS_TILE_SIZE {
		for column in 0 ..< last {
			interior += texel_difference(tile[texel_index(column, row)], tile[texel_index(column + 1, row)])
			interior += texel_difference(tile[texel_index(row, column)], tile[texel_index(row, column + 1)])
		}
		wrap += texel_difference(tile[texel_index(last, row)], tile[texel_index(0, row)])
		wrap += texel_difference(tile[texel_index(row, last)], tile[texel_index(row, 0)])
	}
	return interior / f32(2 * ATLAS_TILE_SIZE * last), wrap / f32(2 * ATLAS_TILE_SIZE)
}

// Cover plants and the torch are drawn per cell with clear texels.
tile_is_opaque :: proc(tile: Tile_Pixels) -> bool {
	for texel in tile {
		if texel.a != 255 {
			return false
		}
	}
	return true
}

@(test)
test_varying_block_tiles_are_periodic :: proc(t: ^testing.T) {
	registry := shipped_block_registry(t)
	checked := 0
	for definition in registry.definitions {
		if definition.framed {
			continue
		}
		tiles := read_block_face_tiles(test_data_directory(), definition.id)
		for group in Face_Group {
			tile, found := tiles[group].?
			if !found || face_tile_variation(definition.keep_orientation, false, group) == .Keep || !tile_is_opaque(tile) {
				continue
			}
			interior, wrap := tile_edge_roughness(tile)
			testing.expectf(t, wrap <= TILE_WRAP_ROUGHNESS_FACTOR * interior, "%s %v: the wrap edge differs by %.2f, the interior by %.2f", definition.id, group, wrap, interior)
			checked += 1
		}
	}
	testing.expect(t, checked > 0, "some tiles vary")
}

// A smooth ramp across the tile jumps back at the wrap and is flagged; the
// same ramp up and down again wraps and passes.
@(test)
test_tile_edge_roughness_flags_a_seam :: proc(t: ^testing.T) {
	ramp, ridge: Tile_Pixels
	for index in 0 ..< TEXTURE_TEXEL_COUNT {
		x := index % ATLAS_TILE_SIZE
		ramp[index] = {u8(100 + 8 * x), 90, 80, 255}
		ridge[index] = {u8(100 + 16 * min(x, ATLAS_TILE_SIZE - x)), 90, 80, 255}
	}
	interior, wrap := tile_edge_roughness(ramp)
	testing.expectf(t, wrap > TILE_WRAP_ROUGHNESS_FACTOR * interior, "the ramp: interior %.2f wrap %.2f", interior, wrap)
	interior, wrap = tile_edge_roughness(ridge)
	testing.expectf(t, wrap <= TILE_WRAP_ROUGHNESS_FACTOR * interior, "the ridge: interior %.2f wrap %.2f", interior, wrap)
}
