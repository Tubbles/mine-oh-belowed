package game

import "core:hash/xxhash"
import "core:math"
import "core:math/linalg"
import "core:slice"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "platform"

// The sun's shadow on the field (work item 0328, doc/presentation.md,
// Light on the field). One cascade round the eye, not fitted to the
// frustum, so turning the camera redraws nothing: the receivers are the
// sphere of radius_metres round the camera, the shadow fading out over its
// last SUN_SHADOW_FADE_SHARE so no edge shows; the map's half size is the
// radius plus SUN_SHADOW_MARGIN_TEXELS texels and half a step, so the
// normal offset and the taps stay inside it wherever the eye stands in
// its step. The light's axes are the sun and the sun path's axis turned
// to the world as the sun is (field_sun_path_world_axis): the sun is
// always square to it, so the basis never degenerates. The centre is an
// anchor moved by whole steps of SUN_SHADOW_SNAP_TEXELS texels along the
// three axes, the sun's included, to the step that holds the eye (in
// f64). A kept map anchors at its previous centre, so a walk shifts it by
// whole texels and no edge changes. The whole pass anchors at the
// world's origin. The ortho box
// runs from the sphere's sun side to its far side, so the depth's bits
// cover only the receivers; a caster up to caster_reach_metres beyond
// the near plane towards the sun is drawn and pressed onto that plane by
// sun_shadow.vs, so a ridge or a tree towards a low sun still shadows the
// sphere. The casters (draw_field_sun_shadows, loop_field_session.odin)
// draw depth only, culling off since models may be open shells.
// A receiver moves SUN_SHADOW_NORMAL_OFFSET_TEXELS along its shading
// normal and SUN_SHADOW_DEPTH_BIAS_TEXELS towards the sun in depth; the
// 4 by 4 texels round it are compared and weighted as the mean of the 3
// by 3 bilinear lookups, an edge three texels soft (sun_shadow_light in
// field.fs, model.fs, tree.fs and cover.fs). The comparisons run in the
// shader through a plain highp sampler2D on the depth texture as
// rlLoadTextureDepth makes it (nearest, clamped, no compare mode): rlgl
// offers no compare mode, and a plain sampler keeps sampler2DShadow, a new
// driver path, off Gladio and the phone. The shadow scales only the
// sun's term of the light, by strength_percent at most. The map is made
// by the first pass that wants it and freed or replaced only between
// frames (serve_sun_shadows) or with the field renderer
// (destroy_field_renderer), the receivers' slots cleared first.
//
// Each viewport keeps a map of its still casters (work item 0348,
// Sun_Shadow_Kept): the terrain, the trees, the foundations and the
// machines whose parts never move. Every frame it is copied into the map
// the receivers read (copy_sun_shadow_depth) and the moving casters (the
// arms, the drills, the launch pads, the hatches, the machines whose
// motion moves a part, the players) are drawn over the copy. The kept map
// is drawn again only when sun_shadow_kept_step asks: the sun turned past
// sun_shadow_turn_limit (the tip of a 10 m caster's shadow moved a
// quarter texel, a twelfth of the edge's width), the row changed, the eye
// left its step, the trees started or stopped casting, the frame table or
// the models changed, or the terrain's fingerprint or a gather of the
// trees in its box did. While the pod's transform is set, in the planet
// preview and for a viewport whose kept map did not load, the whole pass
// draws into the shared map every frame.

SUN_SHADOW_VERTEX_SHADER_PATH :: "shaders/sun_shadow.vs"
SUN_SHADOW_FRAGMENT_SHADER_PATH :: "shaders/sun_shadow.fs"
// Texels past the radius on each side of the map.
SUN_SHADOW_MARGIN_TEXELS :: 4
// The share of the radius over which the shadow fades out.
SUN_SHADOW_FADE_SHARE :: 0.25
// The shaders' sun_shadow_normal_offset_texels and
// sun_shadow_depth_bias_texels (shader_source_test.odin compares them).
SUN_SHADOW_NORMAL_OFFSET_TEXELS :: 2.0
SUN_SHADOW_DEPTH_BIAS_TEXELS :: 0.5
// The receivers' material slot that holds the map: DrawMesh and
// begin_instanced_material bind it to texture unit 2 and the sampler at
// the shader location MAP_ALBEDO + 2 (use_sun_shadow_sampler).
SUN_SHADOW_MAP_SLOT :: rl.MaterialMapIndex.NORMAL
SUN_SHADOW_SAMPLER_LOCATION :: int(rl.ShaderLocationIndex.MAP_ALBEDO) + int(SUN_SHADOW_MAP_SLOT)
// Cells each way an entity's cast box (sun_shadow_entity_box) reaches
// past its footprint, for the parts that leave it (an arm, a door).
SUN_SHADOW_ENTITY_MARGIN_CELLS :: 1
// The centre's step along each light axis in texels (0348): the margin
// grows by half of it.
SUN_SHADOW_SNAP_TEXELS :: 32
// How far the tip of a SUN_SHADOW_STEP_CASTER_METRES caster's shadow may
// move in texels before a kept map turns with the sun
// (sun_shadow_turn_limit).
SUN_SHADOW_STEP_TEXELS :: 0.25
SUN_SHADOW_STEP_CASTER_METRES :: 10.0
// Float noise allowed in the step test (sun_shadow_eye_in_step).
SUN_SHADOW_STEP_TOLERANCE_METRES :: 1e-4
// A kept map per viewport (the loop asserts MAXIMUM_VIEWPORTS), and the
// slot of a pass that keeps none (the planet preview).
SUN_SHADOW_KEPT_MAPS :: 4
SUN_SHADOW_NO_KEPT_MAP :: -1
// GL_DEPTH_BUFFER_BIT, the copy's mask.
SUN_SHADOW_DEPTH_BUFFER_BIT :: 0x00000100

