# 0052 What am I looking at: block names and ore discovery

Status: todo
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
