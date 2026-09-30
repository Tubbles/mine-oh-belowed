package game

import "core:fmt"
import "core:os"
import rl "shared:raylib"

// The window's mode, size, vsync and frame rate cap from the settings
// (work item 0080). display_changes decides what to do and is pure;
// apply_display_changes is the only place that changes the window through
// raylib. run_game opens the window windowed and applies the settings
// right after InitWindow, and the frame loop applies every later change
// from the settings screen (update_display).
//
// raylib 6.0 (platforms/rcore_desktop_glfw.c): borderless is toggled
// (ToggleBorderlessWindowed, which saves and restores the windowed size and
// position), fullscreen is the .FULLSCREEN_MODE window state (which
// switches to the monitor's current mode, saves and restores likewise).
// SetWindowSize on a fullscreen window changes the video mode, so the
// resolution applies to windowed and fullscreen; borderless covers the
// monitor at its current mode. SetWindowState and ClearWindowState with
// .VSYNC_HINT set the swap interval at run time.

Window_Mode :: enum u8 {
	Windowed,
	Borderless,
	Fullscreen,
}

NATIVE_RESOLUTION :: [2]int{0, 0}
MINIMUM_RESOLUTION :: 320
MAXIMUM_RESOLUTION :: 7680
MAXIMUM_FRAME_RATE_CAP :: 480
// InitWindow's size when the resolution is the monitor's: raylib cannot
// report the monitor before the window exists, and a zero size would make
// InitWindow go fullscreen.
INITIAL_WINDOW_SIZE :: [2]int{1280, 720}

// The Resolution row's choices besides Native, filtered to the monitor.
// raylib lists no video modes.
RESOLUTION_CHOICES :: [?][2]int {
	{1280, 720},
	{1280, 800},
	{1600, 900},
	{1920, 1080},
	{1920, 1200},
	{2560, 1440},
	{2560, 1600},
	{3840, 2160},
}

// The Frame rate cap row's choices, 0 is Off.
FRAME_RATE_CAP_CHOICES :: [?]int{0, 30, 40, 60, 90, 120, 144, 165, 240}

// What apply_display_changes does, in field order. The mode transitions,
// from the row to the column (Toggle is ToggleBorderlessWindowed, Set and
// Clear the .FULLSCREEN_MODE window state). Borderless and fullscreen pass
// through windowed, so each leaves before the other enters:
//
//                 to windowed   to borderless        to fullscreen
// windowed        nothing       Toggle               Set
// borderless      Toggle        nothing              Toggle, then Set
// fullscreen      Clear         Clear, then Toggle   nothing
//
// The size is set after the mode whenever the new mode is windowed or
// fullscreen and the mode or the resolution changed: leaving a mode
// restores the size from before it, and entering fullscreen takes the
// monitor's mode.
Display_Changes :: struct {
	leave_borderless:  bool,
	leave_fullscreen:  bool,
	enter_borderless:  bool,
	enter_fullscreen:  bool,
	resize:            bool,
	// NATIVE_RESOLUTION is the monitor's size.
	resolution:        [2]int,
	// A windowed window is centred on its monitor after the resize.
	centre:            bool,
	// The values ride only with their change flags, so settings that
	// differ in nothing the window uses give an empty struct, which is
	// update_display's guard.
	change_vsync:      bool,
	vsync:             bool,
	change_frame_rate: bool,
	frame_rate_cap:    int,
}

display_changes :: proc(previous, next: Settings) -> Display_Changes {
	changes := Display_Changes {
		leave_borderless  = previous.window_mode == .Borderless && next.window_mode != .Borderless,
		leave_fullscreen  = previous.window_mode == .Fullscreen && next.window_mode != .Fullscreen,
		enter_borderless  = previous.window_mode != .Borderless && next.window_mode == .Borderless,
		enter_fullscreen  = previous.window_mode != .Fullscreen && next.window_mode == .Fullscreen,
		change_vsync      = previous.vsync != next.vsync,
		change_frame_rate = previous.frame_rate_cap != next.frame_rate_cap,
	}
	if changes.change_vsync {
		changes.vsync = next.vsync
	}
	if changes.change_frame_rate {
		changes.frame_rate_cap = next.frame_rate_cap
	}
	sized := next.window_mode != .Borderless
	changed := previous.window_mode != next.window_mode || previous.resolution != next.resolution
	if sized && changed {
		changes.resize = true
		changes.resolution = next.resolution
		changes.centre = next.window_mode == .Windowed
	}
	return changes
}

