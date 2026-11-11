# 0375: Vessel tanks and pipes across docking

Status: designed (2026-11-11)

Part C of 0356's specification (`doc/work/0356-the-pipes-netlist.md`): a vessel's tanks as stores, pipes across a docking connector, a vessel tied by a pipe, and the wet mass in the vessel's figures.

## Goal

A vessel is fuelled through a pipe from the ground, and its figures count what its tanks hold.

## Controls

None new.

## Change

- As 0356's specification, part C. After 0374 and 0365.

## Verify

- The checks and the suite, with a tank filled across a connector and the state hash equal on two machines.
