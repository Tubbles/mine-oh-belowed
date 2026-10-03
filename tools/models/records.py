"""The machine records of data/machines.sjson for the model scripts (work
item 0207, doc/build.md, The workbench). Plain Python: imported inside
Blender's Python by tools/make_models.py and by records_test.py on the
host, with tools/ on sys.path for sjson.

A script takes its footprint, motion and pivot, ports by name, open
cells and light from here, so the record and the model cannot disagree.
The dataclasses mirror the record as written (the Odin
Machine_Definition's names, defaults its zero values). Points come in
the footprint's frame (from its minimum corner: x the width, y up, z the
depth) and go out in the kit's Blender frame (kit.py: x the front, y the
game's -z, z up, centred on the footprint).
"""

import dataclasses

import sjson

# A face's outward normal in the Blender frame.
FACE_NORMALS = {
    "positive_x": (1.0, 0.0, 0.0),
    "negative_x": (-1.0, 0.0, 0.0),
    "positive_y": (0.0, 0.0, 1.0),
    "negative_y": (0.0, 0.0, -1.0),
    "positive_z": (0.0, -1.0, 0.0),
    "negative_z": (0.0, 1.0, 0.0),
}
# A face's step from the cell's centre in the footprint's frame.
FACE_STEPS = {
    "positive_x": (0.5, 0.0, 0.0),
    "negative_x": (-0.5, 0.0, 0.0),
    "positive_y": (0.0, 0.5, 0.0),
    "negative_y": (0.0, -0.5, 0.0),
    "positive_z": (0.0, 0.0, 0.5),
    "negative_z": (0.0, 0.0, -0.5),
}
# The motions whose part moves (motion_has_part in model_motion.odin).
PART_MOTIONS = ("pump", "bob", "spin", "swing")


@dataclasses.dataclass(frozen=True)
class Footprint:
    width: int
    depth: int
    height: int


@dataclasses.dataclass(frozen=True)
class Motion:
    kind: str = ""
    axis: str = ""
    amplitude: float = 0.0
    period_seconds: float = 0.0
    pivot: tuple = (0.0, 0.0, 0.0)


@dataclasses.dataclass(frozen=True)
class Port:
    name: str
    cell: tuple
    face: str
    every_face: bool
    direction: str
    fluid: str


@dataclasses.dataclass(frozen=True)
class CellBox:
    """The record's from and to, inclusive ("from" is a keyword)."""

    first: tuple
    last: tuple


@dataclasses.dataclass(frozen=True)
class Machine:
    id: str
    model: str
    kind: str
    footprint: Footprint
    motion: Motion
    ports: tuple
    open_cells: tuple
    light_level: int
    light_color: tuple


def cell(record):
    """An {x, y, z} record as a tuple, a missing axis 0."""
    return (record.get("x", 0), record.get("y", 0), record.get("z", 0))


def port_names(records):
    """<direction>_<fluid>, <direction> without a fluid; a repeat takes
    _2, _3 in file order."""
    names, seen = [], {}
    for record in records:
        base = record["direction"] + (f"_{record['fluid']}" if record.get("fluid", "") else "")
        seen[base] = seen.get(base, 0) + 1
        names.append(base if seen[base] == 1 else f"{base}_{seen[base]}")
    return names


def read_ports(records):
    names = port_names(records)
    return tuple(
        Port(name, cell(record.get("cell", {})), record["face"], record["face"] == "all", record["direction"], record.get("fluid", ""))
        for name, record in zip(names, records)
    )


def read_motion(record):
    pivot = tuple(float(value) for value in record.get("pivot", (0, 0, 0)))
    return Motion(record.get("kind", ""), record.get("axis", ""), float(record.get("amplitude", 0)), float(record.get("period_seconds", 0)), pivot)


def read_machine(record):
    footprint = record["footprint"]
    return Machine(
        id=record["id"],
        model=record.get("model", ""),
        kind=record.get("kind", ""),
        footprint=Footprint(footprint["width"], footprint["depth"], footprint["height"]),
        motion=read_motion(record.get("motion", {})),
        ports=read_ports(record.get("fluid_ports", [])),
        open_cells=tuple(CellBox(cell(box["from"]), cell(box["to"])) for box in record.get("open_cells", [])),
        light_level=record.get("light_level", 0),
        light_color=tuple(record.get("light_color", (0, 0, 0))),
    )


def load_machines(path):
    """Machine id to Machine, in file order."""
    return {machine.id: machine for machine in map(read_machine, sjson.load(path)["machines"])}


def machine_for_model(machines, model):
    """The first record naming the model: records sharing a model share
    its geometry."""
    for machine in machines.values():
        if machine.model == model:
            return machine
    raise SystemExit(f"no machine in data/machines.sjson names the model {model}")


def to_blender(machine, point):
    """A point of the footprint's frame in the kit's Blender frame."""
    x, y, z = point
    return (x - machine.footprint.width / 2, -(z - machine.footprint.depth / 2), y)


def footprint_box(machine):
    """The footprint's (minimum, maximum) in the Blender frame."""
    width, depth, height = machine.footprint.width, machine.footprint.depth, machine.footprint.height
    return (-width / 2, -depth / 2, 0.0), (width / 2, depth / 2, float(height))


def pivot(machine):
    return to_blender(machine, machine.motion.pivot)


def port(machine, name):
    for candidate in machine.ports:
        if candidate.name == name:
            return candidate
    known = ", ".join(candidate.name for candidate in machine.ports) or "none"
    raise SystemExit(f"machine {machine.id} has no port {name}; its ports: {known}")


def port_face(machine, port_record):
    """The face's centre and outward normal in the Blender frame."""
    if port_record.every_face:
        raise SystemExit(f"machine {machine.id}: port {port_record.name} is on every face")
    step = FACE_STEPS[port_record.face]
    centre = tuple(coordinate + 0.5 + offset for coordinate, offset in zip(port_record.cell, step))
    return to_blender(machine, centre), FACE_NORMALS[port_record.face]


def open_cell_box(machine, index):
    """The open cell box's (minimum, maximum) in the Blender frame."""
    box = machine.open_cells[index]
    first = to_blender(machine, box.first)
    last = to_blender(machine, tuple(coordinate + 1 for coordinate in box.last))
    return tuple(map(min, first, last)), tuple(map(max, first, last))
