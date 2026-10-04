# 0228: The data edits overlay read from a reachable directory

Status: todo (2026-10-04, from the user on the phone, "Didn't we add an overlay dir path config?": 0131 added the export direction only, nothing reads an overlay from a directory the phone's file managers reach)

## Goal

On the phone a data file copy dropped into a folder the user can reach (Downloads, or the export directory itself) wins over the app's data, as a copy under the state directory's `data_edits/` does on the couch, so a layout or a record can be tried on the phone without adb and without a preview APK.

## Controls

No binding changes. The setting is a path field on the Data files screen beside Export to (string field, the keyboard).

## Change

- A setting `edits_directory` (absolute path, default empty; expanded `~/`), written to `config.d/90-settings.sjson` like `export_directory`. While set and readable, the overlay reader (`data_edits_reading`, [architecture.md](../architecture.md), Data edits) takes a copy from `<edits_directory>/data_edits/<relative path>` before the state directory's copy; the state directory's copy stays the one the Data files screen writes. The export directory may be the same directory: Export writes `<directory>/data_edits/`, so an edit made on the couch and exported lands where the phone reads it, and an edit written by hand there reads on both.
- The watcher (`shared:fsw`) watches the directory as it watches the state overlay, so a changed copy reloads as today; a directory that disappears turns the reading off for the run with one log line (as `turn_data_edits_off`).
- On Android the directory needs All files access as Export does: without it the setting's page opens with one toast.
- Docs: `doc/developer_tools.md` (Data files screen, a section beside Export), `doc/architecture.md` (Data edits: the second source and its precedence), `doc/android.md` (the paths table).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`.
- Tests: with the setting pointing at a temporary directory, a copy there wins over the data file and loses to the state directory's copy; an unreadable directory turns the reading off and the data file loads; a relative path is refused with its toast; tests never touch the machine's state directory (the hand-back check).
- On the phone: a `data_edits/touch_overlay.sjson` with a B button in Downloads, the setting pointing at Downloads, the button shows after a restart.
