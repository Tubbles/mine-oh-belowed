#version 330

// Tree fragment shader (work item 0310, render_field_trees.odin), for the
// near models (card_on 0) and the far cards (card_on 1). A card reads
// its texel from the atlas (texture0, read before any discard) and keeps
// alpha at least a half; its normal runs from the crown's centre to the
// fragment, so a card is lit as a round crown. The model and the card of
// one tree cross over the near fade by an interleaved gradient noise on
// the pixel: the model kept where the noise is at least the fade, the
// card where it is below, so no tree doubles or vanishes; the cards leave
// the same way over the far fade. The colour is model.fs's on the open
// sky (outdoor_on 1): the albedo (the vertex colour or the texel) times
// the species' tint and the tree's shade (fragment_tint) times
// colDiffuse (the flat daylight the CPU gives a model, divided out by
// daylight_tint), lit by the open sky's light by the normal, the point
// lights and the torchlight, and hazed. outdoor_light, apply_haze,
// point_light_sum and spot_light are model.fs's line for line
// (shader_source_test.odin). The sun's shadow (sun_shadow_light, work
// item 0328) scales the models' open sky sun term; the cards receive
// none.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin), as the point lights' array sizes and loop do.

in vec3 fragment_world_position;
in vec3 fragment_normal;
in vec4 fragment_color;
in vec2 fragment_texcoord;
in vec3 fragment_crown;
in vec3 fragment_tint;
in float fragment_near_fade;
in float fragment_far_fade;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform float card_on;
uniform vec3 daylight_tint;
uniform vec3 camera_position;

// Point lights of working parts (work items 0175 and 0224,
// render_point_lights.odin): up to eight, the nearest to the camera, the
// same the field shader takes. xyz is the position in metres and w the
// radius, 0 for an unused slot; the colour's rgb is the light's colour.
uniform vec4 point_light_positions[8u];
uniform vec4 point_light_colors[8u];
// The lights' clip boxes (work item 0229, render_point_lights.odin): per
// light three rows of the matrix from the world's metres to its machine's
// box, -1 to 1 inside on every axis, light index's rows at index * 3u. A
// light that shines everywhere (an arm's lamp, a record lamp with clip =
// false, an unused slot) has zero rows, which map every point to the
// box's centre, so it passes. A clipped light's colour has alpha 0: it
// gives nothing to a face turned away from it, so a hull's outer skin,
// turned away from a lamp inside, stays dark. No shadows: the box and the
// facing stand in for them.
uniform vec4 point_light_boxes[24u];

out vec4 finalColor;

const float point_light_wrap = 0.5;
// A clipped light fades out over this much of the cosine past grazing, so
// a curved fixture shows no hard edge.
const float back_face_fade = 0.25;
const float smallest_weight_sum = 0.0001;

// The open sky's light (0313, Field_Frame_Lights): the sky's light from
// above and the ground's bounce from below, shared by the normal's facing
// of the local up, and the sun's by its facing of sun_direction (the day
// clock's sun in the world's frame, 0297). The colours carry the time of
// day; the sun's is zero once it has set. The bounce is the caller's
// (0380): a tree takes the planet's. outdoor_light is field.fs's line
// for line (shader_source_test.odin).
uniform vec3 sun_direction;
uniform vec3 sun_color;
uniform vec3 sky_color;
uniform vec3 bounce_color;

vec3 outdoor_light(vec3 normal, vec3 up, float sunlit, vec3 bounce)
{
    float upward = 0.5 + 0.5 * dot(normal, up);
    return mix(bounce, sky_color, upward) + sun_color * (sunlit * max(dot(normal, sun_direction), 0.0));
}

