#version 330

// The portholes' soot (work items 0273, 0288, render_arrival.odin), drawn
// with alpha blending on the outer pane: the disc inscribed in a quad of
// the glass's radius, and outside it nothing is drawn. The soot (no
// time in it) grows from the rim inward after the heat's peak to
// soot_opacity and stays on the pane for good. flame_seed shifts its
// noise per world and per window. The entry's plasma moved to the wake
// outside the pod (arrival_wake.fs, 0304).
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin): Winlator's Gladio appends .0 to a bare
// integer on any line with a float variable.

in vec2 fragment_texture_coordinate;

uniform float soot;
uniform float soot_opacity;
uniform float flame_seed;

out vec4 final_color;

const vec3 SOOT_COLOR = vec3(0.045, 0.038, 0.034);

// An integer hash of a noise cell, 0 to 1 (as flame.fs's, in three
// axes), exact for any cell.
float cell_hash(uvec3 cell)
{
    uint hash = (cell.x * 73856093u) ^ (cell.y * 19349663u) ^ (cell.z * 83492791u);
    hash ^= hash >> 16u;
    hash *= 0x7feb352du;
    hash ^= hash >> 15u;
    hash *= 0x846ca68bu;
    hash ^= hash >> 16u;
    return float(hash >> 8u) / 16777215.0;
}

// Value noise in two axes, the corners at the third axis's cell 0.
float value_noise(vec2 point)
{
    uvec2 cell = uvec2(ivec2(floor(point)));
    vec2 fraction = fract(point);
    vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
    float bottom = mix(cell_hash(uvec3(cell, 0u)), cell_hash(uvec3(cell + uvec2(1u, 0u), 0u)), blend.x);
    float top = mix(cell_hash(uvec3(cell + uvec2(0u, 1u), 0u)), cell_hash(uvec3(cell + uvec2(1u, 1u), 0u)), blend.x);
    return mix(bottom, top, blend.y);
}

// Three octaves of value noise at scales in no small integer ratio, 0
// to 1 (the soot's, no time in it).
float soot_fbm(vec2 point)
{
    float scales[3u] = float[3u](1.0, 2.13, 4.37);
    float total = 0.0;
    float weight = 0.5;
    float weights = 0.0;
    for (uint octave = 0u; octave < 3u; octave++)
    {
        total += weight * value_noise(point * scales[octave] + vec2(float(octave) * 17.3, float(octave) * 29.1));
        weights += weight;
        weight *= 0.5;
    }
    return total / weights;
}

// The soot on the pane: no time in it, darkest at the rim, ragged
// inward.
void main()
{
    vec2 q = (fragment_texture_coordinate - vec2(0.5)) * 2.0;
    vec2 seed = vec2(flame_seed * 97.0, flame_seed * 53.0);
    float r = length(q);
    if (r > 1.0)
    {
        discard;
    }
    float soot_noise = soot_fbm(q * 2.7 + seed);
    float reach = mix(0.12, 0.55, soot);
    float soot_alpha = soot_opacity * soot * smoothstep(1.0 - reach - 0.15, 1.0, r + 0.3 * (soot_noise - 0.5));
    if (soot_alpha < 0.002)
    {
        discard;
    }
    final_color = vec4(SOOT_COLOR, soot_alpha);
}
