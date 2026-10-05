#version 330

// The entry's plasma on a porthole's glass (work items 0200, 0223, 0269,
// 0270, 0273, 0286, render_arrival.odin), drawn on a quad over each of
// the pod's windows with alpha blending. The disc inscribed in the quad
// is the glass, and outside it nothing is drawn. Following DESIGN.md,
// Fire, the plasma is a flow: a haze over the whole glass, brightest at
// the leading edge, tongues and sparks streaming aft along
// travel_on_glass (the travel in the quad's basis, which never turns).
// The colour is a fixed ramp of the two data colours read by the local
// intensity (plasma_ramp: dim violet, the haze's pink, salmon, the
// ablator's orange, white), so the heat, the tongues and the flicker move
// the brightness and with it the place on the ramp, and patches richer in
// the ablator's products run higher. The tongues are value noise in three
// axes (across, along scrolled aft, time), so they change shape as they
// go and live a fraction of a second. A slow and a fast layer are
// crossfaded by the heat. The sparks appear, streak and burn out on the
// glass. The flicker (fire_flicker, 0.4 to 1.5, hashed without period,
// its mean under reduced motion) raises the brightness, the tongues'
// reach and the sparks' rate together. Under reduced motion (calm 1) the
// flow runs at its slow layer, with its morph, its warp and the sparks
// at 0.4 of their pace. The heat drives the alpha (1 near the peak, the
// sheath hiding the outside). flame_seed shifts every noise per world and
// per window. The soot (no time in it) grows from the rim inward after
// the peak to soot_opacity and stays in front of the plasma for good.
// seconds is the fall's own clock, under 32 s, so a float holds it.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin): Winlator's Gladio appends .0 to a bare
// integer on any line with a float variable.

in vec2 fragment_texture_coordinate;

uniform float heat;
uniform float soot;
uniform float soot_opacity;
uniform float seconds;
uniform float flame_seed;
uniform float flicker;
uniform vec2 travel_on_glass;
uniform vec3 haze_color;
uniform vec3 ablator_color;
uniform float calm;

out vec4 final_color;

// The flicker's mean, FIRE_FLICKER_MEAN in render_flames.odin.
const float FLICKER_MEAN = 0.85;
const vec3 WHITE_CORE = vec3(1.0, 0.97, 0.92);
const vec3 SOOT_COLOR = vec3(0.045, 0.038, 0.034);
// The dim haze: the haze colour times this, darker and bluer (the
// ionised nitrogen's blue lines).
const vec3 VIOLET_SHADE = vec3(0.42, 0.30, 0.66);
// The flow's speeds aft in glass radii a second: at the peak a feature
// crosses the glass in 0.36 s.
const float SLOW_FLOW = 1.4;
const float FAST_FLOW = 5.5;

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

