# 0041 Contracts, trade returns, orbital survey and infinite research

Status: implemented
Milestone: M9

## Goal

Shipments mean something: contracts from the venture with soft deadlines, returns that land in the capsule, the orbital survey bought with a shipment, and infinite research to carry the long game.

## Deliverables

- Contracts as data (`data/contracts.sjson`): each names requested items and counts, a reward (items landing in the drop capsule, or an orbital survey), and a soft deadline in game minutes with a reduced reward when late (a percentage). The venture offers up to three open contracts at a time chosen deterministically from the pool by tick and seed, visible in a Contracts tab on the launch pad panel and in the journal; a launch whose cargo satisfies an open contract completes it (the venture takes the requested items, extra cargo is sold at a flat rate into a `venture_credit` counter that later items may spend). Late completion pays the reduced reward; contracts never fail, they only pay less.
- Trade: a shipment with no matching contract is free trade: the cargo is valued by a per item price in data (default derived from the recipe depth) and credited to `venture_credit`. A small catalogue in the pad panel lets the player spend credit on returns delivered by capsule: rare materials (silicon, aluminium, gold plate) and an orbital survey.
- Orbital survey: spending credit (or a contract reward) reveals every surface vein within 256 blocks of the pad on the map with size classes, through the existing map layers and prospecting records.
- Infinite research: repeatable technologies in data (`infinite = true`, cost growing per level: mining productivity giving drills 10 percent more output per level, and research speed), the lab and the technology screen handling levels, and the drill output multiplier applied deterministically (a per mille counter like the power credit).
- Journal: contracts and shipments in the message log.
- Tests: contract selection determinism, completion on launch with and without lateness, credit arithmetic, catalogue purchase landing in the capsule, orbital survey revealing veins, infinite research levels and the drill multiplier, save round trip.

## Verify

- Builds and tests pass.
- User: complete a contract on time and late, buy an orbital survey and watch the map fill, and research mining productivity twice.

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (554 tests, 11 new in `venture_test.odin`), `./build.sh`, `./build.sh release`, `--version`; the shipped data loads through the real loader (the binary stops only at opening a window).

Files: new `data/contracts.sjson`, `src/contract.odin` (data), `src/venture.odin` (runtime), `src/ui_contracts.odin` (pad tabs, journal tab, HUD line), `src/venture_test.odin`; changes to items (price), technologies (infinite levels), lab, drill, launch pad, quest messages, statistics, hint counters, save, world, loop, main, screen context, journal, technology screen, diagnostics, strings and the affected tests.

### Carry overs from 0040

- A launch logs "Shipment launched: {cargo}" to the message log and as a toast. `Quest_Message` gained `value` (`{value}`) and `shipment` (one more than the index into `World.shipments`, rendered as `{cargo}`); both are saved with the message log.
- Shipped cargo counts as consumed (`record_shipment`).

### Model and deviations

