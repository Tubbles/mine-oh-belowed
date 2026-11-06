package game

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "sjson_text"

// The textures of the field's ground (work item 0169,
// doc/presentation.md, Textures): one generated tile per material but air
// and one per look (0307: grass, sand, snow), from
// data/textures/field_materials.sjson. A tile is generate_ore_tile's
// flecks over a ground colour. Only crystal size 1 is accepted: its round
// flecks are isotropic, while larger sizes make squares whose edges stripe
// along the axes of the triplanar projection (render_field.odin). Every
// material and every look needs exactly one entry and every key is
// required. The renderer reads every tile from one atlas
// (field_ground_atlas_pixels).

FIELD_MATERIALS_TEXTURE_FILE :: "textures/field_materials.sjson"

// One tile per material but air, in the material's order.
FIELD_MATERIAL_TILE_COUNT :: len(Field_Material) - 1

// The looks the field shader lays over the topsoil with a climate (0307).
// They are not materials: no sample holds one.
Field_Look :: enum u8 {
	Grass,
	Sand,
	Snow,
}

// The materials' tiles, then the looks': the field shader's tile index.
FIELD_GROUND_TILE_COUNT :: FIELD_MATERIAL_TILE_COUNT + len(Field_Look)

Field_Ground_Tiles :: [FIELD_GROUND_TILE_COUNT]Tile_Pixels

// The atlas: cells of FIELD_GROUND_ATLAS_CELL_TEXELS in
// FIELD_GROUND_ATLAS_COLUMNS columns, each holding its tile repeated, the
// copy the shader reads FIELD_GROUND_ATLAS_MARGIN_TEXELS in from the
// cell's edge, so its mipmaps down to the tile's mean (level 4) never
// reach a neighbour cell.
FIELD_GROUND_ATLAS_COLUMNS :: 4
FIELD_GROUND_ATLAS_CELL_TEXELS :: 64
FIELD_GROUND_ATLAS_TEXELS :: 256
FIELD_GROUND_ATLAS_MARGIN_TEXELS :: 24

#assert(FIELD_GROUND_TILE_COUNT <= FIELD_GROUND_ATLAS_COLUMNS * FIELD_GROUND_ATLAS_COLUMNS, "the ground tiles fit the atlas's 16 cells")
#assert(FIELD_GROUND_ATLAS_COLUMNS * FIELD_GROUND_ATLAS_CELL_TEXELS == FIELD_GROUND_ATLAS_TEXELS, "the cells fill the atlas")
#assert(2 * FIELD_GROUND_ATLAS_MARGIN_TEXELS + ATLAS_TILE_SIZE == FIELD_GROUND_ATLAS_CELL_TEXELS, "the read copy lies in the cell's middle")

field_material_tile :: proc(material: Field_Material) -> int {
	return int(material) - 1
}

field_look_tile :: proc(look: Field_Look) -> int {
	return FIELD_MATERIAL_TILE_COUNT + int(look)
}

field_look_name :: proc(look: Field_Look) -> string {
	return strings.to_lower(fmt.tprintf("%v", look), context.temp_allocator)
}

field_material_texture_key_is_known :: proc(key: string, kind: string) -> bool {
	switch key {
	case kind, "ground", "fleck":
		return true
	}
	for parameter in Ore_Texture_Parameter {
		if ore_texture_parameter_ranges[parameter].key == key {
			return true
		}
	}
	return false
}

