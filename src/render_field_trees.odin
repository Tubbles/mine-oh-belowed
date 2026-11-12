package game

import "core:math"
import "core:math/bits"
import "core:slice"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"
import "render_frustum"

// The trees' draw (work items 0197 and 0310, doc/presentation.md, The
// field session). The standing trees round the eyes come in tiles of
// field_tree_tile_cells tree cubes an edge (about FIELD_TREE_TILE_METRES),
// generated on the field's workers when no chunk job waits
// (world_field_streaming.odin) and kept in a cache by the main thread
// (update_field_tree_cache, before any viewport draws): a tile's keys and
// instances (tree_instance: the tree's transform with its species and
// shade) on the CPU and in a vertex buffer, out to the far distance, at
// most FIELD_TREE_TILES_PENDING_LIMIT on the workers and
// FIELD_TREE_UPLOADS_PER_FRAME taken a frame, nearest first, evicted two
// tiles past the far distance. A felled tree drops out of its tile, which
// goes up again. The near trees, within near_metres and at most
// near_limit nearest first, draw instanced with their species' model; the
// rest out to the far distance as cards (render_tree_cards.odin), three
// crossed quads a tree, a draw a tile while the cards stay within
// far_limit. Both through the tree shader (data/shaders/tree.vs, tree.fs),
// which crosses a tree's model and card over fade_metres by a dither and
// fades the cards out over far_fade_metres, lit by the open sky like the
// models; the distances and the caps are data/game.sjson's field_trees.
// Floats are made here only.
//
// The near models and the sun's casting trees (0346): each viewport has a
// view of the cache (Tree_View, FIELD_TREE_VIEWS) with a pass for each.
// A pass holds its candidates, the standing trees a scan of the tiles
// found within a margin round where it was made (an eighth of
// near_metres), grouped by species, while the eye stays within the
// margin and no change of the cache's tiles (the ring of
// FIELD_TREE_CHANGE_RING boxes, counted by revision) reaches them. Each
// frame the cut runs exactly over the candidates (the distance, the
// frustum or the casters' box, the cap by distance and then key), so the
// drawn set is always what a fresh scan would select. The cut is skipped
// when its inputs are bit equal to the last cut's. The selection goes up into
// the pass's one instance buffer, packed by species, only when it changed
// (commit_tree_selection), and each species draws its range through its
// model's own vertex array (draw_tree_pass).

FIELD_TREE_UPLOADS_PER_FRAME :: 4
FIELD_TREE_TILES_PENDING_LIMIT :: 8
// Tiles are kept this many tile edges past the far distance.
FIELD_TREE_KEEP_TILES :: 2
// The views of the cache, one a viewport (the loop's MAXIMUM_VIEWPORTS,
// asserted there).
FIELD_TREE_VIEWS :: 4
// The changes of the cache's tiles a view can look back over.
FIELD_TREE_CHANGE_RING :: 64
// A pass's candidates hold while the eye stays within near_metres over
// this.
TREE_CANDIDATE_MARGIN_DIVISOR :: 8
// The candidates' reach past the margin, against f32 rounding near 8 km.
TREE_CANDIDATE_SLACK_METRES :: 0.25
TREE_VERTEX_SHADER_PATH :: "shaders/tree.vs"
TREE_FRAGMENT_SHADER_PATH :: "shaders/tree.fs"
// Three quads of two triangles.
TREE_CARD_VERTEX_COUNT :: 18
// The cards' vertices: u and v of a quad and its card, three floats at
// location 0.
TREE_CARD_LAYOUT :: [1]Instanced_Attribute{{location = 0, size = 3, type = rlgl.FLOAT}}

// One tile of the cache: its trees' keys and instances (felled ones
// dropped), its bases' box in metres, the buffers its cards draw from
// (count instances), and dirty while the instances changed since.
Field_Tree_Tile_Draw :: struct {
	keys:      []Tree_Key,
	instances: []matrix[4, 4]f32,
	minimum:   [3]f32,
	maximum:   [3]f32,
	vao:       u32,
	vbo:       u32,
	count:     int,
	dirty:     bool,
}

// A change of the cache's tiles: the bases' box of the tile that came,
// went or lost a tree.
Field_Tree_Change :: struct {
	minimum, maximum: [3]f32,
}

// The tiles round the eyes, the ones on the workers, the felled keys
// already dropped, the tiles' edge in tree cubes (0 before the first
// update), the build target's row of field_trees and the cards' vertices
// (made with the first upload). revision counts the changes of the tiles,
// the last FIELD_TREE_CHANGE_RING of them kept at revision modulo the
// ring, cleared_at the revision of the last time every tile went, and the
// views by the viewport's index (Field_Scene.tree_view).
Field_Tree_Cache :: struct {
	tiles:       map[Field_Tree_Tile]Field_Tree_Tile_Draw,
	pending:     map[Field_Tree_Tile]struct{},
	felled_seen: map[Tree_Key]struct{},
	cells:       i64,
	config:      Field_Trees_Row,
	card_vbo:    u32,
	revision:    u64,
	cleared_at:  u64,
	changes:     [FIELD_TREE_CHANGE_RING]Field_Tree_Change,
	views:       [FIELD_TREE_VIEWS]Tree_View,
}

// A standing tree a pass may draw: its instance and its key.
Tree_Candidate :: struct {
	instance: matrix[4, 4]f32,
	key:      Tree_Key,
}

// A candidate the cut passed: its base's squared distance, its key and
// its index in the candidates.
Tree_Ranked :: struct {
	distance_squared: f32,
	key:              Tree_Key,
	index:            u32,
}

// A species' range in the candidates (first, count) and in the packed
// instances (drawn_first, drawn_count).
Tree_Group :: struct {
	first, count, drawn_first, drawn_count: int,
}

