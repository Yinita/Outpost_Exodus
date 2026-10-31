#!/usr/bin/env python3
"""Exercise actual Main startup refusal in isolated headless subprocesses."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


PROJECT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
BAD_OUTPUT = re.compile(
    r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|ObjectDB[^\n]*leak|resources still in use at exit"
)
CASES = (
    ("campaign_without_root", ["--campaign-validation"],
     "DIAGNOSTICS_REFUSED CAMPAIGN_VALIDATION_ROOT"),
    ("render_without_root", ["--render-diagnostics"],
     "DIAGNOSTICS_REFUSED BENCH_ISOLATION_ROOT"),
    ("unknown_mission", ["--mission=missing"], "Unknown mission: missing"),
)


def snapshot(paths: list[Path]) -> dict:
    result = {}
    for path in paths:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        result[str(path)] = {"bytes": path.stat().st_size, "sha256": digest.hexdigest()}
    return result


def write_report(path: Path, result: dict) -> None:
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def run_case(name: str, user_arguments: list[str], marker: str,
             command: list[str], cwd: Path, directory: Path, timeout: float) -> dict:
    directory.mkdir()
    environment = os.environ.copy()
    environment.pop("CAMPAIGN_VALIDATION_ROOT", None)
    environment.pop("BENCH_ISOLATION_ROOT", None)
    for key, child in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                       ("XDG_CACHE_HOME", "cache")):
        environment[key] = str(directory / child)
    argv = [*command, "--headless", "--", *user_arguments]
    started = time.monotonic()
    timed_out = False
    try:
        completed = subprocess.run(argv, cwd=cwd, env=environment, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   encoding="utf-8", errors="replace", timeout=timeout)
        output, returncode = completed.stdout, completed.returncode
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or b""
        output = partial.decode("utf-8", "replace") if isinstance(partial, bytes) else partial
        returncode, timed_out = None, True
    log = directory / "native-process.log"
    log.write_text(output, encoding="utf-8")
    plain = ANSI.sub("", output)
    player_state = [str(path.relative_to(directory)) for path in directory.rglob("*")
                    if path.name == "settings.cfg" or path.name.startswith("campaign-save.json")
                    or path.name.startswith("campaign-autosave.json")]
    checks = {"expected_exit_2": returncode == 2, "expected_refusal_marker": marker in plain,
              "no_script_error_or_resource_leak": not bool(BAD_OUTPUT.search(plain)),
              "no_player_save_or_settings_created": not player_state, "did_not_time_out": not timed_out}
    return {"name": name, "success": all(checks.values()), "checks": checks,
            "argv": argv, "cwd": str(cwd), "returncode": returncode, "timed_out": timed_out,
            "wall_seconds": round(time.monotonic() - started, 4),
            "isolated_environment": {key: environment[key] for key in
                                     ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")},
            "unset_environment": ["CAMPAIGN_VALIDATION_ROOT", "BENCH_ISOLATION_ROOT"],
            "expected_marker": marker, "unexpected_player_state": player_state,
            "log": {"path": str(log), **snapshot([log])[str(log)]}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-build-dir", type=Path,
                        help="Optional actual Linux EXE/PCK directory; omits source project path")
    parser.add_argument("--timeout", type=float, default=20.0, help="Per-case cap, positive and at most60seconds")
    options = parser.parse_args()
    if not 0 < options.timeout <= 60:
        parser.error("--timeout must be positive and no greater than60")
    if options.native_build_dir is None:
        cwd, command = PROJECT, [str(PROJECT / "run.sh")]
        bound_files = [PROJECT / path for path in
                       ("run.sh", "project.godot", "scripts/main.gd",
                        "scripts/diagnostics/campaign_runner.gd", "scripts/diagnostics/render_runner.gd")]
        mode = "source-runtime actual Main"
    else:
        cwd = options.native_build_dir.resolve()
        executable = cwd / "outpost-exodus.x86_64"
        pack = cwd / "outpost-exodus.pck"
        if not executable.is_file() or not os.access(executable, os.X_OK) or not pack.is_file():
            parser.error("--native-build-dir must contain executable Linux game and adjacent PCK")
        command, bound_files = [str(executable)], [executable, pack]
        mode = "selected native EXE/PCK actual Main"
    base = PROJECT / "work/startup-rejection-tests"
    base.mkdir(parents=True, exist_ok=True)
    # mkdtemp claims a new run only; prior evidence and player data are retained.
    stamp = datetime.now(timezone.utc).strftime("run-%Y%m%dT%H%M%S-")
    directory = Path(tempfile.mkdtemp(prefix=stamp, dir=base))
    report_path = directory / "result.json"
    result = {"success": False, "started_utc": datetime.now(timezone.utc).isoformat(),
              "mode": mode, "scope": "Actual Main startup rejection only; no campaign, GUI, FPS or human-playability claim",
              "directory": str(directory), "timeout_per_case": options.timeout, "cases": [], "errors": []}
    write_report(report_path, result)
    try:
        result["bound_files_before"] = snapshot(bound_files)
        for name, arguments, marker in CASES:
            case = run_case(name, arguments, marker, command, cwd, directory / name, options.timeout)
            result["cases"].append(case)
            write_report(report_path, result)
        result["bound_files_after"] = snapshot(bound_files)
        result["bound_files_changed"] = result["bound_files_before"] != result["bound_files_after"]
        if result["bound_files_changed"]:
            result["errors"].append("Bound source or payload changed during startup checks")
        result["success"] = len(result["cases"]) == len(CASES) and all(case["success"] for case in result["cases"]) and not result["errors"]
    except (OSError, subprocess.SubprocessError) as error:
        result["errors"].append(str(error))
    result["finished_utc"] = datetime.now(timezone.utc).isoformat()
    write_report(report_path, result)
    print(json.dumps({"success": result["success"], "cases": len(result["cases"]),
                      "passed_checks": sum(sum(case["checks"].values()) for case in result["cases"]),
                      "report": str(report_path), "errors": result["errors"]}, ensure_ascii=False, indent=2))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
