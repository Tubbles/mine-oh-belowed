#version 330

// Field fragment shader (work item 0169, render_field.odin): triplanar
// texturing of the smooth terrain, with the point lights of 0175, 0224
// and 0229. Each generated tile (texture_field_materials.odin), the seven
// materials' (every one but air) and the three looks' (grass, sand,
// snow, work item 0307), lies in one atlas (ground_atlas) and is
// projected along the three axes, the three blended by the absolute
// normal, sharpened so a slope shows one projection, not a smear of
// three; a projection whose share is under projection_floor is not read.
// The tile is read at two scales whose ratio is not a fraction of small
// numbers, so the tile's period never shows as a grid (DESIGN.md, No
// perceivable repetition). With a climate (ground_look_on) the topsoil
// takes the looks: rock (the stone's tile) on faces steeper than 40 to
// 50 degrees against the local up, and on the natural ground left over
// snow, sand on slopes under 30 to 40 degrees, and grass, by the vertex's
// look (world_field_ground_look.odin). The tiles blend by their weights,
// only the most_tiles_read largest read; the strata take the vertex's
// tint, the grass its grass colour, the sand and the snow their uniform
// colours; then the light is multiplied in: per channel the brighter of
// the block light and the open sky's light (outdoor_light, work item
// 0313: the sun's on a face turned to sun_direction, the day clock's sun
// in the world's frame, 0297, and the sky's from above and the ground's
// bounce from below) times the vertex's sky light (work item 0173), so
// a cave's samples, with no sky light, take neither; then the point
// lights and the torchlight (spot_light, 0297) add on top, and the
// aerial haze (apply_haze, 0313) brings the far surface to the sky's
// colour. With water_color's alpha above 0 (the water pass, work item
// 0172) the surface takes water_color's colour instead of the materials
// and its alpha as its opacity, and the sun's glint, in the sun's
// colour, where the half vector of the sun and the eye meets the
// normal; the terrain pass sets it to 0. The water's vertices have no
// weights, so it reads no tile. The sun's shadow (sun_shadow_light, work
// item 0328) scales the open sky's sun term and the water's glint.
//
// Texture levels: every read is textureLod at a level computed from the
// derivatives of the position outside any branch, one level per
// projection plane, so the reads may sit in branches and loops without
// the derivatives' problem where a pixel quad straddles a branch.
//
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin), as the point lights' array sizes and loop do.

in vec3 fragment_world_position;
in vec3 fragment_normal;
in vec4 fragment_color;
in vec4 fragment_weights;
in vec3 fragment_ore_weights;
in vec3 fragment_grass_color;
// Snow, sand and the natural share (0307).
in vec3 fragment_look;
in float fragment_block_light;

// Every tile in cells of the atlas (field_ground_atlas_pixels).
uniform sampler2D ground_atlas;
// 1 with a climate, 0 without (set_field_ground_look_uniforms), and the
// sand's and the snow's colours, 0 to 1.
uniform float ground_look_on;
uniform vec3 sand_color;
uniform vec3 snow_color;
uniform vec4 water_color;
// The eye in the world's metres, for the water's glint (0297) and the
// haze (0313).
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
// The atlas (texture_field_materials.odin): the materials' tiles in
// their order, then grass, sand and snow, in cells of atlas_columns
// columns, each cell holding its tile repeated with the copy read
// tile_margin_texels in, so a read up to largest_lod (the level where a
// tile is one texel, its mean) stays inside its cell.
const uint ground_tile_count = 10u;
const uint strata_tile_count = 7u;
const uint grass_tile = 7u;
const uint sand_tile = 8u;
const uint snow_tile = 9u;
const uint atlas_columns = 4u;
const float atlas_cell_texels = 64.0;
const float atlas_texels = 256.0;
const float tile_texels = 16.0;
const float tile_margin_texels = 24.0;
const float largest_lod = 4.0;
// The most tiles a fragment reads, the largest weights first.
const uint most_tiles_read = 4u;
// A projection's share under this is not read; a tile weight is lowered
// by weight_floor, so a trace of a tile reads nothing.
const float projection_floor = 0.05;
const float weight_floor = 0.02;
// The second scale's level lies lower by log2 of its ratio.
const float far_lod_shift = 1.442695;
// The steepness (1 less the cosine to the local up) where rock starts and
// is full (40 and 50 degrees), and where sand gives way (30 to 40).
const float rock_start_steepness = 0.234;
const float rock_full_steepness = 0.357;
const float sand_start_steepness = 0.134;
const float sand_end_steepness = 0.234;
// The sun on the water (0297): the glint's sharpness and its brightness.
const float water_glint_power = 48.0;
const float water_glint_strength = 0.6;

