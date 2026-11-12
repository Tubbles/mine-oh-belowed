package game

import "core:math"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"

// Placeholder entity models: a coloured cube per footprint cell, with a
// brighter top layer on a burning furnace, for inserters a post with an
// arm that turns with the cycle, and for drills a darker top with a
// turning bar (brown burner, blue electric), for
// crafting machines a body in their category's colour (teal assembler,
// brown crusher, blue washer, grey alloy furnace) with a bright top while
// working, and for labs a white body with a blue top while researching.
// A launch pad is a flat platform with a tower on one corner, and the
// rocket a tall box on the platform that grows with its assembly, stands
// while ready, and rises and fades while it launches. Real models come with the art pass.
// A machine with a model (render_models.odin, work items 0055 and 0056) is
// drawn with it instead: the part moves and the glow lights up while the
// machine works (the green of its bottleneck marker), an inserter's arm
// follows its swing and carries the held item at the part's hand, and a
// launch pad's model is the platform, with the tower and the rocket drawn
// as before. A vessel part (0361) without a model is a box per held cell
// in its record's colour, so an empty ring shows its hollow.
// draw_entities draws every pool's body on both worlds (0362), each box
// on a frame under the frame's matrix (begin_entity_cells_draw); the fluid
// ports and the arrows (a drill's output, a pump's flow, a splitter's
// direction) are signs drawn after the bodies (draw_ports_and_arrows), and
// on the field a launching rocket, the one translucent box, after the
// players (draw_launching_rockets).

CHEST_COLOR :: rl.Color{130, 88, 48, 255}
FURNACE_COLOR :: rl.Color{120, 120, 124, 255}
FURNACE_BURNING_TOP_COLOR :: rl.Color{240, 150, 60, 255}
CAPSULE_COLOR :: rl.Color{210, 212, 216, 255}
CAPSULE_TOP_COLOR :: rl.Color{200, 90, 40, 255}
// A full crate shows a gold lid, an emptied one a plain one.
SCHEMATIC_CRATE_COLOR :: rl.Color{120, 84, 50, 255}
SCHEMATIC_CRATE_FULL_TOP_COLOR :: rl.Color{220, 180, 60, 255}
ENTITY_EDGE_COLOR :: rl.Color{30, 30, 30, 255}
INSERTER_POST_COLOR :: rl.Color{70, 70, 76, 255}
BURNER_INSERTER_ARM_COLOR :: rl.Color{150, 110, 70, 255}
ELECTRIC_INSERTER_ARM_COLOR :: rl.Color{220, 190, 60, 255}
FILTER_INSERTER_ARM_COLOR :: rl.Color{150, 90, 190, 255}
INSERTER_POST_SIZE :: [3]f32{0.3, 0.4, 0.3}
INSERTER_PIVOT_HEIGHT :: 0.45
INSERTER_ARM_LENGTH :: 0.7
INSERTER_ARM_RADIUS :: 0.05
INSERTER_HELD_ITEM_SIZE :: 0.2
DRILL_COLOR :: rl.Color{150, 120, 70, 255}
DRILL_TOP_COLOR :: rl.Color{95, 75, 45, 255}
ELECTRIC_DRILL_COLOR :: rl.Color{80, 120, 150, 255}
ELECTRIC_DRILL_TOP_COLOR :: rl.Color{50, 75, 95, 255}
BORE_DRILL_COLOR :: rl.Color{110, 90, 130, 255}
BORE_DRILL_TOP_COLOR :: rl.Color{70, 55, 85, 255}
DRILL_BIT_COLOR :: rl.Color{200, 200, 205, 255}
DRILL_ARROW_COLOR :: rl.Color{240, 220, 80, 255}
DRILL_BIT_LENGTH :: 0.8
DRILL_BIT_RADIUS :: 0.08
ASSEMBLER_WORKING_TOP_COLOR :: rl.Color{120, 220, 200, 255}

@(rodata)
crafting_machine_colors := [Recipe_Maker]rl.Color {
	.Hand          = {},
	.Furnace       = {},
	.Assembler     = {70, 130, 130, 255},
	.Crusher       = {130, 100, 70, 255},
	.Washer        = {70, 110, 160, 255},
	.Alloy_Furnace = {100, 96, 104, 255},
	.Refinery      = {150, 130, 90, 255},
	.Cracking      = {130, 90, 110, 255},
	.Chemistry     = {110, 150, 110, 255},
	.Gasifier      = {120, 100, 80, 255},
	.Electrolysis  = {170, 150, 60, 255},
	.Recycler      = {90, 120, 70, 255},
	.Stone_Cutting = {128, 122, 112, 255},
}
LAB_COLOR :: rl.Color{200, 204, 210, 255}
LAB_RESEARCHING_TOP_COLOR :: rl.Color{90, 150, 240, 255}
CORE_SAMPLE_DRILL_COLOR :: rl.Color{150, 120, 90, 255}
CORE_SAMPLE_DRILL_REPORTED_TOP_COLOR :: rl.Color{80, 200, 200, 255}
LAUNCH_PAD_COLOR :: rl.Color{120, 122, 128, 255}
LAUNCH_TOWER_COLOR :: rl.Color{170, 60, 45, 255}
ROCKET_COLOR :: rl.Color{230, 232, 236, 255}
LAUNCH_PAD_PLATFORM_HEIGHT :: 0.4
LAUNCH_TOWER_HEIGHT :: 14.0
ROCKET_WIDTH :: 2.0
ROCKET_HEIGHT :: 12.0
// The part of the rocket shown as soon as its assembly starts.
ROCKET_MINIMUM_FRACTION :: 0.05
// Blocks the rocket climbs during the ascent.
ROCKET_ASCENT_HEIGHT :: 120.0
// Turns of the bit per drill cycle.
DRILL_BIT_TURNS_PER_CYCLE :: 4
// The cull box of the ports, the arrows and a drill's bar: the footprint
// grown by the margin each way and by the rise above, for the squares on
// the faces and the arrows' tips over the top.
PORT_AND_ARROW_MARGIN_CELLS :: 0.1
PORT_AND_ARROW_RISE_CELLS :: 0.2

