package game

import "core:slice"
import "platform"

// Level of detail of the field (work item 0169, doc/presentation.md, Chunk
// meshes): an octree over field chunks. A node of level L covers 2^L
// chunks a side and meshes FIELD_GRID_CELLS cells a side, so its grid
// samples every 2^L-th sample: level 0 is a chunk at full resolution, 1 to
// 3 are half, quarter and eighth. The level of a node follows its distance
// from the camera, against one distance per level from data/game.sjson
// (field_view.level_distances_metres); beyond the last one nothing is
// drawn but the globe. The coarser levels are generated straight into
// their grid from the planet (generate_field_grid), the finest is meshed
// from the loaded chunks.
//
// Neighbouring nodes of different levels do not meet, so a node's mesh
// hangs skirts from its open border (field_node_skirt_faces,
// append_field_skirts). On the faces that border a coarser node or none
// it hangs an L shaped flap out of the node and into the ground that
// covers the seam seen from above. On the faces that border finer nodes
// (0321) it keeps its mesh inside its own box (cut_field_surface) and
// hangs a curtain from its border into its ground in the face's plane,
// which meets the shallow rays from the finer side that pass over the
// finer node's flap. Nodes of one level meet without a gap and hang none
// there: a skirt's straight leg leaves a curved surface (a dug pit's rim)
// and would stand in the air. The selection is balanced at faces, edges
// and corners (balance_field_selection, 0354), so a skirt never meets a
// node two levels coarser. Everything here is integer: positions in
// World_Position units, distances squared.

// FIELD_LEVEL_COUNT is with the data that sets the levels' distances
// (data_load.odin).
FIELD_COARSEST_LEVEL :: FIELD_LEVEL_COUNT - 1
// A skirt reaches one cell of the next coarser level out and down.
FIELD_SKIRT_REACH :: 2 * FIELD_MESH_POSITION_UNITS
// A curtain hangs one of the node's cells into its ground.
FIELD_CURTAIN_DROP :: FIELD_MESH_POSITION_UNITS
// The cut moves a cell's vertex only where the surface stands steeper
// than 35.26 degrees to the face plane, the angle whose cotangent squared
// this is (0321, decision 3). At a shallower angle θ the finer node's
// flap reaches 2 sin θ - cos θ of its cells along the face's axis,
// nothing below about 27 degrees, and the curtain shows the coarser side
// its back, so a cut cell there opens rays that main's lid closes: the
// cut of every cell lost rays up to 31.5 degrees, none from 32. A
// shallower cell keeps the lid.
FIELD_CUT_COTANGENT_SQUARED :: 2
// The most vertices a node's mesh can hold: one per cell that can carry a
// vertex, and three more per border cell, two for the flap and one for
// the curtain.
FIELD_MESH_VERTEX_BOUND :: FIELD_VERTEX_CELL_COUNT + 3 * (FIELD_VERTEX_CELL_COUNT - (FIELD_GRID_CELLS - 1) * (FIELD_GRID_CELLS - 1) * (FIELD_GRID_CELLS - 1))
#assert(FIELD_MESH_VERTEX_BOUND <= MESH_PART_VERTEX_LIMIT, "a field node's mesh fits the u16 indices")
// The planet check of the view distances (field_view_problem) takes the
// finest node's width at the widest spacing.
#assert(FIELD_FINEST_NODE_MAXIMUM_METRES * MILLIMETRES_PER_METRE == FIELD_CHUNK_SIZE * SAMPLE_SPACING_CHOICES_MILLIMETRES[len(SAMPLE_SPACING_CHOICES_MILLIMETRES) - 1])

// coordinate counts nodes of its level: the node's first chunk is
// coordinate times 2^level.
Field_Node :: struct {
	level:      i32,
	coordinate: [3]i32,
}

Field_Box :: struct {
	minimum, maximum: World_Position,
}

// What choosing the nodes reads, in World_Position units. The shell holds
// every surface the generation can make: the radius plus the planet's
// relief bound (planet_relief_bounds, 0306) widened by a node's margin.
// more_cameras are the other viewports' eyes (0179): a node's distance is
// its nearest camera's, so one selection serves every viewport without
// two nodes covering one place.
Field_View :: struct {
	camera:              World_Position,
	more_cameras:        []World_Position,
	level_distances:     [FIELD_LEVEL_COUNT]i64,
	shell_inner:         i64,
	shell_outer:         i64,
	spacing_millimetres: int,
}

Field_Node_Distance :: struct {
	node:             Field_Node,
	distance_squared: i64,
}

// Samples a node of the level covers on each axis.
field_node_samples :: proc(level: i32) -> i32 {
	return FIELD_CHUNK_SIZE << uint(level)
}

field_node_step :: proc(node: Field_Node) -> i32 {
	return 1 << uint(node.level)
}

field_node_origin :: proc(node: Field_Node) -> Sample_Coordinate {
	return Sample_Coordinate(node.coordinate * field_node_samples(node.level))
}

// The finest level's node of a chunk, and back.
field_chunk_node :: proc(coordinate: Field_Chunk_Coordinate) -> Field_Node {
	return {0, ([3]i32)(coordinate)}
}

