"""The schematic crate (work item 0205): 1 by 1 by 1 cells. A timber
crate in a steel frame with uneven battens on its sides, a latch and a
cyan readout that lights brighter while it holds a schematic. No moving
part. Blender frame of kit.py: x the front, y = -game z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 1, 1)
    volumes = [
        # The primary volume: the crate in its two frames.
        kit.box((-0.42, -0.42, 0.0), (0.42, 0.42, 0.70), "timber", bevel=0.02),
        kit.box((-0.44, -0.44, 0.0), (0.44, 0.44, 0.06), "steel_dark"),
        kit.box((-0.44, -0.44, 0.64), (0.44, 0.44, 0.72), "steel_dark"),
        kit.box((0.45, -0.05, 0.30), (0.49, 0.05, 0.46), "galvanised"),
        kit.strip("+Y", (0.0, 0.42, 0.40), 0.30, 0.05, "electric_glow"),
    ]
    # Battens: two on the front, clear of the latch, three on the back.
    volumes += kit.rib_row("Y", -0.32, 0.32, 2, 0.06, (0.42, 0, 0.06), (0.45, 0, 0.64), "timber_dark", kit.model_random(machine, "front_battens"))
    volumes += kit.rib_row("Y", -0.32, 0.32, 3, 0.06, (-0.45, 0, 0.06), (-0.42, 0, 0.64), "timber_dark", kit.model_random(machine, "back_battens"))
    kit.join(volumes, "body")
