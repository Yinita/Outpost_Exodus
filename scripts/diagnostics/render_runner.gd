extends Node
## Optional native export diagnostics. Main validates isolation BEFORE loading settings,
## then adds this node as its sibling and assigns app to the initialized main instance.
## Never preload main.tscn here: main imports this runner for early validation.

const FRONT_CAMP: int = 5000
const PIXELS: Vector2i = Vector2i(1920, 1080)
# Fingerprint covers canonical _make_busy_scene and all fixture helper functions.
# tests/test_render_diagnostics.gd verifies both source and actual serialized state.
const CANONICAL_FIXTURE_SHA256: String = "95c49eaeba97a500cd95e0ad12a78d59b06103366a239505acc48be38ba20d4d"
const TRACKED_SOURCES: Array[String] = [
	"res://project.godot", "res://main.tscn", "res://scripts/main.gd",
	"res://scripts/campaign_simulation.gd", "res://scripts/campaign_catalog.gd",
	"res://scripts/construction_rules.gd", "res://scripts/actor_atlas.gd", "res://scripts/actor_canvas.gd",
	"res://scripts/recruitment_rules.gd", "res://scripts/game_audio.gd",
	"res://scripts/render_motion.gd",
	"res://scripts/cartoon_canvas.gd", "res://scripts/terrain_cache.gd", "res://scripts/decoration_cache.gd",
	"res://scripts/campaign_save_store.gd", "res://scripts/world_view.gd", "res://scripts/hud.gd",
	"res://scripts/campaign_guide.gd", "res://scripts/diagnostics/render_runner.gd",
	"res://assets/buildings-atlas.png", "res://assets/fonts/NotoSansCJK-Regular.ttc",
	"res://assets/audio/canyon_ambient.wav", "res://assets/audio/sfx_shot_a.wav", "res://assets/audio/sfx_shot_b.wav",
	"res://assets/audio/sfx_impact.wav", "res://assets/audio/sfx_loot.wav", "res://assets/audio/sfx_confirm.wav",
	"res://assets/audio/sfx_reject.wav", "res://assets/audio/sfx_build.wav", "res://assets/audio/sfx_warning.wav",
]

static func parse_arguments(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"frames": 600, "warmup": 120, "max_seconds": 180, "quick": false, "prepare_only": false, "uncapped": false, "zoom": "both", "output_dir": "", "errors": []}
	var seen: Dictionary = {}
	for argument: String in arguments:
		var key: String = argument.get_slice("=", 0)
		if seen.has(key): result.errors.append("duplicate diagnostics argument: " + key)
		seen[key] = true
		if argument == "--render-diagnostics": pass
		elif argument == "--quick": result.quick = true
		elif argument == "--prepare-only": result.prepare_only = true
		elif argument == "--uncapped": result.uncapped = true
		elif key in ["--frames", "--warmup", "--max-seconds"] and argument.contains("="):
			var value: String = argument.trim_prefix(key + "=")
			if not value.is_valid_int():
				result.errors.append("diagnostics requires an integer: " + argument)
				continue
			var limits: Array = [600, 3600] if key == "--frames" else ([120, 600] if key == "--warmup" else [30, 600])
			if int(value) < limits[0] or int(value) > limits[1]: result.errors.append("diagnostics argument outside supported range: " + argument)
			result[key.trim_prefix("--").replace("-", "_")] = int(value)
		elif argument.begins_with("--zoom="): result.zoom = argument.trim_prefix("--zoom=")
		elif argument.begins_with("--output-dir="): result.output_dir = argument.trim_prefix("--output-dir=")
		else: result.errors.append("unknown or mixed diagnostics argument: " + argument)
	if not seen.has("--render-diagnostics"): result.errors.append("--render-diagnostics is required")
	if result.quick and result.prepare_only: result.errors.append("--quick and --prepare-only cannot be combined")
	if result.zoom not in ["both", "normal", "strategic"]: result.errors.append("--zoom must be both, normal or strategic")
	if result.quick:
		result.frames = 12
		result.warmup = 6
	if result.prepare_only:
		result.frames = 1
		result.warmup = 0
	var isolation: String = OS.get_environment("BENCH_ISOLATION_ROOT").simplify_path()
	result.output_dir = isolation.path_join("output") if str(result.output_dir).is_empty() else str(result.output_dir).simplify_path()
	if not _filesystem_absolute(result.output_dir) or not _below(result.output_dir, isolation): result.errors.append("--output-dir must be an absolute child of BENCH_ISOLATION_ROOT")
	return result

