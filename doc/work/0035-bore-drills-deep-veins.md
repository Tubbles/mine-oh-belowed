# 0035 Bore drills, deep veins and vein revival

Status: implemented
Milestone: M8

## Goal

The depth layer tapped from above, as DESIGN.md wants it: deep veins below the surface veins, richer and carrying the rarer ores, reached by a bore drill placed on the surface, and the vein revival route that keeps an exhausted vein producing at the cost of a mining fluid.

## Deliverables

- Deep veins in generation: a second vein layer per region with its own placement hash, centre depth well below the surface (a data range), five times the surface size classes per `doc/content.md`, richer mixes including bauxite, gold ore (in quartz) and pentlandite, no outcrop. Deep veins are entities like surface veins, registered when a chunk column overlapping them loads, and listed by the column lookup with a depth flag.
- Bore drill (4 by 4 by 4, electric 300 kW, `deep_mining` technology stops being a placeholder and unlocks it): valid anywhere on the surface above a deep vein's footprint disc (a column check through the deep vein lookup), draws from the deep vein like a drill from a surface vein at 60 units per minute, outputs to a belt or chest in front of its arrow through the transfer interface, and takes a long time to "reach" the vein after placement (a boring progress bar of several minutes, deterministic in ticks) before producing. Its panel shows depth, progress, the vein's remaining amounts and rate.
- Vein revival: a `mining_fluid` (a new fluid made in the chemical plant from sulfur and water) fed to a bore drill or a surface drill through a fluid port keeps an exhausted vein producing at half rate, consuming 10 litres per unit, honouring the infinite veins setting (no effect when veins are infinite). Spent rock outcrops stay spent; the drill's panel says "revived".
- New ores as data: bauxite and gold ore with items, the bauxite to aluminium plate chain (bauxite to alumina in the washer with water, alumina to aluminium in an electrolyser: a new crafting machine, 3 by 3 by 3, electric 500 kW, category `electrolysis`, unlocked by `electrolysis` technology, science packs 1 and 2), gold ore to gold plate in the furnace. Quartz as a vein output with glass and silicon (electrolyser: quartz to silicon) for phase 7 circuits later.
- Technologies: `deep_mining` (quest gate, unlocks bore drill and mining fluid), `electrolysis` (150 packs of 1 and 2), prerequisites in order.
- Tests: deep vein placement and lookup by column, bore drill validity and boring progress, draw rate, revival arithmetic with fluid consumption and the infinite setting, new recipes through the shared machine code, save round trip with deep veins, determinism over 1200 ticks with a bore drill feeding a chest.

## Verify

- Builds and tests pass.
- User: a bore drill placed on flat ground starts producing bauxite after its boring time, and an exhausted iron vein resumes at half rate once mining fluid arrives.

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (485 tests, 12 new in `deep_mining_test.odin`), `./build.sh`, `./build.sh release`, `--version`; the shipped data loads through the real loader (the binary stops only at opening a window).

### Model