box_centre :: proc(minimum: World_Coordinate, size: [3]i32) -> [3]f32 {
	return {f32(minimum.x) + f32(size.x) / 2, f32(minimum.y) + f32(size.y) / 2, f32(minimum.z) + f32(size.z) / 2}
}

// The footprint's box in its frame's cells.
entity_cell_box :: proc(origin: World_Coordinate, size: [3]i32) -> (minimum, maximum: [3]f32) {
	minimum = {f32(origin.x), f32(origin.y), f32(origin.z)}
	return minimum, minimum + {f32(size.x), f32(size.y), f32(size.z)}
}

// The footprint's box grown for its ports and arrows.
port_and_arrow_box :: proc(common: Entity_Common) -> (minimum, maximum: [3]f32) {
	low, high := entity_cell_box(common.origin, common.size)
	margin := f32(PORT_AND_ARROW_MARGIN_CELLS)
	return low - margin, high + {margin, PORT_AND_ARROW_RISE_CELLS, margin}
}

// Before a box drawn in a frame's cells (low to high): false when the pass
// does not show the box under the frame's matrix (model_frame_shows_cells),
// and nothing pushed; else true with the matrix pushed onto rlgl's stack,
// the block frame's identity skipped as draw_entity_cells skips it. A true
// is closed by end_entity_cells_draw with the same frame.
begin_entity_cells_draw :: proc(frame: Model_Frame, frame_id: Frame_Id, low, high: [3]f32) -> (shown: bool) {
	transform := model_frame_entity_matrix(frame, &frame.world.entities, frame_id)
	if !model_frame_shows_cells(frame, transform, low, high) {
		return false
	}
	if frame_id != BLOCK_FRAME {
		flat := transmute([16]f32)transform
		rlgl.PushMatrix()
		rlgl.MultMatrixf(raw_data(flat[:]))
	}
	return true
}

end_entity_cells_draw :: proc(frame_id: Frame_Id) {
	if frame_id != BLOCK_FRAME {
		rlgl.PopMatrix()
	}
}

// The machine's model (render_models.odin) when it has one, posed for
// working, and true; else a cube per footprint cell in the colours with an
// edge frame, and false. The cubes are left out when the pass does not
// show their footprint (0347).
draw_entity_cells :: proc(common: Entity_Common, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame, working: bool, color, top_color: rl.Color) -> bool {
	if draw_machine_model(models, machines, common, frame, working) {
		return true
	}
	transform := model_frame_entity_matrix(frame, &frame.world.entities, common.frame)
	low, high := entity_cell_box(common.origin, common.size)
	if !model_frame_shows_cells(frame, transform, low, high) {
		return false
	}
	// On a frame the cubes go under its matrix, as the model's do
	// (draw_posed_model); the block frame's is the identity and is skipped.
	if common.frame != BLOCK_FRAME {
		flat := transmute([16]f32)transform
		rlgl.PushMatrix()
		rlgl.MultMatrixf(raw_data(flat[:]))
	}
	defer if common.frame != BLOCK_FRAME {
		rlgl.PopMatrix()
	}
	top := common.origin.y + common.size.y - 1
	for cell in common_cells(common, machines) {
		rl.DrawCube(block_centre(cell), 1, 1, 1, cell.y == top ? top_color : color)
	}
	extent := [3]f32{f32(common.size.x), f32(common.size.y), f32(common.size.z)}
	rl.DrawCubeWiresV(box_centre(common.origin, common.size), extent, ENTITY_EDGE_COLOR)
	return false
}

inserter_arm_color :: proc(machine: Machine) -> rl.Color {
	switch {
	case inserter_has_filter(machine):
		return FILTER_INSERTER_ARM_COLOR
	case inserter_is_electric(machine):
		return ELECTRIC_INSERTER_ARM_COLOR
	}
	return BURNER_INSERTER_ARM_COLOR
}

// The arm turns about the post through the right hand side, from over the
// pickup cell (fraction 0) to over the drop cell (fraction 1).
// A long inserter's arm is as many times longer as its reach.
inserter_arm_end :: proc(pivot: [3]f32, direction: u8, fraction: f32, reach: i32) -> [3]f32 {
	forward := belt_direction_vector(direction)
	right := belt_direction_vector(turn_right(direction))
	angle := math.PI * fraction
	return pivot + (right * math.sin(angle) - forward * math.cos(angle)) * INSERTER_ARM_LENGTH * f32(max(reach, 1))
}

draw_held_item :: proc(position: [3]f32, items: Item_Registry, item: Item_Id) {
	size := f32(INSERTER_HELD_ITEM_SIZE)
	rl.DrawCube(position - {0, size / 2, 0}, size, size, size, item_cube_color(items, item))
}

