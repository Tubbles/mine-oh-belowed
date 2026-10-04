package game

// The pod's airlock (work items 0222, 0231, doc/content.md, Hatches):
// once per tick after the players moved (tick_pod_airlocks), every hatch
// is open exactly while some player's capsule, standing or crouched, any
// heading, is within the reach of its cells, and toggle_hatch applies
// each change on the tick the condition flips; no hold, no interlock, no
// facing (the user, 0231: "just open and close the doors when
// inside/outside 15 cm"). Lockstep state through Foundation.hatch_open
// and hatch_toggle_tick; the prediction never runs it.

// The reach in position units.
Pod_Airlock_Tuning :: struct {
	reach: i64,
}

// From data/game.sjson's pod_airlock. Called by make_field_content and
// the tests.
make_pod_airlock_tuning :: proc(config: Pod_Airlock_Config) -> Pod_Airlock_Tuning {
	return Pod_Airlock_Tuning{reach = millimetres_to_position_units(config.reach_millimetres)}
}

// Any capsule within reach of any of the cells.
capsules_near_cells :: proc(frame: Frame, cells: []World_Coordinate, capsules: []Field_Capsule, reach: i64) -> bool {
	for capsule in capsules {
		for cell in cells {
			if capsule_within_frame_cell(frame, cell, capsule, reach) {
				return true
			}
		}
	}
	return false
}

// Every alive hatch of the foundations' pool by index (toggle_hatch
// changes entries in place and never appends): toggled when whether a
// capsule is near it differs from whether it is open. toggle_hatch's
// capsule check refuses a close while a capsule meets the cells, which
// the reach makes unreachable (a capsule meeting the cells is within
// reach); it stays as the backstop. Only pods place hatches, so the rule
// is per door. Called by tick_field_session_players only.
tick_pod_airlocks :: proc(entities: ^Entities, machines: Machine_Registry, capsules: []Field_Capsule, airlock: Pod_Airlock_Tuning, tick: u64) {
	for index in 0 ..< len(entities.foundations.entries) {
		entry := entities.foundations.entries[index]
		if !entry.alive {
			continue
		}
		open, is_hatch := hatch_state(entities, machines, entry.handle)
		if !is_hatch {
			continue
		}
		frame, found := find_frame(&entities.frames, entry.frame)
		if found && capsules_near_cells(frame, common_cells(entry.common, machines), capsules, airlock.reach) != open {
			toggle_hatch(entities, machines, entry.handle, tick, capsules)
		}
	}
}
