#version 330

// The entry's wake (work item 0304, render_arrival_wake.odin), drawn
// premultiplied (one, one minus source alpha) in two layers. layer 0 is
// the tube streaming straight aft from the heat shield's rim: texture x
// the share of the turn round the pod's axis (0 to 1), y the cells along
// the flow from the rim. layer 1 is the shield's glow, the disc under
// the base: x the share of the turn, y the share of the radius. The
// wake is an emitting and absorbing shell: the intensity on the view's
// path through it is the face's over the cosine between the view and
// the wall's normal (floored at COS_FLOOR), so the silhouettes run
// brighter and the face, seen through a porthole or over the cone, is
// the thinnest; the opacity is 1 - exp(-opacity_scale * intensity).
// The face's light halves every half_light_cells along the flow and is
// gone over the last quarter of length_cells, so no end shows.
// Following DESIGN.md, Fire, the look is 0288's sheath carried onto the
// tube in cells: the tongues (a slow and a fast layer crossfaded by the
// heat), the haze, the chemistry and the sparks streaming aft, the
// colour a fixed ramp of the two data colours read by the local
// intensity (plasma_ramp), the flicker (fire_flicker, one for the wake)
// raising the brightness, the tongues' reach and the sparks' rate
// together. Round the tube every noise wraps a whole number of its cells
// (wrapped_noise), so the seam never shows, and the finer octaves and
// the sparks fade where a noise cell would cover under 3 px (detail), so
// the tube seen from afar does not shimmer. Under reduced motion (calm
// 1) the flow runs at CALM_FLOW, with its morph, its warp and the sparks
// at 0.4 of their pace. flame_seed shifts every noise per world.
// seconds is the fall's own clock, under 32 s, so a float holds it.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin): Winlator's Gladio appends .0 to a bare
// integer on any line with a float variable.

in vec2 fragment_texture_coordinate;
in vec3 fragment_position;

uniform float heat;
uniform float seconds;
uniform float flicker;
uniform float calm;
uniform float flame_seed;
uniform float layer;
uniform float opacity_scale;
uniform float circumference_cells;
uniform float half_light_cells;
uniform float length_cells;
uniform vec3 eye_position;
uniform vec3 wake_origin;
uniform vec3 wake_axis;
uniform vec3 haze_color;
uniform vec3 ablator_color;

out vec4 final_color;

// The flicker's mean, FIRE_FLICKER_MEAN in render_flames.odin.
const float FLICKER_MEAN = 0.85;
const vec3 WHITE_CORE = vec3(1.0, 0.97, 0.92);
// The dim haze: the haze colour times this, darker and bluer (the
// ionised nitrogen's blue lines).
const vec3 VIOLET_SHADE = vec3(0.42, 0.30, 0.66);
// The flow's speeds aft in cells a second, 0288's in glass radii times
// the 0.385 cells a glass radius spans on the wall the chair's porthole
// frames (0304), from Orion's window footage, where a streak never shows
// in two frames at 30 fps: under reduced motion, at the onset and the
// fade, and at the peak, where a feature crosses the porthole's 0.78
// cells of the wake in about 3.3 ticks.
const float CALM_FLOW = 0.22;
const float SLOW_FLOW = 4.7;
const float FAST_FLOW = 14.0;
// The sparks' speeds aft in cells a second and their lives a second,
// slow and fast grid: lives of 4 and 3 ticks, about the footage's one
// frame trails, the speeds crossing the porthole's patch in 2 to 4
// ticks; under reduced motion the calm speeds.
const float SPARK_FLOW = 12.5;
const float SPARK_FAST_FLOW = 17.0;
const float SPARK_CALM_FLOW = 2.9;
const float SPARK_CALM_FAST_FLOW = 4.0;
const float SPARK_LIFE = 15.0;
const float SPARK_FAST_LIFE = 20.0;
// A spark's trail e-folds over this share of its cell, towards the rim.
const float SPARK_TAIL = 8.0;
// The haze's lift where the flow leaves the rim at heat 1.
const float HAZE_LEAD = 0.26;
// The tongues' noise cells a cell at the first octave, round the tube
// and along it: the first octave's streaks run 2.5 cells (straight and
// long from outside) and the third's 0.57 (the motion through the
// porthole's 0.78 cells).
const float STREAK_ACROSS = 8.0;
const float STREAK_ALONG = 0.4;
// The face's gain: the chair's porthole looks at the wall 4.21 cells aft
// of the rim nearly face on (cos 0.904) and reads 0288's intensity
// there at the peak, 0.904 / 2^(-4.21 / 2.725).
const float WAKE_GAIN = 2.64;
// The path through the shell grows as one over the cosine between the
// view and the wall's normal, floored here, so a silhouette runs at
// most 2.9 times the face's intensity.
const float COS_FLOOR = 0.35;

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

