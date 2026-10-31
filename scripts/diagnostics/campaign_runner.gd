extends Node
## Explicit isolated validation entry, never a player campaign mode.
## Drives the real Main loop with public commands; no manual simulation steps.
const RenderRunner = preload("res://scripts/diagnostics/render_runner.gd")
const CampaignRoute = preload("res://scripts/diagnostics/campaign_route.gd")
const Simulation = preload("res://scripts/campaign_simulation.gd")
const STEP_SECONDS: float = 0.05
const SOAK_CYCLES: int = 7
const SOAK_MINIMUM_WALL_SECONDS: int = 3600
const SOAK_RESOLUTION: Vector2i = Vector2i(1920, 1080)
const SOAK_UI_SCALE: float = 1.0

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
var _requested_mission_id: String = "canyon"
var _soak_mode: bool = false
var _root_output_dir: String = ""
var _starting_mission_id: String = "canyon"
var _soak_report: Dictionary = {}
var _cycle_index: int = 0
var _cycle_started_usec: int = 0
var _cycle_start_tick: int = 0
var _cycle_checks_start: int = 0
var _cycle_sealed: bool = false


static func parse_arguments(arguments: PackedStringArray) -> Dictionary:
	var isolation: String = OS.get_environment("CAMPAIGN_VALIDATION_ROOT").simplify_path()
	var result: Dictionary = {"mission": "canyon", "max_seconds": 900, "prepare_only": false, "soak": false, "output_dir": isolation.path_join("output"), "errors": []}
	var seen: Dictionary = {}
	for argument: String in arguments:
		var key: String = argument.get_slice("=", 0)
		if seen.has(key): result.errors.append("duplicate campaign validation argument: " + key)
		seen[key] = true
		if argument == "--campaign-validation": pass
		elif argument == "--prepare-only": result.prepare_only = true
		elif argument == "--soak": result.soak = true
		elif argument.begins_with("--mission="):
			result.mission = argument.trim_prefix("--mission=")
		elif argument.begins_with("--max-seconds="):
			var value: String = argument.trim_prefix("--max-seconds=")
			if not value.is_valid_int(): result.errors.append("campaign validation max-seconds must be a whole number")
			else: result.max_seconds = int(value)
		else: result.errors.append("unsupported or mixed campaign validation argument: " + argument)
	if not seen.has("--campaign-validation"): result.errors.append("--campaign-validation is required")
	if result.soak and result.prepare_only: result.errors.append("soak and prepare-only modes cannot be combined")
	if result.soak and not seen.has("--max-seconds"): result.max_seconds = 5400
	if result.soak:
		if int(result.max_seconds) < 3600 or int(result.max_seconds) > 7200: result.errors.append("soak max-seconds must be3600..7200")
	elif int(result.max_seconds) < 60 or int(result.max_seconds) > 1800: result.errors.append("campaign validation max-seconds must be60..1800")
	if not Simulation.MISSION_SAVE_TAGS.has(result.mission): result.errors.append("campaign validation mission must be canyon, delta or ridge")
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
	# Freshness is validated once by Main, before settings or a campaign exist.
	var config: Dictionary = parse_arguments(OS.get_cmdline_user_args())
	_starting_mission_id = str(config.mission)
	_requested_mission_id = _starting_mission_id
	_soak_mode = bool(config.soak)
	_root_output_dir = str(config.output_dir)
	output_dir = _root_output_dir
	_started_usec = Time.get_ticks_usec()
	_deadline_usec = _started_usec + int(config.max_seconds) * 1000000
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("CAMPAIGN_VALIDATION_REFUSED output directory cannot be created")
		get_tree().quit(2)
		return
	if _soak_mode:
		await _run_soak(config)
		return
	_reset_cycle_observer()
	report = _new_cycle_report(config)
	check(config.errors.is_empty(), "validation arguments accepted")
	check(DisplayServer.get_name() != "headless", "complete campaign verification requires actual rendered native window")
	check(is_equal_approx(Engine.time_scale, 1.0), "engine time scale remains normal")
	if failures.is_empty(): report["startup_focus"] = await _settle_focus()
	if not failures.is_empty():
		await _finish()
		return
	app.start_campaign(_requested_mission_id)
	if not _begin_campaign_observation():
		await _finish()
		return
	if config.prepare_only:
		await advance(1.0, "prepare-only actual main-loop progress")
		if failures.is_empty(): save_and_reload("prepare-only_initial_state")
		report["prepare_complete"] = failures.is_empty() and _ticks >= 20 and bool(report.save_reload.success)
	else:
		var route: RefCounted = CampaignRoute.new()
		report["route"] = await route.run(app, self)
	await _finish()


