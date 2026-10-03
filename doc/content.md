# Content catalogue

The rules behind the numbers in `data/*.sjson`. Every value lives in its data file, and each file's header comment states the keys, their ranges and the local rules. This document keeps what spans files: units, the stack and price classes, the phase budgets, the gates, the ratio checks, and the authoring rules for textures, models, sounds and text.

- A value is changed in its data file, never copied here. A ratio check below is recomputed when a value it names changes.
- Every number is a guess until the couch tests confirm it. When a phase runs long, lower the cost, not the step count.
- The fluid and power mechanisms are in [fluids.md](fluids.md), belts, inserters and drills in [logistics.md](logistics.md).

## Units

- A tick is a sixtieth of a second (`tick_rate` in `data/game.sjson`). A recipe's `seconds` is its time at speed 1 and a whole number of ticks. `recipe_ticks` truncates to whole ticks, at least one.
- Power in kilowatts and megawatts, energy in megajoules. An item's `fuel_megajoules` is what a machine extracts, with no efficiency factor, except a combustion generator's `fuel_efficiency_percent`.
- Fluids in litres. Fluids are never items and never stack.
- Terrain in cubic metres: one item of a field material is a cubic metre dug or placed whatever the sample spacing (Field materials and brushes).
- Factorio's proportions are the anchor, its absolute values are not: where a ratio matches Factorio it does so on purpose.

## Items

`data/items.sjson`.

- Nothing stacks below 50 (user, 2026-10-01), so a pocket holds a useful amount of anything. Classes: raw material, ore, spoils, blocks, plates, alloys, steel, crushed ore, alumina, sulfur and bitumen 50, slag 100, the other intermediates (planks, gears, wire, circuits, glass, silicon, plastic, science packs) 100, machines, tools, rocket parts (the stack also caps a launch pad slot, and a rocket takes at most 10), thumper charges and schematics 50, the machines placed by the dozen (inserters, belts with ramps and lifts, poles, pipes, lamps) 100. `item_test.odin` pins a plate, a gear and a machine.
- Mining a block yields exactly one item: the item whose `places_block` it is, or whose `mined_from` lists it. `also_mined_from` adds a second drop (gold quartz gives quartz and gold ore).
- Prices in venture credit grow with recipe depth. The classes are in the header of `data/items.sjson`.

### Tools

Tools gate hand mining and nothing else (0051).

- Each block needs a tool tier that climbs with the hardness of the material, from bare hands for soil and wood to an iron pickaxe for deep rock. The tier list is in the header of `data/blocks.sjson`.
- The best `tool_tier` of any item in the inventory or on the cursor counts (`player_tool_tier`), so the geologist's hammer mines at tier 2. There is no speed bonus and no durability. The time is the block's `hardness_seconds`.
- Drills ignore tiers, and the developer cheat speed mines every tier (`effective_tool_tier`). `test_tool_tier_gates_hand_mining` guards the gate.
- On the terrain field the material's `tool_tier` in `data/materials.sjson` gates the brush the same way, against the best tier carried (`field_tool_tier`); `test_a_brush_over_a_harder_material_digs_nothing` guards it.

## Recipes

`data/recipes.sjson`. Its header gives the channels (start, discovery, research, quest, schematic), the byproduct rule and the furnace limits.

- Craft times by kind: machines 2 s, inserters, belts, pipes, poles and chests 0.5 s, tools 1 s.
- A furnace makes one input recipes with at most a slag byproduct. Two input alloys (steel, bronze, brass) are alloy furnace recipes. Every ore smelt and alloy craft gives one slag.
- Low grade ore goes back to ore through the crusher and the washer (the chain is in the header of `data/recipes.sjson`). It smelts directly only through the low grade iron plate schematic.
- Crushers, washers, the alloy furnace and the assembler, among them, are one kind: `crafting_machine` (`data/machines.sjson`).
- The recycler reverses the first recipe that makes its input and returns 25 percent of each input, rounded down.
- The slice's chain (0179): the field yields dirt, stone, deep stone, hematite, chalcopyrite and coal (Field materials and brushes) and no wood until M14, so everything chapter 1 and the first line need is made from those by hand and in the stone furnace: the stone furnace (5 stone), stone bricks and plates in it, the foundation, the belt pole, gears, the burner mining drill, the burner inserter, the belt and the iron chest, as before. The torch, which had no recipe, is made by hand from a coal and a stone (four torches). The wooden chest and the wooden tools still need wood. `test_the_slice_recipe_chain_is_reachable_from_the_fields_yield` walks the recipes from the materials' items.

### Hand crafting

`crafting.odin` (0138). The hand crafts at speed 1, one run at a time. The HUD shows the queue ([hud.md](hud.md)).

