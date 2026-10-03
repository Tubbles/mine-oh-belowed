"""The wooden chest (work item 0205): 1 by 1 by 1 cells, a chest. A
plank box with a darker overhanging lid on two skid battens, steel
straps at uneven offsets and a latch on the front. No moving part.
Blender frame of kit.py: x the front, y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 1, 1)
    volumes = [
        kit.box((-0.42, 0.28, 0.0), (0.42, 0.40, 0.06), "timber_dark"),
        kit.box((-0.42, -0.40, 0.0), (0.42, -0.28, 0.06), "timber_dark"),
        # The primary volume: the plank box and its overhanging lid.
        kit.box((-0.40, -0.40, 0.06), (0.40, 0.40, 0.62), "timber", bevel=0.02),
        kit.box((-0.43, -0.43, 0.62), (0.43, 0.43, 0.72), "timber_dark", bevel=0.02),
        # Straps at uneven offsets, and the latch.
        kit.box((-0.41, 0.15, 0.05), (0.41, 0.20, 0.63), "steel_dark"),
        kit.box((-0.41, -0.25, 0.05), (0.41, -0.20, 0.63), "steel_dark"),
        kit.box((0.40, -0.06, 0.48), (0.45, 0.06, 0.66), "galvanised"),
    ]
    kit.join(volumes, "body")
