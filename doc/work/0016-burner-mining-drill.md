# 0016 Burner mining drill on veins

Status: implemented
Milestone: M3

## Goal

The burner mining drill as described in `doc/logistics.md`: placed on a vein outcrop, tapping the reservoir with the vein's output mix, producing into the cell in front of its arrow, stalling on fuel or blocked output, and exhausting finite veins into spent rock.

## Deliverables

- Drill entity kind (2 by 2 by 2) with fuel slot, output arrow, cycle timing from `data/machines.sjson` (15 ore per minute plus spoil at the vein mix), placement validity requiring an outcrop cell of a vein under the footprint, vein handle stored on the drill.
- Reservoir draw with a deterministic generator seeded by tick and vein id, honouring the infinite veins world setting, exhaustion turning the outcrop to spent rock through `world_set_block`, and a drill state for it.
- Output through the transfer interface into the cell in front (belt, chest, machine that accepts the item); stall when blocked.
- Panel: fuel slot, vein remaining per ore, rate, state.
- HUD: the vein name and remaining amount when a drill or outcrop is targeted (the geologist's hammer assay comes later).
- Tests: placement validity on and off outcrops, draw mix over many cycles matching the vein weights within tolerance, exhaustion and spent rock, stall on blocked output and no fuel, shared vein between two drills, determinism.

## Verify

- Builds and tests pass.
- User: place a drill on the iron outcrop by the spawn, fuel it, and watch hematite fall into a chest in front of it.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/machines.sjson` (kind `drill`, machine `burner_mining_drill`), `data/veins.sjson` (`spent_block`, a `name_key` per vein type), `data/game.sjson` (`veins_infinite`), `data/strings/en.sjson`, the hint counter comment in `data/quests/chapter_01.sjson`, `drill.odin` (entity, cycle, reservoir draw, output, placement check), `drill_test.odin`, plus changes to machine, entity, placement, item transfer, inserter (rotation and self feeding), vein registration (`world_vein.odin`), generation (outcrop cells), streaming, statistics, quest hint counters, renderer, placement ghost, machine panel, HUD, loop and main, and the test world helpers.

### Deviations and choices

- Rate: one unit per cycle, with the cycle set so an 80 percent ore vein yields 15 ore per minute: `items_per_minute = 15` plus `rate_reference_ore_percent = 80` in the data, cycle `60 * tick rate * 80 / (100 * 15)` = 192 ticks, 18.75 units per minute. This keeps the reservoir model (every unit comes from the mix) and makes the ratio checks of `doc/content.md` exact on iron veins (five drills, 75 hematite per minute). Other veins follow their own mix: a coal vein gives 16.9 coal per minute, a copper vein 13.1 chalcopyrite and 1.9 cassiterite. The fixed "15 ore plus 3 spoil" alternative would need a notion of which outputs are ore, which the vein data does not have.
- Fuel power is `fuel_power_kilowatts = 150` like the other machines (the file has no watts field). Fuel burns only on ticks the drill mines, 2500 J per tick, three coal per minute.
- The drop cell is at ground level in front of the arrow side. A 2 wide side has no middle cell, so the cell on the arrow's left is taken (the local cell `(width, (depth - 1) / 2)` rotated with the footprint). Belts take the item on the lane nearest the drill; a belt running in line with the arrow takes it on its right lane (the inserter rule). Any entity in the drop cell is a target through `entity_insert`, including another drill or a burner inserter, which take fuel into their fuel slot. Drills themselves take fuel from inserters and give nothing.
- Drill direction on placement is relative to the facing like inserters: rotation 0 drops away from the player.
- Draw: the generator is `hash(world seed, salt, vein region, vein index, vein draw count)`, so the sequence a vein yields does not depend on which drill or which tick draws. An output weighs its percent while it has units left (an output at zero is skipped, not drawn and wasted); an infinite vein keeps all weights and decrements nothing. `World.settings` holds the seed and `veins_infinite`, set in `run_game` from the generator and `game.sjson`.
- Exhaustion and spent rock: generation now lists the outcrop cells it places (`Generated_Chunk.outcrops`), and the main thread keeps them in `World.outcrop_cells` when it inserts a chunk. When the last unit of a finite vein is drawn, `Vein.exhausted` is set and every known outcrop cell of the vein is queued; at the end of the entity tick queued cells whose chunk is loaded and whose block is still one of the vein's outcrop blocks go through `world_set_block` to `spent_rock`. A chunk inserted later registers its outcrop cells, and cells of an exhausted vein are queued at once, so it comes out as spent rock one tick after insertion (through the same block change path, so light and remeshing follow). The spent block is `spent_block` in `data/veins.sjson`. A mined or built over outcrop cell keeps its block.
- Placement validity uses `veins_of_column` and the disc as briefed: a ground cell under the footprint whose column is in a registered vein's disc and whose block is one of the vein type's outcrop blocks. The first such cell in footprint order names the vein. For the quarry type (stone outcrop) that accepts any stone in the disc, including stone below the surface after digging.
- `Simulation_Content` gained `veins: Vein_Content` (per type the name key, outcrop blocks and outputs resolved to items, plus the spent block), resolved in `main` after the generator.
- Statistics: drill output counts as produced when it leaves the drill (a held unit does not count until it lands), never as obtained. New stalls `Drill_Out_Of_Fuel` and `Drill_Waiting_For_Room` (counted when a drill enters the state, so a freshly placed unfuelled drill does not count) and `veins_exhausted`; hint counters `drill_out_of_fuel`, `drill_waiting_for_room`, `vein_exhausted`.
- `fuel_burned` for inserters (and drills) now counts a lit fuel item when the fuel buffer grows, instead of the fuel slot shrinking, so an item an inserter fed itself and lit in the same tick is counted. Same results in the existing tests.
- Carry overs from 0015: Rotate with no machine item selected turns a targeted inserter or drill a quarter turn (`rotate_targeted_entity`, belts as before). A burner inserter with an empty buffer and an empty fuel slot puts the fuel item it is about to pick into its own fuel slot (then picks the next item), and a fuel item in its hand when it runs dry mid swing (then swings on empty handed).
- Picking up a drill returns its fuel and a held unit.
- A drill whose vein id is not registered shows as exhausted. `add_entity` gives a drill the zero vein id; only `place_entity_with_player` (and tests) set the real one.

### Constants

Cycle 192 ticks, 2500 J per tick, draw salt `0x6472696c6c5f7631`. Panel area 480 units wide: fuel slot and burn bar, cycle bar, vein name, one line per output with its remaining amount (or one "Infinite" line), rate in units per minute, state. HUD: a second line under the entity status with the vein name and remaining total, also for a targeted outcrop block. Render: drill cells brown with a darker top, a bar on the top face turning four times per cycle (driven by progress, so it stands still unless mining), the output arrow on the top face; the ghost shows the same arrow.

### Not verified

Everything visual and the feel: the drill model, bar and arrow, the ghost arrow and its direction relative to the facing, the panel layout and text widths at 720p and 1080p and UI scale 1.5, the two HUD lines, spent rock appearing on the outcrop, rotating placed inserters and drills by feel. The user verify (drill on the iron outcrop by the spawn feeding a chest) is not run. The shipped data was loaded through the real loader by starting the binary without a display.

### Open questions

- Should the rate stay tied to the iron vein's ore share (coal veins then give 16.9 coal per minute, copper veins 13.1 chalcopyrite), or should every vein give 15 of its main ore?
- `World.outcrop_cells` keeps every outcrop cell ever loaded and is never pruned on unload (like the vein records); fine until saving lands, then it belongs in the save or is rebuilt on load.
- Placement on quarry veins accepts any stone in the disc. Should placement require the recorded surface outcrop cells (`World.outcrop_cells`) instead?
- `doc/logistics.md` needs an "As implemented in 0016" note (rate model, drop cell and lane, draw seed by vein draw count rather than tick, spent rock for late chunks, drills as fuel targets, inserter self feeding), `doc/content.md` (drill values now in `data/machines.sjson`, `veins_infinite` in `game.sjson`) and `doc/architecture.md` (outcrop cells on the World); this run could not touch them.

