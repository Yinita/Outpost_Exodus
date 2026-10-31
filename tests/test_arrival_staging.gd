extends SceneTree
## A retained actual Delta failure plus public-tick continuation. Arrival helpers
## are never invoked to establish delivery or construction outcomes.
const Simulation = preload("res://scripts/campaign_simulation.gd")
const Route = preload("res://scripts/diagnostics/campaign_route.gd")
const FIXTURE: String = "res://tests/fixtures/delta-arrival-blocked.json"
const FIXTURE_SHA256: String = "06846340fad76c74e3c0684d0255b893bcd6751471f5d2287c9a31f7ab0a1f6c"
const STEP: float = 0.05
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(FileAccess.get_sha256(FIXTURE) == FIXTURE_SHA256, "retained real failed state is byte-identical")
	_test_paid_road_recovery_and_disk_continuation()
	_test_active_orders_and_manual_positions()
	_check(FileAccess.get_sha256(FIXTURE) == FIXTURE_SHA256, "regression leaves captured state unchanged")
	print("ARRIVAL_STAGING_TEST checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: printerr("ARRIVAL_STAGING_FAILURE ", failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok and not failures.has(label): failures.append(label)
	return ok

func _fixture() -> RefCounted:
	var simulation: RefCounted = Simulation.new()
	_check(simulation.load_state(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))), "captured failure loads through public save validation")
	return simulation

func _job(simulation: RefCounted) -> Dictionary:
	for encoded: Variant in Route.serialized_dictionary(simulation.save_state().payload).jobs:
		var decoded: Dictionary = Route.serialized_dictionary(encoded)
		if int(decoded.id) == 276: return decoded
	return {}

func _normalized(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value,"",true,true)),"",true,true)

func _same_continuation(first: Variant, second: Variant) -> bool:
	# Godot's JSON numeric parser can move an unrelated double timer by 1–2ULP.
	# Keep full structure/entry order, strings, IDs, RNG and float32 coordinates;
	# allow only this much smaller-than-game-epsilon numeric round-trip error.
	if (first is int or first is float) and (second is int or second is float):
		return first == second or absf(float(first) - float(second)) <= maxf(1e-12,2e-15 * maxf(absf(float(first)),absf(float(second))))
	if typeof(first) != typeof(second): return false
	if first is Dictionary:
		if first.keys() != second.keys(): return false
		for key: Variant in first:
			if not _same_continuation(first[key],second[key]): return false
		return true
	if first is Array:
		if first.size() != second.size(): return false
		for index: int in range(first.size()):
			if not _same_continuation(first[index],second[index]): return false
		return true
	return first == second

func _check_physical_step(simulation: RefCounted, previous: Dictionary) -> void:
	for unit: Dictionary in simulation.units:
		if unit.team != "friendly" or float(unit.hp) <= 0.0: continue
		# These are read-only geometry checks after normal ticks, never movement.
		_check(simulation._body_position_valid(unit.pos, simulation.UNIT_RADII[unit.kind], "friendly"), "friendly bodies remain valid against terrain and completed footprints")
		if previous.has(int(unit.id)):
			_check(Vector2(unit.pos).distance_to(previous[int(unit.id)]) < 0.25, "arrival staging uses physical movement without jumps")
		previous[int(unit.id)] = unit.pos

