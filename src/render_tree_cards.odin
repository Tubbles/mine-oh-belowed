package game

import "core:math"

// The trees' far cards (work item 0310, doc/presentation.md, The field
// session): every machine of kind tree baked on the CPU, when the models
// load (replace_machine_models), into a row of an atlas of
// TREE_CARD_ATLAS_COLUMNS cells of TREE_CARD_CELL_TEXELS: the model seen
// along its forward, along its right and from above, orthographically,
// each texel the nearest triangle's vertex colour with alpha 255, the
// empty ones coloured by their neighbours with alpha 0, so the filter
// never darkens an edge. The mips go to 1 by 1, each cell's alpha scaled
// so the share the shader keeps (alpha at least a half) stays the full
// size's, and a far forest does not thin out. Pure: the renderer uploads
// the pixels (render_models.odin).

TREE_CARD_CELL_TEXELS :: 128
TREE_CARD_MARGIN_TEXELS :: 2
TREE_CARD_INNER_TEXELS :: TREE_CARD_CELL_TEXELS - 2 * TREE_CARD_MARGIN_TEXELS
// Along forward, along right, from above; the fourth column stays empty.
TREE_CARD_VIEWS :: 3
TREE_CARD_ATLAS_COLUMNS :: 4
TREE_CARD_ATLAS_WIDTH :: TREE_CARD_CELL_TEXELS * TREE_CARD_ATLAS_COLUMNS
TREE_CARD_MAXIMUM_ROWS :: 16
// The crown's centre (the card's light comes from it) and the top card's
// height, in thousandths of the model's top.
TREE_CARD_CROWN_PERMILLE :: 550
TREE_CARD_FILL_PASSES :: 2
TREE_CARD_ALPHA_STEPS :: 8
// The alpha the shader keeps at least (tree.fs).
TREE_CARD_ALPHA_KEPT :: 128

// A model's card in the model's units: half its width (the largest |x| or
// |z|), its top and the crown's height.
Tree_Card_Size :: struct {
	half_width: f32,
	top:        f32,
	crown:      f32,
}

// A machine's card: its row in the atlas (-1 for none) and its size.
Tree_Card :: struct {
	row:  int,
	size: Tree_Card_Size,
}

// The baked atlas: every mip level's texels one after the other, as
// raylib reads them (tree_card_mip_sizes), the cards by Machine_Id and the
// rows of the full size.
Tree_Card_Atlas :: struct {
	pixels: [][4]u8,
	width:  int,
	height: int,
	levels: int,
	rows:   int,
	cards:  []Tree_Card,
}

tree_card_size :: proc(mesh: Model_Mesh) -> Tree_Card_Size {
	size: Tree_Card_Size
	for position in mesh.positions {
		size.half_width = max(size.half_width, abs(position.x), abs(position.z))
		size.top = max(size.top, position.y)
	}
	size.crown = size.top * TREE_CARD_CROWN_PERMILLE / 1000
	return size
}

// A model point to the view's card: u and v from 0 to 1 across the card
// and the depth, larger nearer the viewer. View 0 looks along forward (the
// card is the x, y plane), view 1 along right (z, y), view 2 down from
// above (x, z).
tree_card_projection :: proc(position: [3]f32, size: Tree_Card_Size, view: int) -> (u, v, depth: f32) {
	width := 2 * max(size.half_width, 1e-6)
	top := max(size.top, 1e-6)
	switch view {
	case 0:
		return (position.x + size.half_width) / width, position.y / top, position.z
	case 1:
		return (position.z + size.half_width) / width, position.y / top, position.x
	}
	return (position.x + size.half_width) / width, (position.z + size.half_width) / width, position.y
}

// The texel coordinate of a card coordinate, inside the margin.
tree_card_texel :: proc(coordinate: f32) -> f32 {
	return TREE_CARD_MARGIN_TEXELS + coordinate * TREE_CARD_INNER_TEXELS
}

