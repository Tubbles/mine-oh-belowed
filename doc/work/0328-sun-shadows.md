# 0328: Sun shadows

Status: todo (2026-11-07)

0313 lights the landscape by the sun, the sky and the ground's bounce without shadows; its design left the sun's shadow of the terrain and the trees to an item of its own, after 0310's forests. Its estimate (from published hardware figures, not measured): one 2048 square cascade over 256 m adds about 300 draw calls a viewport (50 terrain chunks, 256 trees), 0.3 to 0.5 ms of GPU and 1 to 2 ms of CPU on the couch, 2 to 3.5 ms on the Steam Deck at a 1024 square map, 4 to 8 ms on the phone.

## Goal

The terrain, the trees, the landmarks and the buildings cast the sun's shadow near the player on the couch and the Deck, behind a setting; none on the phone.

## Controls

A setting on the options panel (on, off), its default per platform from data. No binding.

## Change

- A shadow cascade from the sun over the near field, the terrain's nodes and the instanced trees drawn into it with the fewest draw calls, read by the field, model and tree shaders with 0313's light.
- The setting, its default per platform, and the frame cost measured on the couch with a forest in view and estimated for the Deck.
- The shader rules of CLAUDE.md, checked through Mesa.
- Docs: `doc/presentation.md` (Light on the field).

## Verify

- The checks, the suite, `shader_source_test.odin`.
- Captures at morning and noon from the ground, under trees and beside a landmark, with and without; the frame cost on the couch and the Deck's setting; sent to the user.
