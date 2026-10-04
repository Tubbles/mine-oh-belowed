"""The landing pod (work items 0179, 0198, 0221): a squat riveted
re-entry cone, floor first in its crater, and the one person cabin
inside it.

Frame (cells of 0.5 m, Blender): +X the front with the airlock, z up,
the cabin floor at z 0.06. The hull is a 24 sided solid of revolution:
outside a skirt of radius 5 to z 2.2 leaning in to radius 2.41 at z 6.8;
inside a lining of radius 4.6 to z 2.4 leaning in parallel to the
ceiling at z 6.2. Facet centres sit at multiples of 15 degrees, so the
wall frames (wall()) are flat there.

Floor plan, the chair facing +Y with the airlock on its right:
- the chair in x -3..-1, y -2..0;
- free floor x -3..1, y 0..2 (before the seat and on to the door) and
  x -1..1, y -2..0 (before the door and the locker), 4 cells high;
- the airlock: inner door cells x 1..2, bore x 2..4, outer door x 4..5,
  exit x 5..6, all y -1..1, z 0..2; the shutters slide up into slots
  above each door (x 1.26..1.49 and 4.26..4.49, z 2..3.92);
- pockets: locker x -1..1, y -3..-2, z 0..4; bench x -4..-3, y 0..2,
  z 0..2; oxygen generator x 0..2, y 2..3, z 0..3;
- the bed on the lean wall at 330 degrees, over the airlock housing.
"""

import math

import bpy
from mathutils import Vector

from .. import kit
from . import pod_geometry as geometry
from .pod_geometry import Frame, X, Y, Z

SEGMENTS = 24
PHASE = math.pi / SEGMENTS
FACET = math.cos(math.pi / SEGMENTS)
FLOOR = 0.006
INNER_RADIUS = 4.6
INNER_KNEE = 2.4
CEILING = 6.2
OUTER_RADIUS = 5.0
OUTER_KNEE = 2.2
OUTER_TOP = 6.8
SLOPE = 0.5625

ORANGE = "pod_orange"
DARK = "pod_dark"
METAL = "pod_metal"
PADDING = "pod_padding"
BLACK = "pod_black"
GREEN = "pod_glow_green"
AMBER = "pod_glow_amber"
WHITE = "pod_glow_white"

POCKETS = {
    "locker pocket": ((-1, -3, 0), (1, -2, 4)),
    "bench pocket": ((-4, 0, 0), (-3, 2, 2)),
    "oxygen pocket": ((0, 2, 0), (2, 3, 3)),
}
OPEN_CELLS = {
    "free floor and lane": ((-3, 0, 0), (1, 2, 4)),
    "door front": ((-1, -2, 0), (1, 0, 4)),
    "airlock bore": ((1, -1, 0), (6, 1, 2)),
}
CHAIR_CELLS = ((-3, -2, 0), (-1, 0, 3.7))
# The housing's cabin face stands back from the door cells so its gauges
# and pistons stay out of the cells before the door; the bore is round,
# just wide enough to leave the 2 by 2 cells empty.
HOUSING_FACE = 1.12
HOUSING_TOP = 2.75
BORE_RADIUS = 1.44
INNER_SLOT = ((1.26, -0.98, 1.9), (1.49, 0.98, 4.02))
OUTER_SLOT = ((4.26, -0.98, 1.9), (4.49, 0.98, 4.02))
PORTHOLES = ((30, 3.7), (75, 3.75), (120, 3.7), (195, 3.7), (240, 3.75))
PORTHOLE_RADIUS = 0.42


def inner_radius(z):
    return INNER_RADIUS if z <= INNER_KNEE else INNER_RADIUS - (z - INNER_KNEE) * SLOPE


def outer_radius(z):
    return OUTER_RADIUS if z <= OUTER_KNEE else OUTER_RADIUS - (z - OUTER_KNEE) * SLOPE


def radial(theta):
    angle = math.radians(theta)
    return Vector((math.cos(angle), math.sin(angle), 0)), Vector((-math.sin(angle), math.cos(angle), 0))


def wall(theta, z, lean=None, facet=True):
    """The lining at angle theta (degrees) and height z: u along the wall
    to the left seen from the cabin, v up the wall, w into the cabin."""
    out, tangent = radial(theta)
    leaning = z > INNER_KNEE if lean is None else lean
    origin = out * inner_radius(z) * (FACET if facet else 1.0) + Z * z
    if not leaning:
        return Frame(origin, tangent, Z.copy(), -out)
    up = (Z - out * SLOPE).normalized()
    return Frame(origin, tangent, up, -(out + Z * SLOPE).normalized())


def hull_wall(theta, z, facet=True):
    """The outer skin, w out of the hull."""
    out, tangent = radial(theta)
    origin = out * outer_radius(z) * (FACET if facet else 1.0) + Z * z
    if z <= OUTER_KNEE:
        return Frame(origin, -tangent, Z.copy(), out)
    up = (Z - out * SLOPE).normalized()
    return Frame(origin, -tangent, up, (out + Z * SLOPE).normalized())


def inside_hull(point):
    radius = math.hypot(point[0], point[1])
    return point[2] >= -0.01 and radius <= outer_radius(point[2]) * FACET + 0.02


def interior_builder():
    guards = [(name, low, high, None) for name, (low, high) in POCKETS.items()]
    guards += [(name, low, high, None) for name, (low, high) in OPEN_CELLS.items()]
    guards.append(("the chair's cells", *CHAIR_CELLS, FLOOR + 0.03))
    guards += [("inner shutter slot", *INNER_SLOT, None), ("outer shutter slot", *OUTER_SLOT, None)]
    return geometry.Builder(guards, inside_hull)


# The hull and the airlock's housing ------------------------------------------------


def hull_objects():
    profile = (
        (0, 0.0), (OUTER_RADIUS, 0.0), (OUTER_RADIUS, OUTER_KNEE), (outer_radius(OUTER_TOP), OUTER_TOP), (0, OUTER_TOP),
        (0, CEILING), (inner_radius(CEILING), CEILING), (INNER_RADIUS, INNER_KNEE), (INNER_RADIUS, FLOOR), (0, FLOOR),
    )
    hull = geometry.revolve(profile, SEGMENTS, PHASE, METAL, inner_material=BLACK)
    rim = geometry.revolve(((4.9, 0.0), (5.45, 0.0), (5.45, 0.2), (4.9, 0.5)), SEGMENTS, PHASE, BLACK)
    seam = geometry.revolve(((outer_radius(4.45) - 0.02, 4.45), (outer_radius(4.6) + 0.07, 4.6), (outer_radius(4.75) - 0.02, 4.75)), SEGMENTS, PHASE, DARK)
    shapes = geometry.Builder()
    shapes.prism(Frame(Vector((0, 0, 0)), X, Z, Y), ((3.9, 0.0), (5.0, 0.0), (5.0, 4.0), (4.55, 4.5), (3.9, 4.5)), (-1.8, 1.8), METAL)
    fairing = shapes.objects()[0]
    shapes = geometry.Builder()
    shapes.abox((HOUSING_FACE, -1.75, 0.0), (4.6, 1.75, HOUSING_TOP), DARK)
    housing = shapes.objects()[0]
    shapes = geometry.Builder()
    shapes.abox((HOUSING_FACE + 0.01, -1.25, HOUSING_TOP - 0.02), (1.8, 1.25, 4.3), DARK)
    tower = shapes.objects()[0]

    # Each overlapping object gets its own cutters, grown a step more than
    # the one in front of it (housing 0.012, fairing 0.024, hull 0.036), so
    # no two openings share a plane and none sits on the door frame's own
    # faces at y +-1, z 2: the visible lining is the housing's, the others
    # lie inside it.
    def grown(minimum, maximum, step):
        return tuple(value - step for value in minimum), tuple(value + step for value in maximum)

    def box_cutter(minimum, maximum, step):
        low, high = grown(minimum, maximum, step)
        return geometry.cutter(lambda b: b.abox(low, high, BLACK))

    def bore_cutter(step):
        # A grown bore also ends earlier, so its end ring at the outer door
        # lies inside the housing instead of on the housing's own ring.
        return geometry.cutter(lambda b: b.cylinder((1.9, 0, 1.0), (4.1 - step, 0, 1.0), BORE_RADIUS + step, 24, BLACK, phase=math.pi / 24))

    housing_step, fairing_step, hull_step = 0.012, 0.024, 0.036
    rim_gap = geometry.cutter(lambda b: b.abox((4.0, -1.05, -0.5), (6.3, 1.05, 1.0), BLACK))

    def portholes(builder):
        for theta, z in PORTHOLES:
            frame = wall(theta, z)
            builder.cylinder(geometry.at(frame, 0, 0, 0.3), geometry.at(frame, 0, 0, -1.0), PORTHOLE_RADIUS, 12, BLACK, phase=math.pi / 12)

    porthole_cutter = geometry.cutter(portholes)
    inner_door_box = ((0.99, -1.0, -0.5), (2.0, 1.0, 2.0))
    outer_door_box = ((4.0, -1.0, -0.5), (6.3, 1.0, 2.0))
    for target, cutters in (
        (hull, (box_cutter(*outer_door_box, hull_step), box_cutter(*OUTER_SLOT, hull_step), porthole_cutter)),
        (rim, (rim_gap,)),
        (fairing, (box_cutter(*outer_door_box, fairing_step), box_cutter(*OUTER_SLOT, fairing_step), bore_cutter(fairing_step))),
        (seam, (box_cutter(*outer_door_box, hull_step),)),
        (housing, (
            box_cutter(*inner_door_box, housing_step), box_cutter(*outer_door_box, housing_step), bore_cutter(0.0),
            box_cutter(*INNER_SLOT, housing_step), box_cutter(*OUTER_SLOT, housing_step),
        )),
        (tower, (box_cutter(*INNER_SLOT, fairing_step),)),
    ):
        for item in cutters:
            kit.cut(target, item)
    return [hull, rim, fairing, housing, tower, seam]


# Small furniture on a wall frame -----------------------------------------------------
#
# Every panel has its front edges chamfered (slab), every free piece all
# its face edges (block, bar), screens sit recessed in a bezel, keys
# stand as tapered caps in a well with a gap round each, knobs and
# collars are turned (lathe).


HELPER_TRIANGLES = {}


def tallied(function):
    """Counts the triangles each furniture helper adds (outermost call)."""
    def wrapper(b, *arguments, **keywords):
        before = sum(b.triangles.values())
        depth = getattr(b, "helper_depth", 0)
        b.helper_depth = depth + 1
        if depth == 0:
            b.label = function.__name__
        try:
            return function(b, *arguments, **keywords)
        finally:
            b.helper_depth = depth
            if depth == 0:
                b.label = ""
                HELPER_TRIANGLES[function.__name__] = HELPER_TRIANGLES.get(function.__name__, 0) + sum(b.triangles.values()) - before
    return wrapper


@tallied
def slab(b, frame, u0, u1, v0, v1, w0, w1, material, chamfer=0.03, front=None):
    """A panel on the frame's surface from w0 to w1, its front edges
    chamfered, the back left open: 18 triangles."""
    half_u, half_v = (u1 - u0) / 2, (v1 - v0) / 2
    c = min(chamfer, half_u * 0.45, half_v * 0.45, (w1 - w0) * 0.6)
    b.sweep_rect(frame, (u0 + u1) / 2, (v0 + v1) / 2, half_u, half_v, ((0.0, w0), (0.0, w1 - c), (-c, w1)), material, cap=front or material)


@tallied
def block(b, frame, u0, u1, v0, v1, w0, w1, material, chamfer=0.03):
    """A free standing box with the edges of both faces chamfered: 28."""
    half_u, half_v = (u1 - u0) / 2, (v1 - v0) / 2
    c = min(chamfer, half_u * 0.45, half_v * 0.45, (w1 - w0) * 0.3)
    b.sweep_rect(frame, (u0 + u1) / 2, (v0 + v1) / 2, half_u, half_v, ((-c, w0), (0.0, w0 + c), (0.0, w1 - c), (-c, w1)), material, cap=material, cap_start=material)


