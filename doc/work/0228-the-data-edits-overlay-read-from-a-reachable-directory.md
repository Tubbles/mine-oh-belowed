# 0228: The data edits overlay read from a reachable directory

Status: implementing (2026-10-04, in `.claude/worktrees/0228` on `item/0228` from `main` at 3573cb0, the specification approved the same day with the decisions below; from the user on the phone, "Didn't we add an overlay dir path config?": 0131 added the export direction only, nothing reads an overlay from a directory the phone's file managers reach)

## Goal

On the phone a data file copy dropped into a folder the user can reach (Downloads, or the export directory itself) wins over the app's data, as a copy under the state directory's `data_edits/` does on the couch, so a layout or a record can be tried on the phone without adb and without a preview APK.

## Controls

No binding changes. The setting is a path field on the Data files screen beside Export to (string field, the keyboard).

## Change

- A setting `edits_directory` (absolute path, default empty; expanded `~/`), written to `config.d/90-settings.sjson` like `export_directory`. While set and readable, the overlay reader (`data_edits_reading`, [architecture.md](../architecture.md), Data edits) takes a copy from `<edits_directory>/data_edits/<relative path>` after the state directory's copy and before the data file (the approval's decision 1); the state directory's copy stays the one the Data files screen writes. The export directory may be the same directory: Export writes `<directory>/data_edits/`, so an edit made on the couch and exported lands where the phone reads it, and an edit written by hand there reads on both.
- The watcher (`shared:fsw`) watches the directory as it watches the state overlay, so a changed copy reloads as today; a directory that disappears turns the reading off for the run with one log line (as `turn_data_edits_off`).
- On Android the directory needs All files access as Export does: without it, Done on the field opens the access settings page with one toast, and a start finds the setting set without access logs one line and shows one toast (decision 3).
- Docs: `doc/developer_tools.md` (Data files screen, a section beside Export), `doc/architecture.md` (Data edits: the second source and its precedence), `doc/android.md` (the paths table).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`.
- Tests: with the setting pointing at a temporary directory, a copy there wins over the data file and loses to the state directory's copy; an unreadable directory turns the reading off and the data file loads; a relative path is refused with its toast; tests never touch the machine's state directory (the hand-back check).
- On the phone: a `data_edits/touch_overlay.sjson` with a B button in Downloads, the setting pointing at Downloads, the button shows after a restart.

## Specification (design, 2026-10-04)

### Findings that shape the design

- The state overlay is not watched today: `data_load.odin` (comment over `DATA_EDITS_DIRECTORY_NAME`), `hot_reload.odin` (comment over `apply_data_edit_change`) and `doc/architecture.md` (Data edits overlay, third bullet) all say so; only the data directory has an `fsw` watcher (`open_data_watch`, `data_watch.odin`). The Change's "watches the directory as it watches the state overlay" therefore means: a second recursive `fsw` watcher beside the data directory's, under the same `watch_data` mode, whose events map to categories exactly as the data directory's do.
- The Change says the edits directory's copy is taken "before the state directory's copy"; the Verify says a copy there "loses to the state directory's copy". This specification takes the Verify's order (state copy, then edits directory copy, then data file), see Open questions answered, 1, and Questions to the main agent, 1.
- `fsw.watch_dir_recursive` on Linux returns `.None` for a directory that does not exist (`rec_add_watch` ignores the failed `inotify_add_watch`), so the watcher is only opened on a directory the start found. A removed root arrives as one event whose `path` equals the watcher's `path` (no name), kind `.Removed` (`DELETE_SELF`) or `.Renamed` (`MOVE_SELF`); `data_event_category` already reports it `.Ignored`.
- Settings are read and written by reflection (`assign_configuration_struct`, `settings_file_text`), so a new `string` field in `Settings` is read from and written to `config.d/90-settings.sjson` with no further code.

### The setting

- Key `settings.edits_directory`, type string, default `""` (none). New field in `Settings` (`src/settings.odin`) right after `export_on_save`, with a comment: "The Data files screen's edits directory (work item 0228, data_load.odin): `<edits_directory>/data_edits/<relative path>` is read after the state directory's overlay copy and before the data file; "" for none. Read at start only." `DEFAULT_SETTINGS` gains `edits_directory = ""` after `export_on_save`.
- Bounds: absolute after a leading `~/` is expanded (`expand_home_path`, `data_export.odin`), or empty. Not checked in `validate_settings`: a relative value written by hand over USB is logged at start and not read (below), it does not set the settings file aside (setting aside would drop every other setting over one path).
- Typed on the Data files screen: trimmed, `~/` expanded, a relative result refused with a toast and the setting kept; Done with a changed value toasts that it applies at the next start (see Answered, 2).

### Reading (`src/data_load.odin`)

- `Data_Edits_Reading` gains two fields after `off_problem`: `reachable_directory: string` (`<edits_directory>/data_edits`, on the heap for the run, "" for none; set by `use_reachable_data_edits`) and `reachable_off: bool` (the directory went away or failed during the run). Comment on the struct extended: the edits directory's overlay is resolved once at start on the main thread; tests set their own through `use_reachable_data_edits`.
- New `Reachable_Data_Edits_Refusal :: enum u8 {None, Not_Set, Not_Absolute, No_Access, Not_A_Directory}`.
- New, pure: `reachable_data_edits_refusal :: proc(setting: string, access_granted, directory_exists: bool) -> Reachable_Data_Edits_Refusal`. In this order: `setting == ""` gives `Not_Set`; `!os.is_absolute_path(setting)` gives `Not_Absolute`; `!access_granted` gives `No_Access`; `!directory_exists` gives `Not_A_Directory`; else `None`. Called by `start_reachable_data_edits`.
- New, pure: `reachable_data_edits_refusal_text :: proc(refusal: Reachable_Data_Edits_Refusal) -> string`: the English log reason ("it is not an absolute path", "All files access is not granted", "it has no data_edits directory"; "" for `None` and `Not_Set`). Log text, not a string key, as the other `data:` lines.
- New: `use_reachable_data_edits :: proc(directory: string)`: deletes the old `reachable_directory`, stores `strings.clone(directory)`, sets `reachable_off = false`. Called by `start_reachable_data_edits` and by tests.
- New: `start_reachable_data_edits :: proc(settings: Settings) -> (needs_access: bool)`: expands the setting against `platform.platform_directories(context.temp_allocator).home`; asks `platform.all_files_access_granted()` only when the setting is a non empty absolute path; checks `os.is_dir(platform.join_path(setting, DATA_EDITS_DIRECTORY_NAME))` only when access is granted; maps through `reachable_data_edits_refusal`. `None`: `use_reachable_data_edits(<setting>/data_edits)` and logs `data: reading data edits from <directory>`. `Not_Set`: nothing. Otherwise one line `data: the edits directory <setting> is not read: <reason>`. Returns `refusal == .No_Access`. Called once from `main` (`src/main.odin`) right after `apply_deck_preset_at_start` and before `load_start_data`.
- New: `turn_reachable_data_edits_off :: proc(problem: string)`: when `reachable_directory != ""` and not `reachable_off`, sets `reachable_off = true` and logs one line `data: the edits directory <reachable_directory> is off for this run: <problem>`; otherwise nothing, so the line is logged once. Called by `reachable_data_edits_directory` and `poll_data_watch`.
- New: `reachable_data_edits_directory :: proc() -> string`: "" when `data_edits_reading.off`, `reachable_off` or `reachable_directory == ""`; when `!os.is_dir(reachable_directory)` calls `turn_reachable_data_edits_off("the directory is gone")` and returns ""; else the directory. This is the read time check of a vanished directory (one stat per data file read, never per frame). Called by `reading_data_edits_directories` and `update_data_watch`.
- New, pure, the precedence: `data_edits_directories :: proc(state_directory, reachable_directory: string, off, reachable_off: bool) -> [2]string`: `{}` when `off`; else `{state_directory, reachable_off ? "" : reachable_directory}`. Index 0 wins over index 1, both over the data file. Called by `reading_data_edits_directories`; tests drive it directly.
- New: `reading_data_edits_directories :: proc() -> [2]string`: `data_edits_directories(data_edits_directory(), reachable_data_edits_directory(), data_edits_reading.off, data_edits_reading.reachable_off)`. Called by `read_data_file` and `turn_data_edits_off`. `reading_data_edits_directory` stays as it is (the state one; `test_a_broken_data_edit_turns_the_overlay_off_at_start` reads it).
- New: `read_data_file_from_sources :: proc(data_directory: string, edits_directories: []string, relative_path: string, allocator := context.allocator) -> (data: []byte, path: string, error: os.Error)`: the body of today's `read_data_file_with_edits`, looping the directories in order, skipping "", taking the first `os.is_file` copy with the same `data: <relative path> from the data edits overlay <path>` line; else the data file.
- Changed: `read_data_file_with_edits` keeps its signature and becomes `sources := [1]string{edits_directory}; return read_data_file_from_sources(data_directory, sources[:], relative_path, allocator)` (its four test calls stay).
- Changed: `read_data_file` becomes `directories := reading_data_edits_directories(); return read_data_file_from_sources(data_directory, directories[:], relative_path, allocator)`.
- Changed: `turn_data_edits_off` takes `reading_data_edits_directories()` and returns false only when neither entry is a non empty existing directory; otherwise as today (both sources go off together through `data_edits_reading.off`, see Answered, 4).
- Changed: `reset_data_edits_reading` also deletes `reachable_directory` before zeroing.
- The comment over `DATA_EDITS_DIRECTORY_NAME` is rewritten: the state overlay is not watched (the screen's Save and Discard go through `apply_data_edit_change`); the edits directory's overlay (0228) is read after it and watched with the data directory.

### Start (`src/main.odin`, `src/configuration.odin`, `src/loop.odin`)

- `main`: `edits_need_access := start_reachable_data_edits(loaded_configuration.configuration.settings)` after `apply_deck_preset_at_start`; `Player_Configuration` literal gains `edits_need_access = edits_need_access`.
- `Player_Configuration` (`configuration.odin`) gains `edits_need_access: bool` after `fonts_fell_back`, comment: "The edits directory is set but All files access is missing (work item 0228): the title shows one toast."
- `run_game` (`loop.odin`), beside the other start toasts after `fonts_fell_back`: `if player_configuration.edits_need_access { ui_toast(primary_ui(state), text("data_files_edits_access")) }`. The access settings page is not opened at start (decision 3: a page over the title at every start would nag; Done on the field opens it). On the desktop `all_files_access_granted` is always true, so this never fires there.

### The watcher (`src/data_watch.odin`, `src/hot_reload.odin`)

- `Data_Watch` gains `edits_watcher: fsw.Watcher_Recursive`, `edits_open: bool`, `edits_unavailable: bool` (could not open, or its directory went away; no more tries this run).
- New: `open_data_edits_watch :: proc(watch: ^Data_Watch, edits_directory: string) -> bool`: as `open_data_watch` on the second watcher; a failure sets `edits_unavailable` and logs `data_watch_open_failed_line(edits_directory, error)`. Called by `update_data_watch`.
- New, pure: `data_edits_watch_root_gone :: proc(watched_directory: string, events: []fsw.Event) -> bool`: true when an event's `path == watched_directory` and its kind is `.Removed`, `.Renamed` or `.Invalidated`. Called by `poll_data_watch`.
- Changed: `poll_data_watch` takes the data watcher's events as today; when `edits_open`, also takes `fsw.get_events(&watch.edits_watcher, context.temp_allocator)`, adds `data_event_categories(watch.edits_watcher.path, edits_events)` to `changed`, then when `data_edits_watch_root_gone(watch.edits_watcher.path, edits_events)` calls `turn_reachable_data_edits_off("the directory is gone")`, `fsw.destroy(watch.edits_watcher)`, `edits_open = false`, `edits_unavailable = true`. The content settle logic then runs on the union, so `watch_data` all reloads after a quiet second for either directory. The categories of the edits directory are the data directory's by relative path (`data_edits/touch_overlay.sjson` under the watched root is `touch_overlay.sjson`, Content).
- Changed: `destroy_data_watch` also destroys `edits_watcher` when `edits_open`, and keeps `edits_unavailable` as it keeps `unavailable`.
- Changed: `update_data_watch` (`hot_reload.odin`), after the data watcher is open and before `poll_data_watch`: `if !watch.edits_open && !watch.edits_unavailable { if directory := reachable_data_edits_directory(); directory != "" { open_data_edits_watch(watch, directory) } }`. Once open or unavailable no stat runs per frame; with the reading off `reachable_data_edits_directory` returns "" before any stat.
- The header comment of `data_watch.odin` gains one sentence on the second watcher; the comment over `apply_data_edit_change` names the state overlay as the unwatched one.
- A vanished directory does not reload anything: what was loaded from it stays until the next reload, which reads the state copy or the data file.

### The Data files screen (`src/data_browser.odin`, `src/ui_data_browser.odin`, `src/data_export.odin`)

- `Data_Browser` gains `editing_edits_directory: bool` and `edits_field: Text_Field` after `export_field`, comment: "The edits directory under the keyboard (0228); Done sets the setting (set_edits_directory)."
- New in `data_export.odin` beside `set_export_directory`: `set_edits_directory :: proc(settings: ^Settings, typed, home: string) -> (problem: string, changed: bool)`: `expand_home_path(strings.trim_space(typed), home)`; non empty and not `os.is_absolute_path` returns `text("data_files_edits_directory_not_absolute"), false` with the setting kept; equal to the setting returns `"", false`; else stores `strings.clone(...)` (never freed, as `set_export_directory` says why) and returns `"", true`.
- New, pure, in `data_export.odin`: `edits_directory_done_toast :: proc(problem: string, changed, directory_set, access_granted: bool) -> string`: the problem when there is one; "" when not changed; `text("data_files_edits_access")` when `directory_set && !access_granted`; else `text("data_files_edits_directory_next_start")`.
- New in `ui_data_browser.odin`: `data_edits_directory_entry :: proc(state: ^Ui_State, browser: ^Data_Browser, settings: ^Settings)`: as `data_export_directory_entry` with panel label `"data_edits_directory_entry"` and label `text("data_files_edits_directory")`; on Done calls `set_edits_directory`, asks `platform.all_files_access_granted()` only when changed and the new value is non empty, opens `platform.open_all_files_access_settings()` when that answer is no, toasts `edits_directory_done_toast(...)` when it is not "", clears `editing_edits_directory` and returns the focus as the export entry does. Called from `data_browser_screen` right after the export entry's `if` block, under `state.keyboard.field != 0 && browser.editing_edits_directory && settings != nil`.
- New in `ui_data_browser.odin`: `data_edits_directory_row :: proc(state: ^Ui_State, row: Ui_Rectangle, browser: ^Data_Browser, settings: ^Settings)`: the whole row is `data_export_directory_field(state, row, text("data_files_edits_directory"), settings.edits_directory)` (fitted right, "not set" dimmed while empty); activated, sets `browser.edits_field = make_text_field(settings.edits_directory, TEXT_FIELD_CAPACITY)`, `editing_edits_directory = true`, `open_keyboard(state, ui_id(state, label))`.
- `data_browser_screen`: when `!browser.open && settings != nil`, after cutting `export_row`, cut `edits_row := cut_bottom(&content, UI_ROW_HEIGHT)` and a `UI_GAP`, so Read edits from sits right above Export to; drawn after `data_export_row` with `data_edits_directory_row`. Focus order follows the layout (tree, Read edits from, Export to, Export on save, buttons).
- What the screen shows of the edits directory: nothing new in the tree (the edited tags and Discard edit stay the state overlay's). An opened file reads through `read_data_file`, so a file with only an edits directory copy shows that copy with the heading's "edited" tag (`shows_overlay`); Save writes the state copy, which then wins.

### Strings (`data/strings/en.sjson`, after `data_files_export_sync_failed`)

- `data_files_edits_directory = "Read edits from"`
- `data_files_edits_directory_not_absolute = "The edits directory must be an absolute path"`
- `data_files_edits_directory_next_start = "The edits directory is read from the next start"`
- `data_files_edits_access = "Allow All files access, then restart to read the edits"`
- The empty field reuses `data_files_export_directory_none` ("not set").

### Tests

- `test_data_edits_directories_put_the_state_copy_first` (`data_load_test.odin`), pure: `data_edits_directories("/s", "/r", false, false) == {"/s", "/r"}`; `("/s", "/r", false, true) == {"/s", ""}`; `("/s", "/r", true, false) == {"", ""}`; `("", "/r", false, false) == {"", "/r"}`.
- `test_read_data_file_takes_the_state_copy_then_the_reachable_copy` (`data_browser_test.odin`, beside the 0129 overlay test): one `os.make_directory_temp` base removed at the end, with `data/`, `state_edits/`, `reachable/data_edits/`; `a.sjson` in data only reads "data a"; `b.sjson` in data and reachable reads "reachable b" with the reachable path returned; `c.sjson` in all three reads "state c" with the state path; `"", ""` sources read the data file. Through `read_data_file_from_sources` with `{state_edits, reachable/data_edits}`.
- `test_read_data_file_reads_the_reachable_directory_set_at_start` (`data_browser_test.odin`): temporary directory with `data_edits/strings/en.sjson` holding a changed `data_files_title`; `use_reachable_data_edits(<temp>/data_edits)`, `defer reset_data_edits_reading()`; `read_data_file(test_data_directory(), "strings/en.sjson")` returns the temporary copy's text and path (the state overlay is "" under `odin test`, so the shipped data loses only to the temporary copy).
- `test_a_vanished_reachable_directory_turns_its_reading_off` (`data_browser_test.odin`): as above, then `os.remove_all` the temporary directory; `read_data_file(test_data_directory(), "blocks.sjson")` returns no error and the data directory's path; `data_edits_reading.reachable_off` is true, `data_edits_reading.off` stays false; a second read leaves the state as it is.
- `test_a_broken_reachable_copy_turns_the_overlay_off_at_start` (`data_browser_test.odin`, after the 0130 one): a temporary directory whose `data_edits/blocks.sjson` is `blocks = [`; `use_reachable_data_edits`; `load_start_data(test_data_directory(), ...)` fails naming that path; `turn_data_edits_off(problem)` is true although `data_edits_reading.directory` is ""; the second `load_start_data` succeeds.
- `test_reachable_data_edits_refusal_cases` (`data_load_test.odin`), pure: `("", true, true)` Not_Set; `("Download", true, true)` Not_Absolute; `("~/Download", true, true)` Not_Absolute; `("/storage/emulated/0/Download", false, true)` No_Access; `("/storage/emulated/0/Download", true, false)` Not_A_Directory; `("/storage/emulated/0/Download", true, true)` None.
- `test_the_typed_edits_directory_sets_the_setting` (`data_export_test.odin`, after the export one): `" /storage/emulated/0/Download "` sets it, changed; the same again is not changed; `"~/Download"` with home `/home/player` sets `/home/player/Download`; `"Download"` returns `text("data_files_edits_directory_not_absolute")` and keeps `/home/player/Download`; `"~/Download"` with home "" is refused; `""` clears it, changed. Deletes each cloned value as the export test does.
- `test_edits_directory_done_toast_cases` (`data_export_test.odin`), pure: a problem wins; not changed gives ""; set without access gives the access text; set with access and cleared give the next start text.
- `test_data_files_edits_directory_field_sets_the_setting` (`ui_data_browser_test.odin`, after the export one): "not set" drawn; Confirm on `data_files_button_id("data_files_edits_directory")` opens the keyboard with `editing_edits_directory`; `text_field_set(&browser.edits_field, "/edits")`, Done (`back = true`) sets `audit.settings.edits_directory == "/edits"`, focus returns to the field, `state_has_toast(state, "data_files_edits_directory_next_start")`; again with `"edits"` toasts `data_files_edits_directory_not_absolute` and keeps `/edits`. The desktop's access check answers yes, so the access toast is covered by the pure test only.
- `test_the_edits_watch_sees_its_directory_go` (`data_watch_test.odin`), pure: `data_edits_watch_root_gone` true for `{.Removed, root}`, `{.Renamed, root}`, `{.Invalidated, root}`; false for `{.Removed, root/blocks.sjson}`, `{.Modified, root}`, an empty list.
- `test_watcher_notices_changed_reachable_edits` (`data_watch_test.odin`): two temporary directories (data, edits); `use_reachable_data_edits(edits)`, `defer reset_data_edits_reading()`; `open_data_watch` and `open_data_edits_watch`; writing `edits/strings/en.sjson` gives `{.Strings}` through `wait_for_data_events`; writing `edits/items.sjson` gives `{.Content}` with `content_changed`; `os.remove_all(edits)` then polling until `!watch.edits_open` (same 2 s loop) leaves `edits_unavailable` and `data_edits_reading.reachable_off` true.
- `test_settings_file_round_trip` (`configuration_test.odin`): `settings.edits_directory = "/storage/emulated/0/Download"` and the written file contains `\tedits_directory = "/storage/emulated/0/Download"\n`.
- UI audit (`ui_audit_test.odin`): new `UI_AUDIT_LONG_EDITS_DIRECTORY :: "/storage/emulated/0/Download/mine-oh-belowed-edits/from-the-couch-and-the-phone"`; beside the 0131 cases, with it set: `"data files, an edits directory"` (walk_focus), `"data files, an edits directory, touch row"` (hud, touch), and with `editing_edits_directory` and `edits_field` set: `"data files, the edits directory under the keyboard"` (keyboard, walk_focus); settings restored after.
- Every test uses `os.make_directory_temp` directories it removes, and `reset_data_edits_reading` in a `defer`; `data_edits_directory()` stays "" under `odin test`; nothing calls `start_reachable_data_edits` (it reads the machine's home), so no test reads the machine's state or Downloads.

### Docs

- `doc/developer_tools.md`, Data files screen: a new subsection `### Edits directory` after `### Export`: the Read edits from field (the `edits_directory` setting, "not set" while empty) above Export to; Done trims, expands `~/`, refuses a relative path with "The edits directory must be an absolute path", toasts "The edits directory is read from the next start"; on Android without All files access, Done opens the access settings page with "Allow All files access, then restart to read the edits", and a start with the setting set shows the same toast and logs one line; `<directory>/data_edits/<relative path>` is read after the state overlay and before the data file; setting it to the export directory reads what Export and Export on save write there (a Discard with Export on save deletes that copy too); what the tree and an open file show; the watcher. In `### Editing`, the off notice bullet gains: a broken edits directory copy also turns both overlays off, the problem names its path, delete it there.
- `doc/architecture.md`, Data edits overlay: the Rule line names both sources and the order (state copy, edits directory copy, data file); a new bullet on `start_reachable_data_edits` (resolved once at start, refusals logged, `reachable_off` when the directory vanishes, one line); the third bullet becomes "The state overlay is not watched ... The edits directory's overlay is watched with the data directory (`open_data_edits_watch`)"; the `data_edits_reading` bullet names `reachable_directory`. Configuration and directories: the export settings bullet adds `settings.edits_directory` (default empty).
- `doc/android.md`, Files on the phone: a bullet under the paths table: the edits directory lies on shared storage (for example `/storage/emulated/0/Download`, read as `.../Download/data_edits/`), outside the files folder, set on the Data files screen or in `config.d/90-settings.sjson` over USB. Export and storage access: one bullet that the edits directory needs the same All files access and asks at start and at Done.
- `doc/log/2026-10-04.md`: a section `## The edits directory reads after the state overlay (0228)` with Answered 1 and 2 below.
- Code comments as listed in the sections above.

### Hand-back check

- Memory a frame draws from: the setting's string is cloned and never freed (as `export_directory`); `reachable_directory` changes only at start and in tests; nothing frees during the UI pass. Satisfied.
- Files written through `<path>.tmp`: this item writes no file besides the settings file, which already goes through `write_file_replacing`. A path built from a setting stays under its directory: the read path is `<edits_directory>/data_edits/<relative path>` with relative paths from the loaders' constants, never from a listing of that directory.
- A start load the game can make fail falls back: an unset, relative, refused or missing directory logs one line and starts without it; a broken copy goes through `turn_data_edits_off` (`test_a_broken_reachable_copy_turns_the_overlay_off_at_start`).
- A changed save layout: the settings file gains a key; an old file loads (default ""); a file written by this build read by an older build is set aside by 0149's rule (unknown key), as with every new setting. Named in the log section.
- A long string fitted, at the smallest audit size: the three audit cases.
- A UI audit case made obsolete: none; the 0131 cases stay.
- Tests never touch the machine's state: the Tests section's last bullet.

### Open questions answered

1. Precedence: the state directory's copy first, then the edits directory's, then the data file. The Data files screen writes and tags only state copies; with the edits directory first, a Save on the screen would be shadowed by a dropped copy with nothing on the screen saying so, while with the state copy first a shadowing copy shows as edited and Discard edit removes it. With Export on save into the same directory both copies are equal anyway.
2. When a changed setting applies: at the next start. Taking it during the run would mean reloading every presentation and content file and swapping the watcher; the phone check of the item restarts anyway.
3. A directory that does not exist at start (or has no `data_edits/`): not read for the run, one log line; creating it later needs a restart, since `fsw` opens silently on a missing directory and the game does not scan for it.
4. A broken copy in the edits directory turns both overlays off (the shared `off` flag), as the screen's notice already explains a failed load; telling the sources apart would need the failing path matched against both directories for little gain.
5. No overlap refusal for the edits directory: the game only reads it. Pointing it at the export directory is the intended use.
6. No validation in `validate_settings`: see The setting.

### Questions to the main agent

1. The item's Change and Verify disagree on precedence; this specification follows the Verify (state copy wins). If the Change's order is meant, only `data_edits_directories` swaps its two entries and `test_read_data_file_takes_the_state_copy_then_the_reachable_copy` and `test_data_edits_directories_put_the_state_copy_first` flip their expectations; the doc lines follow.
2. With Export on save and the export directory equal to the edits directory, a Save writes the state copy and the export's copy; the second watcher then reports the same file again: a presentation file reloads twice, a content file announces "content changed" after its reload, and with `watch_data` all reloads the content a second time after a quiet second. Accepted here as harmless in developer mode; say if the watcher should ignore events for files the screen just synced.
3. Opening the All files access page at every start while the setting is set and access is missing is what "the setting's page opens with one toast" reads as; confirm, or keep it to Done only and log at start.

### Decisions at the approval (main agent, 2026-10-04)

1. Question 1: the state directory's copy first, then the edits directory's copy, then the data file, as the specification has it; the item's Change bullet is corrected to match. The screen writes and tags only state copies, so a dropped copy that shadowed a Save with nothing on the screen saying so would be worse than the reverse.
2. Question 2: the double reload with Export on save into the same directory is accepted as harmless in developer mode; the watcher skips nothing.
3. Question 3: the access settings page opens at Done only. A start that finds the setting set without access logs its one line (`start_reachable_data_edits`) and shows the toast; the `run_game` bullet, the `Player_Configuration` comment and the docs are corrected above.

### Not determined

- Whether inotify on Android's `/storage/emulated/0` (a FUSE mount) delivers events for files a file manager writes there; the watcher may stay silent on the phone, which the restart path of the Verify does not need. Only a phone run shows it.
