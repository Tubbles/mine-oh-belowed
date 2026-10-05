# 0289: A motion filter scores our flames against footage

Status: implementing (2026-10-05)

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

## Specification (design, 2026-10-05)

### The choice: pure Python over PIL

`uv` is not on the PATH, every tool under `tools/` runs on the system `python3` with the standard library and PIL, and the method below takes 3.7 s on the game's 60 frame clip (7.1 s with `--steady`) and 1.0 s on 30 footage frames, measured with the prototype. So no venv and no numpy. The cost is held down by doing every statistic on an analysis image of at most 64 pixels a side and a hand written radix 2 FFT on a 64 x 64 grid. A reference implementation that produced every number below is `tmp/0289/motion_stats_prototype.py` in the main checkout (untracked); it may be read and its code taken, and this specification is authoritative where they differ (the prototype prints the `steady:` line only with `--steady` and lacks the frame size check).

### Command

`python3 tools/motion_stats.py <frames directory> [--name NAME] [--crop WxH+X+Y] [--fps N] [--steady WxH+X+Y]`, `argparse`, the module docstring as the description (it names 0289 and `doc/commands.md`, For the assistant, as `capture_clip.sh`'s header does).

- Frames: the files `<name>_<digits>.png` of the directory (not recursive), sorted by the digits as an integer. `--name` picks the name; without it the directory must hold frames of exactly one name, else the error lists the names. `clip_1271_calm_00.png` is a frame of `clip_1271_calm`, never of `clip_1271`; `clip_1271_strip.png`, the GIF and the tool's own strip are not frames.
- `--crop`: ImageMagick's geometry as the capture script takes it, the box every statistic reads; default the whole frame (printed as `WxH+0+0`).
- `--fps`: the series' rate, default 60 (the game's tick); 30 for the Artemis I frames.
- `--steady`: a second box whose rigid motion between consecutive frames (the view's buffet moving the whole porthole) is subtracted from the flow. Only the flow is steadied; energy, brightness and the strip see the shake as the eye does.
- Errors print `motion_stats: <message>` to stderr and exit 1: a crop that does not match `^(\d{1,5})x(\d{1,5})\+(\d{1,5})\+(\d{1,5})$` or is under 8 pixels a side; an fps that does not parse as a float, is not finite, is not above 0 or is over 1000; fewer than 4 frames; a frame whose size differs from the first's (`<file> is WxH, the first frame WxH`); a crop or steady box reaching past the frame (`crop reaches past <file> (WxH)`); an unreadable file (`OSError`).
- Output: the lines below on stdout, then the strip written and its path printed. Exit 0.

### Constants

`ANALYSIS_SIDE = 64`, `TRANSFORM_SIZE = 64`, `COMMON_RATE = 30`, `BAND_EDGES = (2.0, 6.0, 15.0)`, `BAND_NAMES = ("under 2", "2 to 6", "6 to 15", "over 15")`, `MATCH_FLOOR = 0.1` (a phase correlation peak under it is no match), `STILL_SHIFT = 0.5` (crop pixels; a shorter shift is still), `AGREE_DEGREES = 30.0`, `CONCENTRATION_SHARE = 0.1`, `DELTA_GAIN = 8`, `DELTA_EVERY = 3`, `DELTA_COLUMNS = 10`, `DELTA_MARGIN = 2`, `MINIMUM_FRAMES = 4`, `MINIMUM_CROP_SIDE = 8`, `MAXIMUM_RATE = 1000.0`.

### Procedures (`tools/motion_stats.py`, in this order)

An analysis image is a tuple `(width, height, values)`, values the gray levels 0 to 1 row by row.

- `parse_crop(text) -> (left, top, right, bottom)`, `parse_rate(text) -> float`: the refusals above as `ValueError`.
- `frame_groups(directory) -> {name: [paths sorted by number]}`; `select_frames(groups, name) -> (name, paths)`.
- `load_crops(paths, box) -> [Image]`: each frame opened, `convert("L")` (PIL's ITU-R 601 luma), the size checked against the first, cropped to the box (or whole).
- `analysis_size(width, height)`: factor `min(1, ANALYSIS_SIDE / max(width, height))`, each side `max(1, round(side * factor))`. `analysis_image(gray)`: `resize` with `Image.Resampling.BOX` to that size, `get_flattened_data()` (Pillow 12; `getdata` is deprecated) divided by 255. A crop of at most 64 a side is never resampled, so the game's porthole crop is read pixel for pixel and a 340 pixel footage crop at a fifth.
- `mean(values)` (0 for none), `deviation(values)` (population).
- `energy(previous, following)`: mean of `|b - a|` over the analysis pixels. `concentration(previous, following)`: the changes sorted descending, the sum of the top `max(1, round(count * 0.1))` over the total (0 when the total is 0).
- `fft(values)`: recursive radix 2, `even + exp(-2πi k/n) odd`. `transpose(rows)`, `fft_2d(rows)` (rows then columns), `inverse_fft_2d(rows)`: conjugate, `fft_2d`, conjugate, divide by the count.
- `hann(index, count) = 0.5 - 0.5 cos(2π (index + 0.5) / count)`. `windowed_grid(image)`: a 64 x 64 complex grid of zeros, the image's values minus their mean times `hann(x, width) * hann(y, height)` at the top left.
- `normalised_cross_power(previous_spectrum, following_spectrum)`: per element `b * conj(a) / |b * conj(a)|`, 0 when the magnitude is under 1e-12.
- `signed(index)`: `index - 64` when `index >= 32`. `vertex_offset(left, centre, right) = 0.5 (left - right) / (left - 2 centre + right)`, 0 when the denominator is 0.
- `phase_correlation(previous_spectrum, following_spectrum) -> (x, y, peak)`: the real part of the inverse of the cross power, its maximum, the parabola vertex on each axis through the wrapped neighbours, `signed` plus the offset. A positive x is content moving right, a positive y content moving down (image rows). Peak is 1 for a pure shift, near 0 for unrelated frames.
- `pair_shifts(images) -> [(x, y, peak)]`: the spectra of `windowed_grid` of each, once per frame, then `phase_correlation` of each consecutive pair, in analysis pixels.
- `shifted_correlation(previous, following, x, y)`: the Pearson correlation of the overlap after shifting by `round(x), round(y)`; both flat gives 1, one flat 0, no overlap 0.
- `common_step(rate)`: `round(rate / 30)` when it is at least 1 and `rate / 30` is within 1e-6 of it, else None. `resampled(series, rate)` to 30 fps: the mean of each consecutive group of `common_step` samples (60 fps: pairs, what a 30 fps camera exposing 1/30 s sees), else linear interpolation at `index * rate / 30` for `index` in `0 .. int((count - 1) / rate * 30)`.
- `band_index(frequency)`: 0 under 2, 1 under 6, 2 up to and including 15 (a 30 fps Nyquist bin lands in 6 to 15), 3 above. `band_shares(series, rate)`: the mean removed, a direct DFT at bins `1 .. count // 2` (`frequency = bin * rate / count`), power `|X|²` weighted 2 (1 for the Nyquist bin of an even count), summed per band, each band over the total (all 0 for a constant series).
- `direction_degrees(x, y) = degrees(atan2(-y, x)) mod 360`: 0 is screen right, 90 screen up. `angle_between(a, b) = |(a - b + 180) mod 360 - 180|`.
- `Flow`, a frozen dataclass: `direction, net, net_widths, median, median_widths, consistency`. `flow_summary(shifts, rate, crop_width) -> (Flow | None, matched)`, shifts in crop pixels: matched are the pairs with peak at least 0.1; moving the matched with `hypot >= STILL_SHIFT`; None when nothing moves. The net vector is the mean over the matched pairs (still ones count as 0), its direction and length; the median is over the moving pairs' lengths; widths a second are pixels a frame `* rate / crop_width`; consistency is the share of all pairs that move within 30 degrees of the net direction. `matched` is the matched share of all pairs.
- `change_tensor(previous, following)`: on `|b - a|`, central differences `gx, gy` over the inner pixels, the sums of `gx²`, `gy²`, `gx gy`. `streak_summary(images) -> (orientation, coherence) | None`: the tensors summed over all pairs, `orientation = round(0.5 degrees(atan2(-2 xy, xx - yy)) + 90) mod 180` (the direction the change is drawn out along: 0 horizontal, 90 vertical, 45 rising to the right), `coherence = sqrt((xx - yy)² + 4 xy²) / (xx + yy)` (0 blobs, 1 parallel streaks); None when `xx + yy` is 0. It reads where the footage's one frame streaks point although no streak lives two frames.
- `delta_strip(crops) -> Image`: for pair indices `0, 3, 6, ...` the crop resolution `ImageChops.difference` of the gray crops, `point(min(255, value * 8))`, pasted on a black `L` image of `min(10, tiles)` columns and `ceil(tiles / 10)` rows of cells `(width + 4) x (height + 4)`, each tile 2 pixels into its cell (the capture strip's `-tile 10x -geometry +2+2`).
- `write_png(image, path)`: saved as PNG to `<path>.tmp`, then `replace` onto the path.
- `series_text(values)` (3 decimals joined by spaces), `bands_text(shares, rate)` (`under 2 0.41, 2 to 6 0.52, 6 to 15 0.07, over 15 0.01`, the last as `over 15 -` when `rate <= 30`), `report(name, count, crop_text, rate, crops, steady_crops) -> [lines]`, `main(arguments) -> int`. `report` makes the analysis images once and calls `pair_shifts` once; the persistence uses the shifts in analysis pixels, the flow the shifts times `crop width / analysis width`, minus the steady box's pair shifts scaled by its own ratio.

### The lines, in this order, the same for every series

```
frames: clip_1271, 60 at 60 fps (1.00 s), crop 52x32+624+200, analysed at 52x32
energy: mean 0.0728, deviation 0.0286
energy at 30 fps: mean 0.1089, deviation 0.0460
energy concentration: 0.41 of the change in the top tenth of the pixels
energy series: 0.0xx ...
brightness: mean 0.5293, deviation 0.1086, mean step 0.0249, largest step 0.1478
brightness bands: under 2 0.41, 2 to 6 0.52, 6 to 15 0.07, over 15 0.01
brightness bands at 30 fps: under 2 0.42, 2 to 6 0.52, 6 to 15 0.05, over 15 -
brightness series: 0.xxx ...
steady: mean 2.92 px a frame, largest 6.98, subtracted from the flow
flow: direction 73 degrees, net 2.58 px a frame (2.97 crop widths a second), median 4.85 px a frame (5.59 crop widths a second), consistency 0.56, matched 1.00
streaks: orientation 51 degrees, coherence 0.12
persistence: correlation 0.726, decorrelation 0.052 s
delta strip: <directory>/clip_1271_delta_strip.png
```

- energy: over consecutive pairs; at 30 fps over pairs `common_step` frames apart (`energy at 30 fps: -` when the rate is no multiple of 30), so a 60 fps clip and 30 fps footage compare. Concentration is the mean over the consecutive pairs.
- brightness: the analysis image's mean per frame; its steps are consecutive absolute differences. The bands of the series as sampled, then of `resampled` at 30 fps.
- steady: the pair shifts of the steady box in its own crop pixels, their lengths' mean and largest; without `--steady` the line is `steady: none`. With it, the flow's shifts minus the steady box's pair by pair.
- flow: `direction` printed as `round(direction) % 360`; `flow: still, matched 1.00` when nothing moves.
- streaks: `streaks: none` for no change at all.
- persistence: the mean `shifted_correlation` of consecutive pairs at their phase correlation shift; the decorrelation time `-1 / (rate ln r)` in seconds (3 decimals), `inf` when r is at least 1, `0` when r is at most 0: how long a feature keeps its look while it moves.

### Tests (`tools/motion_stats_test.py`, `unittest`, `python3 tools/motion_stats_test.py`)

The docstring as `check_test.py`'s; `sys.path` gets `tools/`. Helper `pattern(width, height, seed)`: `random.Random(seed)` gray levels on a `width // 4 x height // 4` image resized `BICUBIC` to the size. Files only in `tempfile.TemporaryDirectory()`.

- `test_a_still_series_has_no_energy_and_no_flow`: 6 copies of a 64 x 48 crop of `pattern(256, 128, 7)`: every energy 0, `flow_summary` gives None with matched 1.0, persistence 1.0, `report` holds `flow: still, matched 1.00`.
- `test_a_pattern_drifting_right_flows_at_zero_degrees`: 10 frames, frame n the box `(100 - 3n, 40, 164 - 3n, 88)` of the pattern (the content moves 3 pixels a frame to the right), 60 fps: `angle_between(direction, 0) <= 2`, net within 0.1 of 3.0, `net_widths` within 0.1 of `3 * 60 / 64`, consistency 1.0, persistence above 0.95.
- `test_a_pattern_drifting_up_flows_at_ninety_degrees`: the box `(40, 40 + 3n, 104, 88 + 3n)`: direction within 2 of 90, net within 0.1 of 3.0.
- `test_a_flicker_at_10_hz_lands_in_the_6_to_15_band`: 60 flat 32 x 32 frames at `round(128 + 60 sin(2π 10 n / 60))`, 60 fps: the band share 2 above 0.95, also of `resampled` at 30, and `flow_summary` None with matched 0.
- `test_a_1_hz_wave_lands_under_2`: the same at 1 Hz: band 0 above 0.95.
- `test_a_30_fps_series_has_no_over_15_band`: `bands_text` at 30 ends with `over 15 -`; `resampled` of 60 samples at 60 gives 30, of 50 at 25 gives `int(49 / 25 * 30) + 1` points with the first and last equal to the series' ends.
- `test_streaks_read_their_orientation`: 10 frames of fresh `random.Random(3)` noise each, 16 x 2 resized `BICUBIC` to 64 x 64 (vertical streaks): orientation within 5 of 90, coherence above 0.8; 2 x 16 (horizontal): orientation within 5 of 0 modulo 180, coherence above 0.8.
- `test_the_crop_and_the_rate_are_range_checked`: `parse_crop` refuses `52x32`, `52x32+1`, `4x32+0+0`, `52x32+-1+0`, `123456x2+0+0` and gives `(624, 200, 676, 232)` for `52x32+624+200`; `parse_rate` refuses `0`, `-1`, `nan`, `inf`, `1001`, `abc` and takes `29.97`.
- `test_frames_are_selected_by_name`: a directory with `a_9.png`, `a_10.png`, `a_11.png`, `a_12.png`, `a_calm_00.png` to `a_calm_02.png` and `a_strip.png`: groups `a` and `a_calm`, `a` in the order 9, 10, 11, 12; `select_frames(groups, None)` raises naming both; `a_calm` with 3 frames raises.
- `test_the_delta_strip_lands_beside_the_frames`: 31 frames 32 x 24 of the drifting pattern written as `d_00.png` .. `d_30.png`; `main([directory, "--crop", "16x12+0+0"])` (stdout captured) returns 0, `d_delta_strip.png` is 200 x 16 (10 tiles of 20 x 16), no `.tmp` is left, and stdout's lines start with the 14 prefixes above in order.
- `test_a_crop_past_the_frame_is_refused`: the same directory with `--crop 30x30+10+0` returns 1 and writes no strip; a frame of another size returns 1.

### The yardstick (the implementer reproduces it within the tolerances)

Runs, from the main checkout's paths: the game `python3 tools/motion_stats.py tmp/shot0286/state/mine-oh-belowed/screenshots --name clip_1271 --crop 52x32+624+200 --steady 140x150+580+160` (the crop is the glass inside the chair's porthole, above the dark lower band whose moving edge it would count; the steady box is the capture's default crop, the porthole and its ring); the footage `python3 tools/motion_stats.py tmp/0289/a30_285 --crop 340x170+40+15 --fps 30` (copies of `work/reference/0288/a30_285/f_*.png`, 400 x 225; the crop is the pane inside its dark frame and bottom corners). Tolerances: energy and brightness 0.002, shares, consistency, coherence and correlations 0.03, directions and orientations 5 degrees, pixels a frame 0.2.

| Line | Our peak (0286, 1271) | Artemis I, 285 s (peak) | Artemis I, 316 s |
|---|---|---|---|
| energy at 30 fps | 0.1089 | 0.0258 | 0.0230 |
| energy concentration | 0.41 | 0.35 | 0.58 |
| brightness mean, deviation | 0.529, 0.1086 | 0.654, 0.0094 | 0.586, 0.0101 |
| brightness bands at 30 fps | 0.42, 0.52, 0.05 | 0.09, 0.65, 0.26 | 0.10, 0.35, 0.55 |
| steady | 2.92 px a frame, largest 6.98 | none | none |
| flow | 73 degrees, net 2.58, median 4.85 px a frame (5.59 crop widths a second), consistency 0.56 | 190 degrees, net 0.05, median 1.09 (0.10), consistency 0.34 | 36 degrees, net 0.52, median 1.03 (0.09), consistency 0.10 |
| streaks | 51 degrees, coherence 0.12 | 151 degrees, 0.44 | 0 degrees, 0.42 |
| persistence | 0.726, 0.052 s | 0.906, 0.338 s | 0.874, 0.248 s |

Also measured (no tolerance asked): 0286 at 1000 energy at 30 fps 0.070, flow 64 degrees median 7.51 crop widths a second, persistence 0.032 s; at 1600 0.005, persistence 0.393 s; at 1271 with reduced motion 0.0156, flow 75 degrees median 4.26, persistence 0.239 s; the 0273 plasma (`tmp/shot0274`, `--name clip`, the same boxes) 0.057, steady 2.11, flow median 1.11 crop widths a second, persistence 0.337 s; Artemis I at 297 s 0.0101, persistence 1.380 s.

The first comparison, for the log: our peak changes four times as much per thirtieth of a second as the footage, and its brightness swings twelve times as far (deviation 0.109 against 0.009), mostly in slow swings (0.42 under 2 Hz against 0.09) where the footage's flicker sits at 2 to 15 Hz (0.26 to 0.55 of it between 6 and 15). The footage is a steady glow (persistence 0.91, nothing tracked moves, a feature keeps its look a third of a second) with sparse one frame streaks laid over it, and those streaks are oriented (coherence 0.44 against our 0.12). Ours is the whole field translating upward at about 5 crop widths a second and morphing as it goes (persistence 0.73, 0.05 s). So our flames lack a calm, steady backdrop, oriented streaks that are the change, and a fast small flicker in place of the big slow brightness swing; 0288's FAST_FLOW is measured by this tool once its clips exist.

### Docs

`doc/commands.md`, For the assistant, a step 7 after the capture script: `python3 tools/motion_stats.py <frames directory> [--name NAME] [--crop WxH+X+Y] [--fps N] [--steady WxH+X+Y]` (0289) prints the same lines for every series of frames `<name>_NN.png` (a capture's, or footage cut with `ffmpeg`, with its rate as `--fps`): the motion energy, its 30 fps form and its concentration, the brightness and its share in the bands under 2, 2 to 6, 6 to 15 and over 15 Hz (also resampled to 30 fps, so a 60 fps clip and 30 fps footage compare), the flow by phase correlation (degrees with 0 right and 90 up, net and median pixels a frame and crop widths a second, consistency) with `--steady` subtracting a box's own motion (the porthole's ring against the buffet), the streaks' orientation and coherence, the persistence and its decorrelation time, and writes `<name>_delta_strip.png` beside the frames (every third difference amplified eight times, ten a row). Statistics run on the crop reduced to at most 64 pixels a side, so crops of different sizes compare. `doc/developer_tools.md` covers the in-game screens only and is not touched. No log or other doc; the yardstick goes into the log at the landing (the main agent's).

### Hand-back check

- A path from an argument stays where it is given: the strip is written only into the given frames directory under a name built from the matched frame name (no separator in it), through `<path>.tmp` and a rename.
- A number parsed from text is range checked: the crop's four fields (at most 5 digits, sides at least 8, the box inside every frame), the fps (finite, above 0, at most 1000).
- Tests use temporary directories only. The other lines do not apply (no game state, no save, no UI).

### For the main agent

- The steady subtraction carries about one pixel of error per pair: the 140 x 150 box is analysed at 64 pixels a side (2.3 crop pixels each). At 1271 the buffet moves the porthole 2.9 pixels a frame (up to 30 pixels from frame 0 over the clip), so the peak's flow numbers carry that error. A cleaner yardstick is a clip with the buffet off, if a command or setting gives one without slowing the plasma (reduced motion slows both); I did not find whether one exists.
- Speeds are in crop widths, not window widths: the game crop is 52 of the glass's about 75 pixels, the footage crop 340 of the pane's about 380. To read window widths a second multiply by about 0.69 for the game and 0.9 for the footage, or add a `--window PIXELS` option; I left it out.
- The footage's flow is not measurable frame to frame: its streaks live one frame, so phase correlation finds the steady glow and reports no motion. The streak line gives their direction; their speed (a streak's length times the rate, 0288's method) is not automated. A streak length statistic would be its own item.
- `DELTA_GAIN` 8 makes the footage's faint change visible and saturates much of our peak's; no option for it.
- The item's "our clips of 0288" do not exist yet; the table is 0286's peak. Run the tool on 0288's clips when the main agent captures them.
- The footage frames under `work/reference/0288/` are 400 x 225 (the 0288 designer's cut); analysis at 64 pixels a side makes full resolution unnecessary.

### Decisions (main agent, 2026-10-05)

1. Approved as designed: pure Python over PIL, the lines, the strip, `--steady`, the tests and the yardstick with its tolerances.
2. One addition: `--window PIXELS`, the window's width inside the crop, prints every speed a second time in window widths a second beside the crop widths, so the game (about 75 pixels of glass) and the footage (about 380 of pane) compare. Without the option that second number is left out.
3. No command turns the buffet off alone; `--steady` is the way, and the docs say so. A streak length statistic is a later item if the couch wants one. The 0288 clips are scored when the main agent captures them.
