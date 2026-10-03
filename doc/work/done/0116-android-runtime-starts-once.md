# 0116: Start the Odin runtime once per Android process

Status: implemented

## Goal

The phone build (version code 211, commit 5ef6cdc) crashes on every other launch (user, 2026-09-30: "It crashes every other time i try to open it"). The logcat shows why: after Back or Home the activity is destroyed but the process lives on, since Android keeps it for the next launch. The next tap on the icon creates a new NativeActivity in the same process (pid 22696 has two `wm_on_create_called` lines, the crash follows the second at once), raylib's `android_main` runs on a new thread, and `__wrap_main` (`src/main_android.odin`) calls `runtime._startup_runtime()` a second time. That runs every `@(init)` procedure again: `core:image/png`'s `_register` calls `image.register`, whose `assert_contextless(_internal_loaders[kind] == nil)` (`core/image/general.odin:16`) fails because the first run registered the loader, and a contextless assertion traps. Tombstone: `SIGTRAP` in `runtime::default_assertion_contextless_failure_proc` from `png::_register` from `__$startup_runtime` from `__wrap_main` from `android_main` (two of them, pids 22696 and 23096). The process dies, the launch after that gets a fresh process and works, hence every other time.

## Change

- `src/main_android.odin`: a file-private `runtime_started: bool`. `__wrap_main` sets `runtime.args__` and the context every time, calls `runtime._startup_runtime()` only while the flag is clear and sets it, calls `main()`, and never calls `runtime._cleanup_runtime()`: the process outlives the activity and Android ends it without notice, and the only `@(fini)` among the program's dependencies is `core:terminal`'s restore of a terminal the app does not have. Update the file comment.
- A second `main()` in the same process runs without the runtime's global initialisers, so every mutable global must be reset at the end of `main` or assigned before it is read: `global_string_table` (`data_strings.odin`, assigned by `main`), `thread_string_table` (thread local, and the second run is a new thread), `global_console` (`logging_posix.odin`), `global_log` and `captured_log_error` (`logging.odin`). Check each and fix what is not, minimally. The other globals (`grep -n '^[a-z_]* *:=' src/*.odin`) are lookup tables nothing writes. The previous run's game state stays allocated, since `run_game` frees no arena at its end; accepted, one relaunch leaks one run, and Android drops the process under memory pressure anyway.
- `doc/build.md`: the entry point bullet of the Android toolchain section and the entry point bullet of the Android app section say the runtime starts once per process and is never cleaned up, with the reason.
- `doc/log/2026-09-30.md`: a section with the symptom, the cause and the decision.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`.
- The user, on the phone: open the game, leave with Back or Home, open it again; the world opens; repeat twice.

## Implemented

- `src/main_android.odin`: a file private `runtime_started` flag; `__wrap_main` starts the runtime on the first call only and no longer calls `runtime._cleanup_runtime()`. File comment updated.
- Globals checked: `global_string_table` (assigned by `main` before any read), `thread_string_table` (thread local, new thread), `captured_log_error` (set and restored around each data reload), `global_log` (`close_log_file`, deferred in `main`, clears the file). `global_console` needed a fix in `src/logging_posix.odin` (not named in the Change section as a file, but covered by its check): on the second run stderr still pointed at the first run's log, so `redirect_stderr_to_log` saved that as the original stderr and the game's console lines went into the log twice. When an earlier run already redirected, it now only moves stderr to the new log (`point_redirected_stderr_at_log`).
- Deviation: the Change section says the only `@(fini)` is `core:terminal`'s. There are also `core:os`'s (frees `os.args` and the thread's temp arenas) and the runtime's default temporary allocator's; all free memory only, so skipping them changes nothing. The docs name them.
- Environment: an intermediate change that passed the runtime a three entry argument array was reverted; its premise was wrong. `os.get_env` on Android is bionic's `getenv` (the build links bionic, `_get_original_env` exists only under `ODIN_NO_CRT`), so raylib's argv feeds `os.args` only. `runtime.args__ = argv[:argc]` stays; the comment, `doc/build.md` (whose 0114 claim about `_get_original_env` was wrong too) and the log say so.
- Review additions: `last_touch_position` (`src/input_raylib.odin`) is cleared by `start_input_backend` (`src/main.odin`) through a new `reset_raylib_pointer_position`, a no-op off Android; `input_raylib.odin` has no start procedure of its own. The `UI_*` colours are assigned by `apply_ui_theme` before any drawing and need nothing.
- Quit: `main` returning while the activity lives (Quit) would leave raylib's state stale for the next launch in the process (`ClosePlatform` resets only when `destroyRequested` is set), so `__wrap_main` calls `os.exit(0)` when `GetAndroidApp().destroy_requested` is 0. `Android_App` (`src/platform_android.odin`) declares the fields up to `destroyRequested`, checked against the NDK 27.3.13750724 `android_native_app_glue.h`.
- The `dup2` failure message now says stderr stays on the previous log.
- `doc/build.md` (both entry point bullets, the Android app section's Quit note) and `doc/log/2026-09-30.md` updated.
- Verify: `./build.sh check`, `./build.sh check-android` clean, `./build.sh test` 1091 tests passed (1093 after the review changes, with 0117 in the tree).
