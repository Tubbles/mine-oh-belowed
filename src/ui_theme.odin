package game

import "core:encoding/json"
import "core:fmt"
import "core:math"

// The UI theme (work item 0071): colours and art metrics from
// data/ui/theme.sjson, loaded at start and on a presentation reload
// (hot_reload.odin). A key the file leaves out keeps its default, and
// the defaults are the colours the UI was drawn with before the file
// existed, so a file that sets nothing changes nothing. An unknown key,
// a wrong type or a value out of range refuses the whole file, naming
// it. A colour whose alpha is 0 turns its element off (the highlight
// line, the pressed state, dividers). The icon set the theme's art uses
// (Ui_Icon) lives under data/ui/icons/ (render_icons.odin). The theme
// also holds the marker palettes (work item 0074): the bottleneck
// overlay's and the map's colours, one set per palette setting.

UI_THEME_DIRECTORY :: "ui"
UI_THEME_FILE_NAME :: "theme.sjson"
UI_ICONS_DIRECTORY :: "ui/icons"
// One pulse of the focus outline, in seconds.
UI_FOCUS_PULSE_SECONDS :: 1.4
UI_THEME_MAXIMUM_BORDER :: 8
UI_THEME_MAXIMUM_CORNER :: 24
UI_THEME_MAXIMUM_FOCUS_PULSE :: 8

Ui_Theme_Color :: enum u8 {
	Panel,
	Panel_Edge,
	Panel_Highlight,
	Widget,
	Widget_Hover,
	// While Confirm is held on the focused widget or the pointer is held
	// on the hovered one.
	Widget_Active,
	Accent,
	Text,
	Text_Dim,
	Focus,
	Divider,
	Tooltip,
	Toast,
	Danger,
	// The map's entity dots, by the category of the machine's item, in
	// Item_Category order.
	Map_Marker_Raw,
	Map_Marker_Intermediate,
	Map_Marker_Tool,
	Map_Marker_Machine,
	Map_Marker_Block,
}

// The theme file's keys.
@(rodata)
ui_theme_color_names := [Ui_Theme_Color]string {
	.Panel                   = "panel",
	.Panel_Edge              = "panel_edge",
	.Panel_Highlight         = "panel_highlight",
	.Widget                  = "widget",
	.Widget_Hover            = "widget_hover",
	.Widget_Active           = "widget_active",
	.Accent                  = "accent",
	.Text                    = "text",
	.Text_Dim                = "text_dim",
	.Focus                   = "focus",
	.Divider                 = "divider",
	.Tooltip                 = "tooltip",
	.Toast                   = "toast",
	.Danger                  = "danger",
	.Map_Marker_Raw          = "map_marker_raw",
	.Map_Marker_Intermediate = "map_marker_intermediate",
	.Map_Marker_Tool         = "map_marker_tool",
	.Map_Marker_Machine      = "map_marker_machine",
	.Map_Marker_Block        = "map_marker_block",
}

// The colour sets of the markers that tell states and finds apart (work
// item 0074), picked by the palette setting. Colour_Blind is safe for
// deuteranopia and protanopia.
Marker_Palette :: enum u8 {
	Default,
	Colour_Blind,
}

// The colours a palette holds: the bottleneck overlay's four states
// (bottleneck_marker_colors) and the map's markers and legend. Under the
// default palette the map's machine dots keep their category colours
// (map_marker_color); under another every dot takes its Map_Machine.
Palette_Color :: enum u8 {
	Working,
	Waiting,
	Missing,
	Idle,
	Map_Player,
	Map_Machine,
	Map_Assayed,
	Map_Magnetometer,
	Map_Core_Sample,
	Map_Core_Sample_Vein,
	Map_Seismic,
	Map_Resolved,
}

// The bottleneck colours and the map colours are shown apart, so each
// set only needs to be distinct within itself.
BOTTLENECK_PALETTE_COLORS :: bit_set[Palette_Color]{.Working, .Waiting, .Missing, .Idle}
MAP_PALETTE_COLORS :: bit_set[Palette_Color]{.Map_Player, .Map_Machine, .Map_Assayed, .Map_Magnetometer, .Map_Core_Sample, .Map_Core_Sample_Vein, .Map_Seismic, .Map_Resolved}

// The theme file's keys: palettes = {default = {working = ...}}.
@(rodata)
marker_palette_names := [Marker_Palette]string {
	.Default      = "default",
	.Colour_Blind = "colour_blind",
}

