#version 330

// Field fragment shader (work item 0169, render_field.odin): triplanar
// texturing of the smooth terrain. Each material's generated tile
// (texture_field_materials.odin) is projected along the three axes and
// the three are blended by the absolute normal, sharpened so a slope
// shows one projection, not a smear of three. The tile is read at two
// scales whose ratio is not a fraction of small numbers, so the tile's
// period never shows as a grid (DESIGN.md, No perceivable repetition).
// The materials blend by the vertex weights, the palette's tint and the
// vertex light are multiplied in (the brighter of the block light and the
// sky light times daylight, work item 0173), a gentle sun term shades the
// slopes,
// and the fog fades to the sky colour towards the last level of detail
// distance. With water_color's alpha above 0 (the water pass, work item
// 0172) the surface takes water_color's colour instead of the materials
// and its alpha as its opacity; the terrain pass sets it to 0.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin), as the point lights' array sizes and loop do.

in vec3 fragment_world_position;
in vec3 fragment_normal;
in vec4 fragment_color;
in vec4 fragment_weights;
in float fragment_block_light;
in float fragment_distance;

uniform sampler2D material_texture_topsoil;
uniform sampler2D material_texture_stone;
uniform sampler2D material_texture_deep_stone;
uniform sampler2D material_texture_bedrock;
uniform vec3 sun_direction;
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;
uniform vec4 water_color;
// The sky light's share: 1 by day, 0 at night.
uniform float daylight;

out vec4 finalColor;

// Metres one tile spans at the first scale; the second scale's tile is
// larger by second_scale_ratio.
const float tile_metres = 2.0;
const float second_scale_ratio = 2.71828;
// The projections' blend sharpness.
const float blend_sharpness = 4.0;
// The tiles are mid tones; the tint scaled so carries the colour.
const float tint_scale = 2.0;
// The light on a slope facing away from the sun.
const float ambient_share = 0.45;
const float smallest_weight_sum = 0.0001;

vec3 triplanar(sampler2D tile, vec3 position, vec3 blend)
{
    vec3 along_x = texture(tile, position.yz).rgb;
    vec3 along_y = texture(tile, position.zx).rgb;
    vec3 along_z = texture(tile, position.xy).rgb;
    return along_x * blend.x + along_y * blend.y + along_z * blend.z;
}

vec3 material_color(sampler2D tile, vec3 blend)
{
    vec3 position = fragment_world_position / tile_metres;
    vec3 near = triplanar(tile, position, blend);
    vec3 far = triplanar(tile, position.zxy / second_scale_ratio, blend.zxy);
    return mix(near, far, 0.5);
}

// Point lights of working parts (work item 0175, render_point_lights.odin):
// up to eight, the nearest to the camera, added on top of the field's
// light, never in its place. xyz is the position in metres and w the
// radius, 0 for an unused slot; the colour's rgb is the light's colour.
// The lights come nearest first with the unused slots last, so the loop
// stops at the first unused one and costs nothing without lights.
// The term is soft: half of it ignores the facing, and it falls off
// smoothly to nothing at the radius.
uniform vec4 point_light_positions[8u];
uniform vec4 point_light_colors[8u];

const float point_light_wrap = 0.5;

vec3 point_light_sum(vec3 position, vec3 normal)
{
    vec3 sum = vec3(0.0);
    for (uint index = 0u; index < 8u; index++) {
        vec4 light = point_light_positions[index];
        if (light.w <= 0.0) {
            break;
        }
        vec3 offset = light.xyz - position;
        float share = clamp(1.0 - dot(offset, offset) / max(light.w * light.w, smallest_weight_sum), 0.0, 1.0);
        float facing = mix(point_light_wrap, 1.0, max(dot(normal, normalize(offset + vec3(smallest_weight_sum))), 0.0));
        sum += point_light_colors[index].rgb * share * share * facing;
    }
    return sum;
}

void main()
{
    vec3 normal = normalize(fragment_normal);
    vec3 blend = pow(abs(normal), vec3(blend_sharpness));
    blend /= dot(blend, vec3(1.0));
    vec4 weights = fragment_weights / max(dot(fragment_weights, vec4(1.0)), smallest_weight_sum);
    // Every material is sampled, also at weight 0: a mipmapped sample
    // inside a branch has no defined derivatives where a pixel quad
    // straddles a triangle whose weight is 0 at one end.
    vec3 albedo = weights.x * material_color(material_texture_topsoil, blend);
    albedo += weights.y * material_color(material_texture_stone, blend);
    albedo += weights.z * material_color(material_texture_deep_stone, blend);
    albedo += weights.w * material_color(material_texture_bedrock, blend);
    albedo *= fragment_color.rgb * tint_scale;
    float water = step(smallest_weight_sum, water_color.a);
    albedo = mix(albedo, water_color.rgb, water);
    float sun = max(dot(normal, normalize(sun_direction)), 0.0);
    float light = max(fragment_block_light, fragment_color.a * daylight);
    vec3 lit = albedo * light * mix(ambient_share, 1.0, sun);
    lit += albedo * point_light_sum(fragment_world_position, normal);
    float fog = clamp((fragment_distance - fog_start) / (fog_end - fog_start), 0.0, 1.0);
    finalColor = vec4(mix(min(lit, vec3(1.0)), fog_color, fog), mix(1.0, water_color.a, water));
}
