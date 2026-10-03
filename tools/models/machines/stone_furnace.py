"""The stone furnace: a tapered rubble stone stack in a riveted iron
frame, a rust brown hood on its roof, the firebox mouth on the front
(+X), a dirty white console bolted to the left face (-Y), pipes on the
back left and a small panel on the right face (+Y).

Most volumes are written straight into one bmesh per material (Parts),
every face oriented away from its solid's interior, then handed to the
kit as objects and joined with the kit's pipes and cylinders.
"""

import math

import bmesh
from mathutils import Vector

from .. import kit

BASE_HALF = 4.0           # the stone wall's half width at the ground
TAPER = 0.06              # the half width lost per unit of height
WALL_TOP = 9.6            # where the top band starts
BAND_TOP = 10.6           # the roof
BLOCK_TOP = 2.3           # the corner base blocks
BLOCK_INNER = 2.45
BLOCK_OUTER = 4.45
POST_WIDTH = 0.72
FACE_ANGLES = {"+X": 0.0, "+Y": 90.0, "-X": 180.0, "-Y": 270.0}

STONE = "furnace_stone"
MORTAR = "furnace_mortar"
IRON = "furnace_iron"
RUST = "furnace_rust"
CONSOLE = "console_white"
FIRE = "heat_glow"
SCREEN = "electric_glow"
SIGNAL = "signal_glow"


def half(z):
    return BASE_HALF - TAPER * z


def rotate(face, vector):
    angle = math.radians(FACE_ANGLES[face])
    cosine, sine = math.cos(angle), math.sin(angle)
    return Vector((vector.x * cosine - vector.y * sine, vector.x * sine + vector.y * cosine, vector.z))


def face_normal(face):
    return rotate(face, Vector((1.0, 0.0, TAPER)).normalized())


def face_point(face, u, z, d=0.0):
    """The point at u across and z up the sloped wall face, d out of it."""
    length = math.sqrt(1.0 + TAPER * TAPER)
    local = Vector((half(z) + d / length, u, z + d * TAPER / length))
    return rotate(face, local)


class Parts:
    """One bmesh per material."""

    def __init__(self):
        self.meshes = {}

    def mesh(self, material_name):
        if material_name not in self.meshes:
            self.meshes[material_name] = bmesh.new()
        return self.meshes[material_name]

    def faces(self, material_name, polygons, interior):
        """Adds the polygons, each turned to face away from interior."""
        mesh = self.mesh(material_name)
        for polygon in polygons:
            points = [Vector(point) for point in polygon]
            normal = newell_normal(points)
            centre = sum(points, Vector()) / len(points)
            if normal.dot(centre - Vector(interior)) < 0:
                points.reverse()
            mesh.faces.new([mesh.verts.new(point) for point in points])

    def solid(self, material_name, bottom, top, open_bottom=False):
        """A prism between two polygons of the same count; open_bottom
        leaves out the bottom polygon where it lies against a wall."""
        self.loft(material_name, [bottom, top], open_bottom)

    def loft(self, material_name, rings, open_bottom=False):
        """A closed solid through rings of the same count, the first and
        last capped (the first not when open_bottom)."""
        rings = [[Vector(point) for point in ring] for ring in rings]
        interior = sum((point for ring in rings for point in ring), Vector()) / sum(len(ring) for ring in rings)
        polygons = [rings[-1]] if open_bottom else [rings[0], rings[-1]]
        count = len(rings[0])
        for lower, upper in zip(rings, rings[1:]):
            for index in range(count):
                following = (index + 1) % count
                polygons.append([lower[index], lower[following], upper[following], upper[index]])
        self.faces(material_name, polygons, interior)

    def tube(self, material_name, points, radius, sides=4):
        """An uncapped tube along the points, its ends buried in what it
        connects; its rings carried along the path so they never twist."""
        points = [Vector(point) for point in points]
        rings = []
        first = None
        for index, point in enumerate(points):
            before = points[max(index - 1, 0)]
            after = points[min(index + 1, len(points) - 1)]
            tangent = (after - before).normalized()
            if first is None:
                first, _ = tangent_basis(tangent)
            first = (first - tangent * first.dot(tangent)).normalized()
            second = tangent.cross(first)
            rings.append([point + (first * math.cos(angle) + second * math.sin(angle)) * radius
                          for angle in (2 * math.pi * (side + 0.5) / sides for side in range(sides))])
        for ring_index, (lower, upper) in enumerate(zip(rings, rings[1:])):
            centre = (points[ring_index] + points[ring_index + 1]) / 2
            for index in range(sides):
                following = (index + 1) % sides
                self.faces(material_name, [[lower[index], lower[following], upper[following], upper[index]]], centre)

    def pipe(self, material_name, corners, radius, bend, sides=8):
        """A round pipe through the corners with bent elbows (the kit's
        arc points), uncapped: both ends go into something."""
        self.tube(material_name, kit.pipe_arc_points(corners, bend), radius, sides)

    def box(self, material_name, minimum, maximum):
        (x0, y0, z0), (x1, y1, z1) = minimum, maximum
        self.solid(material_name, [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)],
                   [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)])

    def decal(self, material_name, corners, normal):
        """One flat polygon facing normal."""
        centre = sum((Vector(point) for point in corners), Vector()) / len(corners)
        self.faces(material_name, [corners], centre - Vector(normal))

    def lathe(self, material_name, profile, sides, rotation=0.0):
        """A surface of revolution about Z through the (radius, z)
        profile, faces turned to the outside of the profile's direction
        (up the outside, in across a top, down an inside)."""
        mesh = self.mesh(material_name)
        angles = [rotation + 2 * math.pi * index / sides for index in range(sides)]
        rings = [[mesh.verts.new((radius * math.cos(angle), radius * math.sin(angle), z)) for angle in angles]
                 for radius, z in profile]
        for lower, upper in zip(rings, rings[1:]):
            for index in range(sides):
                following = (index + 1) % sides
                mesh.faces.new((lower[index], lower[following], upper[following], upper[index]))

    def objects(self):
        return [kit.mesh_object("parts", mesh, name, 0.0) for name, mesh in self.meshes.items()]


