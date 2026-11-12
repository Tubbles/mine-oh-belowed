package game

import "core:math"
import "core:slice"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "render_frustum"

// The machines' draws culled and instanced (work item 0347,
// doc/presentation.md, Machine models). Each model draw poses its pieces
// (pose_machine_model, pose_arm) and tests the posed box, the union of the
// drawn pieces' mesh bounds (Model_Bounds, kept per mesh at upload) under
// their transforms, against the pass's cull (model_frame_shows_box): the
// casters' box in the sun's pass, the frustum and the haze's end in the
// scene's (Model_View). Exact after posing, so a sliding door or a
// reaching arm never pops at the screen's edge. A shown model appends one
// Model_Instance a piece to the pass's list (Model_Frame.instances), or
// draws as before (emit_posed_model); after draw_entities the list is
// grouped by mesh and layer and drawn instanced from one persistent buffer
// a viewport and pass (Field_Instance_Buffers). An instance carries its
// layer's colour in its matrix's bottom row, as a tree's does: the model
// shader takes the transform with instanced_on and the colour with
// instance_tint_on, and draws the emissive layer, the slabs and the belt
// items unlit with flat_on, as raylib's default shader on its white
// texture does, hazed on the open sky (0360); rlgl's batch takes the same
// flat mode between begin_flat_batch and end_flat_batch (the runs, the
// poles, the torch boxes and the scene's box draws). The pod
// (model_frame_takes_instances), the ghosts and the workbench keep
// DrawMesh; a model shader without the three uniforms leaves every model
// drawn directly (Model_Renderer.instancing_ready). A
// pass reads the frames' matrices from one table sorted by id
// (frame_matrix_table) in place of a scan of the frames per entity.

// The body and an iris's every blade.
MAXIMUM_POSED_PIECES :: 1 + MAXIMUM_IRIS_BLADES

// A machine's meshes: the body, the moving part and the arm's parts in
// Arm_Part's order.
Model_Mesh_Slot :: enum u8 {
	Body,
	Part,
	Arm_Base,
	Arm_Turret,
	Arm_Upper_Arm,
	Arm_Forearm,
	Arm_Gripper,
	Arm_Finger,
}

#assert(int(Model_Mesh_Slot.Arm_Finger) - int(Model_Mesh_Slot.Arm_Base) == int(Arm_Part.Finger), "the arm's slots follow Arm_Part")

Model_Piece :: struct {
	machine: Machine_Id,
	slot:    Model_Mesh_Slot,
}

// A mesh's box in its own units, inverted (minimum above maximum) when it
// is empty.
Model_Bounds :: struct {
	minimum, maximum: [3]f32,
}

Model_Piece_Pose :: struct {
	slot:      Model_Mesh_Slot,
	transform: matrix[4, 4]f32,
}

// A model's pieces as drawn this frame and their box, inverted while
// empty.
Posed_Model :: struct {
	pieces:           [MAXIMUM_POSED_PIECES]Model_Piece_Pose,
	count:            int,
	minimum, maximum: [3]f32,
}

// One piece of a shown model in a pass's list, both layers' colours.
Model_Instance :: struct {
	piece:     Model_Piece,
	transform: matrix[4, 4]f32,
	colors:    [Model_Layer]rl.Color,
}

// A run of one mesh's instances in the packed matrices.
Model_Instance_Group :: struct {
	mesh:         rl.Mesh,
	first, count: int,
}

// The scene's cull: the camera's frustum, the eye and the haze's end (0
// or less for the frustum alone), and the transform the boxes take into
// the world (the pod's during the descent, else the identity).
Model_View :: struct {
	frustum:         render_frustum.Frustum,
	eye:             [3]f32,
	distance_metres: f32,
	transform:       matrix[4, 4]f32,
}

// A frame's record and its frame_render_matrix.
Frame_Matrix_Entry :: struct {
	frame:     Frame,
	transform: matrix[4, 4]f32,
}

// Every frame's entry sorted by id, made once a pass.
Frame_Matrix_Table :: struct {
	entries: []Frame_Matrix_Entry,
}

// A persistent instance buffer and its capacity in instances
// (upload_instances_in_place).
Instance_Buffer :: struct {
	buffer:   u32,
	capacity: int,
}

