extends SceneTree
## Native rendered-frame benchmark, distinct from headless CPU and export proof.
## Quick fixture/parse check (36 sampled/warmup frames plus setup):
##   BENCH_ISOLATION_ROOT="$PWD/work/benchmarks/render-isolation" \
##   XDG_DATA_HOME="$PWD/work/benchmarks/render-isolation/data" \
##   XDG_CONFIG_HOME="$PWD/work/benchmarks/render-isolation/config" \
##   XDG_CACHE_HOME="$PWD/work/benchmarks/render-isolation/cache" \
##   DISPLAY=:0 timeout 60 ./run.sh -s tests/benchmark_rendered.gd -- --quick
## Full: replace --quick with --frames=600 --warmup=120 --output-dir=res://work/benchmarks/rendered-baseline
## Use an idle desktop and unchanged source for each baseline/candidate pair.

const MAIN_SCENE = preload("res://main.tscn")
const FRONT_CAMP: int = 5000
const PIXELS: Vector2i = Vector2i(1920, 1080)
const TRACKED_SOURCES: Array[String] = [
	"res://project.godot", "res://main.tscn", "res://scripts/main.gd",
	"res://scripts/campaign_simulation.gd", "res://scripts/world_view.gd",
	"res://scripts/construction_rules.gd", "res://scripts/actor_atlas.gd", "res://scripts/actor_canvas.gd",
	"res://scripts/recruitment_rules.gd", "res://scripts/game_audio.gd",
	"res://scripts/cartoon_canvas.gd", "res://scripts/terrain_cache.gd", "res://scripts/decoration_cache.gd",
	"res://scripts/hud.gd", "res://scripts/campaign_guide.gd",
	"res://tests/benchmark_campaign.gd", "res://tests/benchmark_rendered.gd",
	"res://assets/buildings-atlas.png", "res://assets/fonts/NotoSansCJK-Regular.ttc",
	"res://assets/audio/canyon_ambient.wav", "res://assets/audio/sfx_shot_a.wav", "res://assets/audio/sfx_shot_b.wav",
	"res://assets/audio/sfx_impact.wav", "res://assets/audio/sfx_loot.wav", "res://assets/audio/sfx_confirm.wav",
	"res://assets/audio/sfx_reject.wav", "res://assets/audio/sfx_build.wav", "res://assets/audio/sfx_warning.wav",
]

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
var output_dir: String = "res://work/benchmarks/rendered"
var errors: Array[String] = []
var main: Node2D
var setup: Dictionary = {}
var report: Dictionary = {}
var workload: Dictionary = {}
var previous_hauling: Dictionary = {}
var finished: bool = false
var started_usec: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--quick": quick = true
		elif argument == "--prepare-only": prepare_only = true
		elif argument == "--uncapped": uncapped = true
		elif argument.begins_with("--frames="): frames = clampi(argument.trim_prefix("--frames=").to_int(), 600, 3600)
		elif argument.begins_with("--warmup="): warmup = clampi(argument.trim_prefix("--warmup=").to_int(), 120, 600)
		elif argument.begins_with("--max-seconds="): max_seconds = clampi(argument.trim_prefix("--max-seconds=").to_int(), 30, 600)
		elif argument.begins_with("--zoom="): zoom_filter = argument.trim_prefix("--zoom=")
		elif argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=").simplify_path()
		else: errors.append("unknown benchmark argument: " + argument)
	if quick:
		warmup = 6
		frames = 12
	if prepare_only:
		warmup = 0
		frames = 1
	if zoom_filter not in ["both", "normal", "strategic"]: errors.append("--zoom must be both, normal or strategic")
	if not output_dir.begins_with("res://work/benchmarks/"): errors.append("output must be inside ignored res://work/benchmarks/")
	_check_isolation()
	if DisplayServer.get_name() == "headless": errors.append("a native display is required; headless is not rendered-frame evidence")
	if not errors.is_empty():
		for error: String in errors: printerr("RENDER_BENCH_INVALID ", error)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	started_usec = Time.get_ticks_usec()
	create_timer(max_seconds).timeout.connect(_on_timeout)
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = PIXELS
	root.content_scale_size = PIXELS
	root.content_scale_factor = 1.0
	root.position = DisplayServer.screen_get_position() + (DisplayServer.screen_get_size() - PIXELS) / 2
	root.title = "Outpost Exodus — rendered benchmark"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if uncapped else DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 0
	if RenderingServer.has_method("viewport_set_measure_render_time"):
		RenderingServer.call("viewport_set_measure_render_time", root.get_viewport_rid(), true)
	report = {
		"recorded_utc": Time.get_datetime_string_from_system(true, true) + "Z",
		"runtime": Engine.get_version_info(), "platform": OS.get_name(), "os_version": OS.get_version(),
		"debug_build": OS.is_debug_build(), "editor_capable_runtime": OS.has_feature("editor"),
		"native_export_proof": false,
		"cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"display_server": DisplayServer.get_name(), "display_environment": OS.get_environment("DISPLAY"),
		"gpu_adapter": RenderingServer.get_video_adapter_name(), "gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"screen_size": _vector(DisplayServer.screen_get_size()), "screen_refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"window_size": _vector(root.size), "viewport_size": _vector(Vector2i(root.get_visible_rect().size)),
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"user_data_dir": OS.get_user_data_dir(), "sources_before": _source_hashes(),
		"fixture_functions_sha256": _fixture_source("res://tests/benchmark_rendered.gd").sha256_text(),
		"campaign_fixture_functions_sha256": _fixture_source("res://tests/benchmark_campaign.gd").sha256_text(),
		"memory_start": _memory_snapshot(), "system_memory": _proc_memory("/proc/meminfo", ["MemTotal", "MemAvailable"]),
		"method": {
			"quick_check_only": quick or prepare_only, "prepare_only": prepare_only,
			"runs_per_zoom": 1, "warmup_frames_per_zoom": warmup, "measured_frames_per_zoom": frames,
			"max_wall_seconds": max_seconds, "fixed_simulation_step_seconds": 0.05,
			"frame_scope": "Wall intervals between successive RenderingServer.frame_post_draw signals from the actual native main scene, including real world/HUD drawing, main processing and renderer/presentation pacing. This is not a physical display scanout measurement.",
			"simulation_scope": "Actual main._process accumulator invokes the timed subclass of campaign_simulation.tick(0.05) at 20 Hz. Each tick timer wraps only super.tick; workload observation follows that timer and is included in wall intervals.",
			"render_scope": "RenderingServer viewport render CPU/GPU and frame setup CPU milliseconds where supported. These exclude game scripts; zero values may mean unavailable backend instrumentation. Performance process/physics monitors are engine-reported samples, not additive isolated subsystem times.",
			"render_timing_reference": "https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-cpu",
			"fixture": "Exact copied busy fixture and helpers from tests/benchmark_campaign.gd, except TimedSimulation subclass. 32 friendly actors, 100 enemies, connected salvage hauling, powered production, three paid building orders and one paid road order. Increased actor/building HP retains the workload; this is not balanced-combat evidence.",
			"counters": "Observed after each actual simulation tick. Cargo/shot values count actor/effect observations; hauling deliveries require cargo-to-empty transition near owner camp.",
			"screenshots": "Saved after the measured interval; GPU readback/PNG encoding is excluded from sampled frame intervals. RSS probes occur before/after each zoom, outside sampled intervals.",
			"percentiles": "Nearest rank over individual measured frames/ticks; FPS is measured frame count / total measured interval, not mean instantaneous FPS.",
			"limits": "Local native editor-capable runtime, not an exported build or minimum hardware claim. OS and other processes are uncontrolled. Quick/prepare runs validate fixture only and cannot substantiate performance. The harness does not move the cursor or change desktop display modes.",
		},
		"zooms": [],
	}
	if report.fixture_functions_sha256 != report.campaign_fixture_functions_sha256:
		errors.append("copied busy fixture differs from benchmark_campaign.gd; refresh the fixture before comparing")
	for zoom: Dictionary in [{"name": "normal", "value": 1.05}, {"name": "strategic", "value": 0.35}]:
		if zoom_filter != "both" and zoom_filter != str(zoom.name): continue
		if finished: return
		var result: Dictionary = await _measure_zoom(zoom)
		if finished: return
		report.zooms.append(result)
		print("RENDER_BENCH_ZOOM ", str(zoom.name), " ", JSON.stringify(result.frame_ms), " ticks=", result.simulation_ticks, " workload=", str(result.workload))
	await _finish()

