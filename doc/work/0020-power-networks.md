# 0020 Power: poles, networks, steam engine, brownouts

Status: todo
Milestone: M4

## Goal

Electric networks from `doc/fluids.md`: poles with supply volumes and wire reach, the steam engine as generator, proportional brownouts, the power switch, the power overview screen, and the first electric consumers running: electric mining drill, electric and filter inserters, lamp, pump.

## Deliverables

- Pole entity (small pole), automatic connection within reach, networks as connected components rebuilt on topology change, supply volumes assigning electric machines to networks.
- Steam engine entity drawing steam through the fluid network and offering up to 900 kW, the per tick energy balance with satisfaction, generators burning only for delivered energy, consumers running at the satisfaction fraction.
- Electric machines join the balance: electric mining drill (mines at satisfaction speed), inserter and filter inserter (their cycle scaled), pump (moves fluid), lamp (light level 14 while powered above a threshold, off otherwise, through the block light path with the lamp as a light emitting entity cell or a light block swap; say which).
- Power switch entity joining and splitting networks.
- Power overview screen (from the pause menu and a new action) listing networks with supply, demand, satisfaction, generators and top consumers; HUD brownout warning; "no power" state in machine panels.
- Tests: pole connection by reach, supply volume membership, satisfaction arithmetic with two generators and three consumers, brownout scaling of a drill's output rate, steam consumption proportional to delivered energy, switch splitting a network, lamp turning on and off with power, determinism over 1200 ticks.

## Verify

- Builds and tests pass.
- User: pump, boiler and engine power a lamp and an electric drill; adding drills until the engine is short makes everything slow down together and the overview shows why.
