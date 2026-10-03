# 0196: Wooden foundations first, iron foundations as the evolution

Status: todo (user, 2026-10-03: "for immersion, i think we need wooden foundation as the first step, and then iron foundation is the evolution, before automated tree farms arrive even later and makes large scale wooden foundations viable again"; after 0189)

## Goal

The pad's material tells the game's stage: wood at the start, iron once a furnace runs, and wood again at scale when tree farms arrive (a later milestone). Today one `foundation` machine (`data/machines.sjson`, kind `foundation`, two stone bricks by hand) is the only one, and the code assumes a single foundation (`content.field.foundation`, `field_foundation` in `entity_frames.odin`, the pod's pad and the benchmark's).

## Change

- Two machines of kind `foundation`, both one cell: `wooden_foundation` (planks by hand; the plank recipe exists, four planks a log) and `iron_foundation` (iron plates, hand or assembler), each with its item; the stone brick `foundation` goes (its item remapped in old saves to the wooden one, a log line). The iron recipe is discovered as the design's channel says (`DESIGN.md`, Three progression channels): it appears the first time iron plates are held, no technology.
- The held item decides which foundation a block places (0193: the block's cells are all of the held machine); mixing is allowed on one frame. The pod's pad (`pod_pad_cells`) and the benchmark's pad use the one `game.sjson` names (`field.pad_foundation = "wooden_foundation"`); the starting items give wooden foundations and enough planks for a first pad (`starting_items`, with the counts chosen so chapter 1's quests still hold).
- Both share the foundation model with their own tint through the model's material weights (the way the field tints materials), so a pad reads as wood or iron at a glance; `doc/content.md` (Foundations: the two, the discovery, the pad's), `doc/architecture.md` (the pad foundation of the content) updated.
- Until trees stand on the planet (0197) the only wood is the kit's; the item says so in the log so nobody mistakes it for the end state.

## Controls

- No control changes: the hotbar's selected item decides, as for any placed machine.

## Verify

- The build and check commands of 0168.
- Tests: a wooden and an iron foundation each place a block of their own kind; a mixed frame holds both; an old save with the stone brick item loads it as wooden with the log line; the iron recipe is undiscovered until an iron plate is obtained; the pod's pad is the content's pad foundation.
- The couch: the kit builds a wooden pad; after the first iron plate the iron foundation appears in the recipes.
