#version 330

// Machine model vertex shader (work item 0224, render_models.odin), for
// the lit layer only. Attribute and matrix names are the raylib defaults,
// so DrawMesh binds them without extra code. The meshers
// (model_mesh.odin, model_triangle_mesh.odin) give each vertex its colour,
// pre-shaded per face on the CPU, and its face's normal. matModel puts the
// vertex in the world's metres, where the point lights are, as field.vs.
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin).

in vec3 vertexPosition;
in vec3 vertexNormal;
in vec4 vertexColor;

uniform mat4 mvp;
uniform mat4 matModel;

out vec3 fragment_world_position;
out vec3 fragment_normal;
out vec4 fragment_color;

void main()
{
    fragment_world_position = (matModel * vec4(vertexPosition, 1.0)).xyz;
    fragment_normal = mat3(matModel) * vertexNormal;
    fragment_color = vertexColor;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
