#!/usr/bin/env python3
"""The frame table of work item 0342 (doc/build.md, Frame profile).

Starts the release build under a nested headless gamescope at 1920 by
1080, with a runtime, configuration, state and data directory of its
own, so it meets no play session, setting or save of the user's. Frames
each view of tools/frame_profile_views.sjson through the command socket
(doc/commands.md), samples it with profile sample, and writes
<output>/table.md from the answers of query profile.

  ./build.sh frame-profile [view ...]
        the night's table: a heavy benchmark, run only by build.sh, which
        holds ~/benchmark.lock from 03:00 to 06:00 Europe/Stockholm
  python3 tools/frame_profile.py --check [view ...]
        every view once at 512 m, capped at 30 frames a second with 30
        frames sampled: the framing and the setup, not a measurement;
        refused while a benchmark holds the lock

Exit status: 0 when the table is written, 1 when the start was refused
or the game ended mid run (the partial table is written), 2 for bad
arguments or the lock.
"""

import argparse
import ctypes
import datetime
import math
import os
import pathlib
import re
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import threading
import time

import sjson

GAME_DIRECTORY_NAME = "mine-oh-belowed"
SOCKET_FILE_NAME = "command.sock"
TERMINATOR = "."
LOCK_PATH = pathlib.Path.home() / "benchmark.lock"
DISPLAY_SIZE = (1920, 1080)
SOCKET_WAIT_SECONDS = 120
LINE_TIMEOUT_SECONDS = 900
# profile settle's frame limit, sent with the line (the game's default).
SETTLE_FRAMES = 3600
# A settle or sample waits for its frames at the frame time measured over
# this many socket round trips (the game reads the socket once a frame),
# times the margin, and never less than LINE_TIMEOUT_SECONDS.
FRAME_TIME_ROUND_TRIPS = 5
SLOW_WAIT_MARGIN = 2.0
SCREENSHOT_WAIT_SECONDS = 10
STOP_WAIT_SECONDS = 10
SAMPLER_PERIOD_SECONDS = 0.1
DRM_ROOT = pathlib.Path("/sys/class/drm")
PROC_ROOT = pathlib.Path("/proc")
# linux/prctl.h
PR_SET_PDEATHSIG = 1
AMD_VENDOR = "0x1002"
SOFTWARE_RENDERERS = ("llvmpipe", "softpipe")
CHECK_FRAMES = 30
CHECK_FRAME_RATE_CAP = 30
JUDGED_DISTANCE = 512
# The factory's stand: the vertical field of view of the run's fresh
# settings (field_of_view, src/settings.odin) on a 16:9 screen (two
# viewports stack, each wider still), and the shares of the half width and
# of the half height above and below the centre the pad and the machines
# may fill. The hotbar covers the bottom below about 0.62 of the half
# height (the screenshots of 2026-11-11).
FIELD_OF_VIEW_DEGREES = 70
SCREEN_ASPECT = 16 / 9
FACTORY_SIDE_SHARE = 0.9
FACTORY_TOP_SHARE = 0.85
FACTORY_BOTTOM_SHARE = 0.55
STAND_STEP_METRES = 0.25
STAND_MOST_METRES = 200
FRAME_BUDGET_MILLISECONDS = 1000 / 60
HEADROOM_FLAG_MILLISECONDS = 14.0
TICK_MEAN_FLAG_MILLISECONDS = 2.0
TICK_WORST_FLAG_MILLISECONDS = 3.0
HITCH_WORST_MILLISECONDS = 33.3
# vsync off and no cap: the GPU's clock is its own choice, logged by the
# sampler, never forced.
GAME_FLAGS = [
    "--dev",
    "--input=none",
    "--name=frame_profile",
    "--set=settings.vsync=false",
    "--set=settings.master_volume=0",
    "--set=settings.autosave_minutes=0",
]
BUDGET_TEXT = (
    "a 512 m run passes when its frame at 60 Hz, the larger of the GPU mean and the CPU at 60 Hz "
    "(work mean + (1 - ticks/frames) x tick mean), is at most 16.67 ms; 1024 m runs are reported, "
    "not judged. Notes: gpu or cpu over 14 ms, tick (mean over 2 ms or worst over 3 ms), hitch "
    "(a p99 of the work or the GPU over 16.67 ms, or a worst over 33.3 ms)"
)
AT_PATTERN = re.compile(r"\bat (-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+)")
PLAYER_PATTERN = re.compile(r"\bplayer (\d+)")
ENTITY_PATTERN = re.compile(
    r"^entity (\S+) frame (\d+) cell (-?\d+) (-?\d+) (-?\d+) size (\d+) (\d+) (\d+) "
    r"rotation \d+ centre (\S+) (\S+) (\S+)$"
)
FRAME_PATTERN = re.compile(
    r"^frame (\d+) origin (\S+) (\S+) (\S+) pitch (\S+) right (\S+) (\S+) (\S+) "
    r"up (\S+) (\S+) (\S+) forward (\S+) (\S+) (\S+) cells \d+$"
)
SCLK_PATTERN = re.compile(r"(\d+)\s*[Mm][Hh]z")


class Game_Gone(Exception):
    """The game or its socket ended: the whole run stops."""


class Setup_Failed(Exception):
    """A line answered error: the run it frames fails."""

    def __init__(self, line, answer):
        super().__init__(f"{line}: {answer}")


class Run_Stopped(Exception):
    """The whole run stops: a restart that cannot be made."""


class Answer_Timeout(Exception):
    """A line's answer did not come within its wait while the socket stayed
    open: the game still works on it, so its state is unknown and the run
    ends there."""

    def __init__(self, line, wait_seconds):
        super().__init__(f"{line}: no answer within {wait_seconds:.0f} s")
        self.line = line


def repository_root():
    return pathlib.Path(__file__).resolve().parent.parent


# Arguments and the lock.


def parse_arguments(arguments):
    root = repository_root()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    parser = argparse.ArgumentParser(description="The frame table of work item 0342 (doc/build.md, Frame profile).")
    parser.add_argument("--frames", type=int, help="frames sampled per run (default: the views file's, or a view's own)")
    parser.add_argument("--views", type=pathlib.Path, default=root / "tools" / "frame_profile_views.sjson")
    parser.add_argument("--binary", type=pathlib.Path, default=root / "build" / "mine-oh-belowed")
    parser.add_argument("--output", type=pathlib.Path, default=root / "tmp" / "frame_profile" / stamp)
    parser.add_argument("--check", action="store_true", help="every view once at 512 m, capped, 30 frames: not a measurement")
    parser.add_argument("names", nargs="*", metavar="view", help="the views to run (default all, factory included)")
    return parser.parse_args(arguments)


