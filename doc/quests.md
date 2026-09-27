# Quests

Quests are the guide through the whole game and replace the tutorial. Chapter 1 is written beat by beat because it is the onboarding. Chapters 2 to 8 are outlines that fill in as their milestones approach. Everything here ends up in `data/quests/*.sjson`.

## Principles

- Quests guide and reward, never block. A player who never opens the journal can do everything except the few main quest gates, about one per gameplay phase.
- Every objective asks for something the player has just done by hand, or for the thing the current pain suggests. The journal never introduces a mechanic before the player has felt the need for it.
- One active objective on the HUD at a time. The journal holds the rest.
- Mission Control is the venture's voice: corporate, dry, occasionally cynical, always brief. Two lines per message, three at most. Humour lives in these messages, never in the world.
- Rewards arrive physically. A drop capsule lands at the landing pad with the items, and the venture notes that the cost is deducted from the outpost's account. Schematics arrive as a message that unlocks the technology.
- Contextual hints fire once, on counters the simulation already keeps: a furnace ran out of fuel three times, a belt ends nowhere for a minute, the inventory has been full for thirty seconds.

## Objective types

Defined in data, evaluated every tick against the statistics counters, placed entity counts and research state.

| Type | Parameters | Example |
| --- | --- | --- |
| obtain | item, count | Obtain 10 logs |
| craft | item, count | Craft 1 wooden pickaxe |
| place | entity, count | Place 1 stone furnace |
| sustain | item, rate per minute, minutes and/or seconds, hands off flag | Reach 40 iron plates per minute and hold it for 5 seconds (windows are seconds since 2026-09-27: a quest that makes the player wait is not fun) |
| research | technology | Research automation; an infinite technology counts at its first level (0042) |
| deliver | item, count | Deliver 100 electronic circuits to the landing pad |
| discover | recipe | Discover bronze plate |
| ship | item (optional), count | Items rockets carried away since the game began, every item when none is named (0042) |
| walk | count | Walk 10 blocks (added by 0013 for beat 2, since "looked around" is not measured) |
| counter | counter, count, label_key | Growth of a hint counter since activation, for example drills burning 10 fuel items (added by 0018 for the coal loop) |
| produce_fluid | fluid, litres | Litres of a fluid produced since activation (added by 0033) |

## As implemented in 0013

- Quests play one at a time in data order across chapters. Beat 1 is a quest with no objectives that completes on the first tick and carries the opening message.
- obtain, craft, place and walk count everything since the game began, so work done ahead of the journal counts. deliver counts what players put into the capsule since the quest became active. Hints count from activation and fire once. "Obtained" is measured as growth of what players hold between ticks, so crafted items and items taken back out of a chest count as obtained.
- The landing pad is stamped by world generation at the spawn, so it returns identically on every load without saved state. One drop capsule stands on it and is never picked up; rewards land in it and wait when it is full.
- Chapter 2 crafts the burner drill instead of placing it, because drills are not entities until M3.
- Chapter 3 (0018) measures placements and production, not layout: it cannot tell that the belt feeds the same furnace or that the coal drill feeds itself. Craft objectives can count from activation with `produced_since_active`. New counters: `drill_fuel_burned`, `belt_dead_end_ticks` (lines whose front item is held at a dead end, feeds into an inserter excluded) and `inserter_idle_a_minute` (one inserter idle for sixty seconds without a break), the last two carrying the "belt ending nowhere" and "inserter facing the wrong way" hints on the connect quest. The main quest's reward unlocks the steam engine recipe through the quest channel and lands a pump, a boiler and pipes in the capsule.

- Chapter 4 (0022) runs steam, first pole (two poles and five glass, since the lamp is behind optics), first research (automation, carrying the brownout and unpowered hints), assembly, electric drill, second engine, and the main quest "The first contract" (100 electronic circuits delivered), which pays copper and iron plates until the phase 5 machines exist. A test plays every shipped chapter in order and checks that no objective needs a locked recipe, that research objectives follow their prerequisites, and (0051) that no obtain or place objective and no mining hint names a block above the best pickaxe an earlier quest had the player craft, obtain or receive.

- Chapter 5 (0029) runs low grade (steel and ore processing research, then low grade hematite), the processing line (crusher, washer, crushed hematite), slag (20 slag heaps placed and 10 concrete blocks, a place objective may now name a block placing item through a per item blocks placed counter), alloys, recycling (a new `recycled` counter), a statistics contract (sustain 30 plates per minute, with a hint that fires on activation through the new `on_activation` hint form), and the main quest "extraction rights" (200 concrete and 100 brass delivered) whose reward marks the placeholder `oil_processing` technology researched through the new `unlocks_technology` reward. Chapter 4's first contract now pays a crusher and a washer.

