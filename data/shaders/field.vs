#version 330

// Field vertex shader (work item 0169, render_field.odin). Attribute and
// matrix names are the raylib defaults, so DrawMesh binds them without
// extra code. The mesher (world_field_mesh.odin) packs:
//   colour rgb   the strata's tint of the ground at the vertex
//   colour a     the sky light (work item 0173), 0 to 1
//   texcoord x   the block light, 0 to 1
//   texcoord y   the weights of hematite, chalcopyrite and coal ore,
//                three bytes in one float (field_pack_bytes)
//   texcoord2 x  the grass colour at full light (work item 0307), bytes
//   texcoord2 y  the snow, the sand and the natural share, bytes
//   normal       the outward surface normal, against the density gradient
//   tangent      the weights of topsoil, stone, deep stone and bedrock
// The seven weights sum to about 1. A packed float is at most 2^24 - 1,
// exact in a float, so unpack_bytes gives the bytes back whole; it runs
// here, per vertex, and the bytes are interpolated.

in vec3 vertexPosition;
in vec3 vertexNormal;
in vec4 vertexColor;
in vec2 vertexTexCoord;
in vec2 vertexTexCoord2;
in vec4 vertexTangent;

uniform mat4 mvp;
uniform mat4 matModel;

out vec3 fragment_world_position;
out vec3 fragment_normal;
out vec4 fragment_color;
out vec4 fragment_weights;
// The ores' weights: hematite, chalcopyrite, coal.
out vec3 fragment_ore_weights;
// The grass colour, 0 to 1, and the look: snow, sand, natural (0307).
out vec3 fragment_grass_color;
out vec3 fragment_look;
out float fragment_block_light;

// Three bytes packed as the lowest plus 256 times the middle plus 65536
// times the highest, each over 255.
vec3 unpack_bytes(float packed_bytes)
{
    float highest = floor(packed_bytes / 65536.0);
    float rest = packed_bytes - highest * 65536.0;
    float middle = floor(rest / 256.0);
    float lowest = rest - middle * 256.0;
    return vec3(lowest, middle, highest) / 255.0;
}

void main()
{
    vec4 world_position = matModel * vec4(vertexPosition, 1.0);
    fragment_world_position = world_position.xyz;
    fragment_normal = mat3(matModel) * vertexNormal;
    fragment_color = vertexColor;
    fragment_weights = vertexTangent;
    fragment_ore_weights = unpack_bytes(vertexTexCoord.y);
    fragment_grass_color = unpack_bytes(vertexTexCoord2.x);
    fragment_look = unpack_bytes(vertexTexCoord2.y);
    fragment_block_light = vertexTexCoord.x;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
