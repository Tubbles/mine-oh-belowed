package game

import "platform"

// The planet preview's arms (work item 0175): the walk screenshot lays two
// arms on its foundation pad, one at rest and one held at full reach by a
// developer pose override for the drawing only (Model_Frame.reaching_arm),
// so one picture shows the folded and the unfolded arm and the working
// arm's light on the ground. The arms are drawn by the session's scene
// (draw_field_scene) with the machine models.

// Cells on the pad (lay_planet_preview_foundations): the arms stand on
// the pad's top facing +x, the reaching one dropping onto the pad's far
// edge.
PLANET_PREVIEW_RESTING_ARM_CELL :: World_Coordinate{-2, 1, -2}
PLANET_PREVIEW_REACHING_ARM_CELL :: World_Coordinate{-2, 1, 0}

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
	machines := preview.content.machines
	machine := find_arm_machine(machines)
	if machine == NO_MACHINE {
		return
	}
	entities := &planet_preview_simulation(preview).world.entities
	place_on_frame(entities, machines, machine, frame, PLANET_PREVIEW_RESTING_ARM_CELL, 0)
	preview.reaching_arm, _ = place_on_frame(entities, machines, machine, frame, PLANET_PREVIEW_REACHING_ARM_CELL, 0)
	platform.log_printf("planet preview: placed two arms on frame %d", frame)
}
