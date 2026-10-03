"""The pod's locker (work item 0198): 1 by 2 by 4 cells, a chest built
into the cabin's wall. A grey cabinet with two doors, yellow front
edges and vents at uneven offsets. No moving part. Blender frame of
kit.py: x the front, y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 2, 4)
    volumes = [
        kit.box((-0.48, -0.98, 0.0), (0.42, 0.98, 0.12), "steel_dark"),
        # The primary volume: the cabinet.
        kit.box((-0.45, -0.95, 0.12), (0.40, 0.95, 3.9), "logistics_grey", bevel=0.03),
        *kit.hatch("+X", (0.40, -0.47, 2.0), 0.86, 3.4, "steel"),
        *kit.hatch("+X", (0.40, 0.47, 2.0), 0.86, 3.4, "steel"),
        kit.box((0.36, -0.97, 0.12), (0.42, -0.91, 3.88), "power_yellow"),
        kit.box((0.36, 0.91, 0.12), (0.42, 0.97, 3.88), "power_yellow"),
        *kit.rib_row("Z", 3.0, 3.6, 3, 0.04, (0.43, -0.80, 0.0), (0.45, -0.20, 0.0), "steel_dark", kit.model_random(machine, "left_vents")),
        *kit.rib_row("Z", 3.0, 3.6, 2, 0.04, (0.43, 0.20, 0.0), (0.45, 0.80, 0.0), "steel_dark", kit.model_random(machine, "right_vents")),
    ]
    kit.join(volumes, "body")
