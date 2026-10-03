# 0196: Wooden, stone brick and iron foundations

Status: todo (user, 2026-10-03: "wooden foundation as the first step, and then iron foundation is the evolution, before automated tree farms arrive even later"; then "i like stone brick foundation as well, unlocked when we get stone cutting table (hand) and some stone cutting machine (automated), as a semi-early alternative to wood foundation"; after 0189)

## Goal

The pad's material tells the game's stage: wood at the start, stone brick once stone is cut, iron once a furnace runs, and wood again at scale when tree farms arrive (a later milestone). Today one `foundation` machine (`data/machines.sjson`, kind `foundation`, two stone bricks by hand, the bricks smelted in the furnace) is the only one, and the code assumes a single foundation (`content.field.foundation`, `field_foundation` in `entity_frames.odin`, the pod's pad and the benchmark's).

## Change

- Three machines of kind `foundation`, all one cell, each with its item: `wooden_foundation` (planks by hand; the plank recipe exists, four a log), `stone_brick_foundation` (the current one renamed, two stone bricks by hand; its item remapped in old saves, a log line) and `iron_foundation` (iron plates, hand or assembler). Every recipe is discovered as the design's channel says (`DESIGN.md`, Three progression channels): it appears the first time its ingredients are held, no technology.
- Stone is cut, not smelted: the `stone_brick` recipe leaves the furnace for two new machines, a `stone_cutting_table` (a hand station: planks and stone by hand; its panel offers the cutting recipes and the player crafts there, the bench of 0198 is the same kind of station) and a `stone_cutter` (automated, fuelled like the burner drill, slots and a panel as a crafting machine, an assembler kin for stone). So the stone brick foundation arrives semi early, after the table and before iron, and scales with the cutter.
- The held item decides which foundation a block places (0193); mixing on one frame is allowed. The benchmark's pad uses the one `game.sjson` names (`field.pad_foundation = "wooden_foundation"`); the pod has no pad (0199); the starting items give wooden foundations and planks for a first pad (`starting_items`, counts chosen so chapter 1's quests still hold; the quest that smelts stone bricks, if one does, moves to the table).
- The three share the foundation model with their own tint through the material weights, so a pad reads as wood, stone or iron at a glance; `doc/content.md` (Foundations: the three, the discovery, the pad's; Stone cutting: the table and the cutter), `doc/architecture.md` (the pad foundation of the content) updated.
- Until trees stand on the planet (0197) the only wood is the kit's; the log says so.

## Controls

- No control changes: the hotbar's selected item decides, as for any placed machine; the table's panel opens with the inventory binding (0194).

## Verify

- The build and check commands of 0168.
- Tests: each foundation places a block of its own kind; a mixed frame holds all three; an old save with the `foundation` item loads it as the stone brick one with the log line; the iron recipe is undiscovered until an iron plate is held and the stone brick one until a brick is; stone bricks are made at the table and the cutter and not in the furnace; the benchmark's pad is the content's pad foundation.
- The couch: the kit builds a wooden pad; the table cuts bricks for a stone pad; after the first iron plate the iron foundation appears.