// The whole number of noise cells round the tube at frequency cells a
// cell, at least one.
uint wake_period(float frequency)
{
    return uint(max(floor(circumference_cells * frequency + 0.5), 1.0));
}

// The share of the turn as noise cells round the tube at frequency,
// moved off 0 so a small warp below it stays positive.
float round_tube(float share, float frequency)
{
    return share * float(wake_period(frequency)) + 4.0;
}

// 1 where a noise cell at frequency covers 3 px or more of the
// footprint (cells a pixel round the tube), fading to 0 under about 1.4.
float detail(float footprint, float frequency)
{
    return 1.0 - smoothstep(0.35, 0.7, footprint * frequency);
}

// Value noise in three axes, trilinear between the hashed corners with a
// smooth blend, 0 to 1, its x cells wrapping every period.
float wrapped_noise(vec3 point, uint period)
{
    vec3 base = floor(point);
    vec3 fraction = point - base;
    vec3 blend = fraction * fraction * (3.0 - 2.0 * fraction);
    uint x0 = uint(base.x) % period;
    uint x1 = (x0 + 1u) % period;
    uint y0 = uint(int(base.y));
    uint z0 = uint(int(base.z));
    uint y1 = y0 + 1u;
    uint z1 = z0 + 1u;
    float near_bottom = mix(cell_hash(uvec3(x0, y0, z0)), cell_hash(uvec3(x1, y0, z0)), blend.x);
    float near_top = mix(cell_hash(uvec3(x0, y1, z0)), cell_hash(uvec3(x1, y1, z0)), blend.x);
    float far_bottom = mix(cell_hash(uvec3(x0, y0, z1)), cell_hash(uvec3(x1, y0, z1)), blend.x);
    float far_top = mix(cell_hash(uvec3(x0, y1, z1)), cell_hash(uvec3(x1, y1, z1)), blend.x);
    return mix(mix(near_bottom, near_top, blend.y), mix(far_bottom, far_top, blend.y), blend.z);
}

// The tongues' noise at one speed: three octaves stretched along the
// flow, all scrolled aft at the one speed (the flow carries its eddies)
// and each morphing in time at its own rate, so a tongue of each octave
// lives about 0.43, 0.26 and 0.15 s; an octave finer than the footprint
// fades to its mean. 0 to 1.
float streak_noise(float share, float along, float speed, vec3 seed, float pace, float footprint)
{
    float scales[3u] = float[3u](1.0, 2.13, 4.37);
    float morphs[3u] = float[3u](2.3, 3.9, 6.7);
    float total = 0.0;
    float weight = 0.5;
    float weights = 0.0;
    for (uint octave = 0u; octave < 3u; octave++)
    {
        float frequency = STREAK_ACROSS * scales[octave];
        vec3 point = vec3(round_tube(share, frequency), (along - seconds * speed) * STREAK_ALONG * scales[octave], seconds * morphs[octave] * pace + float(octave) * 7.1);
        float value = wrapped_noise(point + seed + vec3(float(octave) * 17.3, float(octave) * 29.1, 0.0), wake_period(frequency));
        total += weight * mix(0.5, value, detail(footprint, frequency));
        weights += weight;
        weight *= 0.5;
    }
    return total / weights;
}

