#+build linux:android
package game

import "base:runtime"
import "core:os"

// The Android entry point (work item 0114, facts in doc/build.md, Android
// toolchain). The library is built with -build-mode:shared -no-entry-point
// and -Wl,--wrap=main, so raylib's android_main, which calls the C main,
// lands here. The runtime does not start itself in a shared library, so
// this sets the arguments and the context, starts the runtime and runs the
// game's main. raylib's argv ({"raylib", NULL} on android_main's stack)
// feeds os.args only: the build links bionic, so os.get_env is bionic's
// getenv and reads the environment Android gives the app, which has none
// of the XDG variables.
//
// The runtime starts once per process (work item 0116). After Back or
// Home the activity ends but Android keeps the process, and the next
// launch runs android_main again, on a new thread, in the same process. A
// second start runs every @(init) procedure again, and core:image/png's
// loader registration asserts on that. So a second main runs without the
// global initialisers: main assigns or resets every mutable global it
// reads (logging.odin, logging_posix.odin, data_strings.odin, the touch
// position in input_raylib.odin, reset by start_input_backend), and
// apply_ui_theme assigns the UI_* colours (ui_widgets.odin) before any
// drawing. The runtime is never cleaned up either: Android ends the
// process without notice, and the @(fini) procedures among the
// dependencies only free memory and restore a terminal the app does not
// have.
//
// Quit returns from main while the activity is alive. raylib resets its
// own state for the next launch only when the activity is being destroyed
// (ClosePlatform, destroyRequested), so a later launch in this process
// would start on stale raylib state. Quit therefore ends the process.
@(private = "file")
runtime_started: bool

@(export, link_name = "__wrap_main")
android_wrapped_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
	runtime.args__ = argv[:argc]
	context = runtime.default_context()
	if !runtime_started {
		runtime._startup_runtime()
		runtime_started = true
	}
	main()
	if GetAndroidApp().destroy_requested == 0 {
		os.exit(0)
	}
	return 0
}
