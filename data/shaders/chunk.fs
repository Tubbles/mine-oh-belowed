#version 330

// Chunk fragment shader (work items 0005 and 0008): samples the block
// atlas, lights it from the vertex colour and fades to the fog colour
// between fog_start and fog_end to hide the load boundary. Texels with
// alpha below 0.5 are discarded, so the clear texels of ground cover
// tiles (work item 0082) show what lies behind; every other tile is
// opaque.
//
// Vertex colour packing (world_mesh_light.odin), each channel 0 to 1:
//   r  sky light level / 15, averaged over the cells around the vertex
//   g  the face's tile variation (orientation_flag_green): 0 turn, mirror
//      and slide the tile per block, 0.5 turn and mirror only (a framed
//      block, work item 0101), 1 keep it upright (keep_orientation);
//      read with thresholds at 0.25 and 0.75
//   b  ambient occlusion / 3, 1 where nothing solid touches the vertex
//   a  1, lower for vertices that sway in the wind (chunk.vs)
// The block light's red, green and blue levels / 15, averaged the same
// way, come in the normal attribute (fragment_block_light, work item
// 0072). Sky light is scaled by day_factor and coloured by sky_tint
// (white by day, warm at dawn and dusk, blue grey at night, work item
// 0064), block light is neither, so torches glow the same at night; it
// is multiplied by flicker (0.96 to 1, light_flicker in
// render_chunks.odin), the same for every block light. Brightness is sky
// plus block light per colour channel, at most 1, times the occlusion
// shade, never below minimum_brightness.
//
// Cloud shadows (work item 0063): cloud_texture, a tiling noise, laid
// over the world every cloud_tile_blocks blocks (CLOUD_TILE_BLOCKS in
// render_weather.odin) and drifting by cloud_offset, dims the sky light
// term by up to cloud_shadow_strength.
//
// Per block variation (work item 0088, mirrored in
// texture_variation.odin): a hash of the block's integer position, the
// cell behind the face (fragment_cell), turns and mirrors the tile inside
// the block (one of eight orientations), then slides it by a whole texel
// offset (work item 0101), as far as the green channel allows (a framed
// face turns but never slides, a kept face does neither), and scales the texel's brightness by up to
// brightness_jitter either way, so a field of one block does not repeat
// the same tile in rows. The tiles that vary are periodic (checked by
// texture_periodicity_test.odin), so the offset shows no seam inside the
// block, and two neighbours whose orientations mirror across their shared
// edge still show different crops, not a symmetric motif.

in vec2 fragment_texcoord;
in vec2 fragment_tile_origin;
in vec4 fragment_color;
in vec3 fragment_block_light;
in float fragment_distance;
in vec3 fragment_world_position;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec2 tile_size;
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;
uniform float day_factor;
uniform vec3 sky_tint;
uniform sampler2D cloud_texture;
uniform vec2 cloud_offset;
uniform float cloud_shadow_strength;
uniform float flicker;

out vec4 finalColor;

const float minimum_brightness = 0.06;
const float darkest_occlusion_shade = 0.5;
const float cloud_tile_blocks = 96.0;
const float brightness_jitter = 0.04;
// How far behind the face the cell is read, in blocks.
const float cell_depth = 0.01;
// Keeps a turned, mirrored or shifted texcoord inside its tile's last
// texel.
const float largest_tile_texcoord = 0.9999;
// Texels along a tile's edge (ATLAS_TILE_SIZE in render_atlas.odin).
const float tile_texels = 16.0;
// The green channel's thresholds between the three tile variations.
const float turn_only_green = 0.25;
const float keep_orientation_green = 0.75;

// Light levels to brightness: each level down dims a little more than
// linear, Minecraft style, 0 stays 0 and 1 stays 1.
float light_curve(float level)
{
    return level / (4.0 - 3.0 * level);
}

vec3 light_curve(vec3 level)
{
    return level / (4.0 - 3.0 * level);
}

