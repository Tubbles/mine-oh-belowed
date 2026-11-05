#version 330

// Field fragment shader (work item 0169, render_field.odin): triplanar
// texturing of the smooth terrain, with the point lights of 0175, 0224
// and 0229. Each material's generated tile
// (texture_field_materials.odin) is projected along the three axes and
// the three are blended by the absolute normal, sharpened so a slope
// shows one projection, not a smear of three. The tile is read at two
// scales whose ratio is not a fraction of small numbers, so the tile's
// period never shows as a grid (DESIGN.md, No perceivable repetition).
// The seven materials (every one but air) blend by the vertex weights,
// the palette's tint and the light are multiplied in: the brighter of the
// block light and the sky light times daylight (work item 0173), the sky
// light's share being the ambient plus the sun's term on a slope facing
// sun_direction (the day clock's sun in the world's frame, work item
// 0297), so a cave's samples, with no sky light, take no sun; then the
// point lights and the torchlight (spot_light, 0297) add on top, and the
// fog fades to the sky colour towards the last level of detail distance.
// With water_color's alpha above 0 (the water pass, work item 0172) the
// surface takes water_color's colour instead of the materials and its
// alpha as its opacity, and the sun's glint, white, where the half vector
// of the sun and the eye meets the normal; the terrain pass sets it to 0.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin), as the point lights' array sizes and loop do.

in vec3 fragment_world_position;
in vec3 fragment_normal;
in vec4 fragment_color;
in vec4 fragment_weights;
in vec3 fragment_ore_weights;
in float fragment_block_light;
in float fragment_distance;

uniform sampler2D material_texture_topsoil;
uniform sampler2D material_texture_stone;
uniform sampler2D material_texture_deep_stone;
uniform sampler2D material_texture_bedrock;
uniform sampler2D material_texture_hematite_ore;
uniform sampler2D material_texture_chalcopyrite_ore;
uniform sampler2D material_texture_coal_ore;
// The sun's unit direction in the world's frame (field_sun_world_direction,
// 0297), the sky light's share without the sun and the sun's.
uniform vec3 sun_direction;
uniform float sky_ambient;
uniform float sun_strength;
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;
uniform vec4 water_color;
// The sky light's share: 1 by day, 0 at night.
uniform float daylight;
// The eye in the world's metres, the same uniform field.vs declares (one
// location in the program), for the water's glint (0297).
uniform vec3 camera_position;

out vec4 finalColor;

// Metres one tile spans at the first scale; the second scale's tile is
// larger by second_scale_ratio.
const float tile_metres = 2.0;
const float second_scale_ratio = 2.71828;
// The projections' blend sharpness.
const float blend_sharpness = 4.0;
// The tiles are mid tones; the tint scaled so carries the colour.
const float tint_scale = 2.0;
const float smallest_weight_sum = 0.0001;
// The sun on the water (0297): the glint's sharpness and its brightness.
const float water_glint_power = 48.0;
const float water_glint_strength = 0.6;

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
// smoothly to nothing at the radius. A machine's lamp is clipped to its
// machine's box (work item 0229): its colour's alpha is 0, and the
// terrain takes nothing from it (the machine's floor covers the ground
// inside its box, and the ground round the machine stays unlit), so this
// shader needs no boxes; model.fs tests the box. point_light_sum is the
// one of model.fs but for that line.
uniform vec4 point_light_positions[8u];
uniform vec4 point_light_colors[8u];

const float point_light_wrap = 0.5;
// A clipped light fades out over this much of the cosine past grazing, so
// a curved fixture shows no hard edge.
const float back_face_fade = 0.25;

// The back face factor below is always 1 here, since a clipped light
// (alpha 0) is skipped first; it stays so the sum is line for line
// model.fs's, which shader_source_test.odin compares.
vec3 point_light_sum(vec3 position, vec3 normal)
{
    vec3 sum = vec3(0.0);
    for (uint index = 0u; index < 8u; index++) {
        vec4 light = point_light_positions[index];
        if (light.w <= 0.0) {
            break;
        }
        vec4 color = point_light_colors[index];
        if (color.a < 0.5) {
            continue;
        }
        vec3 offset = light.xyz - position;
        float share = clamp(1.0 - dot(offset, offset) / max(light.w * light.w, smallest_weight_sum), 0.0, 1.0);
        float turned = dot(normal, normalize(offset + vec3(smallest_weight_sum)));
        float facing = mix(point_light_wrap, 1.0, max(turned, 0.0));
        float back_face = clamp(1.0 + turned / back_face_fade, 0.0, 1.0);
        facing *= mix(back_face, 1.0, color.a);
        sum += color.rgb * share * share * facing;
    }
    return sum;
}

