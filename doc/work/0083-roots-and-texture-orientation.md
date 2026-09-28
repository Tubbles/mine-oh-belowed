# 0083 Couch findings: no tree roots, upright side textures

Status: todo
Milestone: M11

## Goal

Couch report (2026-09-28): the root logs beside tree trunks read as obscene ("we need to skip the tree roots"), and some textures are rotated 90 degrees, the grass block's sides among them.

## Deliverables

- Roots removed: no species grows root logs. The `roots` field leaves `data/trees.sjson` and `Tree_Species_Definition`, and `Tree.root_directions`, `tree_root_directions`, `tree_roots_contain`, `MINIMUM_ROOTED_TRUNK_HEIGHT`, `ROOTED_CROWN_MINIMUM_HEIGHT` and the rooted branch of `conical_crown_bottom` go with it (`src/generation_features.odin`, `src/generation_trees.odin`); `tree_log_contains` is the trunk alone and the tree's box no longer reaches a block sideways at the foot. Tests that asserted roots (`src/generation_trees_test.odin`, `src/tree_felling_test.odin`, `test_roots_only_on_tall_rooted_trees` and the felling count) are removed or reduced to the trunk. `GENERATOR_VERSION` goes to 6 (`src/generation_terrain.odin`). `doc/content.md` and the header of `data/trees.sjson` drop the roots.
- Texture orientation, in `src/world_mesh.odin`: today a face's texcoord x runs along `(axis + 1) % 3` and y along `(axis + 2) % 3`, so faces along x have their texture turned a quarter (x along world y), top and bottom faces are turned a quarter against the z faces, and the atlas row 0 (the top of a texture, where the grass fringe is) lands at the bottom of every side face since texcoord y grows with world y. The rule becomes: on a side face texcoord x runs along the horizontal world axis (z for faces along x, x for faces along z) and texcoord y runs down from the face's top (the rectangle's highest y gives 0), so row 0 of the texture is the top of the face; on top and bottom faces texcoord x runs along world x and y along world z. `quad_corners` and `append_quad` compute the texcoords per corner from the corner's position and the rectangle's bounds (a pure `face_texcoord(direction, corner, rectangle_minimum, rectangle_maximum)` with a test per face direction), `shaped_quad_texcoords` follows the same rule (a slab side shows the lower half of its tile, so its texcoord y runs from 0.5 to 1), and the water shader's flow mapping (`data/shaders/water.fs`, which turns the world flow into the face's texcoord axes) is updated to the new axes with its comment. The fragment shaders keep `fract(texcoord)`, so merged quads still tile.
- Tests (`src/world_mesh_test.odin`): for a +z face and a -x face the corner at the top of the face has texcoord y 0 and the bottom corner has y equal to the face height, and texcoord x follows the horizontal axis; a top face's texcoords follow x and z; the shaped slab side's texcoord y range; the existing mesh tests updated to the rule.
- Docs: `doc/architecture.md` (the meshing line's texcoord sentence), `doc/work/0061-block-shapes.md` (the known limit is resolved), `doc/log/2026-09-28.md`, this item.

## Verify

- `~/opt/odin/odin check src -vet -strict-style`, `./build.sh test`, `./build.sh release`.
- User: the grass fringe sits at the top of every side of a grass block, log bark runs vertically on every side, no root logs.

## Notes

Files a subagent may touch: `src/generation_features.odin`, `src/generation_trees.odin`, `src/generation_trees_test.odin`, `src/tree_felling_test.odin`, `src/generation_terrain.odin` (the version constant), `src/world_mesh.odin`, `src/world_mesh_test.odin`, `data/shaders/water.fs`, `data/trees.sjson`, `doc/content.md`, `doc/architecture.md`, `doc/work/0061-block-shapes.md`, `doc/log/2026-09-28.md`, this file.
