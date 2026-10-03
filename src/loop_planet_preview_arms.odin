package game

import rl "shared:raylib"
import "platform"

// The planet preview's arms (work item 0175): the walk screenshot lays two
// arms on its foundation pad, one at rest and one held at full reach by a
// developer pose override for the screenshot only (the preview does not
// run the entity tick), so one picture shows the folded and the unfolded
// arm and the working arm's light on the ground. The arms are drawn with
// the machine models; the frames draw every other occupied cell.

// Cells on the pad (lay_planet_preview_foundations): the arms stand on
// the pad's top facing +x, the reaching one dropping onto the pad's far
// edge.
PLANET_PREVIEW_RESTING_ARM_CELL :: World_Coordinate{-2, 1, -2}
PLANET_PREVIEW_REACHING_ARM_CELL :: World_Coordinate{-2, 1, 0}
// The models are lit evenly: the preview has no block light.
PLANET_PREVIEW_ARM_LIGHT_TINT :: [3]f32{1, 1, 1}

// The first inserter whose model is an arm, NO_MACHINE when the data has
// none.
find_arm_machine :: proc(machines: Machine_Registry) -> Machine_Id {
	for machine, index in machines.machines {
		if machine.kind == .Inserter && machine.motion.kind == .Arm {
			return Machine_Id(index)
		}
	}
	return NO_MACHINE
}

// The two arms on the pad's frame; the reaching one is remembered for
// the pose override.
lay_planet_preview_arms :: proc(preview: ^Planet_Preview, frame: Frame_Id) {
	machine := find_arm_machine(preview.field_content.machines)
	if machine == NO_MACHINE {
		return
	}
	entities := &preview.field.entities
	place_on_frame(entities, preview.field_content.machines, machine, frame, PLANET_PREVIEW_RESTING_ARM_CELL, 0)
	preview.reaching_arm, _ = place_on_frame(entities, preview.field_content.machines, machine, frame, PLANET_PREVIEW_REACHING_ARM_CELL, 0)
	platform.log_printf("planet preview: placed two arms on frame %d", frame)
}

// The arm's placement, the reaching arm posed over its drop cell and
// working.
planet_preview_arm_placement :: proc(preview: ^Planet_Preview, inserter: Inserter) -> Arm_Placement {
	machine := preview.field_content.machines.machines[inserter.machine]
	placement := inserter_arm_placement(&preview.field.entities, inserter, machine, preview.tick_rate)
	if inserter.handle == preview.reaching_arm {
		placement.fraction, placement.working = ARM_DROP_FRACTION, true
	}
	return placement
}

// Before draw_field: the working arms' lights nearest the camera.
set_planet_preview_point_lights :: proc(preview: ^Planet_Preview, camera: rl.Camera3D) {
	lights := make([dynamic]Point_Light, context.temp_allocator)
	for inserter in preview.field.entities.inserters.entries {
		if !inserter.alive {
			continue
		}
		if light, found := arm_point_light(planet_preview_arm_placement(preview, inserter)); found {
			append(&lights, light)
		}
	}
	nearest, _ := nearest_point_lights(lights[:], camera.position)
	set_field_point_lights(&preview.renderer, nearest)
}

// Inside BeginMode3D.
draw_planet_preview_arms :: proc(preview: ^Planet_Preview) {
	for inserter in preview.field.entities.inserters.entries {
		if !inserter.alive {
			continue
		}
		if arm, found := machine_arm_model(preview.models, inserter.machine); found {
			draw_placed_arm(preview.models, arm, planet_preview_arm_placement(preview, inserter), PLANET_PREVIEW_ARM_LIGHT_TINT, inserter.held, preview.items)
		}
	}
}
