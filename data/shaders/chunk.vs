#version 330

// Chunk vertex shader (work item 0005). Attribute and matrix names are the
// raylib defaults, so DrawMesh binds them without extra code. The vertex
// colour carries light and occlusion (packing in chunk.fs).
//
// Wind (work item 0063): the vertex colour's alpha is 1 for rigid
// vertices and lower for those that sway (the upper vertices of cross
// shaped plants, world_mesh.odin); the lower it is, the further they
// move sideways, by two sines of the world position and wind_time, up to
// maximum_sway blocks at wind_strength 1. wind_time wraps after a whole
// number of both wave periods (WIND_TIME_WRAP_SECONDS in
// render_weather.odin).

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec2 vertexTexCoord2;
in vec4 vertexColor;

uniform mat4 mvp;
uniform mat4 matModel;
uniform vec3 camera_position;
uniform float wind_time;
uniform float wind_strength;

// Texcoord in blocks across the merged quad, repeated per block in the
// fragment shader. Tile origin is the atlas UV of the block's tile corner.
out vec2 fragment_texcoord;
out vec2 fragment_tile_origin;
out vec4 fragment_color;
out float fragment_distance;
out vec3 fragment_world_position;

const float maximum_sway = 0.15;
const float tau = 6.28318531;
const float first_wave_seconds = 3.0;
const float second_wave_seconds = 7.5;

// Sideways offset in x and z, each at most 1.
vec2 sway(vec3 world_position)
{
    float phase = dot(world_position.xz, vec2(0.37, 0.23));
    float first = sin(wind_time * tau / first_wave_seconds + phase);
    float second = sin(wind_time * tau / second_wave_seconds + 1.7 * phase);
    return vec2(0.7 * first + 0.3 * second, 0.5 * first * second);
}

void main()
{
    vec3 rest_position = (matModel * vec4(vertexPosition, 1.0)).xyz;
    vec2 offset = sway(rest_position) * maximum_sway * wind_strength * (1.0 - vertexColor.a);
    vec3 position = vertexPosition + vec3(offset.x, 0.0, offset.y);
    vec4 world_position = matModel * vec4(position, 1.0);
    fragment_texcoord = vertexTexCoord;
    fragment_tile_origin = vertexTexCoord2;
    fragment_color = vertexColor;
    fragment_distance = length(world_position.xyz - camera_position);
    fragment_world_position = world_position.xyz;
    gl_Position = mvp * vec4(position, 1.0);
}
