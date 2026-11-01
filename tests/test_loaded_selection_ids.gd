extends SceneTree
## Headless regression for loaded numeric IDs at real controller UI entry points.
## No simulation ticks or draw oracle; WorldView's actual has(int(id)) predicate
## is evaluated after wiring the same selected array as Main._process.
const Simulation = preload("res://scripts/campaign_simulation.gd")
const FIXTURE: String = "res://tests/fixtures/native-exit-funded.json"
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
var stages: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolation: String = OS.get_environment("LOADED_SELECTION_ISOLATION")
	if isolation.is_empty(): isolation = ProjectSettings.globalize_path("res://work/loaded-selection-id-data")
	if DisplayServer.get_name() != "headless" or not OS.get_user_data_dir().begins_with(isolation.trim_suffix("/") + "/"):
		printerr("Loaded selection regression requires headless and isolated userdata")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	_check(DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE), ProjectSettings.globalize_path("user://campaign-save.json")) == OK, "copy unmodified tracked legacy native fixture into isolated slot")
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var app: Variant = QuietMain.new()
	viewport.add_child(app)
	app.set_process(false)
	app._setup_inputs()
	app.sim = Simulation.new()
	app.sim.reset(42, "canyon")
	app.world = QuietWorld.new()
	app.world.sim = app.sim
	app.add_child(app.world)
	app.hud = QuietHud.new()
	app.hud.main = app
	app.add_child(app.hud)
	app.camera = Camera2D.new()
	app.add_child(app.camera)
	_check(app.load_campaign(), "real Main load validates and restores the legacy fixture")
	app.sim.paused = true
	var truck: Dictionary = app.sim.get_unit(int(app.sim.main_truck_id))
	var main_id: int = int(truck.id)
	_check(typeof(truck.id) == TYPE_FLOAT, "test exercises actual JSON float unit ID without changing saved Sim schema")
	var point: Vector2 = app.world.render_unit_position(truck) * app.TILE
	var baseline: String = _literal(app.sim)
	var rng: String = str(app.sim._rng.state)
	_selected(app, [6, 7, 8, 9], "existing load converts saved UI selection to int")
	app.drag_start = point
	app._select(point, false, false)
	_selected(app, [main_id], "single click on actual rendered truck point")
	_same(app, baseline, rng, "single selection")
	app._group_key(3, true, false)
	_check(app.group_bindings[3] == [main_id] and _integers(app.group_bindings[3]), "storing real selected legacy unit preserves integer group IDs")
	app.selected_ids.clear()
	app._group_key(3, false, false)
	_selected(app, [main_id], "bound group recall")
	_check(_integers(app.group_bindings[3]), "group recall does not retain mixed numeric group values")
	app.focus_main_truck()
	app.drag_start = point
	app._select(point, true, false)
	_selected(app, [main_id], "Shift append matches existing int ID and adds no numeric-type duplicate")
	app.drag_start = point - Vector2(12, 12)
	app._select(point + Vector2(12, 12), false, false)
	_selected(app, [main_id], "box selects actual truck as integer ID")
	app.drag_start = point
	app._select(point, false, true)
	_selected(app, [main_id], "same-kind selection uses integer IDs")
	app._select(point, true, true)
	_selected(app, [main_id], "same-kind Shift append does not duplicate int/float identity")
	_same(app, baseline, rng, "all selection paths and bound groups")
	# The actual retained fixture has squad1=[6..9] and squad0=[10..13]. Exercise the
	# actual key handler/Tab route, with no call to a new selection helper.
	app.focus_main_truck()
	for expected: Array in [[6, 7, 8, 9], [10, 11, 12, main_id], [6, 7, 8, 9]]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = KEY_TAB
		key.physical_keycode = KEY_TAB
		key.pressed = true
		app._unhandled_input(key)
		_selected(app, expected, "actual Tab cycles existing squad order " + str(expected))
		_same(app, baseline, rng, "Tab selection")
	app.group_bindings.erase(1)
	app._group_key(1, false, false)
	_selected(app, [6, 7, 8, 9], "unbound group fallback uses actual squad data")
	_check(not app.group_bindings.has(1), "fallback preserves existing unbound-group storage semantics")
	app.group_bindings[1] = []
	app._group_key(1, false, false)
	_selected(app, [6, 7, 8, 9], "empty bound group fallback selects actual squad")
	_check(app.group_bindings[1] == [6, 7, 8, 9] and _integers(app.group_bindings[1]), "fallback's existing empty group alias receives integer IDs")
	_same(app, baseline, rng, "group fallbacks")
	var groups: Dictionary = app.group_bindings.duplicate(true)
	var selected: Array = app.selected_ids.duplicate()
	var encoded_before: String = _canonical(app.sim.save_state())
	var view_payload: Dictionary = app._save_payload().ui
	_check(view_payload.groups.has("1") and view_payload.groups.has("3"), "saved group keys retain original string-key JSON contract")
	_check(app.save_campaign() and app.load_campaign(), "existing real SaveStore/Main group and selection roundtrip")
	_selected(app, selected, "load preserves saved selected target IDs")
	_check(app.group_bindings == groups and _all_groups_integer(app.group_bindings), "existing group keys/values/order survive real save/load as integers")
	_check(_canonical(app.sim.save_state()) == encoded_before and str(app.sim._rng.state) == rng, "real save/load preserves complete production-codec Sim and exact RNG")
	# A new game is an explicit existing reset, not a claim that it keeps the
	# previous battle; compare against the original public reset operation.
	app.start_campaign("delta")
	_selected(app, [6, 7, 8, 9], "new-campaign default selection consists of integer IDs")
	_check(app.group_bindings.is_empty(), "new campaign still clears previous groups")
	var expected_reset: RefCounted = Simulation.new()
	expected_reset.reset(42, "delta")
	_check(_canonical(app.sim.save_state()) == _canonical(expected_reset.save_state()) and app.sim._rng.state == expected_reset._rng.state, "selection fix does not alter actual new-campaign Sim reset or RNG")
	viewport.free()
	var output: String = OS.get_environment("LOADED_SELECTION_REPORT")
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"scope":"Headless loaded-ID controller regression, quiet lifecycle/draw only; no pixel/GUI acceptance", "checks":checks,"failures":failures,"stages":stages}, "\t", true, true) + "\n")
			file.close()
	print("Loaded selection IDs checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)

func _integers(values: Array) -> bool:
	for value: Variant in values:
		if typeof(value) != TYPE_INT: return false
	return true

func _all_groups_integer(groups: Dictionary) -> bool:
	for key: Variant in groups:
		if typeof(key) != TYPE_INT or not _integers(groups[key]): return false
	return true

func _selected(app: Variant, expected: Array, label: String) -> void:
	_check(app.selected_ids == expected, label + " exact expected selected identities")
	_check(_integers(app.selected_ids), label + " all controller IDs have integer type")
	app.world.selected_ids = app.selected_ids
	var predicates: bool = true
	for id: int in expected: predicates = predicates and app.world.selected_ids.has(id)
	_check(predicates, label + " WorldView's actual has(int(unit.id)) predicate is true")
	stages.append({"label":label,"selected":app.selected_ids.duplicate(),"all_integer":_integers(app.selected_ids),"actual_world_has_int":predicates})

func _literal(sim: Variant) -> String:
	return JSON.stringify(sim.save_state(), "", false, true)

func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)

func _same(app: Variant, before: String, rng: String, label: String) -> void:
	_check(_literal(app.sim) == before and str(app.sim._rng.state) == rng, label + " preserves literal complete Sim and exact RNG")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
