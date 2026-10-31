extends SceneTree
## Controlled source GUI integration, not ordinary play, a benchmark or human testing.
## Runs only on this task's private X11 display and isolated user-data directory.

const Readout = preload("res://scripts/command_truck_readout.gd")
var app: Variant
var checks: int = 0
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var evidence: String = ""
var finishing: bool = false
var completed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/command-truck-ui-data").trim_suffix("/")
	if DisplayServer.get_name() != "X11" or OS.get_environment("DISPLAY") != ":92" or not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Command truck GUI requires private X11 :92 and isolated command-truck-ui-data")
		quit(2)
		return
	evidence = "res://work/command-truck-ui-%d" % OS.get_process_id()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(evidence)):
		printerr("Refuse to overwrite command truck UI evidence")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence))
	create_timer(150.0).timeout.connect(_deadline)
	AudioServer.set_bus_mute(0, true)
	root.mode = Window.MODE_WINDOWED
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await _frames(6)
	app.set_process(false)
	app.start_campaign("canyon")
	app.sim.paused = true
	app.edge_scroll = false
	app.feedback_left = 0.0
	var truck: Dictionary = app.sim.get_unit(app.sim.main_truck_id)
	var main_id: int = int(truck.id)
	var extra: Dictionary = app.sim._add_unit("truck", "friendly", Vector2(truck.pos) + Vector2(3, 1), int(truck.camp_id), 3)
	_check(int(extra.id) != main_id, "fixture includes another friendly truck with a different identity")
	app.group_bindings[1] = app.selected_ids.duplicate()
	for configuration: Array in [[Vector2i(1600, 900), 1.0], [Vector2i(1440, 810), 1.0], [Vector2i(1280, 720), 1.2], [Vector2i(1152, 648), 1.2]]:
		root.size = configuration[0]
		root.content_scale_size = configuration[0]
		root.content_scale_factor = configuration[1]
		await _frames(4)
		_check(root.size == configuration[0], "actual native client reaches requested size " + str(configuration))
		_check(app.get_viewport_rect().size.is_equal_approx(Vector2(configuration[0]) / float(configuration[1])), "actual logical viewport follows UI scaling " + str(configuration))
		var card: Dictionary = _hotspot()
		_check(not card.is_empty(), "command truck has an enabled rendered action " + str(configuration))
		if card.is_empty(): continue
		_check(app.get_viewport_rect().encloses(card.rect), "command status remains inside logical viewport")
		_check(Rect2(18, 82, 300, 222).encloses(card.rect), "status stays inside the existing objective footprint")
		_check(String(card.tip).contains("选择并定位") and String(card.tip).contains("保持现有任务"), "tooltip explicitly describes selection and preserved task")
		app.ui_action("build:road")
		var before: String = _snapshot()
		var camp: int = app.selected_camp
		var groups: Dictionary = app.group_bindings.duplicate(true)
		await _click(card.rect.get_center())
		_check(app.selected_ids == [main_id] and app.selected_ids != [int(extra.id)], "real HUD click selects the designated main truck only")
		_check(app.camera.position.is_equal_approx(Vector2(truck.pos) * app.TILE), "real HUD click centers on the actual main truck")
		_check(app.selected_camp == camp and app.group_bindings == groups, "selection leaves camp and saved groups unchanged")
		_check(app.build_kind.is_empty() and app.pending_task.is_empty() and not app.dragging, "selection cleanly cancels pointer modes")
		_check(app.sim.paused and _snapshot() == before, "HUD click does not unpause, issue world orders, charge, or change simulation and RNG")
		await _capture("healthy-%d-%d" % [root.size.x, roundi(root.content_scale_factor * 100)])
	# Health fixtures are explicit test inputs; no natural combat claim is made.
	truck.hp = float(truck.max_hp) * 0.2
	await _frames()
	_check(Readout.status(app.sim).code == "critical", "off-camera critical health refreshes without a simulation tick")
	await _capture("critical-compact")
	_check(app.save_campaign(), "current valid fixture saves through normal Main storage")
	app.start_campaign("ridge")
	app.sim.paused = true
	await _frames()
	_check(Readout.status(app.sim).code == "healthy", "restart replaces the previous critical presentation")
	_check(app.load_campaign(), "normal Main load restores the saved campaign")
	await _frames()
	_check(Readout.status(app.sim).code == "critical", "normal load refreshes the saved main-truck status")
	truck = app.sim.get_unit(app.sim.main_truck_id)
	truck.hp = 0.0
	await _frames()
	_check(_hotspot().is_empty(), "destroyed main truck has no enabled selection hotspot")
	for unit: Dictionary in app.sim.units:
		if unit.team == "friendly" and unit.kind == "rifle" and float(unit.hp) > 0.0:
			app.selected_ids = [int(unit.id)]
			break
	app.ui_action("task:guard")
	await _frames()
	_check(app.pending_task == "guard" and not app.selected_ids.is_empty(), "disabled-click fixture has a living selected squad and an actual pending world task")
	var before_disabled: String = _snapshot()
	var camera_before: Vector2 = app.camera.position
	await _click(app.hud._command_truck_rect().get_center())
	_check(app.pending_task == "guard" and not app.dragging, "disabled card consumes the click instead of issuing a world task")
	_check(_snapshot() == before_disabled and app.camera.position == camera_before, "disabled click cannot mutate simulation or jump to a fallback location")
	await _capture("destroyed-disabled")
	app.sim.main_truck_id = 999999
	await _frames()
	_check(_hotspot().is_empty(), "missing identity does not offer an unrelated training truck")
	app.ui_action("select_command_truck")
	_check(app.camera.position == camera_before, "stale direct action revalidates identity before locating")
	await _capture("missing-disabled")
	completed = true
	call_deferred("_finish")

