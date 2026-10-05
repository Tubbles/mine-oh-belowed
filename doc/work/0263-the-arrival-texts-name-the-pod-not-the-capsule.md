# 0263: The arrival texts name the pod, not the capsule

Status: todo (2026-10-05, found by the 0262 design: the lore note `the_capsule` (`data/notes.sjson`, strings `note_the_capsule_title` and `note_the_capsule_text`: "The drop capsule came down with you and stays on the pad. Rewards land in it...") and the capsule's item description describe the block world's landing, while a field world lands in the pod (0221) and its rewards go to the pod's locker (0210); after 0262)

## Goal

A player on the field reads texts that describe their own arrival: the pod, its locker and its hatch, never a drop capsule on a pad. The block world's texts stay for block saves.

## Controls

No binding changes.

## Change

- The notes and descriptions that name the capsule get a field counterpart (a second string key chosen by the world kind, or a rewrite that fits both), decided with the chapter 1 texts of 0237's chapters table, which the arrival cutscene (0223) and the chapter items rewrite anyway; fold this item into the first chapter item if it lands first.
- `doc/content.md` (the notes), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`.
- Tests: the UI audit of the notes screen on a field session shows the pod's text; the string audit finds no missing key.
- The couch: open the notes after the stock quest on the field and read the arrival note.
