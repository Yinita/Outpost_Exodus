extends SceneTree
## Launches separate writer/reader Godot processes; no live objects cross the boundary.
## DISPLAY=:0 XDG_DATA_HOME="$PWD/work/cross-process-data" Godot --headless
##   --path . --audio-driver Dummy --script res://tests/test_cross_process.gd
## Children use real rendering and actual HUD actions, with deterministic public sim ticks.
## Controller event injection here is not a claim about native human hardware input.

const DATA_ROOT: String = "res://work/cross-process-data"
const SCRIPT_PATH: String = "res://tests/test_cross_process.gd"
const SAMPLE_TICKS: Array[int] = [10, 50, 150, 350]
const DELTA: float = 0.1

var app: Variant
var checks: int = 0
var failures: Array[String] = []
var phase: String = "coordinator"
var run_id: String = ""
var isolated_root: String = ""
var manual_path: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	isolated_root = ProjectSettings.globalize_path(DATA_ROOT).trim_suffix("/")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
		elif arg.begins_with("--run="): run_id = arg.trim_prefix("--run=")
	if not OS.get_user_data_dir().begins_with(isolated_root + "/"):
		printerr("Refusing cross-process test outside isolated XDG_DATA_HOME: ", OS.get_user_data_dir())
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(isolated_root)
	if phase == "coordinator":
		await _coordinate()
		return
	if not ["writer", "reader"].has(phase) or run_id.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Cross-process child requires a valid phase, run ID and real DISPLAY")
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	root.content_scale_factor = 1.0
	if phase == "writer":
		await _write_checkpoint_and_baseline()
	else:
		await _read_checkpoint_and_continue()
	await _finish_child()


func _coordinate() -> void:
	run_id = "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var results: Dictionary = {}
	for child_phase: String in ["writer", "reader"]:
		var result_path: String = isolated_root.path_join(child_phase + "-result.json")
		if FileAccess.file_exists(result_path): DirAccess.remove_absolute(result_path)
		var arguments: PackedStringArray = PackedStringArray([
			"--path", ProjectSettings.globalize_path("res://"),
			"--audio-driver", "Dummy", "--script", SCRIPT_PATH,
			"--", "--phase=" + child_phase, "--run=" + run_id,
		])
		var output: Array = []
		var exit_code: int = OS.execute(OS.get_executable_path(), arguments, output, true)
		var transcript: String = "".join(output)
		_write_json(isolated_root.path_join(child_phase + "-execution.json"), {"exit_code": exit_code, "output": transcript})
		print(transcript.strip_edges())
		_check(exit_code == 0, child_phase + " independent process exits successfully")
		_check(not transcript.contains("SCRIPT ERROR") and not transcript.contains("ERROR:"), child_phase + " process has no engine/script error output")
		var result: Dictionary = _read_json(result_path)
		_check(String(result.get("run", "")) == run_id and String(result.get("phase", "")) == child_phase, child_phase + " reports fresh run-specific evidence")
		_check(result.get("failures", ["missing result"]) is Array and result.get("failures", ["missing result"]).is_empty(), child_phase + " reports no failed product assertions")
		results[child_phase] = result
		if exit_code != 0: break
	var writer: Dictionary = results.get("writer", {})
	var reader: Dictionary = results.get("reader", {})
	_check(int(writer.get("pid", 0)) > 0 and int(reader.get("pid", 0)) > 0 and int(writer.get("pid", 0)) != int(reader.get("pid", 0)), "writer and reader are different native OS processes")
	_check(int(writer.get("pid", 0)) != OS.get_process_id() and int(reader.get("pid", 0)) != OS.get_process_id(), "neither product child is the coordinator process")
	var total: int = checks + int(writer.get("checks", 0)) + int(reader.get("checks", 0))
	print("Cross-process checks: %d; coordinator failures: %d; writer PID: %d; reader PID: %d" % [total, failures.size(), int(writer.get("pid", 0)), int(reader.get("pid", 0))])
	for failure: String in failures: printerr(" - " + failure)
	_write_json(isolated_root.path_join("summary.json"), {"run": run_id, "checks": total, "coordinator_failures": failures, "children": results}, false)
	quit(0 if failures.is_empty() else 1)


func _scene() -> void:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	app = scene.instantiate()
	root.add_child(app)
	await _frames(10)
	manual_path = String(app.SAVE_PATH)
	_check(ProjectSettings.globalize_path(manual_path).begins_with(isolated_root + "/"), "actual product save stays inside the isolated profile")
	_check(root.mode == Window.MODE_WINDOWED and root.size == Vector2i(1600, 900), "child renders actual product at 1600 x 900")


