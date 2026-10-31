#!/usr/bin/env python3
"""Launcher proof-boundary regressions; subprocesses and displays are mocked."""
from __future__ import annotations

from copy import deepcopy
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

if __package__:
    from . import run_native_campaign as launcher
else:
    import run_native_campaign as launcher


def live_identity(mission: str) -> dict:
    return {"mission_id": mission, "mission_tag": launcher.MISSION_TAGS[mission],
            "selected_mission_id": mission}


def disk_identity(mission: str) -> dict:
    return {"mission_id": mission, "mission_tag": launcher.MISSION_TAGS[mission],
            "payload_mission_id": "" if mission == "canyon" else mission}


def fixture(mission: str, prepare: bool = False, executable: str = "/fixture/outpost-exodus.x86_64") -> tuple:
    binaries = {"executable": {"path": executable, "available": True, "sha256": "a" * 64},
                "adjacent_pck": {"path": "/fixture/outpost-exodus.pck", "available": True, "sha256": "b" * 64}}
    arguments = [executable, "--", "--campaign-validation", f"--mission={mission}", "--max-seconds=900"]
    if prepare:
        arguments.append("--prepare-only")
    final_state = {"version": 1, "mission": launcher.MISSION_TAGS[mission],
                   "payload": {"$type": "Dictionary", "entries": [["time", 1.0]]}}
    if mission != "canyon":
        final_state["payload"]["entries"].append(["mission_id", mission])
    report = {
        "requested_mission_id": mission, "campaign_start": live_identity(mission),
        "native_export_proof": True, "prepare_only": prepare, "prepare_complete": prepare,
        "complete_campaign_evidence": not prepare, "errors": [], "display_server": "x11",
        "engine_command_line": {"available": True, "source": "/proc/self/cmdline", "arguments": arguments},
        "engine_time_scale": 1.0, "binaries_before": deepcopy(binaries), "binaries_after": deepcopy(binaries),
        "main_loop": {"fixed_step_seconds": 0.05, "observed_ticks": 20, "observed_sim_seconds": 1.0,
                      "invalid_time_steps": 0},
        "startup_focus": {"ready": True},
        "save_reload": {"success": True, "full_simulation_equal": True, "full_ui_equal": True,
                        "mission_equal": True, "mission_before": live_identity(mission),
                        "mission_on_disk": disk_identity(mission), "mission_after": live_identity(mission)},
        "route": {"success": not prepare, "mission_id": mission},
        "automatic_saves": {"primary": disk_identity(mission), "backup": disk_identity(mission)},
        "final": {**live_identity(mission), "outcome": "playing" if prepare else "victory",
                  "exit_progress": 0.0 if prepare else 1.0, "exit_powered": not prepare,
                  "evacuated": 0 if prepare else 4, "truck_distance": 99.0 if prepare else 1.0},
        "final_state": {**disk_identity(mission), "sha256": "c" * 64},
    }
    return report, binaries, final_state


def validate(report: dict, binaries: dict, state: dict, mission: str, prepare: bool = False) -> list[str]:
    return launcher.validate_report(report, binaries, deepcopy(binaries), prepare,
                                    expected_mission=mission, final_state=state)