field_node_chunk :: proc(node: Field_Node) -> Field_Chunk_Coordinate {
	return Field_Chunk_Coordinate(node.coordinate)
}

field_node_box :: proc(node: Field_Node, spacing_millimetres: int) -> Field_Box {
	origin := field_node_origin(node)
	return {sample_to_world_position(origin, spacing_millimetres), sample_to_world_position(origin + field_node_samples(node.level), spacing_millimetres)}
}

// From the point to the nearest point of the box.
box_distance_squared :: proc(box: Field_Box, point: World_Position) -> i64 {
	total: i64 = 0
	for axis in 0 ..< 3 {
		nearest := clamp(point[axis], box.minimum[axis], box.maximum[axis])
		total += (point[axis] - nearest) * (point[axis] - nearest)
	}
	return total
}

// From the point to the farthest corner of the box.
box_farthest_distance_squared :: proc(box: Field_Box, point: World_Position) -> i64 {
	total: i64 = 0
	for axis in 0 ..< 3 {
		reach := max(abs(point[axis] - box.minimum[axis]), abs(point[axis] - box.maximum[axis]))
		total += reach * reach
	}
	return total
}

// The finest level whose distance the node lies within; none beyond the
// last distance.
field_level_for_distance :: proc(distance_squared: i64, level_distances: [FIELD_LEVEL_COUNT]i64) -> (level: i32, visible: bool) {
	for distance, index in level_distances {
		if distance_squared < distance * distance {
			return i32(index), true
		}
	}
	return 0, false
}

field_box_in_shell :: proc(box: Field_Box, inner, outer: i64) -> bool {
	return box_distance_squared(box, {}) <= outer * outer && box_farthest_distance_squared(box, {}) >= inner * inner
}

make_field_view :: proc(camera: World_Position, planet: Planet, spacing_millimetres: int, level_distances_metres: [FIELD_LEVEL_COUNT]int) -> Field_View {
	radius := metres_to_position_units(i64(planet.radius_metres))
	bounds := planet_relief_bounds(planet)
	margin := 2 * sample_axis_to_position(1, spacing_millimetres)
	view := Field_View {
		camera              = camera,
		shell_inner         = radius + bounds.lowest - margin,
		shell_outer         = radius + bounds.highest + margin,
		spacing_millimetres = spacing_millimetres,
	}
	for distance, level in level_distances_metres {
		view.level_distances[level] = metres_to_position_units(i64(distance))
	}
	return view
}

// The node, or its children where the camera is near enough for a finer
// level. Nodes outside the surface shell or beyond the last distance hold
// nothing to draw. Nodes above the coarsest level only split, so the walk
// visits the nodes crossing the shell near the camera and never the empty
// volume around it.
select_field_node :: proc(view: Field_View, node: Field_Node, selected: ^[dynamic]Field_Node_Distance) {
	box := field_node_box(node, view.spacing_millimetres)
	if !field_box_in_shell(box, view.shell_inner, view.shell_outer) {
		return
	}
	distance_squared := box_distance_squared(box, view.camera)
	for camera in view.more_cameras {
		distance_squared = min(distance_squared, box_distance_squared(box, camera))
	}
	level, visible := field_level_for_distance(distance_squared, view.level_distances)
	if !visible {
		return
	}
	if node.level <= FIELD_COARSEST_LEVEL && level >= node.level {
		append(selected, Field_Node_Distance{node, distance_squared})
		return
	}
	for child in 0 ..< 8 {
		select_field_node(view, Field_Node{node.level - 1, node.coordinate * 2 + field_corner_offset(child)}, selected)
	}
}

field_node_distance_before :: proc(first, second: Field_Node_Distance) -> bool {
	return first.distance_squared < second.distance_squared
}

// The first level from the coarsest up whose nodes are as wide as the last
// distance, so the 27 nodes around the camera's hold everything within it.
field_walk_top_level :: proc(view: Field_View) -> i32 {
	level := i32(FIELD_COARSEST_LEVEL)
	for sample_axis_to_position(field_node_samples(level), view.spacing_millimetres) < view.level_distances[FIELD_COARSEST_LEVEL] {
		level += 1
	}
	return level
}

// The nodes split down the octree from the 27 nodes of the walk's top
// level around each camera, unsorted, in the temp allocator.
walk_field_nodes :: proc(view: Field_View) -> [dynamic]Field_Node_Distance {
	top := field_walk_top_level(view)
	node_size := sample_axis_to_position(field_node_samples(top), view.spacing_millimetres)
	selected := make([dynamic]Field_Node_Distance, context.temp_allocator)
	walked := make(map[Field_Node]struct{}, context.temp_allocator)
	for camera_index in -1 ..< len(view.more_cameras) {
		camera := camera_index < 0 ? view.camera : view.more_cameras[camera_index]
		centre: [3]i32
		for axis in 0 ..< 3 {
			centre[axis] = i32(floor_divide_i64(camera[axis], node_size))
		}
		for child in 0 ..< 27 {
			offset := [3]i32{i32(child % 3), i32(child / 3 % 3), i32(child / 9)} - 1
			node := Field_Node{top, centre + offset}
			if node not_in walked {
				walked[node] = {}
				select_field_node(view, node, &selected)
			}
		}
	}
	return selected
}

