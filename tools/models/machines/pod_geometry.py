"""Mesh building for the pod and its airlock door: pieces gathered per
material into one bmesh each (so hundreds of rivets and boxes stay a
handful of objects), in arbitrary frames (a wall panel, a tilted screen,
a reclined chair back), plus the guards the pod's script checks its
pieces against (the pockets and the walkable cells it must leave
empty)."""

import collections
import math

import bmesh
import bpy
from mathutils import Vector

from .. import kit

Frame = collections.namedtuple("Frame", "origin u v w")

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))
WORLD = Frame(Vector((0, 0, 0)), X, Y, Z)

# The six faces of a hexahedron whose corner i + 2j + 4k sits at u side
# i, v side j, w side k.
HEXA_FACES = ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))


def at(frame, u, v, w):
    """The point (u, v, w) of the frame."""
    return frame.origin + frame.u * u + frame.v * v + frame.w * w


def perpendiculars(axis):
    """Two unit vectors making a right handed frame with axis."""
    helper = Z if abs(axis.dot(Z)) < 0.9 else X
    first = axis.cross(helper).normalized()
    return first, axis.cross(first).normalized()


def turned(frame, degrees, about="w"):
    """The frame turned by degrees about one of its own axes."""
    angle = math.radians(degrees)
    c, s = math.cos(angle), math.sin(angle)
    u, v, w = frame.u, frame.v, frame.w
    if about == "w":
        return Frame(frame.origin, u * c + v * s, v * c - u * s, w)
    if about == "u":
        return Frame(frame.origin, u, v * c + w * s, w * c - v * s)
    return Frame(frame.origin, u * c - w * s, v, w * c + u * s)


def moved(frame, u=0.0, v=0.0, w=0.0):
    return Frame(at(frame, u, v, w), frame.u, frame.v, frame.w)


def triangle_box_overlap(triangle, centre, half):
    """The separating axis test of a triangle against an axis aligned box
    (centre, half sizes)."""
    corners = [point - centre for point in triangle]
    edges = [corners[1] - corners[0], corners[2] - corners[1], corners[0] - corners[2]]
    axes = [X, Y, Z, edges[0].cross(edges[1])]
    axes += [axis.cross(edge) for axis in (X, Y, Z) for edge in edges]
    for axis in axes:
        if axis.length_squared < 1e-12:
            continue
        projections = [corner.dot(axis) for corner in corners]
        reach = half[0] * abs(axis.x) + half[1] * abs(axis.y) + half[2] * abs(axis.z)
        if min(projections) > reach or max(projections) < -reach:
            return False
    return True


def orient_outward(mesh, faces):
    """Consistent winding, then the whole piece flipped when its signed
    volume says it points inward (recalc alone can pick the wrong side of
    a thin hollow shell)."""
    bmesh.ops.recalc_face_normals(mesh, faces=faces)
    volume = 0.0
    for face in faces:
        corners = [vertex.co for vertex in face.verts]
        for index in range(1, len(corners) - 1):
            volume += corners[0].dot(corners[index].cross(corners[index + 1]))
    if volume < 0:
        bmesh.ops.reverse_faces(mesh, faces=faces)


