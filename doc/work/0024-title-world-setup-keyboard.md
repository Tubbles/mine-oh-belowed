# 0024 Title screen, world setup, on-screen keyboard

Status: todo
Milestone: M5

## Goal

The game starts at a title screen instead of straight into a world: Continue, New world, Load, Settings, Quit. New world asks for a name through the on-screen keyboard and offers the world settings. Load lists saved worlds.

## Deliverables

- Title screen as the first screen, with the world rendered behind it as a slowly turning view of a generated area or a plain backdrop (say which).
- New world screen: name field with the on-screen keyboard widget from `doc/ui.md` (QWERTY grid, focus and pointer, shift, space, backspace, done; physical keyboard types into the same field), seed field (random by default, editable digits), and the world settings from DESIGN.md: vein finiteness, vein richness, research cost multiplier, byproduct strictness (stored, no effect yet), all recipes unlocked at start, day length. Settings are written into `world.sjson` and read by the simulation where they already exist (veins infinite, all recipes unlocked, day length; richness and research cost wire into generation and lab cost).
- Load screen: saved worlds sorted by last played with name, seed and play time, Confirm loads, the context action deletes after a confirmation dialog.
- Continue loads the most recently played world.
- Quit to title from the pause menu (saving first).
- `--seed` and `--load` keep working for development; `--debug-terrain` skips the title.
- Tests: keyboard widget input handling (typing, shift, backspace, done), seed field validation, world settings round trip to `world.sjson`, save listing order.

## Verify

- Builds and tests pass.
- User: from the couch, create a world named with the on-screen keyboard using only the controller, play, quit to title, and continue it.