// The sun's shadow (0328, render_sun_shadows.odin): the casters' depth
// seen from the sun in sun_shadow_map, reached through sun_shadow_matrix
// from the world's metres. sun_shadow_shape: x the map's texels a side,
// y a texel in metres, z and w the distances from the eye where the
// shadow starts to fade and is gone. The position moves along its normal
// by sun_shadow_normal_offset_texels and its depth towards the sun by
// sun_shadow_depth_bias_texels, so a lit face never shadows itself; the
// comparisons of 4 by 4 texels are weighted as the mean of the 3 by 3
// bilinear lookups round the position, an edge three texels soft. The
// strength 0 (the setting off, the sun set) and a face turned from the
// sun return 1 before any read. The sampler is highp: GLSL ES gives a
// sampler lowp by default, too coarse for a depth. sun_shadow_light and
// sun_shadow_tap_weight are the same text in field.fs, model.fs, tree.fs
// and cover.fs (shader_source_test.odin).
uniform highp sampler2D sun_shadow_map;
uniform mat4 sun_shadow_matrix;
uniform float sun_shadow_strength;
uniform vec4 sun_shadow_shape;

const float sun_shadow_normal_offset_texels = 2.0;
const float sun_shadow_depth_bias_texels = 0.5;

// A tap's weight along one axis: the outer two by the fraction, the
// inner two whole.
float sun_shadow_tap_weight(uint index, float fraction)
{
    if (index == 0u) {
        return 1.0 - fraction;
    }
    return index == 3u ? fraction : 1.0;
}

// 1 where the sun reaches the position, down to 1 less the strength in
// full shadow.
float sun_shadow_light(vec3 position, vec3 normal, vec3 eye)
{
    if (sun_shadow_strength <= 0.0 || dot(normal, sun_direction) <= 0.0) {
        return 1.0;
    }
    float fade = 1.0 - smoothstep(sun_shadow_shape.z, sun_shadow_shape.w, length(position - eye));
    if (fade <= 0.0) {
        return 1.0;
    }
    vec3 moved = position + normal * (sun_shadow_shape.y * sun_shadow_normal_offset_texels);
    vec3 coordinate = (sun_shadow_matrix * vec4(moved, 1.0)).xyz * 0.5 + 0.5;
    float depth = coordinate.z - sun_shadow_depth_bias_texels / sun_shadow_shape.x;
    vec2 texel_position = coordinate.xy * sun_shadow_shape.x - 0.5;
    vec2 base = floor(texel_position);
    vec2 fraction = texel_position - base;
    float lit = 0.0;
    for (uint row = 0u; row < 4u; row++) {
        for (uint column = 0u; column < 4u; column++) {
            vec2 texel = base + vec2(float(column), float(row)) - 0.5;
            float stored = textureLod(sun_shadow_map, texel / sun_shadow_shape.x, 0.0).r;
            lit += sun_shadow_tap_weight(column, fraction.x) * sun_shadow_tap_weight(row, fraction.y) * step(depth, stored);
        }
    }
    return 1.0 - sun_shadow_strength * fade * (1.0 - lit / 9.0);
}

// The aerial haze (0313, Field_Haze): over the reach from the eye the
// surface takes the sky's colour at the horizon (haze_color), warmed
// towards a low sun (haze_sun_color), by the air's optical depth: the air
// thins with the height above planet_radius by haze_scale_height, so a
// valley holds more haze than a ridge and the view from above less. The
// end fade between fog_start and fog_end, the last level of detail's
// distance, brings it to the full sky colour inside the atmosphere and
// to the globe's colour (globe_color) lit by the open sky above its top,
// mixed by haze_end_share (the sky's share at the eye), so the far
// nodes, the globe and the horizon read as one from the ground and the
// drawn terrain blends into the globe from above the air.
// sky_share scales the aerial haze: air the sky does not light (a cave's,
// by its samples' sky light) scatters no sky colour. The end fade is full
// whatever the share (0354): past the view lies only the end colour, so a
// shaded face fades there as a lit one does.
// apply_haze is field.fs's line for line.
uniform vec3 haze_color;
uniform vec3 haze_sun_color;
uniform float haze_density;
uniform float haze_scale_height;
uniform float haze_end_share;
uniform vec3 globe_color;
uniform float planet_radius;
uniform float eye_height;
uniform float fog_start;
uniform float fog_end;