class Builder:
    """Pieces per material. guard_boxes are (name, minimum, maximum,
    floor_allowed): a piece whose box enters one is reported, unless it
    lies on the floor (its top below floor_allowed) where that is
    allowed."""

    def __init__(self, guard_boxes=(), envelope=None):
        self.meshes = {}
        self.guard_boxes = list(guard_boxes)
        self.envelope = envelope
        self.warnings = []
        self.tag = ""
        self.label = ""
        self.triangles = collections.Counter()
        # (corners, normal, label) of every face, for the coplanar audit.
        self.records = []

    def record(self, face):
        face.normal_update()
        self.records.append(([Vector(vertex.co) for vertex in face.verts], Vector(face.normal), f"{self.tag}/{self.label}"))

    def mesh(self, material):
        if material not in self.meshes:
            self.meshes[material] = bmesh.new()
        return self.meshes[material]

    def check(self, points, faces):
        low = [min(point[index] for point in points) for index in range(3)]
        high = [max(point[index] for point in points) for index in range(3)]
        for name, minimum, maximum, floor_allowed in self.guard_boxes:
            near = all(low[index] < maximum[index] - 0.02 and high[index] > minimum[index] + 0.02 for index in range(3))
            if not near or (floor_allowed is not None and high[2] <= floor_allowed):
                continue
            centre = Vector([(minimum[index] + maximum[index]) / 2 for index in range(3)])
            half = [(maximum[index] - minimum[index]) / 2 - 0.02 for index in range(3)]
            for face in faces:
                corners = [Vector(points[index]) for index in face]
                if any(triangle_box_overlap((corners[0], corners[step], corners[step + 1]), centre, half) for step in range(1, len(corners) - 1)):
                    self.warnings.append(f"{self.tag}: enters {name} ({tuple(round(value, 2) for value in low)} to {tuple(round(value, 2) for value in high)})")
                    break
        if self.envelope is not None:
            for point in points:
                if not self.envelope(point):
                    self.warnings.append(f"{self.tag}: leaves the hull at {tuple(round(value, 2) for value in point)}")
                    break

    def closed(self, material, points, faces):
        self.check(points, faces)
        mesh = self.mesh(material)
        vertices = [mesh.verts.new(point) for point in points]
        created = [mesh.faces.new([vertices[index] for index in face]) for face in faces]
        orient_outward(mesh, created)
        for face in created:
            self.record(face)
        self.triangles[self.tag] += sum(len(face) - 2 for face in faces)

    def convex(self, material, points, faces):
        """A convex piece, open or closed: each face turned away from the
        piece's centre, so a piece may leave out a face nobody sees."""
        self.check(points, faces)
        mesh = self.mesh(material)
        vertices = [mesh.verts.new(point) for point in points]
        centre = sum((Vector(point) for point in points), Vector()) / len(points)
        for face in faces:
            created = mesh.faces.new([vertices[index] for index in face])
            created.normal_update()
            if created.normal.dot(created.calc_center_median() - centre) < 0:
                created.normal_flip()
            self.record(created)
        self.triangles[self.tag] += sum(len(face) - 2 for face in faces)

    def hexa(self, corners, material, skip=()):
        """skip names faces left out: w0 the back (the first w), w1, v0,
        v1, u0, u1."""
        names = ("w0", "w1", "v0", "v1", "u0", "u1")
        self.convex(material, corners, [face for name, face in zip(names, HEXA_FACES) if name not in skip])

    def box(self, frame, u_range, v_range, w_range, material, skip=()):
        corners = [at(frame, u, v, w) for w in w_range for v in v_range for u in u_range]
        self.hexa(corners, material, skip)

    def abox(self, minimum, maximum, material, skip=()):
        """skip "w0" leaves out the bottom."""
        self.box(WORLD, (minimum[0], maximum[0]), (minimum[1], maximum[1]), (minimum[2], maximum[2]), material, skip)

    def tapered(self, frame, v_range, half_widths, w_range, material, u_centre=0.0, skip=()):
        """A slab whose width (2 * half_width) runs from the first v to
        the second: a tapered mattress pad."""
        corners = []
        for w in w_range:
            for v, half in zip(v_range, half_widths):
                for side in (-1, 1):
                    corners.append(at(frame, u_centre + side * half, v, w))
        self.hexa(corners, material, skip)

    def cylinder(self, start, end, radius, sides, material, end_radius=None, phase=0.0, open_start=False):
        """A capped cylinder (a frustum with end_radius) from start to end;
        open_start leaves out the cap at start."""
        start, end = Vector(start), Vector(end)
        axis = (end - start).normalized()
        first, second = perpendiculars(axis)
        points = []
        for centre, ring_radius in ((start, radius), (end, radius if end_radius is None else end_radius)):
            for index in range(sides):
                angle = phase + 2 * math.pi * index / sides
                points.append(centre + (first * math.cos(angle) + second * math.sin(angle)) * ring_radius)
        faces = ([] if open_start else [tuple(range(sides))]) + [tuple(range(sides, 2 * sides))]
        for index in range(sides):
            following = (index + 1) % sides
            faces.append((index, following, sides + following, sides + index))
        self.convex(material, points, faces)

    def washer(self, centre, axis, inner, outer, depth, sides, material, phase=0.0):
        """A flat ring from centre along axis by depth."""
        centre, axis = Vector(centre), Vector(axis).normalized()
        first, second = perpendiculars(axis)
        profile = ((outer, 0.0), (outer, depth), (inner, depth), (inner, 0.0))
        points = []
        for radius, offset in profile:
            for index in range(sides):
                angle = phase + 2 * math.pi * index / sides
                points.append(centre + axis * offset + (first * math.cos(angle) + second * math.sin(angle)) * radius)
        faces = []
        for ring in range(4):
            following_ring = (ring + 1) % 4
            for index in range(sides):
                following = (index + 1) % sides
                faces.append((ring * sides + index, ring * sides + following, following_ring * sides + following, following_ring * sides + index))
        self.closed(material, points, faces)

    def prism(self, frame, polygon, w_range, material):
        """The (u, v) polygon extruded along w."""
        count = len(polygon)
        points = [at(frame, u, v, w) for w in w_range for u, v in polygon]
        faces = [tuple(range(count)), tuple(range(count, 2 * count))]
        for index in range(count):
            following = (index + 1) % count
            faces.append((index, following, count + following, count + index))
        self.closed(material, points, faces)

    def rivet(self, point, normal, size, material, height=None):
        """A four sided pyramid standing on the surface: 4 triangles."""
        point, normal = Vector(point), Vector(normal).normalized()
        first, second = perpendiculars(normal)
        base = [point + (first * math.cos(angle) + second * math.sin(angle)) * size for angle in (0.0, math.pi / 2, math.pi, 1.5 * math.pi)]
        apex = point + normal * (size * 0.7 if height is None else height)
        self.check([*base, apex], ((0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)))
        self.triangles[self.tag] += 4
        mesh = self.mesh(material)
        vertices = [mesh.verts.new(corner) for corner in base]
        top = mesh.verts.new(apex)
        for index in range(4):
            face = mesh.faces.new((vertices[index], vertices[(index + 1) % 4], top))
            face.normal_update()
            centre = (base[index] + base[(index + 1) % 4] + apex) / 3
            if face.normal.dot(centre - point) < 0:
                face.normal_flip()
            self.record(face)

    def directed(self, material, points, faces, normals):
        """Faces each turned to agree with its expected normal: for open
        sweeps whose centre test would pick the wrong side."""
        self.check(points, faces)
        mesh = self.mesh(material)
        vertices = [mesh.verts.new(point) for point in points]
        for face, expected in zip(faces, normals):
            created = mesh.faces.new([vertices[index] for index in face])
            created.normal_update()
            if created.normal.dot(expected) < 0:
                created.normal_flip()
            self.record(created)
        self.triangles[self.tag] += sum(len(face) - 2 for face in faces)

    def sweep_rect(self, frame, u, v, half_u, half_v, profile, material, cap=None, cap_start=None):
        """A rectangle centred at (u, v) on the frame swept through the
        profile's (offset, w) points: ring k has the half sizes grown by
        its offset and stands at its w. The faces between rings face away
        from the material, which lies to the right of the profile walked
        in order (outward offsets, front w). cap closes the last ring with
        a face toward +w, cap_start the first toward -w, each in its own
        material (None leaves it open)."""
        signs = ((1, -1), (1, 1), (-1, 1), (-1, -1))
        outward = (frame.u, frame.v, -frame.u, -frame.v)
        points = []
        for offset, w in profile:
            for su, sv in signs:
                points.append(at(frame, u + su * (half_u + offset), v + sv * (half_v + offset), w))
        faces, normals = [], []
        for ring in range(len(profile) - 1):
            d_offset = profile[ring + 1][0] - profile[ring][0]
            d_w = profile[ring + 1][1] - profile[ring][1]
            for side in range(4):
                following = (side + 1) % 4
                faces.append((ring * 4 + side, ring * 4 + following, (ring + 1) * 4 + following, (ring + 1) * 4 + side))
                normals.append(outward[side] * d_w - frame.w * d_offset)
        self.directed(material, points, faces, normals)
        last = (len(profile) - 1) * 4
        if cap:
            self.directed(cap, points[last:last + 4], [(0, 1, 2, 3)], [frame.w])
        if cap_start:
            self.directed(cap_start, points[:4], [(0, 1, 2, 3)], [-frame.w])

    def lathe(self, centre, axis, profile, sides, material, cap=None, cap_start=None, phase=0.0):
        """The (radius, w) profile turned about axis through centre, the
        same conventions as sweep_rect: the material to the right of the
        profile, cap toward +axis on the last ring, cap_start toward
        -axis on the first."""
        centre, axis = Vector(centre), Vector(axis).normalized()
        first, second = perpendiculars(axis)
        directions = [first * math.cos(phase + 2 * math.pi * index / sides) + second * math.sin(phase + 2 * math.pi * index / sides) for index in range(sides)]
        points = [centre + axis * w + direction * radius for radius, w in profile for direction in directions]
        faces, normals = [], []
        for ring in range(len(profile) - 1):
            d_radius = profile[ring + 1][0] - profile[ring][0]
            d_w = profile[ring + 1][1] - profile[ring][1]
            for index in range(sides):
                following = (index + 1) % sides
                faces.append((ring * sides + index, ring * sides + following, (ring + 1) * sides + following, (ring + 1) * sides + index))
                middle = (directions[index] + directions[following]).normalized()
                normals.append(middle * d_w - axis * d_radius)
        self.directed(material, points, faces, normals)
        last = (len(profile) - 1) * sides
        if cap:
            self.directed(cap, points[last:last + sides], [tuple(range(sides))], [axis])
        if cap_start:
            self.directed(cap_start, points[:sides], [tuple(range(sides))], [-axis])

    def quad(self, frame, u0, u1, v0, v1, w, material):
        """A single sided rectangle facing +w (a scan line on a screen)."""
        points = [at(frame, u0, v0, w), at(frame, u1, v0, w), at(frame, u1, v1, w), at(frame, u0, v1, w)]
        self.directed(material, points, [(0, 1, 2, 3)], [frame.w])

    def objects(self):
        return [kit.mesh_object("detail", mesh, material, 0.0) for material, mesh in sorted(self.meshes.items())]