// The window run_game opens: windowed, at the resolution or
// INITIAL_WINDOW_SIZE, with the vsync hint when vsync is on and raylib's
// default of no frame rate cap.
initial_window_settings :: proc(settings: Settings) -> Settings {
	result := settings
	result.window_mode = .Windowed
	result.resolution = settings.resolution == NATIVE_RESOLUTION ? INITIAL_WINDOW_SIZE : settings.resolution
	result.frame_rate_cap = 0
	return result
}

// The high DPI flag (work item 0085): on a scaled Wayland desktop the
// framebuffer follows the panel's pixels, not the scaled window size. On
// X11 at scale 1 it changes nothing.
window_config_flags :: proc(settings: Settings) -> rl.ConfigFlags {
	flags := rl.ConfigFlags{.WINDOW_RESIZABLE, .WINDOW_HIGHDPI}
	if settings.vsync {
		flags += {.VSYNC_HINT}
	}
	return flags
}

// NATIVE_RESOLUTION becomes the monitor's size.
resolved_resolution :: proc(resolution, monitor_size: [2]int) -> [2]int {
	return resolution == NATIVE_RESOLUTION ? monitor_size : resolution
}

// The Resolution row's choices: Native first, then the fixed list up to
// the monitor's size (all of it when the size is unknown).
resolution_choices :: proc(monitor_size: [2]int, allocator := context.allocator) -> [][2]int {
	choices := make([dynamic][2]int, 0, len(RESOLUTION_CHOICES) + 1, allocator)
	append(&choices, NATIVE_RESOLUTION)
	for choice in RESOLUTION_CHOICES {
		unknown := monitor_size == NATIVE_RESOLUTION
		if unknown || (choice.x <= monitor_size.x && choice.y <= monitor_size.y) {
			append(&choices, choice)
		}
	}
	return choices[:]
}

// The choice after the current one; a resolution not in the list steps to
// the first choice.
next_resolution :: proc(current: [2]int, choices: [][2]int) -> [2]int {
	for choice, index in choices {
		if choice == current {
			return choices[(index + 1) % len(choices)]
		}
	}
	return choices[0]
}

// The next larger choice, Off after the largest; a configured cap between
// choices steps to the next larger one too.
next_frame_rate_cap :: proc(current: int) -> int {
	for choice in FRAME_RATE_CAP_CHOICES {
		if choice > current {
			return choice
		}
	}
	return 0
}

next_window_mode :: proc(mode: Window_Mode) -> Window_Mode {
	return Window_Mode((int(mode) + 1) % len(Window_Mode))
}

// The size of the monitor the window is on, in its current mode. Read
// once while windowed: in fullscreen the current mode is the game's.
current_monitor_size :: proc() -> [2]int {
	monitor := rl.GetCurrentMonitor()
	return {int(rl.GetMonitorWidth(monitor)), int(rl.GetMonitorHeight(monitor))}
}

// On Android (work item 0114) the window is the screen: the mode and the
// resolution changes do nothing there, vsync and the frame rate cap apply.
apply_display_changes :: proc(changes: Display_Changes, monitor_size: [2]int) {
	when ODIN_PLATFORM_SUBTARGET != .Android {
		apply_window_mode_changes(changes, monitor_size)
	}
	apply_vsync_and_frame_rate_changes(changes)
}

