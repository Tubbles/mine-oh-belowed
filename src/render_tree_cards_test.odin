package game

import "core:testing"

// The far trees' cards (work item 0310): a model bakes to its outline in
// each view, the mips keep each cell's coverage, the shipped tree models
// bake.

// The share of the cell's inner texels with alpha.
tree_card_test_coverage :: proc(cell: [][4]u8) -> f32 {
	low := [2]int{TREE_CARD_MARGIN_TEXELS, TREE_CARD_MARGIN_TEXELS}
	return tree_card_coverage(cell, TREE_CARD_CELL_TEXELS, low, low + TREE_CARD_INNER_TEXELS, 255)
}

// A box half as wide along x as along z and twice as tall: half the card
// along forward and from above, all of it along right.
@(test)
test_a_card_bakes_the_models_outline :: proc(t: ^testing.T) {
	layers := box_layers({-0.5, 0, -1}, {0.5, 2, 1})
	mesh := layers[.Lit]
	size := tree_card_size(mesh)
	testing.expect_value(t, size, Tree_Card_Size{half_width = 1, top = 2, crown = 2 * f32(TREE_CARD_CROWN_PERMILLE) / 1000})
	expected := [TREE_CARD_VIEWS]f32{0.5, 1, 0.5}
	cell := make([][4]u8, TREE_CARD_CELL_TEXELS * TREE_CARD_CELL_TEXELS, context.temp_allocator)
	for view in 0 ..< TREE_CARD_VIEWS {
		for &texel in cell {
			texel = {}
		}
		bake_tree_card(mesh, size, view, cell)
		coverage := tree_card_test_coverage(cell)
		testing.expectf(t, abs(coverage - expected[view]) <= 0.02, "view %d covers %.3f, not %.3f", view, coverage, expected[view])
		testing.expect_value(t, cell[0].a, u8(0))
		fill_empty_card_texels(cell, TREE_CARD_CELL_TEXELS, TREE_CARD_FILL_PASSES)
		testing.expectf(t, abs(tree_card_test_coverage(cell) - coverage) < 1e-6, "view %d: the fill adds no alpha", view)
	}
}

// Each level's cells keep level 0's kept share within 10% while a cell is
// at least 8 texels wide; the chain is as long as raylib reads it.
@(test)
test_the_card_mips_keep_the_coverage :: proc(t: ^testing.T) {
	layers := box_layers({-0.3, 0, -0.6}, {0.3, 1.5, 0.6})
	meshes := make([]Machine_Model_Mesh, 1, context.temp_allocator)
	meshes[0].body = layers
	machines := []Machine{{id = "test_tree", kind = .Tree}}
	atlas := bake_tree_card_atlas(meshes, Machine_Registry{machines = machines})
	defer destroy_tree_card_atlas(&atlas)
	testing.expect_value(t, atlas.rows, 1)
	testing.expect_value(t, atlas.cards[0].row, 0)
	testing.expect_value(t, atlas.width, TREE_CARD_ATLAS_WIDTH)
	sizes := tree_card_mip_sizes(atlas.width, atlas.height)
	testing.expect_value(t, atlas.levels, len(sizes))
	testing.expect_value(t, sizes[len(sizes) - 1], [2]int{1, 1})
	total := 0
	for size in sizes {
		total += size.x * size.y
	}
	testing.expect_value(t, len(atlas.pixels), total)
	offset := 0
	level_zero: [TREE_CARD_VIEWS]f32
	for size, level in sizes {
		cell := TREE_CARD_CELL_TEXELS >> uint(level)
		if cell >= 8 {
			for view in 0 ..< TREE_CARD_VIEWS {
				low := [2]int{view * cell, 0}
				coverage := tree_card_coverage(atlas.pixels[offset:][:size.x * size.y], size.x, low, low + cell, 1)
				if level == 0 {
					level_zero[view] = coverage
					testing.expectf(t, coverage > 0.1, "view %d covers %.3f", view, coverage)
					continue
				}
				testing.expectf(t, abs(coverage - level_zero[view]) <= 0.1 * level_zero[view], "level %d view %d covers %.3f against %.3f", level, view, coverage, level_zero[view])
			}
		}
		offset += size.x * size.y
	}
}

// Every shipped machine of kind tree bakes a card with coverage in each
// view.
@(test) // slow
test_the_shipped_tree_models_bake :: proc(t: ^testing.T) {
	machines := shipped_machines()
	defer delete(machines)
	meshes, problem := load_machine_model_meshes(Machine_Registry{machines = machines}, test_data_directory())
	defer destroy_model_meshes(meshes)
	testing.expect_value(t, problem, "")
	if problem != "" {
		return
	}
	atlas := bake_tree_card_atlas(meshes, Machine_Registry{machines = machines})
	defer destroy_tree_card_atlas(&atlas)
	baked := 0
	for machine, index in machines {
		card := atlas.cards[index]
		testing.expectf(t, (card.row >= 0) == (machine.kind == .Tree), "%s: row %d", machine.id, card.row)
		if card.row < 0 {
			continue
		}
		baked += 1
		testing.expectf(t, card.size.half_width > 0 && card.size.top > card.size.crown && card.size.crown > 0, "%s: %v", machine.id, card.size)
		for view in 0 ..< TREE_CARD_VIEWS {
			low := [2]int{view, card.row} * TREE_CARD_CELL_TEXELS
			coverage := tree_card_coverage(atlas.pixels[:atlas.width * atlas.height], atlas.width, low, low + TREE_CARD_CELL_TEXELS, 1)
			testing.expectf(t, coverage > 0.05, "%s: view %d covers %.3f", machine.id, view, coverage)
		}
	}
	testing.expect(t, baked >= 1, "a tree model bakes")
	testing.expect_value(t, atlas.rows, tree_card_atlas_rows(baked))
}
