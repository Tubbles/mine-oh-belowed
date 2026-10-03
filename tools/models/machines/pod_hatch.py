"""A hatch of the pod (work item 0198): 1 by 2 by 4 cells, its front
(+x) facing out of the wall. Two jambs, a sill, guide rails and cyan
strips that glow while the hatch is open; the part is the door panel,
which slides up into the pod's wall (the record's slide motion, no
pivot). Nothing of the body stands above the footprint or in the
panel's path. Blender frame of kit.py: x the front, y = -game z, z up."""

from .. import kit


def build_body():
    volumes = [
        kit.box((-0.5, -1.0, 0.0), (0.5, -0.88, 4.0), "steel_dark"),
        kit.box((-0.5, 0.88, 0.0), (0.5, 1.0, 4.0), "steel_dark"),
        kit.box((-0.5, -0.88, 0.0), (0.5, 0.88, 0.06), "hazard_black"),
    ]
    # The guide rails either side of the panel on both jambs.
    for y_low, y_high in ((-0.90, -0.86), (0.86, 0.90)):
        volumes.append(kit.box((-0.10, y_low, 0.06), (-0.07, y_high, 3.96), "galvanised"))
        volumes.append(kit.box((0.07, y_low, 0.06), (0.10, y_high, 3.96), "galvanised"))
    volumes += [
        kit.strip("+X", (0.5, -0.94, 2.4), 0.08, 0.6, "electric_glow"),
        kit.strip("-X", (-0.5, 0.94, 2.4), 0.08, 0.6, "electric_glow"),
    ]
    kit.join(volumes, "body")


def build_part(machine):
    volumes = [
        # The primary volume: the door panel.
        kit.box((-0.06, -0.86, 0.06), (0.06, 0.86, 3.96), "steel", bevel=0.01),
        kit.box((-0.065, -0.25, 2.6), (0.065, 0.25, 3.2), "soot"),
        kit.box((0.06, -0.55, 1.7), (0.10, -0.47, 2.3), "galvanised"),
        kit.box((-0.10, 0.47, 1.7), (-0.06, 0.55, 2.3), "galvanised"),
        kit.box((-0.065, -0.86, 0.06), (0.065, 0.86, 0.30), "power_yellow"),
    ]
    kit.join_part(volumes, machine)


def build(machine):
    """machine: its record (tools/models/records.py)."""
    kit.expect_footprint(machine, 1, 2, 4)
    build_body()
    build_part(machine)
