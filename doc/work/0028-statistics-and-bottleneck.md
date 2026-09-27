# 0028 Production statistics screen and bottleneck overlay

Status: implemented
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

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: new `production_statistics.odin` (list rows, letter jump, machine counts, marker colours), `ui_statistics.odin` (screen), `production_statistics_test.odin`; changes to `statistics.odin` (rings, consumed, per machine output rate), furnace, assembler, drill, lab, fluid machine and player ticks (consumption and output hooks), entity, render entities (markers), loop (overlay toggle and drawing), settings, session, input actions, UI core, input, screens, power, machine and crafting machine panels, diagnostics, `data/bindings.sjson`, `data/items.sjson`, `data/blocks.sjson`, `data/strings/en.sjson`, and the statistics, save, bindings and byproduct tests.

### Carry over from 0027: slag heaps

- Slag has `places_block = "slag_heap"`; the new `slag_heap` block (hardness 1.5, dark grey brown placeholder colour) mines back into one slag. Slag stays `cannot_recycle`. The concrete and brick placement test now covers slag too.

### Model and choices

- Rings: `Statistics.produced_rates` and `consumed_rates` (`Item_Rate_Rings`) replace `produced_per_second`. Each holds three rings of 60 buckets per item: per second (fine), per ten seconds and per minute. When the clock enters a new second, a ten second bucket whose span ended gets the sum of its fine buckets up to the last ticked second, a minute bucket likewise from its ten second buckets, and spans skipped without a tick are cleared. A window total is the open bucket of its level so far (taken from the finer rings) plus the 59 closed ones before it, so the 10 and 60 minute windows reach back 590 seconds and 59 minutes plus the open span; the rate is the total over the window's nominal minutes (10, 60), so early in a game those rates read low. Everything is integers, saved with the statistics through the reflective codec, so the layout fingerprint changed by itself.
- `consumed` per item: ingredients a craft took (hand crafts at completion, crafting machines and the recycler at craft start, furnaces at completion), science packs labs took, and fuel items burned by furnaces, crafting machines, drills, burner inserters and boilers. Measured as fuel and input slot shrinkage across the machine's tick (those slots only shrink there), or for drills and inserters from the lit fuel item. Boiler fuel is new to the statistics (`fuel_burned` still leaves boilers out, so quest hints keep their meaning); `tick_fluids` takes an optional statistics pointer for it.
- Per machine rate readout: a small lazy ring on the entity (`Machine_Output_Rate`, 60 per second `u16` buckets and the last second recorded) on furnaces, crafting machines and drills, saved with the entity. A record clears the seconds passed since the last one, so idle machines cost nothing per tick. Main output: the furnace's output slot growth, the first non byproduct product of a craft (all returns for the recycler), units a drill output. The panel line reads "Output: N/min" over the last minute. Labs (no item output) and fluid machines have no readout.
- Statistics screen: `Open_Statistics` (keyboard N, a pause menu button), tabs Production and Power (the power overview's body, factored out as `power_overview_body`). Production: a window choice row (1, 10, 60 minutes, Confirm cycles), a list of every item ever produced or consumed, sorted by produced over the window, then consumed, then item order, with the icon and both rates per minute, the letter wheel and keyboard letters jumping to the first row in list order whose name starts with the letter (the list is not name sorted), and the focused item's detail: both rates, machines making and using it now, and the voided total (all time; voided has no ring). The view state (window, focus) lives in the session.
- Machine counts: furnaces and crafting machines by their current recipe (the recycler by the recipe it reverses), drills by their vein's outputs and low grades, labs by the queued technology's packs, and any burner holding the item in its fuel slot as a consumer. Each machine counts once per side.
- Overlay: `Toggle_Bottleneck_Overlay` on keyboard O while no screen is open, plus a "Bottleneck overlay" toggle in the Display settings; it is the persisted setting `bottleneck_overlay`, so O is written to the settings file like any setting change. No gamepad binding yet. Markers on furnaces, crafting machines, drills, labs and fluid machines other than storage tanks; inserters, belts, chests, poles and lamps have none. Colours come from `machine_marker_colour(state, flag)` per kind: green working, yellow output full or waiting for room, red missing input, fluid, fuel, recipe, packs or an exhausted vein, grey idle. The flag: a furnace idle with fuel is red (starved, the verify case), without fuel grey (unused); an electric machine without power is red on a network and grey with none. The marker is a cube above the footprint whose size is `max(0.3, distance * 0.02)` blocks, about constant on screen beyond 15 blocks; it is drawn in the 3D pass with depth testing, so terrain hides it.
- Diagnostics: the world overlay shows "bottleneck overlay yes/no" and the O hint.

### Not verified

Everything visual and the feel: the statistics screen layout (list columns, detail column, window row, header) at 720p, 1080p and UI scale 1.5, icons in rows, focus and pointer on the new screen and the window row, the letter wheel on it, the Power tab inside the statistics panel, the pause menu height with ten buttons, marker colours and sizes near and far and whether depth testing hides too many, the slag heap texture, the new panel rows (furnace, drill and crafting machine panels grew by one row). The user verify (plate rate of the base, the starved furnace at a glance) is not run. The shipped data loads through the real loader (the binary starts and fails only at opening a window).

### Open questions

- A gamepad button for Open_Statistics and the overlay (only N, O, the pause menu and the settings toggle now)?
- Should voided get its own rings so the detail shows a voided rate instead of an all time total?
- Should an idle fixed choice crafting machine with empty inputs be grey rather than red (it reads Missing_Ingredients today)?
- Should inserters get overlay markers?
- The 10 and 60 minute rates divide by the full window from the first minute on; divide by the elapsed time instead while the game is younger than the window?
- `doc/ui.md` (statistics screen, overlay, rate readout), `doc/input.md` (N, O), `doc/architecture.md` (rings, consumed counter, per machine rate) and `doc/content.md` (slag heap) need updates; this run could not touch them.

