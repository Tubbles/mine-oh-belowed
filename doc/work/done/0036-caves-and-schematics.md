# 0036 Caves, schematics and alternate recipes

Status: implemented
Milestone: M8

## Goal

The optional underground tenth: caves hold schematic items that unlock alternate recipes, so exploring pays in recipe choice as the design intends, without ever being required.

## Deliverables

- Cave features: generation places schematic crates (a small non minable entity like the capsule with one slot holding a schematic item) in cave pockets below a depth threshold at a low density per region, deterministic from the region hash, and small rare deposits (gold ore and quartz blocks in cave walls) near them so the cave is worth the walk.
- Schematics: items (`schematic_<name>`) that, when used from the hotbar (a new `Use` action on the selected item: L2 with a schematic selected, or Interact on the crate takes and reads it), unlock one alternate recipe through a new `schematic` recipe channel. Alternates in data, four to start: iron plate from low grade hematite directly at half yield (fewer machines), steel from iron plate and charcoal (no coal), plastic from wood gas without charcoal (cheaper renewable route), concrete from slag and water without crushing (a byproduct turned into a product). Each is a real recipe with `channel = "schematic"` and a schematic id.
- The recipe browser shows schematic recipes as silhouettes with "Found in caves" until unlocked; the journal message log records a found schematic.
- Statistics: schematics found, for quests.
- Tests: crate placement determinism and density, the use action unlocking exactly its recipe, the schematic channel in `Recipe_Unlocks`, silhouettes, save round trip of found schematics.

## Verify

- Builds and tests pass.
- User: find a crate in a cave, read the schematic, and see the alternate recipe lose its silhouette.

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (497 tests, 10 new in `schematic_test.odin`, 2 in `deep_mining_test.odin`), `./build.sh`, `./build.sh release`, `--version`; the shipped data loads through the real loader (the binary stops only at opening a window).

### Carry overs from 0035

- Bore drill ghost: `bore_drill_ghost_vein` (entity_placement.odin) finds the deep vein the ghost's footprint would tap the way `placement_for_player` places it, and `bore_drill_ghost_line` puts "Bauxite vein  120 remaining" (or "No deep vein here" when none is under the centre column) on the HUD's vein line while a bore drill is selected. Shown on the HUD line only, not as text on the 3D ghost.
- Revived draws use the depleted end share of low grade ore (`LOW_GRADE_END_PPM`, 60 percent): `graded_output` takes the share instead of the infinite flag.

### Model