func _new_cycle_report(config: Dictionary) -> Dictionary:
	return {"schema_version": 1, "recorded_utc": Time.get_datetime_string_from_system(true, true) + "Z", "prepare_only": bool(config.prepare_only), "soak_mode": _soak_mode, "requested_mission_id": _requested_mission_id,
		"native_export_proof": not OS.has_feature("editor"), "complete_campaign_evidence": false, "errors": [], "checks": 0,
		"process_id": OS.get_process_id(), "main_instance_id": str(app.get_instance_id()), "simulation_instance_id": str(app.sim.get_instance_id()), "cycle_index": _cycle_index,
		"runtime": Engine.get_version_info(), "display_server": DisplayServer.get_name(), "os": OS.get_name(),
		"engine_command_line": engine_arguments(),
		"time_scale": Engine.time_scale, "max_fps": Engine.max_fps, "user_data_dir": OS.get_user_data_dir(),
		"rendering_method": RenderingServer.get_current_rendering_method(), "gpu_adapter": RenderingServer.get_video_adapter_name(),
		"binaries_before": _binary_hashes(), "sources_before": _source_hashes(), "events": [], "captures": [], "save_reload": {"success": false},
		"route": {"success": false, "not_run": true}, "scope": "Public-command automated selected campaign route through actual Main20Hz fixed simulation, renderer and file save/load. No direct simulation step/state injection; standard3x UI speed. Not physical-mouse, human-playability, Windows, clean-machine or FPS evidence."}


static func soak_missions(starting_mission: String) -> Array[String]:
	var order: Array[String] = ["canyon", "delta", "ridge"]
	var result: Array[String] = []
	var start: int = order.find(starting_mission)
	if start < 0: return result
	for index: int in range(SOAK_CYCLES): result.append(order[(start + index) % order.size()])
	return result


func configure_soak_display() -> void:
	# UI settings only. A caller may apply this before rendering its first frame,
	# then inspect soak_display_snapshot after actual rendered frames settle.
	app.fullscreen = false
	app.window_resolution = SOAK_RESOLUTION
	app.display_configured = true
	app.ui_scale = SOAK_UI_SCALE
	app._apply_display_settings()
	app._save_settings()


func soak_display_snapshot(captured_image_size: Vector2i = Vector2i.ZERO) -> Dictionary:
	var window: Window = app.get_window()
	var viewport: Viewport = app.get_viewport()
	var texture: ViewportTexture = viewport.get_texture()
	var reported: Vector2i = Vector2i(texture.get_size())
	# ViewportTexture size metadata may retain a content-scale multiplier even
	# when the actual rendered image is the requested size. Gate on image pixels.
	var pixels: Vector2i = captured_image_size
	if pixels == Vector2i.ZERO:
		var rendered: Image = texture.get_image()
		if rendered != null and not rendered.is_empty(): pixels = rendered.get_size()
	var visible: Vector2i = Vector2i(viewport.get_visible_rect().size)
	var ready: bool = window.size == SOAK_RESOLUTION and pixels == SOAK_RESOLUTION and is_equal_approx(app.ui_scale, SOAK_UI_SCALE) and is_equal_approx(window.content_scale_factor, SOAK_UI_SCALE) and window.mode == Window.MODE_WINDOWED
	return {"requested_client_size": [SOAK_RESOLUTION.x, SOAK_RESOLUTION.y], "requested_ui_scale": SOAK_UI_SCALE,
		"client_size": [window.size.x, window.size.y], "viewport_pixel_size": [pixels.x, pixels.y], "viewport_visible_size": [visible.x, visible.y],
		"viewport_pixel_size_source": "viewport_texture_get_image", "texture_reported_size": [reported.x, reported.y],
		"ui_scale": app.ui_scale, "window_content_scale_factor": window.content_scale_factor, "windowed": window.mode == Window.MODE_WINDOWED, "ready": ready}


