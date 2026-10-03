# 0205: The model kit and the look of the first machines

Status: todo (user, 2026-10-03: "we can maybe approach techtonica's look. I think techtonica might be the game we are closest resembling, but 'on the surface and in space with multiple planets', and a slightly more low-fi look"; after 0207, before 0196)

## Goal

The look of `DESIGN.md` (Art direction, the rules written on 2026-10-03) applied to the machines the player builds before oil, through the pipeline of 0204. The kit grows the primitives the look needs, and every model is a script of 0207's workbench: it reads its record, is checked by the game and previewed to PNG before it is handed back.

## The look (the art direction pass, main agent, 2026-10-03)

The rules live in `DESIGN.md`, Art direction, one place: silhouette first, details as geometry, flat shading, the triangle budget, the palette of steel and one accent per role, state readable at a glance, scale cues, uneven detail counts. This item applies them; a change to them goes to `DESIGN.md` first.

## Change

- The kit (`tools/models/`): the primitives of 0204 plus a pipe along axis aligned segments with elbows, a ring (bolt heads and flanges), a wedge, a hatch (a bevelled plate with a handle), a rib row with uneven spacing drawn from a per model seed, a strip (a thin inset plate for emissive indicators), and the palette table from `DESIGN.md` as named constants. A script per machine composes them (`tools/models/machines/<id>.py`).
- The models, the machines before oil, each with a `part` group where its record has a motion: wooden_chest, iron_chest, electric_mining_drill, small_pole, big_pole, boiler, steam_engine, offshore_pump, assembler_1, splitter, lamp, power_switch, schematic_crate, wood_gasifier, storage_tank, pump, lab (the stone furnace and the burner mining drill are 0204's). Their .vox files are deleted and `make_placeholder_models.py` stops writing them.
- `doc/presentation.md` Machine models: the kit's primitives and the seed rule, the look by reference to `DESIGN.md`; the log.

## Verify

- The build and check commands of 0168.
- Tests: every machine with a model loads (the content load refuses a malformed model already); the workbench's check (0207) passes over every shipped model, so the budget, the fit and the sweep of `DESIGN.md` are enforced, not remembered.
- The workbench's previews of every model of the set, the front three quarter views sent to the user; the couch judges the look before 0206 writes the rest.
