package game

import "core:fmt"
import "core:math"
import rl "shared:raylib"
import "model_vox"
import "platform"

// The player's body (work item 0066): six limb files in data/models/
// (player_torso.vox and the rest, tools/make_placeholder_models.py), each
// the whole frame of PLAYER_MODEL_FRAME voxels at 16 per block with only
// its limb filled, so every limb stands in place at the same transform.
// A limb swings about a pivot taken from its voxel bounds: the shoulder
// at the top of an arm, the hip at the top of a leg, the neck at the
// bottom of the head. The front is +x and the right side +z, like a
// machine's front and the walk's right hand. Loaded with the machine
// models' reader and mesher (model_vox.odin, model_mesh.odin), uploaded
// at start and again when a model file changes (reload_models). Without
// the files the capsule stands in (draw_player_body). The voxel reading,
// the pivots and the transforms are pure; only the upload and the draw
// calls touch raylib.

PLAYER_MODEL_FRAME :: [3]i32{10, 29, 10}
PLAYER_MODEL_VOXELS_PER_BLOCK :: 16
// The first person arm: the shoulder in the camera's frame (forward, up,
// right, in blocks), the angle it is held forward at, and the share of
// the chop and place swings it follows, so the hand stays in view.
FIRST_PERSON_SHOULDER :: [3]f32{-0.05, -0.15, 0.28}
FIRST_PERSON_ARM_DEGREES :: 80.0
FIRST_PERSON_SWING_SHARE :: 0.5
// The held item's icon, in blocks, a little past the hand.
HELD_ITEM_SIZE :: 0.18
HELD_ITEM_REACH :: 0.08
// A held cube shaped block (work item 0092): its edge in blocks, the top
// face at the hand.
HELD_BLOCK_SIZE :: 0.35

Player_Limb :: enum u8 {
	Torso,
	Head,
	Arm_Left,
	Arm_Right,
	Leg_Left,
	Leg_Right,
}

@(rodata)
player_limb_model_ids := [Player_Limb]string {
	.Torso     = "player_torso",
	.Head      = "player_head",
	.Arm_Left  = "player_arm_left",
	.Arm_Right = "player_arm_right",
	.Leg_Left  = "player_leg_left",
	.Leg_Right = "player_leg_right",
}

// The filled voxels, maximum exclusive, in the model's game axes.
Voxel_Bounds :: struct {
	minimum: [3]i32,
	maximum: [3]i32,
}

// pivots and hand are in the model's frame in blocks, x and z centred and
// y from the feet, like the meshes once scaled. hand is the bottom middle
// of the right arm, where the held item goes.
Player_Model_Mesh :: struct {
	limbs:  [Player_Limb]Model_Layers,
	bounds: [Player_Limb]Voxel_Bounds,
	pivots: [Player_Limb][3]f32,
	hand:   [3]f32,
}

// Nothing uploaded (loaded false) draws the capsule.
Player_Model :: struct {
	loaded: bool,
	limbs:  [Player_Limb]Uploaded_Layers,
	pivots: [Player_Limb][3]f32,
	hand:   [3]f32,
}

// found false for an empty model.
voxel_model_bounds :: proc(model: model_vox.Voxel_Model) -> (bounds: Voxel_Bounds, found: bool) {
	bounds = Voxel_Bounds{minimum = model.size, maximum = {}}
	for z in 0 ..< model.size.z {
		for y in 0 ..< model.size.y {
			for x in 0 ..< model.size.x {
				if model_vox.voxel_at(model, {x, y, z}) != 0 {
					bounds.minimum = {min(bounds.minimum.x, x), min(bounds.minimum.y, y), min(bounds.minimum.z, z)}
					bounds.maximum = {max(bounds.maximum.x, x + 1), max(bounds.maximum.y, y + 1), max(bounds.maximum.z, z + 1)}
					found = true
				}
			}
		}
	}
	return bounds, found
}

// Voxel corners to the model frame in blocks.
player_model_point :: proc(voxel: [3]f32, size: [3]i32) -> [3]f32 {
	centre := [3]f32{f32(size.x) / 2, 0, f32(size.z) / 2}
	return (voxel - centre) / PLAYER_MODEL_VOXELS_PER_BLOCK
}