func _check_isolation() -> void:
	var isolation: String = OS.get_environment("BENCH_ISOLATION_ROOT").simplify_path()
	var allowed_root: String = ProjectSettings.globalize_path("res://work/benchmarks/")
	if isolation.is_empty() or not isolation.is_absolute_path() or not isolation.begins_with(allowed_root):
		errors.append("BENCH_ISOLATION_ROOT must be an absolute dedicated directory inside project work/benchmarks/")
		return
	for key: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var value: String = OS.get_environment(key).simplify_path()
		if not value.begins_with(isolation + "/"): errors.append(key + " must be a dedicated child of BENCH_ISOLATION_ROOT")
	if not OS.get_user_data_dir().begins_with(isolation + "/"):
		errors.append("Godot user:// is outside the isolated benchmark root; refusing to load real settings")
	for path: String in ["user://settings.cfg", "user://campaign-save.json", "user://campaign-autosave.json"]:
		if FileAccess.file_exists(path): errors.append("isolated benchmark must not contain existing settings/saves: " + path)

func _install_scene(zoom: Dictionary) -> void:
	if is_instance_valid(main):
		main.set_process(false)
		main._release_audio()
		main.sim.tick_observer = Callable()
		main.free()
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main
	main.set_process(false)
	main.set_process_input(false)
	main.set_process_unhandled_input(false)
	setup = _make_busy_scene()
	main.sim = setup.sim
	main.world.sim = main.sim
	main.started = true
	main.menu = ""
	main.speed = 1.0
	main.accumulator = 0.0
	main.autosave_time = 0.0
	main.tick_count = 0
	main.edge_scroll = false
	main.selected_camp = FRONT_CAMP
	main.selected_ids.clear()
	for unit: Dictionary in main.sim.units:
		if unit.team == "friendly" and unit.kind == "rifle": main.selected_ids.append(int(unit.id))
	main.guide.reset(main.guide_enabled)
	main.feedback_left = 0.0
	main.window_resolution = PIXELS
	main.ui_scale = 1.0
	main.camera.position = Vector2(29.0, 23.0) * 48.0
	main.camera.zoom = Vector2.ONE * float(zoom.value)
	main.camera.force_update_scroll()
	main.sim.tick_observer = _observe_workload
	main.world.queue_redraw()
	main.hud.queue_redraw()
	main.set_process(true)