@(rodata)
palette_color_names := [Palette_Color]string {
	.Working              = "working",
	.Waiting              = "waiting",
	.Missing              = "missing",
	.Idle                 = "idle",
	.Map_Player           = "map_player",
	.Map_Machine          = "map_machine",
	.Map_Assayed          = "map_assayed",
	.Map_Magnetometer     = "map_magnetometer",
	.Map_Core_Sample      = "map_core_sample",
	.Map_Core_Sample_Vein = "map_core_sample_vein",
	.Map_Seismic          = "map_seismic",
	.Map_Resolved         = "map_resolved",
}

Ui_Theme :: struct {
	colors:      [Ui_Theme_Color]Ui_Color,
	// Edge, highlight and divider lines, in UI units.
	border:      f32,
	// The panel corners are cut by this much (0: square).
	corner:      f32,
	// How much thicker the focus outline grows at the top of its pulse.
	focus_pulse: f32,
	palettes:    [Marker_Palette][Palette_Color]Ui_Color,
}

UI_THEME_METRIC_NAMES :: [?]string{"border", "corner", "focus_pulse"}

DEFAULT_UI_THEME :: Ui_Theme {
	colors = {
		.Panel = {24, 26, 34, 230},
		.Panel_Edge = {90, 96, 120, 255},
		.Panel_Highlight = {0, 0, 0, 0},
		.Widget = {44, 48, 62, 255},
		.Widget_Hover = {60, 66, 86, 255},
		.Widget_Active = {0, 0, 0, 0},
		.Accent = {236, 176, 64, 255},
		.Text = {235, 235, 240, 255},
		.Text_Dim = {160, 164, 180, 255},
		.Focus = {236, 176, 64, 255},
		.Divider = {0, 0, 0, 0},
		.Tooltip = {24, 26, 34, 230},
		.Toast = {24, 26, 34, 230},
		.Danger = {225, 80, 60, 255},
		.Map_Marker_Raw = {240, 240, 245, 255},
		.Map_Marker_Intermediate = {240, 240, 245, 255},
		.Map_Marker_Tool = {240, 240, 245, 255},
		.Map_Marker_Machine = {240, 240, 245, 255},
		.Map_Marker_Block = {240, 240, 245, 255},
	},
	border = 2,
	corner = 0,
	focus_pulse = 0,
	palettes = {
		// The colours the markers had before the palettes.
		.Default = {
			.Working = {60, 200, 80, 255},
			.Waiting = {240, 200, 40, 255},
			.Missing = {225, 55, 45, 255},
			.Idle = {140, 140, 145, 255},
			.Map_Player = MAP_PLAYER_COLOR,
			.Map_Machine = {240, 240, 245, 255},
			.Map_Assayed = MAP_ASSAYED_COLOR,
			.Map_Magnetometer = MAP_READING_COLOR,
			.Map_Core_Sample = MAP_CORE_SAMPLE_COLOR,
			.Map_Core_Sample_Vein = MAP_CORE_SAMPLE_VEIN_COLOR,
			.Map_Seismic = MAP_SEISMIC_COLOR,
			.Map_Resolved = MAP_RESOLVED_COLOR,
		},
		// Blue, orange, black and white, then the rest of the Okabe and
		// Ito set, apart for deuteranopia and protanopia and by lightness.
		.Colour_Blind = {
			.Working = {0, 114, 178, 255},
			.Waiting = {230, 159, 0, 255},
			.Missing = {255, 255, 255, 255},
			.Idle = {0, 0, 0, 255},
			.Map_Player = {255, 255, 255, 255},
			.Map_Machine = {0, 0, 0, 255},
			.Map_Assayed = {230, 159, 0, 255},
			.Map_Magnetometer = {213, 94, 0, 255},
			.Map_Core_Sample = {86, 180, 233, 255},
			.Map_Core_Sample_Vein = {240, 228, 66, 255},
			.Map_Seismic = {0, 114, 178, 255},
			.Map_Resolved = {204, 121, 167, 255},
		},
	},
}

// The icons of data/ui/icons/<name>.png, the tile index the enum value.
Ui_Icon :: enum u8 {
	Button_South,
	Button_East,
	Button_West,
	Button_North,
	Bumper_Left,
	Bumper_Right,
	Trigger_Left,
	Trigger_Right,
	Stick_Left,
	Stick_Right,
	Dpad,
	Menu,
	View,
	// A blank key cap the keyboard glyph's label is drawn on.
	Key,
	Category_Raw,
	Category_Intermediate,
	Category_Tool,
	Category_Machine,
	Category_Block,
	// The recipe categories without an item category of their own.
	Category_Logistics,
	Category_Power,
	Category_Science,
	Mission_Control,
	Journal,
	Map,
	Settings,
	Search,
	// The inventory's context tabs.
	Inventory,
	Recipes,
	Technologies,
	// The HUD's touch buttons (0134, hud.odin).
	Backpack,
	Pause,
	Rotate,
}