// Value noise in three axes, trilinear between the hashed corners with a
// smooth blend, 0 to 1.
float value_noise(vec3 point)
{
    uvec3 cell = uvec3(ivec3(floor(point)));
    vec3 fraction = fract(point);
    vec3 blend = fraction * fraction * (3.0 - 2.0 * fraction);
    float near_bottom = mix(cell_hash(cell), cell_hash(cell + uvec3(1u, 0u, 0u)), blend.x);
    float near_top = mix(cell_hash(cell + uvec3(0u, 1u, 0u)), cell_hash(cell + uvec3(1u, 1u, 0u)), blend.x);
    float far_bottom = mix(cell_hash(cell + uvec3(0u, 0u, 1u)), cell_hash(cell + uvec3(1u, 0u, 1u)), blend.x);
    float far_top = mix(cell_hash(cell + uvec3(0u, 1u, 1u)), cell_hash(cell + uvec3(1u, 1u, 1u)), blend.x);
    return mix(mix(near_bottom, near_top, blend.y), mix(far_bottom, far_top, blend.y), blend.z);
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

// The tongues' noise at one speed: three octaves stretched along the
// travel (the across scale seven times the along one), all scrolled aft
// at the one speed (the flow carries its eddies) and each morphing in
// time at its own rate, so a tongue of each octave lives about 0.43,
// 0.26 and 0.15 s. 0 to 1.
float streak_noise(float across, float along, float speed, vec3 seed, float pace)
{
    float scales[3u] = float[3u](1.0, 2.13, 4.37);
    float morphs[3u] = float[3u](2.3, 3.9, 6.7);
    float total = 0.0;
    float weight = 0.5;
    float weights = 0.0;
    for (uint octave = 0u; octave < 3u; octave++)
    {
        float scale = scales[octave];
        vec3 point = vec3(across * 6.3 * scale, (along + seconds * speed) * 0.9 * scale, seconds * morphs[octave] * pace + float(octave) * 7.1);
        total += weight * value_noise(point + seed + vec3(float(octave) * 17.3, float(octave) * 29.1, 0.0));
        weights += weight;
        weight *= 0.5;
    }
    return total / weights;
}

// One grid of sparks in flow space: each cell's spark lives one unit of
// age (seconds times life_rate, offset per cell), and in each life it
// lights when its hash is below rate, at a hashed centre, long along the
// travel, faded over the last 0.15 of the cell on each side along it so
// no spark is cut at a cell's edge, appearing and burning out over its
// life. Returns the spark's value and writes its colour's white share.
float spark_layer(vec2 point, float rate, float life_rate, vec2 seed, float pace, out float white_share)
{
    vec2 shifted = point + seed;
    uvec2 cell = uvec2(ivec2(floor(shifted)));
    vec2 inside = fract(shifted);
    float age = seconds * life_rate * pace + cell_hash(uvec3(cell, 0xffffffffu));
    uint epoch = uint(int(floor(age)));
    float life = fract(age);
    float lit = cell_hash(uvec3(cell, epoch * 4u));
    white_share = cell_hash(uvec3(cell, epoch * 4u + 1u));
    if (lit >= rate)
    {
        return 0.0;
    }
    vec2 centre = vec2(0.25, 0.42) + vec2(0.5, 0.16) * vec2(cell_hash(uvec3(cell, epoch * 4u + 2u)), cell_hash(uvec3(cell, epoch * 4u + 3u)));
    vec2 offset = inside - centre;
    float edge_fade = smoothstep(0.0, 0.15, inside.y) * smoothstep(0.0, 0.15, 1.0 - inside.y);
    float envelope = smoothstep(0.0, 0.2, life) * (1.0 - smoothstep(0.55, 1.0, life));
    return exp(-(offset.x * offset.x * 90.0 + offset.y * offset.y * 9.0)) * edge_fade * envelope;
}

// The fire's ramp by the local intensity: dim violet, the haze's pink,
// salmon, the ablator's orange, white.
vec3 plasma_ramp(float intensity)
{
    vec3 dim = haze_color * VIOLET_SHADE;
    vec3 salmon = mix(haze_color, ablator_color, 0.55);
    vec3 c = mix(dim, haze_color, smoothstep(0.05, 0.4, intensity));
    c = mix(c, salmon, smoothstep(0.4, 0.75, intensity));
    c = mix(c, ablator_color, smoothstep(0.7, 1.0, intensity));
    return mix(c, WHITE_CORE, smoothstep(1.05, 1.6, intensity));
}

void main()
{
    vec2 q = (fragment_texture_coordinate - vec2(0.5)) * 2.0;
    float r = length(q);
    if (r > 1.0)
    {
        discard;
    }
    vec2 seed = vec2(flame_seed * 97.0, flame_seed * 53.0);
    vec3 seed3 = vec3(seed, flame_seed * 71.0);
    float pace = calm > 0.5 ? 0.4 : 1.0;

    // The soot: no time in it, darkest at the rim, ragged inward.
    float soot_noise = soot_fbm(q * 2.7 + seed);
    float reach = mix(0.12, 0.55, soot);
    float soot_alpha = soot_opacity * soot * smoothstep(1.0 - reach - 0.15, 1.0, r + 0.3 * (soot_noise - 0.5));
    if (heat <= 0.0)
    {
        if (soot_alpha < 0.002)
        {
            discard;
        }
        final_color = vec4(SOOT_COLOR, soot_alpha);
        return;
    }

    // The flow's coordinates: along the travel (+1 the leading edge) and
    // across it, warped so the tongues lick sideways.
    vec2 d = travel_on_glass;
    float along = dot(q, d);
    float across = q.x * d.y - q.y * d.x;
    float lead = 0.5 + 0.5 * along;
    across += 0.16 * (value_noise(vec3(across * 2.9, (along + seconds * 3.0 * pace) * 1.7, seconds * 3.1 * pace) + seed3 + vec3(31.7, 3.9, 0.0)) - 0.5);

    // The tongues: a slow and a fast layer crossfaded by the heat, so the
    // speed follows it without the pattern running backwards, the mix's
    // contrast restored (an even mix of two fields flattens).
    float fast_share = calm > 0.5 ? 0.0 : smoothstep(0.2, 0.9, heat);
    float n = streak_noise(across, along, SLOW_FLOW * pace, seed3, pace);
    if (fast_share > 0.0)
    {
        float fast = streak_noise(across, along, FAST_FLOW, seed3 + vec3(13.7, 41.9, 5.3), pace);
        n = mix(n, fast, fast_share);
        n = clamp(0.5 + (n - 0.5) * inversesqrt(fast_share * fast_share + (1.0 - fast_share) * (1.0 - fast_share)), 0.0, 1.0);
    }

    // A flare lengthens the tongues and thickens their cores, a dip
    // shortens them.
    float flare = flicker - FLICKER_MEAN;
    float threshold = mix(0.68, 0.38, heat) - 0.14 * lead - 0.22 * flare;
    float streak = smoothstep(threshold, threshold + 0.18, n) * smoothstep(0.1, 0.55, heat);
    float core = smoothstep(0.62, 0.8, n + 0.1 * lead + 0.15 * flare) * smoothstep(0.55, 1.0, heat);

    // The haze over the whole glass, the leading edge brightest.
    float haze_along = along + seconds * 1.1 * pace;
    float haze_noise = 0.65 * value_noise(vec3(across * 1.9, haze_along * 0.7, seconds * 0.8 * pace) + seed3) + 0.35 * value_noise(vec3(across * 4.1, haze_along * 1.5, seconds * 1.7 * pace) + seed3 + vec3(17.3, 29.1, 0.0));
    float haze_level = mix(0.18, 0.42, haze_noise) * smoothstep(0.0, 0.35, heat) + 0.18 * heat * lead;

    // The colour: the ramp read by the intensity, patches richer in the
    // ablator's products running higher.
    float chemistry = value_noise(vec3(across * 1.7, (along + seconds * 3.0 * pace) * 0.8, seconds * 1.3 * pace) + seed3 + vec3(5.1, 9.7, 0.0));
    float intensity = (haze_level + 0.55 * streak + 0.45 * core) * flicker * (0.55 + 0.6 * heat);
    vec3 c = plasma_ramp(intensity + 0.18 * (chemistry - 0.5)) * clamp(0.35 + 0.75 * intensity, 0.0, 1.15);

    // The sparks: two hashed grids streaking aft, a flare bringing a
    // shower, the brighter one kept.
    float spark_rate = smoothstep(0.22, 0.85, heat) * (0.5 + 0.6 * flicker);
    float first_white;
    float second_white;
    float first = spark_layer(vec2(across * 11.0, (along + seconds * 7.5 * pace) * 3.1), 0.22 * spark_rate, 4.5, seed + vec2(3.3, 8.9), pace, first_white);
    float second = spark_layer(vec2(across * 17.0, (along + seconds * 10.5 * pace) * 4.7), 0.14 * spark_rate, 6.5, seed + vec2(21.1, 5.7), pace, second_white);
    float spark = max(first, second);
    float white_share = first >= second ? first_white : second_white;
    vec3 spark_color = mix(ablator_color, WHITE_CORE, 0.35 + 0.5 * white_share) * (0.8 + 0.3 * flicker);
    c = min(mix(c, spark_color, spark), vec3(1.0));

    // The veil: faint at the onset, 0.99 at heat 0.8.
    float veil = 1.0 - pow(1.0 - heat, 3.0);
    float plasma_alpha = clamp(veil + (1.0 - veil) * (0.6 * streak + spark), 0.0, 1.0);

    // The soot on the glass is in front of the plasma.
    float alpha = soot_alpha + plasma_alpha * (1.0 - soot_alpha);
    vec3 rgb = (SOOT_COLOR * soot_alpha + c * plasma_alpha * (1.0 - soot_alpha)) / max(alpha, 0.0001);
    final_color = vec4(rgb, alpha);
}
