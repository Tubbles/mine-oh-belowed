#version 330

// Water fragment shader (work item 0065), drawn with alpha blending over
// everything solid (render_water.odin). Lit and fogged as the chunk
// shader does (chunk.fs, without the cloud shadows, with the flickering
// coloured block light), then:
//   the texel at water_alpha;
//   a ripple, two sine waves scrolling over the world x and z, lightens
//   the surface by up to ripple_strength (no geometry moves);
//   the texture runs along the flow at flow_speed blocks per second, so
//   flowing water visibly runs and a source only ripples;
//   foam where the shore value is high: lighter by up to foam_strength,
//   broken up by a pattern scrolling at foam_speed.
// time wraps after WATER_TIME_WRAP_SECONDS (render_water.odin), a whole
// number of both ripple periods.
//
// The texcoords run along the face's own axes (face_texcoord in
// world_mesh.odin: top and bottom faces x then z, faces along x z then
// down, faces along z x then down), so the flow, in world x and z, is
// turned into them by the face's normal.
//
// Per block variation (work item 0088, as in chunk.fs): the brightness
// jitter only. The tile keeps its orientation, since the flow scrolls
// along the face's own axes.

in vec2 fragment_texcoord;
in vec2 fragment_tile_origin;
in vec4 fragment_color;
in vec3 fragment_block_light;
in float fragment_distance;
in vec3 fragment_world_position;
in vec2 fragment_flow;
in float fragment_shore;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec2 tile_size;
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;
uniform float day_factor;
uniform vec3 sky_tint;
uniform float time;
uniform float water_alpha;
uniform float ripple_strength;
uniform float flow_speed;
uniform float foam_speed;
uniform float foam_strength;
uniform float flicker;

out vec4 finalColor;

const float minimum_brightness = 0.06;
const float darkest_occlusion_shade = 0.5;
const float tau = 6.28318531;
const float first_ripple_seconds = 2.5;
const float second_ripple_seconds = 4.0;
const float brightness_jitter = 0.04;
const float cell_depth = 0.01;

float light_curve(float level)
{
    return level / (4.0 - 3.0 * level);
}

vec3 light_curve(vec3 level)
{
    return level / (4.0 - 3.0 * level);
}

// The flow's offset in the face's texcoords.
vec2 flow_texcoord_offset(vec2 flow_blocks)
{
    vec3 normal = abs(cross(dFdx(fragment_world_position), dFdy(fragment_world_position)));
    if (normal.y >= normal.x && normal.y >= normal.z)
    {
        return flow_blocks;
    }
    if (normal.x >= normal.z)
    {
        return vec2(flow_blocks.y, 0.0);
    }
    return vec2(flow_blocks.x, 0.0);
}

// As in chunk.fs.
ivec3 fragment_cell()
{
    vec3 facing = cross(dFdx(fragment_world_position), dFdy(fragment_world_position));
    float length_squared = dot(facing, facing);
    vec3 towards_viewer = length_squared > 0.0 ? facing * inversesqrt(length_squared) : vec3(0.0);
    return ivec3(floor(fragment_world_position - towards_viewer * cell_depth));
}

// As in chunk.fs.
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

// As in chunk.fs.
float variation_brightness(uint hash)
{
    return 1.0 + brightness_jitter * (float((hash >> 8) & 255u) / 127.5 - 1.0);
}

// 0 to 1.
float ripple(vec2 position)
{
    float first = sin(dot(position, vec2(1.9, 0.8)) + time * tau / first_ripple_seconds);
    float second = sin(dot(position, vec2(-0.7, 1.6)) + time * tau / second_ripple_seconds);
    return 0.5 + 0.25 * (first + second);
}

// 0 to 1 at the shore, 0 in open water.
float foam(vec2 position)
{
    float band = smoothstep(0.35, 1.0, fragment_shore);
    float pattern = 0.5 + 0.5 * sin(dot(position, vec2(5.3, 4.1)) + time * foam_speed);
    return band * mix(0.5, 1.0, pattern);
}

void main()
{
    float variation = variation_brightness(variation_hash(fragment_cell()));
    vec2 offset = flow_texcoord_offset(fragment_flow * flow_speed * time);
    vec2 atlas_uv = fragment_tile_origin + fract(fragment_texcoord - offset) * tile_size;
    vec4 texel = texture(texture0, atlas_uv) * colDiffuse;
    vec2 position = fragment_world_position.xz;
    vec3 color = min(texel.rgb * variation * (1.0 + ripple_strength * ripple(position)), 1.0);
    color = mix(color, vec3(1.0), foam_strength * foam(position));
    float sky = light_curve(fragment_color.r) * day_factor;
    vec3 light = sky * sky_tint + light_curve(fragment_block_light) * flicker;
    float shade = mix(darkest_occlusion_shade, 1.0, fragment_color.b);
    vec3 brightness = max(min(light, 1.0) * shade, minimum_brightness);
    float fog = clamp((fragment_distance - fog_start) / (fog_end - fog_start), 0.0, 1.0);
    finalColor = vec4(mix(color * brightness, fog_color, fog), water_alpha);
}