def newell_normal(points):
    normal = Vector()
    for index, point in enumerate(points):
        following = points[(index + 1) % len(points)]
        normal.x += (point.y - following.y) * (point.z + following.z)
        normal.y += (point.z - following.z) * (point.x + following.x)
        normal.z += (point.x - following.x) * (point.y + following.y)
    return normal


def tangent_basis(normal):
    normal = Vector(normal).normalized()
    helper = Vector((0, 0, 1)) if abs(normal.z) < 0.9 else Vector((1, 0, 0))
    first = helper.cross(normal).normalized()
    second = normal.cross(first)
    return first, second


def rivet(parts, centre, normal, size=0.09, material_name=IRON):
    """A low three sided pyramid: a rivet head that catches the light."""
    first, second = tangent_basis(normal)
    centre = Vector(centre)
    base = [centre + (first * math.cos(angle) + second * math.sin(angle)) * size
            for angle in (math.pi / 2, math.pi / 2 + 2 * math.pi / 3, math.pi / 2 + 4 * math.pi / 3)]
    apex = centre + Vector(normal).normalized() * size * 0.75
    polygons = [[base[index], base[(index + 1) % 3], apex] for index in range(3)]
    parts.faces(material_name, polygons, centre - Vector(normal))


def disc_prism(parts, material_name, centre, normal, radius, height, sides=6, top_scale=0.8, open_bottom=False):
    """A short n sided button or knob standing on a surface."""
    first, second = tangent_basis(normal)
    normal = Vector(normal).normalized()
    centre = Vector(centre)
    bottom, top = [], []
    for index in range(sides):
        angle = 2 * math.pi * (index + 0.5) / sides
        offset = first * math.cos(angle) + second * math.sin(angle)
        bottom.append(centre + offset * radius - normal * 0.02)
        top.append(centre + offset * radius * top_scale + normal * height)
    parts.solid(material_name, bottom, top, open_bottom)


def face_slab(parts, material_name, face, outline, d0, d1):
    """A plate on a sloped wall face: outline in (u, z), from d0 to d1."""
    parts.solid(material_name, [face_point(face, u, z, d0) for u, z in outline],
                [face_point(face, u, z, d1) for u, z in outline], open_bottom=True)


def face_bar(parts, material_name, face, start, end, width, d0, d1):
    """A straight bar on the face from start to end in (u, z)."""
    (u0, z0), (u1, z1) = start, end
    length = math.hypot(u1 - u0, z1 - z0)
    across_u, across_z = -(z1 - z0) / length * width / 2, (u1 - u0) / length * width / 2
    outline = [(u0 - across_u, z0 - across_z), (u1 - across_u, z1 - across_z),
               (u1 + across_u, z1 + across_z), (u0 + across_u, z0 + across_z)]
    face_slab(parts, material_name, face, outline, d0, d1)


# The wall ------------------------------------------------------------------

