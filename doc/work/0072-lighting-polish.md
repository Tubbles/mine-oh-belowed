# 0072 Lighting polish

Status: todo
Milestone: M11

## Goal

Light is white and flat. Coloured light from lamps and furnaces, torch flicker, smooth day transitions, and sun shadows if they are cheap.

## Deliverables

- Block light carries a colour per emitter in data; the chunk shader blends it; torches flicker slightly; day transitions ease.
- A cheap sun shadow (a single cascade shadow map on the terrain near the player) behind a setting, measured on the couch machine.
- Tests: light colour propagation stays bounded and deterministic.

## Verify

- Builds and tests pass.
- User: Screenshots at night by a furnace.