Sun_Shadow_State :: enum u8 {
	Unloaded,
	Ready,
	Failed,
}

// The map on the GPU: the framebuffer, its depth texture and the size it
// holds or failed at; the depth only material the casters draw with and
// its instanced_on uniform. kept holds each viewport's kept map of the
// still casters by the viewport's index (0348).
Sun_Shadow_Renderer :: struct {
	state:              Sun_Shadow_State,
	framebuffer:        u32,
	depth_texture:      u32,
	texels:             int,
	material:           rl.Material,
	instanced_location: i32,
	kept:               [SUN_SHADOW_KEPT_MAPS]Sun_Shadow_Kept,
}

// One frame's cascade: the light's view, projection and their product;
// the stepped centre (in f32 and in f64, the step test's and the next
// anchor's) and the light's axes (right, up and towards the sun); the
// map's half size and a texel in metres, the receivers' radius and how
// far beyond the near plane towards the sun casters reach.
Sun_Shadow_Cascade :: struct {
	view, projection, view_projection:                    matrix[4, 4]f32,
	centre, right, up, toward_sun:                        [3]f32,
	precise_centre:                                       [3]f64,
	half_size, texel_metres, radius_metres, reach_metres: f32,
}

// The change counters a kept map was drawn at (0348): the field
// renderer's meshes, the hash of the frame's node selection, the tree
// cache's tiles (0346), the frame table and the models.
Sun_Shadow_Revisions :: struct {
	meshes, selection, trees, frames, models: u64,
}

// What a kept map was drawn from: its cascade, the sun and the path's
// axis the cascade was built on (as the frame gave them, so a Recentre
// builds the same axes bit for bit), the row, whether the trees cast, the
// revisions, the fingerprint of the terrain it drew and the gathers count
// of the view's casting trees it drew (0346, Tree_Pass.gathers).
Sun_Shadow_Kept_Key :: struct {
	cascade:             Sun_Shadow_Cascade,
	toward_sun:          [3]f32,
	path_axis:           [3]f32,
	row:                 Sun_Shadows_Row,
	trees_drawn:         bool,
	revisions:           Sun_Shadow_Revisions,
	terrain_fingerprint: u64,
	tree_gathers:        int,
}

// A viewport's kept map of the still casters: its own framebuffer and
// depth texture at the shared map's size, whether it holds a drawing and
// what it was drawn from.
Sun_Shadow_Kept :: struct {
	state:         Sun_Shadow_State,
	framebuffer:   u32,
	depth_texture: u32,
	drawn:         bool,
	key:           Sun_Shadow_Kept_Key,
}

// What a frame offers a kept map: the eye, the sun, the path's axis and
// the up, the row, whether the trees cast and the revisions.
Sun_Shadow_View :: struct {
	eye, toward_sun, path_axis, up: [3]f32,
	row:                            Sun_Shadows_Row,
	trees_drawn:                    bool,
	revisions:                      Sun_Shadow_Revisions,
}

// What a kept map does this frame (sun_shadow_kept_step): kept as is,
// kept after the fingerprints agree, drawn again on the sun it holds, or
// drawn again on the frame's sun.
Sun_Shadow_Kept_Step :: enum u8 {
	Keep,
	Compare,
	Recentre,
	Turn,
}

// Which machines and players a cast pass draws: every one (the whole
// pass), the still ones (a kept map) or the moving ones (over its copy).
Sun_Shadow_Part :: enum u8 {
	All,
	Still,
	Moving,
}

// What the receiving shaders read: the light's view projection, the
// share of the sun a full shadow takes, the shape (the map's texels a
// side, a texel in metres, the distances from the eye where the shadow
// starts to fade and is gone) and the depth texture. Zero is off.
Sun_Shadow_Frame :: struct {
	view_projection: matrix[4, 4]f32,
	strength:        f32,
	shape:           [4]f32,
	texture:         u32,
}

// What the pass reads besides the scene: whether the setting (or the
// row's default) has it on, the build's row, the strength and where the
// depth shaders load from.
Sun_Shadow_Inputs :: struct {
	on:               bool,
	row:              Sun_Shadows_Row,
	strength_percent: int,
	data_directory:   string,
}

sun_shadow_inputs :: proc(settings: Settings, config: Sun_Shadows_Config, data_directory: string) -> Sun_Shadow_Inputs {
	row := sun_shadows_row(config)
	return Sun_Shadow_Inputs {
		on = sun_shadows_enabled(settings.sun_shadows, row.on),
		row = row,
		strength_percent = config.strength_percent,
		data_directory = data_directory,
	}
}

Sun_Shadow_Uniform :: enum {
	Matrix,
	Strength,
	Shape,
}

SUN_SHADOW_UNIFORM_NAMES :: [Sun_Shadow_Uniform]cstring {
	.Matrix   = "sun_shadow_matrix",
	.Strength = "sun_shadow_strength",
	.Shape    = "sun_shadow_shape",
}

