#version 330

// The flakes the heat shield sheds (work items 0290, 0304,
// render_arrival_flakes.odin): a flake's quad, its texture coordinate
// passed on, x across and y from the head's front to the streak's end.
// All of a frame's quads draw in one batch, so each carries its own
// values in its vertex colour (arrival_flake_vertex_color): the
// brightness times the flicker over flake_brightest in red, the square
// root of the head's share of the quad's length in green (a share as
// small as 0.02 within 2 percent, not 10), the whiteness in blue and
// the plate's opacity in alpha. Attribute and matrix names are the
// raylib defaults.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin): Winlator's Gladio appends .0 to a bare
// integer on any line with a float variable.

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

uniform mat4 mvp;

// The brightness scale, ARRIVAL_FLAKE_BRIGHTEST in
// render_arrival_flakes.odin.
const float flake_brightest = 2.0;

out vec2 fragment_texture_coordinate;
flat out float fragment_brightness;
flat out float fragment_head_share;
flat out float fragment_whiteness;
flat out float fragment_dark_core;

void main()
{
    fragment_texture_coordinate = vertexTexCoord;
    vec4 bytes = floor(vertexColor * 255.0 + 0.5);
    fragment_brightness = bytes.r / 255.0 * flake_brightest;
    fragment_head_share = (bytes.g / 255.0) * (bytes.g / 255.0);
    fragment_whiteness = bytes.b / 255.0;
    fragment_dark_core = bytes.a / 255.0;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
