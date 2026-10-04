"""Helpers the machine scripts build with, inside Blender (work item
0204, doc/build.md, Models).

Every machine is built in Blender's frame: the front at +X, Z up, one
unit per cell, the footprint spanning x +-width/2, y +-depth/2 and z 0 to
height. Blender y is the game's -z; the export (forward -Z, up Y) turns
Blender (x, y, z) into the file's (x, z, -y), the game frame. Each volume
is one mesh object with one material; join() merges them into the
objects the game reads, body and, for a machine with a moving part,
part.

A machine's collision volumes are authored in its script's collision(b)
beside build, b a collision.Collision, in the same frame (work item 0230,
tools/models/collision.py).
"""

import math
import random
import zlib

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import palette, records

# The axis a cylinder runs along, as a rotation of Blender's Z onto it.
AXIS_ROTATIONS = {
    "X": Matrix.Rotation(math.pi / 2, 4, "Y"),
    "Y": Matrix.Rotation(-math.pi / 2, 4, "X"),
    "Z": Matrix.Identity(4),
}


# A face's outward normal and the axes its width and height run along
# (x 0, y 1, z 2).
FACE_FRAMES = {
    "+X": (Vector((1, 0, 0)), 1, 2),
    "-X": (Vector((-1, 0, 0)), 1, 2),
    "+Y": (Vector((0, 1, 0)), 0, 2),
    "-Y": (Vector((0, -1, 0)), 0, 2),
    "+Z": (Vector((0, 0, 1)), 0, 1),
}
# The side a wedge is full height on, as (axis, sign).
WEDGE_RISES = {"+X": (0, 1), "-X": (0, -1), "+Y": (1, 1), "-Y": (1, -1)}
AXIS_INDICES = {"X": 0, "Y": 1, "Z": 2}