// One pass of a view (the near models or the sun's casters): the
// candidates grouped by species and how many gathers made them, the
// cut's ranked candidates, the next selection and the selection drawn
// (indices into the candidates, ascending), the selection's instances
// packed by species for the gathers they were packed at, and the
// instance buffer they go up into (uploaded once they did).
Tree_Pass :: struct {
	candidates:     [dynamic]Tree_Candidate,
	groups:         [MAXIMUM_TREE_SPECIES]Tree_Group,
	group_count:    int,
	gathers:        int,
	ranked:         [dynamic]Tree_Ranked,
	next:           [dynamic]u32,
	selected:       [dynamic]u32,
	packed_gathers: int,
	packed:         [dynamic]matrix[4, 4]f32,
	buffer:         u32,
	capacity:       int,
	uploaded:       bool,
}

// Where and for what the near candidates were gathered: the eye, the near
// distance, the margin, the radius they reach, the species count and the
// cache's revision they are current at.
Near_Tree_Gather :: struct {
	built:         bool,
	eye:           [3]f32,
	near_metres:   int,
	margin_metres: f32,
	radius_metres: f32,
	species_count: int,
	revision:      u64,
}

// The inputs of the last near cut.
Near_Tree_Cut :: struct {
	camera:        [3]f32,
	frustum:       render_frustum.Frustum,
	extent_metres: f32,
	near_metres:   int,
	near_limit:    int,
	gathers:       int,
}

// A viewport's trees: the near models' pass and the sun's casters' pass,
// each with its gather and its last cut, and the near distance the last
// near cut gave.
Tree_View :: struct {
	near:          Tree_Pass,
	near_gather:   Near_Tree_Gather,
	near_cut:      Near_Tree_Cut,
	near_distance: f32,
	shadow:        Tree_Pass,
	shadow_gather: Shadow_Tree_Gather,
	shadow_cut:    Shadow_Tree_Cut,
}

// A far tile and the distance of its box from the camera.
Far_Tile :: struct {
	tile:     ^Field_Tree_Tile_Draw,
	distance: f32,
}

Tree_Uniform :: enum {
	Card_On,
	Card_Rows,
	Near_Distance,
	Fade_Metres,
	Far_Distance,
	Far_Fade_Metres,
	Species_Tint,
	Species_Card,
}

TREE_UNIFORM_NAMES :: [Tree_Uniform]cstring {
	.Card_On         = "card_on",
	.Card_Rows       = "card_rows",
	.Near_Distance   = "near_distance",
	.Fade_Metres     = "fade_metres",
	.Far_Distance    = "far_distance",
	.Far_Fade_Metres = "far_fade_metres",
	.Species_Tint    = "species_tint",
	.Species_Card    = "species_card",
}

// The tree shader's material (the cards' atlas its albedo) and its
// uniforms, the open sky's, the point lights' and the torchlight's set
// with the model shader's (set_model_open_sky and the others); ready
// once the shader loaded. cards by Machine_Id, card_rows the atlas's
// rows.
Tree_Draw :: struct {
	ready:                    bool,
	material:                 rl.Material,
	atlas:                    rl.Texture2D,
	card_rows:                int,
	cards:                    []Tree_Card,
	locations:                [Tree_Uniform]i32,
	point_light_locations:    [3]i32,
	spot_locations:           [6]i32,
	open_sky_locations:       [Open_Sky_Uniform]i32,
	daylight_tint_location:   i32,
	camera_position_location: i32,
	// The sun's shadow's uniforms (0328, use_sun_shadow_sampler).
	sun_shadow_locations:     [Sun_Shadow_Uniform]i32,
}

// When the shader does not load, a log line, and the field shows no
// trees.
use_tree_shader :: proc(trees: ^Tree_Draw, data_directory: string) {
	shader, ok := load_shader_pair(data_directory, TREE_VERTEX_SHADER_PATH, TREE_FRAGMENT_SHADER_PATH, "tree")
	if !ok {
		platform.log_printf("models: the tree shader did not load; the field draws no trees")
		return
	}
	trees.material = rl.LoadMaterialDefault()
	trees.material.shader = shader
	names := TREE_UNIFORM_NAMES
	for name, uniform in names {
		trees.locations[uniform] = rl.GetShaderLocation(shader, name)
	}
	trees.point_light_locations = {rl.GetShaderLocation(shader, "point_light_positions"), rl.GetShaderLocation(shader, "point_light_colors"), rl.GetShaderLocation(shader, "point_light_boxes")}
	trees.spot_locations = spot_light_locations(shader)
	trees.open_sky_locations = open_sky_locations(shader)
	trees.daylight_tint_location = rl.GetShaderLocation(shader, "daylight_tint")
	trees.camera_position_location = rl.GetShaderLocation(shader, "camera_position")
	trees.sun_shadow_locations = use_sun_shadow_sampler(shader)
	trees.ready = true
}

