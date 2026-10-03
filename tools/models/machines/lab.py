"""The lab (work item 0205): 3 by 3 by 2 cells, science white. A
bevelled cabinet under a cupola ringed by a cyan band, a sensor mast
with a dish, two unequal cyan strips and a sample hatch on the front
(the scale cue), vents on a side. No moving part (its motion is glow).
Blender frame of kit.py: x the front, y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 3, 3, 2)
    volumes = [
        kit.box((-1.45, -1.45, 0.0), (1.45, 1.45, 0.10), "steel_dark"),
        # The primary volume: the cabinet, its deck and the cupola.
        kit.box((-1.30, -1.30, 0.10), (1.30, 1.30, 0.90), "science_white", bevel=0.05),
        kit.box((-1.34, -1.34, 0.90), (1.34, 1.34, 0.98), "steel"),
        kit.cone((0.0, 0.0), 0.98, 1.70, 0.95, 0.60, 8, "galvanised"),
        kit.cylinder((0.0, 0.0), 1.30, 1.38, 0.82, 8, "electric_glow"),
        kit.cylinder((0.0, 0.0), 1.70, 1.80, 0.62, 8, "science_white"),
        # The sensor mast and its dish.
        kit.cylinder((-0.70, 0.75), 0.98, 1.90, 0.04, 6, "steel"),
        kit.cone((-0.70, 0.75), 1.85, 1.95, 0.04, 0.20, 8, "galvanised"),
        kit.strip("+X", (1.30, -0.30, 0.65), 1.10, 0.06, "electric_glow"),
        kit.strip("+X", (1.30, -0.45, 0.45), 0.60, 0.06, "electric_glow"),
    ]
    volumes += kit.hatch("+X", (1.30, 0.75, 0.50), 0.55, 0.60, "steel")
    volumes += kit.rib_row("X", -0.80, 0.60, 3, 0.04, (0, 1.30, 0.30), (0, 1.33, 0.75), "steel", kit.model_random(machine, "vents"))
    kit.join(volumes, "body")