// The torchlight (0297): a cone from spot_position along spot_direction,
// full inside spot_cos_inner, gone past spot_cos_outer, inverse square
// from torchlight_reference_metres, ended smoothly at spot_range; a range
// of 0 is off and costs one compare. Half the facing is wrapped as the
// point lights do.
uniform vec3 spot_position;
uniform vec3 spot_direction;
uniform float spot_cos_inner;
uniform float spot_cos_outer;
uniform float spot_range;
uniform vec3 spot_color;

const float torchlight_reference_metres = 4.0;

vec3 spot_light(vec3 position, vec3 normal)
{
    if (spot_range <= 0.0) {
        return vec3(0.0);
    }
    vec3 offset = position - spot_position;
    float distance_squared = dot(offset, offset);
    vec3 to_fragment = offset * inversesqrt(max(distance_squared, smallest_weight_sum));
    float cone = smoothstep(spot_cos_outer, spot_cos_inner, dot(to_fragment, spot_direction));
    float reach = clamp(1.0 - distance_squared / (spot_range * spot_range), 0.0, 1.0);
    float reference = torchlight_reference_metres * torchlight_reference_metres;
    float falloff = reference / (reference + distance_squared) * reach * reach;
    float facing = mix(point_light_wrap, 1.0, max(dot(normal, -to_fragment), 0.0));
    return spot_color * cone * falloff * facing;
}

void main()
{
    vec3 normal = normalize(fragment_normal);
    vec3 blend = pow(abs(normal), vec3(blend_sharpness));
    blend /= dot(blend, vec3(1.0));
    float weight_sum = dot(fragment_weights, vec4(1.0)) + dot(fragment_ore_weights, vec3(1.0));
    vec4 weights = fragment_weights / max(weight_sum, smallest_weight_sum);
    vec3 ore_weights = fragment_ore_weights / max(weight_sum, smallest_weight_sum);
    // Every material is sampled, also at weight 0: a mipmapped sample
    // inside a branch has no defined derivatives where a pixel quad
    // straddles a triangle whose weight is 0 at one end.
    vec3 albedo = weights.x * material_color(material_texture_topsoil, blend);
    albedo += weights.y * material_color(material_texture_stone, blend);
    albedo += weights.z * material_color(material_texture_deep_stone, blend);
    albedo += weights.w * material_color(material_texture_bedrock, blend);
    albedo += ore_weights.x * material_color(material_texture_hematite_ore, blend);
    albedo += ore_weights.y * material_color(material_texture_chalcopyrite_ore, blend);
    albedo += ore_weights.z * material_color(material_texture_coal_ore, blend);
    albedo *= fragment_color.rgb * tint_scale;
    float water = step(smallest_weight_sum, water_color.a);
    albedo = mix(albedo, water_color.rgb, water);
    // The sky light gates the sun: a cave's samples have none and take
    // no sun, the cheap shadow. Block light stays the brighter, never
    // added, so a torch-lit wall keeps its light whichever way it faces.
    float sun_facing = max(dot(normal, sun_direction), 0.0);
    float sun_light = fragment_color.a * daylight * (sky_ambient + sun_strength * sun_facing);
    float light = max(fragment_block_light, sun_light);
    vec3 lit = albedo * light;
    lit += albedo * point_light_sum(fragment_world_position, normal);
    lit += albedo * spot_light(fragment_world_position, normal);
    // The sun on the water: paid as a multiply by water, not a branch
    // (the mipmapped samples' rule above).
    vec3 to_camera = normalize(camera_position - fragment_world_position);
    float glint = water * fragment_color.a * daylight * pow(max(dot(normal, normalize(sun_direction + to_camera + vec3(smallest_weight_sum))), 0.0), water_glint_power) * water_glint_strength;
    lit += vec3(glint);
    float fog = clamp((fragment_distance - fog_start) / (fog_end - fog_start), 0.0, 1.0);
    finalColor = vec4(mix(min(lit, vec3(1.0)), fog_color, fog), mix(1.0, water_color.a, water));
}