// The cards baked from the models just loaded, the old atlas replaced
// (replace_machine_models, before any frame draws again).
replace_tree_cards :: proc(trees: ^Tree_Draw, meshes: []Machine_Model_Mesh, machines: Machine_Registry) {
	if !trees.ready {
		return
	}
	atlas := bake_tree_card_atlas(meshes, machines, context.temp_allocator)
	if trees.atlas.id != 0 {
		rl.UnloadTexture(trees.atlas)
	}
	image := rl.Image {
		data    = raw_data(atlas.pixels),
		width   = i32(atlas.width),
		height  = i32(atlas.height),
		mipmaps = i32(atlas.levels),
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	trees.atlas = load_rgba_texture(image)
	rl.SetTextureFilter(trees.atlas, .TRILINEAR)
	rl.SetTextureWrap(trees.atlas, .CLAMP)
	trees.material.maps[rl.MaterialMapIndex.ALBEDO].texture = trees.atlas
	delete(trees.cards)
	trees.cards = slice.clone(atlas.cards)
	trees.card_rows = atlas.rows
}

// UnloadMaterial unloads the shader and the atlas with it.
destroy_tree_draw :: proc(trees: ^Tree_Draw) {
	if trees.ready {
		rl.UnloadMaterial(trees.material)
	}
	delete(trees.cards)
	trees^ = {}
}

// The model's cells (origin at its footprint's bottom centre) to metres:
// the tree's axes as columns, scaled by the pitch and its scale, the base
// as the translation (as frame_render_matrix).
tree_render_matrix :: proc(tree: Planet_Tree, pitch_millimetres: int) -> matrix[4, 4]f32 {
	axes := tree_axes(tree.up, tree.yaw)
	scale := f32(pitch_millimetres) / MILLIMETRES_PER_METRE * f32(tree.scale_percent) / 100
	right := unit_vector_to_f32(axes[0]) * scale
	up := unit_vector_to_f32(axes[1]) * scale
	forward := unit_vector_to_f32(axes[2]) * scale
	origin := world_position_to_metres(tree.base)
	return matrix[4, 4]f32{
		right.x, up.x, forward.x, origin.x,
		right.y, up.y, forward.y, origin.y,
		right.z, up.z, forward.z, origin.z,
		0, 0, 0, 1,
	}
}

// What the tree shader reads of a tree (instanceTransform): its render
// matrix with the species and the shade (0 to about 1) in place of the
// bottom row's first two, which tree.vs rebuilds to 0, 0, 0, 1.
tree_instance :: proc(tree: Planet_Tree, pitch_millimetres: int) -> matrix[4, 4]f32 {
	instance := tree_render_matrix(tree, pitch_millimetres)
	instance[3, 0] = f32(tree.species)
	instance[3, 1] = f32(tree.shade_percent) / 100
	return instance
}

// The instance's base in metres and its species.
tree_instance_base :: proc(instance: matrix[4, 4]f32) -> [3]f32 {
	return {instance[0, 3], instance[1, 3], instance[2, 3]}
}

tree_instance_species :: proc(instance: matrix[4, 4]f32) -> int {
	return int(instance[3, 0] + 0.5)
}

// The cache.

// Frees every tile's buffers and slices; the cache stays usable. Every
// view gathers again (cleared_at).
clear_field_tree_tiles :: proc(cache: ^Field_Tree_Cache) {
	for _, &tile in cache.tiles {
		release_field_tree_tile(&tile)
	}
	clear(&cache.tiles)
	cache.revision += 1
	cache.cleared_at = cache.revision
}

// A change of the tile's trees, kept in the ring. Nothing for a tile
// without trees (its box inverted).
note_field_tree_change :: proc(cache: ^Field_Tree_Cache, tile: Field_Tree_Tile_Draw) {
	if tile.minimum.x > tile.maximum.x {
		return
	}
	cache.revision += 1
	cache.changes[cache.revision % FIELD_TREE_CHANGE_RING] = {tile.minimum, tile.maximum}
}

// The tile into the cache, noted.
insert_field_tree_tile :: proc(cache: ^Field_Tree_Cache, tile: Field_Tree_Tile, draw: Field_Tree_Tile_Draw) {
	cache.tiles[tile] = draw
	note_field_tree_change(cache, draw)
}

// The tile noted, freed and out of the cache.
evict_field_tree_tile :: proc(cache: ^Field_Tree_Cache, tile: Field_Tree_Tile) {
	draw := &cache.tiles[tile]
	note_field_tree_change(cache, draw^)
	release_field_tree_tile(draw)
	delete_key(&cache.tiles, tile)
}

// The changes since the revision, oldest first (temp allocator). Not
// complete when every tile went since or the ring no longer holds them
// all.
field_tree_changes_since :: proc(cache: ^Field_Tree_Cache, since: u64) -> (changes: []Field_Tree_Change, complete: bool) {
	if since < cache.cleared_at || cache.revision - since > FIELD_TREE_CHANGE_RING {
		return nil, false
	}
	changes = make([]Field_Tree_Change, cache.revision - since, context.temp_allocator)
	for &change, index in changes {
		change = cache.changes[(since + 1 + u64(index)) % FIELD_TREE_CHANGE_RING]
	}
	return changes, true
}

destroy_field_tree_cache :: proc(cache: ^Field_Tree_Cache) {
	for &view in cache.views {
		release_tree_view(&view)
	}
	clear_field_tree_tiles(cache)
	delete(cache.tiles)
	delete(cache.pending)
	delete(cache.felled_seen)
	if cache.card_vbo != 0 {
		rlgl.UnloadVertexBuffer(cache.card_vbo)
	}
	cache^ = {}
}

// The tile's buffers (none in a test, which uploads nothing) and slices.
release_field_tree_tile :: proc(tile: ^Field_Tree_Tile_Draw) {
	unload_instanced_buffer(tile.vao, tile.vbo)
	delete(tile.keys)
	delete(tile.instances)
	tile^ = {}
}

// The eyes projected onto the sphere of the radius (temp allocator).
field_tree_eye_points :: proc(generation: ^Planet_Generation, eyes: []World_Position) -> [][3]i64 {
	points := make([][3]i64, len(eyes), context.temp_allocator)
	for eye, index in eyes {
		points[index] = project_onto_sphere(eye, vector_length(cast([3]i64)eye), generation.radius)
	}
	return points
}

// The nearest eye point's squared distance to the tile's box.
field_tree_tile_distance :: proc(tile: Field_Tree_Tile, edge: i64, points: [][3]i64) -> i64 {
	minimum, maximum := field_tree_tile_box(tile, edge)
	nearest := i64(max(i64))
	for point in points {
		nearest = min(nearest, box_distance_squared(Field_Box{World_Position(minimum), World_Position(maximum)}, World_Position(point)))
	}
	return nearest
}

// The tile edge at the generation's tree spacing; 0 without trees.
field_tree_tile_edge :: proc(generation: ^Planet_Generation) -> i64 {
	if generation.trees.spacing == 0 {
		return 0
	}
	return field_tree_tile_cells(generation.trees.spacing) * generation.trees.spacing
}

// Of the tile range round each eye's point on the sphere, the tiles
// straddling the sphere of the radius whose box lies within the distance,
// nearest first, then in key order (temp allocator); none without trees.
field_tree_tiles_around :: proc(generation: ^Planet_Generation, eyes: []World_Position, distance_metres: int) -> []Field_Tree_Tile {
	edge := field_tree_tile_edge(generation)
	if edge == 0 || len(eyes) == 0 {
		return nil
	}
	reach := metres_to_position_units(i64(distance_metres))
	points := field_tree_eye_points(generation, eyes)
	seen := make(map[Field_Tree_Tile]struct{}, context.temp_allocator)
	Ordered_Tile :: struct {
		tile:     Field_Tree_Tile,
		distance: i64,
	}
	ordered := make([dynamic]Ordered_Tile, context.temp_allocator)
	for point in points {
		first, last: [3]i64
		for axis in 0 ..< 3 {
			first[axis] = floor_divide_i64(point[axis] - reach, edge)
			last[axis] = floor_divide_i64(point[axis] + reach, edge)
		}
		for x in first.x ..= last.x {
			for y in first.y ..= last.y {
				for z in first.z ..= last.z {
					tile := Field_Tree_Tile{i32(x), i32(y), i32(z)}
					minimum, maximum := field_tree_tile_box(tile, edge)
					if tile in seen || box_distance_squared(Field_Box{World_Position(minimum), World_Position(maximum)}, World_Position(point)) > reach * reach || !cube_straddles_sphere(minimum, maximum + 1, generation.radius) {
						continue
					}
					seen[tile] = {}
					append(&ordered, Ordered_Tile{tile, field_tree_tile_distance(tile, edge, points)})
				}
			}
		}
	}
	slice.sort_by(ordered[:], proc(first, second: Ordered_Tile) -> bool {
		if first.distance != second.distance {
			return first.distance < second.distance
		}
		return tree_key_before(first.tile, second.tile)
	})
	tiles := make([]Field_Tree_Tile, len(ordered), context.temp_allocator)
	for entry, index in ordered {
		tiles[index] = entry.tile
	}
	return tiles
}

// The tile a key lies in.
field_tree_tile_of_key :: proc(key: Tree_Key, cells: i64) -> Field_Tree_Tile {
	return {i32(floor_divide_i64(i64(key.x), cells)), i32(floor_divide_i64(i64(key.y), cells)), i32(floor_divide_i64(i64(key.z), cells))}
}

// A worker's tile without the felled keys, its bases' box, dirty. Takes
// the slices.
make_field_tree_tile_draw :: proc(keys: []Tree_Key, instances: []matrix[4, 4]f32, felled: map[Tree_Key]struct{}) -> Field_Tree_Tile_Draw {
	tile := Field_Tree_Tile_Draw {
		keys      = keys,
		instances = instances,
		dirty     = true,
	}
	kept := 0
	for key, index in keys {
		if key in felled {
			continue
		}
		tile.keys[kept], tile.instances[kept] = key, instances[index]
		kept += 1
	}
	tile.keys, tile.instances = tile.keys[:kept], tile.instances[:kept]
	tile.minimum, tile.maximum = math.F32_MAX, -math.F32_MAX
	for instance in tile.instances {
		base := tree_instance_base(instance)
		for axis in 0 ..< 3 {
			tile.minimum[axis] = min(tile.minimum[axis], base[axis])
			tile.maximum[axis] = max(tile.maximum[axis], base[axis])
		}
	}
	return tile
}

// The key out of its tile (swapped with the last), the tile dirty and
// noted. False when the tile is not cached or lacks the key.
drop_field_tree_key :: proc(cache: ^Field_Tree_Cache, key: Tree_Key) -> bool {
	tile, found := &cache.tiles[field_tree_tile_of_key(key, cache.cells)]
	if !found {
		return false
	}
	for entry, index in tile.keys {
		if entry != key {
			continue
		}
		last := len(tile.keys) - 1
		tile.keys[index], tile.instances[index] = tile.keys[last], tile.instances[last]
		tile.keys, tile.instances = tile.keys[:last], tile.instances[:last]
		tile.dirty = true
		note_field_tree_change(cache, tile^)
		return true
	}
	return false
}

// The felled keys not seen yet drop out of their tiles. A key gone from
// the felled table (a shorter one) rebuilds every tile: they are freed and
// generated again.
apply_felled_field_trees :: proc(cache: ^Field_Tree_Cache, felled: map[Tree_Key]struct{}) {
	unseen := 0
	for key in felled {
		if key not_in cache.felled_seen {
			unseen += 1
		}
	}
	if len(cache.felled_seen) > len(felled) - unseen {
		clear_field_tree_tiles(cache)
		clear(&cache.felled_seen)
	}
	if unseen == 0 && len(cache.felled_seen) == len(felled) {
		return
	}
	for key in felled {
		if key in cache.felled_seen {
			continue
		}
		cache.felled_seen[key] = {}
		drop_field_tree_key(cache, key)
	}
}

// The finished tiles, FIELD_TREE_UPLOADS_PER_FRAME at most: a tile still
// pending and within the keep distance goes into the cache (dirty, to go
// up), any other is freed.
take_finished_field_tree_tiles :: proc(cache: ^Field_Tree_Cache, streaming: ^Field_Streaming, edge, keep: i64, points: [][3]i64, felled: map[Tree_Key]struct{}) {
	for result in take_field_tree_tiles(streaming, FIELD_TREE_UPLOADS_PER_FRAME) {
		tile := result.tree_tile
		wanted := tile in cache.pending && tile not_in cache.tiles && field_tree_tile_distance(tile, edge, points) <= keep * keep
		delete_key(&cache.pending, tile)
		if !wanted {
			free_field_job_result(result)
			continue
		}
		insert_field_tree_tile(cache, tile, make_field_tree_tile_draw(result.tree_keys, result.tree_instances, felled))
	}
}

// Before any viewport draws (prepare_field_frame, the preview's stream
// step), so no draw reads a tile freed here: the felled keys applied, the
// finished tiles taken, the tiles past the far distance and two tiles
// evicted (their buffers freed), the wanted ones missing sent to the
// workers nearest first while fewer than FIELD_TREE_TILES_PENDING_LIMIT
// are there. upload_field_tree_tiles puts them on the GPU.
update_field_tree_cache :: proc(cache: ^Field_Tree_Cache, streaming: ^Field_Streaming, generation: ^Planet_Generation, eyes: []World_Position, felled: map[Tree_Key]struct{}, config: Field_Trees_Row, pitch_millimetres: int) {
	cache.config = config
	edge := field_tree_tile_edge(generation)
	cells := edge == 0 ? 0 : field_tree_tile_cells(generation.trees.spacing)
	if cells != cache.cells {
		clear_field_tree_tiles(cache)
		clear(&cache.pending)
		clear(&cache.felled_seen)
		cache.cells = cells
	}
	if edge == 0 || len(eyes) == 0 {
		return
	}
	apply_felled_field_trees(cache, felled)
	points := field_tree_eye_points(generation, eyes)
	keep := metres_to_position_units(i64(config.far_metres)) + FIELD_TREE_KEEP_TILES * edge
	take_finished_field_tree_tiles(cache, streaming, edge, keep, points, felled)
	evicted := make([dynamic]Field_Tree_Tile, context.temp_allocator)
	for tile in cache.tiles {
		if field_tree_tile_distance(tile, edge, points) > keep * keep {
			append(&evicted, tile)
		}
	}
	for tile in evicted {
		evict_field_tree_tile(cache, tile)
	}
	for tile in field_tree_tiles_around(generation, eyes, config.far_metres) {
		if len(cache.pending) >= FIELD_TREE_TILES_PENDING_LIMIT {
			break
		}
		if tile in cache.tiles || tile in cache.pending {
			continue
		}
		cache.pending[tile] = {}
		submit_field_tree_tile(streaming, tile, cells, pitch_millimetres)
	}
}

// The cards' 18 vertices: per quad (card 0, 1, 2) its two triangles' u, v.
tree_card_vertices :: proc() -> [TREE_CARD_VERTEX_COUNT][3]f32 {
	corners := [6][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 0}, {1, 1}, {0, 1}}
	vertices: [TREE_CARD_VERTEX_COUNT][3]f32
	for card in 0 ..< 3 {
		for corner, index in corners {
			vertices[card * 6 + index] = {f32(card), corner.x, corner.y}
		}
	}
	return vertices
}

