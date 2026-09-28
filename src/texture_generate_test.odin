package game

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import rl "shared:raylib"

// -define:TEXTURE_PREVIEW=true makes test_write_ore_texture_previews write
// under tmp/texture_preview/ each generated ore tile at 1 to 1
// (<id>.png), enlarged 8 times (<id>_enlarged.png) and as a 6 by 6 field
// turned, mirrored and slid per cell like the chunk shader, through
// varied_tile_texcoord (<id>_field.png, 4 pixels per texel), and print
// its blob statistics. It calls raylib, so that run
// links like a build: odin test src -collection:shared=<repository>/shared
// -define:TEXTURE_PREVIEW=true
// -define:ODIN_TEST_NAMES=game.test_write_ore_texture_previews
// -extra-linker-flags:-L<repository>/tmp/linker-shims (the shims build.sh
// makes).
TEXTURE_PREVIEW :: #config(TEXTURE_PREVIEW, false)
PREVIEW_FIELD_CELLS :: 6
PREVIEW_PIXELS_PER_TEXEL :: 4
PREVIEW_ENLARGED_SCALE :: 8

SHIPPED_ORE_BLOCKS :: [?]string{"hematite_ore", "coal_ore", "chalcopyrite_ore", "cassiterite_ore", "galena_ore", "sphalerite_ore", "pentlandite_ore"}

test_ore_parameters :: proc() -> Ore_Texture_Parameters {
	return Ore_Texture_Parameters{seed = 7, share = 0.2, blob_width = 0.7, crystal_size = 1, stone_grain = 8, stone_mottle = 16, ore_grain = 14, rim_strength = 0.2}
}

shipped_procedural_textures_data :: proc() -> []byte {
	data, error := os.read_entire_file(join_save_path(test_data_directory(), TEXTURES_DIRECTORY, PROCEDURAL_TEXTURES_FILE_NAME), context.temp_allocator)
	assert(error == nil)
	return data
}

@(test)
test_ore_tile_is_deterministic_and_opaque :: proc(t: ^testing.T) {
	parameters := test_ore_parameters()
	first := generate_ore_tile(parameters, {128, 128, 128}, {150, 70, 60})
	testing.expect_value(t, generate_ore_tile(parameters, {128, 128, 128}, {150, 70, 60}), first)
	for texel in first {
		testing.expect_value(t, texel.a, 255)
	}
	parameters.seed += 1
	testing.expect(t, generate_ore_tile(parameters, {128, 128, 128}, {150, 70, 60}) != first, "another seed gives another tile")
}

@(test)
test_ore_blob_count_follows_the_share :: proc(t: ^testing.T) {
	parameters := test_ore_parameters()
	for share in ([?]f32{0.05, 0.13, 0.2, 0.37, 0.5}) {
		for crystal_size in 1 ..= 4 {
			field := blur_on_torus(white_noise_field(parameters.seed, .Blob, crystal_size), parameters.blob_width)
			count := 0
			for inside in blob_mask(field, share) {
				count += int(inside)
			}
			testing.expectf(t, abs(f32(count) - share * TEXTURE_TEXEL_COUNT) <= 1, "share %v crystal size %d: %d blob texels", share, crystal_size, count)
		}
	}
}

@(test)
test_blur_wraps_around_the_tile_edge :: proc(t: ^testing.T) {
	for width in ([?]f32{0.3, 0.7, 1.6, 3}) {
		across_x: Tile_Field
		across_x[texel_index(0, 8)] = 1
		blurred := blur_on_torus(across_x, width)
		testing.expect_value(t, blurred[texel_index(ATLAS_TILE_SIZE - 1, 8)], blurred[texel_index(1, 8)])
		across_y: Tile_Field
		across_y[texel_index(8, 0)] = 1
		blurred = blur_on_torus(across_y, width)
		testing.expect_value(t, blurred[texel_index(8, ATLAS_TILE_SIZE - 1)], blurred[texel_index(8, 1)])
	}
}

@(test)
test_shipped_procedural_textures_parse :: proc(t: ^testing.T) {
	registry := shipped_block_registry(t)
	entries, problem := parse_procedural_textures(shipped_procedural_textures_data(), "procedural.sjson", registry, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(entries), len(SHIPPED_ORE_BLOCKS))
	for name in SHIPPED_ORE_BLOCKS {
		block, _ := find_block_id(registry, name)
		_, found := find_procedural_texture(entries, block)
		testing.expectf(t, found, "%s has an entry", name)
	}
}

TEST_ORE_ENTRY :: `block = "hematite_ore", kind = "ore", seed = 5, share = 0.2, blob_width = 0.7, crystal_size = 1, stone_grain = 8, stone_mottle = 16, ore_grain = 14, rim_strength = 0.2`

procedural_entry_problem :: proc(registry: Block_Registry, entry: string) -> string {
	text := fmt.tprintf("textures = [{{%s}}]", entry)
	_, problem := parse_procedural_textures(transmute([]byte)text, "test", registry, context.temp_allocator)
	return problem
}

