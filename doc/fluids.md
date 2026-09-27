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

### As implemented in 0020

- Fluid flow now runs outwards from the network's output ports, and a connection leading away from them pushes everything the fuller side holds within the flow cap; other connections balance by fill fraction. Throughput no longer depends on direction (19.7 L per tick either way), at the cost of a known fairness gap: at a branch the first downstream neighbour by coordinate is served first, so a tank on one branch can starve an engine on the other until the tank's fill fraction passes the junction's. Recorded as a follow up.
- Brownout slowdown is a per machine power credit in per mille, one tick of work per thousand, so existing tick counts stay exact. Generators share only the energy consumers received, so produced always equals consumed; steam converts at 30 kJ per litre, whole litres at a time. The supply volume starts at the pole's bottom and reaches four blocks up. Wire reach is straight line distance between origins using the shorter of the two reaches. Lamps are entity light sources read by the light code next to block emission, cleared through the removal queue when dark. The power switch is a lever: Interact turns it, Sneak plus Interact opens its panel. The electric drill draws 37.5 vein units per minute (30 ore on an 80 percent vein).

## Assembler, lab and research

- The assembler makes recipes with `assembler` in `made_in` at speed 0.5. Its recipe is chosen in the machine panel through the recipe browser filtered to assembler recipes and available ones. It has an input slot per ingredient and an output slot per output, and the slot rules feed the transfer interface so inserters put each ingredient in the right slot.
- The lab consumes science packs for the technology queued in the technology screen, one technology at a time per lab, at speed 1, and marks it researched on completion, which opens research channel recipes.
- The technology screen lists the technologies with status (researched, available, locked), cost in packs and seconds, what each unlocks, and lets the player queue one. It is the same graph browsing style as the recipe browser: no search box, letter wheel, focus and pointer.

### As implemented in 0021

- Technologies name their pack items and their prerequisites in the data; a prerequisite must be listed earlier in the file, which rules out cycles. The chain proposed by the implementation: logistics, electric mining and steel processing need automation; optics needs electric mining; fluid handling and prospecting need steel processing; logistics science needs logistics and fast belts need logistics science. Technologies that unlock nothing yet are marked placeholder and the loader rejects any other empty one.
- The research queue lives on the world so labs and power demand reach it. Switching research restarts the new technology from zero (keeping progress per technology is a follow up), several labs share progress and never overshoot. The technology list is sorted by name with a hide researched toggle so the letter jump stays useful. Machine panels stay open under the recipe browser and the technology screen, which is how an assembler chooses its recipe and a lab reaches the tree. Assembler slots are one per ingredient with per ingredient filters; there is no insertion limit yet, and research completion has no toast yet.

### As implemented in 0022

- Research progress is kept per technology across switches (a unit in progress is still dropped), research completion posts a toast and a message log line, automated insertion into an assembler stops at twice the ingredient count and into a lab at two pack sets while the player's hand is unlimited, and placeholder technologies show as locked and cannot be queued.

### As implemented in 0030

- Crude oil, petroleum gas, light oil and heavy oil exist as fluids. Tar flats place tar pit blocks (a fluid source like water) in low spots, the tar pit pump draws crude oil from them, the refinery splits 100 litres of crude into 45 of gas, 30 of light and 25 of heavy oil through three fluid filtered output ports on fixed faces (gas on the left, light oil ahead, heavy oil on the right of the crude inlet), the cracking unit turns heavy oil plus water into light oil and light oil plus water into gas, and the flare stack burns any gas at 60 litres per second for 10 kW, counting it voided. Crafting machines may have fluid outputs and no item slots at all; fixed recipe choice looks at the fluids present first. Technologies gated by a main quest carry a `quest_gate` flag that labs refuse, so oil processing stays a quest gate while it unlocks real recipes. Under strict byproducts a refinery whose gas has nowhere to go stops, which is the byproduct rule at work: the flare and the combustion generator are the sinks. Two follow ups handed to 0031: a craft should wait for its full fluid input before starting rather than start on one litre and stall, and the tar pit pump's 200 litres per minute means six pumps per refinery, which is too many.

### As implemented in 0031

- A craft with fluid inputs starts only when every fluid input is fully present and takes them at the start like items; the tar pit pump gives 600 litres per minute so two feed a refinery. The chemical plant (gas port by phase, second input unfiltered, fixed choice by fluids) makes plastic from petroleum gas and coal, sulfur from gas and water, bitumen from heavy oil, and syngas plastic from wood gas and charcoal; the wood gasifier turns logs into wood gas plus charcoal as a byproduct; asphalt is an assembler recipe from bitumen and gravel. Science pack 2 is plastic based and labs have two pack slots. Fast belts stay a placeholder because a second belt speed is not a data only change. Sulfur has no consumer yet.

### As implemented in 0032

- The combustion generator offers up to 600 kW capped by the gas in its port and the fuel in its slot, draws gas first in whole litres and then burns fuel items, and subtracts exactly the energy delivered so produced equals consumed. Petroleum gas is worth 200 kJ per litre and wood gas 100. The power overview and the statistics Power tab list generators by type. Science pack 2 now requires plastics research. Handed to 0033: the flare stack has no lower priority than a generator on the same gas network, and a gas without fuel value (steam) is accepted by the generator's port and sits there.