// A node's diagonal in World_Position units, rounded up.
field_node_diagonal :: proc(level: i32, spacing_millimetres: int) -> i64 {
	edge := sample_axis_to_position(field_node_samples(level), spacing_millimetres)
	return (edge * SQUARE_ROOT_OF_THREE_TEN_THOUSANDTHS + 9999) / 10000
}

// Whether a selected node can touch one two or more levels coarser: such a
// node lies at least the next level's distance from its nearest camera,
// and a node touching this one lies within its distance plus its diagonal
// (the + 1 covers the square root's floor).
field_node_may_touch_coarser :: proc(view: Field_View, entry: Field_Node_Distance) -> bool {
	distance := i64(integer_square_root(u64(entry.distance_squared)))
	return distance + 1 + field_node_diagonal(entry.node.level, view.spacing_millimetres) >= view.level_distances[entry.node.level + 1]
}

// The held node of least_level or coarser that holds the region: its
// ancestors from least_level up to the coarsest level, the first in held.
field_selected_holder :: proc(held: map[Field_Node]int, region: Field_Node, least_level: i32) -> (holder: Field_Node, found: bool) {
	ancestor := region
	for ancestor.level < least_level {
		ancestor = field_node_parent(ancestor)
	}
	for ; ancestor.level <= FIELD_COARSEST_LEVEL; ancestor = field_node_parent(ancestor) {
		if ancestor in held {
			return ancestor, true
		}
	}
	return {}, false
}

// The selected node replaced by its children as the walk selects them
// (select_field_node), each appended child held at its index.
split_selected_field_node :: proc(view: Field_View, node: Field_Node, selected: ^[dynamic]Field_Node_Distance, held: ^map[Field_Node]int) {
	delete_key(held, node)
	first := len(selected^)
	for child in 0 ..< 8 {
		select_field_node(view, Field_Node{node.level - 1, node.coordinate * 2 + field_corner_offset(child)}, selected)
	}
	for index in first ..< len(selected^) {
		held^[selected^[index].node] = index
	}
}

// Whether no node of the walk can pass field_node_may_touch_coarser, so
// the balance would split nothing: a level l node's parent was split
// within level l's distance, so the node lies under that distance plus
// twice its diagonal, and the check asks that plus its diagonal to reach
// level l + 1's distance. So it holds when, for every level l with a
// level two coarser present (level l + 1's distance below the last),
// the next distance lies more than three of its diagonals past its own,
// in the check's rounding. The shipped levels at 333 mm spacing do.
field_selection_needs_no_balance :: proc(view: Field_View) -> bool {
	distances := view.level_distances
	for level in i32(0) ..= FIELD_COARSEST_LEVEL - 2 {
		coarser_present := distances[level + 1] < distances[FIELD_COARSEST_LEVEL]
		if coarser_present && distances[level + 1] - distances[level] <= 3 * field_node_diagonal(level, view.spacing_millimetres) {
			return false
		}
	}
	return true
}

// Whether the entry at index is still held there (not split).
field_selection_holds :: proc(held: map[Field_Node]int, entry: Field_Node_Distance, index: int) -> bool {
	position, found := held[entry.node]
	return found && position == index
}

// The selection balanced 2:1 at faces, edges and corners (0354): a
// selected node touching one two or more levels finer is split, finest
// contacts first. The level gap does not ensure it: a level L node's
// parent was split within the distance of level L, so the node reaches
// up to that distance plus the parent's diagonal, twice the gap, where a
// node two levels coarser needs only the distance of level L + 1.
// A split child lies past its parent's distance, so the walk keeps it
// whole; splits append only levels coarser than the one in hand, so one
// pass from the finest up settles every contact. Where the distances
// leave no contact possible (field_selection_needs_no_balance) the walk
// is kept as it is, before anything is built.
balance_field_selection :: proc(view: Field_View, selected: ^[dynamic]Field_Node_Distance) {
	if field_selection_needs_no_balance(view) {
		return
	}
	held := make(map[Field_Node]int, len(selected^), context.temp_allocator)
	for entry, index in selected^ {
		held[entry.node] = index
	}
	for level in i32(0) ..= FIELD_COARSEST_LEVEL - 2 {
		for index := 0; index < len(selected^); index += 1 {
			entry := selected^[index]
			if entry.node.level != level || !field_selection_holds(held, entry, index) || !field_node_may_touch_coarser(view, entry) {
				continue
			}
			for neighbour in 0 ..< 27 {
				offset := [3]i32{i32(neighbour % 3), i32(neighbour / 3 % 3), i32(neighbour / 9)} - 1
				if offset == ([3]i32{}) {
					continue
				}
				region := Field_Node{level, entry.node.coordinate + offset}
				for {
					holder, found := field_selected_holder(held, region, level + 2)
					if !found {
						break
					}
					split_selected_field_node(view, holder, selected, &held)
				}
			}
		}
	}
	kept := 0
	for entry, index in selected^ {
		if field_selection_holds(held, entry, index) {
			selected^[kept] = entry
			kept += 1
		}
	}
	resize(selected, kept)
}