apply_window_mode_changes :: proc(changes: Display_Changes, monitor_size: [2]int) {
	if changes.leave_borderless && rl.IsWindowState({.BORDERLESS_WINDOWED_MODE}) {
		rl.ToggleBorderlessWindowed()
	}
	if changes.leave_fullscreen {
		rl.ClearWindowState({.FULLSCREEN_MODE})
	}
	if changes.enter_borderless && !rl.IsWindowState({.BORDERLESS_WINDOWED_MODE}) {
		rl.ToggleBorderlessWindowed()
	}
	if changes.enter_fullscreen {
		rl.SetWindowState({.FULLSCREEN_MODE})
	}
	if changes.resize {
		size := resolved_resolution(changes.resolution, monitor_size)
		rl.SetWindowSize(i32(size.x), i32(size.y))
		if changes.centre {
			centre_window(size, monitor_size)
		}
	}
}

apply_vsync_and_frame_rate_changes :: proc(changes: Display_Changes) {
	if changes.change_vsync {
		if changes.vsync {
			rl.SetWindowState({.VSYNC_HINT})
		} else {
			rl.ClearWindowState({.VSYNC_HINT})
		}
	}
	if changes.change_frame_rate {
		rl.SetTargetFPS(i32(changes.frame_rate_cap))
	}
}

centre_window :: proc(size, monitor_size: [2]int) {
	origin := rl.GetMonitorPosition(rl.GetCurrentMonitor())
	position := centred_window_position({int(origin.x), int(origin.y)}, monitor_size, size)
	rl.SetWindowPosition(i32(position.x), i32(position.y))
}

// The top left corner that centres size on the monitor, clamped to the
// monitor's top left corner when the window is larger.
centred_window_position :: proc(monitor_origin, monitor_size, size: [2]int) -> [2]int {
	free_space := monitor_size - size
	return monitor_origin + {max(free_space.x, 0) / 2, max(free_space.y, 0) / 2}
}

// The frame loop's hook: applies what changed since the settings last
// applied (applied), remembers them and logs the display afterwards.
update_display :: proc(applied: ^Settings, next: Settings, monitor_size: [2]int, platform: Window_Platform) {
	changes := display_changes(applied^, next)
	if changes == {} {
		return
	}
	apply_display_changes(changes, monitor_size)
	applied^ = next
	log_display_diagnostics(platform)
}

// The windowing platform GLFW took (work item 0085). raylib's GLFW has
// both backends and tries Wayland first, X11 when Wayland does not
// connect or XDG_SESSION_TYPE says x11. XWayland is the X11 platform with
// WAYLAND_DISPLAY set; XWayland hands X11 applications the scaled screen
// when the desktop is scaled and upscales them (work item 0084). The
// launcher's MINE_OH_BELOWED_X11 unsets WAYLAND_DISPLAY, so that route
// reports x11 although XWayland serves it. Android (work item 0114) has
// no GLFW: raylib's own platform draws to the activity's surface.
Window_Platform :: enum u8 {
	X11,
	XWayland,
	Wayland,
	Android,
}

// The name the display log line and the Render page show.
window_platform_name :: proc(platform: Window_Platform) -> string {
	switch platform {
	case .X11:
		return "x11"
	case .XWayland:
		return "xwayland"
	case .Wayland:
		return "wayland"
	case .Android:
		return "android"
	}
	return "?"
}

wayland_display_set :: proc() -> bool {
	return os.get_env("WAYLAND_DISPLAY", context.temp_allocator) != ""
}

// glfw_platform is glfwGetPlatform's answer.
window_platform_from_glfw :: proc(glfw_platform: int, wayland_session: bool) -> Window_Platform {
	if glfw_platform == rl.GLFW_PLATFORM_WAYLAND {
		return .Wayland
	}
	return wayland_session ? .XWayland : .X11
}

// Read once after InitWindow: GLFW does not change its platform.
current_window_platform :: proc() -> Window_Platform {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		return .Android
	} else {
		return window_platform_from_glfw(int(rl.glfwGetPlatform()), wayland_display_set())
	}
}

// The desktop scales the window: under XWayland the Resolution row cannot
// reach the panel's size and says so. A native Wayland window with the
// high DPI flag has a framebuffer at the panel's size.
display_is_desktop_scaled :: proc(platform: Window_Platform) -> bool {
	return platform == .XWayland
}