static func validate_environment() -> Array[String]:
	var failures: Array[String] = []
	var isolation: String = OS.get_environment("BENCH_ISOLATION_ROOT").simplify_path()
	if not _filesystem_absolute(isolation) or _has_symlink_component(isolation) or isolation in ["/", OS.get_environment("HOME").simplify_path()]:
		failures.append("BENCH_ISOLATION_ROOT must be an absolute dedicated filesystem directory")
		return failures
	for key: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var path: String = OS.get_environment(key).simplify_path()
		if not _filesystem_absolute(path) or not _below(path, isolation): failures.append(key + " must be a dedicated child of BENCH_ISOLATION_ROOT")
	if not _below(OS.get_user_data_dir().simplify_path(), isolation): failures.append("Godot user:// is outside isolated root; refusing to read real settings/saves")
	for path: String in ["user://settings.cfg", "user://campaign-save.json", "user://campaign-autosave.json", "user://campaign-save.json.bak", "user://campaign-autosave.json.bak"]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)): failures.append("diagnostics requires fresh settings/save paths: " + path)
	var parsed: Dictionary = parse_arguments(OS.get_cmdline_user_args())
	for error: String in parsed.errors: failures.append(error)
	return failures

static func _filesystem_absolute(path: String) -> bool:
	return not path.is_empty() and path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://")

static func _below(path: String, parent: String) -> bool:
	return not parent.is_empty() and path.begins_with(parent.trim_suffix("/") + "/") and not _has_symlink_component(path) and not _has_symlink_component(parent)

static func _has_symlink_component(path: String) -> bool:
	# Check existing ancestors too, so a not-yet-created child cannot escape via
	# an earlier link. No PCK/import internals or settings contents are read.
	var cursor: String = path.simplify_path()
	for depth: int in range(128):
		var parent: String = cursor.get_base_dir()
		if parent == cursor or cursor.is_empty(): return false
		var directory: DirAccess = DirAccess.open(parent)
		if directory != null and directory.is_link(cursor.get_file()): return true
		cursor = parent
	return true

class TimedSimulation:
	extends "res://scripts/campaign_simulation.gd"
	var collect: bool = false
	var tick_samples_usec: Array = []
	var tick_observer: Callable
	func tick(delta: float) -> void:
		var start: int = Time.get_ticks_usec()
		super.tick(delta)
		if collect:
			tick_samples_usec.append(Time.get_ticks_usec() - start)
			if tick_observer.is_valid(): tick_observer.call()

