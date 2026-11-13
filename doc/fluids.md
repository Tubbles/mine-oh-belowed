# Fluids, power and research

How liquids, gases and electricity move, and how assemblers and labs turn them into work. Everything runs per tick in integers: litres, joules and per mille. The values (rates, buffers, heads, powers) are in `data/machines.sjson` and `data/fluids.sjson`, whose headers explain each key. The phase and ratio rules are in [content.md](content.md).

- A fluid network is a connected set of pipes and machine ports holding one fluid. An electric network is a set of machines and junction boxes joined by cables run by hand. Every consumer in it gets the same share of its demand, except behind a cable too thin for what lies beyond it.
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

`power_network.odin`, `power_machine.odin`, `cable.odin` (the cable table), `cable_field.odin` (the run by hand).

- Every power connection is a cable run by hand from one power port to another (0368). Every electric machine and generator has one power port, the first of its `ports`, of at least its rating; a junction box has four (`a` to `d` on its side faces), a junction cabinet eight, a power switch two (`a`, `b`). Vessel parts list theirs ([vessels.md](vessels.md)).
- A cable is one of three items: light (300 kW, spans up to 20 m), heavy (3 MW, 30 m) and trunk (24 MW, 50 m), one item a metre. It carries the least of its item's and its two ports' capacities. Its span is the distance between its ports' points (the centres of the port faces), rounded up to whole metres, and costs as many items. Taken up, or with either end picked up, its metres come back whole: the field refuses the pick up `Inventory_Full` when they do not fit, the block world spills them.
- The netlist (`src/netlist/`): a node per live entity with a power port, its ports joined inside it, and two for a power switch that is off (port `a` on one, `b` on the other). An edge per cable; parallel cables between two nodes add their capacities. Nodes are numbered in pool order (junction boxes and switches, then the consumers' and generators' pools in the balance's order, then vessel parts), so leftover joules go in a fixed order. The netlist never sees a position: a span is measured when a cable is laid, aimed at or drawn, and only its whole metres are stored.
- A cable may close a loop. It is laid, and one bundled edge of the loop, chosen by the sorted node order, becomes a chord that carries nothing until 0377, so laying a cable can idle an older cable of the loop while every node stays joined.
- An electric network is a tree of the netlist holding a cable. The overview, the HUD warning and the statistics read only those. A consumer with no cable, or in a tree with no generator and no battery (Batteries), is unpowered (the `unpowered_machine_ticks` statistic), and its panel says so. A vessel's own network, a tree whose participants are all vessel parts, raises no warning (0383): its consumers, a control unit with no cable among them, are not counted unpowered, and its brownout neither shows on the HUD nor counts in `brownout_ticks`, so a vessel built with empty batteries feeds no hint. A tree that also holds a machine on the ground (a docked vessel) counts as any network does, its vessel parts included.
- The netlist is rebuilt when a cable is laid or taken up, an entity with a power port is placed or removed, or a switch turns. Interact turns a switch (X on the gamepad, F) ([input.md](input.md)).
- A cable's load (0369, `cable_load`): what it carried in the last balance, its share of its bundle's flow in proportion to its watts, rounded down, against its watts. A cable limits when raising it, together with the other cables at capacity on the power's path, would give some consumer on the side it feeds more, even if the total stays the same: between two short regions a thicker cable moves power from the richer to the poorer, and of two full cables in series (an engine on a light cable into a box with nothing else on it, a light cable on to the machines) both limit, though raising either alone gives nothing. What a cable feeds is the equal level region at the end its flow enters and, through cables at capacity that carry the power on, the regions beyond. A level of it costs `ceil(D / 1000)` joules (at least 1, `D` its demand) plus a joule per consumer, since the solve leaves each spare joule under the next level of every region it reaches and under a joule per consumer (0373): up to that much room can stay unused under a cable that bounds a region (4995 of 5000 J). The cable is at capacity while the room left in its flow's direction is under a level's cost. It limits while it is at capacity, what it feeds lies lower (the fed end's level is below the feeding end's, or the regions beyond hold consumers), and both what it feeds is short of, less the spare that already reaches the fed end through cables' rooms, and what could come through reach a level's cost. What could come through is the spare that reaches the cable from the feeding side, the offers' unused joules and a charging battery's intake (the solve serves demand first), plus the share the feeding region would give up for the two to meet at a common level. On their way to the cable the two pass a cable at capacity whole and any other cable through one room they share, the spare first. A battery's unfilled room is no shortage, so a cable that only slows a charge never limits. Nor does a generator's own cable in a generation shortage, where only its rounding is spare and a generator's region has no demand to give up, nor a full generator cable beside a generator whose spare already reaches the box. One limit can be missed: power that could be given up behind a feeding end with no demand of its own at level 1000, where the region that would give way sits at another level beyond it. A cable inside the region a cable feeds whose room is under a level's cost is not seen, so on netlists of cables of a few joules (a vessel's links) a mark can be wrong. A full generator cable is also marked beside the cable that does limit when a generator of a later dispatch order with spare sits inside what it feeds, since that spare is measured at the fed end and not where the shortage enters: about 1 in 500 marks on factory shaped networks and 1 in 60 on long box chains. A junction box's, cabinet's and switch's panel shows a line per power port: free, or the load, the cable and the machine at its other end, "to" where power leaves the port or nothing flows and "from" where it enters. While the cable limits, the line reads "Port b, limiting: …" in the accent colour, the word after the port letter so that both show at the smallest size. The power overview names a network's limiting cables (Balance), each cable of a series among them, and the HUD on the field shows an aimed cable's load in place of the name line, ending in ", limiting" while the cable limits. A cable that closes a loop is the chord and reads 0 until 0377. The load is read from the last balance (the solve's flows and the per node record of `netlist.measure_edge_limits`, four passes after the solve) and kept nowhere: before the first balance after a rebuild (a load, a cable laid) no load shows.
- The run and its refusals (no free power port, the same thing at both ends, past the span, not enough cable, a vessel end that is not its connector, the first end gone) are in [input.md](input.md), Bindings.
- Old saves: the small pole, big pole and substation are `deleted_ids` of `data/machines.sjson`. A save that placed them loads with them deleted, their frames of their own released and one line `save: removed N placed machines of deleted kinds (...)`, with no refund. Its machines stand unpowered until cables are run (the user, 2026-11-11: all power hand run).

