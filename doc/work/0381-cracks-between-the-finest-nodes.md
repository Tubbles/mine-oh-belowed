# 0381: Cracks between the finest nodes

Status: todo (2026-11-12)

Found in 0327's landing capture and traced by 0380's design (2026-11-12): single pixels of the globe's colour show through the ground along the border between two level 0 nodes, where no skirt hangs. Each node is drawn with its own translation (`render_field.odin`, `rl.MatrixTranslate(origin)`; `field.vs`, `mvp * vertexPosition`), so at 8 km from the planet's centre a vertex two nodes share comes out a fraction of a millimetre apart in each, and a few pixel centres fall between the two edges. The cracks are on every such border and show only against a dark floor, as in a cave. The mechanism is read from the matrix path; no capture of the camera matrices confirmed it.

## Goal

A vertex two nodes share lands on the same pixel from both, so no border shows through.

## Controls

None.

## Change

- Draw the nodes so a shared vertex has the same eye relative bits in both (one eye relative origin for the pass, or positions snapped to a grid both nodes share). At a spacing of 333 mm a position unit is not a binary fraction of a metre, which the design has to handle.
- Docs: `doc/presentation.md` (The field session).

## Verify

- The checks and the suite, with a test that two nodes' shared vertices transform to equal clip positions.
- The cave floor capture of 0380 before and after, sent to the user.