// Every dirty tile up: its vertex array of the cards' vertices at
// location 0 and its instances at INSTANCE_TRANSFORM_LOCATION, one per
// instance (upload_instanced_buffer). After update_field_tree_cache,
// before any viewport draws.
upload_field_tree_tiles :: proc(cache: ^Field_Tree_Cache) {
	for _, &tile in cache.tiles {
		if !tile.dirty {
			continue
		}
		if cache.card_vbo == 0 {
			vertices := tree_card_vertices()
			cache.card_vbo = rlgl.LoadVertexBuffer(&vertices, size_of(vertices), false)
		}
		upload_field_tree_tile(&tile, cache.card_vbo)
	}
}

upload_field_tree_tile :: proc(tile: ^Field_Tree_Tile_Draw, card_vbo: u32) {
	unload_instanced_buffer(tile.vao, tile.vbo)
	tile.count = len(tile.instances)
	tile.dirty = false
	layout := TREE_CARD_LAYOUT
	tile.vao, tile.vbo = upload_instanced_buffer(card_vbo, layout[:], 0, tile.instances)
}

// Every tile the eyes want out to the far distance is cached and up.
field_tree_cache_settled :: proc(cache: ^Field_Tree_Cache, generation: ^Planet_Generation, eyes: []World_Position) -> bool {
	for tile in field_tree_tiles_around(generation, eyes, cache.config.far_metres) {
		cached, found := cache.tiles[tile]
		if !found || cached.dirty {
			return false
		}
	}
	return true
}

