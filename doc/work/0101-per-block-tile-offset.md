# 0101 Per block offset for periodic tiles

Status: todo
Milestone: M11

## Goal

Found in the 0099 previews (2026-09-28): every varying tile is periodic (the script's noises wrap, the generator works on the torus), and with 0088's eight orientations two neighbours whose orientations mirror across their shared edge form a symmetric motif there, a kaleidoscope plain in the galena and pentlandite fields; a half turn gives a point symmetric pair. The principle is no perceivable pattern (`DESIGN.md`). The fix: slide the tile by a per block offset as well. A periodic tile shows no seam inside the block at any offset, and no two neighbours show the same crop, so no symmetry survives.

## Deliverables

- `data/shaders/chunk.fs` and `src/texture_variation.odin`: after the mirror and the turns, the tile texcoord is shifted by an offset of whole texels taken from further bits of the same hash (bits 3 to 6 for x, 7 to 10 for y, 0 to 15 texels each), wrapped inside the tile, for faces that vary; faces that keep their orientation get no offset. The Odin mirror (`tile_offset(hash) -> [2]int` and the texcoord procedure) follows the shader, with tests that the offsets spread over the 16 by 16 values and that kept faces get offset 0. The shader's clamp to the tile's last texel still applies after the shift. `water.fs` gets the same offset if the water tile is periodic and the flow's texcoord animation still reads right (the offset keeps the axes); report either way.
- A periodicity check over the shipped tiles: a test reads every block texture file under `data/textures/blocks/` whose faces vary (no `keep_orientation`, and the top and bottom files of every block, which always vary) and checks that the seam across the wrap (column 15 beside column 0, row 15 beside row 0) is no rougher than the interior: the mean absolute channel difference across the wrap edge within a factor of the mean across interior edges; settle the factor by measuring and report the ratios. Every varying tile must pass, or its pattern in `tools/make_placeholder_textures.py` is made to wrap and the file regenerated (report which). The script's noises (`noise`, `smooth_noise`, `isotropic_field`) wrap by design, so the expectation is that all pass; the test guards future files. Tiles with transparent texels (the cover plants, the torch) are drawn per cell and are excluded.
- The 0099 previews (`test_write_ore_texture_previews`, `-define:TEXTURE_PREVIEW=true` with the linker shims, command in `src/texture_generate_test.odin`) apply the offset per cell as the shader would, through the shared Odin procedure.
- Docs: `doc/architecture.md` (the shader line), `doc/content.md` (the `keep_orientation` line: varying tiles must be periodic, checked by the test), `DESIGN.md` (No perceivable repetition: the offset joins the turn and the mirror), `doc/log/2026-09-28.md`, this item, and one line in `doc/work/0100-texture-editor.md` saying the preview field uses the shared procedure.

## Verify

- `./build.sh check`, `./build.sh test`, `./build.sh release` pass.
- Read the seven field previews after the change and say whether any symmetric motif remains.
- User: an ore outcrop shows no kaleidoscope, and stone, dirt and leaves look as before or better.

## Notes

Files a subagent may touch: `data/shaders/chunk.fs`, `data/shaders/water.fs`, `src/texture_variation.odin`, `src/texture_variation_test.odin`, `src/texture_generate_test.odin`, new `src/texture_periodicity_test.odin`, `tools/make_placeholder_textures.py` and regenerated files under `data/textures/blocks/` only if a pattern fails the check, the docs above, this file, `doc/work/0100-texture-editor.md`.
