# 0274: Flames in the furnace and on the torch

Status: todo (2026-10-05, from the user)

## Goal

The stone furnace's firebox burns with live flames instead of the static glowing sheet and tongues of its model (user, 2026-10-05: "chuck the glowing hot mess that tries to be flames"), and the torch's flat flickering quad takes the same flame. One flame shader for both, from the research (`work/research/flames-2026-10-05.md`, untracked) and under DESIGN.md's Fire rule: a flow, soft edged as Techtonica's plume, a fixed ramp for the fuel, flicker without period, a light that flickers with it.

## Controls

No binding changes.

## Change

- A flame shader (`data/shaders/flame.fs`, `flame.vs`): value noise fBm scrolled up with a distortion growing with the height, a teardrop mask, a fixed continuous ramp (a yellow white core, an orange body, dark red tips for coal and wood), soft edged with a glow, flicker from hashed noise with no period, still under reduced motion; the size, the ramp and the direction as uniforms.
- The furnace: three to five fanned quads in the firebox mouth, fixed to the model so they read from the side, drawn only while the furnace works (as its glow motion); the coal bed's emissive pulsing slowly; a firebox point light in the flames' colour flickering with them, through the record's `lights`. The static flame sheet and the three tongues removed from `tools/models/machines/stone_furnace.py`, the OBJ regenerated (the coal bed and the frame stay).
- The torch (`render_flames.odin`): the same shader on its quad at `FLAME_SIZE`, the two colour flicker replaced by the ramp and the noise.
- Docs: `doc/presentation.md` (Machine models, the furnace; the torch flames), `DESIGN.md` if the rule needs a word, `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, `./build.sh model-check` on the furnace; `shader_source_test.odin` on the new shader.
- Tests: the flames and the light are off while the furnace idles; the flicker has no period; the model's triangle count stays under the budget.
- Screenshots of the working furnace from the front and the side, and of a torch, sent to the user before the landing.
- The couch: a furnace at work reads as a fire.