def lock_pid(text):
    """The pid= value of a lock file's lines, or ""."""
    for line in text.splitlines():
        if line.startswith("pid="):
            return line[len("pid="):].strip()
    return ""


def lock_problem(check, lock_text, parent_pid):
    """Why the run may not start, or "". lock_text is None without a lock."""
    if check:
        return "" if lock_text is None else f"--check waits while a benchmark holds {LOCK_PATH}"
    if lock_text is None or lock_pid(lock_text) != str(parent_pid):
        return "the frame table is a benchmark: run it through ./build.sh frame-profile"
    return ""


def read_lock():
    try:
        return LOCK_PATH.read_text()
    except FileNotFoundError:
        return None


# The views.


def view_viewports(view, views_file):
    return view.get("viewports", views_file["viewports"])


def view_frames(view, views_file, arguments):
    if arguments.check:
        return CHECK_FRAMES
    if arguments.frames is not None:
        return arguments.frames
    return view.get("frames", views_file["frames"])


def selected_views(views_file, names):
    """The selected views (all without names) and whether the factory is
    among them, or a problem naming an unknown view."""
    known = [view["name"] for view in views_file["views"]] + ["factory"]
    unknown = [name for name in names if name not in known]
    if unknown:
        return [], False, f"unknown views {', '.join(unknown)}; the views are {', '.join(known)}"
    views = [view for view in views_file["views"] if not names or view["name"] in names]
    return views, not names or "factory" in names, ""


def new_run(name, viewports, distance, frames, water_model=None):
    return {
        "view": name,
        "viewports": viewports,
        "distance": distance,
        "frames": frames,
        # The view's water_model, None for the new world's default.
        "water_model": water_model,
        "failure": "",
        "unsettled": False,
        # Why an unsettled run has no sample (its settle never answered).
        "reason": "",
        "report": None,
        "sampled": None,
    }


def run_name(run):
    return f"{run['view']}_{run['viewports']}vp_{run['distance']}m"


def planned_runs(views_file, views, factory, distances, arguments):
    """The runs in the order they are taken, so one extra player is ever
    added: the views in one viewport, then in two, then the factory in two
    and in one, then the models phase: the views that name a water_model,
    each model's together in a fresh game started under it (0379), one
    viewport then two, in the views file's order."""
    plan = {"views_one": [], "views_two": [], "factory_two": [], "factory_one": [], "models": []}
    for viewports, phase in ((1, "views_one"), (2, "views_two")):
        for view in views:
            if viewports in view_viewports(view, views_file):
                frames = view_frames(view, views_file, arguments)
                model = view.get("water_model")
                runs = [new_run(view["name"], viewports, distance, frames, model) for distance in distances]
                plan[phase if model is None else "models"] += runs
    if factory:
        factory_view = {"name": "factory"}
        frames = view_frames(factory_view, views_file, arguments)
        for viewports, phase in ((2, "factory_two"), (1, "factory_one")):
            if viewports in views_file["viewports"]:
                plan[phase] = [new_run("factory", viewports, distance, frames) for distance in distances]
    # A stable sort: the views file's order within a model and a count.
    plan["models"].sort(key=lambda run: (run["water_model"], run["viewports"]))
    return plan


# The sandbox and the game.


def run_directories(output, runtime_root, pid):
    run = output / "run"
    return {
        "config": run / "config",
        "config_dirs": run / "config_dirs",
        "state": run / "state",
        "data": run / "data",
        "runtime": pathlib.Path(runtime_root) / f"{GAME_DIRECTORY_NAME}-profile-{pid}",
    }


def game_command(binary, directories, check, water_model):
    """The game inside gamescope: X11 through gamescope's Xwayland (never
    the parent compositor), every XDG directory the run's own; a new world
    under the water model, or the default for None."""
    cap = CHECK_FRAME_RATE_CAP if check else 0
    model_flags = [] if water_model is None else [f"--water-model={water_model}"]
    return [
        "env",
        "-u", "WAYLAND_DISPLAY",
        "-u", "MINE_OH_BELOWED_SAVES",
        "XDG_SESSION_TYPE=x11",
        f"XDG_RUNTIME_DIR={directories['runtime']}",
        f"XDG_CONFIG_HOME={directories['config']}",
        f"XDG_CONFIG_DIRS={directories['config_dirs']}",
        f"XDG_STATE_HOME={directories['state']}",
        f"XDG_DATA_HOME={directories['data']}",
        str(binary),
        *GAME_FLAGS,
        *model_flags,
        f"--set=settings.frame_rate_cap={cap}",
    ]


def gamescope_command(game):
    width, height = DISPLAY_SIZE
    return ["gamescope", "--backend", "headless", "-W", str(width), "-H", str(height), "--", *game]


def gamescope_environment(directories):
    """The real runtime directory (gamescope's socket and lock), no DISPLAY,
    and the run's configuration directory (none of the user's scripts)."""
    environment = dict(os.environ)
    environment.pop("DISPLAY", None)
    environment["XDG_CONFIG_HOME"] = str(directories["config"])
    return environment


def exit_on_signal(number, frame):
    """SIGTERM and SIGHUP end the script through SystemExit, so main's
    cleanup runs."""
    raise SystemExit(f"frame profile: stopped by {signal.Signals(number).name}")


def die_with_this_process():
    """A preexec_fn: the child gets SIGKILL when this process dies
    (prctl PR_SET_PDEATHSIG), and ends at once if it already has."""
    prctl = ctypes.CDLL(None, use_errno=True).prctl
    parent = os.getpid()

    def set_parent_death_signal():
        if prctl(PR_SET_PDEATHSIG, int(signal.SIGKILL)) != 0:
            raise OSError(ctypes.get_errno(), "prctl(PR_SET_PDEATHSIG)")
        if os.getppid() != parent:
            os._exit(1)

    return set_parent_death_signal


