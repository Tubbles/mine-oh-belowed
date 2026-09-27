# 0028 Production statistics screen and bottleneck overlay

Status: todo
Milestone: M6

## Goal

The two information tools the design builds in instead of leaning on mods: a production statistics screen with per item rates over time windows, and a bottleneck overlay that colours machines by their state in the world.

## Deliverables

- Statistics screen (new action, keyboard N, and a pause menu button): produced and consumed per item over 1, 10 and 60 minute windows from ring buffers extending the existing one minute ring (add coarser rings fed by the fine one), sorted by rate, with the item icon, letter wheel jump, and a detail row showing which machines produce and consume the focused item (counts from the entity pools). Power in the same screen as a second tab reusing the overview data.
- Bottleneck overlay: a toggle (keyboard B while no screen is open is taken by Sneak; use keyboard O and a settings toggle) that draws a small coloured marker over every machine: green working, yellow waiting for output room, red missing input or fuel or power, grey idle. Data comes from the machine states that already exist.
- A rate readout on every machine panel: items per minute actually produced over the last minute from the statistics.
- Tests: ring buffer coarsening, window rates, sorting, producer and consumer counting, marker colour from each machine state.

## Verify

- Builds and tests pass.
- User: the statistics screen shows the plate rate of the base and the overlay finds the one starved furnace at a glance.
