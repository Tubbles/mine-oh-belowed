# Suggestions

Open questions that need the user's decision, each with the lead architect's recommendation, followed by proposed next steps. Decided items move to `doc/log/`.

## Decisions needed

Balance and design questions are deferred (user, 2026-09-27): the play experience (sound, textures, models, animations), lore and depth come first, and game balancing belongs to late beta, just before the first release. We are before the first alpha, so nothing here is decided arbitrarily now.

Decided on 2026-09-27: tools gate block hardness as well as mining speed (work item 0051); infinite research empties the queue after each level (done).

Deferred to the design and balance phase, with the current behaviour kept until then: rocket returns (rare materials, schematics or both; today both); the vein size numbers (scatterings 2k to 5k units, deposits 20k to 60k, concentrations 100k to 300k, deep veins five times); the byproduct strictness default (strict: a machine whose byproduct output is full waits; lenient: byproducts that do not fit are voided and counted; today strict), pending the byproduct redesign noted in `DESIGN.md`; whether a late orbital survey contract pays a smaller survey radius instead of the full survey; where the infinite technologies sit in the tree (today behind rocket program).

## Follow ups from the M1 implementation

Raised by the work item notes (0005 to 0008), to be turned into work items when they matter:

- Water and light that reach an unloaded chunk stop at the border and do not resume when the chunk loads.
- A saved chunk has no relight path: only generation computes sky light, so save and load (M5) needs a stored height map per column or a relight pass.
- Greedy meshing no longer merges faces with different corner light, doubling mesh time. A light aware merge or a coarser light quantisation would win it back if meshing shows up in profiles.
- All air and all solid chunks are stored in full; a single block id representation would roughly halve memory.
- Water covers about 29 percent of the surface, hills are capped at sea level plus 64, leaves are opaque. All one number each, waiting for the couch impression.
- Data files are not strict about unknown keys yet (`json.unmarshal` ignores them); the configuration strictness rule needs a custom check.
- Bindings are hardcoded tables until configuration lands. The raylib gamepad table lacks Sneak on B. Fly mode does not mine instantly yet.
- The third person camera can still clip into walls at steep angles, and the targeting ray starts at the eye in third person.
- Diagnostics overlay backdrop is narrower than its longest lines.
- Fluid branches are served in coordinate order (0020), so a tank on one branch can starve a consumer on another until the tank's fill fraction passes the junction's. Proportional sharing at junctions would fix it.
- Quest chapters measure placements and production, not layout (0018); an entity graph query would let quests check that pieces are actually connected.
- Bindings are a list overridden per action (0025); an object keyed by action would merge better across layered files, and there is no way to unbind an action (a `none` control). The `context` field is displayed but does not gate actions.
- The log file grows without limit and argument errors before the log opens reach stderr only.
- Saves refuse any change to data ids or struct layout (0023); work item 0047 makes them survive additive changes.
- The load screen shows one long string per world; columns would read better on the couch. World setting choices step forward only; left and right should step back.
- A player built roof over a saved chunk does not darken it on reload (0023), the same gap as generation under a roof.
- The set of found schematics rides on the recipe registry value (0036) so fixed recipe machines can check it without a new parameter through every machine path; session state on a data table is a smell worth removing with an explicit availability parameter once the machine paths settle.
- Sulfur has no consumer yet (0031); sulfuric acid and batteries in phase 7 are the natural users. Fast belts remain a placeholder technology until a second belt speed exists, which needs belt placement and rendering to read the speed from the machine.
- `generate_chunk_blocks` grows the outcrop and crate lists inside its temporary allocator guard, so a caller that passes temporary allocated lists gets them corrupted; the streaming path passes heap lists and the 0045 determinism test avoids it.
- Drill placement by footprint (0048) checks the column, not the height: a drill on a platform above or in a cave below a vein taps it, and a surface drill can be placed over an exhausted vein (which the revival design wants). A height band around the surface would tighten it if the couch minds.
- Fonts (0077): the headless UI audit approximates text width with the default face's average advance (0.37 of the size); Michroma, Orbitron and Oxanium are wider (0.42 to 0.44), so overflow with them can slip past the audit until it takes a per family factor from fonts.sjson.
- Hot reload (0054): block light in loaded chunks is not recomputed after a content reload (an emission change waits for a remesh of light), and a changed vein type keeps registered veins' old records, so outcrops in chunks generated later can disagree with the registry until the world reloads.
- Command socket (0053): `place` does not count as a player placement for quests (use `chapter` to advance); a blueprint's `{vein}` origin needs the vein's chunks loaded, since it reads registered veins rather than the generator's starter veins; veins added by command are invisible to the map survey and the orbital survey, which read the generator.
- The orbital survey (0041) asks the generator for about 25 regions of vein placement on the main thread inside one tick; its cost at the 256 block radius was not measured. The catalogue buttons and the pad panel tabs have not been seen with the gamepad's focus movement.
- Tree roots done properly: the 0059 root logs at the foot of straight trunks were removed after the couch found them obscene (0083). Minecraft's vanilla mangrove (1.19) shows the shape that works: roots as a block type of their own, a tangle arching above ground and water, on a species designed around them. A wetland mangrove and a gnarled badlands tree would be the place to try it, with a root block shape from 0061's pipeline.
- Sun shadows, if they ever return (0097 removed the 0072 shadow map): they must be soft and low contrast, treating the sun as mostly ambient, never a hard directional map. The sky light propagation already shades under crowns and in gullies.

