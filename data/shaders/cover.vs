#version 330

// Ground cover vertex shader (work item 0311, render_field_cover.odin).
// A kind's shape (vertexPosition in the unit box, the base at the
// origin; vertexColor's alpha 1 where the vertex takes the instance's
// colour, 0 where it keeps its own) is drawn once per instance, whose
// transform comes in instanceTransform (a node's buffer at locations 9 to
// 12, render_instancing.odin): the instance's axes scaled by its width,
// height and depth, its base in the world's metres as the translation,
// and in place of the bottom row (cover_instance) the rank, the sky
// light, the block light and the shade packed, and the colour packed,
// rebuilt here to 0, 0, 0, 1. The instance reaches cover_far less the
// span to cover_near times its rank and shrinks into its base over the
// last cover_shrink_share of that; past it every vertex goes outside clip
// space. Foliage (foliage 1) leans each part (part_vertices vertices a
// part) by a hash of the rank and the part, up to part_lean of the unit
// width at the top, so no two tufts share a silhouette, and takes the
// instance's up as its normal, lit as the ground it stands on on both
// faces; a stone takes its face's normal. Every integer literal carries
// the u suffix (work item 0105, shader_source_test.odin).

in vec3 vertexPosition;
in vec3 vertexNormal;
in vec4 vertexColor;
in mat4 instanceTransform;

uniform mat4 mvp;
uniform vec3 camera_position;
uniform float cover_near;
uniform float cover_far;
uniform float part_vertices;
uniform float foliage;
// The scale of the instance's colour (cover_color_scale).
uniform vec3 color_scale;

out vec3 fragment_world_position;
out vec3 fragment_normal;
out vec3 fragment_albedo;
out float fragment_sky_light;
out float fragment_block_light;

const float cover_shrink_share = 0.2;
const float part_lean = 0.25;
const vec4 outside_clip = vec4(2.0, 2.0, 2.0, 1.0);

// Three bytes packed as the lowest plus 256 times the middle plus 65536
// times the highest, each over 255 (field.vs's).
vec3 unpack_bytes(float packed_bytes)
{
    float highest = floor(packed_bytes / 65536.0);
    float rest = packed_bytes - highest * 65536.0;
    float middle = floor(rest / 256.0);
    float lowest = rest - middle * 256.0;
    return vec3(lowest, middle, highest) / 255.0;
}

// An integer hash (lowbias32).
uint hash_bits(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

void main()
{
    float rank = instanceTransform[0u][3u];
    vec3 lights = unpack_bytes(instanceTransform[1u][3u]);
    vec3 instance_color = unpack_bytes(instanceTransform[2u][3u]);
    mat4 model = instanceTransform;
    model[0u][3u] = 0.0;
    model[1u][3u] = 0.0;
    model[2u][3u] = 0.0;
    model[3u][3u] = 1.0;
    vec3 base = model[3u].xyz;
    float reach = cover_far - (cover_far - cover_near) * rank;
    float size = clamp((reach - distance(camera_position, base)) / max(cover_shrink_share * reach, 0.001), 0.0, 1.0);
    uint part = uint(float(gl_VertexID) / max(part_vertices, 1.0));
    uint bits = hash_bits(floatBitsToUint(rank) ^ (part * 0x9e3779b9u));
    vec2 lean = vec2(float(bits & 0xffffu), float(bits >> 16u)) / 65535.0 * 2.0 - 1.0;
    vec3 local = vertexPosition;
    local.xz += lean * part_lean * vertexPosition.y * foliage;
    vec4 world = model * vec4(local * size, 1.0);
    mat3 axes = mat3(model);
    vec3 stone_normal = transpose(inverse(axes)) * vertexNormal;
    fragment_normal = normalize(mix(stone_normal, axes[1u], foliage));
    fragment_world_position = world.xyz;
    vec3 tinted = vertexColor.rgb * instance_color * color_scale;
    fragment_albedo = mix(vertexColor.rgb, tinted, vertexColor.a) * lights.z;
    fragment_sky_light = lights.x;
    fragment_block_light = lights.y;
    gl_Position = size > 0.0 ? mvp * world : outside_clip;
}
