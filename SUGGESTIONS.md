# Suggestions

Open questions that need the user's decision, each with a recommendation, then follow ups noticed during the work. Decided items move to `doc/log/`; follow ups become work items when they matter, and none is approved scope until then.

## Deferred to the balance phase

Balance and design numbers wait for late beta, just before the first release (user, 2026-09-27, `doc/log/2026-09-27.md`): the play experience, lore and depth come first, and nothing here is decided arbitrarily before the first alpha. The current behaviour stays until then.

- Rocket returns: rare materials, schematics or both (today both).
- Vein sizes: scatterings 2k to 5k units, deposits 20k to 60k, concentrations 100k to 300k, deep veins five times.
- The byproduct strictness default (today strict), pending the byproduct direction in `DESIGN.md`.
- Whether a late orbital survey contract pays a smaller survey radius instead of the full survey.
- Where the infinite technologies sit in the tree (today behind rocket program).
- Pump heads (0139): offshore pump 6 metres, tar pit pump 6, pump 30.
- The fuel generator (0140): 75 kW at 25 percent fuel efficiency against the offshore pump's 60 kW. The intent is fixed: it covers the pump and little else, and its fuel goes four times as fast as a boiler's.

## Decisions needed

- Benchmark launch pad module (0050): the benchmark base has no launch pad, because a pad assembles and launches only from its panel's buttons (`start_assembly`, `request_launch` have no simulation caller) and its rocket fuel needs a sulfur and light oil chain of its own. May the benchmark press those buttons in code, or should the pad get an automatic mode?
- Sneak on touch (0134): the Default touch layout has no sneak control. A sneak zone, a hold on the jump zone, or a HUD button beside the hotbar would give touch players the sneak edge walk; none was asked for.

## Follow ups: world, simulation and saves

- Water and light that reach an unloaded chunk stop at the border and do not resume when the chunk loads.
- A loaded chunk recomputes its sky light with the generation procedure, so a player built roof over a saved chunk does not darken it on reload (0023), the same gap as generation under a roof.
- Greedy meshing does not merge faces with different corner light, doubling mesh time. A light aware merge or a coarser light quantisation would win it back if meshing shows up in profiles.
- All air and all solid chunks are stored in full; a single block id representation would roughly halve memory.
- Leaves are opaque to light (they are solid), waiting for the couch impression.
- Game data files are not strict about unknown keys (`json.unmarshal` ignores them); the configuration's strictness rule needs a custom check there.
- `generate_chunk_blocks` grows the outcrop and crate lists inside its temporary allocator guard, so a caller that passes temporary allocated lists gets them corrupted; the streaming path passes heap lists and the 0045 determinism test avoids it.
- Fluid branches are served in coordinate order (0020), so a tank on one branch can starve a consumer on another until the tank's fill fraction passes the junction's. Proportional sharing at junctions would fix it.
- Refinery stall found by 0050: a refinery whose petroleum gas goes only to a flare stack stops, since the flare burns only above 90 percent of its port and the network evens the fill fractions, so the gas port never has room for a craft's 45 litres. The benchmark's oil module works around it; a flare that burns at any fill, or a refinery that waits for less than a whole craft's room, would fix it for players too.
- Splitter round robin per lane found by 0050: an inserter putting plate, slag, plate, slag on one lane makes the splitter send every plate one way. A round robin per item, or per lane item, would split mixed lanes evenly.
- Drill placement by footprint (0048) checks the column, not the height: a drill on a platform above or in a cave below a vein taps it, and a surface drill can be placed over an exhausted vein (which the revival design wants). A height band around the surface would tighten it if the couch minds.
- The set of found schematics rides on the recipe registry (`Recipe_Registry.schematics_found`, 0036) so fixed recipe machines can check it without a new parameter through every machine path; session state on a data table is a smell worth removing with an explicit availability parameter once the machine paths settle.
- Quest chapters measure placements and production, not layout (0018); an entity graph query would let quests check that pieces are actually connected.
- The seismic survey (0038) draws each shot's veins as their true circles; a coarser outline for veins not yet resolved is open.
- The orbital survey (0041) asks the generator for about 25 regions of vein placement on the main thread inside one tick; its cost at the 256 block radius was not measured. The catalogue buttons and the pad panel tabs have not been seen with the gamepad's focus movement.
- Hot reload (0054): block light in loaded chunks is not recomputed after a content reload (an emission change waits for a remesh of light), and a changed vein type keeps registered veins' old records, so outcrops in chunks generated later can disagree with the registry until the world reloads.
- Command socket (0053): `place` does not count as a player placement for quests (use `chapter` to advance); a blueprint's `{vein}` origin needs the vein's chunks loaded, since it reads registered veins rather than the generator's starter veins; veins added by command are invisible to the map survey and the orbital survey, which read the generator.
- Benchmark build time (0050): every placement rebuilds the belt, fluid and electric networks. Batching the rebuilds until a blueprint's last command would speed the benchmark build and the command socket's blueprints.

