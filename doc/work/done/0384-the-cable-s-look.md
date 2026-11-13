# 0384: The cable's look

Status: landed (2026-11-13, cb57d6a)

Step 3 of 0368's specification (`done/0368-cables-junction-boxes-and-the-poles-removal.md`, Steps and "The draw", step 3), split off at its approval. 0368 draws a cable as a line along its sag.

## Goal

A cable reads as a cable near the eye and costs little far from it.

## Controls

None.

## Change

- As 0368's specification, step 3: instanced boxes along the sag within 32 m, the `cables` instance buffer, lines beyond, and the frame profile's factory view with cables. Presentation only.
- After 0368. Independent of 0383.

## Verify

- The checks and the suite.
- Captures of a hand run factory near and at the haze, before and after, sent to the user.
- In the night window: the factory view's row with cables.

### Deviations (implementation, 2026-11-13)

- `draw_cables` takes the carried runs (`runs: []Cable_Look`), and step 1's `draw_cable_run` and `draw_field_cable_runs` became `cable_run_look` and `field_cable_run_looks`: the runs' boxes go up with the cables' in one write of the cables buffer and one instanced draw, as a viewport's buffers are written at most once a frame and no instanced draw sits inside the flat batch (0360).
- The block world keeps the lines everywhere: it has no instance buffer and passes no view, so no eye to measure from.
- A box carries no alpha (the instance's bottom row is the colour's red, green and blue), so a refused run near the eye is opaque `BELT_RUN_REFUSED_COLOR` where its line was see through.
- After the review: the line stays under the boxes near the eye, not only beyond 32 m. Without multisampling a box under a pixel wide breaks into dashes, and the box hides the line by depth where it is wider.
- After the review: `cable_segment_instance` takes a side axis, one per cable (`cable_side_axis`, the normal of the curve's plane), so the boxes' corners meet at every joint. A side axis per segment turned the boxes where a segment's world y crossed 0.9.
