# Fluids and power

The M4 model: pipes with liquids and gases, steam power, electric networks, and the first electric machines. Rates are in [content.md](content.md).

## Fluids

- A fluid is data in `data/fluids.sjson`: name key, phase (liquid or gas), colour. Water and steam in M4, the oil products in phase 6. Fluids are never items.
- Pipes are 1 by 1 by 1 entities connecting in six directions to adjacent pipes and to the fluid ports of machines. A connected set of pipes and ports is a fluid network, rebuilt when a pipe or a machine with ports is placed or removed. A network carries one fluid at a time; a port that would mix fluids stays closed and the panel says why.
- Every segment (a pipe block, a tank, a machine buffer) has a capacity in whole litres and a level. Per tick, each connection moves litres from the fuller segment to the emptier one in proportion to the level difference, capped by a flow limit per connection (1200 litres per second for pipes, 20 litres per tick). Integers only, deterministic order (connections sorted by coordinate).
- Gravity applies to liquids: a liquid segment moves fluid only to neighbours at the same height or lower. Going up needs a pump, which moves its rate from its input side to its output side whatever the heights. Gases ignore height and fill any connected volume. The phase comes from the fluid, so the same pipe network code serves both.
- Sources and sinks in M4: the offshore pump stands next to a water source block and pushes 1200 litres per second of water into its output port. The boiler takes water and fuel and outputs steam at 60 litres per second. The steam engine takes up to 30 litres of steam per second. The storage tank holds 25,000 litres and connects on every side. The pump moves 1200 litres per second uphill and needs electricity (30 kW), so it arrives with the grid.
- Panels show the fluid, the level and the flow in and out. Rendering: pipes as thin boxes with connection stubs and a coloured band showing the level; machine ports as coloured squares on the footprint.

### As implemented in 0019

- Balancing compares fill fractions rather than litres, so a pipe can fill a tank past its own capacity; between equal capacities it is exactly half the difference. Amounts round up when moving away from the network's output ports and down otherwise, so a long run fills a tank to the brim without a litre bouncing between two segments. A network holding a running pump's output ignores height, since a pump moving only between its own buffers could lift water one block. Tanks count at their bottom layer for gravity. The offshore pump is two wide along its facing and valid with a water source in front of its intake at its height or one below, checked at placement. Pipes may stand on pipes. Placed pipes and fluid machines do not rotate, picking one up loses its fluid, and joining networks that hold different fluids loses the second fluid. Known defect handed to 0020: connections run in coordinate order, so fluid flowing towards lower coordinates crosses one connection per tick and throughput depends on direction.

## Power

- Poles are entities with a supply volume (the small pole covers a 5 by 5 footprint 4 blocks high) and a wire reach (7 blocks). Poles within reach connect automatically. A connected set of poles is an electric network, rebuilt on topology change. An electric machine belongs to the network of any pole whose supply volume covers one of its cells, and to no network otherwise (state "no power").
- Per tick, generators offer energy and consumers demand it. A steam engine offers up to 900 kW scaled by the steam it can draw; consumers demand their machine power while working. Satisfaction is supply over demand, capped at one, and every consumer receives that fraction: a proportional brownout that slows every machine equally, as in Factorio. Generators burn fuel or steam only for the energy delivered. Integers in joules per tick.
- The power switch is a pole like entity that joins two networks while on and splits them while off.
- Consumers in M4: electric mining drill 90 kW, inserter and filter inserter 13 kW, assembler 75 kW, lab 60 kW, lamp 5 kW, pump 30 kW. Generators: the steam engine.
- The power overview screen lists each network with supply, demand, satisfaction, its generators and its largest consumers. The HUD shows a brownout warning while any network is below full satisfaction, and machines outside any network say so in their panel.

## Assembler, lab and research

- The assembler makes recipes with `assembler` in `made_in` at speed 0.5. Its recipe is chosen in the machine panel through the recipe browser filtered to assembler recipes and available ones. It has an input slot per ingredient and an output slot per output, and the slot rules feed the transfer interface so inserters put each ingredient in the right slot.
- The lab consumes science packs for the technology queued in the technology screen, one technology at a time per lab, at speed 1, and marks it researched on completion, which opens research channel recipes.
- The technology screen lists the technologies with status (researched, available, locked), cost in packs and seconds, what each unlocks, and lets the player queue one. It is the same graph browsing style as the recipe browser: no search box, letter wheel, focus and pointer.
