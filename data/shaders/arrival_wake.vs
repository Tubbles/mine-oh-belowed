#version 330

// The entry's wake (work item 0304, render_arrival_wake.odin): the tube
// and the shield's disc, the texture coordinate passed on and the
// vertex's position for the view's path through the shell. rlgl moves
// each immediate mode vertex by the pushed matrix on the CPU (the pod's
// transform), so vertexPosition arrives in the moved space, mvp holds
// only the camera, and the uniforms the fragment shader compares it with
// are in that space too (arrival_wake_frame). Attribute and matrix names
// are the raylib defaults.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin): Winlator's Gladio appends .0 to a bare
// integer on any line with a float variable.

in vec3 vertexPosition;
in vec2 vertexTexCoord;

uniform mat4 mvp;

out vec2 fragment_texture_coordinate;
out vec3 fragment_position;

void main()
{
    fragment_texture_coordinate = vertexTexCoord;
    fragment_position = vertexPosition;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
