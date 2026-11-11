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

- The role accents under astro-industrial punk (0211): the 0205 pass gave every machine role an accent colour (mining ochre, smelting brick red, power yellow with black hazard, fluids teal, logistics grey with yellow edges, science white with cyan). The booklet's kept images carry no such accents: the clean world's colour is pale alloy with cyan, green and amber lights, the rough world's is iron and stone. Decide whether a role accent survives as a marking on the clean parts (a painted band, a trim colour) so a machine's role still reads at 30 m, or whether the silhouette and the lights carry it alone. Recommendation: keep one accent per role as a thin trim on the clean parts, decided per machine on its reference sheet, and let the furnace (0212) be the first test.
- The stone furnace at 5 by 5 m on the field (0212): on bare ground the flatness test reads its four corners and centre against the shipped `bare_ground_flatness_millimetres` of 250, which over 5 m allows a slope of about 2.8 degrees, and founding it takes 100 foundation cells against the 16 wooden foundations of the starting kit, while the first quest asks to place one. Options: leave it, raise the flatness, a tolerance per machine record, or more starting foundations. Recommendation: the couch first; if the pod's crater refuses the furnace, a tolerance per record (the furnace stands on four feet and bears a slope a belt pole would not) before a bigger kit.
- Benchmark launch pad module (0050): the benchmark base has no launch pad, because a pad assembles and launches only from its panel's buttons (`start_assembly`, `request_launch` have no simulation caller) and its rocket fuel needs a sulfur and light oil chain of its own. May the benchmark press those buttons in code, or should the pad get an automatic mode?
- A shutter sound for the pod's doors (0231): the doors become camera irises opening and shutting in 0.15 s, and the only hatch sound is the 0.9 s placeholder hiss of `hatch_slide.wav`, which outlasts the motion. The sound table has no trim key, so a short click or snap is a new asset for the user to pick or record; until then the hiss plays once per open and once per shut.

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

