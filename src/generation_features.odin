package game

// Trees and boulders. Each feature is rooted in a cell of a world aligned
// grid, from a hash of the cell, so a chunk finds every feature reaching
// into it by visiting the cells within FEATURE_REACH of its border. Features
// only fill air, in a fixed order (logs, boulders, leaves), so the result
// does not depend on which features a chunk visits first.

TREE_CELL_SIZE :: 6
BOULDER_CELL_SIZE :: 16
MINIMUM_TRUNK_HEIGHT :: 4
MAXIMUM_TRUNK_HEIGHT :: 6
LEAF_REACH :: 2
MINIMUM_BOULDER_RADIUS :: 1
MAXIMUM_BOULDER_RADIUS :: 2
// Farthest a feature reaches horizontally from its root column.
FEATURE_REACH :: max(LEAF_REACH, MAXIMUM_BOULDER_RADIUS)

// root is the surface block under the trunk.
Tree :: struct {
	root:         World_Coordinate,
	trunk_height: i32,
}

// centre is the surface block the boulder sits half buried in.
Boulder :: struct {
	centre: World_Coordinate,
	radius: i32,
}

Feature_Root :: struct {
	position: World_Coordinate,
	hash:     u64,
}

Feature_Kind :: enum u8 {
	Tree,
	Boulder,
}

feature_cell_size :: proc(kind: Feature_Kind) -> i32 {
	return kind == .Tree ? TREE_CELL_SIZE : BOULDER_CELL_SIZE
}

feature_seed :: proc(generator: ^Generator, kind: Feature_Kind) -> u64 {
	return generator.seeds[kind == .Tree ? .Trees : .Boulders]
}

feature_maximum_density :: proc(generator: ^Generator, kind: Feature_Kind) -> f64 {
	return kind == .Tree ? generator.maximum_tree_density : generator.maximum_boulder_density
}

feature_density :: proc(definition: Biome_Definition, kind: Feature_Kind) -> f64 {
	return f64(kind == .Tree ? definition.tree_density : definition.boulder_density)
}

// The column a cell's feature grows from, if the density roll passes. Dry
// land only, and never on a vein outcrop, which should stay readable.
feature_root :: proc(generator: ^Generator, kind: Feature_Kind, cell: [2]i32, veins: []Vein) -> (root: Feature_Root, found: bool) {
	hash := hash_column(feature_seed(generator, kind), cell.x, cell.y)
	roll := hash_to_unit(hash_combine(hash, 2))
	if roll >= feature_maximum_density(generator, kind) {
		return {}, false
	}
	cell_size := feature_cell_size(kind)
	x := cell.x * cell_size + i32(hash % u64(cell_size))
	z := cell.y * cell_size + i32(hash_combine(hash, 1) % u64(cell_size))
	column := sample_column(generator, x, z)
	density := feature_density(column_biome(generator, column).definition, kind)
	if roll >= density || column.height <= SEA_LEVEL || column_in_vein_footprint(veins, x, z) {
		return {}, false
	}
	return Feature_Root{position = {x, column.height, z}, hash = hash}, true
}

tree_in_cell :: proc(generator: ^Generator, cell: [2]i32, veins: []Vein) -> (tree: Tree, found: bool) {
	root := feature_root(generator, .Tree, cell, veins) or_return
	trunk := hash_to_range(hash_combine(root.hash, 3), MINIMUM_TRUNK_HEIGHT, MAXIMUM_TRUNK_HEIGHT)
	return Tree{root = root.position, trunk_height = i32(trunk)}, true
}

boulder_in_cell :: proc(generator: ^Generator, cell: [2]i32, veins: []Vein) -> (boulder: Boulder, found: bool) {
	root := feature_root(generator, .Boulder, cell, veins) or_return
	radius := hash_to_range(hash_combine(root.hash, 3), MINIMUM_BOULDER_RADIUS, MAXIMUM_BOULDER_RADIUS)
	return Boulder{centre = root.position, radius = i32(radius)}, true
}

tree_log_contains :: proc(tree: Tree, position: World_Coordinate) -> bool {
	on_axis := position.x == tree.root.x && position.z == tree.root.z
	return on_axis && position.y > tree.root.y && position.y <= tree.root.y + tree.trunk_height
}

// Two wide layers around the trunk top, then two narrow ones above it.
tree_leaves_contain :: proc(tree: Tree, position: World_Coordinate) -> bool {
	dx := abs(position.x - tree.root.x)
	dz := abs(position.z - tree.root.z)
	switch position.y - (tree.root.y + tree.trunk_height) {
	case -1, 0:
		return dx <= LEAF_REACH && dz <= LEAF_REACH && !(dx == LEAF_REACH && dz == LEAF_REACH)
	case 1:
		return dx <= 1 && dz <= 1
	case 2:
		return dx + dz <= 1
	}
	return false
}

boulder_contains :: proc(boulder: Boulder, position: World_Coordinate) -> bool {
	offset := position - boulder.centre
	distance_squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
	return distance_squared <= boulder.radius * boulder.radius + boulder.radius
}

Block_Box :: struct {
	minimum: World_Coordinate,
	maximum: World_Coordinate,
}

