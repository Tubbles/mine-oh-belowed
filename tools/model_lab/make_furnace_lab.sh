#!/bin/bash
# Builds the sealed modelling lab of the stone furnace (work item 0212,
# CLAUDE.md, Model items) under tmp/furnace_lab/: copies of the kit, the
# Blender wrapper, the sjson reader, the machine records, the reference
# images of work/art/ (untracked, the user's, so the script runs from the
# main checkout), the brief, the check and the renderer of
# tools/model_lab/, and nothing else of the repository. A machine whose
# record has open_cells gets them stripped here first, so the modeller
# decides what to leave empty. Work item 0214 generalises it to any
# machine.
#
# Usage: tools/model_lab/make_furnace_lab.sh
set -eu
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
lab=$root/tmp/furnace_lab
rm -rf "$lab"
mkdir -p "$lab/tools/models/machines" "$lab/data/models" "$lab/reference" "$lab/previews"
cp "$root/tools/blender" "$root/tools/sjson.py" "$root/tools/make_models.py" "$lab/tools/"
cp "$root/tools/models/__init__.py" "$root/tools/models/kit.py" "$root/tools/models/palette.py" "$root/tools/models/records.py" "$lab/tools/models/"
cp "$root/data/machines.sjson" "$lab/data/machines.sjson"
art=$root/work/art
cp "$art/2026-10-03-round-4/furnace/banana2_0.png" "$lab/reference/hero_three_quarter.png"
for view in turnaround plan rear_quarter detail_mouth detail_top; do
	cp "$art/2026-10-03-furnace-sheet/$view/banana_0.png" "$lab/reference/$view.png"
done
cp "$art/2026-10-03-furnace-sheet/sheet.png" "$lab/reference/sheet_all_views.png"
cp "$root/tools/model_lab/BRIEF.md" "$root/tools/model_lab/check.py" "$root/tools/model_lab/render.py" "$lab/"
cat > "$lab/tools/models/machines/__init__.py" <<'PY'
"""The machine scripts of this lab: one."""

from . import stone_furnace

MACHINES = {
    "stone_furnace": stone_furnace.build,
}
PY
cat > "$lab/tools/models/machines/stone_furnace.py" <<'PY'
"""The stone furnace. Replace this stub: build(machine) builds the model
in Blender's frame (tools/models/kit.py, the module docstring) and leaves
the scene holding the objects the export writes."""

from .. import kit


def build(machine):
    kit.expect_footprint(machine, 10, 10, 12)
    raise NotImplementedError("the stone furnace is not modelled yet")
PY
find "$lab" -type f | sort