def start_gamescope(command, environment, log_path, root):
    """In append mode, so a restarted game's output follows the first's."""
    with open(log_path, "ab") as log:
        return subprocess.Popen(
            command,
            env=environment,
            stdout=log,
            stderr=subprocess.STDOUT,
            cwd=root,
            start_new_session=True,
            preexec_fn=die_with_this_process(),
        )


def stop_gamescope(process):
    """SIGTERM to the process group, SIGKILL after STOP_WAIT_SECONDS; False,
    with a line to stderr, when gamescope outlives the SIGKILL's wait."""
    for stop_signal in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, stop_signal)
        except ProcessLookupError:
            return True
        try:
            process.wait(STOP_WAIT_SECONDS)
            return True
        except subprocess.TimeoutExpired:
            continue
    print(f"frame profile: gamescope (pid {process.pid}) did not end within {STOP_WAIT_SECONDS} s of SIGKILL", file=sys.stderr)
    return False


def processes_with_environment_entry(entry, proc_root=PROC_ROOT):
    """The pids whose environment holds the entry exactly. A zombie's
    environment reads empty, so a killed process awaiting its reaping is
    not listed."""
    marker = entry.encode()
    pids = []
    for process in proc_root.iterdir():
        if not process.name.isdigit():
            continue
        try:
            environment = (process / "environ").read_bytes()
        except OSError:
            continue
        if marker in environment.split(b"\0"):
            pids.append(int(process.name))
    return pids


def kill_game(runtime, proc_root=PROC_ROOT):
    """SIGKILL to the game, found exactly by the run's private runtime
    directory in its environment (no other process is given it), until
    none is left or STOP_WAIT_SECONDS pass; the pids still alive."""
    entry = f"XDG_RUNTIME_DIR={runtime}"
    deadline = time.monotonic() + STOP_WAIT_SECONDS
    while True:
        pids = processes_with_environment_entry(entry, proc_root)
        if not pids or time.monotonic() > deadline:
            return pids
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.2)


def socket_path(directories):
    return directories["runtime"] / GAME_DIRECTORY_NAME / SOCKET_FILE_NAME


def wait_for_socket(path, process):
    deadline = time.monotonic() + SOCKET_WAIT_SECONDS
    while not path.exists():
        if process.poll() is not None:
            raise Game_Gone(f"gamescope ended with {process.returncode} before the socket appeared")
        if time.monotonic() > deadline:
            raise Game_Gone(f"no command socket at {path} after {SOCKET_WAIT_SECONDS} s")
        time.sleep(0.5)


class Game_Connection:
    """The command socket: a line in, the answer's lines up to a line
    holding only the terminator, within the line's wait."""

    def __init__(self, path):
        self.client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.client.settimeout(LINE_TIMEOUT_SECONDS)
        self.client.connect(str(path))
        self.stream = self.client.makefile("r", encoding="utf-8", newline="\n")

    def send(self, line, wait_seconds=LINE_TIMEOUT_SECONDS):
        self.client.settimeout(wait_seconds)
        try:
            self.client.sendall((line + "\n").encode("utf-8"))
            lines = []
            for answer_line in self.stream:
                answer_line = answer_line.rstrip("\n")
                if answer_line == TERMINATOR:
                    return "\n".join(lines)
                lines.append(answer_line)
        except TimeoutError:
            raise Answer_Timeout(line, wait_seconds) from None
        except OSError as error:
            raise Game_Gone(f"{line}: {error}") from None
        raise Game_Gone(f"{line}: the game closed the connection")

    def close(self):
        self.client.close()


def expect_ok(connection, line, wait_seconds=LINE_TIMEOUT_SECONDS):
    answer = connection.send(line, wait_seconds)
    if not answer.startswith("ok"):
        raise Setup_Failed(line, answer.split("\n", 1)[0])
    return answer


def wait_for_world(connection):
    deadline = time.monotonic() + LINE_TIMEOUT_SECONDS
    while not connection.send("query world").startswith("ok"):
        if time.monotonic() > deadline:
            raise Game_Gone(f"no world after {LINE_TIMEOUT_SECONDS} s")
        time.sleep(1)


def log_line(log_text, prefix, last):
    lines = [line for line in log_text.splitlines() if line.startswith(prefix)]
    if not lines:
        return ""
    return lines[-1] if last else lines[0]


def start_problem(log_text):
    """Why the start is refused, or "": a software renderer, or a session
    other than gamescope's X11."""
    gl = log_line(log_text, "gl:", last=False)
    if not gl:
        return "the log has no gl: line"
    if any(renderer in gl for renderer in SOFTWARE_RENDERERS):
        return f"a software renderer: {gl}"
    display = log_line(log_text, "display:", last=True)
    if "session x11" not in display:
        return f"not gamescope's X11: {display or 'no display: line'}"
    return ""


def game_version(binary):
    result = subprocess.run([str(binary), "--version"], capture_output=True, text=True, timeout=60)
    return result.stdout.strip() or result.stderr.strip()


def preparation_lines(root):
    game = sjson.load(root / "data" / "game.sjson")
    ticks = game["arrival_ticks"] + game["arrival_settle_ticks"]
    return ["pause", f"tick {ticks}", "resume", "seat stand", "camera first", "weather clear"]


def start_game(game, arguments, directories, output, root):
    """gamescope and the game in the run's sandbox (a new world each
    start), up to a loaded and prepared world; the refusal, or "". The
    process and the connection go into the game as they come, so
    stop_game cleans up a start that fails half way."""
    directories["runtime"].mkdir(mode=0o700)
    command = gamescope_command(game_command(arguments.binary.resolve(), directories, arguments.check, game["water_model"]))
    game["process"] = start_gamescope(command, gamescope_environment(directories), output / "gamescope.log", root)
    wait_for_socket(socket_path(directories), game["process"])
    game["connection"] = Game_Connection(socket_path(directories))
    wait_for_world(game["connection"])
    refusal = start_problem(read_log(directories))
    if refusal:
        return refusal
    for line in preparation_lines(root):
        expect_ok(game["connection"], line)
    return ""


def stop_game(game, directories):
    """The connection closed, gamescope stopped, the game itself killed,
    and the private runtime directory removed once no process holds it;
    False, with a line to stderr, when a process outlived its SIGKILL."""
    if game["connection"] is not None:
        game["connection"].close()
    ended = game["process"] is None or stop_gamescope(game["process"])
    left = kill_game(directories["runtime"])
    if left:
        pids = ", ".join(str(pid) for pid in left)
        print(f"frame profile: the game (pid {pids}) outlived SIGKILL, so {directories['runtime']} is left in place", file=sys.stderr)
        return False
    shutil.rmtree(directories["runtime"], ignore_errors=True)
    return ended


