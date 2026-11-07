package game

import rl "shared:raylib"
import "shared:raylib/rlgl"

// Instanced draws through rlgl (work items 0310 and 0311): a vertex array
// of a shape's vertex buffer, read per vertex, and a buffer of instance
// matrices at INSTANCE_TRANSFORM_LOCATION to + 3, a column a location,
// read once per instance. The trees' card tiles (render_field_trees.odin)
// and the ground cover (render_field_cover.odin) draw through it with
// rlgl.DrawVertexArrayInstanced and the mvp instanced_mvp gives.

// raylib binds instanceTransform here
// (RL_DEFAULT_SHADER_ATTRIB_LOCATION_INSTANCETRANSFORM), a column a
// location.
INSTANCE_TRANSFORM_LOCATION :: 9

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
