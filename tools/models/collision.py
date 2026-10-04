"""The collision volumes of a model script's collision(b) section (work
item 0230, doc/build.md, Models): axis aligned boxes and round volumes
(cylinders and cone frustums about X, Y or Z), solid or shells, a round
one over a sector, authored in the kit's Blender frame beside the
geometry, written to data/models/<model>.collision.sjson in the game's
frame.

Plain Python, no bpy: the exporter inside Blender, the lab's check
outside it and the host test all import it.

The Blender frame is the kit's (kit.py): cells, +X the front, Z up,
centred on the footprint. The file's frame is the OBJ's: Blender (x, y,
z) is the file's (x, z, -y). A box takes its two corners; a cylinder or
a cone takes centre (the other two coordinates in x, y, z order, as
kit.cylinder: (x, y) for Z, (y, z) for X, (x, z) for Y), start and end
along its axis and a radius at each. shell is the wall only, open at
both ends: a round's along the radius, a box's on the two axes across
its axis. sector is two angles in degrees about the axis by the right
hand rule from the axis's first cyclic perpendicular (Z: from +X towards
+Y; X: from +Y towards +Z; Y: from +Z towards +X), the volume spanning
from the first to the second; None is the full turn. At most
VOLUME_LIMIT volumes, a box shell counting 4.
"""

import dataclasses
import math
import os

FILE_SUFFIX = ".collision.sjson"
VOLUME_LIMIT = 64
TOLERANCE = 0.02
# A full ring's segments in wire_lines, as the game's preview draws them.
WIRE_SEGMENTS = 24

AXES = ("X", "Y", "Z")
AXIS_INDICES = {"X": 0, "Y": 1, "Z": 2}
# The Blender axis to the file's: X stays x, Z is y, Y is z (turned over).
FILE_AXES = {"X": "x", "Y": "z", "Z": "y"}
FILE_AXIS_INDICES = {"x": 0, "y": 1, "z": 2}


@dataclasses.dataclass(frozen=True)
class Volume:
    """In the Blender frame: a box's two corners, a round's axis points."""

    kind: str
    axis: str
    start: tuple
    end: tuple
    radius_start: float = 0.0
    radius_end: float = 0.0
    shell: float = 0.0
    sector: tuple = None


def perpendicular_indices(axis_index):
    """The axis's first and second cyclic perpendicular."""
    return (axis_index + 1) % 3, (axis_index + 2) % 3


def sector_span(sector):
    """From the first angle to the second, 0 to under 360 degrees."""
    return (sector[1] - sector[0]) % 360


def axis_point(centre, along, axis):
    """The point at along on the axis through centre (kit.frustum's
    rule)."""
    return {"X": (along, *centre), "Y": (centre[0], along, centre[1]), "Z": (*centre, along)}[axis]


class Collision:
    """The collector a script's collision(b) fills, in the Blender frame."""

    def __init__(self, machine):
        self.machine = machine
        self.volumes = []

    def fail(self, message):
        raise SystemExit(f"model {self.machine.model}: collision volume {len(self.volumes)}: {message}")

    def count(self):
        return sum(4 if volume.kind == "box" and volume.shell > 0 else 1 for volume in self.volumes)

    def add(self, volume):
        self.volumes.append(volume)
        if self.count() > VOLUME_LIMIT:
            self.volumes.pop()
            self.fail(f"over {VOLUME_LIMIT} volumes (a box shell counts as 4)")

    def check_axis(self, axis):
        if axis not in AXES:
            self.fail(f"axis {axis!r}, not X, Y or Z")

    def check_sector(self, sector):
        if sector is None:
            return None
        if len(sector) != 2:
            self.fail(f"sector {sector!r} is not two angles")
        if not 0 < sector_span(sector) < 360:
            self.fail(f"sector {sector!r} spans {sector_span(sector)} degrees, not more than 0 and less than 360")
        return (float(sector[0]), float(sector[1]))

    def box(self, minimum, maximum, shell=0.0, axis="Z"):
        self.check_axis(axis)
        if any(low >= high for low, high in zip(minimum, maximum)):
            self.fail(f"box {minimum} to {maximum}: the minimum is not below the maximum on every axis")
        first, second = perpendicular_indices(AXIS_INDICES[axis])
        size = [high - low for low, high in zip(minimum, maximum)]
        if shell < 0 or (shell > 0 and (2 * shell >= size[first] or 2 * shell >= size[second])):
            self.fail(f"box shell {shell}: not 0 to under half the box across axis {axis}")
        self.add(Volume("box", axis, tuple(map(float, minimum)), tuple(map(float, maximum)), shell=float(shell)))

    def cylinder(self, centre, start, end, radius, axis="Z", shell=0.0, sector=None):
        self.cone(centre, start, end, radius, radius, axis, shell, sector)

    def cone(self, centre, start, end, radius_start, radius_end, axis="Z", shell=0.0, sector=None):
        self.check_axis(axis)
        if start >= end:
            self.fail(f"start {start} is not below end {end}")
        if radius_start <= 0 or radius_end <= 0:
            self.fail(f"radii {radius_start} and {radius_end}: not both above 0")
        if shell < 0 or shell >= min(radius_start, radius_end):
            self.fail(f"shell {shell}: not 0 to under the smaller radius")
        sector = self.check_sector(sector)
        start_point = tuple(map(float, axis_point(centre, start, axis)))
        end_point = tuple(map(float, axis_point(centre, end, axis)))
        self.add(Volume("round", axis, start_point, end_point, float(radius_start), float(radius_end), float(shell), sector))


