"""The pump (work item 0205): 2 by 1 by 1 cells. An inline teal pipe
between flanges at both ports, a volute drum across it, the motor's
cradle above and a valve wheel on the inlet side as the scale cue. The
part is the motor with its end cap and terminal box, bobbing along y (no
pivot). Blender frame of kit.py: x the front, y = -game z, z up."""

from .. import kit, records


def build_body(machine):
    (_, inlet_y, inlet_z), _ = records.port_face(machine, records.port(machine, "input"))
    (_, outlet_y, outlet_z), _ = records.port_face(machine, records.port(machine, "output"))
    volumes = [
        kit.box((-0.90, -0.40, 0.0), (0.90, 0.40, 0.08), "steel_dark"),
        kit.box((-0.67, -0.18, 0.08), (-0.57, 0.18, 0.38), "steel_dark"),
        kit.box((0.50, -0.18, 0.08), (0.60, 0.18, 0.38), "steel_dark"),
        # The primary volumes: the pipe, its flanges at the ports, the
        # volute across it.
        kit.cylinder((0.0, 0.50), -0.98, 0.98, 0.16, 10, "fluids_teal", axis="X"),
        kit.cylinder((outlet_y, outlet_z), 0.92, 1.00, 0.22, 8, "steel", axis="X"),
        kit.cylinder((inlet_y, inlet_z), -1.00, -0.92, 0.22, 8, "steel", axis="X"),
        kit.cylinder((-0.05, 0.50), -0.22, 0.22, 0.30, 10, "fluids_teal", axis="Y"),
        # The motor's cheeks.
        kit.box((0.00, 0.16, 0.74), (0.30, 0.20, 0.98), "steel"),
        kit.box((0.00, -0.20, 0.74), (0.30, -0.16, 0.98), "steel"),
        # Scale cue: the valve wheel on its stem.
        kit.cylinder((-0.60, 0.0), 0.66, 0.86, 0.03, 6, "galvanised"),
        kit.ring((-0.60, 0.0, 0.86), 0.26, 0.03, "galvanised", sides=8, minor_sides=3),
    ]
    kit.join(volumes, "body")


def build_part(machine):
    volumes = [
        kit.cylinder((0.0, 1.00), -0.15, 0.45, 0.13, 10, "steel_dark", axis="X"),
        kit.cylinder((0.0, 1.00), 0.45, 0.52, 0.09, 8, "galvanised", axis="X"),
        kit.box((0.05, -0.06, 1.10), (0.20, 0.06, 1.20), "power_yellow"),
    ]
    kit.join_part(volumes, machine)


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 2, 1, 1)
    build_body(machine)
    build_part(machine)
