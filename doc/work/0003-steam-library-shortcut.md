# 0003 Steam library shortcut

Status: todo
Milestone: M0

## Goal

The game starts from the Steam library on the couch machine.

## Deliverables

- A non-Steam shortcut "Mine oh Belowed" in `~/.steam/steam/userdata/11963684/config/shortcuts.vdf` (binary VDF) pointing at the built binary or a launcher script in the repository, with `StartDir` set to the repository root. Existing shortcuts (Prism Launcher, Battle.net) must survive untouched.
- Steam Input disabled for the shortcut so SDL3 gets the raw controller (see `doc/input.md`), unless 0002 chose the fallback path.
- A short note in `doc/build.md` on how the shortcut is set up and re-created.

## Constraints

- Steam must be closed while `shortcuts.vdf` is edited, otherwise Steam overwrites the file on exit. Check with `pgrep -x steam` first.
- Keep a backup of the original file in `tmp/` before writing.

## Verify

- User: the game appears in the Steam library and launches into the diagnostics screen from 0001.
