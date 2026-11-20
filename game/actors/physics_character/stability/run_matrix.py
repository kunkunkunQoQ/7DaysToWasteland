"""Batch launcher for run_stability.gd. Python standard library only.

Each child is a fresh Godot process with its own physics space. Parallel
execution is for physical comparisons, not for measuring wall-clock step time.
"""

import argparse
import csv
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from itertools import product
from pathlib import Path

CASES = ("drop_low", "drop_front", "drop_back", "drop_side_l", "drop_side_r", "drop_prone_first", "drop_supine_first",
         "hit_front", "hit_back", "hit_left", "hit_right", "hit_arm", "hit_leg", "hit_repeat")
ENTRY = "res://game/actors/physics_character/stability/run_stability.gd"


def run_trial(args, trial):
    case, profile, hz = trial
    prefix = args.out / f"{case}_{profile}_{hz}"
    if args.duration_s != 5:
        prefix = prefix.with_name(f"{prefix.name}_{args.duration_s}s")
    if args.allow_sleep:
        prefix = prefix.with_name(f"{prefix.name}_sleep")
    cmd = [args.godot, "--headless", "--path", str(args.project)]
    if not args.realtime:
        cmd.extend(["--fixed-fps", str(hz)])
    cmd.extend(["--log-file", f"{prefix}.log", "--script", ENTRY, "--", f"--case={case}",
                f"--profile={profile}", f"--hz={hz}", f"--duration-s={args.duration_s}", f"--out={args.out}"])
    if args.trace:
        cmd.append("--trace")
    if args.allow_sleep:
        cmd.append("--allow-sleep")
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False,
                            encoding="utf-8", errors="replace", timeout=180)
    output = result.stdout
    if "STABILITY " not in output or "SCRIPT ERROR:" in output or "ERROR:" in output:
        return False, False, f"EXECUTION ERROR {trial}: {output[-1500:]}"
    passed = result.returncode == 0
    return True, passed, next(line for line in output.splitlines() if line.startswith("STABILITY "))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot 4.6.3 executable")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--profiles", nargs="+", default=["baseline", "rounded_feet60", "rounded_feet120"])
    parser.add_argument("--hz", type=int, choices=(60, 120), nargs="+", default=[60, 120])
    parser.add_argument("--cases", choices=CASES, nargs="+", default=list(CASES))
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--duration-s", type=int, choices=range(5, 31), default=5)
    parser.add_argument("--allow-sleep", action="store_true", help="Diagnostic using native island sleep thresholds")
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--realtime", action="store_true", help="Use normal engine wall-clock pacing")
    args = parser.parse_args()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    trials = list(product(args.cases, args.profiles, args.hz))
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as workers:
        results = list(workers.map(lambda trial: run_trial(args, trial), trials))
    for _, _, label in results:
        print(label)
    if not all(executed for executed, _, _ in results):
        return 2
    # Overwrite the aggregate of this invocation, never append/reuse stale cases.
    for kind in ("body", "joints", "impacts"):
        rows = []
        for case, profile, hz in trials:
            if kind == "impacts" and not case.startswith("hit_"):
                continue
            duration = f"_{args.duration_s}s" if args.duration_s != 5 else ""
            sleep = "_sleep" if args.allow_sleep else ""
            path = args.out / f"{case}_{profile}_{hz}{duration}{sleep}_{kind}.csv"
            with path.open(encoding="utf-8", newline="") as f:
                rows.extend(csv.DictReader(f))
        if rows:
            with (args.out / f"matrix_{kind}.csv").open("w", encoding="utf-8", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=rows[0].keys())
                writer.writeheader()
                writer.writerows(rows)
    return 0 if all(passed for _, passed, _ in results) else 1


if __name__ == "__main__":
    sys.exit(main())