# Framing.


def decimal_word(value):
    return f"{value:.3f}"


def point_words(point):
    return " ".join(decimal_word(value) for value in point)


def parse_at(answer):
    match = AT_PATTERN.search(answer)
    if match is None:
        raise Setup_Failed("teleport", f"no position in {answer!r}")
    return tuple(float(value) for value in match.groups())


def look_point(surface, height):
    """The point height metres over the surface point, along the planet's
    radius through it."""
    length = sum(value * value for value in surface) ** 0.5
    return tuple(value + height * value / length for value in surface)


def view_framing(connection, view):
    """The view's lines to the stand and its look line; a target is found by
    teleporting there, the answer giving its surface point."""
    stand = ["teleport " + point_words(view["stand"])]
    if "target" in view:
        surface = parse_at(expect_ok(connection, "teleport " + point_words(view["target"])))
        return stand, "look at " + point_words(look_point(surface, view.get("target_height", 0)))
    return stand, "look " + point_words(view["look"])


def player_prefix(player):
    return "" if player is None else f"as {player} "


def frame_players(connection, framing, players):
    """Every player to the stand and its look; the look lines, to send
    again once the players dropped onto the ground."""
    stand, look = framing
    looks = []
    for player in players:
        for line in stand:
            expect_ok(connection, player_prefix(player) + line)
        expect_ok(connection, player_prefix(player) + look)
        looks.append(player_prefix(player) + look)
    return looks


def measure_frame_seconds(connection):
    """The frame time now: the game reads the socket once a frame and
    answers a query in that frame, so a round trip takes about a frame."""
    start = time.monotonic()
    for _ in range(FRAME_TIME_ROUND_TRIPS):
        connection.send("query world")
    return (time.monotonic() - start) / FRAME_TIME_ROUND_TRIPS


def frame_wait_seconds(frames, frame_seconds):
    """How long a line that takes the frames may go unanswered: the frames
    at the measured frame time with the margin, at least
    LINE_TIMEOUT_SECONDS."""
    return max(LINE_TIMEOUT_SECONDS, frames * frame_seconds * SLOW_WAIT_MARGIN)


def settle(connection):
    """True once settled; a settle that ran out of frames is no setup
    failure, it makes the run unsettled."""
    line = f"profile settle {SETTLE_FRAMES}"
    answer = connection.send(line, frame_wait_seconds(SETTLE_FRAMES, measure_frame_seconds(connection)))
    if answer.startswith("ok"):
        return True
    if answer.startswith("error not settled"):
        return False
    raise Setup_Failed(line, answer.split("\n", 1)[0])


def take_screenshot(connection, name):
    path = pathlib.Path(expect_ok(connection, f"screenshot {name}")[len("ok "):].strip())
    deadline = time.monotonic() + SCREENSHOT_WAIT_SECONDS
    while not path.exists():
        if time.monotonic() > deadline:
            print(f"frame profile: no screenshot at {path} after {SCREENSHOT_WAIT_SECONDS} s", file=sys.stderr, flush=True)
            return
        time.sleep(0.2)


# The factory.


def parse_entities(answer):
    entities = []
    for line in answer.splitlines():
        match = ENTITY_PATTERN.match(line)
        if match:
            values = match.groups()
            entities.append({
                "machine": values[0],
                "frame": int(values[1]),
                "cell": tuple(int(value) for value in values[2:5]),
                "size": tuple(int(value) for value in values[5:8]),
                "centre": tuple(float(value) for value in values[8:11]),
            })
    return entities


FRAME_AXES = ("right", "up", "forward")


def parse_frames(answer):
    """Each frame by id: its origin (the corner of cell 0) and pitch in
    metres, and its right, up and forward axes."""
    frames = {}
    for line in answer.splitlines():
        match = FRAME_PATTERN.match(line)
        if match:
            values = [float(value) for value in match.groups()[1:]]
            frames[int(match.group(1))] = {
                "origin": tuple(values[0:3]),
                "pitch": values[3] / 1000,
                "right": tuple(values[4:7]),
                "up": tuple(values[7:10]),
                "forward": tuple(values[10:13]),
            }
    return frames


def pad_corner(pod, offset):
    """The pad's corner cell: offset cells from the pod's minimum cell."""
    return tuple(pod["cell"][axis] + offset[axis] for axis in range(3))


def machine_cell(corner, machine):
    return tuple(corner[axis] + machine["cell"][axis] for axis in range(3))


def factory_lines(frame, corner, factory):
    """The pad's foundations, the machines and their inserts, in order."""
    width, depth = factory["pad"]
    lines = [
        f"place wooden_foundation {frame} {corner[0] + x} {corner[1]} {corner[2] + z} 0"
        for x in range(width)
        for z in range(depth)
    ]
    for machine in factory["machines"]:
        cell = " ".join(str(value) for value in machine_cell(corner, machine))
        lines.append(f"place {machine['machine']} {frame} {cell} 0")
        lines += [f"insert {item} {count} {frame} {cell}" for item, count in machine.get("insert", [])]
    return lines


def placed_machines(connection, frame, corner, factory):
    """The placed machines as the game lists them (their cells and sizes)."""
    placed = []
    for machine_id in sorted({machine["machine"] for machine in factory["machines"]}):
        cells = {machine_cell(corner, machine) for machine in factory["machines"] if machine["machine"] == machine_id}
        answer = expect_ok(connection, f"query entities {machine_id} 64")
        placed += [entity for entity in parse_entities(answer) if entity["frame"] == frame and entity["cell"] in cells]
    if len(placed) != len(factory["machines"]):
        raise Setup_Failed("query entities", f"found {len(placed)} of the {len(factory['machines'])} machines placed")
    return placed


# The factory's stand, in metres and in the frame's cells.


def vector_add(first, second):
    return tuple(a + b for a, b in zip(first, second))


def vector_subtract(first, second):
    return tuple(a - b for a, b in zip(first, second))


def vector_scale(vector, factor):
    return tuple(value * factor for value in vector)