func _write_checkpoint_and_baseline() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for name: String in ["campaign-save.json", "campaign-save.json.bak", "campaign-autosave.json", "campaign-autosave.json.bak", "settings.cfg"]:
		var path: String = OS.get_user_data_dir().path_join(name)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	await _scene()
	await _click("new")
	await _click("pause")
	_check(app.started and app.sim.paused and app.menu.is_empty(), "writer starts and tactically pauses through the real HUD")
	var home: Dictionary = app.sim.camps[0]
	var rifles: Array[int] = []
	for unit: Dictionary in app.sim.units:
		if unit.team == "friendly" and unit.kind == "rifle": rifles.append(int(unit.id))
	_check(rifles.size() == 3, "normal mission provides three living riflemen without injected actors")
	await _click("tab:production")
	await _click("recipe:supplies")
	app.sim.command_move(rifles, Vector2(25, 20), true)
	_advance(45.0)
	var highway_captured: bool = false
	for site: Dictionary in app.sim.sites:
		if String(site.kind) == "cache" and Vector2(site.pos).distance_to(Vector2(25, 20)) < 0.1:
			highway_captured = bool(site.captured)
	_check(highway_captured, "real combat and occupation clear the first public-command objective")
	_check(bool(app.sim.build("road", Vector2i(26, 21))), "writer issues a paid real road-construction order")
	var partial: bool = false
	for tick: int in range(300):
		_advance(DELTA)
		for job: Dictionary in app.sim._jobs:
			if job.kind == "road" and not bool(job.done) and float(job.progress) > 0.0 and float(job.progress) < 1.0 and bool(job.delivered):
				partial = true
		if partial: break
	_check(partial, "checkpoint is during physically delivered, partially built road work")
	app.sim.command_move(rifles, Vector2(14, 20), false)
	_advance(0.3)
	var mover: Dictionary = app.sim.get_unit(rifles[0])
	_check(String(mover.order) == "move" and not Array(mover.path).is_empty() and Vector2(mover.pos).distance_to(Vector2(mover.target)) > 2.0, "checkpoint includes an actual unit moving along a remaining path")
	_check(String(home.recipe) == "supplies" and float(home.power_used) > 0.0 and float(home.fuel) > 0.0, "checkpoint includes supplied local powered production")
	await _key(KEY_3, true)
	await _click("speed")
	await _click("ranges")
	await _click("logistics")
	await _click("guide_toggle")
	await _click("minimap")
	app.guide.update(app.sim, app.selected_ids, app.selected_camp)
	_check(int(app.guide.get_hint()["step"]) == 2 and not bool(app.guide.get_hint()["visible"]), "real progressed guide is hidden at save time")
	_check(float(app.speed) == 2.0 and app.world.show_ranges and not app.world.show_logistics, "actual HUD configures nondefault speed and overlays")
	_check(app.group_bindings.get(3, []).size() == 4 and app.selected_ids.size() == 4, "actual Ctrl+3 creates a four-member numbered formation")
	var checkpoint: Dictionary = app._save_payload()
	var metrics: Dictionary = _metrics()
	await _click("menu")
	await _click("save")
	_check(FileAccess.file_exists(manual_path) and FileAccess.file_exists(manual_path + ".bak"), "real save menu creates primary and first backup on disk")
	var persisted: Dictionary = app.save_store.read(manual_path)
	_check(bool(persisted.get("ok", false)) and _equal(checkpoint, persisted.get("data", {})), "disk checkpoint contains the complete current product payload")
	var hash_before: String = FileAccess.get_sha256(manual_path)
	var trajectory: Array[Dictionary] = _trajectory()
	_verify_progress(metrics)
	_check(FileAccess.get_sha256(manual_path) == hash_before, "uninterrupted baseline continuation does not rewrite the saved checkpoint")
	_write_json(isolated_root.path_join("baseline.json"), {"run": run_id, "writer_pid": OS.get_process_id(), "checkpoint": checkpoint, "metrics": metrics, "trajectory": trajectory, "save_sha256": hash_before})
	_check(FileAccess.file_exists(isolated_root.path_join("baseline.json")), "writer publishes its independently continued baseline")


