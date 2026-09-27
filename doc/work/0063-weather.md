# 0063 Weather

Status: todo
Milestone: M11

## Goal

Rain, fog, wind, cloud shadows and snow in cold biomes, cosmetic in alpha so the world stays peaceful and needs no balancing.

## Deliverables

- A weather state per world (clear, overcast, rain, fog, snow in cold biomes) changing over game hours from the seed and the tick, saved.
- Rendering: rain and snow particles around the player, wet ground darkening, fog density, wind swaying leaves and grass through a vertex shader, cloud shadows as a scrolling light modulation.
- A weather setting (on or off) for reduced motion.
- Tests: the weather schedule is deterministic and saved.

## Verify

- Builds and tests pass.
- User: Watch a rain pass; screenshots.