@tallied
def bar(b, start, end, width, height, material, up=None, chamfer=None):
    """A bar of chamfered (octagonal) section from start to end, height
    along up: 28 triangles."""
    start, end = Vector(start), Vector(end)
    axis = (end - start).normalized()
    up = Vector(up) if up is not None else (Z if abs(axis.z) < 0.9 else X)
    side = up.cross(axis).normalized()
    frame = Frame(start, side, axis.cross(side).normalized(), axis)
    half_u, half_v = width / 2, height / 2
    c = min(half_u, half_v) * 0.4 if chamfer is None else chamfer
    polygon = ((-half_u + c, -half_v), (half_u - c, -half_v), (half_u, -half_v + c), (half_u, half_v - c),
               (half_u - c, half_v), (-half_u + c, half_v), (-half_u, half_v - c), (-half_u, -half_v + c))
    b.prism(frame, polygon, (0.0, (end - start).length), material)


@tallied
def cushion(b, frame, u0, u1, v0, v1, w0, w1, material, round=0.05):
    """A stuffed pad: sides that roll over into its face, 26."""
    half_u, half_v = (u1 - u0) / 2, (v1 - v0) / 2
    r = min(round, half_u * 0.4, half_v * 0.4, (w1 - w0) * 0.45)
    profile = ((-r * 0.6, w0), (0.0, w0 + r * 0.5), (0.0, w1 - r), (-r * 1.1, w1))
    b.sweep_rect(frame, (u0 + u1) / 2, (v0 + v1) / 2, half_u, half_v, profile, material, cap=material)


@tallied
def key(b, frame, u, v, w, size, height, material, wide=1.0):
    """A tapered key cap standing at w: 10 triangles."""
    c = size * 0.22
    b.sweep_rect(frame, u, v, size * wide / 2, size / 2, ((0.0, w - 0.005), (-c, w + height)), material, cap=material)


@tallied
def bolt(b, point, normal, radius, material=METAL, height=None):
    """A hex bolt head: 16 triangles."""
    b.lathe(point, normal, ((radius, -0.004), (radius, radius * 0.6 if height is None else height)), 6, material, cap=material, phase=math.pi / 6)


@tallied
def knob(b, frame, u, v, w, radius, material=BLACK, height=0.07, pointer=METAL):
    """A turned knob with a skirt and a pointer line."""
    centre = geometry.at(frame, u, v, w)
    b.lathe(centre, frame.w, ((radius * 1.25, -0.004), (radius, 0.02), (radius, height * 0.8), (radius * 0.8, height)), 6, material, cap=material, phase=math.pi / 6)
    if pointer:
        b.quad(frame, u - 0.008, u + 0.008, v, v + radius * 0.75, w + height + 0.01, pointer)


@tallied
def screen(b, frame, u, v, width, height, glow, depth=0.12, lines=2, keys=0, hood=False):
    """A recessed screen: a housing with a chamfered bezel, the glowing
    glass set back in its well, scan lines, screws in the corners, with
    keys a key bar under it and with hood a visor over the top."""
    border = 0.065
    profile = ((0.0, -0.06), (0.0, depth - 0.025), (-0.025, depth), (-border, depth), (-border - 0.008, depth - 0.035))
    b.sweep_rect(frame, u, v, width / 2, height / 2, profile, DARK, cap=glow)
    glass_v0, glass_v1 = v - height / 2 + border, v + height / 2 - border
    glass_w = depth - 0.035 + 0.012
    inner = width - 2 * border
    for index in range(lines):
        line_v = glass_v0 + (glass_v1 - glass_v0) * (index + 0.7) / (lines + 0.6)
        length = inner * (0.35 + 0.45 * ((index * 7 + int(abs(u) * 13 + abs(v) * 5)) % 5) / 5)
        start = u - inner / 2 + 0.04
        b.quad(frame, start, start + length, line_v - 0.011, line_v + 0.011, glass_w, BLACK)
    for su in (-1, 1):
        b.rivet(geometry.at(frame, u + su * (width / 2 - 0.035), v - su * (height / 2 - 0.035), depth), frame.w, 0.016, METAL, height=0.008)
    if keys:
        bar_v1 = v - height / 2 - 0.012
        slab(b, frame, u - width / 2 + 0.05, u + width / 2 - 0.05, bar_v1 - 0.09, bar_v1, -0.05, depth - 0.03, BLACK, chamfer=0.015)
        pitch = min(0.08, (width - 0.16) / keys)
        for index in range(keys):
            key_u = u - (keys - 1) * pitch / 2 + index * pitch
            key(b, frame, key_u, bar_v1 - 0.045, depth - 0.03, 0.05, 0.02, AMBER if index == keys - 1 and int(abs(u) * 7 + abs(v) * 3) % 2 else METAL)
    if hood:
        top = v + height / 2
        visor = Frame(geometry.at(frame, 0, top, depth - 0.02), frame.u, (frame.w * 0.9 + frame.v * 0.25).normalized(), (frame.v - frame.w * 0.25).normalized())
        block(b, visor, u - width / 2 - 0.02, u + width / 2 + 0.02, 0.0, 0.11, -0.012, 0.012, DARK, chamfer=0.008)


@tallied
def keypad(b, frame, u, v, columns, rows, pitch=0.11, lit=(), depth=0.085):
    """A housing with a well, the keys standing in it with a gap."""
    width, height = columns * pitch + 0.07, rows * pitch + 0.07
    b.sweep_rect(frame, u, v, width / 2, height / 2, ((0.0, -0.05), (0.0, depth - 0.015), (-0.03, depth), (-0.03, depth - 0.022)), DARK, cap=BLACK)
    for column in range(columns):
        for row in range(rows):
            key_u = u - width / 2 + 0.035 + pitch * (column + 0.5)
            key_v = v - height / 2 + 0.035 + pitch * (row + 0.5)
            material = AMBER if (column, row) in lit else METAL
            key(b, frame, key_u, key_v, depth - 0.022, pitch * 0.72, 0.03, material)


@tallied
def gauge(b, frame, u, v, radius, needle_degrees=40, glass=AMBER):
    """A turned bezel, the dial set back in it, a needle and a hub."""
    centre = geometry.at(frame, u, v, 0.0)
    profile = ((radius, -0.04), (radius, 0.055), (radius * 0.8, 0.075), (radius * 0.8 - 0.006, 0.045))
    b.lathe(centre, frame.w, profile, 8, METAL, cap=glass, phase=math.pi / 8)
    needle = geometry.turned(geometry.moved(frame, u, v, 0.0), needle_degrees)
    b.quad(needle, -0.01, 0.01, -0.02, radius * 0.66, 0.06, BLACK)
    b.rivet(centre + frame.w * 0.045, frame.w, 0.022, BLACK, height=0.025)


@tallied
def toggles(b, frame, u, v, count, pitch=0.12, lever=0.1, raised=0.07):
    """A plate with a row of toggle switches in turned collars, each with
    its lamp above it."""
    width = count * pitch + 0.08
    slab(b, frame, u - width / 2, u + width / 2, v - 0.13, v + 0.13, -0.06, raised, DARK, chamfer=0.02)
    for index in range(count):
        toggle_u = u - width / 2 + 0.04 + pitch * (index + 0.5)
        base = geometry.at(frame, toggle_u, v - 0.03, raised)
        b.lathe(base, frame.w, ((0.032, -0.004), (0.022, 0.024)), 4, METAL, cap=METAL, phase=math.pi / 4)
        tip = base + frame.w * lever + frame.v * (0.045 if (index + int(abs(u) * 10)) % 3 else -0.045)
        b.cylinder(base + frame.w * 0.02, tip, 0.012, 4, METAL, open_start=True)
        b.cylinder(tip, tip + (tip - base).normalized() * 0.025, 0.02, 4, BLACK)
        b.rivet(geometry.at(frame, toggle_u, v + 0.08, raised), frame.w, 0.02, GREEN if (index + int(abs(v) * 10)) % 3 else AMBER, height=0.012)


@tallied
def cabinet(b, frame, u0, u1, v0, v1, depth, doors=2, lit=GREEN, style=0):
    """A carcass with doors: each door a raised panel with a sunk field,
    two hinge knuckles on its outer edge and a latch handle on two
    stand offs. style varies the doors (0 plain, 1 louvred, 2 a label
    plate and a bolt pattern)."""
    slab(b, frame, u0, u1, v0, v1, -0.1, depth, BLACK, chamfer=0.02)
    gap = 0.022
    width = (u1 - u0 - 0.06 - gap * (doors - 1)) / doors
    for index in range(doors):
        door_u0 = u0 + 0.03 + index * (width + gap)
        door_u1 = door_u0 + width
        dv0, dv1 = v0 + 0.04, v1 - 0.04
        middle_u = (door_u0 + door_u1) / 2
        b.sweep_rect(frame, middle_u, (dv0 + dv1) / 2, width / 2, (dv1 - dv0) / 2,
                     ((0.0, depth - 0.01), (0.0, depth + 0.022), (-0.014, depth + 0.036), (-0.06, depth + 0.026)), DARK, cap=DARK)
        hinge_left = index % 2 == 0
        hinge_u = door_u0 - 0.006 if hinge_left else door_u1 + 0.006
        for hinge_v in (dv0 + 0.12, dv1 - 0.12):
            b.cylinder(geometry.at(frame, hinge_u, hinge_v - 0.06, depth + 0.02), geometry.at(frame, hinge_u, hinge_v + 0.06, depth + 0.02), 0.018, 3, METAL, phase=math.pi / 6)
        handle_u = door_u1 - 0.075 if hinge_left else door_u0 + 0.075
        handle_v = (dv0 + dv1) / 2
        span = min(0.13, (dv1 - dv0) * 0.25)
        b.box(frame, (handle_u - 0.017, handle_u + 0.017), (handle_v - span - 0.02, handle_v + span + 0.02), (depth + 0.02, depth + 0.07), ORANGE, skip=("w0",))
        if style == 1:
            slots = max(2, int((dv1 - dv0 - 0.3) / 0.07))
            for slot in range(min(slots, 6)):
                slot_v = dv1 - 0.12 - slot * 0.06
                b.quad(frame, door_u0 + 0.08, door_u1 - 0.08, slot_v - 0.013, slot_v + 0.013, depth + 0.036, BLACK)
        elif style == 2:
            slab(b, frame, middle_u - width * 0.25, middle_u + width * 0.25, dv1 - 0.2, dv1 - 0.11, depth + 0.026, depth + 0.036, ORANGE, chamfer=0.005)
            for su in (-1, 1):
                b.rivet(geometry.at(frame, middle_u + su * (width / 2 - 0.035), dv0 + 0.035, depth + 0.036), frame.w, 0.016, METAL, height=0.008)
    if lit:
        b.rivet(geometry.at(frame, u1 - 0.06, v1 - 0.022, depth), frame.w, 0.018, lit, height=0.01)


@tallied
def vent(b, frame, u, v, width, height, depth=0.06):
    """A grille: a chamfered frame round a dark well with tilted slats."""
    b.sweep_rect(frame, u, v, width / 2, height / 2, ((0.0, -0.06), (0.0, depth - 0.015), (-0.015, depth), (-0.05, depth), (-0.05, depth - 0.04)), DARK, cap=BLACK)
    slats = max(2, int(height / 0.075))
    for index in range(slats):
        slat_v = v - height / 2 + 0.05 + (height - 0.1) * (index + 0.5) / slats
        b.box(geometry.turned(geometry.moved(frame, u, slat_v, depth - 0.03), 35, "u"), (-width / 2 + 0.05, width / 2 - 0.05), (-0.016, 0.016), (-0.004, 0.004), METAL, skip=("w0",))
    for su in (-1, 1):
        for sv in (-1, 1):
            bolt(b, geometry.at(frame, u + su * (width / 2 - 0.03), v + sv * (height / 2 - 0.03), depth), frame.w, 0.014)


