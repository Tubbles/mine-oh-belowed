# 0110 Data watch off when scans are slow

Status: implemented
Milestone: M11

## Goal

On the phone (Winlator, 2026-09-29) developer mode drops the game to a frame every few seconds. Developer mode turns the data watch on (`effective_watch_data_mode`, `src/data_watch.odin`: Presentation mode), which once a second stats every file under `data/` on the main thread (`scan_data_files`, 469 files today). The game folder on the phone is Android's shared storage reached through Wine and Box64, where each stat costs milliseconds, so a scan takes seconds and the frame waits for it. The user (2026-09-29): "activating dev mode made the fps crawl to like 0.2 fps".

## Change

- `poll_data_watch` measures the scan (`time.tick_now` before and after `scan_data_files`). When a scan takes longer than `DATA_WATCH_SLOW_SCAN :: 50 * time.Millisecond`, the watch switches itself off for the rest of the run: `watch.disabled = true`, and one log line `data: scanning <count> files took <ms> ms, the data watch is off for this run` is written. `data_watch_poll_due` returns false while `disabled`. The threshold and the decision are pure (a small procedure `data_watch_scan_too_slow(duration) -> bool` with a test), the log line formatted by a pure procedure with a test.
- The first scan at start is the one that stalls once on the phone; that is accepted. Nothing changes on machines where the scan is fast.
- Documentation: the header comment of `src/data_watch.odin`, the data watch sentence in `doc/architecture.md`, and an entry in `doc/log/2026-09-29.md` (tags `#windows #performance #decision`) with the cause and the decision (switch off rather than a worker thread, since no one edits data files on the phone and the log says what happened).

## Verify

- `./build.sh check`, `./build.sh check-windows`, `./build.sh test`.
- User: developer mode on the phone runs at full speed after the first second, the log has the `data: scanning` line; the couch log has no such line.

## Implemented

2026-09-29: `poll_data_watch` times the scan with `time.tick_now` and `time.tick_since`; a scan over `DATA_WATCH_SLOW_SCAN` sets `disabled` and logs the `data: scanning` line, `data_watch_poll_due` returns false while `disabled`, and `update_data_watch` keeps `disabled` when developer mode is switched off, so the watch stays off for the run. `data_watch_scan_too_slow` and `data_watch_slow_scan_line` are tested in `data_watch_test.odin`. Verified here: `./build.sh check`, `./build.sh check-windows` and `./build.sh test` pass. The phone and couch checks are the user's.
