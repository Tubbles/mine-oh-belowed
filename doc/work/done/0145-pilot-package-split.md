# 0145: Pilot package split of the true leaves

Status: implemented

## Goal

The fourth step of the architecture cleanup (user, 2026-09-30): learn what a package split costs before deciding on the layering refactor. In Odin a directory is a package and packages cannot import in a cycle, so the split is only possible for files with no edge back into the game package.

## Change

- Move the files the graph shows outside the main component, or with one or two edges into it that a parameter removes, into packages under `src/`: candidates `sjson_text`, `run_length`, `model_vox`, `platform_paths`, `generation_seed`, `render_frustum`, `jni_indices`, the platform pairs (`haptics_*`, `export_access_*`, `system_keyboard_*`, `local_zone_*`, `logging_*`). Each package is a leaf utility with no back reference (the rule in `CLAUDE.md`), a `doc/code_map.md` entry, and its tests beside it.
- Record per package: the edges that had to be cut and how, the call sites that gained a prefix, the build and test time before and after, and anything the `#+build` tags or the Android build made awkward.
- The item's Implementation notes end with a recommendation: whether a full layering split (content, world, simulation, presentation, ui, loop) is worth its cost given what the pilot showed, as input to 0146.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py`; the play build installs and runs (the user playtests the couch and the phone once).

## Implementation notes

Seven leaf packages under `src/` now, each a cluster of `tools/code_graph.py` named after its directory ([code_map.md](../code_map.md), Packages): `platform` (12 files: logging with its two system files, `platform_paths.odin`, `platform_android.odin`, the three `local_zone` files, `jni_indices.odin`, the new `jni_android.odin`, the two `export_access` files), `generation_seed`, `model_vox`, `render_frustum`, `run_length`, `sjson_text`, plus the existing `android_libc`. The tests of those files moved beside them (`jni_indices_test.odin`, `model_vox_test.odin`, `render_frustum_test.odin`, `run_length_test.odin`, a new `platform/platform_paths_test.odin` with the `make_directory_path` and `trim_trailing_separators` tests, and a new `sjson_text/sjson_text_test.odin`). The writer's one test in `data_browser_test.odin` checked both a written tree and every shipped SJSON file; its first half needs only the package and moved into `sjson_text_test.odin` with a copy of the game's `json_values_equal` helper (a package's tests cannot see another package's test files), the second half needs the game's `list_data_files`, `data_file_kind` and `read_data_file_with_edits` and stays in the game as `test_shipped_sjson_files_round_trip`. That split is why the suite has 1290 tests, one more than before. Every move is a `git mv`.

Edges cut, all without a behaviour change:

- `BUILD_STAMP`: `open_log_file(build_stamp)` and `log_session_header(now, build_stamp)`; `main` passes `BUILD_STAMP`. The log header is byte for byte the same.
- `sorted_object_keys` moved into `sjson_text.odin` (one definition, 7 call sites in 4 files qualified) rather than a copy in the package: the smaller change and no duplicate.
- `join_save_path` (`save_world.odin`) is `platform.join_path` in `platform_paths.odin`; it was the general path join of 28 files, tests included.
- The JNI helpers (`Jni_Value`, `Jni_Calls`, the `Jni_*` procedure types, `jni_function`, `jni_environment`, `jni_checked` and the call helpers, `JNI_OK`) moved out of `haptics_android.odin` into `platform/jni_android.odin`, so `export_access_android.odin` reaches nothing in ui. The vibrator itself stays in the game.
- `Log_Capture`, `begin_log_capture` and `end_log_capture` moved from `data_reload.odin` into `logging.odin`, so `captured_log_error` is set and read only inside the package; the mechanism is unchanged, the four callers write `platform.Log_Capture` and `platform.begin_log_capture`.
- `generation_seed`: `hash_u64` moved in from `render_atlas.odin` (its single edge; the world audit already queued the move), `DEFAULT_WORLD_SEED` moved out to `generation.odin`, since it is the game's default seed and 30 files name it (it would have added 74 prefixes for a constant that is not a hash).
- `model_vox`: its one edge was `join_save_path`, now `platform.join_path`, so the package imports `platform` and stays a leaf. `test_the_shipped_furnace_glow_is_emissive` needs the game's `EMISSIVE_PALETTE_START`, so it moved to `model_motion_test.odin`.
- `render_frustum` and `run_length` needed no cut.
- Not moved: `haptics_*` (`Haptic_Request`, `HAPTIC_RUMBLE_MILLISECONDS` and `vibration_amplitude` of the input layer) and `system_keyboard_*` (`Ui_Rectangle`, `STEAM_DECK_ENVIRONMENT_VARIABLE`): cutting them changes signatures, not a pure move. They joined the ui cluster, and `raylib_log.odin` (only `log_printf` and raylib) the presentation cluster, because the name `platform` is now the package's cluster.