def core(parts):
    """The mortar body under the stones, a tapered square, as a kit
    object so the firebox can be cut into it."""
    mesh = bmesh.new()
    bottom = [mesh.verts.new((sx * half(0), sy * half(0), 0.0)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    top = [mesh.verts.new((sx * half(WALL_TOP + 0.2), sy * half(WALL_TOP + 0.2), WALL_TOP + 0.2)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    mesh.faces.new(bottom[::-1])
    mesh.faces.new(top)
    for index in range(4):
        following = (index + 1) % 4
        mesh.faces.new((bottom[index], bottom[following], top[following], top[index]))
    bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
    return kit.mesh_object("core", mesh, MORTAR, 0.0)


def free_spans(low, high, blocked):
    """[low, high] minus the blocked (u0, u1) spans."""
    spans = [(low, high)]
    for block_low, block_high in sorted(blocked):
        next_spans = []
        for span_low, span_high in spans:
            if block_high <= span_low or block_low >= span_high:
                next_spans.append((span_low, span_high))
                continue
            if block_low > span_low:
                next_spans.append((span_low, block_low))
            if block_high < span_high:
                next_spans.append((block_high, span_high))
        spans = next_spans
    return [(span_low, span_high) for span_low, span_high in spans if span_high - span_low > 0.45]


def stone(parts, face, u0, u1, z0, z1, random, slant_low=0.0, slant_high=0.0):
    """One rubble stone: a hipped mound on an irregular quad, its ridge
    along the longer side at a drawn height, so its four facets catch
    the light differently from its neighbours'. The slants lean its
    side joints (the top corner's offset from the bottom one)."""
    jitter = 0.1
    corners = [(u0, z0), (u1, z0), (u1 + slant_high, z1), (u0 + slant_low, z1)]
    b0, b1, b2, b3 = [face_point(face, u + random.uniform(-jitter, jitter), z + random.uniform(-jitter, jitter), -0.03)
                      for u, z in corners]
    u0, u1 = u0 + slant_low / 2, u1 + slant_high / 2
    width, height = u1 - u0, z1 - z0
    centre_u = (u0 + u1) / 2 + random.uniform(-0.1, 0.1) * width
    centre_z = (z0 + z1) / 2 + random.uniform(-0.12, 0.12) * height
    lift0, lift1 = random.uniform(0.13, 0.27), random.uniform(0.13, 0.27)
    if width >= height:
        reach = height * random.uniform(0.3, 0.45)
        r0 = face_point(face, u0 + reach, centre_z, lift0)
        r1 = face_point(face, u1 - reach, centre_z, lift1)
        polygons = [[b0, b1, r1, r0], [b1, b2, r1], [b2, b3, r0, r1], [b3, b0, r0]]
    else:
        reach = width * random.uniform(0.3, 0.45)
        r0 = face_point(face, centre_u, z0 + reach, lift0)
        r1 = face_point(face, centre_u, z1 - reach, lift1)
        polygons = [[b0, b1, r0], [b1, b2, r1, r0], [b2, b3, r1], [b3, b0, r0, r1]]
    parts.faces(STONE, polygons, face_point(face, (u0 + u1) / 2, (z0 + z1) / 2, -1.0))


def stone_wall(parts, face, keepouts, random, z_start=0.08, z_end=WALL_TOP - 0.05):
    """Courses of rubble stones over the face, around the keepouts
    ((u0, u1, z0, z1) rectangles) and inside the corner posts."""
    gap = 0.11
    z = z_start
    stagger = 0.0
    while z < z_end - 0.35:
        course = random.uniform(0.72, 1.0)
        z_top = min(z + course, z_end)
        if z_end - z_top < 0.35:
            z_top = z_end
        edge = BLOCK_INNER - 0.05 if z < BLOCK_TOP else half(z_top) - POST_WIDTH + 0.02
        blocked = [(u0, u1) for u0, u1, k0, k1 in keepouts if k0 < z_top and k1 > z]
        for low, high in free_spans(-edge, edge, blocked):
            u = low
            first = True
            slant = 0.0
            while u < high - 0.3:
                width = random.uniform(0.8, 2.0)
                if first:
                    width *= 0.45 + 0.5 * stagger
                    first = False
                end = min(u + width, high)
                if high - end < 0.5:
                    end = high
                next_slant = 0.0 if end >= high else random.uniform(-0.28, 0.28)
                stone(parts, face, u + gap / 2, end - gap / 2, z + gap / 2, z_top - gap / 2, random, slant, next_slant)
                slant = next_slant
                u = end
        stagger = random.random()
        z = z_top


def corner_frame(parts):
    """The iron L angles up the four edges, the corner base blocks, the
    diagonal braces under the top band, and their rivets."""
    for face in FACE_ANGLES:
        normal = face_normal(face)
        for side in (-1, 1):
            outline = []
            for z in (BLOCK_TOP, WALL_TOP + 0.1):
                inner, outer = half(z) - POST_WIDTH, half(z) + 0.24
                outline += [(side * inner, z), (side * outer, z)]
            outline = [outline[0], outline[1], outline[3], outline[2]]
            face_slab(parts, IRON, face, outline, -0.02, 0.24)
            z = BLOCK_TOP + 0.45
            while z < WALL_TOP - 0.3:
                rivet(parts, face_point(face, side * (half(z) - 0.42), z, 0.24), normal)
                z += 1.6
            # The diagonal brace from the post into the top band.
            top_half = half(WALL_TOP)
            brace = [(side * (top_half - POST_WIDTH + 0.05), WALL_TOP - 1.55), (side * (top_half - POST_WIDTH + 0.05), WALL_TOP - 0.75),
                     (side * (top_half - 1.65), WALL_TOP + 0.05), (side * (top_half - 2.45), WALL_TOP + 0.05)]
            face_slab(parts, IRON, face, brace, -0.02, 0.2)
    for sx in (-1, 1):
        for sy in (-1, 1):
            corner_block(parts, sx, sy)


def corner_block(parts, sx, sy):
    """A heavy riveted iron block under a post, its top chamfered."""
    outline = [(BLOCK_INNER, BLOCK_INNER), (BLOCK_OUTER, BLOCK_INNER), (BLOCK_OUTER, BLOCK_OUTER), (BLOCK_INNER, BLOCK_OUTER)]
    bottom = [(sx * x, sy * y, 0.0) for x, y in outline]
    middle = [(sx * x, sy * y, BLOCK_TOP - 0.3) for x, y in outline]
    shrink = [(BLOCK_INNER, BLOCK_INNER), (BLOCK_OUTER - 0.25, BLOCK_INNER), (BLOCK_OUTER - 0.25, BLOCK_OUTER - 0.25), (BLOCK_INNER, BLOCK_OUTER - 0.25)]
    top = [(sx * x, sy * y, BLOCK_TOP) for x, y in shrink]
    parts.loft(IRON, [bottom, middle, top], open_bottom=True)
    for along in (BLOCK_INNER + 0.4, BLOCK_OUTER - 0.4):
        for z in (BLOCK_TOP - 0.65,):
            rivet(parts, (sx * BLOCK_OUTER, sy * along, z), (sx, 0, 0), 0.11)
            rivet(parts, (sx * along, sy * BLOCK_OUTER, z), (0, sy, 0), 0.11)


def top_band(parts):
    """The iron band round the top of the wall, the roof plate, and the
    chunky riveted caps on the four corners."""
    low, high = half(WALL_TOP) + 0.26, half(BAND_TOP) + 0.26
    corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    parts.solid(IRON, [(sx * low, sy * low, WALL_TOP) for sx, sy in corners],
                [(sx * high, sy * high, BAND_TOP) for sx, sy in corners])
    plate = high - 0.45
    parts.box(IRON, (-plate, -plate, BAND_TOP - 0.05), (plate, plate, BAND_TOP + 0.1))
    for face in FACE_ANGLES:
        normal = face_normal(face)
        for u in (-1.2, 1.2):
            rivet(parts, face_point(face, u, WALL_TOP + 0.5, 0.27), normal, 0.08)
    for sx, sy in corners:
        cap_low, cap_high = half(WALL_TOP - 0.5) + 0.4, high + 0.18
        size = 1.25

        def outline(edge, z):
            inner = edge - size
            return [(sx * inner, sy * inner, z), (sx * edge, sy * inner, z), (sx * edge, sy * (edge - 0.35), z),
                    (sx * (edge - 0.35), sy * edge, z), (sx * inner, sy * edge, z)]
        parts.solid(IRON, outline(cap_low, WALL_TOP - 0.5), outline(cap_high, BAND_TOP + 0.3), open_bottom=True)
        rivet(parts, (sx * (cap_high - 0.4), sy * (cap_high - 0.8), BAND_TOP + 0.3), (0, 0, 1), 0.1)
        rivet(parts, (sx * (cap_high - 0.8), sy * (cap_high - 0.4), BAND_TOP + 0.3), (0, 0, 1), 0.1)
        for z in (WALL_TOP - 0.05, BAND_TOP - 0.15):
            rivet(parts, (sx * (cap_high - 0.02 + 0.03), sy * (cap_high - 0.85), z), (sx, 0, 0.0), 0.1)
            rivet(parts, (sx * (cap_high - 0.85), sy * (cap_high - 0.02 + 0.03), z), (0, sy, 0.0), 0.1)


# The firebox --------------------------------------------------------------

MOUTH_INNER = [(-1.5, 2.8), (1.5, 2.8), (1.5, 5.25), (1.0, 5.8), (-1.0, 5.8), (-1.5, 5.25)]
MOUTH_OUTER = [(-2.35, 2.8), (2.35, 2.8), (2.35, 5.95), (1.65, 6.75), (-1.65, 6.75), (-2.35, 5.95)]
MOUTH_REVEAL = [(-1.85, 2.8), (1.85, 2.8), (1.85, 5.45), (1.25, 6.15), (-1.25, 6.15), (-1.85, 5.45)]
MOUTH_BACK = 1.9


def mouth_cutter():
    mesh = bmesh.new()
    back = [mesh.verts.new((MOUTH_BACK, u, z - (0.05 if z < 3 else 0.0))) for u, z in MOUTH_INNER]
    front = [mesh.verts.new((5.0, u, z - (0.05 if z < 3 else 0.0))) for u, z in MOUTH_INNER]
    mesh.faces.new(back[::-1])
    mesh.faces.new(front)
    for index in range(len(back)):
        following = (index + 1) % len(back)
        mesh.faces.new((back[index], back[following], front[following], front[index]))
    bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
    return kit.mesh_object("mouth", mesh, MORTAR, 0.0)


def mouth(parts, random):
    """The chamfered iron frame round the opening, the hearth ledge, the
    glowing coal bed, the coals and the flames against the dark back."""
    front_x, back_x = 4.32, 3.3
    count = len(MOUTH_INNER)
    for index in range(count):
        following = (index + 1) % count
        outer, outer_next = MOUTH_OUTER[index], MOUTH_OUTER[following]
        inner, inner_next = MOUTH_INNER[index], MOUTH_INNER[following]
        reveal, reveal_next = MOUTH_REVEAL[index], MOUTH_REVEAL[following]
        if index == 0:
            continue  # the bottom edge rests on the ledge
        back = [outer, outer_next, inner_next, inner]
        front = [outer, outer_next, reveal_next, reveal]
        parts.solid(IRON, [(back_x, u, z) for u, z in back], [(front_x, u, z) for u, z in front], open_bottom=True)
    # A raised lip on the frame's face, and rivets on the jambs.
    for side in (-1, 1):
        for z in (3.4, 4.5, 5.5):
            rivet(parts, (front_x, side * 2.1, z), (1, 0, 0), 0.1)
    for u in (-0.8, 0.0, 0.8):
        rivet(parts, (front_x, u, 6.45), (1, 0, 0), 0.1)
    # The hearth ledge: a thick slab with a chamfered front.
    ledge = [(3.2, 2.0), (4.6, 2.0), (4.75, 2.25), (4.75, 2.62), (4.6, 2.8), (3.2, 2.8)]
    parts.solid(STONE, [(x, -2.7, z) for x, z in ledge], [(x, 2.7, z) for x, z in ledge])
    parts.box(IRON, (4.62, -2.75, 2.28), (4.8, 2.75, 2.58))
    for u in (-2.2, -0.75, 0.75, 2.2):
        rivet(parts, (4.8, u, 2.43), (1, 0, 0), 0.08)
    # The coal bed glows; dark coals and flames on it.
    parts.box(FIRE, (MOUTH_BACK + 0.02, -1.48, 2.72), (3.6, 1.48, 2.86))
    for index in range(6):
        x = random.uniform(2.2, 3.7)
        u = random.uniform(-1.25, 1.25)
        size = random.uniform(0.16, 0.3)
        material_name = MORTAR if index % 3 else RUST
        rivet(parts, (x, u, 2.84), (random.uniform(-0.3, 0.3), random.uniform(-0.3, 0.3), 1), size, material_name)
    # Flames: a jagged glowing sheet against the dark back wall, and
    # three free tongues standing nearer the mouth.
    outline = [(-1.45, 2.86)]
    tongues = 7
    for index in range(tongues):
        low_u = -1.45 + 2.9 * index / tongues
        tip_u = low_u + 2.9 / tongues * random.uniform(0.35, 0.65)
        centre_weight = 1.0 - abs(tip_u) / 1.6
        outline.append((low_u + 0.05, 3.3 + random.uniform(0.0, 0.5) * centre_weight))
        outline.append((tip_u, 3.9 + random.uniform(0.6, 1.4) * centre_weight))
    outline += [(1.4, 3.3), (1.45, 2.86)]
    parts.decal(FIRE, [(MOUTH_BACK + 0.03, u, z) for u, z in outline], (1, 0, 0))
    for u, height in ((-0.6, 1.3), (0.15, 1.8), (0.85, 1.1)):
        x = MOUTH_BACK + 0.8 + random.uniform(-0.2, 0.2)
        blade = [(x, u - 0.28, 2.85), (x, u + 0.25, 2.85), (x, u + 0.1, 2.85 + height * 0.55),
                 (x, u + random.uniform(-0.2, 0.2), 2.85 + height), (x, u - 0.18, 2.85 + height * 0.45)]
        parts.decal(FIRE, blade, (1, 0, 0))


# The console --------------------------------------------------------------

CONSOLE_X = (-1.55, 2.35)
CONSOLE_PROFILE = [(-3.45, 0.0), (-4.92, 0.0), (-4.92, 2.55), (-4.42, 3.65), (-4.42, 5.55), (-3.45, 5.55)]


def console(parts):
    """The dirty white console on the left face: a desk with a sloped
    button deck under an upright screen panel, two light bars, a lever
    and the kick recess at its foot."""
    x0, x1 = CONSOLE_X
    body = [(x0 + 0.12, y, z) for y, z in CONSOLE_PROFILE]
    parts.solid(CONSOLE, body, [(x1 - 0.12, y, z) for y, z in CONSOLE_PROFILE])
    # The thicker cheeks at both ends.
    cheek = [(-3.45, 0.0), (-4.98, 0.0), (-4.98, 2.6), (-4.5, 3.72), (-4.5, 5.65), (-3.45, 5.65)]
    for start, end in ((x0, x0 + 0.16), (x1 - 0.16, x1)):
        parts.solid(CONSOLE, [(start, y, z) for y, z in cheek], [(end, y, z) for y, z in cheek])
    front = Vector((0, -1, 0))
    # The kick recess at the foot: a dark chamfered plate set in.
    recess = [(-0.6, 0.0), (1.4, 0.0), (1.4, 0.95), (1.15, 1.2), (-0.35, 1.2), (-0.6, 0.95)]
    parts.solid(MORTAR, [(x, -4.93, z) for x, z in recess], [(x, -4.96, z) for x, z in recess])
    parts.box(CONSOLE, (-0.72, -5.0, 1.2), (1.52, -4.9, 1.32))
    # The light bars.
    parts.decal(SCREEN, [(x0 + 0.3, -4.935, 2.2), (x1 - 0.3, -4.935, 2.2), (x1 - 0.3, -4.935, 2.36), (x0 + 0.3, -4.935, 2.36)], front)
    parts.box(IRON, (x0 + 0.24, -4.95, 2.14), (x0 + 0.3, -4.9, 2.42))
    parts.decal(SCREEN, [(x0 + 0.3, -4.435, 5.2), (x1 - 0.3, -4.435, 5.2), (x1 - 0.3, -4.435, 5.36), (x0 + 0.3, -4.435, 5.36)], front)
    # The big screen and its graph.
    parts.box(IRON, (-1.2, -4.47, 4.15), (0.1, -4.4, 4.95))
    parts.decal(MORTAR, [(-1.1, -4.475, 4.24), (0.0, -4.475, 4.24), (0.0, -4.475, 4.86), (-1.1, -4.475, 4.86)], front)
    graph = [(-1.0, 4.35), (-0.7, 4.5), (-0.5, 4.42), (-0.25, 4.68), (-0.08, 4.75)]
    screen_line(parts, graph, -4.48)
    # The small screen.
    parts.box(IRON, (1.25, -4.47, 4.2), (2.0, -4.4, 4.65))
    parts.decal(MORTAR, [(1.31, -4.475, 4.26), (1.94, -4.475, 4.26), (1.94, -4.475, 4.59), (1.31, -4.475, 4.59)], front)
    screen_line(parts, [(1.36, 4.32), (1.55, 4.46), (1.7, 4.38), (1.88, 4.53)], -4.48)
    # The row of lights.
    for index, material_name in enumerate((SIGNAL, FIRE, FIRE, SCREEN, SIGNAL)):
        rivet(parts, (0.35 + index * 0.33, -4.43, 4.82), front, 0.12, material_name)
    # Two small knobs and two sliders under the lights.
    for z in (4.3, 4.55):
        rivet(parts, (0.35, -4.43, z), front, 0.08)
    for x in (0.7, 0.92):
        parts.decal(MORTAR, [(x - 0.03, -4.43, 4.2), (x + 0.03, -4.43, 4.2), (x + 0.03, -4.43, 4.62), (x - 0.03, -4.43, 4.62)], front)
        parts.box(IRON, (x - 0.07, -4.52, 4.35), (x + 0.07, -4.42, 4.45))
    # The sloped deck.
    deck_normal = Vector((0, -1.1, 0.5)).normalized()

    def deck_point(x, t, lift=0.0):
        """t runs 0 at the front edge to 1 at the back edge of the deck."""
        point = Vector((x, -4.92 + 0.5 * t, 2.55 + 1.1 * t))
        return point + deck_normal * lift
    buttons = [(-1.15, 0.25, FIRE), (-0.8, 0.3, CONSOLE), (-1.15, 0.6, SIGNAL), (-0.8, 0.65, SCREEN), (-1.15, 0.9, FIRE)]
    for x, t, material_name in buttons:
        disc_prism(parts, material_name, deck_point(x, t), deck_normal, 0.15, 0.1, 5, 0.75, open_bottom=True)
    # Toggle switches with a red one.
    for x, t, material_name in ((-0.45, 0.45, FIRE), (-0.2, 0.55, SCREEN)):
        corners = [deck_point(x - 0.09, t - 0.12, 0.0), deck_point(x + 0.09, t - 0.12, 0.0),
                   deck_point(x + 0.09, t + 0.12, 0.0), deck_point(x - 0.09, t + 0.12, 0.0)]
        parts.solid(material_name, corners, [point + deck_normal * 0.12 for point in corners])
    # Two small deck screens.
    for x_low, x_high, t_low, t_high in ((0.05, 0.75, 0.55, 0.88), (0.05, 0.6, 0.12, 0.38)):
        corners = [deck_point(x_low, t_low, 0.01), deck_point(x_high, t_low, 0.01), deck_point(x_high, t_high, 0.01), deck_point(x_low, t_high, 0.01)]
        parts.solid(IRON, [deck_point(x_low - 0.05, t_low - 0.05, -0.02), deck_point(x_high + 0.05, t_low - 0.05, -0.02),
                           deck_point(x_high + 0.05, t_high + 0.05, -0.02), deck_point(x_low - 0.05, t_high + 0.05, -0.02)],
                    [point + deck_normal * 0.02 for point in [deck_point(x_low - 0.05, t_low - 0.05), deck_point(x_high + 0.05, t_low - 0.05),
                                                              deck_point(x_high + 0.05, t_high + 0.05), deck_point(x_low - 0.05, t_high + 0.05)]])
        parts.decal(SCREEN if t_low > 0.5 else FIRE, [point + deck_normal * 0.025 for point in corners], deck_normal)
    # The lever: a slotted quadrant, an arm and a rust brown grip.
    quadrant = [deck_point(1.15, 0.28), deck_point(1.75, 0.28), deck_point(1.75, 0.95), deck_point(1.15, 0.95)]
    parts.solid(IRON, quadrant, [point + deck_normal * 0.18 for point in quadrant])
    pivot = deck_point(1.45, 0.4, 0.18)
    grip = pivot + Vector((0, 0.1, 0.9))
    arm = [pivot + Vector((-0.06, 0, 0)), pivot + Vector((0.06, 0, 0)), pivot + Vector((0.06, 0.08, 0.04)), pivot + Vector((-0.06, 0.08, 0.04))]
    parts.solid(IRON, arm, [point + (grip - pivot) for point in arm])
    parts.solid(RUST, [grip + Vector((-0.32, -0.1, -0.1)), grip + Vector((0.32, -0.1, -0.1)), grip + Vector((0.32, 0.1, -0.1)), grip + Vector((-0.32, 0.1, -0.1))],
                [grip + Vector((-0.32, -0.1, 0.1)), grip + Vector((0.32, -0.1, 0.1)), grip + Vector((0.32, 0.1, 0.1)), grip + Vector((-0.32, 0.1, 0.1))])
    # Rivets on the console's corners and the bracket the pipe stands on.
    for x in (x0 + 0.3, x1 - 0.3):
        for z in (0.35, 1.7):
            rivet(parts, (x, -4.93, z), front, 0.07)
        rivet(parts, (x, -4.5, 3.9), front, 0.07)
    parts.box(IRON, (-1.25, -4.55, 5.55), (0.55, -3.5, 5.8))
    parts.solid(IRON, [(-1.0, -3.9, 5.8), (0.3, -3.9, 5.8), (0.3, -3.6, 5.8), (-1.0, -3.6, 5.8)],
                [(-1.0, -3.9, 6.6), (0.3, -3.9, 6.6), (0.3, -3.6, 6.6), (-1.0, -3.6, 6.6)])
    for x in (-1.05, 0.35):
        rivet(parts, (x, -4.3, 5.8), (0, 0, 1), 0.12)


def screen_line(parts, points, y):
    """A glowing graph trace: thin quads between the points (x, z)."""
    for (x0, z0), (x1, z1) in zip(points, points[1:]):
        parts.decal(SCREEN, [(x0, y, z0 - 0.025), (x1, y, z1 - 0.025), (x1, y, z1 + 0.025), (x0, y, z0 + 0.025)], (0, -1, 0))


# Pipes, cables and the hood -------------------------------------------------

def collar(objects, centre, axis, radius, length):
    start = {"X": centre[0], "Y": centre[1], "Z": centre[2]}[axis] - length / 2
    other = {"X": (centre[1], centre[2]), "Y": (centre[0], centre[2]), "Z": (centre[0], centre[1])}[axis]
    objects.append(kit.cylinder(other, start, start + length, radius, 6, IRON, axis=axis))


def pipes(parts, objects):
    """The thick pipe rising from the console into the wall, the down
    pipe at the back left corner, the tall stack pipe with its goose
    neck, and the flanges where they meet the stone."""
    # Console riser: up from the bracket, elbow into the left face.
    parts.pipe(RUST, [(-0.35, -4.2, 5.75), (-0.35, -4.2, 8.55), (-0.35, -3.2, 8.55)], 0.42, 0.75)
    collar(objects, (-0.35, -4.2, 6.35), "Z", 0.52, 0.45)
    face_slab(parts, IRON, "-Y", [(-1.25, 7.65), (0.55, 7.65), (0.55, 9.45), (-1.25, 9.45)], -0.02, 0.18)
    for x in (-1.05, 0.35):
        for z in (7.85, 9.25):
            rivet(parts, face_point("-Y", x, z, 0.18), face_normal("-Y"), 0.09)
    collar(objects, (-0.35, -3.95, 8.55), "Y", 0.55, 0.22)
    # Down pipe at the back left: out of the left face, down into the
    # corner block.
    parts.pipe(RUST, [(-3.15, -3.3, 8.3), (-3.15, -4.52, 8.3), (-3.15, -4.52, 2.0)], 0.36, 0.6)
    collar(objects, (-3.15, -3.85, 8.3), "Y", 0.5, 0.2)
    collar(objects, (-3.15, -4.52, 5.6), "Z", 0.44, 0.3)
    collar(objects, (-3.15, -4.52, BLOCK_TOP + 0.08), "Z", 0.46, 0.25)
    face_slab(parts, IRON, "-Y", [(-3.25, 7.6), (-2.55, 7.6), (-2.55, 9.0), (-3.25, 9.0)], -0.02, 0.16)
    # The tall stack pipe on the roof's back left with its goose neck.
    parts.pipe(RUST, [(-3.3, -1.75, BAND_TOP), (-3.3, -1.75, 14.4), (-4.45, -1.75, 14.4), (-4.45, -1.75, 13.75)], 0.3, 0.5)
    objects.append(kit.cylinder((-3.3, -1.75), BAND_TOP, BAND_TOP + 0.35, 0.55, 6, IRON))
    collar(objects, (-3.3, -1.75, 12.3), "Z", 0.4, 0.3)
    collar(objects, (-4.45, -1.75, 13.8), "Z", 0.38, 0.15)
    # A capped port on the roof.
    objects.append(kit.cylinder((-2.15, -2.9), BAND_TOP, BAND_TOP + 0.5, 0.38, 6, IRON))


def cables(parts):
    """Three hoses from the console's front cheek round the corner to a
    socket beside the mouth, sagging in front of the corner block."""
    paths = [
        [(2.4, -4.3, 3.55), (2.75, -4.65, 2.75), (3.4, -4.72, 2.65), (4.25, -4.35, 3.4), (4.45, -3.3, 4.55)],
        [(2.4, -4.3, 3.25), (2.8, -4.7, 2.45), (3.5, -4.78, 2.4), (4.35, -4.4, 3.15), (4.52, -3.3, 4.35)],
        [(2.4, -4.3, 2.95), (2.85, -4.75, 2.2), (3.55, -4.85, 2.12), (4.45, -4.45, 2.9), (4.58, -3.3, 4.15)],
    ]
    for index, path in enumerate(paths):
        parts.tube(RUST if index == 2 else MORTAR, path, 0.08)


def cable_sockets(parts):
    parts.box(IRON, (2.35, -4.45, 2.75), (2.5, -4.15, 3.75))
    parts.box(IRON, (4.25, -3.45, 3.9), (4.5, -2.65, 4.9))


def hood(parts, objects, random):
    """The rust brown hood on the roof: a riveted collar, a tapering
    skirt with plate seams, a rim, and the stone lined throat."""
    sides = 16
    rotation = math.pi / sides
    skirt = [(3.2, BAND_TOP - 0.05), (3.2, BAND_TOP + 0.95), (2.88, BAND_TOP + 1.12), (2.36, 14.2)]
    parts.lathe(RUST, skirt, sides, rotation)
    rim = [(2.38, 14.1), (2.52, 14.25), (2.52, 14.55), (1.9, 14.55), (1.9, 13.6)]
    parts.lathe(IRON, rim, sides, rotation)
    hole = [Vector((1.2 * math.cos(2 * math.pi * index / 10), 1.2 * math.sin(2 * math.pi * index / 10), 13.62)) for index in range(10)]
    parts.decal(MORTAR, hole, (0, 0, 1))
    for index in range(12):
        angle = 2 * math.pi * (index + 0.5) / 12
        direction = Vector((math.cos(angle), math.sin(angle), 0.0))
        rivet(parts, direction * 3.13 + Vector((0, 0, BAND_TOP + 0.48)), direction, 0.1)
    # Plate seams down the skirt.
    for index in range(4):
        angle = 2 * math.pi * index / 4 + 0.45
        direction = Vector((math.cos(angle), math.sin(angle), 0.0))
        side = Vector((-direction.y, direction.x, 0.0)) * 0.07
        low = direction * 2.86 + Vector((0, 0, BAND_TOP + 1.15))
        high = direction * 2.37 + Vector((0, 0, 14.1))
        parts.solid(IRON, [low - side, low + side, high + side, high - side],
                    [low - side + direction * 0.07, low + side + direction * 0.07, high + side + direction * 0.07, high - side + direction * 0.07], open_bottom=True)
    # The throat: a ring of fire stones round a dark hole.
    count = 8
    for index in range(count):
        angle0 = 2 * math.pi * index / count + 0.03
        angle1 = 2 * math.pi * (index + 1) / count - 0.03
        inner, outer = 1.15, 1.88
        bottom = [Vector((radius * math.cos(angle), radius * math.sin(angle), 13.3)) for radius, angle in ((inner, angle0), (outer, angle0), (outer, angle1), (inner, angle1))]
        top = [Vector((point.x, point.y, 14.0 + random.uniform(-0.12, 0.08))) for point in bottom]
        centre = sum(top, Vector()) / 4
        top = [point + (centre - point) * 0.12 for point in top]
        parts.solid(STONE, bottom, top, open_bottom=True)


# The right face -------------------------------------------------------------

def right_box(parts):
    """An iron ash box low on the right face, a small panel on its top."""
    outline = [(4.05, 0.0), (4.7, 0.0), (4.7, 2.6), (4.35, 3.1), (3.6, 3.1)]
    parts.solid(IRON, [(-1.7, y, z) for y, z in outline], [(1.7, y, z) for y, z in outline])
    for x in (-1.4, 1.4):
        for z in (0.4, 2.2):
            rivet(parts, (x, 4.7, z), (0, 1, 0), 0.1)
    # A clean out hatch with a handle.
    parts.box(IRON, (-0.9, 4.7, 0.6), (0.9, 4.8, 1.9))
    parts.box(RUST, (-0.5, 4.8, 1.55), (0.5, 4.92, 1.68))
    # The small panel on the slope: a screen and two lights.
    normal = Vector((0, 0.5, 0.35)).normalized()
    plate = [(-1.2, 4.65, 2.68), (0.9, 4.65, 2.68), (0.9, 4.38, 3.06), (-1.2, 4.38, 3.06)]
    parts.solid(CONSOLE, plate, [Vector(point) + normal * 0.06 for point in plate])
    screen = [(-1.0, 4.6, 2.78), (-0.1, 4.6, 2.78), (-0.1, 4.45, 2.98), (-1.0, 4.45, 2.98)]
    parts.decal(SCREEN, [Vector(point) + normal * 0.07 for point in screen], normal)
    for x, material_name in ((0.25, SIGNAL), (0.6, FIRE)):
        rivet(parts, Vector((x, 4.53, 2.87)) + normal * 0.06, normal, 0.1, material_name)


def conduits(parts):
    """Thin iron conduits along the upper wall, stepping as in the
    sheet."""
    front = [(-2.6, 7.7), (0.4, 7.7), (0.95, 7.2), (2.6, 7.2)]
    for start, end in zip(front, front[1:]):
        face_bar(parts, IRON, "+X", start, end, 0.13, 0.12, 0.32)
    back = [(2.5, 8.2), (-0.5, 8.2), (-1.1, 7.6), (-2.5, 7.6)]
    for start, end in zip(back, back[1:]):
        face_bar(parts, IRON, "-X", start, end, 0.13, 0.12, 0.32)
    right = [(-2.5, 6.9), (2.5, 6.9)]
    face_bar(parts, IRON, "+Y", right[0], right[1], 0.13, 0.12, 0.32)


def triangle_total(parts, objects):
    """The triangles so far, for the budget print."""
    import bpy
    total = sum(len(face.verts) - 2 for mesh in parts.meshes.values() for face in mesh.faces)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for source in objects:
        evaluated = source.evaluated_get(depsgraph).to_mesh()
        total += sum(len(polygon.vertices) - 2 for polygon in evaluated.polygons)
        source.evaluated_get(depsgraph).to_mesh_clear()
    return total


def build(machine):
    kit.expect_footprint(machine, 10, 10, 12)
    random = kit.model_random(machine, "stones")
    details = kit.model_random(machine, "details")
    parts = Parts()
    objects = []
    wall = core(parts)
    kit.cut(wall, mouth_cutter())
    objects.append(wall)
    keepouts = {
        "+X": [(-2.45, 2.45, 1.9, 6.85)],
        "-Y": [(-1.6, 2.4, 0.0, 5.7), (-1.3, 0.6, 5.7, 9.5)],
        "+Y": [(-1.8, 1.8, 0.0, 3.15)],
        "-X": [],
    }
    stages = [
        ("stones", lambda: [stone_wall(parts, face, rectangles, random) for face, rectangles in keepouts.items()]),
        ("frame", lambda: corner_frame(parts)),
        ("band", lambda: top_band(parts)),
        ("mouth", lambda: mouth(parts, details)),
        ("console", lambda: console(parts)),
        ("pipes", lambda: pipes(parts, objects)),
        ("cables", lambda: (cables(parts), cable_sockets(parts))),
        ("hood", lambda: hood(parts, objects, details)),
        ("right", lambda: right_box(parts)),
        ("conduits", lambda: conduits(parts)),
    ]
    previous = triangle_total(parts, objects)
    print(f"budget core {previous}")
    for name, stage in stages:
        stage()
        total = triangle_total(parts, objects)
        print(f"budget {name} {total - previous}")
        previous = total
    objects += parts.objects()
    kit.join(objects, "body")
