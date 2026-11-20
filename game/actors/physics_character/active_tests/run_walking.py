"""Run the eight walking trials in separate 60 Hz GodotPhysics3D processes."""

import argparse
import csv
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


CASES = ("forward", "backward", "left", "right", "turn_left", "turn_right", "slow", "uneven")
ENTRY = "res://game/actors/physics_character/active_tests/verify_walking.gd"


def trial(args, case):
    cmd = [str(args.godot), "--headless", "--fixed-fps", "60", "--path", str(args.project),
           "--log-file", str(args.out / f"walk_{case}.log"), "--script", ENTRY, "--",
           f"--case={case}", f"--out={args.out}"]
    if args.trace:
        cmd.append("--trace")
    process = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                             errors="replace", timeout=120, check=False)
    text = process.stdout + process.stderr
    markers = [line[5:] for line in text.splitlines() if line.startswith("WALK {")]
    if process.returncode not in (0, 1) or "ERROR:" in text or len(markers) != 1:
        raise RuntimeError(f"{case}, Godot exit {process.returncode}: {text[-1700:]}")
    row = json.loads(markers[0])
    if (row["samples"], row["case"], row["solver_iterations"], row["hz"]) != (900, case, 128, 60):
        raise RuntimeError(f"{case} result has an incomplete or inconsistent run.")
    if row["test_pass"] != (process.returncode == 0):
        raise RuntimeError(f"{case} result disagrees with Godot exit code.")
    with (args.out / f"walk_{case}_events.csv").open(encoding="utf-8", newline="") as stream:
        events = [dict(case=case, **event) for event in csv.DictReader(stream)]
    return row, events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--jobs", type=int, choices=range(1, 9), default=1)
    parser.add_argument("--trace", action="store_true")
    args = parser.parse_args()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda case: trial(args, case), CASES))
    rows = [row for row, _ in results]
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with (args.out / "walking_body.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fields)
        writer.writeheader()
        writer.writerows(rows)
    with (args.out / "walking_events.csv").open("w", encoding="utf-8", newline="") as stream:
        fields = ["case", "tick", "kind", "foot", "load_n", "air_frames", "clearance_m", "step_m", "floor_y", "upright"]
        writer = csv.DictWriter(stream, fields)
        writer.writeheader()
        for _, events in results:
            writer.writerows(events)
    passed = sum(row["test_pass"] for row in rows)
    print(f"Walking trials {passed}/{len(rows)}.")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"Walking suite execution error: {error}", file=sys.stderr)
        raise SystemExit(2)
