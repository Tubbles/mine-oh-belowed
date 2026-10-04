#version 330

// Machine model fragment shader (work item 0224, render_models.odin), for
// the lit layer only. The vertex colour (pre-shaded per face on the CPU)
// times colDiffuse (the light tint, a ghost's colour or the broken tint),
// as raylib's default shader draws it, plus the vertex colour's rgb times
// the point lights' sum, each machine lamp clipped to its machine's box
// (work item 0229). point_light_sum is copied from field.fs: keep the
// two in step (they differ in the clip line alone). Without a texture
// sampler: raylib's default texture is white, so leaving it out changes
// nothing.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin), as the point lights' array sizes and loop do.

in vec3 fragment_world_position;
in vec3 fragment_normal;
in vec4 fragment_color;

uniform vec4 colDiffuse;

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

void main()
{
    vec3 normal = normalize(fragment_normal);
    vec4 base = fragment_color * colDiffuse;
    vec3 lit = base.rgb + fragment_color.rgb * point_light_sum(fragment_world_position, normal);
    finalColor = vec4(min(lit, vec3(1.0)), base.a);
}
