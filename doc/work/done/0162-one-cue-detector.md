# 0162: One cue detector per frame

Status: implemented

## Goal

Refactor 3 of the presentation audit (`doc/audit/presentation.md`, section 5; finding 2 in its findings list). The frame turns the simulation's counters into cues three times over: `advance_player_animation_memory` (`player_animation.odin`) and `advance_sound_memory` (`sound_events.odin`) each keep a walked distance, a cadence and a placed total and call `advance_cadence_millimetres`; the particle memory (`render_particles.odin`) keeps its own counts; `enter_session` resets the three memories separately. The cue list the detector emits (footstep, place, break, dig quarter, launch, landing, shipment, discovery, survey) is what a game plugin would emit per tick instead of the frame diffing counters, so this is the frame-side half of the per tick event seam.

## Change

- One memory struct and one pure step per frame (full-word names, for example `Cue_Memory` and `detect_cues`) that reads the counters the three memories read today (the statistics, the player, the shipments, the records the audit names) and returns the frame's cues as a small list or bit set with the data a cue carries (the footstep's block material, the place's position, the break's block, the launch's pad). The step is pure: memory in, counters in, cues and the next memory out, no raylib call.
- `advance_player_animation_memory`, `advance_sound_memory` and the particle emitters read the cue list instead of the counters; the per memory step detectors, message scans and dig memories go. The four resets in `enter_session` become one.
- The cadence rule stays exactly as today (`test_step_detector_fires_once_per_half_cycle`, `test_footstep_fires_once_per_half_cycle`, `test_cheat_speed_footsteps_keep_the_normal_rate`): cheat speed does not speed up the cadence, per `DESIGN.md`'s no perceivable repetition rule.
- `doc/presentation.md` describes the detector in one place and the three readers point to it. `doc/code_map.md`: records lowered where the tool lets, never raised silently.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; the guards the audit names (`test_step_detector_fires_once_per_half_cycle`, `test_footstep_fires_once_per_half_cycle`, `test_counter_cues`, `test_cheat_speed_footsteps_keep_the_normal_rate`, `test_place_swing_fires_once_per_growth`, `test_break_puff_fires_once`, `test_shipment_starts_a_descent`) pass unchanged in what they assert, re-pointed at the detector where they built a memory; a new test of the detector itself over a scripted counter sequence; a playtest (the user) of footsteps, placing, breaking, a launch and a landing.

## Notes

Before the change (HEAD 18423c2), what the three memories read, derived and kept:

| Memory | Counters read | Cues derived | Fields kept |
|---|---|---|---|
| `Player_Animation_Memory` (`advance_player_animation_memory`) | `statistics.distance_walked_millimetres`, `placed_total(statistics)` (`placed`, `blocks_placed`), the tick, cheat speed | footstep (dust in `update_player_presence`), place swing, moving | known, tick, distance, cadence distance, moving, placed total, swing active and start |
| `Sound_Memory` (`advance_sound_memory`, `observe_sounds`) | the same distance, placed total, tick and cheat speed; `statistics.blocks_mined`; `players[0].mining` (`Mining_Sound_Memory`: active, block, entity, quarter); `launching_pad_count(world)`; `Particle_Memory.descent.active`; `len(quests.messages)` and `discovery_since`; the world at the feet on a footstep | footstep, mining hit, block break, block place, launch, landing, discovery | known, tick, distance, cadence distance, step count, placed total, blocks mined, dig, next mining hit tick, launching count, descent active, message count, ambience cluster, hum drift |
| `Particle_Memory` (`update_break_puff`, `update_capsule_descent`, `update_satellite_pass`) | `players[0].mining` (`Mining_Memory`: cell, block, fraction, a block dig only) and the world at its cell; `len(records.shipments)`; `quests.messages` and `orbital_survey_since`; the world under the feet on a footstep (dust) | break puff, descent start, satellite pass start; the descent's end (landing puff) | frame count, dig, shipments known and count, descent, messages known and count, satellite pass |

The cues `detect_cues` emits (`Frame_Cues`, a `bit_set[Cue]` plus fields):

- Footstep: the cadence distance crossed a half walk cycle on a new tick; carries the blocks at and under the feet (`feet_block`, `under_block`). The frame also carries the walk (`cadence_millimetres`, `moving`) the animation phase follows.
- Place: `placed_total` grew. Block_Break: `blocks_mined` grew (the break sound).
- Dig_Break: the local block dig was past `DIG_BREAK_MINIMUM_FRACTION` last frame and its block is gone; carries `broken_cell` and `broken_block` (the puff). Kept apart from Block_Break because the two conditions differ today (the statistic counts every mined block, the puff needs the dig past half way); merging them would change which frames puff or sound.
- Dig_Quarter: the same dig crossed into quarter 1, 2 or 3. The rate cap (`MINING_HIT_MAXIMUM_PER_SECOND`) stays in `Sound_Memory`, since it paces a sound.
- Launch, Shipment: the launching pad count and the shipment count grew.
- Discovery, Survey: a new item discovered or orbital survey message since the last frame's message count (one scan, `quest_message_since`).
- Landing: not a counter. The capsule descent the shipment starts ends in render time, so `update_capsule_descent` returns its end and `draw_session_world` adds Landing to the frame's cues before the sounds read them. Same frame as before: the sound compared the descent after the particles' update.

Not carried, because no reader uses it and the counters do not hold it: the place's position and block, the launch's pad.

What each memory keeps now: `Player_Animation_Memory` the walk copied from the cues and the place swing; `Sound_Memory` the step count (pitch variation), the next mining hit tick, the ambience clusters, the hum drift; `Particle_Memory` the frame count, the descent and the satellite pass. `enter_session` resets five values (`Cue_Memory` added); they stay separate because the remaining memories hold session state of their own (the descent, the ambience clusters, the swing), not cue detection.

`cues.odin` lands in presentation through the prefix `cues`, added to `PREFIX_CLUSTERS` in `tools/code_graph.py`. `code_graph.py --check`: 630 references against the table before and after, 0 new or grown; no record fell, since the presentation to simulation references moved between presentation files without leaving the cluster.

`ui_mission_control_test.odin` was re-pointed too (its satellite pass test called `update_satellite_pass` with the messages), and `doc/audit/presentation.md` marks the removed names (`check_docs.py`).
