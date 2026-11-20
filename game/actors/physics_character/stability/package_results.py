"""Assemble measured CSV files from run_matrix.py; Python standard library only."""
import argparse
import csv
import gzip
import io
import math
from collections import defaultdict
from contextlib import ExitStack
from pathlib import Path

from run_matrix import CASES


PARENTS = {"spine": "pelvis", "chest": "spine", "head": "chest"}
for side in ("_l", "_r"):
    PARENTS.update({"upper_arm" + side: "chest", "lower_arm" + side: "upper_arm" + side,
                    "hand" + side: "lower_arm" + side, "thigh" + side: "pelvis",
                    "calf" + side: "thigh" + side, "foot" + side: "calf" + side})


def trial(row):
    return row["profile"], row["hz"], row["case"]


def read(path):
    with path.open(encoding="utf-8-sig", newline="") as file:
        return list(csv.DictReader(file))


def write(path, rows):
    with ExitStack() as stack:
        if path.suffix == ".gz":
            raw = stack.enter_context(path.open("wb"))
            zipped = stack.enter_context(gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0))
            file = stack.enter_context(io.TextIOWrapper(zipped, encoding="utf-8", newline=""))
        else:
            file = stack.enter_context(path.open("w", encoding="utf-8", newline=""))
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def validate(body, joints, impacts=None, duration_s=5):
    bodies = {trial(row): row for row in body}
    if not bodies or len(bodies) != len(body):
        raise ValueError("Missing or duplicate body trial")
    bones = defaultdict(dict)
    for row in joints:
        key = trial(row)
        child = row["joint"]
        if child in bones[key] or key not in bodies or PARENTS.get(child) != row["parent"]:
            raise ValueError(f"Unexpected, duplicate or misparented joint {key} {child}")
        bones[key][child] = row["parent"]
    events = defaultdict(dict)
    for row in impacts or ():
        key = trial(row)
        number = int(row["shot"])
        if key not in bodies or number in events[key]:
            raise ValueError(f"Unexpected or duplicate shot {key} {number}")
        events[key][number] = row
    for key, row in bodies.items():
        _, hz, case = key
        if int(row["samples"]) != int(hz) * duration_s or float(row["duration_s"]) != duration_s:
            raise ValueError(f"Expected {duration_s} seconds at the stated rate: {key}")
        if bones[key] != PARENTS:
            raise ValueError(f"Incomplete joint topology: {key}")
        if impacts is not None:
            expected = 3 if case == "hit_repeat" else int(case.startswith("hit_"))
            shots = events[key]
            if set(shots) != set(range(1, expected + 1)) or int(row["shots"]) != expected:
                raise ValueError(f"Missing or unexpected shots: {key}")
            verified = sum(event["hit_pass"] == "true" for event in shots.values())
            if verified != int(row["hits_verified"]):
                raise ValueError(f"Body/impact verified count mismatch: {key}")


def envelopes(joints):
    groups = {}
    for row in joints:
        key = (row["profile"], int(row["hz"]), row["parent"], row["joint"])
        groups.setdefault(key, []).append(row)
    result = []
    for (profile, hz, parent, joint), group in groups.items():
        if len(group) != len(CASES) or {r["case"] for r in group} != set(CASES):
            raise ValueError(f"Incomplete envelope for {profile}, {hz} Hz, {joint}")
        peak = max(group, key=lambda r: float(r["peak_anchor_m"]))
        case_rms_sq = [float(r["rms_anchor_m"]) ** 2 for r in group]
        times = [float(r["recovery_s"]) for r in group]
        result.append(dict(profile=profile, hz=hz, parent=parent, joint=joint,
                           peak_anchor_m=peak["peak_anchor_m"], peak_case=peak["case"],
                           peak_tick=peak["peak_tick"],
                           rms_anchor_m=math.sqrt(sum(case_rms_sq) / len(group)),
                           worst_residual_m=max(float(r["residual_m"]) for r in group),
                           peak_angular_error_deg=max(float(r["peak_angular_error_deg"]) for r in group),
                           peak_limit_violation_deg=max(float(r["peak_limit_deg"]) for r in group),
                           max_relative_omega_rad_s=max(float(r["peak_relative_omega_rad_s"]) for r in group),
                           slowest_confirmed_recovery_s=max(times),
                           recovery_unverified_cases=sum(t < 0 for t in times),
                           tail_oscillation_cases=sum(r["sustained_oscillation"] == "true" for r in group)))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", type=Path, required=True)
    parser.add_argument("--extended", type=Path, help="Optional matching 18-second matrix")
    parser.add_argument("--comparisons", type=Path, nargs="+", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--profiles", nargs="+", required=True)
    args = parser.parse_args()
    args.out.mkdir(exist_ok=True, parents=True)
    wanted = {(p, str(hz), case) for p in args.profiles for hz in (60, 120) for case in CASES}
    outputs = {}
    for directory, seconds, suffix in ((args.matrix, 5, ""), (args.extended, 18, "_18s")):
        if directory is None:
            continue
        matrix = {kind: [row for row in read(directory / f"matrix_{kind}.csv") if row["profile"] in args.profiles]
                  for kind in ("body", "joints", "impacts")}
        if {trial(row) for row in matrix["body"]} != wanted:
            raise ValueError(f"Incomplete {seconds}-second matrix coverage")
        validate(**matrix, duration_s=seconds)
        for kind, rows in matrix.items():
            outputs[f"matrix{suffix}_{kind}.csv"] = rows
        outputs[f"joint_envelopes{suffix}.csv"] = envelopes(matrix["joints"])
    comparisons = {"body": {}, "joints": {}}
    for source in args.comparisons:
        data = {kind: read(source / f"matrix_{kind}.csv") for kind in comparisons}
        duration = int(data["body"][0]["duration_s"])
        validate(**data, duration_s=duration)
        conditions = {trial(row): row["allow_sleep"] for row in data["body"]}
        for kind, rows in data.items():
            for row in rows:
                sleep = conditions[trial(row)]
                if kind == "joints":
                    row.update(duration_s=str(duration), allow_sleep=sleep)
                key = (*trial(row), duration, sleep, row.get("joint"))
                unique = comparisons[kind]
                if key in unique and unique[key] != row:
                    raise ValueError(f"Conflicting observations for {key}")
                unique[key] = row
    outputs["parameter_comparison.csv"] = list(comparisons["body"].values())
    outputs["comparison_joints.csv.gz"] = list(comparisons["joints"].values())
    for name, rows in outputs.items():
        write(args.out / name, rows)


if __name__ == "__main__":
    main()
