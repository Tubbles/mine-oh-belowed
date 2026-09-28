# 0076 Steam Deck verification

Status: implemented
Milestone: M11

## Goal

The Steam Deck is a supported target (user, 2026-09-27). The game must hold its frame rate on the Deck's APU at 1280 by 800, its UI must fit and read at arm's length, and the Deck's built in pads, gyro and grips must work through Steam Input the way the couch does.

## Deliverables

- Performance: the benchmark (0050) run on a Deck, and the rendering settings (weather particles, view distance) tuned for a Deck preset chosen automatically when the device is a Deck (`SteamDeck=1` in the environment). The frame rate cap setting itself comes from 0080 (Off, 30, 40, 60 and up); the Deck preset picks its value.
- UI: the audit's 1280 by 800 entries stay green, text sizes checked at arm's length, the safe area for the Deck's screen.
- Controls: SDL's Steam Deck HIDAPI driver behind the same launcher override, pads, gyro (from Steam's layout, 0044 notes) and the four grips mapped like the Steam Controller's; verified in Game Mode on the device.
- A Deck section in `doc/input.md` and `doc/build.md` (installing the play build on a Deck over SSH).

## Verify

- Builds and tests pass.
- User: a full chapter 1 on the Deck at a steady frame rate with the built in controls.

## Notes

Implementation pointers (main agent, 2026-09-28). Lands last, after 0050 gives the benchmark numbers; the device work is the user's.

- Deck preset: `deck_preset_active(environment) -> bool` (a new `src/deck_preset.odin`, pure, tested) is true when `SteamDeck=1` is in the environment and no `--set` names the settings it would change; on the first start on a Deck (no `90-settings.sjson` yet, or one without the marker key `deck_preset_applied = true` which the preset writes) the preset sets `frame_rate_cap` 40, `weather` on, `ui_scale` 1.1, `text_scale` 1.1, `window_mode` borderless, and logs one line; a later start leaves the player's choices alone.
- The audit's 1280 by 800 entries stay in the matrix (they are), with the text scale 1.1 added; the safe area for the Deck's screen is the existing safe area, checked visually by the user.
- Controls: the launcher already carries the SDL override; the Deck's own pads, gyro and grips go through Steam Input's virtual pad plus the Steam layout for the gyro as the couch does (0044 notes); a `doc/input.md` section says what to set in the Deck's layout (gyro to mouse, the grips to the same actions as the Steam Controller's) and a `doc/build.md` section says how to copy a play build to the Deck over SSH (`tools/install_play_build.sh` gains a `--target user@host:path` that runs the same install over ssh and rsync) and add the shortcut with `tools/add_steam_shortcut.py`.
- The benchmark (0050) is run on the Deck by the user with `--benchmark=4`; the numbers go to `doc/content.md` "Learned from couch tests" next to the couch machine's.
- Tests: the preset decision per environment and settings state, the marker key round trip, the audit at text scale 1.1 and 1280 by 800.
- Docs: `doc/input.md`, `doc/build.md`, `doc/ui.md` (the preset), `doc/log/<date>.md`, this item's Status and Notes.

Facts for the implementation (main agent, 2026-09-28, after 0085 landed): the settings file is `SETTINGS_FILE_NAME` (`90-settings.sjson`, `src/configuration.odin`), written by `write_settings_file(environment, settings)` (`src/configuration_output.odin`) whenever the frame loop's `write_changed_settings` sees the settings differ from the stored ones; `load_configuration` merges the layers and returns a `Configuration_Provenance` that says which file or `--set` gave each key, so the preset can tell a key nobody set from one the player chose. The marker is a real `Settings` field (`deck_preset_applied: bool`, default false, documented in `doc/configuration` docs where the keys are listed), since unknown keys are configuration errors. `SteamDeck=1` comes from `os.get_env` at start, passed into the pure decision as a string. The preset runs once in `main` right after `load_configuration` and before `run_game`, and when it applies it writes the settings file at once through `write_settings_file`, so the marker is on disk before the first frame. Verification runs through `./build.sh check|test|release` (0085: the raylib collection needs the flag). `tools/install_play_build.sh` builds from a `git archive` of a commit into `bin/play/builds/<stamp>-<commit>/`; the `--target user@host:path` option runs the same build here and copies the build directory and the launcher over with `rsync` through ssh, then switches the remote `current` link the same way (a rename), never installing locally in that case.

Files a subagent may touch: new `src/deck_preset.odin` and `src/deck_preset_test.odin`, `src/configuration.odin`, `src/configuration_output.odin`, `src/configuration_test.odin`, `src/main.odin` or wherever the configuration is resolved at start, `src/ui_audit_test.odin`, `tools/install_play_build.sh`, the docs above, this file.

Implemented (2026-09-28, the part that needs no Deck): `src/deck_preset.odin` holds the pure decision `deck_preset_active(steam_deck, settings, provenance)` (the `SteamDeck` value, the loaded settings and their provenance: true for `1` without the marker and without a `--set` of any key in `DECK_PRESET_KEYS`), the pure `apply_deck_preset(settings)` and `apply_deck_preset_at_start(environment, &loaded)`, which `main` calls right after `load_configuration`; it reads `SteamDeck` with `os.get_env`, writes the settings file through `write_settings_file` and logs one line. The marker is `Settings.deck_preset_applied` (`src/settings.odin`, outside the listed files, since `Settings` lives there). Tests: `test_deck_preset_decision` (unset, `0`, `1`, the marker, a `--set` of another key and of each preset key), `test_deck_preset_values` (the preset's values, other settings kept, `validate_settings` passes), `test_deck_preset_marker_round_trip` (first start, the marker on disk, a later player choice kept, a settings file without the marker taking the preset) and the marker in `test_settings_file_round_trip`; the UI audit runs every case at `UI_AUDIT_DECK_SIZE` (1280 by 800, UI scale 1.1) with text scale 1.1 after its matrix. `tools/install_play_build.sh` takes `--target user@host:path` (and `--help`); its procedures `switch_current_build` and `remove_old_builds` run locally or are sent to a remote `bash -s`, verified with stub `ssh` and `rsync` acting on a local directory over three installs (the link switched, the oldest build removed, the local `bin/play/current` untouched). Docs: `doc/build.md` and `doc/input.md` (Steam Deck), `doc/ui.md` (Steam Deck preset, the audit), `doc/log/2026-09-28.md`. Left for the user on the device: the benchmark, the frame rate, the controls, the safe area, and whether SteamOS provides the libraries the binary links (`doc/build.md`).