def clear_scene():
    """An empty scene with no orphan data, so machines do not mix."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)


def material(name):
    """The palette material: Base Color the bytes / 255, Emission Color
    black with Strength 0, or the glow with Strength 1, so the exported
    Ke is 0 exactly on the lit materials."""
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    colour, emissive = palette.MATERIALS[name]
    created = bpy.data.materials.new(name)
    shader = created.node_tree.nodes["Principled BSDF"]
    linear = (*(channel / 255 for channel in colour), 1.0)
    shader.inputs["Base Color"].default_value = linear
    shader.inputs["Emission Color"].default_value = linear if emissive else (0.0, 0.0, 0.0, 1.0)
    shader.inputs["Emission Strength"].default_value = 1.0 if emissive else 0.0
    return created


def mesh_object(name, mesh, material_name, bevel):
    """One object of the bmesh with the material and, with bevel, a one
    segment Bevel modifier."""
    data = bpy.data.meshes.new(name)
    mesh.to_mesh(data)
    mesh.free()
    data.materials.append(material(material_name))
    created = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(created)
    if bevel > 0:
        modifier = created.modifiers.new("bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        modifier.limit_method = "ANGLE"
        modifier.harden_normals = False
    return created


def box(minimum, maximum, material_name, bevel=0.0):
    """An axis aligned box from its two corners."""
    mesh = bmesh.new()
    bmesh.ops.create_cube(mesh, size=1.0)
    centre = (Vector(minimum) + Vector(maximum)) / 2
    size = Vector(maximum) - Vector(minimum)
    for vertex in mesh.verts:
        vertex.co = centre + vertex.co * size
    return mesh_object("box", mesh, material_name, bevel)


def cylinder(centre, start, end, radius, sides, material_name, bevel=0.0, axis="Z"):
    """A capped cylinder of n sides from start to end along axis; centre
    is the other two coordinates in x, y, z order ((x, y) for Z, (y, z)
    for X, (x, z) for Y)."""
    return frustum(centre, start, end, radius, radius, sides, material_name, bevel, axis, 0.0)


def cone(centre_xy, z0, z1, radius_bottom, radius_top, sides, material_name, rotation=0.0):
    """A capped vertical frustum, turned rotation radians about Z. A top
    radius of 0 is a point."""
    return frustum(centre_xy, z0, z1, radius_bottom, radius_top, sides, material_name, 0.0, "Z", rotation)


def frustum(centre, start, end, radius_bottom, radius_top, sides, material_name, bevel, axis, rotation):
    middle = (start + end) / 2
    point = {"X": (middle, *centre), "Y": (centre[0], middle, centre[1]), "Z": (*centre, middle)}[axis]
    placement = Matrix.Translation(point) @ AXIS_ROTATIONS[axis] @ Matrix.Rotation(rotation, 4, "Z")
    mesh = bmesh.new()
    bmesh.ops.create_cone(
        mesh, cap_ends=True, cap_tris=False, segments=sides, radius1=radius_bottom,
        radius2=radius_top, depth=end - start, matrix=placement,
    )
    # A point top leaves one vertex per side there: merge them.
    bmesh.ops.remove_doubles(mesh, verts=mesh.verts, dist=1e-6)
    return mesh_object("cylinder", mesh, material_name, bevel)


def cut(target, cutter):
    """Removes cutter's volume from target (an exact boolean); join()
    deletes the cutter."""
    modifier = target.modifiers.new("cut", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.solver = "EXACT"
    modifier.object = cutter
    cutter.hide_set(True)


def opening(target, minimum, maximum):
    """Cuts the box out of target; the opening's walls keep the target's
    material, so a dark inside is a volume of its own."""
    cut(target, box(minimum, maximum, "soot"))


def model_random(machine, salt):
    """The seeded draws of one detail row: the same numbers in every run,
    and one row's edit leaves the others' draws unchanged."""
    return random.Random(zlib.crc32(f"{machine.model}:{salt}".encode("ascii")))


def expect_footprint(machine, width, depth, height):
    """Stops when the record's footprint is not the one the script was
    designed for, so a changed record forces the model to be revisited."""
    footprint = machine.footprint
    if (footprint.width, footprint.depth, footprint.height) != (width, depth, height):
        raise SystemExit(
            f"model {machine.model}: designed for the footprint {width} by {depth} by {height}, "
            f"the record's is {footprint.width} by {footprint.depth} by {footprint.height}"
        )


def wedge(minimum, maximum, material_name, rise="+X"):
    """A right triangular prism in the box: full height on the rise side,
    zero on the opposite one."""
    axis, sign = WEDGE_RISES[rise]
    other = 1 - axis
    mesh = bmesh.new()
    bottom = []
    for along_other in (minimum[other], maximum[other]):
        for along_axis in (minimum[axis], maximum[axis]):
            corner = [0.0, 0.0, minimum[2]]
            corner[axis], corner[other] = along_axis, along_other
            bottom.append(mesh.verts.new(corner))
    high_index = 1 if sign > 0 else 0
    tops = []
    for row in (0, 2):
        corner = Vector(bottom[row + high_index].co)
        corner.z = maximum[2]
        tops.append(mesh.verts.new(corner))
    low_index = 1 - high_index
    mesh.faces.new((bottom[0], bottom[1], bottom[3], bottom[2]))
    mesh.faces.new((bottom[high_index], bottom[2 + high_index], tops[1], tops[0]))
    mesh.faces.new((bottom[low_index], tops[0], tops[1], bottom[2 + low_index]))
    mesh.faces.new((bottom[low_index], bottom[high_index], tops[0]))
    mesh.faces.new((bottom[2 + low_index], tops[1], bottom[2 + high_index]))
    bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
    return mesh_object("wedge", mesh, material_name, 0.0)


def ring(centre, radius, thickness, material_name, axis="Z", sides=8, minor_sides=4):
    """A torus of sides around axis through centre, its tube of radius
    thickness with minor_sides, a flat of the tube facing outward."""
    placement = Matrix.Translation(centre) @ AXIS_ROTATIONS[axis]
    mesh = bmesh.new()
    vertices = []
    for major in range(sides):
        major_angle = major * 2 * math.pi / sides
        for minor in range(minor_sides):
            minor_angle = (minor + 0.5) * 2 * math.pi / minor_sides
            distance = radius + thickness * math.cos(minor_angle)
            local = Vector((distance * math.cos(major_angle), distance * math.sin(major_angle), thickness * math.sin(minor_angle)))
            vertices.append(mesh.verts.new(placement @ local))
    for major in range(sides):
        for minor in range(minor_sides):
            following_major = (major + 1) % sides
            following_minor = (minor + 1) % minor_sides
            mesh.faces.new((
                vertices[major * minor_sides + minor],
                vertices[following_major * minor_sides + minor],
                vertices[following_major * minor_sides + following_minor],
                vertices[major * minor_sides + following_minor],
            ))
    bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
    return mesh_object("ring", mesh, material_name, 0.0)


def pipe_arc_points(points, bend):
    """The path with every interior corner replaced by three arc points
    (start of bend, midpoint, end of bend)."""
    corners = [Vector(point) for point in points]
    path = [corners[0]]
    tangents = [0.0] * len(corners)
    for index in range(1, len(corners) - 1):
        incoming = (corners[index] - corners[index - 1]).normalized()
        outgoing = (corners[index + 1] - corners[index]).normalized()
        angle = incoming.angle(outgoing)
        tangents[index] = bend * math.tan(angle / 2)
    for index in range(1, len(corners)):
        run = (corners[index] - corners[index - 1]).length
        if run < tangents[index - 1] + tangents[index] - 1e-9:
            raise SystemExit(f"pipe: the run {index} from {tuple(corners[index - 1])} is {run:.3f} long, shorter than its bends' {tangents[index - 1] + tangents[index]:.3f}")
    for index in range(1, len(corners) - 1):
        point = corners[index]
        incoming = (point - corners[index - 1]).normalized()
        outgoing = (corners[index + 1] - point).normalized()
        angle = incoming.angle(outgoing)
        centre = point + (outgoing - incoming).normalized() * (bend / math.cos(angle / 2))
        path.append(point - incoming * tangents[index])
        path.append(centre + (point - centre).normalized() * bend)
        path.append(point + outgoing * tangents[index])
    path.append(corners[-1])
    return path


def pipe(points, radius, material_name, sides=8, bend=None):
    """A round pipe of sides along the points, its corners bent with
    radius bend (2 * radius by default) and its ends capped."""
    if sides not in (8, 12):
        raise SystemExit(f"pipe: {sides} sides, the kit bends pipes of 8 or 12")
    path = pipe_arc_points(points, 2 * radius if bend is None else bend)
    curve = bpy.data.curves.new("pipe", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    # Blender 5.2's round bevel has 4 + 2 * resolution sides.
    curve.bevel_resolution = (sides - 4) // 2
    curve.use_fill_caps = True
    spline = curve.splines.new("POLY")
    spline.points.add(len(path) - 1)
    for spline_point, point in zip(spline.points, path):
        spline_point.co = (*point, 1.0)
    curve_object = bpy.data.objects.new("pipe", curve)
    bpy.context.scene.collection.objects.link(curve_object)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    data = bpy.data.meshes.new_from_object(curve_object.evaluated_get(depsgraph))
    bpy.data.objects.remove(curve_object)
    bpy.data.curves.remove(curve)
    # A ring of sides per path point, and each cap a ring of its own.
    expected = sides * (len(path) + 2)
    if len(data.vertices) != expected:
        raise SystemExit(f"pipe: Blender made {len(data.vertices)} vertices, the kit expects {expected}")
    data.materials.clear()
    data.materials.append(material(material_name))
    created = bpy.data.objects.new("pipe", data)
    bpy.context.scene.collection.objects.link(created)
    return created


def face_box(face, centre, width, height, inner, outer, material_name, bevel=0.0):
    """A box on a face: width and height along the face's axes about
    centre, from inner to outer along its outward normal."""
    normal, width_axis, height_axis = FACE_FRAMES[face]
    corners = []
    for offset in (inner, outer):
        corner = Vector(centre) + normal * offset
        corner[width_axis] -= width / 2
        corner[height_axis] -= height / 2
        corners.append(corner)
        corner = Vector(centre) + normal * offset
        corner[width_axis] += width / 2
        corner[height_axis] += height / 2
        corners.append(corner)
    minimum = [min(corner[index] for corner in corners) for index in range(3)]
    maximum = [max(corner[index] for corner in corners) for index in range(3)]
    return box(minimum, maximum, material_name, bevel)


def strip(face, centre, width, height, material_name, depth=0.02):
    """A thin plate set into the face, 0.005 proud of it: an indicator."""
    return face_box(face, centre, width, height, -depth, 0.005, material_name)


def hatch(face, centre, width, height, material_name, handle_material="galvanised", thickness=0.03):
    """A bevelled plate on the face and a handle bar standing off it, a
    quarter of the height above the plate's centre."""
    normal, width_axis, height_axis = FACE_FRAMES[face]
    plate = face_box(face, centre, width, height, 0.0, thickness, material_name, bevel=0.01)
    handle_centre = Vector(centre)
    handle_centre[height_axis] += height / 4
    handle = face_box(face, handle_centre, width / 2, 0.03, thickness + 0.02, thickness + 0.05, handle_material)
    return [plate, handle]


