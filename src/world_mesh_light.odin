package game

// Smooth lighting and ambient occlusion per vertex. The vertex colour
// packs, as read by data/shaders/chunk.fs:
//   red    sky light, 0 to 15 times LIGHT_COLOUR_SCALE (0 to 255)
//   green  block light, same scale
//   blue   ambient occlusion, 0 (both side cells and the corner cell
//          solid) to 3 (all open) times OCCLUSION_COLOUR_SCALE
//   alpha  255
// The light of a vertex averages the cells around it in the layer in front
// of the face: the front cell, the two side cells and the corner cell,
// leaving out opaque ones (they hold no light, block_is_opaque). The
// corner counts as opaque when both sides are, since light cannot get
// past them. Slabs, stairs and torches hold light like air.

Vertex_Light :: [4]u8

LIGHT_COLOUR_SCALE :: 17
OCCLUSION_COLOUR_SCALE :: 85
MAXIMUM_OCCLUSION :: 3
FULL_HEIGHT_EIGHTHS :: 8

// Directions along the face's u and v axes towards each corner, in the
// order of quad_corners.
@(rodata)
corner_signs := [4][2]i32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}

cell_is_opaque :: proc(input: Mesh_Input, local: Local_Coordinate) -> bool {
	return block_is_opaque(input.registry, neighbourhood_block(input, local))
}

average_light_colour :: proc(sum, count: int) -> u8 {
	return u8((sum * LIGHT_COLOUR_SCALE + count / 2) / max(count, 1))
}

vertex_light :: proc(input: Mesh_Input, front: Local_Coordinate, u_axis, v_axis: int, signs: [2]i32) -> Vertex_Light {
	u_step, v_step: Local_Coordinate
	u_step[u_axis] = signs[0]
	v_step[v_axis] = signs[1]
	cells := [4]Local_Coordinate{front, front + u_step, front + v_step, front + u_step + v_step}
	solid: [4]bool
	for cell, index in cells {
		solid[index] = cell_is_opaque(input, cell)
	}
	if solid[1] && solid[2] {
		solid[3] = true
	}
	sky_sum, block_sum, open_count: int
	for cell, index in cells {
		if solid[index] {
			continue
		}
		light := neighbourhood_cell(input, cell).light
		sky_sum += int(light_level(light, .Sky))
		block_sum += int(light_level(light, .Block))
		open_count += 1
	}
	occlusion := MAXIMUM_OCCLUSION - int(solid[1]) - int(solid[2]) - int(solid[3])
	return {average_light_colour(sky_sum, open_count), average_light_colour(block_sum, open_count), u8(occlusion * OCCLUSION_COLOUR_SCALE), 255}
}
