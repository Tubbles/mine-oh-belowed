#version 330

// The flames of the furnace and the torch (work item 0274, DESIGN.md,
// Fire, render_flames.odin): one shader for every burning fuel, drawn on
// a quad standing on the tongue's base with premultiplied blending (one,
// one minus source alpha), so overlapping quads need no sorting.
//
// The flow is fractal value noise rising up the quad, its octaves'
// scales and speeds in no small integer ratio, so it never repeats;
// flame_seed shifts it per flame. A slower noise bends the tongue more
// the higher it reaches. A teardrop mask shapes it, the density is eaten
// from the top, and a continuous ramp runs from the dark red tips
// through the orange body to the yellow white core. A soft halo glows
// round it. The flicker (0.4 to 1.5, fire_flicker in render_flames.odin)
// moves the reach, the brightness and the place on the ramp, hotter
// whiter, and only the flow reads the clock here. The flicker, the
// seed and the height over the width come per quad from flame.vs. Under
// reduced motion (calm 1) only the flow's slowest octave rises and the
// bend stands still.
//
// seconds comes as the whole seconds and the fraction: each octave's
// scroll is split into whole noise cells (an integer, offsetting the
// integer cell hash) and a rest (scroll_at: the remainder of the whole
// seconds, under one cell, plus the fraction times the speed), under
// 12.9 cells for the fastest speed (1182 hundredths) and 4.7 for the
// flow's (361), so the flow keeps its precision and never wraps however
// long the clock runs.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin): Winlator's Gladio appends .0 to a bare
// integer on any line with a float variable.

in vec2 fragment_texture_coordinate;
flat in float fragment_flicker;
flat in float fragment_seed;
flat in float fragment_aspect;

uniform vec2 seconds;
uniform float calm;
uniform vec3 core_color;
uniform vec3 body_color;
uniform vec3 tip_color;

out vec4 final_color;

// The flicker's mean, FIRE_FLICKER_MEAN in render_flames.odin.
const float fire_flicker_mean = 0.85;

// The rise of each octave in hundredths of a noise cell a second: the
// flow's 1.13, 1.71, 2.47 and 3.61, and the bend's, those plus its own
// drift of 0.93 at each octave's scale.
const uvec4 RISE_HUNDREDTHS = uvec4(113u, 171u, 247u, 361u);
const uvec4 BEND_HUNDREDTHS = uvec4(206u, 364u, 648u, 1182u);

// An integer hash of a noise cell, 0 to 1 (as chunk.fs's variation
// hash), exact for any cell.
float cell_hash(uvec2 cell)
{
    uint hash = (cell.x * 73856093u) ^ (cell.y * 19349663u);
    hash ^= hash >> 16u;
    hash *= 0x7feb352du;
    hash ^= hash >> 15u;
    hash *= 0x846ca68bu;
    hash ^= hash >> 16u;
    return float(hash >> 8u) / 16777215.0;
}

// Value noise at point, its cells lowered by lift whole cells.
float value_noise(vec2 point, uint lift)
{
    vec2 floored = floor(point);
    uvec2 cell = uvec2(ivec2(floored)) - uvec2(0u, lift);
    vec2 fraction = point - floored;
    vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
    float bottom = mix(cell_hash(cell), cell_hash(cell + uvec2(1u, 0u)), blend.x);
    float top = mix(cell_hash(cell + uvec2(0u, 1u)), cell_hash(cell + uvec2(1u, 1u)), blend.x);
    return mix(bottom, top, blend.y);
}

// The seconds times hundredths / 100 noise cells: the whole cells, exact
// in integers, and the rest.
void scroll_at(uint hundredths, out uint whole_cells, out float rest)
{
    uint whole = uint(seconds.x);
    uint high = whole / 100u;
    uint low_product = (whole - high * 100u) * hundredths;
    whole_cells = high * hundredths + low_product / 100u;
    rest = float(low_product % 100u) / 100.0 + seconds.y * float(hundredths) / 100.0;
}

// Up to four octaves, the first moving ones rising at their own speeds
// and the rest still, 0 to 1.
float fbm(vec2 point, uint octaves, uint moving, uvec4 hundredths)
{
    float scales[4u] = float[4u](1.0, 2.07, 4.31, 8.83);
    float total = 0.0;
    float weight = 0.5;
    float weights = 0.0;
    for (uint octave = 0u; octave < octaves; octave++)
    {
        uint lift = 0u;
        float rest = 0.0;
        if (octave < moving)
        {
            scroll_at(hundredths[octave], lift, rest);
        }
        total += weight * value_noise(point * scales[octave] - vec2(0.0, rest), lift);
        weights += weight;
        weight *= 0.5;
    }
    return total / weights;
}

void main()
{
    vec2 uv = fragment_texture_coordinate;
    float flicker = fragment_flicker;
    float aspect = fragment_aspect;
    float flame_seed = fragment_seed;
    bool still = calm > 0.5;
    // The reach follows the flicker: the highest flare fills the quad.
    float h = uv.y / (0.82 + 0.12 * flicker);
    if (h >= 1.0)
    {
        discard;
    }
    // The flow's coordinates, unstretched on any quad.
    vec2 q = vec2(uv.x - 0.5, uv.y * aspect);
    vec2 s = vec2(flame_seed * 97.0, flame_seed * 53.0);
    // The bend grows with the height.
    float w = fbm(q * vec2(2.3, 1.6) + s, 2u, still ? 0u : 2u, BEND_HUNDREDTHS);
    float x = (uv.x - 0.5) * 2.0 + 0.55 * h * sqrt(h) * (w - 0.5);
    q.x += 0.25 * h * (w - 0.5);
    // The teardrop, widest at a third of the height.
    float width = 2.6 * sqrt(h) * (1.0 - h);
    float m = (1.0 - smoothstep(0.45 * width, width + 0.02, abs(x))) * smoothstep(0.0, 0.06, h);
    float n = fbm(q * 2.3 + s, 4u, still ? 1u : 4u, RISE_HUNDREDTHS);
    // The density, eaten from the top.
    float d = clamp(m * (1.35 * n + 0.62 - 1.15 * h), 0.0, 1.0);
    // The ramp: tips, body, core, the flicker moving the place on it.
    float heat = clamp(d * (1.2 - 0.6 * h) * flicker / fire_flicker_mean, 0.0, 1.0);
    vec3 c = mix(tip_color, body_color, smoothstep(0.08, 0.5, heat));
    c = mix(c, core_color, smoothstep(0.55, 0.95, heat));
    float halo = 0.22 * (1.0 - smoothstep(0.0, width * 1.7 + 0.12, abs(x))) * (1.0 - h) * smoothstep(0.0, 0.12, h);
    // Premultiplied: the light adds, the body hides 60 percent behind it.
    vec3 rgb = (c * d + body_color * halo) * flicker;
    if (max(rgb.r, max(rgb.g, rgb.b)) < 0.003)
    {
        discard;
    }
    final_color = vec4(rgb, 0.6 * d);
}
