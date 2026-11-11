# 0377: Netlists that carry loops

Status: todo (2026-11-11)

0355's solver takes a forest: a cable that would close a loop is refused (0368's specification), and 0356 cuts a fluid loop at a chord that carries nothing. Asked whether that is acceptable, the user (2026-11-11): "unacceptable". A player must be able to run a cable or a pipe between any two ports, ring mains and meshes included.

## Goal

A power or fluid netlist with loops solves every tick, deterministic and in integers, and a loop's edges carry flow.

## Controls

None. 0368's and 0374's run controls lose the loop refusal.

## Change

- `src/netlist/`: a solve for a general graph. The design decides the method and measures it against the tree solve at the sizes a factory reaches (thousands of nodes, every tick, also where no player is). Candidates to weigh: the tree solve on a spanning tree with the chords' flows found by a bounded number of integer relaxation passes; a max flow per priority order; collapsing every loop whose edges do not limit into one node, so only limiting loops pay.
- The tree solve stays as the path for a netlist without loops, bit for bit.
- 0368 and 0374: the loop refusal and its string go, written into their specifications before either is implemented. 0356's chord rule is replaced by the same solve.
- 0373's charge fix is designed against the tree solve: this item's design says whether it survives or is absorbed.

## Verify

- The brute force reference extended to graphs with loops, agreeing with the solver on seeded netlists, the reference's rule written independently of the solver's (0355's lesson).
- The tick cost at factory sizes, measured in the night window.
