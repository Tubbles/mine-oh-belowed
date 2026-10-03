# 0032 Combustion generator and waste gas power

Status: implemented
Milestone: M7

## Goal

Power from gases and from solid fuel without steam: the combustion generator, so waste gas becomes electricity instead of flare, completing the byproduct rule for gases.

## Deliverables

- Combustion generator (3 by 2 by 2): a generator entity on the electric network offering up to 600 kW, burning either a gas from its input port (petroleum gas 2 MJ per 10 litres, wood gas 1 MJ per 10 litres, values in `data/fluids.sjson` as `fuel_kilojoules_per_litre`) or solid fuel from a fuel slot, gas preferred while present; it draws fuel only for the energy delivered like the steam engine.
- Technology `combustion_power` (75 packs, prerequisite oil processing) unlocks it.
- Power overview lists generators by type.
- Tests: energy accounting for gas and solid fuel, preference order, brownout sharing between a steam engine and a combustion generator, determinism.

## Verify

- Builds and tests pass.
- User: the flare stack goes quiet when a combustion generator takes the gas, and the power overview shows the new supply.

## Notes

- Carry overs from 0031: petroleum gas has `fuel_kilojoules_per_litre = 200`. `logistics_science` now also needs `plastics`, so it and `fast_belts` moved below `plastics` in `data/technologies.sjson` (a prerequisite must be listed earlier). This changes the data fingerprint, so older saves are refused as with any content change.
- The generator is a fluid machine of the new kind `combustion_generator` (3 by 2 by 2, 600 kW, one gas port on the -z face of the middle bottom cell, one fuel slot). Its offer is the tick's 600 kW capped by what `fuel_joules`, the burnable gas in its port and the fuel items in its slot are worth. On delivery it covers what `fuel_joules` lacks with whole litres of gas first, then lights fuel items one at a time through `refuel_from_slot`, and subtracts exactly the delivered energy, so produced equals consumed and the leftover waits in `fuel_joules`.
- Gas preference is per draw: energy already drawn (a litre, or a lit coal) is spent before anything new is drawn, so a coal lit while the port was dry is used up before newly arrived gas is touched. Nothing is wasted that way; the fuel slot is only touched while the port holds no burnable gas.
- A gas without a fuel value (steam) passes the port's gas phase filter and sits in the buffer offering nothing; the fuel slot still works. The panel shows the level, so the player can see it. A per fluid filter on the port could refuse it instead (open question).
- New state `Generating` (green marker). States follow the steam engine: generating while it delivers, no fuel while its network asks and it offers nothing, idle otherwise.
- Statistics: gas drawn counts as fluid consumed per fluid, fuel items lit count in `fuel_burned` and as consumed items. The boiler's items are counted consumed but not in `fuel_burned`; left alone.
- The power overview (and the statistics Power tab, which shares its body) lists generators grouped by machine with count and last tick output, under the generator count line, at most three types; `Consumer_Group` became `Participant_Group`.
- Guessed: the recipe (10 steel, 10 pipe, 5 circuit, 5 gear), 30 s per pack for `combustion_power`, the 200 L port buffer, the placeholder colours.
- No burn bar in the panel: `fuel_joules` mixes gas and item energy, so a bar against the last item's value would be misleading.
- Not verified: the panel layout, the brighter top and the overview lines on screen (headless session), and the user check that the flare stack goes quiet once a combustion generator takes the gas.
- Open question: nothing gives the generator priority over a flare stack on the same gas network; how the gas splits between them is not tested.
- Design documents not touched (outside this item's file list): `doc/fluids.md` needs an "As implemented in 0032" note and `doc/content.md` a combustion generator row.
