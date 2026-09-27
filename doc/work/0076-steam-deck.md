# 0076 Steam Deck verification

Status: todo
Milestone: M11

## Goal

The Steam Deck is a supported target (user, 2026-09-27). The game must hold its frame rate on the Deck's APU at 1280 by 800, its UI must fit and read at arm's length, and the Deck's built in pads, gyro and grips must work through Steam Input the way the couch does.

## Deliverables

- Performance: the benchmark (0050) run on a Deck, a frame rate cap setting (30, 40, 60) and the rendering settings (shadows, weather particles, view distance) tuned for a Deck preset chosen automatically when the device is a Deck (`SteamDeck=1` in the environment).
- UI: the audit's 1280 by 800 entries stay green, text sizes checked at arm's length, the safe area for the Deck's screen.
- Controls: SDL's Steam Deck HIDAPI driver behind the same launcher override, pads, gyro (from Steam's layout, 0044 notes) and the four grips mapped like the Steam Controller's; verified in Game Mode on the device.
- A Deck section in `doc/input.md` and `doc/build.md` (installing the play build on a Deck over SSH).

## Verify

- Builds and tests pass.
- User: a full chapter 1 on the Deck at a steady frame rate with the built in controls.
