"""The wood gasifier (work item 0205): 2 by 2 by 3 cells, a crafting
machine that keeps the fluids accent of its product. A tall steel
reactor drum with two bands on a skid, a fuel hopper on top with a hatch
as the scale cue, a fire door glowing on the front while it works, and
the teal gas pipe leaving the drum's side down to the port. No moving
part (its motion is glow). Blender frame of kit.py: x the front,
y = -game z, z up."""

import math

from .. import kit, records


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 2, 2, 3)
    (port_x, port_y, port_z), _ = records.port_face(machine, records.port(machine, "output_wood_gas"))
    volumes = [
        kit.box((-0.95, -0.95, 0.0), (0.95, 0.95, 0.10), "steel_dark"),
        # The primary volume: the reactor drum and its bands.
        kit.cylinder((0.0, 0.0), 0.10, 2.20, 0.72, 10, "steel"),
        kit.cylinder((0.0, 0.0), 0.62, 0.70, 0.75, 10, "steel_dark"),
        kit.cylinder((0.0, 0.0), 1.70, 1.80, 0.75, 10, "steel_dark"),
        # The fire door and its glow.
        kit.box((0.55, -0.28, 0.22), (0.82, 0.28, 0.66), "steel_dark"),
        kit.box((0.82, -0.20, 0.30), (0.84, 0.20, 0.40), "heat_glow"),
        kit.cone((0.0, 0.0), 2.20, 2.70, 0.30, 0.55, 4, "galvanised", rotation=math.pi / 4),
        # The gas pipe from the drum's side down to the port.
        kit.pipe([(port_x, -0.45, 1.50), (port_x, -0.80, 1.50), (port_x, -0.80, port_z)], 0.10, "fluids_teal"),
        kit.cylinder((port_x, port_z), port_y, -0.80, 0.13, 8, "fluids_teal", axis="Y"),
    ]
    volumes += kit.hatch("+Z", (0.0, 0.0, 2.70), 0.50, 0.50, "steel_dark")
    kit.join(volumes, "body")
