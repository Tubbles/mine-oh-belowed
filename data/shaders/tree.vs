#version 330

// Tree vertex shader (work item 0310, render_field_trees.odin), for the
// near models and the far cards alike. Each instance's transform comes
// in instanceTransform (raylib's DrawMeshInstanced for the near models,
// a tile's buffer at locations 9 to 12 for the cards): the tree's axes
// scaled by the pitch and its scale, the base as the translation, in the
// world's metres, with the species and the shade in place of the bottom
// row (tree_instance), which is rebuilt to 0, 0, 0, 1 here. With card_on
// at 0 the vertex is the model's; at 1 vertexPosition holds the card,
// u and v of one of the three crossed quads (along forward, along right,
// from above), built from the species' card (half width, top, crown,
// atlas row; species_card) and read from the atlas of card_rows rows.
// A card instance whose base lies nearer than near_distance less
// fade_metres, farther than far_distance, or whose species has no card
// (row -1) puts every vertex outside clip space. The near fade (the
// model's share leaving over fade_metres before near_distance) and the
// far fade (the card's over the last far_fade_metres) go to tree.fs.
// Every integer literal carries the u suffix (work item 0105,
// shader_source_test.odin).

in vec3 vertexPosition;
in vec3 vertexNormal;
in vec4 vertexColor;
in mat4 instanceTransform;

uniform mat4 mvp;
uniform float card_on;
uniform vec3 camera_position;
uniform float card_rows;
uniform float near_distance;
uniform float fade_metres;
uniform float far_distance;
uniform float far_fade_metres;
// Per species (MAXIMUM_TREE_SPECIES): the tint, 0 to 1, and
// the card's half width, top and crown in the model's units and its row.
uniform vec3 species_tint[8u];
uniform vec4 species_card[8u];

out vec3 fragment_world_position;
out vec3 fragment_normal;
out vec4 fragment_color;
out vec2 fragment_texcoord;
out vec3 fragment_crown;
out vec3 fragment_tint;
out float fragment_near_fade;
out float fragment_far_fade;

// The atlas's layout (render_tree_cards.odin).
const float card_cell_texels = 128.0;
const float card_margin_texels = 2.0;
const float card_atlas_texels = 512.0;
const vec4 outside_clip = vec4(2.0, 2.0, 2.0, 1.0);

void main()
{
    uint species = min(uint(instanceTransform[0u][3u] + 0.5), 7u);
    float shade = instanceTransform[1u][3u];
    mat4 model = instanceTransform;
    model[0u][3u] = 0.0;
    model[1u][3u] = 0.0;
    model[2u][3u] = 0.0;
    model[3u][3u] = 1.0;
    vec3 base = model[3u].xyz;
    float reach = length(base - camera_position);
    fragment_near_fade = clamp((reach - (near_distance - fade_metres)) / max(fade_metres, 0.001), 0.0, 1.0);
    fragment_far_fade = clamp((reach - (far_distance - far_fade_metres)) / max(far_fade_metres, 0.001), 0.0, 1.0);
    fragment_tint = species_tint[species] * shade;
    vec4 card = species_card[species];
    fragment_crown = (model * vec4(0.0, card.z, 0.0, 1.0)).xyz;
    if (card_on < 0.5) {
        vec4 world = model * vec4(vertexPosition, 1.0);
        fragment_world_position = world.xyz;
        fragment_normal = mat3(model) * vertexNormal;
        fragment_color = vertexColor;
        fragment_texcoord = vec2(0.0);
        gl_Position = mvp * world;
        return;
    }
    uint view = uint(vertexPosition.x + 0.5);
    float u = vertexPosition.y;
    float v = vertexPosition.z;
    float across = (2.0 * u - 1.0) * card.x;
    vec3 local = vec3(across, v * card.y, 0.0);
    if (view == 1u) {
        local = vec3(0.0, v * card.y, across);
    } else if (view == 2u) {
        local = vec3(across, card.z, (2.0 * v - 1.0) * card.x);
    }
    vec4 world = model * vec4(local, 1.0);
    fragment_world_position = world.xyz;
    fragment_normal = vec3(0.0);
    fragment_color = vec4(1.0);
    float inner = card_cell_texels - 2.0 * card_margin_texels;
    fragment_texcoord = vec2((float(view) * card_cell_texels + card_margin_texels + u * inner) / card_atlas_texels, (card.w * card_cell_texels + card_margin_texels + v * inner) / (card_cell_texels * max(card_rows, 1.0)));
    bool hidden = card.w < 0.0 || reach < near_distance - fade_metres || reach > far_distance;
    gl_Position = hidden ? outside_clip : mvp * world;
}
