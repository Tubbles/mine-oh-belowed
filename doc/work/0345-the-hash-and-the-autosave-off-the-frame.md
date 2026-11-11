# 0345: The state hash and the autosave off the frame

Status: todo (2026-11-11)

Every windowed game hosts, so it hashes the whole state every 300 ticks, and the autosave (every minute in the user's settings) encodes and writes on the main thread (`work/performance_research_0340.md`, 2.1). Neither is timed today.

## Goal

No frame over its budget at a hash tick or an autosave.

## Controls

None.

## Change

- The hash: skipped while it can serve nobody, or spread, without changing what a client's comparison needs (the research left open whether a joiner's first comparison reads the lone host's hashes: the design settles it).
- The save: a snapshot on the main thread, the encoding and the write on a thread, through `write_file_replacing`, with a save in flight when the game closes finished first.
- The lockstep and the save format are unchanged.

## Verify

- The checks and the suite, with a save written off the frame equal byte for byte to one written on it.
- 0342's table: the worst frame at the hash ticks and at an autosave in a view held for a minute, before and after.