@tallied
def instrument_box(b, frame, u, v, width, height, depth, glow, seed=0):
    """A box bolted to the wall on two lugs, its lid on a chamfered rim,
    an indicator, a knob or two and a cable gland underneath."""
    b.sweep_rect(frame, u, v, width / 2, height / 2, ((0.0, -0.08), (0.0, depth - 0.045), (-0.025, depth - 0.03), (-0.025, depth - 0.015), (-0.04, depth)), DARK, cap=DARK)
    for su in (-1, 1):
        b.rivet(geometry.at(frame, u + su * (width / 2 - 0.045), v + su * (height / 2 - 0.045), depth - 0.03), frame.w, 0.02, METAL, height=0.014)
    b.box(frame, (u - width / 2 + 0.07, u - width / 2 + 0.2), (v + height / 2 - 0.11, v + height / 2 - 0.075), (depth, depth + 0.012), glow, skip=("w0",))
    knobs = 1 + seed % 2
    for index in range(knobs):
        knob(b, frame, u + width / 2 - 0.1 - index * 0.13, v - height / 2 + 0.11, depth, 0.035, BLACK, height=0.05)


@tallied
def hazard(b, frame, u_range, v_range, w_range, pitch=0.24):
    """Slanted orange stripes across a band (the dark between them is the
    surface below)."""
    slant = v_range[1] - v_range[0]
    start = u_range[0]
    while start + 0.12 + slant <= u_range[1] + 1e-6:
        corners = []
        for w in w_range:
            for v in v_range:
                for side in (0, 1):
                    corners.append(geometry.at(frame, start + side * 0.12 + (slant if v == v_range[1] else 0.0), v, w))
        b.hexa(corners, ORANGE, skip=("w0",))
        start += pitch


def bolts_row(b, frame, u0, u1, v, w, count, size=0.025):
    for index in range(count):
        b.rivet(geometry.at(frame, u0 + (u1 - u0) * index / max(1, count - 1), v, w), frame.w, size, METAL)


@tallied
def handwheel(b, centre, axis, radius, material=ORANGE, spokes=3):
    """A valve's wheel: a rim, spokes and a hub on a stem."""
    centre, axis = Vector(centre), Vector(axis).normalized()
    b.washer(centre - axis * 0.012, axis, radius - 0.03, radius, 0.025, 12, material, phase=math.pi / 12)
    first, second = geometry.perpendiculars(axis)
    for index in range(spokes):
        angle = 2 * math.pi * index / spokes + 0.3
        direction = first * math.cos(angle) + second * math.sin(angle)
        b.cylinder(centre + direction * 0.03, centre + direction * (radius - 0.025), 0.011, 4, material, open_start=True)
    b.lathe(centre - axis * 0.12, axis, ((0.022, 0.0), (0.022, 0.1), (0.035, 0.11), (0.035, 0.14)), 6, METAL, cap=METAL)


# The cabin's walls -------------------------------------------------------------------


def porthole_frames(b):
    """Layered rims: an octagonal backing plate, a stepped turned rim with
    rivets on its step, a raised inner ring and a black sleeve lining
    the hole through the hull."""
    for index, (theta, z) in enumerate(PORTHOLES):
        frame = wall(theta, z)
        centre = frame.origin
        b.lathe(centre, frame.w, ((0.8, -0.06), (0.8, 0.0), (0.77, 0.03), (0.62, 0.03)), 8, DARK, phase=math.pi / 8)
        rim = ((0.66, 0.015), (0.66, 0.075), (0.635, 0.1), (0.56, 0.1), (0.55, 0.15), (0.48, 0.15), (0.42, 0.12))
        b.lathe(centre, frame.w, rim, 12, METAL, phase=math.pi / 12)
        b.lathe(centre, frame.w, ((0.4, 0.125), (0.4, -0.22)), 12, BLACK, phase=math.pi / 12)
        for bolt_index in range(8):
            angle = 2 * math.pi * (bolt_index + 0.5) / 8
            b.rivet(centre + frame.w * 0.1 + (frame.u * math.cos(angle) + frame.v * math.sin(angle)) * 0.6, frame.w, 0.026, METAL, height=0.022)


def desk(b):
    """The console under the screens, one segment per facet: a recessed
    plinth, a carcass with cabinets, a metal top with a rubber bumper,
    and on its slope keypads, toggles, knobs, a small screen and the
    throttle levers, each segment different."""
    for index, (theta, depth) in enumerate(((90, 0.95), (105, 1.25), (120, 1.15), (135, 0.95))):
        # Neighbouring segments overlap at the facet corners: odd ones
        # stand 0.015 higher so no two tops share a plane.
        lift = 0.015 * (index % 2)
        frame = wall(theta, lift, lean=False)
        slab(b, frame, -0.6, 0.6, -lift, 0.22, -0.1, depth - 0.1, BLACK, chamfer=0.015)
        slab(b, frame, -0.62, 0.62, 0.22, 1.5, -0.1, depth - 0.03, DARK, chamfer=0.02)
        cabinet(b, frame, -0.55, 0.55, 0.3, 1.36, depth, doors=2 if index != 2 else 1, lit=GREEN if theta % 30 else AMBER, style=index % 3)
        b.prism(Frame(geometry.at(frame, 0, 0, 0), frame.w, frame.v, frame.u), ((-0.1, 1.5), (depth, 1.5), (depth - 0.5, 1.68), (-0.1, 1.85)), (-0.62, 0.62), METAL)
        bar(b, geometry.at(frame, -0.6, 1.5, depth + 0.01), geometry.at(frame, 0.6, 1.5, depth + 0.01), 0.07, 0.07, BLACK, up=frame.v)
        slope = Frame(geometry.at(frame, 0, 1.5, depth), frame.u, (frame.v * 0.18 - frame.w * 0.5).normalized(), (frame.v * 0.5 + frame.w * 0.18).normalized())
        if theta == 90:
            keypad(b, slope, -0.25, 0.27, 3, 2, pitch=0.11)
            for knob_index in range(3):
                knob(b, slope, 0.12 + knob_index * 0.14, 0.27, 0.0, 0.04, BLACK if knob_index != 1 else ORANGE)
        elif theta == 105:
            screen(b, slope, -0.22, 0.29, 0.44, 0.3, AMBER, depth=0.05, lines=2)
            keypad(b, slope, 0.3, 0.27, 3, 2, pitch=0.1, lit={(1, 1)})
        elif theta == 120:
            toggles(b, slope, -0.26, 0.27, 3, pitch=0.12)
            keypad(b, slope, 0.12, 0.27, 2, 3, pitch=0.09, lit={(0, 2)})
        else:
            keypad(b, slope, -0.28, 0.27, 3, 3, pitch=0.095)
            knob(b, slope, 0.05, 0.3, 0.0, 0.05, BLACK)
        if theta in (120, 135):
            # A throttle lever in a slotted gate, pulled toward the seat.
            u = 0.42
            slab(b, slope, u - 0.08, u + 0.08, 0.05, 0.45, -0.02, 0.04, BLACK, chamfer=0.015)
            b.quad(slope, u - 0.012, u + 0.012, 0.1, 0.4, 0.05, DARK)
            foot = geometry.at(slope, u, 0.2, 0.04)
            knob_point = foot + slope.w * 0.26 - slope.v * 0.05
            b.cylinder(foot, knob_point, 0.018, 6, METAL)
            b.lathe(knob_point, (knob_point - foot).normalized(), ((0.035, -0.01), (0.05, 0.03), (0.045, 0.07), (0.025, 0.085)), 8, AMBER if theta == 120 else ORANGE, cap=BLACK)


def lower_walls(b):
    """Cabinets, gauge boards and columns from the floor to the knee,
    each facet a little different: plinths, louvred and plated doors,
    gauge boards, a screen with its key bar, a grille."""
    for index, (theta, depth, kind) in enumerate((
        (195, 0.85, "gauges"), (210, 0.85, "cabinet"),
        (225, 0.95, "screen"), (240, 0.85, "cabinet"), (255, 0.55, "column"), (285, 0.55, "column"),
        (300, 0.85, "gauges"), (315, 0.85, "cabinet"), (330, 0.7, "vent"),
    )):
        lift = 0.015 * (index % 2)
        frame = wall(theta, lift, lean=False)
        slab(b, frame, -0.62, 0.62, -lift, 0.18, -0.1, depth - 0.06, BLACK, chamfer=0.015)
        if kind == "cabinet":
            slab(b, frame, -0.62, 0.62, 0.18, 2.33, -0.1, depth - 0.18, DARK, chamfer=0.02)
            cabinet(b, frame, -0.6, 0.6, 0.18, 1.4, depth, doors=2, lit=AMBER if theta % 30 else GREEN, style=index % 3)
            cabinet(b, frame, -0.6, 0.6, 1.44, 2.35, depth - 0.15, doors=1, lit=None, style=(index + 1) % 3)
        elif kind == "column":
            cabinet(b, frame, -0.55, 0.55, 0.18, 2.35, depth, doors=1, lit=GREEN, style=1 if theta == 255 else 2)
        elif kind == "gauges":
            cabinet(b, frame, -0.6, 0.6, 0.18, 1.2, depth, doors=2, lit=None, style=2)
            slab(b, frame, -0.6, 0.6, 1.2, 2.35, -0.1, depth - 0.2, DARK, chamfer=0.03)
            board = geometry.moved(frame, 0, 0, depth - 0.2)
            gauge(b, board, -0.27, 1.95, 0.17, 30 + theta % 70)
            gauge(b, board, 0.25, 1.95, 0.17, 110 + theta % 50, glass=GREEN if theta == 300 else AMBER)
            toggles(b, board, 0.0, 1.5, 4)
            hazard(b, board, (-0.55, 0.55), (1.27, 1.33), (0.0, 0.012), pitch=0.2)
            bolts_row(b, board, -0.52, 0.52, 2.27, 0.0, 4, size=0.022)
        elif kind == "screen":
            cabinet(b, frame, -0.6, 0.6, 0.18, 1.2, depth, doors=2, lit=GREEN, style=1)
            slab(b, frame, -0.6, 0.6, 1.2, 2.35, -0.1, depth - 0.25, DARK, chamfer=0.03)
            board = geometry.moved(frame, 0, 0, depth - 0.25)
            screen(b, board, 0.0, 1.9, 0.8, 0.56, WHITE, keys=6, hood=True)
            knob(b, board, -0.4, 1.38, 0.0, 0.04)
            knob(b, board, 0.4, 1.38, 0.0, 0.04, ORANGE)
        elif kind == "vent":
            slab(b, frame, -0.6, 0.6, 0.18, 2.35, -0.1, depth, DARK, chamfer=0.03)
            face = geometry.moved(frame, 0, 0, depth)
            vent(b, face, 0.0, 0.7, 0.9, 0.8)
            toggles(b, face, 0.0, 1.55, 4)
            gauge(b, face, 0.0, 2.05, 0.15, 75)


def lean_ribs(b):
    """The structural ribs between the facets of the lean wall: a web and
    a flange (a T), bolted along the flange, a cable clip on some."""
    length = (CEILING - INNER_KNEE - 0.05) * math.sqrt(1 + SLOPE * SLOPE)
    for index in range(0, SEGMENTS, 2):
        theta = math.degrees(PHASE) + index * 15
        if abs(((theta + 180) % 360) - 180) < 20:
            continue
        frame = wall(theta, INNER_KNEE + 0.02, lean=True, facet=False)
        section = Frame(frame.origin, frame.u, frame.w, frame.v)
        tee = ((-0.022, -0.06), (0.022, -0.06), (0.022, 0.085), (0.075, 0.085), (0.075, 0.115), (-0.075, 0.115), (-0.075, 0.085), (-0.022, 0.085))
        b.prism(section, tee, (0.0, length - (0.5 if index % 4 else 0.0)), DARK)
        for step in range(1, int(length / 0.8)):
            b.rivet(geometry.at(frame, 0.0, step * 0.8 - (0.2 if index % 4 else 0.0), 0.115), frame.w, 0.02, METAL, height=0.012)


