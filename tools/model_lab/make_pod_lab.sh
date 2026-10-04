#!/bin/bash
# Builds the sealed modelling lab of the landing pod (work item 0221,
# CLAUDE.md, Model items) under tmp/pod_lab/ (or the directory given):
# copies of the kit, the Blender wrapper, the sjson reader, the machine
# records with the pod's open_cells, fixtures, lights and
# interior_light_share stripped by key (the modeller decides what to
# leave empty, where the fixtures' pockets and the lamps go), the
# footprints as the records have them (the pod 12 by 12 by 8, the hatch 1
# by 2 by 2 since 0221), the reference images of work/art/ (untracked,
# the user's, read from the main checkout, also from a worktree), the
# brief, the check and the renderer of tools/model_lab/pod/, and nothing
# else of the repository. The lab is built in a staging directory and
# replaces the old one only when every step succeeded. Work item 0214
# generalises it to any machine.
#
# Usage: tools/model_lab/make_pod_lab.sh [lab directory]
set -eu
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
lab=${1:-$root/tmp/pod_lab}
mkdir -p "$(dirname "$lab")"
staging=$(mktemp -d "$lab.staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT
final=$lab
lab=$staging
mkdir -p "$lab/tools/models/machines" "$lab/data/models" "$lab/reference" "$lab/previews"
cp "$root/tools/blender" "$root/tools/sjson.py" "$root/tools/make_models.py" "$lab/tools/"
cp "$root/tools/models/__init__.py" "$root/tools/models/kit.py" "$root/tools/models/palette.py" "$root/tools/models/records.py" "$lab/tools/models/"
python3 - "$root/data/machines.sjson" "$lab/data/machines.sjson" <<'PY'
import sys

STRIPPED = ("open_cells = ", "fixtures = ", "lights = ", "interior_light_share = ")


def strip_entries(lines):
    """The record's lines without the stripped keys' entries (a value
    line, or an array to its closing bracket) and the comment lines
    directly above each."""
    kept = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith("\t\t") or not line.strip().startswith(STRIPPED):
            kept.append(line)
            index += 1
            continue
        while kept and kept[-1].strip().startswith("//"):
            kept.pop()
        if line.rstrip().endswith("["):
            while lines[index].rstrip() != "\t\t]":
                index += 1
        index += 1
    return kept


source, target = sys.argv[1], sys.argv[2]
text = open(source).read()
start = text.index('\t\tid = "pod"\n')
end = text.index("\n\t}\n", start) + len("\n\t}\n")
pod = "\n".join(strip_entries(text[start:end].split("\n")))
for key in STRIPPED:
    assert key not in pod, (key, pod)
assert "footprint = {width = 12, depth = 12, height = 8}" in pod, pod
open(target, "w").write(text[:start] + pod + text[end:])
PY
art=$(cd "$(git -C "$root" rev-parse --git-common-dir)/.." && pwd)/work/art
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
rm -rf "$final"
mv "$lab" "$final"
trap - EXIT
find "$final" -type f | sort
