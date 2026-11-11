# 0354: The view's edge fades everything

Status: todo (2026-11-11)

0343's view distance setting brings the end of the drawn world as near as 256 m, where two things that 1024 m hid show. Its review found by probe that the packed level distances leave selected nodes two levels apart meeting along edges and corners at 256 m and 512 m (130 edge and 49 corner contacts over 48 eyes at 512 m, 230 to 360 m out, against 4 corner contacts at 1024 m): the skirts and curtains cover faces only (`field_node_skirt_faces`), and `field_level_gap_metres` assumes a level's node was chosen for its own distance, where the child of a split node can lie up to its parent's diagonal past it. And `field.fs` scales the haze by the sky's share, so shaded terrain at the view's edge never fades and ends on a hard edge. The landing's capture at 256 m shows a far hilltop standing unfaded in the sky.

## Goal

At every view distance the world ends in haze with no hard edge and no pinhole between levels.

## Controls

None.

## Change

- The haze at the view's end fades shaded ground as it fades lit ground.
- The level distances the setting packs keep nodes two levels apart from meeting at an edge or a corner, or the seam is covered there.
- What the unfaded hilltop of the 256 m capture is (a node past the view, the globe, a tree tile) is found first, since it decides which of the two it belongs to.

## Verify

- The checks and the suite, with a test that no selection at the four view distances holds nodes two levels apart in contact, over many eyes.
- Captures at 256 m and 512 m of the view that showed the hilltop, a grotto mouth at the view's edge, and a ridge 230 to 360 m out, sent to the user.
