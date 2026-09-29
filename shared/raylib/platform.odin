package raylib

// GLFW calls the binding does not expose, from the same archive. Ours, not
// a copy from the Odin toolchain (see README.md). The nix flake rewrites
// the Linux library path to "system:glfw".
//
// glfwGetPlatform: GLFW 3.4 built with both backends picks Wayland when
// the session offers it and X11 otherwise; this says which one it took.
// Call it after InitWindow.
//
// glfwGetWindowSize: the window's size in the coordinates GLFW reports the
// cursor in (logical units on Wayland, pixels on X11). It takes GLFW's
// window, which glfwGetCurrentContext returns for raylib's window (its
// context is current on the main thread); raylib's GetWindowHandle returns
// the native X11 or Wayland handle instead, not GLFW's.
//
// glfwGetProcAddress: a GL function of the current context by name, as
// raylib loads GL itself, so the game reads glGetString without linking
// libGL or opengl32 (work item 0104, the gl line in the log). Call it after
// InitWindow.

// require: on Android nothing in this file uses core:c or the foreign
// import below, and -vet refuses an unused import.
@(require) import "core:c"

// GLFW is inside raylib's static library on both desktop systems. On
// Windows (work item 0102) the MSVC build from raylib's release, see
// README.md. The Android archive (work item 0113) has no GLFW, so the
// procedures below are declared only off Android: a call from the game
// fails at compile time there, not at link time.
when ODIN_OS == .Windows {
	foreign import lib "windows/raylib.lib"
} else when ODIN_OS == .Linux && ODIN_PLATFORM_SUBTARGET == .Android {
	@(require) foreign import lib "android/libraylib.a"
} else {
	foreign import lib "linux/libraylib.a"
}

GLFW_PLATFORM_WAYLAND :: 0x00060003
GLFW_PLATFORM_X11 :: 0x00060004

when ODIN_PLATFORM_SUBTARGET != .Android {
	@(default_calling_convention = "c")
	foreign lib {
		glfwGetPlatform :: proc() -> c.int ---
		glfwGetCurrentContext :: proc() -> rawptr ---
		glfwGetWindowSize :: proc(window: rawptr, width, height: ^c.int) ---
		glfwGetProcAddress :: proc(name: cstring) -> rawptr ---
	}
}