func _reset_cycle_observer() -> void:
	_observing = false
	report = {}
	_cycle_sealed = false
	_cycle_started_usec = Time.get_ticks_usec()
	_cycle_checks_start = checks
	_frames = 0
	_ticks = 0
	_raw_ticks = 0
	_sim_seconds = 0.0
	_invalid_steps = 0
	_terminal_noop_ticks = 0
	_previous_truck_stage = ""
	_previous_origin = 0
	_previous_destination = 0
	_previous_cargo = 0.0
	_previous_transport = false
	_deliveries.clear()
	_auto_changes = 0


func _begin_campaign_observation() -> bool:
	report["campaign_start"] = _live_mission_identity()
	if not check(app.started and app.menu.is_empty() and app.sim.outcome == "playing" and is_zero_approx(float(app.sim.time)) and _mission_matches(report.campaign_start, true), "requested mission starts fresh with matching live, selected and saved identities"): return false
	app.ui_action("speed")
	app.ui_action("speed")
	if not check(is_equal_approx(app.speed, 3.0), "normal speed controls select3x"): return false
	_simulation = app.sim
	_last_time = float(app.sim.time)
	_last_tick = int(app.tick_count)
	_cycle_start_tick = _last_tick
	_auto_changes = 0
	_auto_hash = FileAccess.get_sha256(app.AUTOSAVE_PATH) if FileAccess.file_exists(app.AUTOSAVE_PATH) else ""
	_observing = true
	report["cycle_start_wall_seconds"] = float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	event("campaign_started", {"mission": str(app.sim.mission_id), "mission_tag": report.campaign_start.mission_tag, "speed": app.speed, "initial_state_sha256": _normalized(app.sim.save_state()).sha256_text()})
	return true


func _run_soak(config: Dictionary) -> void:
	_soak_report = {"schema_version": 1, "soak_mode": true, "prepare_only": false, "requested_mission_id": _starting_mission_id,
		"recorded_utc": Time.get_datetime_string_from_system(true, true) + "Z", "cycle_count_required": SOAK_CYCLES,
		"minimum_wall_seconds": SOAK_MINIMUM_WALL_SECONDS, "planned_missions": soak_missions(_starting_mission_id),
		"native_export_proof": not OS.has_feature("editor"), "one_hour_soak_evidence": false, "complete_campaign_evidence": false,
		"process_id": OS.get_process_id(), "main_instance_id": str(app.get_instance_id()), "simulation_instance_id": str(app.sim.get_instance_id()),
		"world_instance_id": str(app.world.get_instance_id()), "hud_instance_id": str(app.hud.get_instance_id()), "audio_instance_id": str(app.game_audio.get_instance_id()), "music_instance_id": str(app.music_player.get_instance_id()),
		"engine_command_line": engine_arguments(), "binaries_before": _binary_hashes(), "sources_before": _source_hashes(),
		"cycles": [], "transitions": [], "stability_samples": [],
		"stability_scope": "Named measurements after the first complete route warms this same Main process. Memory/node/audio observations and bounded voice pools are recorded; this is not minimum-hardware, frame-pacing, human listening or universal no-leak proof."}
	configure_soak_display()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_soak_report["startup_display"] = soak_display_snapshot()
	if not check(_soak_report.startup_display.ready, "soak reaches actual1920x1080 client and rendered viewport at UI scale1 before initial focus"):
		await _finish()
		return
	for index: int in range(SOAK_CYCLES):
		if finished: return
		_cycle_index = index + 1
		_requested_mission_id = str(_soak_report.planned_missions[index])
		output_dir = _root_output_dir.path_join("cycle-%02d-%s" % [_cycle_index, _requested_mission_id])
		_reset_cycle_observer()
		if not check(DirAccess.make_dir_recursive_absolute(output_dir) == OK, "cycle has its own immutable evidence directory"): break
		report = _new_cycle_report(config)
		check(config.errors.is_empty(), "validation arguments accepted")
		check(DisplayServer.get_name() != "headless", "complete campaign verification requires actual rendered native window")
		check(is_equal_approx(Engine.time_scale, 1.0), "engine time scale remains normal")
		if failures.is_empty(): report["startup_focus"] = await _settle_focus()
		if not failures.is_empty(): break
		if index == 0:
			app.start_campaign(_requested_mission_id)
		else:
			if not await _restart_through_title(_requested_mission_id): break
		if not _begin_campaign_observation(): break
		var route: RefCounted = CampaignRoute.new()
		report["route"] = await route.run(app, self)
		if finished: return
		_seal_cycle()
		if not failures.is_empty(): break
	await _finish()