// The arm (render_arm.odin) posed from the cycle, lit like a model; the
// held item hangs at the hand between the grab and the release. Left out
// when the pass does not show the posed arm with its held item (0347);
// true whenever the machine has an arm.
draw_inserter_model :: proc(inserter: Inserter, machine: Machine, models: Model_Renderer, items: Item_Registry, frame: Model_Frame) -> bool {
	if _, found := machine_arm_model(models, inserter.machine); !found {
		return false
	}
	placement := model_frame_arm_placement(frame, inserter, machine)
	posed, angles := pose_arm(models, inserter.machine, placement)
	holds := !stack_is_empty(inserter.held) && arm_shows_held_item(placement.fraction)
	hand := transform_point(placement.transform, arm_hand_point(placement.dimensions, angles))
	if holds {
		minimum, maximum := held_item_box(hand)
		grow_posed_box(&posed, minimum, maximum)
	}
	if !model_frame_shows_box(frame, posed.minimum, posed.maximum) {
		return true
	}
	light_tint := model_light_tint(model_frame_light(frame, model_light_cell(inserter.common)), frame.day_factor, frame.sky_tint)
	glow := emissive_brightness(.Arm, 0, placement.working, light_tint)
	emit_posed_model(models, frame, inserter.machine, machine.kind, posed, {.Lit = brightness_color(light_tint), .Emissive = brightness_color(glow)})
	if holds {
		draw_held_item(hand, items, inserter.held.item)
	}
	return true
}

draw_inserter :: proc(inserter: Inserter, machine: Machine, models: Model_Renderer, items: Item_Registry, frame: Model_Frame) {
	if draw_inserter_model(inserter, machine, models, items, frame) {
		return
	}
	// The box fallback is in the cells of the inserter's frame, its arm
	// reaching up to its reach each way across.
	transform := model_frame_entity_matrix(frame, &frame.world.entities, inserter.frame)
	reach := f32(max(inserter.reach, 1))
	low, high := entity_cell_box(inserter.origin, {1, 1, 1})
	if !model_frame_shows_cells(frame, transform, low - {reach, 0, reach}, high + {reach, 0, reach}) {
		return
	}
	flat := transmute([16]f32)transform
	rlgl.PushMatrix()
	defer rlgl.PopMatrix()
	rlgl.MultMatrixf(raw_data(flat[:]))
	tick_rate := frame.tick_rate
	centre := block_centre(inserter.origin)
	bottom := f32(inserter.origin.y)
	rl.DrawCubeV({centre.x, bottom + INSERTER_POST_SIZE.y / 2, centre.z}, INSERTER_POST_SIZE, INSERTER_POST_COLOR)
	pivot := [3]f32{centre.x, bottom + INSERTER_PIVOT_HEIGHT, centre.z}
	end := inserter_arm_end(pivot, inserter.rotation, inserter_arm_fraction(inserter, machine, tick_rate), inserter.reach)
	rl.DrawCylinderEx(pivot, end, INSERTER_ARM_RADIUS, INSERTER_ARM_RADIUS, 6, inserter_arm_color(machine))
	if !stack_is_empty(inserter.held) {
		draw_held_item(end, items, inserter.held.item)
	}
}

// The bar across the top in the frame's cells, just over the top face's
// centre, turned with the cycle: DRILL_BIT_TURNS_PER_CYCLE turns a cycle
// of the drill's tick counter.
drill_bar_ends :: proc(drill: Drill, machine: Machine, tick_rate: int) -> (start, end: [3]f32) {
	centre := box_centre(drill.origin, drill.size)
	top := centre + {0, f32(drill.size.y) / 2 + 0.02, 0}
	angle := drill_progress_fraction(drill, machine, tick_rate) * DRILL_BIT_TURNS_PER_CYCLE * 2 * math.PI
	half := [3]f32{math.cos(angle), 0, math.sin(angle)} * DRILL_BIT_LENGTH / 2
	return top - half, top + half
}

// The body, and without a model a bar across the top that turns with the
// cycle while the drill mines (a model moves its own part instead), under
// the frame's matrix. The output arrow is draw_ports_and_arrows'.
draw_drill :: proc(drill: Drill, machine: Machine, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	working := drill_model_working(drill)
	color, top_color := DRILL_COLOR, DRILL_TOP_COLOR
	if drill_is_bore(machine) {
		color, top_color = BORE_DRILL_COLOR, BORE_DRILL_TOP_COLOR
	} else if drill_is_electric(drill) {
		color, top_color = ELECTRIC_DRILL_COLOR, ELECTRIC_DRILL_TOP_COLOR
	}
	if draw_entity_cells(drill.common, machines, models, frame, working, color, top_color) {
		return
	}
	low, high := port_and_arrow_box(drill.common)
	if !begin_entity_cells_draw(frame, drill.frame, low, high) {
		return
	}
	defer end_entity_cells_draw(drill.frame)
	start, end := drill_bar_ends(drill, machine, frame.tick_rate)
	rl.DrawCylinderEx(start, end, DRILL_BIT_RADIUS, DRILL_BIT_RADIUS, 6, DRILL_BIT_COLOR)
}

// From the footprint's centre to the side the output drops from, with a
// small cube at the tip.
draw_drill_arrow :: proc(origin: World_Coordinate, size: [3]i32, rotation: u8, height: f32, color: rl.Color) {
	centre := box_centre(origin, size)
	centre.y = height
	forward := belt_direction_vector(rotation)
	tip := centre + forward * (f32(size.x) / 2)
	rl.DrawLine3D(centre, tip, color)
	rl.DrawCubeV(tip, {0.12, 0.12, 0.12}, color)
}

