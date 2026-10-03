# 0208: Re-record the code map's grown edges from the field series

Status: todo (main agent, 2026-10-03: `python3 tools/code_graph.py --check doc/code_map.md` exits 1 on `main` since the field series; found by the 0204 implementer)

## Goal

`doc/code_map.md` records, per cluster, the references the allowed dependency table does not allow, and `tools/code_graph.py --check` fails when one grows. The items of 2026-10-03 (0193 to 0203) grew five edges without the check running, since no verify list named it: world to simulation 232 to 237, content to simulation 101 to 105, content to world 93 to 96, simulation to ui 42 to 44, ui to loop 9 to 10. The record is false until the counts are re-recorded or the references refactored.

## Change

- Run the check, read each grown edge's new references (`tools/code_graph.py --files`), and for each decide: refactor it away where the reference is a plain misplacement (a procedure that belongs in the cluster it reaches into), else re-record the count with the reference named in the cluster's "Reaches into" line, so the M12 audit queue (paused) finds it later.
- `doc/code_map.md` updated; the log names the edges kept and why.

## Verify

- `python3 tools/code_graph.py --check doc/code_map.md` exits 0 on `main`; `python3 tools/check_docs.py` clean; the build and check commands of 0168.