def file_point(point):
    """Blender (x, y, z) to the file's (x, z, -y)."""
    x, y, z = point
    return (x, z, -y)


def file_angle(direction, file_axis):
    """A file direction's angle about the file axis, 0 to 360 degrees."""
    first, second = perpendicular_indices(FILE_AXIS_INDICES[file_axis])
    return math.degrees(math.atan2(direction[second], direction[first])) % 360


def file_sector(axis, sector):
    """A Blender sector about axis as the file's about its axis. A Blender
    Y volume's file axis is turned over, so its two angles swap."""
    first, second = perpendicular_indices(AXIS_INDICES[axis])
    file_axis = FILE_AXES[axis]
    angles = []
    for degrees in sector:
        direction = [0.0, 0.0, 0.0]
        direction[first] = math.cos(math.radians(degrees))
        direction[second] = math.sin(math.radians(degrees))
        angles.append(file_angle(file_point(direction), file_axis))
    if axis == "Y":
        angles.reverse()
    return tuple(angles)


def file_volume(volume):
    """The file's dict of a volume: from below to on every axis of a box
    and on a round's axis."""
    if volume.kind == "box":
        first, last = file_point(volume.start), file_point(volume.end)
        entry = {"kind": "box"}
        if volume.shell > 0:
            entry["axis"] = FILE_AXES[volume.axis]
        entry["from"] = tuple(map(min, first, last))
        entry["to"] = tuple(map(max, first, last))
        if volume.shell > 0:
            entry["shell"] = volume.shell
        return entry
    file_axis = FILE_AXES[volume.axis]
    start, end = file_point(volume.start), file_point(volume.end)
    radius_start, radius_end = volume.radius_start, volume.radius_end
    index = FILE_AXIS_INDICES[file_axis]
    if start[index] > end[index]:
        start, end, radius_start, radius_end = end, start, radius_end, radius_start
    entry = {"kind": "round", "axis": file_axis, "from": start, "to": end, "radius_from": radius_start, "radius_to": radius_end}
    if volume.shell > 0:
        entry["shell"] = volume.shell
    if volume.sector is not None:
        entry["sector"] = file_sector(volume.axis, volume.sector)
    return entry


def format_number(value):
    """Six decimals, trailing zeros and a trailing point stripped, -0 as
    0."""
    text = f"{value:.6f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def format_value(value):
    if isinstance(value, str):
        return f'"{value}"'
    if isinstance(value, (tuple, list)):
        return "[" + ", ".join(format_number(item) for item in value) + "]"
    return format_number(value)


def file_text(collision):
    """The file's text: deterministic, so a regeneration writes the same
    bytes."""
    model = collision.machine.model
    lines = [
        f"// The collision volumes of the model {model} (work item 0230, doc/content.md,",
        f"// Models), written by tools/make_models.py from tools/models/machines/{model}.py's",
        "// collision(b): cells of the model's frame, x and z centred, y up, +x the front.",
        "volumes = [",
    ]
    for volume in collision.volumes:
        entry = file_volume(volume)
        members = ", ".join(f"{key} = {format_value(entry[key])}" for key in ("kind", "axis", "from", "to", "radius_from", "radius_to", "shell", "sector") if key in entry)
        lines.append(f"\t{{{members}}}")
    lines.append("]")
    return "\n".join(lines) + "\n"


def write(collision, path):
    """The text to <path>.tmp, then renamed over the path."""
    if collision.count() > VOLUME_LIMIT:
        raise SystemExit(f"model {collision.machine.model}: {collision.count()} collision volumes, at most {VOLUME_LIMIT}")
    temporary = f"{path}.tmp"
    with open(temporary, "w") as file:
        file.write(file_text(collision))
    os.replace(temporary, path)


