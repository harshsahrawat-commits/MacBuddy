#!/usr/bin/env python3
"""Read-only validation of Mac Buddy's SQLite summaries. No process data is read."""
import argparse
import datetime as dt
import json
import pathlib
import sqlite3

parser = argparse.ArgumentParser()
parser.add_argument("database", nargs="?", type=pathlib.Path, default=pathlib.Path.home() / "Library/Application Support/MacBuddy/history.sqlite")
args = parser.parse_args()
connection = sqlite3.connect(args.database.resolve().as_uri() + "?mode=ro", uri=True)
connection.execute("PRAGMA query_only=ON")
integrity = connection.execute("PRAGMA quick_check").fetchone()[0]
issues = []
if integrity != "ok":
    issues.append(integrity)
count = 0
coverage = 0.0
latest = None
thermal = {}
for bucket, resolution, payload in connection.execute("SELECT bucket,resolution,payload FROM summaries ORDER BY bucket"):
    row = json.loads(payload)
    count += 1
    covered = row["coverage"]
    coverage += covered
    if not 0 <= covered <= resolution + 0.001:
        issues.append(f"Invalid coverage at {bucket}: {covered}/{resolution}")
    if latest is not None and bucket < latest:
        issues.append(f"Overlapping summary at {bucket}")
    latest = bucket + resolution
    if abs(sum(row["thermalSeconds"].values()) - covered) > 0.01:
        issues.append(f"Thermal duration mismatch at {bucket}")
    if abs(sum(row["pressureSeconds"].values()) - covered) > 0.01:
        issues.append(f"Memory-pressure duration mismatch at {bucket}")
    for key, seconds in row["thermalSeconds"].items():
        thermal[key] = thermal.get(key, 0) + seconds
    values = row["metrics"]
    pairs = zip(values[::2], values[1::2]) if isinstance(values, list) else values.items()
    for metric, stat in pairs:
        if stat["seconds"] > covered + 0.001 or stat["seconds"] < 0:
            issues.append(f"Invalid {metric} coverage at {bucket}")
        if stat.get("minimum") is not None and stat.get("peak") is not None and stat["minimum"] > stat["peak"]:
            issues.append(f"Invalid {metric} range at {bucket}")
        if stat["seconds"] > 0:
            average = stat["weightedSum"] / stat["seconds"]
            tolerance = max(0.001, abs(average) * 1e-8)
            if average < stat["minimum"] - tolerance or average > stat["peak"] + tolerance:
                issues.append(f"Invalid {metric} average at {bucket}")
size = sum(path.stat().st_size if path.exists() else 0 for path in [args.database, pathlib.Path(str(args.database) + "-wal"), pathlib.Path(str(args.database) + "-shm"), pathlib.Path(str(args.database) + "-journal")])
print(json.dumps({"integrity": integrity, "summary_count": count, "coverage_hours": round(coverage / 3600, 3), "archive_mib": round(size / 1048576, 3), "last_bucket_end_utc": dt.datetime.fromtimestamp(latest, dt.timezone.utc).isoformat() if latest else None, "thermal_seconds_by_state": thermal, "issues": issues}, indent=2))
connection.close()
raise SystemExit(1 if issues else 0)
