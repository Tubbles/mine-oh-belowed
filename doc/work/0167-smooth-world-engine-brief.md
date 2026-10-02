# 0167: The smooth world engine with multiplayer (design brief)

Status: agreed (design; the user agreed to every section and to the recommendations on the open questions in the design session of 2026-10-02; M13's work items 0168 to 0179 are written from it)

Milestone: M13 The first slice ([PLAN.md](../../PLAN.md)). The decisions this brief rests on are in `doc/log/2026-10-02.md`; the design they produced is in `DESIGN.md`. This brief is the technical reading of them in the shape of 0146: what the engine side owns, how each piece works, what it costs, and what is still open. Nothing here is implemented.

## The direction (user, 2026-10-02)

A true sphere of smooth voxels with gravity at its centre, dug and raised by brushes, with water that conserves volume, light that propagates, foundation frames as local grids for the factory, derived belt curves on free poles, big arm inserters, and lockstep multiplayer for many players with four on one screen, built on `main` with saves breaking as needed. The block world is retired and its content carries over. The plugin system of 0146 is on the back burner; its cut is the guide for where the code goes.

## What the engine side owns after the cut

The engine side (the loop, world, presentation, platform and tools clusters of `doc/code_map.md`) owns the terrain field and the water field with their edits, the field light, meshing with level of detail, collision and raycasts against the field, radial gravity frames, foundation frames and the occupancy of their cells, the derived curves of belts and pipes, chunk streaming and generation, the lockstep driver and the network transport, and the viewports. The game side (simulation and content) owns what it owns today: entities and their systems, placement rules expressed on frame cells, inventories, crafting, veins, power, fluids, research, quests, contracts, the screens. The game never sees a sample grid: it asks for the material at a point, for a brush edit, for a frame cell's occupancy and for a belt's point at a distance along it. That is a smaller host surface than today's 26 block reads and 4 block writes, and it is the surface the plugin boundary will carry when the plugin system returns.

## The terrain field

- Storage: samples on a 3D grid aligned with the planet's axes, the planet's centre at the origin, in chunks of 32 by 32 by 32 samples. Each sample holds a density in signed fixed point (one byte, decided: the surface to 1/128 of a cell, where density crosses zero), a material id and a tint id, three bytes. The spacing comes from the world settings (a third of a metre to a metre); the material unit stays one cubic metre per item whatever the spacing. Chunks are generated lazily from the seed around every player and saved as deltas, as today's chunks are.
- Generation: the planet's base surface is its radius plus noise sampled in three dimensions on the sphere (no latitude and longitude parameterisation, so there is no pole singularity), biomes from temperature and moisture read on the sphere, strata by depth below the local surface, caves as three dimensional noise tubes, veins as reservoirs with outcrops as protrusions of ore material, bedrock at the planet's bedrock depth. All noise is integer or fixed point, since every machine in a multiplayer world generates its own chunks and they must agree byte for byte.
- Edits: brushes, a sphere of a few sizes and a level mode that flattens to a plane, applied in fixed point in a deterministic sample order. A dig sums the density removed per material into cubic metres and credits items, with a fractional remainder kept per player so no volume is lost (the credit pattern of `take_power_step`). A place raises the field from the held material and debits the same way.
- Coordinates: world positions in fixed point with a resolution finer than the sample (a 1/4096 m unit in 64 bit integers covers a planet of tens of kilometres with room to spare); chunk coordinates in 32 bit integers. The HUD shows longitude, latitude and height from the position.

## Meshing and level of detail

- Mesher (decided): naive surface nets, smooth and cheap, with normals from the field gradient and the material blended per vertex for the triplanar shader; marching cubes is the fallback if the nets' smoothing hides detail the brushes make. Dual contouring is not wanted, since the terrain is soft by design and the sharp edges belong to the frames' meshes. Meshing runs on the chunk workers that mesh blocks today.
- Level of detail (decided): an octree over chunks with the field sampled coarser for distant chunks; boundaries between levels hidden by skirts first, transition cells only if the seams show under the soft look. The far end is a globe: a sphere mesh with the explored map painted on it, which is also what the launch shows as the terrain fades.
- The horizon on a small planet is close, by d = sqrt(2 R h) for an eye at h = 1.6 m:

| Radius | Horizon |
| --- | --- |
| 200 m | 25 m |
| 2 km | 80 m |
| 8 km | 160 m |
| 16 km | 226 m |
| 33 km | 325 m |
| Earth | 4.5 km |

  Ground beyond the horizon is hidden except where it rises, which lightens the drawing but means an 8 km planet never shows a far plain. The radius is a planet value in data; 8 km is the home world's default record (decided) and the slice is played at 4, 8 and 16 km before the number is fixed. A sphere of a few hundred metres is too small for that judgement (its horizon is a few steps), so the slice generates a large planet lazily and the user walks a small part of it.

## Light

- Propagation stays a flood fill over samples, as `world_light.odin` does over blocks, which gives occlusion for free and works on the field. Two changes: the level carries further (a byte instead of 0 to 15) and the falloff follows a curve in data, gentle near the source and steep at the edge, so a torch lights a room and a lamp a hall. Sky light is the second channel; on a sphere "up" is radial, so sky light cannot fall down a grid column: it is computed by a radial march per sample at generation and under an edit's shadow, cached as the sky channel, with the flood fill carrying it into cave mouths (decided); a surface height map per surface chunk is the optimisation if profiling asks.
- Point lights from the renderer sit on top for working parts (a machine's glow, the arm's light) and never replace the field light.

## Water

- A second field beside the terrain: a fill fraction per sample (a byte), present only where the terrain density is below the surface. A cellular rule moves fill from a sample to neighbours with lower potential, the potential being the distance to the planet's centre in fixed point, so the rule knows the sphere without knowing it, and equalises among equals. Only awake samples run; a sample sleeps when nothing moved for a while and wakes when a neighbour changes. A fill below a minimum depth stops moving and dries slowly, the honest form of Minecraft's run limit.
- Sources: the sea is a level per planet, infinite and static outside the simulated region (any sample below sea level that is not terrain is full); springs are source samples at river heads; rain adds fill to the surface samples of basins at a biome rate. Everything else conserves volume: a breached dam empties its reservoir, a pump empties a pond.
- Flow is measured per sample for hydro. The water field is meshed by the terrain's mesher with a water material. Update order is the sample order, so every machine agrees.

## Collision, raycasts and movement

- Collision is the field read as a signed distance: a capsule samples the density around it, the surface normal is the gradient, the slope angle is read from the normal against the entity's up. Raycasts march the field.
- The player controller runs in fixed point with a radial up: a walkable angle (about 40 degrees, in data) above which the walk slows and slides, a step height of one sample, a jump of about a metre with a mantle to about one and a half, a tool reach of a few metres. Fall damage is survival's. Every entity carries its up; the renderer orients the camera to the player's.

## Frames and foundations

- A foundation frame is a record: an origin, an orientation (up along the radial at placement, any yaw), the pitch (0.5 m, in data). Cells are integer triples in the frame; an occupant index per frame cell says what stands there (the cell occupant index of 0164 becomes per frame). An entity's position is a frame id, a cell and a rotation, and its world position is derived; the game's placement rules read cells as they read block coordinates today, so belts, splitters and machines keep their lane and footprint logic.
- A frame never re-tangents. Joining has no tolerance maths (decided): a foundation placed by snapping to an existing frame inherits that frame exactly and joins it, a foundation placed free starts a new island, and two existing frames never merge. The terrain under a frame is not changed by placing it; a fill under tool and supports are the player's.
- A sealed room is a flood fill through a frame's cells bounded by floors, walls, hatches and windows, recomputed when one of them changes; a room holds an air budget. Stations are frames without ground under them, in a body's orbit.

## Belts and pipes between frames

- A pole is a free entity with a world position and a facing. A run between two endpoints (pole to pole, or pole to a frame cell's port) is a curve derived from the endpoints and their facings, a cubic with the facings as tangents, constrained as Satisfactory's are: incline or turn, never both at once, within a maximum span and slope in data, with a preview before the second press. Its arc length is computed by fixed point subdivision, so every machine agrees on it.
- The simulation keeps items as a distance along a belt line and never sees the shape; the curve maps a distance to a point for the renderer, which sweeps the belt mesh along it, and for collision. Pipes use the same poles and curves.

## Multiplayer: lockstep

- The model is Factorio's: every machine runs the whole simulation; each player's input frame is stamped with the tick it belongs to and relayed through the host; a tick runs when every player's inputs for it are present, with a latency window set from the round trip measured at join (about the round trip in ticks plus one) in which only the local player's movement and camera are simulated ahead and reconciled (decided; the brushes join the prediction if a brush start feels late in play). A joining player receives the save and catches up by running ticks fast. The host relays and has no authority; a headless dedicated server is the game without a window, which the test suite already runs.
- The desync check is the state hash the benchmark compares today, taken every few seconds and compared across machines. Everything a tick reads must be the same on every machine, which includes the loaded chunks: the simulated set of chunks is derived inside the tick from every player's position, and a machine whose worker has not generated one of them yet stalls its tick until it has (generation is deterministic from the seed, so no chunk data crosses the network, only the save's deltas at join).
- All writes into the simulation become queued inputs applied at the start of a tick (the screens' writes of 0166, the command socket's edits, chunk arrivals as the event that a chunk is ready). Terrain edits made inside a tick are queued and applied at the end of the tick in a fixed order (decided), so every system reads one consistent world and the writes have one rule with the queued inputs.
- Transport: TCP for the first slice, since it is the simplest correct choice and a factory game tolerates its latency; UDP with a reliability layer if measurement says so later.

## Split screen

One simulation, up to four local players, each with a viewport: a camera, a HUD, screens, a selection and an input device. The groups of `Frame_State` (0158) split cleanly: the interaction and presentation groups become one per viewport, the developer and reload groups stay global; the UI contexts are per viewport; of the frame requests, the ones that belong to a screen are per player and the ones that belong to the game (quit, reload) are global. The render pass runs once per viewport with the level of detail doing the saving. Gamepads are per viewport through SDL as today; the touch overlay drives one viewport, so a phone is one remote player.

## What changes per cluster

- world: rewritten. Field storage and generation, meshing and level of detail, light, water, collision, frames and curves. The chunk codec and the streaming workers are the parts that carry over in shape.
- simulation: placement on frame cells instead of block coordinates, the arm's reach and cycle, belt lines with an arc length, players with a frame and an up, every write through queued inputs. The kinds, the networks and the planner stay.
- content: the block table becomes a material table (density behaviour, tool tier, tint, texture parameters, grain); machines get footprints in frame cells and a mesh; new tables for planets and bodies, frames, poles, curves, brushes.
- presentation: the field mesher and its shader (triplanar, blended materials, the gentle light curve), the arm animation, swept belt meshes, the globe, the viewports.
- ui: viewports and their contexts; the world settings gain the mode, the spacing and keep inventory.
- loop: sessions with several players, the lockstep driver, the server mode, the simulated chunk set.
- platform: the network transport and the server's entry point.

## The first slice (M13)

The slice is PLAN.md's M13, written as items 0168 to 0179: one large planet generated lazily, the slope walk under radial gravity, two brush sizes digging and placing with item yield, one basin of conserving water, one torch in a dug cave with the new falloff, one foundation with a drill, an arm and a belt into a chest, a day and a night, and lockstep between two machines plus a split screen pair with the state hash as the check. The items: 0168 the field's storage and generation; 0169 the mesher and level of detail; 0170 the player on the field; 0171 the brushes and the item yield; 0172 the water field; 0173 the field light; 0174 frames and placement; 0175 the arm; 0176 curves on poles; 0177 lockstep; 0178 viewports; 0179 the slice's content and world settings.

## Decided in the design session (2026-10-02)

The user took every recommendation: surface nets with skirts; sky light by a radial march cached as the sky channel; one byte of density beside a material and a tint byte; frame joining by snapping only; terrain edits queued to the end of the tick; a latency window from the measured round trip predicting only the local player's movement; 8 km as the default radius with the slice played at 4, 8 and 16 km. No section was reopened.

## Sequencing on `main`

The field world is built as new files beside the block files and is reachable through tests and a developer command until the frames (0174) switch the simulation's grid to frame cells and the slice (0179) switches the session to the field world. The block files are deleted in M14 once the content has come over. This is not a second world type for the player, it is the order the rewrite lands in without breaking the build between items.

## Verify

The brief is done when the user has agreed to each section or marked it open here, and M13's work items are written from it with their own verify lines; the slice itself is verified by M13's statement in `PLAN.md`.
