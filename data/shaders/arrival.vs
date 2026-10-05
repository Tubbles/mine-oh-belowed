#version 330

// The arrival's window flames (work item 0200, render_arrival.odin): a
// porthole's glass, its texture coordinate passed on. Attribute and
// matrix names are the raylib defaults.

in vec3 vertexPosition;
in vec2 vertexTexCoord;

uniform mat4 mvp;

out vec2 fragment_texture_coordinate;

void main()
{
    fragment_texture_coordinate = vertexTexCoord;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
