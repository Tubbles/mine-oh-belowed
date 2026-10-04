"""The airlock door of the pod (work items 0198, 0221), one per end of
the drum. The body is the frame: a back plate and a thick front
collar, both 1 m square with the 0.8 m bore, a raised ring and bolts
on each face, status strips, and between the plates a slot open at the
top. The part is the shutter: a dark disc with iris blades in relief
on both faces, which slides straight up out of the slot (the record's
slide along y, up) into the pocket the pod leaves above each door. The
blades are tilted so the flat shading tells them apart.

Frame: x -0.5 to 0.5 along the drum (+X out of the pod), y -1 to 1
across, z 0 to 2; the bore's axis at y 0, z 1."""

import math

from mathutils import Vector

from .. import kit
from . import pod_geometry as geometry

BORE = 0.8
RING_OUTER = 0.97
BACK = (-0.5, -0.3)
FRONT = (0.06, 0.5)
RING_DEPTH = 0.06
SHUTTER = (-0.2, -0.05)
SHUTTER_RADIUS = 0.95
SHUTTER_SIDES = 12
BLADES = 8
CENTRE_Z = 1.0


def plate(minimum, maximum):
    """One plate as an object of its own, so the bore is cut from a single
    closed box (touching boxes in one mesh make the exact boolean fail)."""
    builder = geometry.Builder()
    builder.abox(minimum, maximum, "pod_dark")
    return builder.objects()[0]


def spacers(builder):
    """The slot's side and bottom spacers between the plates."""
    for side in (-1, 1):
        builder.abox((BACK[1], side * 0.96 if side > 0 else -1.0, 0), (FRONT[0], 1.0 if side > 0 else -0.96, 2), "pod_dark")
    builder.abox((BACK[1], -0.96, 0), (FRONT[0], 0.96, 0.04), "pod_dark")


def rings_and_bolts(builder):
    centre_back = Vector((BACK[0] + RING_DEPTH, 0, CENTRE_Z))
    centre_front = Vector((FRONT[1] - RING_DEPTH, 0, CENTRE_Z))
    builder.washer(centre_back, (-1, 0, 0), BORE, RING_OUTER, RING_DEPTH, 16, "pod_orange", phase=math.pi / 16)
    builder.washer(centre_front, (1, 0, 0), BORE, RING_OUTER, RING_DEPTH, 16, "pod_orange", phase=math.pi / 16)
    # Bolts in the plates' corners and a bolt circle just outside each ring.
    for centre, normal in ((centre_back, Vector((-1, 0, 0))), (centre_front, Vector((1, 0, 0)))):
        for corner_y in (-0.8, 0.8):
            for corner_z in (0.1, 1.9):
                builder.rivet((centre.x, corner_y, corner_z), normal, 0.045, "pod_metal")
        for index in range(12):
            angle = 2 * math.pi * (index + 0.5) / 12
            y, z = 1.04 * math.cos(angle), CENTRE_Z + 1.04 * math.sin(angle)
            if abs(y) < 0.97 and 0.03 < z < 1.97:
                builder.rivet((centre.x, y, z), normal, 0.03, "pod_metal")


def status_lights(builder):
    """Green strips at the lower corners and amber at the upper ones, set
    into both faces."""
    for x0, x1 in ((BACK[0] + RING_DEPTH - 0.01, BACK[0] + RING_DEPTH + 0.004), (FRONT[1] - RING_DEPTH - 0.004, FRONT[1] - RING_DEPTH + 0.01)):
        for side in (-1, 1):
            builder.abox((x0, side * 0.93 - 0.03, 0.12), (x1, side * 0.93 + 0.03, 0.42), "pod_glow_green")
            builder.abox((x0, side * 0.93 - 0.03, 1.58), (x1, side * 0.93 + 0.03, 1.88), "pod_glow_amber")


def bore_cutter(builder):
    builder.cylinder((-0.6, 0, CENTRE_Z), (0.6, 0, CENTRE_Z), BORE, 16, "pod_black", phase=math.pi / 16)


def shutter(builder):
    """The disc and its tilted iris blades on both faces."""
    builder.cylinder((SHUTTER[0], 0, CENTRE_Z), (SHUTTER[1], 0, CENTRE_Z), SHUTTER_RADIUS, SHUTTER_SIDES, "pod_dark", phase=-math.pi / 2)
    for face_x, outward in ((SHUTTER[0], -1.0), (SHUTTER[1], 1.0)):
        for index in range(BLADES):
            start = 2 * math.pi * index / BLADES * outward
            corners = ((0.1, start), (0.86, start + 0.25 * outward), (0.86, start + 1.0 * outward))
            rises = (0.004, 0.006, 0.016)
            base = [Vector((face_x, radius * math.cos(angle), CENTRE_Z + radius * math.sin(angle))) for radius, angle in corners]
            top = [point + Vector((outward * rise, 0, 0)) for point, rise in zip(base, rises)]
            builder.closed("pod_metal", [*base, *top], ((0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)))


def build(machine):
    kit.expect_footprint(machine, 1, 2, 2)
    plates = [plate((BACK[0] + RING_DEPTH, -1, 0), (BACK[1], 1, 2)), plate((FRONT[0], -1, 0), (FRONT[1] - RING_DEPTH, 1, 2))]
    hole = geometry.cutter(bore_cutter)
    for item in plates:
        kit.cut(item, hole)
    details = geometry.Builder()
    spacers(details)
    rings_and_bolts(details)
    status_lights(details)
    body = kit.join([*plates, *details.objects()], "body")
    geometry.print_emissive(body, merge=0.2)
    part = geometry.Builder()
    shutter(part)
    kit.join_part(part.objects(), machine)
