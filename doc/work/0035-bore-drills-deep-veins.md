# 0035 Bore drills, deep veins and vein revival

Status: todo
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
