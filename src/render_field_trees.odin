package game

import "core:math"
import "core:slice"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "render_frustum"

// The trees' draw (work item 0197, doc/presentation.md, The field
// session). The standing trees round the eyes are generated region by
// region into a cache (update_field_tree_cache, before any viewport
// draws: a region is FIELD_TREE_REGION_CELLS tree cubes an edge, a few
// generated a frame nearest first, evicted once no eye is near) and drawn
// per tree with its species' model (a machine record of kind tree), its
// yaw, scale and shade, the species' tint, and the light of the open sky.
// Within FIELD_TREE_DRAW_METRES of the camera, at most
// FIELD_TREE_DRAW_LIMIT per viewport nearest first, each grown in from
// nothing over the last FIELD_TREE_GROW_IN_METRES so none pops in. A
// felled tree is not drawn. Floats are made here only.

// A region is this many tree cubes an edge (32 m at the shipped 4 m).
FIELD_TREE_REGION_CELLS :: 8
FIELD_TREE_REGIONS_PER_FRAME :: 3
FIELD_TREE_DRAW_METRES :: 128
FIELD_TREE_GROW_IN_METRES :: 16
FIELD_TREE_DRAW_LIMIT :: 256

// A region of FIELD_TREE_REGION_CELLS tree cubes an edge.
Field_Tree_Region :: [3]i32

// The standing and the felled trees of each region the eyes are near,
// felled ones dropped at the draw.
Field_Tree_Cache :: struct {
	regions: map[Field_Tree_Region][dynamic]Planet_Tree,
}

Visible_Tree :: struct {
	tree:             Planet_Tree,
	distance_squared: f32,
}

destroy_field_tree_cache :: proc(cache: ^Field_Tree_Cache) {
	for _, trees in cache.regions {
		delete(trees)
	}
	delete(cache.regions)
	cache^ = {}
}

field_tree_region_edge :: proc(generation: ^Planet_Generation) -> i64 {
	return generation.trees.spacing * FIELD_TREE_REGION_CELLS
}

// The region's box in position units.
field_tree_region_box :: proc(region: Field_Tree_Region, edge: i64) -> (minimum, maximum: [3]i64) {
	minimum = [3]i64{i64(region.x), i64(region.y), i64(region.z)} * edge
	return minimum, minimum + edge - 1
}

// The eyes projected onto the sphere of the radius (temp allocator).
field_tree_eye_points :: proc(generation: ^Planet_Generation, eyes: []World_Position) -> [][3]i64 {
	points := make([][3]i64, len(eyes), context.temp_allocator)
	for eye, index in eyes {
		points[index] = project_onto_sphere(eye, vector_length(cast([3]i64)eye), generation.radius)
	}
	return points
}

// The nearest eye point's squared distance to the region's box.
field_tree_region_distance :: proc(region: Field_Tree_Region, edge: i64, points: [][3]i64) -> i64 {
	minimum, maximum := field_tree_region_box(region, edge)
	nearest := i64(max(i64))
	for point in points {
		nearest = min(nearest, box_distance_squared(Field_Box{World_Position(minimum), World_Position(maximum)}, World_Position(point)))
	}
	return nearest
}

// The regions straddling the sphere within the distance plus one region
// of any eye's point on the sphere, nearest first, then in key order
// (temp allocator); none without trees.
field_tree_regions_around :: proc(generation: ^Planet_Generation, eyes: []World_Position, distance_metres: int) -> []Field_Tree_Region {
	if generation.trees.spacing == 0 || len(eyes) == 0 {
		return nil
	}
	edge := field_tree_region_edge(generation)
	reach := metres_to_position_units(i64(distance_metres)) + edge
	points := field_tree_eye_points(generation, eyes)
	seen := make(map[Field_Tree_Region]struct{}, context.temp_allocator)
	regions := make([dynamic]Field_Tree_Region, context.temp_allocator)
	for point in points {
		first, last := (point - reach) / edge - 1, (point + reach) / edge + 1
		for x in first.x ..= last.x {
			for y in first.y ..= last.y {
				for z in first.z ..= last.z {
					region := Field_Tree_Region{i32(x), i32(y), i32(z)}
					minimum, maximum := field_tree_region_box(region, edge)
					if region in seen || box_distance_squared(Field_Box{World_Position(minimum), World_Position(maximum)}, World_Position(point)) > reach * reach || !cube_straddles_sphere(minimum, maximum + 1, generation.radius) {
						continue
					}
					seen[region] = {}
					append(&regions, region)
				}
			}
		}
	}
	Ordered_Region :: struct {
		region:   Field_Tree_Region,
		distance: i64,
	}
	ordered := make([]Ordered_Region, len(regions), context.temp_allocator)
	for region, index in regions {
		ordered[index] = {region, field_tree_region_distance(region, edge, points)}
	}
	slice.sort_by(ordered, proc(first, second: Ordered_Region) -> bool {
		if first.distance != second.distance {
			return first.distance < second.distance
		}
		return tree_key_before(first.region, second.region)
	})
	for entry, index in ordered {
		regions[index] = entry.region
	}
	return regions[:]
}