// The cascade for the eye and the sun (both in the world's metres, the
// sun and the axis unit): a texel covers the radius's diameter over the
// map less its margins and a step. The centre is the anchor moved along
// right, up and toward_sun by the whole steps (SUN_SHADOW_SNAP_TEXELS
// texels) nearest the eye. The light looks down -toward_sun from half a
// box sunward of the centre, its right square to the sun and the path's
// axis. The default anchor, the world's origin, is the whole pass's.
sun_shadow_cascade :: proc(eye, toward_sun, path_axis: [3]f32, row: Sun_Shadows_Row, anchor: [3]f64 = {}) -> Sun_Shadow_Cascade {
	radius := f64(row.radius_metres)
	texel := 2 * radius / f64(row.map_texels - 2 * SUN_SHADOW_MARGIN_TEXELS - SUN_SHADOW_SNAP_TEXELS)
	half := f64(row.map_texels) * texel / 2
	step := SUN_SHADOW_SNAP_TEXELS * texel
	sun := linalg.normalize(linalg.array_cast(toward_sun, f64))
	right := linalg.normalize(linalg.cross(-sun, linalg.array_cast(path_axis, f64)))
	up := linalg.cross(right, -sun)
	offset := linalg.array_cast(eye, f64) - anchor
	centre := anchor
	for axis in ([3][3]f64{right, up, sun}) {
		centre += axis * (math.round(linalg.dot(offset, axis) / step) * step)
	}
	cascade := Sun_Shadow_Cascade {
		precise_centre = centre,
		centre        = linalg.array_cast(centre, f32),
		right         = linalg.array_cast(right, f32),
		up            = linalg.array_cast(up, f32),
		toward_sun    = linalg.array_cast(sun, f32),
		half_size     = f32(half),
		texel_metres  = f32(texel),
		radius_metres = f32(radius),
		reach_metres  = f32(row.caster_reach_metres),
	}
	cascade.view = linalg.matrix4_look_at_f32(cascade.centre + cascade.toward_sun * cascade.half_size, cascade.centre, cascade.up)
	cascade.projection = linalg.matrix_ortho3d_f32(-cascade.half_size, cascade.half_size, -cascade.half_size, cascade.half_size, 0, 2 * cascade.half_size)
	cascade.view_projection = cascade.projection * cascade.view
	return cascade
}

// Whether the eye lies within half a step of the cascade's centre along
// each of its three axes (in f64, with SUN_SHADOW_STEP_TOLERANCE_METRES
// for float noise): a kept map drawn round that centre still covers it.
sun_shadow_eye_in_step :: proc(cascade: Sun_Shadow_Cascade, eye: [3]f32) -> bool {
	offset := linalg.array_cast(eye, f64) - cascade.precise_centre
	reach := SUN_SHADOW_SNAP_TEXELS * f64(cascade.texel_metres) / 2 + SUN_SHADOW_STEP_TOLERANCE_METRES
	for axis in ([3][3]f32{cascade.right, cascade.up, cascade.toward_sun}) {
		if abs(linalg.dot(offset, linalg.array_cast(axis, f64))) > reach {
			return false
		}
	}
	return true
}

// The angle in radians between the sun a kept map holds and the frame's,
// both normalised in f64.
sun_shadow_turn_angle :: proc(held, current: [3]f32) -> f64 {
	first := linalg.normalize(linalg.array_cast(held, f64))
	second := linalg.normalize(linalg.array_cast(current, f64))
	return math.atan2(linalg.length(linalg.cross(first, second)), linalg.dot(first, second))
}

// How far the sun may turn from the one a kept map holds: a caster
// SUN_SHADOW_STEP_CASTER_METRES tall on flat ground casts its tip from
// its height over the sine of the sun's elevation up the ray, so a turn of
// this many radians moves the tip SUN_SHADOW_STEP_TEXELS texels. 0 with
// the sun at or under the horizon of the up.
sun_shadow_turn_limit :: proc(toward_sun, up: [3]f32, texel_metres: f32) -> f64 {
	sine := linalg.dot(linalg.normalize(linalg.array_cast(toward_sun, f64)), linalg.normalize(linalg.array_cast(up, f64)))
	return SUN_SHADOW_STEP_TEXELS * f64(texel_metres) * max(sine, 0) / SUN_SHADOW_STEP_CASTER_METRES
}

// What the kept map does this frame (0348, decision 2), in order. Turn
// when it holds no drawing, the row changed or the sun turned past the
// limit. Recentre when the eye left its step, the trees started or
// stopped casting, or the frame table or the models changed. Compare when
// the meshes, the node selection or the tree cache changed, which only a
// fingerprint over its own box can tell from a change it does not see.
// Keep otherwise.
sun_shadow_kept_step :: proc(kept: Sun_Shadow_Kept, view: Sun_Shadow_View) -> Sun_Shadow_Kept_Step {
	key := kept.key
	if !kept.drawn || key.row != view.row || sun_shadow_turn_angle(key.toward_sun, view.toward_sun) > sun_shadow_turn_limit(view.toward_sun, view.up, key.cascade.texel_metres) {
		return .Turn
	}
	if !sun_shadow_eye_in_step(key.cascade, view.eye) || key.trees_drawn != view.trees_drawn {
		return .Recentre
	}
	if key.revisions.frames != view.revisions.frames || key.revisions.models != view.revisions.models {
		return .Recentre
	}
	if key.revisions.meshes != view.revisions.meshes || key.revisions.selection != view.revisions.selection || key.revisions.trees != view.revisions.trees {
		return .Compare
	}
	return .Keep
}

