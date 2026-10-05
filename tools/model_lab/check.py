#!/usr/bin/env python3
"""Checks data/models/<model>.obj of the lab against the game's limits
(work item 0214, doc/build.md, The workbench): the body's and the part's
triangle counts against the sanity caps that catch a runaway mesh
(work item 0275: the body's as the game's model_body_triangles_cap,
larger for a pod), the material count and
the materials missing from the .mtl, the object names (body, and part
exactly when the record's motion moves a part), the footprint bounds of
every vertex at rest (sideways and below the ground; a model may rise
above its height). With data/models/<model>.collision.sjson (work item
0230) it also lists the collision volumes and checks their count, their
bounds against the footprint and that none enters an open cells box or a
fixture box of the lab's record. For a model whose lab record has an
iris motion (work item 0231) it prints the iris's numbers and checks
them with the game's bounds, and poses the part as the game does (every
blade at the open fractions 0, 1/16, ..., 1) against the footprint. The
limits mirror the game's, pinned by tools/model_lab/check_test.py. Exit
1 on any problem.

    python3 check.py            every model of lab.sjson
    python3 check.py <model>    one
"""

import math
import pathlib
import sys

LAB = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(LAB / "tools"))

import sjson  # noqa: E402
from models import collision, records  # noqa: E402

BODY_TRIANGLES_CAP = 9600
POD_BODY_TRIANGLES_CAP = 76800
PART_TRIANGLES_CAP = 600
MATERIAL_LIMIT = 8
TOLERANCE = 0.02
# The lattice of the intrusion check: samples per cell along each axis.
LATTICE_PER_CELL = 8
# The game's iris bounds (model_motion.odin) and the check's fractions.
IRIS_BLADES = (3, 16)
IRIS_AMPLITUDE_MAXIMUM = 0.5
IRIS_FRACTIONS = 16


def body_triangles_cap(machine):
    """The body's sanity cap, as the game's model_body_triangles_cap."""
    return POD_BODY_TRIANGLES_CAP if machine.kind == "pod" else BODY_TRIANGLES_CAP


def part_triangles_cap(machine):
    """The part's sanity cap; 0 when the motion moves no part."""
    return PART_TRIANGLES_CAP if machine.motion.kind in records.PART_MOTIONS else 0


def lab_models(lab):
    return sjson.load(lab / "lab.sjson")["models"]


def lab_machines(lab):
    return records.load_machines(lab / "data" / "machines.sjson")


def lab_machine(lab, model):
    return records.machine_for_model(lab_machines(lab), model)


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


def record_boxes(lab, model):
    """The lab record's open cells boxes and fixture boxes in the file's
    frame, shrunk by the tolerance: (label, index, minimum, maximum)."""
    machine = lab_machine(lab, model)
    boxes = []
    for label, count, reader in (("open cells box", len(machine.open_cells), records.open_cell_box), ("fixture box", len(machine.fixtures), records.fixture_box)):
        for index in range(count):
            low, high = (collision.file_point(corner) for corner in reader(machine, index))
            minimum = tuple(min(a, b) + TOLERANCE for a, b in zip(low, high))
            maximum = tuple(max(a, b) - TOLERANCE for a, b in zip(low, high))
            boxes.append((label, index, minimum, maximum))
    return boxes


def lattice(minimum, maximum):
    """The samples of a box, the maximum the last on each axis."""
    axes = []
    for low, high in zip(minimum, maximum):
        values, step, value = [], 1 / LATTICE_PER_CELL, low
        while value < high:
            values.append(value)
            value += step
        axes.append(values + [high])
    return [(x, y, z) for x in axes[0] for y in axes[1] for z in axes[2]]


def collision_problems(lab, model, footprint):
    """The volumes' lines and their problems; one line without the file."""
    path = lab / "data" / "models" / f"{model}{collision.FILE_SUFFIX}"
    if not path.exists():
        return ["collision: none"], []
    volumes = sjson.load(path)["volumes"]
    count = sum(4 if entry["kind"] == "box" and entry.get("shell", 0) > 0 else 1 for entry in volumes)
    lines = [f"collision: {count} volumes (limit {collision.VOLUME_LIMIT})"]
    problems = []
    if count > collision.VOLUME_LIMIT:
        problems.append(f"{count} collision volumes, the limit is {collision.VOLUME_LIMIT}")
    half_x, half_z, height = footprint[0] / 2 + TOLERANCE, footprint[1] / 2 + TOLERANCE, footprint[2] + TOLERANCE
    boxes = record_boxes(lab, model)
    for index, entry in enumerate(volumes):
        low, high = collision.bounds(entry)
        lines.append(f"volume {index}: {entry['kind']} {entry.get('axis', '-')} x {low[0]:.3f}..{high[0]:.3f}  y {low[1]:.3f}..{high[1]:.3f}  z {low[2]:.3f}..{high[2]:.3f}")
        if low[0] < -half_x or high[0] > half_x or low[2] < -half_z or high[2] > half_z or low[1] < -TOLERANCE or high[1] > height:
            problems.append(f"volume {index} leaves the footprint plus {TOLERANCE}")
        for label, box_index, minimum, maximum in boxes:
            if any(high[axis] < minimum[axis] or maximum[axis] < low[axis] for axis in range(3)):
                continue
            inside = next((point for point in lattice(minimum, maximum) if collision.contains(entry, point)), None)
            if inside is not None:
                problems.append(f"volume {index} enters {label} {box_index} near ({inside[0]:.3f}, {inside[1]:.3f}, {inside[2]:.3f})")
    return lines, problems


