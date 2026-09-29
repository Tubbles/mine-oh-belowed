# odin-fsw

File and directory watching (inotify on Linux, ReadDirectoryChangesW on Windows, kqueue on the BSDs and macOS), used through the `shared` collection (`build.sh` passes `-collection:shared=shared`, the game imports `shared:fsw`). The data watch (`src/data_watch.odin`) reads its events instead of scanning the data directory. Work item 0111.

- Upstream: https://github.com/thetarnav/odin-fsw, commit `c2674eaa017e9bc6da18cfcc82c7a162b1a7a9df` of 2026-08-01, MIT (`LICENSE.txt`).
- `fsw.odin`, `track.odin`, `snapshot.odin`, `glob.odin`, `backend_linux.odin`, `backend_kqueue.odin`, `backend_poll.odin`, `LICENSE.txt`: copied unchanged. `backend_kqueue.odin` keeps its BSD build tag, so its `core:sys/posix` import never reaches the Windows link (CLAUDE.md). `example/`, `Makefile` and `test.odin` are not copied.
- `backend_windows.odin`: copied with three patches. Upstream reads the fields of `windows.FILE_NOTIFY_INFORMATION` as `action`, `next_entry_offset`, `file_name_length` and `file_name`; Odin release dev-2026-09 spells them `Action`, `NextEntryOffset`, `FileNameLength` and `FileName`. Only those names changed. Two more in `iocp_drain`: upstream waits up to 50 ms in `GetQueuedCompletionStatus` on every `get_events` call although its header says 0 ms, which would stall every frame of the game on Windows, so the timeout is 0; and it re-issues `ReadDirectoryChangesW` with `bWatchSubtree` false after every batch, so a recursive watcher lost its subdirectories after the first event, so the re-issue passes `W == Watcher_Recursive` like the first request does.
- No foreign library: the backends call the operating system through `core:sys/linux`, `core:sys/windows` and `core:sys/kqueue`.

After an update: copy the files above again, reapply the patches while upstream still uses the old field names, set the commit here, and run `~/opt/odin/odin check shared/fsw -no-entry-point -vet -strict-style`, once plain and once with `-target:windows_amd64`.
