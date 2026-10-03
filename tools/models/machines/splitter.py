"""The splitter (work item 0205): 1 by 2 by 1 cells. Two low side walls
with yellow caps and a gantry beam across both belt halves carrying the
gate housing and a grab handle (the scale cue, 0.6 cells). Nothing stands
between y -0.92 and 0.92 below z 0.50, where the belt and its items
pass. No moving part. Blender frame of kit.py: x the front, y = -game z,
z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 2, 1)
    volumes = []
    # The primary volumes: the side walls and their caps.
    for sign in (-1, 1):
        volumes.append(kit.box((-0.48, min(sign * 0.92, sign * 1.00), 0.0), (0.48, max(sign * 0.92, sign * 1.00), 0.50), "logistics_grey", bevel=0.02))
        volumes.append(kit.box((-0.48, min(sign * 0.91, sign * 1.00), 0.50), (0.48, max(sign * 0.91, sign * 1.00), 0.53), "power_yellow"))
    volumes += [
        # The gantry beam, its yellow edges and the gate housing.
        kit.box((-0.10, -0.98, 0.50), (0.10, 0.98, 0.62), "logistics_grey"),
        kit.box((0.10, -0.90, 0.52), (0.12, 0.90, 0.60), "power_yellow"),
        kit.box((-0.12, -0.90, 0.52), (-0.10, 0.90, 0.60), "power_yellow"),
        kit.box((-0.14, -0.20, 0.62), (0.14, 0.12, 0.74), "steel_dark"),
        # The grab handle on two standoffs.
        kit.box((-0.02, 0.25, 0.66), (0.02, 0.85, 0.70), "galvanised"),
        kit.box((-0.02, 0.25, 0.62), (0.02, 0.29, 0.66), "galvanised"),
        kit.box((-0.02, 0.81, 0.62), (0.02, 0.85, 0.66), "galvanised"),
    ]
    kit.join(volumes, "body")
