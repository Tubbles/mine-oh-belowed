"""Renders data/models/<model>.obj into previews/, the way the game's
workbench frames a machine and, for the pod, from inside the cabin:
the model on a grey pad next to a 1.8 m player capsule, flat shaded,
back faces culled as the game culls them, 1280 by 720. Runs inside
Blender:

    tools/blender render.py pod
    tools/blender render.py pod_hatch
    xvfb-run -a tools/blender render.py pod   (if Blender wants a display)

Exterior cameras: front_right and front_left (three quarter from the
front, the model's front is +X), back_left, top, and close (2 m in
front of the front face at eye height, 1.6 m). Interior cameras (the
pod only, edit INTERIOR_VIEWS to taste as the model takes shape):
chair (a seated eye at the cabin's centre looking at the airlock),
door (an eye at the airlock's inner mouth looking back across the
cabin) and wide (a wide lens from the back wall). One cell is 0.5 m;
the model is imported at one unit per cell and the scene is scaled to
metres.
"""

import math
import pathlib
import sys

import bpy
from mathutils import Vector

LAB = pathlib.Path(__file__).resolve().parent
CELL_METRES = 0.5
FOOTPRINTS_CELLS = {"pod": (12, 12, 8), "pod_hatch": (1, 2, 2)}
FIELD_OF_VIEW_DEGREES = 40
INTERIOR_FIELD_OF_VIEW_DEGREES = 80
RISE = 0.6
# Interior cameras in metres, Blender frame (x the front, z up): position, target.
INTERIOR_VIEWS = {
    "chair": ((0.0, 0.0, 1.2), (2.5, 0.0, 0.9)),
    "door": ((1.6, 0.0, 0.8), (-1.0, 0.0, 1.0)),
    "wide": ((-1.5, 0.0, 1.4), (1.0, 0.0, 0.9)),
}


def model_name():
    arguments = sys.argv
    names = arguments[arguments.index("--") + 1:] if "--" in arguments else []
    return names[0] if names else "pod"


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
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


def main():
    name = model_name()
    clear()
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
    width, depth, height = [value * CELL_METRES for value in FOOTPRINTS_CELLS.get(name, (12, 12, 8))]
    ground = flat_material("ground", (0.46, 0.44, 0.40))
    pad = flat_material("pad", (0.56, 0.54, 0.50))
    player = flat_material("player", (0.30, 0.45, 0.85))
    add_box("ground", (-14, -14, -0.06), (14, 14, 0.0), ground)
    add_box("pad", (-width / 2 - 1, -depth / 2 - 1, -0.03), (width / 2 + 1, depth / 2 + 1, 0.0), pad)
    feet = (width / 2 + 0.6, -depth / 2 - 0.6, 0.0)
    add_capsule(feet, player)
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
    centre = Vector((0, 0, max(height, 4.0) / 2))
    radius = Vector((width / 2, depth / 2, max(height, 4.0) / 2)).length + 1.0
    distance = 1.1 * radius / math.sin(math.radians(FIELD_OF_VIEW_DEGREES / 2))
    camera_data = bpy.data.cameras.new("camera")
    camera_data.sensor_fit = "VERTICAL"
    camera_data.angle = math.radians(FIELD_OF_VIEW_DEGREES)
    camera_data.clip_start = 0.05
    camera = bpy.data.objects.new("camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    views = {
        "front_right": (Vector((1, 1, RISE)).normalized() * distance + centre, centre),
        "front_left": (Vector((1, -1, RISE)).normalized() * distance + centre, centre),
        "back_left": (Vector((-1, -1, RISE)).normalized() * distance + centre, centre),
        "top": (centre + Vector((0, 0, distance)), centre),
        "close": (Vector((width / 2 + 2.0, 0, 1.6)), Vector((width / 2, 0, 1.6))),
    }
    out = LAB / "previews"
    out.mkdir(exist_ok=True)
    for view, (position, target) in views.items():
        aim(camera, position, target)
        scene.render.filepath = str(out / f"{name}_{view}.png")
        bpy.ops.render.render(write_still=True)
        print(f"wrote previews/{name}_{view}.png")
    if name != "pod":
        return
    camera_data.angle = math.radians(INTERIOR_FIELD_OF_VIEW_DEGREES)
    for view, (position, target) in INTERIOR_VIEWS.items():
        aim(camera, Vector(position), Vector(target))
        scene.render.filepath = str(out / f"{name}_inside_{view}.png")
        bpy.ops.render.render(write_still=True)
        print(f"wrote previews/{name}_inside_{view}.png")


main()