@(rodata)
ui_icon_names := [Ui_Icon]string {
	.Button_South          = "button_south",
	.Button_East           = "button_east",
	.Button_West           = "button_west",
	.Button_North          = "button_north",
	.Bumper_Left           = "bumper_left",
	.Bumper_Right          = "bumper_right",
	.Trigger_Left          = "trigger_left",
	.Trigger_Right         = "trigger_right",
	.Stick_Left            = "stick_left",
	.Stick_Right           = "stick_right",
	.Dpad                  = "dpad",
	.Menu                  = "menu",
	.View                  = "view",
	.Key                   = "key",
	.Category_Raw          = "category_raw",
	.Category_Intermediate = "category_intermediate",
	.Category_Tool         = "category_tool",
	.Category_Machine      = "category_machine",
	.Category_Block        = "category_block",
	.Category_Logistics    = "category_logistics",
	.Category_Power        = "category_power",
	.Category_Science      = "category_science",
	.Mission_Control       = "mission_control",
	.Journal               = "journal",
	.Map                   = "map",
	.Settings              = "settings",
	.Search                = "search",
	.Inventory             = "inventory",
	.Recipes               = "recipes",
	.Technologies          = "technologies",
	.Backpack              = "backpack",
	.Pause                 = "pause",
	.Rotate                = "rotate",
}

// The loaded theme, or the defaults before one is loaded (tests).
ui_theme :: proc(state: ^Ui_State) -> Ui_Theme {
	return state.theme.? or_else DEFAULT_UI_THEME
}

theme_color :: proc(state: ^Ui_State, color: Ui_Theme_Color) -> Ui_Color {
	return ui_theme(state).colors[color]
}

// The screens that still name the colour constants (UI_TEXT_COLOR and
// the rest in ui_widgets.odin) read the theme through them.
apply_ui_theme :: proc(state: ^Ui_State, theme: Ui_Theme) {
	state.theme = theme
	UI_PANEL_COLOR = theme.colors[.Panel]
	UI_PANEL_BORDER_COLOR = theme.colors[.Panel_Edge]
	UI_WIDGET_COLOR = theme.colors[.Widget]
	UI_HOVER_COLOR = theme.colors[.Widget_Hover]
	UI_ACCENT_COLOR = theme.colors[.Accent]
	UI_TEXT_COLOR = theme.colors[.Text]
	UI_DIM_TEXT_COLOR = theme.colors[.Text_Dim]
	UI_BORDER = theme.border
}

map_marker_color :: proc(theme: Ui_Theme, category: Item_Category) -> Ui_Color {
	switch category {
	case .Raw:
		return theme.colors[.Map_Marker_Raw]
	case .Intermediate:
		return theme.colors[.Map_Marker_Intermediate]
	case .Tool:
		return theme.colors[.Map_Marker_Tool]
	case .Machine:
		return theme.colors[.Map_Marker_Machine]
	case .Block:
		return theme.colors[.Map_Marker_Block]
	}
	return theme.colors[.Map_Marker_Machine]
}

// The dot colour of a machine item's category under the palette.
map_dot_color :: proc(theme: Ui_Theme, palette: Marker_Palette, category: Item_Category) -> Ui_Color {
	if palette == .Default {
		return map_marker_color(theme, category)
	}
	return theme.palettes[palette][.Map_Machine]
}

// 0 at the start of a pulse, 1 at its middle, eased by a cosine.
focus_pulse_phase :: proc(seconds: f32) -> f32 {
	return 0.5 - 0.5 * math.cos(math.TAU * seconds / UI_FOCUS_PULSE_SECONDS)
}

// Parsing and validation.

find_ui_theme_color :: proc(key: string) -> (color: Ui_Theme_Color, found: bool) {
	for name, candidate in ui_theme_color_names {
		if name == key {
			return candidate, true
		}
	}
	return {}, false
}

