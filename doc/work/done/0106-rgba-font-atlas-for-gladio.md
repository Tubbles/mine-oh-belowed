# 0106 RGBA font atlas for Gladio

Status: implemented
Milestone: M11

## Goal

On the phone (Winlator, Gladio, 2026-09-29) the title screen renders, but every glyph sits in an opaque red box: yellow letters, red where the glyph is clear. raylib keeps font atlases in `PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA` and on OpenGL 3.3 uploads them as `GL_RG8` with a texture swizzle `{RED, RED, RED, GREEN}` set through `glTexParameteriv(GL_TEXTURE_SWIZZLE_RGBA)` (`rlgl.h`, `rlLoadTexture`). Gladio forwards that call to the phone's GLES driver, which has no `GL_TEXTURE_SWIZZLE_RGBA` (only the four single-channel parameters), so the swizzle is dropped and the texture samples as (gray, alpha, 0, 1): (1, 0, 0) opaque red where alpha is 0, (1, 1, 0) yellow where it is 1. Gladio does swizzle the legacy `GL_LUMINANCE_ALPHA` upload path (`texture_utils.h` in `brunodev85/gladio`, copy under `tmp/gladio/`), but raylib only takes that path on GLES 2. Every PNG under `data/` is RGBA and the generated images are `GenImageColor`, so the font atlas is the only two-channel texture the game uploads, and `rl.GetFontDefault()` is another one (raylib's built-in font), used only when a font file fails to load.

## Change

- `load_cached_font` (`src/ui_font.odin`) builds the font itself instead of `rl.LoadFontEx`, the way raylib's `LoadFontFromMemory` does, with the atlas converted to RGBA before upload: `rl.LoadFileData` on the path, `rl.LoadFontData(data, size, key.pixel_size, code_points, count, .DEFAULT)`, `rl.GenImageFontAtlas(glyphs, &recs, count, key.pixel_size, padding, 0)` with raylib's default TTF padding of 4 (`FONT_TTF_DEFAULT_CHARS_PADDING` in `rtext.c`; `Font.glyphPadding` is set to it), `rl.ImageFormat(&atlas, .UNCOMPRESSED_R8G8B8A8)`, `rl.LoadTextureFromImage`, `rl.UnloadImage(atlas)`, `rl.UnloadFileData`. Fill `rl.Font{baseSize, glyphCount, glyphPadding, texture, recs, glyphs}`. `UnloadFont` still frees it, since `LoadFontData` and `GenImageFontAtlas` allocate through raylib. The failure path (no data, or no glyphs) keeps logging and falling back to `rl.GetFontDefault()` as today; note in the item that the fallback font stays two-channel.
- Put the RGBA conversion in one small procedure, `load_rgba_texture(image: rl.Image) -> rl.Texture2D` (or a name of your choice), that reformats a non-RGBA image before `rl.LoadTextureFromImage`, and use it at the six upload sites (`render_belts.odin`, `render_atlas.odin`, `render_weather.odin`, `render_icons.odin`, `render_sky.odin`, `ui_draw.odin`) and for the atlas, so a future gray PNG or generated image cannot reintroduce the problem. Do not change what those images contain.
- Documentation in the same commit: a sentence in `doc/architecture.md` where fonts are described (the atlas is uploaded as RGBA because Gladio drops raylib's two-channel swizzle) and one in the rendering part for `load_rgba_texture`; a Code rules bullet in `CLAUDE.md` (textures go up as RGBA through the one helper, gray and gray alpha formats render red on the phone); an entry in `doc/log/2026-09-29.md` (tags `#windows #textures #gladio #decision`) with the diagnosis above.

## Verify

- `./build.sh check`, `./build.sh check-windows`, `./build.sh test`.
- `./build.sh release` links.
- User: the couch title screen looks as before (same glyph shapes and spacing, bilinear filter), and the phone shows text without boxes.

## Implemented

2026-09-29: `load_font_file` in `src/ui_font.odin` builds the font with `LoadFileData`, `LoadFontData`, `GenImageFontAtlas` (padding 4) and uploads the atlas through `load_rgba_texture` (`src/render_atlas.odin`), which converts a copy of any non RGBA image, since `ImageFormat` frees the pixels it replaces and most callers' images point at Odin memory. The six upload sites use the helper. raylib's glyph image replacement loop in `LoadFontFromMemory` (for `ImageDrawText`) is left out, since the game never draws text into images. The fallback `rl.GetFontDefault()` stays two-channel, so a missing font file still shows red boxes on the phone. Verified here: `./build.sh check`, `./build.sh check-windows`, `./build.sh test` (1053 tests pass) and `./build.sh release` (links). Not verified here: the couch and phone rendering, which needs the user.
