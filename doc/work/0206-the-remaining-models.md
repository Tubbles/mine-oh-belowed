# 0206: The remaining machines, the arm and the player in the new models

Status: todo (0204 and 0205; after 0198, so the pod's model is written once, with the kit)

## Goal

Every model in the game is an OBJ written by the kit, in the look of `DESIGN.md`, and the voxel reader goes.

## Change

- The oil, chemistry and late machines: tar_pit_pump, flare_stack, combustion_generator, chemical_plant, refinery, cracking_unit, electrolyser, washer, crusher, steel_furnace, alloy_furnace, recycler, substation, hydro_turbine, fuel_generator, bore_drill, core_sample_drill, launch_pad, and drop_capsule for as long as the block world type lives (`PLAN.md`, M14).
- The arm: one `arm.obj` with the groups `base`, `turret`, `upper_arm`, `forearm`, `gripper` and `finger`, authored in metres as the six .vox parts are (`ARM_VOXEL_MILLIMETRES`, 25 mm per voxel today), in the authored pose of `doc/presentation.md` (The arm); `load_arm_part_meshes` reads the groups, the footprint check of 0204 does not apply to it (it scales by `cells_per_metre`), and the pose code is untouched.
- The player: one `player.obj` with the groups `torso`, `head`, `arm_left`, `arm_right`, `leg_left` and `leg_right` in the frame `render_player_model.odin` uses (`PLAYER_MODEL_FRAME` in blocks), the pivots read from each group's bounds as they are read from the voxel bounds today.
- The voxel reader goes: the `model_vox` package, `mesh_voxel_model`, `model_face_shades`, the .vox branch of the resolution, `tools/make_placeholder_models.py` and every .vox file under `data/models/`; `Data_File_Category.Models` takes `.obj` and `.mtl` only.
- Docs: `doc/presentation.md` (Machine models, The arm, The player), `doc/content.md` (the authoring rules, the pod's line), `doc/code_map.md` (the `model_vox` row goes), `doc/architecture.md` where it names .vox, the log.

## Verify

- The build and check commands of 0168.
- Tests: every machine model loads; the arm's rest and reach tests pass unchanged with the group meshes; the player's pivot tests pass from the group bounds; the budget test of 0205 over every shipped file; no .vox under `data/models/` and no reference to `model_vox` in `src/`.
- Headless screenshots: the planet preview's arm at full reach, a third person shot of the player, sent to the user.
