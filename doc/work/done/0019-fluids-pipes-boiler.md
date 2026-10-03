# 0019 Fluids: pipes, networks, offshore pump, boiler, tank

Status: implemented
Milestone: M4

## Goal

The fluid model from `doc/fluids.md` with water and steam: pipes and networks, gravity for liquids, the offshore pump, the boiler producing steam from water and fuel, the storage tank, and the pump entity that waits for power.

## Deliverables

- `data/fluids.sjson` with water and steam (name key, phase, colour) and fluid ports on machines in `data/machines.sjson` (offshore pump output, boiler water input and steam output, steam engine steam input, tank on all faces, pump input and output), with buffer capacities.
- Pipe entity kind and fluid networks per `doc/fluids.md`: segments with capacity and level, per tick balancing with flow limits, one fluid per network, gravity for liquids, gases ignoring height, deterministic connection order, rebuild on topology change.
- Offshore pump (valid next to a water source block), boiler (fuel slot, water in, steam out, 1.8 MW fuel burn only while producing), storage tank, pump (moves fluid uphill, unpowered until 0020 so it does nothing yet and says so).
- Panels: fluid, level, flow, fuel slot for the boiler, state texts by key.
- Rendering: pipes as thin boxes with connection stubs and a level band, ports as coloured squares, tanks and boilers as placeholder boxes.
- Tests: balancing between two pipes reaches equal levels, flow limit per tick, no mixing, gravity blocks uphill flow for water and not for steam, pump moves uphill, boiler consumes water and fuel and produces steam at the rates, tank capacity, network rebuild after removing a middle pipe, determinism over 1200 ticks.

## Verify

- Builds and tests pass.
- User: pipe water from a lake into a boiler, fuel it, and watch steam fill a tank on a higher ledge only when a pipe runs downhill from the boiler to it (steam ignores height, water does not).

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/fluids.sjson` (new), `data/machines.sjson` (kinds `pipe`, `offshore_pump`, `boiler`, `steam_engine`, `storage_tank`, `pump` with `fluid_ports`, `buffer_litres`, `flow_litres_per_second`, `fluid_litres_per_second`), `data/strings/en.sjson`, `fluid.odin` (registry), `machine_fluid_ports.odin` (port definitions, validation, rotation, placed faces), `fluid_machine.odin` (pipe and fluid machine entities, offshore pump, boiler, pump ticks, placement checks), `fluid_network.odin` (segments, connections, rebuild, balancing), `ui_fluid.odin` (panels, HUD line), `render_fluids.odin`, `fluid_test.odin`, plus changes to machine, entity, placement, item transfer, machine panel, HUD, formatter, loop, main, the ghost and the test world and machine tests. Items and recipes for all six already existed; nothing was added there.

### Model and deviations

- Entities: one `Pipe` pool and one `Fluid_Machine` pool for the five fluid machines (the machine kind decides the tick, panel and model), so two new entity kinds rather than six.
- "Fuller" is by fill fraction, not by litres: the amount is the one that equalises the two fractions, `(from * to_capacity - to * from_capacity) / (from_capacity + to_capacity)`. Between equal capacities this is exactly half the level difference of the brief. Comparing litres would stop a pipe from ever filling a tank past 100 L.
- Rounding: whole litres leave up to one litre per connection unmoved, and along a chain of pipes that adds up (a 20 pipe run would fill a tank to about 80 percent). The amount is rounded up when it moves away from the network's output ports (connection count from the nearest output port, computed at rebuild) and down otherwise. So a source fills everything downstream exactly to capacity, and because the way back always rounds down no litre ever moves back and forth. Between two plain pipes with no output port anywhere the brief's floor of half the difference holds.
- Pumps and gravity: a pump only moving its rate between its own buffers would lift water one block at most, since the pipes above its output would still refuse to push up. A network that holds the output port of a running (powered) pump ignores height. That is how "the pump moves fluid uphill" reads here.
- Segment heights: a pipe's cell, a port's cell, the tank's bottom layer (so a tank drains only into pipes at its bottom layer or lower, and pipes at any layer can fill it).
- One fluid per network: set by the first giving port with fluid when the network is empty, cleared when the open segments hold nothing. A port is closed ("Mixing refused" in its panel line) when it holds another fluid, or is empty and filtered to another fluid. When a rebuild joins two networks with different fluids in their pipes, the network takes the fluid of the first such pipe in pool order and the pipes holding the other fluid are emptied (the fluid is lost).
- Offshore pump: footprint width 2, depth 1 (the 1 by 2 of content.md read along its facing, like the splitter). Its output port is at the -x end, its intake is the +x end, and it is valid when the cell in front of the intake at its own height or one below is a water source block. The check runs at placement only; removing the water later does not stop it. Rotation follows the facing like drills (rotation 0 points the intake away from the player). The pump uses the same facing rule, input at -x, output at +x.
- Boiler ports on the long sides at the bottom layer (water in on -z, steam out on +z); the steam engine's two input ports are separate buffers, so steam does not pass through an engine. Boiler states in check order: idle (no water and no fuel), no water, output full, no fuel, producing. Fuel burns only on producing ticks.
- Pipes may stand on a solid block or on another pipe, like belt lifts on lifts, so they climb in columns. Horizontal runs over a gap are not possible.
- Rotating a placed fluid machine or pipe is not supported (ports would move); Rotate only turns the ghost.
- Picking up a pipe or machine loses its fluid; a boiler returns its fuel.
- The panels show a level line ("Water: 150 L of 200 L") and a flow line (in and out per minute, from the last tick's transfers) per buffer, the boiler's fuel slot and burn bar, and a state for the offshore pump, boiler and pump. The HUD line shows the state, or a pipe's fluid and level.

### Constants

Pipe 100 L, 1200 L per second per connection (20 per tick). Port buffers 200 L, tank 25,000 L. Offshore pump and pump 20 L per tick, boiler 1 L per tick and 30,000 J per tick. Render: pipe core 0.36, stubs 0.24 thick, level band 0.02 wider than the core, port squares 0.5 by 0.03.

### Not verified

Everything visual and the feel: pipe stubs and level bands, machine colours, port squares and their colours, the direction arrows and ghost ports, panel layout and text widths at 720p and 1080p and UI scale 1.5, the HUD line. The user verify (lake, boiler, steam tank on a ledge) is not run. The shipped data was loaded through the real loader by starting the binary without a display.

### Open questions

- Throughput depends on direction: connections run in coordinate order, so fluid crosses several connections in one tick when it flows towards higher coordinates and one per tick the other way. The tank fill test (offshore pump, three pipes towards -x, tank) holds 24,527 L after 3000 ticks (about 8 L per tick instead of 20) and is full within 6000. Wanted, or should connections run in an order from the output ports outwards?
- Is pressurising the whole output network of a running pump the intended pump model (architecture.md describes a network fill level instead)?
- Does the offshore pump rule (water at the intake's height or one below) match real shores in generated worlds?
- `doc/fluids.md` needs the fill fraction rule, the rounding towards downstream, the pump pressurising its network and the tank's height; `doc/content.md` the fluid values now in `data/machines.sjson`; `doc/architecture.md` the network fill level sentence. This run could not touch them.