var frames: int = 600
var warmup: int = 120
var max_seconds: int = 180
var quick: bool = false
var prepare_only: bool = false
var uncapped: bool = false
var zoom_filter: String = "both"
var output_dir: String = ""
var errors: Array[String] = []
var app: Node2D
var setup: Dictionary = {}
var report: Dictionary = {}
var workload: Dictionary = {}
var previous_hauling: Dictionary = {}
var finished: bool = false
var started_usec: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	errors.assign(validate_environment())
	if not errors.is_empty():
		for error: String in errors: printerr("RENDER_DIAGNOSTICS_INVALID ", error)
		get_tree().quit(1)
		return
	var config: Dictionary = parse_arguments(OS.get_cmdline_user_args())
	frames = int(config.frames)
	warmup = int(config.warmup)
	max_seconds = int(config.max_seconds)
	quick = bool(config.quick)
	prepare_only = bool(config.prepare_only)
	uncapped = bool(config.uncapped)
	zoom_filter = str(config.zoom)
	output_dir = str(config.output_dir)
	if not is_instance_valid(app) or app.sim == null or app.world == null or app.hud == null:
		printerr("RENDER_DIAGNOSTICS_INVALID initialized app, world and HUD are required")
		get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		printerr("RENDER_DIAGNOSTICS_INVALID native display required")
		get_tree().quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("RENDER_DIAGNOSTICS_INVALID output directory cannot be created")
		get_tree().quit(1)
		return
	started_usec = Time.get_ticks_usec()
	get_tree().create_timer(max_seconds).timeout.connect(_on_timeout)
	var window: Window = get_window()
	window.mode = Window.MODE_WINDOWED
	window.borderless = true
	window.size = PIXELS
	window.content_scale_size = PIXELS
	window.content_scale_factor = 1.0
	window.position = DisplayServer.screen_get_position() + (DisplayServer.screen_get_size() - PIXELS) / 2
	window.title = "Outpost Exodus — native render diagnostics"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if uncapped else DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 0
	if RenderingServer.has_method("viewport_set_measure_render_time"):
		RenderingServer.call("viewport_set_measure_render_time", window.get_viewport_rid(), true)
	var fingerprint: Dictionary = fixture_fingerprint()
	report = {
		"recorded_utc": Time.get_datetime_string_from_system(true, true) + "Z",
		"runtime": Engine.get_version_info(), "platform": OS.get_name(), "os_version": OS.get_version(),
		"debug_build": OS.is_debug_build(), "editor_capable_runtime": OS.has_feature("editor"),
		"native_export_proof": not OS.has_feature("editor"),
		"cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"display_server": DisplayServer.get_name(), "display_environment": OS.get_environment("DISPLAY"),
		"gpu_adapter": RenderingServer.get_video_adapter_name(), "gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"screen_size": _vector(DisplayServer.screen_get_size()), "screen_refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"window_size": _vector(window.size), "viewport_size": _vector(Vector2i(window.get_visible_rect().size)),
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"user_data_dir": OS.get_user_data_dir(), "output_dir": output_dir,
		"sources_before": _source_hashes(), "binaries_before": _binary_hashes(),
		"fixture_fingerprint": fingerprint,
		"memory_start": _memory_snapshot(), "system_memory": _proc_memory("/proc/meminfo", ["MemTotal", "MemAvailable"]),
		"method": {
			"quick_check_only": quick or prepare_only, "prepare_only": prepare_only,
			"runs_per_zoom": 1, "warmup_frames_per_zoom": warmup, "measured_frames_per_zoom": frames,
			"max_wall_seconds": max_seconds, "fixed_simulation_step_seconds": 0.05,
			"frame_scope": "Wall intervals between RenderingServer.frame_post_draw signals from the actual native app, including real main simulation loop, world/HUD drawing, diagnostics observations and rendering/presentation pacing. Not physical scanout timing.",
			"simulation_scope": "Actual main._process accumulator calls timed campaign_simulation.tick(0.05) at 20 Hz. Tick timer wraps only super.tick; workload observation follows and remains included in wall frames.",
			"render_scope": "RenderingServer viewport CPU/GPU and frame setup CPU milliseconds where supported; excludes game scripts. Performance monitors are sampled engine totals and cannot be added to isolated subsystem timers.",
			"render_timing_reference": "https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-cpu",
			"fixture": "Canonical deterministic 32 friendly / 100 enemy fixture, connected salvage hauling, powered production, three paid building orders and one paid road order. Increased HP retains workload; no balanced-combat claim.",
			"save_scope": "After measured frame 300, actual app.save_campaign(false) runs on the main thread. Its wall pause is included in frame interval 301. Save call and read/semantic verification times are recorded separately; verification also remains included in that wall interval.",
			"screenshots": "Captured after measurement; GPU readback/PNG encoding and RSS/binary hashing are outside sampled frame intervals.",
			"percentiles": "Nearest rank over individual frames/ticks. FPS = measured frames / sum of measured wall intervals.",
			"limits": "Local host; OS and other processes uncontrolled. Each zoom starts the same fixture, then actual 20 Hz simulation advances by wall time, so faster rendering covers less simulated time for a fixed frame count. Quick/prepare checks do not establish performance. No cursor warp or desktop display-mode change.",
		},
		"zooms": [],
	}
	if not bool(fingerprint.valid): errors.append("fixture fingerprint failed canonical/prevalidated constant verification")
	if not OS.has_feature("editor") and not bool(report.binaries_before.adjacent_pck.available):
		errors.append("native export diagnostics requires the actual adjacent PCK for provenance")
	if not errors.is_empty():
		await _finish()
		return
	for zoom: Dictionary in [{"name": "normal", "value": 1.05}, {"name": "strategic", "value": 0.35}]:
		if zoom_filter != "both" and zoom_filter != str(zoom.name): continue
		if finished: return
		var result: Dictionary = await _measure_zoom(zoom)
		if finished: return
		report.zooms.append(result)
		print("RENDER_DIAGNOSTICS_ZOOM ", str(zoom.name), " ", JSON.stringify(result.frame_ms), " ticks=", result.simulation_ticks, " workload=", str(result.workload))
	await _finish()

func _install_scene(zoom: Dictionary) -> void:
	app.set_process(false)
	app.set_process_input(false)
	app.set_process_unhandled_input(false)
	if app.sim is TimedSimulation: app.sim.tick_observer = Callable()
	setup = _make_busy_scene()
	app.sim = setup.sim
	app.world.sim = app.sim
	app.started = true
	app.menu = ""
	app.speed = 1.0
	app.accumulator = 0.0
	app.autosave_time = 0.0
	app.tick_count = 0
	app.edge_scroll = false
	app.selected_camp = FRONT_CAMP
	app.selected_ids.clear()
	for unit: Dictionary in app.sim.units:
		if unit.team == "friendly" and unit.kind == "rifle": app.selected_ids.append(int(unit.id))
	app.guide.reset(app.guide_enabled)
	app.feedback_left = 0.0
	app.window_resolution = PIXELS
	app.ui_scale = 1.0
	app.camera.position = Vector2(29.0, 23.0) * 48.0
	app.camera.zoom = Vector2.ONE * float(zoom.value)
	app.camera.force_update_scroll()
	app.sim.tick_observer = _observe_workload
	app.world.queue_redraw()
	app.hud.queue_redraw()
	app.set_process(true)