func _read_checkpoint_and_continue() -> void:
	var baseline: Dictionary = _read_json(isolated_root.path_join("baseline.json"))
	_check(String(baseline.get("run", "")) == run_id and int(baseline.get("writer_pid", 0)) != OS.get_process_id(), "reader receives only serialized evidence from a different writer process")
	await _scene()
	_check(not app.started and app.menu == "title", "fresh reader begins at the real title instead of reusing writer objects")
	_check(FileAccess.get_sha256(manual_path) == String(baseline.get("save_sha256", "")), "reader sees the exact checkpoint bytes written before writer exit")
	await _click("load")
	_check(app.started and app.menu.is_empty() and app.sim.paused, "title load action restores the old tactically paused campaign")
	_check(_equal(app._save_payload(), baseline.get("checkpoint", {})), "fresh process restores complete simulation plus UI and guide checkpoint" + _difference(baseline.get("checkpoint", {}), app._save_payload()))
	var checkpoint_ui: Dictionary = baseline.get("checkpoint", {}).get("ui", {})
	var selected: bool = app.selected_ids.size() == checkpoint_ui.get("selected_ids", []).size()
	var grouped: bool = app.group_bindings.get(3, []).size() == checkpoint_ui.get("groups", {}).get("3", []).size()
	for id_value: Variant in checkpoint_ui.get("selected_ids", []): selected = selected and app.selected_ids.has(int(id_value))
	for id_value: Variant in checkpoint_ui.get("groups", {}).get("3", []): grouped = grouped and app.group_bindings.get(3, []).has(int(id_value))
	_check(selected and grouped, "restored selection and numbered formation contain real integer IDs")
	_check(int(app.guide.get_hint()["step"]) == 2 and not bool(app.guide.get_hint()["visible"]), "fresh process retains hidden guide visibility and genuine objective progress")
	_check(float(app.speed) == 2.0 and app.world.show_ranges and not app.world.show_logistics, "fresh process retains gameplay speed and both overlay settings")
	var continued: Array[Dictionary] = _trajectory()
	var expected: Array = baseline.get("trajectory", [])
	_check(continued.size() == SAMPLE_TICKS.size() and expected.size() == continued.size(), "both processes capture the same four continuation times")
	for index: int in range(mini(continued.size(), expected.size())):
		_check(_equal(continued[index]["state"], expected[index]["state"]), "resumed full state matches uninterrupted baseline after %.1f more simulated seconds" % float(continued[index]["elapsed"]) + _difference(expected[index]["state"], continued[index]["state"]))
		_check(_equal(continued[index]["metrics"], expected[index]["metrics"]), "resumed road, movement and inventory outcomes match baseline at sample %d" % index)
	_verify_progress(baseline.get("metrics", {}))
	_check(FileAccess.get_sha256(manual_path) == String(baseline.get("save_sha256", "")), "reader continuation preserves the original disk save")
	await _click("guide_toggle")
	_check(bool(app.guide.get_hint()["visible"]), "persisted hidden guide can be restored after cross-process continuation")


func _trajectory() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tick: int in range(1, SAMPLE_TICKS.back() + 1):
		app.sim.paused = false
		app.sim.tick(DELTA)
		if SAMPLE_TICKS.has(tick):
			app.sim.paused = true
			app.guide.update(app.sim, app.selected_ids, app.selected_camp)
			result.append({"elapsed": tick * DELTA, "state": app._save_payload(), "metrics": _metrics()})
	app.sim.paused = true
	return result


func _metrics() -> Dictionary:
	var complete_roads: int = 0
	var unfinished_roads: int = 0
	for tile: Variant in app.sim.roads:
		var road: Dictionary = app.sim.roads[tile]
		if float(road.progress) >= 1.0: complete_roads += 1
		else: unfinished_roads += 1
	var completed_jobs: int = 0
	for job: Dictionary in app.sim._jobs:
		if job.kind == "road" and bool(job.done): completed_jobs += 1
	var home: Dictionary = app.sim.camps[0]
	var rifle: Dictionary = {}
	for unit: Dictionary in app.sim.units:
		if unit.team == "friendly" and unit.kind == "rifle":
			rifle = unit
			break
	var position: Vector2 = rifle.get("pos", Vector2.ZERO)
	return {"time": app.sim.time, "outcome": app.sim.outcome, "supplies": home.supplies, "fuel": home.fuel, "completed_roads": complete_roads, "unfinished_roads": unfinished_roads, "completed_jobs": completed_jobs, "rifle_position": [position.x, position.y], "rifle_target_distance": position.distance_to(Vector2(14, 20))}