core_sample_drill_is_working :: proc(drill: Core_Sample_Drill) -> bool {
	return core_sample_drill_wants_power(drill) && drill.power.satisfaction > 0
}

launch_pad_is_working :: proc(pad: Launch_Pad) -> bool {
	return pad.state == .Assembling || pad.state == .Launching
}

// Whether a model works this frame: its part moves, its emissive
// materials glow and its lamps shine (0224). The draw and the lamps'
// gather (gather_machine_lights) read the same procedure, so they agree.
furnace_model_working :: proc(furnace: Furnace) -> bool {
	return marker_means_working(entity_marker_colour(furnace.common, machine_marker_colour(furnace.state, furnace_has_fuel(furnace))))
}

schematic_crate_model_working :: proc(crate: Schematic_Crate) -> bool {
	return !stack_is_empty(crate.slots[0])
}

drill_model_working :: proc(drill: Drill) -> bool {
	return marker_means_working(entity_marker_colour(drill.common, machine_marker_colour(drill.state, true)))
}

assembler_model_working :: proc(assembler: Assembler) -> bool {
	return marker_means_working(entity_marker_colour(assembler.common, machine_marker_colour(assembler.state, true)))
}

lab_model_working :: proc(lab: Lab) -> bool {
	return marker_means_working(entity_marker_colour(lab.common, machine_marker_colour(lab.state, true)))
}

fluid_machine_model_working :: proc(fluid_machine: Fluid_Machine) -> bool {
	return marker_means_working(entity_marker_colour(fluid_machine.common, machine_marker_colour(fluid_machine.state, true)))
}

// A power switch that is on; a pole never works.
pole_model_working :: proc(pole: Pole, machine: Machine) -> bool {
	return machine.kind == .Power_Switch && pole.on
}

// The pod always works for its model, its emissive materials and its
// lamps (0224), so its cabin is lit from the arrival on; a hatch while it
// is open (as hatch_pose); the charge controller always (0358), as the
// cradle's supply is unlimited.
foundation_model_working :: proc(entities: ^Entities, foundation: Foundation, machine: Machine) -> bool {
	#partial switch machine.kind {
	case .Pod:
		return true
	case .Hatch:
		return foundation.hatch_open
	case .Charge_Controller:
		return true
	}
	return false
}

// A working machine's lamps (0224) in the world, where its model is drawn,
// clipped to the machine's box up to its model's top (0229). A lamp that
// flickers (0274) takes its colour times flicker, the machine's fire's.
append_machine_lights :: proc(lights: ^[dynamic]Point_Light, entities: ^Entities, common: Entity_Common, machine: Machine, working: bool, top_cells: f32, flicker: f32 = 1) {
	if !working || machine.light_count == 0 {
		return
	}
	body := entity_body_matrix(entities, common)
	pitch := entity_frame_pitch_millimetres(entities, common.frame)
	clip_box := machine_light_clip_box(body, machine.footprint, top_cells)
	for index in 0 ..< machine.light_count {
		light := machine.lights[index]
		if light.flicker {
			light.color *= flicker
		}
		append(lights, machine_point_light(light, body, pitch, clip_box))
	}
}

// The lamps of the machines draw_entities draws whose model works. Chests,
// capsules and splitters never work; an inserter's light is its arm's lamp
// (arm_point_light); a fluid machine works as its draw says, a power
// switch while on, a lamp while lit (0362). The models give each box its
// top (machine_model_top).
// A furnace's lamps flicker with its flames (the salt and the clock of
// gather_machine_flames, 0274), at FIRE_POINT_LIGHT_SHARE of their swing
// (fire_point_light_flicker, 0284).
gather_machine_lights :: proc(lights: ^[dynamic]Point_Light, entities: ^Entities, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	seconds := model_frame_seconds(frame)
	for furnace in entities.furnaces.entries {
		if furnace.alive {
			flicker := fire_point_light_flicker(fire_flicker(seconds, flame_salt(furnace.origin, furnace.frame), frame.reduced_motion))
			append_machine_lights(lights, entities, furnace.common, machines.machines[furnace.machine], furnace_model_working(furnace), machine_model_top(models, furnace.common), flicker)
		}
	}
	for crate in entities.schematic_crates.entries {
		if crate.alive {
			append_machine_lights(lights, entities, crate.common, machines.machines[crate.machine], schematic_crate_model_working(crate), machine_model_top(models, crate.common))
		}
	}
	for drill in entities.drills.entries {
		if drill.alive {
			append_machine_lights(lights, entities, drill.common, machines.machines[drill.machine], drill_model_working(drill), machine_model_top(models, drill.common))
		}
	}
	for assembler in entities.assemblers.entries {
		if assembler.alive {
			append_machine_lights(lights, entities, assembler.common, machines.machines[assembler.machine], assembler_model_working(assembler), machine_model_top(models, assembler.common))
		}
	}
	for lab in entities.labs.entries {
		if lab.alive {
			append_machine_lights(lights, entities, lab.common, machines.machines[lab.machine], lab_model_working(lab), machine_model_top(models, lab.common))
		}
	}
	for drill in entities.core_sample_drills.entries {
		if drill.alive {
			append_machine_lights(lights, entities, drill.common, machines.machines[drill.machine], core_sample_drill_is_working(drill), machine_model_top(models, drill.common))
		}
	}
	for pad in entities.launch_pads.entries {
		if pad.alive {
			append_machine_lights(lights, entities, pad.common, machines.machines[pad.machine], launch_pad_is_working(pad), machine_model_top(models, pad.common))
		}
	}
	for fluid_machine in entities.fluid_machines.entries {
		if fluid_machine.alive {
			append_machine_lights(lights, entities, fluid_machine.common, machines.machines[fluid_machine.machine], fluid_machine_model_working(fluid_machine), machine_model_top(models, fluid_machine.common))
		}
	}
	for pole in entities.poles.entries {
		if pole.alive {
			machine := machines.machines[pole.machine]
			append_machine_lights(lights, entities, pole.common, machine, pole_model_working(pole, machine), machine_model_top(models, pole.common))
		}
	}
	for lamp in entities.lamps.entries {
		if lamp.alive {
			append_machine_lights(lights, entities, lamp.common, machines.machines[lamp.machine], lamp.lit, machine_model_top(models, lamp.common))
		}
	}
	for foundation in entities.foundations.entries {
		if foundation.alive {
			machine := machines.machines[foundation.machine]
			append_machine_lights(lights, entities, foundation.common, machine, foundation_model_working(entities, foundation, machine), machine_model_top(models, foundation.common))
		}
	}
}

