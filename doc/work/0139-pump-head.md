# 0139: Pumps lift liquids up to their head

Status: implemented

## Goal

Asked on 2026-09-30, from the shore problem: the offshore pump needs no power but its network obeys gravity, so the first boiler and steam engine must stand at the offshore pump's height or below, while the electric pump that lifts water arrives with the grid the plant is meant to start. The user: "I think we want a more complex and realistic model here, why wouldn't the offshore pump have a head?" Every pump gets a head, and a liquid rises in a pump's network up to the head line.

## What the code says

- `fluid_network.odin`: a liquid network has `gravity` on unless it is pressurised, and pressurised means it holds the output port of an electric pump (`pressurising` is set for `machine.kind == .Pump` output ports at segment build time) whose power is on (`network_is_pressurised`). With gravity a connection never moves fluid into a higher segment (`move_along_connection`, `pair[from].height < pair[to].height`). Pressurised, heights are ignored entirely. Gases ignore heights always.
- The offshore pump (`advance_offshore_pump`, 1200 litres per second, no power) and the tar pit pump (600 litres per minute, powered) push into their output port and pressurise nothing.

## Change

- Data: every pump kind gets `head_metres` in `data/machines.sjson` (offshore pump 6, tar pit pump 6, pump 30; whole metres, validated at least 1; balance numbers to revisit with the rest, `SUGGESTIONS.md`). One block is one metre (`DESIGN.md`).
- Model: a pump's output port segment is pressurising for every pump kind (offshore pump, tar pit pump, pump), while the pump runs (the offshore pump always, the powered ones with power on). A network's head line is the highest of its pressurising outlets' `height + head_metres`, or none. In `move_along_connection` a liquid moves into a higher segment only while that segment's height is at or below the head line (`Fluid_Tick_Rules.head_line`, an integer height, replacing the `gravity` bool; a network with no pressurising outlet keeps today's rule). Downhill and level moves are unchanged. Gases ignore heights as today. Pumps in series chain by themselves, since a pump's input and output ports sit in different networks: the second pump's outlet height plus its head is its network's line.
- Panels: a pipe or tank above its network's head line shows "Above the pump's head" in place of the flow, so a plant built too high says why it is dry. The pump panels show the head.
- Placement is unchanged; nothing is refused at build time.
- Docs: `doc/fluids.md` (the gravity rule rewritten with the head line and the series case, the numbers, an "As implemented in 0139" note), `doc/content.md` if it lists the pump rates, `doc/log/2026-09-30.md` with the decision and why a head instead of pressurising the whole network or dropping gravity (the pump keeps its job for higher lifts and tanks; gravity keeps meaning for machine fed liquids).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests (`fluid_test.odin`): an offshore pump's network fills a pipe 6 blocks above the outlet and not one 7 above; the electric pump without power lifts nothing and with power lifts 30; two pumps in series lift to the second's outlet plus 30; a machine fed liquid network (a refinery output) still never climbs; gas ignores the line; the head line follows the highest outlet when two pumps feed one network; the panel text for a segment above the line; determinism (integers, connections in coordinate order as today).
- The user: build the first boiler and engine on the bank a few blocks above the water and see them fed; pipe up a hill past six blocks and see the pipe say why it stays dry.

## Implemented

- Data and loader: `head_metres` on the three pumps; `validate_pump_head` (`machine_fluid_ports.odin`) requires 1 to 1000 on pump kinds (so height plus head cannot overflow i32) and refuses the key elsewhere.
- Model: `Fluid_Segment` carries `pressurising` (now for every pump kind's output port), `head_line` (port height plus head) and `needs_power`; `network_head_line` and `tick_head_line` in `fluid_network.odin` replace `network_is_pressurised` and the gravity flag. An outlet counts (`outlet_is_running`) while its port is open (not closed for mixing), its pump has power or needs none, and its input side holds fluid: always for the offshore and tar pit pumps, and for the electric pump a litre in its input buffer or fluid moved this tick (it may drain its input to zero before the line is computed). A pump against a full output keeps its head.
- Panels: `fluid_second_line` swaps the flow line for "Above the pump's head"; `pump_head_line` adds "Head: N m" to the three pump panels.
- Deviation: the "above" note shows on every port of a fluid machine panel, not only tanks, since a boiler or engine input set too high is dry for the same reason. It needs a running pump in the network; with none there is no line.
- Review fixes: closed outlets and pumps with an empty input set no line (tests `test_a_closed_pump_outlet_lifts_nothing`, `test_a_pump_with_an_empty_input_lifts_nothing`); the head cap and the validation messages are tested; the pump descriptions in `en.sjson`, `doc/architecture.md`, the `data/fluids.sjson` header and the 0019 note in `doc/fluids.md` follow the head model.
- Deviation: the item's determinism point is covered by the existing `test_fluid_simulation_is_deterministic`, whose steam plant now has an offshore pump head line; no new determinism test.
