#!/usr/bin/env python3
"""Measure the motion in a series of frames (work item 0289,
doc/commands.md, For the assistant), so a flame of ours and footage of a
flame we want to mimic are compared by the same numbers.

  python3 tools/motion_stats.py <frames directory> [--name NAME]
      [--crop WxH+X+Y] [--fps N] [--steady WxH+X+Y] [--window PIXELS]

Reads the frames <name>_NN.png of the directory (a capture of
tools/capture_clip.sh, or footage cut with ffmpeg) and prints one line per
statistic, the same lines for every series: the motion energy, the
brightness and its share in bands of rates, the flow by phase
correlation, the streaks of the change and the persistence of the
features. Every statistic reads the crop reduced to at most 64 pixels a
side. --steady subtracts a box's own rigid motion from the flow (the
porthole's ring against the buffet). --window gives the window's width in the
frame's pixels (it may be wider than the crop) and prints every speed a
second time in window widths a second. Writes <name>_delta_strip.png beside the frames: every third
difference between consecutive frames amplified, ten a row.
"""

import argparse
import cmath
import dataclasses
import math
import pathlib
import re
import sys

from PIL import Image, ImageChops

ANALYSIS_SIDE = 64
TRANSFORM_SIZE = 64
COMMON_RATE = 30
BAND_EDGES = (2.0, 6.0, 15.0)
BAND_NAMES = ("under 2", "2 to 6", "6 to 15", "over 15")
# A phase correlation peak under it is no match.
MATCH_FLOOR = 0.1
# Crop pixels a frame; a shorter shift is still.
STILL_SHIFT = 0.5
AGREE_DEGREES = 30.0
CONCENTRATION_SHARE = 0.1
DELTA_GAIN = 8
DELTA_EVERY = 3
DELTA_COLUMNS = 10
DELTA_MARGIN = 2
MINIMUM_FRAMES = 4
MINIMUM_CROP_SIDE = 8
MAXIMUM_RATE = 1000.0
FRAME_PATTERN = re.compile(r"(.+)_(\d+)\.png")
CROP_PATTERN = re.compile(r"(\d{1,5})x(\d{1,5})\+(\d{1,5})\+(\d{1,5})")
WINDOW_PATTERN = re.compile(r"\d{1,5}")


def parse_crop(text):
    """The box (left, top, right, bottom) of an ImageMagick geometry
    WxH+X+Y, refused unless each side is at least MINIMUM_CROP_SIDE."""
    match = CROP_PATTERN.fullmatch(text)
    if not match:
        raise ValueError(f"crop {text!r} is not WxH+X+Y")
    width, height, left, top = (int(field) for field in match.groups())
    if width < MINIMUM_CROP_SIDE or height < MINIMUM_CROP_SIDE:
        raise ValueError(f"crop {text} is under {MINIMUM_CROP_SIDE} pixels a side")
    return (left, top, left + width, top + height)


def parse_rate(text):
    """The frames a second, refused unless finite, above 0 and at most
    MAXIMUM_RATE."""
    try:
        rate = float(text)
    except ValueError:
        raise ValueError(f"fps {text!r} is not a number") from None
    if not (math.isfinite(rate) and 0 < rate <= MAXIMUM_RATE):
        raise ValueError(f"fps {text} is not above 0 and at most {MAXIMUM_RATE:g}")
    return rate


def parse_window(text):
    """The window's width in the frame's pixels (it may be wider than
    the crop), refused unless a whole number
    of at most five digits and at least 1."""
    if not WINDOW_PATTERN.fullmatch(text) or int(text) < 1:
        raise ValueError(f"window {text!r} is not a width of 1 to 99999 pixels")
    return int(text)


def frame_groups(directory):
    """The frames of the directory (not recursive) by name, each list
    sorted by the frame number as an integer."""
    groups = {}
    for path in directory.iterdir():
        match = FRAME_PATTERN.fullmatch(path.name)
        if match and path.is_file():
            groups.setdefault(match.group(1), []).append((int(match.group(2)), path))
    return {name: [path for _, path in sorted(found)] for name, found in groups.items()}