// Between BeginMode3D and EndMode3D, after the chunks. Every pool's
// bodies on both worlds (0362): the splitters, the fluid machines, the
// poles and the lamps after the launch pads; a splitter's belt halves
// stay draw_belts', the wires draw_wires', the ports and arrows
// draw_ports_and_arrows'. In the scene's pass collecting instances
// (model_frame_flat_batch) the pools' box draws, the held items and the
// vessel parts' boxes go through the model shader's flat batch and take
// the haze (0360); the foundations' pool stays out, since the pod there
// draws by DrawMesh through the model shader, which would read flat_on
// at 1.
draw_entities :: proc(world: ^World, machines: Machine_Registry, models: Model_Renderer, items: Item_Registry, frame: Model_Frame) {
	flat := model_frame_flat_batch(frame)
	if flat {
		begin_flat_batch(models)
	}
	for chest in world.entities.chests.entries {
		if chest.alive && model_frame_draws_entity(frame, &world.entities, models, chest.common) {
			draw_entity_cells(chest.common, machines, models, frame, false, CHEST_COLOR, CHEST_COLOR)
		}
	}
	for furnace in world.entities.furnaces.entries {
		if furnace.alive && model_frame_draws_entity(frame, &world.entities, models, furnace.common) {
			top := furnace.state == .Burning ? FURNACE_BURNING_TOP_COLOR : FURNACE_COLOR
			draw_entity_cells(furnace.common, machines, models, frame, furnace_model_working(furnace), FURNACE_COLOR, top)
		}
	}
	for capsule in world.entities.capsules.entries {
		if capsule.alive && model_frame_draws_entity(frame, &world.entities, models, capsule.common) {
			draw_entity_cells(capsule.common, machines, models, frame, false, CAPSULE_COLOR, CAPSULE_TOP_COLOR)
		}
	}
	for crate in world.entities.schematic_crates.entries {
		if crate.alive && model_frame_draws_entity(frame, &world.entities, models, crate.common) {
			full := !stack_is_empty(crate.slots[0])
			top := full ? SCHEMATIC_CRATE_FULL_TOP_COLOR : SCHEMATIC_CRATE_COLOR
			draw_entity_cells(crate.common, machines, models, frame, schematic_crate_model_working(crate), SCHEMATIC_CRATE_COLOR, top)
		}
	}
	for inserter in world.entities.inserters.entries {
		if inserter.alive && model_frame_draws_entity(frame, &world.entities, models, inserter.common) {
			draw_inserter(inserter, machines.machines[inserter.machine], models, items, frame)
		}
	}
	for drill in world.entities.drills.entries {
		if drill.alive && model_frame_draws_entity(frame, &world.entities, models, drill.common) {
			draw_drill(drill, machines.machines[drill.machine], machines, models, frame)
		}
	}
	for assembler in world.entities.assemblers.entries {
		if assembler.alive && model_frame_draws_entity(frame, &world.entities, models, assembler.common) {
			color := crafting_machine_colors[machines.machines[assembler.machine].recipe_maker]
			top := assembler.state == .Working ? ASSEMBLER_WORKING_TOP_COLOR : color
			draw_entity_cells(assembler.common, machines, models, frame, assembler_model_working(assembler), color, top)
		}
	}
	for lab in world.entities.labs.entries {
		if lab.alive && model_frame_draws_entity(frame, &world.entities, models, lab.common) {
			draw_entity_cells(lab.common, machines, models, frame, lab_model_working(lab), LAB_COLOR, lab.state == .Researching ? LAB_RESEARCHING_TOP_COLOR : LAB_COLOR)
		}
	}
	for drill in world.entities.core_sample_drills.entries {
		if drill.alive && model_frame_draws_entity(frame, &world.entities, models, drill.common) {
			top := drill.sample >= 0 ? CORE_SAMPLE_DRILL_REPORTED_TOP_COLOR : CORE_SAMPLE_DRILL_COLOR
			draw_entity_cells(drill.common, machines, models, frame, core_sample_drill_is_working(drill), CORE_SAMPLE_DRILL_COLOR, top)
		}
	}
	for pad in world.entities.launch_pads.entries {
		if pad.alive && model_frame_draws_entity(frame, &world.entities, models, pad.common) {
			draw_launch_pad(pad, machines, models, frame)
		}
	}
	for splitter in world.entities.splitters.entries {
		if splitter.alive && model_frame_draws_entity(frame, &world.entities, models, splitter.common) {
			draw_splitter_body(splitter, machines, models, frame)
		}
	}
	for fluid_machine in world.entities.fluid_machines.entries {
		if fluid_machine.alive && model_frame_draws_entity(frame, &world.entities, models, fluid_machine.common) {
			draw_fluid_machine(fluid_machine, machines, models, frame)
		}
	}
	for pole in world.entities.poles.entries {
		if pole.alive && model_frame_draws_entity(frame, &world.entities, models, pole.common) {
			draw_pole(pole, machines, models, frame)
		}
	}
	for lamp in world.entities.lamps.entries {
		if lamp.alive && model_frame_draws_entity(frame, &world.entities, models, lamp.common) {
			draw_lamp(lamp, machines, models, frame)
		}
	}
	if flat {
		end_flat_batch(models)
	}
	// The pod, its hatches, its crafting bench and its charge controller
	// and the crafting stations ride in the foundations' pool
	// (entity_pod.odin); the foundations themselves are
	// draw_field_foundations' slabs. A hatch's door follows its state
	// (draw_hatch); the others work as foundation_model_working says.
	for foundation in world.entities.foundations.entries {
		if !foundation.alive || !model_frame_draws_entity(frame, &world.entities, models, foundation.common) {
			continue
		}
		machine := machines.machines[foundation.machine]
		#partial switch machine.kind {
		case .Foundation:
		case .Hatch:
			draw_hatch(foundation, machine, machines, models, frame)
		case:
			working := foundation_model_working(&frame.world.entities, foundation, machine)
			draw_entity_cells(foundation.common, machines, models, frame, working, FRAME_FOUNDATION_COLOR, FRAME_FOUNDATION_COLOR)
		}
	}
	// The vessels' parts (0361) on their frames; the field session draws
	// them through here like every machine of draw_entities.
	if flat {
		begin_flat_batch(models)
	}
	for part in world.entities.vessel_parts.entries {
		if part.alive && model_frame_draws_entity(frame, &world.entities, models, part.common) {
			draw_vessel_part(part, machines, models, frame)
		}
	}
	if flat {
		end_flat_batch(models)
	}
}

