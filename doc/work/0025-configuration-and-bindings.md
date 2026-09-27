# 0025 Configuration files and bindings in configuration

Status: todo
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