### Balance

Rule: within a region of the netlist satisfaction is supply over demand, capped at one, and every consumer receives that share: a proportional brownout that slows every machine alike, as in Factorio.

- Per tick in joules: consumers ask for their power while they have work (an inserter only while its arm moves, an offshore pump while its port has room), generators offer what they can give.
- Brownout slowdown is power credit: every tick adds the satisfaction in per mille, and a machine takes one tick of work per `POWER_FULL` collected, so tick counts stay exact.
- Generators serve in `dispatch_order`: the lowest order gives up to its offers first and each next order only what is left. Within an order the energy splits in proportion to the offers, the leftover joules in pool order. Hydro turbine 0, steam engine 1, combustion generator 2, fuel generator 3, batteries `STORE_DISPATCH_ORDER` (10, Batteries).
- Generators share only what the consumers and the charging batteries received and burn fuel, steam or gas only for their share. The statistics count as produced what the generators gave, the batteries' charge included and never a battery's discharge, and as consumed what the consumers received, so the two differ by what the batteries gained.
- A lamp shines while its node gets more than `LAMP_ON_ABOVE` per mille. Lamps are entity light sources beside block light.
- The power overview lists each network with supply, demand, satisfaction, its limiting cables (Power, 0369: their count, then the three behind the largest shortfall of what they feed, each from the end power came from), its generators, its batteries and its largest consumers. The HUD warns while any network but a vessel's own is below full.
- The balance runs through the leaf package `src/netlist/` (0355) on the cables' netlist: each node's bundled capacity in whole joules a tick (floored after bundling: a limit, no energy is lost), the solve, and each consumer's level from its own node. Where a cable carries less than what lies behind it asks for, the far side browns out at what the cable lets through and the near side stays full: a thin cable starves only what is behind it.
- Inside a region the solve counts a consumer's exact need (`demand × level / 1000`, unrounded), as the pooled rule does. A branch at its cable's limit so sits up to `1000 × n / D` levels lower than a whole joule rule would put it (`n` consumers, `D` the branch's demand) while every delivery differs by at most 1 J, which keeps a machine's work in step with the energy it draws.
- A saturated cable splits a netlist into regions with one level each, power flowing towards the shortage. A cable of capacity 0 joins nothing: what lies behind it sits at the level its own supply gives it. Every spare joule, a region's slack at its level or the room a region fed from its parent's side leaves on its cable, goes a level at a time to the poorest region it can reach, on either side, at equal levels the cheaper level first, but across a fed cable the parent's region first (0373). What whole per mille levels and whole joules leave stays undelivered, under the next level of every region it can reach and a joule per consumer. A known limit: a fed region's fill charges its parent for levels the parent cannot fund, so on rare netlists one region sits a level under the best split.

### Generators

- Combustion generator: burns the gas in its one `burnable_gas` port first, whole litres at the gas's `fuel_kilojoules_per_litre`, then fuel items at `fuel_efficiency_percent`. Steam never enters the port.
- Fuel generator (0140): a combustion generator without ports at 25 percent, hand crafted from the start. It carries the offshore pump for the first boiler and little else: its fuel goes four times as fast as a boiler's for the same energy, so the steam plant is the goal.
- Every combustion generator's panel shows its efficiency and the burn time left at full output.
- A steam plant whose engines power its own offshore pump restarts only through a generator with fuel: the benchmark's power module and the developer kits of chapters 4 and 5 carry one. The benchmark counts a generator in the Idle state as a reserve ([architecture.md](architecture.md), Performance).
- Hydro turbine: no fuel and no ports. `hydro_kilowatts_per_water_level` times the flowing water levels in its eight cells, up to its output, read from the blocks every tick. It needs support below and one cell of flowing water at `hydro_minimum_water_level` or more. Source water counts nothing, and every flowing block counts as moving since the water has no velocity. Water keeps flowing through it.

### Batteries

A vessel's batteries are the netlist's stores (0383, [vessels.md](vessels.md)): `supplies_watts` is the rate both ways (33 J a tick for the lead battery's 2000 W), `stores_watt_hours` × 3600 the capacity in joules, `stored_joules` the charge.

- A battery offers its charge up to its rate at `STORE_DISPATCH_ORDER`, after every generator, so it gives only what the generators cannot, as long as no generator is held back by its own cable. Where one is, the solve's repair spreads the shortfall over every node's room without regard to the dispatch order, so a battery can give while another generator has spare. That is the repair's rule, older than the batteries (two generators of different orders are misordered the same way); item 0389 changes it. A battery counts in its network's supply and `store_count`, and a consumer in a network with a battery and no generator is powered.
- It charges after the consumers are served, up to its rate and its room, from what the generators have left, through what that first phase left of each cable, the batteries of a region in proportion to their room (the netlist's second phase, the same solve). A battery that gave this tick takes nothing.
- A battery with no cable neither gives nor takes. The power overview lists the batteries apart from the generators, under "Batteries" with their count, each type with what it gave and, marked +, what it took.

## Assembler, lab and research

- A crafting machine with a chosen recipe (the assembler) picks it in its panel through the recipe browser, filtered to its category. It has one input slot per ingredient and one output slot per product. Machine panels stay open under the recipe browser and the technology screen.
- Inserters stop filling an input slot at `INSERTION_LIMIT_CRAFTS` crafts or pack sets ([logistics.md](logistics.md), Item transfer).
- One technology is queued at a time (`lab.odin`). A lab with power and one of each of its packs takes a pack set, works the time per unit at its speed and adds a unit to the shared progress. Labs start a unit only while the units done plus those in progress are short of the cost, so they never overshoot.
- Progress is kept per technology across switches. A unit in progress for the old queue is dropped with its packs. A lab has one slot per pack item any technology consumes.
- A finished technology opens its research channel recipes, posts a toast and a message log line. A finished infinite level empties the queue like any other.
- Labs refuse `placeholder` and `quest_gate` technologies. The screen shows them locked. The screen itself: [ui.md](ui.md), Technology screen.
- The launch pad has a rocket fuel port and takes each of its ten assembly stages' share of parts and fuel when the stage starts, pausing where a share is missing (`launch_pad.odin`).