// A vessel part's model, or a box per held cell (entity_held_cells) in its
// record's colour under its frame's matrix, as a foundation's slab.
draw_vessel_part :: proc(part: Vessel_Part, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	if draw_machine_model(models, machines, part.common, frame, false) {
		return
	}
	machine := machines.machines[part.machine]
	transform := model_frame_entity_matrix(frame, &frame.world.entities, part.frame)
	low, high := entity_cell_box(part.origin, part.size)
	if !model_frame_shows_cells(frame, transform, low, high) {
		return
	}
	flat := transmute([16]f32)transform
	rlgl.PushMatrix()
	defer rlgl.PopMatrix()
	rlgl.MultMatrixf(raw_data(flat[:]))
	for cell in entity_held_cells(part.common, machine) {
		draw_frame_cell(cell, foundation_slab_color(machine))
	}
}

// A hatch of the pod (0198): its door posed from its state (hatch_pose),
// or the box without a model.
draw_hatch :: proc(hatch: Foundation, machine: Machine, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	if _, found := machine_model(models, hatch.machine); found {
		draw_posed_model(models, hatch.common, machine, frame, hatch_pose(frame, hatch, machine))
		return
	}
	draw_entity_cells(hatch.common, machines, models, frame, false, FRAME_FOUNDATION_COLOR, FRAME_FOUNDATION_COLOR)
}

// How far the rocket has climbed and how opaque it is: it speeds up as it
// climbs and fades out over the ascent.
rocket_ascent :: proc(fraction: f32) -> (height: f32, alpha: u8) {
	return fraction * fraction * ROCKET_ASCENT_HEIGHT, u8((1 - fraction) * 255)
}

// A launch pad's boxes in its frame's cells: the platform (drawn without
// a model), the tower on its first cell and, while rocket, the rocket on
// the footprint's centre, growing with its assembly, standing while ready
// and rising and fading (rocket_ascent's alpha) while it launches.
Launch_Pad_Boxes :: struct {
	platform_centre, platform_size: [3]f32,
	tower_centre, tower_size:       [3]f32,
	rocket_centre, rocket_size:     [3]f32,
	rocket_color:                   rl.Color,
	rocket:                         bool,
}

launch_pad_boxes :: proc(pad: Launch_Pad, machine: Machine, tick_rate: int) -> (boxes: Launch_Pad_Boxes) {
	centre := box_centre(pad.origin, pad.size)
	bottom := f32(pad.origin.y)
	boxes.platform_size = {f32(pad.size.x), LAUNCH_PAD_PLATFORM_HEIGHT, f32(pad.size.z)}
	boxes.platform_centre = {centre.x, bottom + LAUNCH_PAD_PLATFORM_HEIGHT / 2, centre.z}
	tower := block_centre(pad.origin)
	boxes.tower_size = {1, LAUNCH_TOWER_HEIGHT, 1}
	boxes.tower_centre = {tower.x, bottom + LAUNCH_TOWER_HEIGHT / 2, tower.z}
	boxes.rocket = pad.state == .Assembling || pad.state == .Rocket_Ready || pad.state == .Launching
	if !boxes.rocket {
		return boxes
	}
	lift, alpha, height := f32(0), u8(255), f32(ROCKET_HEIGHT)
	if pad.state == .Launching {
		lift, alpha = rocket_ascent(launch_pad_progress(pad, machine, tick_rate))
	} else if pad.state == .Assembling {
		height *= max(launch_pad_progress(pad, machine, tick_rate), ROCKET_MINIMUM_FRACTION)
	}
	boxes.rocket_centre = {centre.x, bottom + LAUNCH_PAD_PLATFORM_HEIGHT + height / 2 + lift, centre.z}
	boxes.rocket_size = {ROCKET_WIDTH, height, ROCKET_WIDTH}
	boxes.rocket_color = ROCKET_COLOR
	boxes.rocket_color.a = alpha
	return boxes
}