// A viewport's buffers, each written at most once a frame: the sun's
// machines (the whole pass, or the moving casters over a kept map), the
// still casters drawn into its kept map (0348), the scene's machines and
// the belt items.
Field_Instance_Buffers :: struct {
	cast_models, kept_cast_models, models, items: Instance_Buffer,
}

// Pure.

empty_model_bounds :: proc() -> Model_Bounds {
	return {minimum = math.F32_MAX, maximum = -math.F32_MAX}
}

empty_posed_model :: proc() -> Posed_Model {
	return {minimum = math.F32_MAX, maximum = -math.F32_MAX}
}

// Every frame's record with its frame_render_matrix, sorted by id.
frame_matrix_table :: proc(frames: ^Frame_Table, allocator := context.temp_allocator) -> Frame_Matrix_Table {
	entries := make([]Frame_Matrix_Entry, len(frames.frames), allocator)
	for frame, index in frames.frames {
		entries[index] = {frame = frame, transform = frame_render_matrix(frame)}
	}
	slice.sort_by(entries, proc(first, second: Frame_Matrix_Entry) -> bool {
		return first.frame.id < second.frame.id
	})
	return {entries = entries}
}

// The block frame gives its record and the identity, found, as
// entity_frame_matrix and inserter_arm_placement read it; a missing id the
// zero frame and the identity, not found.
find_frame_matrix :: proc(table: Frame_Matrix_Table, id: Frame_Id) -> (entry: Frame_Matrix_Entry, found: bool) {
	if id == BLOCK_FRAME {
		return {frame = block_frame(), transform = 1}, true
	}
	index, hit := slice.binary_search_by(table.entries, id, proc(entry: Frame_Matrix_Entry, key: Frame_Id) -> slice.Ordering {
		return slice.cmp(entry.frame.id, key)
	})
	if !hit {
		return {transform = 1}, false
	}
	return table.entries[index], true
}

// The frame's matrix as the pass's table gives it, or entity_frame_matrix
// without a table.
model_frame_entity_matrix :: proc(frame: Model_Frame, entities: ^Entities, id: Frame_Id) -> matrix[4, 4]f32 {
	if frame.frames != nil {
		entry, _ := find_frame_matrix(frame.frames^, id)
		return entry.transform
	}
	return entity_frame_matrix(entities, id)
}

// The box round the box under the transform: its centre transformed, its
// half extent through the absolute matrix.
transformed_box :: proc(transform: matrix[4, 4]f32, minimum, maximum: [3]f32) -> (box_minimum, box_maximum: [3]f32) {
	middle, extent := (minimum + maximum) / 2, (maximum - minimum) / 2
	centre := (transform * [4]f32{middle.x, middle.y, middle.z, 1}).xyz
	reach: [3]f32
	for row in 0 ..< 3 {
		reach[row] = abs(transform[row, 0]) * extent.x + abs(transform[row, 1]) * extent.y + abs(transform[row, 2]) * extent.z
	}
	return centre - reach, centre + reach
}

// True without a view; else the box under the view's transform lies
// within its distance of the eye (none at 0 or less) and in its frustum.
model_view_shows :: proc(view: ^Model_View, minimum, maximum: [3]f32) -> bool {
	if view == nil {
		return true
	}
	low, high := transformed_box(view.transform, minimum, maximum)
	if view.distance_metres > 0 && box_distance_metres(low, high, view.eye) > view.distance_metres {
		return false
	}
	return render_frustum.frustum_contains_box(view.frustum, low, high)
}

// Whether the pass draws what lies in the box (in the world before the
// pod's transform): in the sun's pass the box under the casters'
// transform casts, in the scene's the view shows it.
model_frame_shows_box :: proc(frame: Model_Frame, minimum, maximum: [3]f32) -> bool {
	if frame.casters != nil {
		low, high := transformed_box(frame.casters.transform, minimum, maximum)
		if !sun_shadow_box_casts(frame.casters.cascade, low, high) {
			return false
		}
	}
	return model_view_shows(frame.view, minimum, maximum)
}

// The box in a frame's cells under the frame's matrix, as
// model_frame_shows_box takes it.
model_frame_shows_cells :: proc(frame: Model_Frame, transform: matrix[4, 4]f32, minimum, maximum: [3]f32) -> bool {
	low, high := transformed_box(transform, minimum, maximum)
	return model_frame_shows_box(frame, low, high)
}

