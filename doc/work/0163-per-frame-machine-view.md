# 0163: The per frame machine view

Status: todo (paused since 2026-10-01, after 0162)

## Goal

Refactor 5 of the simulation audit and refactor 4 of the presentation audit (`doc/audit/simulation.md`, `doc/audit/presentation.md`, section 5 of each). The renderer and the sound frame loop over the entity pools 35 times per frame and repeat the working rule three times (`draw_entities`, `draw_machine_markers`, `working_hum_sources`, with `launching_pad_count`, `capsule_landing_point`, the port loops of `draw_fluid_entities` and the lamps beside them). The per frame list of what a machine looks like is the draw description a plugin boundary needs: the engine draws a list, the game fills it.

## Change

- One list built once per frame (full-word name, for example `Machine_View` and `Machine_Views`), one entry per live machine: id or handle, origin, size, rotation, machine kind, working, marker colour, phase, held item, port fluids, lit for lamps; built by one procedure over the pools with the working rule for core sample drills and launch pads moved beside the marker colours, so the rule exists once.
- Readers: `draw_entities`, `draw_machine_markers`, `working_hum_sources`, `launching_pad_count`, `capsule_landing_point`, the port loops of `draw_fluid_entities`, the lamps' draw. Each reads the list, none loops a pool. The list lives in the presentation group of `Frame_State` (0158) and is rebuilt each frame into the same backing memory (no per frame allocation after the first frame; hand-back check: nothing a frame draws from is freed inside the frame).
- Draw order is unchanged: the list is filled in the pool order the draws use today, kind by kind, so the same machines draw in the same order (a playtest confirms the models and markers of every machine).
- `doc/presentation.md` describes the view in one place; `doc/code_map.md`: records lowered where the tool lets (presentation -> simulation should fall by most of the pool loops), never raised silently.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; `test_marker_colour_of_every_state`, `test_nearest_working_machine_and_its_volume`, `test_emitters_for_frame_from_the_world` pass unchanged in what they assert; a new test builds the list from a world with one machine of every kind and checks the entry count, the kinds and one working flag; a playtest (the user) of every machine's model and markers, the hum, and a launch.