// The nodes to draw: the walk's (walk_field_nodes) balanced
// (balance_field_selection), nearest first, so streaming serves the near
// ones first.
select_field_nodes :: proc(view: Field_View, allocator := context.allocator) -> []Field_Node {
	selected := walk_field_nodes(view)
	balance_field_selection(view, &selected)
	slice.sort_by(selected[:], field_node_distance_before)
	nodes := make([]Field_Node, len(selected), allocator)
	for entry, index in selected {
		nodes[index] = entry.node
	}
	return nodes
}

// The generation a grid of this step reads: positions as given, densities
// in units of the step's spacing. planet_sample saturates a density one
// spacing from the surface, so with the fine spacing a coarse edge would
// read the full density at both ends and its crossing would land in the
// middle, terracing the slopes; in the coarse spacing the densities stay
// linear across every coarse cell the surface crosses.
field_grid_generation :: proc(generation: Planet_Generation, step: i32) -> Planet_Generation {
	coarse := generation
	coarse.spacing_millimetres = generation.spacing_millimetres * int(step)
	coarse.spacing = sample_axis_to_position(1, coarse.spacing_millimetres)
	return coarse
}

// A coarse grid's value of a sample taken from a loaded chunk, in the
// grid's spacing: a saturated sample on the generation's side of the
// surface keeps the generation's coarse density (a full one would terrace
// the slopes, see field_grid_generation), any other is its density over
// the step, floored as depth_to_density floors (ground stays at least 1),
// so a dig or a place shows. The material and tint are the chunk's, but
// stone where the coarse generation holds topsoil reads topsoil, the
// coarse topsoil band (0322, generation_topsoil_depth).
coarse_field_sample :: proc(loaded, generated: Field_Sample, step: i32) -> Field_Sample {
	material := loaded.material
	if material == .Stone && generated.material == .Topsoil {
		material = .Topsoil
	}
	return {coarse_field_density(loaded.density, generated.density, step), material, loaded.tint}
}

// A coarse grid's water from a loaded sample (0172), as
// coarse_field_density: full water (or empty air and ground) on the
// generated sea's side keeps the generated density, which is a distance
// in the grid's spacing; anything else is its density over the step.
coarse_field_water_density :: proc(loaded, generated: i8, step: i32) -> i8 {
	if (loaded >= FIELD_WATER_DENSITY_HALF && generated > 0) || (loaded <= -FIELD_WATER_DENSITY_HALF && generated <= 0) {
		return generated
	}
	return coarse_field_density(loaded, generated, step)
}

// The density part of coarse_field_sample.
coarse_field_density :: proc(loaded, generated: i8, step: i32) -> i8 {
	if abs(loaded) == MAXIMUM_DENSITY && (loaded > 0) == (generated > 0) {
		return generated
	}
	density := floor_divide_i64(i64(loaded), i64(step))
	if loaded > 0 {
		density = max(density, 1)
	}
	return i8(density)
}

// The node's grid from the generation, every step-th sample; a sample the
// grid took from a loaded chunk (loaded set) goes through
// coarse_field_sample. The water of a sample not loaded is the sea level
// rule (planet_sea_density) and the lakes' (0312, planet_lake_density,
// the lakes meeting the grid's box listed once from the features or the
// tiles, 0326, carved air left dry as the chunks leave it), of a loaded one its owner's plane as the
// gather wrote it (water_exact, 0294) or its fill through
// coarse_field_water_density, so the sea shows at every level. The light
// of a loaded sample is its own; a sample not loaded is generated air
// under the sky or ground, so it has full sky light in air and none in
// ground (0173) or in carved air under a roof (0324, planet_sample_shaded),
// so a grotto's mouth reads dark from afar. Safe on any thread.
generate_field_grid :: proc(generation: Planet_Generation, node: Field_Node, grid: ^Field_Grid) {
	grid.origin = field_node_origin(node)
	grid.step = field_node_step(node)
	density_generation := field_grid_generation(generation, grid.step)
	lakes: []Planet_Lake
	if len(generation.lakes) > 0 || generation.water_tiles != nil {
		low := grid.origin - grid.step
		high := grid.origin + (FIELD_GRID_CELLS + 1) * grid.step
		lakes = generation_lakes_meeting_box(generation, cast([3]i64)sample_to_world_position(low, generation.spacing_millimetres), cast([3]i64)sample_to_world_position(high, generation.spacing_millimetres))
	}
	// The relief's range over boxes of the grid's samples (0314), of the
	// coarse generation, whose spacing gives the air band and the topsoil.
	boxes := Relief_Boxes {
		first               = grid.origin - grid.step,
		step                = grid.step,
		samples             = FIELD_GRID_SIZE,
		spacing_millimetres = generation.spacing_millimetres,
	}
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				sample := grid.origin + Sample_Coordinate([3]i32{x, y, z} * grid.step)
				position := sample_to_world_position(sample, generation.spacing_millimetres)
				value, shaded, carved := planet_sample_reading_boxed(density_generation, position, &boxes, {x + 1, y + 1, z + 1})
				water := planet_sea_density(density_generation, position, value.density)
				index := field_grid_index({x, y, z})
				if len(lakes) > 0 && !carved && !grid.loaded[index] {
					water = max(water, planet_lake_density(density_generation, lakes, position, value.density))
				}
				if grid.loaded[index] {
					value = coarse_field_sample({grid.density[index], grid.material[index], grid.tint[index]}, value, grid.step)
					water = grid.water_exact[index] ? grid.water[index] : coarse_field_water_density(grid.water[index], water, grid.step)
				} else {
					grid.block_light[index], grid.sky_light[index] = 0, field_sample_is_ground(value.density) || shaded ? 0 : FIELD_LIGHT_FULL
				}
				grid.density[index], grid.material[index], grid.tint[index] = value.density, value.material, value.tint
				grid.water[index] = water
			}
		}
	}
}

