# 0237: The ground game on the smooth world (design brief)

Status: designing (2026-10-04, draft one sent to the user, the open questions await their answers)

Milestone: M14 The ground game on the smooth world ([PLAN.md](../../PLAN.md)); its verify is couch test 6. The decision this brief serves is `doc/log/2026-10-04.md`, The field trial is finished. This brief is the technical reading of M14 in the shape of [0167](0167-smooth-world-engine-brief.md): what stands, how each piece works, what it costs, what is open. Nothing here is implemented. Numbers are read off the tree and the logs unless marked "estimate" or "not verified"; recommendations are marked (mine).

## The direction (user, 2026-10-04)

"I think we've come to a point where we can say that this new field render and look of the game probably is viable. It becomes a bigger beast and it requires a slightly different art direction, but it can work, so lets say the trial is finished and we can move on with the rest of the big redesign and game content plan."

And, put at the top of M14's priority list the same day: "On the top of the priority list, we need to fill the world with sprawling colors and biomes, make it feel alive, and not just a ball of dirt like its now. I think the current textures are very smudgey and not great to look at, can we make it match the new art direction we've worked up with the new furnace and pod? Higher resolution? Maybe even cel shaded or some other cool technique?"

M14 turns the slice into the first third of the game on the sphere (PLAN.md, M14): every machine of the current content placed on foundation frames at its real size, belts and pipes on poles between islands, veins and outcrops across the sphere, deep veins and caves, water for the pumps and hydro, quest chapters 1 to 7 played from the pod, the arm model as the inserter, the machine models remade one at a time in the art direction's look, the dev kits and the chapter tests on field worlds, the benchmark sizes 1 to 16 on frames, the play build on the field, and the block world type removed at the end. The world's look comes first, by the user's word.

## What stands after M13

The field build since 0179, with what landed after it (0180 to 0236, `doc/work/done/`):