def upper_walls(b):
    """The lean wall: screens, keypads, overhead cabinets, quilting."""
    lean = lambda theta, z: wall(theta, z, lean=True)  # noqa: E731
    # Before the chair (the bank of screens).
    screen(b, lean(90, 2.5), 0.0, 0.47, 1.0, 0.7, GREEN, keys=5)
    screen(b, lean(105, 2.5), 0.0, 0.45, 1.1, 0.78, AMBER, lines=3, hood=True)
    screen(b, lean(135, 2.5), 0.05, 0.47, 0.95, 0.7, GREEN, keys=4)
    screen(b, lean(150, 2.5), 0.0, 0.42, 0.8, 0.62, AMBER, hood=True)
    screen(b, lean(90, 3.5), 0.55, 0.4, 0.6, 0.5, WHITE)
    keypad(b, lean(105, 3.6), -0.05, 0.15, 3, 4, lit={(2, 3)})
    screen(b, lean(105, 4.4), 0.0, 0.35, 0.9, 0.6, GREEN, lines=3)
    screen(b, lean(135, 3.6), 0.0, 0.4, 0.75, 0.6, AMBER, keys=3)
    toggles(b, lean(150, 3.7), 0.0, 0.2, 5)
    screen(b, lean(120, 4.6), 0.0, 0.3, 0.8, 0.55, GREEN, hood=True)
    screen(b, lean(75, 2.55), 0.0, 0.32, 0.7, 0.5, AMBER)
    # Over the bench: gauges, a screen and a switch board.
    board = lean(165, 2.5)
    slab(b, board, -0.62, 0.62, 0.0, 1.3, -0.1, 0.05, DARK, chamfer=0.03)
    face = geometry.moved(board, 0, 0, 0.05)
    gauge(b, face, -0.3, 0.35, 0.16, 20)
    gauge(b, face, 0.3, 0.35, 0.16, 130, glass=GREEN)
    toggles(b, face, 0.0, 0.85, 5)
    bolts_row(b, face, -0.55, 0.55, 1.22, 0.0, 5, size=0.02)
    screen(b, lean(180, 2.5), 0.0, 0.5, 0.9, 0.7, AMBER, keys=5, lines=3)
    screen(b, lean(180, 3.7), 0.0, 0.35, 0.7, 0.5, GREEN, hood=True)
    # Behind the chair: overhead lockers and screens.
    cabinet(b, lean(210, 2.5), -0.58, 0.58, 0.05, 1.3, 0.35, doors=2, style=1)
    screen(b, lean(225, 2.5), 0.0, 0.47, 0.85, 0.62, GREEN, keys=4)
    keypad(b, lean(225, 3.5), 0.0, 0.2, 4, 3, lit={(0, 2)})
    cabinet(b, lean(255, 4.5), -0.5, 0.5, 0.0, 0.9, 0.3, doors=1, style=2)
    cabinet(b, lean(285, 4.5), -0.5, 0.5, 0.0, 0.9, 0.3, doors=1, lit=AMBER, style=0)
    screen(b, lean(300, 2.5), -0.18, 0.42, 0.7, 0.62, AMBER, hood=True)
    gauge(b, lean(300, 3.6), -0.38, 0.2, 0.14, 60)
    gauge(b, lean(300, 3.6), 0.0, 0.2, 0.14, 160, glass=WHITE)
    cabinet(b, lean(330, 2.5), -0.58, 0.58, 0.05, 1.3, 0.35, doors=2, lit=AMBER, style=2)
    # Beside and over the airlock.
    screen(b, lean(15, 2.6), 0.27, 0.45, 0.7, 0.55, GREEN, keys=4)
    keypad(b, lean(15, 3.6), 0.3, 0.2, 3, 3, lit={(1, 1)})
    toggles(b, lean(345, 4.4), 0.0, 0.2, 4)
    screen(b, lean(45, 2.5), 0.0, 0.42, 0.8, 0.6, WHITE, lines=3)
    cabinet(b, lean(60, 2.5), -0.58, 0.58, 0.05, 1.2, 0.35, doors=2, style=0)
    keypad(b, lean(45, 3.6), 0.0, 0.2, 3, 4, lit={(0, 0), (2, 3)})
    # Mounting plates in a patchwork behind the instruments.
    for index, (theta, z, v1) in enumerate((
        (90, 2.45, 2.2), (105, 2.45, 2.6), (120, 2.45, 1.3), (135, 2.45, 2.2), (150, 2.45, 2.0), (165, 3.6, 1.1),
        (180, 2.45, 2.3), (210, 2.45, 2.4), (225, 2.45, 2.0), (285, 2.45, 2.2), (345, 2.45, 1.6), (45, 2.45, 2.0), (15, 2.45, 2.2),
    )):
        frame = lean(theta, z)
        low, high = {15: (-0.1, 0.85), 345: (-0.85, 0.1)}.get(theta, (-0.6, 0.6))
        slab(b, frame, low, high, 0.04, v1, -0.06, 0.035, DARK if index % 2 else BLACK, chamfer=0.02)
        bolts_row(b, frame, low + 0.08, high - 0.08, v1 - 0.08, 0.035, 2 + index % 2, size=0.022)
        for dot in range(3):
            b.rivet(geometry.at(frame, low + 0.1 + dot * 0.09, 0.14, 0.035), frame.w, 0.024, (GREEN, AMBER, WHITE)[(dot + index) % 3], height=0.014)
    # Bolted instrument boxes where the wall would be bare.
    for index, (theta, z, width, height, depth, glow) in enumerate((
        (0, 4.5, 0.9, 0.55, 0.3, GREEN), (195, 2.6, 0.7, 0.42, 0.28, GREEN),
        (240, 2.55, 0.8, 0.45, 0.35, WHITE), (120, 2.5, 0.7, 0.4, 0.3, AMBER), (165, 3.95, 0.8, 0.5, 0.3, GREEN),
        (60, 4.0, 0.7, 0.45, 0.28, AMBER), (210, 4.1, 0.75, 0.5, 0.3, GREEN),
    )):
        instrument_box(b, lean(theta, z), 0.0, height / 2, width, height, depth, glow, seed=index)
    # Quilted insulation round the top of the wall: two rows of stuffed
    # pads per facet, the rows offset so the seams do not line up.
    for index in range(SEGMENTS):
        theta = index * 15
        if theta in (300, 315, 330):
            continue
        frame = lean(theta, 5.5)
        split = 0.1 * ((index * 5) % 3 - 1)
        cushion(b, frame, -0.58 + split * 0.2, 0.58 + split * 0.2, 0.0, 0.68, -0.04, 0.14 + split * 0.2, PADDING, round=0.08)


def ceiling(b):
    """The top hatch: a stepped ring with bolts and an orange band, the
    dished door with its handwheel and six locking dogs."""
    top = Vector((0, 0, CEILING))
    down = -Z
    b.washer(top + Z * 0.004, down, 1.47, 1.56, 0.02, 24, ORANGE, phase=math.pi / 24)
    ring = ((1.45, -0.01), (1.45, 0.05), (1.41, 0.09), (1.25, 0.09), (1.22, 0.14), (0.97, 0.14), (0.92, 0.1), (0.9, 0.0))
    b.lathe(top, down, ring, 16, METAL, phase=math.pi / 16)
    b.lathe(top, down, ((0.88, 0.0), (0.88, 0.05), (0.78, 0.09), (0.35, 0.12)), 16, DARK, cap=DARK, phase=math.pi / 16)
    handwheel(b, top - Z * 0.3, down, 0.36, METAL, spokes=4)
    for index in range(12):
        angle = 2 * math.pi * (index + 0.5) / 12
        b.rivet(top - Z * 0.09 + Vector((math.cos(angle), math.sin(angle), 0)) * 1.33, down, 0.03, METAL, height=0.025)
    for index in range(6):
        angle = 2 * math.pi * index / 6 + 0.2
        radial_direction = Vector((math.cos(angle), math.sin(angle), 0))
        dog = Frame(top - Z * 0.12 + radial_direction * 1.05, radial_direction.cross(down), radial_direction, down)
        slab(b, dog, -0.05, 0.05, -0.16, 0.06, 0.0, 0.07, ORANGE if index % 3 == 0 else METAL, chamfer=0.015)


# The two lamps ----------------------------------------------------------------------
#
# The game's point lights have no shadows, so the fixtures make the light
# read: each a dark housing on top and a bright face underneath.

OVERHEAD_X = -1.85
OVERHEAD_TOP = CEILING - 0.42
OVERHEAD_HALF_LENGTH = 1.3
OVERHEAD_HALF_WIDTH = 0.21
# The housing's section going down from its top (offset from the
# housing's sides, depth below the top): dark sides, a metal lip, then
# the amber lens standing out below the lip so its slanted sides glow
# when seen from the side.
OVERHEAD_HOUSING = ((-0.04, 0.0), (0.0, 0.04), (0.0, 0.15))
OVERHEAD_LIP = ((0.0, 0.15), (-0.02, 0.17), (-0.05, 0.17))
OVERHEAD_LENS = ((-0.05, 0.17), (-0.085, 0.215))


def overhead_lamp(b):
    """A long lamp strip hung under the ceiling beside the hatch, over
    the chair, on two drop brackets: a black top with cooling fins,
    chamfered dark sides, a metal lip and the amber lens underneath, end
    caps, and a cable up into the ceiling."""
    frame = Frame(Vector((OVERHEAD_X, 0, OVERHEAD_TOP)), X.copy(), Y.copy(), -Z)
    half_u, half_v = OVERHEAD_HALF_WIDTH, OVERHEAD_HALF_LENGTH
    b.sweep_rect(frame, 0.0, 0.0, half_u, half_v, OVERHEAD_HOUSING, DARK, cap_start=BLACK)
    b.sweep_rect(frame, 0.0, 0.0, half_u, half_v, OVERHEAD_LIP, METAL)
    b.sweep_rect(frame, 0.0, 0.0, half_u, half_v, OVERHEAD_LENS, AMBER, cap=AMBER)
    for v in (-half_v - 0.025, half_v + 0.025):
        block(b, frame, -half_u - 0.015, half_u + 0.015, v - 0.035, v + 0.035, -0.015, 0.185, BLACK, chamfer=0.015)
    up = Frame(frame.origin, X.copy(), Y.copy(), Z.copy())
    for index in range(11):
        v = -half_v + 0.12 + index * (2 * half_v - 0.24) / 10
        slab(b, up, -half_u + 0.04, half_u - 0.04, v - 0.014, v + 0.014, 0.0, 0.08, BLACK, chamfer=0.008)
    for v in (-0.9, 0.9):
        base = Vector((OVERHEAD_X, v, OVERHEAD_TOP))
        for side in (-1, 1):
            bar(b, base + X * side * 0.12 + Z * 0.005, Vector((OVERHEAD_X + side * 0.05, v, CEILING - 0.005)), 0.045, 0.03, METAL, up=X)
        block(b, Frame(Vector((OVERHEAD_X, v, CEILING)), X.copy(), Y.copy(), -Z), -0.12, 0.12, -0.06, 0.06, -0.01, 0.03, DARK, chamfer=0.01)
        for side in (-1, 1):
            bolt(b, Vector((OVERHEAD_X + side * 0.08, v, CEILING - 0.03)), -Z, 0.016)
    b.cylinder(Vector((OVERHEAD_X + 0.1, -half_v + 0.15, OVERHEAD_TOP + 0.04)), Vector((OVERHEAD_X + 0.1, -half_v + 0.15, CEILING + 0.01)), 0.025, 5, BLACK)


