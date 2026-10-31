#!/usr/bin/env python3
"""Verify a complete campaign through the exported Linux game's normal loop.

The validator is an explicit packaged game entry point. This launcher never
loads a source project, changes simulation timing, or deletes an existing run.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from typing import Any


PROJECT = Path(__file__).resolve().parents[1]
EXECUTABLE_NAME = "outpost-exodus.x86_64"
PACK_NAME = "outpost-exodus.pck"
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
BAD_OUTPUT = re.compile(
    r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|ObjectDB[^\n]*leak|resources still in use at exit"
)
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
GIT_COMMIT = re.compile(r"[0-9a-f]{40}\Z")
MISSION_TAGS = {"canyon": "rift_escape_01", "delta": "wetland_escape_02", "ridge": "ridge_escape_03"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json(path: Path, value: dict[str, Any]) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def read_object(path: Path, maximum_bytes: int = 16 * 1024 * 1024) -> dict[str, Any]:
    if not path.is_file() or path.stat().st_size > maximum_bytes:
        raise ValueError(f"Missing or oversized JSON record: {path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON record must be an object: {path}")
    return value


def prepare_isolation(raw: Path, build: Path) -> Path:
    """Claim only an absent or completely empty, dedicated real directory."""
    if not raw.is_absolute() or ".." in raw.parts:
        raise ValueError("--isolation-root must be an absolute dedicated path without '..'")
    for component in (raw, *raw.parents):
        if component.is_symlink():
            raise ValueError(f"Isolation cannot contain symlink components: {component}")
    isolation = raw.resolve()
    protected = {Path(isolation.anchor), Path.home().resolve(), PROJECT.resolve(), build}
    if any(isolation == path or isolation in path.parents for path in protected):
        raise ValueError("Isolation must not be a home, project, build directory or their ancestor")
    if isolation.exists() and (not isolation.is_dir() or any(isolation.iterdir())):
        raise ValueError("Isolation already contains data; use a new directory. Nothing was deleted.")
    isolation.mkdir(parents=True, exist_ok=True)
    return isolation


def binary_snapshot(build: Path) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, name in (("executable", EXECUTABLE_NAME), ("adjacent_pck", PACK_NAME)):
        path = build / name
        if not path.is_file():
            raise ValueError(f"Missing native payload: {path}")
        result[key] = {"path": str(path), "available": True,
                       "bytes": path.stat().st_size, "sha256": sha256(path)}
    if not os.access(build / EXECUTABLE_NAME, os.X_OK):
        raise ValueError("Native Linux executable has no execute permission")
    return result


def verify_export_metadata(build: Path, binaries: dict[str, Any]) -> dict[str, Any]:
    # Export tooling refreshes export-source.json before packaging updates the
    # optional build-info.json. An unpacked download contains build-info only.
    path = build / "export-source.json"
    if not path.is_file():
        path = build / "build-info.json"
    metadata = read_object(path)
    commit = metadata.get("source_commit")
    if not isinstance(commit, str) or not GIT_COMMIT.fullmatch(commit):
        raise ValueError("Native build metadata must identify its exact source commit")
    expected = metadata.get("sha256")
    if not isinstance(expected, dict):
        raise ValueError("Native build metadata has no payload hashes")
    for key, name in (("executable", EXECUTABLE_NAME), ("adjacent_pck", PACK_NAME)):
        digest = expected.get(name)
        if not isinstance(digest, str) or not SHA256.fullmatch(digest) or digest != binaries[key]["sha256"]:
            raise ValueError(f"Native export metadata does not match actual {name}")
    return {"path": str(path), "sha256": sha256(path), "source_commit": commit,
            "source_tree": metadata.get("source_tree"), "format": path.name}


def number(value: Any) -> bool:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def mission_identity_errors(identity: Any, mission: str, stage: str,
                            *, live: bool = False, saved: bool = False) -> list[str]:
    if not isinstance(identity, dict):
        return [f"Missing mission identity proof at {stage}"]
    errors: list[str] = []
    if identity.get("mission_id") != mission or identity.get("mission_tag") != MISSION_TAGS[mission]:
        errors.append(f"Mission identity at {stage} does not match requested {mission}")
    if live and identity.get("selected_mission_id") != mission:
        errors.append(f"Controller mission selection at {stage} does not match requested {mission}")
    if saved and identity.get("payload_mission_id") != ("" if mission == "canyon" else mission):
        errors.append(f"Saved mission payload at {stage} does not match requested {mission}")
    return errors


def saved_mission_identity(state: dict[str, Any]) -> dict[str, Any]:
    """Read the encoded save's identity without rewriting or trusting report fields."""
    payload = state.get("payload")
    if not isinstance(payload, dict) or payload.get("$type") != "Dictionary":
        raise ValueError("Final campaign state has no encoded simulation dictionary")
    entries = payload.get("entries")
    if not isinstance(entries, list) or any(not isinstance(pair, list) or len(pair) != 2 for pair in entries):
        raise ValueError("Final campaign state has invalid encoded dictionary entries")
    identifiers = [pair[1] for pair in entries if pair[0] == "mission_id"]
    if len(identifiers) > 1:
        raise ValueError("Final campaign state repeats its mission identity")
    tag = state.get("mission")
    return {"mission_id": next((mission for mission, value in MISSION_TAGS.items() if value == tag), ""),
            "mission_tag": tag, "payload_mission_id": identifiers[0] if identifiers else ""}


