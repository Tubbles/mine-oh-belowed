# 0003 Steam library shortcut

Status: implemented
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

## Notes

- 2026-09-26: `tools/add_steam_shortcut.py` written and validated with `--dry-run` against the existing file. Not run for real because the Steam client was running (gamepad UI) at the time. Run it once Steam is closed, then disable Steam Input for the shortcut in Steam's controller settings.
- 2026-09-27: run for real with Steam closed (the user shut it down from the desktop). The shortcut is entry 2 with app id -1640630315, exe `bin/mine-oh-belowed`, start directory the repository root. A backup of the previous file is in `tmp/`. Left for the user: disable Steam Input for the shortcut in its controller properties, then launch it; that is the verify step.

