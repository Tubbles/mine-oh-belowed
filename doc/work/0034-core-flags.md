# 0034 Command line through core:flags

Status: todo
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
