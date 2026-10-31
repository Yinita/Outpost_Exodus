extends SceneTree
## Headless readout/controller checks with real admitted transport and SaveStore.
## Controlled fixtures and a constructed hotspot do not establish native pixels,
## actual HUD drawing, human usability, listening or performance acceptance.
## XDG_DATA_HOME="$PWD/work/command-status-data" ./run.sh --headless
##   --script res://tests/test_command_truck_status.gd

const Readout = preload("res://scripts/command_truck_readout.gd")

class CountingSim:
	extends "res://scripts/campaign_simulation.gd"
	var move_calls: int = 0
	var task_calls: int = 0
	func command_move(ids: Array, target: Vector2, attack: bool = false) -> void:
		move_calls += 1
		super.command_move(ids, target, attack)
	func command_task(ids: Array, task: String, target: Vector2) -> void:
		task_calls += 1
		super.command_task(ids, task, target)

class QuietMain:
	extends "res://scripts/main.gd"
	func _ready() -> void: pass
	func _play_tone(_frequency: float, _duration: float, _gain: float = 0.25) -> void: pass
	func _play_sfx(_cue: String, _gain: float = 1.0) -> void: pass

class QuietWorld:
	extends "res://scripts/world_view.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _draw() -> void: pass

class QuietHud:
	extends "res://scripts/hud.gd"
	func _ready() -> void: pass
	func _draw() -> void: pass

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/command-status-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Command truck checks require isolated work/command-status-data")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for test: Callable in [_test_exact_identity_and_health, _test_detached_read_only_queries, _test_real_orders_and_focus, _test_invalid_action_does_not_jump, _test_load_and_new_run]:
		var previous: int = failures.size()
		test.call()
		print("%s %s" % ["PASS" if failures.size() == previous else "FAIL", test.get_method()])
	print("Command truck status checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)


func _snapshot(sim: Variant) -> String:
	return JSON.stringify(sim.save_state())


func _fixture() -> Variant:
	var sim: Variant = CountingSim.new()
	sim.reset(42)
	for y: int in range(sim.map_size.y):
		for x: int in range(sim.map_size.x): sim.terrain[y][x] = 0
	sim.ramps = {}
	sim.roads = {}
	sim.camps = []
	sim.buildings = []
	sim.units = []
	sim.sites = []
	sim.effects = []
	sim.messages = []
	sim.chokes = []
	sim._jobs = []
	sim._next_id = 10000
	var origin: Dictionary = sim._make_camp(Vector2(6, 10), "西侧源营", 1000.0, 500.0, 100.0)
	var receiver: Dictionary = sim._make_camp(Vector2(26, 10), "前线接收营", 0.0, 0.0, 0.0)
	origin.recipe = "idle"
	receiver.recipe = "idle"
	sim._add_building("command", origin.pos, int(origin.id), 1.0)
	sim._add_building("command", receiver.pos, int(receiver.id), 1.0)
	for x: int in range(5, 28):
		for y: int in range(9, 14): sim.roads[Vector2i(x, y)] = {"progress": 1.0, "camp_id": int(origin.id)}
	# First matching kind is deliberately NOT the command vehicle.
	sim._add_unit("truck", "friendly", Vector2(3, 8), int(origin.id), 0)
	var command: Dictionary = sim._add_unit("truck", "friendly", Vector2(5, 11), int(origin.id), 0)
	sim.main_truck_id = int(command.id)
	for position: Vector2 in [Vector2(12, 18), Vector2(13, 18), Vector2(14, 18), Vector2(15, 18)]:
		sim._add_unit("rifle", "friendly", position, int(origin.id), 1)
	sim.exit_site_id = 0
	sim.exit_building_id = 0
	sim.pursuit_x = -10000.0
	sim.pursuit_start = 1000000.0
	sim._invalidate_navigation()
	return sim


func _expect(sim: Variant, code: String, enabled: bool, label: String) -> Dictionary:
	var before: String = _snapshot(sim)
	var rng_before: int = sim._rng.state
	var row: Dictionary = Readout.status(sim)
	_check(row.get("code", "") == code and row.get("enabled", not enabled) == enabled, label + " has exact status and eligibility")
	_check(row.get("label") is String and not str(row.get("label", "")).is_empty() and row.get("tooltip") is String and not str(row.get("tooltip", "")).is_empty(), label + " has visible text and explanation")
	_check(row.get("hp") is float and row.get("max_hp") is float, label + " exposes numeric HP as floats")
	_check(_snapshot(sim) == before and sim._rng.state == rng_before, label + " preserves full saved simulation and RNG")
	return row


func _test_exact_identity_and_health() -> void:
	var sim: Variant = _fixture()
	var command: Dictionary = sim.get_unit(int(sim.main_truck_id))
	var ordinary: Dictionary = sim.units[0]
	ordinary.hp = 10.0
	var row: Dictionary = _expect(sim, "healthy", true, "healthy second truck beside a critical ordinary truck")
	_check(int(row.get("unit_id", 0)) == int(command.id) and float(row.hp) == 380.0 and float(row.max_hp) == 380.0, "readout follows main_truck_id rather than first truck or lowest HP")
	command.hp = 200.5
	row = _expect(sim, "damaged", true, "wounded command vehicle")
	_check(float(row.hp) == 200.5, "readout preserves actual fractional HP")
	command.hp = 114.01
	_expect(sim, "damaged", true, "just above thirty percent")
	command.hp = 114.0
	_expect(sim, "critical", true, "exactly thirty percent")
	command.hp = 1.0
	_expect(sim, "critical", true, "living one-HP command vehicle")
	command.hp = 0.0
	_expect(sim, "destroyed", false, "destroyed main vehicle with another live truck available")
	command.hp = 380.0
	command.team = "enemy"
	_expect(sim, "missing", false, "recorded ID points to wrong team")
	command.team = "friendly"
	command.kind = "rifle"
	_expect(sim, "missing", false, "recorded ID points to wrong kind")
	command.kind = "truck"
	command.max_hp = 0.0
	_expect(sim, "missing", false, "zero maximum HP is not a selectable vehicle")
	command.max_hp = INF
	_check(not Readout.status(sim).enabled, "non-finite maximum HP cannot enable selection")
	command.max_hp = 380.0
	command.hp = NAN
	_check(not Readout.status(sim).enabled, "non-finite current HP cannot enable selection")
	command.hp = 380.0
	_check(not Readout.status(null).enabled, "missing simulation has an unavailable detached readout")
	var saved_position: Vector2 = command.pos
	command.pos = Vector2(NAN, 1.0)
	_check(not Readout.status(sim).enabled, "non-finite position cannot enable unsafe camera focus")
	command.pos = "unknown"
	_check(not Readout.status(sim).enabled, "wrong position type cannot enable camera focus")
	command.pos = saved_position
	sim.main_truck_id = 999999
	_expect(sim, "missing", false, "missing recorded ID never falls back to an ordinary truck")
	sim.main_truck_id = 0
	_expect(sim, "missing", false, "unset recorded ID")


func _test_detached_read_only_queries() -> void:
	var sim: Variant = _fixture()
	var before: String = _snapshot(sim)
	var rng_before: int = sim._rng.state
	var baseline: Dictionary = Readout.status(sim)
	for index: int in range(16):
		var row: Dictionary = Readout.status(sim)
		_check(row == baseline, "stable repeated readout %d" % index)
		row["hp"] = -999.0
		row["unit_id"] = -999
		row["label"] = "caller override"
		row["tooltip"] = "caller override"
		row["extra"] = {"caller": true}
	_check(Readout.status(sim) == baseline, "returned dictionaries are detached from later results")
	_check(_snapshot(sim) == before and sim._rng.state == rng_before, "caller mutation and repeated observations preserve full save and RNG")


func _app(sim: Variant) -> Variant:
	var app: Variant = QuietMain.new()
	root.add_child(app)
	app.set_process(false)
	app.sim = sim
	app.world = QuietWorld.new()
	app.world.sim = sim
	app.add_child(app.world)
	app.hud = QuietHud.new()
	app.hud.main = app
	app.add_child(app.hud)
	app.camera = Camera2D.new()
	app.add_child(app.camera)
	app.started = true
	app.menu = ""
	app.selected_camp = int(sim.camps[1].id)
	app.guide.reset(true)
	app.guide.update(sim, [], app.selected_camp)
	return app


func _prime_pointer_modes(app: Variant) -> void:
	app.selected_ids = [int(app.sim.units[0].id), int(app.sim.units[2].id)]
	app.camera.position = Vector2(1111, 777)
	app.build_kind = "generator"
	app.pending_task = "clear"
	app.attack_move = true
	app.dragging = true
	app.selection_double_click = true
	app.pan_active = true
	app.selected_project_id = 999999
	app.construction_readout = {"building_id": 999999}


func _focus_preserves_orders(app: Variant, via_hotspot: bool, label: String) -> void:
	_prime_pointer_modes(app)
	var camp: int = app.selected_camp
	var paused: bool = app.sim.paused
	var speed: float = app.speed
	var tab: String = app.current_tab
	var zoom: Vector2 = app.camera.zoom
	var before: String = _snapshot(app.sim)
	var rng_before: int = app.sim._rng.state
	var command: Dictionary = app.sim.get_unit(int(app.sim.main_truck_id))
	app.sim.move_calls = 0
	app.sim.task_calls = 0
	if via_hotspot:
		var rect: Rect2 = app.hud._command_truck_rect()
		_check(rect == Rect2(34, 153, 266, 31), "pure command control geometry preserves objective lines")
		_check(Rect2(18, 82, 300, 305).encloses(rect), "command control remains inside the existing objective panel")
		app.hud.hotspots.clear()
		app.hud.hotspots.append({"rect": rect, "action": "select_command_truck", "tip": "test dispatch"})
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = rect.get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		_check(app.hud.handle_mouse(event), "real HUD mouse handler consumes the constructed command hotspot")
	else:
		app.ui_action("select_command_truck")
	_check(app.selected_ids == [int(command.id)], label + " selects only the recorded command vehicle")
	_check(app.camera.position == Vector2(command.pos) * 48.0 and app.camera.zoom == zoom, label + " focuses actual vehicle position without changing zoom")
	_check(app.selected_camp == camp and app.sim.paused == paused and app.speed == speed and app.current_tab == tab, label + " preserves selected camp, pause, speed and tab")
	_check(app.build_kind.is_empty() and app.pending_task.is_empty() and not app.attack_move and not app.dragging and not app.selection_double_click and not app.pan_active and app.selected_project_id == 0 and app.construction_readout.is_empty(), label + " clears incompatible pointer and project modes")
	_check(_snapshot(app.sim) == before and app.sim._rng.state == rng_before, label + " preserves complete simulation including order, cargo, path and economics")
	_check(app.sim.move_calls == 0 and app.sim.task_calls == 0, label + " never issues a simulation move or task command")


func _test_real_orders_and_focus() -> void:
	var sim: Variant = _fixture()
	var app: Variant = _app(sim)
	var command: Dictionary = sim.get_unit(int(sim.main_truck_id))
	sim.command_move([int(command.id)], Vector2(17, 15))
	_check(command.order == "move" and bool(command.manual) and not Array(command.path).is_empty(), "ordinary simulation command establishes a real manual route")
	sim.paused = false
	app.speed = 2.0
	app.current_tab = "training"
	_focus_preserves_orders(app, false, "ordinary route focus")
	# Public evacuation admission and its real loader create the outbound cargo.
	_check(sim.evacuate_camp(int(sim.camps[0].id)), "public withdrawal admits a real forward receiver")
	sim._update_evacuations(0.0)
	sim._update_evacuations(6.0)
	_check(command.order == "evacuate_transport" and command.haul_stage == "outbound" and not Dictionary(command.cargo).is_empty() and not Array(command.path).is_empty(), "actual withdrawal has outbound haul stage, loaded cargo and path")
	var before: String = _snapshot(sim)
	_expect(sim, "healthy", true, "actual loaded withdrawal status")
	_check(_snapshot(sim) == before, "status does not redirect the actual receiver or unload cargo")
	sim.paused = true
	app.speed = 3.0
	app.current_tab = "production"
	_focus_preserves_orders(app, true, "loaded withdrawal hotspot focus")
	app.free()


func _test_invalid_action_does_not_jump() -> void:
	for invalid: String in ["missing", "destroyed", "wrong_team", "wrong_kind"]:
		var sim: Variant = _fixture()
		var app: Variant = _app(sim)
		var command: Dictionary = sim.get_unit(int(sim.main_truck_id))
		# The control was available before this live identity/health change.
		_check(bool(Readout.status(sim).get("enabled", false)), invalid + " starts from a previously usable control")
		_prime_pointer_modes(app)
		match invalid:
			"missing": sim.main_truck_id = 999999
			"destroyed": command.hp = 0.0
			"wrong_team": command.team = "enemy"
			"wrong_kind": command.kind = "rifle"
		var selected: Array = app.selected_ids.duplicate()
		var camera_position: Vector2 = app.camera.position
		var before: String = _snapshot(sim)
		app.ui_action("select_command_truck")
		_check(app.selected_ids == selected and app.camera.position == camera_position, invalid + " is revalidated without selecting another truck or jumping to origin")
		_check(_snapshot(sim) == before and sim.move_calls == 0 and sim.task_calls == 0, invalid + " action preserves simulation and issues no orders")
		app.free()


func _test_load_and_new_run() -> void:
	var sim: Variant = _fixture()
	var app: Variant = _app(sim)
	var saved_id: int = int(sim.main_truck_id)
	var saved_position: Vector2 = sim.get_unit(saved_id).pos
	sim.get_unit(saved_id).hp = 200.5
	_check(app.save_campaign(), "real public SaveStore write accepts isolated command fixture")
	var row: Dictionary = Readout.status(sim)
	_check(int(row.get("unit_id", 0)) == saved_id and row.get("code", "") == "damaged", "saved command state has been observed before replacement")
	sim.main_truck_id = int(sim.units[0].id)
	app.ui_action("select_command_truck")
	_check(app.selected_ids == [int(sim.main_truck_id)] and int(sim.main_truck_id) != saved_id, "same-time live ID replacement is revalidated without cached old selection")
	_check(app.load_campaign(), "real public load restores the isolated on-disk campaign")
	row = Readout.status(sim)
	_check(int(row.get("unit_id", 0)) == saved_id and row.get("code", "") == "damaged" and float(row.get("hp", 0.0)) == 200.5, "load immediately observes saved identity and HP rather than stale replacement")
	app.ui_action("select_command_truck")
	_check(app.selected_ids == [saved_id] and app.camera.position == saved_position * 48.0, "post-load action focuses the actually restored command vehicle")
	app.start_campaign("delta")
	row = Readout.status(sim)
	var new_id: int = int(sim.main_truck_id)
	_check(new_id != saved_id and int(row.get("unit_id", 0)) == new_id and row.get("code", "") == "healthy", "ordinary new mission replaces stale loaded identity and damage")
	var before: String = _snapshot(sim)
	app.ui_action("select_command_truck")
	_check(app.selected_ids == [new_id] and app.camera.position == Vector2(sim.get_unit(new_id).pos) * 48.0, "new mission action focuses its actual command vehicle")
	_check(_snapshot(sim) == before, "new mission focus remains read-only")
	app.free()
