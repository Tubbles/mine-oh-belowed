#+build linux:android
package android_libc

// C functions Odin's core library links on Linux that Android's libc
// (bionic, API level 28) does not have (work item 0114). A shared library
// links with undefined symbols unless -Wl,--no-undefined says otherwise,
// and Android's loader then refuses the library, so the game would not
// start. Each is exported under the __wrap_ name and build.sh links with
// -Wl,--wrap=<name>, which sends every call there: an export under the
// plain name sits next to a foreign declaration of the same name (in
// core:c/libc, core:thread, core:debug/trace, logging_posix.odin), and the
// compiler emits only one of the two, not always the same one. Found with
// llvm-nm -D --undefined-only on libmain.so against the NDK's API 28
// libraries (doc/android.md, Link). A package of its own, since the platform
// package declares backtrace itself (logging_posix.odin).

foreign import bionic "system:c"

@(default_calling_convention = "c")
foreign bionic {
	__errno :: proc() -> rawptr ---
}

// glibc's name for bionic's __errno, which core:c/libc reads errno
// through.
@(export, link_name = "__wrap___errno_location")
errno_location :: proc "c" () -> rawptr {
	return __errno()
}

// bionic has no thread cancellation; core:thread only enables it on every
// new thread and asserts the call succeeded.
@(export, link_name = "__wrap_pthread_setcancelstate")
pthread_setcancelstate :: proc "c" (state: i32, old_state: ^i32) -> i32 {
	if old_state != nil {
		old_state^ = 0
	}
	return 0
}

@(export, link_name = "__wrap_pthread_setcanceltype")
pthread_setcanceltype :: proc "c" (type: i32, old_type: ^i32) -> i32 {
	if old_type != nil {
		old_type^ = 0
	}
	return 0
}

// No frames: crash traces (core:debug/trace, logging_posix.odin) come out
// empty on Android, also where libc has backtrace (API level 33 on).
@(export, link_name = "__wrap_backtrace")
backtrace :: proc "c" (buffer: [^]rawptr, size: i32) -> i32 {
	return 0
}

@(export, link_name = "__wrap_backtrace_symbols")
backtrace_symbols :: proc "c" (buffer: [^]rawptr, size: i32) -> [^]cstring {
	return nil
}

@(export, link_name = "__wrap_backtrace_symbols_fd")
backtrace_symbols_fd :: proc "c" (buffer: [^]rawptr, size: i32, file_descriptor: i32) {
}