def overhead_lamp_face():
    """The centre of the overhead strip's lens face (Blender)."""
    return Vector((OVERHEAD_X, 0.0, OVERHEAD_TOP - OVERHEAD_LENS[-1][1]))


DESK_LAMP_BASE = (142.5, 2.25)


def desk_lamp_pose():
    """The desk lamp's head and the axis its face points along."""
    out, _ = radial(130)
    head = Vector((0, 0, 3.05)) + out * 3.45
    axis = (-Z + out * 0.2 + radial(130)[1] * 0.15).normalized()
    return head, axis


def desk_lamp(b):
    """A hooded work lamp on an articulated arm over the left end of the
    desk: a wall plate between two screens, a shoulder knuckle, twin rods
    to the elbow and on to the head, springs, and the hood, black outside
    with the white lens standing out of it, pointed at the work surface."""
    theta, z = DESK_LAMP_BASE
    plate = wall(theta, z)
    slab(b, plate, -0.1, 0.1, -0.08, 0.2, -0.03, 0.045, DARK, chamfer=0.015)
    for v in (-0.03, 0.15):
        bolt(b, geometry.at(plate, 0.0, v, 0.045), plate.w, 0.018)
    shoulder = geometry.at(plate, 0.0, 0.06, 0.14)
    head, axis = desk_lamp_pose()
    elbow = Vector((0, 0, 3.3)) + radial(138.5)[0] * 3.7
    knuckle_axis = (elbow - shoulder).cross(head - elbow).normalized()
    b.lathe(shoulder - knuckle_axis * 0.06, knuckle_axis, ((0.05, 0.0), (0.05, 0.12)), 8, BLACK, cap=METAL, cap_start=METAL)
    b.cylinder(geometry.at(plate, 0.0, 0.06, 0.04), shoulder, 0.028, 6, METAL)
    neck = head - axis * 0.1
    for start, end in ((shoulder, elbow), (elbow, neck)):
        for side in (-1, 1):
            offset = knuckle_axis * side * 0.04
            b.cylinder(start + offset, end + offset, 0.014, 5, METAL)
        middle_offset = (end - start).cross(knuckle_axis).normalized() * 0.06
        b.cylinder(start + (end - start) * 0.2 + middle_offset, start + (end - start) * 0.75 + middle_offset, 0.018, 5, ORANGE)
    b.lathe(elbow - knuckle_axis * 0.07, knuckle_axis, ((0.04, 0.0), (0.04, 0.14)), 8, BLACK, cap=METAL, cap_start=METAL)
    hood = ((0.08, 0.0), (0.1, 0.08), (0.22, 0.25), (0.235, 0.27), (0.2, 0.27))
    b.lathe(head, axis, hood, 12, BLACK, cap_start=BLACK, phase=math.pi / 12)
    b.lathe(head, axis, ((0.2, 0.27), (0.15, 0.31)), 12, WHITE, cap=WHITE, phase=math.pi / 12)
    b.lathe(neck, axis, ((0.045, 0.0), (0.045, 0.1)), 6, METAL, cap_start=METAL)


def desk_lamp_face():
    """The centre of the desk lamp's lens face (Blender)."""
    head, axis = desk_lamp_pose()
    return head + axis * 0.31


# The floor ------------------------------------------------------------------------------


def floor(b):
    """Riveted plates on a grid of 2 cells: dark seams and flat rivets, all
    below 0.02 cells so the free cells stay empty, where the floor shows."""
    covered = (
        ((1.0, -1.8), (4.7, 1.8)), ((-2.75, -1.85), (-1.25, -0.2)),
        *(((low[0], low[1]), (high[0], high[1])) for low, high in POCKETS.values()),
    )

    def shows(point):
        if math.hypot(point.x, point.y) > 3.7:
            return False
        return not any(low[0] - 0.05 < point.x < high[0] + 0.05 and low[1] - 0.05 < point.y < high[1] + 0.05 for low, high in covered)

    lines = [(Vector((x, -4.0, 0)), Y) for x in (-3.0, -1.0, 1.0, 3.0)] + [(Vector((-4.0, y, 0)), X) for y in (-2.0, 0.0, 2.0)]
    for start, direction in lines:
        side = Vector((-direction.y, direction.x, 0))
        points = [start + direction * (step * 0.5) for step in range(17)]
        run = []
        for index, point in enumerate(points + [None]):
            if point is not None and shows(point):
                run.append(point)
                b.rivet(point + side * (0.09 if index % 2 else -0.09) + Z * FLOOR, Z, 0.035, METAL, height=0.008)
                continue
            if len(run) > 1:
                first, last = run[0], run[-1]
                top = Z * (0.012 if direction.y else 0.017)
                b.hexa([first - side * 0.025 + Z * 0.0, last - side * 0.025, first + side * 0.025, last + side * 0.025,
                        first - side * 0.025 + top, last - side * 0.025 + top, first + side * 0.025 + top, last + side * 0.025 + top], DARK)
            run = []


# The airlock's housing details -------------------------------------------------------


def airlock_details(b):
    """The housing's cabin face: a chamfered bezel round the inner door,
    the pistons that work the shutter, hazard stripes, the gauge board on
    the shutter's pocket, a lever on the housing's side, ribs on top."""
    face = Frame(Vector((HOUSING_FACE, 0, 0)), -Y, Z, -X)
    for low, high in (((-1.73, 0.0), (-1.05, HOUSING_TOP - 0.02)), ((1.05, 0.0), (1.73, HOUSING_TOP - 0.02)), ((-1.05, 2.05), (1.05, HOUSING_TOP - 0.02))):
        slab(b, face, low[0], high[0], low[1], high[1], -0.02, 0.06, DARK, chamfer=0.025)
    for side in (-1, 1):
        for z in (0.25, 0.9, 1.55, 2.3):
            bolt(b, geometry.at(face, side * 1.62, z, 0.06), -X, 0.03)
        # A piston: a cylinder with a stepped gland and a polished rod,
        # on two clevis lugs.
        x_u = side * 1.4
        b.lathe(geometry.at(face, x_u, 1.1, 0.06), Z, ((0.06, 0.0), (0.06, 0.62), (0.045, 0.66), (0.045, 0.72), (0.025, 0.75)), 8, DARK, cap_start=DARK, cap=DARK)
        b.cylinder(geometry.at(face, x_u, 0.26, 0.06), geometry.at(face, x_u, 1.12, 0.06), 0.028, 6, METAL)
        b.lathe(geometry.at(face, x_u, 1.8, 0.06), Z, ((0.032, 0.0), (0.032, 0.1)), 6, METAL, cap=METAL)
        for v in (0.24, 1.92):
            slab(b, face, x_u - 0.08, x_u + 0.08, v - 0.06, v + 0.06, 0.04, 0.13, METAL, chamfer=0.02)
            b.cylinder(geometry.at(face, x_u - 0.09, v, 0.1), geometry.at(face, x_u + 0.09, v, 0.1), 0.025, 6, BLACK)
    hazard(b, face, (-0.9, 0.9), (2.12, 2.2), (0.06, 0.072), pitch=0.2)
    hazard(b, face, (-1.72, 1.72), (2.32, 2.6), (0.06, 0.072))
    floor_band = Frame(Vector((0.0, 0.0, FLOOR)), Y.copy(), X.copy(), Z.copy())
    hazard(b, floor_band, (-0.98, 0.98), (0.35, 0.8), (0.0, 0.012), pitch=0.26)
    tower = Frame(Vector((HOUSING_FACE, 0, HOUSING_TOP)), -Y, Z, -X)
    slab(b, tower, -1.15, 1.15, 0.08, 1.5, -0.02, 0.025, DARK, chamfer=0.02)
    board = geometry.moved(tower, 0, 0, 0.025)
    gauge(b, board, -0.55, 0.95, 0.2, 35)
    gauge(b, board, 0.0, 1.05, 0.24, 120)
    gauge(b, board, 0.55, 0.95, 0.2, 200, glass=GREEN)
    toggles(b, board, 0.0, 0.35, 4, lever=0.03, raised=0.03)
    for index in range(7):
        key(b, board, -0.8 + index * 0.26, 1.39, 0.0, 0.07, 0.02, GREEN if index % 3 else AMBER, wide=1.6)
    for u in (-1.08, 1.08):
        for v in (0.15, 1.45):
            bolt(b, geometry.at(board, u, v, 0.0), -X, 0.024)
    # A lever on the side of the housing.
    side_plate = Frame(Vector((1.6, -1.75, 1.4)), X, Z, -Y)
    slab(b, side_plate, -0.15, 0.15, -0.22, 0.22, -0.01, 0.06, DARK, chamfer=0.02)
    b.lathe(Vector((1.6, -1.81, 1.4)), -Y, ((0.05, 0.0), (0.05, 0.04), (0.03, 0.06)), 8, METAL, cap=METAL)
    b.cylinder((1.6, -1.85, 1.4), (1.6, -2.07, 1.75), 0.022, 6, METAL)
    b.lathe(Vector((1.6, -2.07, 1.75)), Vector((0, -0.22, 0.35)), ((0.03, -0.02), (0.045, 0.03), (0.045, 0.1), (0.03, 0.12)), 8, ORANGE, cap=BLACK, cap_start=ORANGE)
    # The housing's flat sides: stiffeners and, on the side under the bed,
    # a bolted access panel.
    right = Frame(Vector((0.0, -1.75, 0.0)), X.copy(), Z.copy(), -Y)
    slab(b, right, 2.3, 3.7, 0.35, 2.2, -0.02, 0.045, DARK, chamfer=0.025)
    for u in (2.38, 3.0, 3.62):
        for v in (0.43, 2.12):
            b.rivet(geometry.at(right, u, v, 0.045), -Y, 0.024, METAL, height=0.016)
    for x in (2.08, 3.95):
        bar(b, (x, -1.78, 0.04), (x, -1.78, HOUSING_TOP - 0.04), 0.07, 0.06, DARK, up=-Y)
    bar(b, (1.62, 1.78, 0.04), (1.62, 1.78, HOUSING_TOP - 0.04), 0.07, 0.06, DARK, up=Y)
    # Housing top: ribs along the shelf.
    for index in range(5):
        y = -1.5 + index * 0.75
        bar(b, (1.82, y, HOUSING_TOP + 0.03), (3.98, y, HOUSING_TOP + 0.03), 0.08, 0.06, DARK)


def bore_ribs(b):
    """Bulkhead rings round the bore, their inner edge following the
    crawl space's square so the 2 by 2 cells stay empty, bolted to the
    bore; a hand rail on each side; a walkway grating no higher than the
    floor plate tolerance."""
    angles = [math.radians(-45 + 15 * index) for index in range(19)]

    def inner_radius_at(angle):
        c, s = math.cos(angle), math.sin(angle)
        return min(1.41, 0.98 / max(abs(c), abs(s)) + 0.045)

    for x0 in (2.3, 3.0, 3.7):
        points, faces = [], []
        for angle in angles:
            c, s = math.cos(angle), math.sin(angle)
            inner = inner_radius_at(angle)
            for x in (x0, x0 + 0.08):
                points.append(Vector((x, c * inner, max(0.006, 1.0 + s * inner))))
                points.append(Vector((x, c * 1.47, max(0.006, 1.0 + s * 1.47))))
        for index in range(len(angles) - 1):
            a, n = index * 4, (index + 1) * 4
            faces += [(a, n, n + 1, a + 1), (a + 2, a + 3, n + 3, n + 2), (a, a + 2, n + 2, n), (a + 1, n + 1, n + 3, a + 3)]
        last = (len(angles) - 1) * 4
        faces += [(0, 1, 3, 2), (last, last + 2, last + 3, last + 1)]
        b.closed(DARK, points, faces)
        for angle in angles[1:-1:2]:
            c, s = math.cos(angle), math.sin(angle)
            radius = inner_radius_at(angle) + 0.07
            b.rivet(Vector((x0 + 0.08, c * radius, 1.0 + s * radius)), X, 0.022, METAL)
            b.rivet(Vector((x0, c * radius, 1.0 + s * radius)), -X, 0.022, METAL)
    for side in (-1, 1):
        bar(b, (2.08, side * 1.08, 1.3), (3.92, side * 1.08, 1.3), 0.05, 0.05, ORANGE)
    for index in range(19):
        x = 2.06 + index * 0.1
        b.box(Frame(Vector((x, 0, FLOOR)), X, Y, Z), (0.0, 0.04), (-0.95, 0.95), (0.0, 0.012), METAL, skip=("w0",))


