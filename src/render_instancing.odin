package game

import "core:math/bits"
import rl "shared:raylib"
import "shared:raylib/rlgl"

// Instanced draws through rlgl (work items 0310 and 0311): a vertex array
// of a shape's vertex buffer, read per vertex, and a buffer of instance
// matrices at INSTANCE_TRANSFORM_LOCATION to + 3, a column a location,
// read once per instance. The trees' card tiles (render_field_trees.odin)
// and the ground cover (render_field_cover.odin) draw through it with
// rlgl.DrawVertexArrayInstanced and the mvp instanced_mvp gives. The
// trees' near and cast models (0346) draw from a persistent buffer of a
// view's pass, written in place (upload_instances_in_place), through the
// model mesh's own vertex array with the instance attributes pointed at a
// range of the buffer (draw_mesh_instances), between
// begin_instanced_material and end_instanced_material: what raylib's
// DrawMeshInstanced does without making and deleting a buffer per call.

// raylib binds instanceTransform here
// (RL_DEFAULT_SHADER_ATTRIB_LOCATION_INSTANCETRANSFORM), a column a
// location.
INSTANCE_TRANSFORM_LOCATION :: 9
// The fewest instances a persistent buffer holds.
INSTANCE_BUFFER_LEAST_CAPACITY :: 256

// One per vertex attribute of a shape's buffer: its location, its
// component count and type (rlgl.FLOAT, rlgl.UNSIGNED_BYTE), whether it
// is normalised and its offset in the vertex.
Instanced_Attribute :: struct {
	location:   u32,
	size:       i32,
	type:       i32,
	normalized: bool,
	offset:     i32,
}

// A vertex array of the shape's buffer, its vertices stride bytes apart
// (0 for tightly packed), and a new buffer of the instances read once
// per instance; none (zero) without instances.
upload_instanced_buffer :: proc(shape_buffer: u32, layout: []Instanced_Attribute, stride: i32, instances: []matrix[4, 4]f32) -> (vertex_array, instance_buffer: u32) {
	if len(instances) == 0 {
		return 0, 0
	}
	vertex_array = rlgl.LoadVertexArray()
	rlgl.EnableVertexArray(vertex_array)
	rlgl.EnableVertexBuffer(shape_buffer)
	for attribute in layout {
		rlgl.SetVertexAttribute(attribute.location, attribute.size, attribute.type, attribute.normalized, stride, attribute.offset)
		rlgl.EnableVertexAttribute(attribute.location)
	}
	instance_buffer = rlgl.LoadVertexBuffer(raw_data(instances), i32(len(instances) * size_of(matrix[4, 4]f32)), false)
	for column in 0 ..< 4 {
		location := u32(INSTANCE_TRANSFORM_LOCATION + column)
		rlgl.EnableVertexAttribute(location)
		rlgl.SetVertexAttribute(location, 4, rlgl.FLOAT, false, size_of(matrix[4, 4]f32), i32(column * size_of([4]f32)))
		rlgl.SetVertexAttributeDivisor(location, 1)
	}
	rlgl.DisableVertexArray()
	rlgl.DisableVertexBuffer()
	return vertex_array, instance_buffer
}

// Both, when they were made.
unload_instanced_buffer :: proc(vertex_array, instance_buffer: u32) {
	if vertex_array != 0 {
		rlgl.UnloadVertexArray(vertex_array)
	}
	if instance_buffer != 0 {
		rlgl.UnloadVertexBuffer(instance_buffer)
	}
}

// The mvp as raylib's instanced draw sets it (rmodels.c): the projection
// times the modelview times the transform, the instance matrices taking
// the model's place.
instanced_mvp :: proc() -> rl.Matrix {
	return rlgl.GetMatrixProjection() * rlgl.GetMatrixModelview() * rlgl.GetMatrixTransform()
}

// A persistent buffer's capacity in instances for count instances: kept
// while they fit, else the larger of INSTANCE_BUFFER_LEAST_CAPACITY and
// the next power of two at or above count, and grow set.
instance_buffer_capacity :: proc(capacity, count: int) -> (new_capacity: int, grow: bool) {
	if count <= capacity {
		return capacity, false
	}
	return max(INSTANCE_BUFFER_LEAST_CAPACITY, 1 << uint(bits.len(uint(count - 1)))), true
}

// The instances written to the start of the buffer, which is made or
// grown (the old one deleted) when they do not fit. Nothing for none.
upload_instances_in_place :: proc(buffer: ^u32, capacity: ^int, instances: []matrix[4, 4]f32) {
	if len(instances) == 0 {
		return
	}
	if new_capacity, grow := instance_buffer_capacity(capacity^, len(instances)); grow {
		if buffer^ != 0 {
			rlgl.UnloadVertexBuffer(buffer^)
		}
		buffer^ = rlgl.LoadVertexBuffer(nil, i32(new_capacity * size_of(matrix[4, 4]f32)), true)
		capacity^ = new_capacity
	}
	rlgl.UpdateVertexBuffer(buffer^, raw_data(instances), i32(len(instances) * size_of(matrix[4, 4]f32)), 0)
	rlgl.DisableVertexBuffer()
}

