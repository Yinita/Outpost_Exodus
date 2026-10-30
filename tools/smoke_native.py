#!/usr/bin/env python3
"""Smoke-test the Linux native export in isolated user directories (needs DISPLAY)."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import struct
import subprocess
import sys
import time
import zlib

PROJECT = Path(__file__).resolve().parents[1]
BUILD = PROJECT / "builds" / "linux-release"
WORK = PROJECT / "work" / "native-smoke"
EXECUTABLE = BUILD / "outpost-exodus.x86_64"
PACK = BUILD / "outpost-exodus.pck"
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
BAD_OUTPUT = re.compile(
    r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|ObjectDB[^\n]*leak|resources still in use at exit"
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_result(result: dict) -> None:
    temporary = WORK / "result.json.tmp"
    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(WORK / "result.json")


def check_png(path: Path) -> dict:
    """Validate chunk integrity/dimensions, without an image-library dependency."""
    raw = path.read_bytes()
    if len(raw) < 4096 or len(raw) > 32 * 1024 * 1024 or raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Capture is missing, implausibly small/large or not a PNG")
    position = 8
    width = height = 0
    has_pixels = has_end = False
    first = True
    while position + 12 <= len(raw):
        length = struct.unpack_from(">I", raw, position)[0]
        end = position + 12 + length
        if end > len(raw):
            raise ValueError("Truncated PNG chunk")
        kind = raw[position + 4:position + 8]
        payload = raw[position + 8:position + 8 + length]
        crc = struct.unpack_from(">I", raw, position + 8 + length)[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != crc:
            raise ValueError("PNG chunk CRC mismatch")
        if first and (kind != b"IHDR" or length != 13):
            raise ValueError("PNG lacks an initial IHDR")
        if kind == b"IHDR":
            width, height = struct.unpack_from(">II", payload)
        elif kind == b"IDAT" and length > 0:
            has_pixels = True
        elif kind == b"IEND":
            has_end = length == 0 and end == len(raw)
            break
        first = False
        position = end
    if width < 1152 or height < 648 or width > 7680 or height > 4320 or not has_pixels or not has_end:
        raise ValueError("PNG has invalid dimensions or missing pixel/end chunks")
    return {"path": str(path), "width": width, "height": height, "bytes": len(raw), "sha256": sha256(path)}


def run_case(name: str, arguments: list[str], display: str, timeout: float) -> dict:
    environment = os.environ.copy()
    for variable, directory in (
        ("XDG_DATA_HOME", f"{name}-data"),
        ("XDG_CONFIG_HOME", f"{name}-config"),
        ("XDG_CACHE_HOME", f"{name}-cache"),
    ):
        environment[variable] = str(WORK / directory)
    if display:
        environment["DISPLAY"] = display
    command = [str(EXECUTABLE), *arguments]
    started = time.monotonic()
    case = {"name": name, "argv": command, "cwd": str(BUILD), "timeout_seconds": timeout,
            "isolated_environment": {key: environment[key] for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")}}
    try:
        completed = subprocess.run(command, cwd=BUILD, env=environment, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, encoding="utf-8", errors="replace", timeout=timeout)
        output = completed.stdout
        case.update(returncode=completed.returncode, timed_out=False)
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or b""
        output = partial.decode("utf-8", "replace") if isinstance(partial, bytes) else partial
        case.update(returncode=None, timed_out=True)
    case["elapsed_seconds"] = round(time.monotonic() - started, 4)
    log = WORK / f"{name}.log"
    log.write_text(output, encoding="utf-8")
    case["log_path"] = str(log)
    case["runtime_output"] = output
    plain = ANSI.sub("", output)
    case["error_or_leak_output"] = bool(BAD_OUTPUT.search(plain))
    simulation_progressed = True
    if name == "headless":
        marker = re.search(r"(?m)^SMOKE_OK ticks=(\d+) units=(\d+)\s*$", plain)
        case["expected_marker"] = marker is not None
        case["simulation_ticks"] = int(marker.group(1)) if marker else None
        case["unit_count"] = int(marker.group(2)) if marker else None
        case["minimum_simulation_ticks"] = 70
        simulation_progressed = marker is not None and int(marker.group(1)) >= 70 and int(marker.group(2)) > 0
    else:
        case["expected_marker"] = bool(re.search(r"(?m)^CAPTURE_RESULT\s+0\s+", plain))
    case["success"] = (case["returncode"] == 0 and case["expected_marker"]
                       and simulation_progressed and not case["error_or_leak_output"])
    return case


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--display", default=os.environ.get("DISPLAY", ""), help="X11 display for the rendered capture")
    parser.add_argument("--timeout", type=float, default=60.0, help="Timeout per native process, at most 60 seconds")
    options = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    result = {
        "schema_version": 1, "success": False, "started_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(), "python": platform.python_version(), "display": options.display,
        "payload_sha256": {}, "runs": [],
        "scope": ["Linux native release export headless startup/simulation smoke", "Linux native release export rendered campaign capture and clean shutdown"],
        "not_verified": ["fresh-player usability", "full native campaign playthrough", "minimum hardware or frame pacing", "clean-machine installation", "Windows execution", "Steam integration/review", "manual screenshot inspection"],
    }
    write_result(result)  # An interrupted/failed run cannot leave an old success report.
    try:
        if not sys.platform.startswith("linux"):
            raise ValueError("This smoke tool executes only the Linux native export")
        if not (0 < options.timeout <= 60):
            raise ValueError("Timeout must be positive and no greater than 60 seconds")
        if not options.display:
            raise ValueError("A DISPLAY is required for the rendered capture")
        if not EXECUTABLE.is_file() or not os.access(EXECUTABLE, os.X_OK) or not PACK.is_file():
            raise ValueError("Missing executable native Linux export; run tools/export_release.sh first")
        result["payload_sha256"] = {path.name: sha256(path) for path in (EXECUTABLE, PACK)}
        provenance = BUILD / "export-source.json"
        if provenance.is_file():
            result["export_provenance"] = json.loads(provenance.read_text(encoding="utf-8"))
        preview = WORK / "preview.png"
        preview.unlink(missing_ok=True)
        # --smoke lasts 240 frames. Fixed frame time makes these exercise about
        # four simulated seconds even when the headless renderer is uncapped.
        for name, arguments in (("headless", ["--headless", "--fixed-fps", "60", "--", "--smoke"]),
                                ("rendered", ["--", f"--capture={preview}"])):
            case = run_case(name, arguments, options.display, options.timeout)
            result["runs"].append(case)
            write_result(result)
            if not case["success"]:
                raise ValueError(f"Native {name} smoke failed; see {case['log_path']}")
        result["capture"] = check_png(preview)
        if result["payload_sha256"] != {path.name: sha256(path) for path in (EXECUTABLE, PACK)}:
            raise ValueError("Native payload changed during validation; rebuild and rerun")
        result["success"] = True
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        result["failure"] = str(error)
    result["finished_utc"] = datetime.now(timezone.utc).isoformat()
    write_result(result)
    print(json.dumps({"success": result["success"], "report": str(WORK / "result.json"),
                      "failure": result.get("failure")}, ensure_ascii=False))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
