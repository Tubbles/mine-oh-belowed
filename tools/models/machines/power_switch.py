"""The power switch (work item 0205): 1 by 1 by 1 cells. A yellow switch
box on a stand, a black lever on its front and a cyan state strip; the
box contains the wire's anchor at the footprint's middle
(render_power.odin). No moving part. Blender frame of kit.py: x the
front, y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 1, 1)
    volumes = [
        kit.box((-0.25, -0.25, 0.0), (0.25, 0.25, 0.04), "hazard_black"),
        kit.box((-0.06, -0.06, 0.04), (0.06, 0.06, 0.25), "steel"),
        # The primary volume: the switch box.
        kit.box((-0.20, -0.22, 0.25), (0.16, 0.22, 0.75), "power_yellow", bevel=0.02),
        kit.cylinder((0.08, 0.55), 0.16, 0.22, 0.05, 8, "galvanised", axis="X"),
        kit.box((0.20, 0.06, 0.55), (0.24, 0.10, 0.72), "hazard_black"),
        kit.strip("+X", (0.16, -0.10, 0.62), 0.08, 0.05, "electric_glow"),
    ]
    kit.join(volumes, "body")
