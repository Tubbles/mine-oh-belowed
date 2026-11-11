# 0369: Cable loads on the panels and the overview

Status: designed (2026-11-11)

Part C of 0355's specification (`doc/work/0355-cables-and-the-power-netlist.md`): a cable's load against its capacity and the bottleneck, on the junction box's panel and the power overview.

## Goal

The player reads which cable limits a netlist.

## Controls

None new: the panels open as they do.

## Change

- As 0355's specification, part C. After 0368.

## Verify

- The checks and the suite, with the UI audit cases at the smallest size.
- Captures of a saturated cable on the panel and the overview, sent to the user.
