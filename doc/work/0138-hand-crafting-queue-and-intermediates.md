# 0138: Held counts in the recipe browser, an open crafting queue, intermediates crafted on demand

Status: implemented

## Goal

Asked on 2026-09-30: "In recipe screen, we need to see how many of something we already have in inventory, also remove the craft queue limit of 8, and automatically craft intermediates as needed (factorio style over minecraft style)". Today the detail panel shows have and need per ingredient (0091) but not how many of the product the player holds; `Craft_Queue` is a fixed array of `HAND_CRAFT_QUEUE_CAPACITY` (8) single crafts; and a craft whose ingredient is itself craftable is refused with Missing ingredients.

## Change

- Held counts: every recipe row of the browser shows the count of its first product held in the inventory (hotbar and main grid) after the name, and the detail panel's product line reads "4 × Plank, 12 held" (a string with both numbers from the string table). Zero shows as 0, dim. The count comes from the frame's inventory each frame like the have and need numbers.
- The queue: `Craft_Queue` holds runs, `Craft_Run{recipe, count}`, up to `HAND_CRAFT_QUEUE_RUNS` (64) runs of any count, so Craft five on a recipe already at the end grows its run. The HUD draws one box per run with the count in the corner like a stack, the front run first with the progress bar, wrapping into rows as today. The queue summary drops the "/ 8". Cancel newest takes one craft off the newest run (a run at zero is removed); the recipe browser's Cancel button (0137) does the same.
- Ingredients are taken when a craft starts (when its run reaches the front and its first craft begins), not when it is queued, since an intermediate's product does not exist when the parent is queued. Queuing validates the plan instead: a walk over the inventory plus the outputs of the runs already queued (a virtual inventory, integers) must cover every input, else the queue refuses and names the first missing item and count in the toast ("Missing 4 Iron ore"). A run at the front whose inputs are no longer in the inventory (spent or dropped meanwhile) waits, `Craft_Queue.waiting_for` names the item, the HUD says "Waiting for Log" as it says "waiting" for full outputs today, and Cancel frees it. Cancelling a queued run returns nothing; cancelling the craft in progress returns its inputs as today.
- Intermediates: when the player queues N of a recipe R, the plan resolves the missing inputs recursively: an input item short by M that has an unlocked hand craftable recipe (the first in registry order among those whose first product is the item; the order is data, so it is deterministic) gets ceil(M / its output count) crafts queued ahead of R, and its own inputs resolve the same way; an item short with no such recipe refuses the whole plan (nothing queued). The resolution depth is bounded (16) against a recipe cycle, and a cycle refuses with the item named. The runs of one queue action go in as a unit: intermediates first, R last.
- Save: the queue's new layout loads from a save written with the old one without refusing: `remap_craft_queue` and the codec (`save_binary.odin`, by name) keep old fields readable or the queue comes back empty with one log line; the round trip test covers a queue with runs and a waiting state. A content reload remaps recipe ids in the runs as it did in the array.
- Determinism: integer counts and ticks only; the plan walk is pure and tested.
- Docs: `doc/ui.md` (the recipe browser: held counts, the queue, the Missing toast, the waiting state; the HUD queue), `doc/logistics.md` or wherever hand crafting is described (take on start, intermediates), `doc/log/2026-09-30.md` with the decisions (why take on start, the first recipe rule, the run cap).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: the held count text for a product held in both grids; a queue of 20 planks is one run of 20 and the summary says 20; Craft five twice on the same recipe makes one run of 10; queuing an iron gear with plates missing but ore and a furnace-less plate recipe by hand available queues the plate run first (or, if plates are not hand craftable in the data, use a recipe pair that is, and add a test data table); a plan short of a raw item queues nothing and names the item and count; a cycle in test data refuses; a run at the front with its input spent waits and names it, and Cancel frees it; cancelling the newest run returns nothing to the inventory and cancelling the craft in progress returns its inputs; an old layout save loads; the HUD audit with a queue of several runs.
- The user: queue 20 planks, watch one box count down; queue a machine whose intermediates are missing, watch them craft first; read the held count of stone in the browser.

## Implementation notes

- Held counts are shown on unlocked rows only: a silhouette and a recipe making only fluids show none. The detail panel shows the held count on every product line, not only the first.
- An old layout save's queue comes back empty (the spec's second option), with one log line; the ingredients its crafts took when queued are lost.
- The HUD box counts crafts of the run, not products. The Missing toast names the first shortage the plan meets; a recipe cycle has its own toast ("Cannot plan: X is made from itself"), and a chain past 16 levels another ("Cannot plan: too many steps to make X").
- "Cancel frees it" holds only when the waiting run is the newest, since Cancel takes from the newest run. A waiting front is repaired by the next queue action of any recipe when the inventory can make the missing item (its makers go in ahead of it, covering every craft of the run), or cancelled by taking the runs behind it off first. A plan's item counts stop at zero, so it never queues a maker behind a run already short.
- The HUD draws at most 4 rows of run boxes; beyond that the front run and the newest runs show, the middle is left out.
- A count below one queues nothing (no refusal).
- Hand crafting is described in `doc/content.md` (Rules of thumb), not `doc/logistics.md`.
