package game

import "core:fmt"
import "core:math"

// Moving parts and world light of machine models (work item 0056), no
// raylib here: render_models.odin draws with the results. A machine's
// motion (data/machines.sjson) names how its part (<model>_part.vox, the
// same size and frame as the body) moves, or makes its glow voxels pulse.
// Everything is a function of the render time, the machine's state and
// the light around it; the simulation never sees any of it.
//
// A phase runs from 0 to 1 over period_seconds while the machine works
// and stays at 0 (the resting pose, the part as authored) while it does
// not. Positions are in blocks in the model's frame: x and z centred on
// the unrotated footprint, y from its bottom (model_mesh.odin), so the
// entity's model_transform turns the posed part with the body.

Motion_Kind :: enum u8 {
	None,
	// Moves along the axis by amplitude blocks and back, once per period.
	Pump,
	// Turns about the axis through the pivot, amplitude turns per period.
	Spin,
	// Turns about the axis through the pivot by amplitude turns and back.
	Swing,
	// Moves along the axis up to amplitude blocks either way.
	Bob,
	// Moves nothing; the glow voxels pulse while the machine works.
	Glow,
}

@(rodata)
motion_kind_names := [Motion_Kind]string {
	.None  = "",
	.Pump  = "pump",
	.Spin  = "spin",
	.Swing = "swing",
	.Bob   = "bob",
	.Glow  = "glow",
}

@(rodata)
motion_axis_names := [3]string{"x", "y", "z"}

// Palette indices from here up are emissive: drawn at the glow brightness
// instead of the light tint.
EMISSIVE_PALETTE_START :: 240
// Idle emissive voxels are lit like the rest; working ones at full
// brightness, or pulsing down to this with a glow motion.
GLOW_MINIMUM_BRIGHTNESS :: 0.55
// Matches chunk.fs, so models are never darker than the ground.
MINIMUM_MODEL_BRIGHTNESS :: 0.06

// As written in the file. pivot and hand are in blocks in the unrotated
// footprint's frame, from its minimum corner.
Motion_Definition :: struct {
	kind:           string,
	axis:           string,
	amplitude:      f32,
	period_seconds: f32,
	pivot:          [3]f32,
	hand:           [3]f32,
}

// hand is where an inserter's held item hangs from its part at rest.
Machine_Motion :: struct {
	kind:           Motion_Kind,
	axis:           int,
	amplitude:      f32,
	period_seconds: f32,
	pivot:          [3]f32,
	hand:           [3]f32,
}

motion_axis_index :: proc(name: string) -> (axis: int, found: bool) {
	for candidate, index in motion_axis_names {
		if candidate == name {
			return index, true
		}
	}
	return 1, false
}

// Every motion but the glow moves a part, which then needs its file.
motion_has_part :: proc(kind: Motion_Kind) -> bool {
	return kind != .None && kind != .Glow
}

point_in_footprint :: proc(point: [3]f32, footprint: Machine_Footprint_Definition) -> bool {
	extent := [3]f32{f32(footprint.width), f32(footprint.height), f32(footprint.depth)}
	for axis in 0 ..< 3 {
		if point[axis] < 0 || point[axis] > extent[axis] {
			return false
		}
	}
	return true
}

// A motion needs a model, a known kind, a positive period, an axis for a
// part that moves, and a pivot and hand inside the footprint.
validate_motion_definition :: proc(definition: Machine_Definition) -> string {
	motion := definition.motion
	kind, found := parse_named_enum(motion_kind_names, motion.kind)
	switch {
	case !found:
		return fmt.tprintf("machine %q has unknown motion kind %q", definition.id, motion.kind)
	case kind == .None:
		return ""
	case definition.model == "":
		return fmt.tprintf("machine %q has a motion but no model", definition.id)
	case motion.period_seconds <= 0:
		return fmt.tprintf("machine %q needs a positive motion period_seconds", definition.id)
	}
	if _, axis_found := motion_axis_index(motion.axis); !axis_found && kind != .Glow {
		return fmt.tprintf("machine %q has motion axis %q, not x, y or z", definition.id, motion.axis)
	}
	if !point_in_footprint(motion.pivot, definition.footprint) || !point_in_footprint(motion.hand, definition.footprint) {
		return fmt.tprintf("machine %q has a motion pivot or hand outside its footprint", definition.id)
	}
	return ""
}

resolve_machine_motion :: proc(definition: Motion_Definition) -> Machine_Motion {
	kind, _ := parse_named_enum(motion_kind_names, definition.kind)
	axis, _ := motion_axis_index(definition.axis)
	return Machine_Motion {
		kind = kind,
		axis = axis,
		amplitude = definition.amplitude,
		period_seconds = definition.period_seconds,
		pivot = definition.pivot,
		hand = definition.hand,
	}
}

// How far through its period a working machine's part is at the render
// time tick + alpha, shifted by offset (motion_phase_offset) so machines
// of one kind do not move in step; 0 (resting) while it does not work.
motion_phase :: proc(tick: u64, alpha: f32, tick_rate: int, period_seconds: f32, working: bool, offset: f32 = 0) -> f32 {
	period_ticks := f64(period_seconds) * f64(tick_rate)
	if !working || period_ticks <= 0 {
		return 0
	}
	cycles := (f64(tick) + f64(alpha)) / period_ticks + f64(offset)
	return f32(cycles - math.floor(cycles))
}