// Four whole numbers from 0 to 255: red, green, blue, alpha.
parse_theme_color :: proc(value: json.Value, source, key: string) -> (color: Ui_Color, problem: string) {
	expected := "an array of 4 whole numbers from 0 to 255"
	array, is_array := value.(json.Array)
	if !is_array || len(array) != 4 {
		return {}, fmt.tprintf("%s: %s must be %s, not %s", source, key, expected, json_type_name(value))
	}
	for channel, index in array {
		number, is_integer := channel.(json.Integer)
		if !is_integer || number < 0 || number > 255 {
			return {}, fmt.tprintf("%s: %s[%d] must be a whole number from 0 to 255", source, key, index)
		}
		color[index] = u8(number)
	}
	return color, ""
}

parse_theme_metric :: proc(value: json.Value, source, key: string, maximum: f32) -> (metric: f32, problem: string) {
	number, ok := json_number(value)
	if !ok {
		return 0, fmt.tprintf("%s: %s must be a number, not %s", source, key, json_type_name(value))
	}
	if number < 0 || f32(number) > maximum {
		return 0, fmt.tprintf("%s: %s is %v, outside 0 to %v", source, key, number, maximum)
	}
	return f32(number), ""
}

// One key of the file into the theme.
assign_theme_key :: proc(theme: ^Ui_Theme, key: string, value: json.Value, source: string) -> string {
	if color, found := find_ui_theme_color(key); found {
		problem: string
		theme.colors[color], problem = parse_theme_color(value, source, key)
		return problem
	}
	problem: string
	switch key {
	case "border":
		theme.border, problem = parse_theme_metric(value, source, key, UI_THEME_MAXIMUM_BORDER)
	case "corner":
		theme.corner, problem = parse_theme_metric(value, source, key, UI_THEME_MAXIMUM_CORNER)
	case "focus_pulse":
		theme.focus_pulse, problem = parse_theme_metric(value, source, key, UI_THEME_MAXIMUM_FOCUS_PULSE)
	case "palettes":
		problem = assign_theme_palettes(theme, value, source)
	case:
		problem = fmt.tprintf("%s: unknown key %s", source, key)
	}
	return problem
}

find_marker_palette :: proc(key: string) -> (palette: Marker_Palette, found: bool) {
	for name, candidate in marker_palette_names {
		if name == key {
			return candidate, true
		}
	}
	return {}, false
}

find_palette_color :: proc(key: string) -> (color: Palette_Color, found: bool) {
	for name, candidate in palette_color_names {
		if name == key {
			return candidate, true
		}
	}
	return {}, false
}

// palettes = {default = {...}, colour_blind = {...}}; a colour left out
// keeps its default.
assign_theme_palettes :: proc(theme: ^Ui_Theme, value: json.Value, source: string) -> string {
	object, is_object := value.(json.Object)
	if !is_object {
		return fmt.tprintf("%s: palettes must be an object, not %s", source, json_type_name(value))
	}
	for name in sorted_object_keys(object) {
		palette, found := find_marker_palette(name)
		if !found {
			return fmt.tprintf("%s: unknown key palettes.%s", source, name)
		}
		if problem := assign_theme_palette(&theme.palettes[palette], object[name], source, name); problem != "" {
			return problem
		}
	}
	return ""
}

assign_theme_palette :: proc(colors: ^[Palette_Color]Ui_Color, value: json.Value, source, name: string) -> string {
	object, is_object := value.(json.Object)
	if !is_object {
		return fmt.tprintf("%s: palettes.%s must be an object, not %s", source, name, json_type_name(value))
	}
	for key in sorted_object_keys(object) {
		key_path := fmt.tprintf("palettes.%s.%s", name, key)
		color, found := find_palette_color(key)
		if !found {
			return fmt.tprintf("%s: unknown key %s", source, key_path)
		}
		problem: string
		colors[color], problem = parse_theme_color(object[key], source, key_path)
		if problem != "" {
			return problem
		}
	}
	return ""
}

// The problem names the source.
parse_ui_theme :: proc(data: []byte, source: string) -> (theme: Ui_Theme, problem: string) {
	tree: json.Object
	tree, problem = parse_configuration_layer(data, source, context.temp_allocator)
	if problem != "" {
		return {}, problem
	}
	theme = DEFAULT_UI_THEME
	for key in sorted_object_keys(tree) {
		if problem = assign_theme_key(&theme, key, tree[key], source); problem != "" {
			return {}, problem
		}
	}
	return theme, ""
}

load_ui_theme :: proc(data_directory: string) -> (theme: Ui_Theme, problem: string) {
	data, path, error := read_data_file(data_directory, UI_THEME_DIRECTORY + "/" + UI_THEME_FILE_NAME, context.temp_allocator)
	if error != nil {
		return {}, fmt.tprintf("%s: cannot read: %v", path, error)
	}
	return parse_ui_theme(data, path)
}
