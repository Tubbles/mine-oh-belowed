# 0172: The water field

Status: todo (after 0171)

## Goal

Water as a second field: a fill fraction per sample moved by a cellular rule towards the planet's centre, awake samples only, volume conserved, the sea and springs as infinite sources, a minimum depth below which water stops and dries, meshed by the field mesher (0167, Water; DESIGN.md, The world).

## Change

- A `world_field_water` file: a byte of fill per sample stored beside the terrain samples or in a parallel chunk array (say which and why), present only where the terrain density is below the surface. Each tick, every awake sample moves fill to neighbours with lower potential (the distance to the centre in fixed point, from the sample's position) and equalises among equals, in sample order; a sample sleeps after a number of still ticks and wakes when a neighbour changes. Fill below the minimum depth stops moving and drops by one every so many ticks (values in data).
- Sources: any non terrain sample below the planet's sea level outside the simulated region counts as full; inside it the sea's edge samples are source samples; spring samples placed by generation (one basin in the slice) are sources; rain is a stub (a rate per biome in data, applied in M15's weather).
- Flow per sample recorded for hydro later.
- The water mesh: the mesher of 0169 over the water field with a water material and the terrain as the lower bound, drawn translucent.
- The block water (`world_water.odin`) stays until M14.
- `doc/architecture.md` (water) and `doc/presentation.md` (water) updated.

## Verify

- The build and check commands of 0168.
- Tests: a column of water poured into a basin settles with a level surface (equal potential) and the total fill unchanged; breaching the basin's wall drains it into the lower basin and the total is unchanged; a pond pumped (a test sink) empties, a sea edge sample never does; a film below the minimum depth stops and dries; a settled basin has no awake samples; the same sequence on two instances gives the same bytes.
