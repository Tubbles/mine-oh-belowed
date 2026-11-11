# 0379: The water model as a world option

Status: todo (2026-11-11)

A new world uses the teleport water model and the water tech demo's start uses bodies; nothing lets a player choose. The user (2026-11-11): "teleport for now, but make both selectable from world options".

## Goal

The new world screen offers the water model, teleport by default.

## Controls

No binding. The world setup screen gains a row "Water" with the two values "Flowing" (teleport) and "Pooling" (bodies), stepped like its other choice rows by focus navigation and by the pointer.

## Change

- The row, its strings and a one line description of each value under it.
- The choice goes into the world's record where the model is read today, so a save keeps its model and a joiner takes the host's. An existing save keeps the model it was made with.
- The tech demo's start keeps bodies.
- `tools/frame_profile_views.sjson`: the spring view under both models, which 0367 asked for.
- Docs: the doc that owns the world setup screen and the one that owns the water models; `SUGGESTIONS.md`'s open question closed.

## Verify

- The checks and the suite: a world made with each value simulates under that model, saves and loads with it; the UI audit case of the world setup screen at the smallest size.
- A capture of the screen with the row.
