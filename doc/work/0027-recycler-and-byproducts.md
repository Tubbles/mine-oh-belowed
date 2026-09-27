# 0027 Recycler and the byproduct rule

Status: todo
Milestone: M6

## Goal

The byproduct rule from DESIGN.md: every byproduct has a use and a sink, and the sink costs something. The recycler as the universal sink, slag and mud and gravel given uses as building blocks, and the byproduct strictness world setting given its effect.

## Deliverables

- Slag as a byproduct of every smelting recipe in the stone and alloy furnaces (a second output, small count), with recipes slag to gravel (crusher) and gravel plus water to concrete blocks (a new placeable block item), mud to clay (drying in a furnace) and clay to bricks, so each byproduct has a use.
- Recycler (2 by 2 by 2, electric 100 kW): any item with a recipe back into 25 percent of its ingredients rounded down, at least nothing, at the recipe's time; a data flag marks items that cannot be recycled. It is the universal sink and the fix for overproduction.
- Byproduct strictness: strict (default) means byproducts must be handled, so a machine whose byproduct output is full stalls, as it already does; lenient means byproducts that do not fit are voided. Read the world setting where machines complete a craft.
- A flare stack placeholder is phase 6 (gases); not in this item.
- Concrete and brick as placeable blocks with placeholder textures and hardness; paving.
- Tests: slag output shares, recycler arithmetic including the rounding floor and the cannot recycle flag, strictness voiding versus stalling, the new block items placing and mining.

## Verify

- Builds and tests pass.
- User: a furnace line's slag goes to a crusher and a concrete line and paves the floor; the recycler eats an overproduced stack and gives some of it back.
