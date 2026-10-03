# 0179: The slice: the content, the world settings and the switch to the field world

Status: todo (last of M13)

## Goal

The first playable slice as PLAN.md's M13 verify statement: a large planet generated lazily and played at 4, 8 and 16 km, the slope walk, two brushes, one basin of water, one torch in a dug cave, one foundation with a drill, an arm and a belt into a chest, a day and a night, lockstep between two machines plus a split screen pair; the session switched from the block world to the field world.

## Change

- The material table (`data/materials.sjson`, started by 0171 with the item and the tool tier) replacing the block table for the terrain: per material the density behaviour, texture parameters, grain and the torch as the slice's one emitter; the block table stays for the block world's files until M14.
- The slice's content: the planet record with the three radii as presets, the pod as the start (a model and a frame with the bed, no oxygen yet), the drill on a vein outcrop of the field (the vein reservoir placed by generation on the sphere), the arm, one belt, one chest, the recipe chain the quest's chapter 1 needs for them.
- World settings: terrain sample spacing (a third of a metre to a metre), the planet radius preset, the mode as a stored value with only peaceful in effect, keep inventory as a stored value; the new world screen shows them. The world file records the planet id and the generation values it was made with (radius, bedrock depth, relief), so a later edit of `data/planets.sjson` cannot reshape the unedited ground around saved chunks (0168's review).
- The session starts the field world; the block world's start is removed from the title (its files remain for M14's content move, reachable by tests only); the dev kits are not rebuilt here (M14).
- The day and night from the shared clock over the planet's rotation; sleeping waits for M15.
- What 0177 left for the slice's multiplayer test: the slot transfers, the held stack and the drags go through the player command list (done by the first part of this item, 2026-10-03, `player_command_slots.odin`); what remains is that a joining player spawns at the pod with the starter kit. What 0171 left: the edit queue and the field's players move from `Field_Simulation` onto `Simulation_State`; a brush edit skips unloaded chunks, which is deterministic only when the field loads from the simulated chunk set so every machine holds the same chunks round an edit, and the field is saved so edits outlive the streaming; `Field_World.edited_chunks` is the renderer's bookkeeping, cleared only by the streaming, so a headless server drains it per tick or caps it. What 0172 left: the sea edge and the missing chunk rule read the loaded set, so the water agrees between machines only when the field loads from the simulated chunk set, and a spring whose water reaches the sea raises the loaded sea since nothing drains above sea level. What 0178 left: the field streaming and the level of detail selection take the union of the viewports' eyes, since the block world's streaming followed the first viewport's player only. What 0174 left: `Field_Simulation.entities` (the field's foundations and frames) is not saved; the lamps (`rebuild_entity_lights`) and `schedule_water_around_freed_cells` take frame local cells as block cells; removing a foundation does not check the machines standing on it; the block placement rules, the belt drag, the fluid networks and the loose items stay on frame 0; the foundation ghost draws at rotation 0.
- `doc/architecture.md` (sessions start the field world), `doc/content.md` (materials, planet presets, world settings), `README.md` (what the game is now) updated; `PLAN.md`'s M13 row set to implemented with the date.

## Verify

- The build and check commands of 0168; the benchmark harness runs on the field world at size 1 (larger sizes in M14).
- Tests: a new world at each preset generates a planet of that radius; the slice's recipe chain is reachable from an empty inventory; the belt line from the drill through the arm fills the chest; the state hash of two instances agrees over the slice's first thousand ticks.
- M13's verify statement: two machines on the home network and a split screen pair on the couch share the sphere for twenty minutes while all four dig, place and run the belt line, with no desync, and the user judges the walk, the digging and the arm at the three radii.
