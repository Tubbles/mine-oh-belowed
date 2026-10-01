# 0162: One cue detector per frame

Status: todo (after 0161)

## Goal

Refactor 3 of the presentation audit (`doc/audit/presentation.md`, section 5; finding 2 in its findings list). The frame turns the simulation's counters into cues three times over: `advance_player_animation_memory` (`player_animation.odin`) and `advance_sound_memory` (`sound_events.odin`) each keep a walked distance, a cadence and a placed total and call `advance_cadence_millimetres`; the particle memory (`render_particles.odin`) keeps its own counts; `enter_session` resets the three memories separately. The cue list the detector emits (footstep, place, break, dig quarter, launch, landing, shipment, discovery, survey) is what a game plugin would emit per tick instead of the frame diffing counters, so this is the frame-side half of the per tick event seam.

## Change

- One memory struct and one pure step per frame (full-word names, for example `Cue_Memory` and `detect_cues`) that reads the counters the three memories read today (the statistics, the player, the shipments, the records the audit names) and returns the frame's cues as a small list or bit set with the data a cue carries (the footstep's block material, the place's position, the break's block, the launch's pad). The step is pure: memory in, counters in, cues and the next memory out, no raylib call.
- `advance_player_animation_memory`, `advance_sound_memory` and the particle emitters read the cue list instead of the counters; the per memory step detectors, message scans and dig memories go. The four resets in `enter_session` become one.
- The cadence rule stays exactly as today (`test_step_detector_fires_once_per_half_cycle`, `test_footstep_fires_once_per_half_cycle`, `test_cheat_speed_footsteps_keep_the_normal_rate`): cheat speed does not speed up the cadence, per `DESIGN.md`'s no perceivable repetition rule.
- `doc/presentation.md` describes the detector in one place and the three readers point to it. `doc/code_map.md`: records lowered where the tool lets, never raised silently.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; the guards the audit names (`test_step_detector_fires_once_per_half_cycle`, `test_footstep_fires_once_per_half_cycle`, `test_counter_cues`, `test_cheat_speed_footsteps_keep_the_normal_rate`, `test_place_swing_fires_once_per_growth`, `test_break_puff_fires_once`, `test_shipment_starts_a_descent`) pass unchanged in what they assert, re-pointed at the detector where they built a memory; a new test of the detector itself over a scripted counter sequence; a playtest (the user) of footsteps, placing, breaking, a launch and a landing.
