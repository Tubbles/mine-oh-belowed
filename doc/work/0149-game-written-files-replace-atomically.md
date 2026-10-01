# 0149: Every file the game writes goes through write_file_replacing, a malformed settings file falls back

Status: implemented

## Goal

Three files the game writes bypass `write_file_replacing` (the content and presentation audits, `SUGGESTIONS.md`): the settings (`write_settings_file`, `configuration_output.odin`), the touch layouts (`touch_overlay.odin`) and the texture edits (`write_texture_edits_file`, `texture_generate.odin`). A crash or a full disk mid write leaves a truncated file; for the settings, `main` then exits on the configuration problem and the game does not start. Both break the hand-back check in `CLAUDE.md`.

## Change

- The three writes go through `write_file_replacing` (tmp and rename), which moves to the platform package if it is not there yet, since the three callers sit in three clusters.
- A problem in the game written settings file (`90-settings.sjson` under the configuration directory) no longer exits: the file is renamed aside with a `.broken` suffix, one log line names it, the defaults load, and the title screen shows a toast. Problems in the other configuration files keep today's behaviour (the user wrote them; strictness surfaces typos).
- `doc/architecture.md` (Configuration and directories) states the fallback; the hand-back check's second line already covers the rule.

## Verify

- A test writes a truncated settings file into a temporary configuration directory and loads: defaults, the file renamed aside, the problem reported. A test for each of the three writers checks that no `.tmp` file remains and the content is complete after a write.
- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`.

## Implementation notes

- `write_file_replacing` moved byte for byte from `data_export.odin` (tools) to `src/platform/file_write.odin`, beside a new `rename_file_aside`; the export and the data browser call it as `platform.write_file_replacing`. No cluster edge count changed (none of the three writers referenced tools before); the cluster line counts in `doc/code_map.md` are updated.
- The three writers (`write_settings_file`, `write_touch_layouts_file`, `write_texture_edits_file`) hand their text to it; their own `make_directory_path` calls went, since it makes the parent directory itself. Their problem lines now read as the export's (`<error>: <path>`) instead of `cannot write <path>: <error>`.
- The settings file is `config.d/90-settings.sjson` under the user configuration directory (`SETTINGS_FILE_NAME`), the last drop in of the usual names. Before this item `load_configuration` returned one problem string naming the file (a parse failure from `read_configuration_layer`, an unknown key or wrong type from the provenance, a range from `validate_settings`), and `main` logged it and exited with 1.
- The decision is in `load_configuration_at_start` (`configuration.odin`), which `main` calls instead of `load_configuration`: on a problem it loads again over the same files without the settings file (`load_configuration_files`, the split out body of `load_configuration`). When that load succeeds the settings file was the cause; it is renamed to `90-settings.sjson.broken` (over an older `.broken`), the line `configuration: the settings file did not load, the game starts without it: <problem>; set aside as <path>.broken` is logged, and the third result `settings_problem` is set. When the second load fails too, the first problem stands and main exits as before, the settings file untouched. The `config` subcommand and the tests keep calling `load_configuration`, so they never move a file.
- The toast is the data edits fallback's mechanism: a `ui_toast` in `run_game` right after the data edits one, driven by the new `Player_Configuration.settings_set_aside`, string `settings_file_set_aside_toast`.
- A font setting the fonts file does not offer (`font_settings_problem`, checked in `load_start_data` after the configuration loaded) falls back as well: `load_start_fonts` (`main.odin`) logs `configuration: <problem>; the default font is used` and sets `Start_Data.fonts_fell_back`; `main` applies `settings_with_default_fonts` (the families of `DEFAULT_SETTINGS`, the rest of the settings kept) and the title screen toasts `settings_font_default_toast` once. This holds whichever layer set the font, since a family can vanish with a build or with the data edits turned off; the settings file stays in place and is rewritten with the default font only when the settings change. The `config` subcommand keeps `load_checked_fonts` and exits.
- The set aside toast reads "did not load, the game started without it", which is true also when the rename failed.
- Tests: `test_an_unavailable_font_setting_falls_back_to_the_default_at_start`, `test_a_cut_off_settings_file_is_set_aside_at_start`, `test_a_settings_file_with_a_refused_value_is_set_aside_at_start`, `test_a_problem_outside_the_settings_file_still_stops_the_start`, `test_the_settings_file_is_written_whole`, `test_the_touch_layouts_file_is_written_whole`, `test_the_texture_edits_file_is_written_whole`.
- Not covered: a cut off file the game does not read at start (touch layouts, texture edits) keeps its own handling (the touch layouts lock, the texture edits ignored whole); with the writes atomic they no longer arise from a crash mid write.
- Left by this item (found in review): no test covers an unreadable settings file (a permission case; on Linux the rename in a writable directory still sets it aside, in an unwritable one the game continues with the log line). When both the settings file and a lower user file are broken, the exit message names the settings file while the remaining cause is in the user's file (diagnostic only, the old behaviour).
- `write_file_replacing` covers the files the game writes and reads back; the data copy of `data_load.odin` and its stamp, and the screenshots, still write in place, and a save gets the same guarantee from its staging directory renamed whole.
