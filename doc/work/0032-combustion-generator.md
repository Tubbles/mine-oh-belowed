# 0032 Combustion generator and waste gas power

Status: todo
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
