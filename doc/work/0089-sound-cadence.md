# 0089 Sound cadence: slower steps, bird clusters, no machine gun

Status: implemented
Milestone: M11

## Goal

Couch report (2026-09-28): many of the new sounds play too often. The walking bob and footsteps should have about a third of their frequency, the birds play too often, and the mining hits under cheat speed sound like a machine gun. The design principle in `DESIGN.md` applies: no perceivable repetition, and never a fixed period.

## Deliverables

- Walk cycle: `WALK_CYCLE_MILLIMETRES` (`src/player_animation.odin`) goes from 1600 to 4800, so the bob and the footsteps run at a third of their rate (at the walking speed that is about two steps a second); the sound detector shares the constant.
- Bird and insect ambience become clusters, not loops: the `ambience_birds` and `ambience_insects` loops are replaced by short effect files (three to five chirps or buzzes each, several variants: `ambience_birds_1` to `_3`, `ambience_insects_1` to `_2`, generated), and a cluster scheduler in `src/sound_events.odin` plays one variant, then a second after 1 to 3 seconds with a chance of a third, then waits 20 to 60 seconds (from a hash of the tick and the count, never a fixed period) before the next cluster, only by day for birds, with the pitch varied by plus or minus 8 percent; wind and water stay loops. The sound table's kind for the clusters is `effect`.
- Every other periodic sound gets a jitter: footstep pitch already varies; the hum loop's volume drifts by plus or minus 5 percent over 3 to 7 seconds; the rain loop's volume follows the intensity as it does.
- The mining hit cap from 0087 applies here if 0087 has not landed first (coordinate through the item files).
- Tests: the cluster scheduler's pauses lie in range and differ between clusters, the variant choice cycles without repeating the last, the walk cycle constant, the hum drift range.
- Docs: `doc/content.md` (the sound table's clusters), `DESIGN.md` if the sparse sound rule mentions loops, `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: steps at a natural pace, birds in short bursts with long silences, no hit burst while digging fast.

## Notes

Files a subagent may touch: `src/player_animation.odin`, `src/player_animation_test.odin`, `src/sound_events.odin`, `src/sound_events_test.odin`, `src/audio.odin`, `src/audio_test.odin`, `tools/make_placeholder_sounds.py`, `data/sounds/` (new files, the table, the removed loops), `data/biomes.sjson` (ambience names), the docs above, this file.

Implemented: `WALK_CYCLE_MILLIMETRES` is 4800 (`src/player_animation.odin`). `src/sound_events.odin` has the cluster scheduler (`Ambience_Cluster_Memory`, `advance_ambience_cluster`, the variant choice, pauses, gaps and pitch from `sound_hash`), the mining hit cap (`MINING_HIT_MAXIMUM_PER_SECOND` 3, `next_mining_hit_tick` in `Sound_Memory`, the 0087 part) and the hum drift (`Hum_Drift_Memory`). `src/audio.odin` reads an optional `day_only` per sound, accepts clustered variants for a biome ambience and plays `ambience_` calls on the ambience volume. `tools/make_placeholder_sounds.py` writes `ambience_birds_1` to `_3` and `ambience_insects_1` to `_2` instead of the two loops and takes an optional output directory; `data/sounds/` gains those five files and loses `ambience_birds.wav` and `ambience_insects.wav`; `data/sounds/sounds.sjson` and the comment in `data/biomes.sjson` follow. `src/loop.odin` (outside the list) passes the daylight blend in `Sound_Frame`, which "only by day for birds" needs. Tests in `src/player_animation_test.odin`, `src/sound_events_test.odin` and `src/audio_test.odin`; 954 tests pass. Docs: `doc/content.md`, `DESIGN.md`, `doc/log/2026-09-28.md`.