- Crate sites (`generation_caves.odin`): per region a hash rolls `CRATE_REGION_CHANCE` (0.25), then tries up to 16 hashed candidate columns and takes the highest pocket (an open cave cell over a closed one) at least 20 blocks below the surface that has at least 2 rock walls within 4 cells horizontally (at the crate's level and one above). 2 or 3 of them (hashed) become `gold_quartz`. A per block cave lookup (`cell_is_open_cave`) uses the chunk generator's lattice and the shared `interpolate_cave_corners`, so it gives the same bits as chunk generation (tested over three chunks cell by cell). Every chunk near a candidate column computes the site as a pure function of seed and region, writes the walls inside it, and the chunk holding the crate cell lists the site in `Generated_Chunk.crates`. New purpose seed `Cave_Crates`, appended, so every other seed is unchanged. Measured: 42, 36 and 31 crates in 144 regions for the three test seeds, every rolled region found a pocket; a site scan costs about 0.2 ms in a debug build.
- Registration: the main thread keeps each region's site once in `World.crate_sites` (saved), and `place_pending_crates` at the end of `tick_entities` adds the crate entity once its chunk is loaded (it needs the content, which chunk insertion does not have). A site stays after its crate is emptied, so a reloaded chunk never refills it.
- Crate: entity kind `Schematic_Crate` and machine kind `schematic_crate` (1 by 1 by 1, one slot, no item, never picked up, no panel, no inserter transfer). The schematic is `schematic_for_choice`: the site's hash modulo the schematic items in recipe order.
- Gold quartz mines into both quartz and gold ore (new item field `also_mined_from`, `Item_Registry.extra_drop_for_block`), no random chance.
- Schematics: items `schematic_<recipe>` (tool, stack 1, `usable`, `cannot_recycle`); recipes `low_grade_iron_plate`, `charcoal_steel`, `wood_gas_plastic`, `slag_concrete` with `channel = "schematic"` and `schematic`. `Recipe_Unlocks.schematics_found` (per recipe) unlocks the channel; unlock all marks every schematic found.
- Use: action `Use_Item`, bound with Place on L2 and the right mouse button. `resolve_use_item` (called from `simulation_tick` before the player tick, on the previous tick's target like `resolve_interact`) drops Place while a usable item is selected and Use_Item otherwise; Interact on a crate takes and reads its schematic and never jumps. `read_schematic` finds the recipe, counts `statistics.schematics_found` (new hint counter `schematics_found`, usable by counter objectives) the first time, and logs "Schematic read: <recipe>" in the message log and as a toast. Reading a duplicate consumes it and logs again without counting.
- Browser: the schematic channel's locked text is "Found in caves"; silhouettes as for any locked recipe.

### Deviations

- Machines gate schematic alternates. Fixed machines and the furnace pick recipes by their inputs and never checked unlocks, and the alternates' inputs are common, so without a gate they would run before being found. `recipe_runs_in_machines` skips an unfound schematic recipe in the furnace lookup, the fixed recipe choice and the crafting input acceptance. The found set reaches them on the `Recipe_Registry` value (`schematics_found`, set by `simulation_tick` and `make_screen_context` through `with_schematics_found`) instead of a new parameter through every machine path; a nil set (tests, tables as loaded) finds none. This puts session state on a table struct; say if a parameter is preferred.
- Plastic from wood gas alone has fewer input items than syngas plastic, which `validate_fixed_category` refused as a subset. It now allows a schematic alternate with fewer input items (`alternate_shortens`); once found it runs whenever the chemical plant holds wood gas and no charcoal.
- The brief's "scan the region's columns" became hashed candidate columns: scanning all 65536 columns of a region per chunk would cost far more than generating the chunk.
- Iron plate from low grade ore and steel from charcoal give 1 slag like every smelt; concrete from slag gives no byproduct.
- The crate density and wall numbers are constants in `generation_caves.odin`, like the tree and boulder cells, not data.
- New glyph `Use_Item` ("L2", "Right mouse") for the HUD hint "Read schematic"; a full crate shows "Take schematic" on Interact.

### Guessed numbers

Region chance 0.25, 16 candidate columns, minimum depth 20, wall reach 4, 2 to 3 gold quartz blocks, gold quartz hardness 3 s and colour (214, 206, 180) / (222, 196, 120), crate colours (120, 84, 50) with a gold lid (220, 180, 60) while full. Recipes: 2 low grade hematite to 1 iron plate and 1 slag in 3.2 s; 5 iron plate and 2 charcoal to 1 steel and 1 slag in 16 s; 40 L wood gas to 1 plastic bar in 2 s; 2 slag and 30 L water to 1 concrete in 1 s.

### Not verified

Everything visual and the feel: crate and gold quartz colours, the HUD vein line while placing a bore drill, the glyph hints, the toast and log line, how deep crates sit (many pockets are 50 to 150 blocks down, since the highest pocket of a candidate column is often far below 20) and whether they can be found without the prospecting tools. The user verify (find a crate, read it, see the recipe lose its silhouette) is covered by tests, not played.

### Open questions

- Crates are often far below the 20 block minimum. Prefer shallower pockets (for example try every candidate for a pocket within 20 to 40 blocks before going deeper)?
- Should duplicate schematics (four schematics, one per crate) turn into something useful instead of only a log line?
- `doc/input.md` (Use_Item on L2 and the right mouse button), `doc/content.md` (alternate recipes, gold quartz), `doc/logistics.md` (as implemented notes for 0036, the 0035 carry overs) and DESIGN.md need updates; this run could not touch them.