// The cascade a kept map is drawn on again, at the frame's row: anchored
// at the centre it holds (at the eye when it holds none), on the sun and
// the path's axis it holds for a Recentre, so the map moves by whole
// texels, and on the frame's for a Turn.
sun_shadow_kept_cascade :: proc(kept: Sun_Shadow_Kept, view: Sun_Shadow_View, step: Sun_Shadow_Kept_Step) -> Sun_Shadow_Cascade {
	anchor := kept.drawn ? kept.key.cascade.precise_centre : linalg.array_cast(view.eye, f64)
	if step == .Recentre {
		return sun_shadow_cascade(view.eye, kept.key.toward_sun, kept.key.path_axis, view.row, anchor)
	}
	return sun_shadow_cascade(view.eye, view.toward_sun, view.path_axis, view.row, anchor)
}

// The words mixed into one value: each xored into the running value and
// then mixed by splitmix64's finalizer, so the order of the words counts.
sun_shadow_fingerprint :: proc(words: ..u64) -> u64 {
	value: u64 = 0
	for word in words {
		value ~= word
		value ~= value >> 30
		value *= 0xBF58476D1CE4E5B9
		value ~= value >> 27
		value *= 0x94D049BB133111EB
		value ~= value >> 31
	}
	return value
}

// The frame's node selection hashed whole (Field_Node is four i32, no
// padding), its order included: a moved hash asks for the fingerprints.
// 0 for none (xxhash refuses an empty slice's nil data).
sun_shadow_selection_hash :: proc(selection: []Field_Node) -> u64 {
	if len(selection) == 0 {
		return 0
	}
	return xxhash.XXH3_64_default(slice.to_bytes(selection))
}

// The node's render, when it has a terrain mesh whose box casts in the
// cascade.
sun_shadow_node_casts :: proc(renderer: ^Field_Renderer, cascade: Sun_Shadow_Cascade, node: Field_Node) -> (render: Field_Node_Render, casts: bool) {
	found: bool
	render, found = renderer.meshes[node]
	if !found || !render.has_mesh {
		return {}, false
	}
	minimum, maximum := field_node_box_metres(render, node, renderer.spacing_millimetres)
	return render, sun_shadow_box_casts(cascade, minimum, maximum)
}

// A casting node's share of the terrain's fingerprint: the node and the
// hash of what its depth reads (Field_Node_Render.terrain_hash).
sun_shadow_node_term :: proc(node: Field_Node, render: Field_Node_Render) -> u64 {
	return sun_shadow_fingerprint(u64(u32(node.level)), u64(u32(node.coordinate.x)), u64(u32(node.coordinate.y)), u64(u32(node.coordinate.z)), render.terrain_hash)
}

// The terrain the cascade's casters draw, as a wrapping sum of the
// casting nodes' terms: the selection's order does not count, a node's
// mesh moved only in its water or its colours does not either.
sun_shadow_terrain_fingerprint :: proc(renderer: ^Field_Renderer, cascade: Sun_Shadow_Cascade, selection: []Field_Node) -> u64 {
	fingerprint: u64 = 0
	for node in selection {
		if render, casts := sun_shadow_node_casts(renderer, cascade, node); casts {
			fingerprint += sun_shadow_node_term(node, render)
		}
	}
	return fingerprint
}

// A box's half extent along a unit axis.
box_extent_along :: proc(axis, extent: [3]f32) -> f32 {
	return abs(axis.x) * extent.x + abs(axis.y) * extent.y + abs(axis.z) * extent.z
}

// Whether the box meets the casters' box: within the half size across
// the right and the up, and along the sun overlapping from the far side
// to the reach beyond the near plane.
sun_shadow_box_casts :: proc(cascade: Sun_Shadow_Cascade, minimum, maximum: [3]f32) -> bool {
	middle := (minimum + maximum) / 2 - cascade.centre
	extent := (maximum - minimum) / 2
	if abs(linalg.dot(middle, cascade.right)) - box_extent_along(cascade.right, extent) > cascade.half_size {
		return false
	}
	if abs(linalg.dot(middle, cascade.up)) - box_extent_along(cascade.up, extent) > cascade.half_size {
		return false
	}
	along := linalg.dot(middle, cascade.toward_sun)
	spread := box_extent_along(cascade.toward_sun, extent)
	return along + spread >= -cascade.half_size && along - spread <= cascade.half_size + cascade.reach_metres
}

sun_shadow_frame :: proc(cascade: Sun_Shadow_Cascade, strength_percent, texels: int, texture: u32) -> Sun_Shadow_Frame {
	return Sun_Shadow_Frame {
		view_projection = cascade.view_projection,
		strength = f32(strength_percent) / 100,
		shape = {f32(texels), cascade.texel_metres, cascade.radius_metres * (1 - SUN_SHADOW_FADE_SHARE), cascade.radius_metres},
		texture = texture,
	}
}

// The casting trees of a view (0346, Tree_View): where and for what the
// candidates were gathered (the cascade grown by the margin and the
// slack, the cascade's half size and reach, the extent, the margin, the
// span of shadow_gather_span_metres, the species count and the cache's
// revision they are current at), and the inputs of the last cut.
Shadow_Tree_Gather :: struct {
	built:         bool,
	grown:         Sun_Shadow_Cascade,
	half_size:     f32,
	reach_metres:  f32,
	extent_metres: f32,
	margin_metres: f32,
	span_metres:   f32,
	species_count: int,
	revision:      u64,
}