@(test)
test_procedural_textures_parser_refuses_malformed_entries :: proc(t: ^testing.T) {
	registry := shipped_block_registry(t)
	testing.expect_value(t, procedural_entry_problem(registry, TEST_ORE_ENTRY), "")
	refused := [?]string {
		fmt.tprintf("%s, sparkle = 1", TEST_ORE_ENTRY),
		strings.concatenate({`block = "no_such_block"`, TEST_ORE_ENTRY[len(`block = "hematite_ore"`):]}, context.temp_allocator),
		strings.concatenate({TEST_ORE_ENTRY[:len(TEST_ORE_ENTRY) - len("0.2")], "0.9"}, context.temp_allocator),
		strings.concatenate({`block = "hematite_ore", kind = "vein"`, TEST_ORE_ENTRY[len(`block = "hematite_ore", kind = "ore"`):]}, context.temp_allocator),
		TEST_ORE_ENTRY[:len(TEST_ORE_ENTRY) - len(", rim_strength = 0.2")],
		fmt.tprintf("%s}}, {{%s", TEST_ORE_ENTRY, TEST_ORE_ENTRY),
	}
	for entry in refused {
		problem := procedural_entry_problem(registry, entry)
		testing.expectf(t, strings.contains(problem, "entry"), "refused with the entry named: %q gives %q", entry, problem)
	}
	top_level := "textures = []\nshaders = []"
	_, problem := parse_procedural_textures(transmute([]byte)top_level, "test", registry, context.temp_allocator)
	testing.expect(t, strings.contains(problem, "unknown key shaders"))
}

@(test)
test_ore_tiles_come_from_the_generator_without_files :: proc(t: ^testing.T) {
	registry := shipped_block_registry(t)
	procedural := load_procedural_textures(test_data_directory(), "", registry)
	tiles := read_block_textures(registry, test_data_directory(), procedural)
	for name in SHIPPED_ORE_BLOCKS {
		testing.expectf(t, !os.exists(texture_file_path(test_data_directory(), BLOCK_TEXTURES_DIRECTORY, name)), "%s has no texture file", name)
		block, _ := find_block_id(registry, name)
		generated := generate_procedural_tile(procedural, registry, block).?
		for group in Face_Group {
			testing.expectf(t, tiles[block][group] == generated, "%s %v is the generated tile", name, group)
		}
	}
	layout := atlas_layout_for_block_count(len(registry.definitions))
	pixels := generate_atlas_pixels(registry, layout, tiles, context.temp_allocator)
	hematite, _ := find_block_id(registry, "hematite_ore")
	testing.expect_value(t, atlas_tile_texels(pixels, layout, atlas_tile_index(hematite, .Top)), tiles[hematite][.Top].?)
}

@(test)
test_texture_edits_replace_an_entry :: proc(t: ^testing.T) {
	registry := shipped_block_registry(t)
	directory := make_configuration_test_directory()
	defer os.remove_all(directory)
	edits_path := join_save_path(directory, TEXTURE_EDITS_FILE_NAME)
	write_test_file(edits_path, fmt.tprintf("textures = [{{%s}}]", TEST_ORE_ENTRY))
	base := load_procedural_textures(test_data_directory(), "", registry)
	edited := load_procedural_textures(test_data_directory(), edits_path, registry)
	testing.expect_value(t, len(edited), len(base))
	hematite, _ := find_block_id(registry, "hematite_ore")
	entry, _ := find_procedural_texture(edited, hematite)
	testing.expect_value(t, entry.parameters.seed, 5)
	coal, _ := find_block_id(registry, "coal_ore")
	edited_coal, _ := find_procedural_texture(edited, coal)
	base_coal, _ := find_procedural_texture(base, coal)
	testing.expect_value(t, edited_coal, base_coal)
	// A malformed edits file is ignored as a whole.
	write_test_file(edits_path, "textures = [{sparkle = 1}]")
	testing.expect(t, slice_equal_procedural(load_procedural_textures(test_data_directory(), edits_path, registry), base))
}

slice_equal_procedural :: proc(first, second: []Procedural_Texture) -> bool {
	if len(first) != len(second) {
		return false
	}
	for entry, index in first {
		if entry != second[index] {
			return false
		}
	}
	return true
}

