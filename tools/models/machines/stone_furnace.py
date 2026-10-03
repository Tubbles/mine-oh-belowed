"""The stone furnace (work item 0204): 2 by 2 by 2 cells, smelting, a
glowing mouth on the front and no moving part (its motion is glow).
Blender frame of kit.py: x the front, y = -game z, z up."""

import math

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py); the furnace takes
    nothing from it, since it has no ports and no moving part."""
    volumes = []
    # Base plate.
    volumes.append(kit.box((-0.96, -0.96, 0.0), (0.96, 0.96, 0.12), "steel_dark", bevel=0.03))
    # The primary volume: the firebox, its mouth cut out of the front.
    firebox = kit.box((-0.82, -0.80, 0.12), (0.78, 0.80, 1.25), "smelting_brick", bevel=0.05)
    kit.cut(firebox, kit.box((0.60, -0.30, 0.30), (0.90, 0.30, 0.75), "soot"))
    volumes.append(firebox)
    # In the mouth: the back plate, the coal bed glowing on the working
    # side, and the lintel over it.
    volumes.append(kit.box((0.58, -0.30, 0.30), (0.62, 0.30, 0.75), "soot"))
    volumes.append(kit.box((0.62, -0.26, 0.30), (0.68, 0.26, 0.38), "heat_glow"))
    volumes.append(kit.box((0.76, -0.36, 0.73), (0.84, 0.36, 0.83), "steel"))
    # Two bands around the firebox, clear of the mouth.
    for bottom, top in ((0.16, 0.22), (0.88, 0.94)):
        volumes.append(kit.box((-0.84, -0.82, bottom), (0.80, 0.82, top), "steel"))
    # Secondary volumes: the hopper and the chimney with its rim, which
    # rises above the footprint's height.
    volumes.append(kit.cone((-0.30, 0.25), 1.25, 1.50, 0.42, 0.25, 4, "galvanised", rotation=math.pi / 4))
    volumes.append(kit.cylinder((-0.50, -0.45), 1.25, 2.35, 0.14, 10, "steel_dark"))
    volumes.append(kit.cylinder((-0.50, -0.45), 2.25, 2.33, 0.18, 10, "steel"))
    # Ribs on the side faces, spaced unevenly.
    for x in (-0.61, -0.19, 0.37):
        volumes.append(kit.box((x - 0.02, 0.80, 0.22), (x + 0.02, 0.83, 0.88), "steel"))
    for x in (-0.55, 0.12):
        volumes.append(kit.box((x - 0.02, -0.83, 0.22), (x + 0.02, -0.80, 0.88), "steel"))
    # Scale cue: the ash door and its handle on the +y side.
    volumes.append(kit.box((-0.45, 0.80, 0.24), (-0.05, 0.84, 0.52), "steel"))
    volumes.append(kit.cylinder((0.858, 0.38), -0.40, -0.10, 0.02, 6, "galvanised", axis="X"))
    kit.join(volumes, "body")