// Whether any chunk the node's grid reads (the node and one step round
// it) is loaded.
field_node_touches_loaded_chunks :: proc(world: ^Field_World, node: Field_Node) -> bool {
	origin := field_node_origin(node)
	step := field_node_step(node)
	first := sample_to_field_chunk_coordinate(origin - {step, step, step})
	last := sample_to_field_chunk_coordinate(origin + FIELD_GRID_CELLS * step)
	for z in first.z ..= last.z {
		for y in first.y ..= last.y {
			for x in first.x ..= last.x {
				if (Field_Chunk_Coordinate{x, y, z}) in world.chunks {
					return true
				}
			}
		}
	}
	return false
}

// A coarser node's grid with the samples of the loaded chunks it reads,
// copied on the main thread (loaded set), for generate_field_grid to
// complete on a worker; nil when it reads no loaded chunk, so the worker
// generates it whole. The edits then show at every level of detail. The
// water is the look's base in the grid's spacing (field_water_look_base,
// 0294): no sheet and no waves, which lie under a coarse cell.
gather_coarse_field_grid :: proc(world: ^Field_World, node: Field_Node, allocator := context.allocator) -> ^Field_Grid {
	if !field_node_touches_loaded_chunks(world, node) {
		return nil
	}
	grid := new(Field_Grid, allocator)
	grid.origin = field_node_origin(node)
	grid.step = field_node_step(node)
	// The chunk of the previous sample, so a run of samples in one chunk
	// looks it up once.
	cached_coordinate := Field_Chunk_Coordinate{max(i32), max(i32), max(i32)}
	chunk: ^Field_Chunk
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				sample := grid.origin + Sample_Coordinate([3]i32{x, y, z} * grid.step)
				if coordinate := sample_to_field_chunk_coordinate(sample); coordinate != cached_coordinate {
					cached_coordinate = coordinate
					chunk = world.chunks[coordinate] or_else nil
				}
				if chunk == nil {
					continue
				}
				index := field_grid_index({x, y, z})
				source := sample_to_field_index(sample)
				grid.density[index], grid.material[index], grid.tint[index] = chunk.density[source], chunk.material[source], chunk.tint[source]
				grid.water[index], grid.water_exact[index] = field_water_look_base(world, chunk, source, sample, grid.step)
				grid.block_light[index], grid.sky_light[index] = chunk.block_light[source], chunk.sky_light[source]
				grid.loaded[index] = true
			}
		}
	}
	return grid
}

// The six faces of a node, the axis's negative side first.
Field_Face :: enum u8 {
	Negative_X,
	Positive_X,
	Negative_Y,
	Positive_Y,
	Negative_Z,
	Positive_Z,
}

Field_Faces :: bit_set[Field_Face;u8]

field_face :: proc(axis: int, positive: bool) -> Field_Face {
	return Field_Face(2 * axis + (positive ? 1 : 0))
}

// The node of the next coarser level that holds the node.
field_node_parent :: proc(node: Field_Node) -> Field_Node {
	return {node.level + 1, {floor_divide(node.coordinate.x, 2), floor_divide(node.coordinate.y, 2), floor_divide(node.coordinate.z, 2)}}
}

// The selected nodes, and every coarser node up to the coarsest level that
// holds a selected node.
Field_Selection_Index :: struct {
	selected:     map[Field_Node]struct{},
	holds_finer: map[Field_Node]struct{},
}

make_field_selection_index :: proc(selection: []Field_Node, allocator := context.allocator) -> Field_Selection_Index {
	index := Field_Selection_Index {
		selected    = make(map[Field_Node]struct{}, allocator),
		holds_finer = make(map[Field_Node]struct{}, allocator),
	}
	for node in selection {
		index.selected[node] = {}
		for parent := field_node_parent(node); parent.level <= FIELD_COARSEST_LEVEL; parent = field_node_parent(parent) {
			index.holds_finer[parent] = {}
		}
	}
	return index
}

// The faces that hang a flap (a coarser node or none beyond) and those
// that cut the surface and hang a curtain (finer nodes beyond). A face
// in neither borders a node of the same level.
Field_Seam_Faces :: struct {
	flaps, curtains: Field_Faces,
}

