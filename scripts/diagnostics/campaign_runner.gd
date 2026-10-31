extends Node
## Explicit isolated validation entry, never a player campaign mode.
## Drives the real Main loop with public commands; no manual simulation steps.
const RenderRunner = preload("res://scripts/diagnostics/render_runner.gd")
const CampaignRoute = preload("res://scripts/diagnostics/campaign_route.gd")
const STEP_SECONDS: float = 0.05

var app: Node2D
var failures: Array[String] = []
var finished: bool = false
var report: Dictionary = {}
var checks: int = 0
var output_dir: String = ""
var phase: String = "starting"
var _started_usec: int = 0
var _deadline_usec: int = 0
var _last_progress_usec: int = 0
var _observing: bool = false
var _simulation: RefCounted
var _last_time: float = 0.0
var _last_tick: int = 0
var _frames: int = 0
var _ticks: int = 0
var _raw_ticks: int = 0
var _sim_seconds: float = 0.0
var _invalid_steps: int = 0
var _terminal_noop_ticks: int = 0
var _previous_truck_stage: String = ""
var _previous_origin: int = 0
var _previous_destination: int = 0
var _previous_cargo: float = 0.0
var _previous_transport: bool = false
var _deliveries: Dictionary = {}
var _auto_hash: String = ""
var _auto_changes: int = 0


static func parse_arguments(arguments: PackedStringArray) -> Dictionary:
	var isolation: String = OS.get_environment("CAMPAIGN_VALIDATION_ROOT").simplify_path()
	var result: Dictionary = {"mission": "canyon", "max_seconds": 900, "prepare_only": false, "output_dir": isolation.path_join("output"), "errors": []}
	var seen: Dictionary = {}
	for argument: String in arguments:
		var key: String = argument.get_slice("=", 0)
		if seen.has(key): result.errors.append("duplicate campaign validation argument: " + key)
		seen[key] = true
		if argument == "--campaign-validation": pass
		elif argument == "--prepare-only": result.prepare_only = true
		elif argument.begins_with("--mission="):
			result.mission = argument.trim_prefix("--mission=")
		elif argument.begins_with("--max-seconds="):
			var value: String = argument.trim_prefix("--max-seconds=")
			if not value.is_valid_int() or int(value) < 60 or int(value) > 1800: result.errors.append("campaign validation max-seconds must be60..1800")
			else: result.max_seconds = int(value)
		else: result.errors.append("unsupported or mixed campaign validation argument: " + argument)
	if not seen.has("--campaign-validation"): result.errors.append("--campaign-validation is required")
	if result.mission != "canyon": result.errors.append("this recorded public route supports canyon only")
	if not RenderRunner._filesystem_absolute(result.output_dir) or not RenderRunner._below(result.output_dir, isolation): result.errors.append("output must be a dedicated absolute isolation child")
	return result


static func validate_environment() -> Array[String]:
	var errors: Array[String] = []
	var command_line: Dictionary = engine_arguments()
	if not command_line.available: errors.append("Linux actual process argument proof is unavailable")
	for argument: String in command_line.arguments:
		if argument.get_slice("=", 0) in ["--fixed-fps", "--time-scale", "--disable-render-loop", "--write-movie"]:
			errors.append("campaign verification requires normal real-time engine clock: " + argument.get_slice("=", 0))
	var isolation: String = OS.get_environment("CAMPAIGN_VALIDATION_ROOT").simplify_path()
	if not RenderRunner._filesystem_absolute(isolation) or RenderRunner._has_symlink_component(isolation) or isolation in ["/", OS.get_environment("HOME").simplify_path()]:
		errors.append("CAMPAIGN_VALIDATION_ROOT must be an absolute dedicated filesystem directory")
		return errors
	for variable: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		if not RenderRunner._filesystem_absolute(OS.get_environment(variable)) or not RenderRunner._below(OS.get_environment(variable).simplify_path(), isolation): errors.append(variable + " must be an isolated child")
	if not RenderRunner._below(OS.get_user_data_dir().simplify_path(), isolation): errors.append("user data is outside isolation; refusing player saves/settings")
	for path: String in ["user://settings.cfg", "user://campaign-save.json", "user://campaign-save.json.bak", "user://campaign-autosave.json", "user://campaign-autosave.json.bak"]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)): errors.append("campaign validation requires fresh settings/save paths: " + path)
	for error: String in parse_arguments(OS.get_cmdline_user_args()).errors: errors.append(error)
	return errors


