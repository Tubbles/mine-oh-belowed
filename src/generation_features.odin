package game

import "core:slice"

// Trees and boulders. Each feature is rooted in a cell of a world aligned
// grid, from a hash of the cell, so a chunk finds every feature reaching
// into it by visiting the cells within FEATURE_REACH of its border. Features
// only fill air, in a fixed order (logs, boulders, leaves), so the result
// does not depend on which features a chunk visits first. Trees take a
// species from their biome's list (generation_trees.odin, work item 0059).
// Ground cover (work item 0082) comes last: one cross shaped block per
// column at most, from a hash of the column.

TREE_CELL_SIZE :: 6
BOULDER_CELL_SIZE :: 16
// The widest crown: no leaf lies farther from its trunk horizontally.
LEAF_REACH :: MAXIMUM_CROWN_RADIUS
MINIMUM_BOULDER_RADIUS :: 1
MAXIMUM_BOULDER_RADIUS :: 2
// Farthest a feature reaches horizontally from its root column.
FEATURE_REACH :: max(LEAF_REACH, MAXIMUM_BOULDER_RADIUS)
// Clearings: patches of about this size where a biome with a
// clearing_share grows no trees.
CLEARING_WAVELENGTH :: 48.0
// A conical crown over roots starts at least this high above the root, so
// no leaf lies within LEAF_SUPPORT_DISTANCE of a root log and a felled
// tree's crown never stays on its roots. Round and flat crowns over roots
// (trunks of MINIMUM_ROOTED_TRUNK_HEIGHT or more) start high enough by
// themselves.
ROOTED_CROWN_MINIMUM_HEIGHT :: LEAF_SUPPORT_DISTANCE + 2

// Indices into tree_root_offsets.
Tree_Root_Directions :: bit_set[0 ..< 4;u8]

@(rodata)
tree_root_offsets := [4][2]i32{{1, 0}, {0, 1}, {-1, 0}, {0, -1}}

// root is the surface block under the trunk. species indexes the
// generator's species table; crown and crown_radius come from it
// (crown_radius 0 without a crown). root_directions is empty for a tree
// without roots.
Tree :: struct {
	root:            World_Coordinate,
	trunk_height:    i32,
	species:         int,
	crown:           Tree_Crown,
	crown_radius:    i32,
	root_directions: Tree_Root_Directions,
}

// centre is the surface block the boulder sits half buried in.
Boulder :: struct {
	centre: World_Coordinate,
	radius: i32,
}