# Pockets: the niches round the three machines ---------------------------------------


@tallied
def ablock(b, minimum, maximum, material, chamfer=0.02):
    if chamfer <= 0:
        b.abox(minimum, maximum, material)
        return
    block(b, geometry.WORLD, minimum[0], maximum[0], minimum[1], maximum[1], minimum[2], maximum[2], material, chamfer=chamfer)


def niche(b, pocket, facing_axis, facing_sign):
    """An open frame round a pocket: a post at each front and back corner,
    a rail and a diagonal orange brace on each side, a lintel above and a
    panel behind, all chamfered and bolted. Nothing enters the pocket."""
    (low, high) = pocket
    f, l = facing_axis, 1 - facing_axis
    front = high[f] if facing_sign > 0 else low[f]
    back = low[f] if facing_sign > 0 else high[f]
    height = high[2]

    def put(f_range, l_range, z_range, material, chamfer=0.02):
        minimum, maximum = [0.0, 0.0, z_range[0]], [0.0, 0.0, z_range[1]]
        minimum[f], maximum[f] = min(f_range), max(f_range)
        minimum[l], maximum[l] = min(l_range), max(l_range)
        ablock(b, minimum, maximum, material, chamfer)

    def point(along_f, along_l, z):
        coordinates = [0.0, 0.0, z]
        coordinates[f], coordinates[l] = along_f, along_l
        return Vector(coordinates)

    inward = -facing_sign
    facing = point(facing_sign, 0, 0) - point(0, 0, 0)
    for side_l, outward in ((low[l], -1), (high[l], 1)):
        posts = (side_l + outward * 0.02, side_l + outward * 0.17)
        put((front + inward * 0.03, front + inward * 0.19), posts, (0.0, height + 0.02), DARK)
        put((back, back + inward * 0.12), posts, (0.0, height + 0.02), DARK, chamfer=0.0)
        put((front + inward * 0.19, back), (side_l + outward * 0.06, side_l + outward * 0.13), (height * 0.45, height * 0.45 + 0.1), DARK)
        middle_l = side_l + outward * 0.095
        b.cylinder(point(front + inward * 0.2, middle_l, 0.15), point(back + inward * 0.04, middle_l, height - 0.1), 0.035, 6, ORANGE)
        for z in (0.3, height / 2 + 0.3, height - 0.2):
            b.rivet(point(front + inward * 0.03, middle_l, z), facing, 0.028, METAL, height=0.02)
        for z in (0.12, height - 0.12):
            put((front + inward * 0.05, front + inward * 0.17), (side_l + outward * 0.0, side_l + outward * 0.19), (z - 0.05, z + 0.05), METAL, chamfer=0.012)
    put((front + inward * 0.03, back + inward * 0.3), (low[l] - 0.2, high[l] + 0.2), (height + 0.02, height + 0.3), DARK, chamfer=0.03)
    put((back + inward * 0.02, back + inward * 0.3), (low[l] - 0.05, high[l] + 0.05), (0.0, height + 0.01), DARK, chamfer=0.0)
    hazard_frame = Frame(point(front + inward * 0.03, 0, height + 0.02), point(0, 1, 0) - point(0, 0, 0), Z.copy(), facing)
    lintel = (min(low[l], high[l]) - 0.15, max(low[l], high[l]) + 0.15)
    if hazard_frame.u.cross(hazard_frame.v).dot(facing) < 0:
        hazard_frame = Frame(hazard_frame.origin, -hazard_frame.u, hazard_frame.v, facing)
        lintel = (-lintel[1], -lintel[0])
    hazard(b, hazard_frame, lintel, (0.07, 0.21), (0.0, 0.012), pitch=0.22)


def niches(b):
    niche(b, POCKETS["locker pocket"], 1, 1)
    niche(b, POCKETS["bench pocket"], 0, 1)
    niche(b, POCKETS["oxygen pocket"], 1, -1)
    oxygen_plumbing(b)


def oxygen_plumbing(b):
    """Over the oxygen generator's niche (x 0..2, facing -Y): a manifold
    with two valves on handwheels, a gauge cluster on the wall above it,
    and the feeds dropping into the niche's lintel."""
    y = 2.55
    z = 3.62
    b.lathe(Vector((-0.25, y, z)), X, ((0.07, 0.0), (0.07, 2.5)), 8, METAL, cap=METAL, cap_start=METAL, phase=math.pi / 8)
    for x in (-0.15, 0.95, 2.15):
        b.lathe(Vector((x - 0.05, y, z)), X, ((0.1, 0.0), (0.1, 0.1)), 8, DARK, cap=DARK, cap_start=DARK, phase=math.pi / 8)
    for x in (0.45, 1.45):
        body = Vector((x, y, z))
        b.lathe(body - Y * 0.0, -Y, ((0.11, -0.1), (0.11, 0.06), (0.08, 0.1)), 8, ORANGE, cap=ORANGE, cap_start=ORANGE, phase=math.pi / 8)
        handwheel(b, body - Y * 0.24, -Y, 0.15, ORANGE if x < 1 else METAL)
        b.lathe(Vector((x, y, z - 0.08)), -Z, ((0.045, 0.0), (0.045, 0.3)), 8, METAL, phase=math.pi / 8)
    for index, x in enumerate((0.05, 0.95, 1.95)):
        b.cylinder(Vector((x, y, z + 0.05)), Vector((x, y, z + 0.2)), 0.02, 6, METAL)
        dial = Frame(Vector((x, y - 0.02, z + 0.3)), X.copy(), Z.copy(), -Y)
        gauge(b, dial, 0.0, 0.0, 0.11 if index != 1 else 0.13, 50 + index * 60, glass=(WHITE, AMBER, GREEN)[index])


def keypad_console(b):
    """The console between the airlock's housing and the oxygen niche
    (x 2.1..3.3, y 1.75..2.9), its panel tilted toward the cabin."""
    ablock(b, (2.13, 1.77, 0.0), (3.3, 2.9, 2.2), DARK, chamfer=0.03)
    ablock(b, (2.04, 1.79, 0.0), (3.35, 2.95, 0.15), BLACK, chamfer=0.02)
    front = Frame(Vector((2.1, 2.3, 0.0)), Y, Z, -X)
    cabinet(b, front, -0.5, 0.5, 0.22, 1.35, 0.0, doors=1, lit=GREEN, style=1)
    tilted = Frame(Vector((2.55, 2.3, 2.2)), Y, (Z - X * 0.45).normalized(), (-X + Z * 0.45).normalized())
    slab(b, tilted, -0.58, 0.58, 0.0, 0.9, -0.25, 0.0, DARK, chamfer=0.03)
    screen(b, tilted, 0.0, 0.64, 0.7, 0.38, GREEN, depth=0.05)
    keypad(b, tilted, -0.15, 0.21, 4, 2, pitch=0.1, lit={(3, 1)})
    toggles(b, tilted, 0.38, 0.21, 2, pitch=0.1)


# The chair ---------------------------------------------------------------------------


@tallied
def buckle(b, frame, u, v, w, width, height, material=METAL):
    """A strap buckle: a chamfered frame plate with a tongue bar."""
    slab(b, frame, u - width / 2, u + width / 2, v - height / 2, v + height / 2, w, w + 0.025, material, chamfer=0.008)
    b.box(frame, (u - width / 2 + 0.015, u + width / 2 - 0.015), (v - 0.012, v + 0.012), (w + 0.025, w + 0.035), BLACK, skip=("w0",))


