package game

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"
import "platform"

// The `config` subcommand's dump and the settings file the settings screen
// writes.

// The files in precedence order, then the effective configuration as SJSON
// with the source of every value as a trailing comment. Bindings are the
// effective list: data/bindings.sjson with the configuration's overrides.
configuration_dump :: proc(loaded: Loaded_Configuration, bindings: []Binding) -> string {
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "// Configuration files, lowest precedence first:\n")
	for file in loaded.files {
		fmt.sbprintf(&builder, "//   %s%s\n", file.path, file.found ? "" : " (missing)")
	}
	fmt.sbprintf(&builder, "//   %s (--set)\n", COMMAND_LINE_SOURCE)
	strings.write_string(&builder, "// Effective configuration:\n")
	configuration := loaded.configuration
	for field in reflect.struct_fields_zipped(Configuration) {
		if field.name == "bindings" {
			write_bindings_dump(&builder, bindings)
			continue
		}
		value := any{rawptr(uintptr(&configuration) + field.offset), field.type.id}
		write_configuration_dump_value(&builder, value, field.name, field.name, 0, loaded.provenance, true)
	}
	return strings.to_string(builder)
}

write_dump_indentation :: proc(builder: ^strings.Builder, depth: int) {
	for _ in 0 ..< depth {
		strings.write_byte(builder, '\t')
	}
}

// SJSON for a struct or a leaf, with the source of each leaf as a comment
// when with_sources is set.
write_configuration_dump_value :: proc(builder: ^strings.Builder, value: any, key, key_path: string, depth: int, provenance: Configuration_Provenance, with_sources: bool) {
	write_dump_indentation(builder, depth)
	info := runtime.type_info_base(type_info_of(value.id))
	if _, is_struct := info.variant.(runtime.Type_Info_Struct); !is_struct {
		fmt.sbprintf(builder, "%s = %s", key, dump_leaf_text(value))
		if with_sources {
			fmt.sbprintf(builder, " // %s", source_of_key_path(provenance, key_path))
		}
		strings.write_byte(builder, '\n')
		return
	}
	fmt.sbprintf(builder, "%s = {{\n", key)
	for field in reflect.struct_fields_zipped(value.id) {
		field_value := any{rawptr(uintptr(value.data) + field.offset), field.type.id}
		field_key := configuration_key(field.name, field.tag)
		child_path := join_key_path(key_path, field_key, context.temp_allocator)
		write_configuration_dump_value(builder, field_value, field_key, child_path, depth + 1, provenance, with_sources)
	}
	write_dump_indentation(builder, depth)
	strings.write_string(builder, "}\n")
}

// Enums by lower case name, as the configuration reads them.
dump_leaf_text :: proc(value: any) -> string {
	if text, is_string := value.(string); is_string {
		return fmt.tprintf("%q", text)
	}
	if reflect.is_enum(type_info_of(value.id)) {
		return fmt.tprintf("%q", strings.to_lower(fmt.tprint(value), context.temp_allocator))
	}
	return fmt.tprint(value)
}

binding_entry_text :: proc(binding: Binding) -> string {
	backend := ""
	if binding.backends != {.Raylib, .Sdl3} {
		backend = fmt.tprintf(" backend = %q", backends_text(binding.backends))
	}
	return fmt.tprintf(
		"{{action = %q device = %q control = %q context = %q%s}}",
		fmt.tprint(binding.action),
		device_names[binding.device],
		binding.control,
		context_names[binding.binding_context],
		backend,
	)
}

write_bindings_dump :: proc(builder: ^strings.Builder, bindings: []Binding) {
	strings.write_string(builder, "bindings = [\n")
	for binding in bindings {
		fmt.sbprintf(builder, "\t%s // %s\n", binding_entry_text(binding), binding.source)
	}
	strings.write_string(builder, "]\n")
}

// Settings file.

// Written like the dump rather than with json.marshal, which prints an f32
// 1.15 as 1.14999998.
settings_file_text :: proc(settings: Settings) -> string {
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "// Written by the settings screen. Other files in config.d are left alone.\n")
	settings := settings
	write_configuration_dump_value(&builder, settings, "settings", "settings", 0, nil, false)
	return strings.to_string(builder)
}

// Returns the problem, or an empty string.
write_settings_file :: proc(environment: Configuration_Environment, settings: Settings) -> string {
	user_directory, found := user_configuration_directory(environment)
	if !found {
		return "no configuration directory (set " + platform.CONFIG_HOME_VARIABLES + ")"
	}
	text := settings_file_text(settings)
	path := platform.join_path(user_directory, CONFIGURATION_DROP_IN_DIRECTORY, SETTINGS_FILE_NAME)
	return platform.write_file_replacing(path, transmute([]byte)text)
}