def revolve(profile, segments, phase, material, inner_material=None):
    """A closed solid of the (r, z) profile turned about Z: a point with
    r 0 is one vertex on the axis. With inner_material, the shells nested
    inside the outermost one (a hollow's lining) take that material."""
    mesh = bmesh.new()
    rings = []
    for radius, height in profile:
        if radius == 0:
            rings.append([mesh.verts.new((0, 0, height))])
        else:
            rings.append([
                mesh.verts.new((radius * math.cos(phase + 2 * math.pi * index / segments), radius * math.sin(phase + 2 * math.pi * index / segments), height))
                for index in range(segments)
            ])
    for index in range(len(rings)):
        this, following = rings[index], rings[(index + 1) % len(rings)]
        if len(this) == 1 and len(following) == 1:
            continue
        for step in range(segments):
            after = (step + 1) % segments
            if len(this) == 1:
                mesh.faces.new((this[0], following[after], following[step]))
            elif len(following) == 1:
                mesh.faces.new((this[step], this[after], following[0]))
            else:
                mesh.faces.new((this[step], this[after], following[after], following[step]))
    inner_faces = orient_shells(mesh)
    if inner_material is not None:
        for face in inner_faces:
            face.material_index = 1
    created = kit.mesh_object("revolve", mesh, material, 0.0)
    if inner_material is not None:
        created.data.materials.append(kit.material(inner_material))
    return created