def select_frames(groups, name):
    """The name and the frames of the named group, or of the only group
    when no name is given; refused under MINIMUM_FRAMES frames."""
    if name is None:
        if len(groups) != 1:
            if not groups:
                raise ValueError("the directory holds no frames <name>_NN.png")
            raise ValueError(f"the directory holds frames of {', '.join(sorted(groups))}, name one with --name")
        name = next(iter(groups))
    if name not in groups:
        raise ValueError(f"no frames named {name}_NN.png")
    if len(groups[name]) < MINIMUM_FRAMES:
        raise ValueError(f"{name} has {len(groups[name])} frames, under {MINIMUM_FRAMES}")
    return name, groups[name]


def load_crops(paths, box, box_name="crop"):
    """Each frame as gray (ITU-R 601 luma), checked against the first
    frame's size, cropped to the box (or whole when the box is None); a
    box reaching past a frame is refused under its name."""
    crops = []
    first_size = None
    for path in paths:
        with Image.open(path) as opened:
            gray = opened.convert("L")
        first_size = first_size or gray.size
        if gray.size != first_size:
            raise ValueError(f"{path.name} is {gray.width}x{gray.height}, the first frame {first_size[0]}x{first_size[1]}")
        if box is not None and (box[2] > gray.width or box[3] > gray.height):
            raise ValueError(f"{box_name} reaches past {path.name} ({gray.width}x{gray.height})")
        crops.append(gray if box is None else gray.crop(box))
    return crops


def analysis_size(width, height):
    """The size a crop is analysed at: at most ANALYSIS_SIDE a side,
    never enlarged."""
    factor = min(1.0, ANALYSIS_SIDE / max(width, height))
    return max(1, round(width * factor)), max(1, round(height * factor))


def analysis_image(gray):
    """The analysis image (width, height, values) of a gray crop, values
    the gray levels 0 to 1 row by row."""
    width, height = analysis_size(*gray.size)
    small = gray.resize((width, height), Image.Resampling.BOX)
    return width, height, [value / 255 for value in small.get_flattened_data()]


def mean(values):
    """The mean, 0 for no values."""
    return sum(values) / len(values) if values else 0.0


def deviation(values):
    """The population standard deviation."""
    middle = mean(values)
    return math.sqrt(mean([(value - middle) ** 2 for value in values]))


def energy(previous, following):
    """The mean absolute change between two analysis images."""
    return mean([abs(after - before) for before, after in zip(previous[2], following[2])])


def concentration(previous, following):
    """The share of the change held by the top CONCENTRATION_SHARE of
    the pixels, 0 when nothing changes."""
    changes = sorted((abs(after - before) for before, after in zip(previous[2], following[2])), reverse=True)
    total = sum(changes)
    top = max(1, round(len(changes) * CONCENTRATION_SHARE))
    return sum(changes[:top]) / total if total > 0 else 0.0