// The faces whose neighbour of the same level is neither selected nor
// split into selected finer nodes hang a flap: a coarser node or nothing
// lies there. Those whose neighbour is split hang a curtain. The finer
// side's flap closes the seam from above whichever side the coarser node
// is on (test_a_level_seam_on_flat_ground_is_closed_from_above); the
// coarser side's curtain meets the shallow rays from the finer side
// (test_a_level_seam_is_closed_at_grazing_views).
field_node_skirt_faces :: proc(index: Field_Selection_Index, node: Field_Node) -> Field_Seam_Faces {
	faces: Field_Seam_Faces
	for axis in 0 ..< 3 {
		for positive in ([2]bool{false, true}) {
			neighbour := node
			neighbour.coordinate[axis] += positive ? 1 : -1
			switch {
			case neighbour in index.holds_finer:
				faces.curtains += {field_face(axis, positive)}
			case neighbour not_in index.selected:
				faces.flaps += {field_face(axis, positive)}
			}
		}
	}
	return faces
}

// Undirected, the lower index in the high half.
field_edge_key :: proc(first, second: u16) -> u32 {
	return u32(min(first, second)) << 16 | u32(max(first, second))
}

// How many triangles of the surface use each edge.
count_field_edges :: proc(indices: []u16, allocator := context.allocator) -> map[u32]int {
	counts := make(map[u32]int, allocator)
	for triangle := 0; triangle + 2 < len(indices); triangle += 3 {
		for corner in 0 ..< 3 {
			counts[field_edge_key(indices[triangle + corner], indices[triangle + (corner + 1) % 3])] += 1
		}
	}
	return counts
}

// Out of the node from a vertex in a border cell: -1 or 1 on each axis
// whose border it sits in on one of faces, 0 elsewhere.
field_skirt_outward :: proc(position: [3]i32, faces: Field_Faces) -> [3]i32 {
	outward: [3]i32
	for axis in 0 ..< 3 {
		cell := floor_divide(position[axis], FIELD_MESH_POSITION_UNITS)
		switch {
		case cell < 0 && field_face(axis, false) in faces:
			outward[axis] = -1
		case cell >= FIELD_GRID_CELLS - 1 && field_face(axis, true) in faces:
			outward[axis] = 1
		}
	}
	return outward
}

// Whether a border edge lies on one of faces: the face whose outermost
// cells the edge is nearest, both its vertices in them or one in them and
// the other a cell in (an edge across a quad's diagonal); an edge as near
// to two faces (along the node's edge) lies on both.
field_edge_on_faces :: proc(from, to: Field_Surface_Vertex, faces: Field_Faces) -> bool {
	nearest := max(i32)
	on: Field_Faces
	for axis in 0 ..< 3 {
		cells := floor_divide(from.position[axis], FIELD_MESH_POSITION_UNITS) + floor_divide(to.position[axis], FIELD_MESH_POSITION_UNITS)
		from_faces := [2]i32{cells + 2, 2 * (FIELD_GRID_CELLS - 1) - cells}
		for from_face, side in from_faces {
			face := field_face(axis, side == 1)
			switch {
			case from_face < nearest:
				nearest, on = from_face, {face}
			case from_face == nearest:
				on += {face}
			}
		}
	}
	return nearest <= 1 && on & faces != {}
}

// The vector scaled to length; zero for a zero vector. In i64, since the
// tangent's components reach the cube of a gradient's.
field_scaled_vector :: proc(vector: [3]i64, length: i64) -> [3]i32 {
	magnitude := i64(integer_square_root(u64(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)))
	if magnitude == 0 {
		return {}
	}
	return {i32(vector.x * length / magnitude), i32(vector.y * length / magnitude), i32(vector.z * length / magnitude)}
}

// The outward direction with its part along the gradient removed, so the
// flap's first leg runs along the surface's slope instead of out of it.
field_skirt_tangent :: proc(outward, gradient: [3]i32) -> [3]i64 {
	along := [3]i64{i64(outward.x), i64(outward.y), i64(outward.z)}
	slope := [3]i64{i64(gradient.x), i64(gradient.y), i64(gradient.z)}
	return along * (slope.x * slope.x + slope.y * slope.y + slope.z * slope.z) - slope * (along.x * slope.x + along.y * slope.y + along.z * slope.z)
}

// The flap's two vertices below a border vertex: one coarse cell out of
// the node along the surface and half a coarse cell into the ground, then
// a coarse cell further into the ground.
field_skirt_vertices :: proc(vertex: Field_Surface_Vertex, faces: Field_Faces) -> (outer, lower: Field_Surface_Vertex) {
	gradient := [3]i64{i64(vertex.gradient.x), i64(vertex.gradient.y), i64(vertex.gradient.z)}
	outer, lower = vertex, vertex
	outer.position += field_scaled_vector(field_skirt_tangent(field_skirt_outward(vertex.position, faces), vertex.gradient), FIELD_SKIRT_REACH) + field_scaled_vector(gradient, FIELD_SKIRT_REACH / 2)
	lower.position = outer.position + field_scaled_vector(gradient, FIELD_SKIRT_REACH)
	return outer, lower
}

// The flap's first vertex of a border vertex, made the first time an edge
// asks; the second follows it.
field_skirt_vertex_index :: proc(surface: ^Field_Surface, skirt_vertices: []i32, vertex: u16, faces: Field_Faces) -> u16 {
	slot := &skirt_vertices[vertex]
	if slot^ < 0 {
		slot^ = i32(len(surface.vertices))
		outer, lower := field_skirt_vertices(surface.vertices[vertex], faces)
		append(&surface.vertices, outer, lower)
	}
	return u16(slot^)
}