- Benchmark launch pad module (0050): the base has no launch pad because a pad assembles and launches only from its panel's buttons (`start_assembly`, `request_launch` have no simulation caller) and its rocket fuel needs a sulfur and light oil chain of its own. Decision needed: may the benchmark press those buttons in code, or should the pad get an automatic mode?
- Refinery stall found by 0050: a refinery whose petroleum gas goes only to a flare stack stops, since the flare burns only above 90 percent of its port and the network evens the fill fractions, so the refinery's gas port never has room for a craft's 45 litres. The oil module works around it; a flare that burns at any fill, or a refinery that waits for less than a whole craft's room, would fix it for players too.
- Splitter round robin per lane found by 0050: an inserter putting plate, slag, plate, slag on one lane makes the splitter send every plate one way. A round robin per item, or per lane item, would split mixed lanes evenly.
- Benchmark build time (0050): every placement rebuilds the belt, fluid and electric networks, so size 64 takes minutes to build. Batching the rebuilds until a blueprint's last command would cut it, and would speed the command socket's blueprints too.
- Deck link against an older glibc (0076): the release binary linked on the couch machine needs GLIBC_2.43 symbol versions (atan2f, asinf, acosf, sqrtf in libm; glibc 2.43 is from 2026, and the Deck was on 2.37 in early 2024). If ldd on the Deck says so, the --target install should link inside a container whose glibc is no newer than the Deck's; the Odin compiler at ~/opt/odin is a static binary (checked 2026-09-28), so it runs in such a container, and tools/build_raylib.sh has the distrobox pattern to copy.

## Next steps

1. Settle the decisions above, then update `DESIGN.md` and log them.
2. Continue the design topic list top down: review `doc/content.md` and `doc/quests.md`, then sound as feedback, the ending, strings and units in data, determinism and fixed point.
3. Work item 0002, the Steam Controller input spike, before anything else in code. It decides whether the SDL3 direct path works on this machine with Steam running.
4. Work item 0001, toolchain skeleton and `build.sh`, so CI turns green and the Steam shortcut (0003) has something to launch.
5. Write `doc/world.md` (generation, strata, vein reservoirs, prospecting, water, spawn requirements), `doc/logistics.md` (belt lines, ramps, lifts, inserters, splitters), `doc/fluids.md` (network model, phases, gravity) and `doc/lore.md` (the venture, Mission Control, naming glossary) before their milestones start.
- Windows test run in CI (0102): the `windows` job builds only. Running `odin test` there needs `core:testing`'s own libc import kept away from the dynamic runtime (it links `libucrt.lib` on Windows) and the tests' Unix path and socket assumptions sorted per platform.
- Windows artifact without a GitHub login (0102): a workflow artifact needs a signed in browser or `gh` to download. Attaching the zip to a GitHub release on a tag would give the phone a plain URL.

## Follow ups from the Android app series (0112 to 0115)

Written at the end of the series (2026-09-29 and 2026-09-30). Each names why it was not done in the series.