// The model's triangles orthographically into one cell
// (TREE_CARD_CELL_TEXELS squared, row by row, v rising with the row), the
// nearest triangle's vertex colour (the first corner's) with alpha 255
// where one covers the texel's centre; the rest stays as given.
bake_tree_card :: proc(mesh: Model_Mesh, size: Tree_Card_Size, view: int, cell: [][4]u8) {
	depths := make([]f32, TREE_CARD_CELL_TEXELS * TREE_CARD_CELL_TEXELS, context.temp_allocator)
	for &depth in depths {
		depth = -math.F32_MAX
	}
	for triangle in 0 ..< model_mesh_triangle_count(mesh) {
		corners := model_mesh_triangle_vertices(mesh, triangle)
		points: [3][3]f32
		for corner, index in corners {
			u, v, depth := tree_card_projection(mesh.positions[corner], size, view)
			points[index] = {tree_card_texel(u), tree_card_texel(v), depth}
		}
		color := mesh.colors[corners[0]] if len(mesh.colors) > corners[0] else [4]u8{255, 255, 255, 255}
		rasterise_tree_card_triangle(points, {color.r, color.g, color.b, 255}, cell, depths)
	}
}

// One triangle in texel space (x, y, depth) into the cell: each texel
// whose centre it covers and where it lies nearer than what is there.
rasterise_tree_card_triangle :: proc(points: [3][3]f32, color: [4]u8, cell: [][4]u8, depths: []f32) {
	area := tree_card_edge(points[0], points[1], points[2].xy)
	if abs(area) < 1e-9 {
		return
	}
	low := [2]int{int(math.floor(min(points[0].x, points[1].x, points[2].x))), int(math.floor(min(points[0].y, points[1].y, points[2].y)))}
	high := [2]int{int(math.ceil(max(points[0].x, points[1].x, points[2].x))), int(math.ceil(max(points[0].y, points[1].y, points[2].y)))}
	for y in max(low.y, 0) ..< min(high.y + 1, TREE_CARD_CELL_TEXELS) {
		for x in max(low.x, 0) ..< min(high.x + 1, TREE_CARD_CELL_TEXELS) {
			centre := [2]f32{f32(x) + 0.5, f32(y) + 0.5}
			first := tree_card_edge(points[1], points[2], centre) / area
			second := tree_card_edge(points[2], points[0], centre) / area
			third := 1 - first - second
			if first < 0 || second < 0 || third < 0 {
				continue
			}
			depth := first * points[0].z + second * points[1].z + third * points[2].z
			index := y * TREE_CARD_CELL_TEXELS + x
			if depth > depths[index] {
				depths[index] = depth
				cell[index] = color
			}
		}
	}
}

