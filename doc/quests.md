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
| sustain | item, rate per minute, minutes, hands off flag | Sustain 10 iron plates per minute for 10 minutes without interacting |
| research | technology | Research automation |
| deliver | item, count | Deliver 100 electronic circuits to the landing pad |
| discover | recipe | Discover bronze plate |
| ship | item, count, contract | Ship 200 electronic circuits, phase 8 |
| walk | count | Walk 10 blocks (added by 0013 for beat 2, since "looked around" is not measured) |

## As implemented in 0013

- Quests play one at a time in data order across chapters. Beat 1 is a quest with no objectives that completes on the first tick and carries the opening message.
- obtain, craft, place and walk count everything since the game began, so work done ahead of the journal counts. deliver counts what players put into the capsule since the quest became active. Hints count from activation and fire once. "Obtained" is measured as growth of what players hold between ticks, so crafted items and items taken back out of a chest count as obtained.
- The landing pad is stamped by world generation at the spawn, so it returns identically on every load without saved state. One drop capsule stands on it and is never picked up; rewards land in it and wait when it is full.
- Chapter 2 crafts the burner drill instead of placing it, because drills are not entities until M3.

## Spawn requirements

Chapter 1 only works if the world guarantees, within about 150 blocks of the landing pad: trees, surface stone, sand, water, one iron outcrop, one copper outcrop and one coal outcrop. World generation searches for a spawn that satisfies this. It belongs to `doc/world.md` once written.

## Chapter 1: Arrival

Target: ten minutes. Teaches look, move, mine, craft, place, and the machine panel. Ends with the first iron plates in hand.

1. Fade in next to the drop capsule on the landing pad. Mission Control: "Contractor. You have landed on schedule. The lease starts now, and so does the invoice." The HUD shows the first objective and the button glyph bar. No text boxes about controls.
2. Get your bearings. Complete on the player having looked around and walked ten blocks. Teaches the sticks and gyro without saying so.
3. Timber. Obtain 10 logs. The nearest tree is marked on the compass strip. Hint if the player holds mine on grass for two seconds: "Trees. The grass is not on the manifest."
4. Tools of the trade. Craft 4 planks, then sticks, then a wooden pickaxe from the hand crafting menu. Teaches the inventory and the recipe browser; the silhouettes of undiscovered recipes are visible from the first opening.
5. Stone. Mine 20 stone from boulders and exposed stone. The pickaxe is visibly faster than the hand.
6. Read the rocks. Walk to the iron outcrop on the compass strip and mine 10 hematite by hand. Mission Control: "Hematite. The venture pays for plates, not rocks."
7. First furnace. Craft a stone furnace (5 stone) and place it. Teaches placement, the footprint preview and rotation.
8. Light the fire. Open the furnace panel, add fuel (logs work, coal is better and the coal outcrop is marked), add hematite. Teaches the machine panel and the fuel slot. Mission Control fills the wait: "Smelting takes time. Time is billed."
9. Stock check. Obtain 10 iron plates. Chapter complete. Reward capsule: 50 coal and 10 iron plates. "An advance against your first delivery. Interest applies."

## Chapter 2: The workshop

Target: thirty minutes. The pain is carrying. Quests: three stone furnaces, 50 iron plates, copper plates, iron gears, the first burner mining drill placed on the iron outcrop, refuelling it, an iron chest, 200 plates in storage. Discoveries along the way: charcoal, glass, the circuit once wire exists. Contextual hints: furnace out of fuel three times ("A machine that feeds machines exists. Consider it."), inventory full ("Chests. They hold things while you are elsewhere."). Main quest: deliver 100 iron plates to the landing pad, the outpost's first invoice. Reward: a capsule with 20 belts and 4 burner inserters, so chapter 3 starts with the parts in hand and the recipes discovered.

## Chapter 3: Belts

Target: forty five minutes. The pain is the furnace going cold. Quests: connect a drill to a furnace with a belt and an inserter, the coal loop (a coal drill whose belt feeds its own fuel slot), a chest at the end of a plate line, four drills feeding three furnaces. Hints: a belt that ends nowhere for a minute, an inserter facing the wrong way. Main quest, "Prove the outpost": sustain 10 iron plates per minute for ten minutes without interacting. This is the phase 4 gate: the venture releases the steam engine schematics only to an outpost that runs unattended. "Automation verified. Power generation schematics attached. Their cost is on your account."

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
