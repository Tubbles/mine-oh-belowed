"""Renders data/models/<model>.obj of the lab into previews/ (work item
0214, doc/build.md, The workbench), the way the game's workbench frames
a machine: the model on a grey pad next to a 1.8 m player capsule, flat
shaded, back faces culled as the game culls them, 1280 by 720. Runs
inside Blender:

    tools/blender render.py            every model of lab.sjson
    tools/blender render.py <model>    one
    xvfb-run -a tools/blender render.py   (if Blender wants a display)

Cameras, from the record's footprint: front_right and front_left (three
quarter from the front, the model's front is +X), back_left, top, and
close (2 m in front of the front face at eye height, half the model's
height and no higher than 1.6 m), into previews/<model>_<view>.png. The
lab's views.sjson, when it exists, adds the cameras listed under a
model's name ({name, position, target, field_of_view_degrees}, metres in
the Blender frame: x the front, y left, z up, the footprint centred). One
cell is 0.5 m; the model is imported at one unit per cell and the scene
is scaled to metres.

With data/models/<model>.collision.sjson (work item 0230), every camera
is rendered again with the collision volumes drawn as magenta wires:
previews/<model>_<view>_collision.png.

For a model whose lab record has an iris motion (work item 0231) the one
blade the file holds is instanced as the game draws it (blade k of n at
open fraction f: R(pivot, k / n turn) R(hinge, amplitude * f turn)), and
every camera and an aperture camera (face on at the pivot) are rendered
at open fractions 0, 0.5 and 1: previews/<model>_<view>_open_0.png,
_open_0.5.png and _open_1.png. The collision pass then runs at fraction
0.
"""

import math
import pathlib
import sys

import bpy
from mathutils import Matrix, Vector

LAB = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(LAB / "tools"))

import sjson  # noqa: E402
from models import collision, records  # noqa: E402

CELL_METRES = 0.5
FIELD_OF_VIEW_DEGREES = 40
RISE = 0.6
# The height the exterior cameras frame at least, in metres: a 1 m door
# and the 1.8 m capsule stay in the picture.
FRAMED_HEIGHT_MINIMUM = 2.0
# The iris's open fractions in the previews (work item 0231).
IRIS_FRACTIONS = (0.0, 0.5, 1.0)
# The record's axis in the Blender frame (x the game's x, y the game's
# -z, z the game's y): the axis name and the sign of a turn.
IRIS_AXES = {"x": ("X", 1.0), "y": ("Z", 1.0), "z": ("Y", -1.0)}
# The record axis's positive direction in the Blender frame.
AXIS_DIRECTIONS = {"x": (1.0, 0.0, 0.0), "y": (0.0, 0.0, 1.0), "z": (0.0, -1.0, 0.0)}
APERTURE_DISTANCE = 1.2


def requested_models():
    """The names after "--", every model of lab.sjson when there are none."""
    arguments = sys.argv
    names = arguments[arguments.index("--") + 1:] if "--" in arguments else []
    return names or sjson.load(LAB / "lab.sjson")["models"]


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights, bpy.data.curves):
        for item in list(block):
            block.remove(item)


def flat_material(name, colour):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*colour, 1.0)
    material.diffuse_color = (*colour, 1.0)
    return material


def add_box(name, minimum, maximum, material):
    centre = [(a + b) / 2 for a, b in zip(minimum, maximum)]
    size = [b - a for a, b in zip(minimum, maximum)]
    bpy.ops.mesh.primitive_cube_add(location=centre)
    cube = bpy.context.object
    cube.name = name
    cube.scale = [value / 2 for value in size]
    cube.data.materials.append(material)
    return cube


def add_capsule(feet, material):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.3, depth=1.8, location=(feet[0], feet[1], feet[2] + 0.9), vertices=16)
    capsule = bpy.context.object
    capsule.name = "player"
    capsule.data.materials.append(material)
    return capsule


def aim(camera, position, target, up=Vector((0, 0, 1))):
    camera.location = position
    direction = (Vector(target) - Vector(position)).normalized()
    quaternion = direction.to_track_quat("-Z", "Y")
    if abs(direction.dot(up)) > 0.99:
        quaternion = direction.to_track_quat("-Z", "X")
    camera.rotation_euler = quaternion.to_euler()