// The draw.

// The distance from the point to the box, 0 inside.
box_distance_metres :: proc(minimum, maximum, point: [3]f32) -> f32 {
	nearest := [3]f32{clamp(point.x, minimum.x, maximum.x), clamp(point.y, minimum.y, maximum.y), clamp(point.z, minimum.z, maximum.z)}
	offset := point - nearest
	return math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
}

// The passes' pure parts.

// How far the eye may move before a pass gathers again: an eighth of the
// near distance.
tree_candidate_margin_metres :: proc(config: Field_Trees_Row) -> f32 {
	return f32(config.near_metres) / TREE_CANDIDATE_MARGIN_DIVISOR
}

// The one expression every distance test and rank of the passes uses.
squared_distance_metres :: proc(first, second: [3]f32) -> f32 {
	offset := first - second
	return offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
}

// The instance's group: its species modulo the species count, 0 for every
// tree without species.
tree_species_group :: proc(instance: matrix[4, 4]f32, species_count: int) -> int {
	return tree_instance_species(instance) % clamp(species_count, 1, MAXIMUM_TREE_SPECIES)
}

// The groups' lists (temp) one after the other into the candidates, their
// ranges kept and the gather counted.
group_tree_candidates :: proc(pass: ^Tree_Pass, groups: ^[MAXIMUM_TREE_SPECIES][dynamic]Tree_Candidate, species_count: int) {
	clear(&pass.candidates)
	for &list, group in groups^ {
		pass.groups[group] = {first = len(pass.candidates), count = len(list)}
		append(&pass.candidates, ..list[:])
	}
	pass.group_count = clamp(species_count, 1, MAXIMUM_TREE_SPECIES)
	pass.gathers += 1
}

// Nearer first, then by key.
tree_ranked_before :: proc(first, second: Tree_Ranked) -> bool {
	if first.distance_squared != second.distance_squared {
		return first.distance_squared < second.distance_squared
	}
	return tree_key_before(first.key, second.key)
}