static func engine_arguments() -> Dictionary:
	# Godot strips recognized engine flags from OS.get_cmdline_args(). Proc files
	# report length zero, so read a bounded buffer rather than get_file_as_bytes.
	var arguments: Array[String] = []
	var file: FileAccess = FileAccess.open("/proc/self/cmdline", FileAccess.READ)
	if file == null: return {"available": false, "arguments": arguments, "source": "/proc/self/cmdline"}
	var bytes: PackedByteArray = file.get_buffer(65536)
	file.close()
	var word: PackedByteArray = PackedByteArray()
	for byte: int in bytes:
		if byte == 0:
			arguments.append(word.get_string_from_utf8())
			word.clear()
		else: word.append(byte)
	return {"available": not arguments.is_empty() and word.is_empty() and bytes.size() < 65536,
		"arguments": arguments, "source": "/proc/self/cmdline"}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Main validated isolation before reading settings or constructing a campaign.
	# Do not recheck freshness after Main's legitimate display/config initialization.
	var config: Dictionary = parse_arguments(OS.get_cmdline_user_args())
	output_dir = str(config.output_dir)
	_started_usec = Time.get_ticks_usec()
	_deadline_usec = _started_usec + int(config.max_seconds) * 1000000
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("CAMPAIGN_VALIDATION_REFUSED output directory cannot be created")
		get_tree().quit(2)
		return
	report = {"schema_version": 1, "recorded_utc": Time.get_datetime_string_from_system(true, true) + "Z", "prepare_only": bool(config.prepare_only),
		"native_export_proof": not OS.has_feature("editor"), "complete_campaign_evidence": false, "errors": [], "checks": 0,
		"runtime": Engine.get_version_info(), "display_server": DisplayServer.get_name(), "os": OS.get_name(),
		"engine_command_line": engine_arguments(),
		"time_scale": Engine.time_scale, "max_fps": Engine.max_fps, "user_data_dir": OS.get_user_data_dir(),
		"rendering_method": RenderingServer.get_current_rendering_method(), "gpu_adapter": RenderingServer.get_video_adapter_name(),
		"binaries_before": _binary_hashes(), "sources_before": _source_hashes(), "events": [], "captures": [], "save_reload": {"success": false},
		"route": {"success": false, "not_run": true}, "scope": "Public-command automated Canyon route through actual Main20Hz fixed simulation, renderer and file save/load. No direct simulation step/state injection; standard3x UI speed. Not physical-mouse, human-playability, Windows, clean-machine or FPS evidence."}
	check(config.errors.is_empty(), "validation arguments accepted")
	check(DisplayServer.get_name() != "headless", "complete campaign verification requires actual rendered native window")
	check(is_equal_approx(Engine.time_scale, 1.0), "engine time scale remains normal")
	if failures.is_empty(): report["startup_focus"] = await _settle_focus()
	if not failures.is_empty():
		await _finish()
		return
	app.start_campaign(str(config.mission))
	app.ui_action("speed")
	app.ui_action("speed")
	check(is_equal_approx(app.speed, 3.0), "normal speed controls select3x")
	_simulation = app.sim
	_last_time = float(app.sim.time)
	_last_tick = int(app.tick_count)
	_observing = true
	event("campaign_started", {"mission": str(app.sim.mission_id), "speed": app.speed, "initial_state_sha256": _normalized(app.sim.save_state()).sha256_text()})
	if config.prepare_only:
		await advance(1.0, "prepare-only actual main-loop progress")
		if failures.is_empty(): save_and_reload("prepare-only_initial_state")
		report["prepare_complete"] = failures.is_empty() and _ticks >= 20 and bool(report.save_reload.success)
	else:
		var route: RefCounted = CampaignRoute.new()
		report["route"] = await route.run(app, self)
	await _finish()