func _restart_through_title(mission: String) -> bool:
	var transition: Dictionary = {"from_cycle": _cycle_index - 1, "to_cycle": _cycle_index, "mission_id": mission,
		"process_id": OS.get_process_id(), "main_instance_id": str(app.get_instance_id()), "actions": [],
		"start_main_tick_count": int(app.tick_count), "started_wall_seconds": float(Time.get_ticks_usec() - _started_usec) / 1000000.0}
	app.ui_action("title")
	transition.actions.append("title")
	transition["title_ready"] = not app.started and app.menu == "title"
	if not check(transition.title_ready, "completed campaign returns through the real title action"): return false
	await RenderingServer.frame_post_draw
	if finished: return false
	app.ui_action("campaigns")
	transition.actions.append("campaigns")
	transition["campaign_selector_ready"] = app.menu == "campaigns"
	app.ui_action("campaign:" + mission)
	transition.actions.append("campaign:" + mission)
	transition["selected_start_ready"] = app.started and app.menu.is_empty() and str(app.sim.mission_id) == mission and is_zero_approx(float(app.sim.time))
	app.ui_action("new")
	transition.actions.append("new")
	transition["restart_confirmation_ready"] = app.menu == "restart" and str(app.pending_mission_id) == mission
	app.ui_action("restart_confirm")
	transition.actions.append("restart_confirm")
	transition["restart_ready"] = app.started and app.menu.is_empty() and str(app.sim.mission_id) == mission and is_zero_approx(float(app.sim.time)) and app.sim.outcome == "playing"
	transition["restart_autosave"] = _slot(app.AUTOSAVE_PATH, "restart-autosave.json")
	transition["end_main_tick_count"] = int(app.tick_count)
	transition["ended_wall_seconds"] = float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	transition["success"] = transition.title_ready and transition.campaign_selector_ready and transition.selected_start_ready and transition.restart_confirmation_ready and transition.restart_ready and transition.restart_autosave.schema_valid and _mission_matches(transition.restart_autosave, false, true)
	_soak_report.transitions.append(transition)
	return check(bool(transition.success), "title, campaign selection and confirmed restart reuse the same live Main and valid real autosave")


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
		_observe_main_clock()
	if Time.get_ticks_usec() - _last_progress_usec > 5000000:
		_last_progress_usec = Time.get_ticks_usec()
		_observe_auto()
		_write_progress()


