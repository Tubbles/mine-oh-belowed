# Quests

Quests guide the player through the whole game and replace the tutorial. The chapters are data in `data/quests/`, one file per chapter. The header of `data/quests/chapter_01.sjson` is the format reference (objective parameters, hint counters, rewards). The runtime is `quest_runtime.odin`, Mission Control's panel on the HUD is in [hud.md](hud.md). This document holds the principles, the tone, the spawn requirements and each chapter's intent.

## Principles

The design rules are in [DESIGN.md](../DESIGN.md), Research, quests and rockets.

- Quests guide and reward, never block. A player who never opens the journal can do everything except the main quest gates, one per gameplay phase ([content.md](content.md), Technologies and gates).
- Every objective asks for what the player has just done by hand, or for what the current pain suggests. The journal never introduces a mechanic before the player has felt the need for it.
- One active objective on the HUD. The journal holds the rest.
- No quest makes the player wait: a sustain window is seconds, not minutes (user, 2026-09-27).
- Rewards arrive physically: a drop capsule on the landing pad holds the items, and schematics arrive as a message that unlocks the technology.
- Contextual hints fire once, on counters the simulation already keeps.
- World building lives in the journal's Notes tab (`data/notes.sjson`), not in quest text.
- Chapters measure placements and production, not layout: nothing checks that a belt feeds the same furnace or that a pump lifts water. A chapter whose intent is a layout says so in its header and measures a stand in (ten lifts for a second floor).

## Objective types

Evaluated every tick against the statistics counters, placed counts, recipe unlocks, research state and the capsule.

| Type | Counts | Example |
| --- | --- | --- |
| obtain | Growth of what players hold, since the game began | Obtain 10 logs |
| craft | Crafted or smelted, since the game began or with `produced_since_active` since activation | Craft 1 wooden pickaxe |
| place | Placements of a machine, or blocks placed with an item | Place 3 stone furnaces |
| sustain | Ticks in a row at a rate, optionally hands off | 40 iron plates per minute for 5 seconds |
| research | The technology researched, an infinite one at its first level | Research automation |
| deliver | Items in the capsule since activation | 100 electronic circuits |
| discover | The recipe available | Discover charcoal |
| walk | Blocks walked on foot | Walk 10 blocks |
| counter | Growth of a hint counter since activation | Drills burn 10 fuel items |
| produce_fluid | Litres put into machine ports since activation | 500 litres of petroleum gas |
| ship | Items rockets carried away, of one item or of all | Ship 1000 items |

## Runtime

- One quest is active at a time, chapter after chapter in data order. A quest without objectives completes on its first tick and carries its opening message.
- Counting since the game began means work done ahead of the journal counts. Obtained is growth of what players hold between ticks, so crafted items and items taken back out of a chest count.
- Completion logs Mission Control's line, queues the rewards, unlocks quest channel recipes and `unlocks_technology` rewards, and activates the next quest in the same tick. Delivered items leave the capsule then.
- The landing pad is stamped by world generation at the spawn, so it returns identically on every load. Its drop capsule is never picked up. Rewards that do not fit wait for room and are never dropped.
- A message key starting with `mc_` is Mission Control speaking (`MISSION_CONTROL_KEY_PREFIX`), shown in the HUD panel and framed in the journal. The venture's notices (research done, contracts, trade, surveys, the capsule landing) stay toasts and plain journal rows. A new Mission Control line needs only the prefix.
- In a message text `{value}` takes the message's number and `{cargo}` the cargo of the shipment it names.
- Ore discovery (`discovery.odin`): the first time a discoverable block's drop is obtained, "{name} discovered!" (`item_discovered`) shows as the HUD's discovery card, once per world. Starting items and unlock all do not trigger it. Developer kits and `--give` do.
- Mining a vein's last outcrop block with units left logs `mc_outcrop_spent` once per vein, whatever quest is active ([content.md](content.md), Veins).
- After the last quest the journal's last chapter tab starts with "Contracts continue" and the HUD's objective column shows the oldest open contract.
- Developer mode completes quests up to a chapter through the same completion path: rewards queued, deliveries not taken, only the final activation's message kept ([commands.md](commands.md)). Kits per chapter are in `data/dev_kits.sjson`.
- `test_shipped_quests_never_need_a_locked_recipe` plays every chapter in order: no objective needs a locked recipe, research follows its prerequisites, and no obtain or place objective or mining hint names a block above the best pickaxe the starter kit (a stone pickaxe, 0179) and the earlier quests put in hand. Chapters 2 to 8 each have a `quest_chapter_<n>_test.odin` that plays the chapter in order.

## Spawn requirements

`generation_spawn.odin`, `generation_starter_veins.odin`. Chapter 1 works only where the world guarantees its materials near the landing pad.

