#version 330

// Field vertex shader (work item 0169, render_field.odin). Attribute and
// matrix names are the raylib defaults, so DrawMesh binds them without
// extra code. The mesher (world_field_mesh.odin) packs:
//   colour rgb  the planet palette's tint of the ground at the vertex
//   colour a    the vertex light, full daylight until the field light
//               (work item 0173) provides it
//   normal      the outward surface normal, against the density gradient
//   tangent     the weights of the four textured materials (topsoil,
//               stone, deep stone, bedrock), summing to about 1

in vec3 vertexPosition;
in vec3 vertexNormal;
in vec4 vertexColor;
in vec4 vertexTangent;

uniform mat4 mvp;
uniform mat4 matModel;
uniform vec3 camera_position;

out vec3 fragment_world_position;
out vec3 fragment_normal;
out vec4 fragment_color;
out vec4 fragment_weights;
out float fragment_distance;

void main()
{
    vec4 world_position = matModel * vec4(vertexPosition, 1.0);
    fragment_world_position = world_position.xyz;
    fragment_normal = mat3(matModel) * vertexNormal;
    fragment_color = vertexColor;
    fragment_weights = vertexTangent;
    fragment_distance = length(world_position.xyz - camera_position);
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
