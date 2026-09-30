# 0140: A fuel generator for the first electricity, and a powered offshore pump

Status: todo

## Goal

Asked on 2026-09-30, following 0139: "I also think the offshore pump should require electricity, and that we can introduce some sort of generator that we can feed with coal and logs etc". Today the offshore pump runs without power (`doc/fluids.md`), and the only generator that burns solid fuel is the combustion generator, which arrives with combustion power after oil processing and draws gas first. The first electricity is meant to come from a small generator that eats what the player already mines and chops; the steam plant is the scale up.

## Change

- Data: a new machine `fuel_generator` (`data/machines.sjson`, kind `combustion_generator` without fluid ports if the kind tolerates that, else a kind of its own with the same fuel path): footprint 2 by 2 by 2, one fuel slot, `electric_output_kilowatts = 150`, burning any item with a fuel value (coal, logs, charcoal, planks, what `fuel_power_kilowatts` machines already accept). Its recipe (`data/recipes.sjson`) is hand craftable on the start channel from iron plates, iron gears, a stone furnace and copper wire or whatever the phase 1 to 3 materials in `doc/content.md` allow, so it comes before the steam engine; the technology gating follows the small pole's. An item, a placeholder model through the script that made the other machines' models (`tools/`, `.vox`), an icon if machines have icons, strings, a description and a note if machines have notes.
- The offshore pump gets `electric_power_kilowatts = 60` and draws like the pump: unpowered it pushes nothing and its panel says Unpowered; with the 0139 head it pressurises its network only while powered. The tar pit pump is already powered.
- The quest chapter that introduces steam power (`data/quests/`) gains the fuel generator before the offshore pump where it places the offshore pump, so the chapter still completes; check `doc/quests.md` for the chapter's steps and the starting items (`data/game.sjson`), which must not need changing.
- Balance numbers are placeholders like the rest (`SUGGESTIONS.md`, balance deferred): 150 kW feeds the offshore pump, an electric drill and a few inserters; coal's fuel value sets how long a stack lasts.
- Docs: `doc/fluids.md` (Sources and sinks: the offshore pump's power, the fuel generator under Power with an "As implemented in 0140" note), `doc/content.md` (Machines: the fuel generator, the offshore pump's power), `doc/quests.md` if the chapter text changes, `doc/log/2026-09-30.md` with the decision (why a small fuel generator rather than a free offshore pump: the plant starts from what is mined, the steam plant scales it).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: the fuel generator with coal in its slot offers 150 kW and burns fuel only for the energy delivered, produced equals consumed (the combustion generator's tests as the pattern); an unpowered offshore pump pushes nothing and a powered one 1200 litres per second; the steam chapter's quest completes in the chapter test with the fuel generator placed; the recipe and technology graph validates; the model and icon load.
- The user: place a fuel generator with coal, a small pole and the offshore pump, see water flow; remove the coal, see the pump say Unpowered.
