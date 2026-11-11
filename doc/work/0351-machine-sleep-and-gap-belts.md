# 0351: Machine sleep and gap belts

Status: todo (2026-11-11)

Every entity ticks every tick, and a belt moves every item every tick (`work/performance_research_0340.md`, 2.5). The user (2026-11-11): "Decrease entity update loop for entities that are not provable to be interacted by anything in the coming short while". Under the lockstep an entity may skip ticks only when its state afterwards is provably the same as if it had ticked, decided from simulation state alone, never from a camera. Little today (0.27 ms a tick at 5,121 entities), the tick's largest item at M14's factory sizes.

## Goal

A factory's tick costs what is active in it, with every state hash equal to the always ticking game's.

## Controls

None.

## Change

- Wake lists: a machine with nothing to do leaves the active list and waits on what it lacks (a slot, a lane, a network), and a change there wakes it.
- Catch-up in closed form: a machine mid craft with steady inputs and power sleeps to the tick its craft ends; the per tick statistics accrue the same way, and a brownout change wakes its network.
- Networks whose members all sleep with an unchanged balance sleep as one.
- Belts store the gaps between items, as Factorio does, so a flowing line moves its end gaps only.
- The save's layout, if it changes, loads an old save.

## Verify

- The checks and the suite, with a reference test: the state hash at every tick equals the always ticking reference's over the benchmark's factory and the dev kits.
- The night's benchmark table before and after, and the tick's share in 0342's factory views.