func _hotspot() -> Dictionary:
	for item: Dictionary in app.hud.hotspots:
		if item.action == "select_command_truck": return item
	return {}

func _snapshot() -> String:
	return JSON.stringify(app.sim.save_state(), "", false, true)

func _frames(count: int = 2) -> void:
	for frame: int in range(count):
		if is_instance_valid(app):
			app._process(0.0)
			app.hud.queue_redraw()
			app.world.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw

func _click(point: Vector2) -> void:
	root.warp_mouse(point)
	await _frames(1)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(1)

func _capture(label: String) -> void:
	root.warp_mouse(Vector2(app.get_viewport_rect().size.x * 0.5, 70))
	app.feedback_left = 0.0
	await _frames()
	var path: String = evidence + "/" + label + ".png"
	var image: Image = root.get_texture().get_image()
	_check(image.save_png(path) == OK, "raw GUI capture saved " + label)
	captures.append({"path":ProjectSettings.globalize_path(path), "pixels":str(image.get_size()), "physical_client":str(root.size), "logical_viewport":str(app.get_viewport_rect().size), "ui_scale":root.content_scale_factor})

func _deadline() -> void:
	if finishing: return
	_check(false, "GUI test exceeded 150 seconds or coroutine did not reach completion")
	await _finish()

func _finish() -> void:
	if finishing: return
	finishing = true
	_check(completed, "all GUI cases reached completion guard")
	var report: Dictionary = {"scope":"Controlled source GUI, synthetic health/multi-truck fixtures, private X11/software request/muted; not packaged/human/performance/full campaign", "checks":checks, "failures":failures, "captures":captures, "user_data":OS.get_user_data_dir(), "exit_path":"Main._quit_cleanly, including its existing wall-clock audio retirement"}
	var file: FileAccess = FileAccess.open(evidence + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	file = null
	print("Command truck GUI checks: %d; failures: %d; report: %s" % [checks, failures.size(), ProjectSettings.globalize_path(evidence + "/report.json")])
	for failure: String in failures: printerr(" - ", failure)
	if is_instance_valid(app):
		# Exercise production cleanup, rather than bypassing its wall-clock mixer
		# retirement with a few unthrottled virtual-display frames.
		app._quit_cleanly(0 if failures.is_empty() else 1)
	else:
		quit(0 if failures.is_empty() else 1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
