#!/usr/bin/env python3
"""Tests of tools/motion_stats.py (work item 0289): the statistics on
synthetic series made with PIL, the frames written into temporary
directories.

Usage: python3 tools/motion_stats_test.py
"""

import contextlib
import io
import math
import os
import pathlib
import random
import re
import sys
import tempfile
import unittest

from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import motion_stats  # noqa: E402

LINE_PREFIXES = (
    "frames:", "energy:", "energy at 30 fps:", "energy concentration:", "energy series:",
    "brightness:", "brightness bands:", "brightness bands at 30 fps:", "brightness series:",
    "steady:", "flow:", "streaks:", "persistence:", "delta strip:",
)


def pattern(width, height, seed):
    """A smooth random gray pattern: random levels on a quarter size image
    resized bicubic to the size."""
    generator = random.Random(seed)
    small = Image.new("L", (width // 4, height // 4))
    small.putdata([generator.randrange(256) for _ in range(small.width * small.height)])
    return small.resize((width, height), Image.Resampling.BICUBIC)


def drifting_crops(boxes):
    """The pattern cropped to each box in turn."""
    source = pattern(256, 128, 7)
    return [source.crop(box) for box in boxes]


def flat_frames(level_of_frame, count):
    """Flat 32 x 32 frames at the level each frame index gives."""
    return [Image.new("L", (32, 32), level_of_frame(index)) for index in range(count)]


def flicker(frequency):
    """The level of a frame of a flat field flickering at the frequency
    at 60 fps."""
    return lambda index: round(128 + 60 * math.sin(2 * math.pi * frequency * index / 60))


def analysed(crops):
    return [motion_stats.analysis_image(crop) for crop in crops]


def flow_of(crops, rate):
    images = analysed(crops)
    scale = crops[0].width / images[0][0]
    shifts = motion_stats.scaled_shifts(motion_stats.pair_shifts(images), scale)
    return motion_stats.flow_summary(shifts, rate, crops[0].width)


def persistence_of(crops):
    images = analysed(crops)
    shifts = motion_stats.pair_shifts(images)
    pairs = zip(zip(images, images[1:]), shifts)
    return motion_stats.mean([motion_stats.shifted_correlation(previous, following, x, y)
                              for (previous, following), (x, y, _) in pairs])


def noise_frames(small_width, small_height):
    """Ten frames of fresh noise each, small_width x small_height resized
    bicubic to 64 x 64, so the change is drawn out along the long side."""
    generator = random.Random(3)
    frames = []
    for _ in range(10):
        small = Image.new("L", (small_width, small_height))
        small.putdata([generator.randrange(256) for _ in range(small_width * small_height)])
        frames.append(small.resize((64, 64), Image.Resampling.BICUBIC))
    return frames


def write_drifting_frames(directory, count):
    """count frames 32 x 24 of the pattern drifting right, d_00.png on."""
    for index in range(count):
        drifting_crops([(100 - index, 40, 132 - index, 64)])[0].save(directory / f"d_{index:02}.png")


def run_main(arguments):
    """main's return code, stdout lines and stderr text."""
    output, errors = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
        code = motion_stats.main(arguments)
    return code, output.getvalue().splitlines(), errors.getvalue()


class MotionStatsTest(unittest.TestCase):
    def test_a_still_series_has_no_energy_and_no_flow(self):
        crops = [pattern(256, 128, 7).crop((10, 10, 74, 58)) for _ in range(6)]
        images = analysed(crops)
        for previous, following in zip(images, images[1:]):
            self.assertEqual(motion_stats.energy(previous, following), 0)
        self.assertEqual(flow_of(crops, 60), (None, 1.0))
        self.assertAlmostEqual(persistence_of(crops), 1.0)
        lines = motion_stats.report("still", len(crops), "64x48+0+0", 60, crops, None)
        self.assertIn("flow: still, matched 1.00", lines)

    def test_a_pattern_drifting_right_flows_at_zero_degrees(self):
        crops = drifting_crops([(100 - 3 * index, 40, 164 - 3 * index, 88) for index in range(10)])
        flow, _ = flow_of(crops, 60)
        self.assertLessEqual(motion_stats.angle_between(flow.direction, 0), 2)
        self.assertAlmostEqual(flow.net, 3.0, delta=0.1)
        self.assertAlmostEqual(flow.net_widths, 3 * 60 / 64, delta=0.1)
        self.assertEqual(flow.consistency, 1.0)
        self.assertGreater(persistence_of(crops), 0.95)

    def test_a_pattern_drifting_up_flows_at_ninety_degrees(self):
        crops = drifting_crops([(40, 40 + 3 * index, 104, 88 + 3 * index) for index in range(10)])
        flow, _ = flow_of(crops, 60)
        self.assertLessEqual(motion_stats.angle_between(flow.direction, 90), 2)
        self.assertAlmostEqual(flow.net, 3.0, delta=0.1)

    def test_a_flicker_at_10_hz_lands_in_the_6_to_15_band(self):
        crops = flat_frames(flicker(10), 60)
        brightness = [motion_stats.mean(image[2]) for image in analysed(crops)]
        self.assertGreater(motion_stats.band_shares(brightness, 60)[2], 0.95)
        self.assertGreater(motion_stats.band_shares(motion_stats.resampled(brightness, 60), 30)[2], 0.95)
        self.assertEqual(flow_of(crops, 60), (None, 0.0))

    def test_a_1_hz_wave_lands_under_2(self):
        brightness = [motion_stats.mean(image[2]) for image in analysed(flat_frames(flicker(1), 60))]
        self.assertGreater(motion_stats.band_shares(brightness, 60)[0], 0.95)

    def test_a_30_fps_series_has_no_over_15_band(self):
        self.assertTrue(motion_stats.bands_text([0.25] * 4, 30).endswith("over 15 -"))
        self.assertEqual(len(motion_stats.resampled([float(index) for index in range(60)], 60)), 30)
        series = [float(index) for index in range(50)]
        points = motion_stats.resampled(series, 25)
        self.assertEqual(len(points), int(49 / 25 * 30) + 1)
        self.assertAlmostEqual(points[0], series[0])
        # The last point is the last whole thirtieth inside the series.
        self.assertAlmostEqual(points[-1], (len(points) - 1) * 25 / 30)
        self.assertLessEqual(points[-1], series[-1])

    def test_streaks_read_their_orientation(self):
        orientation, coherence = motion_stats.streak_summary(analysed(noise_frames(16, 2)))
        self.assertLessEqual(abs(orientation - 90), 5)
        self.assertGreater(coherence, 0.8)
        orientation, coherence = motion_stats.streak_summary(analysed(noise_frames(2, 16)))
        self.assertLessEqual(min(orientation, 180 - orientation), 5)
        self.assertGreater(coherence, 0.8)

    def test_the_crop_and_the_rate_are_range_checked(self):
        for text in ("52x32", "52x32+1", "4x32+0+0", "52x32+-1+0", "123456x2+0+0"):
            with self.assertRaises(ValueError):
                motion_stats.parse_crop(text)
        self.assertEqual(motion_stats.parse_crop("52x32+624+200"), (624, 200, 676, 232))
        for text in ("0", "-1", "nan", "inf", "1001", "abc"):
            with self.assertRaises(ValueError):
                motion_stats.parse_rate(text)
        self.assertEqual(motion_stats.parse_rate("29.97"), 29.97)
        for text in ("0", "-5", "7.5", "123456", "abc"):
            with self.assertRaises(ValueError):
                motion_stats.parse_window(text)
        self.assertEqual(motion_stats.parse_window("75"), 75)

    def test_frames_are_selected_by_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            names = ["a_9.png", "a_10.png", "a_11.png", "a_12.png", "a_calm_00.png", "a_calm_01.png",
                     "a_calm_02.png", "a_strip.png"]
            for name in names:
                Image.new("L", (8, 8)).save(directory / name)
            groups = motion_stats.frame_groups(directory)
            self.assertEqual(sorted(groups), ["a", "a_calm"])
            self.assertEqual([path.name for path in groups["a"]], ["a_9.png", "a_10.png", "a_11.png", "a_12.png"])
            with self.assertRaisesRegex(ValueError, "a, a_calm"):
                motion_stats.select_frames(groups, None)
            with self.assertRaises(ValueError):
                motion_stats.select_frames(groups, "a_calm")

    def test_the_delta_strip_lands_beside_the_frames(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            write_drifting_frames(directory, 31)
            code, lines, _ = run_main([str(directory), "--crop", "16x12+0+0"])
            self.assertEqual(code, 0)
            with Image.open(directory / "d_delta_strip.png") as strip:
                self.assertEqual(strip.size, (200, 16))
            self.assertEqual(list(directory.glob("*.tmp")), [])
            self.assertEqual(len(lines), len(LINE_PREFIXES))
            for line, prefix in zip(lines, LINE_PREFIXES):
                self.assertTrue(line.startswith(prefix), line)
            self.assertNotIn("window widths", lines[10])

    def test_the_window_adds_window_widths_to_every_speed(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            write_drifting_frames(directory, 8)
            code, lines, _ = run_main([str(directory), "--window", "64"])
            self.assertEqual(code, 0)
            speeds = re.findall(r"\(([\d.]+) crop widths a second, ([\d.]+) window widths a second\)", lines[10])
            self.assertEqual(len(speeds), 2)
            for crop_widths, window_widths in speeds:
                self.assertAlmostEqual(float(window_widths), float(crop_widths) / 2, delta=0.01)

    def test_a_crop_past_the_frame_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            write_drifting_frames(directory, 31)
            code, _, errors = run_main([str(directory), "--crop", "30x30+10+0"])
            self.assertEqual(code, 1)
            self.assertIn("motion_stats: crop reaches past", errors)
            code, _, errors = run_main([str(directory), "--steady", "20x20+0+10"])
            self.assertEqual(code, 1)
            self.assertIn("motion_stats: steady box reaches past", errors)
            self.assertFalse((directory / "d_delta_strip.png").exists())
            Image.new("L", (40, 24)).save(directory / "d_31.png")
            code, _, _ = run_main([str(directory)])
            self.assertEqual(code, 1)
            self.assertFalse((directory / "d_delta_strip.png").exists())

    @unittest.skipIf(os.geteuid() == 0, "root writes into a read only directory")
    def test_an_unwritable_directory_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            write_drifting_frames(directory, 8)
            directory.chmod(0o555)
            try:
                code, _, errors = run_main([str(directory)])
            finally:
                directory.chmod(0o755)
            self.assertEqual(code, 1)
            self.assertTrue(errors.startswith("motion_stats: "), errors)

    def test_an_empty_directory_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            code, _, errors = run_main([temporary])
            self.assertEqual(code, 1)
            self.assertIn("holds no frames", errors)


if __name__ == "__main__":
    unittest.main()
