# 0141: Documentation pass: lean, current, layered

Status: todo

## Goal

Asked on 2026-09-30: "a big pass of the docs the subagents read and trim them down, remove everything that is stale or outdated, trim down anything that is unnecessarily wordy, restructure to make more lean, and deduplicate things that need only exist in one place. Make sure to utilize progressive disclosure." Measured that day: 382 KB over 17 files; `doc/ui.md` is 67 KB with one bullet of 9.6 KB and 64 work item mentions; five files hold 250 KB; 42 lines in `ui.md` alone run past 400 characters; `README.md` still says nothing is playable. The docs grew by appending a paragraph per work item, so they read as history, not as reference.

## Rules

- A reference doc states the current behaviour only, in the present tense, verified against the code: read the code before keeping a claim. No history ("since 0125", "used to", "was replaced by", "the review found"). The why lives in `doc/log/` and `doc/work/`: a work item number in parentheses once per topic is the pointer to it; drop the others.
- One place per fact. Rules for agents in `CLAUDE.md`; design intent in `DESIGN.md`; how a thing works in `doc/<topic>.md`; how to build and ship in `doc/build.md`; values in `doc/content.md`. Where two docs say the same thing, keep it where its reader needs it and link from the other with half a sentence.
- Progressive disclosure: `CLAUDE.md` (rules and pointers, no mechanism) leads to `doc/README.md` (one line per doc) leads to `doc/<topic>.md` (a summary of three to six lines, then sections, each stating the rule first and the details after) leads to the log and the work items for the why. A section past about 8 KB with a reader of its own becomes its own file, listed in `doc/README.md`.
- A bullet carries one fact in at most three sentences. More than that is a paragraph or a sub-section with a heading. Values go in tables.
- Lean wording: no restated context, no "note that", no narration of what a change did, no hedges.
- Nothing is deleted that lives only there: a rule, a gotcha, a value, a constraint, a test name that guards a rule. Such things move. Every backticked symbol and path is verified to exist.
- `doc/log/*` and `doc/work/*` are history and are never edited. `SUGGESTIONS.md` loses items the log records as decided and merges duplicates. `TODO.md` is the user's.
- Markdown: one paragraph per line, never reflowed (the global rule). Sentence-level punctuation without dashes (the global writing rule).

## Clusters

One subagent each, in series, each reviewed before its commit:

- A. `doc/ui.md` and `doc/input.md` (they overlap on touch, the keyboard and the gamepad). Also writes `tools/check_docs.py`.
- B. `doc/architecture.md`, `doc/build.md`, `doc/commands.md`.
- C. `doc/content.md`, `doc/fluids.md`, `doc/logistics.md`, `doc/quests.md`, `doc/inspiration.md`.
- D. `CLAUDE.md`, `DESIGN.md`, `PLAN.md`, `README.md`, `doc/README.md`, `SUGGESTIONS.md`: last, so the index and the pointers match the new layout.

## Verify

- `tools/check_docs.py` (cluster A adds it, Python, no dependencies): every relative Markdown link resolves; every backticked `src/…`, `doc/…`, `data/…` or `tools/…` path exists; every backticked `snake_case` name with an underscore appears in `src/` or `data/`, or is on a short allow list in the script for external names (raylib, SDL and glibc sources). Zero findings after every cluster.
- Every cluster reports the size of each file before and after; the aim is under half, without losing a fact.
- The reviewer samples fifteen claims per document against the code, lists every rule, value or gotcha that went missing, and checks the links and the index.
- `./build.sh check` and `./build.sh test` still pass.