// The model, then under the frame's matrix the platform without a model,
// the tower and the rocket, culled together up to the rocket's ascent. A
// launching rocket is translucent: the field's passes (a view or casters)
// leave it to draw_launching_rockets, the block world draws it here.
draw_launch_pad :: proc(pad: Launch_Pad, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	machine := machines.machines[pad.machine]
	has_model := draw_machine_model(models, machines, pad.common, frame, launch_pad_is_working(pad))
	low, high := entity_cell_box(pad.origin, pad.size)
	high.y = low.y + LAUNCH_PAD_PLATFORM_HEIGHT + ROCKET_HEIGHT + ROCKET_ASCENT_HEIGHT
	if !begin_entity_cells_draw(frame, pad.frame, low, high) {
		return
	}
	defer end_entity_cells_draw(pad.frame)
	boxes := launch_pad_boxes(pad, machine, frame.tick_rate)
	if !has_model {
		rl.DrawCubeV(boxes.platform_centre, boxes.platform_size, LAUNCH_PAD_COLOR)
		rl.DrawCubeWiresV(boxes.platform_centre, boxes.platform_size, ENTITY_EDGE_COLOR)
	}
	rl.DrawCubeV(boxes.tower_centre, boxes.tower_size, LAUNCH_TOWER_COLOR)
	launching_elsewhere := pad.state == .Launching && (frame.view != nil || frame.casters != nil)
	if boxes.rocket && !launching_elsewhere {
		rl.DrawCubeV(boxes.rocket_centre, boxes.rocket_size, boxes.rocket_color)
	}
}

