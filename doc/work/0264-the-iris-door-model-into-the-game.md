# 0264: The iris door model into the game

Status: todo (2026-10-05, from 0231)

## Goal

The pod's two doors are drawn as the camera iris the modeller built in the pod lab (`tmp/model_lab/pod`, round four: 14 blades, the aperture 0.7 m, the hull pockets closed), in place of the shipped slide, so the open and shut rule of 0231 is seen as a shutter.

## Controls

No binding changes.

## Change

- The lab's `pod_hatch.py`, `pod.py`, palette entries and record values (`blades`, `pivot`, `hinge`, `amplitude`, `axis`, `period_seconds` of the `iris` motion of 0231) integrated as the model items rule of `CLAUDE.md` says: the OBJ regenerated and compared byte for byte with the lab's, the record's open cells set to what the model leaves empty, the collision volumes unchanged.
- The user's acceptance of the lab previews comes first; notes go back to the same modeller.
- Docs: `doc/presentation.md` (Machine models, the hatch), `doc/content.md` (Hatches), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `./build.sh model-check`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- The workbench previews of the pod with the doors shut and open; the couch and the phone: the blades open and shut like a camera's.
