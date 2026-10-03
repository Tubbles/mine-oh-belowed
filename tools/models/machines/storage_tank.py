"""The storage tank (work item 0205): 3 by 3 by 3 cells, a port on every
face. A teal vertical drum on a plinth under a conical roof, one dark
band, a manway on the roof, two nozzles and a ladder on the front as the
scale cue. No moving part. Blender frame of kit.py: x the front,
y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 3, 3, 3)
    volumes = [
        kit.box((-1.45, -1.45, 0.0), (1.45, 1.45, 0.12), "steel_dark"),
        # The primary volume: the drum and its roof.
        kit.cylinder((0.0, 0.0), 0.12, 2.30, 1.30, 12, "fluids_teal"),
        kit.cone((0.0, 0.0), 2.30, 2.75, 1.30, 0.40, 12, "steel"),
        kit.cylinder((0.0, 0.0), 0.70, 0.80, 1.33, 12, "steel_dark"),
        kit.cylinder((0.15, -0.10), 2.70, 2.85, 0.25, 8, "steel_dark"),
        # Scale cue: the ladder's rails.
        kit.box((1.32, 0.18, 0.12), (1.38, 0.22, 2.40), "galvanised"),
        kit.box((1.32, -0.22, 0.12), (1.38, -0.18, 2.40), "galvanised"),
        # The nozzles.
        kit.cylinder((-0.30, 0.45), 1.25, 1.50, 0.14, 8, "steel", axis="Y"),
        kit.cylinder((0.0, 0.45), -1.50, -1.25, 0.14, 8, "steel", axis="X"),
    ]
    volumes += kit.rib_row("Z", 0.30, 2.30, 4, 0.04, (1.32, -0.20, 0), (1.38, 0.20, 0), "galvanised", kit.model_random(machine, "ladder"))
    kit.join(volumes, "body")
