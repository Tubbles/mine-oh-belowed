# 0344: The water's look on the workers

Status: todo (2026-11-11)

`gather_field_grid` runs `write_field_water_look` on the main thread for every mesh job it gathers: 2.8 ms for a lake's chunk and 5.5 ms for a sea chunk in the test build, up to 8 jobs a frame (`work/performance_research_0340.md`, 2.1). It is there because the workers never read `Field_World`.

## Goal

No water look computed on the main thread, with the same bytes as today.

## Controls

None.

## Change

- The gather copies the raw arrays of the look's reach into the job, as it copies the samples, and the worker builds the sheet and the wall guard.
- The job's memory grows by the copied reach; the hand-back rule on memory a frame may draw from holds.

## Verify

- The checks and the suite, with the settled lake's water mesh byte for byte as before.
- 0342's table: the streaming section's worst frame along a lake shore and at the sea, before and after.
