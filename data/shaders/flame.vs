#version 330

// The flames of the furnace and the torch (work item 0274, DESIGN.md,
// Fire, render_flames.odin): a flame's quad, its texture coordinate
// passed on, 0 to 1 across and up the tongue. All of a frame's quads
// draw in one batch, so each carries its own values in its vertex colour
// (flame_vertex_color): the flicker in red, the seed in green in 256ths,
// the height over the width in hundredths in blue (high byte) and alpha
// (low byte). Attribute and matrix names are the raylib defaults.

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

uniform mat4 mvp;

out vec2 fragment_texture_coordinate;
flat out float fragment_flicker;
flat out float fragment_seed;
flat out float fragment_aspect;

void main()
{
    fragment_texture_coordinate = vertexTexCoord;
    vec4 bytes = floor(vertexColor * 255.0 + 0.5);
    fragment_flicker = bytes.r / 255.0;
    fragment_seed = bytes.g / 256.0;
    fragment_aspect = (bytes.b * 256.0 + bytes.a) / 100.0;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
