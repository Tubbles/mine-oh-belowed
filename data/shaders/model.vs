#version 330

// Machine model vertex shader (work item 0224, render_models.odin), for
// the lit layer and, instanced and flat, the emissive layer, the slabs and
// the belt items (0347). Attribute and matrix names are the raylib
// defaults, so DrawMesh binds them without extra code. The meshers
// (model_mesh.odin, model_triangle_mesh.odin) give each vertex its colour,
// pre-shaded per face on the CPU, and its face's normal. matModel puts the
// vertex in the world's metres, where the point lights are, as field.vs.
// With instanced_on at 1 (render_model_instances.odin) the vertex first
// goes through instanceTransform, whose bottom row carries the instance's
// colour and is rebuilt to 0, 0, 0, 1 as tree.vs does; matModel is then
// the rlgl stack's transform (the pod's during the descent) and mvp the
// light's or the camera's times it, as begin_instanced_material sets it.
// With instance_tint_on also at 1 that row's first three are the tint
// model.fs multiplies in. A direct draw has both at 0.
// With flat_on at 1 and instanced_on at 0 the vertex is rlgl's batch
// drawn through the shader (0360, begin_flat_batch): rlgl moved it by
// the matrix stack on the CPU, so it is already in the world's metres,
// and matModel is not read for it, since rlgl writes the stack's
// transform there at whatever flush draws the batch. The texture
// coordinate passes to the flat mode's texture0.
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin).

in vec3 vertexPosition;
in vec3 vertexNormal;
in vec4 vertexColor;
in vec2 vertexTexCoord;
in mat4 instanceTransform;

uniform mat4 mvp;
uniform mat4 matModel;
uniform float instanced_on;
uniform float instance_tint_on;
uniform float flat_on;

out vec3 fragment_world_position;
out vec3 fragment_normal;
out vec4 fragment_color;
out vec4 fragment_tint;
out vec2 fragment_texcoord;

void main()
{
    mat4 model = mat4(1.0);
    fragment_tint = vec4(1.0);
    if (instanced_on > 0.5) {
        model = instanceTransform;
        model[0u][3u] = 0.0;
        model[1u][3u] = 0.0;
        model[2u][3u] = 0.0;
        model[3u][3u] = 1.0;
        if (instance_tint_on > 0.5) {
            fragment_tint = vec4(instanceTransform[0u][3u], instanceTransform[1u][3u], instanceTransform[2u][3u], 1.0);
        }
    }
    vec4 local = model * vec4(vertexPosition, 1.0);
    bool batch_vertex = flat_on > 0.5 && instanced_on < 0.5;
    fragment_world_position = batch_vertex ? local.xyz : (matModel * local).xyz;
    fragment_normal = mat3(matModel) * (mat3(model) * vertexNormal);
    fragment_color = vertexColor;
    fragment_texcoord = vertexTexCoord;
    gl_Position = mvp * local;
}