class ReportProofTests(unittest.TestCase):
    def test_all_missions_and_modes_retain_strict_proofs(self):
        for mission in launcher.MISSION_TAGS:
            for prepare in (False, True):
                with self.subTest(mission=mission, prepare=prepare):
                    report, binaries, state = fixture(mission, prepare)
                    self.assertEqual(validate(report, binaries, state, mission, prepare), [])

    def test_every_live_disk_route_and_final_identity_is_checked(self):
        paths = [("campaign_start",), ("save_reload", "mission_before"),
                 ("save_reload", "mission_on_disk"), ("save_reload", "mission_after"),
                 ("route",), ("final",), ("final_state",),
                 ("automatic_saves", "primary"), ("automatic_saves", "backup")]
        for mission in launcher.MISSION_TAGS:
            for path in paths:
                with self.subTest(mission=mission, path=path):
                    report, binaries, state = fixture(mission)
                    identity = report
                    for key in path:
                        identity = identity[key]
                    identity["mission_id"] = "delta" if mission != "delta" else "canyon"
                    self.assertTrue(validate(report, binaries, state, mission))
        report, binaries, state = fixture("ridge")
        report["requested_mission_id"] = "canyon"
        self.assertTrue(validate(report, binaries, state, "ridge"))

    def test_actual_process_selector_and_selected_controller_identity_are_required(self):
        for selector in (["--mission=canyon"], [], ["--mission=ridge", "--mission=ridge"]):
            report, binaries, state = fixture("ridge")
            report["engine_command_line"]["arguments"] = [binaries["executable"]["path"], "--", *selector]
            self.assertTrue(validate(report, binaries, state, "ridge"))
        report, binaries, state = fixture("delta")
        report["campaign_start"]["selected_mission_id"] = "canyon"
        self.assertTrue(validate(report, binaries, state, "delta"))

    def test_independent_final_file_identity_cannot_be_replaced_by_report_claim(self):
        for mutation in ("outer_tag", "inner_id", "missing_inner_id", "duplicate_inner_id", "malformed_entries"):
            with self.subTest(mutation=mutation):
                report, binaries, state = fixture("delta")
                if mutation == "outer_tag": state["mission"] = launcher.MISSION_TAGS["ridge"]
                elif mutation == "inner_id": state["payload"]["entries"][-1][1] = "ridge"
                elif mutation == "missing_inner_id": state["payload"]["entries"].pop()
                elif mutation == "duplicate_inner_id": state["payload"]["entries"].append(["mission_id", "delta"])
                else: state["payload"]["entries"] = ["mission_id"]
                self.assertTrue(validate(report, binaries, state, "delta"))
        report, binaries, _state = fixture("canyon")
        self.assertTrue(launcher.validate_report(report, binaries, binaries, False))

    def test_prepare_only_never_substitutes_for_a_complete_campaign(self):
        report, binaries, state = fixture("ridge", True)
        self.assertTrue(validate(report, binaries, state, "ridge", False))
        report["complete_campaign_evidence"] = True
        self.assertTrue(validate(report, binaries, state, "ridge", True))
        report["complete_campaign_evidence"] = False
        report["prepare_complete"] = False
        self.assertTrue(validate(report, binaries, state, "ridge", True))
        report["prepare_complete"] = True
        report["save_reload"]["mission_equal"] = False
        self.assertTrue(validate(report, binaries, state, "ridge", True))

    def test_existing_clock_native_state_and_victory_gates_are_not_weakened(self):
        mutations = [
            lambda r: r.update(native_export_proof=False),
            lambda r: r.update(display_server="headless"),
            lambda r: r.update(engine_time_scale=3.0),
            lambda r: r["engine_command_line"]["arguments"].append("--fixed-fps=60"),
            lambda r: r["main_loop"].update(fixed_step_seconds=0.1),
            lambda r: r["main_loop"].update(observed_sim_seconds=1.1),
            lambda r: r["main_loop"].update(invalid_time_steps=1),
            lambda r: r["save_reload"].update(full_simulation_equal=False),
            lambda r: r["save_reload"].update(full_ui_equal=False),
            lambda r: r["route"].update(success=False),
            lambda r: r["final"].update(outcome="playing"),
            lambda r: r["final"].update(exit_powered=False),
            lambda r: r["final"].update(exit_progress=0.5),
            lambda r: r["final"].update(evacuated=3),
            lambda r: r["final"].update(truck_distance=6.0),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(gate=index):
                report, binaries, state = fixture("delta")
                mutate(report)
                self.assertTrue(validate(report, binaries, state, "delta"))


class LaunchTests(unittest.TestCase):
    def _run_launcher(self, mission: str | None, *, prepare: bool = False, corrupt_final: bool = False) -> tuple:
        selected_mission = mission or "canyon"
        with tempfile.TemporaryDirectory(prefix="native-campaign-launch-test-") as temporary:
            root = Path(temporary)
            build = root / "build"
            build.mkdir()
            for name in (launcher.EXECUTABLE_NAME, launcher.PACK_NAME):
                (build / name).write_bytes(b"test payload; never executed")
            (build / launcher.EXECUTABLE_NAME).chmod(0o755)
            hashes = {name: launcher.sha256(build / name) for name in (launcher.EXECUTABLE_NAME, launcher.PACK_NAME)}
            launcher.write_json(build / "export-source.json", {"source_commit": "1" * 40, "sha256": hashes})
            isolation = root / "isolation"
            arguments = ["run_native_campaign.py", "--build-dir", str(build), "--isolation-root", str(isolation)]
            if mission is not None:
                arguments.extend(("--mission", mission))
            if prepare:
                arguments.append("--prepare-only")
            captured: dict = {}

            def fake_process(command, **kwargs):
                captured.update(command=command, **kwargs)
                report, _binaries, state = fixture(selected_mission, prepare, str(build / launcher.EXECUTABLE_NAME))
                report["binaries_before"] = launcher.binary_snapshot(build)
                report["binaries_after"] = launcher.binary_snapshot(build)
                report["engine_command_line"]["arguments"] = list(command)
                output = isolation / "output"
                output.mkdir()
                final_path = output / "final-campaign-state.json"
                launcher.write_json(final_path, state)
                report["final_state"]["sha256"] = launcher.sha256(final_path)
                if corrupt_final:
                    state["mission"] = launcher.MISSION_TAGS["canyon" if selected_mission != "canyon" else "delta"]
                    launcher.write_json(final_path, state)
                launcher.write_json(output / "campaign-validation.json", report)
                return SimpleNamespace(pid=123456, poll=lambda: 0, wait=lambda **_kwargs: 0)

            with patch.object(launcher.sys, "argv", arguments), patch.dict(launcher.os.environ, {"DISPLAY": ":mock"}), \
                    patch.object(launcher.subprocess, "Popen", side_effect=fake_process) as process, \
                    redirect_stdout(io.StringIO()):
                status = launcher.main()
            process.assert_called_once()
            result = json.loads((isolation / "verification.json").read_text())
            for key in ("CAMPAIGN_VALIDATION_ROOT", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                self.assertTrue(Path(captured["env"][key]).is_relative_to(isolation))
            self.assertTrue(captured["start_new_session"])
            return status, result, captured["command"]

    def test_selected_mission_reaches_exact_launch_and_verification_record(self):
        for mission in launcher.MISSION_TAGS:
            for prepare in (False, True):
                with self.subTest(mission=mission, prepare=prepare):
                    status, result, command = self._run_launcher(mission, prepare=prepare)
                    self.assertEqual(status, 0, result["errors"])
                    self.assertEqual([value for value in command if value.startswith("--mission=")], [f"--mission={mission}"])
                    self.assertEqual(result["requested_mission_id"], mission)
                    self.assertEqual(result["complete_campaign_evidence"], not prepare)
                    self.assertFalse(result["performance_evidence"])

    def test_modified_final_proof_file_is_rejected(self):
        status, result, _command = self._run_launcher("ridge", corrupt_final=True)
        self.assertEqual(status, 1)
        self.assertFalse(result["complete_campaign_evidence"])
        self.assertTrue(any("proof hash" in error for error in result["errors"]))
        self.assertTrue(any("independently read final state" in error for error in result["errors"]))

    def test_default_launch_remains_canyon(self):
        status, result, command = self._run_launcher(None)
        self.assertEqual(status, 0, result["errors"])
        self.assertEqual(result["requested_mission_id"], "canyon")
        self.assertIn("--mission=canyon", command)

    def test_unknown_mission_is_rejected_before_creating_isolation_or_launching(self):
        with tempfile.TemporaryDirectory() as temporary:
            isolation = Path(temporary) / "untouched"
            with patch.object(launcher.sys, "argv", ["run_native_campaign.py", "--isolation-root", str(isolation), "--mission", "unknown"]), \
                    patch.object(launcher.subprocess, "Popen") as process, redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as stopped:
                    launcher.main()
            self.assertEqual(stopped.exception.code, 2)
            self.assertFalse(isolation.exists())
            process.assert_not_called()


if __name__ == "__main__":
    unittest.main()
