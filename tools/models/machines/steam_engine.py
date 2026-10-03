"""The steam engine (work item 0205): 3 by 5 by 2 cells. A long yellow
cylinder lying along the depth on a bed, a crosshead guide towards the
-y end with the cyan strip that lights while it generates, a pedestal
carrying the shaft forward to the flywheel on the front, a steam chest
on top fed by a pipe from the -y port, and a valve wheel on the chest as
the scale cue. The part is the flywheel (rim, spokes, hub, shaft and
crank pin), spinning about X through the record's pivot. Blender frame
of kit.py: x the front, y = -game z, z up."""

from .. import kit, records


def build_body(machine):
    (stub_x, _, stub_z), _ = records.port_face(machine, records.port(machine, "input_steam"))
    (pipe_x, pipe_y, pipe_z), _ = records.port_face(machine, records.port(machine, "input_steam_2"))
    volumes = [
        # The bed ends at x 0.70, so the wheel turns clear of it.
        kit.box((-1.40, -2.40, 0.0), (0.70, 2.40, 0.14), "steel_dark"),
        kit.box((-0.50, 0.20, 0.14), (0.30, 0.30, 0.40), "steel_dark"),
        kit.box((-0.50, 1.65, 0.14), (0.30, 1.75, 0.40), "steel_dark"),
        # The primary volume: the cylinder and its heads.
        kit.cylinder((-0.10, 0.78), -0.30, 2.30, 0.48, 10, "power_yellow", axis="Y"),
        kit.cylinder((-0.10, 0.78), 2.22, 2.36, 0.54, 10, "steel_dark", axis="Y"),
        kit.cylinder((-0.10, 0.78), -0.36, -0.22, 0.54, 10, "steel_dark", axis="Y"),
        # The crosshead guide, its strip, and the shaft's pedestal.
        kit.box((-0.50, -1.10, 0.55), (0.30, -0.30, 1.00), "steel"),
        kit.strip("+X", (0.30, -0.70, 0.80), 0.40, 0.05, "electric_glow"),
        kit.box((0.36, -1.41, 0.14), (0.60, -1.09, 1.16), "steel_dark"),
        # The steam chest, its inlet stub and the pipe from the far port:
        # a short run in from the face, then up, its rising run's outside
        # inside the footprint.
        kit.box((-0.25, 0.20, 1.22), (0.25, 1.90, 1.42), "galvanised"),
        kit.cylinder((stub_x, stub_z), 2.36, 2.50, 0.12, 8, "galvanised", axis="Y"),
        kit.pipe([(pipe_x, pipe_y + 0.01, pipe_z), (pipe_x, pipe_y + 0.20, pipe_z), (pipe_x, pipe_y + 0.20, 1.40), (pipe_x, 0.25, 1.40)], 0.08, "galvanised"),
        # Scale cue: the valve wheel on its stem.
        kit.cylinder((0.0, 1.20), 1.42, 1.62, 0.03, 6, "galvanised"),
        kit.ring((0.0, 1.20, 1.62), 0.28, 0.03, "galvanised", sides=8, minor_sides=3),
    ]
    kit.join(volumes, "body")


def build_part(machine):
    pivot = records.pivot(machine)
    _, pivot_y, pivot_z = pivot
    volumes = [
        kit.ring(pivot, 0.86, 0.04, "steel_dark", axis="X", sides=12, minor_sides=3),
        kit.box((0.84, pivot_y - 0.84, pivot_z - 0.05), (0.91, pivot_y + 0.84, pivot_z + 0.05), "steel"),
        kit.box((0.84, pivot_y - 0.05, pivot_z - 0.84), (0.91, pivot_y + 0.05, pivot_z + 0.84), "steel"),
        kit.cylinder((pivot_y, pivot_z), 0.80, 0.96, 0.14, 8, "steel_dark", axis="X"),
        kit.cylinder((pivot_y, pivot_z), 0.62, 0.80, 0.07, 8, "steel", axis="X"),
        kit.box((0.91, pivot_y + 0.39, pivot_z - 0.06), (1.00, pivot_y + 0.51, pivot_z + 0.06), "galvanised"),
    ]
    kit.join_part(volumes, machine, pivot)


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 3, 5, 2)
    build_body(machine)
    build_part(machine)