def rotate_about(point, centre, axis, angle):
    """point turned by angle about the axis (0 x, 1 y, 2 z) through
    centre, right handed as the game's axis_rotation_matrix."""
    relative = [value - origin for value, origin in zip(point, centre)]
    cosine, sine = math.cos(angle), math.sin(angle)
    first, second = ((1, 2), (2, 0), (0, 1))[axis]
    a, b = relative[first], relative[second]
    relative[first], relative[second] = cosine * a - sine * b, sine * a + cosine * b
    return tuple(value + origin for value, origin in zip(relative, centre))


def in_footprint(point, footprint):
    """A record point (blocks from the footprint's minimum corner: x the
    width, y up, z the depth) inside the footprint, as the game's
    point_in_footprint."""
    extent = (footprint[0], footprint[2], footprint[1])
    return all(0 <= value <= limit for value, limit in zip(point, extent))


def iris_record_problems(machine, footprint):
    """The iris's numbers against the game's bounds."""
    motion = machine.motion
    problems = []
    if not IRIS_BLADES[0] <= motion.blades <= IRIS_BLADES[1]:
        problems.append(f"machine {machine.id!r} has iris blades {motion.blades} outside {IRIS_BLADES[0]} to {IRIS_BLADES[1]}")
    if not 0 < motion.amplitude <= IRIS_AMPLITUDE_MAXIMUM:
        problems.append(f"machine {machine.id!r} has an iris amplitude outside 0 to {IRIS_AMPLITUDE_MAXIMUM} turn")
    if not in_footprint(motion.pivot, footprint):
        problems.append(f"machine {machine.id!r} has a motion pivot outside its footprint")
    if not in_footprint(motion.hinge, footprint):
        problems.append(f"machine {machine.id!r} has an iris hinge outside its footprint")
    return problems


def iris_problems(lab, model, footprint, vertices, part):
    """The iris's lines and problems; nothing for another motion. The
    blade's vertices are posed in the file's frame (x and z centred, y
    up), blade k of n at fraction f as R(centre, k / n turn) R(hinge,
    amplitude * f turn)."""
    machine = lab_machine(lab, model)
    motion = machine.motion
    if motion.kind != "iris":
        return [], []
    lines = [f"iris: {motion.blades} blades, amplitude {motion.amplitude:g} turn, pivot {list(motion.pivot)}, hinge {list(motion.hinge)} (record cells)"]
    problems = iris_record_problems(machine, footprint)
    if problems or motion.axis not in ("x", "y", "z"):
        return lines, problems
    axis = "xyz".index(motion.axis)
    shift = (footprint[0] / 2, 0.0, footprint[1] / 2)
    centre = tuple(value - offset for value, offset in zip(motion.pivot, shift))
    hinge = tuple(value - offset for value, offset in zip(motion.hinge, shift))
    indices = sorted({index for _, corners in part for index in corners})
    blade_points = [vertices[index] for index in indices]
    limits = ((-footprint[0] / 2, footprint[0] / 2), (0.0, float(footprint[2])), (-footprint[1] / 2, footprint[1] / 2))
    for blade in range(motion.blades):
        slot = 2 * math.pi * blade / motion.blades
        for step in range(IRIS_FRACTIONS + 1):
            fraction = step / IRIS_FRACTIONS
            opening = 2 * math.pi * motion.amplitude * fraction
            posed = [rotate_about(rotate_about(point, hinge, axis, opening), centre, axis, slot) for point in blade_points]
            for index, name in enumerate("xyz"):
                low, high = min(point[index] for point in posed), max(point[index] for point in posed)
                if low < limits[index][0] - TOLERANCE or high > limits[index][1] + TOLERANCE:
                    problems.append(f"blade {blade} at open fraction {fraction:g} leaves the footprint ({name} spans {low:.3f} to {high:.3f})")
                    break
            else:
                continue
            break
    return lines, problems