- Upstream report to Odin: `core:sys/posix`'s `sigaction_t` follows glibc (handler first) while bionic's 64 bit struct puts `sa_flags` first, so `sigaction` on Android installs SIG_DFL; `install_crash_handlers` (`src/platform/logging_posix.odin`) skips Android for that reason. Also `os.make_directory_all` (`core/os/path_linux.odin`) opens `/` to walk an absolute path, which Android's SELinux policy refuses; `make_directory_path` (`src/platform/platform_paths.odin`) is the workaround.
- Upstream report to odin-fsw: the Windows backend waits 50 ms per `get_events` and drops the subtree flag on re-issue, both patched in `shared/fsw/backend_windows.odin` (README there, 0111). Not sent because the Windows runtime behaviour was never checked on a Windows machine.
- Android time zone: `load_local_zone` (`src/platform/local_zone_posix.odin`) finds no tz database on Android, so the title screen's dates show UTC; the system property `persist.sys.timezone` (`__system_property_get`) names the zone and `core:time/timezone` could load it from a bundled region file. Not needed for the first runs.
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
- `write_texture_edits_file` (`texture_generate.odin`) writes the texture edits file in place with `os.write_entire_file` instead of `write_file_replacing`, against the hand-back rule (presentation audit, `doc/audit/presentation.md`, refactor 1). One line fix.
- Belt items may step at frame rates above 60: the belt surface scrolls with the interpolation alpha (`belt_scroll_offset`, `render_belts.odin`) while the items on it are drawn at their tick position (presentation audit). Read in the code, not seen on screen; worth a look on the couch at 120 Hz before it becomes a work item.
- The shader copies of the variation hash and the light curve (`chunk.fs`, `water.fs` against `texture_variation_hash` and `light_curve`) have no test that keeps them equal; a test that evaluates both on a few inputs would catch a drift (presentation audit).
- The content loaders accept unknown keys (`json.unmarshal` skips them) and check name keys only in tests, so a typo in `items.sjson` is silent until the item is used (content audit). Refusing unknown keys as the configuration does is one shared loader change; the decision is whether the data edits overlay (0130) should also refuse, since a typo there would then brick the overlay at start (the fallback of 0130 covers that).
- `generation.odin` names six blocks by id in code (stone, deep stone, water, sand, landing pad, gold quartz), against the rule that content stays in data (content audit). The generator's block roles belong in `game.sjson` or `biomes.sjson`.
- Deferred from the pilot package split (0145): the package names stutter at the call sites (`sjson_text.sjson_text`, `run_length.run_length_encode`, `render_frustum.frustum_from_matrix`, 13 uses); renaming inside the packages is a follow up the pilot kept out of scope as a pure move. `haptics_*` and `system_keyboard_*` stay in the game package because leaving it changes their signatures (`Haptic_Request` and `Ui_Rectangle` come from the ui cluster); they move once those types move down, queued under the pure moves of the 0143 queue.
- The full layering split is not recommended yet (0145's Implementation notes): the game clusters reference each other about 5,800 times against 464 references into the seven leaves the pilot moved, and Odin refuses import cycles, so a layer can move into a package only when its "Reaches into" record in `doc/code_map.md` says nothing. The ratchet in `tools/code_graph.py` enforces the layering meanwhile at no cost. Decision for the user, as input to 0146.
- `store_unsigned` sits in `configuration.odin` since 0148 (the lower of its two users by the allowed table) while its pair `load_unsigned` stays in `save_binary.odin`, and its panic text still says "save:". Either the configuration stops needing it (a `mem.copy` of the value does the same on the little endian targets) or the pair moves to a leaf package together; the panic text follows whichever is chosen.

## The paused audit queue (2026-10-01, re-read 2026-10-02)

The M12 refactor queue stopped after 0162 to keep tokens for smaller items. On 2026-10-02 the rebuild toward the smooth world (`doc/log/2026-10-02.md`) changed what the rest of the queue is for: architecture questions that survive the decisions stay high priority, the plugin system is on the back burner. Counted against the six audits' ranked lists (section 5 of each file under `doc/audit/`): 18 of 55 entries done.

- Into M13 as lockstep needs them: 0166 (queued screen writes, no longer optional, its one frame of latency accepted by the model), the per tick event list, and 0163 (the per frame machine view) if the viewports want it.
- To re-read against the field world before they are kept or closed: 0164 (the cell occupant index becomes per frame cell), 0165 (the chunk arrival list becomes the chunk ready event of the simulated set), the world audit's block registry and cell queue entries (the material table and the water field replace them).
- Waiting with the plugin system: the kind table, component locations and the burner step (simulation audit 2 to 4), the topology change seam (simulation 6), the screen table and theme copy (ui 3 and 4), the SJSON table reader and the command table (content 4 and 8), the player tick's cut named in 0155.
- Moot with the world rewrite: the world audit's quality refactors (world 6 to 9) and the presentation entries about chunk meshes (presentation 9 and 10 are re-read with the new mesher).
- Still to verify, since 0145 and 0147 may have covered them: simulation 1's one electric rule, presentation 2's pure moves, content 2's platform moves.
- Optional quality refactors the user may pick at any time: loop 6 and 9; simulation 8 (simulation 9, the furnace, is the user's call and not recommended); presentation 5, 6 (half done by 0161), 7, 8; ui 5, 6, 9; content 3, 5, 6, 7, 9.

## Suggestions from the switch to the field world (0179, third part)

The work the switch left that an agent would do anyway became work items on 2026-10-03 (0180 the home spawn, 0181 sounds and cues, 0182 the field player's prediction, 0183 the command socket on the field, 0184 the preview at the home, 0185 the restore off the main thread); the benchmark above size 1 and the footprints at real frame cell sizes are named for M14 in the 0179 item. What stays here needs a decision or a measurement first.

- Local time by longitude: the field shader's daylight is the shared clock's at every longitude (`prepare_field_frame`, `loop_field_session.odin`), so a player on the far side of the planet has noon with the others. The sun's direction per viewer would follow from the planet's rotation and the player's up. Decide whether the slice's shared noon is wanted on a planet players share (a remote player on the night side cannot see), before M15's day and night matter.
- The save writes each changed field chunk whole (`encode_field_chunk` in `encode_field_file`); a delta against a fresh generation would make `field.bin` smaller for a lightly dug chunk at the cost of generating it at save time. Measure a saved world's size after a session before choosing.
- Placing dug material needs a drag from the inventory grid into the hotbar, since a dig credits the inventory as any item (`field_mining.odin`). A dug material could go to the hotbar first, as a block game's pickup does; a design choice for the user after the playtest.
- The field's water and light over the set cost about 1.3 ms a tick for one player in the debug build (the benchmark's players row); a set per player multiplies it in split screen and multiplayer when the players stand apart. Measure four players apart in the release build before deciding on a budget.
- The field shader samples all seven material tiles at every fragment (42 tile reads, `field.fs`), against 24 before the ores; on the phone a branch on the weight with explicit derivatives (`textureGrad`) would skip the absent materials. Measure on the phone first.
- Short white dashes sit on the far horizon at left and right in the planet preview at pitch -10 (`tmp/preview_main_e110f60.png` of 2026-10-03, after 0176 landed), likely the seams between the coarse level of detail nodes or their skirts (`world_field_lod.odin`, `field_skirt_faces_changed`); unverified, the playtest will show whether the game's horizon has them, and a confirmed one becomes a bug item.

## Suggestions from the multiplayer series (0188, 0185, 0186, 0187, 0182, 0190; 2026-10-03)

- Builds and test runs load every core of the couch machine while the user plays (asked 2026-10-03). This session pinned itself to cores 4 to 7 at nice 10 by hand, which does not survive the session. `build.sh` could pin and renice itself whenever a game process runs on the machine (a `pgrep` of the play build and of `build/mine-oh-belowed`), with a flag to turn it off. Decide whether the user wants that, or a build cores variable they set in the shell instead.
- A headless game under Xvfb opens the system's gamepads through SDL and takes the user's Steam Controller while they play (seen 2026-10-03, headless 0187 shots). A `--no-gamepad` flag (or the SDL joystick device hint set empty in `tools/moc`'s recipe) would keep the assistant's games off the controller. Decide the form; the dev flag is the smallest.

## Suggestions from the placement editor (0215, 2026-10-04)

- The HUD's glyph bar above the hotbar (0219) shares the band of the target lines under the crosshair at UI scale 1.2 and 1.5: on a screen H units tall the band ends at H/2 + 194 and the bar's first row tops at 0.95H - 216, so they overlap wherever H is under 911, which is every screen at those scales (at 1920 by 1080 scale 1.5 with a furnace held on the keyboard the row at y 468 to 512 sits on target lines 1 and 2). A long target line can cross the bar. Two options: lift the target lines (start them higher, or above the crosshair, at the large scales), or give the large scales a HUD layout of their own (the glyph bar moved elsewhere, a narrower hotbar). Decide after seeing it on the couch.
- The tools radial's steer adds up the whole look delta since it opened, the gyro's included, and never decays (`tools_radial` in `hud.odin`); the dead centre is 45 px of gathered look. With gyro look on, tilting the controller while D-pad Up is held can carry the highlight off the centre, so a release meant to cancel selects an entry. Try it on the couch before deciding whether the gyro's delta should be left out of the steer or the steer should decay while the stick rests.

## Suggestions from the arrival seen from the chair (0223, 2026-10-05)

- From the chair the five portholes sit about 0.5 m above the seated eye and their sleeves tilt up, so during the fall they show sky, horizon and flames, not the crater coming up. If the ground should show, the pod needs one more porthole low and ahead of the chair (a modelling item on the accepted pod, `tools/models/machines/pod.py`) or a tilt along the path. Decide after the first playtest from the chair.

## Suggestions from the pod's tilt (0270, 2026-10-05)

- The horizon earlier in the fall: through the chair's porthole it shows only in the last half second, since its sight line lies 11 degrees above the base plane and base first on a steep path the portholes face the sky. Knobs: `arrival_rest_tilt_degrees` up to 25 drops the sight line 14 degrees below the base plane once the ease completes; the ease rides on `arrival_real_seconds` (6 s); a lower porthole ahead of the chair (the 0223 suggestion) would show it through the glow. A feel decision for the couch.
- The seated camera's up: it stays the planet's during the fall and after the hit, so looking sideways the cabin rolls round a level view while the horizon stays level. The chair's up instead (the frame's up for the strapped and the seated player until they stand) would keep the cabin upright and tilt the world outside, as a strapped passenger sees it, moving the roll change to the unbuckle. One presentation item if wanted.

## Suggestions from the crater at the hit (0271, 2026-10-05)

- The hit's apply at 333 mm: 61k samples through `field_world_set_sample`, 121 ms in the debug build on the couch machine, unmeasured in release and on the phone. If the phone hitches at the bang, spread the apply over the settle's ticks (the pod's chunk first, the rest by coordinate), deterministic since every machine applies the same chunks in the same tick. Measure on the phone first.

## Suggestions from the debris (0272, 2026-10-05)

- The dust puffs along the rim are drawn as the arrival dust always was, a soft disc per puff; at 64 puffs of 1.2 to 4.7 m along a rim of a few metres they overlap into large round translucent discs with visible edges (the headless shots at 1.5 and 2 s), more a cluster of bubbles than a curtain. A noise cut edge on the disc, or fewer larger puffs with a softer falloff, would read as dust; the puff shader is the place, not the count.
- The clods at rest read a shade darker than the ground round them (the rim shots at 4 and 9 s). A clod's face is lit `0.5 + 0.5·max(n·up, 0)` times the day factor on the tile's mean texel; the field takes its sun term over an ambient share of 0.45 and the vertex light on the triplanar texel. Which of the two differs is unmeasured: compare a clod's top against the field beside it in one shot before tuning either.
- The flying clods are plain cubes; a hashed box with unequal edges (0.6 to 1.4 of the edge per axis) would break the cube read at no cost. A model would be the Techtonica way (DESIGN.md, the look), once a reference model exists.

## Suggestions from the flames (0274, 2026-10-05)

- The flames draw before the water as the old billboards did, so water in front of a flame covers it. A furnace at a shore is rare enough to leave; the fix is a second flame pass after the water, which costs a batch.
- The model preview shows the mean flicker with the flow at `phase · 8` seconds; a preview that advances the clock would show the flow moving, which the user may want for judging a new fire.

## Suggestions from the entry's flames outside the pod (0303 to 0305, 2026-11-06)

- An outside view during the fall: a strapped player is first person, so the wake (0304) shows in play only through the portholes; the developer command `arrival_camera` is the one outside view. Letting the camera toggle reach the strapped seat with a chase camera behind the pod would be a control change for its own item. Recommendation: do it, since the outside flames were made to be seen.
- KSP's brighter body: its trail keeps full light for about a third of a shield diameter and then halves every 0.35 diameters, where ours halves every quarter from the rim (0305's measurement). Matching it is two constants and a new gain for the porthole, which then reads brighter.
- A pod for every joiner: today a joiner after the landing spawns in the landed pod's cabin, so nobody sees another player arrive; the wake is drawn on any falling pod, so a pod per joiner would show it to the players on the ground. A gameplay feature, not a look one.
- The wake's sparks keep 0304's flicker factor and can clamp to a pale yellow at a flare (never white), and no test catches a brightness factor coming back into the shell (0305's review).

## Suggestions from the relief (0306, 2026-11-06)

- `ATMOSPHERE_CLEAR_GROUND_METRES` (64 m, `src/data_arrival_curve.odin`) dates from relief within 34 m. A planet may now reach 256 m, and `game.sjson` is checked without the planets, so valid data could dim the day sky over a peak. The shipped data has 360 m of clear sky over peaks of 126 m. A check of the clear sky against the planets' highest relief at load would catch it.
- An old world logs that it keeps its relief on every load, also after this build saved it, since a zero `landforms` object reads like an absent one.

## Suggestions from the ground's colours (0307, 2026-11-07)

- `loop_planet_preview.odin` loads the field's tiles and renderer without the overlay fallback, so an overlay copy from before 0307 makes `--planet-preview` exit with an error.
- An overlay copy of `field.vs` alone from before 0307 links with the new `field.fs` on desktop Mesa and draws without the looks. A uniform only the new vertex shader uses would let the renderer catch it.
- The Odin mirror of the shader's `unpack_bytes` (`unpack_test_bytes`) is checked against its own packing, not against the GLSL body, so the two could drift.

## Suggestions from the ledges (0322, 2026-11-07)

- Felling by digging: the fell rule's probe lies 1.06 to 1.44 m under a trunk's base, so its sample cell reaches the stone under the 2 m of topsoil, and a tree on deep topsoil may not fall when only the topsoil (the shovel's reach) is dug under it. A shallower probe, or a rule on the dug share of the cell, would let the shovel suffice. Decide whether the shovel alone should fell a tree.

## Suggestions from the carved landmarks (0324, 2026-11-07)

- A chunk with carved air under a roof that a neighbour's arrival seed writes light into is marked modified; saved before its own seed runs, it loads with `generated_shade` cleared while it is already in the restored `light.arrived_chunks`, so its roofed air stays at sky 0 until an edit relights it. The window is the few ticks of the seed queue (4 chunks a tick). Saving `generated_shade`, or seeding a loaded chunk's dark roofed air again, would close it.

## Suggestions from the slowest tests (0318, 2026-11-07)

- `test_the_cached_field_chunks_are_the_generated_ones` reports "got Full" if the suite ever fills `FIELD_CHUNK_CACHE_CAPACITY` (2048, the slow tier fills about 950) before it runs; a message naming the full cache would read better.
- `fill_field_chunk_cache` uses `find_field_chunk_cache_entry` without a nil check, so a key that failed to match its own stored copy would crash every staging test instead of missing.
- The `differs` checks of the cache test catch a key that leaves out a part only when the base home entry is filled at that moment; while another test still generates it, a broken key passes that run.

## Suggestions from the ground cover's design (0311, 2026-11-07)

- Blocking boulders of 1 to 3 m in the generated density, scattered by climate and slope like the cover. They would be ground the player climbs or walks round and digs (the cover's boulders stay under 0.65 m and are walked through), so they change walking and the generation's cost. Yours to decide.

## Suggestions from the springs and lakes (0312, 2026-11-07)

- The waters finder runs for every session, a block world's too (`resolve_session_planet`), where nothing uses it: about 0.3 s of the start at `-o:speed`. Skipping it when the session does not play the field (`session_plays_field`) saves that.
- At the data's bound of the simulated set (radius 3, margin 2: 11 chunks, a 610 m diagonal) the 400 m spring spacing lets two derived springs into one set; the shipped set holds one.

## Suggestions from the forests (0310, 2026-11-07)

- If `model.fs` fails to load while `tree.fs` loads, `set_model_open_sky`, `set_model_point_lights` and `set_model_spot_light` return early, so the tree shader keeps zero camera and sky uniforms and the field draws no trees.
- When `use_machine_models` fails after the machine table changes, it keeps the old card atlas indexed by the old machine ids.
- With `far_limit` below a tile's count, or `far_distance` below `near_distance`, the near models dither out with no cards behind them; the shipped rows never reach it.

## Suggestions from the sun shadows' design (0328, 2026-11-07)

- A second, far shadow cascade would let ridges shade the valleys at dusk; 0328's one map covers 64 m round the eye. It costs a second depth pass of the coarse terrain. Yours to decide.

## Suggestions from the ground cover (0311, 2026-11-07)

- `snapshot_cover_frames` walks and sorts every occupied cell of a frame on each revision change (a placement, a removal, a hatch), and `cover_frames_meeting` copies whole frames into each job; a late base on one large frame pays that per build action. Marking only the changed cells' box and copying the cells near the node would bound it.
- The cover's wet test reads `grid.water`, which near a disturbed shore holds the waves' offsets, so a narrow band of beach cover may pop in and out while the water moves.
- The patch noise is one octave of trilinear `value_noise` on world axes; thresholded drifts of flowers and grass may sit on a visible lattice of 7 to 13 m. The landing captures look for it.
- The streaming keeps placing cover when the cover shaders failed to load, work nothing draws.

## Suggestions from the sun shadows (0328, 2026-11-07)

- The cast pass draws every foundation cell of every frame (`draw_frames` in `draw_field_sun_shadows`), where the machines are culled to its box; a base of thousands of cells doubles that batch work, twice in split screen. A box test per frame or per cell run would bound it.
- The map is snapped as the eye moves but not as the sun turns, so shadow edges in the outer ring may shimmer slowly through the day; stepping the sun direction the cascade uses is the usual remedy. The captures at dusk would show whether it is visible.
- The Windows build under Winlator on the phone takes the desktop row, so shadows are on there by default; an Android-like row for Winlator would need a way to tell it apart.
- Belts, runs and torches neither cast nor receive (as specified), so they stay lit under a tree.
- `draw_far_tree_cards` still binds and unbinds the shadow map, though the cards no longer read it.

## Suggestions from the snow on the cover (0335, 2026-11-07)

- `test_snow_buries_the_plants`'s density bounds and its "no grass at the cold spot" depend on the shipped data and seed, so a retune of the climate or the relief can fail it with no fault in the code; its `most_buried_snow` check is the one that tests the code itself. Reading the bounds off the kinds and the shares would make it robust to data changes.

## Suggestions from the shared spill saddle (0334, 2026-11-11)

- The join search answers joined once it has visited `WATER_JOIN_SEARCH_LIMIT` (4096) samples. Two basins whose shared saddle has, on both sides, a shelf less than a slab under the saddle and wider than about 64 by 64 samples would merge and release each other in turn as before 0334 (the review forced it with the limit at 1; one side over the limit still settled). No shipped lake comes near: the largest search over every lake at 4, 8 and 16 km is 513 samples. Worth a rule of its own only when a world shows such a shelf.
- Thin water (no sample wholly under its level) that reaches its seed only through a chunk that is not loaded answers not joined, so a flood takes that lobe sample by sample with its volume instead of merging it. The water is conserved and the lobe is flooded again when the chunk arrives. Read in the code by the review, not reproduced.

## Suggestions from raylib 6.2 (0319, 2026-11-11)

- The precision patch (0126) may be dead weight: desktop compilers define `GL_FRAGMENT_PRECISION_HIGH` for ES 3.00 although the specification does not list it. If the phone's driver does too (a one line log of a shader compiled with the `#ifdef` would tell), the patch can go and the Android archive is built from unpatched rlgl.
- The poll after a cursor capture resets the mouse delta on X11 and Windows. The review read that a capture under a native Wayland GLFW would still jump, as it did before this item; the archive is built with X11 only, so today the game never runs there. It matters only if the Linux build gains Wayland.

## Suggestions from the flood's pass under a lake (0336, 2026-11-11)

- The walk up a water column is not charged to the flood's visit budget and runs once for every popped sample of no one's water under the sill: up to the far water's depth under the sill in steps, each a map lookup and an integer square root, for up to 4000 pops a tick. Bounded and not measured. Worth a count in the night's water report before a deep generated lake (0326 finds more of them) is blamed for a slow tick.
- `test_a_water_column_reaches_the_level_its_top_stands_at` walks the +y half axis only. The review's probe walked the -x half axis across a chunk border (`tmp/0336/verify/tree/src/zz_verify_0336_test.odin`, untracked) and passed; it could join the suite if the walk is ever changed.

## Suggestions from the relief's box bound (0314, 2026-11-11)

- `landmark_sites_most` (`generation_planet_bound.odin`) walks every site cube a projected box meets. When `projected_box` answers the radius cube (a box nearer the centre than 3/4 of the radius, so a planet under about 1.1 km with deep relief) and `site_spacing_metres` is small, that is (2R / spacing)³ cubes per box: slow, never wrong. The shipped data cannot reach it (4 km and up, 448 m). If a small planet is ever shipped, the radius cube should answer a full raise and cut without the walk. Read in the code by the review, not reproduced.

## Suggestions from the tree tiles' relief cost (0337, 2026-11-11)

- The tree tiles' relief reads are the standing trees' own: a base and two slope probes each, the slope's two being 65 percent of a tile's reads (825k of 1.27M at the 8 km home). They fall only if the trees' bytes change: a slope taken from a coarser lattice of reads, recorded with the forest so only new worlds differ, would read about 0.1M instead (the designer's estimate from the tiles' area at an 8 m lattice, not probed), at the price of trees standing or missing where a slope crosses the limit between lattice points. Worth weighing once the night's tree line (0337, 0338) shows what the tiles still cost.

## Suggestions from the waters over the whole planet (0326, 2026-11-11)

- A final finds the analyses it lacks on the thread that asked (up to 26 at a cold start). Claiming them all first and letting idle workers take them would spread the tech demo's start over the workers, at the price of a second kind of job in the generation queue. Worth it only if the night's waters report shows the start stalls.
- `water_tiles_near` skips a face when a corner of its square lies behind it, which is why the query reach stops at 21 percent of the radius. A skip by the disc's angle from the face's axis would lift the limit. Nothing shipped needs it: the largest reach against the radius is 803 m at 4 km, 20.1 percent, so a preset under 3824 m with the shipped waters is refused at load.
- 0314's parity tests (bounded against unbounded generation) hold no lake chunk with tiles. The 0327 review compared 27 such chunks by probe and found them equal, so this is cover for later changes, not a known gap.
- `test_water_tiles_keep_the_waters_across_the_seams` analyses 30 border tiles and is marked slow without a measured time under a quiet machine. If the night shows it over a minute, fewer tiles round two corners keep the same cases.

## Decisions The Last Caretaker opens (2026-11-11)

The user named its look, the lone machine's tone, the vessel as a base and its power and cable play as influences, all four. Each meets a decision `DESIGN.md` already holds. 0353 studies the game first; these are the forks it will bring back with pictures and sources.

- Tone: the player is a contractor with Mission Control's corporate voice in the ear (Lore and tone). A lone machine's quiet is the opposite register. Does the player become a machine, does Mission Control fall silent for long stretches, or does only the world's mood change?
- The base: the pod lands once and stays, and the factory grows on the ground round it. A vessel as a base moves with the player. Does the pod become a vehicle, does a later ship take that role (Space already has ships that park), or is it the pod's interior that grows? The user's direction (2026-11-11): "by vessel, we could have a land based one for now that you build up and improve like a ship of theseus". So a land vessel, improved part by part until little of the first one is left. Still open for 0353's proposal: whether it is the pod itself, whether it drives, and what of the factory rides on it against what stands on the ground.
- Power: poles join into networks (Power). Cables run by hand from socket to socket are a different game at the small scale. Do cables replace the poles early on, with poles as the later bulk form, or sit beside them?
- The look: Techtonica is the leading star (Art direction, user, 2026-10-05). Which of the two leads where they differ?
