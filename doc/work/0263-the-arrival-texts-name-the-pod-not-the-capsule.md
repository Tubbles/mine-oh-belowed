# 0263: The arrival texts name the pod, not the capsule

Status: todo (2026-10-05, from 0262)

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