- Venture state on the world: `contracts` (fixed `Contract_State`: open contracts oldest first with offer tick and deliveries per request, offer counts per contract), `venture_credit`, `catalogue_orders`. All saved; the content fingerprint now includes the contract ids and the catalogue size.
- Offering starts once a launch pad was placed (`Statistics.placed`). Tier from `tier_shipments = [0, 3, 10]` in the data against `rockets_launched`. "Cycling" is implemented as: the candidates are the eligible contracts offered least often; the pick among them hashes seed, tick and slot. Slots fill the tick they free; with no candidate they stay free until one exists.
- Catalogue lives in `data/contracts.sjson`. An order is refused in the panel (toast) when credit minus the credit promised to pending orders does not cover it; the next tick deducts and queues the items (or runs the survey) and logs "Ordered: ...".
- Orbital survey: centre is the launching (or ordering) pad's footprint centre, stored on `Shipment.pad_centre` and on the order. It asks `Simulation_Content.generator` (new, set only by `frame_simulation_content`, read only) for every surface vein in the regions around the pad, so veins in chunks never loaded are charted too; without a generator (tests, save test) it uses the registered veins. Revealed veins are added to `World.assayed_veins` (`veins_assayed` is not bumped, that stays the hammer's counter).
- `surveys_bought` counts every survey run, the contract reward ones included, since DESIGN.md calls both "bought with a shipment". A late survey contract still runs the survey in full (a survey cannot be cut); the late message still names the percent.
- Levels live in `Research_State.levels` on the world, not in `Recipe_Unlocks`: drills and labs tick with the world and need them, and every save of the research state carries them. So `finish_research_unit` counts the level, not `mark_technology_researched` as briefed; `mark_technology_researched` still sets `researched` (research objectives work). An infinite technology is never "Researched" in the status, stays queued after each level, and a quest reward cannot grant levels.
- Technology effects are data (`effect`, `effect_percent`), not ids in code. Level cost is exact integer arithmetic on the reduced growth fraction, capped at 1 000 000 000 units; for growths with large reduced denominators it is approximate past 2^64 in the intermediate.
- Drill productivity: per mille credit per unit drawn; each full 1000 is a bonus unit of the same item, costing the vein nothing, going out one at a time after the drawn unit (so a partial insert can never duplicate). Picking a drill up returns the bonus units with the held one.
- Research speed: a lab's speed is its speed times (1000 + effect per mille) / 1000.
- Prices: every item needs a positive `price` (loader refuses otherwise).
- Journal: the Contracts section is an extra last tab after the chapters. HUD: `contract_objective_lines` gives the oldest open contract's name and line; nothing draws it yet (0042).
- New hint counters for chapter 8: `contracts_completed`, `contracts_late`, `credit_earned`, `surveys_bought`.
- Test pitfall found: `text()` stores missing keys in the shared string table with the caller's allocator, so a test running under the temp allocator that renders an unknown key corrupts other tests. The new test switches to the heap allocator for that call; `lookup_text` could clone with a fixed allocator instead (not changed, outside the item).

### Guessed numbers

All contract contents, deadlines (30 to 60 min), late shares (30 to 50 percent), rewards, tier thresholds 0/3/10, catalogue (50 silicon 600, 50 aluminium plate 750, 20 gold plate 600, 100 science pack 2 2250, survey 3000). Item prices (data/items.sjson header): raw and ore 1, coal 2, plates 2, bronze/brass/nickel 3, glass 2, steel 12, gear 4, circuit 6, pipe 2, science pack 1 7, plastic 5, sulfur/bitumen 3, science pack 2 15, alumina 4, aluminium plate 10, silicon 8, gold ore 8, gold plate 20, quartz 3, concrete/asphalt 3, schematics 50, machines about the sum of their inputs (launch pad 1800, rocket structure 160, guidance unit 80, cargo capsule 290). Infinite technologies: 30 s per pack, prerequisite `rocket_program`.

### Not verified

Everything visual: the pad panel tabs (tab row, contract lines and catalogue buttons in the 696 unit wide area at 720p, 1080p, UI scale 1.5; long contract names), the journal Contracts tab layout, technology screen level text, toast lengths of the longer Mission Control lines, focus movement on the catalogue buttons with the gamepad. The orbital survey against the real generator was only tested with the test generator around the origin; its cost at 256 blocks (about 25 regions of vein placement) was not measured. The user verify (contracts on time and late, a survey filling the map, mining productivity twice) is covered by tests, not played.

### Open questions

- Should the late survey contract pay something less instead of the full survey?
- Should contract survey rewards count in `surveys_bought`?
- Should infinite research auto requeue (now it does) or stop after each level?
- Prerequisite of the infinite technologies: `rocket_program` (a quest gate, like `rocketry`) or something earlier?
- Docs outside this item need lines from the main agent: DESIGN.md (tier thresholds, catalogue), `doc/content.md` (prices, contracts, infinite technologies), `doc/ui.md` (pad tabs, journal Contracts tab), `doc/architecture.md` (venture state on the world, generator in the simulation content), `doc/quests.md` (message `{value}` and `{cargo}`, new counters).