Prefixing: every use is qualified (`platform.log_printf`), no alias file. An alias (`log_printf :: platform.log_printf`) would have hidden the cost the pilot is meant to price, and it puts one game file in the middle of every cluster's edges. The prefixes were written by a script over the tokens (comments and strings skipped); the compiler found what it missed: `case MODELS_DIRECTORY:`, `? NO_STATE_DIRECTORY_PROBLEM :`, and three places where a parameter or local named `platform` (a `Window_Platform`) hid the package (`log_display_diagnostics` in `display.odin` and the start of `run_game` in `loop.odin`), where the local is now `window_platform`.

Measurements (this machine, once each, `time`):

| | Before | After |
|---|---|---|
| `./build.sh check` | 0.59 s | 0.60 s |
| `./build.sh test` | 36.2 s wall (runner 22.0 s), 1289 tests | 35.6 s wall (runner 21.5 s), 1289 tests (1290 after the sjson_text test split) |
| Qualified uses | 0 | 635 in 96 files: 458 in code (platform 302, generation_seed 112, model_vox 21, sjson_text 13, render_frustum 5, run_length 5), 177 in tests (platform 153, most of them `platform.join_path`) |
| Import lines of local packages | 1 | 113 (112 new) |
| Diff | | 129 files, +1174 / -945 |
| Lines moved | | about 1950: 1753 in the moved files, 144 in `jni_android.odin`, 31 of tests, `Log_Capture`, `hash_u64`, `sorted_object_keys`, `join_path` and one test |

The graph (`python3 tools/code_graph.py`): the largest strongly connected component is 176 of the 195 files, down from 185 of 193; outside it are the 18 package files and `main_android.odin`. Cluster edges against the allowed table fell from 22 edges and 1018 references to 19 and 973: the platform records are gone (their `text` parameter noise with them, since a package's names now resolve only in itself and its imports), content to world 105 to 94 (`join_save_path`), world to presentation 16 to 12 (`hash_u64`), content to presentation 18 to 16 (the model file names are `model_vox` now).

What was awkward:

- Odin imports are per file, so a package used across the game costs an import line in every file that names it (112 here), besides the prefix at every use.
- A local or parameter named like a package hides it, and the error ("'platform' of type 'Window_Platform' has no field 'log_printf'") appears only at the use. A full split would meet this with every short package name (`world`, `ui`, `content` are common local names).
- `odin test src` runs only the game package's tests: without `-all-packages` the 18 moved tests silently stop running (checked: `-define:ODIN_TEST_NAMES=run_length.test_run_length_single_value` finds no test without the flag). `build.sh test` and the flake's check phase pass it now; the Nix Odin version was not checked for the flag, CI will tell.
- Two rule tests (`test_static_runtime_imports_stay_out_of_windows`, `test_game_sources_do_not_call_make_directory_all`) read `#directory` without subdirectories, so after the move they silently skipped `platform/logging_posix.odin`, the one file the first rule exists for. They now walk the package directories.
- `#load` paths are relative to the file, so a moved test's `#load("../data/...")` became `../../data/...`.
- A package test that needs a game constant cannot stay in the package.
- Name stutter: `sjson_text.sjson_text`, `run_length.run_length_encode`, `render_frustum.frustum_from_matrix`. The pilot kept the names (pure moves); a real split would rename them.
- `#+build` tags needed nothing: they work per file in any package, and `check-android` and `check-windows` reach every package through its imports (each package here is imported by desktop files too; a package imported only from an Android tagged file would be checked only by `check-android`). `-vet -strict-style` raised nothing. The full Android build (`./build.sh android`) was not run; `check-android` passes, and `platform_android.odin` imports `../android_libc` by its new relative path.
- The tools: `code_graph.py` resolved names by bare word over one package; it now resolves a name after an import's name and a dot in that package and every other name in the file's own package. `check_dead_code.py` reads definitions from every package.

Recommendation for 0146: do not split the six layers into packages now. The pilot shows that the mechanics are cheap to write and cost nothing at build or test time, but the price grows with the references crossed, and the layers cross far more: the game clusters reference each other 5825 times (graph count, with some noise) against 464 for the seven leaves, so a full split qualifies roughly twelve times as many uses and adds an import per file per layer used, and it can only start once the graph is acyclic. Today 973 references in 19 edges run against the allowed table and 19 cluster pairs reference each other; Odin refuses the import cycle, so every one of them has to be refactored away first (0143 queue entries 1, 3 and 5). The ratchet (`code_graph.py --check`) already enforces the layering at the name level at no cost to the code. Keep the leaf packages, work through the queue with the ratchet, and move a layer into a package when its "Reaches into" record reaches nothing: the bottom layers (world storage, the content registries) are the candidates, one at a time, each priced as this pilot was.
