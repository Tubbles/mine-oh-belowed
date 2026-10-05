#version 330

// The arrival's flames on a porthole's glass (work items 0200, 0223,
// 0269, render_arrival.odin), drawn on a quad over each of the pod's
// windows during the descent with alpha blending. The disc inscribed in
// the quad is the glass; outside it nothing is drawn. The flames of the
// drag grow from its rim, highest on the edge the pod travels towards
// (texture y grows along the travel, so that edge leads), to a height
// that follows heat (0 to 1, the entry's heating): at heat 1, the drag's
// peak, the leading edge's reach the centre. Their shape is four octaves
// of value noise scrolling inwards, the octaves' scales and speeds in no
// small integer ratio, so the pattern never repeats; flame_seed shifts it
// per world and per window. A glow over the whole glass follows them.
// The tint follows the heat: rising (cooling 0) pink, then orange, white
// hot at the peak; falling (cooling 1, after the peak) white hot, orange,
// then a dull red. Both meet at white hot at heat 1, so the step of
// cooling at the peak shows nothing.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin): Winlator's Gladio appends .0 to a bare
// integer on any line with a float variable.

in vec2 fragment_texture_coordinate;

uniform float heat;
uniform float cooling;
uniform float seconds;
uniform float flame_seed;

out vec4 final_color;

const vec3 PINK = vec3(1.0, 0.42, 0.62);
const vec3 ORANGE = vec3(1.0, 0.5, 0.12);
const vec3 WHITE_HOT = vec3(1.0, 0.96, 0.88);
const vec3 DULL_RED = vec3(0.5, 0.07, 0.03);

float cell_hash(vec2 cell)
{
    return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 point)
{
    vec2 cell = floor(point);
    vec2 fraction = fract(point);
    vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
    float bottom = mix(cell_hash(cell), cell_hash(cell + vec2(1.0, 0.0)), blend.x);
    float top = mix(cell_hash(cell + vec2(0.0, 1.0)), cell_hash(cell + vec2(1.0, 1.0)), blend.x);
    return mix(bottom, top, blend.y);
}

// Four octaves scrolling inwards at their own speeds, 0 to 1.
float flame_noise(float along, float depth)
{
    float scales[4u] = float[4u](1.0, 2.03, 4.11, 8.37);
    float speeds[4u] = float[4u](1.0, 1.37, 1.91, 2.53);
    float total = 0.0;
    float weight = 0.5;
    float weights = 0.0;
    for (uint octave = 0u; octave < 4u; octave++)
    {
        vec2 point = vec2(along * 4.0, depth * 9.0 - seconds * 6.0 * speeds[octave]) * scales[octave];
        total += weight * value_noise(point + vec2(flame_seed * 97.0, flame_seed * 53.0));
        weights += weight;
        weight *= 0.5;
    }
    return total / weights;
}

void main()
{
    vec2 p = fragment_texture_coordinate - vec2(0.5);
    float d = length(p) - 0.5;
    if (d > 0.0)
    {
        discard;
    }
    float depth = -d;
    // p.y grows along the travel: that edge leads.
    float lead = clamp(0.5 + p.y, 0.0, 1.0);
    // At heat 1 the leading edge's flames reach the centre (depth 0.5),
    // the trailing edge's a third as far.
    float weight = mix(0.33, 1.0, lead);
    float along = atan(p.y, p.x) * 3.0;
    float n = flame_noise(along, depth);
    float height = heat * weight * (0.6 + 0.8 * n);
    float flame = 1.0 - smoothstep(0.0, max(height, 0.0001), depth);
    flame *= step(0.0001, heat);
    vec3 rising = mix(mix(PINK, ORANGE, smoothstep(0.0, 0.45, heat)), WHITE_HOT, smoothstep(0.45, 1.0, heat));
    vec3 falling = mix(mix(DULL_RED, ORANGE, smoothstep(0.0, 0.6, heat)), WHITE_HOT, smoothstep(0.6, 1.0, heat));
    vec3 tint = mix(rising, falling, cooling);
    vec3 color = mix(tint * 0.8, mix(tint, vec3(1.0, 0.97, 0.9), 0.5), flame * flame);
    float glow = 0.35 * heat;
    float alpha = flame + glow * (1.0 - flame);
    vec3 blended = (color * flame + tint * glow * (1.0 - flame)) / max(alpha, 0.0001);
    final_color = vec4(blended, alpha);
}