// In voxels: the middle of the bounds across, at the joint's height. An
// arm turns one voxel below its top, so the shoulder stays inside it.
player_limb_pivot_voxels :: proc(limb: Player_Limb, bounds: Voxel_Bounds) -> [3]f32 {
	minimum := [3]f32{f32(bounds.minimum.x), f32(bounds.minimum.y), f32(bounds.minimum.z)}
	maximum := [3]f32{f32(bounds.maximum.x), f32(bounds.maximum.y), f32(bounds.maximum.z)}
	pivot := (minimum + maximum) / 2
	switch limb {
	case .Torso, .Head:
		pivot.y = minimum.y
	case .Arm_Left, .Arm_Right:
		pivot.y = maximum.y - 1
	case .Leg_Left, .Leg_Right:
		pivot.y = maximum.y
	}
	return pivot
}

// The bottom middle of the right arm.
player_hand_voxels :: proc(bounds: Voxel_Bounds) -> [3]f32 {
	return {f32(bounds.minimum.x + bounds.maximum.x) / 2, f32(bounds.minimum.y), f32(bounds.minimum.z + bounds.maximum.z) / 2}
}

destroy_player_model_mesh :: proc(mesh: Player_Model_Mesh) {
	for layers in mesh.limbs {
		destroy_model_layers(layers)
	}
}

// One limb file: the frame's size, some voxels, a mesh in voxel units.
// The mesh is in allocator.
load_player_limb :: proc(mesh: ^Player_Model_Mesh, data_directory: string, limb: Player_Limb, allocator := context.allocator) -> string {
	id := player_limb_model_ids[limb]
	model, problem := model_vox.load_voxel_model_file(model_vox.model_file_path(data_directory, id), context.temp_allocator)
	if problem != "" {
		return problem
	}
	if model.size != PLAYER_MODEL_FRAME {
		return fmt.tprintf("model %s is %v voxels, not %v", id, model.size, PLAYER_MODEL_FRAME)
	}
	bounds, found := voxel_model_bounds(model)
	if !found {
		return fmt.tprintf("model %s: no voxels", id)
	}
	mesh.bounds[limb] = bounds
	mesh.pivots[limb] = player_model_point(player_limb_pivot_voxels(limb, bounds), model.size)
	// The footprint as large as the model: one unit per voxel, scaled to
	// blocks when drawn.
	if mesh.limbs[limb], problem = mesh_voxel_model(model, model.size, allocator); problem != "" {
		return fmt.tprintf("model %s: %s", id, problem)
	}
	return ""
}

// Every limb or nothing; the problem names the file.
load_player_model_mesh :: proc(data_directory: string, allocator := context.allocator) -> (mesh: Player_Model_Mesh, problem: string) {
	for limb in Player_Limb {
		if problem = load_player_limb(&mesh, data_directory, limb, allocator); problem != "" {
			destroy_player_model_mesh(mesh)
			return {}, problem
		}
	}
	mesh.hand = player_model_point(player_hand_voxels(mesh.bounds[.Arm_Right]), PLAYER_MODEL_FRAME)
	return mesh, ""
}

// The transforms, model frame to world. Angles in degrees.

// Voxel units to blocks.
player_model_scale :: proc() -> matrix[4, 4]f32 {
	scale := f32(1) / PLAYER_MODEL_VOXELS_PER_BLOCK
	return matrix[4, 4]f32{
		scale, 0, 0, 0,
		0, scale, 0, 0,
		0, 0, scale, 0,
		0, 0, 0, 1,
	}
}

// Standing at position, the front (+x) turned to the yaw like the look.
player_body_transform :: proc(position: [3]f32, yaw: f32) -> matrix[4, 4]f32 {
	cosine, sine := math.cos(yaw * math.RAD_PER_DEG), math.sin(yaw * math.RAD_PER_DEG)
	return matrix[4, 4]f32{
		cosine, 0, -sine, position.x,
		0, 1, 0, position.y,
		sine, 0, cosine, position.z,
		0, 0, 0, 1,
	}
}

