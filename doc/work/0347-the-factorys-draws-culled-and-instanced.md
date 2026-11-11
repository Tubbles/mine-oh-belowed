# 0347: The factory's draws culled and instanced

Status: todo (2026-11-11)

Every machine (up to 4 draw calls each), every foundation cell (twice a frame) and every belt item is drawn every frame wherever it is, with no culling (`work/performance_research_0340.md`, 2.2; `doc/audit/presentation.md`). Small with a handful of machines, the largest CPU item of the frame once factories grow. Builds on 0163 (`work/0163-per-frame-machine-view.md`).

## Goal

A factory's draw cost follows what is in view, in a few instanced calls per model.

## Controls

None.

## Change

- One list of machines per frame, culled by the frustum and a distance, grouped by model and drawn instanced, the light tint and the glow per instance.
- Foundations as instances or one mesh per frame table revision; belt items instanced per kind.
- The pod and the ghosts keep their own path. The looks do not change.

## Verify

- The checks and the suite; the UI and model audits unchanged.
- 0342's table: the early factory view and a factory of 1000 machines by blueprint, draw calls and the CPU's entity section, before and after.
- Captures of a factory before and after, sent to the user.
