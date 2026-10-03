# 0176: Belt and pipe curves between frames on free poles

Status: implemented

## Goal

Free belts between foundation islands as Satisfactory's: poles placed freely, the run between two endpoints a cubic curve derived from the endpoints' positions and facings under constraints, its arc length in fixed point, items as a distance along the line as today, the mesh swept along the curve, a preview before the second press (decision 13; 0167, Belts and pipes between frames).

## Change

- A pole entity in the simulation (world position in the planet frame, a facing, a height) placed on the terrain or on a frame cell; a run is created from pole to pole or pole to a frame cell's belt end.
- The curve: a cubic with the facings as tangents, the tangent lengths from the span; constrained to incline or turn, never both at once, within a maximum span and slope in data; the arc length by fixed point subdivision (a fixed number of segments), so every machine agrees; a run that breaks a constraint is refused with the reason.
- Belt lines (`doc/logistics.md`) gain a run as a segment of length equal to the arc length; items keep their distance along the line; a run's point at a distance maps to the world for the renderer and collision.
- The renderer sweeps the belt mesh along the curve's subdivisions; pipes sweep the pipe mesh on the same poles.
- Placement on the gamepad: the first press places or selects the first endpoint, the ghost shows the curve to the reticle's candidate as the player aims, the second press confirms; the reticle's selection assist offers poles and belt ends.
- `doc/logistics.md` (runs) and `doc/presentation.md` (swept meshes) updated.

## Verify

- The build and check commands of 0168.
- Tests: a run between two poles 10 m apart with aligned facings is straight and 10 m long within a centimetre; a run with facings at right angles is a quarter turn whose length matches the subdivision; a run that would incline and turn at once is refused; items on a line with a run keep their spacing across the run; two instances compute the same arc length bytes.
- A headless render of two islands joined by a run read by the main agent.