// The tile's texel at a coordinate in tiles, wrapped inside its cell.
vec3 atlas_texel(uint tile, vec2 coordinate, float lod)
{
    vec2 cell = vec2(float(tile % atlas_columns), float(tile / atlas_columns)) * atlas_cell_texels;
    vec2 texel = cell + tile_margin_texels + fract(coordinate) * tile_texels;
    return textureLod(ground_atlas, texel / atlas_texels, min(lod, largest_lod)).rgb;
}

// One projection's plane at both scales, the second's coordinate scaled
// down by second_scale_ratio and its level lowered to match.
vec3 plane_color(uint tile, vec2 coordinate, float lod)
{
    vec3 near = atlas_texel(tile, coordinate, lod);
    vec3 far = atlas_texel(tile, coordinate / second_scale_ratio, lod - far_lod_shift);
    return mix(near, far, 0.5);
}

// The tile over the projections with a share.
vec3 tile_color(uint tile, vec3 position, vec3 blend, vec3 levels)
{
    vec3 color = vec3(0.0);
    if (blend.x > 0.0) {
        color += blend.x * plane_color(tile, position.yz, levels.x);
    }
    if (blend.y > 0.0) {
        color += blend.y * plane_color(tile, position.zx, levels.y);
    }
    if (blend.z > 0.0) {
        color += blend.z * plane_color(tile, position.xy, levels.z);
    }
    return color;
}

// The strata take the vertex's tint, the looks their colours.
vec3 tile_tint(uint tile)
{
    if (tile < strata_tile_count) {
        return fragment_color.rgb;
    }
    if (tile == grass_tile) {
        return fragment_grass_color;
    }
    if (tile == sand_tile) {
        return sand_color;
    }
    return snow_color;
}

// The open sky's light (0313, Field_Frame_Lights): the sky's light from
// above and the ground's bounce from below, shared by the normal's facing
// of the local up, and the sun's by its facing of sun_direction (the day
// clock's sun in the world's frame, 0297). The colours carry the time of
// day; the sun's is zero once it has set. outdoor_light is model.fs's
// line for line (shader_source_test.odin).
uniform vec3 sun_direction;
uniform vec3 sun_color;
uniform vec3 sky_color;
uniform vec3 bounce_color;

