#!/bin/bash
# Builds the sealed modelling lab of the landing pod (work item 0221,
# CLAUDE.md, Model items) under tmp/pod_lab/: copies of the kit, the
# Blender wrapper, the sjson reader, the machine records with the pod's
# footprint widened to 12 by 12 by 8 and its open_cells and fixtures
# stripped (the modeller decides what to leave empty and where the
# fixtures' pockets go) and the hatch's footprint set to 1 by 2 by 2, the
# reference images of work/art/ (untracked, the user's, so the script runs
# from the main checkout), the brief, the check and the renderer of
# tools/model_lab/pod/, and nothing else of the repository. Work item
# 0214 generalises it to any machine.
#
# Usage: tools/model_lab/make_pod_lab.sh
set -eu
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
lab=$root/tmp/pod_lab
rm -rf "$lab"
mkdir -p "$lab/tools/models/machines" "$lab/data/models" "$lab/reference" "$lab/previews"
cp "$root/tools/blender" "$root/tools/sjson.py" "$root/tools/make_models.py" "$lab/tools/"
cp "$root/tools/models/__init__.py" "$root/tools/models/kit.py" "$root/tools/models/palette.py" "$root/tools/models/records.py" "$lab/tools/models/"
python3 - "$root/data/machines.sjson" "$lab/data/machines.sjson" <<'PY'
import re
import sys

source, target = sys.argv[1], sys.argv[2]
text = open(source).read()
# The pod: a 12 by 12 by 8 footprint, no open cells, no fixtures.
start = text.index('\t\tid = "pod"\n')
end = text.index("\n\t}\n", start) + len("\n\t}\n")
pod = text[start:end]
pod = pod.replace("footprint = {width = 12, depth = 8, height = 8}", "footprint = {width = 12, depth = 12, height = 8}")
pod = re.sub(r"\t\t// 12 cells from the outer hatch.*?\n\t\t// 8 across, 8 high.*?\n", "\t\t// 12 by 12 by 8 cells: 6 by 6 by 4 m at the 500 mm pitch (the lab's bound).\n", pod, flags=re.S)
pod = re.sub(r"\t\t// The cabin past the bed.*?open_cells = \[.*?\n\t\t\]\n", "", pod, flags=re.S)
pod = re.sub(r"\t\t// The outer hatch in the front wall.*?fixtures = \[.*?\n\t\t\]\n", "", pod, flags=re.S)
assert "open_cells" not in pod and "fixtures" not in pod, pod
text = text[:start] + pod + text[end:]
# The hatch: 1 by 2 by 2 cells, the motion left for the modeller to set.
start = text.index('\t\tid = "pod_hatch"\n')
end = text.index("\n\t}\n", start) + len("\n\t}\n")
hatch = text[start:end]
hatch = hatch.replace("footprint = {width = 1, depth = 2, height = 4}", "footprint = {width = 1, depth = 2, height = 2}")
hatch = hatch.replace("\t\t// The door panel rises 3.95 cells into the wall's pocket.\n", "\t\t// The motion is the modeller's to set (BRIEF.md, The airlock).\n")
text = text[:start] + hatch + text[end:]
open(target, "w").write(text)
PY
art=$root/work/art
cp "$art/2026-10-04-pod-round-12/edit_3_2_seed_18/banana_0.png" "$lab/reference/interior_kept.png"
cp "$art/2026-10-04-pod-round-12/user_reference.png" "$lab/reference/interior_user_b.png"
cp "$art/2026-10-04-pod-round-11/user_accepted.png" "$lab/reference/interior_user_a.png"
cp "$art/2026-10-04-pod-round-11/interior_seed_21/banana_0.png" "$lab/reference/interior_lean.png"
cp "$root/tools/model_lab/pod/BRIEF.md" "$root/tools/model_lab/pod/check.py" "$root/tools/model_lab/pod/render.py" "$lab/"
cat > "$lab/tools/models/machines/__init__.py" <<'PY'
"""The machine scripts of this lab: the pod and its airlock door."""

from . import pod, pod_hatch

MACHINES = {
    "pod": pod.build,
    "pod_hatch": pod_hatch.build,
}
PY
cat > "$lab/tools/models/machines/pod.py" <<'PY'
"""The landing pod. Replace this stub: build(machine) builds the model
in Blender's frame (tools/models/kit.py, the module docstring) and
leaves the scene holding one object named body (kit.join(volumes,
"body")). The pod has no moving part."""

from .. import kit


def build(machine):
    kit.expect_footprint(machine, 12, 12, 8)
    raise NotImplementedError("the pod is not modelled yet")
PY
cat > "$lab/tools/models/machines/pod_hatch.py" <<'PY'
"""The airlock door of the pod. Replace this stub: build(machine) builds
the door in Blender's frame (tools/models/kit.py, the module docstring)
and leaves the scene holding two objects: body (the frame that stays,
kit.join(volumes, "body")) and part (the shutter that moves by the
record's motion, kit.join_part(volumes, machine, pivot) where pivot is
the record's for a spin or a swing and None for a slide)."""

from .. import kit


def build(machine):
    kit.expect_footprint(machine, 1, 2, 2)
    raise NotImplementedError("the airlock door is not modelled yet")
PY
find "$lab" -type f | sort
