# 0283: Machines work on bare ground for good

Status: todo (2026-10-05)

## Goal

A machine on bare ground works as one on a foundation, Techtonica's way (placing is allowed everywhere and no foundation is required; user, 2026-10-05, "starting to think we should do too"): the sixty minute breakdown of 0201 goes, with the worn and broken states, their HUD hint and the panel's danger line. The flatness check stays so a machine stands level, and foundations remain for the grid: the snapping, the rows, the neat factory.

## Controls

None.

## Change

- `bare_ground_life_minutes` and the records' override go from `game.sjson` and `machines.sjson` with the wear tick and the broken state. Open (design): what `salvage_percent` becomes without a broken state (a tear down of any machine returns the full recipe today), and the quests or notes that teach foundations as the cure for the breakdown.
- Old saves: a worn or broken machine loads sound, one log line; the dev kits cover it.
- Docs: `doc/content.md` (Machines on bare ground), `DESIGN.md` (Building), `doc/hud.md` (the hint), `doc/log`.

## Verify

- Tests: a machine on bare ground runs past sixty minutes; an old save with a broken machine loads it sound; the flatness refusal stays.
- `python3 tools/check_docs.py`.
- The couch.
