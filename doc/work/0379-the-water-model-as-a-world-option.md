# 0379: The water model as a world option

Status: verified (2026-11-11)

A new world uses the teleport water model; only the water tech demo's screen offers bodies. The user (2026-11-11): "teleport for now, but make both selectable from world options".

## Goal

The new world screen offers the water model, teleport by default.

## Controls

No binding. The world setup screen gains a row "Water" with the two values "Teleport" and "Bodies" (user, 2026-11-11: "Change the water model names back to teleport and bodies"), stepped like its other choice rows by focus navigation and by the pointer.

## Change

- The row, its strings and a one line description of each value under it.
- The choice goes into the world's record where the model is read today, so a save keeps its model and a joiner takes the host's. An existing save keeps the model it was made with.
- The tech demo keeps its own choice and its default.
- `tools/frame_profile_views.sjson`: the spring view under both models, which 0367 asked for.
- Docs: the doc that owns the world setup screen and the one that owns the water models; `SUGGESTIONS.md`'s open question closed.

## Verify

- The checks and the suite: a world made with each value simulates under that model, saves and loads with it; the UI audit case of the world setup screen at the smallest size.
- A capture of the screen with the row.

## Specification (design, 2026-11-11)

### What exists

The storage is 0291's and needs nothing: `World_Settings.water_model` and `World_File_Settings.water_model` (`world_chunk.odin` 50, `save_world.odin` 63), written to `world.sjson` by name (`make_world_file` 205), read back by `parse_world_file` with `world_file_setting_names_problem` (275 to 287: none or an unknown name reads teleport with a log line, a number refuses the file; `test_a_world_file_without_a_water_model_reads_teleport`), copied to `Field_World.water_model` for a new world (`enable_new_field_world`, `simulation_field.odin` 747) and for every session (`start_field_world`, `session.odin` 123), kept by a content reload (`data_reload.odin` 300). A joiner parses the host's `world.sjson` from the snapshot (`start_joined_session`, `session_network.odin` 1374) and takes the same path. What is missing: `World_Setup` has no field, so `world_file_settings_from_setup` (the screen's Create, `loop.odin` 1728) and `default_world_file_settings` (`--name`, `--seed`, `--server`, the title's defaults) both leave the zero value, `Teleport`.

