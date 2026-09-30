package game

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"

// Player configuration (doc/architecture.md, Configuration and
// directories). Layers, lowest precedence first:
// <dir>/mine-oh-belowed/config.sjson for each entry of $XDG_CONFIG_DIRS
// applied last to first, $XDG_CONFIG_HOME/mine-oh-belowed/config.sjson,
// its config.d/*.sjson sorted by file name, then --set flags. Every file
// is parsed into a generic tree and the trees are merged: objects merge
// recursively, scalars and arrays replace the value below wholesale. The
// merged tree is then mapped onto Configuration by reflection, so an
// unknown key or a wrong type names the file that set it.

CONFIGURATION_FILE_NAME :: "config.sjson"
CONFIGURATION_DROP_IN_DIRECTORY :: "config.d"
CONFIGURATION_EXTENSION :: ".sjson"
// The settings screen writes this drop in and nothing else.
SETTINGS_FILE_NAME :: "90-settings.sjson"
when ODIN_OS == .Windows {
	// No system wide configuration directory on Windows.
	DEFAULT_CONFIG_DIRS :: ""
} else {
	DEFAULT_CONFIG_DIRS :: "/etc/xdg"
}
CONFIG_HOME_UNDER_HOME :: ".config"
COMMAND_LINE_SOURCE :: "command line"
DEFAULT_SOURCE :: "default"
MAXIMUM_AUTOSAVE_MINUTES :: 24 * 60
// Keys of removed settings, accepted and ignored with a log line so that a
// settings file written by an older build still loads: settings.shadows
// went with the sun shadows (work item 0097).
RETIRED_CONFIGURATION_KEYS :: [?]string{"settings.shadows"}

Configuration_Paths :: struct {
	// The saves directory. MINE_OH_BELOWED_SAVES still wins over it.
	saves: string,
}

Configuration :: struct {
	settings: Settings,
	// Overrides of data/bindings.sjson: the entries for an action replace
	// every default binding of that action.
	bindings: []Binding_Entry,
	paths:    Configuration_Paths,
}

DEFAULT_CONFIGURATION :: Configuration {
	settings = DEFAULT_SETTINGS,
}

// What the frame loop takes from the configuration.
Player_Configuration :: struct {
	environment:    Configuration_Environment,
	settings:       Settings,
	// Effective bindings, and the tables the input backend reads.
	bindings:       []Binding,
	input_bindings: Input_Bindings,
	// The configuration's bindings, applied again when data/bindings.sjson
	// reloads (hot_reload.odin).
	binding_overrides: []Binding,
	// --watch-data, Default when not given.
	watch_data:     Watch_Data_Mode,
	// --touch-overlay: the touch overlay on for this run (work item 0115).
	touch_overlay_forced: bool,
}

// The environment variables the layering reads, passed in so that tests
// point it at their own directories.
Configuration_Environment :: struct {
	config_home: string,
	config_dirs: string,
	home:        string,
}

Configuration_File :: struct {
	path:  string,
	found: bool,
}

// Key paths look like settings.ui_scale or bindings[2].control; the
// provenance maps each key path a layer set to that layer's source.
Configuration_Provenance :: map[string]string

Loaded_Configuration :: struct {
	configuration: Configuration,
	// Precedence order, lowest first, including the missing ones.
	files:         []Configuration_File,
	provenance:    Configuration_Provenance,
}

// platform_paths.odin: %APPDATA% as the config home on Windows.
read_configuration_environment :: proc() -> Configuration_Environment {
	directories := platform_directories(context.allocator)
	return Configuration_Environment{config_home = directories.config_home, config_dirs = directories.config_dirs, home = directories.home}
}

// Directories.

// $XDG_CONFIG_HOME only when absolute, as the XDG specification requires.
user_configuration_directory :: proc(environment: Configuration_Environment) -> (directory: string, ok: bool) {
	switch {
	case environment.config_home != "" && os.is_absolute_path(environment.config_home):
		return join_save_path(environment.config_home, GAME_DIRECTORY_NAME), true
	case environment.home != "":
		return join_save_path(environment.home, CONFIG_HOME_UNDER_HOME, GAME_DIRECTORY_NAME), true
	}
	return "", false
}