- The field and its session: `world_field.odin` (samples of density, material and tint, 32 cubed chunks), `generation_planet.odin` (relief octaves, the `relief_shape` ledges, terraces and basins of 0189, the crater of 0199), `simulation_field.odin` (the tick, the spawn in the pod's cabin), `simulation_field_chunk_set.odin` (the simulated set, 125 chunks round each player, about 1.3 ms a tick for one player in the debug build, `doc/log/2026-10-03.md`), `simulation_field_save.odin` (`field.bin`, the field tables, the restore off the main thread of 0185). New World and Load start a field session (`session_plays_field`); a block world save is refused by the title (`saved_world_plan`).
- Mesher, light and water: surface nets with skirts (`world_field_mesh.odin`, `world_field_lod.odin`), the field light with a sky channel (`world_field_light.odin`, `data/lighting.sjson`), the conserving water field with its sea, one spring and a per sample flow (`world_field_water.odin`; the flow is not saved).
- The player: `player_field.odin` with the slope walk, step, mantle, crouch (0218), walkability over small steep ground (0203), prediction under the lockstep window (0182), the 6 m reach (0219).
- Frames and placement: `world_frame.odin` (`Frame_Table`, the per cell occupant index), `entity_frames.odin` (`place_on_frame`, the field's queued placements), foundation tiers and blocks (0193, 0196), the centre rule and the placement editor with the tools radial (0215, `ui_placement_editor.odin`), machines on bare ground that wear out (0201, `machine_wear.odin`), pick up on the field (0195), the configure widget (0202).
- The arm: `inserter_reach_on_frame` turns `reach_millimetres` into cells; its voxel parts and pose (`model_arm.odin`, `render_arm.odin`); every inserter record shares the `arm` model.
- Runs on poles: `belt_run.odin`, `belt_run_placement.odin` (cubic curves, integer arc length, the incline or turn rule). A pipe run draws but joins no fluid network ([logistics.md](../logistics.md), Runs).
- Lockstep and viewports: `lockstep.odin`, `session_network.odin`, every game hosts and the LAN lists it (0188), a joiner restores as a follower (0190), up to four viewports (`viewport.odin`).
- Veins and the pod: three starter veins round the home (`generation_planet_veins.odin`, `PLANET_STARTER_VEIN_MATERIALS`), the pod in its crater with hatches, locker, bench and oxygen generator (`entity_pod.odin`), the locker as the reward target (0210), the arrival (0200), the airlock as camera shutters (0231), collision volumes authored with the model (0230, `world_frame_body.odin`), trees as a generation function with felled keys saved (0197).
- Models: the OBJ pipeline and kit (0204, 0205), the workbench (0207), point lights clipped to a machine's box (0224, 0229), the furnace (0212, 3173 triangles) and the pod (0221, 25488) from sealed labs. Of 62 machine records, 27 have an OBJ model, 24 a voxel model (the five inserters share the arm's) and 11 none (belts, pipes, foundations, the belt pole) (`data/machines.sjson` against `data/models/`, counted by script).
- Touch: the virtual gamepad (0115 on), the crouch button (0227), the GameSir fixes (0235, 0236).

What of the block world is still in the tree and who depends on it:

- The world storage, light, water, mesher, streaming and generation of blocks (`world_chunk.odin` to `world_streaming.odin`, the block `generation_*.odin`, `landing_pad.odin`), the block player (`player.odin`, `player_collision.odin`, `player_interaction.odin`), the belt drag (`belt_placement.odin`), `render_chunks.odin` and `render_water.odin`: about 10,000 lines over the 39 files I counted, not all of each file block only.
- Frame 0 (`BLOCK_FRAME`, 25 files name it), on which the block placement, the `inserter_reach` rule and the fluid networks run.
- Tests: 53 test files name a block world type (`Chunk_Coordinate`, `world_set_block`, `world_get_block`, `Block_Registry`, by grep), among them the chapter tests 2 to 8 (none names the field), the systems tests and the save tests; most build content through `make_test_content`.
- The benchmark (`benchmark_factory.odin`): its four modules stand on a block floor and mine block veins; sizes above `BENCHMARK_FIELD_LARGEST_SIZE` (1) are refused (`benchmark_size_problem`).
- The field session draws no weather, particles or ambient life and plays no cues or machine sounds (`draw_field_scene`; `loop.odin` calls them on the block path only; [presentation.md](../presentation.md), The field session); the command socket answers about the block world (0183).
- The power network compares pole origins as cells with no frame (`power_network.odin`, `supply_volume_origin`; read in the code), so poles on two frames do not connect correctly; the fluid networks connect pipes by cell on frame 0, a segment's height is its cell's y ([fluids.md](../fluids.md)); loose items are frame 0 only (0195's log); the offshore pump checks block water (`offshore_pump_has_water`) and the hydro turbine block water levels (`power_machine.odin`); a bore drill is refused on every frame (0179's log).

## The world's look

The user's first ask. What the ground is today, read in the code:

- Tiles: one 16 by 16 tile per material (`ATLAS_TILE_SIZE` 16, `generate_ore_tile`, `data/textures/field_materials.sjson`: flecks of crystal size 1 over a ground colour), uploaded with mipmaps and trilinear filtering (`upload_field_material_tile`). `field.fs` spreads a tile over 2 m (`tile_metres`), so a texel is 125 mm.
- Where the smudge comes from: a 125 mm texel magnified with bilinear filtering is a blur at walking distance; the near and the far scale are mixed half and half at every distance (`material_color`), which halves the contrast of each; the three projections cross fade on every slope (normal to the fourth power); the seven materials blend by per vertex weights over a metre at 1 m spacing; the colour is the tint times two over mid tone tiles, so the tiles carry little of the look.
- Colour: the tint is a hash per 256 m cube (`planet_tint`, `TINT_REGION_METRES`) into four brown palette entries of `home` (`data/planets.sjson`), averaged per mesh cell (`field_cell_look`), so neighbouring cubes meet at hard edges (0169's log). The tint is saved in `field.bin` and not hashed.
- No biomes on the field: temperature and moisture exist only in the block generator (`generation_biome.odin`, `data/biomes.sjson`, 14 biomes with `bird_density`, top and filler blocks). Field materials are topsoil, stone, deep stone, bedrock and three ores (`Field_Material`, `data/materials.sjson`).
- Light: the brighter of the block light and the sky light times `daylight`, a sun term with `ambient_share` 0.45 (`FIELD_SUN_DIRECTION`, fixed), fog to `FIELD_FOG_COLOR`. Machines are flat shaded by a fixed gradient (`MODEL_SHADE_BASE`, `MODEL_SHADE_GRADIENT`) and lit by the open sky (`Model_Frame.open_sky`), so the ground and the machines do not share a sun.
- Alive: one pine species in groves (0197, 128 m draw distance, at most 256 trees, `FIELD_TREE_DRAW_LIMIT`); no ground cover, no animals, no weather.
- Cost today: 42 tile reads a fragment (seven materials, three projections, two scales; [presentation.md](../presentation.md), Field meshes), flagged for the phone in `SUGGESTIONS.md`.

The parts, in the order I would land them (mine: cheap and visible first):

1. Higher resolution tiles with a grain per material (0238). Change: a field tile size of its own (256 by 256 proposed, the block atlas keeps 16), the generator per material in data (grain, mottle, stone courses, crack lines, pebbles; DESIGN.md's "sand smooth, rock faceted"), the far scale as a macro brightness variation rather than a second copy of the tile, a sharper projection blend. Presentation and content only, no save or hash change. Cost: 7 tiles of 256 KB plus mips, about 2.4 MB (estimate); generation at load not measured; the 42 reads stay until part 3. Open: the size (128, 256, 512), generated against painted images, the texel density against the machines' detail.
2. Climate and biome colour across the sphere (0239). Change: temperature and moisture as integer noise on the sphere plus latitude and height (as the relief is sampled, no pole singularity), a biome table per planet in data with a palette per biome, and the colour blended smoothly per vertex from position instead of the 256 m cubes. Seam: the colour is presentation, computed in the mesher from the position and the planet record (the tint byte stays for DESIGN.md's tint of dug material and is no longer the ground's colour). The climate function lives in the generation cluster because the veins (0249) and the ground materials (0241) read it too. Cost: a few noise reads per vertex on the mesh workers. Open: the home world's "two biome families", the palettes, the scale of a biome (hundreds of metres at 8 km).
3. One texture array for the materials (0240). Change: the materials in a `sampler2DArray` and each vertex carrying the ids and weights of its four heaviest materials, so the shader reads 4 materials whatever the material count; this lifts today's limit (four slots plus three ore weights in the free attributes, `FIELD_TEXTURED_MATERIAL_COUNT`, `field_material_slot`) before part 4 adds materials. Cost: 24 reads a fragment instead of 42; texture arrays are not used in the tree today and raylib 6.0's support for them is not verified (an atlas with padding is the fallback). Presentation and world (the mesher's vertex layout); no save change.
4. Biome ground materials (0241). Change: new `Field_Material` values appended (sand on beaches and dunes, clay in wetlands, snow and frozen soil, red rock, a grass soil), each with an item, tool tier and dig rate in `data/materials.sjson`, placed by the climate and the height. Simulation: digging yields them, so the chapters' sand and clay come from the ground (`data/items.sjson` has sand, clay and gravel). Save: material bytes keep their meaning since values are appended; unedited ground of an old world regenerates with the new materials (a behaviour change, one log line, as 0197 and 0199 did). Open: the list, and whether slag and concrete placed by a quest are field materials (chapter 5).
5. Ground cover (0242). Change: grass tufts, flowers, reeds, stones and boulders as small instanced meshes scattered by a hash of position on the surface, per biome, in regions cached like the trees (`update_field_tree_cache`), swaying with a wind phase from the clock, removed where the ground was edited (the presentation reads the chunk's modified flag). Simulation: nothing, it is presentation seeded by position; boulders that block the walk would be trees' kin and are left out (mine). Cost: draw calls (raylib's instanced draw is not used in the tree today); a cap per viewport and a distance as the trees have.
6. Ambient life and sound (0243, folds 0181). Change: `ambient_life.odin` (pure in seed, tick and camera) reads the field's surface and the biome's `bird_density` instead of block columns: birds, insects over flowers, fish shadows in field water; the footsteps by material and the biome ambience of 0181. Presentation only; DESIGN.md's no perceivable repetition holds (clusters, varied pauses).
7. The shading trial (0244), behind a setting, judged on screenshots. Candidates: (a) faceted rock: the face normal from the screen derivatives of the position for rock materials, smooth normals for soil and sand, so the rock speaks the machines' flat shaded language; (b) one sun: the model shader takes the sun direction and the field's light at the machine, so a machine darkens with the ground at night and its lit side matches the slope beside it; (c) a toon ramp: the sun term quantised into three or four bands with a narrow soft edge; (d) outlines: an edge pass on depth and normals over the viewport's render texture (split screen already draws into one; one viewport would need one too). Repetition: on a smooth field a toon ramp's band edges are iso lines of the slope, and on the terraces of 0189 (1.2 m rises) every riser makes the same band edge, a stripe at the terrace period; the trial checks screenshots of the terraces, a basin's rim and the crater at the three radii, and breaks the edges by the macro variation of part 1 if they stripe. Cost: (a) and (b) a few instructions; (d) a full screen pass per viewport. Open: which ones to trial and whether the result becomes the default.
8. Sky and fog per planet palette, and the planet preview at the home (0184) so the look items' screenshots show the pod, an outcrop and a biome edge; 0184 lands first in this stream. Weather on the field waits for M15 (DESIGN.md: weather's mechanics are survival's).

The order decided at the review (main agent, 2026-10-04): 0184 first for the screenshots, then 0239 (the colour and the biomes are the user's first words and the largest change on screen, and they do not need the new tiles), then 0244 (the shading trial early, since the technique decides what a tile should carry: a cel look wants flat colour with sparse geometric detail, a realistic look wants structure in the tile), then 0238, 0240, 0241, 0242 and 0243. The sky and the fog per planet palette go into 0239's scope. Weather's look on the field (rain, clouds, wind, the block world's `render_weather.odin` moved over) is question 16 below; its drains stay M15's.

## Machines on frames at real footprints

Exists: footprints in cells of `data/machines.sjson`, bounded by `MAXIMUM_FOOTPRINT_SIZE` (12, `machine.odin`, read by `validate_footprint`); the centre rule of 0215; `direct_placement_limit` (2 by 2 by 3) beyond which the editor's outline and anchor place; bare ground flatness over the footprint (`bare_ground_is_flat`, 250 mm); a machine saved at an older size keeps its box until picked up (`entity_keeps_saved_size`, 0212). The rule's text lives in [content.md](../content.md), Foundations: footprints count cells, so on the 500 mm frame every machine but the furnace and the pod stands at half its block size.

Change: every record gets its real footprint. An OBJ model is in cells and not scaled, and a model script stops on a changed footprint (`expect_footprint`), so either each machine's footprint lands with its lab item (the furnace's way) or one data pass lands them all with a temporary uniform model scale per record until the machine is remade. The ports (`machine_fluid_ports.odin`), the drill's bottom cells over a vein, the arm's pick and drop cells and the panel follow the footprint already. `MAXIMUM_FOOTPRINT_SIZE` rises (the launch pad). Cost: the occupant index holds one map entry per cell, 1200 for the furnace; a size 16 factory at real sizes may hold hundreds of thousands of cells (estimate, not measured). Old saves: the 0212 rule covers them, no layout change.

The table (today's cells are the block world's metres; the proposals are mine, to be set by each machine's lab where it differs):

| Machine | Today, cells | Today at 500 mm | Proposed, cells | Proposed, metres |
| --- | --- | --- | --- | --- |
| wooden_chest, iron_chest, schematic_crate | 1x1x1 | 0.5 m cube | 2x2x2 | 1 |
| stone_furnace | 10x10x12 | 5x5x6 m | kept (0212) | 5x5x6 |
| steel_furnace | 2x2x2 | 1 m cube | 10x10x12 | 5x5x6, swaps in place for the stone one |
| belt (six records), splitter, pipe, belt_pole, foundations | 1 wide | 0.5 m | kept | 0.5 m belt, lanes as today |
| inserters (five records) | 1x1x1 | 0.5 m base | kept | 2 m reach, 4 m long inserter |
| burner_mining_drill | 2x2x2 | 1 m | 6x6x6 | 3x3x3 |
| electric_mining_drill | 3x3x3 | 1.5 m | 10x10x8 | 5x5x4 |
| bore_drill | 4x4x4 | 2 m | 14x14x14 | 7x7x7 |
| offshore_pump, tar_pit_pump | 2x1x1 | 1x0.5x0.5 m | 6x4x4 | 3x2x2 |
| pump | 2x1x1 | 1x0.5x0.5 m | 3x2x2 | 1.5x1x1 |
| boiler | 3x2x2 | 1.5x1x1 m | 8x6x6 | 4x3x3 |
| steam_engine | 3x5x2 | 1.5x2.5x1 m | 6x12x6 | 3x6x3 |
| storage_tank | 3x3x3 | 1.5 m | 8x8x8 | 4 |
| flare_stack | 1x1x3 | 0.5x0.5x1.5 m | 2x2x16 | 1x1x8 |
| combustion_generator | 3x2x2 | 1.5x1x1 m | 8x6x6 | 4x3x3 |
| fuel_generator | 2x2x2 | 1 m | 4x4x4 | 2 |
| hydro_turbine | 2x2x2 | 1 m | 6x6x6 | 3 |
| small_pole, big_pole, substation | 1x1x3, 1x1x6, 2x2x3 | 1.5, 3, 1.5 m high | 1x1x8, 2x2x24, 4x4x10 | 4, 12, 5 high |
| power_switch, lamp | 1x1x1 | 0.5 m | 1x1x2, 1x1x4 | 1, 2 high |
| assembler_1 | 3x3x2 | 1.5x1.5x1 m | 10x10x8 | 5x5x4 |
| crusher, recycler | 2x2x2 | 1 m | 6x6x6 | 3 |
| washer | 3x2x2 | 1.5x1x1 m | 8x6x6 | 4x3x3 |
| alloy_furnace | 3x2x2 | 1.5x1x1 m | 10x8x10 | 5x4x5 |
| stone_cutter | 2x2x2 | 1 m | 4x4x4 | 2 |
| stone_cutting_table | 2x1x2 | 1x0.5x1 m | 4x2x2 | 2x1x1 |
| wood_gasifier | 2x2x3 | 1x1x1.5 m | 6x6x10 | 3x3x5 |
| refinery | 5x5x3 | 2.5x2.5x1.5 m | 16x16x16 | 8 |
| cracking_unit, chemical_plant | 3x3x3 | 1.5 m | 10x10x12, 10x10x10 | 5x5x6, 5x5x5 |
| electrolyser | 3x3x3 | 1.5 m | 8x8x8 | 4 |
| core_sample_drill | 1x1x2 | 0.5x0.5x1 m | 4x4x8 | 2x2x4 |
| lab | 3x3x2 | 1.5x1.5x1 m | 8x8x6 | 4x4x3 |
| launch_pad | 9x9x2 | 4.5x4.5x1 m | 40x40x4 | 20x20x2 |
| drop_capsule | 1x1x2 | | goes with the block world | |
| pod, pod fixtures, pine_tree | | | kept | |

What it costs the player: founding a 10 by 10 machine takes 100 foundation cells against the 16 of `starting_items`, and bare ground flatness over 5 m is about 2.8 degrees (`SUGGESTIONS.md`, Decisions needed); the starter vein discs are 3 to 5 m in radius (`generation_planet_veins.odin`), so four 3 m burner drills (chapter 3) barely fit on one. Open: the sizes, the scale pass against per machine footprints, the starter foundations and the vein discs at these sizes.

## Belts and pipes between islands

Exists: runs on poles for belts (items keep their distance along the line across a run), and for pipes as a drawn curve only; belts, lanes, splitters and lifts on a frame run as on frame 0; a belt is placed on a frame one at a time (the drag is the block world's, [logistics.md](../logistics.md)).

Change: (a) power across frames (0246): a pole's node keeps its frame and its world position, wires reach by world distance, supply volumes are boxes in the pole's frame tested against a machine's cells in that frame; (b) fluids on frames (0247): pipes connect by cell within a frame, a pipe run joins the two networks at its ends as a segment of its arc length, and a segment's height is its distance from the planet's centre (fixed point) rather than a cell's y, so the pump head of 0139 means the same on every frame; (c) a way to lay many belts on a frame from the field (a line or drag tool): this is a binding question for the main agent and is not designed here; (d) loose items on frames (0248) so a pick up into a full inventory can spill as 0195 asked. Underground belts do not exist in `data/machines.sjson`; they are not in M14 (mine), runs bridge instead. Save: the pole node's frame and the run's network membership are derived at rebuild; no layout change expected for (a) and (b), a remap for (d) if loose items gain a frame field (read by name, as 0218's fields are). Cost: the networks rebuild on placement as today.

## Veins, outcrops, deep veins and caves on the sphere

Exists: three starter discs round the home with reservoirs from `data/veins.sjson` at registration (`register_planet_veins`, `vein_under_world_position`), outcrops replacing the top 2 m; the block world's vein types (13, biome gated), size classes and richness by distance; no caves, no deep veins, no crates on the field.

Change: (a) veins across the sphere (0249): vein discs planned per region on the sphere from the seed, typed by the climate of 0239 (the block world's biome lists), sized by the size classes and the distance from the home, registered when their region enters the simulated set (the arrival list of 0165, now the chunk ready command); the starter discs stay. (b) Caves and deep veins (0250): cave tubes as three dimensional integer noise in `planet_sample` below the topsoil, deep veins under surface veins between the block world's depth bounds, the bore drill on a frame over one (`bore_drill_vein_under` on the sphere), schematic crates in cave pockets, the prospecting tools on the sphere. Save: discs are generation (record their parameters in the world record as the crater is); reservoirs are saved as today. Cost: one hash per region for the plan; the caves add noise reads per sample at generation (not measured, the block generator's carving is the guide). Open: vein spacing and count over an 8 km sphere, caves' share of the ground.

## Water and hydro on the field

Exists: the field water with sea, springs and a per sample flow; pumps and the hydro turbine read block water. Change (0251): the offshore pump stands with its intake cells over field water and draws litres from the samples under it (the sea is infinite, a pond conserves and drains, DESIGN.md); the hydro turbine reads the flow of the samples in its cells (`water_flow`, so the flow joins the save or is recomputed deterministically on load, which the item decides); placement checks read the field. Simulation and world clusters; the water's tick order is the sample order, so lockstep holds. Cost: a pump's draw wakes the samples it drains; measured in the item.

## The quest chapters 1 to 7 from the pod

| Chapter | What the field lacks for it |
| --- | --- |
| 1 | Nothing structural: the slice's chapter plays today. The furnace at 10 by 10 needs 100 foundation cells or flat bare ground. |
| 2 | Sand for glass discovery and chapter 4's glass (0241); a burner drill on the copper disc. |
| 3 | Laying belts on frames from the field (a binding question); four drills on starter discs at real sizes. |
| 4 | Field water for the offshore pump (0251); poles across frames (0246); sand dug for five glass (0241). |
| 5 | Tin and zinc veins (0249; copper drills also yield cassiterite and sand, `data/veins.sjson`); the `place` objectives of slag and concrete as items (0241 decides how they count). |
| 6 | Pumps uphill by radial height (0247); tar pits as a generated feature (the block world's `tar_flats` biome); refinery and chemical plant at real sizes. |
| 7 | Assays of two veins (0249); core samples, a bore drill and deep units (0250); bauxite and gold quartz deep veins; belt lifts on frames; hydro (0251); a substation grid (0246); a cave schematic (0250). |

Chapter 8 (the rocket program) belongs to M16 by PLAN.md, but its test plays on the block world and must move before the block world goes. The dev kits (`data/dev_kits.sjson`) are item lists and world agnostic; what is block bound is the chapter tests and `--chapter`'s setup. "The dev kits rebuilt as field worlds" (mine): each chapter test starts a field world at the home with its kit, lays its factory on frames over registered veins through the placement commands, and plays the chapter, which is also the dev kit a developer starts with `--chapter`.

## The arm as the inserter

Exists: on a frame every inserter is the arm with `reach_millimetres` and a cycle laid over the inserter's (0175); its parts are voxel files (0206 lists `arm.obj` as its group form). Change (0252): the arm made in a sealed lab from a booklet page (the user's 2026-10-02 words: an elbow, a folded rest, the look Factorio's inserter reaches for), its base at real size on its one cell or a larger footprint (open), the five tiers told apart by the clean and rough ratio. The pick and drop rule, the reach and the lanes stay. Presentation and content only.

## The machine models remade

Exists: the lab by hand (`tools/model_lab/make_furnace_lab.sh`, `make_pod_lab.sh`), 0214 to make it a tool, 3200 triangles and 8 materials a body. Change: one lab per machine, never a batch (0206's hold, user 2026-10-03): a booklet page (rounds, a reference sheet), a lab, the user's sign off, an implementer's integration. Queue (mine, the order a new player meets them): the arm, the burner mining drill, the wooden and iron chests, the belt pole and electric poles, the stone cutting table and cutter, the electric drill, the boiler and steam engine, the offshore pump, the lab, the assembler, then chapter 5 to 7 machines. Each item sets its machine's real footprint where the scale pass guessed. The voxel reader goes in 0206 once every model is OBJ. Cost: rounds of images (about 10 to 14 cents each, `doc/art/booklet.md`) and one lab session per machine.

## The benchmark 1 to 16

Exists: size 1 on the field with the modules on a block floor; size 1 at 1.68 ms a tick in the debug test build, of which 1.54 ms the field (`doc/log/2026-10-03.md`); the block world's size 16 at 0.27 ms in release ([content.md](../content.md), Tick cost baseline). Change (0256): each module copy on a frame of its own on the field round the home, its veins added on the sphere, its blueprint in frame cells at real footprints; sizes up to 16 again. A size 16 layout at real sizes spans several hundred metres (estimate), and a frame never re-tangents: at 440 m from its origin on 8 km the ground falls 12 m below the plane (d squared over 2R), hence one frame per copy. The benchmark is heavy: it runs only in the window of the global rules. Open: whether the entity tick reads anything outside the simulated set (not verified), the launch pad module (SUGGESTIONS.md).

## The play build switch

The installed play build has started field worlds since 0179 (every landing installs it) and the title refuses block saves. What is left is the block world's removal; no item of its own (mine).

## The block world's removal

Order, each commit green: (1) the tests that build block worlds move onto frame worlds through a test helper that makes a field world with a frame at the home (0257), the chapter tests with the chapter items; (2) the benchmark onto frames (0256); (3) the block simulation paths go: the block player, the block placement and the belt drag, `BLOCK_FRAME` and the `inserter_reach` rule, the capsule and landing pad, loose items on frame 0 (after 0248); (4) the block world storage, light, water, mesher, streaming and generation, `render_chunks.odin`, `render_water.odin`, the block parts of weather and ambient life (after 0243), the save's region files (the title keeps refusing an old save by name); (5) `doc/code_map.md` re-recorded (the world to simulation and content to world edges fall), `doc/architecture.md` and the cluster table rewritten (0258). The world cluster keeps the field and frame files; 0146's cut stays the guide.

## The art direction on the smooth world

The booklet of 0211 and DESIGN.md's rules stand. What the smooth terrain asks of them, as questions:

1. The ground's palette against the machines'. The booklet's images stand machines on red desert, pale ground, orange plants and crystals (round one to five); the machines are muted iron, rust, stone and pale alloy. Recommendation (mine): saturated but mid value biome colours, so rust and pale alloy read against every biome; the palette chosen on one screenshot of the furnace and the pod on each biome.
2. Soft ground against flat shaded machines. Recommendation (mine): rock faceted by face normals, soil and sand smooth (DESIGN.md's grain per material), so the hard surfaces share the machines' language and the soft ones stay Astroneer's.
3. One light for both. Recommendation (mine): the model shader takes the sun and the field's light at the machine, so the gentle shading reads as one world; the flat shade gradient stays as the fill.
4. Machine scale on the soft ground. A 5 m furnace on a slope stands on foundations that leave the ground. Recommendation (mine): foundations get a modelled tile per tier and visible legs drawn down to the ground under a frame's lowest row (presentation only, no collision), so a platform reads built, not floating.
5. Poles and runs. Recommendation (mine): the belt pole and the electric poles go early in the model queue, since they stand in every shot between islands.
6. The pod as the reference. Recommendation (mine): the pod's and the furnace's palette entries are the reference for every later model and for the ground's value range, and the pod's interior light share (0.25) sets how dark a cabin may be against a day sky.
7. Cel shading. Recommendation (mine): a trial behind a setting (0244), never the default without the user's verdict on screenshots of terraces, a basin and the crater.

## The items

Five streams; items in one stream touch the same files and land in series, the streams run in parallel within the four subagents. Clusters are those of [code_map.md](../code_map.md).

| Item | Title | Scope | Clusters | Depends on | Stream |
| --- | --- | --- | --- | --- | --- |
| 0184 | The planet preview at the home (open) | screenshots for the look items | loop | | A |
| 0238 | Terrain tiles at a higher resolution with a grain per material | tile size, grain generator, macro variation, sharper blend | presentation, content | 0244 (the user's verdict on the technique) | A |
| 0239 | Climate and biome colour across the sphere | climate on the sphere, biome palettes per planet, smooth colour from position, sky and fog per palette | world, content, presentation | 0184 | A |
| 0240 | The terrain materials in one texture array | four material ids and weights a vertex, 24 reads | presentation, world (mesher) | 0239 | A |
| 0241 | Biome ground materials | sand, clay, snow, red rock, soils; items and digging | world, content, simulation | 0240 | A |
| 0242 | Ground cover on the field | instanced scatter per biome, wind sway | presentation, loop | 0239 | A |
| 0243 | Ambient life and sound on the field | birds, insects, fish, footsteps, ambience (folds 0181) | presentation | 0241 | A |
| 0244 | The shading trial | faceted rock, one sun, toon ramp, outlines, behind a setting | presentation, ui (setting) | 0239 | A |
| 0245 | Machines at real footprints | the table above, the footprint bound, a temporary model scale | content, simulation | | B |
| 0246 | Power networks across frames | pole nodes in world positions, supply in the pole's frame | simulation | 0245 | B |
| 0247 | Fluids on frames and pipe runs | per frame pipes, runs join networks, radial height | simulation | 0246 | B |
| 0248 | Loose items on frames | spill on a full pick up, frame cells | simulation | 0247 | B |
| 0249 | Veins and outcrops across the sphere | vein plan per region by climate and distance | world, simulation | 0239 | C |
| 0250 | Caves, deep veins, the bore drill and crates | caves in `planet_sample`, deep veins, bore drill, crates, prospecting | world, simulation | 0249 | C |
| 0251 | Pumps and hydro on the field's water | offshore pump draw, turbine flow | simulation, world | 0250 | C |
| 0214 | The sealed modelling lab as a tool (open) | | tools | | D |
| 0252 | The arm in the lab | the inserter's model | presentation, content | 0214 | D |
| 0253 | The burner mining drill in the lab; the queue after it | one item per machine, written as each lands | presentation, content | 0252, 0245 | D |
| 0254 | Chapters 1 to 4 on the field | quest fixes, chapter tests and dev kits as field worlds | content, simulation | 0245, 0246, 0241, 0251 | E |
| 0255 | Chapters 5 to 7 on the field, chapter 8's test | as 0254 | content, simulation | 0254, 0247, 0250 | E |
| 0256 | The benchmark on frames, sizes 1 to 16 | modules per frame, veins on the sphere | tools, content | 0249, 0247 | E |
| 0257 | The block world's tests onto frame worlds | the test helper, every block test moved | tests across clusters | 0256 | E |
| 0258 | The block world removed | the order above, code map and docs | all | 0257, 0255, 0243 | E |

Start at once (main agent): 0184 (A, loop) and 0214 (D, tools), both open items already approved, with the designs of 0239 and 0245 ahead in the other slots once the questions are answered. Landing order: 0184, 0239, 0214, 0245, 0244, 0246, 0252, 0238, 0247, 0240, 0249, 0241, 0242, 0248, 0250, 0251, 0243, 0253 and its queue, 0254, 0255, 0256, 0257, 0258. Binding questions arise in 0244 (the setting only), 0254 (laying belts on a frame) and 0249 or 0250 (the prospecting tools' controls on the field); the control design is the main agent's.

## Open questions

1. Footprints: one data pass now with a temporary model scale (0245), or each machine's footprint with its lab item? (mine: the data pass now, so the factory plays at real scale from the start.)
2. Belts, pipes, belt poles and the arm's base stay one 0.5 m cell? (mine: yes; a two cell belt breaks the line's cell rule.)
3. The proposed sizes in the table: accept as the scale pass, adjusted per lab? (mine: yes.)
4. The starter foundations against a 10 by 10 furnace: more in `starting_items`, a flatness tolerance per record, or a smaller first furnace? (mine: the couch first, as `SUGGESTIONS.md` says.)
5. The tile size and source: 128, 256 or 512, generated from parameters or painted? (mine: 256, generated, so the editors can tune it in game.)
6. The ground's colour: derived in presentation from position (no save, no hash), with the tint byte kept for dug material? (mine: yes.)
7. The new ground materials: which? (mine: sand, clay, snow, red rock and a grass soil, at most 12 materials in all for the array.)
8. Slag and concrete placed by chapter 5 and 7: field materials raised by a brush, or a foundation tier? (mine: field materials, since they are ground a player shapes.)
9. Ground cover in the simulation: none, and no colliding boulders? (mine: none.)
10. The shading trial: which candidates? (mine: faceted rock and one sun as defaults if they read well, toon ramp and outlines as settings to try.)
11. Ambient animals now, or with the second living world? (mine: now, DESIGN.md lets fauna be scenery.)
12. Vein spacing over an 8 km sphere and the caves' share: the block world's tables as the start? (mine: yes, measured on the couch.)
13. Chapter 8: its test moves to a field world in M14 with no rocket rework, the rocket stays M16's? (mine: yes.)
14. The M13 follow ups: 0180 (dry spawn) and 0183 (socket on the field) into M14, 0191 and 0192 after couch test 6 shows them? (mine: yes.)
15. Laying belts on a frame from the field (chapter 3): the main agent designs the control; is a straight line tool enough? (mine: a line from the first to the second press, previewed, as runs are.)
16. Weather's look on the field now (rain, clouds, wind and the cloud shadow of `render_weather.odin`, presentation only, in 0243's stream), with its drains and mechanics kept for M15? (mine: yes, the sky is half of "alive".)

## Verify

The brief is done when the user has answered each open question or marked it open here, and M14's items are written from it with their own verify lines. M14 itself is verified by couch test 6 (PLAN.md): "Chapters 1 to 7 played through by two players on the couch and one remote, saved and resumed between sessions, at 60 ticks per second at benchmark size 16."

What each item's own verify covers: the look items (0238 to 0244) by headless screenshots at the three radii read by the main agent and the user, the repetition rule checked on each, no state hash change for the presentation only ones and a phone frame time reading for 0240; 0241, 0249, 0250 by generation tests that two machines agree byte for byte and old worlds load with one log line; 0245 to 0248 and 0251 by placement, network and save round trip tests on frames with the state hash; 0252 and 0253 by the workbench and the user's sign off; 0254 and 0255 by each chapter played by its test on a field world; 0256 by `./build.sh bench` and `--benchmark=16` in the benchmark window; 0257 and 0258 by the suite green at every commit and `python3 tools/code_graph.py --check doc/code_map.md`.