display_diagnostics_text :: proc(monitor_size, window_size, render_size: [2]int, scale: [2]f32, platform: Window_Platform) -> string {
	return fmt.tprintf(
		"display: monitor %d x %d, window %d x %d, render %d x %d, scale %.2f x %.2f, session %s",
		monitor_size.x,
		monitor_size.y,
		window_size.x,
		window_size.y,
		render_size.x,
		render_size.y,
		scale.x,
		scale.y,
		window_platform_name(platform),
	)
}

window_scale :: proc() -> [2]f32 {
	scale := rl.GetWindowScaleDPI()
	return {scale.x, scale.y}
}

// The framebuffer's size in pixels, which the 3D pass fills and the UI
// lays out in (work item 0085). With the high DPI flag it differs from
// the window's size (GetScreenWidth) under a scaled Wayland desktop.
render_size :: proc() -> [2]int {
	return {int(rl.GetRenderWidth()), int(rl.GetRenderHeight())}
}

// A position in the window's coordinates, as GLFW reports the cursor, in
// render pixels: scaled per axis by the framebuffer's size over the
// window's size in the same coordinates. The identity on X11, where both
// are pixels; a zero size (a minimised window) leaves the position alone.
pointer_to_render_pixels :: proc(position: [2]f32, window_size, render_size: [2]int) -> [2]f32 {
	if window_size.x <= 0 || window_size.y <= 0 {
		return position
	}
	return position * [2]f32{f32(render_size.x) / f32(window_size.x), f32(render_size.y) / f32(window_size.y)}
}

// The window's size in the cursor's coordinates, from GLFW. raylib's
// GetScreenWidth is not that on Wayland in fullscreen, where raylib 6.0
// sets it to the framebuffer's size while GLFW keeps the cursor in the
// window's logical coordinates. On Android the screen's size, which is
// the render size there.
cursor_window_size :: proc() -> [2]int {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		return {int(rl.GetScreenWidth()), int(rl.GetScreenHeight())}
	} else {
		width, height: i32
		rl.glfwGetWindowSize(rl.glfwGetCurrentContext(), &width, &height)
		return {int(width), int(height)}
	}
}

log_display_diagnostics :: proc(platform: Window_Platform) {
	window_size := [2]int{int(rl.GetScreenWidth()), int(rl.GetScreenHeight())}
	log_printf("%s", display_diagnostics_text(current_monitor_size(), window_size, render_size(), window_scale(), platform))
}

// The GL implementation, logged once per start after the display line
// (work item 0104): on the phone a translation layer between Wine and the
// GPU (GL4ES, VirGL) rejected a fragment shader at link time without
// saying which layer it was or what GLSL level it offers.
GL_VENDOR :: 0x1F00
GL_RENDERER :: 0x1F01
GL_VERSION :: 0x1F02
GL_SHADING_LANGUAGE_VERSION :: 0x8B8C

Gl_Get_String :: #type proc "c" (name: u32) -> cstring

gl_info_field :: proc(value: string) -> string {
	return value if value != "" else "unknown"
}

gl_info_text :: proc(vendor, renderer, version, shading_language_version: string) -> string {
	return fmt.tprintf(
		"gl: vendor %s, renderer %s, version %s, glsl %s",
		gl_info_field(vendor),
		gl_info_field(renderer),
		gl_info_field(version),
		gl_info_field(shading_language_version),
	)
}

// A nil procedure or a nil string reads as empty, which logs as unknown.
gl_string :: proc(get_string: Gl_Get_String, name: u32) -> string {
	if get_string == nil {
		return ""
	}
	return string(get_string(name))
}

// Through GLFW's loader, so the game links neither libGL nor opengl32.
// On Android from libGLESv3, which raylib's archive links anyway.
log_gl_info :: proc() {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		get_string: Gl_Get_String = glGetString
	} else {
		get_string := cast(Gl_Get_String)rl.glfwGetProcAddress("glGetString")
	}
	log_printf(
		"%s",
		gl_info_text(
			gl_string(get_string, GL_VENDOR),
			gl_string(get_string, GL_RENDERER),
			gl_string(get_string, GL_VERSION),
			gl_string(get_string, GL_SHADING_LANGUAGE_VERSION),
		),
	)
}