// Lowest precedence first: the last entry of $XDG_CONFIG_DIRS comes first
// so that the first entry wins. Relative entries are ignored.
system_configuration_directories :: proc(environment: Configuration_Environment) -> []string {
	value := environment.config_dirs != "" ? environment.config_dirs : DEFAULT_CONFIG_DIRS
	directories := make([dynamic]string, context.temp_allocator)
	entries := strings.split(value, ":", context.temp_allocator)
	#reverse for entry in entries {
		if entry != "" && os.is_absolute_path(entry) {
			append(&directories, join_save_path(entry, GAME_DIRECTORY_NAME))
		}
	}
	return directories[:]
}

// Every file the layering reads, lowest precedence first, with the missing
// system and user files (and a missing config.d, as "config.d/") marked.
find_configuration_files :: proc(environment: Configuration_Environment, allocator := context.allocator) -> []Configuration_File {
	files := make([dynamic]Configuration_File, allocator)
	for directory in system_configuration_directories(environment) {
		append(&files, configuration_file(join_save_path(directory, CONFIGURATION_FILE_NAME), allocator))
	}
	user_directory, found := user_configuration_directory(environment)
	if !found {
		return files[:]
	}
	append(&files, configuration_file(join_save_path(user_directory, CONFIGURATION_FILE_NAME), allocator))
	append_drop_in_files(&files, join_save_path(user_directory, CONFIGURATION_DROP_IN_DIRECTORY), allocator)
	return files[:]
}

configuration_file :: proc(path: string, allocator := context.allocator) -> Configuration_File {
	return Configuration_File{path = strings.clone(path, allocator), found = os.is_file(path)}
}

append_drop_in_files :: proc(files: ^[dynamic]Configuration_File, directory: string, allocator := context.allocator) {
	entries, error := os.read_all_directory_by_path(directory, context.temp_allocator)
	if error != nil {
		append(files, Configuration_File{path = strings.concatenate({directory, "/"}, allocator)})
		return
	}
	names := make([dynamic]string, context.temp_allocator)
	for entry in entries {
		if entry.type == .Regular && strings.has_suffix(entry.name, CONFIGURATION_EXTENSION) {
			append(&names, entry.name)
		}
	}
	slice.sort(names[:])
	for name in names {
		append(files, Configuration_File{path = strings.clone(join_save_path(directory, name), allocator), found = true})
	}
}

// Trees.

join_key_path :: proc(parent, key: string, allocator := context.allocator) -> string {
	if parent == "" {
		return strings.clone(key, allocator)
	}
	return strings.concatenate({parent, ".", key}, allocator)
}

// The layer that set the key path. Inside an array the array's layer
// counts (arrays replace wholesale). A key no layer set is a default; the
// empty key path stands for a whole file, as data/bindings.sjson uses it.
source_of_key_path :: proc(provenance: Configuration_Provenance, key_path: string) -> string {
	if source, found := provenance[key_path]; found {
		return source
	}
	if bracket := strings.index_byte(key_path, '['); bracket >= 0 {
		if source, found := provenance[key_path[:bracket]]; found {
			return source
		}
	}
	if source, found := provenance[""]; found {
		return source
	}
	return DEFAULT_SOURCE
}

// Records the key path and every key below it.
record_provenance :: proc(provenance: ^Configuration_Provenance, key_path: string, value: json.Value, source: string, allocator := context.allocator) {
	provenance[key_path] = source
	object, is_object := value.(json.Object)
	if !is_object {
		return
	}
	for key, child in object {
		record_provenance(provenance, join_key_path(key_path, key, allocator), child, source, allocator)
	}
}

