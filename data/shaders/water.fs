#version 330

// Water fragment shader (work item 0065), drawn with alpha blending over
// everything solid (render_water.odin). Lit and fogged as the chunk
// shader does (chunk.fs, without the cloud shadows), then:
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
// The texcoords run along the face's own axes (world_mesh.odin: top and
// bottom faces z then x, faces along x y then z, faces along z x then y),
// so the flow, in world x and z, is turned into them by the face's
// normal.

in vec2 fragment_texcoord;
in vec2 fragment_tile_origin;
in vec4 fragment_color;
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

out vec4 finalColor;

const float minimum_brightness = 0.06;
const float darkest_occlusion_shade = 0.5;
const float tau = 6.28318531;
const float first_ripple_seconds = 2.5;
const float second_ripple_seconds = 4.0;

float light_curve(float level)
{
    return level / (4.0 - 3.0 * level);
}

// The flow's offset in the face's texcoords.
vec2 flow_texcoord_offset(vec2 flow_blocks)
{
    vec3 normal = abs(cross(dFdx(fragment_world_position), dFdy(fragment_world_position)));
    if (normal.y >= normal.x && normal.y >= normal.z)
    {
        return flow_blocks.yx;
    }
    if (normal.x >= normal.z)
    {
        return vec2(0.0, flow_blocks.y);
    }
    return vec2(flow_blocks.x, 0.0);
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
    vec2 offset = flow_texcoord_offset(fragment_flow * flow_speed * time);
    vec2 atlas_uv = fragment_tile_origin + fract(fragment_texcoord - offset) * tile_size;
    vec4 texel = texture(texture0, atlas_uv) * colDiffuse;
    vec2 position = fragment_world_position.xz;
    vec3 color = min(texel.rgb * (1.0 + ripple_strength * ripple(position)), 1.0);
    color = mix(color, vec3(1.0), foam_strength * foam(position));
    vec3 light = light_curve(fragment_color.r) * day_factor * sky_tint + light_curve(fragment_color.g);
    float shade = mix(darkest_occlusion_shade, 1.0, fragment_color.b);
    vec3 brightness = max(min(light, 1.0) * shade, minimum_brightness);
    float fog = clamp((fragment_distance - fog_start) / (fog_end - fog_start), 0.0, 1.0);
    finalColor = vec4(mix(color * brightness, fog_color, fog), water_alpha);
}
