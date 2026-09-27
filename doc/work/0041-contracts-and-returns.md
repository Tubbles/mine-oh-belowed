# 0041 Contracts, trade returns, orbital survey and infinite research

Status: todo
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
