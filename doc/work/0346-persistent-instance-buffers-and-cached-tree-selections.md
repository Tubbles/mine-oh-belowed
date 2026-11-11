# 0346: Persistent instance buffers and cached tree selections

Status: todo (2026-11-11)

The near trees and the shadow trees are selected by a scan every frame (up to about 35 thousand instances in a dense forest, 0328) and drawn through `DrawMeshInstanced`, which makes and frees a buffer per call (`work/performance_research_0340.md`, 2.2).

## Goal

The trees' CPU cost per frame falls to what changed since the last frame.

## Controls

None.

## Change

- One instance buffer per tree kind, updated in place.
- The near and the shadow selections kept across frames while the eye has moved less than a set share of the near distance, with the same trees drawn.

## Verify

- The checks and the suite, with a test that the cached selection equals a fresh one along a walk.
- 0342's table: the forest views' tree sections on the CPU, before and after.
- Captures of a forest before and after, sent to the user.