- Within `SPAWN_REQUIREMENT_RADIUS` of the pad: trees, surface stone, sand and water.
- The iron, copper and coal outcrops are starter veins (0045): one scattering of each `spawn_vein_types` entry, `STARTER_VEIN_MINIMUM_DISTANCE` to `STARTER_VEIN_MAXIMUM_DISTANCE` blocks from the pad in directions spread around it, on dry land and whatever the biome, generated after trees and boulders with the column above each outcrop cleared, so they are in sight of the pad. Natural veins they overlap are left out.
- The pad's column is temperate, between `SPAWN_MINIMUM_TEMPERATURE` and `SPAWN_MAXIMUM_TEMPERATURE`, checked first as the cheapest. The origin is temperate by construction.
- The site is flat: within `LANDING_SITE_FLAT_RADIUS` the surface varies by at most `LANDING_SITE_FLAT_HEIGHT_RANGE` with no water, within `LANDING_SITE_SURROUNDINGS_RADIUS` by at most `LANDING_SITE_SURROUNDINGS_HEIGHT_RANGE`, which keeps gorges and lakes off the pad. A flat range of 3 leaves no site on any seed, since the detail noise alone moves the surface by about 5.
- The search walks square rings outwards from the origin and queries the generator's functions directly, so no chunk is generated.

## Chapters

The objectives, hints and rewards are in the chapter files. The intent per chapter:

1. Arrival, ten minutes. It teaches look, move, mine, craft, place and the machine panel, with no text boxes about controls.
   - The slice's chapter (0179; the field has no trees until M14 and the starter kit carries a stone pickaxe): stone dug out of the ground, hematite and coal from the starter outcrops round the pod, a stone furnace, fuel and ore in its panel, ten plates, then the stone cutting table (0196, quest `cutting`: craft and place the table, cut two stone bricks at it, since the line's belt poles need bricks and bricks are cut, not fired), then the first line: a burner mining drill, a burner inserter, a belt and an iron chest placed.
   - The main quest, ten plates, brings coal and plates, "an advance against your first delivery"; the line comes after it.
2. The workshop, thirty minutes. The pain is carrying.
   - Three furnaces, copper and gears, then a burner drill on the iron outcrop before the fifty plates, so the plates are the drill's output. Fifty plates by hand would empty the starter outcrop's visible blocks.
   - Hints for a furnace out of fuel, a full inventory and a drill refused for lack of a vein.
   - Main quest: deliver 100 iron plates. The capsule brings belts and burner inserters, so chapter 3 starts with the parts in hand.
3. Belts, forty five minutes. The pain is the furnace going cold.
   - A drill to a furnace by belt and inserter, the coal loop (a coal drill whose belt feeds its own fuel slot, running on into a chest), a plate line into a chest, four drills feeding three furnaces.
   - Main quest "Prove the outpost": 40 iron plates a minute held for five seconds. It releases the steam engine and lands an offshore pump, a boiler and pipes.
4. Power, seventy five minutes.
   - A fuel generator first, since the offshore pump draws power, then the offshore pump, boiler and engine. Two poles and five glass (the first dig for sand on purpose).
   - A lab and automation, with the brownout and unpowered hints, an assembler, the electric drill, a second engine.
   - Main quest "The first contract": 100 electronic circuits, paid with a crusher and a washer.
5. Contracts. Low grade ore and its processing line, slag and concrete, alloys, the recycler, a rate contract that introduces the statistics screen. Main quest "Extraction rights" researches oil processing.
6. Fluids. A pump uphill and a tank, tar and the refinery (the mixing hint), fractions and cracking, the flare, plastic on both routes, waste gas into a generator. Main quest "Deep mining permit" researches deep mining.
7. Scale. A second vein, the deep permit (prospecting, electrolysis, a bore drill), aluminium and silicon, two floors, hydro power, the grid, a cave schematic, sixty plates a minute. Main quest "Launch pad permit" researches the rocket program.
8. Rocket program. Rocketry, the launch pad and one rocket's parts, the first launch, a contract, an orbital survey, mining productivity.
   - Main quest "Self sufficient": ship 1000 items. Its line is the soft ending in one sentence, ending "The contracts continue.", and the venture keeps offering contracts.

## Mission Control tone

- Corporate, terse, dry, occasionally cynical, always brief: two lines per message, three at most. Humour lives in these messages, never in the world.
- No exclamation marks, no emoji, no mascots. It never explains a mechanic: the objective text carries the instruction, Mission Control comments on the outcome.
- It calls the planet "the asset" and the player "contractor". It is never cruel to the player, only indifferent. The cynicism is aimed at the venture itself.