def add_collision_wires(name):
    """The volumes' wire lines as one curve of poly splines, file (x, y,
    z) to Blender (x, -z, y), scaled like the import; None without the
    file."""
    path = LAB / "data" / "models" / f"{name}{collision.FILE_SUFFIX}"
    if not path.exists():
        return None
    curve = bpy.data.curves.new("collision", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.012 / CELL_METRES
    for entry in sjson.load(path)["volumes"]:
        for start, end in collision.wire_lines(entry):
            spline = curve.splines.new("POLY")
            spline.points.add(1)
            for point, (x, y, z) in zip(spline.points, (start, end)):
                point.co = (x, -z, y, 1.0)
    wires = bpy.data.objects.new("collision", curve)
    wires.scale = (CELL_METRES,) * 3
    wires.data.materials.append(flat_material("collision", (1.0, 0.25, 0.78)))
    bpy.context.scene.collection.objects.link(wires)
    return wires


def lab_machine(name):
    """The lab record of the model."""
    return records.machine_for_model(records.load_machines(LAB / "data" / "machines.sjson"), name)


def footprint_metres(machine):
    """Width, depth and height in metres."""
    footprint = machine.footprint
    return footprint.width * CELL_METRES, footprint.depth * CELL_METRES, footprint.height * CELL_METRES


def exterior_views(machine):
    """View name to (position, target, field of view in degrees), metres."""
    width, depth, height = footprint_metres(machine)
    framed = max(height, FRAMED_HEIGHT_MINIMUM)
    centre = Vector((0, 0, framed / 2))
    radius = Vector((width / 2, depth / 2, framed / 2)).length + 1.0
    distance = 1.1 * radius / math.sin(math.radians(FIELD_OF_VIEW_DEGREES / 2))
    eye = min(height / 2, 1.6)
    return {
        "front_right": (Vector((1, 1, RISE)).normalized() * distance + centre, centre, FIELD_OF_VIEW_DEGREES),
        "front_left": (Vector((1, -1, RISE)).normalized() * distance + centre, centre, FIELD_OF_VIEW_DEGREES),
        "back_left": (Vector((-1, -1, RISE)).normalized() * distance + centre, centre, FIELD_OF_VIEW_DEGREES),
        "top": (centre + Vector((0, 0, distance)), centre, FIELD_OF_VIEW_DEGREES),
        "close": (Vector((width / 2 + 2.0, 0, eye)), Vector((width / 2, 0, eye)), FIELD_OF_VIEW_DEGREES),
    }


def extra_views(name):
    """The cameras views.sjson lists under the model's name."""
    path = LAB / "views.sjson"
    if not path.exists():
        return {}
    return {
        entry["name"]: (Vector(entry["position"]), Vector(entry["target"]), entry["field_of_view_degrees"])
        for entry in sjson.load(path).get(name, [])
    }


def aperture_view(machine):
    """Face on at an iris's pivot, from APERTURE_DISTANCE along the
    record axis's positive direction."""
    target = Vector(records.pivot(machine)) * CELL_METRES
    position = target + Vector(AXIS_DIRECTIONS[machine.motion.axis]) * APERTURE_DISTANCE
    return position, target, FIELD_OF_VIEW_DEGREES


def iris_blades(imported, machine):
    """The part object and blades - 1 objects sharing its mesh, all
    linked to the scene, with the part's world matrix as imported."""
    part = next(item for item in imported if item.name.split(".")[0] == "part")
    bpy.context.view_layer.update()
    base = part.matrix_world.copy()
    blades = [part]
    for index in range(1, machine.motion.blades):
        blade = bpy.data.objects.new(f"part_{index}", part.data)
        bpy.context.scene.collection.objects.link(blade)
        blades.append(blade)
    return blades, base


def blade_matrix(machine, blade, fraction):
    """Blade k at open fraction f in cells of the Blender frame: turned
    k / blades about the pivot after it opened about the hinge."""
    name, sign = IRIS_AXES[machine.motion.axis]
    pivot, hinge = Vector(records.pivot(machine)), Vector(records.hinge(machine))

    def about(point, angle):
        return Matrix.Translation(point) @ Matrix.Rotation(sign * angle, 4, name) @ Matrix.Translation(-point)

    return about(pivot, 2 * math.pi * blade / machine.motion.blades) @ about(hinge, 2 * math.pi * machine.motion.amplitude * fraction)


def pose_iris(blades, base, machine, fraction):
    scale = Matrix.Scale(CELL_METRES, 4)
    for index, blade in enumerate(blades):
        blade.matrix_world = scale @ blade_matrix(machine, index, fraction) @ scale.inverted() @ base


def render_views(camera, camera_data, name, views, suffix):
    """Every view at its own field of view."""
    scene = bpy.context.scene
    out = LAB / "previews"
    out.mkdir(exist_ok=True)
    for view, (position, target, field_of_view_degrees) in views.items():
        camera_data.angle = math.radians(field_of_view_degrees)
        aim(camera, position, target)
        scene.render.filepath = str(out / f"{name}_{view}{suffix}.png")
        bpy.ops.render.render(write_still=True)
        print(f"wrote previews/{name}_{view}{suffix}.png")


def import_model(name):
    """The model's objects, scaled to metres, flat, back faces culled."""
    bpy.ops.wm.obj_import(filepath=str(LAB / "data" / "models" / f"{name}.obj"), forward_axis="NEGATIVE_Z", up_axis="Y")
    imported = list(bpy.context.selected_objects)
    for item in imported:
        item.scale = (CELL_METRES,) * 3
        for polygon in item.data.polygons:
            polygon.use_smooth = False
        for material in item.data.materials:
            if material and material.use_nodes:
                node = material.node_tree.nodes.get("Principled BSDF")
                if node:
                    material.diffuse_color = node.inputs["Base Color"].default_value
            if material:
                material.use_backface_culling = True
    return imported


def set_up_scene(machine):
    """The ground, the pad, the capsule, the workbench engine and the
    camera; returns the camera object and its data."""
    width, depth, _ = footprint_metres(machine)
    ground = flat_material("ground", (0.46, 0.44, 0.40))
    pad = flat_material("pad", (0.56, 0.54, 0.50))
    player = flat_material("player", (0.30, 0.45, 0.85))
    add_box("ground", (-14, -14, -0.06), (14, 14, 0.0), ground)
    add_box("pad", (-width / 2 - 1, -depth / 2 - 1, -0.03), (width / 2 + 1, depth / 2 + 1, 0.0), pad)
    add_capsule((width / 2 + 0.6, -depth / 2 - 0.6, 0.0), player)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = False
    scene.display.shading.show_cavity = False
    scene.display.shading.show_backface_culling = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
    world = bpy.data.worlds[0] if bpy.data.worlds else bpy.data.worlds.new("world")
    scene.world = world
    world.color = (0.55, 0.65, 0.78)
    scene.display.shading.background_type = "WORLD"
    camera_data = bpy.data.cameras.new("camera")
    camera_data.sensor_fit = "VERTICAL"
    camera_data.angle = math.radians(FIELD_OF_VIEW_DEGREES)
    camera_data.clip_start = 0.05
    camera = bpy.data.objects.new("camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera, camera_data


def render_model(name):
    clear()
    machine = lab_machine(name)
    imported = import_model(name)
    camera, camera_data = set_up_scene(machine)
    views = {**exterior_views(machine), **extra_views(name)}
    if machine.motion.kind == "iris":
        # The plain suffix would show one blade, so an iris renders only
        # posed, with the shutter face on as well.
        views["aperture"] = aperture_view(machine)
        blades, base = iris_blades(imported, machine)
        for fraction in IRIS_FRACTIONS:
            pose_iris(blades, base, machine, fraction)
            render_views(camera, camera_data, name, views, f"_open_{fraction:g}")
        pose_iris(blades, base, machine, 0.0)
    else:
        render_views(camera, camera_data, name, views, "")
    if add_collision_wires(name) is not None:
        render_views(camera, camera_data, name, views, "_collision")


def main():
    for name in requested_models():
        render_model(name)


main()
