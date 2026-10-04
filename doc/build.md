# Build

How to build, check, test and ship the game: the host toolchain, `build.sh`, the command line, the play build on the couch and the Deck, Nix, CI and the Windows build. The Android app has its own file, [android.md](android.md).

- Every build and check goes through `build.sh`, which passes the `shared` collection; a bare `odin check src` does not compile.
- `build/` holds build output; `bin/` is the installed play build's.
- After every commit on `main` that changes `src/` or `data/`, `tools/install_play_build.sh` installs the couch's build ([CLAUDE.md](../CLAUDE.md)).

## Host toolchain

The couch machine runs Bazzite.

| Tool | Where | Notes |
|---|---|---|
| Odin dev-2026-09 (nightly a2fb372) | `~/opt/odin-linux-amd64-nightly+2026-09-01`, linked as `~/opt/odin` | The `odin-linux-amd64-dev-2026-09.tar.gz` release asset. `build.sh` uses `${ODIN:-$HOME/opt/odin/odin}` |
| clang 23 | Homebrew | Odin drives the linker through it |
| SDL3 3.4.16 | `/usr/lib64/libSDL3.so.0` (Fedora 44) | `vendor:sdl3` links `system:SDL3` |
| raylib 6.0 | `shared/raylib/` | Built from source, committed (below) |
| Blender 5.2 LTS | Flatpak `org.blender.Blender` with host file access | Only to regenerate models ([Models](#models)) |

### The shared collection

- `shared` is the collection Odin reserves for packages outside its own; `build.sh` points it at the repository's `shared/` with `-collection:shared=<repository>/shared` on every command. The toolchain stays untouched.
- `shared/raylib/` holds the toolchain's binding (`raylib.odin`, `raymath.odin`, `rlgl/rlgl.odin`, `LICENSE`), copied with one patch: `raylib.odin` and `rlgl/rlgl.odin` carry a `when` branch importing the Android archive (0113), which must be put back after an Odin upgrade ([shared/raylib/README.md](../shared/raylib/README.md) has the redo steps). Beside it: our `platform.odin` (`glfwGetPlatform`, `glfwGetCurrentContext`, `glfwGetWindowSize`, `glfwGetProcAddress`, which the binding lacks, left out on Android) and the libraries. The copy exists because the binding names its library by a path next to itself, which no linker flag can swap.
- `shared/raylib/README.md` records each build (raylib commit, cmake flags, compiler, date, size) and how to redo the copy after an Odin upgrade.
- `shared/fsw/` is odin-fsw, the file watcher, vendored with patches for the Windows backend; `shared/fsw/README.md` records the commit, the patches and how to update. It has no foreign library. Check it alone with `~/opt/odin/odin check shared/fsw -no-entry-point -vet -strict-style`, plain and with `-target:windows_amd64`.

### raylib archive

- `linux/libraylib.a` (about 3.4 MB, committed, so a fresh checkout needs no cmake) has GLFW with both the Wayland and the X11 backend. It links the system `libdl`, `libpthread` and `libX11`; GLFW opens `libwayland-client`, `libwayland-cursor`, `libwayland-egl`, `libxkbcommon` and `libdecor` with dlopen at run time, so `ldd` shows no Wayland library and a machine without them falls back to X11. Windowed decorations on Wayland come through libdecor, and GLFW has fallback decorations without it.
- `tools/build_raylib.sh` clones raylib tag `6.0` from https://github.com/raysan5/raylib (shallow) into `tmp/raylib-src/`, configures in `tmp/raylib-build/`, builds, copies the archive into `shared/raylib/linux/` and rewrites the README's build record. Flags:

```
-G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF
-DPLATFORM=Desktop -DGLFW_BUILD_WAYLAND=ON -DGLFW_BUILD_X11=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
```

- The generator is named because the user environment sets `CMAKE_GENERATOR=Ninja`, which the container lacks.
- The host has no cmake and no development headers, so by default the script runs itself with `--host` inside the distrobox `mine-oh-belowed-raylib` (image `registry.fedoraproject.org/fedora-toolbox:44`, created on first use with cmake, gcc, make, git and the Wayland, wayland-protocols, xkbcommon, libdecor, Mesa GL and X11 development packages; the home directory is shared). `tools/build_raylib.sh --host` runs the steps on a machine that has the tools.
- `windows/raylib.lib` is raylib's own MSVC release library and `android/libraylib.a` the Android build ([android.md](android.md)); both records are in `shared/raylib/README.md`.

### Linker shims

Gotcha: Bazzite ships runtime libraries without the development symlinks (`libX11.so.6` exists, `libX11.so` does not), so linking fails with `cannot find -lX11`.

- `build.sh` makes `tmp/linker-shims/` with `libX11.so -> /usr/lib64/libX11.so.6` and `libSDL3.so -> /usr/lib64/libSDL3.so.0` and passes `-extra-linker-flags:"-L<repository>/tmp/linker-shims"` to both builds, `test` and `bench`. No package is layered onto the image.
- `test` needs them too: Odin links a foreign library only when a reachable procedure uses it, and tests reach raylib (and with it X11).

## build.sh

```
./build.sh                # debug build (-debug) to build/mine-oh-belowed
./build.sh debug          # the same
./build.sh release        # optimised build (-o:speed) to build/mine-oh-belowed
./build.sh check          # odin check src -vet -strict-style
./build.sh check-windows  # the same check for -target:windows_amd64, on any host
./build.sh check-android  # the same check for Android arm64 (android.md)
./build.sh test           # odin test src -all-packages
./build.sh bench          # test_factory_benchmark only, optimised
./build.sh android        # the signed APK (android.md)
./build.sh model-check [machine]  # the debug build, then --model-check (all by default)
```

- Every command passes the collection; both builds pass `-vet -strict-style` and the `BUILD_INFO` define (below).
- `test` passes `-all-packages`: plain `odin test src` runs only the game package's tests, not those of the packages under `src/` it imports (`src/platform/` and the others, [code_map.md](code_map.md), Packages). The checks need nothing extra: `odin check src` checks every package the game imports, tests included, for the target it checks.
- `check-windows` catches code that does not compile for Windows without a Windows machine; the Nix build runs the same check, so CI guards it on every push.
- `bench` runs `test_factory_benchmark` with `-o:speed`: size 1 on the field world (0179), its table logged, a failure when it averages 8 ms per tick or more, half the 60 Hz budget. Plain `test` (and CI) runs it unoptimised and only logs. `bench` is a heavy benchmark and follows the benchmark rules in [CLAUDE.md](../CLAUDE.md).
- On a Windows host (Git Bash) `build.sh` makes no shims, writes `build/mine-oh-belowed.exe` and adds `-subsystem:windows` to `release`.

## Source checks

Python 3 scripts without dependencies, run by hand from anywhere; none is part of `build.sh` or CI.

- `python3 tools/check_docs.py` checks the Markdown docs against the repository: relative links, backticked paths, file names and identifiers. Exit 1 lists each finding.
- `python3 tools/check_dead_code.py` lists the definitions of `src/**/*.odin` (the game package and the packages under it) that nothing references, and those outside the test files that only `*_test.odin` files reference. It scans the declarations at file level, including those inside file level `when` and `foreign` blocks, and counts whole word uses in the code of every `.odin` file under `src/` (comments and strings stripped, the definition's own body and every definition line of the same name left out) plus `build.sh`, `tools/` and `data/shaders/`. `@(test)`, `@(export)`, `@(init)` and `@(fini)` definitions are exempt; its allow lists hold what no attribute covers (`main`) and the test seams, each with its reason. Exit 1 when it finds anything.
- `python3 tools/code_graph.py` prints the file dependency graph of `src/` grouped into clusters by file name prefix, each package under `src/` a cluster of its own, whose names resolve only in the package itself and in the packages it imports: the cluster edges with reference counts, the clusters that reference each other, the strongly connected components with the files outside the largest, and the files of the largest with the fewest edges into it. `--files` adds each file's edges, `--json` dumps the graph, `--tests` includes the test files; these exit 0. `--check doc/code_map.md` compares the cluster edges that the map's allowed dependency table does not allow with the map's record of them (the "Reaches into" line of each cluster): it exits 1 when an edge is new or above its recorded count, 2 when the map cannot be read, 0 otherwise, and marks the edges that fell below their record. A refactor that lowers a count lowers the record by hand ([code_map.md](code_map.md)).

## Models

The OBJ machine models (0204, [presentation.md](presentation.md), Machine models) are built by Python scripts that run inside Blender.

- `tools/blender <script> [argument ...]` runs a script headless (`--background --factory-startup --python-exit-code 1`, the arguments after `--`): the host's `blender` when it is on the PATH, else `flatpak run org.blender.Blender`. The Flatpak sees the home directory but not `/tmp`, so a script it runs lives under the repository.
- `tools/blender tools/make_models.py [model ...]` writes `data/models/<model>.obj` and `.mtl` for the named machines, all of them without names; an unknown name exits 1 listing the known ones.
- The committed OBJ and MTL files are the product: the build, the tests and CI never run Blender, only a regeneration does. The same script in the same Blender version writes the same bytes (the scene is cleared per machine, the booleans use the exact solver).
- The export: `bpy.ops.wm.obj_export` with forward `NEGATIVE_Z` and up `Y` (Blender's front +X and Z up become the game's +x and y up), scale 1, modifiers applied, triangulated, normals on, no UVs, colours or groups beyond the object names, materials on, paths stripped.
- Layout: `tools/models/palette.py` (the materials of `DESIGN.md`'s palette, byte colours and the glow flag), `tools/models/kit.py` (the frame, `box`, `cylinder`, `cone`, `cut`, `join`, `join_part`, `material`, `export`, `wedge`, `ring`, `pipe`, `hatch`, `rib_row`, `strip`, `opening`, `model_random`, `expect_footprint`), `tools/models/records.py` (the machine records, below), `tools/models/machines/` (one script per machine, `MACHINES` in its `__init__.py`, each `build(machine)` taking its record). Each machine ends as one object `body` and, with a moving part, one `part`.

### The workbench

The model workbench (0207) checks a model in the game's own mesher and motion code and renders it with the game's renderer, so an agent writes the script and reads the result without directing a run of the game.

- The records: `tools/sjson.py` reads SJSON as the game does (an implicit root object, bare or quoted keys, `=` or `:`, optional commas, both comment forms, JSON values; a duplicate key is an error naming the line and column); `tools/make_placeholder_textures.py` reads `data/` through it too. `tools/models/records.py` reads `data/machines.sjson` into frozen dataclasses (footprint, motion with its pivot, ports, open cells, a pod's fixtures with their rotated sizes, light) and maps them into the kit's Blender frame: `pivot`, `port(machine, name)` and `port_face` (the face's centre and normal), `open_cell_box`, `fixture_box` (0198), `footprint_box`. A port is named `<direction>_<fluid>` (`<direction>` without a fluid), a repeat taking `_2`, `_3` in file order. `tools/make_models.py` hands each script the first record naming its model (`machine_for_model`), and `kit.join_part(objects, machine, pivot)` refuses a part on a motion that moves none, a spin or swing without its pivot, and a pivot that is not the record's. `python3 tools/models/records_test.py` checks both modules against golden values of the shipped records.
- `--model-check=<machine|all>` (`model_check.odin`, `loop_model_check.odin`) runs no window. `all` takes every machine with a model; the OBJ models and the arm are checked, a voxel model is skipped and counted (named explicitly it is one `load` problem). The checks: `load`, the loader's refusal (0204's fit); `budget`, `DESIGN.md`'s maxima (a body and a part at most 3200 and 200 triangles, a pod's body 25600 (0221, `model_body_triangles_maximum`), at most 8 materials, counted as distinct colour and glow pairs), and only within it the rest; `sweep`, the part posed by `motion_transform` at 16 phases (index / 16) crossing the body (edges through triangle interiors, so contact and coplanar faces pass); `footprint`, the posed part's bounds through `model_footprint_problem`; `open_cells`, a body or part triangle at rest inside an open cell box shrunk by the footprint tolerance, and as well inside a pod's fixture box (0198, the detail naming `fixture box N` instead of `open cells box N`), so no pod geometry stands where a fixture's model stands; `sweep` also, for a pod, each fixture's part over its motion, open fraction 0 to 1 in 17 steps, placed at its fixture box, against the pod's body (0221, `pod_fixture_part_problems`, the detail naming `fixture N (<machine>)`), the body filtered to the part's swept bounds first; `arm`, the upper arm, forearm, gripper and both fingers at 16 cycle fractions on a frame of `foundation_pitch_millimetres` crossing the base. Each problem is one line `<machine>: <check>: <detail>` on stdout, at most one per check and phase (or box), then `model check: N checked (N obj, N arm), N voxel models skipped, N problems`. Exit 2 for a bad selection (an unknown machine, one without a model, an id that is not `[a-z0-9_]+`), 1 for any problem, 0 otherwise. `test_the_shipped_models_pass_the_checks` runs the same checks in the suite.
- `--model-preview=<machine>[,<machine>] --model-preview-directory=<path>` (`loop_model_preview.odin`) opens a 1280 by 720 window, as `--planet-preview-screenshot` does, and draws the machine alone on a pad of foundation cells (two cells round the footprint, an arm's reach plus one round its post) one cell below it, lit by the field's full sky light, with the player's capsule on its -z side at the back corner for scale. Five cameras (`front` from the front right, `front_left` from the front left (0212, the reference sheet's hero angle) and `back` from the back left, three quarter views, and `top`, framing the scene's bounding sphere at a 40 degree field of view, `close` 2 m in front of the front face at half the model's height, no higher than the player's eye height of 1.6 m) at rest and at phases 0.25, 0.5 and 0.75 (an arm at its grab, lift and drop fractions) give 20 files per machine, `<machine>_<camera>_<phase>.png` (`rest`, `0.25`, `0.5`, `0.75`). Three warm up frames are drawn before the first export; each file is read from the back buffer, encoded with `ExportImageToMemory` and written through `write_file_replacing`. A machine whose model did not load or a file that cannot be written exits 1.
- Both flags run no world: they cannot be combined with each other, with `--benchmark`, the planet preview's flags, `--server`, `--join` or a world's flags.
- `tools/make_models.sh [model ...]` runs `tools/make_models.py` in Blender and then `./build.sh model-check`, exiting as the check does, so a committed model passes. `tools/model_preview.sh <machine>[,<machine>] [machine ...]` builds the debug binary and runs the preview under `xvfb-run -a` (a virtual display of its own, also when a display is set, so no window opens on the couch), into `$MODEL_PREVIEW_DIRECTORY` (default `tmp/model_preview`).
- The agent's loop: write the machine's script against its record, `tools/make_models.sh <model>`, `tools/model_preview.sh <machine>`, and read the PNG files before handing back.
- The sealed lab (0212, `CLAUDE.md`, Work flow, Model items): a machine remade from a reference sheet is modelled outside the repository's influence. `tools/model_lab/make_furnace_lab.sh` builds `tmp/furnace_lab/` from copies of `tools/blender`, `tools/sjson.py`, `tools/make_models.py`, the kit, the palette and the record reader, the records (a machine's `open_cells` stripped first when it has any, so the modeller decides what to leave empty), the reference images of `work/art/` (untracked, so the script runs from the main checkout), a registry with one machine and a stub script, and the three lab files of `tools/model_lab/`: `BRIEF.md` (the look in the user's words, the footprint, the renderer's limits, the budget, the commands), `check.py` (the body's triangle count against the budget, the material count, the footprint bounds, the object names, exit 1 on a problem) and `render.py` (Blender's workbench engine from the five preview cameras with a capsule for scale, `tools/blender render.py`, under `xvfb-run -a` if Blender wants a display). The modeller works only in the lab; the main agent copies the lab's OBJ into the item's worktree for the game's own check and preview. `tools/model_lab/make_pod_lab.sh [lab directory]` builds `tmp/pod_lab/` (or the directory given) for the pod (0221) from the same copies, the brief, check and renderer of `tools/model_lab/pod/`, and the records with the pod's `open_cells`, `fixtures`, `lights` and `interior_light_share` stripped by key with the comments above them (the footprints as the records have them: the pod 12 by 12 by 8, the hatch 1 by 2 by 2); it builds in a staging directory and replaces the old lab only when every step succeeded, and reads the reference images from the main checkout's `work/art/`, so it runs from a worktree too; its accepted scripts (`pod.py`, `pod_hatch.py` and their shared `pod_geometry.py`) and palette entries were copied into the repository and the regenerated OBJs compared byte for byte with the lab's. Work item 0214 makes the lab a tool for any machine.

## Command line

Parsed with `core:flags` in Unix style; `--help` or `-h` prints the usage page. A bad command line (unknown items and chapters included) exits 2, a failed start 1.

| Flag | Meaning |
|---|---|
| `config` | Prints the configuration files found and the effective values, no window |
| `--version` | Prints the build stamp, no window |
| `--set=<key>=<value>` | The last configuration layer, repeatable |
| `--input=sdl3`, `--input=raylib` | Input backend (default SDL3 with raylib fallback; [input.md](input.md)) |
| `--seed=<n>` | Seed of a new world, an unsigned 64 bit decimal; the default is a fixed constant, so runs reproduce |
| `--name=<world>`, `--load=<world>` | Name a new world, or load a saved one |
| `--debug-terrain` | The fixed 8 by 2 by 8 chunk test terrain, nothing streams |
| `--unlock-all` | Every technology researched and every item discovered |
| `--touch-overlay` | The touch overlay on for the run; on the desktop the mouse is its touch while the left button is held ([touch_overlay.md](touch_overlay.md)) |
| `--watch-data=<off\|presentation\|all>` | What reloads while the game runs ([architecture.md](architecture.md), Hot reload) |
| `--dev` | Developer mode ([developer_tools.md](developer_tools.md)) |
| `--chapter=<n>` | A new world with the quests before chapter n completed with their rewards, plus chapter n's kit from `data/dev_kits.sjson` |
| `--give=<item>:<count>` | Items into the inventory on the first tick, the rest into the drop capsule, repeatable |
| `--benchmark=<size>` | The headless factory benchmark, size 1 until M14 (below) |
| `--planet-preview` | A window flying over the home planet's terrain field, no game (below) |
| `--planet-preview-screenshot=<path>` | The planet preview from a fixed camera without input, the frame saved to the path (below) |
| `--planet-preview-walk` | The planet preview, or its screenshot, starting in the walk mode (below) |
| `--planet-preview-daylight=<percent>` | The planet preview's daylight, the sky light's share, 0 to 100 (default 100; below) |
| `--planet-preview-pitch=<degrees>` | The walk screenshot's tilt once the pit is dug, -89 to 89 (default -50, down into the pit; below) |
| `--model-check=<machine\|all>` | Checks the machine's model in the game's mesher and motion, no window (below) |
| `--model-preview=<machine>[,<machine>]` | Renders each machine's model from five cameras at four phases, then exits (below) |
| `--model-preview-directory=<path>` | Where `--model-preview` writes its PNG files (below) |
| `--server`, `--port=<n>` | Host the world of the command line without a window ([commands.md](commands.md), Multiplayer) |
| `--join=<address>[:port]` | Join a server's world instead of showing the title ([commands.md](commands.md), Multiplayer) |

- `--load` cannot be combined with `--seed`, `--name`, `--debug-terrain` or `--chapter`. `--chapter` and `--give` start a new world like `--seed`.
- `--model-check`, `--model-preview` and `--model-preview-directory`: the model workbench (0207), [Models](#models), The workbench.
- `settings.font` and `settings.monospace_font` take family ids from `data/fonts/fonts.sjson`; an unknown id is refused like any configuration error by `mine-oh-belowed config`, while the game logs it, starts with the default family and toasts it once on the title screen (`load_start_fonts`, 0149).
- `--benchmark=<size>` runs no window and no controller: the shipped data, two simulated minutes of warm up and ten measured, then the table on stdout (milliseconds per tick per system, the average and worst tick, the entity counts, the idle machines). The table ends with the state hash after the ticks, so two runs of one build can be compared. Since the slice (0179) the benchmark runs on the field world and a size above 1 is refused at the command line naming M14, until the factories stand on frames ([architecture.md](architecture.md), Performance). It exits 1 when the factory cannot be built or a machine idles, and cannot be combined with `--load`, `--seed`, `--name`, `--chapter` or `--debug-terrain`. Quote numbers from the release build (`./build.sh release`, then `./build/mine-oh-belowed --benchmark=1`), under the same benchmark rules. Method: [architecture.md](architecture.md), Performance.
- `--planet-preview` (0169) opens a window with the fly camera 40 m above the pole of the home planet of `data/planets.sjson` at the default sample spacing, and streams, meshes and draws the terrain field with the level of detail ([presentation.md](presentation.md), Chunk meshes): mouse or right stick to look, the move keys or left stick to fly, Jump and Sneak up and down, Sprint faster, the speed growing with the height; Escape closes it. Raylib input only, no UI but a line of counts. `--seed` picks the world seed; the other world flags are ignored, and `--benchmark` runs instead when both are given. Since the slice (0179) the preview runs a field session of its own (a new world of the seed on the home planet, not saved): its player is spawned with the starter kit plus an iron pickaxe, 100 foundations and 50 belt poles (`give_planet_preview_items`), ticked by `simulation_tick`, streamed and drawn as a session is ([presentation.md](presentation.md), The field session), so it shows what the game plays. The new world lays the pod and the starter veins round the planet's home (latitude 83 in the shipped record, about 975 m from the pole at 8 km), so the preview's start over the pole shows neither; the game's spawn does.
- `--planet-preview-screenshot=<path>` runs the preview without input from a fixed camera: above the pole's local ground by the finest level distance less 2 m, so the finest nodes lie under it, looking along the horizon tilted 8 degrees down towards longitude 132 (as the interactive start camera does), so the level seams lie ahead and so does the home, whose basins below the sea level (0189) lie about 1 km from the pole with the default seed at 8 km, near the last distance; the pole's own ground holds no sea within 1 km. It runs 120 frames and on until the field has streamed (every selected node meshed, nothing pending), at most 1200 frames, saves the frame to the path (`LoadImageFromScreen` and `ExportImage`, the format by the extension, `.png`) and exits 0; a frame that cannot be saved exits 1 with a log line. From that height the horizon lies near the last distance (1024 m), so the globe shows past it only where the ground beyond is visible.
- The walk mode (0170): G in the preview switches between the free camera and the field player standing on the generated surface under the camera, heading where the camera looks; G again puts the free camera at the player's eye. The session ticks on a fixed step at `tick_rate` (at most five ticks a frame) on the raylib input while walking (the world stands still under the free camera), the field streams round the eye, and the camera follows the eye with the player's up, so walking round the planet tilts the world and keeps the horizon level ([architecture.md](architecture.md), The player on the field). The line of counts names the mode. Walking, the hotbar's selected stack decides the tool as in the game (0179, [architecture.md](architecture.md), The field session): Mine (left mouse button, right trigger) digs with the brush, Place (right mouse button, left trigger) places the held material, a foundation, a run's end or a torch, Rotate Building (R, North) cycles the brushes of `data/game.sjson`, and Hotbar Next (the wheel down, `]`, right shoulder) picks the slot. Dug material lands in the inventory, so placing it needs it in the hotbar; a second line names the brush, the held material, the material and tint under the reticle, the cubic metres held per material and why the latest edit was refused. `--planet-preview-walk` starts the preview in the walk mode; with `--planet-preview-screenshot` the player stands on the pole's ground under the screenshot camera, looking along the horizon, one tick a frame without input, and once it stands and the field round it has streamed (a dig skips chunks not loaded yet, which would arrive undug) a sphere of radius 2.5 m is dug 3.3 m ahead of its feet and 1.5 m below them (open at the top), a torch is placed at the pit's lowest air sample and the camera tilts down into it, 50 degrees unless `--planet-preview-pitch=<degrees>` (0176, -89 to 89) sets another tilt (`dig_planet_preview_pit`, 0173); the frame is taken once the field has streamed, the light's queues are empty and the changed chunks have meshed again.
- The field light in the preview (0173): walking, Place with the torch held places a torch at the air sample in front of the targeted ground and Mine aimed at a torch takes it back (0179; the L key is gone). `--planet-preview-daylight=<percent>` sets the sky light's share (the field shader's `daylight`), 0 to 100, default 100; at 0 only torches light, so a torch's room shows at night. `--planet-preview-walk --planet-preview-screenshot=tmp/preview_0173_night.png --planet-preview-daylight=0` renders the pit by its torch alone.
- Foundations in the walk mode (0174): with the foundation item selected (the second line says `holding foundation` and counts the frames), Place puts one: against the face of the targeted frame's cell, which joins that frame, or free on the targeted ground, which starts a new frame with its up along the radial and the player's heading rounded to 15 degrees. A see-through ghost shows where it goes; the foundations are drawn as a box per cell (`render_frames.odin`). The walk screenshot lays a pad once the player stands (`lay_planet_preview_foundations`): a free foundation 9 m ahead, past the pit of 0173, the five by five square round it snapped to its frame and a column of three on a corner, so the shot shows a frame. On the pad it places two arms facing along the pad (0175, `lay_planet_preview_arms`): one at rest and one held at full reach over the pad's far edge by a pose override for the screenshot only (`Model_Frame.reaching_arm`; the session's tick would rest it, having nothing to move), working, so its lamp's point light falls on the ground.
- Runs in the walk mode (0176): with a belt or pole item selected the tool is the belt run tool, with a pipe item the pipe run tool (`holding belt run`, `holding pipe run`; the second line counts the runs). Place picks the run's start (the pole or belt end the selection assist offers near the reticle, else a new pole on the targeted frame cell or ground), a see-through ghost draws the curve to the reticle, red when it would be refused, Place again lays it and Back forgets the start; a refusal names its reason. The walk screenshot lays a second pad of five by five foundations 12 m from the first along the diagonal between its forward and its right, a free pole off each pad's facing corner and a belt run between them with iron plates along both lanes (`lay_planet_preview_run`), so a level shot shows two islands joined by a swept belt: `--planet-preview-walk --planet-preview-screenshot=tmp/preview_0176.png --planet-preview-pitch=-10`.

## Data directory and build stamp

- The data directory is the first of: `$MINE_OH_BELOWED_DATA` (wins even when missing, so a typo fails loudly), `./data`, `<executable directory>/data` (the unzipped Windows build), `<executable directory>/../share/mine-oh-belowed/data` (the Nix package). Android copies its own ([android.md](android.md)).
- The build stamp is the version, the short commit (`+dirty` with uncommitted changes) and the UTC build time. It shows under the title, at the bottom of the pause menu, in the log's header line and on `--version`, so a bug report names the build.
- `build.sh` passes commit and time as one `BUILD_INFO` define, a string with a space, since a define holding only digits arrives as a number. `MINE_OH_BELOWED_COMMIT` overrides the commit (the play build installer builds from a `git archive` without `.git`; CI passes it so a line ending difference never marks the build dirty). The Nix build uses the flake's revision and last modified date.

## Play build

`tools/install_play_build.sh [commit]` builds a commit (default HEAD) in release mode from a `git archive` into `bin/play/builds/<install time>-<commit>/` with its own copy of `data/`, switches `bin/play/current` to it in one rename, and writes the launcher `bin/mine-oh-belowed`, which resolves the link at launch.

- The install never waits for the game: a running game keeps its build directory and the next launch takes the newest. The two newest builds stay; older ones go unless a game still runs from them.
- The installed game never reads the working tree, so edits to `src/` and `data/` cannot break a couch session.
- The launcher unsets `SDL_GAMECONTROLLER_IGNORE_DEVICES` and sets `SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=0` ([input.md](input.md), Steam Input beside the game).

### Display

- GLFW tries Wayland first, so a Wayland desktop gets a native window, and under gamescope (the couch) the game can be a Wayland client of gamescope. With the high DPI flag a laptop at 2880 by 1920 and 170 percent renders 2880 by 1920 while the window is 1694 by 1129 in the desktop's units.
- `MINE_OH_BELOWED_X11=1 bin/mine-oh-belowed` is the way back to X11: the launcher unsets `WAYLAND_DISPLAY` and sets `XDG_SESSION_TYPE=x11`. Unsetting alone is not enough, since GLFW's Wayland connection falls back to the `wayland-0` socket.
- Under XWayland a scaled desktop hands the game the scaled screen and upscales it. `MINE_OH_BELOWED_GAMESCOPE` holds gamescope's own arguments and runs the game inside gamescope at the panel's full size: `MINE_OH_BELOWED_GAMESCOPE="-f -W 2880 -H 1920" bin/mine-oh-belowed`. Without gamescope on the path it prints one line to stderr and runs the game directly.
- The game logs `display: monitor W x H, window W x H, render W x H, scale X x Y, session <x11|xwayland|wayland>` after the window opens and after every display change. The session is the platform GLFW took (`glfwGetPlatform`); `xwayland` is X11 with `WAYLAND_DISPLAY` set, so the `MINE_OH_BELOWED_X11` route reports `x11`. On the couch at scale 1 render equals window.

## Steam shortcut

- `tools/add_steam_shortcut.py` adds or updates the "Mine oh Belowed" non-Steam shortcut in `~/.steam/steam/userdata/<user>/config/shortcuts.vdf`, pointing at `bin/mine-oh-belowed` beside its own `tools/` directory. `--user-id` picks the Steam user, `--dry-run` shows what would be written.
- It parses the binary VDF and refuses to write unless the existing file round trips through its parser byte for byte; other shortcuts stay untouched.
- Steam must be closed while it runs (`pgrep -x steam`), or Steam overwrites the file on exit.
- Steam Input for the shortcut is disabled by hand ([input.md](input.md)).

## Steam Deck

The Deck runs the same play build, installed over SSH from the couch machine (0076).

- `tools/install_play_build.sh --target deck@steamdeck:mine-oh-belowed/bin [commit]` builds here exactly as a local install, copies the build directory and the launcher with `rsync` over `ssh`, switches the remote `current` link in one rename and removes older remote builds by the same rule; nothing installs locally. `--help` prints the usage.
- The path after the colon takes the place of `bin/` (absolute, or relative to the remote home; a leading `~/` means the home), so the example puts the launcher at `~/mine-oh-belowed/bin/mine-oh-belowed`.
- The remote side needs `bash`, `rsync`, `find` and `pgrep`. On the Deck: a password for `deck` (`passwd` in Desktop Mode's Konsole), `sudo systemctl enable --now sshd`, and optionally `ssh-copy-id deck@steamdeck`.
- The remote install is tested only against stub `ssh` and `rsync` acting on a local directory, not against a Deck.
- The shortcut: `ssh deck@steamdeck mkdir -p mine-oh-belowed/tools`, `scp tools/add_steam_shortcut.py deck@steamdeck:mine-oh-belowed/tools/`, then run it there in Desktop Mode with Steam closed and `--user-id` set to the Deck's Steam user id (the directory under `~/.steam/steam/userdata/`). The controller layout: [input.md](input.md), Steam Deck.
- The binary links `libSDL3.so.0`, `libX11.so.6`, `libm` and `libc` dynamically, with glibc symbol versions up to `GLIBC_2.43` (`atan2f`, `asinf`, `acosf`, `sqrtf`; `objdump -T`). `ldd ~/mine-oh-belowed/bin/play/current/mine-oh-belowed` on the Deck names a missing library or version. Whether SteamOS ships a glibc that new and `libSDL3.so.0` is unchecked.
- The game applies a Steam Deck preset on its first start there ([ui.md](ui.md), Steam Deck preset).

## Nix

- `flake.nix` provides `packages.default` (the game), `devShells.default` (odin, raylib, glfw, sdl3, libX11) and `checks`.
- The flake patches the binding in `postPatch`: `shared/raylib/raylib.odin` and `rlgl/rlgl.odin` link `system:raylib` instead of the committed archive, and `platform.odin` links `system:glfw`, since nixpkgs raylib is built against an external GLFW with both backends. libX11 stays a build input for the binding's import block. A renamed foreign import line breaks `substituteInPlace` loudly.
- The build runs `odin build` with `-o:speed -vet -strict-style`, then `odin test src -all-packages` and the Windows target check, all with `-collection:shared=shared`, and installs the data under `share/mine-oh-belowed/`.
- Nix is not installed on the couch machine; CI validates the flake.

## CI

`.github/workflows/ci.yml` runs on every push and pull request:

| Job | Runner | Does |
|---|---|---|
| `nix` | `ubuntu-latest` | `nix develop --command odin version`, then `nix build` (build, tests, Windows check) |
| `windows` | `windows-latest` | The Windows package (below), no tests: they assume Unix paths and sockets |
| `android` | `ubuntu-latest` | `check-android` and the APK ([android.md](android.md)) |

## Windows (GameNative on Android)

The user plays on an Android phone through GameNative, which runs the Windows x86-64 build under Wine and Box64 (0102).

- The `windows` job, in Git Bash: checkout; the MSVC environment (`ilammy/msvc-dev-cmd@v1`, x64), which Odin links with; Odin's `odin-windows-amd64-dev-2026-09.zip` and `SDL3-devel-3.4.16-VC.zip`, both SHA-256 checked; `SDL3.lib` copied into the toolchain's `vendor/sdl3/` (the binding imports it next to itself and Odin's release does not ship it); `MINE_OH_BELOWED_COMMIT=<short commit> ./build.sh release`.
- The package `dist/mine-oh-belowed/` holds `mine-oh-belowed.exe`, `SDL3.dll`, `data/` and a `README.txt`, uploaded as `mine-oh-belowed-windows-x64-<short commit>`. raylib comes from the committed `shared/raylib/windows/raylib.lib`; nothing of SDL is committed.

### The C runtime

Gotcha: raylib's release library is built for the dynamic C runtime (`/DEFAULTLIB:MSVCRT` inside it; the binding drops Odin's `libcmt`), so nothing may pull the static one.

- `core:c/libc` and `core:sys/posix` pull `libucrt.lib` by their import alone, whether a procedure is used or not. A `when` block does not help, since the import stays.
- `raylib_log.odin` declares its formatter against `ucrt.lib` instead of importing `core:c/libc`.
- Files that need `core:sys/posix` carry `#+build !windows` on their first line, each with a `#+build windows` counterpart ([architecture.md](architecture.md), Platforms).
- `test_static_runtime_imports_stay_out_of_windows` (`platform_paths_test.odin`) fails when a file in `src/` or a package directory under it imports either package without a tag that excludes Windows.

### Fetching and installing

- Download the artifact from the workflow run (Actions, the run of the commit, Artifacts), or `gh run download <run id> --name mine-oh-belowed-windows-x64-<short commit>` (`gh run list --workflow ci.yml` lists runs). It arrives as a zip holding `mine-oh-belowed/`.
- Copy the folder to the phone and add a custom game in GameNative pointed at `mine-oh-belowed/mine-oh-belowed.exe`. `data/` and `SDL3.dll` stay beside it.
- The release build opens no console window, so its stderr goes nowhere; `log.txt` has every line.

| File | Under Wine |
|---|---|
| `log.txt` | Beside `mine-oh-belowed.exe`, since GameNative's Wine container lives in the app's private data the phone's file manager cannot reach |
| `screenshots\`, `texture_edits.sjson`, `data_edits\` | `%LOCALAPPDATA%\mine-oh-belowed\` (`C:\users\<user>\AppData\Local`) |
| `config.sjson`, `config.d\`, `saves\` | `%APPDATA%\mine-oh-belowed\` (`C:\users\<user>\AppData\Roaming`), so they roam on real Windows |

- `MINE_OH_BELOWED_SAVES` and `paths.saves` still win for saves; a leading `~/` in `paths.saves` is not expanded on Windows.

### Smoke test

- `tools/wine_smoke_test.sh [path/to/mine-oh-belowed.exe]` runs the executable under Proton 11's Wine from Steam's library (`~/.steam/steam/steamapps/common/Proton 11.0/files/bin/wine`) in the prefix `tmp/wineprefix`, without a display: `--version`, then a start that loads the data and ends at the window, then it prints the `log.txt` beside the executable.
- The default executable is the newest under `tmp/artifact`, where `gh run download <run id> --dir tmp/artifact` puts an artifact.
- Gotcha: `core:time/timezone`'s Windows path asks ICU (`icu.dll`, `ucal_getDefaultTimeZone`) for the local zone, which Wine does not implement and aborts on, so `local_zone_windows.odin` takes the offset from `GetTimeZoneInformation`.

### What the Windows build lacks

- The command socket: `COMMAND_SOCKET_SUPPORTED` is false, so developer mode opens none and logs nothing about it (0108); `tools/moc` is Linux only.
- The stderr redirect into the log and the raw back trace on SIGSEGV or SIGILL; an assertion or panic of the main thread still logs its back trace.
- The couch launcher and the play build installer (Linux only).
- Testing here: the build runs only on the phone; this machine checks the target with `./build.sh check-windows`.

## Android app

The native Android build, its toolchain, the phone's files and the export's storage access are in [android.md](android.md).