- Deep veins: `Vein_Layer` (`Surface`, `Deep`, i32 sized so the map key has no padding) is part of `Vein_Id`, `Vein` gained `depth` (0 on the surface; for a deep vein the blocks from the surface height at its centre down to `centre.y`). `layer_veins` places either layer with the same size classes and region rules; the deep pass uses the new `Deep_Veins` purpose seed (appended to the enum, so every other seed is unchanged), only `deep = true` vein types, `deep_units_factor` times the units and a depth from `deep_minimum_depth` to `deep_maximum_depth` (`data/veins.sjson`). Surface generation is byte for byte what it was. `column_veins` lists both layers (surface first), so deep veins register on the main thread through the existing chunk path; `veins_near_box` and the spawn search stay surface only. Accessors `vein_is_deep` and `deep_vein_at_column`.
- The draw hash mixes in the layer only for deep veins, so surface draw streams are unchanged.
- Bore drill: a drill with `boring_seconds`. Placement needs the ordinary footprint rules plus the centre column (`origin + size / 2`, for 4 wide the column just past the middle) inside a registered deep vein's disc. It bores for `boring_seconds * tick rate` ticks of work (power credit steps, so a brownout lengthens it), state "Boring down to the vein", the panel bar and the bit show boring progress. Then the ordinary drill cycle: `items_per_minute = 48` at `rate_reference_ore_percent = 80` is a 60 tick cycle, 60 units per minute.
- Revival: `revival_port = true` requires exactly one single face input port with a fluid filter (validated in `validate_fluid_port_layout`). `drill_activity` decides boring, mining, revived or exhausted; revived mining takes twice the cycle and 10 L per unit (`REVIVAL_CYCLE_FACTOR`, `REVIVAL_LITRES_PER_UNIT` in `drill.odin`), draws with the infinite rule (full mix, start low grade share, no decrement) while the draw count still advances. Power is only demanded while the activity is not exhausted. Mining fluid use is counted as fluid consumed. Drill ports join fluid networks (segments after the crafting machines), rotating a drill rebuilds the networks, pipes draw stubs to them.
- Chemical plant gained a third port (+z, output, filtered to mining fluid) for `mining_fluid`. New maker `electrolysis` and the `electrolyser` machine (fixed, one input and one output slot).
- Save: `Drill` (bored ticks, port buffers) and `Vein_Id`/`Vein` changed, so the layout fingerprint changed as expected. The save round trip site now holds a deep vein, a bore drill part way bored and mining fluid in the electric drill's port.

### Deviations

- Bauxite has a low grade twin as briefed, which needs a use: `crushed_bauxite` plus `crush_bauxite` and `wash_bauxite` (unlocked by `deep_mining`) follow the other ores' pattern.
- The work item's "quartz ... with glass" became a furnace recipe `quartz_glass` (1 quartz to 1 glass, discovery), next to silicon in the electrolyser.
- `choose_vein_type` returns -1 when no type of the layer is allowed and no vein is placed, instead of falling back to type 0 (which could be a deep type now). Never happens with the shipped data.
- The revival rule constants live in `drill.odin` like the grade constants, not in data.
- Gold ore has no low grade twin, gold quartz blocks for 0036 are not added.

### Guessed numbers

Deep mixes and weights: deep iron 90 hematite, 10 gravel (25); deep copper 75 chalcopyrite, 15 cassiterite, 10 sand (20); bauxite 85 bauxite, 15 gravel (25); gold quartz 20 gold ore, 70 quartz, 10 gravel (10); deep pentlandite 75 pentlandite, 15 chalcopyrite, 10 sand (15); all biomes. Depth 40 to 120. Recipes: bore drill 20 steel, 10 circuit, 20 gear, 10 pipe; electrolyser 10 steel, 10 circuit, 20 copper plate, 5 pipe; alumina 1 bauxite and 30 L water to 1 alumina and 1 mud, 2 s; aluminium plate 2 alumina, 3.2 s; silicon 2 quartz, 3.2 s; gold plate 1 gold ore, 3.2 s with slag; crush and wash bauxite as the other ores. Revival port buffers 200 L on the -x face middle cell of the bottom layer (the side away from the arrow at rotation 0). Colours: mining fluid (120, 200, 170), bore drill (110, 90, 130), electrolyser (170, 150, 60).

### Not verified

Everything visual and the feel: bore drill and electrolyser colours, the port squares on drills, the drill panel with the depth and port rows at 720p, 1080p and UI scale 1.5, the ghost over a deep vein (nothing on the surface shows where deep veins are until prospecting, 0038). The user verify (bauxite after boring, revived iron vein) is covered by tests, not played.

### Open questions

- Nothing on the surface marks a deep vein, so placing a bore drill is guesswork until the prospecting tools of 0038 exist. Fine for now, or should the bore drill ghost say which deep vein it would tap?
- A revived vein draws at the low grade share of a full vein (10 percent). Should it stay at the end share (60 percent) instead, as "as if the reservoir were full" is read here literally?
- `doc/content.md` (phase 7 values, deep vein table), `doc/logistics.md` (bore drill, revival port as implemented), `doc/fluids.md` (drill ports, chemical plant output port) and DESIGN.md ("a bore drill supplied with a mining fluid keeps an exhausted vein producing": the electric mining drill has the port too, per the brief) need updates; this run could not touch them.