// A fixed share of a period from 0 up to 1 per entity, hashed from its
// origin cell, so it needs no state and survives saves and reloads.
motion_phase_offset :: proc(origin: World_Coordinate) -> f32 {
	hash := u32(origin.x) * 0x9E3779B1 ~ u32(origin.y) * 0x85EBCA77 ~ u32(origin.z) * 0xC2B2AE3D
	hash ~= hash >> 16
	hash *= 0x7FEB352D
	hash ~= hash >> 15
	hash *= 0x846CA68B
	hash ~= hash >> 16
	return f32(hash >> 8) / (1 << 24)
}

// An inserter's arm follows the simulation's swing instead of the clock:
// half a period takes the pump or swing stroke from pickup (0) to drop.
inserter_motion_phase :: proc(arm_fraction: f32) -> f32 {
	return clamp(arm_fraction, 0, 1) / 2
}

// 0 at phase 0 and 1, 1 at phase 0.5, easing at both ends.
motion_stroke :: proc(phase: f32) -> f32 {
	return (1 - math.cos(2 * math.PI * phase)) / 2
}

translation_matrix :: proc(offset: [3]f32) -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		1, 0, 0, offset.x,
		0, 1, 0, offset.y,
		0, 0, 1, offset.z,
		0, 0, 0, 1,
	}
}

// Right handed: a quarter turn about y takes +x to -z and -x to +z.
axis_rotation_matrix :: proc(axis: int, angle: f32) -> matrix[4, 4]f32 {
	cosine, sine := math.cos(angle), math.sin(angle)
	switch axis {
	case 0:
		return matrix[4, 4]f32{
			1, 0, 0, 0,
			0, cosine, -sine, 0,
			0, sine, cosine, 0,
			0, 0, 0, 1,
		}
	case 2:
		return matrix[4, 4]f32{
			cosine, -sine, 0, 0,
			sine, cosine, 0, 0,
			0, 0, 1, 0,
			0, 0, 0, 1,
		}
	}
	return matrix[4, 4]f32{
		cosine, 0, sine, 0,
		0, 1, 0, 0,
		-sine, 0, cosine, 0,
		0, 0, 0, 1,
	}
}

// A point in the footprint's frame to the model's frame.
footprint_point_to_model :: proc(point: [3]f32, footprint: [3]i32) -> [3]f32 {
	return point - {f32(footprint.x) / 2, 0, f32(footprint.z) / 2}
}

rotation_about_pivot :: proc(axis: int, angle: f32, pivot: [3]f32) -> matrix[4, 4]f32 {
	return translation_matrix(pivot) * axis_rotation_matrix(axis, angle) * translation_matrix(-pivot)
}

// The part's pose in the model's frame; footprint is the machine's
// unrotated footprint. Identity at phase 0 for every kind.
motion_transform :: proc(motion: Machine_Motion, footprint: [3]i32, phase: f32) -> matrix[4, 4]f32 {
	direction: [3]f32
	direction[clamp(motion.axis, 0, 2)] = 1
	pivot := footprint_point_to_model(motion.pivot, footprint)
	switch motion.kind {
	case .Pump:
		return translation_matrix(direction * motion.amplitude * motion_stroke(phase))
	case .Bob:
		return translation_matrix(direction * motion.amplitude * math.sin(2 * math.PI * phase))
	case .Spin:
		return rotation_about_pivot(motion.axis, 2 * math.PI * motion.amplitude * phase, pivot)
	case .Swing:
		return rotation_about_pivot(motion.axis, 2 * math.PI * motion.amplitude * motion_stroke(phase), pivot)
	case .None, .Glow:
	}
	return translation_matrix({})
}

// The brightness of the emissive voxels: lit like the rest while the
// machine does not work, full while it works, pulsing with a glow motion
// (full at phase 0 and 1, GLOW_MINIMUM_BRIGHTNESS at 0.5).
emissive_brightness :: proc(kind: Motion_Kind, phase: f32, working: bool, light_tint: f32) -> f32 {
	if !working {
		return light_tint
	}
	if kind != .Glow {
		return 1
	}
	return GLOW_MINIMUM_BRIGHTNESS + (1 - GLOW_MINIMUM_BRIGHTNESS) * (1 - motion_stroke(phase))
}

// Light levels to brightness like chunk.fs: each level down dims a little
// more than linear, 0 stays 0 and 15 is 1.
light_curve :: proc(level: u8) -> f32 {
	fraction := f32(level) / MAXIMUM_LIGHT
	return fraction / (4 - 3 * fraction)
}

// A packed light byte (sky high, block low) to the brightness of a model,
// combined like chunk.fs: sky light scaled by the day factor plus block
// light, at most 1 and never below MINIMUM_MODEL_BRIGHTNESS.
model_light_tint :: proc(light: u8, day_factor: f32) -> f32 {
	sky := light_curve(light_level(light, .Sky)) * day_factor
	block := light_curve(light_level(light, .Block))
	return max(min(sky + block, 1), MINIMUM_MODEL_BRIGHTNESS)
}

// The cell a model takes its light from: above the footprint's centre, or
// for a machine one block across the cell in front of it at its base.
model_light_cell :: proc(common: Entity_Common) -> World_Coordinate {
	if common.size.x == 1 && common.size.z == 1 {
		return common.origin + belt_direction_offset(common.rotation)
	}
	return {common.origin.x + common.size.x / 2, common.origin.y + common.size.y, common.origin.z + common.size.z / 2}
}

// Where the part's hand (Machine_Motion.hand) is in the world at the
// phase, for the item an inserter holds.
posed_hand_position :: proc(common: Entity_Common, machine: Machine, phase: f32) -> [3]f32 {
	hand := footprint_point_to_model(machine.motion.hand, machine.footprint)
	transform := model_transform(common.origin, common.size, common.rotation) * motion_transform(machine.motion, machine.footprint, phase)
	return (transform * [4]f32{hand.x, hand.y, hand.z, 1}).xyz
}