def fft(values):
    """The discrete Fourier transform of a power of two count of values,
    recursive radix 2."""
    count = len(values)
    if count == 1:
        return list(values)
    even, odd = fft(values[0::2]), fft(values[1::2])
    result = [0j] * count
    for index in range(count // 2):
        turned = cmath.exp(-2j * math.pi * index / count) * odd[index]
        result[index] = even[index] + turned
        result[index + count // 2] = even[index] - turned
    return result


def transpose(rows):
    """The columns of a grid as rows."""
    return [list(column) for column in zip(*rows)]


def fft_2d(rows):
    """The two dimensional transform: the rows, then the columns."""
    return transpose([fft(column) for column in transpose([fft(row) for row in rows])])


def inverse_fft_2d(rows):
    """The inverse two dimensional transform through the conjugates."""
    conjugated = [[value.conjugate() for value in row] for row in rows]
    count = len(rows) * len(rows[0])
    return [[value.conjugate() / count for value in row] for row in fft_2d(conjugated)]


def hann(index, count):
    """The Hann window's weight of a sample of count."""
    return 0.5 - 0.5 * math.cos(2 * math.pi * (index + 0.5) / count)


def windowed_grid(image):
    """A TRANSFORM_SIZE square complex grid holding the image's values
    minus their mean, Hann windowed, at the top left, zeros elsewhere."""
    width, height, values = image
    middle = mean(values)
    grid = [[0j] * TRANSFORM_SIZE for _ in range(TRANSFORM_SIZE)]
    for y in range(height):
        for x in range(width):
            grid[y][x] = complex((values[y * width + x] - middle) * hann(x, width) * hann(y, height))
    return grid


def normalised_cross_power(previous_spectrum, following_spectrum):
    """Per element the following times the previous conjugated, over its
    magnitude, 0 where the magnitude is under 1e-12."""
    rows = []
    for previous_row, following_row in zip(previous_spectrum, following_spectrum):
        row = []
        for before, after in zip(previous_row, following_row):
            product = after * before.conjugate()
            magnitude = abs(product)
            row.append(product / magnitude if magnitude > 1e-12 else 0j)
        rows.append(row)
    return rows


def signed(index):
    """A transform index as a signed shift."""
    return index - TRANSFORM_SIZE if index >= TRANSFORM_SIZE // 2 else index


def vertex_offset(left, centre, right):
    """The offset of the parabola's vertex through three samples, 0 when
    they lie on a line."""
    denominator = left - 2 * centre + right
    return 0.0 if denominator == 0 else 0.5 * (left - right) / denominator


def phase_correlation(previous_spectrum, following_spectrum):
    """The shift (x, y, peak) from the previous frame to the following
    in analysis pixels: x positive to the right, y positive down, peak 1
    for a pure shift and near 0 for unrelated frames."""
    cross_power = normalised_cross_power(previous_spectrum, following_spectrum)
    surface = [[value.real for value in row] for row in inverse_fft_2d(cross_power)]
    peak, peak_x, peak_y = max((value, x, y) for y, row in enumerate(surface) for x, value in enumerate(row))
    size = TRANSFORM_SIZE
    offset_x = vertex_offset(surface[peak_y][(peak_x - 1) % size], peak, surface[peak_y][(peak_x + 1) % size])
    offset_y = vertex_offset(surface[(peak_y - 1) % size][peak_x], peak, surface[(peak_y + 1) % size][peak_x])
    return signed(peak_x) + offset_x, signed(peak_y) + offset_y, peak


def pair_shifts(images):
    """The phase correlation shift of each consecutive pair of analysis
    images, in analysis pixels, each spectrum made once."""
    spectra = [fft_2d(windowed_grid(image)) for image in images]
    return [phase_correlation(previous, following) for previous, following in zip(spectra, spectra[1:])]


def shifted_correlation(previous, following, shift_x, shift_y):
    """The Pearson correlation of the overlap of two analysis images
    after shifting by the rounded shift: 1 when both are flat, 0 when one
    is or when nothing overlaps."""
    width, height, previous_values = previous
    following_values = following[2]
    step_x, step_y = round(shift_x), round(shift_y)
    pairs = [(previous_values[y * width + x], following_values[(y + step_y) * width + x + step_x])
             for y in range(max(0, -step_y), min(height, height - step_y))
             for x in range(max(0, -step_x), min(width, width - step_x))]
    if not pairs:
        return 0.0
    previous_mean = mean([before for before, _ in pairs])
    following_mean = mean([after for _, after in pairs])
    product = sum((before - previous_mean) * (after - following_mean) for before, after in pairs)
    previous_spread = sum((before - previous_mean) ** 2 for before, _ in pairs)
    following_spread = sum((after - following_mean) ** 2 for _, after in pairs)
    if previous_spread <= 1e-12 or following_spread <= 1e-12:
        return 1.0 if previous_spread <= 1e-12 and following_spread <= 1e-12 else 0.0
    return product / math.sqrt(previous_spread * following_spread)


def common_step(rate):
    """The frames a COMMON_RATE frame spans when the rate is a whole
    multiple of it, else None."""
    ratio = rate / COMMON_RATE
    step = round(ratio)
    return step if step >= 1 and abs(ratio - step) < 1e-6 else None


def resampled(series, rate):
    """The series at COMMON_RATE: the mean of each group of common_step
    samples (what a camera exposing a whole frame sees), else linear
    interpolation."""
    step = common_step(rate)
    if step is not None:
        return [mean(series[index:index + step]) for index in range(0, len(series) - step + 1, step)]
    points = []
    for index in range(int((len(series) - 1) / rate * COMMON_RATE) + 1):
        position = index * rate / COMMON_RATE
        low = min(int(position), len(series) - 1)
        high = min(low + 1, len(series) - 1)
        fraction = position - low
        points.append(series[low] * (1 - fraction) + series[high] * fraction)
    return points


def band_index(frequency):
    """The band of a frequency in Hz; the last edge belongs to the band
    below it, so a 30 fps Nyquist bin lands in 6 to 15."""
    for index, edge in enumerate(BAND_EDGES):
        if frequency < edge or (index == len(BAND_EDGES) - 1 and frequency <= edge):
            return index
    return len(BAND_EDGES)


def band_shares(series, rate):
    """Each band's share of the series' power, the mean removed, all 0
    for a constant series."""
    count = len(series)
    middle = mean(series)
    powers = [0.0] * (len(BAND_EDGES) + 1)
    for bin_index in range(1, count // 2 + 1):
        total = sum((value - middle) * cmath.exp(-2j * math.pi * bin_index * index / count)
                    for index, value in enumerate(series))
        weight = 1.0 if 2 * bin_index == count else 2.0
        powers[band_index(bin_index * rate / count)] += weight * abs(total) ** 2
    whole = sum(powers)
    return [power / whole if whole > 0 else 0.0 for power in powers]


def direction_degrees(shift_x, shift_y):
    """The direction of a shift in image axes: 0 is screen right, 90
    screen up."""
    return math.degrees(math.atan2(-shift_y, shift_x)) % 360


def angle_between(first, second):
    """The smaller angle between two directions in degrees."""
    return abs((first - second + 180) % 360 - 180)


@dataclasses.dataclass(frozen=True)
class Flow:
    """The flow of a series: the net direction in degrees, the net and
    median speeds in crop pixels a frame and crop widths a second, and the
    share of the pairs moving within AGREE_DEGREES of the net direction."""

    direction: float
    net: float
    net_widths: float
    median: float
    median_widths: float
    consistency: float


def flow_summary(shifts, rate, crop_width):
    """The Flow of the pair shifts (x, y, peak) in crop pixels, or None
    when no matched pair moves, and the matched share of the pairs."""
    matched = [(x, y) for x, y, peak in shifts if peak >= MATCH_FLOOR]
    moving = [(x, y) for x, y in matched if math.hypot(x, y) >= STILL_SHIFT]
    matched_share = len(matched) / len(shifts)
    if not moving:
        return None, matched_share
    net_x, net_y = mean([x for x, _ in matched]), mean([y for _, y in matched])
    direction = direction_degrees(net_x, net_y)
    agreeing = sum(1 for x, y in moving if angle_between(direction_degrees(x, y), direction) <= AGREE_DEGREES)
    speeds = sorted(math.hypot(x, y) for x, y in moving)
    middle = len(speeds) // 2
    median = speeds[middle] if len(speeds) % 2 else 0.5 * (speeds[middle - 1] + speeds[middle])
    net = math.hypot(net_x, net_y)
    flow = Flow(direction, net, net * rate / crop_width, median, median * rate / crop_width, agreeing / len(shifts))
    return flow, matched_share


def change_tensor(previous, following):
    """The structure tensor sums (xx, yy, xy) of the central differences
    of the change between two analysis images, over the inner pixels."""
    width, height, previous_values = previous
    change = [abs(after - before) for before, after in zip(previous_values, following[2])]
    xx = yy = xy = 0.0
    for y in range(1, height - 1):
        for x in range(1, width - 1):
            gradient_x = 0.5 * (change[y * width + x + 1] - change[y * width + x - 1])
            gradient_y = 0.5 * (change[(y + 1) * width + x] - change[(y - 1) * width + x])
            xx += gradient_x * gradient_x
            yy += gradient_y * gradient_y
            xy += gradient_x * gradient_y
    return xx, yy, xy


def streak_summary(images):
    """The orientation in degrees the change is drawn out along (0
    horizontal, 90 vertical, 45 rising to the right) and its coherence (0
    blobs, 1 parallel streaks), or None when nothing changes."""
    tensors = [change_tensor(previous, following) for previous, following in zip(images, images[1:])]
    xx, yy, xy = (sum(tensor[index] for tensor in tensors) for index in range(3))
    if xx + yy <= 0:
        return None
    orientation = round(0.5 * math.degrees(math.atan2(-2 * xy, xx - yy)) + 90) % 180
    coherence = math.sqrt((xx - yy) ** 2 + 4 * xy * xy) / (xx + yy)
    return orientation, coherence


def delta_strip(crops):
    """Every DELTA_EVERY difference of consecutive gray crops, amplified
    DELTA_GAIN times, DELTA_COLUMNS a row on black."""
    width, height = crops[0].size
    tiles = [ImageChops.difference(crops[index], crops[index + 1]).point(lambda value: min(255, value * DELTA_GAIN))
             for index in range(0, len(crops) - 1, DELTA_EVERY)]
    columns = min(DELTA_COLUMNS, len(tiles))
    rows = math.ceil(len(tiles) / DELTA_COLUMNS)
    cell_width, cell_height = width + 2 * DELTA_MARGIN, height + 2 * DELTA_MARGIN
    strip = Image.new("L", (columns * cell_width, rows * cell_height), 0)
    for index, tile in enumerate(tiles):
        left = (index % DELTA_COLUMNS) * cell_width + DELTA_MARGIN
        top = (index // DELTA_COLUMNS) * cell_height + DELTA_MARGIN
        strip.paste(tile, (left, top))
    return strip


def write_png(image, path):
    """The image saved as PNG to <path>.tmp, then renamed over the path."""
    temporary = path.with_name(path.name + ".tmp")
    image.save(temporary, format="PNG")
    temporary.replace(path)


def series_text(values):
    """The values with three decimals, joined by spaces."""
    return " ".join(f"{value:.3f}" for value in values)


def bands_text(shares, rate):
    """The band shares named, the band over 15 Hz as - when the rate
    cannot hold it."""
    parts = []
    for index, (name, share) in enumerate(zip(BAND_NAMES, shares)):
        reachable = index < len(BAND_EDGES) or rate > 2 * BAND_EDGES[-1]
        parts.append(f"{name} {share:.2f}" if reachable else f"{name} -")
    return ", ".join(parts)


def scaled_shifts(shifts, scale):
    """Pair shifts in analysis pixels scaled to crop pixels."""
    return [(x * scale, y * scale, peak) for x, y, peak in shifts]


def speed_text(pixels, widths, rate, window):
    """A speed in pixels a frame with its crop widths a second, and its
    window widths a second when a window is given."""
    window_text = "" if window is None else f", {pixels * rate / window:.2f} window widths a second"
    return f"{pixels:.2f} px a frame ({widths:.2f} crop widths a second{window_text})"


def report(name, count, crop_text, rate, crops, steady_crops, window=None):
    """The lines of the statistics of a series of gray crops, the same
    lines in the same order for every series."""
    images = [analysis_image(crop) for crop in crops]
    crop_width = crops[0].size[0]
    shifts = pair_shifts(images)
    energies = [energy(previous, following) for previous, following in zip(images, images[1:])]
    step = common_step(rate)
    common_energies = [energy(previous, following) for previous, following in zip(images, images[step:])] if step else []
    concentrations = [concentration(previous, following) for previous, following in zip(images, images[1:])]
    brightness = [mean(image[2]) for image in images]
    steps = [abs(after - before) for before, after in zip(brightness, brightness[1:])]
    correlations = [shifted_correlation(previous, following, x, y)
                    for (previous, following), (x, y, _) in zip(zip(images, images[1:]), shifts)]
    flow_shifts = scaled_shifts(shifts, crop_width / images[0][0])
    steady_line = "steady: none"
    if steady_crops:
        steady_images = [analysis_image(crop) for crop in steady_crops]
        steady = scaled_shifts(pair_shifts(steady_images), steady_crops[0].size[0] / steady_images[0][0])
        flow_shifts = [(x - steady_x, y - steady_y, peak)
                       for (x, y, peak), (steady_x, steady_y, _) in zip(flow_shifts, steady)]
        steady_speeds = [math.hypot(steady_x, steady_y) for steady_x, steady_y, _ in steady]
        steady_line = (f"steady: mean {mean(steady_speeds):.2f} px a frame, largest {max(steady_speeds):.2f},"
                       " subtracted from the flow")
    flow, matched = flow_summary(flow_shifts, rate, crop_width)
    if flow is None:
        flow_line = f"flow: still, matched {matched:.2f}"
    else:
        flow_line = (f"flow: direction {round(flow.direction) % 360} degrees,"
                     f" net {speed_text(flow.net, flow.net_widths, rate, window)},"
                     f" median {speed_text(flow.median, flow.median_widths, rate, window)},"
                     f" consistency {flow.consistency:.2f}, matched {matched:.2f}")
    streaks = streak_summary(images)
    persistence = mean(correlations)
    if persistence >= 1:
        decorrelation = "inf"
    elif persistence <= 0:
        decorrelation = "0"
    else:
        decorrelation = f"{-1 / (rate * math.log(persistence)):.3f}"
    common_text = f"mean {mean(common_energies):.4f}, deviation {deviation(common_energies):.4f}" if step else "-"
    return [
        f"frames: {name}, {count} at {rate:g} fps ({count / rate:.2f} s), crop {crop_text},"
        f" analysed at {images[0][0]}x{images[0][1]}",
        f"energy: mean {mean(energies):.4f}, deviation {deviation(energies):.4f}",
        f"energy at 30 fps: {common_text}",
        f"energy concentration: {mean(concentrations):.2f} of the change in the top tenth of the pixels",
        f"energy series: {series_text(energies)}",
        f"brightness: mean {mean(brightness):.4f}, deviation {deviation(brightness):.4f},"
        f" mean step {mean(steps):.4f}, largest step {max(steps):.4f}",
        f"brightness bands: {bands_text(band_shares(brightness, rate), rate)}",
        f"brightness bands at 30 fps: {bands_text(band_shares(resampled(brightness, rate), COMMON_RATE), COMMON_RATE)}",
        f"brightness series: {series_text(brightness)}",
        steady_line,
        flow_line,
        "streaks: none" if streaks is None else f"streaks: orientation {streaks[0]} degrees, coherence {streaks[1]:.2f}",
        f"persistence: correlation {persistence:.3f}, decorrelation {decorrelation} s",
    ]


def main(arguments):
    """Print the statistics of the frames named on the command line and
    write the delta strip beside them; 0 on success, 1 on an error."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory", help="the directory holding the frames <name>_NN.png")
    parser.add_argument("--name", help="the frames' name, needed when the directory holds several")
    parser.add_argument("--crop", help="the box every statistic reads, WxH+X+Y (default the whole frame)")
    parser.add_argument("--fps", default="60", help="the series' rate (default 60, the game's tick)")
    parser.add_argument("--steady", help="a box WxH+X+Y whose own motion is subtracted from the flow")
    parser.add_argument("--window", help="the window's width in the frame's pixels (it may be wider than the crop), for speeds in window widths")
    options = parser.parse_args(arguments)
    try:
        directory = pathlib.Path(options.directory)
        rate = parse_rate(options.fps)
        box = parse_crop(options.crop) if options.crop else None
        steady_box = parse_crop(options.steady) if options.steady else None
        window = parse_window(options.window) if options.window else None
        name, paths = select_frames(frame_groups(directory), options.name)
        crops = load_crops(paths, box)
        steady_crops = load_crops(paths, steady_box, "steady box") if steady_box else None
    except (ValueError, OSError) as error:
        print(f"motion_stats: {error}", file=sys.stderr)
        return 1
    crop_text = options.crop or f"{crops[0].width}x{crops[0].height}+0+0"
    for line in report(name, len(paths), crop_text, rate, crops, steady_crops, window):
        print(line)
    strip_path = directory / f"{name}_delta_strip.png"
    try:
        write_png(delta_strip(crops), strip_path)
    except OSError as error:
        print(f"motion_stats: {error}", file=sys.stderr)
        return 1
    print(f"delta strip: {strip_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
