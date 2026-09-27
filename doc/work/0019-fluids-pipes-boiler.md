# 0019 Fluids: pipes, networks, offshore pump, boiler, tank

Status: todo
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