func _measure_zoom(zoom: Dictionary) -> Dictionary:
	var errors_before: int = errors.size()
	_install_scene(zoom)
	await RenderingServer.frame_post_draw
	for index: int in range(warmup):
		await RenderingServer.frame_post_draw
		if finished: return {}
	var sim: Variant = app.sim
	var memory_start: Dictionary = _memory_snapshot()
	_reset_workload()
	sim.tick_samples_usec.clear()
	var frames_usec: Array = []
	var ticks_per_frame: Array = []
	var metrics: Dictionary = {
		"performance_process_ms": [], "performance_physics_ms": [],
		"render_setup_cpu_ms": [], "viewport_render_cpu_ms": [], "viewport_render_gpu_ms": [],
		"draw_calls": [], "rendered_objects": [], "rendered_primitives": [],
	}
	# Align the first sample to a completed draw after all setup and RSS probes.
	await RenderingServer.frame_post_draw
	if finished: return {}
	_reset_workload()
	sim.tick_samples_usec.clear()
	sim.collect = true
	var previous: int = Time.get_ticks_usec()
	var start_tick: int = app.tick_count
	var previous_tick: int = start_tick
	var simulated_start: float = sim.time
	var save_measurements: Array = []
	for index: int in range(frames):
		await RenderingServer.frame_post_draw
		if finished: return {}
		var now: int = Time.get_ticks_usec()
		frames_usec.append(now - previous)
		previous = now
		ticks_per_frame.append(app.tick_count - previous_tick)
		previous_tick = app.tick_count
		metrics.performance_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		metrics.performance_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		metrics.draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		metrics.rendered_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		metrics.rendered_primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		_append_render_metric(metrics.render_setup_cpu_ms, "get_frame_setup_time_cpu")
		_append_render_metric(metrics.viewport_render_cpu_ms, "viewport_get_measured_render_time_cpu", true)
		_append_render_metric(metrics.viewport_render_gpu_ms, "viewport_get_measured_render_time_gpu", true)
		if index + 1 == 300:
			save_measurements.append(_measure_real_save(index + 1))
	sim.collect = false
	app.set_process(false)
	var frame_stats: Dictionary = _time_stats(frames_usec)
	var total_usec: float = 0.0
	var over_16_667: int = 0
	var over_33_333: int = 0
	for duration: Variant in frames_usec:
		total_usec += float(duration)
		if float(duration) > 16666.667: over_16_667 += 1
		if float(duration) > 33333.333: over_33_333 += 1
	frame_stats["observed_fps"] = float(frames) * 1000000.0 / maxf(1.0, total_usec)
	frame_stats["intervals_over_16_667_ms"] = over_16_667
	frame_stats["intervals_over_33_333_ms"] = over_33_333
	var metric_stats: Dictionary = {}
	for key: String in metrics: metric_stats[key] = _stats(metrics[key])
	var image: Image = get_viewport().get_texture().get_image()
	var screenshot: String = output_dir + "/" + str(zoom.name) + ".png"
	var screenshot_result: Error = image.save_png(screenshot)
	if screenshot_result != OK: errors.append("screenshot save failed: " + screenshot)
	if image.get_size() != PIXELS or get_window().size != PIXELS: errors.append("render/window is not actual 1920x1080")
	var actor_count: Dictionary = _actor_counts(sim)
	if actor_count.friendly != 32 or actor_count.enemy != 100: errors.append("fixture lost requested 32 friendly / 100 enemy actors")
	if sim.outcome != "playing" or not app.menu.is_empty(): errors.append("gameplay stopped or opened a menu")
	if setup.construction_ids.size() != 3: errors.append("fixture did not enqueue all three paid building orders")
	if not quick and not prepare_only:
		if save_measurements.size() != 1 or not bool(save_measurements[0].get("write_and_read_valid", false)): errors.append("actual app save failed at measured frame 300")
		if workload.hauling_cargo_samples == 0 or workload.hauling_deliveries == 0: errors.append("no real resource pickup and delivery observed; increase --frames or investigate hauling")
		if workload.combat_effect_samples == 0: errors.append("no actual combat observed")
		if workload.construction_max_progress_delta <= 0.0: errors.append("paid construction did not advance in measurement")
		if workload.friendly_min != 32 or workload.enemy_min != 100: errors.append("busy actor population was not retained throughout measurement")
	return {
		"name": zoom.name, "zoom": zoom.value,
		"camera_tile": _vector(app.camera.position / 48.0),
		"warmup_frames": warmup, "measured_frames": frames,
		"frame_ms": frame_stats, "frame_intervals_usec": frames_usec,
		"simulation_tick_ms": _time_stats(sim.tick_samples_usec), "simulation_tick_samples_usec": sim.tick_samples_usec.duplicate(),
		"simulation_ticks": app.tick_count - start_tick, "ticks_per_frame": ticks_per_frame,
		"simulated_seconds_measured": sim.time - simulated_start,
		"actual_fixed_step_hz": 20.0, "speed": app.speed,
		"available_engine_metrics": metric_stats, "engine_metric_samples": metrics,
		"workload": workload.duplicate(true), "actor_counts_end": actor_count,
		"construction_ids": setup.construction_ids.duplicate(), "save_measurements": save_measurements,
		"remaining_nearby_salvage": _site_stock(sim, 6000, "salvage"),
		"screenshot": screenshot, "screenshot_pixels": _vector(image.get_size()),
		"memory_start": memory_start, "memory_end": _memory_snapshot(),
		"valid_workload": errors.size() == errors_before,
	}

