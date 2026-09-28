# 0091 Recipe browser: have and need, unlocked only, the missing glyph

Status: todo
Milestone: M11

## Goal

Couch report (2026-09-28): the recipe page should say how much of each ingredient the player has ("13/5 stone", not "5 stone"), it needs a filter for unlocked recipes only, and with the Oxanium font the ingredient line reads "1 ? Concrete".

## Deliverables

- Ingredient rows (`draw_stack_rows` in `src/ui_recipes.odin`) read "13 / 5 Stone" (have, then need, then the name) with the have count in the accent colour when it covers the need and the danger colour when it does not, and the detail panel says how many crafts the inventory covers ("Can craft 2"). Output rows keep the count and the name.
- A filter toggle "Unlocked only" in the browser's filter row (`Recipe_Filter` in `src/recipe_browser.odin` gains `unlocked_only`, default on; the existing available flag decides), remembered per session.
- The missing glyph: the multiplication sign in code formats (`src/ui_recipes.odin`, `src/technology_browser.odin`, `src/ui_contracts.odin`) is not in the string table, so the font cache never loads it and Oxanium shows "?". Move those formats into `data/strings/en.sjson` keys with `{count}` and `{name}` marks (`format_message_text`), which loads the glyph with the rest, and add a test in `src/data_strings_test.odin` that every non ASCII code point in the string table exists in every shipped font family (`src/ui_font.odin` can read a font's glyph set through the loader used for the atlas, or the test lists the code points and the loader checks them at start and logs a missing one).
- Tests: the have and need text, the craft count, the filter, the glyph audit.
- Docs: `doc/ui.md`, `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: the stone furnace row reads "13 / 5 Stone"; the filter hides locked recipes; no "?" in Oxanium.

## Notes

Files a subagent may touch: `src/ui_recipes.odin`, `src/recipe_browser.odin`, `src/recipe_browser_test.odin`, `src/technology_browser.odin`, `src/ui_contracts.odin`, `src/ui_font.odin`, `src/ui_font_test.odin`, `src/data_strings_test.odin`, `src/ui_audit_test.odin`, `data/strings/en.sjson`, the docs above, this file.