// The index of the median of the first, middle and last by
// tree_ranked_before.
median_of_three_ranked :: proc(ranked: []Tree_Ranked) -> int {
	first, middle, last := 0, len(ranked) / 2, len(ranked) - 1
	if tree_ranked_before(ranked[middle], ranked[first]) {
		first, middle = middle, first
	}
	if tree_ranked_before(ranked[last], ranked[middle]) {
		middle = last
		if tree_ranked_before(ranked[middle], ranked[first]) {
			middle = first
		}
	}
	return middle
}

// Hoare's partition of at least two round the median of three moved to
// the front: every entry up to the returned split (which lies below the
// last) is not after every one past it.
partition_ranked :: proc(ranked: []Tree_Ranked) -> int {
	pivot_index := median_of_three_ranked(ranked)
	ranked[0], ranked[pivot_index] = ranked[pivot_index], ranked[0]
	pivot := ranked[0]
	low, high := -1, len(ranked)
	for {
		low += 1
		for tree_ranked_before(ranked[low], pivot) {
			low += 1
		}
		high -= 1
		for tree_ranked_before(pivot, ranked[high]) {
			high -= 1
		}
		if low >= high {
			return high
		}
		ranked[low], ranked[high] = ranked[high], ranked[low]
	}
}

// Needs count below the length. Afterwards ranked[:count] are the count
// first by tree_ranked_before and ranked[count] the next: Hoare's
// partitions narrowing to count, the rest sorted after twice the length's
// bits of rounds, so the worst case stays n log n.
select_nearest_ranked :: proc(ranked: []Tree_Ranked, count: int) {
	assert(count < len(ranked))
	low, high := 0, len(ranked) - 1
	rounds := 2 * bits.len(uint(len(ranked)))
	for low < high {
		if rounds == 0 {
			slice.sort_by(ranked[low:high + 1], tree_ranked_before)
			return
		}
		rounds -= 1
		split := low + partition_ranked(ranked[low:high + 1])
		if count <= split {
			high = split
		} else {
			low = split + 1
		}
	}
}

// The ranked candidates' indices into next, ascending: all of them within
// the limit, else the limit nearest and the first cut's distance.
finish_tree_cut :: proc(pass: ^Tree_Pass, limit: int) -> (cut_distance_squared: f32, cut: bool) {
	clear(&pass.next)
	if len(pass.ranked) <= limit {
		for entry in pass.ranked {
			append(&pass.next, entry.index)
		}
		return 0, false
	}
	select_nearest_ranked(pass.ranked[:], limit)
	for entry in pass.ranked[:limit] {
		append(&pass.next, entry.index)
	}
	slice.sort(pass.next[:])
	return pass.ranked[limit].distance_squared, true
}

// The next selection becomes the one drawn and is packed, unless it and
// its gather are the ones packed already.
commit_tree_selection :: proc(pass: ^Tree_Pass) {
	if pass.packed_gathers == pass.gathers && slice.equal(pass.next[:], pass.selected[:]) {
		return
	}
	pass.next, pass.selected = pass.selected, pass.next
	pack_tree_selection(pass)
	pass.packed_gathers = pass.gathers
	pass.uploaded = false
}

// The selected candidates' instances in order, each group's range in them.
pack_tree_selection :: proc(pass: ^Tree_Pass) {
	clear(&pass.packed)
	for &group in pass.groups {
		group.drawn_first, group.drawn_count = 0, 0
	}
	group := 0
	for index, position in pass.selected {
		for int(index) >= pass.groups[group].first + pass.groups[group].count {
			group += 1
		}
		if pass.groups[group].drawn_count == 0 {
			pass.groups[group].drawn_first = position
		}
		pass.groups[group].drawn_count += 1
		append(&pass.packed, pass.candidates[index].instance)
	}
}

// The pass's arrays and its buffer (none in a test).
release_tree_pass :: proc(pass: ^Tree_Pass) {
	delete(pass.candidates)
	delete(pass.ranked)
	delete(pass.next)
	delete(pass.selected)
	delete(pass.packed)
	unload_instanced_buffer(0, pass.buffer)
	pass^ = {}
}

release_tree_view :: proc(view: ^Tree_View) {
	release_tree_pass(&view.near)
	release_tree_pass(&view.shadow)
	view^ = {}
}

// The near pass.

// The standing trees whose base lies within the radius of the eye, from
// the tiles whose bases' box does.
gather_near_tree_candidates :: proc(pass: ^Tree_Pass, cache: ^Field_Tree_Cache, eye: [3]f32, radius_metres: f32, felled: map[Tree_Key]struct{}, species_count: int) {
	groups: [MAXIMUM_TREE_SPECIES][dynamic]Tree_Candidate
	for &list in groups {
		list = make([dynamic]Tree_Candidate, context.temp_allocator)
	}
	for _, tile in cache.tiles {
		if len(tile.instances) == 0 || box_distance_metres(tile.minimum, tile.maximum, eye) > radius_metres {
			continue
		}
		for instance, index in tile.instances {
			if squared_distance_metres(tree_instance_base(instance), eye) > radius_metres * radius_metres || tile.keys[index] in felled {
				continue
			}
			append(&groups[tree_species_group(instance, species_count)], Tree_Candidate{instance, tile.keys[index]})
		}
	}
	group_tree_candidates(pass, &groups, species_count)
}

// The near candidates must be gathered again: none yet, another near
// distance or species count, the camera past the margin from where they
// were, or a change of the tiles since that reaches their radius (or
// changes the ring no longer holds).
near_tree_candidates_stale :: proc(cache: ^Field_Tree_Cache, gather: Near_Tree_Gather, camera: [3]f32, near_metres, species_count: int) -> bool {
	if !gather.built || gather.near_metres != near_metres || gather.species_count != species_count {
		return true
	}
	if squared_distance_metres(camera, gather.eye) > gather.margin_metres * gather.margin_metres {
		return true
	}
	changes, complete := field_tree_changes_since(cache, gather.revision)
	if !complete {
		return true
	}
	for change in changes {
		if box_distance_metres(change.minimum, change.maximum, gather.eye) <= gather.radius_metres {
			return true
		}
	}
	return false
}

