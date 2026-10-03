"""The stone cutting table (work items 0196, 0205): 2 by 1 by 2 cells,
a crafting station built by hand. A timber workbench at 0.8 m with a
shelf below, a stone block with a cut groove on the top, a chisel and a
mallet beside it: the tools are the scale cue. No moving part. Blender
frame of kit.py: x the front, y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 2, 1, 2)
    volumes = []
    for x in (-0.85, 0.85):
        for y in (-0.38, 0.38):
            volumes.append(kit.box((x - 0.05, y - 0.05, 0.0), (x + 0.05, y + 0.05, 1.60), "timber_dark"))
    block = kit.box((-0.55, -0.25, 1.72), (-0.05, 0.20, 1.98), "stone")
    kit.opening(block, (-0.30, -0.26, 1.85), (-0.27, 0.21, 1.99))
    volumes += [
        kit.box((-0.88, -0.40, 0.40), (0.88, 0.40, 0.46), "timber"),
        # The primary volume: the bench top.
        kit.box((-0.98, -0.48, 1.60), (0.98, 0.48, 1.72), "timber", bevel=0.02),
        block,
        # The chisel and the mallet.
        kit.box((0.25, 0.10, 1.72), (0.55, 0.14, 1.75), "steel"),
        kit.cylinder((0.12, 1.735), 0.55, 0.75, 0.025, 6, "timber", axis="X"),
        kit.box((0.20, -0.30, 1.72), (0.36, -0.16, 1.84), "timber_dark"),
        kit.cylinder((-0.23, 1.78), 0.36, 0.62, 0.02, 6, "timber", axis="X"),
    ]
    kit.join(volumes, "body")
