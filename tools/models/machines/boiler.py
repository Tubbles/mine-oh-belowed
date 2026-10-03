"""The boiler (work item 0205): 3 by 2 by 2 cells. A yellow drum lying
along x on a steel firebox at the front, the firebox's mouth glowing on
the front face while it burns, a chimney rising from the drum near the
centre (smoke leaves at the footprint's centre at the model's top), the
teal water inlet and the galvanised steam outlet at the ports, and a
hatch on the firebox's side as the scale cue. No moving part (its motion
is glow). Blender frame of kit.py: x the front, y = -game z, z up."""

from .. import kit, records


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 3, 2, 2)
    (inlet_x, _, inlet_z), _ = records.port_face(machine, records.port(machine, "input_water"))
    (outlet_x, _, outlet_z), _ = records.port_face(machine, records.port(machine, "output_steam"))
    firebox = kit.box((0.40, -0.80, 0.10), (1.40, 0.80, 1.10), "steel", bevel=0.04)
    kit.opening(firebox, (1.30, -0.30, 0.25), (1.45, 0.30, 0.60))
    volumes = [
        kit.box((-1.45, -0.95, 0.0), (1.45, 0.95, 0.10), "steel_dark"),
        firebox,
        kit.box((1.28, -0.30, 0.25), (1.31, 0.30, 0.60), "soot"),
        kit.box((1.28, -0.26, 0.25), (1.36, 0.26, 0.31), "heat_glow"),
        # The primary volume: the drum and its band.
        kit.cylinder((0.0, 0.75), -1.40, 0.40, 0.62, 10, "power_yellow", axis="X"),
        kit.cylinder((0.0, 0.75), -0.98, -0.92, 0.65, 10, "steel_dark", axis="X"),
        # The chimney, the highest point.
        kit.cylinder((0.20, 0.0), 1.20, 2.40, 0.12, 8, "steel_dark"),
        kit.cylinder((0.20, 0.0), 2.32, 2.40, 0.16, 8, "steel"),
        # The ports.
        kit.cylinder((inlet_x, inlet_z), 0.55, 1.00, 0.12, 8, "fluids_teal", axis="Y"),
        kit.cylinder((outlet_x, outlet_z), -1.00, -0.55, 0.12, 8, "galvanised", axis="Y"),
    ]
    volumes += kit.hatch("+Y", (0.90, 0.80, 0.55), 0.50, 0.60, "steel_dark")
    kit.join(volumes, "body")