// Objects merge recursively; anything else replaces the value below.
merge_configuration_object :: proc(target: ^json.Object, layer: json.Object, key_path, source: string, provenance: ^Configuration_Provenance, allocator := context.allocator) {
	for key, value in layer {
		child_path := join_key_path(key_path, key, allocator)
		layer_object, layer_is_object := value.(json.Object)
		if existing, found := &target[key]; found && layer_is_object {
			if existing_object, existing_is_object := &existing.(json.Object); existing_is_object {
				merge_configuration_object(existing_object, layer_object, child_path, source, provenance, allocator)
				continue
			}
		}
		target[key] = value
		record_provenance(provenance, child_path, value, source, allocator)
	}
}

parse_configuration_layer :: proc(data: []byte, source: string, allocator := context.allocator) -> (tree: json.Object, problem: string) {
	value, error := json.parse(data, .SJSON, true, allocator)
	if error != .None {
		return {}, fmt.tprintf("%s: cannot parse: %v", source, error)
	}
	object, is_object := value.(json.Object)
	if !is_object {
		return {}, fmt.tprintf("%s: the top level must be an object", source)
	}
	return object, ""
}

read_configuration_layer :: proc(path: string, allocator := context.allocator) -> (tree: json.Object, problem: string) {
	data, error := os.read_entire_file(path, allocator)
	if error != nil {
		return {}, fmt.tprintf("%s: cannot read: %v", path, error)
	}
	return parse_configuration_layer(data, path, allocator)
}

// Command line layer: --set=settings.ui_scale=1.25. A value that does not
// parse as a JSON5 value is taken as a plain string, so paths need no quotes.
command_line_configuration_layer :: proc(assignments: []string, allocator := context.allocator) -> (tree: json.Object, problem: string) {
	tree = make(json.Object, allocator)
	for assignment in assignments {
		key_path, _, value_text := strings.partition(assignment, "=")
		if key_path == "" || !strings.contains(assignment, "=") {
			return {}, fmt.tprintf("%s: expected --set=<key>=<value>, got %q", COMMAND_LINE_SOURCE, assignment)
		}
		set_command_line_value(&tree, strings.split(key_path, ".", context.temp_allocator), command_line_value(value_text, allocator), allocator)
	}
	return tree, ""
}

command_line_value :: proc(text: string, allocator := context.allocator) -> json.Value {
	value, error := json.parse_string(text, .JSON5, true, allocator)
	if error != .None {
		return json.String(strings.clone(text, allocator))
	}
	return value
}

set_command_line_value :: proc(tree: ^json.Object, keys: []string, value: json.Value, allocator := context.allocator) {
	key := strings.clone(keys[0], allocator)
	if len(keys) == 1 {
		tree[key] = value
		return
	}
	child, found := &tree[key]
	if !found || !is_json_object(child^) {
		tree[key] = make(json.Object, allocator)
		child = &tree[key]
	}
	set_command_line_value(&child.(json.Object), keys[1:], value, allocator)
}

is_json_object :: proc(value: json.Value) -> bool {
	_, is_object := value.(json.Object)
	return is_object
}

// Typed mapping.

json_type_name :: proc(value: json.Value) -> string {
	switch _ in value {
	case json.Null:
		return "null"
	case json.Integer, json.Float:
		return "a number"
	case json.Boolean:
		return "a boolean"
	case json.String:
		return "a string"
	case json.Array:
		return "an array"
	case json.Object:
		return "an object"
	}
	return "nothing"
}

wrong_type_problem :: proc(provenance: Configuration_Provenance, key_path, expected: string, value: json.Value) -> string {
	return fmt.tprintf("%s: %s must be %s, not %s", source_of_key_path(provenance, key_path), key_path, expected, json_type_name(value))
}

sorted_object_keys :: proc(object: json.Object) -> []string {
	keys := make([dynamic]string, 0, len(object), context.temp_allocator)
	for key in object {
		append(&keys, key)
	}
	slice.sort(keys[:])
	return keys[:]
}