func _observe_main_clock() -> void:
	if not _observing: return
	if str(app.sim.mission_id) != _requested_mission_id or str(app.selected_mission_id) != _requested_mission_id:
		check(false, "requested campaign identity remains unchanged during normal Main processing")
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
	var mission_before: Dictionary = _live_mission_identity()
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
	var mission_on_disk: Dictionary = _saved_mission_identity(disk.get("data", {}))
	var loaded: bool = app.load_campaign() if wrote and disk_valid else false
	var mission_after: Dictionary = _live_mission_identity()
	var mission_equal: bool = _mission_matches(mission_before, true) and _mission_matches(mission_on_disk, false, true) and _mission_matches(mission_after, true)
	var simulation_equal: bool = loaded and simulation_before == _normalized(app.sim.save_state())
	var ui_equal: bool = loaded and _normalized(before.ui) == _normalized(app._save_payload().ui)
	var result: Dictionary = {"label": label, "write_success": wrote, "disk_schema_valid": disk_valid, "load_success": loaded,
		"mission_before": mission_before, "mission_on_disk": mission_on_disk, "mission_after": mission_after, "mission_equal": mission_equal,
		"read_only_guide_refreshed_before_save": true,
		"full_simulation_equal": simulation_equal, "full_ui_equal": ui_equal, "simulation_sha256": simulation_before.sha256_text(),
		"file_sha256": FileAccess.get_sha256(app.SAVE_PATH) if wrote else "", "simulation_time": float(app.sim.time),
		"success": wrote and disk_valid and loaded and simulation_equal and ui_equal and mission_equal}
	if _soak_mode and wrote:
		result.merge(_retain_file(app.SAVE_PATH, "checkpoint-save.json"))
	report["save_reload"] = result
	check(bool(result.success), "loaded checkpoint resumes byte-equivalent full simulation/RNG, UI and mission from real disk")
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
	if ok:
		var record: Dictionary = {"label": label, "path": path, "sha256": FileAccess.get_sha256(path), "simulation_time": app.sim.time}
		if _soak_mode:
			record["display"] = soak_display_snapshot(frame.get_size())
			record["image_pixel_size"] = [frame.get_width(), frame.get_height()]
			ok = check(record.display.ready and frame.get_size() == SOAK_RESOLUTION, "soak capture retains actual1920x1080 rendered pixels at UI scale1: " + label)
		report.captures.append(record)
	return check(ok, "actual rendered capture: " + label)


func _observe_auto() -> void:
	if FileAccess.file_exists(app.AUTOSAVE_PATH):
		var digest: String = FileAccess.get_sha256(app.AUTOSAVE_PATH)
		if digest != _auto_hash:
			_auto_hash = digest
			_auto_changes += 1


func _write_progress() -> void:
	if output_dir.is_empty() or not is_instance_valid(app) or app.sim == null: return
	var progress_root: String = _root_output_dir if _soak_mode else output_dir
	_write_json(progress_root.path_join("campaign-progress.json"), {"phase": phase, "simulation_time": app.sim.time, "outcome": app.sim.outcome,
		"soak_mode": _soak_mode, "cycle_index": _cycle_index, "cycles_completed": _soak_report.get("cycles", []).size(), "starting_mission_id": _starting_mission_id,
		"requested_mission_id": _requested_mission_id, "mission_id": str(app.sim.mission_id),
		"wall_seconds": float(Time.get_ticks_usec() - _started_usec) / 1000000.0, "main_tick_count": app.tick_count,
		"observed_ticks": _ticks, "deliveries": _deliveries, "errors": failures, "finished": finished, "last_event": report.get("events", []).back() if not report.get("events", []).is_empty() else {}})