def object_problems(model, objects, part_maximum):
    """The object names against body and, under a part motion, part."""
    problems = []
    if "body" not in objects:
        problems.append(f"no object named body (objects: {', '.join(objects) or 'none'})")
    for name in objects:
        if name not in ("body", "part"):
            problems.append(f"object {name!r}: the game reads only body and part")
    if part_maximum == 0 and "part" in objects:
        problems.append(f"{model} has no moving part, but the file holds a part object")
    if part_maximum > 0 and "part" not in objects:
        problems.append(f"{model} moves a part, but the file holds no part object")
    return problems


def vertex_bounds(vertices):
    """The (low, high) corners over every vertex."""
    low = tuple(min(vertex[axis] for vertex in vertices) for axis in range(3))
    high = tuple(max(vertex[axis] for vertex in vertices) for axis in range(3))
    return low, high


def bounds_problems(low, high, footprint):
    """A vertex past the sides or below the ground; no bound above."""
    half_x, half_z = footprint[0] / 2, footprint[1] / 2
    problems = []
    if high[0] > half_x + TOLERANCE or low[0] < -half_x - TOLERANCE:
        problems.append(f"x spans {low[0]:.3f} to {high[0]:.3f}, the footprint allows -{half_x:g} to {half_x:g}")
    if high[2] > half_z + TOLERANCE or low[2] < -half_z - TOLERANCE:
        problems.append(f"z spans {low[2]:.3f} to {high[2]:.3f}, the footprint allows -{half_z:g} to {half_z:g}")
    if low[1] < -TOLERANCE:
        problems.append(f"y reaches {low[1]:.3f}, below the ground")
    return problems


def check_model(lab, model):
    """The report lines and the problems of one model of the lab."""
    machine = lab_machine(lab, model)
    footprint = (machine.footprint.width, machine.footprint.depth, machine.footprint.height)
    obj_path = lab / "data" / "models" / f"{model}.obj"
    mtl_path = lab / "data" / "models" / f"{model}.mtl"
    if not obj_path.exists():
        return [], [f"no {obj_path}"]
    vertices, objects = read_obj(obj_path)
    materials = read_mtl(mtl_path) if mtl_path.exists() else {}
    body_cap, part_cap = body_triangles_cap(machine), part_triangles_cap(machine)
    problems = object_problems(model, objects, part_cap)
    body = objects.get("body", [])
    part = objects.get("part", [])
    body_triangles = sum(len(corners) - 2 for _, corners in body)
    part_triangles = sum(len(corners) - 2 for _, corners in part)
    used = sorted({material for material, _ in body + part if material})
    if body_triangles > body_cap:
        problems.append(f"body has {body_triangles} triangles, over the sanity cap {body_cap}")
    if part_triangles > part_cap and part_cap > 0:
        problems.append(f"part has {part_triangles} triangles, over the sanity cap {part_cap}")
    if len(used) > MATERIAL_LIMIT:
        problems.append(f"{len(used)} materials over body and part, the limit is {MATERIAL_LIMIT}")
    problems += [f"material {name} is not in the .mtl" for name in used if name not in materials]
    emissive = [name for name in used if any(value > 0 for value in materials.get(name, {}).get("Ke", (0, 0, 0)))]
    lines = [
        f"{model}: body {body_triangles} triangles (cap {body_cap}), part {part_triangles} (cap {part_cap}), {len(used)} materials (limit {MATERIAL_LIMIT}): {', '.join(used)}",
        f"emissive: {', '.join(emissive) or 'none'}",
    ]
    if vertices:
        low, high = vertex_bounds(vertices)
        problems += bounds_problems(low, high, footprint)
        lines.append(f"bounds: x {low[0]:.2f}..{high[0]:.2f}  y {low[1]:.2f}..{high[1]:.2f} (top, may exceed {footprint[2]})  z {low[2]:.2f}..{high[2]:.2f}  (cells of 0.5 m, the file's frame: y up, z the game's depth)")
    for more_lines, more_problems in (iris_problems(lab, model, footprint, vertices, part), collision_problems(lab, model, footprint)):
        lines += more_lines
        problems += more_problems
    return lines, problems


def model_report(lab, model):
    """The lines and problems of one requested model, one the lab's
    records do not name a problem naming the lab's models."""
    if model not in {machine.model for machine in lab_machines(lab).values()}:
        return [], [f"unknown model {model}; this lab's models: {', '.join(lab_models(lab))}"]
    return check_model(lab, model)


def main():
    models = sys.argv[1:] or lab_models(LAB)
    failed = False
    for model in models:
        lines, problems = model_report(LAB, model)
        for line in lines:
            print(line)
        for problem in problems:
            print(f"PROBLEM: {problem}")
        print("OK" if not problems else f"{len(problems)} problem(s)")
        failed = failed or bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
