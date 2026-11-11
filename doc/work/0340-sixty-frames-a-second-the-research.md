# 0340: Sixty frames a second on the couch machine: the research

Status: todo (2026-11-11)

The user (2026-11-11): "Let's target 60 fps at least, on this machine. So we need to work out some LOD, culling, etc. Decrease entity update loop for entities that are not provable to be interacted by anything in the coming short while etc. Do proper research into what can be done". Nothing measures the frame on the couch's own GPU today: the headless captures draw with Mesa's software renderer and the benchmark times the tick without a window.

## Goal

A researched, ranked plan to hold 60 frames a second at least on the couch machine in every shipped view, and the measurement that shows where each view stands against it.

## Controls

None.

## Change

- A report under `work/` (untracked): what a frame and a tick cost today and where, read from the code and from what is already measured; the techniques that apply (levels of detail, culling, batching, the entities' update rate and sleep under the lockstep's determinism), each with what it would save here, what it costs and the measurement that would prove it; the prior art read for each.
- The measurement the plan needs: how a frame is timed on the couch's GPU, in which views, and when it may run.
- The work items the plan becomes, written by the main agent after the user has read the report.

## Verify

- The report sent to the user.
