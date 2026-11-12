#version 330

// Field vertex shader (work item 0169, render_field.odin). The attribute
// names are raylib's defaults, so DrawMesh binds them; the matrix and the
// node's place are the field's own uniforms (0381, below). The mesher
// (world_field_mesh.odin) packs:
//   position     samples from the node's first sample (0381), exact
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

// The anchored pass (0381, use_field_anchor, set_field_node_uniforms):
// the viewport's projection times the camera's view about the anchor,
// the sample nearest the eye, for positions in samples; the node's first
// sample less the anchor, whole samples; the node's first sample in the
// world's metres; and the world's spacing in metres.
uniform mat4 field_view_projection;
uniform vec3 node_offset;
uniform vec3 node_origin;
uniform float metres_per_sample;

// Two nodes' copies of a vertex they share add up to the same samples
// from the anchor exactly, so they land on one clip position bit for
// bit; invariant keeps the compiler from regrouping the sum (0381).
invariant gl_Position;

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
    fragment_world_position = node_origin + vertexPosition * metres_per_sample;
    fragment_normal = vertexNormal;
    fragment_color = vertexColor;
    fragment_weights = vertexTangent;
    fragment_ore_weights = unpack_bytes(vertexTexCoord.y);
    fragment_grass_color = unpack_bytes(vertexTexCoord2.x);
    fragment_look = unpack_bytes(vertexTexCoord2.y);
    fragment_block_light = vertexTexCoord.x;
    gl_Position = field_view_projection * vec4(vertexPosition + node_offset, 1.0);
}