// One grid of sparks in flow space, its x cells wrapping every period:
// each cell's spark lives one unit of age (seconds times life_rate,
// offset per cell), and in each life it lights when its hash is below
// rate, at a hashed centre, a trail with its head downstream (+y, aft)
// and its tail towards the rim, faded over the last 0.15 of the cell on
// each side along it so no spark is cut at a cell's edge, appearing and
// burning out over its life. Returns the spark's value and writes its
// colour's white share.
float spark_layer(vec2 point, uint period, float rate, float life_rate, vec2 seed, float pace, out float white_share)
{
    vec2 shifted = point + seed + vec2(4.0, 0.0);
    vec2 base = floor(shifted);
    uvec2 cell = uvec2(uint(base.x) % period, uint(int(base.y)));
    vec2 inside = shifted - base;
    float age = seconds * life_rate * pace + cell_hash(uvec3(cell, 0xffffffffu));
    uint epoch = uint(int(floor(age)));
    float life = fract(age);
    float lit = cell_hash(uvec3(cell, epoch * 4u));
    white_share = cell_hash(uvec3(cell, epoch * 4u + 1u));
    if (lit >= rate)
    {
        return 0.0;
    }
    vec2 centre = vec2(0.25, 0.68) + vec2(0.5, 0.2) * vec2(cell_hash(uvec3(cell, epoch * 4u + 2u)), cell_hash(uvec3(cell, epoch * 4u + 3u)));
    vec2 offset = inside - centre;
    float edge_fade = smoothstep(0.0, 0.15, inside.y) * smoothstep(0.0, 0.15, 1.0 - inside.y);
    float envelope = smoothstep(0.0, 0.2, life) * (1.0 - smoothstep(0.55, 1.0, life));
    float trail = offset.y > 0.0 ? exp(-offset.y * offset.y * 400.0) : exp(offset.y * SPARK_TAIL);
    return exp(-offset.x * offset.x * 90.0) * trail * edge_fade * envelope;
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

// The shell's colour and opacity at the intensity on the view's path,
// patches richer in the ablator's products running higher on the ramp;
// not premultiplied.
vec4 shell(float intensity, float chemistry)
{
    vec3 c = plasma_ramp(intensity + 0.18 * (chemistry - 0.5)) * clamp(0.35 + 0.75 * intensity, 0.0, 1.15);
    float alpha = 1.0 - exp(-opacity_scale * intensity);
    return vec4(c, alpha);
}

void main()
{
    float share = fragment_texture_coordinate.x;
    float along = fragment_texture_coordinate.y;
    vec3 offset = fragment_position - wake_origin;
    vec3 view = normalize(eye_position - fragment_position);
    float footprint = fwidth(share * circumference_cells);
    float pace = calm > 0.5 ? 0.4 : 1.0;
    float slow_speed = calm > 0.5 ? CALM_FLOW : SLOW_FLOW;
    vec3 seed3 = vec3(flame_seed * 97.0, flame_seed * 53.0, flame_seed * 71.0);
    float heat_light = flicker * (0.55 + 0.6 * heat);

    // The shield's glow under the base: brightest at the centre, seen
    // through the disc's thickness along the axis.
    if (layer > 0.5)
    {
        float glow = wrapped_noise(vec3(round_tube(share, 1.0), along * 3.0, seconds * 2.3 * pace) + seed3, wake_period(1.0));
        float face = (1.25 - 0.35 * along * along + 0.2 * (glow - 0.5)) * smoothstep(0.0, 0.35, heat) * heat_light;
        vec4 shield = shell(face / max(abs(dot(view, wake_axis)), COS_FLOOR), glow);
        final_color = vec4(shield.rgb * shield.a, shield.a);
        return;
    }

    // The path through the wall, the light's fall along the flow (1 at
    // the rim) and the end's fade, the across warped so the tongues lick
    // sideways, the fast wake straighter.
    vec3 radial = offset - wake_axis * dot(offset, wake_axis);
    float path = 1.0 / max(abs(dot(view, normalize(radial))), COS_FLOOR);
    float fast_share = calm > 0.5 ? 0.0 : smoothstep(0.2, 0.9, heat);
    float lead = exp2(-along / half_light_cells);
    float end = 1.0 - smoothstep(0.75 * length_cells, length_cells, along);
    float warp = 0.06 * (1.0 - 0.7 * fast_share) * (wrapped_noise(vec3(round_tube(share, 3.0), (along - seconds * slow_speed) * 0.6, seconds * 3.1 * pace) + seed3 + vec3(31.7, 3.9, 0.0), wake_period(3.0)) - 0.5);
    float warped = share + warp / circumference_cells;

    // The tongues: a slow and a fast layer crossfaded by the heat, so the
    // speed follows it without the pattern running backwards, the mix's
    // contrast restored (an even mix of two fields flattens).
    float n = streak_noise(warped, along, slow_speed, seed3, pace, footprint);
    if (fast_share > 0.0)
    {
        float fast = streak_noise(warped, along, FAST_FLOW, seed3 + vec3(13.7, 41.9, 5.3), pace, footprint);
        n = mix(n, fast, fast_share);
        n = clamp(0.5 + (n - 0.5) * inversesqrt(fast_share * fast_share + (1.0 - fast_share) * (1.0 - fast_share)), 0.0, 1.0);
    }

    // A flare lengthens the tongues and thickens their cores, a dip
    // shortens them.
    float flare = flicker - FLICKER_MEAN;
    float threshold = mix(0.68, 0.38, heat) - 0.14 * lead - 0.22 * flare;
    float streak = smoothstep(threshold, threshold + 0.18, n) * smoothstep(0.1, 0.55, heat);
    float core = smoothstep(0.62, 0.8, n + 0.1 * lead + 0.15 * flare) * smoothstep(0.55, 1.0, heat);

    // The haze: bands longer than the porthole streaming aft, brightest
    // at the rim.
    float haze_along = along - seconds * slow_speed;
    float haze_noise = 0.65 * wrapped_noise(vec3(round_tube(warped, 2.0), haze_along * 0.15, seconds * 0.8 * pace) + seed3, wake_period(2.0)) + 0.35 * wrapped_noise(vec3(round_tube(warped, 4.3), haze_along * 0.33, seconds * 1.7 * pace) + seed3 + vec3(17.3, 29.1, 0.0), wake_period(4.3));
    float haze_level = mix(0.18, 0.42, haze_noise) * smoothstep(0.0, 0.35, heat) + HAZE_LEAD * heat * lead;

    // The colour and the opacity: the shell at the face's intensity
    // times the path.
    float chemistry = wrapped_noise(vec3(round_tube(warped, 1.5), haze_along * 0.3, seconds * 1.3 * pace) + seed3 + vec3(5.1, 9.7, 0.0), wake_period(1.5));
    float face = (haze_level + 0.55 * streak + 0.45 * core) * heat_light * lead * WAKE_GAIN * end;
    vec4 wake = shell(face * path, chemistry);

    // The sparks: two hashed grids streaking aft, a flare bringing a
    // shower, the brighter one kept, fading with the light along the
    // flow and where a cell would be under 3 px.
    float spark_rate = smoothstep(0.22, 0.85, heat) * (0.5 + 0.6 * flicker) * min(lead * WAKE_GAIN, 2.0) * end;
    float spark_speed = calm > 0.5 ? SPARK_CALM_FLOW : SPARK_FLOW;
    float spark_fast_speed = calm > 0.5 ? SPARK_CALM_FAST_FLOW : SPARK_FAST_FLOW;
    float spark_life = calm > 0.5 ? 4.5 : SPARK_LIFE;
    float spark_fast_life = calm > 0.5 ? 6.5 : SPARK_FAST_LIFE;
    uint first_period = wake_period(28.6);
    uint second_period = wake_period(44.2);
    float first_white;
    float second_white;
    float first = spark_layer(vec2(share * float(first_period), (along - seconds * spark_speed * pace) * 2.6), first_period, 0.22 * spark_rate, spark_life, seed3.xy + vec2(3.3, 8.9), pace, first_white) * detail(footprint, 28.6);
    float second = spark_layer(vec2(share * float(second_period), (along - seconds * spark_fast_speed * pace) * 3.25), second_period, 0.14 * spark_rate, spark_fast_life, seed3.xy + vec2(21.1, 5.7), pace, second_white) * detail(footprint, 44.2);
    float spark = max(first, second);
    float white_share = first >= second ? first_white : second_white;
    vec3 spark_color = mix(ablator_color, WHITE_CORE, 0.35 + 0.5 * white_share) * (0.8 + 0.3 * flicker);
    vec3 c = min(mix(wake.rgb, spark_color, spark), vec3(1.0));
    float alpha = max(wake.a, spark);
    final_color = vec4(c * alpha, alpha);
}
