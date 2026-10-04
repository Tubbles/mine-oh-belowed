#version 330

// Machine model fragment shader (work item 0224, render_models.odin), for
// the lit layer only. The vertex colour (pre-shaded per face on the CPU)
// times colDiffuse (the light tint, a ghost's colour or the broken tint),
// as raylib's default shader draws it, plus the vertex colour's rgb times
// the point lights' sum. point_light_sum is copied from field.fs: keep the
// two in step. Without a texture sampler: raylib's default texture is
// white, so leaving it out changes nothing.
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

out vec4 finalColor;

const float point_light_wrap = 0.5;
const float smallest_weight_sum = 0.0001;

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
    vec4 base = fragment_color * colDiffuse;
    vec3 lit = base.rgb + fragment_color.rgb * point_light_sum(fragment_world_position, normal);
    finalColor = vec4(min(lit, vec3(1.0)), base.a);
}
