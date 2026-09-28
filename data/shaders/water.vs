#version 330

// Water vertex shader (work item 0065), the chunk vertex shader without
// the wind: water faces never sway. Attribute and matrix names are the
// raylib defaults, so DrawMesh binds them without extra code. The vertex
// colour carries sky light and occlusion and the normal the block light
// as for the chunks (chunk.fs); the
// tangent carries the water cell's flow direction in x and z (a unit
// vector, zero for a source or level water) and the vertex's shore value,
// 1 where a solid cell touches the vertex, 0 in open water
// (water_tangent in world_mesh.odin).

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec2 vertexTexCoord2;
in vec4 vertexColor;
in vec4 vertexTangent;
in vec3 vertexNormal;

uniform mat4 mvp;
uniform mat4 matModel;
uniform vec3 camera_position;

// Texcoord in blocks across the merged quad, repeated per block in the
// fragment shader. Tile origin is the atlas UV of the block's tile corner.
out vec2 fragment_texcoord;
out vec2 fragment_tile_origin;
out vec4 fragment_color;
out vec3 fragment_block_light;
out float fragment_distance;
out vec3 fragment_world_position;
out vec2 fragment_flow;
out float fragment_shore;

void main()
{
    vec4 world_position = matModel * vec4(vertexPosition, 1.0);
    fragment_texcoord = vertexTexCoord;
    fragment_tile_origin = vertexTexCoord2;
    fragment_color = vertexColor;
    fragment_block_light = vertexNormal;
    fragment_distance = length(world_position.xyz - camera_position);
    fragment_world_position = world_position.xyz;
    fragment_flow = vertexTangent.xy;
    fragment_shore = vertexTangent.z;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