Shadow_Tree_Cut :: struct {
	cascade:       Sun_Shadow_Cascade,
	eye:           [3]f32,
	extent_metres: f32,
	limit:         int,
	gathers:       int,
}

// The cascade with its half size grown, so its casters' box reaches the
// growth further on every face, the sun's side too. The rest as is (only
// the box test reads it).
grown_sun_shadow_cascade :: proc(cascade: Sun_Shadow_Cascade, growth_metres: f32) -> Sun_Shadow_Cascade {
	grown := cascade
	grown.half_size += growth_metres
	return grown
}

// How far from the gather's centre a tree the casters' box takes can
// stand, plus its extent and the margin: the box's corner
// sqrt(2 (h + e √3)² + (h + r + e √3)²) for the half size h, the reach r
// and the extent e, then e √3 and the margin.
shadow_gather_span_metres :: proc(cascade: Sun_Shadow_Cascade, extent_metres, margin_metres: f32) -> f32 {
	spread := extent_metres * math.SQRT_THREE
	across := cascade.half_size + spread
	along := cascade.half_size + cascade.reach_metres + spread
	return math.sqrt(2 * across * across + along * along) + spread + margin_metres
}

// The gathered candidates still hold every tree the cascade's box takes:
// a box test's term moves by at most the centre's move plus the span
// times the largest move of the light's axes, which must stay within the
// margin the gather grew the box by.
shadow_gather_covers :: proc(gather: Shadow_Tree_Gather, cascade: Sun_Shadow_Cascade) -> bool {
	chord := max(linalg.length(cascade.right - gather.grown.right), linalg.length(cascade.up - gather.grown.up), linalg.length(cascade.toward_sun - gather.grown.toward_sun))
	return linalg.length(cascade.centre - gather.grown.centre) + gather.span_metres * chord <= gather.margin_metres
}

// The standing trees whose box (the base and the extent either way)
// casts in the grown cascade, from the tiles whose bases' box widened by
// the extent does.
gather_shadow_tree_candidates :: proc(pass: ^Tree_Pass, cache: ^Field_Tree_Cache, grown: Sun_Shadow_Cascade, extent_metres: f32, felled: map[Tree_Key]struct{}, species_count: int) {
	groups: [MAXIMUM_TREE_SPECIES][dynamic]Tree_Candidate
	for &list in groups {
		list = make([dynamic]Tree_Candidate, context.temp_allocator)
	}
	for _, tile in cache.tiles {
		if len(tile.instances) == 0 || !sun_shadow_box_casts(grown, tile.minimum - extent_metres, tile.maximum + extent_metres) {
			continue
		}
		for instance, index in tile.instances {
			base := tree_instance_base(instance)
			if !sun_shadow_box_casts(grown, base - extent_metres, base + extent_metres) || tile.keys[index] in felled {
				continue
			}
			append(&groups[tree_species_group(instance, species_count)], Tree_Candidate{instance, tile.keys[index]})
		}
	}
	group_tree_candidates(pass, &groups, species_count)
}

// The casting candidates must be gathered again: none yet, another half
// size, reach, extent, margin or species count, a cascade the gather no
// longer covers (shadow_gather_covers), or a change of the tiles since
// whose box widened by the extent casts in the grown cascade (or changes
// the ring no longer holds).
shadow_tree_candidates_stale :: proc(cache: ^Field_Tree_Cache, gather: Shadow_Tree_Gather, cascade: Sun_Shadow_Cascade, extent_metres, margin_metres: f32, species_count: int) -> bool {
	if !gather.built || gather.half_size != cascade.half_size || gather.reach_metres != cascade.reach_metres {
		return true
	}
	if gather.extent_metres != extent_metres || gather.margin_metres != margin_metres || gather.species_count != species_count {
		return true
	}
	if !shadow_gather_covers(gather, cascade) {
		return true
	}
	changes, complete := field_tree_changes_since(cache, gather.revision)
	if !complete {
		return true
	}
	for change in changes {
		if sun_shadow_box_casts(gather.grown, change.minimum - gather.extent_metres, change.maximum + gather.extent_metres) {
			return true
		}
	}
	return false
}

// The candidates whose box casts in the cascade, ranked by their base's
// squared distance from the eye. Past limit the nearest by distance and
// then key, none at limit 0. Every distance band: a tree drawn as a card
// casts its model.
cut_shadow_trees :: proc(pass: ^Tree_Pass, cascade: Sun_Shadow_Cascade, eye: [3]f32, extent_metres: f32, limit: int) {
	clear(&pass.ranked)
	if limit <= 0 {
		clear(&pass.next)
		return
	}
	for candidate, index in pass.candidates {
		base := tree_instance_base(candidate.instance)
		if !sun_shadow_box_casts(cascade, base - extent_metres, base + extent_metres) {
			continue
		}
		append(&pass.ranked, Tree_Ranked{squared_distance_metres(base, eye), candidate.key, u32(index)})
	}
	finish_tree_cut(pass, limit)
}