// Evicts the regions no eye is near, then generates up to
// FIELD_TREE_REGIONS_PER_FRAME missing ones nearest first. Runs before
// any viewport draws (prepare_field_frame, the preview's stream step), so
// no draw reads a region it frees.
update_field_tree_cache :: proc(cache: ^Field_Tree_Cache, generation: ^Planet_Generation, eyes: []World_Position) {
	wanted := field_tree_regions_around(generation, eyes, FIELD_TREE_DRAW_METRES)
	wanted_set := make(map[Field_Tree_Region]struct{}, len(wanted), context.temp_allocator)
	for region in wanted {
		wanted_set[region] = {}
	}
	evicted := make([dynamic]Field_Tree_Region, context.temp_allocator)
	for region in cache.regions {
		if region not_in wanted_set {
			append(&evicted, region)
		}
	}
	for region in evicted {
		delete(cache.regions[region])
		delete_key(&cache.regions, region)
	}
	edge := field_tree_region_edge(generation)
	generated := 0
	for region in wanted {
		if generated >= FIELD_TREE_REGIONS_PER_FRAME {
			break
		}
		if region in cache.regions {
			continue
		}
		minimum, maximum := field_tree_region_box(region, edge)
		cache.regions[region] = planet_trees_in_box(generation, minimum, maximum, context.allocator)
		generated += 1
	}
}

// Every region the eyes need is cached.
field_tree_cache_settled :: proc(cache: ^Field_Tree_Cache, generation: ^Planet_Generation, eyes: []World_Position) -> bool {
	for region in field_tree_regions_around(generation, eyes, FIELD_TREE_DRAW_METRES) {
		if region not_in cache.regions {
			return false
		}
	}
	return true
}

// 1 out to the grow in's start, falling to 0 at the draw distance.
tree_grow_factor :: proc(distance_metres: f32) -> f32 {
	start := f32(FIELD_TREE_DRAW_METRES - FIELD_TREE_GROW_IN_METRES)
	return math.clamp((FIELD_TREE_DRAW_METRES - distance_metres) / (FIELD_TREE_DRAW_METRES - start), 0, 1)
}

// The model's cells (origin at its footprint's bottom centre) to metres:
// the tree's axes as columns, scaled by the pitch, its scale and the grow
// in, the base as the translation (as frame_render_matrix).
tree_render_matrix :: proc(tree: Planet_Tree, pitch_millimetres: int, grow: f32) -> matrix[4, 4]f32 {
	axes := tree_axes(tree.up, tree.yaw)
	scale := f32(pitch_millimetres) / MILLIMETRES_PER_METRE * f32(tree.scale_percent) / 100 * grow
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

// The standing trees within the draw distance whose box (the base and
// extent_metres either way) is in the frustum; past the limit the
// nearest (temp allocator).
field_visible_trees :: proc(cache: ^Field_Tree_Cache, felled: map[Tree_Key]struct{}, camera_metres: [3]f32, frustum: render_frustum.Frustum, extent_metres: f32) -> []Visible_Tree {
	visible := make([dynamic]Visible_Tree, context.temp_allocator)
	limit := f32(FIELD_TREE_DRAW_METRES * FIELD_TREE_DRAW_METRES)
	for _, trees in cache.regions {
		for tree in trees {
			base := world_position_to_metres(tree.base)
			offset := base - camera_metres
			squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
			if squared > limit || tree.key in felled || !render_frustum.frustum_contains_box(frustum, base - extent_metres, base + extent_metres) {
				continue
			}
			append(&visible, Visible_Tree{tree, squared})
		}
	}
	if len(visible) <= FIELD_TREE_DRAW_LIMIT {
		return visible[:]
	}
	slice.sort_by(visible[:], proc(first, second: Visible_Tree) -> bool {
		return first.distance_squared < second.distance_squared
	})
	return visible[:FIELD_TREE_DRAW_LIMIT]
}

// The widest reach of a species' model from its base in metres at the
// pitch and the largest scale: its top or its half footprint diagonal.
field_tree_model_extent :: proc(scene: Field_Scene) -> f32 {
	extent: f32 = 0
	for species in scene.content.field.tree_species {
		model, found := machine_model(scene.models, species.machine)
		if !found {
			continue
		}
		footprint := scene.content.machines.machines[species.machine].footprint
		diagonal := math.sqrt(f32(footprint.x * footprint.x + footprint.z * footprint.z)) / 2
		extent = max(extent, model.top, diagonal)
	}
	return extent * f32(scene.content.field.foundation_pitch_millimetres) / MILLIMETRES_PER_METRE * PLANET_TREE_MAXIMUM_SCALE_PERCENT / 100
}

// Inside BeginMode3D with the field camera, after the machines: each
// visible tree's species' model lit by the open sky, times the species'
// tint and the tree's shade. A species whose model did not load is not
// drawn.
draw_field_trees :: proc(scene: Field_Scene, camera: rl.Camera3D) {
	view_projection := rlgl.GetMatrixProjection() * rl.GetCameraMatrix(camera)
	frustum := render_frustum.frustum_from_matrix(cast(matrix[4, 4]f32)view_projection)
	sky := model_light_tint(with_light_level(0, .Sky, MAXIMUM_LIGHT), scene.frame.day_factor, scene.frame.sky_tint)
	pitch := scene.content.field.foundation_pitch_millimetres
	for visible in field_visible_trees(&scene.renderer.trees, scene.state.field.felled_trees, camera.position, frustum, field_tree_model_extent(scene)) {
		species, found := field_tree_species(scene.content.field, visible.tree)
		if !found {
			continue
		}
		model, model_found := machine_model(scene.models, species.machine)
		if !model_found {
			continue
		}
		tint := [3]f32{f32(species.tint.r), f32(species.tint.g), f32(species.tint.b)} / 255
		light := sky * tint * f32(visible.tree.shade_percent) / 100
		grow := tree_grow_factor(math.sqrt(visible.distance_squared))
		draw_model_layers(scene.models, model.body, tree_render_matrix(visible.tree, pitch, grow), light, {})
	}
}
