# 0081 Placement ghosts show the machine

Status: implemented
Milestone: M11

## Goal

Couch request (2026-09-27): "when building belts and inserters its very hard to preview the rotation since all i see is a green ghost box, i would like to see the ghost machine as well." The placement preview (`draw_placement_preview` in `src/render_player.odin`) draws a translucent cube over the footprint with thin line arrows; since 0056 every machine has a model, and the ghost should show it.

## Deliverables

- Machine ghosts: for a machine with an uploaded model (`machine_model` in `src/render_models.odin`) the preview draws the body and the part at rest (phase 0, `motion_transform` is the identity) at the placement's origin and rotation through `model_transform`, translucent and tinted with `GHOST_VALID_COLOR` or `GHOST_INVALID_COLOR`. Add a `draw_model_layers` variant that takes the tint colour with alpha in place of the grey brightness (the material's diffuse colour multiplies the vertex colours; raylib's default blend mode is alpha blending, so the alpha applies; both layers get the tint). No lighting on the ghost: full brightness under the tint, so it reads in the dark. Machines without a model keep the cube. The renderer reaches the preview through `draw_player_world_overlay` (`src/loop.odin` line about 440), which gets the model renderer and the belt renderer as arguments.
- Belt ghosts: the cube goes; the ghost is the belt's own surface, `renderer.models[placement.belt_shape]` drawn exactly as `draw_belt_surfaces` draws a real belt (same position and `DrawModelEx` rotation), tinted translucent green or red. Direction: a flat chevron on top of the surface pointing along the flow (three thick triangles or a `DrawTriangle3D` arrow head plus a shaft, about 0.6 blocks long, in `BELT_GHOST_ARROW_COLOR`), in place of the one pixel line the couch could not read. Curves and ramps use the shape's own surface as today's real belts do.
- Inserter ghosts: the model, plus the pickup cell and the drop cell outlined with `DrawCubeWiresV` the way `draw_drill_drop_cell` outlines the drill's drop cell: the drop cell in `BELT_GHOST_ARROW_COLOR`, the pickup cell in a dimmer colour, and the chevron from the pickup to the drop over the post. The cells come from `inserter_pickup_cell` and `inserter_drop_cell` for the placement's reach (`Machine.inserter_reach`), so a long inserter shows two cells away.
- Drills, splitters, fluid machines and poles keep their extra overlays (the drop cell, the splitter arrow, the port colours, the supply volume) drawn over the model.
- Tests, none opening a window: the belt ghost's position and rotation for every shape and rotation equal those `draw_belt_surfaces` would use for a real belt with the same fields (factor the position and angle into a pure procedure both call); the ghost tint keeps the ghost colours' alpha; the inserter ghost's pickup and drop cells for the four rotations and both reaches; the chevron's triangles point along the flow for each rotation (a pure procedure returning the corners).
- Docs: `doc/ui.md` (the HUD or placement paragraph that mentions the ghost), `doc/logistics.md` (the drill section says "the placement ghost outlines the drop cell": add the inserter's cells), `doc/log/2026-09-27.md`, this item's Status and Notes.

## Verify

- `~/opt/odin/odin check src -vet -strict-style`, `./build.sh test`, `./build.sh release`.
- User: hold a belt, an inserter and a drill; the ghost shows the machine, turns with Rotate, and the arrow and cells say where items go before placing.

## Notes

Files a subagent may touch: `src/render_player.odin`, `src/render_models.odin`, `src/render_belts.odin`, `src/loop.odin` (the call chain arguments only), `src/inserter.odin` (only if a cell helper needs a variant that takes a placement), new tests `src/render_ghost_test.odin` or additions to `src/belt_placement_test.odin`, `doc/ui.md`, `doc/logistics.md`, `doc/log/2026-09-27.md`, this file.

Implemented: `src/render_models.odin` (`draw_model_layers_colored`, `ghost_layer_colors`, `draw_ghost_model`), `src/render_belts.odin` (`belt_surface_pose` shared by real and ghost belts, `placement_ghost_belt`, `ghost_chevron_triangles`, `draw_belt_ghost` with the shape surface), `src/render_player.odin` (`draw_placement_preview` draws the model, `inserter_ghost_cells`, `inserter_ghost_chevron`, `draw_inserter_ghost`), `src/loop.odin` (the renderers passed to `draw_player_world_overlay`), new `src/render_ghost_test.odin` with 4 tests; 710 tests pass. `src/inserter.odin` needed no change: the cells come from `make_inserter` and the existing cell procedures. Decisions are in `doc/log/2026-09-27.md`.
