extends SceneTree
## Headless static preflight only; never creates Main or advances a campaign.
const Runner = preload("res://scripts/diagnostics/campaign_runner.gd")

class ObserverSimulation:
	extends RefCounted
	signal evacuation_delivery(witness: Dictionary)
	var time: float = 120.0
	var main_truck_id: int = 7
	var truck: Dictionary = {}
	var camps: Dictionary = {}
	func get_unit(id: int) -> Dictionary:
		return truck if id == main_truck_id else {}
	func get_camp(id: int) -> Dictionary:
		return camps.get(id, {})

class ObserverApp:
	extends Node2D
	var sim: RefCounted
	var tick_count: int = 2400

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var initial: Array[String] = Runner.validate_environment()
	if not initial.is_empty():
		for error: String in initial: printerr("CAMPAIGN_PREFLIGHT_REQUIRES_FRESH_ISOLATION ", error)
		quit(2)
		return
	_test_arguments()
	_test_environment()
	_test_symlink_boundary()
	_test_delivery_observer()
	print("CAMPAIGN_DIAGNOSTICS_TEST checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: printerr("CAMPAIGN_DIAGNOSTICS_TEST_FAILURE ", failure)
	quit(0 if failures.is_empty() else 1)


func _test_arguments() -> void:
	var valid: Dictionary = Runner.parse_arguments(PackedStringArray(["--campaign-validation"]))
	_check(valid.errors.is_empty(), "required validation flag is accepted")
	_check(valid.mission == "canyon" and int(valid.max_seconds) == 900 and not valid.prepare_only, "defaults select original campaign with full900second scope")
	_check(valid.output_dir == OS.get_environment("CAMPAIGN_VALIDATION_ROOT").path_join("output"), "output belongs to dedicated validation root")
	for limit: int in [60, 900, 1800]:
		var bounded: Dictionary = Runner.parse_arguments(PackedStringArray(["--campaign-validation", "--mission=canyon", "--max-seconds=%d" % limit]))
		_check(bounded.errors.is_empty() and int(bounded.max_seconds) == limit, "inclusive supported wall-time bound%d" % limit)
	var prepared: Dictionary = Runner.parse_arguments(PackedStringArray(["--campaign-validation", "--prepare-only"]))
	_check(prepared.errors.is_empty() and prepared.prepare_only, "explicit prepare-only mode is separate")
	for mission: String in ["canyon", "delta", "ridge"]:
		var full: Dictionary = Runner.parse_arguments(PackedStringArray(["--campaign-validation", "--mission=" + mission]))
		_check(full.errors.is_empty() and full.mission == mission and not full.prepare_only, "full route accepts explicit supported mission:" + mission)
		var prepare: Dictionary = Runner.parse_arguments(PackedStringArray(["--campaign-validation", "--mission=" + mission, "--prepare-only"]))
		_check(prepare.errors.is_empty() and prepare.mission == mission and prepare.prepare_only, "prepare-only retains explicit supported mission:" + mission)
	for arguments: PackedStringArray in [
		PackedStringArray([]),
		PackedStringArray(["--mission=canyon"]),
		PackedStringArray(["--campaign-validation", "--campaign-validation"]),
		PackedStringArray(["--campaign-validation", "--prepare-only", "--prepare-only"]),
		PackedStringArray(["--campaign-validation", "--mission=canyon", "--mission=canyon"]),
		PackedStringArray(["--campaign-validation", "--max-seconds=60", "--max-seconds=900"]),
		PackedStringArray(["--campaign-validation", "--mission=delta", "--mission=ridge"]),
		PackedStringArray(["--campaign-validation", "--mission="]),
		PackedStringArray(["--campaign-validation", "--mission=unknown"]),
		PackedStringArray(["--campaign-validation", "--max-seconds=59"]),
		PackedStringArray(["--campaign-validation", "--max-seconds=1801"]),
		PackedStringArray(["--campaign-validation", "--max-seconds=bad"]),
		PackedStringArray(["--campaign-validation", "--max-seconds=60=garbage"]),
		PackedStringArray(["--campaign-validation", "--max-seconds="]),
		PackedStringArray(["--campaign-validation", "--render-diagnostics"]),
		PackedStringArray(["--campaign-validation", "--capture=/tmp/unwanted.png"]),
		PackedStringArray(["--campaign-validation", "--smoke"]),
		PackedStringArray(["--campaign-validation", "--fixed-fps=60"]),
		PackedStringArray(["--campaign-validation", "--time-scale=3"]),
		PackedStringArray(["--campaign-validation", "--unknown"]),
	]:
		_check(not Runner.parse_arguments(arguments).errors.is_empty(), "reject duplicate, unsupported or mixed flags:%s" % str(arguments))


func _test_environment() -> void:
	var isolation: String = OS.get_environment("CAMPAIGN_VALIDATION_ROOT")
	_check(not isolation.is_empty(), "preflight starts with explicit isolation")
	OS.unset_environment("CAMPAIGN_VALIDATION_ROOT")
	_check(not Runner.validate_environment().is_empty(), "missing isolation is rejected before loading player state")
	OS.set_environment("CAMPAIGN_VALIDATION_ROOT", isolation)
	for bad_root: String in ["", "/", OS.get_environment("HOME"), "relative-validation-root"]:
		OS.set_environment("CAMPAIGN_VALIDATION_ROOT", bad_root)
		_check(not Runner.validate_environment().is_empty(), "non-dedicated root is rejected:%s" % bad_root)
	OS.set_environment("CAMPAIGN_VALIDATION_ROOT", isolation)
	for key: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var original: String = OS.get_environment(key)
		OS.set_environment(key, OS.get_environment("HOME").path_join(".local/share"))
		_check(not Runner.validate_environment().is_empty(), "outside%s is rejected" % key)
		OS.set_environment(key, original)
	var user_dir: String = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(user_dir)
	for name: String in ["settings.cfg", "campaign-save.json", "campaign-save.json.bak", "campaign-autosave.json", "campaign-autosave.json.bak"]:
		var path: String = user_dir.path_join(name)
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		_check(file != null, "isolated%s sentinel can be written" % name)
		if file != null:
			file.store_string("fresh-validation-sentinel")
			file.close()
			_check(not Runner.validate_environment().is_empty(), "existing%s is rejected" % name)
			DirAccess.remove_absolute(path)
			_check(Runner.validate_environment().is_empty(), "fresh guard recovers after%s sentinel removal" % name)
	var directory_path: String = user_dir.path_join("campaign-autosave.json")
	_check(DirAccess.make_dir_recursive_absolute(directory_path) == OK, "isolated save-shaped directory can be created")
	_check(not Runner.validate_environment().is_empty(), "save-shaped directory cannot bypass freshness guard")
	DirAccess.remove_absolute(directory_path)
	_check(Runner.validate_environment().is_empty(), "fresh environment remains valid after sentinel cleanup")


func _test_symlink_boundary() -> void:
	var isolation: String = OS.get_environment("CAMPAIGN_VALIDATION_ROOT")
	var directory: DirAccess = DirAccess.open(isolation)
	var link: String = isolation.path_join("outside-link")
	var target: String = isolation.get_base_dir().path_join("uncreated-outside-campaign-target")
	var status: Error = directory.create_link(target, link)
	_check(status == OK, "can create dedicated dangling test symlink without writing outside root")
	if status != OK: return
	for key: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var original: String = OS.get_environment(key)
		OS.set_environment(key, link.path_join("nested-data"))
		_check(not Runner.validate_environment().is_empty(), "symlink escape below%s is rejected" % key)
		OS.set_environment(key, original)
	OS.set_environment("CAMPAIGN_VALIDATION_ROOT", link)
	_check(not Runner.validate_environment().is_empty(), "symlink root is rejected")
	OS.set_environment("CAMPAIGN_VALIDATION_ROOT", isolation)
	DirAccess.remove_absolute(link)
	_check(Runner.validate_environment().is_empty(), "symlink checks leave isolated environment fresh")


func _test_delivery_observer() -> void:
	# Interface-only facade: real admitted unloads are tested separately.
	var fixture: Dictionary = _delivery_fixture()
	var observer: Node = fixture.observer
	var simulation: RefCounted = fixture.simulation
	var before: String = _facade_state(simulation)
	observer._attach_delivery_observer(simulation)
	_check(simulation.get_signal_connection_list("evacuation_delivery").size() == 1, "repeated attachment is idempotent")
	simulation.evacuation_delivery.emit(fixture.witness)
	_check(int(simulation.truck.camp_id) == 11, "fixture retains original camp ownership at actual receiver")
	_check(observer.deliveries_from(11) == 1 and observer.deliveries_from(22) == 0, "one committed unload signal counts once for its actual origin")
	_check(observer.report.events.size() == 1 and int(observer.report.events[0].destination) == 22, "recorded arrival identifies receiver rather than truck camp ownership")
	_check(_facade_state(simulation) == before and observer.failures.is_empty(), "valid event leaves every facade field unchanged")
	_free_delivery_fixture(fixture)
	for variant: String in ["empty_parcel", "zero_parcel", "negative_parcel", "canceled", "ordinary_haul", "not_main", "wrong_team", "wrong_kind", "wrong_origin", "wrong_destination", "away_from_destination", "stale_position", "cargo_not_cleared", "bad_conservation", "stale_live_stock"]:
		fixture = _delivery_fixture()
		observer = fixture.observer
		simulation = fixture.simulation
		var witness: Dictionary = fixture.witness
		match variant:
			"empty_parcel": witness.parcel = {}
			"zero_parcel": witness.parcel = {"materials": 0.0}
			"negative_parcel": witness.parcel = {"materials": -1.0}
			"canceled": simulation.truck.order = "idle"
			"ordinary_haul": simulation.truck.order = "haul"
			"not_main": witness.truck_id = 8
			"wrong_team": simulation.truck.team = "enemy"
			"wrong_kind": simulation.truck.kind = "worker"
			"wrong_origin": witness.origin_id = 33
			"wrong_destination": witness.destination_id = 33
			"away_from_destination":
				simulation.truck.pos = Vector2(4, 4)
				witness.position = simulation.truck.pos
			"stale_position": witness.position = Vector2(24, 14)
			"cargo_not_cleared": simulation.truck.cargo = {"materials": 180.0}
			"bad_conservation": witness.stock_after.materials = 201.0
			"stale_live_stock": simulation.camps[22].materials = 201.0
		before = _facade_state(simulation)
		simulation.evacuation_delivery.emit(witness)
		_check(observer.deliveries_from(11) == 0 and observer.report.events.is_empty(), "no false delivery for " + variant)
		_check(observer.failures.is_empty() if variant == "not_main" else not observer.failures.is_empty(), "invalid witness is explicitly rejected; non-main truck is ignored: " + variant)
		_check(_facade_state(simulation) == before, "negative " + variant + " event remains read-only")
		observer.failures.clear()  # These are expected rejection checks, not real route failures.
		_free_delivery_fixture(fixture)
	_test_delivery_connection_lifecycle()


func _delivery_fixture() -> Dictionary:
	var simulation: RefCounted = ObserverSimulation.new()
	simulation.camps = {11: {"id": 11, "pos": Vector2(4, 4), "materials": 0.0, "supplies": 0.0, "fuel": 0.0, "salvage": 0.0, "crude": 0.0},
		22: {"id": 22, "pos": Vector2(25, 14), "materials": 200.0, "supplies": 30.0, "fuel": 40.0, "salvage": 0.0, "crude": 0.0}}
	simulation.truck = {"id": 7, "camp_id": 11, "evac_origin_id": 11, "evac_destination_id": 22,
		"kind": "truck", "team": "friendly", "hp": 380.0,
		"order": "evacuate_transport", "haul_stage": "outbound", "pos": Vector2(25, 14), "cargo": {}}
	var app: Node2D = ObserverApp.new()
	app.sim = simulation
	var observer: Node = Runner.new()
	observer.app = app
	observer.report = {"events": []}
	observer.output_dir = ""
	observer._observing = true
	observer._attach_delivery_observer(simulation)
	var witness: Dictionary = {"truck_id": 7, "origin_id": 11, "destination_id": 22,
		"position": Vector2(25, 14), "destination_position": Vector2(25, 14), "parcel": {"materials": 180.0},
		"stock_before": {"materials": 20.0, "supplies": 30.0, "fuel": 40.0, "salvage": 0.0, "crude": 0.0},
		"stock_after": {"materials": 200.0, "supplies": 30.0, "fuel": 40.0, "salvage": 0.0, "crude": 0.0}}
	return {"observer": observer, "app": app, "simulation": simulation, "witness": witness}


func _test_delivery_connection_lifecycle() -> void:
	var first: Dictionary = _delivery_fixture()
	var second: Dictionary = _delivery_fixture()
	var observer: Node = first.observer
	second.observer._reset_cycle_observer()
	second.observer.free()
	first.app.sim = second.simulation
	observer._attach_delivery_observer(second.simulation)
	_check(first.simulation.get_signal_connection_list("evacuation_delivery").is_empty() and second.simulation.get_signal_connection_list("evacuation_delivery").size() == 1, "switching simulation disconnects old and connects new exactly once")
	first.simulation.evacuation_delivery.emit(first.witness)
	_check(observer.deliveries_from(11) == 0, "old simulation cannot contaminate current cycle")
	second.simulation.evacuation_delivery.emit(second.witness)
	_check(observer.deliveries_from(11) == 1, "new exact simulation event is observed")
	observer._reset_cycle_observer()
	_check(observer.deliveries_from(11) == 0 and second.simulation.get_signal_connection_list("evacuation_delivery").is_empty(), "reset clears counts and disconnects old simulation")
	second.simulation.evacuation_delivery.emit(second.witness)
	_check(observer.deliveries_from(11) == 0, "disconnected events cannot repopulate cleared counts")
	observer.report = {"events": []}
	observer._observing = true
	observer._attach_delivery_observer(second.simulation)
	second.simulation.evacuation_delivery.emit(second.witness)
	_check(observer.deliveries_from(11) == 1 and observer.failures.is_empty(), "fresh attachment after reset records one valid event")
	observer._reset_cycle_observer()
	observer.free()
	first.app.free()
	second.app.free()


func _facade_state(simulation: RefCounted) -> String:
	return JSON.stringify({"truck": simulation.truck, "camps": simulation.camps, "time": simulation.time, "main_truck_id": simulation.main_truck_id})


func _free_delivery_fixture(fixture: Dictionary) -> void:
	fixture.observer._reset_cycle_observer()
	fixture.observer.free()
	fixture.app.free()


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description)
