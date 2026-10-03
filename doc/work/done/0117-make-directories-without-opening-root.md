# 0117: Make directories on Android without opening /

Status: implemented

## Goal

On the phone (version code 211) the game cannot save, write its settings, take a screenshot, write texture edits, open the command socket or open its log file. Logcat, 2026-09-30: `error: saving "New world" failed: cannot write /storage/emulated/0/Android/data/io.github.tubbles.mineohbelowed/files/share/mine-oh-belowed/saves/New world.saving: Permission_Denied` and `error: command socket: cannot make /storage/emulated/0/Android/data/io.github.tubbles.mineohbelowed/files/state/mine-oh-belowed: Permission_Denied`, each right after an SELinux line `avc: denied { read } for name="/" ... tclass=dir`. `os.make_directory_all` opens `/` with `O_DIRECTORY` and walks an absolute path from there (`core/os/path_linux.odin:66`), and Android's policy refuses an untrusted app that read. The 0114 follow up fixed the data copy only (`make_directories_below` in `data_load.odin`) and decided against a general replacement (`doc/log/2026-09-30.md`, "the desktop builds keep it"). Every other directory the game makes is absolute and fails the same way, so that decision is reversed: one helper, used everywhere.

## Change

- `make_directory_path :: proc(path: string, perm := os.Permissions_Default_Directory) -> os.Error` in `src/platform_paths.odin`, replacing `make_directories_below` and every `os.make_directory_all` call in the game (tests keep theirs, they run on the desktop). It trims a trailing slash, calls `os.make_directory(path, perm)`, and treats `.Exist` as success. On `.Not_Exist` (the parent is missing) it makes the parent the same way (the directory part of `os.split_path`; stop with the error when that is empty or equal to the path) and retries the call. Any other error returns. So it never touches a directory above the first missing one: nothing outside the app's folder is opened on Android, and elsewhere it is `mkdir -p`. On Windows `ERROR_PATH_NOT_FOUND` also maps to `.Not_Exist` and `ERROR_ALREADY_EXISTS` to `.Exist` (`core/os/errors_windows.odin:34`), so the same code serves there.
- Call sites: `save_world.odin` (`write_save_files`), `command_socket_posix.odin` (`open_command_server`, keeping its `{.Read_User, .Write_User, .Execute_User}`), `configuration_output.odin` (`write_settings_file`), `command.odin` (the screenshot directory), `logging.odin` (`open_log_for_append`), `texture_generate.odin` (`write_texture_edits_file`), `data_load.odin` (`copy_android_asset`, joining the internal directory and the asset's relative directory).
- Tests: `test_make_directories_below_makes_each_level_and_tolerates_existing` (`data_load_test.odin`) becomes a test of the helper in `platform_paths_test.odin`: a three level missing path, an existing path, a path whose parent exists, a path with a trailing slash. A guard test next to `test_static_runtime_imports_stay_out_of_windows` (same file scan): no non-test file in `src/` contains `os.make_directory_all`, so a new call site fails the suite instead of the phone.
- `doc/build.md`: the Android app section's sentence on `make_directories_below` names the helper and says every directory the game makes goes through it. `doc/log/2026-09-30.md`: a section that reverses the earlier decision, with the logcat evidence.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`.
- The user, on the phone: a new world saves and shows on the title screen after a relaunch; `Android/data/io.github.tubbles.mineohbelowed/files/state/mine-oh-belowed/log.txt` appears.

## Implemented

- `make_directory_path` and a small `trim_trailing_separators` (keeps a lone `/`) in `src/platform_paths.odin`. Every `os.make_directory_all` in the game's sources replaced (`save_world.odin`, `command_socket_posix.odin` with its 0700 mode, `configuration_output.odin`, `command.odin`, `logging.odin`, `texture_generate.odin`); `make_directories_below` removed from `data_load.odin`, `copy_android_asset` makes the directory part of the joined target path.
- Tests in `src/platform_paths_test.odin`: the helper (three missing levels, existing, parent exists, trailing slash), the trim, and the guard over non test sources. The old test and its now unused `core:os` import left `data_load_test.odin`.
- Deviations: the guard also refuses `os.mkdir_all`, core:os's alias of the same procedure. The `doc/build.md` sentence sits in the Android app section's link flags bullet; it was rewritten there.
- Behaviour change: a regular file where a directory belongs now surfaces at the following write, with the write's message, where `make_directory_all` reported it at the directory (the helper takes `.Exist` from a file as success).
- Review: the parameter `perm` is now `permissions`.
- Verify: `./build.sh check`, `./build.sh check-android` clean, `./build.sh test` 1093 tests passed.
