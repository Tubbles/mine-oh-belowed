# 0052 What am I looking at: block names and ore discovery

Status: implemented
Milestone: M10

## Goal

User request (2026-09-27): a small help text under the crosshair says what the player looks at, and vanishes on air. Ore blocks read "Unknown ore" until that ore has been in the player's hands once, which pops a small achievement, "Hematite discovered!".

## Deliverables

- Block display names in data: a `name_key` per block in `data/blocks.sjson` (air excepted) with strings in `data/strings/en.sjson`; strict loading refuses a block without one. Outcrop blocks name their ore ("Hematite ore").
- The HUD target line (`target_status_lines`, `draw_target_status` in `src/hud.odin`) shows the targeted block's name for every block, in front of the tool line where both apply; entities keep their name and state line; nothing shows when the ray hits nothing. One line, dim, small.
- Discovery: an ore block (any block whose drop item is an ore, or a `discoverable = true` flag on the block in data if the rule needs data) shows "Unknown ore" until the player has obtained its drop item once (`Recipe_Unlocks.obtained`, which already tracks items that were in a player's inventory or on the cursor). The vein status line follows the same rule for a vein type none of whose outputs is discovered ("Unknown ore vein, n units" or similar: keep the size, hide the composition). The moment an ore item is first obtained, a toast and a message log line read "{name} discovered!" (one string key, item name substituted), through the quest message log so it lands in the journal too. Discovery is per world (it lives in the unlocks, which are saved). With all recipes unlocked at start everything is discovered.
- Tests: block name validation; the target line for a block, an ore before and after discovery, an entity, and no hit; the discovery toast fires once per item; the vein line before and after; the UI audit still passes with the extra line.

## Verify

- Builds and tests pass.
- User: look at grass, stone and an outcrop; the outcrop reads "Unknown ore" until mined once, then the toast, then its name.

## Notes

Implemented by a subagent (2026-09-27). Every block but air has a `name_key` (`block_<id>`, the flowing water levels share `block_flowing_water`); the unused `name` field is gone, and the core sample band line now reads the name through the string table too. `load_block_registry` checks the keys against the loaded string table (`validate_block_name_keys` in `src/world_block.odin`). `discoverable = true` sits on the eight ore blocks (hematite, coal, chalcopyrite, cassiterite, galena, sphalerite and pentlandite ore, gold quartz); `resolve_item_registry` refuses a discoverable block without a drop (`validate_discoverable_drops`). The HUD helper is `block_display_name`, since `block_name` already exists in the diagnostics overlay (it shows the id).

Discovery lives in `src/discovery.odin`. `update_recipe_unlocks` returns the items it saw for the first time and `simulation_tick` passes them to `log_discoveries`, which logs `item_discovered` for items that are the drop of a discoverable block. Starting items are recorded in `make_simulation` before any tick and unlock all marks everything obtained, so neither is announced; developer kit grants and `--give` land during a tick and are announced. Gold quartz is discovered through its drop, quartz; gold ore (its extra drop) is not announced.

A vein type counts as discovered once any of its outputs that some discoverable block drops is obtained. Outputs no discoverable block drops (gravel, sand, stone, bauxite) are ignored, otherwise the first gravel would name every vein; a type with no such output (the quarry, the deep bauxite vein) is always named. The HUD draws the target lines compacted: block or entity line, tool line, vein line, empty lines take no room. The block name is dim, an entity's name and state keep the normal colour.