def chair(b):
    """Bolted to the floor in x -3..-1, y -2..0, facing +Y: a plate with
    seat rails, a turned pedestal with shock struts, the seat pan with
    tufted cushions and bolsters, the reclined back's shell with stuffed
    rows and wings, the headrest, the five point harness with its buckles
    and adjusters, armrests with a stick and a keypad."""
    cx = -2.0
    ablock(b, (cx - 0.72, -1.82, FLOOR), (cx + 0.72, -0.22, FLOOR + 0.07), DARK, chamfer=0.03)
    for x in (cx - 0.62, cx + 0.62):
        for y in (-1.72, -1.02, -0.32):
            bolt(b, Vector((x, y, FLOOR + 0.07)), Z, 0.035)
    for x in (cx - 0.35, cx + 0.35):
        bar(b, (x, -1.75, FLOOR + 0.1), (x, -0.3, FLOOR + 0.1), 0.07, 0.06, METAL)
    b.lathe(Vector((cx, -1.0, FLOOR + 0.07)), Z, ((0.36, 0.0), (0.36, 0.05), (0.3, 0.09), (0.28, 0.42), (0.37, 0.46), (0.37, 0.55), (0.32, 0.6)), 12, DARK, cap=DARK, phase=math.pi / 12)
    for x in (cx - 0.55, cx + 0.55):
        b.cylinder((x, -0.32, FLOOR + 0.08), (x, -0.8, 0.7), 0.05, 6, METAL)
        b.lathe(Vector((x, -0.32, FLOOR + 0.08)), Vector((0, -0.18, 0.23)), ((0.085, 0.03), (0.085, 0.24), (0.06, 0.27)), 8, BLACK, cap=BLACK, cap_start=BLACK)
        b.cylinder((x, -1.7, FLOOR + 0.08), (x, -1.25, 0.7), 0.05, 6, METAL)
    # Seat pan, tufted cushion in three rolls, the side bolsters.
    ablock(b, (cx - 0.8, -1.32, 0.64), (cx + 0.8, -0.16, 0.84), DARK, chamfer=0.035)
    for y0, y1, top in ((-1.25, -0.88, 1.0), (-0.86, -0.53, 1.0), (-0.51, -0.18, 1.04)):
        cushion(b, geometry.WORLD, cx - 0.64, cx + 0.64, y0, y1, 0.83, top, PADDING, round=0.06)
    for side in (-1, 1):
        x = cx + side * 0.79
        cushion(b, geometry.WORLD, x - 0.09, x + 0.09, -1.22, -0.22, 0.83, 1.1, PADDING, round=0.07)
        b.lathe(Vector((cx + side * 0.82, -1.22, 0.95)), X * side, ((0.17, 0.0), (0.17, 0.09), (0.12, 0.13), (0.06, 0.13)), 10, ORANGE, cap=DARK, cap_start=ORANGE)
    # Back, reclined 8.5 degrees: the shell, three stuffed rows, wings.
    up = Vector((0, -0.15, 1)).normalized()
    forward = Vector((0, 1, 0.15)).normalized()
    back = Frame(Vector((cx, -1.25, 0.84)), X.copy(), up, forward)
    block(b, back, -0.8, 0.8, 0.05, 1.64, -0.26, -0.04, DARK, chamfer=0.04)
    for v0, v1 in ((0.1, 0.56), (0.59, 1.06), (1.09, 1.56)):
        cushion(b, back, -0.5, 0.5, v0, v1, -0.05, 0.16, PADDING, round=0.07)
    for side in (-1, 1):
        wing = geometry.turned(geometry.moved(back, side * 0.52, 0, 0.0), -side * 28, "v")
        u_range = (0.0, 0.26) if side > 0 else (-0.26, 0.0)
        cushion(b, wing, *u_range, 0.12, 0.8, -0.06, 0.2, PADDING, round=0.06)
        cushion(b, wing, *u_range, 0.83, 1.5, -0.06, 0.2, PADDING, round=0.06)
        b.cylinder(geometry.at(back, side * 0.24, 1.6, -0.14), geometry.at(back, side * 0.24, 1.76, -0.14), 0.035, 6, METAL)
    block(b, back, -0.44, 0.44, 1.72, 2.3, -0.24, -0.06, DARK, chamfer=0.035)
    cushion(b, back, -0.34, 0.34, 1.76, 2.26, -0.07, 0.11, PADDING, round=0.06)
    for side in (-1, 1):
        wing = geometry.turned(geometry.moved(back, side * 0.36, 0, 0.0), -side * 35, "v")
        cushion(b, wing, *((0.0, 0.16) if side > 0 else (-0.16, 0.0)), 1.8, 2.24, -0.05, 0.15, PADDING, round=0.04)
    # Harness: shoulder straps over the pads with adjusters, the lap belt,
    # the crotch strap, and the round release buckle where they meet.
    buckle_point = Vector((cx, -0.6, 1.17))
    for side in (-1, 1):
        top = geometry.at(back, side * 0.22, 1.5, 0.165)
        direction = (buckle_point + X * side * 0.08 - top).normalized()
        across = direction.cross(forward).normalized()
        strap = Frame(top, across, direction, forward)
        b.box(strap, (-0.065, 0.065), (-0.1, (buckle_point - top).length), (0.0, 0.022), ORANGE)
        buckle(b, strap, 0.0, 0.35, 0.022, 0.15, 0.09)
        b.box(Frame(geometry.at(back, side * 0.22, 1.4, 0.0), X.copy(), up, forward), (-0.065, 0.065), (0.0, 0.6), (0.165, 0.185), ORANGE, skip=("w0",))
        ablock(b, (cx + side * 0.64 - 0.07, -0.67, 1.0), (cx + side * 0.64 + 0.07, -0.53, 1.19), METAL, chamfer=0.015)
    b.abox((cx - 0.62, -0.66, 1.1), (cx + 0.62, -0.56, 1.16), ORANGE)
    b.abox((cx - 0.06, -0.58, 1.0), (cx + 0.06, -0.2, 1.06), ORANGE)
    b.lathe(Vector((cx, -0.72, 1.16)), -forward * -1, ((0.1, 0.0), (0.1, 0.05), (0.08, 0.075)), 10, METAL, cap=ORANGE, cap_start=METAL, phase=math.pi / 10)
    # Armrests: a stuffed pad on two posts, a control head with a stick on
    # the right and a keypad on the left.
    for side in (-1, 1):
        x = cx + side * 0.86
        cushion(b, geometry.WORLD, x - 0.11, x + 0.11, -1.2, -0.34, 1.4, 1.55, PADDING, round=0.05)
        for y in (-1.0, -0.5):
            bar(b, (x, y, 0.9), (x, y, 1.41), 0.07, 0.07, METAL)
        ablock(b, (x - 0.13, -0.34, 1.36), (x + 0.13, -0.06, 1.6), DARK, chamfer=0.03)
        head = Frame(Vector((x, -0.2, 1.6)), X.copy(), Y.copy(), Z.copy())
        if side > 0:
            b.lathe(Vector((x, -0.22, 1.6)), Z, ((0.06, 0.0), (0.06, 0.02), (0.035, 0.05)), 8, BLACK, cap=BLACK)
            b.cylinder((x, -0.22, 1.64), (x, -0.24, 1.8), 0.02, 6, METAL)
            b.lathe(Vector((x, -0.24, 1.78)), Z, ((0.035, 0.0), (0.045, 0.04), (0.042, 0.11), (0.025, 0.13)), 8, BLACK, cap=ORANGE)
            b.rivet((x - 0.08, -0.1, 1.6), Z, 0.022, GREEN, height=0.012)
        else:
            for column in range(2):
                for row in range(2):
                    key(b, head, -0.045 + column * 0.09, -0.07 + row * 0.09, 0.0, 0.06, 0.018, AMBER if (column, row) == (1, 1) else METAL)
        b.box(Frame(Vector((x, -0.06, 1.42)), X.copy(), Z.copy(), Y.copy()), (-0.08, 0.08), (0.03, 0.12), (0.0, 0.012), GREEN if side > 0 else AMBER, skip=("w0",))


# The bed -----------------------------------------------------------------------------


def bed(b):
    """Strapped flat on the lean wall at 315 degrees, beside and above the
    airlock's housing, its foot on the cabinets, wider at the foot as the
    cone narrows upward: a chamfered frame on wall brackets, a mattress
    in six stuffed sections, a pillow, four straps with cam buckles and
    a padded head board."""
    theta = 315
    base = wall(theta, 2.6, lean=True)
    length = 3.7
    widths = (0.66, 0.5)

    def half(v):
        return widths[0] + (widths[1] - widths[0]) * v / length

    b.tapered(base, (-0.05, length + 0.05), (half(0) + 0.08, half(length) + 0.08), (-0.08, 0.04), DARK)
    sections = 6
    for index in range(sections):
        v0 = length * index / sections + 0.015
        v1 = length * (index + 1) / sections - 0.015
        width = half((v0 + v1) / 2)
        cushion(b, base, -width, width, v0, v1, 0.03, 0.29, PADDING, round=0.08)
    cushion(b, base, -half(length) + 0.1, half(length) - 0.1, length - 0.62, length - 0.14, 0.27, 0.42, PADDING, round=0.07)
    for side in (-1, 1):
        start = geometry.at(base, side * (half(0) + 0.1), -0.08, 0.16)
        end = geometry.at(base, side * (half(length) + 0.1), length + 0.08, 0.16)
        bar(b, start, end, 0.07, 0.07, METAL, up=base.w)
        for v in (0.15, length / 2, length - 0.15):
            u = side * (half(v) + 0.1)
            slab(b, base, u - 0.06, u + 0.06, v - 0.08, v + 0.08, -0.1, 0.12, DARK, chamfer=0.02)
            bolt(b, geometry.at(base, u, v - 0.04, 0.12), base.w, 0.022)
    for v in (0.0, length):
        bar(b, geometry.at(base, -half(v) - 0.1, v, 0.1), geometry.at(base, half(v) + 0.1, v, 0.1), 0.06, 0.06, METAL, up=base.w)
    for index, v in enumerate((0.55, 1.4, 2.25, 3.0)):
        width = half(v) + 0.037
        b.box(base, (-width, width), (v - 0.065, v + 0.065), (0.29, 0.315), ORANGE)
        for side in (-1, 1):
            edge = half(v) + 0.025
            b.box(base, (side * edge - 0.012, side * edge + 0.012), (v - 0.065, v + 0.065), (0.03, 0.29), ORANGE)
        buckle(b, base, half(v) * (0.35 if index % 2 else -0.3), v, 0.315, 0.16, 0.16)
    slab(b, base, -0.48, 0.48, length + 0.1, length + 0.3, -0.06, 0.1, DARK, chamfer=0.03)
    cushion(b, base, -0.42, 0.42, length + 0.12, length + 0.28, 0.1, 0.2, PADDING, round=0.04)


# Pipes and cables -----------------------------------------------------------------------


def wall_points(path, offset):
    return [wall(theta, z).origin + wall(theta, z).w * offset for theta, z in path]


PIPE_RUNS = (
    # Up the wall from the oxygen niche to the ceiling ring.
    (((68, 3.3), (68, 4.6), (62, 6.0)), 0.12, 0.06, ORANGE),
    (((83, 3.3), (83, 4.6), (88, 6.0)), 0.12, 0.05, METAL),
    # Along the knee behind the chair and round the back.
    (((190, 2.45), (205, 2.45), (220, 2.45), (235, 2.45), (250, 2.45)), 0.1, 0.06, PADDING),
    # From the bed's corner up to the ceiling.
    (((340, 2.8), (340, 4.6), (345, 6.0)), 0.1, 0.05, METAL),
    # Cable bundles from the screen bank up into the ceiling.
    (((97, 3.3), (97, 5.0), (93, 6.05)), 0.07, 0.035, BLACK),
    (((99, 3.3), (99, 5.0), (95, 6.05)), 0.07, 0.025, ORANGE),
    (((128, 3.4), (128, 5.0), (132, 6.05)), 0.07, 0.035, BLACK),
    (((126.2, 3.4), (126.2, 5.0), (130.2, 6.05)), 0.07, 0.025, BLACK),
    # A cable along the knee beside the airlock.
    (((25, 2.36), (37, 2.36), (50, 2.36)), 0.06, 0.025, BLACK),
)


def pipes():
    return [kit.pipe(wall_points(path, offset), radius, material, sides=8, bend=0.15) for path, offset, radius, material in PIPE_RUNS]


def pipe_clamps(b):
    """Saddle clamps holding every run to the wall, bolted on both sides."""
    for path, offset, radius, material in PIPE_RUNS:
        if radius < 0.03 and path[0][0] in (99, 126.2):
            continue
        for (theta0, z0), (theta1, z1) in zip(path, path[1:]):
            steps = max(1, int(math.hypot((theta1 - theta0) * 0.07, z1 - z0) / 0.6))
            for step in range(steps):
                t = (step + 0.5) / steps
                theta, z = theta0 + (theta1 - theta0) * t, z0 + (z1 - z0) * t
                if z > 5.35:
                    continue
                frame = wall(theta, z)
                along_u = abs(theta1 - theta0) * 0.07 > abs(z1 - z0)
                reach = radius + 0.035
                if along_u:
                    slab(b, frame, -0.03, 0.03, -reach, reach, -0.03, offset + radius + 0.015, DARK, chamfer=0.01)
                else:
                    slab(b, frame, -reach, reach, -0.03, 0.03, -0.03, offset + radius + 0.015, DARK, chamfer=0.01)


# The outside --------------------------------------------------------------------------