func _reset_workload() -> void:
	previous_hauling.clear()
	workload = {
		"observed_simulation_ticks": 0, "observer_cpu_usec": 0,
		"friendly_min": 99999, "friendly_max": 0, "enemy_min": 99999, "enemy_max": 0,
		"nonempty_cargo_samples": 0, "hauling_cargo_samples": 0, "hauling_deliveries": 0,
		"combat_effect_samples": 0, "construction_peak_progress": 0.0, "construction_start_progress": 0.0,
		"construction_start_progress_by_id": {}, "construction_max_progress_delta": 0.0,
		"completed_ordered_buildings": 0,
	}
	for building: Dictionary in app.sim.buildings:
		if setup.construction_ids.has(int(building.id)):
			workload.construction_start_progress = maxf(workload.construction_start_progress, float(building.progress))
			workload.construction_start_progress_by_id[int(building.id)] = float(building.progress)
	# A warmup may finish with loaded carriers; seed transition tracking there.
	for unit: Dictionary in app.sim.units:
		previous_hauling[int(unit.id)] = str(unit.get("order", "")) == "haul" and not Dictionary(unit.get("cargo", {})).is_empty()

func _observe_workload() -> void:
	var start: int = Time.get_ticks_usec()
	var sim: Variant = app.sim
	var counts: Dictionary = _actor_counts(sim)
	workload.observed_simulation_ticks += 1
	workload.friendly_min = mini(workload.friendly_min, counts.friendly)
	workload.friendly_max = maxi(workload.friendly_max, counts.friendly)
	workload.enemy_min = mini(workload.enemy_min, counts.enemy)
	workload.enemy_max = maxi(workload.enemy_max, counts.enemy)
	for unit: Dictionary in sim.units:
		var has_cargo: bool = not Dictionary(unit.get("cargo", {})).is_empty()
		var hauling: bool = str(unit.get("order", "")) == "haul" and has_cargo
		if has_cargo: workload.nonempty_cargo_samples += 1
		if hauling: workload.hauling_cargo_samples += 1
		if bool(previous_hauling.get(int(unit.id), false)) and not has_cargo:
			var owner: Dictionary = sim.get_camp(int(unit.camp_id))
			if not owner.is_empty() and Vector2(unit.pos).distance_to(Vector2(owner.pos)) <= 2.5:
				workload.hauling_deliveries += 1
		previous_hauling[int(unit.id)] = hauling
	for effect: Dictionary in sim.effects:
		if effect.kind in ["shot", "hit"]: workload.combat_effect_samples += 1
	workload.completed_ordered_buildings = 0
	for building: Dictionary in sim.buildings:
		if setup.construction_ids.has(int(building.id)):
			workload.construction_peak_progress = maxf(workload.construction_peak_progress, float(building.progress))
			workload.construction_max_progress_delta = maxf(workload.construction_max_progress_delta, float(building.progress) - float(workload.construction_start_progress_by_id.get(int(building.id), 0.0)))
			if float(building.progress) >= 1.0: workload.completed_ordered_buildings += 1
	workload.observer_cpu_usec += Time.get_ticks_usec() - start

func _actor_counts(sim: Variant) -> Dictionary:
	var result: Dictionary = {"friendly": 0, "enemy": 0}
	for unit: Dictionary in sim.units:
		if float(unit.hp) <= 0.0: continue
		if unit.team == "friendly": result.friendly += 1
		else: result.enemy += 1
	return result

func _append_render_metric(values: Array, method: String, viewport: bool = false) -> void:
	if not RenderingServer.has_method(method): return
	var value: float = float(RenderingServer.call(method, get_window().get_viewport_rid()) if viewport else RenderingServer.call(method))
	if is_finite(value): values.append(value)

