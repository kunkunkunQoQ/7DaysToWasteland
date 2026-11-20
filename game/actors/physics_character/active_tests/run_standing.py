"""Run the standing gate in fresh Godot processes and compare full visual pairs."""

import argparse
import csv
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


CASES = ("quiet", "front", "back", "left", "right")
ENTRY = "res://game/actors/physics_character/active_tests/verify_standing.gd"


def run(args, trial):
    mode, case, visual = trial
    prefix = f"{mode}_{case}_{visual}"
    command = [str(args.godot), "--headless", "--fixed-fps", "60", "--path", str(args.project),
               "--log-file", str(args.out / f"{prefix}.log"), "--script", ENTRY, "--",
               f"--mode={mode}", f"--case={case}", f"--visual={visual}", f"--out={args.out}"]
    if args.trace:
        command.append("--trace")
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=180, check=False)
    output = result.stdout + result.stderr
    markers = [line[len("STANDING "):] for line in output.splitlines() if line.startswith("STANDING {")]
    if result.returncode not in (0, 1) or "SCRIPT ERROR:" in output or "ERROR:" in output or len(markers) != 1:
        raise RuntimeError(f"{prefix}: Godot failed ({result.returncode})\n{output[-1500:]}")
    row = json.loads(markers[0])
    if (mode, case, visual) != (row["mode"], row["case"], row["visual"]) or row["samples"] != 3600:
        raise ValueError(f"{prefix}: incomplete or mislabeled trial")
    if row["test_pass"] != (result.returncode == 0):
        raise ValueError(f"{prefix}: result and exit code disagree")
    with (args.out / f"{prefix}_joints.csv").open(encoding="utf-8", newline="") as stream:
        joints = list(csv.DictReader(stream))
    if len(joints) != 15 or len({j["joint"] for j in joints}) != 15:
        raise ValueError(f"{prefix}: incomplete joint records")
    for joint in joints:
        joint.update(mode=mode, case=case, visual=visual)
    return row, joints


def write_csv(path, rows):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--jobs", type=int, choices=range(1, 13), default=1)
    parser.add_argument("--trace", action="store_true")
    args = parser.parse_args()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    trials = [("active", case, visual) for case in CASES for visual in ("on", "off")]
    trials.append(("passive", "quiet", "off"))
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda trial: run(args, trial), trials))
    body = [row for row, _ in results]
    joints = [joint for _, rows in results for joint in rows]
    hashes = {(row["case"], row["visual"]): row["physics_sha256"] for row in body if row["mode"] == "active"}
    pairs = [{"case": case, "on_sha256": hashes[case, "on"], "off_sha256": hashes[case, "off"],
              "identical": hashes[case, "on"] == hashes[case, "off"]} for case in CASES]
    write_csv(args.out / "standing_body.csv", body)
    write_csv(args.out / "standing_joints.csv", joints)
    write_csv(args.out / "visual_pairs.csv", pairs)
    passed = sum(row["test_pass"] for row in body)
    same = sum(pair["identical"] for pair in pairs)
    print(f"Standing trials {passed}/{len(body)} including passive negative control. Visual pairs {same}/{len(pairs)}.")
    return 0 if passed == len(body) and same == len(pairs) else 1


if __name__ == "__main__":
    raise SystemExit(main())