func _verify_progress(before: Dictionary) -> void:
	var after: Dictionary = _metrics()
	_check(String(after.outcome) == "playing" and float(after.time) > float(before.get("time", INF)) + 34.0, "continuation advances a living campaign for 35 simulated seconds")
	_check(float(after.supplies) > float(before.get("supplies", INF)) and float(after.fuel) < float(before.get("fuel", -INF)), "production really continues consuming fuel and adding usable supplies")
	_check(int(after.completed_jobs) > int(before.get("completed_jobs", 999)) and int(after.unfinished_roads) == 0 and int(after.completed_roads) > int(before.get("completed_roads", 999)), "the saved partial road physically finishes after continuation")
	_check(float(after.rifle_target_distance) < 0.8 and float(after.rifle_target_distance) < float(before.get("rifle_target_distance", -INF)), "the saved moving rifleman actually arrives at the ordered destination")


func _advance(seconds: float) -> void:
	app.sim.paused = false
	for tick: int in range(ceili(seconds / DELTA)): app.sim.tick(DELTA)
	app.sim.paused = true


func _frames(count: int = 4) -> void:
	for frame: int in range(count):
		if is_instance_valid(app): app.hud.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw


func _click(action: String) -> bool:
	await _frames()
	for hotspot: Dictionary in app.hud.hotspots:
		if String(hotspot.get("action", "")) != action: continue
		var rectangle: Rect2 = hotspot["rect"]
		_check(app.hud.get_viewport_rect().encloses(rectangle), "HUD action fits the logical viewport: " + action)
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = rectangle.get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		var consumed: bool = app.hud.handle_mouse(event)
		_check(consumed, "actual HUD consumes " + action)
		await _frames()
		return consumed
	_check(false, "actual HUD exposes " + action + " in menu " + String(app.menu))
	return false


func _key(code: Key, control: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.ctrl_pressed = control
	event.pressed = true
	app._unhandled_input(event)
	await _frames()
	event.pressed = false
	app._unhandled_input(event)


func _equal(expected: Variant, actual: Variant) -> bool:
	return _difference(expected, actual).is_empty()


func _difference(expected: Variant, actual: Variant, path: String = "$") -> String:
	if (expected is int or expected is float) and (actual is int or actual is float):
		return "" if absf(float(expected) - float(actual)) <= 0.00001 else " at %s: %s != %s" % [path, str(expected), str(actual)]
	if expected is Dictionary and actual is Dictionary:
		if expected.size() != actual.size(): return " at %s: dictionary lengths differ" % path
		for key: Variant in expected:
			if not actual.has(key): return " at %s: missing %s" % [path, str(key)]
			var difference: String = _difference(expected[key], actual[key], path + "." + str(key))
			if not difference.is_empty(): return difference
		return ""
	if expected is Array and actual is Array:
		if expected.size() != actual.size(): return " at %s: array lengths %d != %d" % [path, expected.size(), actual.size()]
		for index: int in range(expected.size()):
			var difference: String = _difference(expected[index], actual[index], path + "[%d]" % index)
			if not difference.is_empty(): return difference
		return ""
	return "" if typeof(expected) == typeof(actual) and expected == actual else " at %s: %s != %s" % [path, str(expected), str(actual)]


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)


func _read_json(path: String) -> Dictionary:
	if not path.begins_with(isolated_root + "/"): return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	file.close()
	return parser.data if error == OK and parser.data is Dictionary else {}


func _write_json(path: String, data: Dictionary, checked: bool = true) -> void:
	if checked: _check(path.begins_with(isolated_root + "/"), "evidence write stays inside isolated test data")
	if not path.begins_with(isolated_root + "/"): return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if checked: _check(file != null, "evidence file opens: " + path.get_file())
	if file == null: return
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.flush()
	if checked: _check(file.get_error() == OK, "evidence flush succeeds: " + path.get_file())
	file.close()


func _finish_child() -> void:
	if is_instance_valid(app):
		app.fullscreen = false
		app.ui_scale = 1.0
		app.window_resolution = Vector2i(1600, 900)
		app.display_configured = true
		app._apply_display_settings()
		app.queue_free()
		await _frames(6)
	for failure: String in failures: printerr(" - " + failure)
	print("Cross-process %s checks: %d; failures: %d; PID: %d" % [phase, checks, failures.size(), OS.get_process_id()])
	_write_json(isolated_root.path_join(phase + "-result.json"), {"run": run_id, "phase": phase, "pid": OS.get_process_id(), "checks": checks, "failures": failures}, false)
	quit(0 if failures.is_empty() else 1)