// Writes the tree into target, whose current values are the defaults.
// Supports the field types Configuration uses: structs, f32, int, bool,
// string, enums (by lower case name), slices of structs and fixed arrays
// (settings.resolution).
assign_configuration_value :: proc(target: any, value: json.Value, key_path: string, provenance: Configuration_Provenance, allocator := context.allocator) -> string {
	info := runtime.type_info_base(type_info_of(target.id))
	#partial switch variant in info.variant {
	case runtime.Type_Info_Struct:
		return assign_configuration_struct(target, value, key_path, provenance, allocator)
	case runtime.Type_Info_Slice:
		return assign_configuration_slice(target, variant.elem, value, key_path, provenance, allocator)
	case runtime.Type_Info_Array:
		return assign_configuration_array(target, variant, value, key_path, provenance, allocator)
	case runtime.Type_Info_Float:
		number, ok := json_number(value)
		if !ok {
			return wrong_type_problem(provenance, key_path, "a number", value)
		}
		(^f32)(target.data)^ = f32(number)
	case runtime.Type_Info_Integer:
		integer, ok := value.(json.Integer)
		if !ok {
			return wrong_type_problem(provenance, key_path, "a whole number", value)
		}
		(^int)(target.data)^ = int(integer)
	case runtime.Type_Info_Boolean:
		boolean, ok := value.(json.Boolean)
		if !ok {
			return wrong_type_problem(provenance, key_path, "a boolean", value)
		}
		(^bool)(target.data)^ = boolean
	case runtime.Type_Info_String:
		text, ok := value.(json.String)
		if !ok {
			return wrong_type_problem(provenance, key_path, "a string", value)
		}
		(^string)(target.data)^ = strings.clone(text, allocator)
	case runtime.Type_Info_Enum:
		return assign_configuration_enum(target, variant, info.size, value, key_path, provenance)
	case:
		panic("assign_configuration_value: unsupported field type")
	}
	return ""
}

// An enum is written as its value's name in lower case.
assign_configuration_enum :: proc(target: any, variant: runtime.Type_Info_Enum, size: int, value: json.Value, key_path: string, provenance: Configuration_Provenance) -> string {
	text, ok := value.(json.String)
	names := configuration_enum_names(variant)
	if !ok {
		return wrong_type_problem(provenance, key_path, fmt.tprintf("one of %s", names), value)
	}
	for name, index in variant.names {
		if strings.to_lower(name, context.temp_allocator) == text {
			store_unsigned(target.data, size, u64(variant.values[index]))
			return ""
		}
	}
	return fmt.tprintf("%s: %s is %q, not one of %s", source_of_key_path(provenance, key_path), key_path, text, names)
}

configuration_enum_names :: proc(variant: runtime.Type_Info_Enum) -> string {
	names := make([]string, len(variant.names), context.temp_allocator)
	for name, index in variant.names {
		names[index] = strings.to_lower(name, context.temp_allocator)
	}
	return strings.join(names, ", ", context.temp_allocator)
}

json_number :: proc(value: json.Value) -> (number: f64, ok: bool) {
	#partial switch number_value in value {
	case json.Integer:
		return f64(number_value), true
	case json.Float:
		return number_value, true
	}
	return 0, false
}

assign_configuration_struct :: proc(target: any, value: json.Value, key_path: string, provenance: Configuration_Provenance, allocator := context.allocator) -> string {
	object, is_object := value.(json.Object)
	if !is_object {
		return wrong_type_problem(provenance, key_path, "an object", value)
	}
	for key in sorted_object_keys(object) {
		child_path := join_key_path(key_path, key, context.temp_allocator)
		field, found := configuration_field(target.id, key)
		if !found && is_retired_configuration_key(child_path) {
			log_printf("%s: %s is no longer used and is ignored", source_of_key_path(provenance, child_path), child_path)
			continue
		}
		if !found {
			return fmt.tprintf("%s: unknown key %s", source_of_key_path(provenance, child_path), child_path)
		}
		field_value := any{rawptr(uintptr(target.data) + field.offset), field.type.id}
		if problem := assign_configuration_value(field_value, object[key], child_path, provenance, allocator); problem != "" {
			return problem
		}
	}
	return ""
}

