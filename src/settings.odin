package game

// Player settings, read from the configuration (configuration.odin) and
// written back to config.d/90-settings.sjson after the settings screen
// changed them. The settings screen edits them live; the input layer
// applies them to each frame before the simulation sees it, so the
// simulation keeps its fixed base rates and only ever reads input.

Settings :: struct {
	// The window (display.odin, work item 0080). resolution is the
	// windowed size and the fullscreen video mode, {0, 0} the monitor's
	// size; borderless always covers the monitor. frame_rate_cap 0 is no
	// cap.
	window_mode:               Window_Mode,
	resolution:                [2]int,
	vsync:                     bool,
	frame_rate_cap:            int,
	ui_scale:                  f32,
	// Gyro aiming in the world (SDL3 backend only).
	gyro_enabled:              bool,
	// Multipliers on the base look rates.
	stick_look_sensitivity:    f32,
	gyro_look_sensitivity:     f32,
	trackpad_look_sensitivity: f32,
	invert_pitch:              bool,
	// Screen heights the UI pointer crosses per right trackpad width.
	pointer_speed:             f32,
	// Minutes of simulated time between autosaves.
	autosave_minutes:          int,
	// Machine state markers in the world (work item 0028), also toggled
	// with Toggle_Bottleneck_Overlay.
	bottleneck_overlay:        bool,
	// The Developer entry in the pause menu (ui_developer.odin, work item
	// 0043), so a tester needs no launch options; --dev shows it too.
	developer_mode:            bool,
	// Reloading changed data files while the game runs (data_watch.odin,
	// work item 0054): default, off, presentation or all. --watch-data
	// overrides it for one run.
	watch_data:                Watch_Data_Mode,
	// Font family ids from data/fonts/fonts.sjson (ui_font.odin, work item
	// 0077): the UI's, and the diagnostics overlay's among the monospace
	// families. main refuses an id the file does not list.
	font:                      string,
	monospace_font:            string,
}

DEFAULT_SETTINGS :: Settings {
	// Borderless for the couch; gamescope presents the window full screen
	// in any mode.
	window_mode               = .Borderless,
	resolution                = {0, 0},
	vsync                     = true,
	frame_rate_cap            = 0,
	ui_scale                  = 1,
	gyro_enabled              = true,
	stick_look_sensitivity    = 1,
	gyro_look_sensitivity     = 1,
	trackpad_look_sensitivity = 1,
	invert_pitch              = false,
	pointer_speed             = 1.5,
	autosave_minutes          = 5,
	bottleneck_overlay        = false,
	developer_mode            = false,
	watch_data                = .Default,
	font                      = "exo_2",
	monospace_font            = "jetbrains_mono",
}

UI_SCALE_RANGE :: Slider_Range{0.75, 1.5, 0.05}
LOOK_SENSITIVITY_RANGE :: Slider_Range{0.25, 3, 0.05}
POINTER_SPEED_RANGE :: Slider_Range{0.5, 3, 0.1}
// 0 turns autosave off. The configuration accepts up to
// MAXIMUM_AUTOSAVE_MINUTES; the slider stops at an hour so a stick can
// walk it.
AUTOSAVE_MINUTES_RANGE :: Slider_Range{0, 60, 1}

// Stick sensitivity and pitch inversion. Gyro and trackpad sensitivity are
// applied by the SDL3 backend, where those deltas are still separate.
apply_look_settings :: proc(frame: Input_Frame, settings: Settings) -> Input_Frame {
	result := frame
	result.look *= settings.stick_look_sensitivity
	if settings.invert_pitch {
		result.look.y = -result.look.y
		result.look_delta.y = -result.look_delta.y
	}
	return result
}