// The pass collects instances, and the machine is not the pod, which
// draws alone.
model_frame_takes_instances :: proc(frame: Model_Frame, kind: Machine_Kind) -> bool {
	return frame.instances != nil && kind != .Pod
}

// The scene's pass collecting instances, where no model of draw_entities'
// pools draws by DrawMesh but the pod, so their batch draws may go
// through the model shader's flat batch (0360, begin_flat_batch).
model_frame_flat_batch :: proc(frame: Model_Frame) -> bool {
	return frame.view != nil && frame.instances != nil
}

model_slot_bounds :: proc(layers: Model_Layers) -> Model_Bounds {
	bounds := empty_model_bounds()
	for mesh in layers {
		for position in mesh.positions {
			for axis in 0 ..< 3 {
				bounds.minimum[axis] = min(bounds.minimum[axis], position[axis])
				bounds.maximum[axis] = max(bounds.maximum[axis], position[axis])
			}
		}
	}
	return bounds
}

// Every slot's bounds of a machine's meshes.
machine_model_bounds :: proc(mesh: Machine_Model_Mesh) -> (bounds: [Model_Mesh_Slot]Model_Bounds) {
	bounds[.Body] = model_slot_bounds(mesh.body)
	bounds[.Part] = model_slot_bounds(mesh.part)
	for layers, part in mesh.arm {
		bounds[arm_part_slot(part)] = model_slot_bounds(layers)
	}
	return bounds
}

arm_part_slot :: proc(part: Arm_Part) -> Model_Mesh_Slot {
	return Model_Mesh_Slot(int(Model_Mesh_Slot.Arm_Base) + int(part))
}

// The piece's uploaded layers, none for a machine past the models.
model_piece_layers :: proc(renderer: Model_Renderer, piece: Model_Piece) -> Uploaded_Layers {
	if int(piece.machine) >= len(renderer.models) {
		return {}
	}
	model := &renderer.models[piece.machine]
	switch piece.slot {
	case .Body:
		return model.body
	case .Part:
		return model.part
	case .Arm_Base, .Arm_Turret, .Arm_Upper_Arm, .Arm_Forearm, .Arm_Gripper, .Arm_Finger:
		return model.arm[Arm_Part(int(piece.slot) - int(Model_Mesh_Slot.Arm_Base))]
	}
	return {}
}

// The piece's mesh bounds, inverted for a machine past the models.
model_piece_bounds :: proc(renderer: Model_Renderer, piece: Model_Piece) -> Model_Bounds {
	if int(piece.machine) >= len(renderer.models) {
		return empty_model_bounds()
	}
	return renderer.models[piece.machine].bounds[piece.slot]
}

grow_posed_box :: proc(posed: ^Posed_Model, minimum, maximum: [3]f32) {
	for axis in 0 ..< 3 {
		posed.minimum[axis] = min(posed.minimum[axis], minimum[axis])
		posed.maximum[axis] = max(posed.maximum[axis], maximum[axis])
	}
}

// The piece at the transform, and the box grown by its bounds under it;
// nothing when the slot's layers have no vertices.
add_posed_piece :: proc(posed: ^Posed_Model, renderer: Model_Renderer, machine: Machine_Id, slot: Model_Mesh_Slot, transform: matrix[4, 4]f32) {
	piece := Model_Piece{machine, slot}
	if !layers_have_vertices(model_piece_layers(renderer, piece)) || posed.count >= MAXIMUM_POSED_PIECES {
		return
	}
	posed.pieces[posed.count] = {slot = slot, transform = transform}
	posed.count += 1
	bounds := model_piece_bounds(renderer, piece)
	low, high := transformed_box(transform, bounds.minimum, bounds.maximum)
	grow_posed_box(posed, low, high)
}

// The body, then the part at each pose of motion_part_transforms, in the
// order the model draws.
pose_machine_model :: proc(renderer: Model_Renderer, machine_id: Machine_Id, body: matrix[4, 4]f32, machine: Machine, phase: f32) -> Posed_Model {
	posed := empty_posed_model()
	add_posed_piece(&posed, renderer, machine_id, .Body, body)
	poses := motion_part_transforms(machine.motion, machine.footprint, phase)
	for transform in poses.transforms[:poses.count] {
		add_posed_piece(&posed, renderer, machine_id, .Part, body * transform)
	}
	return posed
}