is_retired_configuration_key :: proc(key_path: string) -> bool {
	retired := RETIRED_CONFIGURATION_KEYS
	return slice.contains(retired[:], key_path)
}

// A field's key is its json tag when it has one.
configuration_key :: proc(name: string, tag: reflect.Struct_Tag) -> string {
	if tagged, has_tag := reflect.struct_tag_lookup(tag, "json"); has_tag && tagged != "" {
		return tagged
	}
	return name
}

configuration_field :: proc(type: typeid, key: string) -> (field: reflect.Struct_Field, found: bool) {
	for index in 0 ..< reflect.struct_field_count(type) {
		field = reflect.struct_field_at(type, index)
		if configuration_key(field.name, field.tag) == key {
			return field, true
		}
	}
	return {}, false
}

// Each element starts from its zero value: array elements have no defaults.
assign_configuration_slice :: proc(target: any, element: ^runtime.Type_Info, value: json.Value, key_path: string, provenance: Configuration_Provenance, allocator := context.allocator) -> string {
	array, is_array := value.(json.Array)
	if !is_array {
		return wrong_type_problem(provenance, key_path, "an array", value)
	}
	data, _ := mem.alloc(max(len(array), 1) * element.size, element.align, allocator)
	for item, index in array {
		element_path := fmt.tprintf("%s[%d]", key_path, index)
		element_value := any{rawptr(uintptr(data) + uintptr(index * element.size)), element.id}
		if problem := assign_configuration_value(element_value, item, element_path, provenance, allocator); problem != "" {
			return problem
		}
	}
	(^runtime.Raw_Slice)(target.data)^ = {data, len(array)}
	return ""
}

// A fixed array takes exactly its element count.
assign_configuration_array :: proc(target: any, variant: runtime.Type_Info_Array, value: json.Value, key_path: string, provenance: Configuration_Provenance, allocator := context.allocator) -> string {
	array, is_array := value.(json.Array)
	if !is_array || len(array) != variant.count {
		return wrong_type_problem(provenance, key_path, fmt.tprintf("an array of %d", variant.count), value)
	}
	for item, index in array {
		element_path := fmt.tprintf("%s[%d]", key_path, index)
		element_value := any{rawptr(uintptr(target.data) + uintptr(index * variant.elem_size)), variant.elem.id}
		if problem := assign_configuration_value(element_value, item, element_path, provenance, allocator); problem != "" {
			return problem
		}
	}
	return ""
}

// Validation beyond types.

range_problem :: proc(provenance: Configuration_Provenance, key_path: string, value, minimum, maximum: f32) -> string {
	if value >= minimum && value <= maximum {
		return ""
	}
	return fmt.tprintf("%s: %s is %v, outside %v to %v", source_of_key_path(provenance, key_path), key_path, value, minimum, maximum)
}

