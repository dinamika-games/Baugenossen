"""
Analyze a pose log of the game, so that bugs of the body controls can be found
without any recording of pictures.

Start the game with `-- --log-pose` (or `--log-pose=<lines a second>`); the
lines starting with "POSE " go to the standard output and to Godot's log file
(e.g., ~/.local/share/godot/app_userdata/Baugenossen/logs/godot.log on Linux).
Then:

    python3 dev/pose/analyze_pose_log.py <log> [--csv out.csv]

prints a summary for each screen session: the duration and the rate of the
samples, the share of stale frames and of low-confidence key points (by joint),
the time the tracking was frozen or lost, the gesture events and their
outcomes (gestures started vs. confirmed vs. cancelled, which hints at false
triggers), the hook movement while a gesture was pending (must be zero), the
range of each measure against the calibration, and suspicious jumps of the
key points between samples. With --csv, every sample becomes one row.
"""

import argparse
import collections
import csv
import json
import math
import pathlib
import sys
from typing import Any, Dict, Iterator, List

PREFIX = "POSE "
LOW_CONFIDENCE = 0.6
STALE_SECONDS = 0.25
# A key point moving more than this (in picture units) between two samples
# less than 0.2 s apart is suspicious (a swap of left and right, or a jump to
# another person).
JUMP = 0.15


def records(path: pathlib.Path) -> Iterator[Dict[str, Any]]:
    with path.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            index = line.find(PREFIX)
            if index < 0:
                continue
            try:
                yield json.loads(line[index + len(PREFIX) :])
            except json.JSONDecodeError:
                continue


def sessions(path: pathlib.Path) -> List[Dict[str, Any]]:
    """Split the log into sessions, one per start of a screen."""
    result: List[Dict[str, Any]] = []
    for record in records(path):
        if record.get("kind") == "start" or not result:
            result.append({"start": record if record.get("kind") == "start" else {}, "samples": []})
        if record.get("kind") == "sample":
            result[-1]["samples"].append(record)
    return result


def summarize(session: Dict[str, Any]) -> List[str]:
    start = session["start"]
    samples = session["samples"]
    lines = [f"== {start.get('screen', '?')} at {start.get('wall', '?')}"]
    settings = start.get("settings", {})
    if settings:
        lines.append(f"   settings: {json.dumps(settings, sort_keys=True)}")
    if not samples:
        lines.append("   no samples")
        return lines
    t0, t1 = samples[0]["t"], samples[-1]["t"]
    duration = max(t1 - t0, 1e-6)
    lines.append(
        f"   {len(samples)} samples over {duration:.1f} s ({len(samples) / duration:.1f}/s)"
    )

    no_frame = sum(1 for s in samples if s.get("frame", 0) is None)
    stale = sum(1 for s in samples if s.get("age", 0.0) > STALE_SECONDS)
    lines.append(f"   without a pose: {no_frame}, stale (> {STALE_SECONDS} s): {stale}")

    low: Dict[str, int] = collections.Counter()
    with_points = [s for s in samples if s.get("kp")]
    for sample in with_points:
        for name, (_, _, score) in sample["kp"].items():
            if score < LOW_CONFIDENCE:
                low[name] += 1
    if with_points:
        shares = ", ".join(
            f"{name} {100.0 * count / len(with_points):.0f}%" for name, count in low.most_common()
        )
        lines.append(f"   low confidence (< {LOW_CONFIDENCE}): {shares or 'none'}")

    tracking: Dict[str, float] = collections.Counter()
    for before, after in zip(samples, samples[1:]):
        tracking[before.get("tracking", "?")] += after["t"] - before["t"]
    if tracking:
        lines.append(
            "   tracking: " + ", ".join(f"{k} {v:.1f} s" for k, v in sorted(tracking.items()))
        )

    events = collections.Counter(e for s in samples for e in s.get("events", []))
    if events:
        lines.append("   events: " + ", ".join(f"{k} {v}" for k, v in sorted(events.items())))
        started = events.get("gesture_started", 0)
        done = sum(
            events.get(k, 0) for k in ("confirm", "open_catalogue", "catalogue_release", "resume")
        )
        cancelled = events.get("gesture_cancelled", 0)
        lines.append(f"   gestures: {started} started, {done} completed, {cancelled} cancelled")

    moved_pending = [
        s["t"]
        for s in samples
        if s.get("state") == "GESTURE_PENDING" and any(abs(v) > 1e-6 for v in s.get("vel", [0, 0]))
    ]
    if moved_pending:
        lines.append(f"   BUG? the hook moved while a gesture was pending at t={moved_pending[:5]}")

    calibration = settings.get("calibration", {}) if isinstance(settings, dict) else {}
    for key in ("h", "v", "lift_left", "lift_right"):
        values = [s["m"][key] for s in samples if key in s.get("m", {})]
        if values:
            reference = calibration.get(key)
            extra = f" (neutral {reference:.3f})" if isinstance(reference, (int, float)) else ""
            lines.append(f"   {key}: {min(values):.3f} .. {max(values):.3f}{extra}")

    jumps = []
    for before, after in zip(with_points, with_points[1:]):
        if after["t"] - before["t"] > 0.2:
            continue
        for name, (x, y, score) in after["kp"].items():
            if name not in before["kp"] or score < LOW_CONFIDENCE:
                continue
            bx, by, bscore = before["kp"][name]
            if bscore >= LOW_CONFIDENCE and math.hypot(x - bx, y - by) > JUMP:
                jumps.append((after["t"], name))
    if jumps:
        lines.append(f"   key point jumps (> {JUMP}): {len(jumps)}, first {jumps[:5]}")
    return lines


def write_csv(all_sessions: List[Dict[str, Any]], path: pathlib.Path) -> None:
    names = [
        "nose",
        "l_shoulder",
        "r_shoulder",
        "l_elbow",
        "r_elbow",
        "l_wrist",
        "r_wrist",
        "l_hip",
        "r_hip",
    ]
    header = ["session", "screen", "t", "age", "state", "state_after", "tracking", "step"]
    header += ["h", "v", "lift_left", "lift_right", "unit", "sx", "sy", "vx", "vy"]
    header += ["hand_left", "hand_right", "needs_neutral", "events"]
    for name in names:
        header += [f"{name}_x", f"{name}_y", f"{name}_score"]
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(header)
        for index, session in enumerate(all_sessions):
            for s in session["samples"]:
                m = s.get("m", {})
                row = [index, s.get("screen", ""), s["t"], s.get("age", ""), s.get("state", "")]
                row += [s.get("state_after", ""), s.get("tracking", ""), s.get("step", "")]
                row += [m.get(k, "") for k in ("h", "v", "lift_left", "lift_right", "unit")]
                row += list(s.get("s", ["", ""])) + list(s.get("vel", ["", ""]))
                hands = s.get("hands", {})
                row += [hands.get("left", ""), hands.get("right", ""), s.get("needs_neutral", "")]
                row += [" ".join(s.get("events", []))]
                for name in names:
                    row += list(s.get("kp", {}).get(name, ["", "", ""]))
                writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("log", type=pathlib.Path, help="the log of the game")
    parser.add_argument("--csv", type=pathlib.Path, help="write every sample to this CSV file")
    args = parser.parse_args()
    all_sessions = sessions(args.log)
    if not all_sessions:
        print(f"No pose lines in {args.log}; start the game with -- --log-pose.", file=sys.stderr)
        return 1
    for session in all_sessions:
        print("\n".join(summarize(session)))
    if args.csv:
        write_csv(all_sessions, args.csv)
        print(f"Wrote {args.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
