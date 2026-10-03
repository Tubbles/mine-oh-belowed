"""The lamp (work item 0205): 1 by 1 by 1 cells. A short post with a
glowing head under a conical cap. No moving part. Blender frame of
kit.py: x the front, y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 1, 1)
    volumes = [
        kit.box((-0.18, -0.18, 0.0), (0.18, 0.18, 0.04), "steel_dark"),
        kit.cylinder((0.0, 0.0), 0.04, 0.55, 0.04, 6, "steel"),
        # The primary volume: the head and its cap.
        kit.cylinder((0.0, 0.0), 0.55, 0.78, 0.14, 8, "lamp_glow"),
        kit.cone((0.0, 0.0), 0.78, 0.88, 0.20, 0.08, 8, "steel_dark"),
    ]
    kit.join(volumes, "body")
