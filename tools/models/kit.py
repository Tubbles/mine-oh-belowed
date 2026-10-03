"""Helpers the machine scripts build with, inside Blender (work item
0204, doc/build.md, Models).

Every machine is built in Blender's frame: the front at +X, Z up, one
unit per cell, the footprint spanning x +-width/2, y +-depth/2 and z 0 to
height. Blender y is the game's -z; the export (forward -Z, up Y) turns
Blender (x, y, z) into the file's (x, z, -y), the game frame. Each volume
is one mesh object with one material; join() merges them into the
objects the game reads, body and, for a machine with a moving part,
part.
"""

import math

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
        slots = []
        for slot_material in evaluated.materials:
            if joined.materials.find(slot_material.name) < 0:
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


def join_part(objects, machine, pivot=None):
    """join(objects, "part") for a machine whose motion moves a part.
    A spin or a swing names the pivot it was built about, which must be
    the record's (records.pivot); a pump or a bob may leave it out."""
    kind = machine.motion.kind
    expected = records.pivot(machine)
    if kind not in records.PART_MOTIONS:
        raise SystemExit(f"model {machine.model}: its motion {kind!r} moves no part")
    if kind in ("spin", "swing") and pivot is None:
        raise SystemExit(f"model {machine.model}: a {kind} part needs its pivot, the record's is {expected}")
    if pivot is not None and any(abs(given - wanted) > 1e-6 for given, wanted in zip(pivot, expected)):
        raise SystemExit(f"model {machine.model}: the part's pivot {tuple(pivot)} is not the record's {expected}")
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