func _slot(path: String, retained_name: String = "") -> Dictionary:
	var read: Dictionary = app.save_store.read(path)
	var identity: Dictionary = _saved_mission_identity(read.get("data", {}))
	identity.merge({"path": ProjectSettings.globalize_path(path), "exists": FileAccess.file_exists(path), "schema_valid": bool(read.get("ok", false)) and app._validate_save_payload(read.get("data", {})),
		"sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "", "simulation_time": CampaignRoute.serialized_dictionary(read.get("data", {}).get("payload")).get("time", null)})
	if _soak_mode and not retained_name.is_empty() and FileAccess.file_exists(path): identity.merge(_retain_file(path, retained_name))
	return identity


func _retain_file(source: String, name: String) -> Dictionary:
	var destination: String = output_dir.path_join(name)
	var data: PackedByteArray = FileAccess.get_file_as_bytes(source)
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if not check(file != null and not data.is_empty(), "retain actual save bytes for independent cycle verification: " + name): return {}
	file.store_buffer(data)
	file.close()
	var digest: String = FileAccess.get_sha256(destination)
	check(digest == FileAccess.get_sha256(source), "retained cycle save matches original disk bytes: " + name)
	return {"retained_path": destination, "retained_sha256": digest}


func _saved_mission_identity(state: Dictionary) -> Dictionary:
	var tag: String = str(state.get("mission", ""))
	var mission_id: String = ""
	for candidate: String in Simulation.MISSION_SAVE_TAGS:
		if Simulation.MISSION_SAVE_TAGS[candidate] == tag:
			mission_id = candidate
			break
	return {"mission_id": mission_id, "mission_tag": tag, "payload_mission_id": CampaignRoute.serialized_dictionary(state.get("payload")).get("mission_id", "")}


func _live_mission_identity() -> Dictionary:
	return {"mission_id": str(app.sim.mission_id), "mission_tag": str(app.sim.save_state().get("mission", "")), "selected_mission_id": str(app.selected_mission_id)}


func _mission_matches(identity: Dictionary, live: bool = false, saved: bool = false) -> bool:
	if identity.get("mission_id") != _requested_mission_id or identity.get("mission_tag") != Simulation.MISSION_SAVE_TAGS.get(_requested_mission_id): return false
	if live and identity.get("selected_mission_id") != _requested_mission_id: return false
	if saved and identity.get("payload_mission_id") != ("" if _requested_mission_id == "canyon" else _requested_mission_id): return false
	return true


func _seal_cycle() -> void:
	if _cycle_sealed or report.is_empty(): return
	_observe_main_clock()
	_observing = false
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
	report.final.merge(_live_mission_identity())
	report["ui_speed"] = app.speed
	check(_mission_matches(report.final, true), "final live campaign retains the requested mission identity")
	report["main_loop"] = {"fixed_step_seconds": STEP_SECONDS, "observed_frames": _frames, "observed_ticks": _ticks, "raw_main_ticks": _raw_ticks,
		"observed_sim_seconds": _sim_seconds, "invalid_time_steps": _invalid_steps, "terminal_noop_ticks": _terminal_noop_ticks,
		"start_main_tick_count": _cycle_start_tick, "end_main_tick_count": int(app.tick_count)}
	report["automatic_saves"] = {"observed_file_changes": _auto_changes, "primary": _slot(app.AUTOSAVE_PATH, "autosave-primary.json"), "backup": _slot(app.AUTOSAVE_PATH + ".bak", "autosave-backup.json")}
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
		check(_mission_matches(report.automatic_saves.primary, false, true) and _mission_matches(report.automatic_saves.backup, false, true), "automatic save generations retain requested mission identity")
	var final_state: Dictionary = app._save_payload()
	var final_path: String = output_dir.path_join("final-campaign-state.json")
	_write_json(final_path, final_state)
	report["final_state"] = _saved_mission_identity(final_state)
	report.final_state.merge({"path": final_path, "sha256": FileAccess.get_sha256(final_path)})
	check(app._validate_save_payload(final_state) and _mission_matches(report.final_state, false, true), "final saved campaign proof has valid schema and requested mission identity")
	if _soak_mode:
		var label: String = "post_warmup_cycle_%02d_victory" % _cycle_index if app.sim.outcome == "victory" and bool(report.route.get("success", false)) else "failed_cycle_%02d" % _cycle_index
		var stability: Dictionary = _stability_snapshot(label)
		report["stability_after"] = stability
		_soak_report.stability_samples.append(stability)
	report["checks"] = checks - _cycle_checks_start
	report["errors"] = failures.duplicate()
	report["wall_elapsed_seconds"] = float(Time.get_ticks_usec() - _cycle_started_usec) / 1000000.0
	report["cycle_end_wall_seconds"] = float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	report["complete_campaign_evidence"] = full and report.native_export_proof and failures.is_empty()
	_write_json(output_dir.path_join("campaign-validation.json"), report)
	_cycle_sealed = true
	if _soak_mode:
		var directory: String = output_dir.get_file()
		_soak_report.cycles.append({"cycle_index": _cycle_index, "mission_id": _requested_mission_id,
			"report_path": directory.path_join("campaign-validation.json"), "report_sha256": FileAccess.get_sha256(output_dir.path_join("campaign-validation.json")),
			"final_state_path": directory.path_join("final-campaign-state.json"), "final_state_sha256": report.final_state.sha256,
			"start_main_tick_count": _cycle_start_tick, "end_main_tick_count": int(app.tick_count),
			"complete_campaign_evidence": report.complete_campaign_evidence})
	_write_progress()
	print("CAMPAIGN_VALIDATION_REPORT ", output_dir.path_join("campaign-validation.json"), " complete=", report.complete_campaign_evidence, " errors=", failures.size())


func _finish() -> void:
	if finished: return
	finished = true
	_seal_cycle()
	_observing = false
	app.set_process(false)
	app.set_process_unhandled_input(false)
	if _soak_mode: _seal_soak()
	await app._quit_cleanly(0 if failures.is_empty() else 1)


func _seal_soak() -> void:
	var elapsed: float = float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	_soak_report["final_display"] = soak_display_snapshot()
	check(_soak_report.final_display.ready, "soak finishes at actual1920x1080 client and rendered viewport at UI scale1")
	check(_soak_report.cycles.size() == SOAK_CYCLES and _soak_report.transitions.size() == SOAK_CYCLES - 1, "same Main completes all seven real campaigns and six public restarts")
	check(elapsed >= SOAK_MINIMUM_WALL_SECONDS, "seven completed routes include at least one actual wall-clock hour without padding")
	_soak_report["binaries_after"] = _binary_hashes()
	_soak_report["sources_after"] = _source_hashes()
	check(_soak_report.binaries_before == _soak_report.binaries_after and _soak_report.sources_before == _soak_report.sources_after, "entire soak uses the same native payload and source")
	var final_path: String = _root_output_dir.path_join("final-campaign-state.json")
	_write_json(final_path, app._save_payload())
	_soak_report["final_state"] = _saved_mission_identity(app._save_payload())
	_soak_report.final_state.merge({"path": final_path, "sha256": FileAccess.get_sha256(final_path)})
	_soak_report["wall_elapsed_seconds"] = elapsed
	_soak_report["checks"] = checks
	_soak_report["errors"] = failures.duplicate()
	_soak_report["complete_campaign_evidence"] = _soak_report.cycles.size() == SOAK_CYCLES and failures.is_empty() and _soak_report.native_export_proof
	_soak_report["one_hour_soak_evidence"] = _soak_report.complete_campaign_evidence and elapsed >= SOAK_MINIMUM_WALL_SECONDS
	_write_json(_root_output_dir.path_join("campaign-validation.json"), _soak_report)
	_write_progress()
	print("CAMPAIGN_SOAK_REPORT ", _root_output_dir.path_join("campaign-validation.json"), " one_hour=", _soak_report.one_hour_soak_evidence, " errors=", failures.size())


func _stability_snapshot(label: String) -> Dictionary:
	var allocated: int = OS.get_static_memory_usage()
	var peak: int = OS.get_static_memory_peak_usage()
	var memory: Dictionary = {"process_linux": _process_memory(),
		"godot_static_available": allocated > 0, "godot_static_bytes": allocated if allocated > 0 else null,
		"godot_static_peak_available": peak > 0, "godot_static_peak_bytes": peak if peak > 0 else null,
		"allocator_scope": "Release allocator counters may be unavailable; null is not zero memory.",
		"gpu_memory_available": false, "gpu_memory_bytes": null, "gpu_memory_status": "No per-process GPU allocation reading is claimed by this gate."}
	var audio: Node = app.game_audio
	var music: AudioStreamPlayer = app.music_player
	var music_id: String = str(music.get_instance_id())
	var world_ids: Array[String] = []
	var ui_ids: Array[String] = []
	var active_ui: int = 0
	for player: AudioStreamPlayer in audio.world_players: world_ids.append(str(player.get_instance_id()))
	for player: AudioStreamPlayer in audio.ui_players:
		ui_ids.append(str(player.get_instance_id()))
		if player.playing: active_ui += 1
	check(world_ids.size() == audio.WORLD_VOICES and ui_ids.size() == audio.UI_VOICES and audio.active_world_voices() <= audio.WORLD_VOICES, "soak keeps configured bounded audio voice pools")
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var snapshot: Dictionary = {"name": label, "cycle_index": _cycle_index, "mission_id": _requested_mission_id, "warmup_complete": app.sim.outcome == "victory" and bool(report.route.get("success", false)),
		"wall_seconds": float(Time.get_ticks_usec() - _started_usec) / 1000000.0, "main_tick_count": int(app.tick_count), "memory": memory,
		"main_instance_id": str(app.get_instance_id()), "world_instance_id": str(app.world.get_instance_id()), "hud_instance_id": str(app.hud.get_instance_id()), "audio_instance_id": str(audio.get_instance_id()), "music_instance_id": music_id,
		"tree_node_count": get_tree().get_node_count(), "world_child_count": app.world.get_child_count(), "hud_child_count": app.hud.get_child_count(),
		"audio_stream_player_count": app.find_children("*", "AudioStreamPlayer", true, false).size(),
		"object_count_available": objects > 0, "object_count": objects if objects > 0 else null,
		"orphan_node_count_available": OS.is_debug_build(), "orphan_node_count": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) if OS.is_debug_build() else null,
		"monitor_scope": "Unsupported release monitors are null; actual tree/child counts and instance IDs are measured directly.",
		"audio": {"world_player_ids": world_ids, "ui_player_ids": ui_ids, "allocated_world_voices": world_ids.size(), "allocated_ui_voices": ui_ids.size(), "allocated_music_players": 1 if music.get_parent() == app else 0,
			"active_world_voices": audio.active_world_voices(), "active_ui_voices": active_ui, "observed_updates": audio.observed_updates,
			"play_counts": audio.play_counts.duplicate(true), "dropped": audio.dropped, "peak_world_voices": audio.peak_world_voices}}
	check(snapshot.audio.allocated_music_players == 1 and not music_id in world_ids and not music_id in ui_ids, "same Main retains one separate music player outside the effect voice pools")
	check(snapshot.audio_stream_player_count == audio.WORLD_VOICES + audio.UI_VOICES + 1, "same Main has exactly the configured effect voices plus one music player")
	if not _soak_report.stability_samples.is_empty():
		var baseline: Dictionary = _soak_report.stability_samples[0]
		check(world_ids == baseline.audio.world_player_ids and ui_ids == baseline.audio.ui_player_ids, "campaign restarts reuse the same allocated audio voices")
		for key: String in ["main_instance_id", "world_instance_id", "hud_instance_id", "audio_instance_id", "music_instance_id", "tree_node_count", "world_child_count", "hud_child_count", "audio_stream_player_count"]:
			check(snapshot[key] == baseline[key], "campaign restarts retain fixed node identity/count: " + key)
	return snapshot


func _process_memory() -> Dictionary:
	var result: Dictionary = {"source": "/proc/self/status", "available": false, "read_limit_bytes": 65536}
	var file: FileAccess = FileAccess.open("/proc/self/status", FileAccess.READ)
	if file == null: return result
	# Proc files advertise length zero; bounded reads still return their content.
	var bytes: PackedByteArray = file.get_buffer(65536)
	file.close()
	if bytes.is_empty() or bytes.size() >= 65536: return result
	for line: String in bytes.get_string_from_utf8().split("\n"):
		var fields: PackedStringArray = line.replace("\t", " ").split(" ", false)
		if fields.size() >= 3 and fields[0] in ["VmRSS:", "VmHWM:"] and fields[1].is_valid_int() and fields[2] == "kB":
			result[fields[0].trim_suffix(":") + "_bytes"] = int(fields[1]) * 1024
	result.available = int(result.get("VmRSS_bytes", 0)) > 0 and int(result.get("VmHWM_bytes", 0)) > 0
	return result


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
