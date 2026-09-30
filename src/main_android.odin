#+build linux:android
package game

import "base:runtime"

// The Android entry point (work item 0114, facts in doc/build.md, Android
// toolchain). The library is built with -build-mode:shared -no-entry-point
// and -Wl,--wrap=main, so raylib's android_main, which calls the C main,
// lands here. The runtime does not start itself in a shared library, so
// this sets the arguments and the context, starts the runtime, runs the
// game's main and cleans up.
@(export, link_name = "__wrap_main")
android_wrapped_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
	runtime.args__ = argv[:argc]
	context = runtime.default_context()
	runtime._startup_runtime()
	main()
	runtime._cleanup_runtime()
	return 0
}
