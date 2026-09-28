#version 330

// Shadow map depth pass (work item 0072, render_shadows.odin): the chunk
// meshes near the camera seen from the sun. Position only; mvp is the
// light's projection and view times the chunk's transform, set by
// DrawMesh from the matrices the pass loads.

in vec3 vertexPosition;

uniform mat4 mvp;

void main()
{
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
