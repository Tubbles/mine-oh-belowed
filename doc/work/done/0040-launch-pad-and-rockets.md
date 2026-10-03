# 0040 Launch pad, rocket parts and shipments

Status: implemented
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

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (541 tests, 9 new in `launch_pad_test.odin`), `./build.sh`, `./build.sh release`, `--version`; the shipped data loads through the real loader (the binary stops only at opening a window).

Files: new `src/launch_pad.odin` (entity, states, stages, slot rules, launch, shipments), `src/ui_launch_pad.odin` (panel, Shipments tab), `src/launch_pad_test.odin`; changes to machine, fluid ports, entity, placement (pick up), item transfer, power and fluid networks, save, world, statistics, quest counters, player (Interact), loop, machine and crafting machine panels, statistics screen, renderers, the data files and strings, and the count and technology assertions of existing tests.

### Model

- `launch_pad` is its own machine and entity kind with fields in `machines.sjson`: `launch_parts` (item and count, one slot each, at most 3), `launch_fuel_litres`, `assembly_seconds`, `launch_seconds`, `slots = 8` for the cargo, and one input port filtered to rocket fuel (400 L, on the -z face middle cell). `MAXIMUM_FOOTPRINT_SIZE` went from 8 to 9 for it.
- States: waiting for parts, ready to assemble, assembling, rocket ready, launching. "Consumes them over the 60 seconds" is read as ten equal stages: each stage takes its share of every part and of the fuel when it starts (a structure and 20 L per stage, a guidance unit at the 5th and 10th, the capsule at the 10th). A share that is missing (the player took parts out) pauses the assembly without asking for power; it goes on once the share is back. Power is 200 kW while assembling, one tick of work per power credit step, so a brownout lengthens it.
- Launch: the panel button or Interact sets `launch_requested`; `apply_launch_requests` runs in `simulation_tick` right after the entity tick, since the shipment needs the tick. Sneak with Interact opens the panel, like the power switch. Interact posts a "Launch sequence started" toast.
- A shipment is {tick, up to 8 distinct items with counts}, merged per item in slot order, kept in `World.shipments` and saved after the research state. `Statistics.shipped` (per item) and `rockets_launched` (also a quest counter `rockets_launched`) are saved with the statistics. Shipped cargo is not counted as consumed; parts and fuel taken by the assembly are.
- Transfer: parts go only to their slot, up to a rocket's count even from a larger stack (`slot_insert_limit`); anything else goes to the cargo; nothing is given. The player's panel lets any item into the cargo, parts included.
- Picking up a pad returns its slots and the parts already built into the rocket (by stages taken); the fuel is lost.
- Rendering: a 0.4 high platform over the footprint, a 1 by 14 tower on the origin corner, the rocket a 2 by 12 white box that grows with the assembly, stands while ready, and rises (quadratic, 120 blocks) and fades over the ascent. The fuel port square draws like other ports. No bottleneck marker for the pad.

### Deviations

- The wood gas rocket fuel takes 60 L of wood gas and 1 coal, not wood gas alone: the chemical plant picks its fixed recipe by its inputs, and wood gas alone already names the plastic schematic recipe, so the loader refuses the pair. Coal keeps it oil free.
- The chemical plant's output port lost its mining fluid filter, because rocket fuel goes into the first output port too. One plant still makes one fluid at a time; a craft waits until its output fits.
- `rocketry` has the quest gate `rocket_program` as its prerequisite, as briefed; DESIGN.md says no other path waits for a gated technology (`cracking` already does the same with `oil_processing`).
- A new schematic item (`schematic_wood_gas_rocket_fuel`) joins the cave crate pool, so crate contents per site change for existing seeds.

### Guessed numbers

Launch pad recipe 100 steel, 100 concrete, 50 circuits, 50 pipes (hand or assembler, 2 s). Part stack size 10. Rocketry 30 s per pack. Rocket fuel colour (230, 110, 50). Tower 14 blocks, rocket 2 by 12, ascent 120 blocks.

### Not verified

Everything visual and the feel: the platform, tower, rocket growth and ascent, fade with alpha on a depth tested cube, the port square, the panel layout (two slot rows, part lines, fuel rows, two buttons, 696 units wide) at 720p, 1080p and UI scale 1.5, the Shipments tab list and totals, the toast. The user verify (inserter fed rocket, launch, shipment in the statistics) is covered by tests, not played.

### Open questions

- Should cargo count as consumed in the production statistics, or stay only in the shipped totals?
- Should the panel refuse parts in the cargo section, so a player cannot ship parts by accident?
- A Mission Control line and a message log entry on launch (the first shipment's "self sufficient" message is 0042's)?
- `doc/content.md` (phase 8 values), `doc/logistics.md` (pad slot rules in the transfer interface), `doc/fluids.md` (chemical plant output port, pad fuel port), `doc/ui.md` (pad panel, Shipments tab, Interact launches) and `doc/architecture.md` (shipments on the world) need updates; this run could not touch them.
