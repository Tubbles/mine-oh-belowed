"""The pod's crafting bench (work item 0198): 1 by 2 by 2 cells, a
crafting station with the hand maker. A steel top at 0.8 m on four legs,
a shelf, a back board with hanging tools and a vise as the scale cue.
No moving part. Blender frame of kit.py: x the front, y = -game z, z
up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 2, 2)
    volumes = []
    for x in (-0.40, 0.40):
        for y in (-0.90, 0.90):
            volumes.append(kit.box((x - 0.04, y - 0.04, 0.0), (x + 0.04, y + 0.04, 1.5), "steel_dark"))
    volumes += [
        # The primary volume: the bench top.
        kit.box((-0.48, -0.98, 1.5), (0.48, 0.98, 1.62), "steel", bevel=0.02),
        kit.box((-0.42, -0.92, 0.40), (0.42, 0.92, 0.46), "galvanised"),
        kit.box((-0.48, -0.98, 1.62), (-0.42, 0.98, 1.98), "logistics_grey"),
        # Scale cue: the vise and its jaw.
        kit.box((0.25, 0.55, 1.62), (0.45, 0.80, 1.80), "power_yellow"),
        kit.box((0.45, 0.58, 1.66), (0.48, 0.77, 1.78), "galvanised"),
        *kit.rib_row("Y", -0.8, 0.2, 4, 0.04, (-0.42, 0.0, 1.70), (-0.38, 0.0, 1.92), "galvanised", kit.model_random(machine, "tools")),
    ]
    kit.join(volumes, "body")
