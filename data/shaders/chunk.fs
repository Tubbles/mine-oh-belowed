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
//   g  unused
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

void main()
{
    vec2 atlas_uv = fragment_tile_origin + fract(fragment_texcoord) * tile_size;
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
    finalColor = vec4(mix(texel.rgb * brightness, fog_color, fog), 1.0);
}
