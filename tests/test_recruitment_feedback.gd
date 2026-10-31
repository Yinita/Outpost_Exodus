extends SceneTree
## Recruitment plans, atomic admission and real queued training continuation.

const Simulation = preload("res://scripts/campaign_simulation.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_test_read_only_and_stale_plans, _test_admission_order_and_caps, _test_local_inventory, _test_power_and_facilities, _test_worker_fallback_and_snapshot, _test_training_status_and_completion, _test_existing_evacuation_policy, _test_save_continuation_and_legacy_pair]:
		var previous: int = failures.size()
		test.call()
		print("%s %s" % ["PASS" if previous == failures.size() else "FAIL", test.get_method()])
	print("Recruitment feedback checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures:
		printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _fixture() -> Variant:
	var sim: Variant = Simulation.new()
	sim.reset(42)
	var rows: Array = []
	for y: int in range(sim.map_size.y):
		var row: Array = []
		row.resize(sim.map_size.x)
		row.fill(0)
		rows.append(row)
	sim.terrain = rows
	sim.ramps = {}
	sim.camps = []
	sim.buildings = []
	sim.units = []
	sim.sites = []
	sim.effects = []
	sim.messages = []
	sim.chokes = []
	sim._jobs = []
	sim._next_id = 10000
	var camp: Dictionary = sim._make_camp(Vector2(6, 10), "西营", 1000.0, 500.0, 100.0)
	camp["recipe"] = "idle"
	sim.roads = {}
	for x: int in range(6, 10):
		for y: int in range(10, 14):
			sim.roads[Vector2i(x, y)] = {"progress": 1.0, "camp_id": int(camp["id"])}
	sim._add_building("command", Vector2(6, 10), int(camp["id"]), 1.0)
	sim._add_building("generator", Vector2(6, 12), int(camp["id"]), 1.0)
	sim._add_building("barracks", Vector2(9, 10), int(camp["id"]), 1.0)
	sim._add_building("workshop", Vector2(9, 13), int(camp["id"]), 1.0)
	var truck: Dictionary = sim._add_unit("truck", "friendly", Vector2(5, 11), int(camp["id"]), 0)
	sim.main_truck_id = int(truck["id"])
	for position: Vector2 in [Vector2(12, 18), Vector2(13, 18), Vector2(14, 18), Vector2(15, 18)]:
		sim._add_unit("rifle", "friendly", position, int(camp["id"]), 1)
	sim.exit_site_id = 0
	sim.exit_building_id = 0
	sim.exit_progress = 0.0
	sim.pursuit_x = -10000.0
	sim.pursuit_start = 1000000.0
	sim._invalidate_navigation()
	sim._update_power(0.0)
	return sim


func _snapshot(sim: Variant, ignore_messages: bool = false) -> String:
	var state: Dictionary = sim.save_state()
	if ignore_messages:
		for entry in state["payload"]["entries"]:
			if entry[0] == "messages":
				entry[1] = []
	return JSON.stringify(state)


func _building(sim: Variant, kind: String) -> Dictionary:
	for building: Dictionary in sim.buildings:
		if building["kind"] == kind:
			return building
	return {}


func _expect_rejection(sim: Variant, kind: String, code: String, camp_id: int = -1) -> void:
	if camp_id < 0:
		camp_id = int(sim.camps[0]["id"])
	var before: String = _snapshot(sim)
	var query: Dictionary = sim.query_recruit(camp_id, kind)
	_check(not bool(query["ok"]) and query["code"] == code, code + " is the authoritative query reason")
	_check(not str(query["message"]).is_empty(), code + " explains the failed condition")
	_check(_snapshot(sim) == before, code + " query preserves encoded state, including IDs and RNG")
	var authoritative_before: String = _snapshot(sim, true)
	var commit: Dictionary = sim.try_recruit(camp_id, kind)
	_check(not bool(commit["ok"]) and commit["message"] == query["message"], code + " commit reports the fresh query reason")
	_check(_snapshot(sim, true) == authoritative_before, code + " rejection leaves payment and all queues atomic")


func _test_read_only_and_stale_plans() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	var id: int = int(camp["id"])
	var before: String = _snapshot(sim)
	for index: int in range(4):
		for kind: String in ["rifle", "engineer", "worker", "truck"]:
			var query: Dictionary = sim.query_recruit(id, kind)
			_check(bool(query["ok"]) and query["code"] == "ready", kind + " query accepts a funded powered facility")
			_check(query["cap"] == 32 and query["queue_cap"] == 4 and float(query["duration"]) > 0.0, kind + " plan exposes actual limits and duration")
			query["costs"]["materials"] = -100.0
			sim.get_training_status(id)
	_check(_snapshot(sim) == before, "repeated successful plans and statuses preserve complete encoded authoritative state")
	_check(float(sim.query_recruit(id, "rifle")["costs"]["materials"]) == 20.0, "caller mutation cannot change a future price or simulation constants")
	var preview: Dictionary = sim.query_recruit(id, "rifle")
	camp["materials"] = 0.0
	_expect_rejection(sim, "rifle", "resources")
	_check(bool(preview["ok"]) and Array(camp["recruit_queue"]).is_empty(), "an earlier successful plan reserves no resources and cannot force stale admission")
	camp["materials"] = 1000.0
	preview = sim.query_recruit(id, "worker")
	camp["state"] = "packing"
	_expect_rejection(sim, "worker", "camp_packing")
	_check(bool(preview["ok"]), "a stale active-camp plan remains a detached observation")


func _test_admission_order_and_caps() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	var id: int = int(camp["id"])
	sim.outcome = "defeat"
	_expect_rejection(sim, "unknown", "not_playing", 999999)
	sim.outcome = "playing"
	_expect_rejection(sim, "unknown", "unknown_kind", 999999)
	_expect_rejection(sim, "rifle", "no_camp", 999999)
	camp["state"] = "abandoned"
	_expect_rejection(sim, "rifle", "camp_inactive")
	camp["state"] = "active"
	for index: int in range(4):
		_check(sim.recruit(id, "worker"), "local queue accepts slot %d" % index)
	camp["materials"] = 0.0
	_expect_rejection(sim, "rifle", "queue_full")
	var other: Dictionary = sim._make_camp(Vector2(30, 10), "东营", 1000.0, 1000.0, 100.0)
	other["state"] = "packing"
	other["recruit_queue"] = [{"kind": "worker", "elapsed": 0.0, "progress": 0.0, "duration": 12.0, "costs": {}}]
	while sim.units.size() < 27:
		sim._add_unit("rifle", "friendly", Vector2(12, 20), id, 1)
	var dead: Dictionary = sim._add_unit("rifle", "friendly", Vector2(13, 20), id, 1)
	dead["hp"] = 0.0
	sim._add_unit("zombie", "enemy", Vector2(50, 20), -1, 0)
	var capped: Dictionary = sim.query_recruit(id, "rifle")
	_check(capped["population"] == 32, "global population counts live friendlies and every camp queue, excluding dead units and enemies")
	_expect_rejection(sim, "rifle", "population_full")
	# One free slot in the global count must still admit exactly once.
	camp["recruit_queue"] = []
	camp["materials"] = 1000.0
	while sim.units.size() < 32:
		sim._add_unit("rifle", "friendly", Vector2(12, 20), id, 1)
	_check(sim.query_recruit(id, "rifle")["population"] == 31, "queued orders in another camp consume the penultimate global slot")
	_check(sim.recruit(id, "rifle"), "last global slot remains admissible")
	_expect_rejection(sim, "rifle", "population_full")


func _test_local_inventory() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	var other: Dictionary = sim._make_camp(Vector2(30, 10), "东营", 999.0, 999.0, 999.0)
	camp["materials"] = 4.0
	camp["supplies"] = 5.0
	camp["fuel"] = 6.0
	var query: Dictionary = sim.query_recruit(int(camp["id"]), "truck")
	_check(query["missing"] == {"materials": 66.0, "supplies": 20.0, "fuel": 6.0}, "truck plan exposes exact local deficits for all declared resources")
	_check(str(query["message"]).contains("西营") and str(query["message"]).contains("其他营地"), "local shortage names its paying camp and explains other inventory")
	_expect_rejection(sim, "truck", "resources")
	_check(float(other["materials"]) == 999.0 and float(other["fuel"]) == 999.0, "another camp's wealth cannot pay the local order")
	camp["materials"] = 8.0 - 0.00005
	camp["supplies"] = 12.0
	_check(sim.recruit(int(camp["id"]), "worker"), "legacy payment tolerance remains admissible")
	_check(float(camp["materials"]) == 0.0 and float(camp["supplies"]) == 0.0, "accepted tolerance payment clamps the same resources exactly once")


func _test_power_and_facilities() -> void:
	var sim: Variant = _fixture()
	_building(sim, "barracks")["hp"] = 0.0
	_expect_rejection(sim, "rifle", "missing_facility")
	_building(sim, "barracks")["hp"] = 340.0
	_building(sim, "barracks")["progress"] = 0.5
	_expect_rejection(sim, "rifle", "unfinished_facility")
	_building(sim, "barracks")["progress"] = 1.0
	_building(sim, "generator")["hp"] = 0.0
	sim._update_power(0.0)
	_expect_rejection(sim, "rifle", "missing_generator")
	_building(sim, "generator")["hp"] = 220.0
	_building(sim, "generator")["progress"] = 0.5
	_expect_rejection(sim, "rifle", "unfinished_generator")
	_building(sim, "generator")["progress"] = 1.0
	sim.camps[0]["fuel"] = 0.0
	sim.camps[0]["crude"] = 1000.0
	_expect_rejection(sim, "rifle", "fuel_empty")
	sim.camps[0]["fuel"] = 100.0
	_building(sim, "generator")["pos"] = Vector2(25, 10)
	sim._invalidate_navigation()
	sim._update_power(0.0)
	_expect_rejection(sim, "rifle", "generator_road")
	for x: int in range(6, 26):
		sim.roads[Vector2i(x, 10)] = {"progress": 0.5, "camp_id": int(sim.camps[0]["id"])}
	sim._invalidate_navigation()
	sim._update_power(0.0)
	_expect_rejection(sim, "rifle", "generator_road")
	for x: int in range(6, 26):
		sim.roads[Vector2i(x, 10)]["progress"] = 1.0
	sim._invalidate_navigation()
	sim._update_power(0.0)
	_expect_rejection(sim, "rifle", "power_range")
	_building(sim, "generator")["pos"] = Vector2(6, 12)
	_building(sim, "barracks")["pos"] = Vector2(9, 25)
	sim._invalidate_navigation()
	sim._update_power(0.0)
	_expect_rejection(sim, "rifle", "facility_road")
	_building(sim, "barracks")["pos"] = Vector2(9, 10)
	_building(sim, "workshop")["required_power"] = 12.0
	sim._invalidate_navigation()
	sim._update_power(0.0)
	_expect_rejection(sim, "rifle", "power_output")
	_check(bool(sim.query_recruit(int(sim.camps[0]["id"]), "truck")["ok"]), "a powered workshop can train trucks while priority leaves barracks unpowered")


func _test_worker_fallback_and_snapshot() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	var id: int = int(camp["id"])
	_building(sim, "command")["hp"] = 0.0
	_check(bool(sim.query_recruit(id, "worker")["ok"]), "workers retain the real powered-barracks fallback when command building is gone")
	_building(sim, "barracks")["hp"] = 0.0
	_expect_rejection(sim, "worker", "missing_facility")
	_building(sim, "barracks")["hp"] = 340.0
	_building(sim, "barracks")["powered"] = false
	_building(sim, "generator")["available_output"] = 12.0
	_expect_rejection(sim, "rifle", "power_pending")
	sim._update_power(0.0)
	camp["fuel"] = 0.0
	_check(bool(sim.query_recruit(id, "rifle")["ok"]), "query preserves the legacy latest power snapshot until a real tick updates allocation")
	sim._update_power(0.0)
	_expect_rejection(sim, "rifle", "fuel_empty")
	# An unpowered queued head never becomes an added admission restriction.
	camp["fuel"] = 100.0
	_building(sim, "command")["hp"] = 500.0
	sim._update_power(0.0)
	_check(sim.recruit(id, "rifle"), "queue-head fixture begins training")
	_building(sim, "barracks")["powered"] = false
	_check(bool(sim.query_recruit(id, "worker")["ok"]), "new worker admission remains legal when the earlier barracks head lacks power")
	_check(sim.recruit(id, "worker"), "unpowered head does not add a new queue admission rule")


func _test_training_status_and_completion() -> void:
	var sim: Variant = _fixture()
	var id: int = int(sim.camps[0]["id"])
	_check(sim.get_training_status(999999)["code"] == "no_camp", "missing selection has a training status")
	_check(sim.get_training_status(id)["code"] == "idle", "an empty queue has an idle training status")
	for state: String in ["packing", "abandoned"]:
		sim.camps[0]["state"] = state
		var inactive: Dictionary = sim.get_training_status(id)
		_check(inactive["code"] == "inactive" and inactive["text"] == "驻点已停止训练", state + " empty queue explains that the camp stopped training")
		_check(str(inactive["detail"]).contains("无法接收新的训练订单"), state + " empty status explains why new admissions fail")
		_check(inactive["queue_size"] == 0 and inactive["current_name"] == "" and float(inactive["remaining"]) == 0.0 and float(inactive["progress"]) == 0.0, state + " empty queue keeps neutral head readouts")
	sim.camps[0]["state"] = "active"
	_check(sim.recruit(id, "worker") and sim.recruit(id, "rifle"), "training fixture admits two actual sequential orders")
	sim.tick(3.0)
	var status: Dictionary = sim.get_training_status(id)
	_check(status["code"] == "training" and status["current_name"] == "工人" and status["queue_size"] == 2, "training status reflects the actual current queue head")
	_check(is_equal_approx(float(status["remaining"]), 9.0) and is_equal_approx(float(status["progress"]), 0.25), "remaining seconds and progress derive from elapsed training")
	var before: String = _snapshot(sim)
	for index: int in range(5):
		sim.get_training_status(id)
	_check(_snapshot(sim) == before, "status polling cannot advance training or alter recruitment status")
	sim.paused = true
	_check(sim.get_training_status(id)["code"] == "paused", "tactical pause is visible without waiting for a tick")
	sim.tick(20.0)
	_check(is_equal_approx(float(sim.get_training_status(id)["remaining"]), 9.0), "paused wall time cannot complete queued training")
	sim.paused = false
	sim.camps[0]["state"] = "packing"
	_check(sim.get_training_status(id)["code"] == "inactive", "packing warns that local training is paused")
	_check(is_equal_approx(float(sim.get_training_status(id)["remaining"]), 9.0) and is_equal_approx(float(sim.get_training_status(id)["progress"]), 0.25), "a retained inactive queue preserves its current-head progress and remaining time")
	sim.camps[0]["state"] = "active"
	sim.camps[0]["fuel"] = 0.0
	sim.tick(1.0)
	_check(sim.get_training_status(id)["code"] == "waiting_power", "power loss explains the retained queue head")
	_check(is_equal_approx(float(sim.get_training_status(id)["remaining"]), 9.0), "unpowered elapsed time preserves head progress")
	sim.camps[0]["fuel"] = 100.0
	sim.tick(9.0)
	_check(sim.units.size() == 6 and sim.get_training_status(id)["current_name"] == "步枪兵", "actual powered completion spawns one unit and advances to next queued kind")
	sim.tick(20.0)
	_check(sim.units.size() == 7 and sim.get_training_status(id)["code"] == "idle", "sequential training completes and empties exactly once")


func _legacy_recruit(sim: Variant, camp_id: int, kind: String) -> bool:
	# Baseline admission and successful queue payload, from base8a026a4.
	if sim.outcome != "playing" or not Simulation.RECRUIT_COSTS.has(kind):
		return false
	var camp: Dictionary = sim.get_camp(camp_id)
	if camp.is_empty() or str(camp["state"]) != "active":
		return false
	var population: int = 0
	for unit in sim.units:
		if str(unit["team"]) == "friendly" and float(unit["hp"]) > 0.0:
			population += 1
	for other_camp in sim.camps:
		population += Array(other_camp.get("recruit_queue", [])).size()
	if population >= 32:
		return false
	var queue: Array = camp.get("recruit_queue", [])
	if queue.size() >= 4 or not sim._training_power_available(camp, kind):
		return false
	var costs: Dictionary = Dictionary(Simulation.RECRUIT_COSTS[kind]).duplicate(true)
	if not sim._can_pay(camp, costs):
		return false
	sim._pay(camp, costs)
	queue.append({"kind": kind, "elapsed": 0.0, "progress": 0.0, "duration": float(Simulation.RECRUIT_SECONDS[kind]), "costs": costs})
	camp["recruit_queue"] = queue
	camp["recruit_status"] = "training"
	sim._message("%s已安排训练：%s。" % [str(camp.get("name", "营地")), str({"rifle": "步枪兵", "engineer": "工程师", "worker": "工人", "truck": "补给卡车"}[kind])])
	return true


func _test_existing_evacuation_policy() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	var id: int = int(camp["id"])
	_check(sim.recruit(id, "rifle") and sim.recruit(id, "worker"), "evacuation policy fixture has paid training orders")
	sim._make_camp(Vector2(30, 10), "东营", 0.0, 0.0, 0.0)
	_check(sim.evacuate_camp(id), "real evacuation action starts packing the local camp")
	_check(camp["state"] == "packing" and Array(camp["recruit_queue"]).is_empty(), "existing evacuation policy still clears paid training orders")
	_check(is_equal_approx(float(camp["materials"]), 986.0) and is_equal_approx(float(camp["supplies"]), 485.0), "evacuation still refunds exactly half the original recruit costs")
	_check(sim.get_training_status(id)["code"] == "inactive" and sim.get_training_status(id)["queue_size"] == 0, "cleared evacuation queue reports stopped training without implying a retained paused order")
	_expect_rejection(sim, "worker", "camp_packing")


func _test_save_continuation_and_legacy_pair() -> void:
	var baseline: Variant = _fixture()
	var candidate: Variant = _fixture()
	var id: int = int(candidate.camps[0]["id"])
	for kind: String in ["rifle", "engineer", "worker", "truck"]:
		var accepted: bool = _legacy_recruit(baseline, id, kind)
		_check(accepted and candidate.recruit(id, kind) == accepted, kind + " admission matches successful legacy orders")
		_check(_snapshot(baseline) == _snapshot(candidate), kind + " legacy/candidate encoded pair preserves queue payload, success message, exact payment, IDs and RNG")
	baseline.tick(7.0)
	candidate.tick(7.0)
	_check(_snapshot(baseline) == _snapshot(candidate), "legacy/candidate pair stays identical through actual training ticks")
	var loaded: Variant = Simulation.new()
	loaded.reset(88)
	_check(loaded.load_state(JSON.parse_string(_snapshot(candidate))), "a real partially trained queue survives JSON save loading")
	_check(_equivalent(loaded.save_state(), candidate.save_state()), "saved training restores encoded state through JSON numeric roundtrip")
	for seconds: float in [14.0, 27.0, 13.0, 41.0]:
		baseline.tick(seconds)
		candidate.tick(seconds)
		loaded.tick(seconds)
		_check(_snapshot(baseline) == _snapshot(candidate), "legacy/candidate training completion remains deterministic after %s seconds" % seconds)
		_check(_equivalent(loaded.save_state(), candidate.save_state()), "saved queue continuation matches actual completion after %s seconds" % seconds)
	_check(candidate.units.size() == 9 and Array(candidate.camps[0]["recruit_queue"]).is_empty(), "paired real orders produce all four unit kinds and clear their paid queue")


func _equivalent(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return is_equal_approx(float(left), float(right))
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _equivalent(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _equivalent(left[index], right[index]):
				return false
		return true
	return left == right
