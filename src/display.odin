package game

import rl "vendor:raylib"

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
		vsync             = next.vsync,
		change_frame_rate = previous.frame_rate_cap != next.frame_rate_cap,
		frame_rate_cap    = next.frame_rate_cap,
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

window_config_flags :: proc(settings: Settings) -> rl.ConfigFlags {
	flags := rl.ConfigFlags{.WINDOW_RESIZABLE}
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

apply_display_changes :: proc(changes: Display_Changes, monitor_size: [2]int) {
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
// applied (applied), and remembers them.
update_display :: proc(applied: ^Settings, next: Settings, monitor_size: [2]int) {
	changes := display_changes(applied^, next)
	if changes == {} {
		return
	}
	apply_display_changes(changes, monitor_size)
	applied^ = next
}
