# 0386: Foundations stay bright at night

Status: todo (2026-11-13)

## Goal

A foundation pad on a field world takes the time of day like the ground and the machines on it. Seen in 0368's captures (main agent, 2026-11-13): at dusk and at night a pad of wooden foundations draws at its noon brightness while the terrain, the trees and the machines standing on it go dark. `main` before 0368 shows the same (a pad of 0362's layout at dusk), so the cause is older than both; which landing brought it is not known.

## Change

- Find where the foundation cells' draw leaves the scene's light (the sun term, the ambient or the shadow pass) and give it what the machines' draw takes.

## Verify

- A test on the light the foundation batch is drawn with, where one can be written without GL.
- Captures of a pad with machines at noon, dusk and midnight, before and after.