func _settle_focus() -> Dictionary:
	var samples: Array = []
	var stable: int = 0
	var start: int = Time.get_ticks_usec()
	for index: int in range(180):
		await RenderingServer.frame_post_draw
		var focused: bool = get_window().has_focus() and not app._window_suspended and get_window().mode != Window.MODE_MINIMIZED
		stable = stable + 1 if focused else 0
		samples.append({"frame": index, "focused": focused, "suspended": app._window_suspended})
		if stable >= 12 or Time.get_ticks_usec() - start > 8000000: break
		if not get_window().has_focus() and index % 30 == 0: get_window().grab_focus()
	check(stable >= 12, "window obtains stable real focus before campaign start")
	return {"ready": stable >= 12, "stable_frames": stable, "required_stable_frames": 12, "elapsed_ms": float(Time.get_ticks_usec() - start) / 1000.0, "samples": samples}


func _process(_delta: float) -> void:
	if finished or _started_usec == 0: return
	if Time.get_ticks_usec() > _deadline_usec:
		check(false, "independent wall-clock deadline exceeded")
		call_deferred("_finish")
		return
	if _observing:
		_frames += 1
		var delta_ticks: int = int(app.tick_count) - _last_tick
		var elapsed: float = float(app.sim.time) - _last_time
		var effective: int = roundi(elapsed / STEP_SECONDS)
		var terminal: bool = app.sim.outcome != "playing"
		if app.sim != _simulation or elapsed < -0.000001 or effective < 0 or absf(elapsed - effective * STEP_SECONDS) > 0.000001 or (not terminal and effective != delta_ticks) or effective > delta_ticks:
			_invalid_steps += 1
			check(false, "normal Main clock or simulation identity changed unexpectedly")
		_ticks += maxi(0, effective)
		_raw_ticks += maxi(0, delta_ticks)
		_sim_seconds += maxf(0.0, elapsed)
		if terminal: _terminal_noop_ticks += maxi(0, delta_ticks - effective)
		_last_time = float(app.sim.time)
		_last_tick = int(app.tick_count)
		_observe_deliveries()
	if Time.get_ticks_usec() - _last_progress_usec > 5000000:
		_last_progress_usec = Time.get_ticks_usec()
		_observe_auto()
		_write_progress()


func healthy() -> bool:
	if finished or not failures.is_empty(): return false
	if not app.started or not app.menu.is_empty() or app._window_suspended or app.sim.paused or app.sim.outcome != "playing" or not app.is_processing():
		check(false, "campaign stopped, paused, lost focus or opened an unexpected menu")
		return false
	if not is_equal_approx(Engine.time_scale, 1.0) or not is_equal_approx(app.speed, 3.0):
		return check(false, "normal engine clock or3x campaign speed changed")
	return true


func advance(seconds: float, label: String) -> bool:
	var target: float = float(app.sim.time) + seconds
	return await wait_for(func() -> bool: return float(app.sim.time) + 0.000001 >= target, seconds + 5.0, label)


func wait_for(condition: Callable, timeout: float, label: String) -> bool:
	phase = label
	var deadline: float = float(app.sim.time) + timeout
	event("wait_started", {"label": label, "simulation_deadline": deadline})
	while not finished and failures.is_empty():
		if bool(condition.call()):
			event("wait_complete", {"label": label})
			return true
		if not healthy(): return false
		if float(app.sim.time) > deadline:
			check(false, "simulation timeout: " + label)
			return false
		await get_tree().process_frame
	return false


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		if not failures.has(label): failures.append(label)
		printerr("CAMPAIGN_VALIDATION_FAILURE ", label)
	return ok


func event(label: String, details: Dictionary = {}) -> void:
	if report.is_empty(): return
	var data: Dictionary = details.duplicate(true)
	data["event"] = label
	data["wall_seconds"] = float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	data["simulation_time"] = float(app.sim.time)
	data["main_tick_count"] = int(app.tick_count)
	report.events.append(data)
	_write_progress()


func deliveries_from(origin: int) -> int:
	return int(_deliveries.get(origin, 0))