// The view's casting trees for the cascade, as update_near_trees: the
// candidates gathered again when stale, in the cascade grown by the
// margin (the cache's row) and the slack, else current at the cache's
// revision. The cut and its commit when its inputs changed.
update_shadow_trees :: proc(cache: ^Field_Tree_Cache, view: ^Tree_View, cascade: Sun_Shadow_Cascade, eye: [3]f32, extent_metres: f32, felled: map[Tree_Key]struct{}, limit, species_count: int) {
	pass := &view.shadow
	margin := tree_candidate_margin_metres(cache.config)
	if shadow_tree_candidates_stale(cache, view.shadow_gather, cascade, extent_metres, margin, species_count) {
		grown := grown_sun_shadow_cascade(cascade, margin + TREE_CANDIDATE_SLACK_METRES)
		gather_shadow_tree_candidates(pass, cache, grown, extent_metres, felled, species_count)
		view.shadow_gather = Shadow_Tree_Gather {
			built         = true,
			grown         = grown,
			half_size     = cascade.half_size,
			reach_metres  = cascade.reach_metres,
			extent_metres = extent_metres,
			margin_metres = margin,
			span_metres   = shadow_gather_span_metres(cascade, extent_metres, margin),
			species_count = species_count,
			revision      = cache.revision,
		}
	} else {
		view.shadow_gather.revision = cache.revision
	}
	cut := Shadow_Tree_Cut{cascade, eye, extent_metres, limit, pass.gathers}
	if cut != view.shadow_cut {
		cut_shadow_trees(pass, cascade, eye, extent_metres, limit)
		view.shadow_cut = cut
		commit_tree_selection(pass)
	}
}

// What the cast pass hands draw_entities (Model_Frame.casters): the
// cascade and the transform the entities draw under (the pod's during
// the descent, else the identity), the machines and which of them the
// pass draws (0348, zero for every one).
Sun_Shadow_Casters :: struct {
	cascade:   Sun_Shadow_Cascade,
	transform: matrix[4, 4]f32,
	machines:  Machine_Registry,
	part:      Sun_Shadow_Part,
}

// Whether an entity's depth can change while nothing occupies or vacates
// a cell (0348): an inserter (its arm and held item), a drill (its pump or
// bar), a launch pad (its rocket), a hatch (its door) and a machine whose
// motion moves a part. None and Glow leave the part where it is.
sun_shadow_entity_moves :: proc(kind: Entity_Kind, machine: Machine) -> bool {
	#partial switch kind {
	case .Inserter, .Drill, .Launch_Pad:
		return true
	}
	if machine.kind == .Hatch {
		return true
	}
	return machine.motion.kind != .None && machine.motion.kind != .Glow
}

// The box in the world's metres round an entity's cells (origin and
// size, in its frame's cells) up to top_cells above its bottom, widened
// by SUN_SHADOW_ENTITY_MARGIN_CELLS each way, under the transform from
// its frame's cells.
sun_shadow_entity_box :: proc(transform: matrix[4, 4]f32, origin, size: [3]i32, top_cells: f32) -> (minimum, maximum: [3]f32) {
	low := [3]f32{f32(origin.x), f32(origin.y), f32(origin.z)} - SUN_SHADOW_ENTITY_MARGIN_CELLS
	high := [3]f32{f32(origin.x + size.x), f32(origin.y) + max(f32(size.y), top_cells), f32(origin.z + size.z)} + SUN_SHADOW_ENTITY_MARGIN_CELLS
	middle, extent := (low + high) / 2, (high - low) / 2
	centre := (transform * [4]f32{middle.x, middle.y, middle.z, 1}).xyz
	reach: [3]f32
	for row in 0 ..< 3 {
		reach[row] = abs(transform[row, 0]) * extent.x + abs(transform[row, 1]) * extent.y + abs(transform[row, 2]) * extent.z
	}
	return centre - reach, centre + reach
}

// Whether draw_entities draws the entity: always, but in the cast pass
// only when it is of the pass's part (sun_shadow_entity_moves, 0348) and
// its box (sun_shadow_entity_box, up to its model's top) casts.
model_frame_draws_entity :: proc(frame: Model_Frame, entities: ^Entities, models: Model_Renderer, common: Entity_Common) -> bool {
	if frame.casters == nil {
		return true
	}
	if frame.casters.part != .All {
		moves := sun_shadow_entity_moves(common.handle.kind, frame.casters.machines.machines[common.machine])
		if moves != (frame.casters.part == .Moving) {
			return false
		}
	}
	transform := frame.casters.transform * model_frame_entity_matrix(frame, entities, common.frame)
	minimum, maximum := sun_shadow_entity_box(transform, cast([3]i32)common.origin, common.size, machine_model_top(models, common))
	return sun_shadow_box_casts(frame.casters.cascade, minimum, maximum)
}

// The materials that read the map: the field's, the lit model layer's and
// the tree shader's (a material without maps, the trees' without their
// shader, is skipped by set_sun_shadow_map_slot).
sun_shadow_receivers :: proc(field: ^Field_Renderer, models: Model_Renderer) -> [3]rl.Material {
	return {field.material, models.material, models.trees.material}
}

// The map's slot of each material with maps; {} clears it.
set_sun_shadow_map_slot :: proc(materials: []rl.Material, texture: rl.Texture2D) {
	for material in materials {
		if material.maps != nil {
			material.maps[SUN_SHADOW_MAP_SLOT].texture = texture
		}
	}
}

// A failed load: one line, the state Failed at the size, so the same
// setting does not retry it.
fail_sun_shadow_map :: proc(shadows: ^Sun_Shadow_Renderer, texels: int, what: string) -> bool {
	platform.log_printf("error: the sun's shadow map did not load (%s), the field draws without shadows", what)
	shadows^ = {state = .Failed, texels = texels}
	return false
}

