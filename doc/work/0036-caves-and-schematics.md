# 0036 Caves, schematics and alternate recipes

Status: todo
Milestone: M8

## Goal

The optional underground tenth: caves hold schematic items that unlock alternate recipes, so exploring pays in recipe choice as the design intends, without ever being required.

## Deliverables

- Cave features: generation places schematic crates (a small non minable entity like the capsule with one slot holding a schematic item) in cave pockets below a depth threshold at a low density per region, deterministic from the region hash, and small rare deposits (gold ore and quartz blocks in cave walls) near them so the cave is worth the walk.
- Schematics: items (`schematic_<name>`) that, when used from the hotbar (a new `Use` action on the selected item: L2 with a schematic selected, or Interact on the crate takes and reads it), unlock one alternate recipe through a new `schematic` recipe channel. Alternates in data, four to start: iron plate from low grade hematite directly at half yield (fewer machines), steel from iron plate and charcoal (no coal), plastic from wood gas without charcoal (cheaper renewable route), concrete from slag and water without crushing (a byproduct turned into a product). Each is a real recipe with `channel = "schematic"` and a schematic id.
- The recipe browser shows schematic recipes as silhouettes with "Found in caves" until unlocked; the journal message log records a found schematic.
- Statistics: schematics found, for quests.
- Tests: crate placement determinism and density, the use action unlocking exactly its recipe, the schematic channel in `Recipe_Unlocks`, silhouettes, save round trip of found schematics.

## Verify

- Builds and tests pass.
- User: find a crate in a cave, read the schematic, and see the alternate recipe lose its silhouette.