def vector_dot(first, second):
    return sum(a * b for a, b in zip(first, second))


def vector_cross(first, second):
    return (
        first[1] * second[2] - first[2] * second[1],
        first[2] * second[0] - first[0] * second[2],
        first[0] * second[1] - first[1] * second[0],
    )


def vector_unit(vector):
    return vector_scale(vector, 1 / math.sqrt(vector_dot(vector, vector)))


def frame_point(frame, cells):
    """A point of the frame given in cells (fractions allowed), in metres."""
    point = frame["origin"]
    for name, count in zip(FRAME_AXES, cells):
        point = vector_add(point, vector_scale(frame[name], count * frame["pitch"]))
    return point


def frame_cells(frame, point):
    """A point in metres in the frame's cells."""
    offset = vector_subtract(point, frame["origin"])
    return tuple(vector_dot(offset, frame[name]) / frame["pitch"] for name in FRAME_AXES)


def factory_boxes(corner, factory, placed):
    """The pad's box first, then each placed machine's, as (minimum cell,
    size in cells)."""
    width, depth = factory["pad"]
    return [(corner, (width, 1, depth))] + [(machine["cell"], machine["size"]) for machine in placed]


def box_corners(box):
    minimum, size = box
    return [tuple(minimum[axis] + size[axis] * ((corner >> axis) & 1) for axis in range(3)) for corner in range(8)]


def box_distance_cells(box, cells):
    """How far a point given in cells lies from the box, in cells."""
    minimum, size = box
    gaps = [max(minimum[axis] - cells[axis], 0, cells[axis] - minimum[axis] - size[axis]) for axis in range(3)]
    return math.sqrt(sum(gap * gap for gap in gaps))


def over_box(box, cells):
    """Whether a point given in cells stands over or under the box (inside
    its extent along right and forward)."""
    minimum, size = box
    return all(minimum[axis] <= cells[axis] <= minimum[axis] + size[axis] for axis in (0, 2))


def top_centre(box):
    """The centre of the box's top face, in cells."""
    minimum, size = box
    return (minimum[0] + size[0] / 2, minimum[1] + size[1], minimum[2] + size[2] / 2)


def stand_look(frame, target, view_from, pitch_degrees):
    """The unit look from the stand to the target: level at the target
    from the view_from side (along the frame's right and forward) towards
    it, turned pitch_degrees down."""
    radial = vector_unit(target)
    away = vector_add(vector_scale(frame["right"], view_from[0]), vector_scale(frame["forward"], view_from[1]))
    level = vector_unit(vector_subtract(away, vector_scale(radial, vector_dot(away, radial))))
    pitch = math.radians(pitch_degrees)
    return vector_subtract(vector_scale(level, -math.cos(pitch)), vector_scale(radial, math.sin(pitch)))


def screen_shares(eye, look, point):
    """Where the point lies on the screen of a camera at the eye looking
    along look with the planet's up as its up (field_camera): across and up
    as shares of the depth, or None behind the eye."""
    up = vector_unit(eye)
    right = vector_unit(vector_cross(look, up))
    screen_up = vector_cross(right, look)
    offset = vector_subtract(point, eye)
    depth = vector_dot(offset, look)
    if depth <= 0:
        return None
    return vector_dot(offset, right) / depth, vector_dot(offset, screen_up) / depth


def inside_factory_frame(shares):
    """Whether screen shares fall inside the part of the screen the factory
    may fill."""
    if shares is None:
        return False
    half = math.tan(math.radians(FIELD_OF_VIEW_DEGREES) / 2)
    across, up = shares
    return abs(across) <= half * SCREEN_ASPECT * FACTORY_SIDE_SHARE and -half * FACTORY_BOTTOM_SHARE <= up <= half * FACTORY_TOP_SHARE


def stand_fits(frame, boxes, eye, look, reach):
    """Whether an eye sees every box corner inside the factory's part of
    the screen, stands outside the pad's extent and lies beyond the reach
    of every box, so the held foundation shows no ghost."""
    cells = frame_cells(frame, eye)
    if over_box(boxes[0], cells):
        return False
    if min(box_distance_cells(box, cells) for box in boxes) * frame["pitch"] <= reach:
        return False
    return all(inside_factory_frame(screen_shares(eye, look, frame_point(frame, corner))) for box in boxes for corner in box_corners(box))


def factory_stand(frame, boxes, factory, reach):
    """The eye and the target: the target the centre of the pad's top, the
    eye the nearest one back along the look that fits (stand_fits)."""
    target = frame_point(frame, top_centre(boxes[0]))
    look = stand_look(frame, target, factory["view_from"], factory["pitch_degrees"])
    for step in range(1, int(STAND_MOST_METRES / STAND_STEP_METRES) + 1):
        eye = vector_subtract(target, vector_scale(look, step * STAND_STEP_METRES))
        if stand_fits(frame, boxes, eye, look, reach):
            return eye, target
    raise Setup_Failed("factory", f"no stand within {STAND_MOST_METRES} m sees the whole factory")


def factory_framing(eye, target, eye_height):
    """Flying, so the player stays at the eye; the feet eye_height under
    it along the radial (field_player_eye); the look at the target."""
    feet = vector_subtract(eye, vector_scale(vector_unit(eye), eye_height))
    return ["fly on", "teleport " + point_words(feet)], "look at " + point_words(target)


def player_eye_and_reach_metres(root):
    """The field player's eye height and tool reach (data/game.sjson)."""
    game = sjson.load(root / "data" / "game.sjson")
    return game["field_player"]["eye_height_millimetres"] / 1000, game["field_player"]["tool_reach_millimetres"] / 1000


def build_factory(connection, factory):
    """The pad, the machines and their items on the pod's frame; the
    factory's framing."""
    expect_ok(connection, "teleport pod")
    pods = parse_entities(expect_ok(connection, "query entities pod 64"))
    if not pods:
        raise Setup_Failed("query entities pod 64", "no pod listed")
    pod = pods[0]
    frame = parse_frames(expect_ok(connection, "query frames 64")).get(pod["frame"])
    if frame is None:
        raise Setup_Failed("query frames 64", f"frame {pod['frame']} not listed")
    corner = pad_corner(pod, factory["corner"])
    expect_ok(connection, "pause")
    try:
        for line in factory_lines(pod["frame"], corner, factory):
            expect_ok(connection, line)
    finally:
        connection.send("resume")
    boxes = factory_boxes(corner, factory, placed_machines(connection, pod["frame"], corner, factory))
    eye_height, reach = player_eye_and_reach_metres(repository_root())
    eye, target = factory_stand(frame, boxes, factory, reach)
    return factory_framing(eye, target, eye_height)