## Follow ups: presentation, input and UI

- Tree roots done properly: the 0059 root logs at the foot of straight trunks were removed after the couch found them obscene (0083). Minecraft's vanilla mangrove (1.19) shows the shape that works: roots as a block type of their own, a tangle arching above ground and water, on a species designed around them. A wetland mangrove and a gnarled badlands tree would be the place to try it, with a root block shape from 0061's pipeline.
- Sun shadows, if they ever return (0097 removed the 0072 shadow map): soft and low contrast, treating the sun as mostly ambient, never a hard directional map. The sky light propagation already shades under crowns and in gullies.
- Fonts (0077): the headless UI audit approximates text width with the default face's average advance (`APPROXIMATE_ADVANCE_FACTOR`, 0.37 of the size); Michroma, Orbitron and Oxanium are wider (0.42 to 0.44), so overflow with them can slip past the audit until it takes a per family factor from fonts.sjson.
- The world overlay's backdrop (`draw_world_overlay`, `src/diagnostics.odin`, the F4 statistics overlay) is `font_size` times 24 wide, narrower than its 79 character hint line.
- The targeting ray starts at the eye in third person.
- Fly mode does not mine instantly.
- Bindings are a list overridden per action (0025); an object keyed by action would merge better across layered files, and there is no way to unbind an action (a `none` control).
- World setting choices on the new world screen step forward only; left and right should step back.
- The log file grows without limit, and argument errors before the log opens reach stderr only.

## Follow ups: Windows, Deck and Android

- Windows test run in CI (0102): the `windows` job builds only. Running `odin test` there needs `core:testing`'s own libc import kept away from the dynamic runtime (it links `libucrt.lib` on Windows) and the tests' Unix path and socket assumptions sorted per platform.
- Windows artifact without a GitHub login (0102): a workflow artifact needs a signed in browser or `gh` to download. Attaching the zip to a GitHub release on a tag would give the phone a plain URL.
- Deck link against an older glibc (0076): the release binary needs GLIBC_2.43 symbol versions ([doc/build.md](doc/build.md), Steam Deck). If ldd on the Deck says so, the Deck install should link inside a container whose glibc is no newer than the Deck's; the Odin compiler at `~/opt/odin` is a static binary, so it runs in such a container, and `tools/build_raylib.sh` has the distrobox pattern to copy.
- Steam Deck touch: `--touch-overlay` on the desktop build reads the mouse as touch point 0 (`src/touch_overlay.odin`), since raylib's desktop platform reports no touch points; the Deck's screen would need the raylib GLFW touch path or SDL's finger events. Not needed while the Deck has its pads.

Written at the end of the Android app series (0112 to 0115), each with why it was not done then:

