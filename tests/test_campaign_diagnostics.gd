extends SceneTree
## Headless static preflight only; never creates Main or advances a campaign.
const Runner = preload("res://scripts/diagnostics/campaign_runner.gd")

class ObserverSimulation:
	extends RefCounted
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
	for arguments: PackedStringArray in [
		PackedStringArray([]),
		PackedStringArray(["--mission=canyon"]),
		PackedStringArray(["--campaign-validation", "--campaign-validation"]),
		PackedStringArray(["--campaign-validation", "--prepare-only", "--prepare-only"]),
		PackedStringArray(["--campaign-validation", "--mission=canyon", "--mission=canyon"]),
		PackedStringArray(["--campaign-validation", "--max-seconds=60", "--max-seconds=900"]),
		PackedStringArray(["--campaign-validation", "--mission=delta"]),
		PackedStringArray(["--campaign-validation", "--mission=ridge"]),
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
	# Facade-only regression for the read-only parcel counter. These transitions
	# are controlled fixtures, not actual simulated deliveries or native play.
	var fixture: Dictionary = _delivery_fixture("evacuate_transport", 180.0)
	var observer: Node = fixture.observer
	var simulation: RefCounted = fixture.simulation
	var before: String = _facade_state(simulation)
	observer._observe_deliveries()
	_check(observer.deliveries_from(11) == 0, "loaded outbound parcel is not counted before arrival")
	_check(_facade_state(simulation) == before, "outbound observation leaves every facade field unchanged")
	simulation.truck.haul_stage = "returning"
	simulation.truck.cargo = {}
	simulation.truck.pos = Vector2(25, 14)
	# A partial delivery still belongs to its ORIGIN camp, not its receiver.
	_check(int(simulation.truck.camp_id) == 11, "fixture retains original camp ownership at actual receiver")
	before = _facade_state(simulation)
	observer._observe_deliveries()
	_check(observer.deliveries_from(11) == 1 and observer.deliveries_from(22) == 0, "loaded parcel arriving at prior destination counts exactly once for origin")
	_check(observer.report.events.size() == 1 and int(observer.report.events[0].destination) == 22, "recorded arrival identifies receiver rather than truck camp ownership")
	_check(_facade_state(simulation) == before, "arrival observation does not change cargo, position, camps or clock")
	for frame: int in range(4): observer._observe_deliveries()
	_check(observer.deliveries_from(11) == 1 and observer.report.events.size() == 1, "repeated empty returning frames cannot duplicate a delivery")
	_free_delivery_fixture(fixture)
	for variant: String in ["empty_outbound", "away_from_destination", "ordinary_haul"]:
		fixture = _delivery_fixture("haul" if variant == "ordinary_haul" else "evacuate_transport", 0.0 if variant == "empty_outbound" else 180.0)
		observer = fixture.observer
		simulation = fixture.simulation
		observer._observe_deliveries()
		simulation.truck.haul_stage = "returning"
		simulation.truck.cargo = {}
		simulation.truck.pos = Vector2(4, 4) if variant == "away_from_destination" else Vector2(25, 14)
		before = _facade_state(simulation)
		observer._observe_deliveries()
		_check(observer.deliveries_from(11) == 0 and observer.report.events.is_empty(), "no false parcel arrival for%s" % variant)
		_check(_facade_state(simulation) == before, "negative%s observation remains read-only" % variant)
		_free_delivery_fixture(fixture)


func _delivery_fixture(order: String, quantity: float) -> Dictionary:
	var simulation: RefCounted = ObserverSimulation.new()
	simulation.camps = {11: {"id": 11, "pos": Vector2(4, 4)}, 22: {"id": 22, "pos": Vector2(25, 14)}}
	simulation.truck = {"id": 7, "camp_id": 11, "evac_origin_id": 11, "evac_destination_id": 22,
		"order": order, "haul_stage": "outbound", "pos": Vector2(10, 8), "cargo": {"materials": quantity}}
	var app: Node2D = ObserverApp.new()
	app.sim = simulation
	var observer: Node = Runner.new()
	observer.app = app
	observer.report = {"events": []}
	observer.output_dir = ""
	return {"observer": observer, "app": app, "simulation": simulation}


func _facade_state(simulation: RefCounted) -> String:
	return JSON.stringify({"truck": simulation.truck, "camps": simulation.camps, "time": simulation.time, "main_truck_id": simulation.main_truck_id})


func _free_delivery_fixture(fixture: Dictionary) -> void:
	fixture.observer.free()
	fixture.app.free()


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description)
