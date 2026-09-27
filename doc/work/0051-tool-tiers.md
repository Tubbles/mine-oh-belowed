# 0051 Tools gate block hardness

Status: implemented
Milestone: M10

## Goal

User decision (2026-09-27): tools gate what can be mined, Minecraft style, on top of the mining speed. Dirt, sand, gravel, logs and the like yield to hands; stone and the first ores need a wooden pickaxe; harder ores need stone, then iron.

## Deliverables

- `data/blocks.sjson`: a `tool_tier` per minable block (0 hands, 1 wooden pickaxe, 2 stone pickaxe, 3 iron pickaxe), chosen so chapter 1 still works in its order: the tools quest crafts the wooden pickaxe before the stone and rocks quests, so stone, coal ore, hematite and chalcopyrite outcrops are tier 1; the phase 5 ores (cassiterite, galena, sphalerite, pentlandite) and bauxite tier 2; deep stone, gold quartz and anything below tier 3. `data/items.sjson`: a `tool_tier` on the pickaxes (wooden 1, stone 2, iron 3). Strict loading: a minable block without a tier or a tier above the best tool is an error.
- Rule: the best pickaxe anywhere in the player's inventory counts (gamepad first: no hotbar juggling), mining a block above it makes no progress and the HUD target line says which tool it needs ("Needs a stone pickaxe"). Machines (drills) are unaffected. The mining speed multiplier of tools, if one exists, stays as it is.
- Quests: the ordering test gains the rule that no obtain or place objective needs a block whose tier exceeds the best pickaxe craftable by then (recipes available at that point of the chapters).
- Tests: data validation, the gate with each tier, the HUD line, the quest ordering rule.

## Verify

- Builds and tests pass.
- User: hands break dirt and logs but not stone until the wooden pickaxe exists; the HUD names the missing tool.

## Notes

Implemented by a subagent (2026-09-27). A missing `tool_tier` reads as 0 (hands). Loading refuses a negative tier, a `tool_tier` on an item outside the tool category, and a minable block whose tier no tool reaches (`validate_block_tool_tiers` in `src/item.odin`). `player_tool_tier` in `src/player_interaction.odin` takes the best tier over every inventory slot and the cursor; `required_ticks_for` returns 0 above it, so `advance_mining` never starts. `target_status_lines` puts `mining_needs_tool` ("Needs a tool: {name}", the item name is capitalised so "Needs a stone pickaxe" would need per language casing) in the first HUD line. Pickaxes do not change mining speed: no speed effect existed and none was added.

The quest ordering rule does not use recipe availability: all three pickaxe recipes are start recipes, so the iron pickaxe would count from the first quest. The ordering test instead counts the best pickaxe an earlier quest had the player craft or obtain, or gave as a reward (`quest_granted_tool_tier` in `src/quest_chapter_04_test.odin`). Obtain and place objectives check the lowest tier among the blocks that yield the item.

Tiers: hands for dirt, grass, sand, log, leaves, torch, tar (the tar flats surface) and slag heaps; wooden for stone, spent rock, coal, hematite and chalcopyrite ore, brick, concrete and asphalt; stone for cassiterite, galena, sphalerite and pentlandite ore; iron for deep stone and gold quartz. Bauxite, gravel, clay, mud and snow have no blocks.
