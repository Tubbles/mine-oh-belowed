# Fluids, power and research

How liquids, gases and electricity move, and how assemblers and labs turn them into work. Everything runs per tick in integers: litres, joules and per mille. The values (rates, buffers, heads, powers) are in `data/machines.sjson` and `data/fluids.sjson`, whose headers explain each key. The phase and ratio rules are in [content.md](content.md).

- A fluid network is a connected set of pipes and machine ports holding one fluid. An electric network is a connected set of poles. Every consumer in it gets the same share of its demand.
- Networks are rebuilt when a member is placed or removed and evaluated every tick in a fixed order, so the result never depends on timing.

## Fluid networks

`fluid_network.odin`. A segment is one pipe block or one port buffer of a machine. The litres live on the entities, so a rebuild keeps them.

- Pipes connect on all six faces to pipes and to ports facing them. Pipes stand on solid blocks or on other pipes, so they climb in columns.
- A network holds one fluid: the first that enters, kept until the network is empty. A port holding another fluid, only taking another, or refusing the fluid by its phase filter is closed and moves nothing. Each closing counts as a mixing refusal (`mixing_refusals`) and the panel says why. When two networks join, pipes holding the other fluid lose it.
- Per tick the connections run outwards from the output ports, breadth first, ties in coordinate order. Along a connection leading away from the output ports the fuller segment pushes everything it can within the flow limit and the room, so a pump's rate crosses a whole run in one tick in either direction.
- Every other connection evens the fill fractions, rounded down, so a pipe can fill a tank past its own capacity and a litre never bounces between two full segments.
- The flow limit per connection is the pipe's `flow_litres_per_second` in whole litres per tick.
- Gotcha: at a branch the first downstream neighbour in coordinate order is served first, so a tank on one branch can starve an engine on the other until the tank's fill fraction passes the junction's.
- Picking up a machine loses its fluid. Placed pipes and fluid machines do not rotate.

### Height and pump head

Rule: a liquid rises only as high as a running pump's head allows (0139). Gases ignore height.

- A segment's height is its cell's y. A storage tank's port on every face counts at the tank's bottom.
- Every pump kind has `head_metres` (one block is one metre), required on those kinds and refused on others. A network's head line is the highest outlet height plus head of the running pumps whose output port is in it (`tick_head_line`).
- A liquid moves into a higher segment only while that segment is at or below the head line. Level and downhill moves are always allowed. A network without a running pump outlet, such as a refinery's output, never lifts liquid.
- A pump runs when its output port is open, it has power or needs none, and its input side holds fluid. The offshore and tar pit pumps stand at their source, so their input side always does. The electric pump needs a litre in its input buffer, or to have moved fluid this tick, since it may have drained its input to zero doing so.
- A pump pushing against a full output still runs, as a real pump holds its head against a closed pipe.
- A pump moves its rate from its input side to its output side whatever the heights, and its ports sit in different networks, so pumps in series chain: each outlet sets its own network's line.
- Pipes and every port in a fluid machine's panel show "Above the pump's head" in place of the flow when they stand above the line of a network with a running pump. Crafting machine, drill and launch pad panels do not. Pump panels show the head. Placement is not checked against the head.

### Fluid machines

`fluid_machine.odin`. One pool, the machine's kind decides the tick. Machines run before the networks, so what they make flows on in the same tick.