// The edges only one triangle uses, which is the node's open border, as
// from and to in the triangle's winding.
field_border_edges :: proc(surface: ^Field_Surface, allocator := context.allocator) -> [dynamic][2]u16 {
	counts := count_field_edges(surface.indices[:], context.temp_allocator)
	edges := make([dynamic][2]u16, allocator)
	for triangle := 0; triangle + 2 < len(surface.indices); triangle += 3 {
		for corner in 0 ..< 3 {
			from, to := surface.indices[triangle + corner], surface.indices[triangle + (corner + 1) % 3]
			if counts[field_edge_key(from, to)] == 1 {
				append(&edges, [2]u16{from, to})
			}
		}
	}
	return edges
}

field_border_vertex_count :: proc(edges: [][2]u16, vertex_count: int) -> int {
	seen := make([]bool, vertex_count, context.temp_allocator)
	count := 0
	for edge in edges {
		for vertex in edge {
			count += seen[vertex] ? 0 : 1
			seen[vertex] = true
		}
	}
	return count
}

// The cells at -1 on an axis that the cut moves run over the other two
// axes from 0 to this end: the last cell is left when the positive face
// on that axis borders a node of this level (in neither set), whose quads
// use it as its cell -1.
field_cut_cell_end :: proc(axis: int, faces: Field_Seam_Faces) -> i32 {
	positive := field_face(axis, true)
	return positive in faces.flaps || positive in faces.curtains ? FIELD_GRID_CELLS : FIELD_GRID_CELLS - 1
}

// The position moved along the line to inner until its coordinate on axis
// is 0. The position lies in a cell at -1 on axis and inner in the cell
// at 0, so inner's coordinate is the larger unless both are 0.
field_cut_position :: proc(position, inner: [3]i32, axis: int) -> [3]i32 {
	moved := position
	if position[axis] < 0 {
		from := [3]i64{i64(position.x), i64(position.y), i64(position.z)}
		to := [3]i64{i64(inner.x), i64(inner.y), i64(inner.z)}
		shifted := from + (to - from) * -from[axis] / (to[axis] - from[axis])
		moved = {i32(shifted.x), i32(shifted.y), i32(shifted.z)}
	}
	moved[axis] = 0
	return moved
}

// Whether the surface at a vertex with the gradient stands steeper than
// FIELD_CUT_COTANGENT_SQUARED's angle to the plane of a face on axis: the
// gradient's part along the axis squared under that many times its part
// across the axis squared, in integers. A zero gradient is not.
field_surface_steep_to_face :: proc(gradient: [3]i32, axis: int) -> bool {
	along := i64(gradient[axis])
	length_squared := i64(gradient.x) * i64(gradient.x) + i64(gradient.y) * i64(gradient.y) + i64(gradient.z) * i64(gradient.z)
	return along * along < FIELD_CUT_COTANGENT_SQUARED * (length_squared - along * along)
}

// The surface kept inside the node's box on the negative faces in
// faces.curtains (0321): the vertex of each cell at -1 on such an axis
// where the surface stands steep to the face (field_surface_steep_to_face)
// slides along the surface onto the face, towards the vertex of the cell
// at 0 beside it, or straight onto the face when that cell holds none;
// the gradient stays. A shallower cell keeps main's lid. A cell at -1 on
// another axis is left, and so is the last cell beside a node of this
// level (field_cut_cell_end): a node of this level beside or diagonal to
// this one can mesh those cells too, and the copies of one vertex in two
// meshes would part. The last cell
// beside a node of another level is cut, though a node of this level
// diagonally across the cut face and that face can mesh it too: only two
// viewports select one there, and no ray opened at it (measured for
// 0321). Positive faces need no cut, since the surface stops in the last
// cell. A uniform grid's surface (no cell_vertices) holds nothing to
// cut.
cut_field_surface :: proc(surface: ^Field_Surface, faces: Field_Seam_Faces) {
	if surface.cell_vertices == nil {
		return
	}
	for axis in 0 ..< 3 {
		if field_face(axis, false) not_in faces.curtains {
			continue
		}
		first, second := (axis + 1) % 3, (axis + 2) % 3
		for first_coordinate in i32(0) ..< field_cut_cell_end(first, faces) {
			for second_coordinate in i32(0) ..< field_cut_cell_end(second, faces) {
				cell: [3]i32
				cell[axis], cell[first], cell[second] = -1, first_coordinate, second_coordinate
				vertex := surface.cell_vertices[field_vertex_cell_index(cell)]
				if vertex < 0 || !field_surface_steep_to_face(surface.vertices[vertex].gradient, axis) {
					continue
				}
				inner_cell := cell
				inner_cell[axis] = 0
				inner := surface.cell_vertices[field_vertex_cell_index(inner_cell)]
				position := &surface.vertices[vertex].position
				if inner >= 0 {
					position^ = field_cut_position(position^, surface.vertices[inner].position, axis)
				} else {
					position^[axis] = 0
				}
			}
		}
	}
}