// biome indexes the generator's biomes: the root column's biome.
Feature_Root :: struct {
	position: World_Coordinate,
	hash:     u64,
	biome:    int,
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
// land only, never on a vein outcrop, which should stay readable, and no
// tree in a clearing or next to the landing pad.
feature_root :: proc(generator: ^Generator, kind: Feature_Kind, cell: [2]i32, veins: []Vein) -> (root: Feature_Root, found: bool) {
	hash := hash_column(feature_seed(generator, kind), cell.x, cell.y)
	roll := hash_to_unit(hash_combine(hash, 2))
	if roll >= feature_maximum_density(generator, kind) {
		return {}, false
	}
	cell_size := feature_cell_size(kind)
	x := cell.x * cell_size + i32(hash % u64(cell_size))
	z := cell.y * cell_size + i32(hash_combine(hash, 1) % u64(cell_size))
	if kind == .Tree && column_near_landing_pad(generator.landing_pad, x, z) {
		return {}, false
	}
	column := sample_column(generator, x, z)
	definition := column_biome(generator, column).definition
	if roll >= feature_density(definition, kind) || column.height <= SEA_LEVEL || column_in_vein_footprint(veins, x, z) {
		return {}, false
	}
	if kind == .Tree && column_in_clearing(generator.seeds, definition.clearing_share, x, z) {
		return {}, false
	}
	return Feature_Root{position = {x, column.height, z}, hash = hash, biome = column.biome}, true
}

// The clearing noise spreads almost evenly over -1 to 1 (as the terrain
// noises do), so the columns below this threshold are about share of all.
clearing_threshold :: proc(share: f32) -> f64 {
	return 2 * f64(share) - 1
}

column_in_clearing :: proc(seeds: Purpose_Seeds, share: f32, x, z: i32) -> bool {
	if share <= 0 {
		return false
	}
	return noise_2d_at(seeds[.Clearings], x, z, CLEARING_WAVELENGTH) < clearing_threshold(share)
}

// Trees root at least LEAF_REACH beside the pad, so no trunk stands on it
// and no crown reaches over it, where the pad clears only
// LANDING_PAD_CLEARANCE blocks while trees grow up to
// FEATURE_MAXIMUM_HEIGHT.
column_near_landing_pad :: proc(site: Landing_Pad_Site, x, z: i32) -> bool {
	if !site.present {
		return false
	}
	box := landing_pad_box(site)
	return x >= box.minimum.x - LEAF_REACH && x <= box.maximum.x + LEAF_REACH && z >= box.minimum.z - LEAF_REACH && z <= box.maximum.z + LEAF_REACH
}

tree_in_cell :: proc(generator: ^Generator, cell: [2]i32, veins: []Vein) -> (tree: Tree, found: bool) {
	root := feature_root(generator, .Tree, cell, veins) or_return
	species := choose_tree_species(generator.biomes[root.biome].trees, hash_combine(root.hash, 4))
	return make_tree(generator.species[species], species, root), true
}

make_tree :: proc(species: Tree_Species, species_index: int, root: Feature_Root) -> Tree {
	definition := species.definition
	trunk := i32(hash_to_range(hash_combine(root.hash, 3), i64(definition.minimum_trunk_height), i64(definition.maximum_trunk_height)))
	return Tree {
		root = root.position,
		trunk_height = trunk,
		species = species_index,
		crown = species.crown,
		crown_radius = species.crown == .None ? 0 : definition.crown_radius,
		root_directions = tree_root_directions(definition.roots, trunk, hash_combine(root.hash, 5)),
	}
}

// Two or three neighbouring directions from the hash, for a rooted
// species with a trunk tall enough.
tree_root_directions :: proc(rooted: bool, trunk_height: i32, hash: u64) -> Tree_Root_Directions {
	if !rooted || trunk_height < MINIMUM_ROOTED_TRUNK_HEIGHT {
		return {}
	}
	count := 2 + int(hash & 1)
	first := int((hash >> 1) % 4)
	directions: Tree_Root_Directions
	for step in 0 ..< count {
		directions += {(first + step) % 4}
	}
	return directions
}

boulder_in_cell :: proc(generator: ^Generator, cell: [2]i32, veins: []Vein) -> (boulder: Boulder, found: bool) {
	root := feature_root(generator, .Boulder, cell, veins) or_return
	radius := hash_to_range(hash_combine(root.hash, 3), MINIMUM_BOULDER_RADIUS, MAXIMUM_BOULDER_RADIUS)
	return Boulder{centre = root.position, radius = i32(radius)}, true
}

tree_trunk_contains :: proc(tree: Tree, position: World_Coordinate) -> bool {
	on_axis := position.x == tree.root.x && position.z == tree.root.z
	return on_axis && position.y > tree.root.y && position.y <= tree.root.y + tree.trunk_height
}

// Roots lie beside the lowest trunk block, on the surface.
tree_roots_contain :: proc(tree: Tree, position: World_Coordinate) -> bool {
	if position.y != tree.root.y + 1 {
		return false
	}
	for direction in tree.root_directions {
		offset := tree_root_offsets[direction]
		if position.x == tree.root.x + offset.x && position.z == tree.root.z + offset.y {
			return true
		}
	}
	return false
}

tree_log_contains :: proc(tree: Tree, position: World_Coordinate) -> bool {
	return tree_trunk_contains(tree, position) || tree_roots_contain(tree, position)
}

// A horizontal disc with the corners cut: radius 0 is the centre alone,
// radius 1 a plus, radius 2 five by five without its corners.
crown_disc_contains :: proc(radius, dx, dz: i32) -> bool {
	if radius <= 0 {
		return dx == 0 && dz == 0
	}
	return dx * dx + dz * dz <= radius * radius + radius - 1
}

// Crown layers count from the trunk top (layer 0), up positive. Each
// procedure gives the disc radius of a layer, or -1 where the crown has
// none.

// From two below the trunk top to two above, widest at and just below
// the top.
round_crown_layer_radius :: proc(crown_radius, layer: i32) -> i32 {
	switch layer {
	case -2, 1:
		return max(crown_radius - 1, 0)
	case -1, 0:
		return crown_radius
	case 2:
		return max(crown_radius - 2, 0)
	}
	return -1
}

// bottom is the lowest layer (0 or below). The radius steps down from
// crown_radius at the bottom to 1 at the top in pairs of layers, the
// upper layer of each pair narrower, and a tip block sits above the top.
conical_crown_layer_radius :: proc(crown_radius, bottom, layer: i32) -> i32 {
	if layer == 1 {
		return 0
	}
	if layer > 1 || layer < bottom {
		return -1
	}
	from_bottom := layer - bottom
	radius := crown_radius - from_bottom / 2 * (crown_radius - 1) / max(-bottom / 2, 1)
	if from_bottom % 2 == 1 {
		radius = max(radius - 1, 1)
	}
	return radius
}

flat_crown_layer_radius :: proc(crown_radius, layer: i32) -> i32 {
	switch layer {
	case 0:
		return crown_radius
	case 1:
		return 1
	}
	return -1
}

// A third of the trunk up, and above the roots' reach on a rooted tree.
conical_crown_bottom :: proc(tree: Tree) -> i32 {
	height := tree.trunk_height / 3
	if tree.root_directions != {} {
		height = max(height, ROOTED_CROWN_MINIMUM_HEIGHT)
	}
	return min(height, tree.trunk_height) - tree.trunk_height
}

tree_crown_layer_radius :: proc(tree: Tree, layer: i32) -> i32 {
	switch tree.crown {
	case .Round:
		return round_crown_layer_radius(tree.crown_radius, layer)
	case .Conical:
		return conical_crown_layer_radius(tree.crown_radius, conical_crown_bottom(tree), layer)
	case .Flat:
		return flat_crown_layer_radius(tree.crown_radius, layer)
	case .None:
	}
	return -1
}

// The lowest and highest crown layers.
tree_crown_layers :: proc(tree: Tree) -> (bottom, top: i32) {
	switch tree.crown {
	case .Round:
		return -2, 2
	case .Conical:
		return conical_crown_bottom(tree), 1
	case .Flat:
		return 0, 1
	case .None:
	}
	return 0, 0
}

tree_leaves_contain :: proc(tree: Tree, position: World_Coordinate) -> bool {
	radius := tree_crown_layer_radius(tree, position.y - (tree.root.y + tree.trunk_height))
	return radius >= 0 && crown_disc_contains(radius, abs(position.x - tree.root.x), abs(position.z - tree.root.z))
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

// The trunk and the roots.
tree_log_box :: proc(tree: Tree) -> Block_Box {
	reach: i32 = tree.root_directions != {} ? 1 : 0
	return Block_Box{minimum = tree.root + {-reach, 1, -reach}, maximum = tree.root + {reach, tree.trunk_height, reach}}
}

tree_crown_box :: proc(tree: Tree) -> Block_Box {
	bottom, top := tree_crown_layers(tree)
	radius := tree.crown_radius
	return Block_Box {
		minimum = tree.root + {-radius, tree.trunk_height + bottom, -radius},
		maximum = tree.root + {radius, tree.trunk_height + top, radius},
	}
}

// The whole tree.
tree_box :: proc(tree: Tree) -> Block_Box {
	logs := tree_log_box(tree)
	crown := tree_crown_box(tree)
	return Block_Box {
		minimum = {min(logs.minimum.x, crown.minimum.x), logs.minimum.y, min(logs.minimum.z, crown.minimum.z)},
		maximum = {max(logs.maximum.x, crown.maximum.x), max(logs.maximum.y, crown.maximum.y), max(logs.maximum.z, crown.maximum.z)},
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
	switch feature.shape {
	case .Log:
		return tree_log_box(feature.tree)
	case .Leaves:
		return tree_crown_box(feature.tree)
	case .Boulder:
	}
	return boulder_box(feature.boulder)
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
		place_feature(chunk, Feature{shape = .Log, tree = tree}, generator.species[tree.species].log_block)
	}
	for boulder in boulders {
		place_feature(chunk, Feature{shape = .Boulder, boulder = boulder}, generator.blocks.stone)
	}
	for tree in trees {
		if tree.crown != .None {
			place_feature(chunk, Feature{shape = .Leaves, tree = tree}, generator.species[tree.species].leaves_block)
		}
	}
}

// The entry a roll in [0, 1) picks: entries in order, the roll against
// the running sum of their chances. found is false past the last sum.
choose_ground_cover :: proc(cover: []Biome_Cover, roll: f64) -> (entry: Biome_Cover, found: bool) {
	sum: f64 = 0
	for candidate in cover {
		sum += f64(candidate.chance)
		if roll < sum {
			return candidate, true
		}
	}
	return {}, false
}

// The top block of a column as fill_terrain_column sets it: the biome's
// top block, or its pit block in a low spot.
column_top_block :: proc(generator: ^Generator, columns: ^Column_Grid, local_x, local_z: i32) -> Block_Id {
	biome := column_biome(generator, grid_column(columns, local_x, local_z))
	return column_is_pit(generator, columns, local_x, local_z) ? biome.pit_block : biome.top_block
}

// The cover block a column's roll gives on its top block, or air when
// the roll picks no entry or one that does not stand on top. A pure
// function of the seed and the column, so every chunk agrees.
ground_cover_at :: proc(cover: []Biome_Cover, top: Block_Id, seed: u64, x, z: i32) -> Block_Id {
	if len(cover) == 0 {
		return AIR_BLOCK
	}
	entry, found := choose_ground_cover(cover, hash_to_unit(hash_column(seed, x, z)))
	if !found || !slice.contains(entry.on, top) {
		return AIR_BLOCK
	}
	return entry.block
}

// Sets each column's cover into the cell above its surface when that cell
// lies in the chunk and is still air after the features: water keeps it
// off flooded columns, logs, leaves and boulders keep it out of their
// cells. Vein footprints stay bare so outcrops read clearly. The landing
// pad is stamped afterwards and clears its own cells.
apply_ground_cover :: proc(generator: ^Generator, chunk: ^Chunk, columns: ^Column_Grid, veins: []Vein) {
	origin := chunk_origin(chunk.coordinate)
	for z in i32(0) ..< CHUNK_SIZE {
		for x in i32(0) ..< CHUNK_SIZE {
			y := grid_column(columns, x, z).height + 1 - origin.y
			if y < 0 || y >= CHUNK_SIZE {
				continue
			}
			index := local_to_index({x, y, z})
			world_x, world_z := origin.x + x, origin.z + z
			if chunk.blocks[index] != AIR_BLOCK || column_in_vein_footprint(veins, world_x, world_z) {
				continue
			}
			cover := column_biome(generator, grid_column(columns, x, z)).ground_cover
			top := column_top_block(generator, columns, x, z)
			chunk.blocks[index] = ground_cover_at(cover, top, generator.seeds[.Ground_Cover], world_x, world_z)
		}
	}
}
