# 0040 Launch pad, rocket parts and shipments

Status: todo
Milestone: M9

## Goal

The phase 8 loop from DESIGN.md: a launch pad and rocket parts as the big sink, and shipments that carry cargo to the venture. No building is mandatory, the pad included.

## Deliverables

- Rocket parts as data: rocket fuel (chemical plant, light oil and sulfur, or wood gas based alternative on the schematic channel), rocket structure (assembler, aluminium plate and steel), guidance unit (assembler, silicon, copper wire, plastic), and a cargo capsule item (steel and plastic). Technologies: `rocket_program` stops being a placeholder but stays a quest gate and unlocks the launch pad, rocket structure and guidance unit; `rocketry` (science packs 1 and 2, 200 packs, prerequisite rocket program) unlocks rocket fuel and the cargo capsule.
- Launch pad entity (9 by 9 by 2, electric 200 kW while assembling): a panel with part slots (10 rocket structure, 2 guidance units, 200 litres of rocket fuel through a fluid port, 1 cargo capsule) and a cargo section of 8 slots, an Assemble button that turns the parts into a rocket over 60 seconds when all parts are present, a Launch button (and Interact when the rocket is ready) that consumes the rocket and the cargo, plays a placeholder ascent (a box rising over 5 seconds in the renderer), and records a shipment {tick, cargo items and counts} on the world. Inserters can feed the part and cargo slots through the transfer interface with the slot rules.
- Shipments: a `shipments` list on the world, saved, with a per item total shipped statistic and a `rockets_launched` counter for quests; the statistics screen gets a Shipments tab listing them.
- Rendering: the pad as a flat placeholder platform with a tower, the rocket as a tall box on the pad while assembled, the ascent as the box rising and fading.
- Tests: part slot rules through the transfer interface, assembly timing, launch consuming parts and cargo, shipment recorded and saved, the statistics, technology gating, determinism over 1200 ticks with an inserter fed pad.

## Verify

- Builds and tests pass.
- User: assemble a rocket from inserter fed parts, load the cargo, launch, and see the shipment in the statistics.
