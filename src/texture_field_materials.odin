package game

import "core:encoding/json"
import "core:fmt"
import "sjson_text"

// The textures of the field's materials (work item 0169,
// doc/presentation.md, Textures): one generated tile per material but air,
// from data/textures/field_materials.sjson. A tile is generate_ore_tile's
// flecks over a ground colour. Only crystal size 1 is accepted: its round
// flecks are isotropic, while larger sizes make squares whose edges stripe
// along the axes of the triplanar projection (render_field.odin). Every material needs exactly one entry and every
// key is required.

FIELD_MATERIALS_TEXTURE_FILE :: "textures/field_materials.sjson"

Field_Material_Tiles :: [FIELD_TEXTURED_MATERIAL_COUNT]Tile_Pixels

field_material_texture_key_is_known :: proc(key: string) -> bool {
	switch key {
	case "material", "ground", "fleck":
		return true
	}
	for parameter in Ore_Texture_Parameter {
		if ore_texture_parameter_ranges[parameter].key == key {
			return true
		}
	}
	return false
}

parse_field_material :: proc(object: json.Object) -> (material: Field_Material, problem: string) {
	name, is_string := object["material"].(json.String)
	if !is_string {
		return .Air, "material must be a string"
	}
	for candidate in Field_Material {
		if candidate != .Air && field_material_name(candidate) == name {
			return candidate, ""
		}
	}
	return .Air, fmt.tprintf("unknown material %s (expected topsoil, stone, deep_stone or bedrock)", name)
}

parse_texture_color :: proc(object: json.Object, key: string) -> (color: [3]u8, problem: string) {
	array, is_array := object[key].(json.Array)
	if !is_array || len(array) != 3 {
		return {}, fmt.tprintf("%s must be an array of red, green and blue", key)
	}
	for component, index in array {
		value, is_integer := component.(json.Integer)
		if !is_integer || value < 0 || value > MAXIMUM_COLOR_COMPONENT {
			return {}, fmt.tprintf("%s[%d] must be a whole number from 0 to %d", key, index, MAXIMUM_COLOR_COMPONENT)
		}
		color[index] = u8(value)
	}
	return color, ""
}

parse_field_material_texture :: proc(value: json.Value) -> (material: Field_Material, tile: Tile_Pixels, problem: string) {
	object, is_object := value.(json.Object)
	if !is_object {
		return .Air, {}, fmt.tprintf("must be an object, not %s", json_type_name(value))
	}
	for key in sjson_text.sorted_object_keys(object) {
		if !field_material_texture_key_is_known(key) {
			return .Air, {}, fmt.tprintf("unknown key %s", key)
		}
	}
	if material, problem = parse_field_material(object); problem != "" {
		return .Air, {}, problem
	}
	colors: [2][3]u8
	for key, index in ([2]string{"ground", "fleck"}) {
		if colors[index], problem = parse_texture_color(object, key); problem != "" {
			return .Air, {}, problem
		}
	}
	parameters: Ore_Texture_Parameters
	for parameter in Ore_Texture_Parameter {
		parameter_value: f64
		if parameter_value, problem = parse_texture_parameter(object, ore_texture_parameter_ranges[parameter]); problem != "" {
			return .Air, {}, problem
		}
		set_ore_texture_parameter(&parameters, parameter, parameter_value)
	}
	if parameters.crystal_size != 1 {
		return .Air, {}, fmt.tprintf("crystal_size is %d, not 1: blocks of %d by %d texels stripe along the axes under the triplanar projection", parameters.crystal_size, parameters.crystal_size, parameters.crystal_size)
	}
	return material, generate_ore_tile(parameters, colors[0], colors[1]), ""
}

// source names the file in the problem.
parse_field_material_textures :: proc(data: []byte, source: string) -> (tiles: Field_Material_Tiles, problem: string) {
	tree, parse_problem := parse_configuration_layer(data, source, context.temp_allocator)
	if parse_problem != "" {
		return {}, parse_problem
	}
	entries, is_array := tree["materials"].(json.Array)
	if !is_array || len(tree) != 1 {
		return {}, fmt.tprintf("%s: expected only materials, an array", source)
	}
	seen: [Field_Material]bool
	for entry, index in entries {
		material, tile, entry_problem := parse_field_material_texture(entry)
		if entry_problem != "" {
			return {}, fmt.tprintf("%s: materials[%d] %s", source, index, entry_problem)
		}
		if seen[material] {
			return {}, fmt.tprintf("%s: materials[%d] repeats %s", source, index, field_material_name(material))
		}
		seen[material] = true
		tiles[field_material_slot(material)] = tile
	}
	for material in Field_Material {
		if material != .Air && !seen[material] {
			return {}, fmt.tprintf("%s: no entry for %s", source, field_material_name(material))
		}
	}
	return tiles, ""
}

load_field_material_tiles :: proc(data_directory: string) -> (tiles: Field_Material_Tiles, problem: string) {
	data, path, error := read_data_file(data_directory, FIELD_MATERIALS_TEXTURE_FILE, context.temp_allocator)
	if error != nil {
		return {}, fmt.tprintf("cannot read %s: %v", path, error)
	}
	return parse_field_material_textures(data, path)
}
