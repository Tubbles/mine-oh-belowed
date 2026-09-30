# 0144: Code map

Status: todo

## Goal

The third step of the architecture cleanup (user, 2026-09-30): progressive disclosure for the code. An agent opening the source today faces 329 files in one directory; the map lets it read one page, pick a cluster, and open its entry file.

## Change

- `doc/code_map.md`: one section per cluster (the clusters of 0143, refined by its audits): purpose in one line, the entry file, the files in reading order with a half line each, the state it owns, the clusters it may depend on and the ones it must not, the tests that guard it. Generated in part by `tools/code_graph.py` (the file lists and the edges), written by hand for the rest, kept true by `tools/check_docs.py` (every file and name it cites must exist).
- `CLAUDE.md` points at it in the Layout section, `doc/README.md` lists it, `doc/architecture.md` keeps the mechanism and links the map for the file level.
- The allowed dependency table is the first statement of the layering the pilot split (0145) and any later package split follow; a violation found by the graph script is a finding, not a build error, until packages enforce it.

## Verify

- `python3 tools/check_docs.py` passes; `python3 tools/code_graph.py --check doc/code_map.md` (or equivalent) reports every edge that runs against the map's allowed table, and the item lists them as accepted or as refactors queued.
