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
	// The camera (work item 0073), in degrees and blocks: the vertical
	// field of view, the degrees added to it while sprinting (eased in and
	// out, sprint_field_of_view), and the third person camera's distance
	// behind the eye and its offset to the right of it.
	field_of_view:             f32,
	sprint_field_of_view_kick: f32,
	third_person_distance:     f32,
	third_person_shoulder:     f32,
	// Rain, fog, wind and cloud shadows (work item 0063); off keeps the
	// weather clear, still and without shadows, for reduced motion.
	weather:                   bool,
	// The first person camera rises and falls with each step (work item
	// 0066); off for reduced motion.
	head_bob:                  bool,
	// Two players in split screen (viewport.odin, work item 0178): one
	// above the other, or side by side. Three and four take quarters.
	split_screen:              Split_Screen_Layout,
	// Sound (audio.odin, work item 0068), 0 to 1 each: the master volume
	// scales everything, the effects volume the short sounds, the
	// ambience volume the loops (biome ambience, rain, the machine hum).
	master_volume:             f32,
	effects_volume:            f32,
	ambience_volume:           f32,
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
	// Accessibility (work item 0074). text_scale multiplies every text
	// size the UI draws, on top of ui_scale (ui_core.odin). palette picks
	// the colour set of the bottleneck markers and the map from the theme
	// (ui_theme.odin). reduced_motion stills the head bob, the sprint
	// kick, the weather, the torch flames and the light's flicker, the
	// portholes' flicker during the arrival (0273), the focus outline's
	// pulse and Mission Control's typing. sneak_hold and sprint_hold
	// choose whether Sneak and Sprint act while held or toggle on a
	// press; the input layer hands the choice to the simulation in the
	// input frame (apply_hold_settings).
	text_scale:                f32,
	palette:                   Marker_Palette,
	reduced_motion:            bool,
	sneak_hold:                Hold_Mode,
	sprint_hold:               Hold_Mode,
	// The touch overlay (touch_overlay.odin, work item 0115): auto is on
	// for the Android build and off elsewhere; --touch-overlay forces it
	// on for a run.
	touch_overlay:             Touch_Overlay_Mode,
	// How the overlay aims Mine, Place and Interact while it drives the
	// world (work item 0118): tap at the touched point, or crosshair at
	// the view's centre.
	touch_interaction:         Touch_Interaction,
	// Where a text field types (work item 0133): system uses the phone's
	// or Steam's keyboard where one is available, game always the game's
	// own keys (ui_keyboard.odin).
	on_screen_keyboard:        On_Screen_Keyboard,
	// The Data files screen's export (work item 0131, data_export.odin):
	// the directory Export copies the data files and the data edits into,
	// "" for no export, and whether every save and discard of a data edit
	// also writes or deletes its copy there.
	export_directory:          string,
	export_on_save:            bool,
	// The Data files screen's edits directory (work item 0228,
	// data_load.odin): <edits_directory>/data_edits/<relative path> is
	// read after the state directory's overlay copy and before the data
	// file; "" for none. Read at start only.
	edits_directory:           string,
	// Set by the Steam Deck preset (deck_preset.odin, work item 0076)
	// when it applied, so it applies once and later starts leave the
	// player's choices alone.
	deck_preset_applied:       bool,
}

On_Screen_Keyboard :: enum u8 {
	System,
	Game,
}

// Stacked keeps a 16:9 screen's full width for each of two players, so
// the field of view stays as wide as at full screen.
Split_Screen_Layout :: enum u8 {
	Stacked,
	Side_By_Side,
}

// Hold acts while the button is held, Toggle switches on a press.
Hold_Mode :: enum u8 {
	Toggle,
	Hold,
}

DEFAULT_SETTINGS :: Settings {
	// Borderless for the couch; gamescope presents the window full screen
	// in any mode.
	window_mode               = .Borderless,
	resolution                = {0, 0},
	vsync                     = true,
	frame_rate_cap            = 0,
	ui_scale                  = 1,
	field_of_view             = 70,
	sprint_field_of_view_kick = 6,
	third_person_distance     = THIRD_PERSON_DISTANCE,
	// The camera to the right, so the player stands left of centre.
	third_person_shoulder     = 0.6,
	weather                   = true,
	head_bob                  = true,
	split_screen              = .Stacked,
	master_volume             = 0.8,
	effects_volume            = 1,
	ambience_volume           = 0.7,
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
	text_scale                = 1,
	palette                   = .Default,
	reduced_motion            = false,
	// As before the setting: Sneak held, Sprint toggled by the stick
	// click.
	sneak_hold                = .Hold,
	sprint_hold               = .Toggle,
	touch_overlay             = .Auto,
	touch_interaction         = .Tap,
	on_screen_keyboard        = .System,
	export_directory          = "",
	export_on_save            = false,
	edits_directory           = "",
	deck_preset_applied       = false,
}

UI_SCALE_RANGE :: Slider_Range{0.75, 1.5, 0.05}
TEXT_SCALE_RANGE :: Slider_Range{0.8, 1.6, 0.1}
LOOK_SENSITIVITY_RANGE :: Slider_Range{0.25, 3, 0.05}
POINTER_SPEED_RANGE :: Slider_Range{0.5, 3, 0.1}
VOLUME_RANGE :: Slider_Range{0, 1, 0.05}
FIELD_OF_VIEW_RANGE :: Slider_Range{60, 110, 1}
SPRINT_FIELD_OF_VIEW_KICK_RANGE :: Slider_Range{0, 15, 1}
THIRD_PERSON_DISTANCE_RANGE :: Slider_Range{2, 8, 0.5}
THIRD_PERSON_SHOULDER_RANGE :: Slider_Range{-1, 1, 0.1}
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

// The hold or toggle choices ride in the frame, so the simulation reads
// them from its input like any press (update_sneaking, update_sprinting).
apply_hold_settings :: proc(frame: Input_Frame, settings: Settings) -> Input_Frame {
	result := frame
	result.sneak_toggles = settings.sneak_hold == .Toggle
	result.sprint_holds = settings.sprint_hold == .Hold
	return result
}
