package game

import rl "shared:raylib"

// The inserter's arm on screen (work item 0175): the parts of
// model_arm.odin posed from the inserter's cycle and drawn with the
// machine models' material, on the block frame and on foundation frames
// alike. While the arm moves its lamp glows and a point light shines from
// it (render_point_lights.odin), which the field shader adds on top of
// the field's light.

// The arm's uploaded parts, or found false when the machine has no arm.
machine_arm_model :: proc(renderer: Model_Renderer, machine: Machine_Id) -> (arm: [Arm_Part]Uploaded_Layers, found: bool) {
	if int(machine) >= len(renderer.models) || !layers_have_vertices(renderer.models[machine].arm[.Base]) {
		return {}, false
	}
	return renderer.models[machine].arm, true
}

// transform is the arm's space to the world (arm_entity_transform under
// the frame's matrix); each part goes from its voxels through its pose.
draw_arm_colored :: proc(renderer: Model_Renderer, arm: [Arm_Part]Uploaded_Layers, transform: matrix[4, 4]f32, dimensions: Arm_Dimensions, angles: Arm_Joint_Angles, colors: [Model_Layer]rl.Color) {
	voxels := arm_voxel_scale()
	parts := arm_part_transforms(dimensions, angles)
	for part in Arm_Part {
		if part != .Finger {
			draw_model_layers_colored(renderer, arm[part], transform * parts[part] * voxels, colors)
		}
	}
	for finger in arm_finger_transforms(parts[.Gripper], angles.grip) {
		draw_model_layers_colored(renderer, arm[.Finger], transform * finger * voxels, colors)
	}
}

draw_arm :: proc(renderer: Model_Renderer, arm: [Arm_Part]Uploaded_Layers, transform: matrix[4, 4]f32, dimensions: Arm_Dimensions, angles: Arm_Joint_Angles, light_tint, glow: [3]f32) {
	colors := [Model_Layer]rl.Color {
		.Lit      = brightness_color(light_tint),
		.Emissive = brightness_color(glow),
	}
	draw_arm_colored(renderer, arm, transform, dimensions, angles, colors)
}

// One inserter's arm this frame: where it stands and how it is posed.
Arm_Placement :: struct {
	// The arm's space to the world.
	transform:  matrix[4, 4]f32,
	dimensions: Arm_Dimensions,
	fraction:   f32,
	working:    bool,
}

// The inserter's arm on its frame at its cycle fraction.
inserter_arm_placement :: proc(entities: ^Entities, inserter: Inserter, machine: Machine, tick_rate: int) -> Arm_Placement {
	frame, _ := find_frame(&entities.frames, inserter.frame)
	dimensions := arm_dimensions_on_frame(inserter.reach, frame.pitch_millimetres)
	transform := entity_frame_matrix(entities, inserter.frame) * arm_entity_transform(inserter.common, frame.pitch_millimetres)
	return Arm_Placement {
		transform = transform,
		dimensions = dimensions,
		fraction = inserter_cycle_fraction(inserter, machine, tick_rate),
		working = inserter.state == .Moving,
	}
}

// The inserter's placement this frame, the frame's reaching arm held at
// its drop.
model_frame_arm_placement :: proc(frame: Model_Frame, inserter: Inserter, machine: Machine) -> Arm_Placement {
	placement := inserter_arm_placement(&frame.world.entities, inserter, machine, frame.tick_rate)
	if frame.reaching_arm != NO_ENTITY && inserter.handle == frame.reaching_arm {
		placement.fraction, placement.working = ARM_DROP_FRACTION, true
	}
	return placement
}

// The arm at its placement; the held item hangs at the hand between the
// grab and the release.
draw_placed_arm :: proc(renderer: Model_Renderer, arm: [Arm_Part]Uploaded_Layers, placement: Arm_Placement, light_tint: [3]f32, held: Item_Stack, items: Item_Registry) {
	angles := arm_pose_at(placement.dimensions, placement.fraction)
	glow := emissive_brightness(.Arm, 0, placement.working, light_tint)
	draw_arm(renderer, arm, placement.transform, placement.dimensions, angles, light_tint, glow)
	if !stack_is_empty(held) && arm_shows_held_item(placement.fraction) {
		draw_held_item(transform_point(placement.transform, arm_hand_point(placement.dimensions, angles)), items, held.item)
	}
}

// The lamp's light while the arm moves; found false at rest. With no clip
// box: it lights the ground it works over (0229).
arm_point_light :: proc(placement: Arm_Placement) -> (light: Point_Light, found: bool) {
	if !placement.working {
		return {}, false
	}
	angles := arm_pose_at(placement.dimensions, placement.fraction)
	gripper := arm_part_transforms(placement.dimensions, angles)[.Gripper]
	position := transform_point(placement.transform * gripper, ARM_LAMP_POINT)
	return Point_Light{position = position, color = ARM_LIGHT_COLOR, radius = ARM_LIGHT_RADIUS_METRES}, true
}