// The glow's narrowness towards the sun (HAZE_SUN_EXPONENT, the dome's);
// a rise under haze_level_rise scale heights takes the mean height's
// density, where the exact form divides by nearly nothing. The scale
// height is at least 1 m, so the zero uniforms outside a field session
// divide by no zero.
const float haze_sun_exponent = 6.0;
const float haze_level_rise = 0.01;

vec3 apply_haze(vec3 color, vec3 position, vec3 eye, float sky_share)
{
    vec3 offset = position - eye;
    float reach = length(offset);
    float height = length(position) - planet_radius;
    float scale_height = max(haze_scale_height, 1.0);
    float rise = (height - eye_height) / scale_height;
    float mean_density = abs(rise) < haze_level_rise ? exp(-0.5 * (height + eye_height) / scale_height) : (exp(-eye_height / scale_height) - exp(-height / scale_height)) / rise;
    float aerial = 1.0 - exp(-reach * haze_density * mean_density);
    float toward_sun = max(dot(offset, sun_direction) / max(reach, smallest_weight_sum), 0.0);
    vec3 sky = min(haze_color + haze_sun_color * pow(toward_sun, haze_sun_exponent), vec3(1.0));
    vec3 up = position / max(length(position), smallest_weight_sum);
    vec3 globe = min(globe_color * outdoor_light(up, up, 1.0, bounce_color), vec3(1.0));
    vec3 end_color = mix(globe, sky, haze_end_share);
    vec3 hazed = mix(color, sky, aerial * sky_share);
    return mix(hazed, end_color, smoothstep(fog_start, max(fog_end, fog_start + 1.0), reach));
}

bool point_light_inside_box(uint index, vec3 position)
{
    vec4 point = vec4(position, 1.0);
    vec3 local = vec3(dot(point_light_boxes[index * 3u], point), dot(point_light_boxes[index * 3u + 1u], point), dot(point_light_boxes[index * 3u + 2u], point));
    vec3 reach = abs(local);
    return max(max(reach.x, reach.y), reach.z) <= 1.0;
}

vec3 point_light_sum(vec3 position, vec3 normal)
{
    vec3 sum = vec3(0.0);
    for (uint index = 0u; index < 8u; index++) {
        vec4 light = point_light_positions[index];
        if (light.w <= 0.0) {
            break;
        }
        vec4 color = point_light_colors[index];
        if (!point_light_inside_box(index, position)) {
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

// The dither of the crossfades: from 0 to 1 by the pixel.
float interleaved_gradient_noise(vec2 pixel)
{
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

void main()
{
    vec4 texel = texture(texture0, fragment_texcoord);
    float noise = interleaved_gradient_noise(gl_FragCoord.xy);
    bool card = card_on > 0.5;
    if (card && (texel.a < 0.5 || noise >= fragment_near_fade || noise < fragment_far_fade)) {
        discard;
    }
    if (!card && noise < fragment_near_fade) {
        discard;
    }
    vec3 normal = card ? normalize(fragment_world_position - fragment_crown + vec3(smallest_weight_sum)) : normalize(fragment_normal);
    vec3 albedo = card ? texel.rgb : fragment_color.rgb;
    vec4 base = vec4(albedo * fragment_tint, 1.0) * colDiffuse;
    // A card receives no sun's shadow: its planes run through the crown
    // of the model that casts for it (0328), which would shade its sun
    // side.
    float sunlit = card ? 1.0 : sun_shadow_light(fragment_world_position, normal, camera_position);
    vec3 light = outdoor_light(normal, normalize(fragment_world_position), sunlit, bounce_color) / max(daylight_tint, vec3(smallest_weight_sum));
    vec3 lit = min(base.rgb * light + albedo * (point_light_sum(fragment_world_position, normal) + spot_light(fragment_world_position, normal)), vec3(1.0));
    finalColor = vec4(apply_haze(lit, fragment_world_position, camera_position, 1.0), 1.0);
}