def validate_report(report: dict[str, Any], before: dict[str, Any],
                    after: dict[str, Any], prepare_only: bool,
                    expected_arguments: list[str] | None = None,
                    expected_mission: str = "canyon",
                    final_state: dict[str, Any] | None = None) -> list[str]:
    """Reject narrower or stale evidence even if the native process exits zero."""
    errors: list[str] = []
    if expected_mission not in MISSION_TAGS:
        return ["Unsupported requested campaign mission"]
    if report.get("requested_mission_id") != expected_mission:
        errors.append("Native report requested mission does not match the launch")
    errors.extend(mission_identity_errors(report.get("campaign_start"), expected_mission, "campaign start", live=True))
    if report.get("native_export_proof") is not True:
        errors.append("Report is not from a native release export")
    if report.get("prepare_only") is not prepare_only:
        errors.append("Report mode does not match requested prepare/full mode")
    if report.get("errors") != []:
        errors.append(f"Native validator reported errors: {report.get('errors')!r}")
    if report.get("display_server") in (None, "", "headless"):
        errors.append("A real native graphical display is required")
    command_line = report.get("engine_command_line", {})
    if not isinstance(command_line, dict):
        command_line = {}
    arguments = command_line.get("arguments")
    if (command_line.get("available") is not True or command_line.get("source") != "/proc/self/cmdline"
            or not isinstance(arguments, list) or not arguments
            or not all(isinstance(argument, str) for argument in arguments)):
        errors.append("Actual complete native process arguments were not proven")
    else:
        if Path(arguments[0]).resolve() != Path(before["executable"]["path"]).resolve():
            errors.append("Actual command line does not identify the launched executable")
        forbidden = {"--fixed-fps", "--time-scale", "--disable-render-loop", "--write-movie"}
        if any(argument.split("=", 1)[0] in forbidden for argument in arguments[1:]):
            errors.append("Actual process used a forbidden engine clock/render override")
        if expected_arguments is not None and arguments != expected_arguments:
            errors.append("Actual native process arguments differ from the verifier's launch")
        if [argument for argument in arguments[1:] if argument.split("=", 1)[0] == "--mission"] != [f"--mission={expected_mission}"]:
            errors.append("Actual native process mission selector does not match the requested campaign")
    time_scale = report.get("engine_time_scale")
    if time_scale is None:
        time_scale = report.get("time_scale")
    if not number(time_scale) or abs(time_scale - 1.0) > 1e-9:
        errors.append("Engine time scale must remain normal")
    for stage, expected in (("binaries_before", before), ("binaries_after", after)):
        recorded = report.get(stage)
        if not isinstance(recorded, dict):
            errors.append(f"Report lacks {stage}")
            continue
        for key in ("executable", "adjacent_pck"):
            actual = recorded.get(key, {})
            if not isinstance(actual, dict) or actual.get("available") is not True or actual.get("sha256") != expected[key]["sha256"]:
                errors.append(f"Report {stage}/{key} is not the launched payload")
    if before != after:
        errors.append("Native payload changed while the campaign ran")
    loop = report.get("main_loop", {})
    if not isinstance(loop, dict):
        loop = {}
    step, ticks, seconds = (loop.get("fixed_step_seconds"), loop.get("observed_ticks"),
                            loop.get("observed_sim_seconds"))
    if not number(step) or abs(step - 0.05) > 1e-9:
        errors.append("Main loop did not use the original 0.05-second fixed step")
    if not number(ticks) or ticks <= 0 or int(ticks) != ticks:
        errors.append("No positive whole number of actual simulation ticks was observed")
    if not number(seconds) or seconds <= 0:
        errors.append("Actual simulation time did not advance")
    if number(ticks) and number(seconds) and abs(seconds - ticks * 0.05) > 0.00001:
        errors.append("Observed simulation time does not match actual fixed-step tick count")
    if not number(loop.get("invalid_time_steps")) or loop["invalid_time_steps"] != 0:
        errors.append("Main loop recorded an invalid time step")
    startup = report.get("startup_focus", {})
    if not isinstance(startup, dict) or startup.get("ready") is not True:
        errors.append("Native window focus was not ready before the campaign")
    save = report.get("save_reload", {})
    if not isinstance(save, dict) or any(save.get(key) is not True for key in
                                       ("success", "full_simulation_equal", "full_ui_equal", "mission_equal")):
        errors.append("Actual disk save/load simulation, UI and mission equality was not proven")
        save = save if isinstance(save, dict) else {}
    for key, live, saved in (("mission_before", True, False), ("mission_on_disk", False, True),
                             ("mission_after", True, False)):
        errors.extend(mission_identity_errors(save.get(key), expected_mission, f"save/load {key}", live=live, saved=saved))
    errors.extend(mission_identity_errors(report.get("final"), expected_mission, "final simulation", live=True))
    proof = report.get("final_state", {})
    errors.extend(mission_identity_errors(proof, expected_mission, "final saved state", saved=True))
    if not isinstance(proof, dict) or not isinstance(proof.get("sha256"), str) or not SHA256.fullmatch(proof["sha256"]):
        errors.append("Final saved state proof has no valid file hash")
    if final_state is None:
        errors.append("Actual final campaign state was not independently read")
    else:
        try:
            errors.extend(mission_identity_errors(saved_mission_identity(final_state), expected_mission,
                                                  "independently read final state", saved=True))
        except ValueError as error:
            errors.append(str(error))
    if prepare_only:
        if report.get("prepare_complete") is not True:
            errors.append("Prepare-only setup and actual disk continuation did not complete")
        if report.get("complete_campaign_evidence") is not False:
            errors.append("Prepare-only run must not claim a complete campaign")
        return errors
    if report.get("complete_campaign_evidence") is not True:
        errors.append("Native report does not prove a complete campaign")
    route = report.get("route", {})
    if not isinstance(route, dict) or route.get("success") is not True:
        errors.append("Public-command campaign route did not succeed")
    if not isinstance(route, dict) or route.get("mission_id") != expected_mission:
        errors.append("Public-command route mission does not match the requested campaign")
    automatic = report.get("automatic_saves", {})
    if not isinstance(automatic, dict):
        automatic = {}
    for slot in ("primary", "backup"):
        errors.extend(mission_identity_errors(automatic.get(slot), expected_mission,
                                              f"automatic save {slot}", saved=True))
    final = report.get("final", {})
    if not isinstance(final, dict):
        final = {}
    if final.get("outcome") != "victory":
        errors.append("Final simulation outcome is not victory")
    if not number(final.get("exit_progress")) or final["exit_progress"] < 1.0:
        errors.append("Exit construction did not actually complete")
    if final.get("exit_powered") is not True:
        errors.append("Completed exit was not actually powered")
    if not number(final.get("evacuated")) or final["evacuated"] < 4 or int(final["evacuated"]) != final["evacuated"]:
        errors.append("Fewer than four actual survivors were evacuated")
    distance = final.get("truck_distance")
    if not number(distance) or not 0.0 <= distance <= 5.000001:
        errors.append("Actual command truck did not arrive at the exit")
    return errors


