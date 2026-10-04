# 0229: Machine lamps stay inside their machine's box

Status: todo (2026-10-04, from the user on the phone with the round three preview: "it looks like the point lights lighten up the outside exterior of the pod as well, the light doesnt seem to be blocked by solids?"; 0224's decision 1 accepted that spill and the user does not)

## Goal

The pod's cabin lamps light the cabin and nothing outside it: the hull seen from the crater, the ground round the pod and the machines beside it take no light from a lamp inside, by day or by night. Solids do not cast shadows in this renderer (no shadow maps; a point light is a soft falloff round a point in `field.fs` and `model.fs`), so the lamp is clipped to its machine instead: a lamp's light stops at the faces of its machine's footprint box.

## Controls

No binding changes.

## Change

- Every `Point_Light` may carry a clip box: the machine's footprint box in the world (the body matrix of `machine_point_light`, 0224, times the footprint's extent in cells: x and z centred, y from the bottom), handed to both shaders as a matrix per light that maps a world position into the box's unit coordinates, so the shader adds a light's term only where the mapped position lies inside the unit box (a cheap test, no shadows). The arm's lamp carries no box (the identity or a flag that skips the test), since it lights the ground it works over. A record's lamp may opt out with a key (`clip = false`) for a lamp meant to shine out of a machine, such as a street lamp; the pod's lamps keep the default, clipped.
- Light through the portholes and the open door is lost with the clip (the box stops at the hull); the portholes' and the door's emissive patches are what shows the pod lit from outside, and 0222's closed doors make the loss small. The design stage names what the arrival's open doors look like from outside.
- The uniforms: `point_light_boxes[8u]` as `mat4` in both shaders (GLSL 330 and 300 es take mat4 arrays; every integer literal with the `u` suffix), set with the others in `set_field_point_lights` and `set_model_point_lights` from `point_light_uniform_values`.
- Docs: `doc/presentation.md` (Chunk meshes, the field shader bullet; Machine models, the point lights bullet), `doc/content.md` (the `lights` key: `clip`), the log.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the box matrix maps the footprint's corners to the unit box's corners on the 500 and 1000 mm frames and under every rotation; a point just outside a face maps outside; the arm's lamp has no box; a lamp with `clip = false` has none; the packing puts the matrices in the slots of their lights with the unused slots' matrices at zero; the shaders pass `shader_source_test.odin`.
- A headless screenshot pass (`tmp/pod_shots.sh`) on the round three model: the cabin lit as before, the hull from outside and the ground round the pod unlit by the lamps (the outside shots at dusk if the pass can set the time, else by the terrain's colour under the pod).
