#version 330

// The sun's shadow map (work item 0328, render_sun_shadows.odin): the
// casters' depth seen from the sun. mvp is the light's projection and
// view times the draw's transform (DrawMesh), or the light's alone for
// an instanced draw (a view's instance buffer, draw_tree_pass), where
// instanced_on is 1 and each tree's transform comes in instanceTransform
// with its species and shade in the bottom row (tree_instance), rebuilt
// to 0, 0, 0, 1 as tree.vs does. The machines' pieces and the
// foundations' slabs come the same way, their colour in that row (0347,
// draw_cast_model_instances, draw_field_foundations), mvp then including
// the rlgl stack's transform (the pod's, a frame's). A caster nearer the
// sun than the map's near plane is pressed onto that plane (its depth
// clamped to it, not clipped), so it shadows every receiver behind it
// however far towards the sun it stands.
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin).

in vec3 vertexPosition;
in mat4 instanceTransform;

uniform mat4 mvp;
uniform float instanced_on;

void main()
{
    vec4 position = vec4(vertexPosition, 1.0);
    if (instanced_on > 0.5) {
        mat4 model = instanceTransform;
        model[0u][3u] = 0.0;
        model[1u][3u] = 0.0;
        model[2u][3u] = 0.0;
        model[3u][3u] = 1.0;
        position = model * position;
    }
    gl_Position = mvp * position;
    gl_Position.z = max(gl_Position.z, -gl_Position.w);
}
