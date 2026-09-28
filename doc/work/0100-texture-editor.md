# 0100 Texture editor

Status: todo
Milestone: M11

## Goal

The user (2026-09-28) wants to reroll and tune the procedural textures (0099) from the couch: an in-game editor in developer mode where each texture's seed and parameters change on the fly, with the data file's values to reset to, and a way to hand the chosen values to an agent that makes them the new defaults. The first of the game's editors (`DESIGN.md`, Editors): gamepad first, like every screen.

## Deliverables

- A Textures screen (new `src/ui_texture_editor.odin`, a new screen in the enum of `src/ui_core.odin`), opened by a Texture editor button in a new row of the Developer screen. Left: the procedural textures by block name, focusable rows, the selected one marked. Right, above: the preview, the selected tile at a large zoom beside a field of it, at least 6 by 6 tiles at 3 pixels per texel or more, each cell with the orientation and the brightness jitter the chunk shader gives it (`texture_variation.odin`, hashed from the cell), so the macro pattern is judged as in the world; each cell's texcoord goes through `varied_tile_texcoord` (0101), the procedure the 0099 preview field uses, so the offset shows too; drawn with the UI's image command (`.Image`, pixels pushed from the CPU, `src/ui_widgets.odin`). Right, below: the seed row (the value, step left and right by one, a Reroll button that takes a hash of the frame's tick and the old seed), one slider per parameter with its range and step from 0099, then Reset (the data file's entry for this texture), Save and Back.
- On the fly: any change regenerates the tile and updates the chunk atlas in place (`rl.UpdateTextureRec` on the tile's rectangles for the three face groups; `src/render_atlas.odin` knows the origins), so the world behind the panel shows it at once, and the preview uses the same pixels.
- Save writes every procedural texture's current parameters to `$XDG_STATE_HOME/mine-oh-belowed/texture_edits.sjson` (the overrides file 0099 reads at start) in the data file's format, and logs one line per texture in that format, so an agent copies the entry into `data/textures/procedural.sjson`. Unsaved edits live until the game exits. A toast names the file written.
- Command socket: `query textures` answers one line per procedural texture with its current parameters in the file's format (`doc/commands.md`).
- Strings in `data/strings/en.sjson`; the glyph audit passes. The UI audit (`src/ui_audit_test.odin`) covers the screen at every size, text scale and glyph set, with a screen context that holds a texture list.
- Tests: the seed step and the reroll are pure; the preview field's cell orientation matches `face_tile_orientation`; the save file round trips through 0099's parser; the audit.
- Docs: `doc/ui.md` (the screen), `doc/commands.md`, `doc/log/<date>.md`, this item.

## Verify

- `./build.sh check`, `./build.sh test`, `./build.sh release` pass.
- User on the couch: open the editor from the Developer screen with the pad, pick an ore, reroll, step a slider with the d-pad and drag it with the trackpad, watch the outcrop behind the panel change, Save, then read the values with `tools/moc query textures`.

## Notes

Files a subagent may touch: new `src/ui_texture_editor.odin` and its test, `src/ui_developer.odin`, `src/ui_core.odin` (the screen enum and the screen context), `src/ui_screens.odin` (the screen dispatch), `src/loop.odin` (the context fields and the atlas update), `src/render_atlas.odin` (the tile update), `src/texture_generate.odin` (the overrides writer), `src/command.odin` and `src/command_test.odin`, `src/ui_audit_test.odin`, `data/strings/en.sjson`, the docs above, this file.