- Chapter 6 (0033) runs uphill (fluid handling, a pump and a tank), tar (tar pit pump and refinery with the mixing hint on a new `mixing_refusals` counter), fractions (500 litres of petroleum gas and cracking research), flare (a flare stack with a hint on `flared_litres`), plastic, two routes (the gasifier, with the route itself not measurable), waste power (combustion generator and `generator_gas_litres`), and the main quest "deep mining permit" (200 plastic and 50 sulfur delivered) rewarding the quest gated `deep_mining` placeholder. Layout facts (a pump lifting water, gas going into tanks) are not measurable and the chapter header says so.

- Chapter 7 (0039) runs second vein (prospecting, two assays, four electric drills), deep permit (electrolysis, a core sample, a bore drill and 200 bore drill units, with a hint when placement is refused for lack of a deep vein), aluminium, two floors (ten lifts and twenty concrete blocks stand in for a layout that cannot be measured), hydro (a turbine and 10 MJ generated, with a hint for a turbine in still water), grid (a substation), schematic (one found, with a hint on the first seismic shot), sixty plates per minute, and the main quest "launch pad permit" (100 aluminium and 50 silicon delivered) rewarding the quest gated `rocket_program` placeholder. Its deep permit quest also researches `logistics` and `logistics_science` since 0042, which science pack 2 technologies need, and chapter 6's permit line no longer calls the bore drill schematics pending.

- Contracts and trade (0041) add to the message log: `{value}` in a message text is replaced by the message's number and `{cargo}` by the cargo of the shipment it names, so "Shipment launched: {cargo}" lists the items. The venture's lines (contract offered, fulfilled on time or late, cargo sold, survey charted, catalogue order) go through the same log and toasts as Mission Control's. New counters for chapter 8: `contracts_completed`, `contracts_late`, `credit_earned` (venture credit from free trade) and `surveys_bought` (every orbital survey run, contract rewards included). The HUD shows the oldest open contract in the objective column once every quest is done (0042).

- Ore discovery (0052): the first time an item dropped by a discoverable block is obtained, the log and a toast read "{name} discovered!" (`item_discovered`), once per world since it fires when `Recipe_Unlocks.obtained` flips; starting items and unlock all do not trigger it, developer kits and `--give` do.

- Chapter 8 (0042) runs rocketry (research), launch pad (place), rocket parts (craft one rocket's parts), first launch (`rockets_launched`, with hints on the new `launch_parts_missing` and `launch_cargo_empty` counters, which the pad panel's Assemble and Launch buttons bump when refused), contract (`contracts_completed`), orbital survey (`surveys_bought`), productivity (research mining productivity, done at its first level) and the main quest "self sufficient": a new `ship` objective of 1000 items in total on the new `items_shipped` counter, whose completion line is the soft ending in one sentence followed by "The contracts continue." Counter objectives count from activation, so a contract fulfilled by the very first launch does not count for the contract beat; the venture keeps offering. After the last quest the last chapter's journal tab starts with "Contracts continue" and the HUD objective column shows the oldest open contract, or nothing without one.

- Developer mode (0043) completes quests up to a chapter by walking the active quest forward through the runtime's own completion path: each earlier quest is marked done and its rewards queued (items to the capsule, recipes and technologies unlocked), deliveries are not taken from the capsule, and only the final activation's message stays in the log. Chapter kits, what a player typically holds at a chapter's start, live in `data/dev_kits.sjson`, one per chapter in order.

## Spawn requirements

Chapter 1 only works if the world guarantees, within about 150 blocks of the landing pad: trees, surface stone, sand and water. The iron, copper and coal outcrops are starter veins (0045): one small vein of each spawn type stamped 24 to 40 blocks from the pad in directions spread around it, generated after trees and boulders with the column above every outcrop cleared, so they are in sight of the pad. The pad's column is temperate, a temperature between -0.2 and 0.5 (0058), checked first since it is the cheapest; the origin sits at 0.1, so the search stays near it. The site is flat: within 24 blocks the surface height range is at most 5 with no water, within 64 blocks at most 12, which keeps river gorges and lakes off the pad (a range of 3 left no site on any seed, the detail noise alone moves the surface by about 5). World generation searches for a spawn that satisfies this, in 1 to 50 milliseconds for most seeds. It belongs to `doc/world.md` once written.

## Chapter 1: Arrival

Target: ten minutes. Teaches look, move, mine, craft, place, and the machine panel. Ends with the first iron plates in hand.