// A field of cells, each the tile turned, mirrored and slid as the chunk
// shader does for a top face at (x, 0, z), with its brightness jitter.
oriented_field_pixels :: proc(tile: Tile_Pixels, cells, scale: int) -> []rl.Color {
	size := cells * ATLAS_TILE_SIZE * scale
	pixels := make([]rl.Color, size * size, context.temp_allocator)
	for pixel_y in 0 ..< size {
		for pixel_x in 0 ..< size {
			cell := [2]int{pixel_x, pixel_y} / (ATLAS_TILE_SIZE * scale)
			hash := texture_variation_hash({i32(cell.x), 0, i32(cell.y)})
			inside := [2]f32{f32(pixel_x % (ATLAS_TILE_SIZE * scale)), f32(pixel_y % (ATLAS_TILE_SIZE * scale))}
			varied := varied_tile_texcoord((inside + 0.5) / f32(ATLAS_TILE_SIZE * scale), hash, .Full)
			texel := tile[texel_index(int(varied.x * ATLAS_TILE_SIZE), int(varied.y * ATLAS_TILE_SIZE))]
			pixels[pixel_y * size + pixel_x] = rl.Color(shaded_texel(texel.rgb, 0, texture_variation_brightness(hash)))
		}
	}
	return pixels
}

// Blobs as four connected groups on the torus: how many, the largest,
// and how many touch the tile's edge.
blob_components :: proc(blobs: Tile_Mask) -> (count, largest, touching_edge: int) {
	seen: Tile_Mask
	for start in 0 ..< TEXTURE_TEXEL_COUNT {
		if !blobs[start] || seen[start] {
			continue
		}
		stack := make([dynamic]int, 0, TEXTURE_TEXEL_COUNT, context.temp_allocator)
		append(&stack, start)
		seen[start] = true
		size, edge := 0, false
		for len(stack) > 0 {
			index := pop(&stack)
			size += 1
			x, y := index % ATLAS_TILE_SIZE, index / ATLAS_TILE_SIZE
			edge ||= x == 0 || y == 0 || x == ATLAS_TILE_SIZE - 1 || y == ATLAS_TILE_SIZE - 1
			for neighbour in ([4]int{texel_index(wrap_texel(x - 1), y), texel_index(wrap_texel(x + 1), y), texel_index(x, wrap_texel(y - 1)), texel_index(x, wrap_texel(y + 1))}) {
				if blobs[neighbour] && !seen[neighbour] {
					seen[neighbour] = true
					append(&stack, neighbour)
				}
			}
		}
		count += 1
		largest = max(largest, size)
		touching_edge += int(edge)
	}
	return count, largest, touching_edge
}

preview_image :: proc(pixels: []rl.Color, size: int) -> rl.Image {
	return rl.Image{data = raw_data(pixels), width = i32(size), height = i32(size), mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
}

@(test)
test_write_ore_texture_previews :: proc(t: ^testing.T) {
	when TEXTURE_PREVIEW {
		registry := shipped_block_registry(t)
		procedural := load_procedural_textures(test_data_directory(), "", registry)
		directory := join_save_path(#directory, "..", "tmp", "texture_preview")
		os.make_directory_all(directory)
		for name in SHIPPED_ORE_BLOCKS {
			block, _ := find_block_id(registry, name)
			tile := generate_procedural_tile(procedural, registry, block).?
			entry, _ := find_procedural_texture(procedural, block)
			parameters := entry.parameters
			blobs := blob_mask(blur_on_torus(white_noise_field(parameters.seed, .Blob, parameters.crystal_size), parameters.blob_width), parameters.share)
			count, largest, touching_edge := blob_components(blobs)
			fmt.printfln("preview %s: %d blobs, largest %d texels, %d touch the edge", name, count, largest, touching_edge)
			tile_pixels := oriented_field_pixels(tile, 1, 1)
			// The single tile unturned: cell (0, 0) may turn, so copy it.
			for texel, index in tile {
				tile_pixels[index] = rl.Color(texel)
			}
			rl.ExportImage(preview_image(tile_pixels, ATLAS_TILE_SIZE), strings.clone_to_cstring(join_save_path(directory, fmt.tprintf("%s.png", name)), context.temp_allocator))
			// The same tile unturned, enlarged for a look.
			enlarged := make([]rl.Color, len(tile) * PREVIEW_ENLARGED_SCALE * PREVIEW_ENLARGED_SCALE, context.temp_allocator)
			enlarged_size := ATLAS_TILE_SIZE * PREVIEW_ENLARGED_SCALE
			for &pixel, index in enlarged {
				pixel = rl.Color(tile[texel_index(index % enlarged_size / PREVIEW_ENLARGED_SCALE, index / enlarged_size / PREVIEW_ENLARGED_SCALE)])
			}
			rl.ExportImage(preview_image(enlarged, enlarged_size), strings.clone_to_cstring(join_save_path(directory, fmt.tprintf("%s_enlarged.png", name)), context.temp_allocator))
			field_size := PREVIEW_FIELD_CELLS * ATLAS_TILE_SIZE * PREVIEW_PIXELS_PER_TEXEL
			field := oriented_field_pixels(tile, PREVIEW_FIELD_CELLS, PREVIEW_PIXELS_PER_TEXEL)
			rl.ExportImage(preview_image(field, field_size), strings.clone_to_cstring(join_save_path(directory, fmt.tprintf("%s_field.png", name)), context.temp_allocator))
		}
	}
}