tree_box :: proc(tree: Tree) -> Block_Box {
	return Block_Box {
		minimum = tree.root + {-LEAF_REACH, 1, -LEAF_REACH},
		maximum = tree.root + {LEAF_REACH, tree.trunk_height + 2, LEAF_REACH},
	}
}

boulder_box :: proc(boulder: Boulder) -> Block_Box {
	return Block_Box{minimum = boulder.centre - boulder.radius, maximum = boulder.centre + boulder.radius}
}

chunk_box :: proc(coordinate: Chunk_Coordinate) -> Block_Box {
	origin := chunk_origin(coordinate)
	return Block_Box{minimum = origin, maximum = origin + CHUNK_SIZE - 1}
}

// The part of a box inside the chunk. Empty when minimum exceeds maximum.
clip_box_to_chunk :: proc(box: Block_Box, coordinate: Chunk_Coordinate) -> Block_Box {
	bounds := chunk_box(coordinate)
	return Block_Box{minimum = {max(box.minimum.x, bounds.minimum.x), max(box.minimum.y, bounds.minimum.y), max(box.minimum.z, bounds.minimum.z)}, maximum = {min(box.maximum.x, bounds.maximum.x), min(box.maximum.y, bounds.maximum.y), min(box.maximum.z, bounds.maximum.z)}}
}

Feature_Shape :: enum u8 {
	Log,
	Leaves,
	Boulder,
}

Feature :: struct {
	shape:   Feature_Shape,
	tree:    Tree,
	boulder: Boulder,
}

feature_contains :: proc(feature: Feature, position: World_Coordinate) -> bool {
	switch feature.shape {
	case .Log:
		return tree_log_contains(feature.tree, position)
	case .Leaves:
		return tree_leaves_contain(feature.tree, position)
	case .Boulder:
		return boulder_contains(feature.boulder, position)
	}
	return false
}

feature_box :: proc(feature: Feature) -> Block_Box {
	return feature.shape == .Boulder ? boulder_box(feature.boulder) : tree_box(feature.tree)
}

// Writes the feature's block into every air cell of the chunk it covers.
place_feature :: proc(chunk: ^Chunk, feature: Feature, block: Block_Id) {
	box := clip_box_to_chunk(feature_box(feature), chunk.coordinate)
	origin := chunk_origin(chunk.coordinate)
	for y in box.minimum.y ..= box.maximum.y {
		for z in box.minimum.z ..= box.maximum.z {
			for x in box.minimum.x ..= box.maximum.x {
				position := World_Coordinate{x, y, z}
				index := local_to_index(Local_Coordinate(position - origin))
				if chunk.blocks[index] == AIR_BLOCK && feature_contains(feature, position) {
					chunk.blocks[index] = block
				}
			}
		}
	}
}

// Feature cells whose root columns lie within FEATURE_REACH of the chunk.
feature_cell_range :: proc(coordinate: Chunk_Coordinate, cell_size: i32) -> (first, last: [2]i32) {
	origin := chunk_origin(coordinate)
	first = {floor_divide(origin.x - FEATURE_REACH, cell_size), floor_divide(origin.z - FEATURE_REACH, cell_size)}
	last = {floor_divide(origin.x + CHUNK_SIZE - 1 + FEATURE_REACH, cell_size), floor_divide(origin.z + CHUNK_SIZE - 1 + FEATURE_REACH, cell_size)}
	return
}

chunk_trees :: proc(generator: ^Generator, coordinate: Chunk_Coordinate, veins: []Vein, allocator := context.allocator) -> [dynamic]Tree {
	trees := make([dynamic]Tree, allocator)
	first, last := feature_cell_range(coordinate, feature_cell_size(.Tree))
	for cell_z in first.y ..= last.y {
		for cell_x in first.x ..= last.x {
			if tree, found := tree_in_cell(generator, {cell_x, cell_z}, veins); found {
				append(&trees, tree)
			}
		}
	}
	return trees
}

chunk_boulders :: proc(generator: ^Generator, coordinate: Chunk_Coordinate, veins: []Vein, allocator := context.allocator) -> [dynamic]Boulder {
	boulders := make([dynamic]Boulder, allocator)
	first, last := feature_cell_range(coordinate, feature_cell_size(.Boulder))
	for cell_z in first.y ..= last.y {
		for cell_x in first.x ..= last.x {
			if boulder, found := boulder_in_cell(generator, {cell_x, cell_z}, veins); found {
				append(&boulders, boulder)
			}
		}
	}
	return boulders
}

// Features only fill air, and the phases run in a fixed order, so a log
// always wins over a boulder and both over leaves, whatever the visiting order.
apply_features :: proc(generator: ^Generator, chunk: ^Chunk, trees: []Tree, boulders: []Boulder) {
	for tree in trees {
		place_feature(chunk, Feature{shape = .Log, tree = tree}, generator.blocks.log)
	}
	for boulder in boulders {
		place_feature(chunk, Feature{shape = .Boulder, boulder = boulder}, generator.blocks.stone)
	}
	for tree in trees {
		place_feature(chunk, Feature{shape = .Leaves, tree = tree}, generator.blocks.leaves)
	}
}
