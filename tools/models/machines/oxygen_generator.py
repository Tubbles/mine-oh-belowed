"""The pod's oxygen generator (work item 0198): 1 by 2 by 3 cells. A
galvanised cabinet with a fan grille and a cyan strip that glows while
the generator supplies a sealed room, a teal water tank beside it with a
valve wheel as the scale cue, and a pipe from the tank's top over to the
cabinet. No moving part. Blender frame of kit.py: x the front, y = -game
z, z up."""

from .. import kit


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 2, 3)
    volumes = [
        kit.box((-0.48, -0.98, 0.0), (0.48, 0.98, 0.10), "steel_dark"),
        # The primary volumes: the cabinet and the water tank.
        kit.box((-0.45, -0.95, 0.10), (0.35, 0.10, 2.6), "galvanised", bevel=0.03),
        kit.cylinder((-0.05, 0.52), 0.10, 2.40, 0.38, 10, "fluids_teal"),
        kit.cone((-0.05, 0.52), 2.40, 2.55, 0.38, 0.12, 10, "galvanised"),
        kit.pipe([(-0.05, 0.52, 2.50), (-0.05, 0.52, 2.80), (-0.05, -0.30, 2.80)], 0.06, "fluids_teal"),
        kit.cylinder((-0.05, -0.30), 2.6, 2.8, 0.06, 8, "fluids_teal"),
        kit.strip("+X", (0.35, -0.42, 1.9), 0.5, 0.06, "electric_glow"),
        # The fan grille and its bars.
        kit.ring((0.36, -0.42, 1.2), 0.25, 0.03, "steel_dark", axis="X", sides=8, minor_sides=3),
        *kit.rib_row("Z", 0.98, 1.42, 3, 0.03, (0.35, -0.62, 0.0), (0.37, -0.22, 0.0), "steel_dark", kit.model_random(machine, "grille")),
        # Scale cue: the valve wheel on its stem.
        kit.cylinder((0.52, 1.0), 0.33, 0.40, 0.03, 6, "galvanised", axis="X"),
        kit.ring((0.40, 0.52, 1.0), 0.14, 0.025, "galvanised", axis="X", sides=8, minor_sides=3),
    ]
    kit.join(volumes, "body")
