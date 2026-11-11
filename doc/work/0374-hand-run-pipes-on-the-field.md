# 0374: Hand run pipes on the field

Status: designed (2026-11-11)

Part B of 0356's specification (`doc/work/0356-the-pipes-netlist.md`): on the field every pipe is run by hand from port to port as a cable is (the main agent's proposal, the user may overturn it: the alternative is placed pipe pieces on frames, with pole runs that carry fluid and a second model for vessels), a fluid junction, fluid ports in 0361's `ports` key, `machine_port_is_linked` for fluid ports, and the pipe run tool between belt poles removed.

## Goal

A fluid connection on a planet or a vessel is a pipe the player runs by hand.

## Controls

0355's control design with a pipe item held, unchanged.

## Change

- As 0356's specification, part B. After 0356, 0368, 0362 and 0361.
- Not started before the user has seen the proposal.

## Verify

- The checks and the suite.
- Captures of a boiler line run by hand, sent to the user.