def exterior(b):
    """Ribs and rivets on the hull panels, scorch streaks, the top can
    with its antennas, thruster blocks and the outer porthole rims."""
    for index in range(SEGMENTS):
        theta = math.degrees(PHASE) + index * 15
        if abs(((theta + 180) % 360) - 180) < 20:
            low = 4.6
        else:
            low = 0.5
        start = max(low, OUTER_KNEE + 0.15)
        frame = hull_wall(theta, start, facet=False)
        length = (OUTER_TOP - 0.2 - start) * math.sqrt(1 + SLOPE * SLOPE)
        b.box(frame, (-0.06, 0.06), (0.0, length), (-0.05, 0.05), DARK)
        for step in range(int(length / 2.2)):
            b.rivet(geometry.at(frame, 0, 0.8 + step * 2.2, 0.05), frame.w, 0.045, METAL)
    for theta, z in PORTHOLES:
        inner = wall(theta, z)
        outer_point = inner.origin - inner.w * 0.4 * FACET / math.sqrt(1 + SLOPE * SLOPE)
        b.washer(outer_point, -inner.w, PORTHOLE_RADIUS - 0.03, 0.58, 0.07, 6, METAL, phase=0.0)
    random = kit.model_random(type("Model", (), {"model": "pod"})(), "scorch")
    for index in range(20):
        theta = index * 18.0 + 4.0 + random.uniform(-5, 5)
        if abs(((theta + 180) % 360) - 180) < 22:
            continue
        frame = hull_wall(theta, 0.45)
        b.tapered(frame, (0.0, random.uniform(0.9, 1.7)), (random.uniform(0.4, 0.62), random.uniform(0.1, 0.25)), (-0.02, 0.012), BLACK)
        if index % 3 == 0:
            lean = hull_wall(theta + random.uniform(-3, 3), OUTER_KNEE + 0.05)
            b.tapered(lean, (0.0, random.uniform(0.8, 1.8)), (random.uniform(0.3, 0.45), 0.08), (-0.02, 0.012), BLACK)
    # The top can, its lid and the antennas.
    b.cylinder((0, 0, OUTER_TOP - 0.05), (0, 0, OUTER_TOP + 0.45), 1.75, 12, DARK, phase=math.pi / 12)
    b.washer((0, 0, OUTER_TOP + 0.45), Z, 1.2, 1.75, 0.08, 12, METAL, phase=math.pi / 12)
    b.cylinder((0, 0, OUTER_TOP + 0.45), (0, 0, OUTER_TOP + 0.6), 1.15, 12, METAL, phase=math.pi / 12)
    for index in range(8):
        angle = 2 * math.pi * (index + 0.5) / 8
        b.rivet((1.48 * math.cos(angle), 1.48 * math.sin(angle), OUTER_TOP + 0.53), Z, 0.04, METAL)
    b.cylinder((0.8, 0.7, OUTER_TOP + 0.6), (0.8, 0.7, OUTER_TOP + 3.0), 0.05, 6, METAL)
    b.cylinder((0.8, 0.7, OUTER_TOP + 0.6), (0.8, 0.7, OUTER_TOP + 0.9), 0.12, 6, DARK)
    b.box(Frame(Vector((0.8, 0.7, OUTER_TOP + 3.0)), X, Y, Z), (-0.05, 0.05), (-0.05, 0.05), (0.0, 0.1), AMBER)
    b.cylinder((-0.7, -0.6, OUTER_TOP + 0.6), (-0.7, -0.6, OUTER_TOP + 1.4), 0.06, 6, METAL)
    b.cylinder((-0.7, -0.6, OUTER_TOP + 1.25), (-0.7, -0.6, OUTER_TOP + 1.45), 0.55, 10, METAL, end_radius=0.1)
    b.box(Frame(Vector((-0.9, 0.6, OUTER_TOP + 0.6)), X, Y, Z), (-0.03, 0.03), (-0.3, 0.3), (0.0, 0.9), DARK)
    # Thruster blocks round the cone.
    for theta in (45, 135, 225, 315):
        frame = hull_wall(theta, 5.0)
        b.box(frame, (-0.35, 0.35), (-0.3, 0.3), (-0.1, 0.22), DARK)
        for u, v in ((-0.18, 0.0), (0.18, 0.0)):
            start = geometry.at(frame, u, v, 0.22)
            b.cylinder(start, start + frame.w * 0.15, 0.08, 6, BLACK, end_radius=0.12)
    # The fairing's face round the outer door: bolts, hazard lamps.
    face = Frame(Vector((5.0, 0, 0)), Y, Z, X)
    for side in (-1, 1):
        for z in (0.3, 1.0, 1.7, 2.4, 3.1, 3.8):
            b.rivet(geometry.at(face, side * 1.35, z, 0.0), X, 0.04, METAL)
    b.box(face, (-1.1, 1.1), (2.2, 2.32), (-0.02, 0.02), AMBER)
    b.box(face, (-1.4, 1.4), (2.45, 3.9), (0.0, 0.04), DARK)
    for u in (-1.25, -0.42, 0.42, 1.25):
        for v in (2.6, 3.75):
            b.rivet(geometry.at(face, u, v, 0.04), X, 0.045, METAL)
    b.box(face, (-1.4, 1.4), (3.12, 3.22), (0.04, 0.06), METAL)


def build(machine):
    kit.expect_footprint(machine, 12, 12, 8)
    volumes = hull_objects()
    inside = interior_builder()
    for part, name in (
        (porthole_frames, "porthole frames"), (desk, "desk"), (lower_walls, "lower walls"), (upper_walls, "upper walls"),
        (lean_ribs, "ribs"), (ceiling, "ceiling"), (overhead_lamp, "overhead lamp"), (desk_lamp, "desk lamp"),
        (floor, "floor"), (airlock_details, "airlock face"), (niches, "niches"),
        (keypad_console, "keypad console"), (bed, "bed"), (pipe_clamps, "pipe clamps"),
    ):
        inside.tag = name
        part(inside)
    seat = geometry.Builder([(name, low, high, None) for name, (low, high) in {**POCKETS, **OPEN_CELLS}.items()], inside_hull)
    seat.tag = "chair"
    chair(seat)
    drum = geometry.Builder([(name, low, high, None) for name, (low, high) in OPEN_CELLS.items()])
    drum.tag = "bore"
    bore_ribs(drum)
    outside = geometry.Builder()
    outside.tag = "exterior"
    exterior(outside)
    for warning in inside.warnings + seat.warnings + drum.warnings:
        print("WARNING", warning)
    for builder in (inside, seat, drum, outside):
        for tag, count in sorted(builder.triangles.items(), key=lambda item: -item[1]):
            print(f"TRIANGLES {tag}: {count}")
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for index, item in enumerate(volumes):
        evaluated = bpy.data.meshes.new_from_object(item.evaluated_get(depsgraph))
        print(f"TRIANGLES volume {index}: {sum(len(polygon.vertices) - 2 for polygon in evaluated.polygons)}")
        bpy.data.meshes.remove(evaluated)
    pipe_objects = pipes()
    print(f"TRIANGLES pipes: {sum(sum(len(polygon.vertices) - 2 for polygon in item.data.polygons) for item in pipe_objects)}")
    volumes += inside.objects() + seat.objects() + drum.objects() + outside.objects() + pipe_objects
    body = kit.join(volumes, "body")
    for name, count in sorted(HELPER_TRIANGLES.items(), key=lambda item: -item[1]):
        print(f"HELPER {name}: {count}")
    audit(body)
    audit_coplanar(body)
    records = inside.records + seat.records + drum.records
    pairs = geometry.coplanar_pairs(records)
    print(f"COPLANAR pieces: {len(pairs)} overlapping label pairs")
    for centre, first, second in sorted(pairs, key=lambda item: (item[1], item[2])):
        print("COPLANAR piece", centre, first, "|", second)
    geometry.print_emissive(body)
    # The two lamps, in the OBJ file's frame (Blender x, y, z is x, z, -y):
    # the lens face's centre and the suggested point light just below it.
    head, axis = desk_lamp_pose()
    for name, face, light in (
        ("overhead strip", overhead_lamp_face(), overhead_lamp_face() - Z * 0.25),
        ("desk light", desk_lamp_face(), desk_lamp_face() + axis * 0.25),
    ):
        print(f"LAMP {name}: face ({face.x:.3f}, {face.z:.3f}, {-face.y:.3f}) light ({light.x:.3f}, {light.z:.3f}, {-light.y:.3f})")


def triangles_overlap(first, second, margin=0.005):
    """Two triangles in a plane overlap by more than margin (2D separating
    axes on their edges)."""
    for triangle in (first, second):
        for index in range(3):
            ax, ay = triangle[index]
            bx, by = triangle[(index + 1) % 3]
            nx, ny = by - ay, ax - bx
            length = math.hypot(nx, ny)
            if length < 1e-9:
                continue
            nx, ny = nx / length, ny / length
            one = [x * nx + y * ny for x, y in first]
            two = [x * nx + y * ny for x, y in second]
            if min(max(one), max(two)) - max(min(one), min(two)) < margin:
                return False
    return True


def audit_coplanar(body):
    """Pairs of same facing triangles in one plane (within 0.006 cells)
    that overlap, over the whole body (triangles bucketed by normal and
    plane offset), and pod triangles lying on the door frames' outer
    faces: the surfaces that would fight for depth in the game."""
    mesh = body.data
    mesh.calc_loop_triangles()
    buckets = {}
    triangles = []
    for triangle in mesh.loop_triangles:
        corners = [Vector(mesh.vertices[index].co) for index in triangle.vertices]
        normal = (corners[1] - corners[0]).cross(corners[2] - corners[0])
        if normal.length < 1e-9:
            continue
        normal.normalize()
        if normal.z < -0.99 and max(c.z for c in corners) < 0.01:
            continue
        name = f"{mesh.materials[mesh.polygons[triangle.polygon_index].material_index].name}#{triangle.polygon_index}"
        index = len(triangles)
        triangles.append((corners, normal, name))
        key = (round(normal.x * 20), round(normal.y * 20), round(normal.z * 20), round(normal.dot(corners[0]) / 0.006))
        buckets.setdefault(key, []).append(index)
    pairs = set()
    for key, members in buckets.items():
        candidates = []
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for dd in (-1, 0, 1):
                        candidates += buckets.get((key[0] + dx, key[1] + dy, key[2] + dz, key[3] + dd), [])
        for first_index in members:
            first, normal, first_name = triangles[first_index]
            low = [min(c[axis] for c in first) for axis in range(3)]
            high = [max(c[axis] for c in first) for axis in range(3)]
            for second_index in candidates:
                if second_index <= first_index:
                    continue
                second, other, second_name = triangles[second_index]
                if normal.dot(other) < 0.999 or abs(normal.dot(second[0] - first[0])) > 0.006:
                    continue
                if any(min(c[axis] for c in second) > high[axis] + 1e-4 or max(c[axis] for c in second) < low[axis] - 1e-4 for axis in range(3)):
                    continue
                axis = max(range(3), key=lambda a: abs(normal[a]))
                plane = [a for a in range(3) if a != axis]
                if triangles_overlap([(c[plane[0]], c[plane[1]]) for c in first], [(c[plane[0]], c[plane[1]]) for c in second]):
                    pairs.add((tuple(round(value, 2) for value in sum(first, Vector()) / 3), tuple(round(value, 2) for value in sum(second, Vector()) / 3), tuple(round(value, 2) for value in normal), first_name.split("#")[0], second_name.split("#")[0]))
    frames = 0
    for x0 in (1.0, 4.0):
        for corners, normal, _ in triangles:
            for axis, value in ((1, -1.0), (1, 1.0), (2, 2.0), (0, x0), (0, x0 + 1.0)):
                if all(abs(c[axis] - value) < 0.005 for c in corners):
                    inside = all(x0 - 0.005 <= c[0] <= x0 + 1.005 and -1.005 <= c[1] <= 1.005 and -0.005 <= c[2] <= 2.005 for c in corners)
                    if inside:
                        frames += 1
                        print("COPLANAR frame face", tuple(round(value, 2) for value in sum(corners, Vector()) / 3))
    print(f"COPLANAR {len(pairs)} overlapping pairs, {frames} triangles on the door frames' faces")
    for place in sorted(pairs):
        print("COPLANAR at", place)


def audit(body):
    """Every triangle of the finished body against the cells it must
    leave empty (the free cells, the door boxes, the pockets), each shrunk
    by 0.02 cells as the game tests them."""
    boxes = {**OPEN_CELLS, **POCKETS, "inner shutter slot": INNER_SLOT, "outer shutter slot": OUTER_SLOT}
    found = {name: 0 for name in boxes}
    mesh = body.data
    mesh.calc_loop_triangles()
    for polygon in mesh.loop_triangles:
        corners = [mesh.vertices[index].co for index in polygon.vertices]
        low = [min(corner[axis] for corner in corners) for axis in range(3)]
        high = [max(corner[axis] for corner in corners) for axis in range(3)]
        for name, (minimum, maximum) in boxes.items():
            if not all(low[axis] < maximum[axis] - 0.02 and high[axis] > minimum[axis] + 0.02 for axis in range(3)):
                continue
            centre = Vector([(minimum[axis] + maximum[axis]) / 2 for axis in range(3)])
            half = [(maximum[axis] - minimum[axis]) / 2 - 0.02 for axis in range(3)]
            for step in range(1, len(corners) - 1):
                if geometry.triangle_box_overlap((Vector(corners[0]), Vector(corners[step]), Vector(corners[step + 1])), centre, half):
                    found[name] += 1
                    if found[name] <= 3:
                        print(f"AUDIT {name}: a triangle near {tuple(round(value, 2) for value in polygon.center)}")
                    break
    print("AUDIT " + ", ".join(f"{name} {count}" for name, count in found.items()))
