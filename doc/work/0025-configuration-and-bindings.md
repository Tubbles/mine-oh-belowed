# 0025 Configuration files and bindings in configuration

Status: implemented
Milestone: M5

## Goal

Settings and input bindings live in configuration files following the layering from the global preference (SJSON, XDG directories, `config.d`, strict keys), with a `config` subcommand that shows where each value came from. The hardcoded binding tables become data.

## Deliverables

- Configuration loading per `doc/architecture.md`: `$XDG_CONFIG_DIRS/mine-oh-belowed/config.sjson` (last to first), `$XDG_CONFIG_HOME/mine-oh-belowed/config.sjson`, `$XDG_CONFIG_HOME/mine-oh-belowed/config.d/*.sjson` sorted by name, then command line flags. Objects merge recursively, scalars and arrays replace. Unknown keys and wrong types are errors naming the file. Home expansion for path values.
- `mine-oh-belowed config` prints the files found in precedence order and the effective values with defaults filled in.
- The `Settings` struct (UI scale, pointer speed, gyro, sensitivities, invert, autosave interval) is read from configuration and written back to `$XDG_CONFIG_HOME/mine-oh-belowed/config.d/90-settings.sjson` when changed in the settings screen, leaving other files alone.
- Bindings: the default tables of both input backends move to `data/bindings.sjson` (action, device, control, context), the configuration may override any binding, and the settings screen shows the effective bindings read only for now. The world and menu contexts stay as they are.
- Logs go to `$XDG_STATE_HOME/mine-oh-belowed/` (a small log file of the stderr lines the game already prints).
- Tests: layering precedence with temporary directories, merge rules, unknown key and wrong type errors, home expansion, bindings loading and override, the config dump.

## Verify

- Builds and tests pass.
- User: change the UI scale in settings, quit, see it in `config.d/90-settings.sjson`, put a binding override in a file, and see it take effect.

## Notes

Implemented 2026-09-27. Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (384 tests, 12 new in `configuration_test.odin` and `bindings_test.odin`), `./build.sh`, `./build.sh release`, `--version`, and `mine-oh-belowed config` with scratch XDG directories (file list with missing files marked, effective values, exit 0, nothing created). A run with a typo in a `config.d` file exits 1 with `error: <that file>: unknown key settings.gyro`, also in the log.

Code: `configuration.odin` (layers, generic SJSON trees merged with per key provenance, reflection mapping onto `Configuration`, range checks, home expansion, `--set`), `configuration_output.odin` (the dump, `90-settings.sjson`), `bindings.odin` (entries, vocabulary, overrides, per backend tables, Controls rows), `logging.odin`, `data/bindings.sjson`, with changes to `main.odin`, `loop.odin`, `input_raylib.odin`, `input_sdl3.odin`, `input_actions.odin`, `ui_screens.odin`, `save_world.odin`, `settings.odin`, `data/strings/en.sjson`, and every former `fmt.eprintfln` call site.

### Deviations

- The former tables differed between backends: the raylib pad had no Sneak on B and no Sprint on the left stick click. To keep every control as it was, a binding takes an optional `backend` (`sdl3`, `raylib`), and those two entries are `sdl3` only. A test compares the tables built from `data/bindings.sjson` with copies of the former hardcoded tables, per backend.
- `context` does not gate anything. Actions reach the world or not through `WORLD_ACTIONS` as before, and the UI reads every action. The field is validated (`world`, `menu`, `both`) and shown, nothing more. `context` is an Odin keyword, so the struct field is `binding_context` with a `json:"context"` tag, and the reflection mapping honours json tags.
- The sticks (move, look) and WASD stay in code; they are axes, not actions. Stick axes are not in the gamepad vocabulary, only the two trigger axes.
- Configuration `bindings` is a list in the data file's shape. Across configuration layers it follows the array rule, so a later file's list replaces an earlier file's whole list. Against the defaults, every action the list mentions loses all of its default bindings.
- The command line layer is `--set=<key>=<value>` (repeatable, value parsed as JSON5, otherwise taken as a string). No other flag maps onto configuration.
- `paths.saves` sits between `MINE_OH_BELOWED_SAVES` (still wins) and `$XDG_DATA_HOME`.
- Settings ranges are validated (the slider ranges, autosave 0 to 1440 minutes) with the file named, beyond the requested type checks.
- `90-settings.sjson` holds the whole `settings` object, written when the settings screen is left with changed values and on exit. It is written with the dump's writer rather than `json.marshal`, which prints an f32 1.15 as 1.14999998. Consequence: once written, it overrides every setting from `config.sjson`, including ones the player did not touch there.
- The Controls list is a third settings tab, "Bindings", one row per bound action. The existing "Controls" tab keeps the sensitivities.
- The raylib backend reports the bindings it cannot express (paddles, MISC2, the left trackpad: 12 by default) in one `input:` line at start.
- Argument errors printed before the log opens (unknown argument, bad seed) go to stderr only. The `config` subcommand does not open the log. The log grows without bound.

### Not verified

Everything in a window: the Bindings tab layout and scrolling, the settings file being written when leaving the settings screen and on quit, a binding override taking effect on a real pad or keyboard, and the raylib pad through the SDL name mapping table (`raylib_gamepad_button`).

### Open questions

- Drop the `backend` field and give the raylib pad Sneak on B and Sprint on the stick click like SDL3?
- Should `context` gate actions, or be removed from the format?
- There is no way to unbind an action entirely (an empty override list cannot name its action). Add a `none` control?
- Would a `bindings` object keyed by action (merging per action across layers) suit layered files better than the list?
- Should `90-settings.sjson` hold only the values that differ from the lower layers?
- `doc/input.md` ("Bindings implemented so far" still points at the source tables), `doc/architecture.md` (Configuration: `--set`, the bindings file, the log) and `doc/ui.md` (Bindings tab) need updates; this run could not touch them.
