package raylib

// GLFW calls the binding does not expose, from the same archive. Ours, not
// a copy from the Odin toolchain (see README.md). The nix flake rewrites
// the library path to "system:glfw".
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

import "core:c"

foreign import lib "linux/libraylib.a"

GLFW_PLATFORM_WAYLAND :: 0x00060003
GLFW_PLATFORM_X11 :: 0x00060004

@(default_calling_convention = "c")
foreign lib {
	glfwGetPlatform :: proc() -> c.int ---
	glfwGetCurrentContext :: proc() -> rawptr ---
	glfwGetWindowSize :: proc(window: rawptr, width, height: ^c.int) ---
}