- Queuing takes nothing. It plans the crafts against a virtual inventory: the inventory plus what the queued runs make minus what they use.
- An ingredient short by M gets ceil(M / output count) crafts of its hand recipe queued ahead: the first unlocked hand recipe in `data/recipes.sjson` order whose first product is the item. The resolution recurses up to `HAND_CRAFT_PLAN_DEPTH` levels.
- A raw shortage, a recipe cycle or a chain past the depth refuses the whole plan, and a toast names the reason ([ui.md](ui.md), Recipe browser).
- A plan never counts on covering a deficit of runs already queued: an item's planned count stops at zero.
- A craft takes its ingredients when it starts at the front of the queue. A front craft whose ingredient was spent or dropped waits. The next queue action first plans the makers of what the whole front run lacks against the inventory alone and queues them ahead (`plan_front_repair`), or leaves it waiting when the inventory cannot make the item.
- A finished craft whose outputs do not fit waits with its progress kept. Cancelling takes one craft off the newest run and gives back the ingredients of a craft in progress, refused when they no longer fit.

## Phase budgets

Target playtime and what the player owns at the end of each phase. They drive recipe costs. Phases 1 to 4 add up to about two hours forty minutes over two or three sittings.

| Phase | Target | End state |
| --- | --- | --- |
| 1 Arrival | 10 min | Stone, hematite and coal dug, one stone furnace placed, ten plates, a drill, an arm, a belt and a chest placed |
| 2 Workshop | 30 min | 3 stone furnaces, 2 burner drills, 200 plates, first gears, belts discovered |
| 3 Automation | 45 min | One self feeding coal drill, 4 drills feeding 3 furnaces, inserters, chests, ten unattended minutes |
| 4 Power | 75 min | 1 fuel generator, 1 offshore pump, 1 boiler, 2 steam engines, 10 poles, 4 electric drills, 4 assemblers, 2 labs, 5 technologies |

Budgets for phases 5 to 8 come with their couch tests. Planned machines not in the data yet: assembler 2, steel chest and medium pole (phase 5), assembler 3, express belt, stack inserter and science pack 4 (phase 7), science pack 5 (phase 8).

## Technologies and gates

`data/technologies.sjson`: packs times seconds per pack in a speed 1 lab, prerequisites listed earlier in the file.

- One main quest gate per phase, and nothing else waits on it ([DESIGN.md](../DESIGN.md), Research, quests and rockets). Phase 4: the steam engine is a quest channel recipe that chapter 3's main quest unlocks, so until then boilers make steam nothing can use. Phases 6 to 8: `oil_processing`, `deep_mining` and `rocket_program` carry `quest_gate`, labs refuse them, and the main quests of chapters 5 to 7 research them.
- `mining_productivity` and `research_speed` are infinite: each level costs `level_cost_growth_percent` of the one before and adds `effect_percent`.
- The venture's contracts and catalogue are in `data/contracts.sjson`. An orbital survey charts the surface veins within `ORBITAL_SURVEY_RADIUS` of the pad.

## Veins

`data/veins.sjson`: size classes (scattering, deposit, concentration), vein types with their output mix, deep veins at five times the surface class (`deep_units_factor`) for the phase 7 bore drills.

- An outcrop is the visible top of a vein, not its reservoir: hand mining takes outcrop blocks, drills draw from the reservoir under the whole footprint disc.
- Mining a vein's last outcrop block while its reservoir has units makes Mission Control say once per vein that the vein continues below (`mc_outcrop_spent`, 0096). The vein then counts as known: the map keeps its footprint drawn like an assayed one, while the drill panel does not call it assayed.
- A finite vein drained by drills turns its outcrop to `spent_block`.
- The low grade share of a draw rises linearly from `LOW_GRADE_START_PPM` at a full reservoir to `LOW_GRADE_END_PPM` with `LOW_GRADE_END_REMAINING_PERCENT` left (`drill.odin`). Infinite veins stay at the start.
- The starter veins by the landing pad: [quests.md](quests.md), Spawn requirements.

### Veins on the sphere

The terrain field's veins (0179, `generation_planet_veins.odin`): a vein is a disc on the planet, a unit direction and a radius along the sphere of the planet's radius, not voxels.

