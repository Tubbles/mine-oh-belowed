"""The burner mining drill (work item 0204): 2 by 2 by 2 cells, mining.
The mast stands at the back, so the moving head (the object part, its
motion a pump along y) shows over the low housing from the front and
from above. The part is built about the shaft axis through Blender
(-0.55, 0), the footprint point (0.45, y, 1.0). Blender frame of kit.py:
x the front, y = -game z, z up."""

from .. import kit

SHAFT = (-0.55, 0.0)


def build_body():
    volumes = []
    # Skid: two rails and a cross plate under the bore.
    for low, high in ((0.60, 0.90), (-0.90, -0.60)):
        volumes.append(kit.box((-0.95, low, 0.0), (0.95, high, 0.14), "steel_dark", bevel=0.03))
    cross_plate = kit.box((-0.95, -0.60, 0.06), (-0.15, 0.60, 0.12), "steel_dark")
    volumes.append(cross_plate)
    # The primary volume: the engine housing, with the firebox slit and
    # the output chute on its front.
    volumes.append(kit.box((-0.10, -0.75, 0.14), (0.90, 0.75, 0.85), "mining_ochre", bevel=0.05))
    volumes.append(kit.box((0.90, -0.60, 0.30), (0.93, -0.30, 0.36), "heat_glow"))
    volumes.append(kit.box((0.90, 0.10, 0.20), (0.98, 0.45, 0.40), "galvanised"))
    # Secondary: the mast, four legs braced on each side, and its crown.
    for x in (-0.85, -0.25):
        for y in (-0.35, 0.35):
            volumes.append(kit.box((x - 0.04, y - 0.04, 0.14), (x + 0.04, y + 0.04, 1.90), "steel"))
    for z in (0.70, 1.30):
        for y in (-0.35, 0.35):
            volumes.append(kit.box((-0.81, y - 0.03, z - 0.03), (-0.29, y + 0.03, z + 0.03), "steel"))
    volumes.append(kit.box((-0.90, -0.40, 1.82), (-0.20, 0.40, 1.95), "steel_dark"))
    # Secondary: the burner chimney.
    volumes.append(kit.cylinder((0.55, 0.45), 0.85, 1.45, 0.10, 8, "steel_dark"))
    # The bore collar the bit sinks into.
    collar = kit.cylinder(SHAFT, 0.14, 0.24, 0.22, 10, "steel_dark")
    volumes.append(collar)
    # The bore the bit moves in, through the collar and the cross plate
    # (the bit's radius 0.10 plus clearance), so the part never passes
    # through the body at any phase of its pump.
    bore = kit.cylinder(SHAFT, -0.05, 0.50, 0.13, 12, "steel_dark")
    kit.cut(collar, bore)
    kit.cut(cross_plate, bore)
    # Scale cue: ladder rungs between the back legs.
    for z in (0.45, 1.05, 1.62):
        volumes.append(kit.cylinder((-0.85, z), -0.35, 0.35, 0.025, 6, "galvanised", axis="Y"))
    kit.join(volumes, "body")


def build_part(machine):
    volumes = [
        kit.box((-0.72, -0.20, 1.25), (-0.38, 0.20, 1.60), "galvanised", bevel=0.03),
        kit.cylinder(SHAFT, 1.60, 1.78, 0.12, 10, "steel_dark"),
        kit.cylinder(SHAFT, 0.45, 1.25, 0.06, 8, "steel"),
        kit.cone(SHAFT, 0.25, 0.45, 0.10, 0.0, 8, "mining_ochre"),
    ]
    kit.join_part(volumes, machine)


def build(machine):
    """machine: its record (tools/models/records.py)."""
    build_body()
    build_part(machine)
