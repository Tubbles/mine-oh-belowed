"""The small pole (work item 0205): 1 by 1 by 3 cells, a power pole. A
timber post on a black foot plate with a yellow band, a meter box (the
scale cue, 0.3 m), a short crossarm and the insulator on the axis where
the wire meets it (WIRE_DROP below the top, render_power.odin). No
moving part. Blender frame of kit.py: x the front, y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 1, 3)
    volumes = [
        kit.box((-0.20, -0.20, 0.0), (0.20, 0.20, 0.05), "hazard_black"),
        # The primary volume: the post.
        kit.cylinder((0.0, 0.0), 0.05, 2.80, 0.09, 8, "timber"),
        kit.cylinder((0.0, 0.0), 0.30, 0.46, 0.10, 8, "power_yellow"),
        kit.box((0.09, -0.12, 0.90), (0.20, 0.12, 1.50), "power_yellow"),
        kit.box((-0.05, -0.22, 2.60), (0.05, 0.22, 2.68), "timber_dark"),
        kit.cylinder((0.0, 0.0), 2.80, 2.92, 0.05, 6, "galvanised"),
    ]
    kit.join(volumes, "body")