func _measure_zoom(zoom: Dictionary) -> Dictionary:
	var errors_before: int = errors.size()
	_install_scene(zoom)
	await RenderingServer.frame_post_draw
	for index: int in range(warmup):
		await RenderingServer.frame_post_draw
		if finished: return {}
	var sim: Variant = main.sim
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
	var start_tick: int = main.tick_count
	var previous_tick: int = start_tick
	var simulated_start: float = sim.time
	for index: int in range(frames):
		await RenderingServer.frame_post_draw
		if finished: return {}
		var now: int = Time.get_ticks_usec()
		frames_usec.append(now - previous)
		previous = now
		ticks_per_frame.append(main.tick_count - previous_tick)
		previous_tick = main.tick_count
		metrics.performance_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		metrics.performance_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		metrics.draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		metrics.rendered_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		metrics.rendered_primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		_append_render_metric(metrics.render_setup_cpu_ms, "get_frame_setup_time_cpu")
		_append_render_metric(metrics.viewport_render_cpu_ms, "viewport_get_measured_render_time_cpu", true)
		_append_render_metric(metrics.viewport_render_gpu_ms, "viewport_get_measured_render_time_gpu", true)
	sim.collect = false
	main.set_process(false)
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
	var image: Image = root.get_texture().get_image()
	var screenshot: String = output_dir + "/" + str(zoom.name) + ".png"
	var screenshot_result: Error = image.save_png(screenshot)
	if screenshot_result != OK: errors.append("screenshot save failed: " + screenshot)
	if image.get_size() != PIXELS or root.size != PIXELS: errors.append("render/window is not actual 1920x1080")
	var actor_count: Dictionary = _actor_counts(sim)
	if actor_count.friendly != 32 or actor_count.enemy != 100: errors.append("fixture lost requested 32 friendly / 100 enemy actors")
	if sim.outcome != "playing" or not main.menu.is_empty(): errors.append("gameplay stopped or opened a menu")
	if setup.construction_ids.size() != 3: errors.append("fixture did not enqueue all three paid building orders")
	if not quick and not prepare_only:
		if workload.hauling_cargo_samples == 0 or workload.hauling_deliveries == 0: errors.append("no real resource pickup and delivery observed; increase --frames or investigate hauling")
		if workload.combat_effect_samples == 0: errors.append("no actual combat observed")
		if workload.construction_max_progress_delta <= 0.0: errors.append("paid construction did not advance in measurement")
		if workload.friendly_min != 32 or workload.enemy_min != 100: errors.append("busy actor population was not retained throughout measurement")
	return {
		"name": zoom.name, "zoom": zoom.value,
		"camera_tile": _vector(main.camera.position / 48.0),
		"warmup_frames": warmup, "measured_frames": frames,
		"frame_ms": frame_stats, "frame_intervals_usec": frames_usec,
		"simulation_tick_ms": _time_stats(sim.tick_samples_usec), "simulation_tick_samples_usec": sim.tick_samples_usec.duplicate(),
		"simulation_ticks": main.tick_count - start_tick, "ticks_per_frame": ticks_per_frame,
		"simulated_seconds_measured": sim.time - simulated_start,
		"actual_fixed_step_hz": 20.0, "speed": main.speed,
		"available_engine_metrics": metric_stats, "engine_metric_samples": metrics,
		"workload": workload.duplicate(true), "actor_counts_end": actor_count,
		"construction_ids": setup.construction_ids.duplicate(),
		"remaining_nearby_salvage": _site_stock(sim, 6000, "salvage"),
		"screenshot": ProjectSettings.globalize_path(screenshot), "screenshot_pixels": _vector(image.get_size()),
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
	for building: Dictionary in main.sim.buildings:
		if setup.construction_ids.has(int(building.id)):
			workload.construction_start_progress = maxf(workload.construction_start_progress, float(building.progress))
			workload.construction_start_progress_by_id[int(building.id)] = float(building.progress)
	# A warmup may finish with loaded carriers; seed transition tracking there.
	for unit: Dictionary in main.sim.units:
		previous_hauling[int(unit.id)] = str(unit.get("order", "")) == "haul" and not Dictionary(unit.get("cargo", {})).is_empty()

func _observe_workload() -> void:
	var start: int = Time.get_ticks_usec()
	var sim: Variant = main.sim
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
	var value: float = float(RenderingServer.call(method, root.get_viewport_rid()) if viewport else RenderingServer.call(method))
	if is_finite(value): values.append(value)

func _on_timeout() -> void:
	if finished: return
	errors.append("internal wall-time cap exceeded")
	await _finish()

func _finish() -> void:
	if finished: return
	finished = true
	if is_instance_valid(main):
		main.set_process(false)
		main.set_process_input(false)
		main.set_process_unhandled_input(false)
		main.sim.collect = false
		main.sim.tick_observer = Callable()
		main._release_audio()
	report["memory_end"] = _memory_snapshot()
	report["sources_after"] = _source_hashes()
	report["source_changed_during_run"] = report.get("sources_before", {}) != report.sources_after
	if report.source_changed_during_run: errors.append("source/assets changed during the run; rerun against a stable candidate")
	report["wall_elapsed_seconds"] = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	report["errors"] = errors
	report["valid_workload"] = errors.is_empty()
	report["performance_evidence"] = errors.is_empty() and not quick and not prepare_only
	var path: String = output_dir + "/rendered-benchmark.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("RENDER_BENCH_INVALID report could not be written")
		errors.append("report write failed")
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("RENDER_BENCH_REPORT ", ProjectSettings.globalize_path(path))
	for error: String in errors: printerr("RENDER_BENCH_INVALID ", error)
	# Match main's audio retirement interval, then destroy the real scene cleanly.
	await create_timer(0.12).timeout
	if is_instance_valid(main): main.free()
	setup.clear()
	quit(0 if errors.is_empty() else 1)

func _fixture_source(path: String) -> String:
	var source: String = FileAccess.get_file_as_string(path)
	var start: int = source.find("\nfunc " + "_make_busy_scene()") + 1
	var end: int = source.find("\nfunc " + "_measure_run(", start)
	if start < 0: return ""
	return source.substr(start, end - start if end >= 0 else -1).strip_edges().replace("TimedSimulation.new()", "Simulation.new()")

func _source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in TRACKED_SOURCES: result[path] = FileAccess.get_sha256(path)
	return result

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

