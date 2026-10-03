#version 330

// The arrival's window overlay (work item 0200, render_arrival.odin),
// drawn over the descent's view with alpha blending. The quad covers the
// viewport; a rounded box in its middle is the cabin's window, the rest
// is the cabin wall (wall_color, a lighter bevel at the window's edge).
// Inside the window the flames of the drag grow from its edges, highest
// at its bottom (the leading edge: the camera's up is tilted back along
// the path, so the air presses in from below), to a height that follows
// flame_strength (0 to 1). Their shape is four octaves of value noise
// scrolling inwards, the octaves' scales and speeds in no small integer
// ratio, so the pattern never repeats; flame_seed shifts it per world.
// An orange glow over the whole window follows the flames.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin): Winlator's Gladio appends .0 to a bare
// integer on any line with a float variable.

in vec2 fragment_texture_coordinate;

uniform float flame_strength;
uniform float seconds;
uniform float aspect;
uniform float flame_seed;
uniform vec3 wall_color;

out vec4 final_color;

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

// The signed distance to a box of half size half_size with rounded
// corners of the radius, negative inside.
float rounded_box_distance(vec2 point, vec2 half_size, float radius)
{
    vec2 outside = abs(point) - half_size + vec2(radius);
    return length(max(outside, vec2(0.0))) + min(max(outside.x, outside.y), 0.0) - radius;
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
    vec2 p = (fragment_texture_coordinate - vec2(0.5)) * vec2(aspect, 1.0);
    float d = rounded_box_distance(p, vec2(0.38 * aspect, 0.36), 0.07);
    if (d > 0.0)
    {
        vec3 wall = d < 0.012 ? wall_color + vec3(0.08) : wall_color;
        final_color = vec4(wall, 1.0);
        return;
    }
    float depth = -d;
    // p.y grows downwards on the screen: the bottom edge leads.
    float lead = clamp(0.5 + p.y / 0.72, 0.0, 1.0);
    float weight = 0.25 + 0.75 * lead;
    float along = atan(p.y, p.x) * 3.0;
    float n = flame_noise(along, depth);
    float height = flame_strength * weight * 0.22 * (0.6 + 0.8 * n);
    float flame = 1.0 - smoothstep(0.0, max(height, 0.0001), depth);
    flame *= step(0.0001, flame_strength);
    vec3 color = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.9, 0.6), flame * flame);
    float glow = 0.12 * flame_strength;
    float alpha = flame + glow * (1.0 - flame);
    vec3 blended = (color * flame + vec3(1.0, 0.45, 0.1) * glow * (1.0 - flame)) / max(alpha, 0.0001);
    final_color = vec4(blended, alpha);
}
