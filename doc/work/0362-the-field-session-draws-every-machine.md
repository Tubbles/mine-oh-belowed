# 0362: The field session draws every machine

Status: todo (2026-11-11)

Found by 0347's design: `draw_fluid_entities` and `draw_power_entities` are called only from the block world's pass (`loop.odin`), so on a field world a boiler, a steam engine, a pipe, a pump, a tank, a lamp and a pole are placed and simulated and never drawn. And `draw_drill`'s bar and arrow and `draw_launch_pad`'s fallback platform, tower and rocket draw in raw cells without their frame's matrix, so on a planet they land near its centre.

## Goal

Everything placed on a field world is drawn where it stands.

## Controls

None.

## Change

- The field session's entity pass draws the fluid and the power machines under their frames' matrices, lit and hazed as the other machines.
- The drill's bar and arrow and the launch pad's fallback take their frame's matrix.
- After 0347, through its instance list, and with 0355 in mind: the poles leave the content there, and a cable's draw is that item's.

## Verify

- The checks and the suite, with a test that every machine kind of the shipped table reaches the field session's draw list.
- Captures of a boiler, a steam engine, a tank and a drill on the tech demo's planet, sent to the user.
