# 0067 Particles and feedback

Status: todo
Milestone: M11

## Goal

Actions have no visible consequence beyond the block change. Debris, smoke, steam, sparks and exhaust make machines and mining read at a glance.

## Deliverables

- A small particle system on the renderer: mining debris in the block's colour, break puffs, furnace and boiler smoke, steam from engines, sparks from the alloy furnace, flare flame, rocket exhaust and launch smoke, the capsule descending under a parachute.
- Emitters driven by entity state at render time; nothing in the simulation.
- Tests: emitter selection per state as pure procedures.

## Verify

- Builds and tests pass.
- User: Screenshots of a working furnace line and a launch.
