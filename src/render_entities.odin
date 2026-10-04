package game

import "core:math"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"

// Placeholder entity models: a coloured cube per footprint cell, with a
// brighter top layer on a burning furnace, for inserters a post with an
// arm that turns with the cycle, and for drills a darker top with a
// turning bar and the output arrow (brown burner, blue electric), for
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
// as before.

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

box_centre :: proc(minimum: World_Coordinate, size: [3]i32) -> [3]f32 {
	return {f32(minimum.x) + f32(size.x) / 2, f32(minimum.y) + f32(size.y) / 2, f32(minimum.z) + f32(size.z) / 2}
}

// The machine's model (render_models.odin) when it has one, posed for
// working, and true; else a cube per footprint cell in the colours with an
// edge frame, and false.
draw_entity_cells :: proc(common: Entity_Common, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame, working: bool, color, top_color: rl.Color) -> bool {
	if draw_machine_model(models, machines, common, frame, working) {
		return true
	}
	// On a frame the cubes go under its matrix, as the model's do
	// (draw_posed_model); the block frame's is the identity and is skipped.
	if common.frame != BLOCK_FRAME {
		flat := transmute([16]f32)entity_frame_matrix(&frame.world.entities, common.frame)
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

// The arm (render_arm.odin) posed from the cycle, lit like a model.
draw_inserter_model :: proc(inserter: Inserter, machine: Machine, models: Model_Renderer, items: Item_Registry, frame: Model_Frame) -> bool {
	arm := machine_arm_model(models, inserter.machine) or_return
	light_tint := model_light_tint(model_frame_light(frame, model_light_cell(inserter.common)), frame.day_factor, frame.sky_tint)
	placement := model_frame_arm_placement(frame, inserter, machine)
	draw_placed_arm(models, arm, placement, light_tint, inserter.held, items)
	return true
}

draw_inserter :: proc(inserter: Inserter, machine: Machine, models: Model_Renderer, items: Item_Registry, frame: Model_Frame) {
	if draw_inserter_model(inserter, machine, models, items, frame) {
		return
	}
	// The box fallback is in the cells of the inserter's frame.
	flat := transmute([16]f32)entity_frame_matrix(&frame.world.entities, inserter.frame)
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

// A bar across the top that turns with the cycle while the drill mines
// (a model moves its own part instead), and the output arrow on the top
// face.
draw_drill :: proc(drill: Drill, machine: Machine, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	working := drill_model_working(drill)
	color, top_color := DRILL_COLOR, DRILL_TOP_COLOR
	if drill_is_bore(machine) {
		color, top_color = BORE_DRILL_COLOR, BORE_DRILL_TOP_COLOR
	} else if drill_is_electric(drill) {
		color, top_color = ELECTRIC_DRILL_COLOR, ELECTRIC_DRILL_TOP_COLOR
	}
	has_model := draw_entity_cells(drill.common, machines, models, frame, working, color, top_color)
	centre := box_centre(drill.origin, drill.size)
	top := centre + {0, f32(drill.size.y) / 2 + 0.02, 0}
	if !has_model {
		angle := drill_progress_fraction(drill, machine, frame.tick_rate) * DRILL_BIT_TURNS_PER_CYCLE * 2 * math.PI
		half := [3]f32{math.cos(angle), 0, math.sin(angle)} * DRILL_BIT_LENGTH / 2
		rl.DrawCylinderEx(top - half, top + half, DRILL_BIT_RADIUS, DRILL_BIT_RADIUS, 6, DRILL_BIT_COLOR)
	}
	draw_drill_arrow(drill.origin, drill.size, drill.rotation, top.y, DRILL_ARROW_COLOR)
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

// The pod always works for its model, its emissive materials and its
// lamps (0224), so its cabin is lit from the arrival on; a hatch while it
// is open (as hatch_pose); the oxygen generator while it supplies a
// sealed room.
foundation_model_working :: proc(entities: ^Entities, foundation: Foundation, machine: Machine) -> bool {
	#partial switch machine.kind {
	case .Pod:
		return true
	case .Hatch:
		return foundation.hatch_open
	case .Oxygen_Generator:
		return oxygen_generator_supplies_a_room(entities, foundation.handle)
	}
	return false
}

// A working machine's lamps (0224) in the world, where its model is drawn.
append_machine_lights :: proc(lights: ^[dynamic]Point_Light, entities: ^Entities, common: Entity_Common, machine: Machine, working: bool) {
	if !working || machine.light_count == 0 {
		return
	}
	body := entity_body_matrix(entities, common)
	pitch := entity_frame_pitch_millimetres(entities, common.frame)
	for index in 0 ..< machine.light_count {
		append(lights, machine_point_light(machine.lights[index], body, pitch))
	}
}

// The lamps of the machines draw_entities draws whose model works. Chests
// and capsules never work; an inserter's light is its arm's lamp
// (arm_point_light).
gather_machine_lights :: proc(lights: ^[dynamic]Point_Light, entities: ^Entities, machines: Machine_Registry) {
	for furnace in entities.furnaces.entries {
		if furnace.alive {
			append_machine_lights(lights, entities, furnace.common, machines.machines[furnace.machine], furnace_model_working(furnace))
		}
	}
	for crate in entities.schematic_crates.entries {
		if crate.alive {
			append_machine_lights(lights, entities, crate.common, machines.machines[crate.machine], schematic_crate_model_working(crate))
		}
	}
	for drill in entities.drills.entries {
		if drill.alive {
			append_machine_lights(lights, entities, drill.common, machines.machines[drill.machine], drill_model_working(drill))
		}
	}
	for assembler in entities.assemblers.entries {
		if assembler.alive {
			append_machine_lights(lights, entities, assembler.common, machines.machines[assembler.machine], assembler_model_working(assembler))
		}
	}
	for lab in entities.labs.entries {
		if lab.alive {
			append_machine_lights(lights, entities, lab.common, machines.machines[lab.machine], lab_model_working(lab))
		}
	}
	for drill in entities.core_sample_drills.entries {
		if drill.alive {
			append_machine_lights(lights, entities, drill.common, machines.machines[drill.machine], core_sample_drill_is_working(drill))
		}
	}
	for pad in entities.launch_pads.entries {
		if pad.alive {
			append_machine_lights(lights, entities, pad.common, machines.machines[pad.machine], launch_pad_is_working(pad))
		}
	}
	for foundation in entities.foundations.entries {
		if foundation.alive {
			machine := machines.machines[foundation.machine]
			append_machine_lights(lights, entities, foundation.common, machine, foundation_model_working(entities, foundation, machine))
		}
	}
}

// Between BeginMode3D and EndMode3D, after the chunks.
draw_entities :: proc(world: ^World, machines: Machine_Registry, models: Model_Renderer, items: Item_Registry, frame: Model_Frame) {
	for chest in world.entities.chests.entries {
		if chest.alive {
			draw_entity_cells(chest.common, machines, models, frame, false, CHEST_COLOR, CHEST_COLOR)
		}
	}
	for furnace in world.entities.furnaces.entries {
		if furnace.alive {
			top := furnace.state == .Burning ? FURNACE_BURNING_TOP_COLOR : FURNACE_COLOR
			draw_entity_cells(furnace.common, machines, models, frame, furnace_model_working(furnace), FURNACE_COLOR, top)
		}
	}
	for capsule in world.entities.capsules.entries {
		if capsule.alive {
			draw_entity_cells(capsule.common, machines, models, frame, false, CAPSULE_COLOR, CAPSULE_TOP_COLOR)
		}
	}
	for crate in world.entities.schematic_crates.entries {
		if crate.alive {
			full := !stack_is_empty(crate.slots[0])
			top := full ? SCHEMATIC_CRATE_FULL_TOP_COLOR : SCHEMATIC_CRATE_COLOR
			draw_entity_cells(crate.common, machines, models, frame, schematic_crate_model_working(crate), SCHEMATIC_CRATE_COLOR, top)
		}
	}
	for inserter in world.entities.inserters.entries {
		if inserter.alive {
			draw_inserter(inserter, machines.machines[inserter.machine], models, items, frame)
		}
	}
	for drill in world.entities.drills.entries {
		if drill.alive {
			draw_drill(drill, machines.machines[drill.machine], machines, models, frame)
		}
	}
	for assembler in world.entities.assemblers.entries {
		if assembler.alive {
			color := crafting_machine_colors[machines.machines[assembler.machine].recipe_maker]
			top := assembler.state == .Working ? ASSEMBLER_WORKING_TOP_COLOR : color
			draw_entity_cells(assembler.common, machines, models, frame, assembler_model_working(assembler), color, top)
		}
	}
	for lab in world.entities.labs.entries {
		if lab.alive {
			draw_entity_cells(lab.common, machines, models, frame, lab_model_working(lab), LAB_COLOR, lab.state == .Researching ? LAB_RESEARCHING_TOP_COLOR : LAB_COLOR)
		}
	}
	for drill in world.entities.core_sample_drills.entries {
		if drill.alive {
			top := drill.sample >= 0 ? CORE_SAMPLE_DRILL_REPORTED_TOP_COLOR : CORE_SAMPLE_DRILL_COLOR
			draw_entity_cells(drill.common, machines, models, frame, core_sample_drill_is_working(drill), CORE_SAMPLE_DRILL_COLOR, top)
		}
	}
	for pad in world.entities.launch_pads.entries {
		if pad.alive {
			draw_launch_pad(pad, machines, models, frame)
		}
	}
	// The pod, its hatches, its crafting bench and its oxygen generator
	// and the crafting stations ride in the foundations' pool
	// (entity_pod.odin); the foundations themselves are draw_frames'
	// boxes. A hatch's door follows its state (draw_hatch); the others
	// work as foundation_model_working says.
	for foundation in world.entities.foundations.entries {
		if !foundation.alive {
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
}

// A hatch of the pod (0198): its door posed from its state (hatch_pose),
// or the box without a model.
draw_hatch :: proc(hatch: Foundation, machine: Machine, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	if model, found := machine_model(models, hatch.machine); found {
		draw_posed_model(models, model, hatch.common, machine, frame, hatch_pose(frame, hatch, machine))
		return
	}
	draw_entity_cells(hatch.common, machines, models, frame, false, FRAME_FOUNDATION_COLOR, FRAME_FOUNDATION_COLOR)
}

// How far the rocket has climbed and how opaque it is: it speeds up as it
// climbs and fades out over the ascent.
rocket_ascent :: proc(fraction: f32) -> (height: f32, alpha: u8) {
	return fraction * fraction * ROCKET_ASCENT_HEIGHT, u8((1 - fraction) * 255)
}

draw_launch_pad :: proc(pad: Launch_Pad, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	machine := machines.machines[pad.machine]
	tick_rate := frame.tick_rate
	centre := box_centre(pad.origin, pad.size)
	bottom := f32(pad.origin.y)
	if !draw_machine_model(models, machines, pad.common, frame, launch_pad_is_working(pad)) {
		platform := [3]f32{f32(pad.size.x), LAUNCH_PAD_PLATFORM_HEIGHT, f32(pad.size.z)}
		rl.DrawCubeV({centre.x, bottom + platform.y / 2, centre.z}, platform, LAUNCH_PAD_COLOR)
		rl.DrawCubeWiresV({centre.x, bottom + platform.y / 2, centre.z}, platform, ENTITY_EDGE_COLOR)
	}
	tower := block_centre(pad.origin)
	rl.DrawCubeV({tower.x, bottom + LAUNCH_TOWER_HEIGHT / 2, tower.z}, {1, LAUNCH_TOWER_HEIGHT, 1}, LAUNCH_TOWER_COLOR)
	if pad.state != .Assembling && pad.state != .Rocket_Ready && pad.state != .Launching {
		return
	}
	lift, alpha, height := f32(0), u8(255), f32(ROCKET_HEIGHT)
	if pad.state == .Launching {
		lift, alpha = rocket_ascent(launch_pad_progress(pad, machine, tick_rate))
	} else if pad.state == .Assembling {
		height *= max(launch_pad_progress(pad, machine, tick_rate), ROCKET_MINIMUM_FRACTION)
	}
	rocket := [3]f32{centre.x, bottom + LAUNCH_PAD_PLATFORM_HEIGHT + height / 2 + lift, centre.z}
	color := ROCKET_COLOR
	color.a = alpha
	rl.DrawCubeV(rocket, {ROCKET_WIDTH, height, ROCKET_WIDTH}, color)
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