# The GPU's clock.


def find_amd_device(root=DRM_ROOT):
    """The device directory of the first DRM card whose vendor is AMD, or
    None."""
    for card in sorted(root.glob("card*")):
        if not re.fullmatch(r"card\d+", card.name):
            continue
        try:
            if (card / "device" / "vendor").read_text().strip() == AMD_VENDOR:
                return card / "device"
        except OSError:
            continue
    return None


def parse_sclk(text):
    """The MHz of pp_dpm_sclk's line marked *, or None."""
    for line in text.splitlines():
        if line.rstrip().endswith("*"):
            match = SCLK_PATTERN.search(line)
            if match:
                return int(match.group(1))
    return None


def sampled_summary(clocks, busy):
    return {
        "clock_mean": statistics.fmean(clocks) if clocks else None,
        "clock_maximum": max(clocks) if clocks else None,
        "busy_mean": statistics.fmean(busy) if busy else None,
    }


class Gpu_Sampler:
    """Reads the card's shader clock and busy percent every 0.1 s on a
    thread of its own while a sample runs."""

    def __init__(self, device):
        self.device = device
        self.clocks = []
        self.busy = []
        self.stopping = threading.Event()
        self.thread = threading.Thread(target=self.sample, daemon=True)

    def start(self):
        if self.device is not None:
            self.thread.start()

    def sample(self):
        while True:
            try:
                clock = parse_sclk((self.device / "pp_dpm_sclk").read_text())
                if clock is not None:
                    self.clocks.append(clock)
                self.busy.append(int((self.device / "gpu_busy_percent").read_text().strip()))
            except (OSError, ValueError):
                pass
            if self.stopping.wait(SAMPLER_PERIOD_SECONDS):
                return

    def stop(self):
        self.stopping.set()
        if self.thread.is_alive():
            self.thread.join()
        return sampled_summary(self.clocks, self.busy)


# One run.


def print_run(run):
    print(f"frame profile: {run_name(run)}: {run_verdict(run)}", flush=True)


def end_run_on_lost_game(run, problem):
    """A line not answered within its wait (the game still working on it)
    or a game that ended: the run's result. A settle that never answered
    leaves the run unsettled, anything else fails it."""
    if isinstance(problem, Answer_Timeout) and problem.line.startswith("profile settle"):
        run["unsettled"], run["reason"] = True, str(problem)
    elif isinstance(problem, Answer_Timeout):
        run["failure"] = str(problem)
    else:
        run["failure"] = f"the game ended: {problem}"


def profile_run(connection, run, framing, players, walk, device, output):
    """One view in one viewport count at one distance: framed, settled,
    captured, settled again and sampled. A refused line fails the run; a
    line not answered in time or a game that ended ends it too, and then
    the game needs a restart (True)."""
    try:
        for line in (f"view_distance {run['distance']}", "time noon", "weather clear"):
            expect_ok(connection, line)
        looks = frame_players(connection, framing(), players)
        run["unsettled"] = not settle(connection)
        for line in looks:
            expect_ok(connection, line)
        take_screenshot(connection, run_name(run))
        run["unsettled"] = not settle(connection) or run["unsettled"]
        sample_run(connection, run, walk, device, output)
    except Setup_Failed as failure:
        run["failure"] = str(failure)
    except (Answer_Timeout, Game_Gone) as problem:
        end_run_on_lost_game(run, problem)
        return True
    finally:
        print_run(run)
    return False


def sample_run(connection, run, walk, device, output):
    """The sample, waited for at the measured frame time. The stick is let
    go once the sample answered; a sample that never answers leaves it to
    the restart."""
    if walk:
        expect_ok(connection, "stick left " + point_words(walk))
    line = f"profile sample {run['frames']}"
    wait_seconds = frame_wait_seconds(run["frames"], measure_frame_seconds(connection))
    sampler = Gpu_Sampler(device)
    sampler.start()
    try:
        answer = connection.send(line, wait_seconds)
    finally:
        run["sampled"] = sampler.stop()
    if walk:
        expect_ok(connection, "stick left 0 0")
    if not answer.startswith("ok"):
        raise Setup_Failed(line, answer.split("\n", 1)[0])
    answer = expect_ok(connection, "query profile")
    (output / f"{run_name(run)}.txt").write_text(answer + "\n")
    run["report"] = parse_profile_report(answer)
    render = run["report"]["render"]
    if render != DISPLAY_SIZE:
        run["failure"] = f"render {render[0]} {render[1]}, not {DISPLAY_SIZE[0]} {DISPLAY_SIZE[1]}"


def new_game(water_model=None):
    """A game's process, connection and what the runs set up in it: the
    second viewport's player, the factory's framing, and a viewport add or
    factory build that failed, remembered for the game's later runs. The
    water model it is started under, None for the default."""
    return {
        "water_model": water_model,
        "process": None,
        "connection": None,
        "second": None,
        "factory_framing": None,
        "viewport_failure": "",
        "factory_failure": "",
    }


def ready_for_run(game, run, views_file):
    """The game's viewports and factory brought to what the run needs; the
    failure that keeps the run from running, or ""."""
    connection = game["connection"]
    if run["viewports"] == 2 and game["second"] is None and not game["viewport_failure"]:
        try:
            game["second"] = int(PLAYER_PATTERN.search(expect_ok(connection, "viewport add")).group(1))
        except Setup_Failed as failure:
            game["viewport_failure"] = str(failure)
    if run["viewports"] == 2 and game["second"] is None:
        return game["viewport_failure"]
    if run["viewports"] == 1 and game["second"] is not None:
        try:
            expect_ok(connection, "viewport remove")
        except Setup_Failed as failure:
            return str(failure)
        game["second"] = None
    if run["view"] == "factory" and game["factory_framing"] is None and not game["factory_failure"]:
        try:
            game["factory_framing"] = build_factory(connection, views_file["factory"])
        except Setup_Failed as failure:
            game["factory_failure"] = f"factory: {failure}"
    if run["view"] == "factory" and game["factory_framing"] is None:
        return game["factory_failure"]
    return ""