func _observe_deliveries() -> void:
	var truck: Dictionary = app.sim.get_unit(int(app.sim.main_truck_id))
	if truck.is_empty(): return
	var stage: String = str(truck.get("haul_stage", ""))
	var cargo: float = 0.0
	for amount: Variant in Dictionary(truck.get("cargo", {})).values(): cargo += float(amount)
	if _previous_transport and _previous_cargo > 0.0 and _previous_truck_stage == "outbound" and stage != "outbound" and cargo <= 0.0:
		# During partial evacuation deliveries camp_id still names the origin.
		# Only the actual parcel destination can confirm this arrival.
		var camp: Dictionary = app.sim.get_camp(_previous_destination)
		if not camp.is_empty() and Vector2(truck.pos).distance_to(Vector2(camp.pos)) <= 2.5:
			_deliveries[_previous_origin] = deliveries_from(_previous_origin) + 1
			event("actual_delivery", {"origin": _previous_origin, "destination": int(camp.id), "count": deliveries_from(_previous_origin)})
	_previous_truck_stage = stage
	_previous_origin = int(truck.get("evac_origin_id", 0))
	_previous_destination = int(truck.get("evac_destination_id", 0))
	_previous_cargo = cargo
	_previous_transport = truck.get("order", "") == "evacuate_transport"


func save_and_reload(label: String) -> bool:
	var before_refresh: String = _normalized(app.sim.save_state())
	# Main refreshes this derived read-only hint on load. Synchronize the saved
	# hint too, so equality does not mistake its0.25second UI cache for lost state.
	app.guide.update(app.sim, app.selected_ids, app.selected_camp)
	if not check(before_refresh == _normalized(app.sim.save_state()), "checkpoint guide refresh leaves full simulation and RNG unchanged"): return false
	var before: Dictionary = app._save_payload()
	var simulation_before: String = _normalized(app.sim.save_state())
	var wrote: bool = app.save_campaign()
	var disk: Dictionary = app.save_store.read(app.SAVE_PATH)
	var disk_valid: bool = bool(disk.get("ok", false)) and app._validate_save_payload(disk.get("data", {}))
	var loaded: bool = app.load_campaign() if wrote and disk_valid else false
	var simulation_equal: bool = loaded and simulation_before == _normalized(app.sim.save_state())
	var ui_equal: bool = loaded and _normalized(before.ui) == _normalized(app._save_payload().ui)
	var result: Dictionary = {"label": label, "write_success": wrote, "disk_schema_valid": disk_valid, "load_success": loaded,
		"read_only_guide_refreshed_before_save": true,
		"full_simulation_equal": simulation_equal, "full_ui_equal": ui_equal, "simulation_sha256": simulation_before.sha256_text(),
		"file_sha256": FileAccess.get_sha256(app.SAVE_PATH) if wrote else "", "simulation_time": float(app.sim.time),
		"success": wrote and disk_valid and loaded and simulation_equal and ui_equal}
	report["save_reload"] = result
	check(bool(result.success), "loaded withdrawal resumes byte-equivalent full simulation/RNG and UI from real disk")
	event("actual_disk_roundtrip", result)
	return bool(result.success)


func capture(label: String, focus_tile: Vector2) -> bool:
	if finished: return false
	# Display camera only; this never moves a simulation entity or changes orders.
	app.camera.position = focus_tile * app.TILE
	app.camera.force_update_scroll()
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	var path: String = output_dir.path_join(label + ".png")
	var ok: bool = frame != null and not frame.is_empty() and frame.save_png(path) == OK
	if ok: report.captures.append({"label": label, "path": path, "sha256": FileAccess.get_sha256(path), "simulation_time": app.sim.time})
	return check(ok, "actual rendered capture: " + label)


func _observe_auto() -> void:
	if FileAccess.file_exists(app.AUTOSAVE_PATH):
		var digest: String = FileAccess.get_sha256(app.AUTOSAVE_PATH)
		if digest != _auto_hash:
			_auto_hash = digest
			_auto_changes += 1


func _write_progress() -> void:
	if output_dir.is_empty() or not is_instance_valid(app) or app.sim == null: return
	_write_json(output_dir.path_join("campaign-progress.json"), {"phase": phase, "simulation_time": app.sim.time, "outcome": app.sim.outcome,
		"wall_seconds": float(Time.get_ticks_usec() - _started_usec) / 1000000.0, "main_tick_count": app.tick_count,
		"observed_ticks": _ticks, "deliveries": _deliveries, "errors": failures, "finished": finished, "last_event": report.get("events", []).back() if not report.get("events", []).is_empty() else {}})