func _on_timeout() -> void:
	if finished: return
	errors.append("internal wall-time cap exceeded")
	await _finish()

func _finish() -> void:
	if finished: return
	finished = true
	if is_instance_valid(app):
		app.set_process(false)
		app.set_process_input(false)
		app.set_process_unhandled_input(false)
		if app.sim is TimedSimulation:
			app.sim.collect = false
			app.sim.tick_observer = Callable()
		app._release_audio()
	report["memory_end"] = _memory_snapshot()
	report["sources_after"] = _source_hashes()
	report["binaries_after"] = _binary_hashes()
	report["binaries_changed_during_run"] = report.get("binaries_before", {}) != report.binaries_after
	if report.binaries_changed_during_run: errors.append("executable/PCK changed during run")
	report["source_changed_during_run"] = report.get("sources_before", {}) != report.sources_after
	if report.source_changed_during_run: errors.append("source/assets changed during the run; rerun against a stable candidate")
	report["wall_elapsed_seconds"] = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	report["errors"] = errors
	report["valid_workload"] = errors.is_empty()
	report["performance_evidence"] = errors.is_empty() and not quick and not prepare_only
	var path: String = output_dir + "/rendered-benchmark.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("RENDER_DIAGNOSTICS_INVALID report could not be written")
		errors.append("report write failed")
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("RENDER_DIAGNOSTICS_REPORT ", path)
	for error: String in errors: printerr("RENDER_DIAGNOSTICS_INVALID ", error)
	# Match main's audio retirement interval; SceneTree owns both sibling nodes.
	await get_tree().create_timer(0.12).timeout
	if RenderingServer.has_method("viewport_set_measure_render_time"):
		RenderingServer.call("viewport_set_measure_render_time", get_viewport().get_viewport_rid(), false)
	setup.clear()
	get_tree().quit(0 if errors.is_empty() else 1)

static func _fixture_source(path: String) -> String:
	if not FileAccess.file_exists(path): return ""
	var source: String = FileAccess.get_file_as_string(path)
	var start: int = source.find("\nfunc " + "_make_busy_scene()")
	if start < 0: return ""
	start += 1
	var end: int = source.find("\nfunc " + "_measure_run(", start)
	return source.substr(start, end - start if end >= 0 else -1).strip_edges().replace("TimedSimulation.new()", "Simulation.new()")

static func fixture_fingerprint() -> Dictionary:
	var own: String = _fixture_source("res://scripts/diagnostics/render_runner.gd")
	var canonical: String = _fixture_source("res://tests/benchmark_campaign.gd")
	if OS.has_feature("editor"):
		var own_hash: String = own.sha256_text() if not own.is_empty() else ""
		var canonical_hash: String = canonical.sha256_text() if not canonical.is_empty() else ""
		return {"mode": "editor_source_compared_to_canonical", "valid": not own.is_empty() and not canonical.is_empty() and own_hash == CANONICAL_FIXTURE_SHA256 and canonical_hash == CANONICAL_FIXTURE_SHA256, "runner_sha256": own_hash, "canonical_sha256": canonical_hash}
	return {"mode": "compiled_imported_prebuild_fingerprint_plus_runtime_workload", "valid": true, "prevalidated_fixture_sha256": CANONICAL_FIXTURE_SHA256, "source_text_verified_at_runtime": false, "note": "Release PCK contains imported scripts. Constant is verified against canonical fixture by prebuild tests; actual actor/combat/haul/construction checks and binary hashes provide runtime evidence."}

func _source_hashes() -> Dictionary:
	var result: Dictionary = {}
	var paths: Array[String] = TRACKED_SOURCES.duplicate()
	_collect_public_script_paths("res://scripts", paths)
	paths.sort()
	for path: String in paths:
		result[path] = {"status": "source_available", "sha256": FileAccess.get_sha256(path)} if FileAccess.file_exists(path) else {"status": "compiled/imported", "sha256": null}
	return result

func _collect_public_script_paths(directory: String, paths: Array[String]) -> void:
	for filename: String in DirAccess.get_files_at(directory):
		if filename.ends_with(".gd") or filename.ends_with(".gd.remap"):
			var logical: String = directory.path_join(filename.trim_suffix(".remap"))
			if not paths.has(logical): paths.append(logical)
	for child: String in DirAccess.get_directories_at(directory):
		if not child.begins_with("."): _collect_public_script_paths(directory.path_join(child), paths)

func _binary_hashes() -> Dictionary:
	var executable: String = OS.get_executable_path()
	var pck: String = executable.get_basename() + ".pck"
	return {"executable": _file_fingerprint(executable), "adjacent_pck": _file_fingerprint(pck)}