def run_framing(game, run, by_name):
    """The run's framing (a callable giving its lines to the stand and its
    look line), its players and its walk."""
    players = [None] if run["viewports"] == 1 else [None, game["second"]]
    if run["view"] == "factory":
        return (lambda: game["factory_framing"]), players, None
    view = by_name[run["view"]]
    return (lambda: view_framing(game["connection"], view)), players, view.get("walk")


def run_needs_start(game, run, lost):
    """Whether the run needs a fresh game (the last one lost, or a run of
    another water model) and whether that start counts as a restart (a
    lost game only)."""
    return lost or run["water_model"] != game["water_model"], lost


def profile_views(session, restart, views_file, views, runs, device, output):
    """The runs in order, each result in its entry. The game is brought to
    what each run needs (viewports, the factory) first. After a run that
    left the game in an unknown state, or before a run of another water
    model, restart(water_model, counted) stops it and starts a fresh one
    under the run's model for the runs after it, so one slow view never
    costs the others."""
    by_name = {view["name"]: view for view in views}
    needs_restart = False
    for run in runs:
        start, counted = run_needs_start(session["game"], run, needs_restart)
        if start:
            restart(run["water_model"], counted)
        game = session["game"]
        try:
            failure = ready_for_run(game, run, views_file)
        except (Answer_Timeout, Game_Gone) as problem:
            end_run_on_lost_game(run, problem)
            print_run(run)
            needs_restart = True
            continue
        if failure:
            run["failure"] = failure
            print_run(run)
            needs_restart = False
            continue
        needs_restart = profile_run(game["connection"], run, *run_framing(game, run, by_name), device, output)


# The report and the table.


def parse_statistics(words):
    return [float(word) for word in words]


def parse_profile_report(text):
    """query profile's lines (doc/commands.md, Frame profile) as a dict:
    the frame statistics as [mean, p50, p99, worst], the sections and
    counters by name in their order."""
    report = {"cpu": {}, "gpu": {}, "tick": {}, "draws": {}, "count": {}, "frame": {}}
    for line in text.splitlines():
        words = line.split()
        if not words:
            continue
        kind = words[0]
        if kind == "frames":
            report["frames"], report["gpu_frames"], report["dropped"] = int(words[1]), int(words[3]), int(words[5])
            report["seconds"], report["fps"] = float(words[7]), float(words[9])
        elif kind == "display":
            report["render"] = (int(words[2]), int(words[3]))
            report["window"] = (int(words[5]), int(words[6]))
            report["viewports"] = int(words[8])
        elif kind == "frame":
            report["frame"][words[1]] = None if words[2] == "none" else parse_statistics(words[2:6])
        elif kind == "ticks":
            report["ticks"], report["tick_mean"], report["tick_worst"] = int(words[1]), float(words[3]), float(words[5])
            report["hashes"], report["saves"] = int(words[7]), int(words[9])
        elif kind in ("cpu", "gpu") and words[1] != "none":
            report[kind][words[1]] = parse_statistics(words[2:6])
        elif kind == "tick":
            report["tick"][words[1]] = float(words[2])
        elif kind in ("draws", "count"):
            report[kind][words[1]] = (float(words[2]), int(words[3]))
    return report


def run_estimate(report):
    """The CPU at 60 Hz, the frame at 60 Hz and its headroom. A free run
    has fewer ticks per frame than 60 Hz, so the ticks missing from its
    frames are added at their mean."""
    work = report["frame"]["work"]
    gpu = report["frame"].get("gpu")
    ticks_per_frame = report["ticks"] / report["frames"] if report["frames"] else 0
    cpu_60 = work[0] + (1 - ticks_per_frame) * report["tick_mean"]
    frame_60 = max(cpu_60, gpu[0] if gpu else 0)
    return {"cpu_60": cpu_60, "frame_60": frame_60, "headroom": FRAME_BUDGET_MILLISECONDS - frame_60}


def run_verdict(run):
    if run["failure"]:
        return f"failed: {run['failure']}"
    if run["unsettled"] and run["reason"]:
        return f"unsettled: {run['reason']}"
    if run["report"] is None:
        return "not run"
    if run["unsettled"]:
        return "unsettled"
    if run["distance"] != JUDGED_DISTANCE:
        return "report"
    return "pass" if run_estimate(run["report"])["frame_60"] <= FRAME_BUDGET_MILLISECONDS else "fail"


def run_notes(report):
    estimate = run_estimate(report)
    work = report["frame"]["work"]
    gpu = report["frame"].get("gpu")
    notes = []
    if gpu and gpu[0] > HEADROOM_FLAG_MILLISECONDS:
        notes.append("gpu")
    if estimate["cpu_60"] > HEADROOM_FLAG_MILLISECONDS:
        notes.append("cpu")
    if report["tick_mean"] > TICK_MEAN_FLAG_MILLISECONDS or report["tick_worst"] > TICK_WORST_FLAG_MILLISECONDS:
        notes.append("tick")
    statistics_list = [work] + ([gpu] if gpu else [])
    if any(values[2] > FRAME_BUDGET_MILLISECONDS or values[3] > HITCH_WORST_MILLISECONDS for values in statistics_list):
        notes.append("hitch")
    return " ".join(notes)


def number(value, decimals=2):
    return "-" if value is None else f"{value:.{decimals}f}"


def cell(text):
    return str(text).replace("|", "\\|")


def table_row(values):
    return "| " + " | ".join(cell(value) for value in values) + " |"


def main_row(run):
    key = [run["view"], run["viewports"], run["distance"]]
    report = run["report"]
    if report is None or run["failure"]:
        return table_row(key + ["-"] * 11 + [run_verdict(run), ""])
    estimate = run_estimate(report)
    gpu = report["frame"].get("gpu")
    sampled = run["sampled"] or sampled_summary([], [])
    clock = "-" if sampled["clock_mean"] is None else f"{sampled['clock_mean']:.0f}/{sampled['clock_maximum']}"
    return table_row(key + [
        number(report["fps"], 1),
        number(gpu[0] if gpu else None),
        number(gpu[2] if gpu else None),
        number(estimate["cpu_60"]),
        number(report["frame"]["work"][2]),
        number(report["tick_mean"]),
        number(report["tick_worst"]),
        number(estimate["frame_60"]),
        number(estimate["headroom"]),
        clock,
        number(sampled["busy_mean"], 0),
        run_verdict(run),
        run_notes(report),
    ])


