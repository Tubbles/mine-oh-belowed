# 0063 Weather

Status: implemented
Milestone: M11

## Goal

Rain, fog, wind, cloud shadows and snow in cold biomes, cosmetic in alpha so the world stays peaceful and needs no balancing.

## Deliverables

- A weather state per world (clear, overcast, rain, fog, snow in cold biomes) changing over game hours from the seed and the tick, saved.
- Rendering: rain and snow particles around the player, wet ground darkening, fog density, wind swaying leaves and grass through a vertex shader, cloud shadows as a scrolling light modulation.
- A weather setting (on or off) for reduced motion.
- Tests: the weather schedule is deterministic and saved.

## Verify

- Builds and tests pass.
- User: Watch a rain pass; screenshots.

## Notes

Order decision (main agent, 2026-09-28): lands after 0064, which defines the fog distances, the sky colours and the sky light tint the weather modulates. Read 0064's Notes and its Implemented paragraph for the names.

Implementation pointers, decisions taken so the item is unambiguous:

- The schedule is a pure function, not state: `weather_at(seed, tick, day_length_ticks) -> Weather {kind, intensity}` in a new `src/weather.odin`, with `Weather_Kind` clear, overcast, rain, fog, and the intensity 0 to 1. Each game hour (a twenty fourth of the day) gets a kind and a peak intensity from a hash of the seed and the hour index (weights: clear 50 percent, overcast 25, rain 15, fog 10, consecutive hours of the same kind allowed), and the intensity ramps over the first and last tenth of the hour so changes are gradual. Nothing is saved: the same seed and tick always give the same weather, which is what "saved" asks for. Snow is not a kind: a cold column (`terrain_temperature` below -0.45, the cold barrens' bound, at the player's column) renders rain as snow. The developer command `weather <kind>` (doc/commands.md, `src/command.odin`, `src/developer.odin`) forces a kind until `weather auto`, for screenshots; the override lives in the session, not the save.
- Rendering, in a new `src/render_weather.odin`, all from the render time and the camera, no simulation state: rain as short vertical streaks and snow as small quads, 600 particles in a cylinder of 12 blocks around the camera, each particle's position a hash based origin plus its fall speed times the time, wrapped to the cylinder, drawn with `rl.DrawLine3D` (rain) or small billboards (snow) with depth test on so they do not show through walls, count scaled by the intensity; fog from the intensity: the fog distances of 0064 scaled by 0.8 for overcast, 0.5 for rain, 0.25 for fog, blended by intensity, and the sky colours desaturated and darkened by the intensity (overcast and rain); wet ground: the sky light tint darkened by up to 25 percent in rain. Wind: `data/shaders/chunk.vs` gains `uniform float wind_time` and `uniform float wind_strength`, and sways the vertices whose colour alpha says so (the mesher sets vertex alpha 255 for rigid vertices and a lower value for the upper vertices of cross shaped blocks and leaves blocks, `world_mesh.odin`, `world_mesh_light.odin`; the packing comment is updated), by a sine of the world position and the time, up to 0.15 blocks at full strength; strength from the weather (0.3 clear, 1 rain). Cloud shadows: a 64 by 64 value noise texture generated once at start (`src/render_weather.odin`, deterministic), sampled in `data/shaders/chunk.fs` by world xz over 96 blocks plus a scrolling offset from the time, multiplying the sky light term by one minus `cloud_shadow_strength` times the sample; strength 0.15 clear, 0.35 overcast and rain, 0 at night. The chunk vertex shader passes the world position it already computes.
- Setting: `weather` (bool, default true) in `Settings` (`src/settings.odin`, `src/configuration.odin` mapping and its test, `src/ui_screens.odin` Display tab as a toggle "Weather" with a tooltip about motion), off means clear weather always: no particles, no sway, no cloud shadows, the clear fog. 0074 accessibility will fold it into reduced motion.
- Tests (`src/weather_test.odin`, `src/render_weather_test.odin` for the pure parts): the schedule is the same for the same seed and tick and differs between seeds; over a day every kind occurs on the test seeds; the intensity changes by at most a small step between consecutive ticks; the fog scale per kind and the blend; the particle position function wraps inside the cylinder and is deterministic; the cold column rule picks snow; the mesher marks cross and leaves upper vertices with a sway alpha and everything else 255; the configuration round trips the setting; the UI audit passes with the toggle.
- Docs: `doc/architecture.md` (rendering: weather), `doc/ui.md` (the setting), `doc/commands.md` (the command), `DESIGN.md` if the weather is mentioned, `doc/log/2026-09-28.md`, this item's Status and Notes.

Files a subagent may touch: new `src/weather.odin`, `src/weather_test.odin`, `src/render_weather.odin`, `src/render_weather_test.odin`; `src/render_day.odin` and `src/render_sky.odin` (the hooks the weather modulates), `src/render_chunks.odin`, `data/shaders/chunk.vs`, `data/shaders/chunk.fs`, `src/world_mesh.odin`, `src/world_mesh_light.odin`, `src/world_mesh_test.odin`, `src/settings.odin`, `src/configuration.odin`, `src/configuration_test.odin`, `src/ui_screens.odin`, `src/ui_audit_test.odin`, `src/command.odin`, `src/developer.odin`, `src/session.odin` (the override field), `src/loop.odin` (the draw calls and uniforms), `data/strings/en.sjson`, the docs above, this file.

Implemented: new `src/weather.odin` (the schedule `weather_at`, `forced_weather`, `weather_precipitation`) and `src/weather_test.odin`; new `src/render_weather.odin` (`Weather_Look`, the fog scale, the sky gloom and wet ground, the particle positions, the cloud noise texture, the rain and snow draw calls) and `src/render_weather_test.odin`; `src/render_chunks.odin` (`apply_weather` sets the fog distances, the wind and the cloud uniforms per frame; the cloud texture in the material's second map); `data/shaders/chunk.vs` (sway by vertex alpha) and `data/shaders/chunk.fs` (cloud shadows on the sky light term); `src/world_mesh.odin`, `src/world_mesh_light.odin` and `src/world_mesh_test.odin` (the upper vertices of crosses get `SWAY_VERTEX_ALPHA`); `src/settings.odin`, `src/configuration_test.odin`, `src/ui_screens.odin` and `data/strings/en.sjson` (the Weather toggle; the configuration maps a bool setting generically, so `src/configuration.odin` is unchanged); `src/command.odin`, `src/session.odin` and `src/loop.odin` (the `weather` command, the session override, `session_weather`, `draw_session_weather`, the uniforms and the draw call). Per frame at full rain the weather draws about 470 of its 600 particles (those inside the cylinder) as `DrawLine3D` streaks, or as many snow billboards, in one batch with depth writes off; it sets six more chunk uniforms and adds one texture sample per chunk fragment and a few sines per chunk vertex. Leaves do not sway: the mesher cannot tell them from other cubes without a data flag on the block, outside this item's files (see the log). 824 tests pass.