// Twice the signed area of the triangle a, b, point.
tree_card_edge :: proc(a, b: [3]f32, point: [2]f32) -> f32 {
	return (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
}

// Each empty texel (alpha 0) beside a coloured one takes the mean of its
// coloured neighbours, passes times outwards; alpha stays 0.
fill_empty_card_texels :: proc(cell: [][4]u8, side: int, passes: int) {
	coloured := make([]bool, len(cell), context.temp_allocator)
	for texel, index in cell {
		coloured[index] = texel.a > 0
	}
	next := make([]bool, len(cell), context.temp_allocator)
	for _ in 0 ..< passes {
		copy(next, coloured)
		for y in 0 ..< side {
			for x in 0 ..< side {
				index := y * side + x
				if coloured[index] {
					continue
				}
				sum: [3]int
				count := 0
				for offset in ([4][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
					neighbour := [2]int{x, y} + offset
					if neighbour.x < 0 || neighbour.y < 0 || neighbour.x >= side || neighbour.y >= side || !coloured[neighbour.y * side + neighbour.x] {
						continue
					}
					texel := cell[neighbour.y * side + neighbour.x]
					sum += {int(texel.r), int(texel.g), int(texel.b)}
					count += 1
				}
				if count > 0 {
					cell[index] = {u8(sum.r / count), u8(sum.g / count), u8(sum.b / count), 0}
					next[index] = true
				}
			}
		}
		copy(coloured, next)
	}
}

// The sizes of the levels from width by height down to 1 by 1, as
// raylib's rlLoadTexture steps them (halved, at least 1).
tree_card_mip_sizes :: proc(width, height: int, allocator := context.temp_allocator) -> [][2]int {
	sizes := make([dynamic][2]int, allocator)
	size := [2]int{width, height}
	for {
		append(&sizes, size)
		if size.x == 1 && size.y == 1 {
			break
		}
		size = {max(1, size.x / 2), max(1, size.y / 2)}
	}
	return sizes[:]
}

// The level below: each texel the 2 by 2 (or 2 by 1) texels above it, the
// colour weighed by alpha (the plain mean where all are empty), the alpha
// their mean.
tree_card_next_level :: proc(above: [][4]u8, above_size, size: [2]int, below: [][4]u8) {
	for y in 0 ..< size.y {
		for x in 0 ..< size.x {
			weighed, plain: [3]int
			alpha, count := 0, 0
			for dy in 0 ..< 2 {
				for dx in 0 ..< 2 {
					source := [2]int{min(2 * x + dx, above_size.x - 1), min(2 * y + dy, above_size.y - 1)}
					texel := above[source.y * above_size.x + source.x]
					weighed += [3]int{int(texel.r), int(texel.g), int(texel.b)} * int(texel.a)
					plain += {int(texel.r), int(texel.g), int(texel.b)}
					alpha += int(texel.a)
					count += 1
				}
			}
			color := alpha > 0 ? weighed / alpha : plain / count
			below[y * size.x + x] = {u8(color.r), u8(color.g), u8(color.b), u8(alpha / count)}
		}
	}
}

// The share of the texels in the box with alpha at least the threshold
// (0 to 255 scaled by scale).
tree_card_coverage :: proc(pixels: [][4]u8, width: int, low, high: [2]int, scale: f32) -> f32 {
	kept, count := 0, 0
	for y in low.y ..< high.y {
		for x in low.x ..< high.x {
			if f32(pixels[y * width + x].a) * scale >= TREE_CARD_ALPHA_KEPT {
				kept += 1
			}
			count += 1
		}
	}
	return f32(kept) / f32(max(count, 1))
}

// The scale of the cell's alpha that keeps the target share: the
// threshold whose share at or above it is the target, by
// TREE_CARD_ALPHA_STEPS bisections from 0 to 256, moved to
// TREE_CARD_ALPHA_KEPT. A small cell's share jumps between thresholds, so
// the bracket's end whose share lies nearer the target wins.
tree_card_alpha_scale :: proc(pixels: [][4]u8, width: int, low, high: [2]int, target: f32) -> f32 {
	least, most := f32(0), f32(256)
	for _ in 0 ..< TREE_CARD_ALPHA_STEPS {
		middle := (least + most) / 2
		if tree_card_coverage(pixels, width, low, high, TREE_CARD_ALPHA_KEPT / max(middle, 1)) > target {
			least = middle
		} else {
			most = middle
		}
	}
	least_scale, most_scale := TREE_CARD_ALPHA_KEPT / max(least, 1), TREE_CARD_ALPHA_KEPT / max(most, 1)
	least_error := abs(tree_card_coverage(pixels, width, low, high, least_scale) - target)
	most_error := abs(tree_card_coverage(pixels, width, low, high, most_scale) - target)
	return least_error <= most_error ? least_scale : most_scale
}

// The mip levels below level 0 (width by height, the atlas of rows rows),
// appended to the pixels; each cell of a level at least a texel wide
// takes the alpha scale that keeps its level 0 kept share. Returns the
// levels' count with level 0.
tree_card_mip_chain :: proc(pixels: ^[dynamic][4]u8, width, height, rows: int) -> int {
	sizes := tree_card_mip_sizes(width, height)
	coverage := make([]f32, TREE_CARD_ATLAS_COLUMNS * rows, context.temp_allocator)
	for row in 0 ..< rows {
		for column in 0 ..< TREE_CARD_ATLAS_COLUMNS {
			low := [2]int{column, row} * TREE_CARD_CELL_TEXELS
			coverage[row * TREE_CARD_ATLAS_COLUMNS + column] = tree_card_coverage(pixels^[:width * height], width, low, low + TREE_CARD_CELL_TEXELS, 1)
		}
	}
	offset := 0
	for level in 1 ..< len(sizes) {
		above_size, size := sizes[level - 1], sizes[level]
		start := len(pixels)
		resize(pixels, start + size.x * size.y)
		above := pixels^[offset:start]
		below := pixels^[start:]
		tree_card_next_level(above, above_size, size, below)
		offset = start
		cell := TREE_CARD_CELL_TEXELS >> uint(level)
		if cell < 1 {
			continue
		}
		for row in 0 ..< rows {
			for column in 0 ..< TREE_CARD_ATLAS_COLUMNS {
				low := [2]int{column, row} * cell
				target := coverage[row * TREE_CARD_ATLAS_COLUMNS + column]
				if target == 0 {
					continue
				}
				scale := tree_card_alpha_scale(below, size.x, low, low + cell, target)
				for y in low.y ..< low.y + cell {
					for x in low.x ..< low.x + cell {
						texel := &below[y * size.x + x]
						texel.a = u8(min(f32(texel.a) * scale, 255))
					}
				}
			}
		}
	}
	return len(sizes)
}

// The rows of the atlas for the count of cards: a power of two, at least
// one.
tree_card_atlas_rows :: proc(cards: int) -> int {
	rows := 1
	for rows < cards {
		rows *= 2
	}
	return rows
}

// Every machine of kind tree whose lit body has vertices gets a row, in
// Machine_Id order, TREE_CARD_MAXIMUM_ROWS at most; the rest row -1. In
// the allocator.
bake_tree_card_atlas :: proc(meshes: []Machine_Model_Mesh, machines: Machine_Registry, allocator := context.allocator) -> Tree_Card_Atlas {
	atlas := Tree_Card_Atlas {
		cards = make([]Tree_Card, len(machines.machines), allocator),
	}
	baked := 0
	for &card, index in atlas.cards {
		card.row = -1
		if index >= len(meshes) || machines.machines[index].kind != .Tree || len(meshes[index].body[.Lit].positions) == 0 || baked >= TREE_CARD_MAXIMUM_ROWS {
			continue
		}
		card = {row = baked, size = tree_card_size(meshes[index].body[.Lit])}
		baked += 1
	}
	atlas.rows = tree_card_atlas_rows(baked)
	atlas.width = TREE_CARD_ATLAS_WIDTH
	atlas.height = TREE_CARD_CELL_TEXELS * atlas.rows
	pixels := make([dynamic][4]u8, atlas.width * atlas.height, allocator)
	cell := make([][4]u8, TREE_CARD_CELL_TEXELS * TREE_CARD_CELL_TEXELS, context.temp_allocator)
	for card, index in atlas.cards {
		if card.row < 0 {
			continue
		}
		for view in 0 ..< TREE_CARD_VIEWS {
			for &texel in cell {
				texel = {}
			}
			bake_tree_card(meshes[index].body[.Lit], card.size, view, cell)
			fill_empty_card_texels(cell, TREE_CARD_CELL_TEXELS, TREE_CARD_FILL_PASSES)
			for y in 0 ..< TREE_CARD_CELL_TEXELS {
				target := (card.row * TREE_CARD_CELL_TEXELS + y) * atlas.width + view * TREE_CARD_CELL_TEXELS
				copy(pixels[target:][:TREE_CARD_CELL_TEXELS], cell[y * TREE_CARD_CELL_TEXELS:][:TREE_CARD_CELL_TEXELS])
			}
		}
	}
	atlas.levels = tree_card_mip_chain(&pixels, atlas.width, atlas.height, atlas.rows)
	atlas.pixels = pixels[:]
	return atlas
}

destroy_tree_card_atlas :: proc(atlas: ^Tree_Card_Atlas, allocator := context.allocator) {
	delete(atlas.pixels, allocator)
	delete(atlas.cards, allocator)
	atlas^ = {}
}