def read_progress(path: Path, result: dict[str, Any], started: float) -> bool:
    if not path.is_file():
        return False
    try:
        progress = read_object(path)
        digest = sha256(path)
    except (OSError, ValueError):
        # A writer interrupted between replacement/stat may be observed once;
        # only the final report is acceptance evidence.
        return False
    previous = result.get("progress", {})
    if previous.get("sha256") == digest:
        return False
    result["progress"] = {"path": str(path), "sha256": digest, "latest": progress,
                          "observations": int(previous.get("observations", 0)) + 1,
                          "last_observed_wall_seconds": round(time.monotonic() - started, 3)}
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=PROJECT / "builds/linux-release")
    parser.add_argument("--isolation-root", type=Path, required=True,
                        help="Absolute, absent or completely empty dedicated directory; never deleted")
    parser.add_argument("--max-seconds", type=int, default=900,
                        help="Native validator wall-time limit, 60 through 1800 seconds")
    parser.add_argument("--mission", choices=tuple(MISSION_TAGS), default="canyon",
                        help="Campaign to launch and prove through actual disk continuation (default: canyon)")
    parser.add_argument("--prepare-only", action="store_true",
                        help="Verify native setup/normal-loop progress only; never proves a complete campaign")
    options = parser.parse_args()
    build = options.build_dir.resolve()
    try:
        if not sys.platform.startswith("linux"):
            raise ValueError("This launcher validates the Linux native export only")
        if not 60 <= options.max_seconds <= 1800:
            raise ValueError("--max-seconds must be between 60 and 1800")
        isolation = prepare_isolation(options.isolation_root, build)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    verification = isolation / "verification.json"
    log = isolation / "native-process.log"
    report_path = isolation / "output/campaign-validation.json"
    progress_path = isolation / "output/campaign-progress.json"
    final_state_path = isolation / "output/final-campaign-state.json"
    started = time.monotonic()
    result: dict[str, Any] = {"schema_version": 1, "success": False,
                              "complete_campaign_evidence": False, "performance_evidence": False,
                              "prepare_only": options.prepare_only, "requested_mission_id": options.mission,
                              "started_utc": utc_now(),
                              "build_dir": str(build), "isolation_root": str(isolation),
                              "errors": [], "timed_out": False,
                              "scope": "Native exported game's actual Main loop and public-command campaign route",
                              "not_verified": ["fresh-player usability", "mouse-driven full UI playthrough",
                                               "minimum hardware or frame pacing", "clean-machine installation",
                                               "Windows execution", "Steam integration/review"]}
    write_json(verification, result)
    process: subprocess.Popen[bytes] | None = None
    old_signal = signal.getsignal(signal.SIGTERM)

    def interrupted(_signum: int, _frame: Any) -> None:
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        before = binary_snapshot(build)
        metadata = verify_export_metadata(build, before)
        result.update(binaries_before=before, export_metadata=metadata,
                      source_commit=metadata["source_commit"])
        environment = os.environ.copy()
        environment["CAMPAIGN_VALIDATION_ROOT"] = str(isolation)
        for key, directory in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                               ("XDG_CACHE_HOME", "cache")):
            environment[key] = str(isolation / directory)
        if not environment.get("DISPLAY"):
            raise ValueError("DISPLAY must identify the actual native graphical display")
        command = [str(build / EXECUTABLE_NAME), "--", "--campaign-validation", f"--mission={options.mission}",
                   f"--max-seconds={options.max_seconds}"]
        if options.prepare_only:
            command.append("--prepare-only")
        result.update(argv=command, cwd=str(build), timeout_seconds=options.max_seconds + 20,
                      isolated_environment={key: environment[key] for key in
                                            ("CAMPAIGN_VALIDATION_ROOT", "XDG_DATA_HOME",
                                             "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "DISPLAY")})
        write_json(verification, result)
        with log.open("wb") as output:
            process = subprocess.Popen(command, cwd=build, env=environment, stdin=subprocess.DEVNULL,
                                       stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            result["pid"] = process.pid
            write_json(verification, result)
            deadline = time.monotonic() + options.max_seconds + 20
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    result["timed_out"] = True
                    result["errors"].append("Native campaign process exceeded its wall-time cap")
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
                    break
                if read_progress(progress_path, result, started):
                    write_json(verification, result)
                time.sleep(0.5)
            result["returncode"] = process.wait(timeout=5)
        read_progress(progress_path, result, started)
        after = binary_snapshot(build)
        result["binaries_after"] = after
        if sha256(Path(metadata["path"])) != metadata["sha256"]:
            result["errors"].append("Native export metadata changed during the run")
        plain = ANSI.sub("", log.read_text(encoding="utf-8", errors="replace"))
        result["log"] = {"path": str(log), "bytes": log.stat().st_size, "sha256": sha256(log),
                         "error_or_leak_output": bool(BAD_OUTPUT.search(plain))}
        if result["returncode"] != 0:
            result["errors"].append(f"Native campaign process returned {result['returncode']}")
        if result["log"]["error_or_leak_output"]:
            result["errors"].append("Native process log contains a script error or resource leak")
        report = read_object(report_path)
        result["native_report"] = {"path": str(report_path), "sha256": sha256(report_path),
                                   "data": report}
        final_state = read_object(final_state_path)
        final_digest = sha256(final_state_path)
        result["final_campaign_state"] = {"path": str(final_state_path), "sha256": final_digest}
        if not isinstance(report.get("final_state"), dict) or report["final_state"].get("sha256") != final_digest:
            result["errors"].append("Final state file does not match the native report's proof hash")
        result["errors"].extend(validate_report(report, before, after, options.prepare_only, command,
                                                 options.mission, final_state))
        result["success"] = not result["errors"]
        result["complete_campaign_evidence"] = result["success"] and not options.prepare_only
    except KeyboardInterrupt:
        result["errors"].append("Campaign verification was interrupted; partial data is not accepted")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        result["errors"].append(str(error))
    finally:
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            except ProcessLookupError:
                process.wait(timeout=5)
        signal.signal(signal.SIGTERM, old_signal)
        result["success"] = result["success"] and not result["errors"] and not result["timed_out"]
        result["complete_campaign_evidence"] = result["success"] and not options.prepare_only
        result["finished_utc"] = utc_now()
        result["wall_elapsed_seconds"] = round(time.monotonic() - started, 3)
        write_json(verification, result)
    print(json.dumps({"success": result["success"], "prepare_only": options.prepare_only,
                      "requested_mission_id": options.mission,
                      "complete_campaign_evidence": result["complete_campaign_evidence"],
                      "verification_path": str(verification), "errors": result["errors"]},
                     ensure_ascii=False, indent=2))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
