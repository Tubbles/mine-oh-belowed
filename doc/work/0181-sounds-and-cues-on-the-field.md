# 0181: Sounds and cues in a field session

Status: todo (2026-10-03, from 0179; folds into 0243 of the brief)

## Goal

A field session sounds like the block world did: footsteps by the material under the feet, the ambience, the machines' sounds at their places, the cue detector's cues per viewport. Today `render_frame` (`loop.odin`) keeps sounds and cues off in a field session because their readers take the block world (block positions, block materials).

## Change

- The footstep reads the field sample under the feet (its material from the material table) and the frame cell when standing on a pad; the machine sounds take the entity's world position through its frame transform (`entity_frame_matrix`); the ambience reads the field's sky light and water nearby where it read blocks.
- The cue detector (0162) takes the field session's events (refusals, placements, the belt line) per viewport.
- The block world's readers stay for the tests until M14 removes the block world type.
- Every sound checked against DESIGN.md's no perceivable repetition rule (clusters, varying pauses, varied pitch); `doc/presentation.md` (Sound) updated.

## Verify

- The build and check commands of 0168.
- Tests: a step on topsoil and a step on stone pick different sounds; a machine on a frame plays at the frame transform of its cell; a refused placement cues once per press; the repetition audit of the sound tests passes for the new sources.
- The couch: the user judges the footsteps and the arm's sounds on the slice.