- Upstream report to Odin: `odin bundle android` hands aapt `<dir>/lib` as a directory argument, so its contents land at the APK root (`bundle_command.cpp`); `build.sh android` works around it with `lib/lib/arm64-v8a/libmain.so`. Out of scope for the series, needs a minimal reproduction on the Odin side.
- Upstream report to Odin: for `-subtarget:android -build-mode:shared` the link passes `-Wl,-init,'_odin_entry_point'` but the library has no INIT entry (`llvm-readelf -d`), so the runtime never starts on its own; the quotes may reach the linker literally (`linker.cpp`, not checked). The game uses `--wrap=main` instead (`src/main_android.odin`).
- Upstream report to Odin: `core:sys/posix`'s `sigaction_t` follows glibc (handler first) while bionic's 64 bit struct puts `sa_flags` first, so `sigaction` on Android installs SIG_DFL; `install_crash_handlers` (`src/logging_posix.odin`) skips Android for that reason. Also `os.make_directory_all` (`core/os/path_linux.odin`) opens `/` to walk an absolute path, which Android's SELinux policy refuses; `make_directories_below` (`src/data_load.odin`) is the workaround.
- Upstream report to odin-fsw: the Windows backend waits 50 ms per `get_events` and drops the subtree flag on re-issue, both patched in `shared/fsw/backend_windows.odin` (README there, 0111). Not sent because the Windows runtime behaviour was never checked on a Windows machine.
- Android time zone: `load_local_zone` (`src/local_zone_posix.odin`) finds no tz database on Android, so the title screen's dates show UTC; the system property `persist.sys.timezone` (`__system_property_get`) names the zone and `core:time/timezone` could load it from a bundled region file. Not needed for the first runs.
- Android app icon: the manifest (`tools/android/AndroidManifest.xml`) sets no `android:icon`, so the launcher shows the default; an adaptive icon under `tools/android/res/mipmap-*` needs art first.
- Android crash traces: `src/android_libc/android_libc.odin` stubs `backtrace`, so the game's own trace lines are empty on Android and only the system tombstone in logcat has frames; `libunwind` from the NDK or parsing the tombstone could restore the log's trace. Left out until a crash on the phone asks for it.
- `adb` from the container: `platform-tools` is installed under `~/opt/android/sdk` (0113) but no `adb install` or `adb logcat` path is written up in `doc/build.md`; it needs USB debugging on the phone and a udev rule on the host. Sideloading the APK was enough for the series.
- Steam Deck touch: `--touch-overlay` on the desktop build reads the mouse as touch point 0 (`src/touch_overlay.odin`), since raylib's desktop platform reports no touch points; the Deck's screen would need the raylib GLFW touch path or SDL's finger events. Not needed while the Deck has its pads.

## Follow ups from the touch overlay series (0118 to 0123)

Written on 2026-09-30 at the end of the series. Things the implementers and reviewers noticed and left alone because no work item asked for them; none is approved scope.

- Haptics renewal: `apply_vibrator_haptics` (`src/haptics_android.odin`) plays a new 100 ms one shot every frame while a request holds, the SDL3 rumble pattern. On some phone motors a restart every 16 ms may feel rougher or weaker than one steady vibration; renewing only when the amplitude changes or when the 100 ms is nearly used up would be the fix. Waits for the phone test of version code 221.
- Gamepad rumble on the phone: a gamepad attached to the phone does not rumble, since raylib has no rumble API; only the vibrator plays haptics there.
- Layout editor panel: the element panel (`src/ui_touch_layout_editor.odin`) sits in the middle of the screen, so elements behind it are reached with focus navigation only, not with the pointer. Moving the panel to the side the selected element is not on would fix it.
- Layout editor and hot reload: a data file reload while the editor shows a draft of Default keeps the old copy in the draft until the editor is reopened.
- Target status lines in tap mode: with `touch_interaction = tap` the crosshair is not drawn, but the target's status lines (`draw_target_status`, `src/hud.odin`) still sit at the screen centre where the crosshair was.
- Test duplication: `test_no_touch_overlay_element_covers_a_hotbar_slot` (`src/touch_overlay_test.odin`) converts the hotbar rectangles to pixels inline instead of calling `hud_hotbar_pixel_rectangles` (0119).
- `os.args` after an Android relaunch: `core:os` builds `os.args` once at the first runtime start, so on a second `main` in the same process (0116) its `[0]` points at the first launch's `arg0` on raylib's stack. Nothing reads it (the game reads `os.args[1:]`, empty on Android); a static literal in `__wrap_main` would remove the dangling pointer.

## Follow ups from the touch inventory and misclick series (0124 to 0133)

- The gamepad glyph bar and the touch button row cross the HUD's hotbar, which draws under open screens, at UI scales above 1 (0125 review). The row avoids it at scale 1 by sitting right of the hotbar; a layout that hides the HUD hotbar under slot screens, or moves the bar, would settle every scale.
- Widgets registered inside a clipped scroll region keep their full rectangle for hit tests, so a row scrolled out of the visible area can take a press or a hover through the clip if nothing later covers it (0132 review; pre-existing). Clipping the widget rectangles to the region's area in `ui_interact` would close it.
- The tap sound (`ui_frame_sound_events`, at resolve time) and the activation (`ui_interact`, at declaration time) read the widget list at different moments, so an overlapping later widget can make one fire without the other (0132 review; pre-existing).
- A d-pad step on the UI scale or text scale slider during a finger drag is overwritten by the drag's release (`ui_layout_slider`, 0132 review). Rare; a drag could cancel on a step.
- The mouse gets no feedback inside the slop on a slider press: nothing moves until the pointer leaves 16 units or the button lifts (0132 review). A mouse only rule could keep the press behaviour.
- A merge of two players' drops hands the stack's dropper mark to the later dropper, so the earlier one can take it back at once (0128 review; multiplayer only).
- Two Backspaces from the phone's IME in one frame count as one (0133), since the field reads a per frame flag; a count would fix it.