# For the lab: the file's volumes (dicts as sjson reads them), in the
# file's frame.


def round_radii(entry, along):
    """The outer and inner radius at along on the axis (inner 0 for a
    solid), or None outside the axis span."""
    index = FILE_AXIS_INDICES[entry["axis"]]
    low, high = entry["from"][index], entry["to"][index]
    if not low <= along <= high:
        return None
    share = (along - low) / (high - low)
    outer = entry["radius_from"] + (entry["radius_to"] - entry["radius_from"]) * share
    shell = entry.get("shell", 0)
    return outer, (outer - shell if shell > 0 else 0.0)


def in_sector(sector, angle):
    if sector is None:
        return True
    return (angle - sector[0]) % 360 <= sector_span(sector)


def contains(entry, point):
    """Whether the point lies inside the volume."""
    if entry["kind"] == "box":
        return all(low <= value <= high for low, value, high in zip(entry["from"], point, entry["to"]))
    index = FILE_AXIS_INDICES[entry["axis"]]
    radii = round_radii(entry, point[index])
    if radii is None:
        return False
    first, second = perpendicular_indices(index)
    across = (point[first] - entry["from"][first], point[second] - entry["from"][second])
    radius = math.hypot(*across)
    if not radii[1] <= radius <= radii[0]:
        return False
    return radius == 0 or in_sector(entry.get("sector"), math.degrees(math.atan2(across[1], across[0])))


def bounds(entry):
    """The box round the volume (a round's full turn)."""
    if entry["kind"] == "box":
        return tuple(entry["from"]), tuple(entry["to"])
    index = FILE_AXIS_INDICES[entry["axis"]]
    radius = max(entry["radius_from"], entry["radius_to"])
    minimum = [value - radius for value in entry["from"]]
    maximum = [value + radius for value in entry["from"]]
    minimum[index], maximum[index] = entry["from"][index], entry["to"][index]
    return tuple(minimum), tuple(maximum)


def round_point(entry, radius, degrees, along):
    index = FILE_AXIS_INDICES[entry["axis"]]
    first, second = perpendicular_indices(index)
    point = list(entry["from"])
    point[first] += radius * math.cos(math.radians(degrees))
    point[second] += radius * math.sin(math.radians(degrees))
    point[index] = along
    return tuple(point)


def box_wire_lines(minimum, maximum):
    extent = (minimum, maximum)
    lines = []
    for index in range(3):
        first, second = perpendicular_indices(index)
        for corner in range(4):
            start, end = [0.0] * 3, [0.0] * 3
            start[index], end[index] = minimum[index], maximum[index]
            start[first] = end[first] = extent[corner & 1][first]
            start[second] = end[second] = extent[corner >> 1][second]
            lines.append((tuple(start), tuple(end)))
    return lines


def wire_lines(entry):
    """The volume's outline as (start, end) pairs in the file's frame,
    the rules of the game's collision_volume_wire_lines."""
    if entry["kind"] == "box":
        return box_wire_lines(entry["from"], entry["to"])
    index = FILE_AXIS_INDICES[entry["axis"]]
    sector = entry.get("sector")
    start, span = (sector[0], sector_span(sector)) if sector else (0.0, 360.0)
    segments = max(1, math.ceil(WIRE_SEGMENTS * span / 360)) if sector else WIRE_SEGMENTS
    heights = (entry["from"][index], entry["to"][index])
    shell = entry.get("shell", 0)
    outer = (entry["radius_from"], entry["radius_to"])
    inner = (outer[0] - shell, outer[1] - shell) if shell > 0 else (0.0, 0.0)
    lines = []
    for end in range(2):
        for radius in (outer[end], inner[end]) if shell > 0 else (outer[end],):
            for step in range(segments):
                lines.append((
                    round_point(entry, radius, start + span * step / segments, heights[end]),
                    round_point(entry, radius, start + span * (step + 1) / segments, heights[end]),
                ))
    if not sector:
        for quarter in range(4):
            lines.append((round_point(entry, outer[0], 90 * quarter, heights[0]), round_point(entry, outer[1], 90 * quarter, heights[1])))
        return lines
    for angle in (start, start + span):
        lines.append((round_point(entry, outer[0], angle, heights[0]), round_point(entry, outer[1], angle, heights[1])))
        lines.append((round_point(entry, inner[0], angle, heights[0]), round_point(entry, inner[1], angle, heights[1])))
        for end in range(2):
            lines.append((round_point(entry, inner[end], angle, heights[end]), round_point(entry, outer[end], angle, heights[end])))
    return lines
