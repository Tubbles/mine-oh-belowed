# 0179: The slice: the content, the world settings and the switch to the field world

Status: todo (last of M13)

## Goal

The first playable slice as PLAN.md's M13 verify statement: a large planet generated lazily and played at 4, 8 and 16 km, the slope walk, two brushes, one basin of water, one torch in a dug cave, one foundation with a drill, an arm and a belt into a chest, a day and a night, lockstep between two machines plus a split screen pair; the session switched from the block world to the field world.

## Change

- The material table (`data/materials.sjson`) replacing the block table for the terrain: per material the density behaviour, tool tier, texture parameters, grain and the torch as the slice's one emitter; the block table stays for the block world's files until M14.
- The slice's content: the planet record with the three radii as presets, the pod as the start (a model and a frame with the bed, no oxygen yet), the drill on a vein outcrop of the field (the vein reservoir placed by generation on the sphere), the arm, one belt, one chest, the recipe chain the quest's chapter 1 needs for them.
- World settings: terrain sample spacing (a third of a metre to a metre), the planet radius preset, the mode as a stored value with only peaceful in effect, keep inventory as a stored value; the new world screen shows them. The world file records the planet id and the generation values it was made with (radius, bedrock depth, relief), so a later edit of `data/planets.sjson` cannot reshape the unedited ground around saved chunks (0168's review).
- The session starts the field world; the block world's start is removed from the title (its files remain for M14's content move, reachable by tests only); the dev kits are not rebuilt here (M14).
- The day and night from the shared clock over the planet's rotation; sleeping waits for M15.
- `doc/architecture.md` (sessions start the field world), `doc/content.md` (materials, planet presets, world settings), `README.md` (what the game is now) updated; `PLAN.md`'s M13 row set to implemented with the date.

## Verify

- The build and check commands of 0168; the benchmark harness runs on the field world at size 1 (larger sizes in M14).
- Tests: a new world at each preset generates a planet of that radius; the slice's recipe chain is reachable from an empty inventory; the belt line from the drill through the arm fills the chest; the state hash of two instances agrees over the slice's first thousand ticks.
- M13's verify statement: two machines on the home network and a split screen pair on the couch share the sphere for twenty minutes while all four dig, place and run the belt line, with no desync, and the user judges the walk, the digging and the arm at the three radii.
