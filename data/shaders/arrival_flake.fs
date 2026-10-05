#version 330

// The flakes the heat shield sheds (work item 0290,
// render_arrival_flakes.odin), drawn premultiplied (one, one minus
// source alpha): a round soft head, the ablator's colour towards white
// as the flake is faster and hotter, and a streak behind it narrowing
// and cooling from the ablator's orange to the air's pink, as the
// footage's tails. A large flake (its dark core above 0) shows a dark
// plate inside its glowing rim, the footage's tumbling pieces: only the
// core writes alpha and hides what lies behind it, the rest adds light,
// so the quads need no sorting. No clock is read here: the motion comes
// from the CPU and the flicker per quad.
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

out vec4 final_color;

const vec3 WHITE_CORE = vec3(1.0, 0.97, 0.92);

void main()
{
    float across = fragment_texture_coordinate.x * 2.0 - 1.0;
    float along = fragment_texture_coordinate.y;
    float head_centre = 0.5 * fragment_head_share;
    float head_along = (along - head_centre) / max(head_centre, 0.001);
    float radial = across * across + head_along * head_along;
    float head = exp(-3.0 * radial);
    // The dark plate: opaque to r 0.35, gone by r 0.63, where the rim
    // glows twice as bright and more golden.
    float core = fragment_dark_core * (1.0 - smoothstep(0.12, 0.4, radial));
    float trail = clamp((along - head_centre) / max(1.0 - head_centre, 0.001), 0.0, 1.0);
    float width = mix(0.45, 0.08, trail);
    float streak = along > head_centre ? exp(-across * across / (width * width)) * (1.0 - trail) * (1.0 - trail) : 0.0;
    vec3 head_color = mix(ablator_color, WHITE_CORE, fragment_whiteness * (1.0 - 0.5 * fragment_dark_core));
    vec3 streak_color = mix(mix(ablator_color, WHITE_CORE, 0.3), haze_color, trail);
    float rim_gain = 1.4 * (1.0 + fragment_dark_core);
    vec3 c = (head_color * head * rim_gain + streak_color * streak * 0.7) * (1.0 - core) * fragment_brightness;
    float alpha = 0.9 * core;
    if (max(c.r, max(c.g, c.b)) < 0.003 && alpha < 0.003) discard;
    final_color = vec4(c, alpha);
}