// The block a fragment belongs to: a step behind the face, away from the
// viewer (the cross product of the screen derivatives points towards
// it), so a face on a block boundary reads one cell steadily.
ivec3 fragment_cell()
{
    vec3 facing = cross(dFdx(fragment_world_position), dFdy(fragment_world_position));
    float length_squared = dot(facing, facing);
    vec3 towards_viewer = length_squared > 0.0 ? facing * inversesqrt(length_squared) : vec3(0.0);
    return ivec3(floor(fragment_world_position - towards_viewer * cell_depth));
}

// texture_variation_hash: the cell's coordinates mixed, then the
// lowbias32 finaliser.
uint variation_hash(ivec3 cell)
{
    uvec3 bits = uvec3(cell);
    uint hash = (bits.x * 73856093u) ^ (bits.y * 19349663u) ^ (bits.z * 83492791u);
    hash ^= hash >> 16;
    hash *= 0x7feb352du;
    hash ^= hash >> 15;
    hash *= 0x846ca68bu;
    hash ^= hash >> 16;
    return hash;
}

// orient_tile_texcoord: bit 2 mirrors x, bits 0 and 1 then turn by
// quarters.
vec2 oriented_tile_texcoord(vec2 texcoord, uint hash)
{
    vec2 oriented = texcoord;
    if ((hash & 4u) != 0u)
    {
        oriented.x = 1.0 - oriented.x;
    }
    uint turns = hash & 3u;
    if (turns == 1u)
    {
        oriented = vec2(1.0 - oriented.y, oriented.x);
    }
    else if (turns == 2u)
    {
        oriented = 1.0 - oriented;
    }
    else if (turns == 3u)
    {
        oriented = vec2(oriented.y, 1.0 - oriented.x);
    }
    return min(oriented, vec2(largest_tile_texcoord));
}

// tile_offset: bits 3 to 6 for x, 7 to 10 for y, whole texels.
vec2 tile_offset(uint hash)
{
    return vec2(float((hash >> 3) & 15u), float((hash >> 7) & 15u));
}

// varied_tile_texcoord: oriented, clamped, slid by the offset and
// wrapped inside the tile, clamped again.
vec2 varied_tile_texcoord(vec2 texcoord, uint hash)
{
    vec2 shifted = fract(oriented_tile_texcoord(texcoord, hash) + tile_offset(hash) / tile_texels);
    return min(shifted, vec2(largest_tile_texcoord));
}

// texture_variation_brightness: bits 8 to 15.
float variation_brightness(uint hash)
{
    return 1.0 + brightness_jitter * (float((hash >> 8) & 255u) / 127.5 - 1.0);
}

void main()
{
    uint hash = variation_hash(fragment_cell());
    vec2 tile_texcoord = fract(fragment_texcoord);
    if (fragment_color.g < turn_only_green)
    {
        tile_texcoord = varied_tile_texcoord(tile_texcoord, hash);
    }
    else if (fragment_color.g < keep_orientation_green)
    {
        tile_texcoord = oriented_tile_texcoord(tile_texcoord, hash);
    }
    vec2 atlas_uv = fragment_tile_origin + tile_texcoord * tile_size;
    vec4 texel = texture(texture0, atlas_uv) * colDiffuse;
    if (texel.a < 0.5)
    {
        discard;
    }
    float cloud = texture(cloud_texture, (fragment_world_position.xz + cloud_offset) / cloud_tile_blocks).r;
    float cloud_shade = 1.0 - cloud_shadow_strength * cloud;
    float sky = light_curve(fragment_color.r) * day_factor * cloud_shade;
    vec3 light = sky * sky_tint + light_curve(fragment_block_light) * flicker;
    float shade = mix(darkest_occlusion_shade, 1.0, fragment_color.b);
    vec3 brightness = max(min(light, 1.0) * shade, minimum_brightness);
    float fog = clamp((fragment_distance - fog_start) / (fog_end - fog_start), 0.0, 1.0);
    finalColor = vec4(mix(texel.rgb * variation_brightness(hash) * brightness, fog_color, fog), 1.0);
}