The tech demo picks its own model (`Tech_Demo_Setup.water_model`, `start_tech_demo_session` 274) and is not touched. Its default is teleport, not bodies (`DEFAULT_TECH_DEMO_SETUP`, `--tech-demo`'s empty word, build.md, The water tech demo); the user's bodies capture was chosen on its screen. See question 1.

**Save: no layout change, no remap, no log line, no format version step.** An existing save keeps the model in its `world.sjson`; one from before 0291 reads teleport as today.

### Code

`src/ui_world_setup.odin`:

- `World_Setup` gains `water_model: Water_Model` after `keep_inventory`, comment `// The Water row (0379).`
- `default_world_file_settings`: `water_model = .Teleport` written out, comment `// Teleport for now (user, 2026-11-11, 0379).`
- `make_world_setup`: `water_model = defaults.water_model`.
- `step_world_setup_water :: proc(setup: ^World_Setup)` after `step_world_setup_mode`: `setup.water_model = Water_Model(next_choice(int(setup.water_model), len(Water_Model)))`. Called by the row.
- `world_file_settings_from_setup`: `water_model = setup.water_model`.

`src/ui_title.odin`:

- `NEW_WORLD_ROW_COUNT :: 17`, comment `// Heading, name, seed, twelve settings, the water's description and the button row.`
- `world_water_text :: proc(model: Water_Model) -> string` after `world_mode_text`, the same switch shape: `.Teleport` `text("new_world_water_flowing")`, `.Bodies` `text("new_world_water_pooling")`.
- `world_water_description_text :: proc(model: Water_Model) -> string`: `new_world_water_flowing_description`, `new_world_water_pooling_description`. Literal keys in both, so `test_shipped_strings_cover_the_ui` checks them.
- `world_planet_rows`, after the spacing row and before Mode: `if ui_choice(state, cut_row(content), text("new_world_water"), world_water_text(setup.water_model), text("new_world_water_tooltip")) { step_world_setup_water(setup) }`, then the description: `description := cut_row(content)`, `cut_left(&description, UI_PADDING)` (aligned with the choice's label, full row height), `ui_label(state, description, world_water_description_text(setup.water_model), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)`. The label is unfitted on purpose: the audit's `Text_Too_Wide` then proves the line whole at every size and text scale. If a size flags it, shorten the string; never fit or wrap it. The procedure's comment names the water row and its description.

`data/strings/en.sjson`, after `new_world_metres`:

```
new_world_water = "Water"
new_world_water_tooltip = "How the world's water moves, kept with the world for good"
new_world_water_flowing = "Flowing"
new_world_water_pooling = "Pooling"
new_world_water_flowing_description = "Water keeps flowing, thin water dries"
new_world_water_pooling_description = "Water fills basins and spills when full"
```

`src/main.odin` (the profile's seam, below):

- `Command_Line` gains `water_model: string` after `debug_terrain`, its tag `args:"name=water-model" usage:"teleport or bodies: the water model of a new world (default teleport)"`.
- `parse_water_model_word :: proc(word: string) -> (model: Water_Model, ok: bool)` above `parse_tech_demo_setup`: `"teleport"` and `"bodies"`, anything else not ok. `parse_tech_demo_setup`'s model switch calls it, its message unchanged.
- `command_line_water_model :: proc(command_line: Command_Line, fallback: Water_Model) -> (model: Water_Model, ok: bool)` beside `command_line_seed`: the fallback for an empty flag, else the word's.
- `command_line_value_problem`, after the seed: `invalid --water-model=%s (expected teleport or bodies)`.
- `command_line_starts_world` gains `command_line.water_model != ""`, so the flag alone starts a new world as `--seed` does, and `workbench_conflict` and `network_conflict`'s join case refuse it with no edit of theirs.
- `command_line_plan`, the new world branch: `settings.water_model, _ = command_line_water_model(command_line, settings.water_model)` with the seed's comment (validated before any data loads). `--server` takes it through the same call.
- Refusals, one case each: `command_line_conflict`'s `--load` switch, `"--load and --water-model cannot be combined (a saved world keeps its water model)"`; `tech_demo_conflict`, `other = "--water-model"`; `relief_map_conflict`, `other = "--water-model"`; `benchmark_conflict`, `"--benchmark and --water-model cannot be combined (the benchmark builds its own world)"`.

### The profile under both models

A view names its model, and the script starts a game for it with `--water-model`. The default views run as today in the first game; the views with a model run last, in a fresh game started under it.

`tools/frame_profile_views.sjson`: the header's view paragraph gains a sentence. A view's `water_model = "bodies"` (or `"teleport"`) runs it after the other runs, in a game started with `--water-model=<it>` (0379). Without it the view runs under the new world's default, teleport. After `spring`: `{name = "spring_bodies", stand = [79.159, 150.561], target = [79, 151], target_height = 1, water_model = "bodies"}`, comment `// The spring under the bodies model (0367, 0379).`

`tools/frame_profile.py`:

- `new_run(name, viewports, distance, frames, water_model=None)`: the run carries `"water_model"`.
- `planned_runs`: a view with `water_model` goes to a new phase `"models"` in place of `views_one` or `views_two`, with its model; at the end `plan["models"].sort(key=lambda run: (run["water_model"], run["viewports"]))`, a stable sort, so each model's runs are together, one viewport before two, in the views file's order. The docstring names the new phase. `main` appends `plan["models"]` after `factory_one`.
- `game_command(binary, directories, check, water_model)`: `f"--water-model={water_model}"` after `GAME_FLAGS` when the model is not None.
- `new_game(water_model=None)`: the game carries `"water_model"`. `start_game` passes `game["water_model"]` to `game_command`.
- `run_needs_start(game, run, lost) -> tuple`: `(lost or run["water_model"] != game["water_model"], lost)`, whether the run needs a fresh game and whether that start counts as a restart (a lost game only).
- `profile_views`: before `ready_for_run`, `start, counted = run_needs_start(session["game"], run, needs_restart)` and `restart(run["water_model"], counted)` when start, in place of the bare `restart()`.
- `main`: the first game is `new_game(runs[0]["water_model"] if runs else None)`, so a run of only `spring_bodies` starts under bodies once. `restart(water_model, counted)`: stops the game, `new_game(water_model)`, counts and prints `restarting the game` only when counted, else prints `frame profile: starting the game under the <model> water model`, then `start_game` as now. The table head's restarts stay the lost games only; the rows' view names say the model.

Rejected: a socket command that switches a running world's model. The models keep different state (the bodies table, owners, the front; a teleport world's settled water is no one's), so a switch would need a conversion that no save or rule has, and as a world write it would have to travel in the lockstep record. Also rejected: profiling bodies through `--tech-demo=bodies,,spring`, a different world (no fall, the demo kit, the F4 overlay drawn from the start) that cannot be combined with `--name`.

### Tests

`src/ui_world_setup_test.odin`:

- `non_default_world_setup` gains `step_world_setup_water(&setup)`. `test_world_settings_round_trip_through_world_file` drops `settings.water_model = .Bodies` and its comment (the row sets it now) and keeps expecting `Bodies` after the parse.
- `test_world_setup_defaults_follow_the_config` gains `settings.water_model == Water_Model.Teleport`.
- `test_the_water_row_steps_both_models_with_their_texts` (new): a setup from `default_world_file_settings` holds teleport; a step gives bodies and `world_file_settings_from_setup` carries it; a second step gives teleport. For each model `world_water_text` and `world_water_description_text` are not empty, and the two models' values and descriptions differ.
- `test_the_water_row_steps_on_confirm` (new, the pattern of `test_the_title_opens_the_tech_demos_list_and_the_water_screen`): `make_ui_audit`, `.Title` and `.New_World` pushed, a frame, `requested_focus` the row's id `ui_hash(ui_hash(0, "new_world", -1), text("new_world_water"), -1)`, a gamepad frame (focus equals it), a frame with `confirm` and `confirm_down`: `audit.title.setup.water_model` is `Bodies`.
- `test_a_new_world_runs_saves_and_loads_its_water_model` (new): for each model, `test_field_game_config()` and `make_field_test_game_content()`, a setup from `make_world_setup(default_world_file_settings(config), content.planets, "Water", DEFAULT_WORLD_SEED)` stepped to the model, the plan `new_world_plan("Water", DEFAULT_WORLD_SEED, world_file_settings_from_setup(setup, content.planets), "", false, false)` (the Create path, nothing written), `start_session`. Then `simulation.world.settings.water_model` and `simulation.field.world.water_model` are the model; under bodies `water_bodies[WATER_BODY_SEA]` is alive and the sea, under teleport `water_bodies` is empty. Two ticks (`tick_field_test_simulation` with `field_test_content`), the hash, then `reload_field_test_session` (the bytes path, which is the joiner's `load_world_from_files`): `file.settings.water_model`, the loaded world's settings and field model are the model, and the hash is equal. It builds its plan itself and does not use `start_field_test_session`, which 0367 changes.

`src/ui_audit_test.odin`: `audit_new_world_pooling_water :: proc(audit: ^Ui_Audit)` (the shape of `audit_crafting_waits_on_a_full_inventory`): `audit.title.setup.water_model` set to `Bodies`, restored on return, `audit_case(audit, {name = "new world, pooling water", screens = {.Title, .New_World}})`, called in `audit_every_case` after the `"new world"` case. The existing `"new world"` case (with `walk_focus`, so the row's tooltip too) draws Flowing's description; this one draws Pooling's. Both run every `UI_AUDIT_SIZES` entry, 960 by 540 the smallest, at both text scales and the Deck's.

`src/main_test.odin`:

- `test_command_line_usage_lists_every_flag`: `"--water-model"` in the list.
- `test_command_line_water_model` (new): an empty command line gives `(Teleport, true)` for a teleport fallback and starts no world; `--water-model=bodies` has no value problem and no conflict, starts a world, and `command_line_plan(command_line, test_game_config(), "", false)` gives a new world plan whose settings hold bodies (without the flag teleport); `--water-model=lakes` has a value problem with the prefix `invalid --water-model`; with `--load=a` the conflict's prefix is `--load and --water-model`, with `--tech-demo=bodies` `--tech-demo and --water-model`, with `--benchmark=1` `--benchmark and --water-model`, with `--relief-map=planet` and `--relief-map-file=x.png` it contains `--water-model`, with `--join=a` it is not empty, with `--model-check=all` its prefix is `--model-check runs no world`; with `--server` there is none. `test_command_line_tech_demo`'s `--tech-demo=rivers` keeps its `invalid --tech-demo` prefix.

`tools/frame_profile_test.py` (new, unittest, the shape of `tools/test_tiers_test.py`, run as `python3 tools/frame_profile_test.py`):

- `test_runs_of_another_water_model_come_last`: a views file of `spring` and `spring_bodies` (`water_model = "bodies"`), distances `[512]`, viewports `[1, 2]`, a factory: the runs in order are spring 1, spring 2, factory 2, factory 1, spring_bodies 1, spring_bodies 2, the last two with `"bodies"`, the others with None.
- `test_the_game_command_names_the_water_model`: `--water-model=bodies` in the command for bodies, no `--water-model` argument for None.
- `test_a_new_water_model_starts_a_game_without_counting_a_restart`: `run_needs_start` gives (False, False) for the same model, (True, False) for another, (True, True) for a lost game under either.

### Docs

- `doc/ui.md`, Other screens, the New world bullet: after Terrain detail, Water (Flowing or Pooling, the water model teleport or bodies, Flowing by default, with the value's one line description dim under the row).
- `doc/architecture.md`, The water field, the water model bullet: chosen on the New world screen's Water row (0379: Flowing is `Teleport`, Pooling `Bodies`, Flowing by default), by `--water-model` for a world the command line starts, on the Tech demo screen or by `--tech-demo`; the rest of the bullet stays.
- `doc/content.md`, the field's world settings bullet: `water_model` (`Teleport` or `Bodies`, default teleport) in the list, pointing at architecture.md, The water field.
- `DESIGN.md`, World settings: the water model (flowing or pooling) after the terrain sample spacing.
- `doc/build.md`, Command line: a row `--water-model=<teleport|bodies>` after `--name`, `--load` (the water model of a new world, as the New world screen's Water row sets it; default teleport); the `--load` line names it among the flags it refuses and among those that start a new world like `--seed`; the `--benchmark` bullet's refused list gains it.
- `doc/build.md`, Frame profile: The game (`--water-model=<model>` for a view's model), The views (after the factory in one, the views that name a `water_model`, in a fresh game started under it, one viewport then two), The waits (a lost game restarts under the run's model; a model's start is not counted in the head's restarts), and the tests `python3 tools/frame_profile_test.py`.
- `SUGGESTIONS.md`: nothing. Its question was removed in bb7981a ("Record the user's answers and add 0377 to 0379").
- `doc/code_map.md`: no line names what changes; the implementer runs the check and follows what it reports.

The capture of the screen with the row is the main agent's.

### Hand-back check

- Memory a frame draws from: the description is a string table entry, as every label's.
- A number parsed from text: none; the flag's word is matched exactly.
- A changed save layout: none (above).
- A long string: the description is unfitted, checked by the audit at 960 by 540 and both text scales; the strings are at most 40 characters.
- An obsolete audit case: none; the new case draws Pooling's description.
- Tests: in-memory sessions and save bytes, saves "" and not found; `command_line_plan` with saves "" and not found.

### Decided

1. The seam is the setup's own field through `world_file_settings_from_setup`, since the record, the save and the joiner already carry the model. Rejected: a default key in `data/game.sjson`. "Teleport for now" is a constant, and only three of the screen's defaults come from the data today.
2. The row goes after Terrain detail: the planet rows are the world's physical shape, Mode and Keep inventory its rules of play.
3. The tech demo keeps its row's names (Teleport pressure, Bodies), the screen that judges the models by their rules.
4. The profile's seam is a command line flag (above). The profile already starts a fresh game after a lost one, so a model is one more start.

### Collisions with 0367

- 0367's item says the spring view under bodies is added at its landing (its decision 8 and the note under it). This item adds it, so one of the two must drop it (question 2).
- 0367 adds a `water_model` parameter to `start_field_test_session`. This item does not touch that helper or `simulation_field_test.odin`.
- `doc/architecture.md`, The water field: 0367 edits Storage, Sleeping, Sources, Bodies and The look, this item the water model bullet. Different lines, so a rebase merges them.

### Questions for the main agent

1. The item says the tech demo's start uses bodies, but the code's default is teleport. This design leaves the tech demo as it is. Should `DEFAULT_TECH_DEMO_SETUP` (and `--tech-demo`'s empty model word) become bodies?
2. The bodies spring view: strike it from 0367's landing, since this item adds it?
3. `--water-model` is a flag the user did not ask for, added for the profile. Keep it, or give the profile another way?

### Approved (main agent, 2026-11-11)

1. The tech demo is left as it is; the item's premise was wrong and is corrected above.
2. This item adds the `spring_bodies` view. 0367 lands without it.
3. `--water-model` is kept: a developer flag, listed in `doc/build.md` only.
4. The values are named Teleport and Bodies (user, 2026-11-11); wherever the specification says Flowing or Pooling, in strings, keys, the audit case and the docs, read Teleport and Bodies. The implementer was told.
