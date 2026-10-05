# 0265: Digging needs a tool: the shovel, the pickaxe and the axe

Status: todo (2026-10-05, from the user: a thumb resting on the phone digs a hole)

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