// The field scene's launching rockets, after the players and before the
// open sky is cleared: drawn in draw_entities' region they would be
// flushed before the instanced machines and the trees, and their depth
// would hide what stands behind them (0360). Through the flat batch with
// the depth test on and depth writes off, the batch flushed before and
// after so nothing else draws without writing depth; the depth mask is
// back on at the end. Nothing unless a pad launches.
draw_launching_rockets :: proc(world: ^World, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	if launching_pad_count(world) == 0 {
		return
	}
	begin_flat_batch(models)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	for pad in world.entities.launch_pads.entries {
		if !pad.alive || pad.state != .Launching {
			continue
		}
		boxes := launch_pad_boxes(pad, machines.machines[pad.machine], frame.tick_rate)
		low, high := boxes.rocket_centre - boxes.rocket_size / 2, boxes.rocket_centre + boxes.rocket_size / 2
		if begin_entity_cells_draw(frame, pad.frame, low, high) {
			rl.DrawCubeV(boxes.rocket_centre, boxes.rocket_size, boxes.rocket_color)
			end_entity_cells_draw(pad.frame)
		}
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	end_flat_batch(models)
}

// The sign a machine shows over its body (draw_entity_ports_and_arrow).
Machine_Arrow :: enum u8 {
	None,
	Drill_Output,
	Flow,
	Splitter,
}

// The machine's single face ports and its arrow under its frame's matrix,
// culled by the footprint grown for them; nothing for no port and no
// arrow. buffers may be nil (the ports' filter colours).
draw_entity_ports_and_arrow :: proc(common: Entity_Common, machine: Machine, buffers: []Fluid_Buffer, fluids: Fluid_Registry, frame: Model_Frame, arrow: Machine_Arrow) {
	if machine.fluid_port_count == 0 && arrow == .None {
		return
	}
	low, high := port_and_arrow_box(common)
	if !begin_entity_cells_draw(frame, common.frame, low, high) {
		return
	}
	defer end_entity_cells_draw(common.frame)
	draw_fluid_ports(common, machine, buffers, fluids)
	switch arrow {
	case .None:
	case .Drill_Output:
		draw_drill_arrow(common.origin, common.size, common.rotation, f32(common.origin.y + common.size.y) + 0.02, DRILL_ARROW_COLOR)
	case .Flow:
		draw_direction_arrow(common.origin, common.size, common.rotation, FLUID_MACHINE_ARROW_COLOR)
	case .Splitter:
		draw_splitter_arrow(common.origin, common.size, common.rotation, SPLITTER_ARROW_COLOR)
	}
}

// Between BeginMode3D and EndMode3D, after draw_entities: the ports and
// arrows of the drills, the crafting machines, the launch pads, the fluid
// machines and the splitters, in the flat batch in the scene's collecting
// pass as draw_entities' boxes. Signs, not bodies: never in the sun's
// pass.
draw_ports_and_arrows :: proc(world: ^World, machines: Machine_Registry, fluids: Fluid_Registry, models: Model_Renderer, frame: Model_Frame) {
	flat := model_frame_flat_batch(frame)
	if flat {
		begin_flat_batch(models)
	}
	for drill in world.entities.drills.entries {
		if drill.alive {
			buffers := drill.buffers
			draw_entity_ports_and_arrow(drill.common, machines.machines[drill.machine], buffers[:], fluids, frame, .Drill_Output)
		}
	}
	for assembler in world.entities.assemblers.entries {
		if assembler.alive {
			buffers := assembler.buffers
			draw_entity_ports_and_arrow(assembler.common, machines.machines[assembler.machine], buffers[:], fluids, frame, .None)
		}
	}
	for pad in world.entities.launch_pads.entries {
		if pad.alive {
			buffers := pad.buffers
			draw_entity_ports_and_arrow(pad.common, machines.machines[pad.machine], buffers[:], fluids, frame, .None)
		}
	}
	for fluid_machine in world.entities.fluid_machines.entries {
		if fluid_machine.alive {
			machine := machines.machines[fluid_machine.machine]
			buffers := fluid_machine.buffers
			draw_entity_ports_and_arrow(fluid_machine.common, machine, buffers[:], fluids, frame, fluid_machine_has_arrow(machine.kind) ? .Flow : .None)
		}
	}
	for splitter in world.entities.splitters.entries {
		if splitter.alive {
			draw_entity_ports_and_arrow(splitter.common, machines.machines[splitter.machine], nil, fluids, frame, .Splitter)
		}
	}
	if flat {
		end_flat_batch(models)
	}
}

// Bottleneck overlay markers (work item 0028): a cube above each machine
// in its state's colour, over the top of its model (work item 0056). Its size grows with the distance from the eye,
// so it covers about the same part of the screen near and far, and never
// shrinks below a small world size up close. Its colours come from the
// theme's palette the palette setting picks (work item 0074).
MARKER_MINIMUM_SIZE :: 0.3
MARKER_SIZE_PER_DISTANCE :: 0.02
MARKER_GAP :: 0.25

// Which palette colour shows each state.
@(rodata)
marker_palette_colors := [Marker_Colour]Palette_Color {
	.Green  = .Working,
	.Yellow = .Waiting,
	.Red    = .Missing,
	.Grey   = .Idle,
}

bottleneck_marker_colors :: proc(theme: Ui_Theme, palette: Marker_Palette) -> (colors: [Marker_Colour]Ui_Color) {
	for &color, marker in colors {
		color = theme.palettes[palette][marker_palette_colors[marker]]
	}
	return colors
}

marker_size :: proc(distance: f32) -> f32 {
	return max(MARKER_MINIMUM_SIZE, distance * MARKER_SIZE_PER_DISTANCE)
}

// Centred over the footprint, one gap above top, the height of the
// machine's model or footprint above its bottom.
marker_position :: proc(common: Entity_Common, size, top: f32) -> [3]f32 {
	centre := box_centre(common.origin, common.size)
	return {centre.x, f32(common.origin.y) + top + MARKER_GAP + size / 2, centre.z}
}

draw_marker :: proc(common: Entity_Common, models: Model_Renderer, color: Ui_Color, eye: [3]f32) {
	size := marker_size(linalg.length(box_centre(common.origin, common.size) - eye))
	position := marker_position(common, size, machine_model_top(models, common))
	rl.DrawCubeV(position, {size, size, size}, to_raylib_color(color))
	rl.DrawCubeWiresV(position, {size, size, size}, ENTITY_EDGE_COLOR)
}

machine_is_connected :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	return entity_network(&entities.electric_networks, handle) >= 0
}

furnace_has_fuel :: proc(furnace: Furnace) -> bool {
	return furnace.fuel_joules > 0 || !stack_is_empty(furnace.slots[FURNACE_FUEL_SLOT])
}

// Between BeginMode3D and EndMode3D, after the entities. colors from
// bottleneck_marker_colors.
draw_machine_markers :: proc(world: ^World, machines: Machine_Registry, models: Model_Renderer, eye: [3]f32, colors: [Marker_Colour]Ui_Color) {
	entities := &world.entities
	for furnace in entities.furnaces.entries {
		if furnace.alive {
			draw_marker(furnace.common, models, colors[entity_marker_colour(furnace.common, machine_marker_colour(furnace.state, furnace_has_fuel(furnace)))], eye)
		}
	}
	for assembler in entities.assemblers.entries {
		if assembler.alive {
			draw_marker(assembler.common, models, colors[entity_marker_colour(assembler.common, machine_marker_colour(assembler.state, machine_is_connected(entities, assembler.handle)))], eye)
		}
	}
	for drill in entities.drills.entries {
		if drill.alive {
			draw_marker(drill.common, models, colors[entity_marker_colour(drill.common, machine_marker_colour(drill.state, machine_is_connected(entities, drill.handle)))], eye)
		}
	}
	for lab in entities.labs.entries {
		if lab.alive {
			draw_marker(lab.common, models, colors[entity_marker_colour(lab.common, machine_marker_colour(lab.state, machine_is_connected(entities, lab.handle)))], eye)
		}
	}
	for fluid_machine in entities.fluid_machines.entries {
		if fluid_machine.alive && fluid_machine_has_marker(machines.machines[fluid_machine.machine].kind) {
			connected := machine_is_connected(entities, fluid_machine.handle)
			draw_marker(fluid_machine.common, models, colors[entity_marker_colour(fluid_machine.common, machine_marker_colour(fluid_machine.state, connected))], eye)
		}
	}
}
