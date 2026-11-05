# 0291: The water tech demo mode

Status: implementing (2026-11-05)

Milestone: side quest for M14 (the ground game): a couch build that drops straight onto a planet to judge the water models of the browser study (`work/research` of the water-demos session, 2026-11-03 to 05: the body model and the cellular rule with teleport pressure, both with a wave layer and a thin-sheet mesher), with the player walking, digging, raising, adding and removing water and placing pumps, under a sun and a torchlight. The items: 0291 (this, the mode, the menu, the demo kit, the couch script), 0292 (teleport pressure and the dead band), 0293 (water bodies), 0294 (the water's look: sheet, radial plane, waves), 0295 (water tools and pumps), 0296 (jetpack, cheat mode), 0297 (sun and torchlight).

## Goal

`./update-and-run.sh` on the couch (a Steam shortcut in game mode) pulls `main`, builds the release and launches the game into a small gamepad menu: water model (Teleport pressure, Bodies), planet radius (4, 8, 16 km), start point (Home, Spring), Start. Start drops the player standing at the chosen point on a `home` planet of that radius with no arrival fall, no save, no quests, holding a demo kit that digs any material and raises ground without cost, with the HUD and the normal field controls. Back (B) on the menu returns to the title; Pause in the world offers Quit to title.

## Controls

- Menu: the title gains a button "Water tech demo" between New world and Load; the screen `Tech_Demo` holds three `ui_choice` rows (water model, radius, start point) and Start, navigated as every screen (D-pad, Confirm A, Back B).
- World: the field bindings as they are (`data/bindings.sjson`): Mine R2 digs, Place L2 raises or places the held item, hotbar on D-pad left/right and the shoulders, Next_Brush Y, Jump A, Sneak B, Sprint L3, Pause Start. The demo kit fills the hotbar: 1 iron pickaxe (digs every material but bedrock in the demo), 2 dirt (unlimited in the demo), 3 water bucket (0295), 4 drain bucket (0295), 5 pump (0295), 6 torch. No binding changes in this item; 0296 and 0297 add theirs.
- Command line: `--tech-demo[=model,radius,start]` starts the world directly with the menu's defaults (model `teleport`, radius 8000, start `spring`), so the Steam shortcut's LaunchOptions can skip the title; `--tech-demo` alone opens the title with the tech demo screen pushed.

## Change

- `Session_Request_Kind.Tech_Demo` and `Screen.Tech_Demo` (`ui_title.odin`, `ui_screens.odin`, `ui_core.odin`), served in `apply_session_request` (`loop.odin`) by `start_tech_demo_session` (`session.odin`, after the pattern of `start_planet_preview_session`: `default_world_file_settings`, planet `home`, the chosen radius, `new_world_plan` with saves "" so nothing is saved, `start_session`, `arrival = {}`), entering the normal loop so SDL3 input and the HUD are the real ones.
- `World_File_Settings.water_model` (`save_world.odin`: `teleport` default, `bodies`) read by 0293; `tech_demo` flag on `Simulation_Content.field` (`simulation_field.odin`) that `field_diggable_materials` and `drain_field_place` / `drain_field_dig` honour (dig everything but bedrock, no credit, no debit); the spawn at the spring: the first air sample over the spring's surface point, `spawn_field_player_at` beside `field_pod_spawn`; the demo kit through a `tech_demo_items` list in `data/game.sjson` given as `give_planet_preview_items` does.
- `--tech-demo` in `Command_Line` (`main.odin`), `doc/commands.md`.
- `update-and-run.sh` at the repository root: `git pull --ff-only`, `./build.sh release`, `exec build/mine-oh-belowed --tech-demo "$@"` with `MINE_OH_BELOWED_GAMESCOPE` honoured as the play launcher does; it refuses to run with uncommitted changes in `src/` or `data/` and prints why. `tools/add_steam_shortcut.py --tech-demo` writes a second shortcut "Mine oh Belowed: water tech demo" whose target is the script. `doc/build.md` (Steam, the tech demo), `doc/README.md` index.
- HUD: the debug overlay's water line (total water, awake samples, bodies when 0293 is in) is on by default in the tech demo.

## Verify

- `./build.sh check`, `check-android`, `test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- A test starts a tech demo session at 4000 m at the spring and asserts: no arrival, the player stands within 2 m of the spring's surface, the hotbar holds the kit, a dig of stone succeeds with no credit, a place of dirt succeeds with an empty inventory, nothing is saved (the saves directory stays empty).
- `./update-and-run.sh` in a clean checkout builds and launches (the user, on the couch).

## Specification (design, 2026-11-05)

Designed against `main`. No binding changes; the screen is navigated like every title screen (D-pad, Confirm, Back), and the overlay toggles stay the keyboard's F4 and the Developer screen's "Statistics overlay". Odin cannot be run in the design session (no toolchain in the container), so the `core:flags` rewrite below is stated as a fact the implementer confirms.

### Answers

1. "The debug overlay" is F4's world statistics overlay (`draw_world_overlay`, `Frame_Developer_Tools.show_world_overlay`): it already draws over the HUD in a session, and the World page shows the same lines. A tech demo session turns it on at entry; F4 or the Developer screen turn it off.
2. The menu's seed is `DEFAULT_WORLD_SEED` (runs reproduce, as `--seed`'s default); `--seed=<n>` with `--tech-demo` picks another.
3. `--tech-demo` alone opens the title with the Tech demo screen pushed; `--tech-demo=<model>,<radius>,<start>` (any of the three words, empty ones keeping the defaults) starts the world before the window opens. `update-and-run.sh` passes `--tech-demo` only when it got no arguments, so a Steam LaunchOptions of `--tech-demo=teleport,8000,spring` skips the title without repeating the flag.
4. `water_model` is a stored world setting with no row on the New world screen; the tech demo's menu is its only UI until 0293 decides otherwise.
5. "No quests": the quests are silenced (no active quest, no Mission Control lines), not completed; completing them would pour rewards into the pod's locker and unlock recipes. The HUD then shows no objective (`hud_objective_source` gives `.None`, as no contract is open).
6. The spring spawn is the spring's source sample, the first air sample over the surface under the spring's point (`planet_spring_sample`, the same procedure that makes it a source), with the spawn clearance along the radial, facing the home; a spring with no air above its surface falls back to the generated surface under its point (`field_surface_under`), as the surface teleport does.
7. A radius of 0 in the setup means the planet's default (`Planet.radius_metres`); the command line refuses a radius that is not one of the planet's presets once the data is loaded, instead of `resolve_world_planet`'s silent fallback.
8. In the demo the pickaxe digs every material with an item (so topsoil too, and the ores), never bedrock or air, which have none. `field_player_digs` still needs a digging tool held, so a resting thumb on the dirt or the torch digs nothing.
9. The kit's list order is the hotbar's order: `iron_pickaxe`, `dirt`, `torch` ship now in slots 1 to 3; 0295 inserts its bucket, drain bucket and pump before the torch, which moves to slot 6 as the Controls section lists.

### Data

`data/game.sjson`, after `starting_items`, with a comment (the water tech demo's hotbar, 0291; one entry per slot in order; dirt is one full stack since the demo never debits it; 0295 adds its tools before the torch):

```
tech_demo_items = [
	{item = "iron_pickaxe", count = 1}
	{item = "dirt", count = 50}
	{item = "torch", count = 20}
]
```

- `src/data_load.odin`: `Game_Config.tech_demo_items: []Starting_Item` after `starting_items` (comment names 0291). `validate_starting_items` gains `what := "starting item"` used in both messages ("%s %q is not in %s", "%s %q has count %d"); `load_game_tables` (`data_reload.odin`) and the reload's check call it a second time with `config.tech_demo_items` and `"tech demo item"`. A list longer than the inventory is not refused: `give_starting_items` drops what does not fit, as the starter kit does.
- `src/player_test.odin`, `test_field_game_config`: copies `tech_demo_items` from the shipped config beside `starting_items`.

### The world setting

- `src/world_chunk.odin`: `Water_Model :: enum u8 {Teleport, Bodies}` after `World_Mode` (comment: the water field's rule, 0291; `Teleport` is 0292's cellular rule, `Bodies` 0293's; stored, read by the water step). `World_Settings.water_model: Water_Model` after `keep_inventory`; `world_settings_from_file` copies it.
- `src/save_world.odin`: `World_File_Settings.water_model: Water_Model` after `keep_inventory` (comment: a file without it was written before 0291 and reads as teleport). `make_world_file` writes it from `state.world.settings.water_model`. The file holds the enum name (`"Teleport"`, `"Bodies"`), as `mode` does.
- Old saves: `world_file_mode_problem` becomes `world_file_setting_names_problem :: proc(data: []byte) -> string`, which parses the raw tree once and checks `mode` as today and then `water_model` the same way: a value that is not a string returns `water_model must be one of [Teleport, Bodies]`; an unknown name logs `world: the water model %q is not one of %v, the world reads it as teleport`; a missing key logs `world: the save has no water_model, the world reads it as teleport` once (the unmarshal already leaves `Teleport`). `parse_world_file` calls it where it called the old one. The log lines are the remap; nothing else changes for an old save.
- `default_world_file_settings` leaves `water_model` at `.Teleport`; `world_file_settings_from_setup` copies nothing (no row).

### The command line

`src/main.odin`:

- `Command_Line.tech_demo: string` with `args:"name=tech-demo"` and the usage `[=<model>,<radius>,<start>]: the water tech demo (0291): alone, the title with the Tech demo screen open; with values, straight into the demo world (model teleport or bodies, radius a preset in metres, start home or spring; an empty word keeps its default teleport, the planet's default radius, spring)`.
- `TECH_DEMO_MENU_WORD :: "menu"`. `parse_command_line` copies `arguments` into a temp slice and replaces every argument equal to `--tech-demo` by `--tech-demo=menu` before `flags.parse`, since `core:flags` takes a value for a string field. `--tech-demo=menu` typed by hand means the same.
- `tech_demo_opens_menu :: proc(command_line: Command_Line) -> bool`: `tech_demo == TECH_DEMO_MENU_WORD`. `tech_demo_starts_world :: proc(command_line: Command_Line) -> bool`: `tech_demo != "" && !tech_demo_opens_menu(command_line)`.
- `parse_tech_demo_setup :: proc(value: string, defaults: Tech_Demo_Setup) -> (setup: Tech_Demo_Setup, problem: string)`: splits on `,` (at most three words; a fourth gives `invalid --tech-demo=%s (expected <model>,<radius>,<start>)`); each empty word keeps the default. Word 1 `teleport` or `bodies` (else `invalid --tech-demo model %q (expected teleport or bodies)`); word 2 digits through `parse_seed`, then 1 to `MAXIMUM_PLANET_RADIUS_METRES` (else `invalid --tech-demo radius %q (expected a preset in metres, 1 to %d)`); word 3 `home` or `spring` (else `invalid --tech-demo start %q (expected home or spring)`). Called from `command_line_value_problem` with `tech_demo_starts_world` true and `Tech_Demo_Setup{}` (radius 0, the planet's default) as the defaults.
- `command_line_data_problem` gains `planets: []Planet`: with `tech_demo_starts_world`, the parsed radius must be 0 or in `default_planet(planets).radius_presets_metres` (else `invalid --tech-demo radius %d (%s offers %v)` with `PLANETS_FILE_NAME`); no planets gives `the data has no planet for the tech demo`.
- `tech_demo_conflict :: proc(command_line: Command_Line) -> string`, called from `command_line_conflict` after `workbench_conflict`: with `tech_demo != ""`, `--load`, `--name`, `--debug-terrain`, `--chapter`, `--give`, `--server`, `--join`, `--benchmark`, `--planet-preview`, `--planet-preview-screenshot`, `--planet-preview-walk`, `--model-check` and `--model-preview` are each refused as `--tech-demo and %s cannot be combined (the tech demo builds its own world)`; `--seed`, `--dev`, `--set`, `--input`, `--unlock-all`, `--touch-overlay` and `--watch-data` combine.
- `start_command_line_tech_demo :: proc(command_line: Command_Line, config: Game_Config, content: Game_Content, base_generator: Generator) -> ^Session`: nil unless `tech_demo_starts_world`; else `start_tech_demo_session(config, content, base_generator, seed, setup)` with `command_line_seed` and the parsed setup, exiting 1 with `error: cannot start the tech demo: %s` as `start_command_line_session` does. `main` calls it right after `start_command_line_session` when that returned nil (before `start_input_backend`, so a problem shows without a display), and sets `player_configuration.tech_demo_menu = tech_demo_opens_menu(command_line)`.
- `src/configuration.odin`: `Player_Configuration.tech_demo_menu: bool` (comment: `--tech-demo` alone, 0291: the title opens with the Tech demo screen pushed). `run_game` (`loop.odin`), after `show_title(state)` in the `session == nil` branch: `if player_configuration.tech_demo_menu { push_screen(&primary_ui(state).screens, .Tech_Demo) }`.

### The screen

`src/ui_tech_demo.odin` (new, ui cluster, after `ui_multiplayer.odin` in the map; header comment: the water tech demo's menu, 0291, three choices and Start, no world behind it):

- `Tech_Demo_Start :: enum u8 {Home, Spring}`. `Tech_Demo_Setup :: struct {water_model: Water_Model, planet_radius_metres: int, start: Tech_Demo_Start}` with the comment that radius 0 is the planet's default. `DEFAULT_TECH_DEMO_SETUP :: Tech_Demo_Setup{start = .Spring}`.
- `tech_demo_radius_metres :: proc(setup: Tech_Demo_Setup, planets: []Planet) -> int`: the setup's radius, or `default_planet(planets).radius_metres` when 0 (0 without planets).
- `step_tech_demo_radius :: proc(setup: ^Tech_Demo_Setup, planets: []Planet)`: as `step_world_setup_radius`, over the default planet's presets from `tech_demo_radius_metres`; nothing without planets. `step_tech_demo_model :: proc(setup: ^Tech_Demo_Setup)` and `step_tech_demo_start :: proc(setup: ^Tech_Demo_Setup)` cycle their enums with `next_choice`.
- `tech_demo_model_text :: proc(model: Water_Model) -> string` (`tech_demo_model_teleport`, `tech_demo_model_bodies`), `tech_demo_start_text :: proc(start: Tech_Demo_Start) -> string` (`tech_demo_start_home`, `tech_demo_start_spring`).
- `start_tech_demo :: proc(title: ^Title_State)`: `title.request = {kind = .Tech_Demo}`.
- `TECH_DEMO_PANEL_WIDTH :: 720`, `TECH_DEMO_ROW_COUNT :: 5` (heading, three rows, the button row). `tech_demo_screen :: proc(state: ^Ui_State, screen_context: Screen_Context)`: `fitted_panel(ui_panel_area(state), TECH_DEMO_PANEL_WIDTH, panel_height(TECH_DEMO_ROW_COUNT, -UI_GAP))`, `ui_panel_begin(state, "tech_demo", panel)`, the heading `tech_demo_title` at `UI_HEADING_TEXT_SIZE` centred, then three `ui_choice` rows: `tech_demo_model` with the model text and `tech_demo_model_tooltip`; `new_world_radius` with `format_message_text(text("new_world_kilometres"), kilometres_number_text(tech_demo_radius_metres(setup, planets)))` and `new_world_radius_tooltip`; `tech_demo_start` with the start text and `tech_demo_start_tooltip`; then a button row split in two with `column_rectangle` as `new_world_screen`'s: `tech_demo_start_button` (calls `start_tech_demo`) and `new_world_back` (`pop_screen`). The glyph bar as the New world screen's (Confirm `hint_select`, Back) unless `touch_row_shows`. The setup is `screen_context.title.tech_demo`, the planets `screen_context.planets`.
- `src/ui_title.odin`: `Session_Request_Kind.Tech_Demo` after `.Join` (comment: start the tech demo of Title_State.tech_demo, 0291). `Title_State.tech_demo: Tech_Demo_Setup`, set to `DEFAULT_TECH_DEMO_SETUP` in `make_title_state`. `title_screen`: `button_count` becomes `has_save ? 7 : 6`; the button `title_tech_demo` between New world and Load pushes `.Tech_Demo`.
- `src/ui_core.odin`: `Screen.Tech_Demo` after `.Multiplayer` (comment: the water tech demo's menu, ui_tech_demo.odin, 0291); `screen_pauses_simulation` lists it with the title's screens. `src/ui_screens.odin`: `case .Tech_Demo: tech_demo_screen(state, screen_context)`. Back pops it as every title screen (`handle_screen_keys` already pops anything but `.Title`).
- `data/strings/en.sjson`, a `// Tech demo screen` block after the title's: `title_tech_demo = "Water tech demo"`, `tech_demo_title = "Water tech demo"`, `tech_demo_model = "Water model"`, `tech_demo_model_teleport = "Teleport pressure"`, `tech_demo_model_bodies = "Bodies"`, `tech_demo_model_tooltip = "How the water moves: the cellular rule with teleport pressure, or bodies of still water"`, `tech_demo_start = "Start point"`, `tech_demo_start_home = "Home"`, `tech_demo_start_spring = "Spring"`, `tech_demo_start_tooltip = "Stand at the pod, or at the first spring"`, `tech_demo_start_button = "Start"`.

### The session

`src/session.odin`, after `start_session`:

- `TECH_DEMO_WORLD_NAME :: "water tech demo"`.
- `start_tech_demo_session :: proc(config: Game_Config, content: Game_Content, base_generator: Generator, seed: u64, setup: Tech_Demo_Setup) -> (session: ^Session, problem: string)`, after `start_planet_preview_session`: `settings := default_world_file_settings(config)`, `settings.water_model = setup.water_model`, `settings.planet_radius_metres = tech_demo_radius_metres(setup, content.planets)`; `plan := new_world_plan(TECH_DEMO_WORLD_NAME, seed, settings, "", false, false)` (saves "" and not found: `new_world_save_setup` logs that saving is off and the session never saves); `start_session`; a session without `field.enabled` is ended with `the data has no planet for the tech demo`. Then, in order: `session.simulation.field.arrival = {}` (no fall); `session.field_content.tech_demo = true`; `silence_quests(&session.simulation.quests)`; the first player: `slice.fill(player.inventory.slots, EMPTY_STACK)`, `give_starting_items(player, content.items, config.tech_demo_items)`, `player.selected_hotbar_slot = 0`; the spawn by `setup.start`: `.Home` calls `stand_field_player_from_seat(&entities, content.machines, &player.field)` (out of the strapped chair onto the cabin's floor); `.Spring` sets `player.field` from `field_spring_spawn` when found, else the home's stand. Last, one log line: `tech demo: water model %v, radius %d m, start %v, seed %d`.
- `src/quest_runtime.odin`: `silence_quests :: proc(state: ^Quest_State)` after `start_quests`: `state.active = NO_QUEST`, every `progress[i].status = .Locked`, `clear(&state.messages)`, `clear(&state.notices)`, `state.hints_fired = 0`. Comment: the tech demo plays without quests (0291); `tick_quests` then advances nothing and the HUD shows no objective.
- `src/simulation_field.odin`, after `field_pod_spawn`: `field_spring_spawn :: proc(seed: u64, planet: Planet, spacing_millimetres: int) -> (player: Field_Player, found: bool)`: found false without springs. Otherwise `generation := make_planet_generation(seed, planet, spacing_millimetres)` (the spring lies outside the crater's reach, so the baked overlay does not matter), `spring := planet.springs[0]`, `direction := planet_spring_direction(spring)`, `clearance := millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES)`; feet: `sample, air := planet_spring_sample(generation, spring)`; with air `sample_to_world_position(sample, spacing_millimetres) + World_Position(fixed_scale(direction, clearance))`, else `field_surface_under(generation, World_Position(fixed_scale(direction, generation.radius)), clearance)`; heading `tangent_of(direction, chord)` with `chord, ok := normalize_fixed(planet_home_direction(planet.home) - direction)` and `{UNIT_VECTOR_ONE, 0, 0}` when not ok (as `field_home_heading`); returns `make_field_player(feet, heading), true`.
- `src/loop.odin`, `apply_session_request`: `case .Tech_Demo:` calls `start_tech_demo_session(state.config, state.content, state.base_generator, DEFAULT_WORLD_SEED, state.interaction.title.tech_demo)`; a problem goes to `report_session_problem`, else `enter_session`. `enter_session`, after `state.session = session`: `state.developer.show_world_overlay ||= session.field_content.tech_demo` (comment: the tech demo starts with the water line showing, 0291; `leave_session` already clears it).

### The demo flag

- `src/field_mining.odin`: `Field_Content.tech_demo: bool` after `starting_items` (comment: the water tech demo's session, 0291: every material with an item digs with any digging tool and no credit, a place spends nothing; set by `start_tech_demo_session`, never saved). `src/data_reload.odin`, `reload_session`: `field_content.tech_demo = session.field_content.tech_demo` right after `make_field_content`.
- `field_demo_diggable_materials :: proc(table: Field_Material_Table) -> bit_set[Field_Material]` after `field_diggable_materials`: every material whose `item != NO_ITEM`.
- `drain_field_dig`: `dig.diggable = content.field.tech_demo ? field_demo_diggable_materials(content.field.materials) : field_diggable_materials(...)`; the credit loop runs only when `!content.field.tech_demo` (the dug steps go nowhere); `report_blocked_dig` and `fell_trees_over_dug_ground` as today.
- `FIELD_UNLIMITED_BUDGET :: max(i64)` beside `Field_Edit` in `world_field_edit.odin` (comment: a place that stops only when the brush is done, 0291). `drain_field_place`: with `content.field.tech_demo`, `place.budget = FIELD_UNLIMITED_BUDGET` instead of the inventory's budget and `debit_field_volume` is skipped; the bury refusals stay.

### The water line

- `src/world_field_water.odin`: `Field_Water_Census :: struct {fill: i64, awake_samples, awake_chunks: int}` and `field_water_census :: proc(world: ^Field_World) -> Field_Water_Census`: `fill` sums `chunk.water[i]` over every chunk of `world.chunks`; `awake_chunks` is `len(world.water_awake_chunks)` and `awake_samples` the set bits of `water_awake` of those chunks through `field_sample_bits_count :: proc(bits: ^Field_Sample_Bits) -> int` (new beside `field_sample_bits_any`, `intrinsics.count_ones` per word). `field_water_cubic_metres :: proc(fill: i64, spacing_millimetres: int) -> i64`: `fill * spacing^3 / (FIELD_WATER_FULL * 1_000_000_000)` in i64.
- `src/loop.odin`: `Frame_Developer_Tools` gains `water_census: Field_Water_Census, water_census_tick: u64, water_census_taken: bool` (comment: the overlay's water line, taken once a second while it shows, 0291). `diagnostics_context`, when `session.simulation.field.enabled` and (`!taken` or `tick - water_census_tick >= u64(state.config.tick_rate)`), takes `field_water_census(&session.simulation.field.world)` and stamps the tick; `leave_session` sets `water_census_taken = false`. `Diagnostics_Context` gains `water_census: Field_Water_Census, water_dropped: i64, field_spacing_millimetres: int` filled there (`world.water_dropped`, `field.spacing_millimetres`).
- `src/diagnostics.odin`: `field_water_line :: proc(diagnostics: Diagnostics_Context) -> string`: `"water %d m3  awake %d samples in %d chunks  dropped %d m3"` with `field_water_cubic_metres` on the fill and the dropped amount. `world_overlay_statistics_lines` appends it after the light line when `diagnostics.simulation.field.enabled`; the World page shows it through `overlay_lines`. 0292 adds its visits and milliseconds to this line.

### The couch script and the shortcut

`update-and-run.sh` at the repository root, executable, in full:

```bash
#!/usr/bin/env bash
# The couch's way into the water tech demo (work item 0291): pulls main,
# builds the release and runs it with --tech-demo (the title with the Tech
# demo screen open) unless arguments are given, which go to the game as
# they are (Steam LaunchOptions --tech-demo=teleport,8000,spring skips the
# title). It refuses a tree with changes under src/ or data/, since the
# pull would fail or the build would not be main's, and prints why.
# MINE_OH_BELOWED_GAMESCOPE is honoured as the play launcher does.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repository_root"

if [ -n "$(git status --porcelain -- src data)" ]; then
	echo "update-and-run.sh: src/ or data/ has uncommitted changes, commit or stash them first:" >&2
	git status --short -- src data >&2
	exit 1
fi
git pull --ff-only
./build.sh release

if [ $# -eq 0 ]; then
	set -- --tech-demo
fi
if [ -n "${MINE_OH_BELOWED_GAMESCOPE:-}" ]; then
	if command -v gamescope >/dev/null; then
		# shellcheck disable=SC2086
		exec gamescope $MINE_OH_BELOWED_GAMESCOPE -- "$repository_root/build/mine-oh-belowed" "$@"
	fi
	echo "update-and-run.sh: MINE_OH_BELOWED_GAMESCOPE is set but gamescope is not on the path, running without it" >&2
fi
exec "$repository_root/build/mine-oh-belowed" "$@"
```

The game reads `./data` (the data directory rule), so the working tree's data is the pulled one. A `git pull` that cannot fast forward exits with git's message (`set -e`).

`tools/add_steam_shortcut.py`: `TECH_DEMO_APP_NAME = "Mine oh Belowed: water tech demo"`, `TECH_DEMO_EXECUTABLE = REPOSITORY_ROOT / "update-and-run.sh"`; `build_shortcut(app_name: str, executable: pathlib.Path)` takes both; `--tech-demo` (an `argparse` store_true, added to the docstring's usage) writes that shortcut instead of the game's, upserted by its own AppName, `LaunchOptions` empty, `StartDir` the repository. The appid differs since it hashes the executable and the name.

### Tests

- `src/simulation_field_test.odin`, `test_the_tech_demo_starts_at_the_spring_without_a_save_or_a_fall`: `config := test_field_game_config()`, `content := make_field_test_game_content()`, `session, problem := start_tech_demo_session(config, content, make_test_generator(DEFAULT_WORLD_SEED), DEFAULT_WORLD_SEED, {water_model = .Bodies, planet_radius_metres = 4000, start = .Spring})`, `defer end_session`. Asserts: `problem == ""`; `session.planet.radius_metres == 4000`; `session.simulation.world.settings.water_model == .Bodies`; `!session.save.enabled` and `session.save.location.directory_name == ""` (no directory, so nothing can be written); `session.simulation.field.arrival == {}`; `session.field_content.tech_demo`; `simulation.quests.active == NO_QUEST` and `len(simulation.quests.messages) == 0`; the player's `field.seat == .Standing`; its feet within `2 * POSITION_UNITS_PER_METRE` of `field_surface_under(generation, on_sphere, 0)` for the spring's direction at 4000 m, and `dot(normalize(feet), planet_spring_direction(spring))` above `UNIT_VECTOR_ONE - 1` (on the spring's radial); the hotbar `slots[0]` is `iron_pickaxe` x1, `slots[1]` `dirt` x50, `slots[2]` `torch` x20, and `inventory_count(wooden_foundation) == 0`. A second session with `start = .Home` stands within `2 * POSITION_UNITS_PER_METRE` of `field_pod_spawn`'s position, seat Standing. A third with radius 0 gets `content.planets[0].radius_metres`.
- `src/field_mining_test.odin`, `test_the_tech_demo_digs_any_material_free_and_places_from_nothing`: `test_field_simulation_content(items, test_brush(.Sphere, 1500, 254))` with `content.field.tech_demo = true`; through `dig_uniform_test_field` with `wooden_pickaxe` on `.Topsoil`, `.Stone` and `.Deep_Stone`: `dug > 0`, `credited == 0`, refusal `.None`; on `.Bedrock`: `dug == 0`, refusal `.Undiggable`. Then a place: `make_test_field_state(make_uniform_test_field({-MAXIMUM_DENSITY, .Air, 0}), 1000)` (or the air field the bury test uses), `add_test_miner` with an empty kit and `hold_test_item` of `dirt`, `drain_one_field_edit` with `{mode = .Place, material = .Topsoil, brush, centre}`: the sample at the centre becomes ground (`field_ground_sample_at(...).material == .Topsoil`), the refusal `.None`, the dirt count still 1 and `field_credit[.Topsoil] == 0`; the same with `tech_demo = false` and the empty inventory refuses `.Nothing_Held`.
- `src/main_test.odin`, `test_command_line_tech_demo`: `parse_command_line({"--tech-demo"})` gives `tech_demo == "menu"`, `tech_demo_opens_menu` true, `command_line_value_problem` ""; `{"--tech-demo=bodies,4000,home"}` parses to `{.Bodies, 4000, .Home}`; `{"--tech-demo=,16000"}` to `{.Teleport, 16000, .Spring}`; `{"--tech-demo=rivers"}`, `{"--tech-demo=teleport,abc"}`, `{"--tech-demo=teleport,0"}`, `{"--tech-demo=teleport,8000,moon"}` and `{"--tech-demo=teleport,8000,spring,extra"}` each give a problem starting `invalid --tech-demo`; `{"--tech-demo", "--load=x"}` gives `command_line_conflict` starting `--tech-demo and --load`, `{"--tech-demo=bodies", "--planet-preview"}` one naming `--planet-preview`, and `{"--tech-demo", "--seed=5", "--dev"}` no problem. `command_line_data_problem` with `shipped_test_planets()` refuses radius 5000 naming the presets and accepts 4000 and 0. `test_command_line_usage_lists_every_flag` adds `--tech-demo`.
- `src/generation_planet_record_test.odin`, `test_a_world_file_without_a_water_model_reads_teleport`, beside the mode test: a file with `water_model = .Bodies` encodes `"Bodies"` and parses back to `.Bodies`; the line removed parses to `.Teleport` with problem ""; `"Rivers"` parses to `.Teleport` with problem ""; `7` gives a problem containing `water_model must be one of`. `src/ui_world_setup_test.odin`, `test_world_settings_round_trip_through_world_file`: the settings carry `water_model = .Bodies` through `make_world_file` and back.
- `src/ui_tech_demo_test.odin` (new), `test_the_tech_demo_screen_steps_its_rows_and_asks_the_loop`: from `DEFAULT_TECH_DEMO_SETUP` with `shipped_test_planets()`, `tech_demo_radius_metres` is 8000; `step_tech_demo_radius` three times gives 16000, 4000, 8000; `step_tech_demo_model` twice gives `.Bodies` then `.Teleport`; `step_tech_demo_start` twice gives `.Home` then `.Spring`; `start_tech_demo` on an `audit_title_state`-shaped `Title_State` sets `request.kind == .Tech_Demo`. `src/ui_audit_test.odin`: `{name = "tech demo", screens = {.Title, .Tech_Demo}}` in the touch cases and `audit_case(audit, {name = "tech demo", screens = {.Title, .Tech_Demo}, walk_focus = true})` in the focus walk, after the New world ones.
- `src/data_load_test.odin`: the starting items test also checks `validate_starting_items(config.tech_demo_items, make_test_items())` is "" for the shipped config and that an unknown item with `"tech demo item"` gives a problem starting `tech demo item`.
- `src/world_field_water_test.odin` (existing file beside the water step; else `world_field_test.odin`), `test_the_water_census_counts_fill_and_awake_samples`: a world with one chunk whose `water` holds three samples at `FIELD_WATER_FULL` and two at 10, two of them awake and the chunk in `water_awake_chunks`: `fill == 3 * 254 + 20`, `awake_samples == 2`, `awake_chunks == 1`; `field_water_cubic_metres(254 * 8, 500)` is 1 (eight full half metre samples).
- `data_strings_test`'s `test_shipped_strings_cover_the_ui` covers the new keys without change.

### Docs

- `doc/build.md`: the Command line table gains `--tech-demo[=<model>,<radius>,<start>]` (one row, pointing below); a new section `## The water tech demo` after `## Steam shortcut`: the mode (the menu, the demo world, no save, the kit, the overlay's water line), the flag's grammar and defaults, `update-and-run.sh` (what it does, the clean tree rule, `MINE_OH_BELOWED_GAMESCOPE`, that the game reads the working tree's `data/` here, unlike the play build), `tools/add_steam_shortcut.py --tech-demo` and the LaunchOptions that skip the title. The Steam shortcut section names the flag in one line.
- `doc/README.md`: build.md's line gains "the water tech demo".
- `doc/ui.md`: the pausing screens table gains Tech demo; the Title bullet lists "Water tech demo" between New world and Load; a **Tech demo** bullet (the three rows, Start, Back) after Multiplayer's.
- `doc/architecture.md`, Sessions: one bullet for the tech demo session (`start_tech_demo_session`: no save, no fall, no quests, the kit of `tech_demo_items`, `Field_Content.tech_demo` and what it does to digs and places, the spawn at the spring or the pod); The water field: `water_model` as a stored setting read by 0292 and 0293; Save format: the `water_model` key and the old file rule.
- `doc/content.md`, Planets (after the starter kit bullet at "World"): `tech_demo_items` of `data/game.sjson`, validated like the starter kit.
- `doc/developer_tools.md`, Diagnostics pages: F4's overlay gains the water line (its text, once a second) and shows from the start of a tech demo session.
- `doc/code_map.md`: `ui_tech_demo.odin` in the ui cluster's reading order after `ui_multiplayer.odin`; the counts as `tools/code_graph.py` reports; `update-and-run.sh` named under the loop cluster's entry notes is not needed (it is not source).
- `doc/log/2026-11-05.md`: the main agent's, from the answers above.

### Hand-back check

- A number parsed from text is range checked: the radius word goes through `parse_seed` (digits, no wrap), then 1 to `MAXIMUM_PLANET_RADIUS_METRES`, then the planet's presets once the data is loaded.
- A changed save layout loads an old save: `water_model` missing or unknown reads as teleport with one log line each; the test above.
- A start-up load the game can make fail: a tech demo the data cannot start exits 1 with the problem from the command line (as `--seed` does) and toasts from the menu (`report_session_problem`); `field_spring_spawn` without air falls back to the surface.
- Tests never touch the machine's state directory: the demo plan has saves "" and `saves_found` false, so no path is ever built.
- A list that grows without bound: the kit beyond the inventory's slots is dropped as the starter kit's is; the census runs once a second and only while the overlay or the World page shows (one byte sum over the set's chunks).
- A UI audit case: the Tech demo screen is added to both audits, nothing replaced.
- Memory a frame draws from: the session change is served by `apply_session_request` between frames as every request.

### For the main agent

- The spawn stands in the spring's source sample itself (water at the feet from the first tick). If that reads badly on the couch, move the feet one sample towards the home along the tangent (`feet + spacing * heading`), which keeps the 2 m test; chosen here as the item says.
- `core:flags` and a string flag given bare: the rewrite in `parse_command_line` assumes `flags.parse` would otherwise refuse `--tech-demo` without a value (or eat the next argument). If the implementer finds it accepts a bare string flag as "", the rewrite still holds (the menu word stays the signal) and costs three lines.

### Main agent's decisions (approval, 2026-11-05)

- The spawn stands one sample towards the home along the heading (`feet + spacing * heading`), not in the spring's source sample, so the player does not start with water at the feet; the 2 m test holds.
- The `core:flags` rewrite as designed; the implementer confirms the bare flag's behaviour and keeps the menu word either way.
- Approved.