func _file_fingerprint(path: String) -> Dictionary:
	var available: bool = FileAccess.file_exists(path)
	return {"path": path, "available": available, "sha256": FileAccess.get_sha256(path) if available else null}

func _measure_real_save(frame: int) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var wrote: bool = bool(app.save_campaign(false))
	var call_usec: int = Time.get_ticks_usec() - start
	var verify_start: int = Time.get_ticks_usec()
	var path: String = ProjectSettings.globalize_path("user://campaign-autosave.json")
	var available: bool = FileAccess.file_exists(path)
	var valid: bool = false
	var bytes: int = 0
	if available:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file != null:
			bytes = file.get_length()
			file.close()
		var stored: Dictionary = app.save_store.read(path)
		valid = bool(stored.get("ok", false)) and app._validate_save_payload(stored.get("data", {}))
	return {"after_measured_frame": frame, "included_in_wall_frame_interval": frame + 1, "save_call_usec": call_usec, "save_call_ms": float(call_usec) / 1000.0, "read_semantic_verification_usec": Time.get_ticks_usec() - verify_start, "path": path, "bytes": bytes, "exists": available, "save_returned_success": wrote, "write_and_read_valid": wrote and valid}

func _vector(value: Vector2) -> Array:
	return [value.x, value.y]

func _time_stats(values: Array) -> Dictionary:
	var result: Dictionary = _stats(values)
	for key: String in ["p50", "p95", "p99", "max", "mean"]:
		if result.has(key): result[key + "_ms"] = float(result[key]) / 1000.0
	return result

func _stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"samples": 0, "nonzero_samples": 0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	var nonzero: int = 0
	for value: Variant in sorted:
		total += float(value)
		if float(value) > 0.0: nonzero += 1
	return {
		"samples": sorted.size(), "nonzero_samples": nonzero,
		"p50": float(sorted[maxi(0, ceili(sorted.size() * 0.50) - 1)]),
		"p95": float(sorted[maxi(0, ceili(sorted.size() * 0.95) - 1)]),
		"p99": float(sorted[maxi(0, ceili(sorted.size() * 0.99) - 1)]),
		"max": float(sorted.back()), "mean": total / sorted.size(),
	}

func _site_stock(sim: Variant, site_id: int, resource: String) -> float:
	for site: Dictionary in sim.sites:
		if int(site.id) == site_id: return float(Dictionary(site.get("stock", {})).get(resource, 0.0))
	return 0.0

func _memory_snapshot() -> Dictionary:
	return {
		"process_linux": _proc_memory("/proc/self/status", ["VmRSS", "VmHWM"]),
		"godot_static_bytes": OS.get_static_memory_usage(), "godot_static_peak_bytes": OS.get_static_memory_peak_usage(),
	}

func _proc_memory(path: String, keys: Array) -> Dictionary:
	var result: Dictionary = {"source": path, "available": FileAccess.file_exists(path)}
	if not FileAccess.file_exists(path): return result
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.available = false
		return result
	while not file.eof_reached():
		var fields: PackedStringArray = file.get_line().replace("\t", " ").split(" ", false)
		if fields.size() >= 2:
			var key: String = fields[0].trim_suffix(":")
			if keys.has(key): result[key + "_bytes"] = fields[1].to_int() * 1024
	file.close()
	return result

