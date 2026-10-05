# 0289: A motion filter scores our flames against footage

Status: todo (2026-10-05, from the user)

## Goal

The user (2026-10-05): "There ought to be some transformation or delta detection filter you could apply to a series of images to see the difference, and we could run that on our flames and flames we know we want to mimic, and see how it behaves and what needs to change". So: one tool that takes a directory of consecutive frames (the game's clips from `tools/capture_clip.sh`, the footage's frames cut with `ffmpeg`), applies the same filters to both and prints the same numbers, so a flame of ours and a flame we want to mimic are compared by measurement, not by eye alone: how much changes between frames, how the brightness moves and at what rates, which way and how fast the features flow, and a difference strip that shows where the change is.

## Controls

None.

## Change

- `tools/motion_stats.py <frames directory> [--crop WxH+X+Y] [--fps N]`: per series the mean absolute difference between consecutive frames (the motion energy) and its series, the mean brightness series with its spectrum (the share of the change in bands of rates, so a 1 Hz wave and a 10 Hz crackle read apart), the flow's dominant direction and speed in frame widths a second (a phase correlation or a block match between consecutive frames, in pure Python over PIL or in a project venv with numpy, the design decides), and a strip of difference images (`|frame n+1 - frame n|`, amplified) beside the frames. One line per statistic, the same lines for every series, so two runs are set side by side.
- The yardstick run: our clips of 0286 and 0288 against the Artemis I window frames under `work/reference/0288/` (untracked), the numbers in the log.
- Docs: `doc/commands.md` (For the assistant, beside the capture script) or `doc/developer_tools.md`, the design decides.

## Verify

- `python3 tools/motion_stats_test.py` (the statistics on synthetic series: a still series gives zero energy, a drifting pattern gives its speed and direction, a flickering flat field gives its rate's band).
- `python3 tools/check_docs.py`.
- The tool run on a game clip and on the footage, the two summaries side by side in the reply.
