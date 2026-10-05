#version 330

// The entry's plasma on a porthole's glass (work items 0200, 0223, 0269,
// 0270, 0273, render_arrival.odin), drawn on a quad over each of the
// pod's windows with alpha blending. The disc inscribed in the quad is
// the glass; outside it nothing is drawn. Following DESIGN.md, Fire, the
// plasma is a flow, never a shape: the stages of the descent are
// structures in one hue family, never hues. Black, then a pink haze
// (haze_color, the air's glow), sparks streaking in it, bright streaming
// at the peak with white only in its cores (ablator_color, the heat
// shield's), fading, then sooty glass. The heat (0 to 1) drives the
// brightness, the reach, the speed, the sparks and the alpha (1 near the
// peak, the sheath hiding the outside), never the hue. Everything streams
// aft along travel_on_glass (the travel in the quad's basis, which never
// turns). The noise's octaves and the spark grids have scales and speeds
// in no small integer ratio and flame_seed shifts them per world and per
// window, so nothing repeats; flicker (hashed noise without period,
// stilled under reduced motion) pulses the brightness. The soot (no time
// in it) grows from the rim inward after the peak to soot_opacity and
// stays in front of the plasma for good.
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

out vec4 final_color;

const vec3 WHITE_CORE = vec3(1.0, 0.97, 0.92);
const vec3 SOOT_COLOR = vec3(0.045, 0.038, 0.034);

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

// Octaves of value noise at scales in no small integer ratio, 0 to 1.
float fbm(vec2 point, uint octaves)
{
    float scales[4u] = float[4u](1.0, 2.13, 4.37, 8.71);
    float total = 0.0;
    float weight = 0.5;
    float weights = 0.0;
    for (uint octave = 0u; octave < octaves; octave++)
    {
        total += weight * value_noise(point * scales[octave] + vec2(float(octave) * 17.3, float(octave) * 29.1));
        weights += weight;
        weight *= 0.5;
    }
    return total / weights;
}

// The streaks' noise at one speed: four octaves stretched along the
// travel (the across scale seven times the along one) and scrolled aft,
// each octave at its own speed, 0 to 1.
float streak_noise(float across, float along, float speed, vec2 seed)
{
    float scales[4u] = float[4u](1.0, 2.13, 4.37, 8.71);
    float speeds[4u] = float[4u](0.43, 0.61, 0.89, 1.27);
    float total = 0.0;
    float weight = 0.5;
    float weights = 0.0;
    for (uint octave = 0u; octave < 4u; octave++)
    {
        vec2 point = vec2(across * 6.3, along * 0.9 + seconds * speed * speeds[octave]) * scales[octave];
        total += weight * value_noise(point + seed);
        weights += weight;
        weight *= 0.5;
    }
    return total / weights;
}

// One grid of sparks in flow space: a cell lights when its hash is below
// rate, its spark long along the travel at a hashed centre (0.4 to 0.6
// of the cell along the travel) and faded to 0 over the last 0.15 of
// the cell on each side along it, so no spark is cut at a cell's edge;
// returns the spark's value and writes its colour's white share.
float spark_layer(vec2 point, float rate, vec2 seed, out float white_share)
{
    vec2 cell = floor(point);
    vec2 inside = fract(point);
    float lit = cell_hash(cell + seed);
    white_share = cell_hash(cell + seed + vec2(7.7, 3.1));
    if (lit >= rate)
    {
        return 0.0;
    }
    vec2 centre = vec2(0.25, 0.4) + vec2(0.5, 0.2) * vec2(cell_hash(cell + seed + vec2(1.9, 5.3)), cell_hash(cell + seed + vec2(4.3, 2.7)));
    vec2 offset = inside - centre;
    float edge_fade = smoothstep(0.0, 0.15, inside.y) * smoothstep(0.0, 0.15, 1.0 - inside.y);
    return exp(-(offset.x * offset.x * 90.0 + offset.y * offset.y * 14.0)) * edge_fade;
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

    // The soot: no time in it, darkest at the rim, ragged inward.
    float soot_noise = fbm(q * 2.7 + seed, 3u);
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
    // across it, lightly warped.
    vec2 d = travel_on_glass;
    float along = dot(q, d);
    float across = q.x * d.y - q.y * d.x;
    float lead = 0.5 + 0.5 * along;
    across += 0.12 * (value_noise(vec2(across * 2.9, along * 1.7 + seconds * 0.37) + seed) - 0.5);

    // The streaks: a slow and a fast layer crossfaded by the heat, so the
    // speed follows it without the pattern running backwards.
    float slow = streak_noise(across, along, 0.55, seed);
    float fast = streak_noise(across, along, 2.35, seed + vec2(13.7, 41.9));
    float n = mix(slow, fast, smoothstep(0.2, 0.9, heat));
    float threshold = mix(0.66, 0.40, heat) - 0.08 * lead;
    float streak = smoothstep(threshold, threshold + 0.22, n) * smoothstep(0.1, 0.55, heat);
    float glow = 0.5 * smoothstep(threshold - 0.18, threshold + 0.3, n);
    float core = smoothstep(0.78, 0.95, n) * smoothstep(0.65, 1.0, heat);

    // The sparks: two hashed grids streaking aft, the brighter one kept.
    float spark_onset = smoothstep(0.22, 0.85, heat);
    float first_white;
    float second_white;
    float first = spark_layer(vec2(across * 11.0, along * 3.1 + seconds * 2.9), 0.22 * spark_onset, seed + vec2(3.3, 8.9), first_white);
    float second = spark_layer(vec2(across * 17.0, along * 4.7 + seconds * 4.3), 0.14 * spark_onset, seed + vec2(21.1, 5.7), second_white);
    float spark = max(first, second);
    float white_share = first >= second ? first_white : second_white;
    vec3 spark_color = mix(ablator_color, WHITE_CORE, 0.35 + 0.5 * white_share);

    // The haze and its veil: faint at the onset, 0.99 at heat 0.8.
    float haze_noise = fbm(vec2(across * 1.9, along * 0.7 + seconds * 0.31) + seed, 2u);
    float veil = 1.0 - pow(1.0 - heat, 3.0);

    // The colour: the two data colours and the structure alone.
    vec3 c = haze_color * mix(0.55, 1.0, haze_noise);
    c = mix(c, mix(haze_color, ablator_color, 0.7), streak);
    c += ablator_color * glow * 0.35 * heat;
    c = mix(c, WHITE_CORE, core);
    c = mix(c, spark_color, spark);
    c = min(c * flicker * (0.5 + 0.5 * heat), vec3(1.0));

    float plasma_alpha = clamp(veil + (1.0 - veil) * (0.6 * streak + spark), 0.0, 1.0);

    // The soot on the glass is in front of the plasma.
    float alpha = soot_alpha + plasma_alpha * (1.0 - soot_alpha);
    vec3 rgb = (SOOT_COLOR * soot_alpha + c * plasma_alpha * (1.0 - soot_alpha)) / max(alpha, 0.0001);
    final_color = vec4(rgb, alpha);
}