func _make_busy_scene() -> Dictionary:
	var sim: Variant = TimedSimulation.new()
	sim.reset(42)
	var templates: Dictionary = {}
	for unit: Dictionary in sim.units:
		if not templates.has(str(unit.kind)):
			templates[str(unit.kind)] = unit.duplicate(true)
	for building: Dictionary in sim.buildings:
		building.hp = 1000000.0
		building.max_hp = 1000000.0
	for camp: Dictionary in sim.camps:
		camp.materials = 10000.0
		camp.supplies = 10000.0
		camp.fuel = 10000.0
		camp.recipe = "idle"
	var front: Dictionary = {
		"id": FRONT_CAMP, "name": "Busy-scene forward camp", "pos": Vector2(26, 23),
		"state": "active", "materials": 10000.0, "supplies": 10000.0,
		"fuel": 10000.0, "salvage": 60.0, "crude": 60.0, "power": 0.0,
		"priority": "defense", "recipe": "materials", "recruit_queue": [],
	}
	sim.camps.append(front)
	sim.buildings.append(_building(5100, "camp", Vector2(26, 23)))
	sim.buildings.append(_building(5101, "generator", Vector2(27, 27)))
	sim.buildings.append(_building(5102, "workshop", Vector2(25, 27)))
	sim.buildings.append(_building(5103, "tower", Vector2(27, 19)))
	sim.buildings.append(_building(5104, "tower", Vector2(27, 24)))
	for x: int in range(9, 36): _road(sim, Vector2i(x, 21))
	for y: int in range(10, 32): _road(sim, Vector2i(35, y))
	for y: int in range(21, 28): _road(sim, Vector2i(26, y))
	for x: int in range(24, 30): _road(sim, Vector2i(x, 27))
	for y: int in range(19, 24): _road(sim, Vector2i(27, y))
	for x: int in range(26, 34): _road(sim, Vector2i(x, 23))
	for y: int in range(23, 26): _road(sim, Vector2i(33, y))
	sim.sites.append({"id": 6000, "kind": "quarry", "name": "Nearby benchmark salvage", "pos": Vector2(33, 25), "captured": true, "progress": 1.0, "stock": {"salvage": 100000.0}})
	sim.units.clear()
	var army: Array = []
	for index: int in range(32):
		var kind: String = "truck" if index < 2 else ("worker" if index < 8 else ("engineer" if index < 12 else "rifle"))
		var position: Vector2
		if kind == "truck": position = Vector2(24 + index, 23)
		elif kind == "worker": position = Vector2(24 + (index - 2) % 3 * 0.65, 24 + (index - 2) / 3 * 0.65)
		elif kind == "engineer": position = Vector2(24 + (index - 8) * 0.65, 26)
		else: position = Vector2(26 + (index - 12) % 5 * 0.65, 18.7 + (index - 12) / 5 * 0.65)
		position = _free_position(sim, position)
		var unit: Dictionary = _clone_actor(templates[kind], 1000 + index, position, FRONT_CAMP)
		sim.units.append(unit)
		if kind == "rifle": army.append(int(unit.id))
	for index: int in range(100):
		var position: Vector2 = Vector2(30 + index % 10 * 0.55, 17.5 + index / 10 * 0.55)
		var enemy: Dictionary = _clone_actor(templates["zombie"], 2000 + index, position, -1)
		enemy.pursuer = false
		sim.units.append(enemy)
	sim.main_truck_id = 1000
	sim.pursuit_start = 1000000.0
	sim.pursuit_x = -10000.0
	sim.effects.clear()
	sim.messages.clear()
	var state: Dictionary = sim.save_state()
	for pair: Array in state.payload.entries:
		if pair[0] == "next_id": pair[1] = 20000
	if not sim.load_state(state): errors.append("busy fixture failed semantic save validation")
	var construction_ids: Array = []
	for order: Array in [["tower", Vector2i(29, 26)], ["barracks", Vector2i(24, 30)], ["barricade", Vector2i(28, 29)], ["road", Vector2i(39, 27)]]:
		if not sim.build(order[0], order[1]): errors.append("busy construction order was rejected: " + str(order))
		elif order[0] != "road": construction_ids.append(int(sim.buildings.back().id))
	sim.command_task(army, "guard", Vector2(29, 20))
	return {"sim": sim, "construction_ids": construction_ids}

func _clone_actor(template: Dictionary, id_value: int, position: Vector2, owner: int) -> Dictionary:
	var unit: Dictionary = template.duplicate(true)
	unit.id = id_value
	unit.pos = position
	unit.target = position
	unit.guard_pos = position
	unit.camp_id = owner
	unit.hp = 1000000.0
	unit.max_hp = 1000000.0
	unit.path = []
	unit.path_index = 0
	unit.order = "idle"
	unit.state = "idle" if owner >= 0 else "guard"
	unit.manual = false
	unit.job_id = 0
	unit.cargo = {}
	unit.haul_site = 0
	unit.haul_stage = ""
	return unit

func _building(id_value: int, kind: String, position: Vector2) -> Dictionary:
	return {
		"id": id_value, "kind": kind, "pos": position, "camp_id": FRONT_CAMP,
		"hp": 1000000.0, "max_hp": 1000000.0, "progress": 1.0,
		"powered": false, "power_radius": 10.0 if kind == "generator" else 0.0,
		"required_power": 4.0 if kind == "workshop" else (3.0 if kind == "tower" else 0.0),
		"range": 7.0 if kind == "tower" else 0.0, "cooldown": 0.0,
	}

func _road(sim: Variant, tile: Vector2i) -> void:
	if int(sim.terrain[tile.y][tile.x]) >= 0:
		sim.roads[tile] = {"progress": 1.0, "camp_id": FRONT_CAMP}

func _free_position(sim: Variant, candidate: Vector2) -> Vector2:
	# Free tile centers also leave room for the largest .46-radius vehicle body.
	if sim.is_walkable(Vector2i(candidate.round())): return Vector2(Vector2i(candidate.round()))
	for distance: int in range(1, 5):
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP]:
			var test: Vector2 = candidate + Vector2(offset * distance)
			if sim.is_walkable(Vector2i(test.round())): return Vector2(Vector2i(test.round()))
	return candidate

