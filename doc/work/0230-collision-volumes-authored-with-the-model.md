# 0230: Collision volumes authored with the model

Status: todo (2026-10-04, from the user with the round three pod preview: "I think the pod's exterior hitbox is a big cube, right?" and "Skip the stepped collider work, do a better collision directly, i think we need to add a collision bounding box to the model as a part of the blender modelling to begin with?"; the main agent's take, agreed in principle, is below; after 0221, whose decision 4 (the stepped open cells) is struck)

## Goal

A machine model collides as its shape, not as its footprint's box of cells: the pod's sloped hull is sloped to a player walking round it, the empty corners of its footprint are walkable, and inside the cabin the chair, the desk, the bed and the drum stop the player where they stand. The volumes are authored in the model script beside the geometry, in the model's own frame, so the modeller shapes both at once.

## Why volumes, not triangles and not cells

The simulation is fixed point and lockstep: a capsule against thousands of triangles in integer arithmetic, per player and per tick, hashed alike on two machines, is a lot of delicate code for one benefit. A handful of analytic primitives in the model's frame (box, cylinder, cone frustum, each optionally a shell with a wall thickness) is tested exactly in integer millimetres, is deterministic by construction, and matches how the lab's models are built from the kit's box, cylinder and cone. Cells at half a metre give a staircase, which the user declined.

## Controls

No binding changes.

## Change

- The model script lists collision volumes in a `collision(b)` section (the kit grows `b.collision_box`, `b.collision_cylinder`, `b.collision_cone`, each with a `shell` thickness option, in the Blender frame like the geometry); the exporter writes them to `data/models/<model>.collision.sjson` in the model's frame in cells (x and z centred, y from the bottom, +x the front), the same conversion the OBJ gets. The lab's check reports the volumes' bounds against the footprint and draws them in the previews as wireframes.
- The game loads the file with the model (`model_obj.odin`'s neighbour, a reader of the volumes with bounds: inside the footprint plus the model tolerance, at most a cap of volumes, radii and thicknesses positive) and keeps them on the machine record's model; a machine without the file collides as today.
- The field player's collision against frames (`world_frame_collision.odin`, `frame_solid_probe`, `raycast_frames` with `.Solid`) takes a machine with volumes by its volumes alone: the capsule, transformed into the machine's frame by the inverse of its rotation and pitch (integer millimetres, the pitch a whole number of millimetres), is tested against each volume (the distance from the capsule's segment to the box, the cylinder, the frustum, and for a shell the band between its two surfaces), and pushed out along the volume's normal, with the walk, step, slide and mantle rules of `field_player` applied as they are for cells (the design stage says how the step height and the walkable angle apply to a sloped hull: a cone of the pod's slope is steeper than the walkable angle, so the player slides off it). The aiming ray stops at the volumes of such a machine, so Interact and the tool reach the hull where it is and pass the empty corners.
- The record's open cells keep their other duties (the spawn box, the fixture boxes, the sealed room for the oxygen generator, placement refusal on the cells); the player's collision inside such a machine is the volumes'. The hatches stay cell collided (a 1 by 2 by 2 door panel is a box of cells already) and their open rows passable as today.
- Determinism: all of it in integer millimetres with the simulation's own integer square root and vector helpers (`world_field_vector.odin`, `world_field_distance.odin`), no float in the simulation, the lockstep hash unchanged by the volumes themselves (they are content, loaded alike on every machine) and changed by the movement they cause, as any collision is.
- The pod's volumes: the modeller adds them in the lab in a round of its own once the engine side is on `main` (the hull as a cone shell, the drum as a cylinder, the housing a box, the chair, the desk, the bed, the lockers and the niches as boxes, the floor plate; the cabin's free floor left open), checked by the lab's previews and the game's model check.
- Docs: `doc/content.md` (Models: the collision file; the pod bullet), `doc/architecture.md` (Frames: collision by volumes), `doc/build.md` (The workbench: the volumes in the check and the previews), `doc/presentation.md` if the preview draws them, `DESIGN.md` Art direction if it names collision, `tools/model_lab/pod/BRIEF.md` (the volumes section for the modeller).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, `./build.sh model-check`, `tools/make_models.sh` for the pod.
- Tests: a capsule beside a cone shell is pushed out along the slope and slides where the slope exceeds the walkable angle; a capsule in the empty corner of a footprint with a cone volume moves freely; a capsule inside the shell (the cabin) is held by the inner surface; a box volume stops the capsule on each face and lets it step onto one lower than the step height; the ray stops at a volume and passes the empty corner; a machine without a file collides as before (the existing tests unchanged); two machines hash alike over a walk round and into the pod; the reader refuses a volume outside the footprint, a non positive radius and too many volumes, naming the file.
- The couch and the phone: walk round the pod and feel the cone, crawl in and bump the chair.
