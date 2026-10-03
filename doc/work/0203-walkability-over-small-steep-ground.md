# 0203: Walkability: a short steep rise is a step, not a wall

Status: todo (user, 2026-10-03, digging holes: "it feels like determining walkability on slope angle alone doesnt cut it, a tiny but steep slope of 1 decimeter becomes unwalkable. we need some more sophisticated solution"; before 0189)

## Goal

The player walks over anything lower than the step height whatever its slope, and slides only on ground that is steep across the whole footprint. Today `walk_field_player` (`player_field.odin`) decides from the ground probe's normal under the feet alone: on ground steeper than `walkable_angle_degrees` the walk loses its uphill part and slides, and the step (`find_field_ledge`) is tried only from walkable ground, only when the walk was nearly fully blocked (`field_walk_blocked`), and only onto walkable ground. A dug lip of a decimetre reads as steep ground, so standing on it the player cannot walk up, and walking into it at an angle the sweep slides along it instead of stepping.

## Change

- The step is tried on every impeded walk, from walkable and steep ground alike: the walk is swept plain and stepped (raised by the step height, swept, dropped by the step height) and the result that travels farther along the walk direction is taken, provided the stepped end stands on ground within the walkable angle or the net rise is within the step height (a short steep rise is a step even though its own normal is steep).
- Walkable ground is judged over the footprint: the ground normal used for the walk and the slide is the plane through the ground heights probed at the feet and at the capsule radius around them (four probes), so a bump smaller than the footprint averages away and only ground steep across the capsule slides. The probe under the feet alone still decides on_ground.
- On steep ground with walkable ground within the step height above and a stride ahead, the walk steps there instead of sliding; the slide stays for a steep face taller than the step.
- The tuning stays in `game.sjson` (`step_height_samples`, `walkable_angle_degrees`, set to 60 by the user on 2026-10-03; a `walk_stride_millimetres` only if the stride cannot be the capsule radius plus a sample as `find_field_ledge` uses).
- The prediction (0182) runs the same procedure, so nothing changes there. `doc/architecture.md` (the field player's movement) and the header of `player_field.odin` say the new rule.

## Controls

- None.

## Verify

- The build and check commands of 0168.
- Tests, at every test spacing: a vertical wall of one decimetre is walked over head on and at 45 degrees without slowing; a wall of the step height plus a sample stops the walk (and mantles with Jump as today); a slope past the walkable angle and wider than the footprint slides as today; a bump past the angle but narrower than the footprint is walked over; standing in a dug hole with a lip under the step height the player walks out; the hash agrees on two sessions.
- The couch: the user digs holes and steps out of them.