// The candidates within near_metres of the camera (compared before the
// frustum, as the scan did) whose box (the base and the extent either
// way) is in the frustum, ranked. Past near_limit the nearest by distance
// and then key. near_distance is the first one cut's, else near_metres:
// every tree nearer is selected.
cut_near_trees :: proc(pass: ^Tree_Pass, camera: [3]f32, frustum: render_frustum.Frustum, extent_metres: f32, config: Field_Trees_Row) -> (near_distance: f32) {
	near := f32(config.near_metres)
	clear(&pass.ranked)
	for candidate, index in pass.candidates {
		base := tree_instance_base(candidate.instance)
		squared := squared_distance_metres(base, camera)
		if squared > near * near || !render_frustum.frustum_contains_box(frustum, base - extent_metres, base + extent_metres) {
			continue
		}
		append(&pass.ranked, Tree_Ranked{squared, candidate.key, u32(index)})
	}
	cut_distance_squared, cut := finish_tree_cut(pass, config.near_limit)
	return cut ? math.sqrt(cut_distance_squared) : near
}

// The view's near selection for the camera (the cache's row): the
// candidates gathered again when stale, at near_metres, the margin and
// the slack round the camera, else current at the cache's revision. The
// cut and its commit when its inputs changed. Returns the near distance.
update_near_trees :: proc(cache: ^Field_Tree_Cache, view: ^Tree_View, camera: [3]f32, frustum: render_frustum.Frustum, extent_metres: f32, felled: map[Tree_Key]struct{}, species_count: int) -> (near_distance: f32) {
	config := cache.config
	pass := &view.near
	if near_tree_candidates_stale(cache, view.near_gather, camera, config.near_metres, species_count) {
		margin := tree_candidate_margin_metres(config)
		radius := f32(config.near_metres) + margin + TREE_CANDIDATE_SLACK_METRES
		gather_near_tree_candidates(pass, cache, camera, radius, felled, species_count)
		view.near_gather = Near_Tree_Gather {
			built         = true,
			eye           = camera,
			near_metres   = config.near_metres,
			margin_metres = margin,
			radius_metres = radius,
			species_count = species_count,
			revision      = cache.revision,
		}
	} else {
		view.near_gather.revision = cache.revision
	}
	cut := Near_Tree_Cut{camera, frustum, extent_metres, config.near_metres, config.near_limit, pass.gathers}
	if cut != view.near_cut {
		view.near_distance = cut_near_trees(pass, camera, frustum, extent_metres, config)
		view.near_cut = cut
		commit_tree_selection(pass)
	}
	return view.near_distance
}

// The tiles with cards within far_metres whose box (widened by the
// extent) is in the frustum, nearest first, while their running count
// stays within far_limit (temp allocator). far_distance is the first tile
// left out's, else far_metres: every tree nearer is in a listed tile.
select_far_tiles :: proc(cache: ^Field_Tree_Cache, camera_metres: [3]f32, frustum: render_frustum.Frustum, extent_metres: f32, config: Field_Trees_Row) -> (tiles: []Far_Tile, far_distance: f32) {
	far := f32(config.far_metres)
	candidates := make([dynamic]Far_Tile, context.temp_allocator)
	for _, &tile in cache.tiles {
		if tile.count == 0 {
			continue
		}
		minimum, maximum := tile.minimum - extent_metres, tile.maximum + extent_metres
		distance := box_distance_metres(minimum, maximum, camera_metres)
		if distance > far || !render_frustum.frustum_contains_box(frustum, minimum, maximum) {
			continue
		}
		append(&candidates, Far_Tile{&tile, distance})
	}
	slice.sort_by(candidates[:], proc(first, second: Far_Tile) -> bool {
		return first.distance < second.distance
	})
	running := 0
	for entry, index in candidates {
		if running + entry.tile.count > config.far_limit {
			return candidates[:index], entry.distance
		}
		running += entry.tile.count
	}
	return candidates[:], far
}

// The widest reach of a species' model from its base in metres at the
// pitch and its most scale: its top or its half footprint diagonal.
field_tree_model_extent :: proc(scene: Field_Scene) -> f32 {
	extent: f32 = 0
	for species in scene.content.field.tree_species {
		model, found := machine_model(scene.models, species.machine)
		if !found {
			continue
		}
		footprint := scene.content.machines.machines[species.machine].footprint
		diagonal := math.sqrt(f32(footprint.x * footprint.x + footprint.z * footprint.z)) / 2
		extent = max(extent, max(model.top, diagonal) * f32(species.most_scale_percent) / 100)
	}
	return extent * f32(scene.content.field.foundation_pitch_millimetres) / MILLIMETRES_PER_METRE
}

// Per species the tint (0 to 1) and the card (half width, top, crown,
// row, -1 without a card).
set_tree_species_uniforms :: proc(trees: Tree_Draw, species_list: []Field_Tree_Species) {
	tints: [MAXIMUM_TREE_SPECIES][3]f32
	cards: [MAXIMUM_TREE_SPECIES][4]f32
	for index in 0 ..< MAXIMUM_TREE_SPECIES {
		cards[index] = {0, 0, 0, -1}
		if index >= len(species_list) {
			continue
		}
		species := species_list[index]
		tints[index] = [3]f32{f32(species.tint.r), f32(species.tint.g), f32(species.tint.b)} / 255
		if int(species.machine) < len(trees.cards) && trees.cards[species.machine].row >= 0 {
			card := trees.cards[species.machine]
			cards[index] = {card.size.half_width, card.size.top, card.size.crown, f32(card.row)}
		}
	}
	shader := trees.material.shader
	rl.SetShaderValueV(shader, trees.locations[.Species_Tint], &tints, .VEC3, MAXIMUM_TREE_SPECIES)
	rl.SetShaderValueV(shader, trees.locations[.Species_Card], &cards, .VEC4, MAXIMUM_TREE_SPECIES)
}