1. Fade in next to the drop capsule on the landing pad. Mission Control: "Contractor. You have landed on schedule. The lease starts now, and so does the invoice." The HUD shows the first objective and the button glyph bar. No text boxes about controls.
2. Get your bearings. Complete on the player having looked around and walked ten blocks. Teaches the sticks and gyro without saying so.
3. Timber. Obtain 10 logs. The nearest tree is marked on the compass strip. Hint if the player holds mine on grass for two seconds: "Trees. The grass is not on the manifest."
4. Tools of the trade. Craft 4 planks, then sticks, then a wooden pickaxe from the hand crafting menu. Teaches the inventory and the recipe browser; the silhouettes of undiscovered recipes are visible from the first opening.
5. Stone. Mine 20 stone from boulders and exposed stone. Stone needs the wooden pickaxe (0051): bare hands make no progress and the HUD names the tool.
6. Read the rocks. Walk to the iron outcrop on the compass strip and mine 10 hematite by hand. Mission Control: "Hematite. The venture pays for plates, not rocks."
7. First furnace. Craft a stone furnace (5 stone) and place it. Teaches placement, the footprint preview and rotation.
8. Light the fire. Open the furnace panel, add fuel (logs work, coal is better and the coal outcrop is marked), add hematite. Teaches the machine panel and the fuel slot. Mission Control fills the wait: "Smelting takes time. Time is billed."
9. Stock check. Obtain 10 iron plates. Chapter complete. Reward capsule: 50 coal and 10 iron plates. "An advance against your first delivery. Interest applies."

## Chapter 2: The workshop

Target: thirty minutes. The pain is carrying. Quests: three stone furnaces, 50 iron plates, copper plates, iron gears, the first burner mining drill placed on the iron outcrop, refuelling it, an iron chest, 200 plates in storage. Discoveries along the way: charcoal, glass, the circuit once wire exists. Contextual hints: furnace out of fuel three times ("A machine that feeds machines exists. Consider it."), inventory full ("Chests. They hold things while you are elsewhere."). Main quest: deliver 100 iron plates to the landing pad, the outpost's first invoice. Reward: a capsule with 20 belts and 4 burner inserters, so chapter 3 starts with the parts in hand and the recipes discovered.

## Chapter 3: Belts

Target: forty five minutes. The pain is the furnace going cold. Quests: connect a drill to a furnace with a belt and an inserter, the coal loop (a coal drill whose belt feeds its own fuel slot), a chest at the end of a plate line, four drills feeding three furnaces. Hints: a belt that ends nowhere for a minute, an inserter facing the wrong way. Main quest, "Prove the outpost": reach 40 iron plates per minute and hold it for five seconds (it was ten minutes hands off; the user found being told not to play counter to the point of a game, 2026-09-27). This is the phase 4 gate: the venture releases the steam engine schematics to an outpost that produces at a rate. "Automation verified. Power generation schematics attached. Their cost is on your account."

## Chapter 4: Power

Target: seventy five minutes. Quests: offshore pump, boiler and steam engine, the first pole, lights on (a lamp needs glass, which needs sand, the first time discovery sends the player digging on purpose), electric drill replacing a burner drill, an assembler making gears, a lab and the first science pack, research automation, a brownout the first time demand exceeds supply ("Demand exceeded supply. Machines slowed down. Nobody was harmed, which is not the point."), a second engine. Main quest, "The first contract": deliver 100 electronic circuits to the landing pad. The venture's reply opens phase 5: contracts, and the ore processing schematics that come with the first low grade ore.

## Chapter 5: Contracts

Sorting mixed ore, crusher and washer, the first slag and where it goes, the recycler, an alloy line, the production statistics screen introduced by a contract that asks for a rate. Main quest gate: a delivery that unlocks oil processing, "the venture has acquired the extraction rights".

## Chapter 6: Fluids

Water network with a pump uphill, tar pit pump, refinery, gases into tanks, plastic on both routes, waste gas into a generator. Main quest gate: a deep mining permit that unlocks bore drills and the seismic survey.

## Chapter 7: Scale

A second vein feeding the base, a deep vein tapped from the surface, a two floor factory, hydro power, a cave schematic. Main quest gate: the launch pad permit.

## Chapter 8: Rocket program

Launch pad, rocket parts, the first shipment, a contract with a soft deadline, the orbital survey bought with a shipment. Soft ending: the venture declares the outpost self sufficient and thanks the contractor in one sentence. The contracts continue.

## Mission Control tone

Corporate, terse, no exclamation marks, no emoji, no mascots. It never explains a mechanic; it comments on the outcome and lets the objective text carry the instruction. It refers to the planet as "the asset" and to the player as "contractor". It is never cruel to the player, only indifferent, and the cynicism is aimed at the venture itself.