def signed_volume(faces):
    volume = 0.0
    for face in faces:
        corners = [vertex.co for vertex in face.verts]
        for index in range(1, len(corners) - 1):
            volume += corners[0].dot(corners[index].cross(corners[index + 1]))
    return volume


def orient_shells(mesh):
    """A hollow solid of nested closed shells: the outermost faces out,
    the shells inside it face into the hollow."""
    mesh.faces.ensure_lookup_table()
    remaining = set(mesh.faces)
    shells = []
    while remaining:
        seed = remaining.pop()
        shell, stack = {seed}, [seed]
        while stack:
            face = stack.pop()
            for edge in face.edges:
                for other in edge.link_faces:
                    if other in remaining:
                        remaining.discard(other)
                        shell.add(other)
                        stack.append(other)
        shells.append(list(shell))
    for shell in shells:
        bmesh.ops.recalc_face_normals(mesh, faces=shell)
    volumes = [signed_volume(shell) for shell in shells]
    largest = max(range(len(shells)), key=lambda index: abs(volumes[index]))
    for index, shell in enumerate(shells):
        wanted = 1 if index == largest else -1
        if volumes[index] * wanted < 0:
            bmesh.ops.reverse_faces(mesh, faces=shell)
    return [face for index, shell in enumerate(shells) if index != largest for face in shell]


