# 0034 Command line through core:flags

Status: implemented
Milestone: M5

## Goal

Replace the hand written argument parsing in `src/main.odin` with `core:flags`, the idiomatic Odin way, keeping every documented flag and the `config` subcommand working with the same spelling, and gaining generated usage text and typed errors.

## Deliverables

- A `Command_Line` struct annotated with `args` tags, parsed with `flags.parse_or_exit` in Unix style so `--seed=42`, `--load=<name>`, `--name=<name>`, `--input=sdl3`, `--debug-terrain`, `--unlock-all`, `--version` and `--set=<key>=<value>` (repeatable) keep their spelling; `config` as a positional command; `usage` tags on every field so `--help` prints a real usage page.
- Validation that belongs to the game stays in the game (seed as an unsigned 64 bit decimal, `--load` combined with `--seed` refused, the input backend names) and reports through the existing log, with the same messages and exit codes as today: 2 for a bad command line, 1 for a failed start.
- `doc/build.md` command line paragraph updated to mention `--help`.
- Tests: the existing command line tests updated to the new parser, plus one for `--help` output containing every flag and one for a repeated `--set`.

## Verify

- `./build.sh check`, `./build.sh test`, `./build.sh`, `./build.sh release` pass.
- `./bin/mine-oh-belowed --help` prints usage and exits 0; `./bin/mine-oh-belowed --seed=bogus` exits 2 with the seed message; `./bin/mine-oh-belowed config` prints the configuration as before.

## Notes

- Deviation: `parse_command_line` returns `(Command_Line, flags.Error)` instead of `(Command_Line, ok)`, because `main` needs to tell a help request (exit 0) from a parse error (exit 2). `flags.parse_or_exit` is not used: it exits with status 1 on a parse error, and the game needs 2.
- `Command_Line` holds only flags. The seed and the input backend are plain strings, checked after parsing by `command_line_value_problem` (same messages as before); `command_line_seed` and `parse_input_request` turn them into values. `seed_given` became `seed != ""`, `show_configuration` became `subcommand == "config"`. `parse_input_request` now maps the empty string to `.Automatic`.
- Behaviour changes that come with `core:flags`: the space form works too (`--seed 42`, `--set key=value`), a single dash works (`-seed=42`), bool flags accept `--debug-terrain=false`, and an empty value such as `--load=` or `--seed=` is now a parse error (before, `--load=` was ignored and `--seed=` gave the seed message). Unknown flags print the package message, for example "Unable to find any flag named `bogus`.", followed by "(see --help)".
- The usage page lists the positional as `--subcommand <string>` in the Flags section; that is how `core:flags` renders positionals, and `--subcommand=config` is accepted as a side effect.
- `SET_ARGUMENT_PREFIX` in `src/configuration.odin` is now unused. It was left in place because this item only allowed changes to `src/main.odin`.
- Not verified: a windowed start with each flag (headless session). The flags that start a world were checked only through the tests and the early exits.