vec3 outdoor_light(vec3 normal, vec3 up, float sunlit)
{
    float upward = 0.5 + 0.5 * dot(normal, up);
    return mix(bounce_color, sky_color, upward) + sun_color * (sunlit * max(dot(normal, sun_direction), 0.0));
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
// apply_haze is model.fs's line for line.
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
    vec3 globe = min(globe_color * outdoor_light(up, up, 1.0), vec3(1.0));
    vec3 end_color = mix(globe, sky, haze_end_share);
    vec3 hazed = mix(color, sky, aerial * sky_share);
    return mix(hazed, end_color, smoothstep(fog_start, max(fog_end, fog_start + 1.0), reach));
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
    blend = max(blend - projection_floor, vec3(0.0));
    blend /= dot(blend, vec3(1.0));
    // The levels, outside every branch: per projection plane, the larger
    // of the two screen derivatives in texels.
    vec3 position = fragment_world_position / tile_metres;
    vec3 position_dx = dFdx(position);
    vec3 position_dy = dFdy(position);
    vec3 footprint = vec3(
        max(length(position_dx.yz), length(position_dy.yz)),
        max(length(position_dx.zx), length(position_dy.zx)),
        max(length(position_dx.xy), length(position_dy.xy)));
    vec3 levels = log2(max(footprint * tile_texels, vec3(smallest_weight_sum)));
    float weight_sum = dot(fragment_weights, vec4(1.0)) + dot(fragment_ore_weights, vec3(1.0));
    vec4 weights = fragment_weights / max(weight_sum, smallest_weight_sum);
    vec3 ore_weights = fragment_ore_weights / max(weight_sum, smallest_weight_sum);
    // The looks over the topsoil (0307); the planet's centre is the
    // origin, so the local up is the position's direction.
    float steepness = 1.0 - dot(normal, normalize(fragment_world_position));
    float topsoil = weights.x;
    float rock = topsoil * ground_look_on * smoothstep(rock_start_steepness, rock_full_steepness, steepness);
    float cover = (topsoil - rock) * ground_look_on * fragment_look.z;
    float snow = cover * fragment_look.x;
    float sand = (cover - snow) * fragment_look.y * (1.0 - smoothstep(sand_start_steepness, sand_end_steepness, steepness));
    float grass = cover - snow - sand;
    float tile_weights[ground_tile_count];
    tile_weights[0u] = topsoil - rock - cover;
    tile_weights[1u] = weights.y + rock;
    tile_weights[2u] = weights.z;
    tile_weights[3u] = weights.w;
    tile_weights[4u] = ore_weights.x;
    tile_weights[5u] = ore_weights.y;
    tile_weights[6u] = ore_weights.z;
    tile_weights[grass_tile] = grass;
    tile_weights[sand_tile] = sand;
    tile_weights[snow_tile] = snow;
    for (uint tile = 0u; tile < ground_tile_count; tile++) {
        tile_weights[tile] = max(tile_weights[tile] - weight_floor, 0.0);
    }
    // The largest weights first, at most most_tiles_read of them.
    vec3 albedo = vec3(0.0);
    float picked = 0.0;
    for (uint pick = 0u; pick < most_tiles_read; pick++) {
        uint largest = 0u;
        for (uint tile = 1u; tile < ground_tile_count; tile++) {
            if (tile_weights[tile] > tile_weights[largest]) {
                largest = tile;
            }
        }
        float weight = tile_weights[largest];
        if (weight <= 0.0) {
            break;
        }
        tile_weights[largest] = 0.0;
        albedo += weight * tile_color(largest, position, blend, levels) * tile_tint(largest);
        picked += weight;
    }
    albedo *= tint_scale / max(picked, smallest_weight_sum);
    float water = step(smallest_weight_sum, water_color.a);
    albedo = mix(albedo, water_color.rgb, water);
    // The sky light gates the open sky's light: a cave's samples have none
    // and take neither sky nor sun, the cheap shadow. Block light stays
    // the brighter per channel, never added, so a torch-lit wall keeps its
    // light whichever way it faces.
    float sunlit = sun_shadow_light(fragment_world_position, normal, camera_position);
    vec3 outdoor = fragment_color.a * outdoor_light(normal, normalize(fragment_world_position), sunlit);
    vec3 light = max(vec3(fragment_block_light), outdoor);
    vec3 lit = albedo * light;
    lit += albedo * point_light_sum(fragment_world_position, normal);
    lit += albedo * spot_light(fragment_world_position, normal);
    // The sun on the water, in the sun's colour: paid as a multiply by
    // water, not a branch.
    vec3 to_camera = normalize(camera_position - fragment_world_position);
    float glint = water * fragment_color.a * pow(max(dot(normal, normalize(sun_direction + to_camera + vec3(smallest_weight_sum))), 0.0), water_glint_power) * water_glint_strength;
    lit += sun_color * glint * sunlit;
    finalColor = vec4(apply_haze(min(lit, vec3(1.0)), fragment_world_position, camera_position, fragment_color.a), mix(1.0, water_color.a, water));
}