def cutter(build):
    """A throwaway Builder's pieces as one object, for kit.cut."""
    builder = Builder()
    build(builder)
    mesh = bmesh.new()
    for piece in builder.meshes.values():
        temporary = bpy.data.meshes.new("cutter")
        piece.to_mesh(temporary)
        mesh.from_mesh(temporary)
        bpy.data.meshes.remove(temporary)
        piece.free()
    return kit.mesh_object("cutter", mesh, "pod_black", 0.0)


def emissive_patches(body, merge=0.45):
    """The emissive surfaces of a finished object as patches: connected
    pieces per glowing material, pieces closer than merge (cells, centroid
    to centroid, single linkage) joined. Each patch is (material, its area
    weighted centroid in the OBJ file's frame (Blender x, y, z exports as
    x, z, -y), pieces, extent in the file's frame, area)."""
    mesh = body.data
    mesh.calc_loop_triangles()
    glowing = {index for index, material in enumerate(mesh.materials) if material and material.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value > 0}
    parent = {}

    def find(vertex):
        while parent.setdefault(vertex, vertex) != vertex:
            parent[vertex] = parent[parent[vertex]]
            vertex = parent[vertex]
        return vertex

    triangles = []
    for triangle in mesh.loop_triangles:
        material_index = mesh.polygons[triangle.polygon_index].material_index
        if material_index not in glowing:
            continue
        corners = [Vector(mesh.vertices[index].co) for index in triangle.vertices]
        area = (corners[1] - corners[0]).cross(corners[2] - corners[0]).length / 2
        first = find(triangle.vertices[0])
        for vertex in triangle.vertices[1:]:
            parent[find(vertex)] = first
        triangles.append((material_index, triangle.vertices[0], corners, area))
    pieces = {}
    for material_index, vertex, corners, area in triangles:
        key = (material_index, find(vertex))
        piece = pieces.setdefault(key, [Vector(), 0.0, []])
        piece[0] += sum(corners, Vector()) / 3 * area
        piece[1] += area
        piece[2].extend(corners)
    items = [(key[0], total / area if area > 0 else sum(points, Vector()) / len(points), area, points) for key, (total, area, points) in pieces.items()]
    groups = list(range(len(items)))

    def root(index):
        while groups[index] != index:
            groups[index] = groups[groups[index]]
            index = groups[index]
        return index

    for first in range(len(items)):
        for second in range(first + 1, len(items)):
            if items[first][0] == items[second][0] and (items[first][1] - items[second][1]).length < merge:
                groups[root(second)] = root(first)
    patches = {}
    for index, (material_index, centre, area, points) in enumerate(items):
        patch = patches.setdefault(root(index), [material_index, Vector(), 0.0, 0, []])
        weight = max(area, 1e-6)
        patch[1] += centre * weight
        patch[2] += weight
        patch[3] += 1
        patch[4].extend(points)
    result = []
    for material_index, total, weight, count, points in patches.values():
        centre = total / weight
        low = [min(point[axis] for point in points) for axis in range(3)]
        high = [max(point[axis] for point in points) for axis in range(3)]
        extent = (high[0] - low[0], high[2] - low[2], high[1] - low[1])
        result.append((mesh.materials[material_index].name, (centre.x, centre.z, -centre.y), count, extent, weight))
    return sorted(result, key=lambda patch: (patch[0], patch[1]))


