# 0031 Plastics and chemistry: both routes

Status: todo
Milestone: M7

## Goal

Plastic on the fossil route and on the renewable route from DESIGN.md, with sulfur and bitumen as byproducts that have uses, so the phase 6 puzzle has its trade off.

## Deliverables

- Chemical plant (3 by 3 by 3, electric 210 kW, category `chemistry`, fixed recipe by inputs): plastic bar from 20 litres of petroleum gas plus 1 coal (2 plastic, 1 s), sulfur from 30 litres of petroleum gas plus 30 litres of water (2 sulfur, 1 s), bitumen from 40 litres of heavy oil (1 bitumen, 2 s, a byproduct flagged output of the refining recipe is an alternative; choose the chemical plant route and say why), asphalt block from 2 bitumen plus 4 gravel (a placeable paving block with hardness 3, made in the washer category like concrete, or in the chemical plant; say which).
- Renewable route: wood gasifier (2 by 2 by 3, fuel free, electric 90 kW, category `gasifier`): 4 logs to 60 litres of wood gas (a new gas) plus 1 charcoal; chemical plant recipe syngas plastic: 30 litres of wood gas plus 1 charcoal to 1 plastic (2 s), slower and land hungry as designed. Wood gas also burns in the combustion generator (0032).
- Technologies: `plastics` (100 packs, prerequisite oil processing) unlocks the chemical plant and the fossil plastic and sulfur recipes; `renewable_plastics` (75 packs, prerequisite plastics) unlocks the wood gasifier and the syngas recipe; `bitumen_paving` (50 packs, prerequisite plastics) unlocks bitumen and asphalt.
- Science pack 2 recipe (1 inserter, 1 belt as in Factorio's logistic pack, or plastic based; choose plastic based: 1 plastic bar, 1 copper wire, 1 iron gear, 6 s) and the `logistics_science` technology stops being a placeholder by unlocking it; later technologies may cost pack 2 (make the pack list per technology data driven as it already is).
- Statistics and the recipe browser pick up the new recipes automatically; check the browser's tags (add `oil`, `plastic`, `wood`).
- Tests: every new recipe through the shared machine code including fluid inputs and outputs, gasifier byproduct, technology gating, science pack 2 costs on a technology, the ordering test.

## Verify

- Builds and tests pass.
- User: plastic comes out of a chemical plant on both routes side by side, and the statistics screen shows which route is faster.