func _test_paid_road_recovery_and_disk_continuation() -> void:
	var simulation: RefCounted = _fixture()
	var initial: Dictionary = _job(simulation)
	_check(simulation.mission_id == "delta" and initial.assigned == 9 and initial.picked_up and not initial.delivered and not initial.done, "actual fixture is the blocked picked-up road parcel")
	_check(float(simulation.get_unit(9).cargo.get("materials",0.0)) == 8.0 and float(initial.progress) == 0.0, "crew already carries eight paid materials before recovery")
	var materials_before: float = float(simulation.get_camp(173).materials)
	var previous: Dictionary = {}
	for unit: Dictionary in simulation.units:
		if unit.team == "friendly": previous[int(unit.id)] = unit.pos
	for tick: int in range(20):
		simulation.tick(STEP)
		_check_physical_step(simulation, previous)
	var staged: Dictionary = {}
	for id: int in [10,11,12,13]:
		var arrival: Dictionary = simulation.get_unit(id)
		staged[id] = {"target":arrival.target,"path":Array(arrival.path).duplicate(),"path_index":arrival.path_index}
		_check(Vector2(arrival.target).distance_to(Vector2(54,27)) > 2.0 and arrival.order == "move" and not arrival.manual, "idle arrival receives an automatic waiting path outside the depot approach")
		_check(not Array(arrival.path).is_empty(), "automatic waiting target has a normal legal path")
	var checkpoint: Dictionary = simulation.save_state()
	var path: String = "user://arrival-staging-test-%d.json" % OS.get_process_id()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null,"staged checkpoint opens a dedicated real disk file"): return
	file.store_string(JSON.stringify(checkpoint,"",true,true))
	file.close()
	var continued: RefCounted = Simulation.new()
	_check(continued.load_state(JSON.parse_string(FileAccess.get_file_as_string(path))), "staging paths load through real disk JSON and public validation")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(_normalized(checkpoint) == _normalized(continued.save_state()), "disk continuation retains full simulation, RNG, assigned waiting targets and paths")
	for id: int in staged:
		_check(continued.get_unit(id).target == staged[id].target and continued.get_unit(id).path == staged[id].path and continued.get_unit(id).path_index == staged[id].path_index, "loading does not choose a new waiting route")
	var saw_delivery: bool = false
	var saw_progress: bool = false
	var completed: bool = false
	for tick: int in range(400):
		simulation.tick(STEP)
		continued.tick(STEP)
		_check_physical_step(simulation, previous)
		_check(_same_continuation(simulation.save_state(),continued.save_state()), "loaded and uninterrupted ticks preserve full state and entry ordering within JSON double precision")
		var job: Dictionary = _job(simulation)
		saw_delivery = saw_delivery or bool(job.delivered)
		saw_progress = saw_progress or float(job.progress) > 0.0 or int(job.road_cursor) > 1
		if bool(job.done):
			completed = true
			break
	_check(saw_delivery and saw_progress and completed, "actual paid cargo reaches the road and remaining segment completes through public ticks")
	_check(bool(_job(continued).done), "actual disk continuation also completes the physically supplied road")
	_check(simulation.get_unit(9).cargo.is_empty(), "all eight carried materials are consumed by the four remaining road tiles")
	_check(is_equal_approx(float(simulation.get_camp(173).materials),materials_before), "recovery neither grants nor charges camp materials again")
	for tile: Vector2i in [Vector2i(54,27),Vector2i(55,27),Vector2i(56,27),Vector2i(57,27),Vector2i(57,28)]:
		_check(simulation.roads.has(tile) and float(simulation.roads[tile].progress) == 1.0, "physically supplied road tile finishes")
	_check(simulation.outcome == "playing" and simulation.mission_id == "delta", "recovery preserves the actual campaign and live rules")

func _test_active_orders_and_manual_positions() -> void:
	var simulation: RefCounted = _fixture()
	simulation.command_task([10],"guard",Vector2(54,27))
	simulation.command_move([11],Vector2(53,26))
	var guard_target: Vector2 = simulation.get_unit(10).target
	var manual_target: Vector2 = simulation.get_unit(11).target
	# The captured save supplies controlled valid states for distinct exclusions.
	var manual_idle: Dictionary = simulation.get_unit(12)
	manual_idle.manual = true
	var idle_target: Vector2 = manual_idle.target
	var truck: Dictionary = simulation.get_unit(13)
	truck.order = "evacuate_transport"
	truck.state = "evacuating"
	truck.haul_stage = "outbound"
	truck.pos = Vector2(50,26)
	truck.target = Vector2(54,27)
	truck.path = [Vector2(51,26),Vector2(52,26),Vector2(53,26),Vector2(54,26),Vector2(54,27)]
	truck.path_index = 0
	_check(simulation.load_state(simulation.save_state()), "protected guard/manual/transport layout remains a semantically valid public save")
	for tick: int in range(20): simulation.tick(STEP)
	_check(simulation.get_unit(10).order == "guard" and simulation.get_unit(10).target == guard_target, "guarded positions retain their public order and target")
	_check(simulation.get_unit(11).target == manual_target and simulation.get_unit(11).formation_anchor == Vector2(53,26), "manual movement keeps its intended position")
	_check(simulation.get_unit(12).manual and simulation.get_unit(12).target == idle_target, "explicitly manual idle units are not automatically retargeted")
	_check(simulation.get_unit(9).order == "construct" and int(simulation.get_unit(9).job_id) == 276, "assigned construction crew keeps its real paid job")
	_check(simulation.get_unit(13).order == "evacuate_transport" and simulation.get_unit(13).target == Vector2(54,27), "moving evacuation transport retains its delivery route")