- Offshore pump: two blocks wide along its facing, valid with a water source in front of its intake end at its height or one below, checked at placement. It needs electricity: it pumps a full tick's litres once per power credit step, so over a second it yields its rate times its network's satisfaction exactly, and starts Unpowered.
- Tar pit pump: placed like the offshore pump, with a block whose `fluid_source` is crude oil in front (the tar flats' pits, infinite). Its rate is litres per minute, whole litres as the minute adds up, one tick of pumping per power credit step.
- Electric pump: its rate times the satisfaction per tick, truncated, from its input port to its output port.
- Boiler: turns water into as much steam, burning fuel only on the ticks it produces.
- Steam engine: input ports only. A litre of steam is `electric_output_kilowatts` times 1000 over `fluid_litres_per_second` joules (30 kJ), drawn a whole litre at a time only for the energy delivered.
- Storage tank: one port on every face. Its buffer is the tank. It holds gases too.
- Flare stack: a relief valve that burns gas only while its port is at least `FLARE_RELIEF_PERCENT` full. The network evens fill fractions, so generators and chemical plants on the same gas are served first. Burned gas counts as voided.
- Rendering (`render_fluids.odin`): a pipe shows a stub per connection and a band at its level in the fluid's colour. Ports are coloured squares on the footprint.

### Oil and chemistry

The recipes are in `data/recipes.sjson`, the port layouts in the header of `data/machines.sjson`.

- A crafting machine may have fluid inputs, fluid outputs and no item slots at all. A fixed choice machine picks its recipe by the loaded items, then by the fluids in its input ports.
- A craft starts only when every fluid input is fully present and every output would fit, and takes its fluids at the start like items, so it never stalls part way.
- The refinery's three outputs leave by fixed faces, each filtered to its fluid. Under strict byproducts a refinery whose gas has nowhere to go stops: the flare stack and the combustion generator are the sinks.
- The chemical plant's second input and its output port have no filter, so the fluids present and the loaded item pick the recipe. Wood gas alone picks the schematic's wood gas plastic.

## Power

`power_network.odin`, `power_machine.odin`.

- Poles and power switches are the nodes. Two nodes are wired when their footprint centres (across, at the bottom) are at most the shorter of their two `wire_reach` apart. A switch that is off takes part in no network.
- A pole's `supply_volume` is centred across its footprint and starts at its bottom. An electric machine or generator belongs to the network of the first pole whose volume covers one of its cells, and to none otherwise. Its panel then says so.
- Networks and memberships are rebuilt when a pole, a switch or an electric machine is placed or removed, or a switch turns. Interact turns a switch. The inventory binding opens its panel ([input.md](input.md)).

### Balance

Rule: satisfaction is supply over demand, capped at one, and every consumer receives that share: a proportional brownout that slows every machine alike, as in Factorio.

- Per tick in joules: consumers ask for their power while they have work (an inserter only while its arm moves, an offshore pump while its port has room), generators offer what they can give.
- Brownout slowdown is power credit: every tick adds the satisfaction in per mille, and a machine takes one tick of work per `POWER_FULL` collected, so tick counts stay exact.
- Generators serve in `dispatch_order`: the lowest order gives up to its offers first and each next order only what is left. Within an order the energy splits in proportion to the offers, the leftover joules in pool order. Hydro turbine 0, steam engine 1, combustion generator 2, fuel generator 3.
- Generators share only what the consumers received and burn fuel, steam or gas only for their share, so produced equals consumed.
- A lamp shines while its network gives more than `LAMP_ON_ABOVE` per mille. Lamps are entity light sources beside block light.
- The power overview lists each network with supply, demand, satisfaction, its generators and largest consumers. The HUD warns while any network is below full.

### Generators

- Combustion generator: burns the gas in its one `burnable_gas` port first, whole litres at the gas's `fuel_kilojoules_per_litre`, then fuel items at `fuel_efficiency_percent`. Steam never enters the port.
- Fuel generator (0140): a combustion generator without ports at 25 percent, hand crafted from the start. It carries the offshore pump for the first boiler and little else: its fuel goes four times as fast as a boiler's for the same energy, so the steam plant is the goal.
- Every combustion generator's panel shows its efficiency and the burn time left at full output.
- A steam plant whose engines power its own offshore pump restarts only through a generator with fuel: the benchmark's power module and the developer kits of chapters 4 and 5 carry one. The benchmark counts a generator in the Idle state as a reserve ([architecture.md](architecture.md), Performance).
- Hydro turbine: no fuel and no ports. `hydro_kilowatts_per_water_level` times the flowing water levels in its eight cells, up to its output, read from the blocks every tick. It needs support below and one cell of flowing water at `hydro_minimum_water_level` or more. Source water counts nothing, and every flowing block counts as moving since the water has no velocity. Water keeps flowing through it.

## Assembler, lab and research

- A crafting machine with a chosen recipe (the assembler) picks it in its panel through the recipe browser, filtered to its category. It has one input slot per ingredient and one output slot per product. Machine panels stay open under the recipe browser and the technology screen.
- Inserters stop filling an input slot at `INSERTION_LIMIT_CRAFTS` crafts or pack sets ([logistics.md](logistics.md), Item transfer).
- One technology is queued at a time (`lab.odin`). A lab with power and one of each of its packs takes a pack set, works the time per unit at its speed and adds a unit to the shared progress. Labs start a unit only while the units done plus those in progress are short of the cost, so they never overshoot.
- Progress is kept per technology across switches. A unit in progress for the old queue is dropped with its packs. A lab has one slot per pack item any technology consumes.
- A finished technology opens its research channel recipes, posts a toast and a message log line. A finished infinite level empties the queue like any other.
- Labs refuse `placeholder` and `quest_gate` technologies. The screen shows them locked. The screen itself: [ui.md](ui.md), Technology screen.
- The launch pad has a rocket fuel port and takes each of its ten assembly stages' share of parts and fuel when the stage starts, pausing where a share is missing (`launch_pad.odin`).