def section_table(title, runs, kind, value):
    """A row per sampled run that did not fail, of each name's mean in the
    report's kind."""
    reported = [run for run in runs if run["report"] is not None and not run["failure"] and run["report"][kind]]
    if not reported:
        return []
    names = list(reported[0]["report"][kind])
    lines = ["", f"## {title}", "", table_row(["view", "viewports", "m"] + names), table_row(["---"] * (3 + len(names)))]
    for run in reported:
        entries = run["report"][kind]
        lines.append(table_row([run["view"], run["viewports"], run["distance"]] + [value(entries.get(name)) for name in names]))
    return lines


def table_text(head, runs):
    columns = [
        "view", "viewports", "m", "fps", "GPU mean", "GPU p99", "CPU 60 Hz", "work p99", "tick mean", "tick worst",
        "frame 60 Hz", "headroom", "sclk MHz (mean/max)", "busy %", "verdict", "notes",
    ]
    lines = head + ["", table_row(columns), table_row(["---"] * len(columns))]
    lines += [main_row(run) for run in runs]
    lines += section_table("CPU sections (mean ms)", runs, "cpu", lambda entry: number(entry[0] if entry else None))
    lines += section_table("GPU sections (mean ms)", runs, "gpu", lambda entry: number(entry[0] if entry else None))
    lines += section_table("Counts (mean)", runs, "count", lambda entry: number(entry[0] if entry else None, 1))
    return "\n".join(lines) + "\n"


def table_head(check, version, gl, stopped, restarts):
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    head = [f"# Frame profile {date}", ""]
    if check:
        head += ["check, not a measurement", ""]
    head += [f"- build: {version}", f"- {gl or 'gl: not read'}", f"- budget: {BUDGET_TEXT}"]
    if restarts:
        head.append(f"- restarts: {restarts} (the game was started afresh after a run it did not answer; log.txt holds each start)")
    if stopped:
        head.append(f"- stopped: {stopped}")
    return head


def run_failed(run):
    """A failed run or one never reached; an unsettled run is a result."""
    return bool(run["failure"]) or (run["report"] is None and not run["unsettled"])


def copy_outputs(directories, output):
    """The game's log and the screenshots beside the table."""
    state = directories["state"] / GAME_DIRECTORY_NAME
    if (state / "log.txt").exists():
        shutil.copy2(state / "log.txt", output / "log.txt")
    if (state / "screenshots").is_dir():
        shutil.copytree(state / "screenshots", output / "screenshots", dirs_exist_ok=True)


def read_log(directories):
    try:
        return (directories["state"] / GAME_DIRECTORY_NAME / "log.txt").read_text(errors="replace")
    except OSError:
        return ""


def main(arguments):
    for stop_signal in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(stop_signal, exit_on_signal)
    arguments = parse_arguments(arguments)
    root = repository_root()
    problem = lock_problem(arguments.check, read_lock(), os.getppid())
    if problem:
        print(f"frame profile: {problem}", file=sys.stderr)
        return 2
    views_file = sjson.load(arguments.views)
    views, factory, problem = selected_views(views_file, arguments.names)
    runtime_root = os.environ.get("XDG_RUNTIME_DIR", "")
    if not problem and not os.path.isabs(runtime_root):
        problem = "XDG_RUNTIME_DIR is not set, and gamescope and the game's socket need it"
    if not problem and not arguments.binary.is_file():
        problem = f"no game at {arguments.binary}: build it with ./build.sh release"
    if not problem and shutil.which("gamescope") is None:
        problem = "gamescope is not on the PATH"
    if problem:
        print(f"frame profile: {problem}", file=sys.stderr)
        return 2
    distances = [JUDGED_DISTANCE] if arguments.check else views_file["distances"]
    plan = planned_runs(views_file, views, factory, distances, arguments)
    runs = plan["views_one"] + plan["views_two"] + plan["factory_two"] + plan["factory_one"] + plan["models"]
    output = arguments.output.resolve()
    version = game_version(arguments.binary)
    directories = run_directories(output, runtime_root, os.getpid())
    for name in ("config", "config_dirs", "state", "data"):
        directories[name].mkdir(parents=True, exist_ok=True)
    # Under the first run's model, so a run of only one model starts once.
    session = {"game": new_game(runs[0]["water_model"] if runs else None), "restarts": 0}

    def restart(water_model, counted):
        """This game stopped and cleaned up, a fresh one started under the
        water model and prepared; counted in the head's restarts when the
        last game was lost."""
        if not stop_game(session["game"], directories):
            raise Run_Stopped("a process outlived its SIGKILL, so the game was not restarted")
        session["game"] = new_game(water_model)
        if counted:
            session["restarts"] += 1
            print("frame profile: restarting the game", flush=True)
        else:
            print(f"frame profile: starting the game under the {water_model} water model", flush=True)
        refusal = start_game(session["game"], arguments, directories, output, root)
        if refusal:
            raise Run_Stopped(f"the restarted game was refused: {refusal}")

    stopped, cleanup_failed = "", False
    try:
        refusal = start_game(session["game"], arguments, directories, output, root)
        if refusal:
            print(f"frame profile: refused: {refusal}", file=sys.stderr)
            stopped = f"refused: {refusal}"
        else:
            profile_views(session, restart, views_file, views, runs, find_amd_device(), output)
    except Game_Gone as gone:
        stopped = f"the game ended: {gone}"
    except Answer_Timeout as timeout:
        stopped = f"the game did not answer: {timeout}"
    except Setup_Failed as failure:
        stopped = f"the preparation failed: {failure}"
    except Run_Stopped as stop:
        stopped = str(stop)
    except SystemExit as stop:
        stopped = str(stop.code)
        raise
    finally:
        cleanup_failed = not stop_game(session["game"], directories)
        copy_outputs(directories, output)
        gl = log_line(read_log(directories), "gl:", last=False)
        head = table_head(arguments.check, version, gl, stopped, session["restarts"])
        (output / "table.md").write_text(table_text(head, runs))
    print(f"frame profile: {output / 'table.md'}", flush=True)
    return 1 if stopped or cleanup_failed or any(run_failed(run) for run in runs) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
