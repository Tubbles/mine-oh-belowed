#!/usr/bin/env python3
"""Checks data/models/<model>.obj against the lab's limits (the game's
loader rules and the budgets of this lab): the body's and the part's
triangle counts, the material count, the footprint bounds and the
object names. Exit 1 on any problem.

    python3 check.py pod
    python3 check.py pod_hatch
"""

import pathlib
import sys

LAB = pathlib.Path(__file__).resolve().parent
# body triangles, part triangles (0: no part allowed), footprint
# (width x, depth z, height y) in cells.
MODELS = {
    "pod": (12800, 0, (12, 12, 8)),
    "pod_hatch": (3200, 200, (1, 2, 2)),
}
MATERIAL_LIMIT = 8
TOLERANCE = 0.02


def read_obj(path):
    vertices, objects, current, material = [], {}, None, None
    for line in path.read_text().splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "v":
            vertices.append(tuple(float(value) for value in parts[1:4]))
        elif parts[0] in ("o", "g"):
            current = " ".join(parts[1:])
            objects.setdefault(current, [])
        elif parts[0] == "usemtl":
            material = parts[1]
        elif parts[0] == "f":
            corners = [int(token.split("/")[0]) - 1 for token in parts[1:]]
            objects.setdefault(current, []).append((material, corners))
    return vertices, objects


def read_mtl(path):
    materials, name = {}, None
    for line in path.read_text().splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "newmtl":
            name = parts[1]
            materials[name] = {"Kd": None, "Ke": (0.0, 0.0, 0.0)}
        elif parts[0] in ("Kd", "Ke") and name:
            materials[name][parts[0]] = tuple(float(value) for value in parts[1:4])
    return materials


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else "pod"
    if model not in MODELS:
        print(f"unknown model {model}; known: {', '.join(MODELS)}")
        return 1
    body_budget, part_budget, footprint = MODELS[model]
    obj_path = LAB / "data" / "models" / f"{model}.obj"
    mtl_path = LAB / "data" / "models" / f"{model}.mtl"
    if not obj_path.exists():
        print(f"no {obj_path}")
        return 1
    vertices, objects = read_obj(obj_path)
    materials = read_mtl(mtl_path) if mtl_path.exists() else {}
    problems = []
    if "body" not in objects:
        problems.append(f"no object named body (objects: {', '.join(objects) or 'none'})")
    for name in objects:
        if name not in ("body", "part"):
            problems.append(f"object {name!r}: the game reads only body and part")
    body = objects.get("body", [])
    part = objects.get("part", [])
    body_triangles = sum(len(corners) - 2 for _, corners in body)
    part_triangles = sum(len(corners) - 2 for _, corners in part)
    used = sorted({material for material, _ in body + part if material})
    if body_triangles > body_budget:
        problems.append(f"body has {body_triangles} triangles, the budget is {body_budget}")
    if part_budget == 0 and part:
        problems.append(f"{model} has no moving part, but the file holds a part object")
    if part_budget > 0 and not part:
        problems.append(f"{model} moves a part, but the file holds no part object")
    if part_triangles > part_budget:
        problems.append(f"part has {part_triangles} triangles, the budget is {part_budget}")
    if len(used) > MATERIAL_LIMIT:
        problems.append(f"{len(used)} materials over body and part, the limit is {MATERIAL_LIMIT}")
    for name in used:
        if name not in materials:
            problems.append(f"material {name} is not in the .mtl")
    half_x, half_z, height = footprint[0] / 2, footprint[1] / 2, footprint[2]
    low = [1e9] * 3
    high = [-1e9] * 3
    for x, y, z in vertices:
        low = [min(low[0], x), min(low[1], y), min(low[2], z)]
        high = [max(high[0], x), max(high[1], y), max(high[2], z)]
    if vertices:
        if high[0] > half_x + TOLERANCE or low[0] < -half_x - TOLERANCE:
            problems.append(f"x spans {low[0]:.3f} to {high[0]:.3f}, the footprint allows -{half_x} to {half_x}")
        if high[2] > half_z + TOLERANCE or low[2] < -half_z - TOLERANCE:
            problems.append(f"z spans {low[2]:.3f} to {high[2]:.3f}, the footprint allows -{half_z} to {half_z}")
        if low[1] < -TOLERANCE:
            problems.append(f"y reaches {low[1]:.3f}, below the ground")
    emissive = [name for name in used if any(value > 0 for value in materials.get(name, {}).get("Ke", (0, 0, 0)))]
    print(f"{model}: body {body_triangles} triangles (budget {body_budget}), part {part_triangles} (budget {part_budget}), {len(used)} materials (limit {MATERIAL_LIMIT}): {', '.join(used)}")
    print(f"emissive: {', '.join(emissive) or 'none'}")
    if vertices:
        print(f"bounds: x {low[0]:.2f}..{high[0]:.2f}  y {low[1]:.2f}..{high[1]:.2f} (top, may exceed {height})  z {low[2]:.2f}..{high[2]:.2f}  (cells of 0.5 m, the file's frame: y up, z the game's depth)")
    for problem in problems:
        print(f"PROBLEM: {problem}")
    print("OK" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
