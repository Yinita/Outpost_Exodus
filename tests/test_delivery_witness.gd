extends SceneTree
## Self-contained source-headless public-order unload regression.
## Not native/GUI/full-route proof; external C4/old-source oracle is separate.
const Simulation = preload("res://scripts/campaign_simulation.gd")
const Runner = preload("res://scripts/diagnostics/campaign_runner.gd")
const MODES: Array[String] = ["none", "normal", "mutating"]

class ObserverApp:
	extends Node2D
	var sim: RefCounted
	var tick_count: int = 0

class WitnessListener:
	extends RefCounted
	var sim: RefCounted
	var mutate: bool = false
	var records: Array[Dictionary] = []
	var errors: Array[String] = []
	func receive(witness: Dictionary) -> void:
		var before: Dictionary = sim.save_state()
		var rng_before: int = sim._rng.state
		var truck: Dictionary = sim.get_unit(int(witness.get("truck_id", 0)))
		var origin: Dictionary = sim.get_camp(int(witness.get("origin_id", 0)))
		var destination: Dictionary = sim.get_camp(int(witness.get("destination_id", 0)))
		var record: Dictionary = witness.duplicate(true)
		record["origin_state_at_unload"] = origin.get("state", "missing")
		record["simulation_time"] = sim.time
		if truck.is_empty() or destination.is_empty() or not Dictionary(truck.get("cargo", {})).is_empty(): errors.append("event is not after actual cargo clear")
		if truck.get("order") != "evacuate_transport" or truck.get("haul_stage") != "outbound": errors.append("event is not before actual transport-stage transition")
		if truck.get("pos") != witness.get("position") or destination.get("pos") != witness.get("destination_position"): errors.append("witness positions do not identify actual units/camps")
		var weight: float = 0.0
		for amount: Variant in Dictionary(witness.get("parcel", {})).values(): weight += float(amount)
		if weight <= 0.0: errors.append("empty parcel was emitted")
		for resource: String in Simulation.RESOURCE_KEYS:
			if absf(float(witness.stock_before[resource]) + float(witness.parcel.get(resource, 0.0)) - float(witness.stock_after[resource])) > 0.000001 or float(witness.stock_after[resource]) != float(destination.get(resource, 0.0)):
				errors.append("parcel/actual stock delta differs: " + resource)
		records.append(record)
		if mutate:
			# Deliberately hostile caller edits ONLY the detached witness.
			witness.parcel["materials"] = 999999.0
			witness.stock_before.clear()
			witness.stock_after["fuel"] = -999.0
			witness["position"] = Vector2(-99, -99)
			witness["origin_id"] = -99
		if sim.save_state() != before or sim._rng.state != rng_before: errors.append("listener mutation changed live encoded state or RNG")

var checks: int = 0
var failures: Array[String] = []
var baseline_script: Script = Simulation
var compared_steps: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_public_withdrawal(false)
	_test_public_withdrawal(true)
	print("DELIVERY_WITNESS_TEST checks=%d failures=%d compared_fixed_steps=%d" % [checks, failures.size(), compared_steps])
	for failure: String in failures: printerr("DELIVERY_WITNESS_FAILURE ", failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)


func _public_fixture() -> Dictionary:
	var sim: RefCounted = baseline_script.new()
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
	var origin: Dictionary = sim._make_camp(Vector2(6, 10), "撤收源营", 240.0, 80.0, 70.0)
	var destination: Dictionary = sim._make_camp(Vector2(22, 10), "真实接收营", 0.0, 0.0, 0.0)
	origin.recipe = "idle"
	destination.recipe = "idle"
	sim._add_building("command", origin.pos, int(origin.id), 1.0)
	sim._add_building("command", destination.pos, int(destination.id), 1.0)
	for x: int in range(5, 25):
		for y: int in range(9, 14): sim.roads[Vector2i(x, y)] = {"progress": 1.0, "camp_id": int(origin.id)}
	var truck: Dictionary = sim._add_unit("truck", "friendly", Vector2(5, 11), int(origin.id), 0)
	sim.main_truck_id = int(truck.id)
	for position: Vector2 in [Vector2(12, 18), Vector2(13, 18), Vector2(14, 18), Vector2(15, 18)]:
		sim._add_unit("rifle", "friendly", position, int(origin.id), 1)
	sim.exit_building_id = 0
	sim.exit_site_id = 0
	sim.pursuit_x = -10000.0
	sim.pursuit_start = 1000000.0
	sim._invalidate_navigation()
	return sim.save_state()


func _comparison(data: Dictionary) -> Dictionary:
	var expected: RefCounted = baseline_script.new()
	_check(expected.load_state(data), "unobserved simulation loads full fixture")
	var result: Dictionary = {"baseline": expected}
	for mode: String in MODES:
		var sim: RefCounted = Simulation.new()
		_check(sim.load_state(data), mode + " current simulation loads identical full fixture")
		result[mode] = sim
		_check(sim.save_state() == expected.save_state() and sim._rng.state == expected._rng.state, mode + " starts encoded/RNG-identical to unobserved simulation")
	var normal: RefCounted = WitnessListener.new()
	normal.sim = result.normal
	result.normal.evacuation_delivery.connect(normal.receive)
	var mutating: RefCounted = WitnessListener.new()
	mutating.sim = result.mutating
	mutating.mutate = true
	result.mutating.evacuation_delivery.connect(mutating.receive)
	result["normal_listener"] = normal
	result["mutating_listener"] = mutating
	var app: Node2D = ObserverApp.new()
	app.sim = result.normal
	var runner: Node = Runner.new()
	runner.app = app
	runner.report = {"events": []}
	runner.output_dir = ""
	runner._observing = true
	runner._attach_delivery_observer(result.normal)
	result["app"] = app
	result["runner"] = runner
	_check(result.none.get_signal_connection_list("evacuation_delivery").is_empty(), "no-listener branch has no unload observation callbacks")
	return result


