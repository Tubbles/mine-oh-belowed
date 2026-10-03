# 0201: Machines on bare ground wear out

Status: implemented (user, 2026-10-03: "all machines should be buildable without foundation, given roughly flat terrain, but they break down after X minutes/hours of operation and you need to go there and tear it down (yielding say 80 % of the raw materials that went in, stone, iron plates, etc) and then build it up again, so its a temporary thing (except belt poles, pipes etc)"; after 0195, before 0194)

## Goal

A machine stands on flat ground without a foundation, but not for good: it runs for a while, breaks down, and is torn down for most of its materials and built again. A foundation makes it permanent. Today a machine other than a foundation over bare ground is refused (`Needs_Foundation`, 0187), and belt poles are the only machines that stand on the ground on their own.

## Change

- Placement on bare ground: with a machine held, no frame targeted and ground in reach, the ground under the footprint is checked for flatness (the surface heights under the footprint's corners and centre within `bare_ground_flatness_millimetres` of each other, in `game.sjson`); flat enough places the machine on a new frame of its own with no foundation (`free_frame_at` as for a foundation, the machine at cell (0,0,0), the frame removed when its last machine goes); too steep is refused with a new `Field_Edit_Refusal` ("Too steep, needs a foundation") and the red ghost. `Needs_Foundation` goes. The pod's crater floor (0199) is flat by construction.
- Wear: a machine on a frame without foundations under its cells (`machine_is_founded`, read when it is placed and when a foundation is placed or picked up under it) accumulates operation ticks while it works (not while idle, so a waiting furnace lasts); at `bare_ground_life_minutes` of operation (in `game.sjson`, with a per machine override in the record for the user to tune: "X minutes/hours") it breaks down: it stops working, its marker turns red (`Marker_Colour.Red`, as a machine without power), a toast names it once when it breaks ("Stone furnace broke down", through the records' notices as finished research is told), its panel and the hint beside it say "Broken down, tear it down", and the model is tinted. (The HUD has no alert row for stalled belts; the item's first text was wrong there, corrected 2026-10-03.) The counter is simulation state, saved, hashed.
- Tear down: picking a broken or a worn machine up (0195) returns `salvage_percent` (80 in `game.sjson`) of its recipe's direct inputs, rounded down per item, plus its contents as today; an unworn machine on a foundation returns itself as today. Building it again on the spot starts a fresh life.
- Exempt kinds never wear and are never refused for slope: belt poles, poles, pipes, belts and the pod's fixtures; a machine record flag `stands_on_ground` (default false) marks them, the records of those kinds set it, so content decides.
- `doc/content.md` (Machines: standing on ground, wear, salvage; the new values), `doc/architecture.md` (frames without foundations, the wear tick), `doc/hud.md` (the toast, the hint), the log.

## Controls

- None new: Place on flat bare ground places, Mine (0195) tears down. The tool line over bare ground says "On bare ground, wears out in N min" so the user knows what they are building.

## Verify

- The build and check commands of 0168.
- Tests: a furnace placed on flat ground stands on a frame with no foundation and runs; on a slope past the tolerance it is refused with the new refusal; a furnace on a foundation never wears; one on bare ground breaks down after its minutes of operation and not while idle; tearing it down returns 80 % of its recipe's inputs rounded down and its contents; a belt pole and a pipe never wear; the counter round trips a save and the hash agrees on two sessions.
- The couch: the user builds a furnace on the ground, runs it until it breaks, tears it down and rebuilds it.
