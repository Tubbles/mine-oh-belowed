# 0365: The vessel's swap, figures and panel

Status: designed (2026-11-11)

Part B of 0361's specification (`doc/work/0361-the-vessel-model-system.md`), split off at its approval: the swap in place, the computed figures, the link seam and the vessel's panel.

## Goal

A vessel's parts are upgraded in place, and its panel shows what it can do and what is not hooked up.

## Controls

0361's: a better part aimed at a lesser one of its line swaps it with Place; the panel opens with the inventory binding aimed at the control unit.

## Change

- As 0361's specification, part B. "Hooked up" answers false for every port until 0355 and 0356 land, so the panel's capture with one connection missing waits for 0355.
- After 0361. Before or after 0355.

## Verify

- The checks and the suite, with one part of each role swapped and the state hash equal on two machines.
- Captures of the panel at the smallest audit size, sent to the user.
