#version 330

// Chunk fragment shader (work item 0005): samples the block atlas, applies
// the per vertex colour (light from work item 0008) and fades to the clear
// colour between fog_start and fog_end to hide the load boundary.

in vec2 fragment_texcoord;
in vec2 fragment_tile_origin;
in vec4 fragment_color;
in float fragment_distance;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec2 tile_size;
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;

out vec4 finalColor;

void main()
{
    vec2 atlas_uv = fragment_tile_origin + fract(fragment_texcoord) * tile_size;
    vec4 texel = texture(texture0, atlas_uv) * fragment_color * colDiffuse;
    float fog = clamp((fragment_distance - fog_start) / (fog_end - fog_start), 0.0, 1.0);
    finalColor = vec4(mix(texel.rgb, fog_color, fog), 1.0);
}