- Upstream report to Odin: `odin bundle android` hands aapt `<dir>/lib` as a directory argument, so its contents land at the APK root (`bundle_command.cpp`); `build.sh android` works around it with `lib/lib/arm64-v8a/libmain.so`. Needs a minimal reproduction on the Odin side.
- Upstream report to Odin: for `-subtarget:android -build-mode:shared` the link passes `-Wl,-init,'_odin_entry_point'` but the library has no INIT entry (`llvm-readelf -d`), so the runtime never starts on its own; the quotes may reach the linker literally (`linker.cpp`, not checked). The game uses `--wrap=main` instead (`src/main_android.odin`).
- Upstream report to Odin: `core:sys/posix`'s `sigaction_t` follows glibc (handler first) while bionic's 64 bit struct puts `sa_flags` first, so `sigaction` on Android installs SIG_DFL; `install_crash_handlers` (`src/logging_posix.odin`) skips Android for that reason. Also `os.make_directory_all` (`core/os/path_linux.odin`) opens `/` to walk an absolute path, which Android's SELinux policy refuses; `make_directory_path` (`src/platform_paths.odin`) is the workaround.
- Upstream report to odin-fsw: the Windows backend waits 50 ms per `get_events` and drops the subtree flag on re-issue, both patched in `shared/fsw/backend_windows.odin` (README there, 0111). Not sent because the Windows runtime behaviour was never checked on a Windows machine.
- Android time zone: `load_local_zone` (`src/local_zone_posix.odin`) finds no tz database on Android, so the title screen's dates show UTC; the system property `persist.sys.timezone` (`__system_property_get`) names the zone and `core:time/timezone` could load it from a bundled region file. Not needed for the first runs.
- Android app icon: the manifest (`tools/android/AndroidManifest.xml`) sets no `android:icon`, so the launcher shows the default; an adaptive icon under `tools/android/res/mipmap-*` needs art first.
- Android crash traces: `src/android_libc/android_libc.odin` stubs `backtrace`, so the game's own trace lines are empty on Android and only the system tombstone in logcat has frames; `libunwind` from the NDK or parsing the tombstone could restore the log's trace. Left out until a crash on the phone asks for it.
- `adb` from the container: `platform-tools` is installed under `~/opt/android/sdk` (0113) and the `adb install` and `adb logcat` path is in `doc/android.md` (CI and installing); it needs USB debugging on the phone and a udev rule on the host. Sideloading the APK was enough for the series.

## Follow ups from the touch overlay series (0118 to 0123)

- Haptics renewal: `apply_vibrator_haptics` (`src/haptics_android.odin`) plays a new 100 ms one shot every frame while a request holds, the SDL3 rumble pattern. On some phone motors a restart every 16 ms may feel rougher or weaker than one steady vibration; renewing only when the amplitude changes or when the 100 ms is nearly used up would be the fix. Waits for the phone test of version code 221.
- Gamepad rumble on the phone: a gamepad attached to the phone does not rumble, since raylib has no rumble API; only the vibrator plays haptics there.
- Layout editor panel: the element panel (`src/ui_touch_layout_editor.odin`) sits in the middle of the screen, so elements behind it are reached with focus navigation only, not with the pointer. Moving the panel to the side the selected element is not on would fix it.
- Layout editor and hot reload: a data file reload while the editor shows a draft of Default keeps the old copy in the draft until the editor is reopened.
- Target status lines in tap mode: with `touch_interaction = tap` the crosshair is not drawn, but the target's status lines (`draw_target_status`, `src/hud.odin`) still sit at the screen centre where the crosshair was.
- Test duplication: `test_no_touch_overlay_element_covers_a_hotbar_slot` (`src/touch_overlay_test.odin`) converts the hotbar rectangles to pixels inline instead of calling `hud_hotbar_pixel_rectangles` (0119).
- `os.args` after an Android relaunch: `core:os` builds `os.args` once at the first runtime start, so on a second `main` in the same process (0116) its `[0]` points at the first launch's `arg0` on raylib's stack. Nothing reads it (the game reads `os.args[1:]`, empty on Android); a static literal in `__wrap_main` would remove the dangling pointer.

## Follow ups from the touch inventory and misclick series (0124 to 0133)

