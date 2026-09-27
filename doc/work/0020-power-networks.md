# 0020 Power: poles, networks, steam engine, brownouts

Status: implemented
Milestone: M4

## Goal

Electric networks from `doc/fluids.md`: poles with supply volumes and wire reach, the steam engine as generator, proportional brownouts, the power switch, the power overview screen, and the first electric consumers running: electric mining drill, electric and filter inserters, lamp, pump.

## Deliverables

- Pole entity (small pole), automatic connection within reach, networks as connected components rebuilt on topology change, supply volumes assigning electric machines to networks.
- Steam engine entity drawing steam through the fluid network and offering up to 900 kW, the per tick energy balance with satisfaction, generators burning only for delivered energy, consumers running at the satisfaction fraction.
- Electric machines join the balance: electric mining drill (mines at satisfaction speed), inserter and filter inserter (their cycle scaled), pump (moves fluid), lamp (light level 14 while powered above a threshold, off otherwise, through the block light path with the lamp as a light emitting entity cell or a light block swap; say which).
- Power switch entity joining and splitting networks.
- Power overview screen (from the pause menu and a new action) listing networks with supply, demand, satisfaction, generators and top consumers; HUD brownout warning; "no power" state in machine panels.
- Tests: pole connection by reach, supply volume membership, satisfaction arithmetic with two generators and three consumers, brownout scaling of a drill's output rate, steam consumption proportional to delivered energy, switch splitting a network, lamp turning on and off with power, determinism over 1200 ticks.

## Verify

