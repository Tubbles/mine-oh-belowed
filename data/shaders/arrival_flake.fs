#version 330

// The flakes the heat shield sheds (work items 0290, 0304,
// render_arrival_flakes.odin), drawn premultiplied (one, one minus
// source alpha) after the wake: every flake a charred plate, opaque
// (0.92, faded in and out with the flake) to 0.6 of its radius and
// rimmed in gold, the ablator's orange towards the core colour as the
// flake is faster and hotter, so its core reads dark against the glow
// behind it, the footage's tumbling pieces; behind it a streak aft as
// wide as the plate at its root, narrowing to a quarter, its light
// halving every quarter of its length and cooling from gold to the
// air's red (0305). The plate hides what lies behind it, the streak
// adds light. No clock is read here: the motion comes from the CPU and
// the flicker per quad.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin): Winlator's Gladio appends .0 to a bare
// integer on any line with a float variable.

in vec2 fragment_texture_coordinate;
flat in float fragment_brightness;
flat in float fragment_head_share;
flat in float fragment_whiteness;
flat in float fragment_dark_core;

uniform vec3 haze_color;
uniform vec3 ablator_color;
uniform vec3 core_color;

out vec4 final_color;

// The plate's charred core.
const vec3 CHAR_COLOR = vec3(0.11, 0.065, 0.04);

void main()
{
    float across = fragment_texture_coordinate.x * 2.0 - 1.0;
    float along = fragment_texture_coordinate.y;
    float head_centre = 0.5 * fragment_head_share;
    float head_along = (along - head_centre) / max(head_centre, 0.001);
    float radius = sqrt(across * across + head_along * head_along);
    float plate = fragment_dark_core * (1.0 - smoothstep(0.85, 1.0, radius));
    float rim = smoothstep(0.5, 0.75, radius);
    vec3 gold = mix(ablator_color, core_color, 0.25 + 0.4 * fragment_whiteness);
    vec3 plate_color = mix(CHAR_COLOR, gold * 1.6 * fragment_brightness, rim);
    float trail = clamp((along - head_centre) / max(1.0 - head_centre, 0.001), 0.0, 1.0);
    float width = mix(0.8, 0.25, trail);
    float streak = along > head_centre ? exp(-across * across / (width * width)) * exp2(-4.0 * trail) * (1.0 - smoothstep(0.85, 1.0, trail)) : 0.0;
    vec3 streak_color = mix(mix(ablator_color, core_color, 0.6), haze_color, trail);
    float alpha = 0.92 * plate;
    vec3 c = plate_color * alpha + streak_color * streak * fragment_brightness * (1.0 - alpha);
    if (max(c.r, max(c.g, c.b)) < 0.003 && alpha < 0.003) discard;
    final_color = vec4(c, alpha);
}
