# 0287: The porthole's glass seen whole from the chair

Status: todo (2026-10-05, from the 0286 design)

## Goal

From the chair the plasma of 0273 fills only the upper part of each porthole, with a straight edge across the glass's middle, in every phase of the entry. Diagnosed by the main agent on 2026-10-05 with the windows drawn without the depth test (`tmp/shot0274/state/mine-oh-belowed/screenshots/diag_nodepth_1272.png` beside `clip_00.png`): the disc then fills the hole, so the sleeve's own lining, which lies between the chair's low eye and a glass placed 0.2 cells out along the sleeve (0273, `windows` of the pod record), hides its lower half. The glass must sit where nothing of the sleeve lies between any eye in the cabin and it.

## Controls

None.

## Change

- The glass placed at the sleeve's cabin end (the record's window positions or an offset in `draw_arrival_windows`, the design decides), the depth test kept, so the plasma and the soot cover the whole hole from the chair and from the cabin floor and never show through the wall.
- Docs: `doc/presentation.md` (The arrival, the windows bullet), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the glass's centre lies at the sleeve's cabin end for every shipped window.
- Headless screenshots from the chair and from the cabin floor at the peak: the whole disc covered, nothing of the plasma outside the hole.
- The couch.