- The outcrop: within the disc, from the local surface down `OUTCROP_DEPTH_METRES` (2 m), generation makes the ground the vein's ore material (`planet_sample`), never bedrock, so hand mining the outcrop yields the ore through the material table. Below it the strata go on.
- The slice places the three starter veins only, one per ore of `PLANET_STARTER_VEIN_MATERIALS` (hematite, chalcopyrite, coal), round the home direction (the pod's, a parameter of `make_planet_generation`, `DEFAULT_PLANET_HOME` over +y until the planet record carries one): each in its own third of the circle round the home, turned by up to a quarter of the third from a seeded rotation, at `PLANET_VEIN_MINIMUM_DISTANCE_METRES` to `PLANET_VEIN_MAXIMUM_DISTANCE_METRES` (30 to 80 m), with a radius of 3 to 5 m (the scattering class), all from the `Planet_Veins` sub seed. The rest of the sphere has none until M14 scatters veins.
- The discs come from the seed, the planet's radius and the home only, not from `data/veins.sjson`: they shape the ground, which a data edit must not reshape round saved chunks. The reservoir does come from it: `register_planet_veins` makes one `Vein` per disc, of the spawn vein type whose outcrop block has the ore's name (`hematite_ore` is the iron type's) and holding the starter size class's units by the type's mix. A file whose spawn types lack an ore refuses the registration.
- A `Vein` keeps its block footprint and gains the disc (`sphere_centre`, `sphere_radius`, zero for a block world vein), which the save leaves out: the session registers the veins again at start, which keeps a loaded reservoir and restores its disc. `vein_under_world_position` finds the vein whose disc holds a world position projected onto the sphere; a drill on a frame taps it ([logistics.md](logistics.md), Drills).

## Ratio checks

Recomputed from the data. A unit is one draw from a vein, ore or spoil.

- A burner drill draws 18.75 units a minute: 15 hematite on an iron vein. A stone furnace smelts 18.75 plates a minute. Five burner drills (75 hematite) feed four stone furnaces.
- Five electric drills (150 hematite) feed eight stone furnaces or four steel furnaces.
- A belt carries 900 items a minute: the hematite of sixty burner or thirty electric drills, fewer once spoil rides along.
- One boiler (60 L of steam a second) feeds two steam engines (30 L each). One offshore pump (1200 L a second) feeds twenty boilers, so forty engines and 36 MW.
- A boiler burns 1.8 MW, 27 coal a minute. A burner drill on a coal vein draws 16.9 coal a minute and burns 2.25, so the coal loop feeds itself with room to spare.
- The fuel generator lights a coal at 25 percent, 1 MJ, which lasts 13 seconds at its full 75 kW. For the same energy it burns four times the fuel of a boiler and engine: it starts the steam plant and is no substitute for it.
- A speed 0.5 assembler makes 6 science pack 1 a minute. A lab on a 15 second technology uses 4.
- A 30,000 unit deposit lasts one burner drill about 27 hours and ten electric drills 80 minutes. Finite veins matter only at scale, which is the intent.
- A phase 4 base draws about 1.1 MW: 4 electric drills 360 kW, 4 assemblers 300 kW, 2 labs 120 kW, 20 inserters 260 kW, the offshore pump 60 kW, lamps. One boiler and two engines cover it.

## World

- Biomes (`data/biomes.sjson`): a column takes the first biome whose height, moisture and temperature ranges hold it. Temperature is a latitude band along z (`ORIGIN_TEMPERATURE` at the origin, colder towards -z, over `TEMPERATURE_PERIOD`), noise (`TEMPERATURE_NOISE_AMPLITUDE` at `TEMPERATURE_WAVELENGTH`) and a lapse of `TEMPERATURE_LAPSE` per block above sea level (`generation_terrain.odin`).
- Trees (`data/trees.sjson`, shapes in `generation_features.odin`): every log block drops `log` and every leaves block `leaves`, so recipes see one kind of wood. Trees have no roots: log blocks beside a trunk's foot read badly (0083).
- Trees and boulders keep off water and vein footprints. A clearing noise of `CLEARING_WAVELENGTH` keeps about a biome's `clearing_share` free of trees. Trees root at least `LEAF_REACH` off the landing pad, which clears only `LANDING_PAD_CLEARANCE` blocks above itself.
- Felling (`tree_felling.odin`): mining a log drops every log above it as loose items and queues the leaves near the column. Placed leaves decay only when a log near them is felled.
- A queued leaf decays after `LEAF_DECAY_MINIMUM_DELAY_TICKS` to `LEAF_DECAY_MAXIMUM_DELAY_TICKS` unless a log lies within `LEAF_SUPPORT_DISTANCE` (Manhattan), then queues its leaf neighbours. One decay in `LEAF_LITTER_CHANCE` drops leaves and one in `SAPLING_CHANCE` a sapling (no use yet).
- Ground cover (a biome's `ground_cover`, 0082): one hash of the column (the `Ground_Cover` sub seed) picks at most one entry, in order against the running sum of the chances. The cover goes into the cell above the surface when it is still air after trees and boulders and the column is outside every vein footprint. The landing pad clears its own cells, and mining under cover spills it ([hud.md](hud.md), Targeting).
- Ambient life (render only): a biome's `bird_density` and a ground cover entry's `insects` ([presentation.md](presentation.md), Ambient life).

## Planets

`data/planets.sjson` holds the planet records the terrain field generates from (0168; [architecture.md](architecture.md), World generation). The slice ships one, `home`.

- Keys, all required: `id` (at most `MAXIMUM_PLANET_ID_LENGTH` bytes; the New world screen names it by the string `planet_<id>`), `radius_metres` (the mean surface, 1 to `MAXIMUM_PLANET_RADIUS_METRES`, the default radius), `radius_presets_metres` (0179: the radii a new world offers, 1 to `MAXIMUM_RADIUS_PRESET_COUNT`, each passing every check below as the record's radius, `radius_metres` among them), `surface_gravity_centimetres_per_second_squared` (1 to 5000, 981 is Earth's), `bedrock_depth_metres` (below the radius, from `MINIMUM_BEDROCK_DEPTH_METRES`, the maximum relief plus the deep stone band, so bedrock never stands in a valley in place of topsoil, to the radius less one), `sea_level_metres` (above the radius, negative below it, within the radius; every sample below it that is not ground is sea), `springs` (at most `MAXIMUM_SPRING_COUNT` records of `latitude_degrees`, -90 to 90 with 90 the pole on +y, and `longitude_degrees`, -180 to 180 with 0 towards +x and 90 towards +z; the generation makes the first air sample above the surface under each a source of the water field), `rain_fill_per_minute` (0 to `MAXIMUM_RAIN_FILL_PER_MINUTE`, fill per surface sample per minute, 254 a sample; read and bounded, applied by the weather in M15), `rotation_period_seconds` (game seconds, 60 to 86400), `relief_octaves` (0179: three records of `wavelength_metres`, 1 to `MAXIMUM_RELIEF_WAVELENGTH_METRES`, and `amplitude_metres`, 0 up, adding up to at most `MAXIMUM_RELIEF_METRES`, 34; the surface is the radius plus their value noise), `palette` (1 to 256 red, green, blue triples of 0 to 255; a sample's tint indexes it).
- The file is held to the configuration's strict keys: an unknown key, a wrong type or a missing field refuses the content load with the key's name. The rotation is recorded for the day (0179); generation reads the radius, the bedrock depth, the relief, the palette's length, the sea level and the springs (0172), and the field player (0170) the gravity. A world records these values in its `world.sjson` when it is made ([architecture.md](architecture.md), Save format), and once the slice switches the session to the field world it generates from them, so an edit of the file reshapes new worlds only.
- The shipped `home`: radius presets of 4, 8 and 16 km with 8 the default; octaves of 512, 128 and 32 m at 24, 8 and 2 m; a sea level of -14 m, which with the default seed keeps the pole (about 9 m below the radius, where the preview starts) dry and puts hollows below the sea 70 to 500 m from it towards longitude -105, where the preview's cameras look; one spring at latitude 88, longitude -120, about 280 m from the pole on the slope above those hollows; rain 2 a minute.
- The world settings of the field (0179), chosen on the New world screen ([ui.md](ui.md), Other screens) and stored in `world.sjson`: `planet_id` (a record of this file, default `home`), `planet_radius_metres` (one of that record's presets, default its `radius_metres`), `sample_spacing_millimetres` (333, 500 or 1000, default `DEFAULT_SAMPLE_SPACING_MILLIMETRES`, the field's grid), `mode` (`Peaceful`, `Survival` or `Creative`, default peaceful; stored only, every mode plays as peaceful until the survival stats of M15) and `keep_inventory` (default on; stored only, read by death in M15). A file without `planet_id` was written before them and reads the defaults; one without the spacing reads its default. A planet the data no longer has falls back to `home` (or the first record) for a new world; a loaded world keeps its id in the settings and its save and takes the default record's palette and rain. A radius that is not a preset falls back to the default radius. Each writes a log line and never refuses the load. The mode is written by name: a number is refused, an unknown name reads as peaceful with a log line.
- `home` (0179, required): `latitude_degrees` (-90 to 90) and `longitude_degrees` (-180 to 180) in whole degrees, where every new player spawns: on the generated surface under the point, `FIELD_SPAWN_CLEARANCE_MILLIMETRES` above it, facing the first spring ([architecture.md](architecture.md), The field session). A world records it with the planet's other values; a `world.sjson` recorded without it takes the data's with one log line. The shipped home lies at latitude 86, longitude -115, about 280 m from the spring at 8 km (140 m at 4 km, 560 m at 16 km), downhill from it and the hollows beyond: with the default seed its ground stands above the sea level at every preset (3.5, 2.8 and 8.0 m below the radius at 4, 8 and 16 km, with the sea at 14 m below), where the pole's neighbourhood at 89 degrees lies under the sea at 8 and 4 km. Another seed can put it under the sea (SUGGESTIONS.md).
- The starter kit (0179): `starting_items` of `data/game.sjson`, given to every new player of a field session, the first and a joining one (`make_field_session_player`): one `stone_pickaxe` (tier 2, digs stone and the outcrops), sixteen `foundation` and four `torch`, nothing of wood.
- `field_simulation` in `data/game.sjson` (0179): `chunk_radius` (1 to `MAXIMUM_FIELD_CHUNK_RADIUS`, 3) and `chunk_margin` (0 to `MAXIMUM_FIELD_CHUNK_MARGIN`, 2) of the field's simulated chunk set ([architecture.md](architecture.md), The field session), `torch_item` (the item Place puts down as a torch on the field) and `torch_emitter` (its emitter of `data/lighting.sjson`), both checked against the data when the tables load (`field_torch_problem`). The shipped set: a radius of 2 and a margin of 1, 125 chunks of 32 samples round each player, 160 m across at 1 m spacing.

- `field_view.level_distances_metres` in `data/game.sjson` (0169) sets the field's levels of detail ([presentation.md](presentation.md), Field meshes). Each distance must exceed the one before by at least the diagonal of a node of the level before at the widest spacing (`field_level_gap_metres`: 56, 111 and 222 m), and the last may not pass `MAXIMUM_FIELD_VIEW_DISTANCE_METRES`. The gap keeps a node chosen at one level from bordering one chosen two levels coarser, which the skirts' reach assumes, and keeps the children of a node split at the last but one distance inside the last one, so the far end has no holes. The shipped 64, 160, 384 and 1024 m pass.
- `field_player` in `data/game.sjson` (0170) tunes the field player ([architecture.md](architecture.md), The player on the field), every key required and bounded (`field_player_problem`), lengths in millimetres and speeds in millimetres per second: `capsule_radius_millimetres` (100 to 1000), `capsule_height_millimetres` (above two radii, to 4000), `eye_height_millimetres` (inside the capsule), `walkable_angle_degrees` (1 to 89, stored in degrees and turned into its fixed point cosine at load), `slide_speed_millimetres_per_second`, `step_height_samples` (0 to 4 samples of the world's spacing), `jump_height_millimetres` and `mantle_height_millimetres` (from 1 mm; the step at the widest spacing, 1 m a sample, must stay below the mantle), `tool_reach_millimetres`, `walk_speed_millimetres_per_second`, `sprint_speed_millimetres_per_second`, `sneak_speed_millimetres_per_second`, `fall_speed_limit_millimetres_per_second`, `fly_speed_millimetres_per_second`, `fly_sprint_speed_millimetres_per_second`; each speed is refused above `MAXIMUM_FIELD_PLAYER_MILLIMETRES_PER_TICK` (8 m) a tick at the `tick_rate` (`field_player_speed_problem`), which keeps the controller's integers inside an i64. The shipped values: a capsule of 0.3 by 1.8 m with the eye at 1.6 m, 40 degrees walkable, a slide of 6 m/s, a step of one sample, a jump of 1.1 m (a metre and the capsule's clearance), a mantle of 1.5 m, a reach of 4 m, the block player's 4.3, 5.6 and 1.3 m/s and the fly camera's 12 and 36 m/s. Gravity is the planet record's.
- `field_water` in `data/game.sjson` (0172) tunes the water field ([architecture.md](architecture.md), The water field), every key required and bounded (`field_water_problem`), fill in 1/`FIELD_WATER_FULL` (254) of a sample: `fill_rate_per_tick` (1 to 254, the most fill a sample moves to one neighbour a tick), `still_ticks_to_sleep` (1 to 255), `minimum_fill` (1 to 253, a film at or below it stops and dries) and `dry_ticks_per_step` (1 to `MAXIMUM_FIELD_WATER_DRY_TICKS`, the ticks between two drops of a film). The shipped values: 64, 20, 8 (about 3 cm at 1 m spacing) and 60 (a film of the minimum dries in 8 seconds). A missing key reads as zero and is refused by its bound, as for `field_player`. The full fill is a constant, not data: the levels and the mesher's density are counted in it.

## Field materials and brushes

The hand tool on the terrain field (0171; [architecture.md](architecture.md), The terrain field's brushes).

- `data/materials.sjson` holds one record per field material but air: `id` (the material's name, `topsoil`, `stone`, `deep_stone`, `bedrock` and the ores `hematite_ore`, `chalcopyrite_ore`, `coal_ore`), `item` (the `items.sjson` id a cubic metre yields and a place takes; empty for a material that is never dug or placed), `tool_tier` (the pickaxe the brush needs, 0 to the highest tool's tier, as `blocks.sjson`'s) and `dig_rate_percent` (0179, `MINIMUM_DIG_RATE_PERCENT` to `MAXIMUM_DIG_RATE_PERCENT`, 10 to 400: the brush's rate on the material in percent, `scaled_dig_rate`; a place keeps the brush's rate). Held to the configuration's strict keys: an unknown key, a missing key, an unknown material or item, a material listed twice or missing refuses the file. The texture parameters stay in `data/textures/field_materials.sjson` (Textures). The shipped table: topsoil gives dirt by hand at 150 percent, stone gives stone with a wooden pickaxe at 100, deep stone gives deep stone with an iron one at 60, bedrock gives nothing (100, never dug); the ores of the outcrops (0179, Veins on the sphere) give hematite and chalcopyrite with a stone pickaxe and coal with a wooden one, at 80. It loads with the tables and reloads with them (0179).
- The material unit: a cubic metre an item. A sample's ground is the positive part of its density, 127 steps the whole sample, so at a spacing of s metres one step is s^3 / 127 cubic metres; the volume short of a whole item is kept per player and material, so digging at a third of a metre yields as much per cubic metre as at one.
- `field_brushes` in `data/game.sjson` lists the brushes the brush key cycles, one to `MAXIMUM_FIELD_BRUSH_COUNT`, every key required and bounded (`field_brushes_problem`): `id` (unique), `shape` (`sphere` round the hit, or `level`, which flattens to the plane through the hit across the player's up), `radius_millimetres` (`MINIMUM_FIELD_BRUSH_RADIUS_MILLIMETRES` to `MAXIMUM_FIELD_BRUSH_RADIUS_MILLIMETRES`) and `rate_density_steps_per_tick` (1 to `MAXIMUM_FIELD_BRUSH_RATE`, in steps of 128 a spacing). The shipped brushes: a small sphere of 1 m at 6 steps a tick (a full sample in about a third of a second), a large one of 2 m at 3 and a level brush of 2 m at 6.

## Lighting

The field light's numbers (0173; [architecture.md](architecture.md), The field light), in `data/lighting.sjson`, every key required and held to the configuration's strict keys (`parse_lighting_file`, `lighting_problem`).

- `falloff`: the light lost per metre by level band, the darkest band first. The bands split the levels 0 to 255 evenly, so their count is a power of two from 1 to 16; each loss is 1 to 255 and none rises above the one before it, so a brighter level never spreads dimmer than a darker one and the fill's result does not depend on its visiting order. A step between samples loses the falloff of the level it leaves times the spacing, rounded to the nearest and at least 1 (`make_field_light_tuning`), so a room is the same size in metres at every spacing; multiples of 6 divide evenly at 333, 500 and 1000 mm. The shipped curve is 24, 18, 12 and 6 per metre: gentle near the source, steep at the edge.
- `dark_level`: a level at or below it reads as dark (24; the tests' threshold).
- `steps_per_tick` (8192) and `chunk_seeds_per_tick` (4): the queue nodes the light runs per tick over both channels, and the arrived chunks whose borders are compared per tick.
- `emitters`: the light sources by `id` with their `level` at the source sample, 1 to 255, ids unique, `torch` and `lamp` required. The lamp's level lives here rather than on its machine record until the slice (0179) moves it there. The torch (192) reaches about 11 m along a corridor and lights every sample of an 8 m room, the lamp (255) about 21 m and a 16 m hall (`test_the_light_radius_in_metres_is_the_same_at_every_spacing`). The field's torch places the emitter `field_simulation.torch_emitter` names (0179). The file loads with the tables and reloads with them.

## Foundations

Foundation frames (0174; [architecture.md](architecture.md), Frames).

- The foundation is a machine of kind `foundation` in `data/machines.sjson` (`id` `foundation`, placed by the `foundation` item of `data/items.sjson`, made by hand or in an assembler from two stone bricks): its footprint must be one cell high (`validate_machine_kind_fields`) and it has no other fields and no model; the frame renderer draws its cells as grey slabs. Placed free it starts a new frame, snapped to a frame's cell it joins that frame, and machines on a frame stand on foundation cells.
- `foundation_pitch_millimetres` in `data/game.sjson` is the cell of a new frame, required and bounded from `MINIMUM_FOUNDATION_PITCH_MILLIMETRES` (250) to `MAXIMUM_FOUNDATION_PITCH_MILLIMETRES` (2000); the shipped 500 mm. A saved frame keeps the pitch it was made with.
- An inserter's arm reaches `reach_millimetres` unfolded (0175), required on every inserter record and bounded from `MINIMUM_ARM_REACH_MILLIMETRES` (250) to `MAXIMUM_ARM_REACH_MILLIMETRES` (8000): 2000 on the shipped inserters (the design's 2 m), 4000 on the long inserter, which keeps twice the reach it has on the block frame. On a frame the reach in cells is that over the pitch ([logistics.md](logistics.md), Inserters).
- Machine footprints are counted in cells, so on a 500 mm frame every machine stands at half its block size until the slice's content (0179) sets the real sizes in frame cells; the footprints of `data/machines.sjson` are unchanged until then.

## Belt poles and runs

Runs between poles (0176; [logistics.md](logistics.md), Runs).

- The belt pole is a machine of kind `belt_pole` in `data/machines.sjson` (`id` `belt_pole`, placed by the `belt_pole` item of `data/items.sjson`, made by hand or in an assembler from two iron plates and a stone brick): a 1 by 1 by 1 footprint and `height_millimetres`, how high over its bottom a run meets it, required and bounded from `MINIMUM_BELT_POLE_HEIGHT_MILLIMETRES` (250) to `MAXIMUM_BELT_POLE_HEIGHT_MILLIMETRES` (4000) (`validate_belt_pole_definition`); the shipped 1500. No model and no panel: it is drawn as a post. The electric poles are kind `pole`, so the run's poles took `belt_pole`.
- A belt run moves at the speed of the first flat belt of the data (`find_belt_machine`), a pipe run looks like the first pipe; the slice's content (0179) gives them items and costs.
- `belt_runs` in `data/game.sjson`, each key required and bounded (`belt_runs_problem`): `maximum_span_millimetres` (1000 to 100000, shipped 30000), `maximum_slope_percent` (1 to 100, shipped 70), `maximum_turn_degrees` (15 to 135, shipped 90), `level_tolerance_millimetres` (0 to 1000, shipped 250) and `aligned_degrees` (8 to 30, shipped 8), how far an incline's facings and chord may turn apart. A new free pole faces the nearest of the 24 yaw steps of 15 degrees, up to 7.5 degrees off the chord, so the bound's floor is half a step plus one (asserted against `FRAME_YAW_STEPS`): below it a third of the aim directions would refuse an incline to a new pole. The slope limit holds along the whole belt, not only its chord. The bounds keep the polyline and the arc length inside an i64 and the length in line units inside an i32 at the finest pitch.

## The pod

The start on the field (0179, `entity_pod.odin`).

- The pod is a machine of kind `pod` in `data/machines.sjson` (`id` `pod`): no item (`machine_kind_is_placed_by_world`, so it is never crafted, held or picked up), no panel and no slots, a footprint of 6 by 6 by 8 cells, 3 by 3 by 4 m at the 500 mm pitch, and the model `pod`. Its oxygen and bed wait for M15. It rides in the foundations' pool, an entity of its common data only.
- `place_pod` lays it at the surface position: a free frame whose forward is the heading's yaw step, a pad of `POD_PAD_SIZE` by `POD_PAD_SIZE` (10 by 10) foundations that cost nothing, and the pod centred on the pad with its door, the model's front, towards the forward (`POD_ROTATION`).

## Blocks

`data/blocks.sjson` holds the shapes, orientation flags, light and sound materials.

- Slabs and stairs are solid and collide with their boxes. There is no step up: the player jumps onto them.
- A tile that varies per block is slid by whole texels and wrapped, so it must be periodic: `test_varying_block_tiles_are_periodic` fails when the mean texel difference across the wrap edge exceeds `TILE_WRAP_ROUGHNESS_FACTOR` times the mean across interior edges. `keep_orientation` and `framed` blocks are exempt ([presentation.md](presentation.md), Per block variation).
- Coloured light: the largest channel of `light_color` equals `light_level`, which stays the one level everything else reads. The furnace's and the boiler's glow is emissive voxels in their models, not light.

## Textures

Block tiles and item icons are 16 by 16 RGBA PNG files under `data/textures/`, or generated tiles, loaded into atlases at start, on a content reload and when a file changes (`render_atlas.odin`).

- `textures/blocks/<id>.png` serves all three face groups, and `<id>_top.png`, `<id>_side.png` and `<id>_bottom.png` override one group each. A block or group without a file takes its colour from `data/blocks.sjson` with a little noise. Shape variants use the listed block's tiles.
- `textures/items/<id>.png` is the item's icon ([ui.md](ui.md), Text and theme).
- A file that is not 16 by 16 with 8 bit channels, or does not decode, is logged and takes the fallback.
- `data/textures/procedural.sjson` (0099) lists the blocks whose tile the game generates (`texture_generate.odin`, pure): the seven ores. Its header gives the parameters and ranges. A generated tile serves every face group and wins over any file.
- `data/textures/field_materials.sjson` (0169) holds one entry per field material but air (topsoil, stone, deep stone, bedrock and the three ores): `material`, `ground` and `fleck` (red, green, blue), and the ore parameters of `procedural.sjson` with their ranges, every key required, except that `crystal_size` must be 1: round flecks are isotropic, while larger sizes make squares whose edges stripe along the axes of the triplanar projection, so the file is refused. The tile is generated as an ore's, flecks over the ground; the ores (0179) take the stone's ground with rust red, brassy and black flecks. How they are drawn: [presentation.md](presentation.md), Textures. The planet palette's tint multiplies it ([presentation.md](presentation.md), Field meshes); it is read when the planet preview starts, not on a reload.
- `blob_width` below about 0.55 blurs little, and the blobs join diagonally into a checkerboard. Above about 0.8 a tile holds a few large blobs that read per block.
- The texture editor ([developer_tools.md](developer_tools.md)) saves `$XDG_STATE_HOME/mine-oh-belowed/texture_edits.sjson` in the data file's form. Its entries replace the data file's per block on every atlas build, so once the chosen values are copied into `procedural.sjson`, delete the edits file. A file that does not load is logged and ignored whole.
- `tools/make_placeholder_textures.py` writes the placeholder block tiles, item icons and UI icons from the ids and colours in the data, skipping the procedural blocks. Rerun it after adding a block or item. Hand made files replace its output one by one.
- Placeholder patterns follow the per block variation: stone, gold quartz, leaves and water use isotropic noise only (`isotropic_field`), with no rows or diagonals, and every varying pattern wraps at the tile edge. The log rings need not, being framed.

## Models

How models are loaded, lit and moved: [presentation.md](presentation.md), Machine models and The player.

- A machine model is authored at 8 or 16 voxels per block, z up, with its +x side as the front. The keys are in the header of `data/machines.sjson`.
- The pod (0179) is authored at 8 voxels per cell, 62.5 mm at the 500 mm pitch: a hull on a base plate, a door opening on the front and a bed inside (`tools/make_placeholder_models.py`, `pod()`).
- The arm (0175) is authored at real scale instead, six files at 25 mm per voxel, one per part; the files and the authored pose are in [presentation.md](presentation.md), The arm. Every inserter record names it with `model = "arm"` and `motion = {kind = "arm"}`.
- The player is six files (`player_torso.vox` and the limbs), each the whole `PLAYER_MODEL_FRAME` at 16 voxels per block with only its limb filled, +x the front and +z the right side. A replacement keeps the frame and puts the shoulders at the tops of the arms, the hips at the tops of the legs and the neck under the head.

## Sounds

`data/sounds/sounds.sjson` lists every sound and the ids the game asks for. The mixer and triggers, footsteps and mining hits included, are in [presentation.md](presentation.md), Sound.

- Every block's `sound_material` needs its `footstep_<material>` and every biome's `ambience` its loop or variants, or the table does not load.
- Ambience calls (`sound_events.odin`): a cluster plays two variants `AMBIENCE_CALL_GAP_MINIMUM_TICKS` to `AMBIENCE_CALL_GAP_MAXIMUM_TICKS` apart, a third in `AMBIENCE_THIRD_CALL_PERCENT` of clusters, then pauses `AMBIENCE_CLUSTER_PAUSE_MINIMUM_TICKS` to `AMBIENCE_CLUSTER_PAUSE_MAXIMUM_TICKS`. The variant never repeats the last one, and the pitch varies by `AMBIENCE_CALL_PITCH_SHARE`, all from a hash of the tick and the cluster count.
- A `day_only` ambience calls only while the daylight blend is above `AMBIENCE_DAYLIGHT_MINIMUM`. The first variant's flag speaks for all.
- The hum drifts by `HUM_DRIFT_SHARE` over `HUM_DRIFT_MINIMUM_TICKS` to `HUM_DRIFT_MAXIMUM_TICKS`.
- `tools/make_placeholder_sounds.py` (standard library only, deterministic) writes the placeholder files, mono at 22050 Hz, into `data/sounds/` or a directory given. The table is written by hand, and recorded sounds replace files one by one.

## Descriptions and notes

- Every item, machine and technology names a `description_key` (`describe_item_<id>` and so on, 0070). `test_shipped_descriptions_exist` keeps every shipped entry described.
- A description is one to three sentences in the venture's register ([DESIGN.md](../DESIGN.md), Lore and tone): what the thing is, what it does for the outpost, and one concrete fact, real (a formula, a melting point, an ore's metal content) or the game's own (a rate, a draw, a capacity).
- A game fact in a description copies a value in the data: changing the value means changing the text.
- A machine's item and the machine have two texts: what it is for (the recipe browser) and how it runs (the machine panel).
- Temperatures read "degrees Celsius": not every selectable font has a degree sign.
- Notes (`data/notes.sjson`, `notes.odin`) are the journal's world building, one unlock each, in the order their milestones come in play. Geology in a note is real geology (Mississippi Valley type lead and zinc, magmatic nickel with copper, lateritic bauxite), the rest is the venture.

## Tick cost baseline

The factory benchmark on the couch machine (Ryzen 7 2700X, headless, release build), 2026-09-28, in milliseconds per tick ([architecture.md](architecture.md), Performance).

| Size | Entities | Average | Worst |
| --- | --- | --- | --- |
| 1 | 321 | 0.026 | 0.046 |
| 4 | 1281 | 0.075 | 0.18 |
| 16 | 5121 | 0.27 | 0.77 |
| 64 | 20481 | 1.35 | 6.5 |

- Electric networks (`tick_electric_networks`) take the largest share at every size (22 to 29 percent), then inserters and fluids (about 20 percent each). At size 64 statistics grows to 20 percent.