- Builds and tests pass.
- User: pump, boiler and engine power a lamp and an electric drill; adding drills until the engine is short makes everything slow down together and the overview shows why.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/machines.sjson` (`electric_mining_drill`, `small_pole`, `power_switch`, `lamp`, steam engine `electric_output_kilowatts` and `fluid_litres_per_second`, fields `supply_volume`, `wire_reach`, `light_level`), `data/strings/en.sjson`, the hint counter comment in `data/quests/chapter_01.sjson`, new `power_machine.odin` (poles, lamps, power credit, steam engine energy, entity light sync, switch toggle), `power_network.odin` (nodes, wires, networks, memberships, energy balance, tick), `ui_power.odin` (overview screen, panel lines, HUD warning), `render_power.odin`, `power_test.odin`, plus changes to machine, entity, drill, inserter, fluid machine, fluid network, world light, World, statistics, quest hint counters, player (Interact), input actions and bindings, screens, HUD, machine and fluid panels, renderers and the test world. Items and recipes for all four existed already.

### Carry over from 0019: fluid flow order

- Connections now run in order of the nearer end's distance from an output port (breadth first, computed at rebuild), ties and networks without an output port by coordinate.
- The order alone did not reach the pump's rate: fill fraction balancing needs a large level difference per connection to move 20 L, and between a 100 L pipe and a 25,000 L tank the tank cannot pass about 80 percent at full rate. So a connection that leads away from the output ports now pushes everything the fuller side holds, capped by the flow limit and the room (`fluid_push_amount`); every other connection balances fill fractions rounded down as before. The rounding up rule of 0019 is gone, the push replaces it. `doc/fluids.md` ("As implemented in 0019") needs this.
- Test: pump, three pipes and a tank towards -x and the mirror towards +x both reach 99 percent in exactly 1258 ticks (19.7 L per tick). The existing fluid tests pass unchanged.
- Side effect to watch: a branch point pushes into its first downstream neighbour (by coordinate) first, so a tank on a branch can take the whole flow until its fill fraction passes the junction's, and a steam engine on the other branch waits meanwhile.

### Model and choices

- Poles and switches share one `Pole` pool (entity kind `Pole`), lamps have their own. Supply volume 5 by 5 across centred on the pole and 4 high starting at the pole's bottom (a 4 high box cannot centre on a 3 high pole; this covers machines next to the pole and one layer above it). Wire reach is the straight line distance between origins, the shorter reach of the two counts.
- Networks: union find over wires, an off switch is inactive and its wires carry nothing (they are still drawn). A lone switch that is on counts as a network of its own. Memberships (a map from handle to network, `entity_network`) are rebuilt with the networks on every pole, switch or electric machine placement or removal and on every toggle.
- Balance each tick before drills and inserters: consumers ask `watts / tick rate` joules (integer division like fuel: inserter 216, lamp 83, pump 500, electric drill 1500) only while they have work (inserter while its arm swings, drill with an empty hand and a live vein, pump with input fluid and output room, lamp always). Satisfaction per mille is `min(supply, demand) * 1000 / demand`; with no demand it is full when anything could give and 0 otherwise. Each consumer receives `demand * satisfaction / 1000`; the generators share the sum received in proportion to their offers, rounded down, the leftover joules to the first ones, so produced always equals consumed.
- Working at the satisfaction fraction: a power credit per machine gains the satisfaction each tick and pays one tick of work per 1000 (at 50 percent every other tick). This keeps the existing tick counts of inserters and drills and makes rates exact. Pumps move `rate * satisfaction / 1000` litres. `powered` on inserters and fluid machines became `power: Power_State`.
- Steam engine: offers `min(15 kJ, fuel_joules + steam litres * 30 kJ)` and turns whole litres into joules only as the delivered energy needs them; the remainder waits in `fuel_joules`. 30 kJ per litre comes from the data (900 kW over 30 L per second). New state "No steam".
- Electric drill: the drill code with `slot_count` 0 (no fuel slot); 30 units per minute at the 80 percent reference, a 96 tick cycle, 37.5 units per minute in total. New drill state Unpowered.
- Lamp light: an entity light source list, `World.entity_lights` (cell to level), read by the light code as a cell's emission next to its block's. Chosen over an invisible light block because entity cells are air in the chunk data and a light block would need its own block id, mining rules and meshing exclusions. `tick_lamps` compares the lit lamps with the list each tick in coordinate order and turns changed cells on or off through `set_entity_light`, which clears through the removal queue; a picked up lamp disappears from the list the next tick.
- Power switch: Interact turns it like a lever (world action, breaks hands off objectives), Sneak with Interact opens its panel, where a choice row turns it too. The brief asked for both; Interact cannot both open the panel and toggle. The HUD hint says "Turn" on a switch.
- Overview: `Open_Power_Overview` on keyboard P and a pause menu button; network list on the left, the focused network's supply, demand, satisfaction, generator count and the five largest consumer groups by current demand (grouped by machine type, `name xN  power`). It does not pause.
- Statistics: `energy_produced_joules`, `energy_consumed_joules`, `brownout_ticks`, `unpowered_machines` (last tick) and `unpowered_machine_ticks`; hint counters `brownout_ticks` and `unpowered_machine_ticks`.

### Constants

Power credit and satisfaction in per mille (`POWER_FULL` 1000), lamp on above 500. Render: pole 0.2 wide post, wires 0.15 below the pole top, switch cube 0.6 (green on, red off), lamp cube 0.4, electric drill blue, supply volume ghost outline light blue.

### Not verified

Everything visual and the feel: pole, wire, switch, lamp and drill models and colours, the supply volume ghost, the lamp's light in the rendered world, the overview layout and the panel rows at 720p and 1080p and UI scale 1.5, the HUD brownout line position, the Sneak with Interact gesture on both gamepad backends. The user verify (pump, boiler and engine powering a lamp and an electric drill, brownout with more drills) is not run. The shipped data was loaded through the real loader by starting the binary without a display.

### Open questions

- Is the downstream push the wanted fluid model? It makes throughput match the pump rate but lets a branch starve the other branch for a while (above).
- Switch: lever on Interact with Sneak for the panel, or panel on Interact like every other machine?
- Supply volume height: from the pole's bottom up (chosen) or one below to two above?
- Should idle consumers (zero demand) appear in the overview's largest consumers? They do not now.
- `doc/fluids.md` (flow order and push, entity light sources, switch gesture, supply volume height), `doc/content.md` (power values now in `data/machines.sjson`, electric drill 37.5 units per minute in total) and `doc/input.md` (P, Sneak with Interact) need updates; this run could not touch them.