func _compare_now(comparison: Dictionary, label: String) -> bool:
	var encoded: Dictionary = comparison.baseline.save_state()
	var rng: int = comparison.baseline._rng.state
	for mode: String in MODES:
		if comparison[mode].save_state() != encoded or comparison[mode]._rng.state != rng:
			_check(false, label + " changes full encoded state/RNG versus unobserved simulation in " + mode + " at " + str(comparison.baseline.time))
			return false
	return true


func _tick(comparison: Dictionary, label: String) -> bool:
	comparison.baseline.tick(0.05)
	for mode: String in MODES: comparison[mode].tick(0.05)
	# Match Main: tick_count increments only after Sim.tick and its callback return.
	comparison.app.tick_count += 1
	compared_steps += 1
	return _compare_now(comparison, label)


func _drive_to_last_unload(comparison: Dictionary, origin_id: int, label: String, emergency: bool = false) -> void:
	var completed: bool = false
	var abandoned: bool = false
	for tick: int in range(7200):
		if not _tick(comparison, label): break
		var truck: Dictionary = comparison.normal.get_unit(int(comparison.normal.main_truck_id))
		if emergency and not abandoned and truck.get("haul_stage") == "outbound" and not Dictionary(truck.get("cargo", {})).is_empty():
			for mode: String in ["baseline", "none", "normal", "mutating"]:
				_check(comparison[mode].evacuate_camp(origin_id), label + " public second request performs emergency abandonment in " + mode)
			abandoned = true
			if not _compare_now(comparison, label + " public abandonment"): break
		if comparison.normal.get_camp(origin_id).get("state") == "abandoned" and truck.get("order") == "idle" and Dictionary(truck.get("cargo", {})).is_empty():
			completed = true
			break
	_check(completed, label + " actually finishes its final delivery within360 simulated seconds")
	var normal: RefCounted = comparison.normal_listener
	var mutating: RefCounted = comparison.mutating_listener
	_check(normal.errors.is_empty() and mutating.errors.is_empty(), label + " all real signals occur after stock credit/clear and are deep detached")
	_check(not normal.records.is_empty() and normal.records == mutating.records, label + " normal and mutating listeners see the same physical deliveries")
	_check(comparison.runner.failures.is_empty() and comparison.runner.deliveries_from(origin_id) == normal.records.size(), label + " runner synchronously records every actual main-truck unload")
	var packing: int = 0
	var last: int = 0
	for record: Dictionary in normal.records:
		if record.origin_state_at_unload == "packing": packing += 1
		if record.origin_state_at_unload == "abandoned": last += 1
	_check(last == 1, label + " abandoned-origin last parcel is witnessed exactly once")
	if not emergency: _check(packing > 0, label + " packing-origin ordinary parcels are witnessed too")
	var count: int = normal.records.size()
	for repeat: int in range(20):
		if not _tick(comparison, label + " completed idle continuation"): break
	_check(normal.records.size() == count and mutating.records.size() == count and comparison.runner.deliveries_from(origin_id) == count, label + " empty/idle updates cannot emit or duplicate an unload")
	var stock: Dictionary = comparison.normal.get_camp(int(comparison.normal.get_unit(int(comparison.normal.main_truck_id)).camp_id)).duplicate(true)
	var before: Dictionary = comparison.normal.save_state()
	var truck: Dictionary = comparison.normal.get_unit(int(comparison.normal.main_truck_id))
	comparison.normal._unload_evacuation_cargo(comparison.normal.get_camp(origin_id), comparison.normal.get_camp(int(truck.camp_id)), truck)
	_check(comparison.normal.save_state() == before and normal.records.size() == count and comparison.runner.deliveries_from(origin_id) == count, label + " direct empty helper is a no-op without a false signal")
	_check(comparison.normal.get_camp(int(truck.camp_id)) == stock, label + " empty helper never changes receiver stock")
	print("DELIVERY_WITNESS_CASE ", label, " actual_unloads=", count, " packing=", packing, " last=", last)


func _test_public_withdrawal(emergency: bool) -> void:
	var comparison: Dictionary = _comparison(_public_fixture())
	var origin: int = int(comparison.normal.camps[0].id)
	for mode: String in ["baseline", "none", "normal", "mutating"]:
		_check(comparison[mode].evacuate_camp(origin), "actual public evacuation admission succeeds in " + mode)
	_check(_compare_now(comparison, "public evacuation admission"), "public admission is byte-state/RNG-identical in all observation modes")
	_drive_to_last_unload(comparison, origin, "public emergency" if emergency else "public packing", emergency)
	_cleanup(comparison)


func _cleanup(comparison: Dictionary) -> void:
	comparison.runner._reset_cycle_observer()
	comparison.runner.free()
	comparison.app.free()
	comparison.normal.evacuation_delivery.disconnect(comparison.normal_listener.receive)
	comparison.mutating.evacuation_delivery.disconnect(comparison.mutating_listener.receive)
	comparison.normal_listener.sim = null
	comparison.mutating_listener.sim = null