// draw_arm_colored's parts, then its two fingers, each from its voxels
// through its pose to the world; the angles at the placement's fraction.
pose_arm :: proc(renderer: Model_Renderer, machine_id: Machine_Id, placement: Arm_Placement) -> (posed: Posed_Model, angles: Arm_Joint_Angles) {
	angles = arm_pose_at(placement.dimensions, placement.fraction)
	posed = empty_posed_model()
	voxels := arm_voxel_scale()
	parts := arm_part_transforms(placement.dimensions, angles)
	for part in Arm_Part {
		if part != .Finger {
			add_posed_piece(&posed, renderer, machine_id, arm_part_slot(part), placement.transform * parts[part] * voxels)
		}
	}
	for finger in arm_finger_transforms(parts[.Gripper], angles.grip) {
		add_posed_piece(&posed, renderer, machine_id, .Arm_Finger, placement.transform * finger * voxels)
	}
	return posed, angles
}

// draw_held_item's cube, hanging from the hand.
held_item_box :: proc(hand: [3]f32) -> (minimum, maximum: [3]f32) {
	half := f32(INSERTER_HELD_ITEM_SIZE) / 2
	return hand - {half, 2 * half, half}, hand + {half, 0, half}
}

// The bottom row the colour over 255 and 1, as a tree's carries its
// species (tree_instance): the shaders rebuild it to 0, 0, 0, 1.
instance_matrix_with_color :: proc(transform: matrix[4, 4]f32, color: rl.Color) -> matrix[4, 4]f32 {
	instance := transform
	instance[3, 0] = f32(color.r) / 255
	instance[3, 1] = f32(color.g) / 255
	instance[3, 2] = f32(color.b) / 255
	instance[3, 3] = 1
	return instance
}

model_instance_before :: proc(first, second: Model_Instance) -> bool {
	if first.piece.machine != second.piece.machine {
		return first.piece.machine < second.piece.machine
	}
	return first.piece.slot < second.piece.slot
}

// The instances sorted by machine and slot, keeping their order within a
// piece; then per layer, per run of one piece whose layer has vertices, a
// group at the packed matrices' end and the run's matrices with that
// layer's colour.
pack_model_instances :: proc(renderer: Model_Renderer, instances: []Model_Instance, packed: ^[dynamic]matrix[4, 4]f32, groups: ^[Model_Layer][dynamic]Model_Instance_Group) {
	slice.stable_sort_by(instances, model_instance_before)
	for layer in Model_Layer {
		start := 0
		for start < len(instances) {
			end := start + 1
			for end < len(instances) && instances[end].piece == instances[start].piece {
				end += 1
			}
			mesh := model_piece_layers(renderer, instances[start].piece)[layer]
			if mesh.vertexCount > 0 {
				append(&groups[layer], Model_Instance_Group{mesh = mesh, first = len(packed), count = end - start})
				for instance in instances[start:end] {
					append(packed, instance_matrix_with_color(instance.transform, instance.colors[layer]))
				}
			}
			start = end
		}
	}
}

// A cube of side 1 round the origin: 24 corners, four a face with its
// outward normal, white, 36 indices counter clockwise seen from outside.
unit_cube_mesh :: proc(allocator := context.temp_allocator) -> Model_Mesh {
	mesh := Model_Mesh {
		positions = make([dynamic][3]f32, allocator),
		normals   = make([dynamic][3]f32, allocator),
		colors    = make([dynamic][4]u8, allocator),
		indices   = make([dynamic]u16, allocator),
	}
	for axis in 0 ..< 3 {
		for sign in ([2]f32{1, -1}) {
			normal, across, along: [3]f32
			normal[axis] = sign
			across[(axis + 1) % 3] = 1
			along[(axis + 2) % 3] = 1
			if sign < 0 {
				across, along = along, across
			}
			first := u16(len(mesh.positions))
			for corner in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
				append(&mesh.positions, (normal + across * corner.x + along * corner.y) / 2)
				append(&mesh.normals, normal)
				append(&mesh.colors, [4]u8{255, 255, 255, 255})
			}
			append(&mesh.indices, first, first + 1, first + 2, first, first + 2, first + 3)
		}
	}
	return mesh
}