// A framebuffer with a depth texture of texels a side attached, as
// rlLoadTextureDepth makes it (the shared map and the kept maps share its
// format, which a depth copy needs). On a failure what it made is freed
// and the problem named.
load_sun_shadow_target :: proc(texels: int) -> (framebuffer, depth_texture: u32, problem: string) {
	framebuffer = rlgl.LoadFramebuffer()
	if framebuffer == 0 {
		return 0, 0, "no framebuffer"
	}
	depth_texture = rlgl.LoadTextureDepth(i32(texels), i32(texels), false)
	if depth_texture == 0 {
		rlgl.UnloadFramebuffer(framebuffer)
		return 0, 0, "no depth texture"
	}
	rlgl.FramebufferAttach(framebuffer, depth_texture, i32(rlgl.FramebufferAttachType.DEPTH), i32(rlgl.FramebufferAttachTextureType.TEXTURE2D), 0)
	if !rlgl.FramebufferComplete(framebuffer) {
		// The framebuffer deletes its attached texture; the second delete
		// covers an attach that did not take and is ignored otherwise.
		rlgl.UnloadFramebuffer(framebuffer)
		rlgl.UnloadTexture(depth_texture)
		return 0, 0, "an incomplete framebuffer"
	}
	return framebuffer, depth_texture, ""
}

// From the pass when Unloaded: the depth shaders into a default
// material, the framebuffer and its depth texture of texels a side;
// everything made so far freed on a failure (fail_sun_shadow_map). Ready
// puts the depth texture into the receivers' slot.
load_sun_shadow_map :: proc(shadows: ^Sun_Shadow_Renderer, data_directory: string, texels: int, receivers: []rl.Material) -> bool {
	shader, ok := load_shader_pair(data_directory, SUN_SHADOW_VERTEX_SHADER_PATH, SUN_SHADOW_FRAGMENT_SHADER_PATH, "sun shadow")
	if !ok {
		return fail_sun_shadow_map(shadows, texels, "its shaders")
	}
	framebuffer, depth, problem := load_sun_shadow_target(texels)
	if problem != "" {
		rl.UnloadShader(shader)
		return fail_sun_shadow_map(shadows, texels, problem)
	}
	material := rl.LoadMaterialDefault()
	material.shader = shader
	shadows^ = Sun_Shadow_Renderer {
		state              = .Ready,
		framebuffer        = framebuffer,
		depth_texture      = depth,
		texels             = texels,
		material           = material,
		instanced_location = rl.GetShaderLocation(shader, "instanced_on"),
	}
	set_sun_shadow_instanced(shadows^, false)
	side := i32(texels)
	set_sun_shadow_map_slot(receivers, rl.Texture2D{id = depth, width = side, height = side, mipmaps = 1, format = .UNCOMPRESSED_GRAYSCALE})
	return true
}

// The depth shader reads each vertex through instanceTransform (the
// trees, draw_tree_pass; the machines, draw_cast_model_instances; the
// foundations' slabs, draw_field_foundations, 0347) or not.
set_sun_shadow_instanced :: proc(shadows: Sun_Shadow_Renderer, instanced: bool) {
	value: f32 = instanced ? 1 : 0
	rl.SetShaderValue(shadows.material.shader, shadows.instanced_location, &value, .FLOAT)
}

// From the pass when a viewport's kept map is Unloaded: its target at the
// shared map's size, Ready. A failure logs one line and leaves it Failed,
// so its viewport draws the whole pass every frame until it is released.
load_sun_shadow_kept :: proc(kept: ^Sun_Shadow_Kept, texels: int) -> bool {
	framebuffer, depth, problem := load_sun_shadow_target(texels)
	if problem != "" {
		platform.log_printf("error: a viewport's kept sun shadow map did not load (%s), its shadow is drawn whole every frame", problem)
		kept^ = {state = .Failed}
		return false
	}
	kept^ = {state = .Ready, framebuffer = framebuffer, depth_texture = depth}
	return true
}

// Between frames: the kept map's framebuffer (raylib 6.2 deletes its depth
// texture with it) when it holds one, then nothing kept.
release_sun_shadow_kept :: proc(kept: ^Sun_Shadow_Kept) {
	if kept.state == .Ready {
		rlgl.UnloadFramebuffer(kept.framebuffer)
	}
	kept^ = {}
}

// Between frames: every kept map, the receivers' slot cleared, then the
// framebuffer (raylib 6.2 deletes its depth texture with it) and the depth
// material. A Failed map freed what it made and only returns to Unloaded.
release_sun_shadow_map :: proc(shadows: ^Sun_Shadow_Renderer, receivers: []rl.Material) {
	for &kept in shadows.kept {
		release_sun_shadow_kept(&kept)
	}
	if shadows.state == .Ready {
		set_sun_shadow_map_slot(receivers, {})
		rlgl.UnloadFramebuffer(shadows.framebuffer)
		rl.UnloadMaterial(shadows.material)
	}
	shadows^ = {}
}

// A map is stale when the setting turned off or the row's size changed;
// a Failed one is not retried while the setting stays on at its size.
sun_shadow_map_stale :: proc(shadows: Sun_Shadow_Renderer, on: bool, texels: int) -> bool {
	return shadows.state != .Unloaded && (!on || shadows.texels != texels)
}

