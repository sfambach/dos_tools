#!/usr/bin/env python3
"""Turn the raw files of BENCH.BAT runs into a taxmod/apply change list.

    python3 bench2apply.py RESULTS/ bench-map.json out.json

Every RESULTS/<host>/NEW folder that holds READY.TXT is one finished run. It is
renamed to RESULTS/<host>/<timestamp> (the DOS PC has no reliable clock), its
files are parsed, and each measurement whose key is mapped to a measured
quantity in bench-map.json becomes one new measurement record. Repeated runs of
a test (DOOM1..3) are averaged; the single values go into the note.

Python 3.8+, standard library only.
"""

from __future__ import annotations

import argparse
import configparser
import datetime
import json
import re
import statistics
import sys
from pathlib import Path

SETUP_FIELD, QUANTITY_FIELD, VALUE_FIELD, NOTE_FIELD = (
    "149000109407", "149000109408", "149000109409", "149000109410")

DOOM_TICS = re.compile(r"timed\s+(\d+)\s+gametics\s+in\s+(\d+)\s+realtics")
QUAKE_FPS = re.compile(r"(\d+)\s+frames\s+([\d.]+)\s+seconds\s+([\d.]+)\s+fps")
# Doom runs at 35 tics per second; the demo has 2134 gametics, so 74690 / realtics
DOOM_TICS_PER_SECOND = 35


def read_text(path: Path) -> str:
    return path.read_bytes().decode("cp437", errors="replace")


def read_ini(path: Path) -> dict[str, str]:
    """RUN.INI style KEY=VALUE lines without a section header."""
    values = {}
    for line in read_text(path).splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            values[key.strip().upper()] = value.strip()
    return values


def parse_doom(run: Path) -> dict[str, list[float]]:
    fps, realtics = [], []
    for path in sorted(run.glob("DOOM*.TXT")):
        match = DOOM_TICS.search(read_text(path))
        if match:
            gametics, real = int(match.group(1)), int(match.group(2))
            realtics.append(real)
            fps.append(round(gametics * DOOM_TICS_PER_SECOND / real, 2))
    return {"doom.realtics": realtics, "doom.fps": fps}


def parse_quake(run: Path) -> dict[str, list[float]]:
    path = run / "QUAKE.TXT"
    if not path.exists():
        return {}
    return {"quake.fps": [float(m.group(3)) for m in QUAKE_FPS.finditer(read_text(path))]}


def parse_topbench(run: Path) -> dict[str, list[float]]:
    path = run / "TOPBENCH.INI"
    if not path.exists():
        return {}
    ini = configparser.ConfigParser(strict=False)
    ini.read_string(read_text(path))
    values: dict[str, list[float]] = {}
    for section in ini.sections():
        for key in ("Score", "MemoryTest", "OpcodeTest", "VidramTest", "MemEATest", "3DGameTest"):
            if ini.has_option(section, key):
                values.setdefault("topbench." + key.lower(), []).append(float(ini.get(section, key)))
    return values


def parse_speedsys(run: Path) -> dict[str, list[float]]:
    # Format of the 4.79 text report not seen yet (crashes in DOSBox 0.74); first real file decides.
    path = run / "SPEEDSYS.TXT"
    if not path.exists():
        return {}
    match = re.search(r"CPU\s+Speed\s+Index\s*[:=]?\s*([\d.]+)", read_text(path), re.IGNORECASE)
    return {"speedsys.cpu": [float(match.group(1))]} if match else {}


PARSERS = (parse_doom, parse_quake, parse_topbench, parse_speedsys)


def claim_finished_runs(results: Path) -> list[Path]:
    runs = []
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    for new in sorted(results.glob("*/NEW")):
        if (new / "READY.TXT").exists():
            target = new.with_name(stamp)
            new.rename(target)
            runs.append(target)
    runs.extend(p for p in sorted(results.glob("*/*-*")) if p.is_dir() and not (p / "APPLIED.TXT").exists() and p not in runs)
    return runs


def changes_for_run(run: Path, mapping: dict, report: list[str]) -> list[dict]:
    meta = read_ini(run / "RUN.INI") if (run / "RUN.INI").exists() else {}
    setup = meta.get("SETUP", "")
    if not setup or setup == "0":
        report.append(f"{run}: no SETUP in HOST.BAT, run skipped")
        return []
    measurements: dict[str, list[float]] = {}
    for parser in PARSERS:
        measurements.update({k: v for k, v in parser(run).items() if v})
    errors = read_ini(run / "ERRORS.INI") if (run / "ERRORS.INI").exists() else {}
    for test, state in errors.items():
        report.append(f"{run}: {test} {state}, no values")

    changes = []
    for key, values in sorted(measurements.items()):
        quantity = mapping["quantities"].get(key)
        if not quantity:
            report.append(f"{run}: {key} = {values} has no measured quantity in the map")
            continue
        value = round(statistics.mean(values), 2)
        single = ", ".join(f"{v:g}" for v in values)
        note = (f"Automatisch gemessen (BENCH.BAT), Lauf {run.parent.name}/{run.name}, "
                f"{'Mittelwert aus ' + str(len(values)) + ' Läufen: ' if len(values) > 1 else 'Rohwert: '}{single}")
        ref = f"m{len(changes) // 2 + 1}_{run.parent.name}_{run.name}"
        changes.append({"op": "create_record", "node": mapping["measurement_node"], "ref": ref})
        changes.append({"op": "set_values", "record": "@" + ref, "values": {
            SETUP_FIELD: setup, QUANTITY_FIELD: quantity, VALUE_FIELD: f"{value:g}", NOTE_FIELD: note}})
    (run / "APPLIED.TXT").write_text(json.dumps(measurements, indent=1))
    return changes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("results", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    mapping = json.loads(args.mapping.read_text(encoding="utf-8"))
    report: list[str] = []
    changes: list[dict] = []
    for run in claim_finished_runs(args.results):
        changes += changes_for_run(run, mapping, report)
    for line in report:
        print(line, file=sys.stderr)
    if not changes:
        print("no measurements to upload", file=sys.stderr)
        return 1
    args.output.write_text(json.dumps({"changes": changes}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(changes) // 2} measurements -> {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