def print_emissive(body, merge=0.45):
    for material, centre, count, extent, area in emissive_patches(body, merge):
        print(f"EMISSIVE {material} at ({centre[0]:.3f}, {centre[1]:.3f}, {centre[2]:.3f}) pieces {count} extent ({extent[0]:.2f}, {extent[1]:.2f}, {extent[2]:.2f}) area {area:.3f}")


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


def coplanar_pairs(records, tolerance=0.006):
    """Overlapping same facing faces within tolerance of one plane, from
    Builder records (corners, normal, label): a bucket per normal and
    plane offset, neighbours compared. Returns (centre, label, label)."""
    triangles = []
    for corners, normal, label in records:
        if normal.length < 0.5 or (normal.z < -0.99 and max(c.z for c in corners) < 0.01):
            continue
        for step in range(1, len(corners) - 1):
            triangles.append(((corners[0], corners[step], corners[step + 1]), normal, label))
    buckets = {}
    for index, (corners, normal, label) in enumerate(triangles):
        key = (round(normal.x * 20), round(normal.y * 20), round(normal.z * 20), round(normal.dot(corners[0]) / tolerance))
        buckets.setdefault(key, []).append(index)
    found = {}
    for key, members in buckets.items():
        candidates = []
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for dd in (-1, 0, 1):
                        candidates += buckets.get((key[0] + dx, key[1] + dy, key[2] + dz, key[3] + dd), [])
        for first_index in members:
            first, normal, first_label = triangles[first_index]
            low = [min(c[axis] for c in first) for axis in range(3)]
            high = [max(c[axis] for c in first) for axis in range(3)]
            for second_index in candidates:
                if second_index <= first_index:
                    continue
                second, other, second_label = triangles[second_index]
                if normal.dot(other) < 0.999 or abs(normal.dot(second[0] - first[0])) > tolerance:
                    continue
                if any(min(c[axis] for c in second) > high[axis] + 1e-4 or max(c[axis] for c in second) < low[axis] - 1e-4 for axis in range(3)):
                    continue
                axis = max(range(3), key=lambda a: abs(normal[a]))
                plane = [a for a in range(3) if a != axis]
                if triangles_overlap([(c[plane[0]], c[plane[1]]) for c in first], [(c[plane[0]], c[plane[1]]) for c in second]):
                    labels = tuple(sorted((first_label, second_label)))
                    found.setdefault(labels, tuple(round(value, 2) for value in sum(first, Vector()) / 3))
    return [(centre, *labels) for labels, centre in found.items()]