// The unit cube's 12 edges as 24 points, a segment each two in order,
// normals +y, in the colour, no indices.
cube_edge_mesh :: proc(color: rl.Color, allocator := context.temp_allocator) -> Model_Mesh {
	mesh := Model_Mesh {
		positions = make([dynamic][3]f32, allocator),
		normals   = make([dynamic][3]f32, allocator),
		colors    = make([dynamic][4]u8, allocator),
	}
	for axis in 0 ..< 3 {
		for corner in ([4][2]f32{{-0.5, -0.5}, {0.5, -0.5}, {0.5, 0.5}, {-0.5, 0.5}}) {
			start: [3]f32
			start[(axis + 1) % 3] = corner.x
			start[(axis + 2) % 3] = corner.y
			end := start
			start[axis], end[axis] = -0.5, 0.5
			append(&mesh.positions, start, end)
			append(&mesh.normals, [3]f32{0, 1, 0}, [3]f32{0, 1, 0})
			append(&mesh.colors, [4]u8{color.r, color.g, color.b, color.a}, [4]u8{color.r, color.g, color.b, color.a})
		}
	}
	return mesh
}

// Impure.

// With the pass's list, one instance a piece; else each piece's layers
// drawn at once, in order (the pod, today's draws).
emit_posed_model :: proc(renderer: Model_Renderer, frame: Model_Frame, machine_id: Machine_Id, kind: Machine_Kind, posed: Posed_Model, colors: [Model_Layer]rl.Color) {
	if model_frame_takes_instances(frame, kind) {
		for index in 0 ..< posed.count {
			pose := posed.pieces[index]
			append(frame.instances, Model_Instance{piece = {machine_id, pose.slot}, transform = pose.transform, colors = colors})
		}
		return
	}
	for index in 0 ..< posed.count {
		pose := posed.pieces[index]
		draw_model_layers_colored(renderer, model_piece_layers(renderer, {machine_id, pose.slot}), pose.transform, colors)
	}
}

// The camera's frustum, inside BeginMode3D (draw_field's two lines).
camera_frustum :: proc(camera: rl.Camera3D) -> render_frustum.Frustum {
	view_projection := rlgl.GetMatrixProjection() * rl.GetCameraMatrix(camera)
	return render_frustum.frustum_from_matrix(cast(matrix[4, 4]f32)view_projection)
}

// The model shader's three switches; nothing unless instancing_ready.
set_model_instancing :: proc(renderer: Model_Renderer, instanced, tint, flat: bool) {
	if !renderer.instancing_ready {
		return
	}
	shader := renderer.material.shader
	values := [3]f32{instanced ? 1 : 0, tint ? 1 : 0, flat ? 1 : 0}
	rl.SetShaderValue(shader, renderer.instanced_location, &values[0], .FLOAT)
	rl.SetShaderValue(shader, renderer.instance_tint_location, &values[1], .FLOAT)
	rl.SetShaderValue(shader, renderer.flat_location, &values[2], .FLOAT)
}

// The lit material with colDiffuse white, which the instances' colours
// take the place of.
white_model_material :: proc(renderer: Model_Renderer) -> rl.Material {
	material := renderer.material
	material.maps[rl.MaterialMapIndex.ALBEDO].color = rl.WHITE
	return material
}

// The slabs, their edges and the belt items draw between these: the
// model shader instanced and flat, the colour per instance with tint,
// matModel the rlgl stack's transform (a frame's matrix for the slabs,
// the identity for the items) as draw_scene_model_instances sets it, so
// the haze reads the world position.
begin_flat_instances :: proc(renderer: Model_Renderer, tint: bool) {
	set_model_instancing(renderer, true, tint, true)
	material := white_model_material(renderer)
	begin_instanced_material(material)
	set_material_matrix_uniform(material.shader.locs[int(rl.ShaderLocationIndex.MATRIX_MODEL)], rlgl.GetMatrixTransform())
}

end_flat_instances :: proc(renderer: Model_Renderer) {
	end_instanced_material(renderer.material)
	set_model_instancing(renderer, false, false, false)
}