validate_settings :: proc(settings: Settings, provenance: Configuration_Provenance) -> string {
	checks := [?]struct {
		key:   string,
		value: f32,
		range: Slider_Range,
	} {
		{"settings.ui_scale", settings.ui_scale, UI_SCALE_RANGE},
		{"settings.text_scale", settings.text_scale, TEXT_SCALE_RANGE},
		{"settings.field_of_view", settings.field_of_view, FIELD_OF_VIEW_RANGE},
		{"settings.sprint_field_of_view_kick", settings.sprint_field_of_view_kick, SPRINT_FIELD_OF_VIEW_KICK_RANGE},
		{"settings.third_person_distance", settings.third_person_distance, THIRD_PERSON_DISTANCE_RANGE},
		{"settings.third_person_shoulder", settings.third_person_shoulder, THIRD_PERSON_SHOULDER_RANGE},
		{"settings.pointer_speed", settings.pointer_speed, POINTER_SPEED_RANGE},
		{"settings.stick_look_sensitivity", settings.stick_look_sensitivity, LOOK_SENSITIVITY_RANGE},
		{"settings.gyro_look_sensitivity", settings.gyro_look_sensitivity, LOOK_SENSITIVITY_RANGE},
		{"settings.trackpad_look_sensitivity", settings.trackpad_look_sensitivity, LOOK_SENSITIVITY_RANGE},
	}
	for check in checks {
		if problem := range_problem(provenance, check.key, check.value, check.range.minimum, check.range.maximum); problem != "" {
			return problem
		}
	}
	if problem := range_problem(provenance, "settings.autosave_minutes", f32(settings.autosave_minutes), 0, MAXIMUM_AUTOSAVE_MINUTES); problem != "" {
		return problem
	}
	if problem := range_problem(provenance, "settings.frame_rate_cap", f32(settings.frame_rate_cap), 0, MAXIMUM_FRAME_RATE_CAP); problem != "" {
		return problem
	}
	return resolution_problem(provenance, settings.resolution)
}

// {0, 0} is the monitor's size; anything else is in range on both axes.
resolution_problem :: proc(provenance: Configuration_Provenance, resolution: [2]int) -> string {
	if resolution == NATIVE_RESOLUTION {
		return ""
	}
	for size, axis in resolution {
		key_path := fmt.tprintf("settings.resolution[%d]", axis)
		if problem := range_problem(provenance, key_path, f32(size), MINIMUM_RESOLUTION, MAXIMUM_RESOLUTION); problem != "" {
			return problem
		}
	}
	return ""
}

// A leading ~/ becomes $HOME/. Without HOME the path stays as written.
expand_home :: proc(path, home: string, allocator := context.allocator) -> string {
	if home == "" || !strings.has_prefix(path, "~/") {
		return path
	}
	return strings.concatenate({strings.trim_right(home, "/"), path[1:]}, allocator)
}

// Loading.

// The merged tree of every found file and the command line layer.
merge_configuration_layers :: proc(files: []Configuration_File, assignments: []string, allocator := context.allocator) -> (tree: json.Object, provenance: Configuration_Provenance, problem: string) {
	tree = make(json.Object, allocator)
	provenance = make(Configuration_Provenance, allocator)
	for file in files {
		if !file.found {
			continue
		}
		layer, layer_problem := read_configuration_layer(file.path, allocator)
		if layer_problem != "" {
			return {}, {}, layer_problem
		}
		merge_configuration_object(&tree, layer, "", file.path, &provenance, allocator)
	}
	command_line, command_line_problem := command_line_configuration_layer(assignments, allocator)
	if command_line_problem != "" {
		return {}, {}, command_line_problem
	}
	merge_configuration_object(&tree, command_line, "", COMMAND_LINE_SOURCE, &provenance, allocator)
	return tree, provenance, ""
}

// The problem, when there is one, names the file ("error: " is the
// caller's to add).
load_configuration :: proc(environment: Configuration_Environment, assignments: []string, allocator := context.allocator) -> (loaded: Loaded_Configuration, problem: string) {
	loaded.files = find_configuration_files(environment, allocator)
	tree: json.Object
	tree, loaded.provenance, problem = merge_configuration_layers(loaded.files, assignments, allocator)
	if problem != "" {
		return {}, problem
	}
	loaded.configuration = DEFAULT_CONFIGURATION
	target := any{&loaded.configuration, typeid_of(Configuration)}
	if problem = assign_configuration_value(target, json.Value(tree), "", loaded.provenance, allocator); problem != "" {
		return {}, problem
	}
	if problem = validate_settings(loaded.configuration.settings, loaded.provenance); problem != "" {
		return {}, problem
	}
	loaded.configuration.paths.saves = expand_home(loaded.configuration.paths.saves, environment.home, allocator)
	return loaded, ""
}
