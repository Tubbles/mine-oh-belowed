#version 330

// Chunk vertex shader (work item 0005). Attribute and matrix names are the
// raylib defaults, so DrawMesh binds them without extra code. The vertex
// colour carries light and occlusion (packing in chunk.fs).

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec2 vertexTexCoord2;
in vec4 vertexColor;

uniform mat4 mvp;
uniform mat4 matModel;
uniform vec3 camera_position;

// Texcoord in blocks across the merged quad, repeated per block in the
// fragment shader. Tile origin is the atlas UV of the block's tile corner.
out vec2 fragment_texcoord;
out vec2 fragment_tile_origin;
out vec4 fragment_color;
out float fragment_distance;

void main()
{
    vec4 world_position = matModel * vec4(vertexPosition, 1.0);
    fragment_texcoord = vertexTexCoord;
    fragment_tile_origin = vertexTexCoord2;
    fragment_color = vertexColor;
    fragment_distance = length(world_position.xyz - camera_position);
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
