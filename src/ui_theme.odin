package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"

// The UI theme (work item 0071): colours and art metrics from
// data/ui/theme.sjson, loaded at start and on a presentation reload
// (hot_reload.odin). A key the file leaves out keeps its default, and
// the defaults are the colours the UI was drawn with before the file
// existed, so a file that sets nothing changes nothing. An unknown key,
// a wrong type or a value out of range refuses the whole file, naming
// it. A colour whose alpha is 0 turns its element off (the highlight
// line, the pressed state, dividers). The icon set the theme's art uses
// (Ui_Icon) lives under data/ui/icons/ (render_icons.odin).

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

Ui_Theme :: struct {
	colors:      [Ui_Theme_Color]Ui_Color,
	// Edge, highlight and divider lines, in UI units.
	border:      f32,
	// The panel corners are cut by this much (0: square).
	corner:      f32,
	// How much thicker the focus outline grows at the top of its pulse.
	focus_pulse: f32,
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
	case:
		problem = fmt.tprintf("%s: unknown key %s", source, key)
	}
	return problem
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

ui_theme_path :: proc(data_directory: string) -> string {
	return join_save_path(data_directory, UI_THEME_DIRECTORY, UI_THEME_FILE_NAME)
}

load_ui_theme :: proc(data_directory: string) -> (theme: Ui_Theme, problem: string) {
	path := ui_theme_path(data_directory)
	data, error := os.read_entire_file(path, context.temp_allocator)
	if error != nil {
		return {}, fmt.tprintf("%s: cannot read: %v", path, error)
	}
	return parse_ui_theme(data, path)
}