parse_field_look :: proc(object: json.Object) -> (look: Field_Look, problem: string) {
	name, is_string := object["look"].(json.String)
	if !is_string {
		return .Grass, "look must be a string"
	}
	for candidate in Field_Look {
		if field_look_name(candidate) == name {
			return candidate, ""
		}
	}
	return .Grass, fmt.tprintf("unknown look %s (expected grass, sand or snow)", name)
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
	return .Air, fmt.tprintf("unknown material %s (expected a material of the field but air)", name)
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

// An entry's object with every key known, kind ("material" or "look")
// naming what it is.
field_texture_object :: proc(value: json.Value, kind: string) -> (object: json.Object, problem: string) {
	is_object: bool
	if object, is_object = value.(json.Object); !is_object {
		return nil, fmt.tprintf("must be an object, not %s", json_type_name(value))
	}
	for key in sjson_text.sorted_object_keys(object) {
		if !field_material_texture_key_is_known(key, kind) {
			return nil, fmt.tprintf("unknown key %s", key)
		}
	}
	return object, ""
}

// The tile of an entry's colours and parameters.
parse_field_texture_tile :: proc(object: json.Object) -> (tile: Tile_Pixels, problem: string) {
	colors: [2][3]u8
	for key, index in ([2]string{"ground", "fleck"}) {
		if colors[index], problem = parse_texture_color(object, key); problem != "" {
			return {}, problem
		}
	}
	parameters: Ore_Texture_Parameters
	for parameter in Ore_Texture_Parameter {
		parameter_value: f64
		if parameter_value, problem = parse_texture_parameter(object, ore_texture_parameter_ranges[parameter]); problem != "" {
			return {}, problem
		}
		set_ore_texture_parameter(&parameters, parameter, parameter_value)
	}
	if parameters.crystal_size != 1 {
		return {}, fmt.tprintf("crystal_size is %d, not 1: blocks of %d by %d texels stripe along the axes under the triplanar projection", parameters.crystal_size, parameters.crystal_size, parameters.crystal_size)
	}
	return generate_ore_tile(parameters, colors[0], colors[1]), ""
}

parse_field_material_texture :: proc(value: json.Value) -> (material: Field_Material, tile: Tile_Pixels, problem: string) {
	object: json.Object
	if object, problem = field_texture_object(value, "material"); problem != "" {
		return .Air, {}, problem
	}
	if material, problem = parse_field_material(object); problem != "" {
		return .Air, {}, problem
	}
	if tile, problem = parse_field_texture_tile(object); problem != "" {
		return .Air, {}, problem
	}
	return material, tile, ""
}

parse_field_look_texture :: proc(value: json.Value) -> (look: Field_Look, tile: Tile_Pixels, problem: string) {
	object: json.Object
	if object, problem = field_texture_object(value, "look"); problem != "" {
		return .Grass, {}, problem
	}
	if look, problem = parse_field_look(object); problem != "" {
		return .Grass, {}, problem
	}
	if tile, problem = parse_field_texture_tile(object); problem != "" {
		return .Grass, {}, problem
	}
	return look, tile, ""
}

// source names the file in the problem.
parse_field_material_textures :: proc(data: []byte, source: string) -> (tiles: Field_Ground_Tiles, problem: string) {
	tree, parse_problem := parse_configuration_layer(data, source, context.temp_allocator)
	if parse_problem != "" {
		return {}, parse_problem
	}
	materials, materials_are_array := tree["materials"].(json.Array)
	looks, looks_are_array := tree["looks"].(json.Array)
	if !materials_are_array || !looks_are_array || len(tree) != 2 {
		return {}, fmt.tprintf("%s: expected only materials and looks, arrays", source)
	}
	if problem = parse_field_material_entries(materials, source, &tiles); problem != "" {
		return {}, problem
	}
	if problem = parse_field_look_entries(looks, source, &tiles); problem != "" {
		return {}, problem
	}
	return tiles, ""
}

parse_field_material_entries :: proc(entries: json.Array, source: string, tiles: ^Field_Ground_Tiles) -> string {
	seen: [Field_Material]bool
	for entry, index in entries {
		material, tile, entry_problem := parse_field_material_texture(entry)
		if entry_problem != "" {
			return fmt.tprintf("%s: materials[%d] %s", source, index, entry_problem)
		}
		if seen[material] {
			return fmt.tprintf("%s: materials[%d] repeats %s", source, index, field_material_name(material))
		}
		seen[material] = true
		tiles[field_material_tile(material)] = tile
	}
	for material in Field_Material {
		if material != .Air && !seen[material] {
			return fmt.tprintf("%s: no entry for %s", source, field_material_name(material))
		}
	}
	return ""
}

parse_field_look_entries :: proc(entries: json.Array, source: string, tiles: ^Field_Ground_Tiles) -> string {
	seen: [Field_Look]bool
	for entry, index in entries {
		look, tile, entry_problem := parse_field_look_texture(entry)
		if entry_problem != "" {
			return fmt.tprintf("%s: looks[%d] %s", source, index, entry_problem)
		}
		if seen[look] {
			return fmt.tprintf("%s: looks[%d] repeats %s", source, index, field_look_name(look))
		}
		seen[look] = true
		tiles[field_look_tile(look)] = tile
	}
	for look in Field_Look {
		if !seen[look] {
			return fmt.tprintf("%s: no entry for look %s", source, field_look_name(look))
		}
	}
	return ""
}

// The atlas's texels, row major: tile index fills the cell of column
// index % FIELD_GROUND_ATLAS_COLUMNS and row index /
// FIELD_GROUND_ATLAS_COLUMNS, repeated so the cell's texel
// FIELD_GROUND_ATLAS_MARGIN_TEXELS in on both axes is the tile's first.
// Each 16 texel block of a cell holds every tile texel once, so the
// cell's level 4 mipmap is the tile's mean. Unused cells are zero.
field_ground_atlas_pixels :: proc(tiles: Field_Ground_Tiles, allocator := context.allocator) -> [][4]u8 {
	pixels := make([][4]u8, FIELD_GROUND_ATLAS_TEXELS * FIELD_GROUND_ATLAS_TEXELS, allocator)
	for tile, index in tiles {
		cell := [2]int{index % FIELD_GROUND_ATLAS_COLUMNS, index / FIELD_GROUND_ATLAS_COLUMNS} * FIELD_GROUND_ATLAS_CELL_TEXELS
		for y in 0 ..< FIELD_GROUND_ATLAS_CELL_TEXELS {
			for x in 0 ..< FIELD_GROUND_ATLAS_CELL_TEXELS {
				source := ((y - FIELD_GROUND_ATLAS_MARGIN_TEXELS) %% ATLAS_TILE_SIZE) * ATLAS_TILE_SIZE + (x - FIELD_GROUND_ATLAS_MARGIN_TEXELS) %% ATLAS_TILE_SIZE
				pixels[(cell.y + y) * FIELD_GROUND_ATLAS_TEXELS + cell.x + x] = tile[source]
			}
		}
	}
	return pixels
}

load_field_material_tiles :: proc(data_directory: string) -> (tiles: Field_Ground_Tiles, problem: string) {
	data, path, error := read_data_file(data_directory, FIELD_MATERIALS_TEXTURE_FILE, context.temp_allocator)
	if error != nil {
		return {}, fmt.tprintf("cannot read %s: %v", path, error)
	}
	return parse_field_material_textures(data, path)
}
