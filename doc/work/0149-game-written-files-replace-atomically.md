# 0149: Every file the game writes goes through write_file_replacing, a malformed settings file falls back

Status: todo

## Goal

Three files the game writes bypass `write_file_replacing` (the content and presentation audits, `SUGGESTIONS.md`): the settings (`write_settings_file`, `configuration_output.odin`), the touch layouts (`touch_overlay.odin`) and the texture edits (`write_texture_edits_file`, `texture_generate.odin`). A crash or a full disk mid write leaves a truncated file; for the settings, `main` then exits on the configuration problem and the game does not start. Both break the hand-back check in `CLAUDE.md`.

## Change

- The three writes go through `write_file_replacing` (tmp and rename), which moves to the platform package if it is not there yet, since the three callers sit in three clusters.
- A problem in the game written settings file (`90-settings.sjson` under the configuration directory) no longer exits: the file is renamed aside with a `.broken` suffix, one log line names it, the defaults load, and the title screen shows a toast. Problems in the other configuration files keep today's behaviour (the user wrote them; strictness surfaces typos).
- `doc/architecture.md` (Configuration and directories) states the fallback; the hand-back check's second line already covers the rule.

## Verify

- A test writes a truncated settings file into a temporary configuration directory and loads: defaults, the file renamed aside, the problem reported. A test for each of the three writers checks that no `.tmp` file remains and the content is complete after a write.
- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`.