// rlgl's batch drawn through the model shader's flat mode, so the runs,
// the poles, the torch boxes and the scene's box draws take the haze
// (0360); nothing unless flat_batch_ready, which leaves raylib's default
// shader. Flat without instanced_on tells model.vs the vertex is a batch
// vertex: rlgl moves it by the matrix stack on the CPU (rlVertex3f) and
// writes matModel from the stack's transform at every flush, so a flush
// inside a frame's push or DrawCube's own would apply a transform twice
// if matModel were read. Between the two nothing draws through the model
// shader by DrawMesh or instanced and nothing sets its switches, since
// the flush at the end reads the program's uniforms as they stand then.
begin_flat_batch :: proc(renderer: Model_Renderer) {
	if !renderer.flat_batch_ready {
		return
	}
	rl.BeginShaderMode(renderer.material.shader)
	set_model_instancing(renderer, false, false, true)
}

end_flat_batch :: proc(renderer: Model_Renderer) {
	if !renderer.flat_batch_ready {
		return
	}
	rl.EndShaderMode()
	set_model_instancing(renderer, false, false, false)
}

// The pass's packed matrices and groups, in temp memory.
packed_model_instances :: proc(renderer: Model_Renderer, instances: []Model_Instance) -> (packed: [dynamic]matrix[4, 4]f32, groups: [Model_Layer][dynamic]Model_Instance_Group) {
	packed = make([dynamic]matrix[4, 4]f32, 0, 2 * len(instances), context.temp_allocator)
	for &list in groups {
		list = make([dynamic]Model_Instance_Group, context.temp_allocator)
	}
	pack_model_instances(renderer, instances, &packed, &groups)
	return packed, groups
}

// The scene's instances up into the buffer, then the lit groups through
// the model shader lit by the open sky, the emissive ones flat, matModel
// the rlgl stack's transform (the pod's during the descent) as DrawMesh
// gives it. Nothing for none.
draw_scene_model_instances :: proc(renderer: Model_Renderer, instances: []Model_Instance, buffer: ^Instance_Buffer) {
	if len(instances) == 0 {
		return
	}
	packed, groups := packed_model_instances(renderer, instances)
	upload_instances_in_place(&buffer.buffer, &buffer.capacity, packed[:])
	material := white_model_material(renderer)
	for layer in Model_Layer {
		if len(groups[layer]) == 0 {
			continue
		}
		set_model_instancing(renderer, true, true, layer == .Emissive)
		begin_instanced_material(material)
		set_material_matrix_uniform(material.shader.locs[int(rl.ShaderLocationIndex.MATRIX_MODEL)], rlgl.GetMatrixTransform())
		for group in groups[layer] {
			draw_mesh_instances(group.mesh, buffer.buffer, group.first, group.count)
		}
		end_instanced_material(material)
	}
	set_model_instancing(renderer, false, false, false)
}

// The sun's pass's instances up into the buffer, then every group of both
// layers through the depth shader's instanced_on. Nothing for none.
draw_cast_model_instances :: proc(renderer: Model_Renderer, instances: []Model_Instance, buffer: ^Instance_Buffer, shadows: Sun_Shadow_Renderer) {
	if len(instances) == 0 {
		return
	}
	packed, groups := packed_model_instances(renderer, instances)
	upload_instances_in_place(&buffer.buffer, &buffer.capacity, packed[:])
	set_sun_shadow_instanced(shadows, true)
	begin_instanced_material(shadows.material)
	for layer in Model_Layer {
		for group in groups[layer] {
			draw_mesh_instances(group.mesh, buffer.buffer, group.first, group.count)
		}
	}
	end_instanced_material(shadows.material)
	set_sun_shadow_instanced(shadows, false)
}

release_instance_buffer :: proc(buffer: ^Instance_Buffer) {
	unload_instanced_buffer(0, buffer.buffer)
	buffer^ = {}
}

release_field_instance_buffers :: proc(buffers: []Field_Instance_Buffers) {
	for &slot in buffers {
		release_instance_buffer(&slot.cast_models)
		release_instance_buffer(&slot.kept_cast_models)
		release_instance_buffer(&slot.models)
		release_instance_buffer(&slot.items)
	}
}