func _slot(path: String) -> Dictionary:
	var read: Dictionary = app.save_store.read(path)
	return {"path": ProjectSettings.globalize_path(path), "exists": FileAccess.file_exists(path), "schema_valid": bool(read.get("ok", false)) and app._validate_save_payload(read.get("data", {})),
		"sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "", "simulation_time": CampaignRoute.serialized_dictionary(read.get("data", {}).get("payload")).get("time", null)}


func _finish() -> void:
	if finished: return
	finished = true
	_observing = false
	app.set_process(false)
	app.set_process_unhandled_input(false)
	_observe_auto()
	var exit_position: Vector2 = Vector2.ZERO
	var exit_powered: bool = false
	for building: Dictionary in app.sim.buildings:
		if int(building.id) == int(app.sim.exit_building_id):
			exit_position = building.pos
			exit_powered = bool(building.get("powered", false)) and float(building.get("progress", 0.0)) >= 1.0 and float(building.get("hp", 0.0)) > 0.0
	var truck: Dictionary = app.sim.get_unit(int(app.sim.main_truck_id))
	report["final"] = {"outcome": app.sim.outcome, "exit_progress": app.sim.exit_progress, "exit_powered": exit_powered, "evacuated": app.sim.evacuated,
		"truck_distance": Vector2(truck.get("pos", Vector2(-999, -999))).distance_to(exit_position), "truck_state": truck.get("state", "missing"), "summary": app.sim.get_summary()}
	report["main_loop"] = {"fixed_step_seconds": STEP_SECONDS, "observed_frames": _frames, "observed_ticks": _ticks, "raw_main_ticks": _raw_ticks,
		"observed_sim_seconds": _sim_seconds, "invalid_time_steps": _invalid_steps, "terminal_noop_ticks": _terminal_noop_ticks}
	report["automatic_saves"] = {"observed_file_changes": _auto_changes, "primary": _slot(app.AUTOSAVE_PATH), "backup": _slot(app.AUTOSAVE_PATH + ".bak")}
	report["binaries_after"] = _binary_hashes()
	report["sources_after"] = _source_hashes()
	report["binaries_changed"] = report.binaries_before != report.binaries_after
	report["sources_changed"] = report.sources_before != report.sources_after
	check(not report.binaries_changed and not report.sources_changed, "campaign payload and source stay unchanged for entire run")
	check(_ticks > 0 and _invalid_steps == 0 and absf(_sim_seconds - _ticks * STEP_SECONDS) < 0.00001, "actual normal Main fixed-step clock is coherent")
	var full: bool = not report.prepare_only
	if full:
		check(bool(report.route.get("success", false)) and bool(report.save_reload.get("success", false)), "full route and loaded withdrawal completed")
		check(app.sim.outcome == "victory" and app.sim.evacuated >= 4 and app.sim.exit_progress >= 1.0 and exit_powered and float(report.final.truck_distance) <= 5.0, "truthful powered exit and truck/survivor victory")
		check(_auto_changes >= 2 and report.automatic_saves.primary.schema_valid and report.automatic_saves.backup.schema_valid, "actual long campaign rotates valid automatic saves")
	report["checks"] = checks
	report["errors"] = failures.duplicate()
	report["wall_elapsed_seconds"] = float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	report["complete_campaign_evidence"] = full and report.native_export_proof and failures.is_empty()
	_write_json(output_dir.path_join("final-campaign-state.json"), app._save_payload())
	_write_json(output_dir.path_join("campaign-validation.json"), report)
	_write_progress()
	print("CAMPAIGN_VALIDATION_REPORT ", output_dir.path_join("campaign-validation.json"), " complete=", report.complete_campaign_evidence, " errors=", failures.size())
	await app._quit_cleanly(0 if failures.is_empty() else 1)


func _binary_hashes() -> Dictionary:
	var helper: Node = RenderRunner.new()
	var result: Dictionary = helper._binary_hashes()
	helper.free()
	return result


func _source_hashes() -> Dictionary:
	var helper: Node = RenderRunner.new()
	var result: Dictionary = helper._source_hashes()
	helper.free()
	return result


func _normalized(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _write_json(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		check(false, "cannot write diagnostic evidence: " + path)
		return
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: check(false, "cannot replace diagnostic evidence: " + path)