- The gamepad glyph bar and the touch button row cross the HUD's hotbar, which draws under open screens, at UI scales above 1 (0125 review). The row avoids it at scale 1 by sitting right of the hotbar; a layout that hides the HUD hotbar under slot screens, or moves the bar, would settle every scale.
- Widgets registered inside a clipped scroll region keep their full rectangle for hit tests, so a row scrolled out of the visible area can take a press or a hover through the clip if nothing later covers it (0132 review). Clipping the widget rectangles to the region's area in `ui_interact` would close it.
- The tap sound (`ui_frame_sound_events`, at resolve time) and the activation (`ui_interact`, at declaration time) read the widget list at different moments, so an overlapping later widget can make one fire without the other (0132 review).
- A d-pad step on the UI scale or text scale slider during a finger drag is overwritten by the drag's release (`ui_layout_slider`, 0132 review). Rare; a drag could cancel on a step.
- The mouse gets no feedback inside the slop on a slider press: nothing moves until the pointer leaves 16 units or the button lifts (0132 review). A mouse only rule could keep the press behaviour.
- A merge of two players' drops hands the stack's dropper mark to the later dropper, so the earlier one can take it back at once (0128 review; multiplayer only).
- Two Backspaces from the phone's IME in one frame count as one (0133), since the field reads a per frame flag; a count would fix it.

## Follow ups from the crafting, power and data browser series (0129 to 0131, 0138 to 0140)

- A crafting run behind a waiting front is repaired only by the next queue action, and a deficit in a run that is not at the front surfaces only once it reaches the front (0138 review). Only adjacent runs of one recipe merge, so a plan can hold two runs of one recipe apart.
- The electric pump keeps the per tick truncation of its satisfaction scaled rate, since its Pumping state feeds the 0139 head line and its power demand (0140 review); the offshore and tar pit pumps pump a full tick's litres once per power credit step. Aligning the pump would make all three yield exactly rate times satisfaction.
- The factory benchmark counts a generator in the Idle state as a reserve standing by behind a lower dispatch order (0140), so a generator with no load at all is no longer reported idle either.
- The Data files screen keeps its tree until the screen is rebuilt or the game exits; it is small (0129 review). The overlay log line comes once per read, so a file read twice at start logs twice.
- A content file's Save reloads at once rather than marking the data changed for the Reload button (0130); a `watch_data` gate would restore the item's wording. A string holding a character past printable ASCII (the strings file's `×`) or longer than 512 cannot be edited in the game and toasts. After a failed start turned the overlay off, it stays off for the run: Discard the broken file and restart; a Save meanwhile still writes and takes effect at the next start.
- The export (0131) copies about 475 files in one frame on the main thread, a second or more on the phone's shared storage; a worker would remove the stall. The overlap check does not resolve symbolic links. Android before 11 has no All files access check, so a refused write toasts with its path there. On the phone the user sets the Syncthing folder's absolute path once on the Data files screen and grants All files access when the page opens.

## Follow ups from the documentation pass (0141)

- `tools/check_docs.py` runs by hand and is not part of `build.sh` or CI, so a stale link or name in a doc surfaces only when someone runs it. A CI step (the nix check) or a test that shells out to it would catch it on every push.
- The belt surface scroll, the splitter's speed and the loose item's look have no doc since the pass; the old text was stale. `presentation.md` is the home if they are ever written up (cluster C review).

## Follow ups from the architecture cleanup (0142 onwards)

- The save round trip test never covered oil machines: an oil fixture procedure sat in `save_test.odin` without a caller, and 0142 removed it as dead. A save test that places a pumpjack, a refinery and a pipe run and compares the state hash after a reload would close the gap (`save_test.odin`, `simulation_state_hash`).
- `tools/check_dead_code.py` and `tools/code_graph.py` run by hand like `check_docs.py`; the same CI step would keep all three honest.
- The glyph bar and the button glyphs ignore rebindings: `glyph_key` and `glyph_icon` (`ui_widgets.odin`) take a device and a button but no bindings, so a rebound action keeps showing the default glyph (ui audit, `doc/audit/ui.md`). Passing the bindings in and looking the glyph up from the bound control fixes it; the decision is whether the glyph shows the first binding or all of them.
