# 0265: Digging needs a tool: the shovel, the pickaxe and the axe

Status: landed (2026-10-05, cf4d6d8)

## Goal

Nothing changes the ground unless the player holds a digging tool, as in Valheim, Space Engineers or Astroneer: the hand digs nothing. Today Mine is always the hand tool on the field and a finger resting a quarter second on the phone's screen presses it, so a hole appears under a pausing thumb. The first tools are simple: a shovel for soil, a pickaxe for stone and ore, an axe for trees, each in wood, stone and iron like the pickaxes of `data/items.sjson`. A small tree is always fellable by hand, slowly, so the first wooden tools can be made from it.

## Controls

No new binding. Mine with a digging tool selected on the hotbar does that tool's work at the aim (the shovel and the pickaxe dig with their material rates, the axe fells); Mine with the hand or any other item selected leaves the ground alone and only fells a small tree, at the hand's rate. Place is unchanged. The touch hold stays Mine; it digs nothing while the hotbar holds no digging tool. The spawn hotbar does not start on a digging tool.

## Change

- The tool decision reads the selected item's tool role and tier from the data (`field_tool_for_item`); the materials carry which tool digs them and how fast, never a rate in code.
- Items and recipes for the wooden, stone and iron shovel and axe beside the pickaxes; the starter kit and chapter 1's loop decided by the design with the recipes (a tree felled by hand gives the logs for the first wooden tools).
- Docs: `doc/content.md` (Field materials and brushes, Trees, The starter kit), `doc/input.md` (Mine), `doc/touch_overlay.md`, `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: Mine with the hand digs nothing on topsoil and fells a small tree; the shovel digs topsoil and not stone; the pickaxe digs stone; the axe fells a large tree the hand cannot; the touch hold with planks selected digs nothing; the recipes resolve.
- The phone: walk and look around for a minute with the default hotbar slot, no hole.

## Specification (design, 2026-10-05)

### Data model

- `Item_Tool_Role :: enum u8 {None, Shovel, Pickaxe, Axe}` (`item.odin`) with `item_tool_role_names` (`""`, `"shovel"`, `"pickaxe"`, `"axe"`), parsed with `parse_named_enum` like `configurable`. `Item_Definition.tool_role: string` (optional, default `""`), `Item.tool_role: Item_Tool_Role`. Validation in the item check: an unknown role refuses the file; a role needs category `tool` and `tool_tier` 1 or more. New `MAXIMUM_TOOL_TIER :: 15`: every item's `tool_tier` is 0 to 15 (the message `item %q has tool_tier %d outside 0 to 15`). The geologist's hammer keeps `tool_tier = 2` and no role.
- `data/materials.sjson` gains the required key `dug_with` (`"shovel"`, `"pickaxe"` or `""`). `Field_Material_Definition.dug_with: string`, `Field_Material_Record.dug_with: Item_Tool_Role`. Checks in `field_material_record`: `dug_with` names `shovel` or `pickaxe` when `item` is set (`axe` and `""` refused), and is `""` when `item` is empty; with a role `tool_tier` is 1 to `highest_tool_tier`, without one it is 0. `tool_tier` now means the tier of the `dug_with` tool the material needs. Shipped (rates unchanged):

  | id | item | dug_with | tool_tier | dig_rate_percent |
  | --- | --- | --- | --- | --- |
  | topsoil | dirt | shovel | 1 | 150 |
  | stone | stone | pickaxe | 1 | 100 |
  | deep_stone | deep_stone | pickaxe | 3 | 60 |
  | bedrock | "" | "" | 0 | 100 |
  | hematite_ore | hematite | pickaxe | 2 | 80 |
  | chalcopyrite_ore | chalcopyrite | pickaxe | 2 | 80 |
  | coal_ore | coal | pickaxe | 1 | 80 |

- Trees (`Planet_Tree_Species`, `data/planets.sjson`): `felling_milliseconds` is replaced by three required keys. `hand_felling_scale_percent` (0 to `PLANET_TREE_MAXIMUM_SCALE_PERCENT`, 115): a tree whose `scale_percent` is at most this is small and falls to the hand (0 to 84: none). `hand_felling_milliseconds` (100 to 60000): the hand's time on a small tree. `axe_felling_milliseconds: [3]int` (each 100 to 60000): the wooden, stone and iron axe's time on any tree; a tier above 3 takes the last. Shipped pine: `hand_felling_scale_percent = 100` (85 to 100 of 85 to 115, about half the trees), `hand_felling_milliseconds = 10000`, `axe_felling_milliseconds = [6000, 4000, 2500]` (the wooden axe keeps today's 6 s). `Field_Tree_Species` replaces `felling_ticks` with `hand_felling_scale_percent: u8`, `hand_felling_ticks: u32`, `axe_felling_ticks: [3]u32` (each `max(ms * tick_rate / 1000, 1)`). `tree_species_problem` checks the bounds; `PLANET_TREE_STAND_IN_SPECIES` gets `100`, `1000`, `{1000, 1000, 1000}`.

### The tool decision

- `Field_Held_Tool` gains `Tool` after `Hand` (a shovel, pickaxe or axe). `Field_Player` gains `held_tool_role: Item_Tool_Role` and `held_tool_tier: u8` after `tool`. Both are enum names and fields read by name in the save, so an old save loads them as `Hand` and None/0 and the first tick sets them.
- `field_tool_for_item`: after the `NO_ITEM` check, an item whose `tool_role != .None` returns `.Tool, .Air, NO_MACHINE`. A role-less tool (the hammer, a schematic) still falls through to `.Hand`.
- `update_field_held_tool`: sets `held_tool_role, held_tool_tier` from the item when `tool == .Tool`, `.None, 0` otherwise. A change of role counts as a change of tool for `run_started`. `Next_Brush` cycles the brush with `.Tool` as with `.Material` and `.Hand`.
- `field_player_digs :: proc(player: Field_Player) -> bool`: `tool == .Tool` and the role is `Shovel` or `Pickaxe`. `field_player_edit`'s Dig case becomes `.Dig in input.held && field_player_digs(player)`. Without it no edit is queued: no refusal, no toast, nothing is dug. A toast here would fire under every resting thumb, which is the bug this item fixes. The quests teach the tools instead. Torch removal and the entity pick up keep taking Mine with any item.
- `field_diggable_materials :: proc(table, role: Item_Tool_Role, tool_tier: int)`: item set, `dug_with == role` and `tool_tier <= tool_tier`. `drain_field_dig` passes `player.field.held_tool_role, int(player.field.held_tool_tier)`. `field_tool_tier` (best tier carried) loses its only caller and is removed.
- `report_blocked_dig(player, table, blocked, role)`: no item gives `Undiggable`; `dug_with != role` gives `Needs_Shovel` or `Needs_Pickaxe` from the material's `dug_with`; otherwise `Tool_Tier`.
- `Field_Edit_Refusal` gains `Needs_Shovel`, `Needs_Pickaxe` and `Needs_Axe` at the end, with keys `field_refused_needs_shovel = "Needs a shovel"`, `field_refused_needs_pickaxe = "Needs a pickaxe"` and `field_refused_needs_axe = "Too big to fell by hand, needs an axe"`. `field_edit_refusal_text` (`loop_planet_preview.odin`) adds `"  %s needs a shovel"`, `"  %s needs a pickaxe"` and `"  the tree needs an axe"`.
- Felling: `field_felling_ticks :: proc(species: Field_Tree_Species, tree: Planet_Tree, player: Field_Player) -> (ticks: u32, fellable: bool)`. An axe takes `axe_felling_ticks[clamp(tier, 1, 3) - 1]`. Anything else takes `hand_felling_ticks` when `tree.scale_percent <= hand_felling_scale_percent`, otherwise it is not fellable. In `advance_field_felling`, after the found check and before the inventory check, a tree that is not fellable clears `player.mining`, sets `field_refusal = .Needs_Axe` and returns. `cheat_mining_ticks` is applied as today. The Fell hint stays on every trunk, as the pick up hint does: the press's toast says why.
- `held_glyph_hints`: `field_held_tool_places` is false for `.Hand` and `.Tool`, and `field_held_tool_cycles_brush` is true for `.Material`, `.Hand` and `.Tool`. `field_held_name`: `.Tool` prints `"<role> tier <n>"`.
- The block world is unchanged. Its hand still mines tier 0 blocks, and `player_tool_tier` still takes the best `tool_tier` of any item. A shovel or an axe therefore counts as a pickaxe of its tier there, which is accepted for the legacy world. The new items go after `iron_pickaxe` in `items.sjson` so that `tool_item_for_tier` still names the pickaxes (the first item wins a tie).

### Items, recipes, strings

- Items (category `tool`, stack 50) go after `iron_pickaxe`. The three pickaxes gain `tool_role = "pickaxe"`. `wooden_shovel` (tier 1, price 3), `stone_shovel` (2, 3), `iron_shovel` (3, 4), `wooden_axe` (1, 5), `stone_axe` (2, 5), `iron_axe` (3, 8), with roles `shovel` and `axe`, `name_key = item_<id>`, `description_key = describe_item_<id>`.
- Recipes after `iron_pickaxe`: each shovel takes 1 plank, stone or iron plate and 2 sticks. Each axe takes 3 of them and 2 sticks. All are `seconds = 1`, `made_in = ["hand", "assembler"]`, `category = "tools"`, `channel = "start"`, and tagged `["mining", "wood" | "stone" | "iron"]`. A small pine (4 logs, 16 planks) makes the wooden shovel, pickaxe and axe (9 planks with the sticks) and the stone cutting table (4).
- Names: `Wooden shovel`, `Stone shovel`, `Iron shovel`, `Wooden axe`, `Stone axe`, `Iron axe`.
- Descriptions:
  - `wooden_shovel`: "A plank blade on two sticks. Digs topsoil, the first two metres of ground, into dirt."
  - `stone_shovel`: "A stone blade on two sticks, tool tier 2. Digs topsoil into dirt."
  - `iron_shovel`: "An iron blade on two sticks, tool tier 3. Digs topsoil into dirt."
  - `wooden_axe`: "Three planks and two sticks. Fells any tree in 6 s. A small one also comes down by hand, in 10."
  - `stone_axe`: "A stone head on two sticks. Fells any tree in 4 s."
  - `iron_axe`: "An iron head on two sticks. Fells any tree in 2.5 s."
- Icons: `tools/make_placeholder_textures.py` gains `draw_shovel` (an upright handle with a rounded blade at the top) and `draw_axe` (an upright handle with a blade reaching to the right at the top). `draw_tool` dispatches on the words `shovel` and `axe`. Rerun it: `git status` must show only the six new PNGs under `data/textures/items/`.

### The starter kit and chapter 1

- `starting_items`: `wooden_foundation` 16 and `torch` 4. The stone pickaxe goes, and so do the 8 planks, which would make the wooden tools without a tree. The cutting table's planks now come from the logs. The hotbar's start slot stays slot 1 (`selected_hotbar_slot` 0), which holds the foundations: no digging tool, so a resting thumb digs nothing. The `game.sjson` comment says so.
- Chapter 1 (`data/quests/chapter_01.sjson`) inserts two quests after `bearings`:
  - `timber`: `{obtain log 4}`, with `message_key = "mc_timber"`.
    - `quest_timber_title`: "Timber"
    - `quest_timber_text`: "Fell a small tree by hand for 4 logs. The big ones need an axe."
    - `mc_timber`: "The lease includes the trees. The small ones come down by hand, if you lean on them long enough."
  - `tools`: `{craft wooden_shovel 1}`, `{craft wooden_pickaxe 1}`, with `message_key = "mc_tools"`.
    - `quest_tools_title`: "Tools"
    - `quest_tools_text`: "Make planks and sticks from the logs, then a wooden shovel and a wooden pickaxe."
    - `mc_tools`: "Hands are for signing invoices. The soil wants a shovel, the rock a pickaxe."
- The `stone` quest's text becomes "Dig through the topsoil with the shovel, then 20 stone out of the ground with the pickaxe."
- `rocks` gets `{craft stone_pickaxe 1}` before its hematite objective, and its text becomes "Make a stone pickaxe, find the iron outcrop and mine 10 hematite."
- The rest of the chapter is unchanged. The file header drops "no trees until M14" and the kit's pickaxe.
- Dev kits: chapter 1 gets `wooden_shovel` 1 and `wooden_axe` 1. Chapter 2 gets `stone_shovel` 1 and `stone_axe` 1. Every kit holding `iron_pickaxe` gets `iron_shovel` 1 and `iron_axe` 1.

### Save and network

- No layout change and no remap. The new enum values and fields load by name, and quests remap by id.
- An old hand-dug world loads as it is. Its players dig only with a shovel or a pickaxe selected, so a kit's stone pickaxe still digs stone and the outcrops, and topsoil needs a crafted shovel (the old kit's planks make one). Hand dug holes stay.
- A save whose active quest is later in chapter 1 skips `timber` and `tools`. One with every quest done (no active quest) is given `timber` by `settle_active_quest`; its obtain counts logs since the game began.
- Lockstep: `held_tool_role` and `held_tool_tier` derive from the hotbar inside the tick on every machine.

### Tests

- Fixtures:
  - `hold_test_item(player: ^Player, content: Simulation_Content, item_id: string)` sets `tool`, `held_tool_role` and `held_tool_tier` as `update_field_held_tool` would. The drain tests in `field_mining_test.odin` and the `entity_frames_test.odin` digs use it (a wooden pickaxe on stone, a wooden shovel on topsoil).
  - `field_test_digging_kit()` returns `wooden_shovel 1, wooden_foundation 16, torch 4, plank 8`, so slot numbers keep their old meaning. `field_test_script_frame`'s users and `test_a_held_refused_dig_raises_one_event` set `config.starting_items` to it.
  - The existing felling tests hold a `wooden_axe` in slot 1 (360 ticks stay).
- New tests:
  - `test_mine_with_the_hand_digs_nothing_on_topsoil`: an empty hotbar and Mine held 120 ticks at topsoil in a session. The field's chunk hash is unchanged, no dirt is credited, and no `Field_Refused` event fires.
  - `test_mine_with_planks_selected_digs_nothing`: as above with planks in slot 1. This is the touch hold, since a hold is Mine.
  - `test_the_shovel_digs_topsoil_and_not_stone`: wooden shovel. Topsoil credits dirt; stone credits nothing and refuses `Needs_Pickaxe`.
  - `test_the_pickaxe_digs_stone_and_not_topsoil`: wooden pickaxe. Stone credits stone; topsoil refuses `Needs_Shovel`. `Deep_Stone` with the wooden pickaxe still refuses `Tool_Tier`, the existing table case.
  - `test_the_hand_fells_a_small_tree`: the test species' `hand_felling_scale_percent = 115` and an empty hotbar. The tree stands after `hand_felling_ticks - 1` and is felled with 4 logs on the next tick.
  - `test_the_axe_fells_a_large_tree_the_hand_cannot`: `hand_felling_scale_percent = 0`. The hand holds for `2 * hand_felling_ticks`: the tree stands, `Needs_Axe` is told once and `mining` stays inactive. Then a wooden axe fells it in `axe_felling_ticks[0]`.
  - `test_field_felling_ticks_follow_the_tool`, pure:
    - the hand on small and large trees;
    - a pickaxe on a small tree (the hand's ticks);
    - axes of tiers 1, 2 and 3;
    - a tier 4 axe takes `[2]`.
  - `test_field_tool_for_item_reads_the_role` (replaces the table at `field_mining_test.odin:293`): the pickaxe, shovel and axe give `.Tool` with their role and tier; plank and `geologists_hammer` give `.Hand`; the rest are as before.
  - `test_the_material_table_needs_a_digging_role`:
    - the shipped table matches the specification table;
    - refused: `dug_with = "axe"`, an item with `""`, bedrock with `"shovel"`, a role with `tool_tier = 0`.
  - `test_tool_roles_parse_and_validate`:
    - the nine shipped tools' roles and tiers;
    - refused: a role on a non-tool, a role at tier 0, an unknown role, `tool_tier = 16`.
  - The `data_planet_test.odin` bound table drops the `felling_milliseconds` rows. It adds 99 and 60001 for `hand_felling_milliseconds` and for `axe_felling_milliseconds[1]`, and -1 and 116 for `hand_felling_scale_percent`.
  - `test_the_tool_recipes_resolve`: the six new recipes and the three pickaxes resolve with their inputs, `hand` and `start`.
  - `test_the_starter_kit_holds_no_digging_tool`: no shipped `starting_items` entry has a role, and a new session player's `field.tool` after one tick is not `.Tool`.
  - `test_a_small_tree_stands_near_the_home`: the shipped planet at 8 km over seeds 1 to 16, with a standing tree of scale at most 100 within 80 m of the home (`field_trees_near` or `planet_trees_in_box`). If a seed fails, report the distances; do not change the data.
- Changed tests:
  - `test_the_slice_recipe_chain_is_reachable_from_the_fields_yield` adds `wooden_shovel`, `wooden_pickaxe`, `wooden_axe`, `stone_pickaxe` and `stone_shovel` to `reachable` and checks the first three against the logs.
  - `starter_kit_tool_tier` returns 0, the best `pickaxe` role in the kit.
  - `quest_granted_tool_tier` counts only items with the `pickaxe` role.
  - `test_chapter_one_needs_the_starter_kits_pickaxe` becomes `test_chapter_one_crafts_its_pickaxes_before_it_digs`:
    - `stone` has a problem at tier 0 and none at 1;
    - `rocks` has none at 2;
    - the deep stone hint still has a problem at 2;
    - `quest_granted_tool_tier` of `tools` is 1 and of `rocks` is 2.
  - The `ui_recipe_browser_test.odin:47` tools list adds the six ids in sorted order.
  - `test_the_held_hints_follow_the_tool` follows the new `places` and `cycles_brush` rules.
  - The felling tests' `ticks == 360` reads `axe_felling_ticks[0]`.
- Unchanged, and they must pass untouched: `test_tool_tier_gates_hand_mining`, `test_player_tool_tier_is_the_best_pickaxe_held`, `test_pickaxes_carry_their_tool_tier` (the block world's hand and tool gate).

### Docs

- `doc/content.md`:
  - Tools: replace the field bullet with "On the terrain field a tool digs or fells only while selected on the hotbar (0265): an item's `tool_role` (`shovel`, `pickaxe` or `axe`, tools with `tool_tier` 1 or more) meets a material's `dug_with` and `tool_tier`, and the hand or any other item digs nothing. The block world still counts the best `tool_tier` carried, a shovel's and an axe's included."
  - Field materials and brushes: the `dug_with` key and the shipped table above, with "topsoil gives dirt with any shovel".
  - Trees: the three species keys replace `felling_milliseconds`. The felling bullet becomes "Mine held on a trunk fells it: an axe in `axe_felling_milliseconds` by its tier, the hand or any other item only a small tree (`scale_percent` at most `hand_felling_scale_percent`) in `hand_felling_milliseconds`; a larger one refuses `Needs_Axe`." The shipped pine gets 10 s by hand up to 100 percent and 6, 4 and 2.5 s by axe.
  - The starter kit (Planets) becomes "sixteen `wooden_foundation` and four `torch`, no digging tool (0265): the first logs come from a small tree felled by hand and make the wooden shovel and pickaxe."
  - The slice's chain: logs make the wooden tools and the cutting table, and the kit has no planks.
- `doc/input.md`, Bindings, after "R2 mines": "On the field Mine digs only with a shovel or a pickaxe selected and fells any tree with an axe; with the hand or any other item it digs nothing and fells only a small tree (0265, [content.md](content.md), Tools)."
- `doc/touch_overlay.md`, the hold bullet (line 58): "A hold is Mine, so it digs only while the hotbar's selected slot holds a shovel or a pickaxe (0265); a thumb resting with anything else selected leaves the ground alone."
- `doc/architecture.md`:
  - The tick: "a shovel, pickaxe or axe item the Tool, with its role and tier (0265); anything else is the hand". "Dig is always the hand tool" becomes "Dig digs with the Tool's role and tier (`field_player_digs`, `drain_field_dig`)".
  - The player on the field: "The brush tool (0171): Place held with a material, or Dig held with a shovel or pickaxe (0265), queues a brush edit…".
- `doc/quests.md`: line 49 says "the pickaxe the earlier quests had crafted (the kit has none, 0265)". Line 66 adds the `timber` and `tools` beats and drops "no trees until M14".
- `doc/log/2026-10-05.md`:

  ```
  ## Digging needs a tool (0265)

  Tags: field, tools, shovel, pickaxe, axe, trees, felling, touch, starter-kit, quests, 0265, m14

  The hand digs nothing on the field: Mine digs only with a shovel or a pickaxe selected, so a thumb resting on the phone leaves no hole, and no refusal is toasted for the hand, since it would fire under every resting thumb. Which tool digs what is data on both sides (an item's tool_role, a material's dug_with and tool_tier); tiers gate and do not speed, so the stone and iron shovels dig the shipped topsoil like the wooden one. A small tree is a tree at most hand_felling_scale_percent of its species' size, not a species: a second species would change every recorded world's trees, since the species is the hash modulo the recorded count. The pine falls by hand at up to 100 percent (about half the trees) in 10 s, by axe in 6, 4 and 2.5 s. The kit loses the stone pickaxe and the planks (which would skip the tree), and chapter 1 gains timber and tools. Old saves load without a remap; their players need a shovel for topsoil, and a save with every quest done is handed timber. The block world is unchanged, so a shovel or axe counts there as a pickaxe of its tier.
  ```

- Data headers: `materials.sjson` (dug_with), `items.sjson` (`tool_role`, `tool_tier` up to 15 and its field meaning), `planets.sjson` species comment, `game.sjson` kit comment, the `chapter_01.sjson` header, `tools/make_placeholder_textures.py` docstring (shovel, axe).

### Hand-back check lines that apply

- Numbers parsed from text are range checked: `tool_tier` 0 to 15, the new species bounds and `dug_with` names.
- Old saves: no layout change; the behaviour change for old worlds is named in the log; the dev kits carry the shovels and axes.
- A UI audit case made obsolete: none. No source outside the tests names `stone_pickaxe`, so an audit drawing a session's hotbar shows the new kit, and that is intended.
- Tests use temporary directories only.

### Verify

`taskset -c 8-15 nice -n 10 ./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, and `python3 tools/make_placeholder_textures.py` followed by `git status` (six new icons only). The phone check stays the user's.

### Open questions, answered

- What makes a tree small? A scale threshold per species (no model, no generation change). A species of its own would reroll recorded worlds.
- Should the hand on the ground toast? No: a resting thumb would toast, and the quests teach.
- Do higher tiers dig faster? No, tiers only gate, as in the block world. The material rate stays the one rate.
- Should Next_Brush with the hand keep cycling? Yes, unchanged: the control design adds no binding change.
- Do the kit's planks stay? No: with them the tree is optional.

### For the main agent

1. Is 10 s by hand and the 100 percent threshold (about half the pines) right, or should the small trees be fewer and the hand slower?
2. Should the block world stop counting shovels and axes as pickaxes? It is a one line `stack_tool_tier` filter, but it changes the legacy world, so I left it.
3. A finished old save is handed `timber` (and then `tools`). Should that be accepted, or should the two quests count as done for a save past `bearings`?

Decided (main agent, 2026-10-05): approved. 1: as designed, the couch judges the feel. 2: no, the block world stays as it is. 3: accepted, the log names it. The item descriptions name no number that lives in data (no seconds, no metres), so text and data cannot drift.

Ran: read the named sources, data, tests and docs; no build or experiment.
