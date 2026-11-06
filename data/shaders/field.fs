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
// colours; then the light is multiplied in: the brighter of the
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
// The water's vertices have no weights, so it reads no tile.
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
in float fragment_distance;

// Every tile in cells of the atlas (field_ground_atlas_pixels).
uniform sampler2D ground_atlas;
// 1 with a climate, 0 without (set_field_ground_look_uniforms), and the
// sand's and the snow's colours, 0 to 1.
uniform float ground_look_on;
uniform vec3 sand_color;
uniform vec3 snow_color;
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
    // The sky light gates the sun: a cave's samples have none and take
    // no sun, the cheap shadow. Block light stays the brighter, never
    // added, so a torch-lit wall keeps its light whichever way it faces.
    float sun_facing = max(dot(normal, sun_direction), 0.0);
    float sun_light = fragment_color.a * daylight * (sky_ambient + sun_strength * sun_facing);
    float light = max(fragment_block_light, sun_light);
    vec3 lit = albedo * light;
    lit += albedo * point_light_sum(fragment_world_position, normal);
    lit += albedo * spot_light(fragment_world_position, normal);
    // The sun on the water: paid as a multiply by water, not a branch.
    vec3 to_camera = normalize(camera_position - fragment_world_position);
    float glint = water * fragment_color.a * daylight * pow(max(dot(normal, normalize(sun_direction + to_camera + vec3(smallest_weight_sum))), 0.0), water_glint_power) * water_glint_strength;
    lit += vec3(glint);
    float fog = clamp((fragment_distance - fog_start) / (fog_end - fog_start), 0.0, 1.0);
    finalColor = vec4(mix(min(lit, vec3(1.0)), fog_color, fog), mix(1.0, water_color.a, water));
}
