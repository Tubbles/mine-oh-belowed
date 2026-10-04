# 0217: The editor's glyph bar overlaps the hotbar

Status: cancelled (2026-10-04, folded into 0219, The fit; found in the headless screenshots of 0215 at 1280 by 720: the placement editor's four glyphs (Move, Turn, Place, Cancel) are drawn over the hotbar's three rightmost slots)

## Goal

The HUD's glyph bar never covers the hotbar. In the placement editor the bar holds four entries (the nudge, the turn, the commit and the cancel), wider than the two of the world, and at 1280 by 720 its left end sits on the hotbar's slots 6 to 8 (`tmp/xdg0215/state/mine-oh-belowed/screenshots/editor_41_anchored.png` of 2026-10-04, the keyboard glyphs; the gamepad's are narrower but the touch sizes are smaller).

## Change

- The glyph bar is laid out against the hotbar's right edge: when its width would reach past the hotbar's right edge at the audit size, it wraps into a second row above the first, or moves up a row above the hotbar, whichever `hud.odin` already does for the touch row (0215 stacks the touch row when it does not fit); the design stage picks the one that keeps the glyphs readable at the smallest audit size and says why.
- The UI audit gets a case with the editor's four glyphs at every size, and the test asserts no glyph box intersects a hotbar slot box.

## Verify

- `test_the_glyph_bar_never_covers_the_hotbar` (or the audit's assertion) at every audit size, keyboard and gamepad glyphs.
- A headless screenshot at 1280 by 720 with the editor anchored, sent to the user.
