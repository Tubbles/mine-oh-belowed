# 0376: The field's pumps draw from nothing

Status: todo (2026-11-11)

Found by 0356's design: on the field the offshore pump and the tar pit pump have no source check and produce their fluid wherever they stand.

## Goal

A pump produces only where its source is.

## Controls

None.

## Change

- The offshore pump draws from the field's water at its intake (the sea, a lake, a body), the tar pit pump from its deposit, each refused or idle elsewhere with the reason shown.
- What drawing does to the water it draws from (a lake's level, a body's volume) is decided in the design against the water models and 0370.

## Verify

- The checks and the suite.
