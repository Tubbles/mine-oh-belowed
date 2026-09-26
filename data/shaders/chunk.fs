#version 330

// Chunk fragment shader (work items 0005 and 0008): samples the block
// atlas, lights it from the vertex colour and fades to the fog colour
// between fog_start and fog_end to hide the load boundary.
//
// Vertex colour packing (world_mesh_light.odin), each channel 0 to 1:
//   r  sky light level / 15, averaged over the cells around the vertex
//   g  block light level / 15, same
//   b  ambient occlusion / 3, 1 where nothing solid touches the vertex
// Sky light is scaled by day_factor, block light is not, so torches glow
// the same at night. Brightness is sky plus block light, times the
// occlusion shade, never below minimum_brightness.

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
uniform float day_factor;

out vec4 finalColor;

const float minimum_brightness = 0.06;
const float darkest_occlusion_shade = 0.5;

// Light levels to brightness: each level down dims a little more than
// linear, Minecraft style, 0 stays 0 and 1 stays 1.
float light_curve(float level)
{
    return level / (4.0 - 3.0 * level);
}

void main()
{
    vec2 atlas_uv = fragment_tile_origin + fract(fragment_texcoord) * tile_size;
    vec4 texel = texture(texture0, atlas_uv) * colDiffuse;
    float light = light_curve(fragment_color.r) * day_factor + light_curve(fragment_color.g);
    float shade = mix(darkest_occlusion_shade, 1.0, fragment_color.b);
    float brightness = max(min(light, 1.0) * shade, minimum_brightness);
    float fog = clamp((fragment_distance - fog_start) / (fog_end - fog_start), 0.0, 1.0);
    finalColor = vec4(mix(texel.rgb * brightness, fog_color, fog), 1.0);
}
