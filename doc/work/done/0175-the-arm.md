# 0175: The arm: the inserter as an industrial arm

Status: implemented (2026-10-03; the point lights reach the planet preview's terrain only until the slice, 0179, draws the field in the game)

## Goal

The inserter becomes a big industrial arm with an elbow and a folded resting pose, reaching 2 m when unfolded (a value in data), its cycle (reach, grab, swing, release, return) timed by the belt and the machine it serves so no two arms swing in step (decisions 11 and 12; DESIGN.md, Art direction).

## Change

- The inserter's reach in cells comes from the arm's reach in metres divided by the frame's pitch (2 m at 0.5 m is four cells), in data; the pickup and drop cells follow, and the lane logic of `doc/logistics.md` is unchanged.
- The arm model: a mesh with a base, two segments, an elbow, a wrist and a gripper, built through the pipeline of `doc/presentation.md` (Models) as the first mesh at real scale; the miniature crane model goes.
- Animation: joint angles from the inserter's phase (the existing hand state and progress), the rest pose folded over the base, with the cadence following the work done and never a fixed period (`DESIGN.md`, No perceivable repetition); the arm's light as a point light while it works.
- The arm's panel and the filter stay as the inserter's.
- `doc/logistics.md` (inserters: the reach from data), `doc/presentation.md` (the arm's animation), `doc/content.md` (the arm record) updated.

## Verify

- The build and check commands of 0168; the inserter tests run with the reach from data.
- Tests: an arm with a 2 m reach on a 0.5 m frame picks from four cells away and not five; two arms fed by one belt at different rates have different phases after a minute; the animation's joint angles at rest fold the arm within its base's footprint and at full reach place the gripper over the drop cell.
- A headless render of one arm at rest and one at full reach read by the main agent.