def rib_row(axis, start, end, count, thickness, minimum, maximum, material_name, random, jitter=0.35):
    """count ribs along axis from start to end, each nudged off its even
    spot by a seeded draw; minimum and maximum give the other two axes."""
    spacing = (end - start) / count
    if not 0 <= jitter <= 1:
        raise SystemExit(f"rib_row: the jitter {jitter} is outside 0 to 1")
    if thickness > spacing * (1 - jitter):
        raise SystemExit(f"rib_row: ribs {thickness} thick could touch at the spacing {spacing:.3f} and the jitter {jitter}")
    index_of_axis = AXIS_INDICES[axis]
    ribs = []
    for index in range(count):
        middle = start + (index + 0.5) * spacing + random.uniform(-jitter, jitter) * spacing / 2
        low, high = list(minimum), list(maximum)
        low[index_of_axis], high[index_of_axis] = middle - thickness / 2, middle + thickness / 2
        ribs.append(box(low, high, material_name))
    return ribs


def join(objects, name):
    """One flat shaded object called name from the objects with their
    modifiers applied and their materials kept. The sources and their
    cutters are deleted."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    joined = bpy.data.meshes.new(name)
    combined = bmesh.new()
    for source in objects:
        evaluated = bpy.data.meshes.new_from_object(source.evaluated_get(depsgraph))
        first_face = len(combined.faces)
        combined.from_mesh(evaluated)
        combined.faces.ensure_lookup_table()
        # Only the materials a face uses: a boolean also lists its
        # cutter's material, which no face of an opening carries.
        used = {polygon.material_index for polygon in evaluated.polygons}
        slots = []
        for index, slot_material in enumerate(evaluated.materials):
            if index in used and joined.materials.find(slot_material.name) < 0:
                joined.materials.append(slot_material)
            slots.append(joined.materials.find(slot_material.name))
        for face in combined.faces[first_face:]:
            face.material_index = slots[face.material_index]
        bpy.data.meshes.remove(evaluated)
    for face in combined.faces:
        face.smooth = False
    combined.to_mesh(joined)
    combined.free()
    created = bpy.data.objects.new(name, joined)
    bpy.context.scene.collection.objects.link(created)
    cutters = dict.fromkeys(modifier.object for source in objects for modifier in source.modifiers if modifier.type == "BOOLEAN")
    for source in [*objects, *cutters]:
        data = source.data
        bpy.data.objects.remove(source)
        if data.users == 0:
            bpy.data.meshes.remove(data)
    return created


def join_part(objects, machine, pivot=None, hinge=None):
    """join(objects, "part") for a machine whose motion moves a part.
    A spin or a swing names the pivot it was built about, which must be
    the record's (records.pivot); a pump or a bob may leave it out. An
    iris (work item 0231) names both its pivot and its hinge
    (records.hinge), each the record's."""
    kind = machine.motion.kind
    expected = records.pivot(machine)
    expected_hinge = records.hinge(machine)
    if kind not in records.PART_MOTIONS:
        raise SystemExit(f"model {machine.model}: its motion {kind!r} moves no part")
    if kind in ("spin", "swing") and pivot is None:
        raise SystemExit(f"model {machine.model}: a {kind} part needs its pivot, the record's is {expected}")
    if kind == "iris" and (pivot is None or hinge is None):
        raise SystemExit(f"model {machine.model}: an iris part needs its pivot and its hinge, the record's are {expected} and {expected_hinge}")
    if pivot is not None and any(abs(given - wanted) > 1e-6 for given, wanted in zip(pivot, expected)):
        raise SystemExit(f"model {machine.model}: the part's pivot {tuple(pivot)} is not the record's {expected}")
    if hinge is not None and any(abs(given - wanted) > 1e-6 for given, wanted in zip(hinge, expected_hinge)):
        raise SystemExit(f"model {machine.model}: the part's hinge {tuple(hinge)} is not the record's {expected_hinge}")
    return join(objects, "part")


def export(name, directory):
    """<name>.obj and <name>.mtl in directory, every object of the scene.
    The options are listed in doc/build.md, Models."""
    bpy.ops.wm.obj_export(
        filepath=str(directory / f"{name}.obj"),
        check_existing=False,
        export_animation=False,
        forward_axis="NEGATIVE_Z",
        up_axis="Y",
        global_scale=1.0,
        apply_modifiers=True,
        apply_transform=True,
        export_eval_mode="DAG_EVAL_VIEWPORT",
        export_selected_objects=False,
        export_uv=False,
        export_normals=True,
        export_colors=False,
        export_materials=True,
        export_pbr_extensions=False,
        path_mode="STRIP",
        export_triangulated_mesh=True,
        export_curves_as_nurbs=False,
        export_object_groups=False,
        export_material_groups=False,
        export_vertex_groups=False,
        export_smooth_groups=False,
    )