// About the sideways axis (z) through the pivot; positive takes the
// front (+x) up, which swings a hanging limb forward.
limb_swing_transform :: proc(pivot: [3]f32, degrees: f32) -> matrix[4, 4]f32 {
	cosine, sine := math.cos(degrees * math.RAD_PER_DEG), math.sin(degrees * math.RAD_PER_DEG)
	rotation := matrix[4, 4]f32{
		cosine, -sine, 0, 0,
		sine, cosine, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
	return translation_matrix(pivot) * rotation * translation_matrix(-pivot)
}

player_limb_angle :: proc(limb: Player_Limb, angles: Player_Limb_Angles) -> f32 {
	switch limb {
	case .Torso:
		return 0
	case .Head:
		return angles.head_pitch
	case .Arm_Left:
		return angles.left_arm
	case .Arm_Right:
		return angles.right_arm
	case .Leg_Left:
		return angles.left_leg
	case .Leg_Right:
		return angles.right_leg
	}
	return 0
}

// The camera's frame: forward, up and right as the model's x, y and z,
// at the eye.
camera_frame_transform :: proc(eye: [3]f32, yaw, pitch: f32) -> matrix[4, 4]f32 {
	forward := fly_camera_forward(Fly_Camera{yaw = yaw, pitch = pitch})
	right := [3]f32{-math.sin(yaw * math.RAD_PER_DEG), 0, math.cos(yaw * math.RAD_PER_DEG)}
	up := [3]f32{right.y * forward.z - right.z * forward.y, right.z * forward.x - right.x * forward.z, right.x * forward.y - right.y * forward.x}
	return matrix[4, 4]f32{
		forward.x, up.x, right.x, eye.x,
		forward.y, up.y, right.y, eye.y,
		forward.z, up.z, right.z, eye.z,
		0, 0, 0, 1,
	}
}

// The first person right arm in the model frame: its shoulder moved to
// FIRST_PERSON_SHOULDER, held forward, swinging a share of the chop.
first_person_arm_transform :: proc(shoulder: [3]f32, action_degrees: f32) -> matrix[4, 4]f32 {
	degrees := FIRST_PERSON_ARM_DEGREES + action_degrees * FIRST_PERSON_SWING_SHARE
	return translation_matrix(FIRST_PERSON_SHOULDER - shoulder) * limb_swing_transform(shoulder, degrees)
}

transform_point :: proc(transform: matrix[4, 4]f32, point: [3]f32) -> [3]f32 {
	result := transform * [4]f32{point.x, point.y, point.z, 1}
	return result.xyz
}

// Needs the window.

upload_player_model :: proc(mesh: Player_Model_Mesh) -> (model: Player_Model) {
	for layers, limb in mesh.limbs {
		model.limbs[limb] = upload_model_layers(layers)
	}
	model.pivots, model.hand, model.loaded = mesh.pivots, mesh.hand, true
	return model
}

unload_player_model :: proc(model: ^Player_Model) {
	for layers in model.limbs {
		unload_model_layers(layers)
	}
	model^ = {}
}

// On a problem the old meshes stay.
replace_player_model :: proc(model: ^Player_Model, data_directory: string) -> string {
	mesh, problem := load_player_model_mesh(data_directory, context.temp_allocator)
	if problem != "" {
		return problem
	}
	unload_player_model(model)
	model^ = upload_player_model(mesh)
	return ""
}

// At start: without the files the capsule stands in.
init_player_model :: proc(data_directory: string) -> (model: Player_Model) {
	if problem := replace_player_model(&model, data_directory); problem != "" {
		platform.log_printf("error: %s; the player is drawn as a capsule", problem)
	}
	return model
}

draw_player_limb :: proc(renderer: Model_Renderer, model: Player_Model, limb: Player_Limb, transform: matrix[4, 4]f32, light: rl.Color) {
	draw_model_layers_colored(renderer, model.limbs[limb], transform, {.Lit = light, .Emissive = light})
}

// The six limbs at the pose, posed by the angles.
draw_player_model :: proc(renderer: Model_Renderer, model: Player_Model, pose: Player_Pose, angles: Player_Limb_Angles, light: rl.Color) {
	body := player_body_transform(pose.position, pose.yaw)
	for limb in Player_Limb {
		swing := limb_swing_transform(model.pivots[limb], player_limb_angle(limb, angles))
		draw_player_limb(renderer, model, limb, body * swing * player_model_scale(), light)
	}
}