// Between frames (prepare_field_frame): a stale map released with every
// kept map, so the next pass that wants one makes it at the row's size;
// else the kept maps of the viewports removed (from viewport_count up).
serve_sun_shadows :: proc(shadows: ^Sun_Shadow_Renderer, receivers: []rl.Material, on: bool, texels, viewport_count: int) {
	if sun_shadow_map_stale(shadows^, on, texels) {
		release_sun_shadow_map(shadows, receivers)
		return
	}
	for slot in max(viewport_count, 0) ..< SUN_SHADOW_KEPT_MAPS {
		release_sun_shadow_kept(&shadows.kept[slot])
	}
}

// The viewport's kept map to draw on, or nil for the whole pass: a slot
// outside the kept maps (the planet preview), a frame whose casters move
// (the pod's descent, which also forgets what the map holds), a map that
// does not load. An Unloaded one is loaded at the shared map's size.
usable_sun_shadow_kept :: proc(shadows: ^Sun_Shadow_Renderer, slot: int, moving_frame: bool) -> ^Sun_Shadow_Kept {
	if slot < 0 || slot >= SUN_SHADOW_KEPT_MAPS {
		return nil
	}
	kept := &shadows.kept[slot]
	if moving_frame {
		kept.drawn = false
		return nil
	}
	if kept.state == .Unloaded {
		load_sun_shadow_kept(kept, shadows.texels)
	}
	return kept.state == .Ready ? kept : nil
}

// A receiving shader's map sampler where DrawMesh and
// begin_instanced_material bind the slot's texture (unit 2), and its
// three uniforms.
use_sun_shadow_sampler :: proc(shader: rl.Shader) -> (locations: [Sun_Shadow_Uniform]i32) {
	if shader.locs != nil {
		shader.locs[SUN_SHADOW_SAMPLER_LOCATION] = rl.GetShaderLocation(shader, "sun_shadow_map")
	}
	names := SUN_SHADOW_UNIFORM_NAMES
	for name, uniform in names {
		locations[uniform] = rl.GetShaderLocation(shader, name)
	}
	return locations
}

set_sun_shadow_uniforms :: proc(shader: rl.Shader, locations: [Sun_Shadow_Uniform]i32, frame: Sun_Shadow_Frame) {
	frame := frame
	rl.SetShaderValueMatrix(shader, locations[.Matrix], cast(rl.Matrix)frame.view_projection)
	rl.SetShaderValue(shader, locations[.Strength], &frame.strength, .FLOAT)
	rl.SetShaderValue(shader, locations[.Shape], &frame.shape, .VEC4)
}

// For the draws that enable their shader by hand (the cards, the cover):
// the map on unit 2 and the sampler set to it; nothing at texture 0.
bind_sun_shadow_texture :: proc(shader: rl.Shader, texture: u32) {
	if texture == 0 {
		return
	}
	slot := i32(SUN_SHADOW_MAP_SLOT)
	rl.SetShaderValue(shader, shader.locs[SUN_SHADOW_SAMPLER_LOCATION], &slot, .INT)
	rlgl.ActiveTextureSlot(slot)
	rlgl.EnableTexture(texture)
	rlgl.ActiveTextureSlot(0)
}

unbind_sun_shadow_texture :: proc(texture: u32) {
	if texture == 0 {
		return
	}
	rlgl.ActiveTextureSlot(i32(SUN_SHADOW_MAP_SLOT))
	rlgl.DisableTexture()
	rlgl.ActiveTextureSlot(0)
}

// A map (the shared one or a kept one) bound as the target with the
// cascade's matrices: the depth mask on, its depth cleared when asked (not
// over a kept map's copy), depth test on, both faces drawn.
begin_sun_shadow_target :: proc(framebuffer, depth_texture: u32, texels: int, cascade: Sun_Shadow_Cascade, clear: bool) {
	side := i32(texels)
	rl.BeginTextureMode(rl.RenderTexture2D{id = framebuffer, texture = {width = side, height = side}, depth = {id = depth_texture}})
	rlgl.EnableDepthMask()
	if clear {
		rlgl.ClearScreenBuffers()
	}
	rlgl.SetMatrixProjection(cast(rl.Matrix)cascade.projection)
	rlgl.SetMatrixModelview(cast(rl.Matrix)cascade.view)
	rlgl.EnableDepthTest()
	rlgl.DisableBackfaceCulling()
}

// The batch flushed under the cascade's matrices, culling back on, the
// depth test off and the window (or nothing) bound again.
end_sun_shadow_map :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
	rlgl.DisableDepthTest()
	rl.EndTextureMode()
}

// The kept map's depth copied into the shared map (0348): one depth blit,
// nearest, between two framebuffers whose textures one
// rlLoadTextureDepth call made at one size (GL 3.0 and GLES 3.0 core),
// the batch flushed, the scissor test off and the depth mask on first;
// nothing bound after.
copy_sun_shadow_depth :: proc(source, destination: u32, texels: int) {
	side := i32(texels)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableScissorTest()
	rlgl.EnableDepthMask()
	rl.rlBindFramebuffer(rl.RL_READ_FRAMEBUFFER, source)
	rl.rlBindFramebuffer(rl.RL_DRAW_FRAMEBUFFER, destination)
	rlgl.BlitFramebuffer(0, 0, side, side, 0, 0, side, side, SUN_SHADOW_DEPTH_BUFFER_BIT)
	rlgl.DisableFramebuffer()
}