// The curtain's drop below a border vertex: the gradient without its
// parts on the axes where the vertex sits in a border cell of faces, one
// cell long, so the curtain runs down into the ground in the face's
// plane; zero when the gradient lies across the face.
field_curtain_drop :: proc(vertex: Field_Surface_Vertex, faces: Field_Faces) -> [3]i32 {
	outward := field_skirt_outward(vertex.position, faces)
	gradient: [3]i64
	for axis in 0 ..< 3 {
		gradient[axis] = outward[axis] == 0 ? i64(vertex.gradient[axis]) : 0
	}
	return field_scaled_vector(gradient, FIELD_CURTAIN_DROP)
}

// Each curtain border vertex's drop by vertex index, taken before the cut
// moves the vertex out of its border cell.
field_curtain_drops :: proc(surface: ^Field_Surface, edges: [][2]u16, faces: Field_Faces) -> [][3]i32 {
	drops := make([][3]i32, len(surface.vertices), context.temp_allocator)
	for edge in edges {
		for vertex in edge {
			drops[vertex] = field_curtain_drop(surface.vertices[vertex], faces)
		}
	}
	return drops
}

// The flap's two bands below each edge.
append_field_flaps :: proc(surface: ^Field_Surface, edges: [][2]u16, faces: Field_Faces) {
	skirt_vertices := make([]i32, len(surface.vertices), context.temp_allocator)
	for &slot in skirt_vertices {
		slot = -1
	}
	for edge in edges {
		from, to := edge[0], edge[1]
		from_outer := field_skirt_vertex_index(surface, skirt_vertices, from, faces)
		to_outer := field_skirt_vertex_index(surface, skirt_vertices, to, faces)
		append(&surface.indices, to, from, from_outer, to, from_outer, to_outer)
		append(&surface.indices, to_outer, from_outer, from_outer + 1, to_outer, from_outer + 1, to_outer + 1)
	}
}

// The curtain's vertex below a border vertex: a copy of the (cut) vertex
// moved by its drop, made the first time an edge asks.
field_curtain_vertex_index :: proc(surface: ^Field_Surface, lower_vertices: []i32, drops: [][3]i32, vertex: u16) -> u16 {
	slot := &lower_vertices[vertex]
	if slot^ < 0 {
		slot^ = i32(len(surface.vertices))
		lower := surface.vertices[vertex]
		lower.position += drops[vertex]
		append(&surface.vertices, lower)
	}
	return u16(slot^)
}

// The curtain's band below each edge.
append_field_curtains :: proc(surface: ^Field_Surface, edges: [][2]u16, drops: [][3]i32) {
	lower_vertices := make([]i32, len(drops), context.temp_allocator)
	for &slot in lower_vertices {
		slot = -1
	}
	for edge in edges {
		from, to := edge[0], edge[1]
		from_lower := field_curtain_vertex_index(surface, lower_vertices, drops, from)
		to_lower := field_curtain_vertex_index(surface, lower_vertices, drops, to)
		append(&surface.indices, to, from, from_lower, to, from_lower, to_lower)
	}
}

// The skirts of the node's open border on faces. A node's surface stops
// half a cell before its border on one side and half a cell past it on
// the other, so between levels the strip between the meshes is up to
// half a coarse cell wide.
// On faces.flaps (a coarser node or none beyond) an L shaped flap: out of
// the node by one coarse cell along the surface's slope and half a cell
// below it, so it neither stands above the neighbour's ground nor fights
// it in depth, then down by a coarse cell. The outward leg covers the
// strip from above whichever side the coarser node is on.
// On faces.curtains (finer nodes beyond) nothing of the node lies over
// the finer ground: the surface is cut to the node's box
// (cut_field_surface) and a curtain one cell long hangs from the border
// into the ground in the face's plane. A shallow ray from the finer side
// that passes over the finer node's flap and under this surface, whose
// back faces are culled, meets the curtain.
// Each band continues the winding over its edge, so its front faces out
// of the node. A node whose skirts would outgrow the u16 indices keeps
// its surface without them or the cut and logs a line;
// FIELD_MESH_VERTEX_BOUND says this cannot happen with today's grid.
append_field_skirts :: proc(surface: ^Field_Surface, faces: Field_Seam_Faces) {
	flap_edges := make([dynamic][2]u16, context.temp_allocator)
	curtain_edges := make([dynamic][2]u16, context.temp_allocator)
	for edge in field_border_edges(surface, context.temp_allocator) {
		from, to := surface.vertices[edge[0]], surface.vertices[edge[1]]
		if field_edge_on_faces(from, to, faces.flaps) {
			append(&flap_edges, edge)
		}
		if field_edge_on_faces(from, to, faces.curtains) {
			append(&curtain_edges, edge)
		}
	}
	vertex_count := len(surface.vertices)
	skirt_vertex_count := 2 * field_border_vertex_count(flap_edges[:], vertex_count) + field_border_vertex_count(curtain_edges[:], vertex_count)
	if vertex_count + skirt_vertex_count > MESH_PART_VERTEX_LIMIT {
		platform.log_printf("field: a node's skirts would need %d vertices beyond its %d, drawn without them", skirt_vertex_count, vertex_count)
		return
	}
	drops := field_curtain_drops(surface, curtain_edges[:], faces.curtains)
	cut_field_surface(surface, faces)
	append_field_flaps(surface, flap_edges[:], faces.flaps)
	append_field_curtains(surface, curtain_edges[:], drops)
}