// The cube map slots of a material, which raylib binds as cube maps.
material_map_is_cubemap :: proc(index: int) -> bool {
	map_index := rl.MaterialMapIndex(index)
	return map_index == .IRRADIANCE || map_index == .PREFILTER || map_index == .CUBEMAP
}

// The colour as the shader's vec4 at the location, unless it has none.
set_material_color_uniform :: proc(location: i32, color: rl.Color) {
	if location == -1 {
		return
	}
	values := [4]f32{f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
	rlgl.SetUniform(location, &values, i32(rl.ShaderUniformDataType.VEC4), 1)
}

set_material_matrix_uniform :: proc(location: i32, value: rl.Matrix) {
	if location != -1 {
		rlgl.SetUniformMatrix(location, value)
	}
}

// What DrawMeshInstanced (rmodels.c of raylib 6.2) sets before its draw:
// the shader on, the diffuse and specular colours, the view, projection
// and normal matrices where the shader has them (the normal matrix the
// identity, as the instances take the model's place), every map with a
// texture bound at its unit with its sampler set to it, and the mvp
// (instanced_mvp). No batch flush, as DrawMeshInstanced.
begin_instanced_material :: proc(material: rl.Material) {
	shader := material.shader
	rlgl.EnableShader(shader.id)
	set_material_color_uniform(shader.locs[int(rl.ShaderLocationIndex.COLOR_DIFFUSE)], material.maps[rl.MaterialMapIndex.ALBEDO].color)
	set_material_color_uniform(shader.locs[int(rl.ShaderLocationIndex.COLOR_SPECULAR)], material.maps[rl.MaterialMapIndex.METALNESS].color)
	set_material_matrix_uniform(shader.locs[int(rl.ShaderLocationIndex.MATRIX_VIEW)], rlgl.GetMatrixModelview())
	set_material_matrix_uniform(shader.locs[int(rl.ShaderLocationIndex.MATRIX_PROJECTION)], rlgl.GetMatrixProjection())
	set_material_matrix_uniform(shader.locs[int(rl.ShaderLocationIndex.MATRIX_NORMAL)], rl.Matrix(1))
	for index in 0 ..< rl.MAX_MATERIAL_MAPS {
		texture := material.maps[index].texture
		if texture.id == 0 {
			continue
		}
		rlgl.ActiveTextureSlot(i32(index))
		if material_map_is_cubemap(index) {
			rlgl.EnableTextureCubemap(texture.id)
		} else {
			rlgl.EnableTexture(texture.id)
		}
		if location := shader.locs[int(rl.ShaderLocationIndex.MAP_ALBEDO) + index]; location != -1 {
			slot := i32(index)
			rlgl.SetUniform(location, &slot, i32(rl.ShaderUniformDataType.INT), 1)
		}
	}
	set_material_matrix_uniform(shader.locs[int(rl.ShaderLocationIndex.MATRIX_MVP)], instanced_mvp())
}

// The material's textures unbound, then the vertex array, the buffers and
// the shader, as DrawMeshInstanced ends.
end_instanced_material :: proc(material: rl.Material) {
	for index in 0 ..< rl.MAX_MATERIAL_MAPS {
		if material.maps[index].texture.id == 0 {
			continue
		}
		rlgl.ActiveTextureSlot(i32(index))
		if material_map_is_cubemap(index) {
			rlgl.DisableTextureCubemap()
		} else {
			rlgl.DisableTexture()
		}
	}
	rlgl.DisableVertexArray()
	rlgl.DisableVertexBuffer()
	rlgl.DisableVertexBufferElement()
	rlgl.DisableShader()
}

// Between begin_instanced_material and end_instanced_material: count
// instances from first on in the buffer, drawn with the mesh through its
// own vertex array (its element buffer included), the instance attributes
// pointed at that range. The array keeps pointing at the buffer after.
draw_mesh_instances :: proc(mesh: rl.Mesh, instance_buffer: u32, first, count: int) {
	rlgl.EnableVertexArray(mesh.vaoId)
	rlgl.EnableVertexBuffer(instance_buffer)
	for column in 0 ..< 4 {
		location := u32(INSTANCE_TRANSFORM_LOCATION + column)
		rlgl.EnableVertexAttribute(location)
		rlgl.SetVertexAttribute(location, 4, rlgl.FLOAT, false, size_of(matrix[4, 4]f32), i32(first * size_of(matrix[4, 4]f32) + column * size_of([4]f32)))
		rlgl.SetVertexAttributeDivisor(location, 1)
	}
	rlgl.DisableVertexBuffer()
	if mesh.indices != nil {
		rlgl.DrawVertexArrayElementsInstanced(0, mesh.triangleCount * 3, nil, i32(count))
	} else {
		rlgl.DrawVertexArrayInstanced(0, mesh.vertexCount, i32(count))
	}
	count_draw_call()
	rlgl.DisableVertexArray()
}