set_tree_float :: proc(trees: Tree_Draw, uniform: Tree_Uniform, value: f32) {
	value := value
	rl.SetShaderValue(trees.material.shader, trees.locations[uniform], &value, .FLOAT)
}

// Inside BeginMode3D with the field camera, after the machines and the
// open sky's uniforms (set_model_open_sky): the near trees' models, then
// the far trees' cards, lit by the open sky, times the species' tint and
// the tree's shade. Nothing without the tree shader.
draw_field_trees :: proc(scene: Field_Scene, camera: rl.Camera3D) {
	trees := scene.models.trees
	cache := &scene.renderer.trees
	if !trees.ready || len(cache.tiles) == 0 {
		return
	}
	config := cache.config
	view_projection := rlgl.GetMatrixProjection() * rl.GetCameraMatrix(camera)
	frustum := render_frustum.frustum_from_matrix(cast(matrix[4, 4]f32)view_projection)
	extent := field_tree_model_extent(scene)
	species := scene.content.field.tree_species
	view := &cache.views[scene.tree_view]
	near_distance := update_near_trees(cache, view, camera.position, frustum, extent, scene.state.field.felled_trees, len(species))
	far, far_distance := select_far_tiles(cache, camera.position, frustum, extent, config)
	sky := model_light_tint(with_light_level(0, .Sky, MAXIMUM_LIGHT), scene.frame.day_factor, scene.frame.sky_tint)
	set_tree_species_uniforms(trees, species)
	set_tree_float(trees, .Card_Rows, f32(trees.card_rows))
	set_tree_float(trees, .Near_Distance, near_distance)
	set_tree_float(trees, .Fade_Metres, f32(config.fade_metres))
	set_tree_float(trees, .Far_Distance, far_distance)
	set_tree_float(trees, .Far_Fade_Metres, f32(config.far_fade_metres))
	draw_near_trees(scene.models, species, &view.near, brightness_color(sky))
	draw_far_tree_cards(trees, far, brightness_color(sky), scene.lights.sun_shadow.texture)
	count_frame(scene.profile, .Near_Trees, len(view.near.selected))
	count_frame(scene.profile, .Far_Tiles, len(far))
	cards := 0
	for entry in far {
		cards += entry.tile.count
	}
	count_frame(scene.profile, .Far_Cards, cards)
}

// The near pass instanced through the tree shader's material.
draw_near_trees :: proc(models: Model_Renderer, species_list: []Field_Tree_Species, pass: ^Tree_Pass, daylight: rl.Color) {
	trees := models.trees
	if len(pass.selected) == 0 || len(species_list) == 0 {
		return
	}
	set_tree_float(trees, .Card_On, 0)
	material := trees.material
	material.maps[rl.MaterialMapIndex.ALBEDO].color = daylight
	draw_tree_pass(models, species_list, pass, material)
}

// The pass's selection with the material: up into its buffer when it
// changed since the last upload, then a draw a species with a model of
// its range: the near models with the tree shader's material, the sun's
// casters with the depth material (0328, draw_field_sun_shadows).
draw_tree_pass :: proc(models: Model_Renderer, species_list: []Field_Tree_Species, pass: ^Tree_Pass, material: rl.Material) {
	if !pass.uploaded {
		upload_instances_in_place(&pass.buffer, &pass.capacity, pass.packed[:])
		pass.uploaded = true
	}
	if len(pass.packed) == 0 || len(species_list) == 0 {
		return
	}
	begin_instanced_material(material)
	for group in 0 ..< min(pass.group_count, len(species_list)) {
		range := pass.groups[group]
		if range.drawn_count == 0 {
			continue
		}
		model, found := machine_model(models, species_list[group].machine)
		if !found || model.body[.Lit].vertexCount == 0 {
			continue
		}
		draw_mesh_instances(model.body[.Lit], pass.buffer, range.drawn_first, range.drawn_count)
	}
	end_instanced_material(material)
}

// The far tiles' cards: the batch flushed, the tree shader with mvp as
// raylib's instanced draw sets it, the atlas and the sun's shadow map
// (0328, 0 for none) bound, a draw a tile of its instances, both faces.
draw_far_tree_cards :: proc(trees: Tree_Draw, far: []Far_Tile, daylight: rl.Color, shadow_texture: u32) {
	if len(far) == 0 {
		return
	}
	rlgl.DrawRenderBatchActive()
	shader := trees.material.shader
	set_tree_float(trees, .Card_On, 1)
	diffuse := [4]f32{f32(daylight.r), f32(daylight.g), f32(daylight.b), f32(daylight.a)} / 255
	rl.SetShaderValue(shader, shader.locs[int(rl.ShaderLocationIndex.COLOR_DIFFUSE)], &diffuse, .VEC4)
	slot: i32 = 0
	rl.SetShaderValue(shader, shader.locs[int(rl.ShaderLocationIndex.MAP_ALBEDO)], &slot, .INT)
	rl.SetShaderValueMatrix(shader, shader.locs[int(rl.ShaderLocationIndex.MATRIX_MVP)], instanced_mvp())
	rlgl.EnableShader(shader.id)
	rlgl.ActiveTextureSlot(0)
	rlgl.EnableTexture(trees.atlas.id)
	bind_sun_shadow_texture(shader, shadow_texture)
	rlgl.DisableBackfaceCulling()
	for entry in far {
		rlgl.EnableVertexArray(entry.tile.vao)
		rlgl.DrawVertexArrayInstanced(0, TREE_CARD_VERTEX_COUNT, i32(entry.tile.count))
		count_draw_call()
	}
	rlgl.EnableBackfaceCulling()
	rlgl.DisableVertexArray()
	unbind_sun_shadow_texture(shadow_texture)
	rlgl.DisableTexture()
	rlgl.DisableShader()
}
