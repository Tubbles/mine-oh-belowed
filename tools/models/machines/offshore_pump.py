"""The offshore pump (work item 0205): 2 by 1 by 1 cells. A teal pump
drum at the back over the output port, an intake pipe forward and down
to a strainer at the front (+x, the water side), a valve wheel on the
intake as the scale cue. The part is the motor on its cradle, bobbing
along y (no pivot). The intake ends at the footprint's bottom, since the
loader refuses geometry below it, although the water may stand a cell
lower. Blender frame of kit.py: x the front, y = -game z, z up."""

from .. import kit, records


def build_body(machine):
    (_, outlet_y, outlet_z), _ = records.port_face(machine, records.port(machine, "output_water"))
    volumes = [
        kit.box((-1.00, -0.45, 0.0), (0.30, 0.45, 0.08), "steel_dark"),
        # The primary volume: the drum, its outlet at the port.
        kit.cylinder((0.0, 0.38), -0.95, -0.15, 0.28, 10, "fluids_teal", axis="X"),
        kit.cylinder((outlet_y, outlet_z), -1.00, -0.95, 0.12, 8, "galvanised", axis="X"),
        # The intake and its strainer.
        kit.pipe([(-0.15, 0.0, 0.38), (0.70, 0.0, 0.38), (0.70, 0.0, 0.04)], 0.09, "fluids_teal"),
        kit.cylinder((0.70, 0.0), 0.0, 0.16, 0.16, 8, "fluids_teal"),
        # The motor's cradle: a saddle and two cheeks.
        kit.box((-0.80, -0.12, 0.64), (-0.40, 0.12, 0.68), "steel_dark"),
        kit.box((-0.66, 0.17, 0.64), (-0.54, 0.21, 0.86), "steel"),
        kit.box((-0.66, -0.21, 0.64), (-0.54, -0.17, 0.86), "steel"),
        # Scale cue: the valve wheel on its stem.
        kit.cylinder((0.30, 0.0), 0.47, 0.62, 0.03, 6, "galvanised"),
        kit.ring((0.30, 0.0, 0.62), 0.24, 0.03, "galvanised", sides=8, minor_sides=3),
    ]
    kit.join(volumes, "body")


def build_part(machine):
    volumes = [
        kit.cylinder((0.0, 0.88), -0.80, -0.40, 0.12, 10, "steel_dark", axis="X"),
        kit.cylinder((0.0, 0.88), -0.86, -0.80, 0.10, 8, "galvanised", axis="X"),
    ]
    volumes += kit.rib_row("X", -0.75, -0.45, 3, 0.03, (0, -0.15, 0.80), (0, 0.15, 1.02), "steel", kit.model_random(machine, "motor_fins"))
    kit.join_part(volumes, machine)


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 2, 1, 1)
    build_body(machine)
    build_part(machine)
