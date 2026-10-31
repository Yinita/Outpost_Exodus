extends SceneTree
## Headless behavior checks for shared placement and production feedback.

const Simulation = preload("res://scripts/campaign_simulation.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_test_queries_and_atomic_commits, _test_rejection_reasons, _test_local_inventory_and_road_costs, _test_cached_preview_invalidation, _test_builders_and_recovery, _test_production_status, _test_exit_power_is_progress_gate]:
		var previous: int = failures.size()
		test.call()
		print("%s %s" % ["PASS" if previous == failures.size() else "FAIL", test.get_method()])
	print("Construction feedback checks: %d; failures: %d" % [checks, failures.size()])
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
	var camp: Dictionary = sim._make_camp(Vector2(6, 10), "西营", 500.0, 200.0, 100.0)
	camp["recipe"] = "idle"
	sim.roads = {Vector2i(6, 10): {"progress": 1.0, "camp_id": int(camp["id"])}}
	sim._add_building("command", Vector2(6, 10), int(camp["id"]), 1.0)
	var truck: Dictionary = sim._add_unit("truck", "friendly", Vector2(6, 11), int(camp["id"]), 0)
	sim.main_truck_id = int(truck["id"])
	for position: Vector2 in [Vector2(8, 13), Vector2(9, 13), Vector2(10, 13)]:
		sim._add_unit("rifle", "friendly", position, int(camp["id"]), 1)
	sim._add_unit("worker", "friendly", Vector2(5, 10), int(camp["id"]), 0)
	sim.exit_site_id = 0
	sim.exit_building_id = 0
	sim.exit_progress = 0.0
	sim.pursuit_x = -10000.0
	sim.pursuit_start = 1000000.0
	sim._invalidate_navigation()
	return sim


func _snapshot(sim: Variant, ignore_messages: bool = false) -> String:
	var state: Dictionary = sim.save_state()
	if ignore_messages:
		for entry in state["payload"]["entries"]:
			if entry[0] == "messages":
				entry[1] = []
	return JSON.stringify(state)


func _advance(sim: Variant, seconds: float) -> void:
	for tick: int in range(ceili(seconds / 0.05)):
		sim.tick(0.05)


func _road(sim: Variant, from_x: int, to_x: int, y: int, progress: float = 1.0) -> void:
	for x: int in range(from_x, to_x + 1):
		sim.roads[Vector2i(x, y)] = {"progress": progress, "camp_id": int(sim.camps[0]["id"])}
	sim._invalidate_navigation()


func _expect_rejection(sim: Variant, kind: String, tile: Vector2i, code: String) -> void:
	var before: String = _snapshot(sim)
	var query: Dictionary = sim.query_build(kind, tile)
	_check(not bool(query["ok"]) and query["code"] == code, code + " has a precise preview rejection")
	_check(not str(query["message"]).is_empty(), code + " has an explanation")
	_check(not sim.can_build(kind, tile) and _snapshot(sim) == before, code + " queries do not change saved state")
	var authoritative_before: String = _snapshot(sim, true)
	var result: Dictionary = sim.try_build(kind, tile)
	_check(not bool(result["ok"]) and result["message"] == query["message"], code + " click matches preview reason")
	_check(_snapshot(sim, true) == authoritative_before, code + " rejects atomically without charges or partial orders")


func _test_queries_and_atomic_commits() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	var before: String = _snapshot(sim)
	for index: int in range(3):
		var query: Dictionary = sim.query_build("tower", Vector2i(8, 10))
		_check(bool(query["ok"]) and query["position"] == Vector2(8, 10), "query uses authoritative integer placement")
		_check(str(query["message"]).begins_with("可下单"), "preview success is prospective")
		sim.query_build("road", Vector2i(13, 10))
		sim.get_production_status(int(camp["id"]))
	_check(_snapshot(sim) == before, "repeated queries preserve resources, jobs, messages, IDs and RNG")
	var query: Dictionary = sim.query_build("tower", Vector2i(8, 10))
	query["costs"]["materials"] = 1.0
	_check(float(sim.query_build("tower", Vector2i(8, 10))["costs"]["materials"]) == 35.0, "caller cannot modify declared costs through a query")
	var materials_before: float = float(camp["materials"])
	var result: Dictionary = sim.try_build("tower", Vector2i(8, 10))
	_check(bool(result["ok"]) and float(camp["materials"]) == materials_before - 35.0, "accepted building pays exactly once")
	_check(result["message"] == "已设立工地：自动炮塔。工程师会领取材料并前往施工。", "building commit preserves legacy success message")
	_check(sim._jobs.size() == 1 and sim.buildings.size() == 2, "accepted building creates one job and site")
	_expect_rejection(sim, "tower", Vector2i(8, 10), "spacing")
	var stale: Variant = _fixture()
	_check(bool(stale.query_build("tower", Vector2i(8, 10))["ok"]), "preview initially affordable")
	stale.camps[0]["materials"] = 0.0
	_expect_rejection(stale, "tower", Vector2i(8, 10), "resources")
	stale.camps[0]["materials"] = 34.98
	_check(str(stale.query_build("tower", Vector2i(8, 10))["message"]).contains("建材0.02"), "fractional shortage never appears as zero")
	stale.camps[0]["materials"] = 34.999
	_check(str(stale.query_build("tower", Vector2i(8, 10))["message"]).contains("不足0.01"), "tiny nonzero shortage remains visible")


func _test_rejection_reasons() -> void:
	var sim: Variant = _fixture()
	_expect_rejection(sim, "road", Vector2i(-1, 10), "terrain")
	sim.terrain[10][12] = -1
	_expect_rejection(sim, "tower", Vector2i(12, 10), "terrain")
	_expect_rejection(sim, "tower", Vector2i(7, 11), "spacing")
	_expect_rejection(sim, "exit", Vector2i(12, 10), "automatic_exit")
	_expect_rejection(sim, "unknown", Vector2i(12, 10), "unknown_kind")
	sim.outcome = "victory"
	_expect_rejection(sim, "tower", Vector2i(8, 10), "not_playing")
	sim = _fixture()
	sim.camps[0]["state"] = "packing"
	_expect_rejection(sim, "tower", Vector2i(8, 10), "no_active_camp")
	sim = _fixture()
	sim.pursuit_x = 20.0
	_expect_rejection(sim, "tower", Vector2i(8, 10), "pursuit")
	_check(bool(sim.query_build("road", Vector2i(7, 10))["ok"]), "road rules still bypass pursuit and building spacing")
	sim = _fixture()
	_check(bool(sim.query_build("generator", Vector2i(15, 10))["ok"]), "local buildings can be ordered without a completed road or power")
	_expect_rejection(sim, "tower", Vector2i(20, 10), "road_connection")
	_road(sim, 6, 20, 10, 0.0)
	_expect_rejection(sim, "tower", Vector2i(20, 10), "road_connection")
	_road(sim, 6, 20, 10)
	_check(bool(sim.query_build("tower", Vector2i(20, 10))["ok"]), "completed usable road permits distant building")
	sim = _fixture()
	for y: int in range(sim.map_size.y):
		for x: int in range(10, sim.map_size.x):
			sim.terrain[y][x] = 1
	_expect_rejection(sim, "tower", Vector2i(12, 10), "unreachable")
	_expect_rejection(sim, "road", Vector2i(12, 10), "road_unreachable")
	sim = _fixture()
	_expect_rejection(sim, "road", Vector2i(6, 10), "road_exists")
	sim.roads[Vector2i(8, 10)] = {"progress": 0.0, "camp_id": int(sim.camps[0]["id"])}
	_expect_rejection(sim, "road", Vector2i(8, 10), "road_planned")


func _test_local_inventory_and_road_costs() -> void:
	var sim: Variant = _fixture()
	var west: Dictionary = sim.camps[0]
	var east: Dictionary = sim._make_camp(Vector2(16, 10), "东营", 0.0, 0.0, 0.0)
	sim._add_building("camp", Vector2(16, 10), int(east["id"]), 1.0)
	var query: Dictionary = sim.query_build("generator", Vector2i(14, 10))
	_check(query["camp_id"] == east["id"] and query["camp_name"] == "东营", "nearest active camp owns the order")
	_check(query["missing"] == {"materials": 30.0, "fuel": 5.0}, "deficits use only nearest local inventory")
	_expect_rejection(sim, "generator", Vector2i(14, 10), "resources")
	east["materials"] = 30.0
	east["fuel"] = 5.0
	var west_before: float = float(west["materials"])
	_check(sim.build("generator", Vector2i(14, 10)) and float(west["materials"]) == west_before and float(east["materials"]) == 0.0, "richer remote inventory is neither charged nor substituted")
	sim = _fixture()
	query = sim.query_build("road", Vector2i(12, 10))
	var planned: Array = query["road_tiles"].duplicate()
	_check(not planned.is_empty() and float(query["costs"]["materials"]) == planned.size() * 2.0, "route query prices every new tile exactly")
	sim.camps[0]["materials"] = float(query["costs"]["materials"]) - 1.0
	_expect_rejection(sim, "road", Vector2i(12, 10), "resources")
	sim.camps[0]["materials"] = float(query["costs"]["materials"])
	var result: Dictionary = sim.try_build("road", Vector2i(12, 10))
	_check(bool(result["ok"]) and float(sim.camps[0]["materials"]) == 0.0, "full road segment pays atomically once")
	_check(result["message"] == "已规划 %d 格道路，工人和工程师将逐段施工。" % planned.size(), "road commit preserves legacy success message")
	result["road_tiles"].clear()
	result["costs"]["materials"] = -10.0
	_check(sim._jobs[0]["road_tiles"] == planned and float(sim._jobs[0]["costs"]["materials"]) == planned.size() * 2.0, "returned road plan cannot mutate authoritative job")
	for tile in planned:
		_check(sim.roads.has(tile) and float(sim.roads[tile]["progress"]) == 0.0, "accepted route contains every quoted unfinished tile")


func _test_cached_preview_invalidation() -> void:
	var sim: Variant = _fixture()
	_check(bool(sim.query_build("tower", Vector2i(8, 10), false)["ok"]), "cached preview starts with available location")
	_check(sim.build("tower", Vector2i(8, 10)), "normal building order commits")
	_check(sim.query_build("tower", Vector2i(8, 10), false)["code"] == "spacing", "cached preview sees newly committed site at same simulation time")
	sim = _fixture()
	for y: int in range(sim.map_size.y):
		if y < 9 or y > 11:
			sim.terrain[y][12] = -1
	for index: int in range(sim.units.size()):
		sim.units[index]["pos"] = Vector2(16 + index, 10)
	sim.chokes = [{"pos": Vector2(12, 10), "name": "测试关口", "sealed": false}]
	_check(bool(sim.query_build("tower", Vector2i(14, 10), false)["ok"]), "cached preview sees initially open crossing")
	_check(sim.seal_choke(0), "normal seal command creates complete barrier")
	_check(sim.query_build("tower", Vector2i(14, 10), false)["code"] == "unreachable", "cached preview honors normal seal navigation invalidation")


func _test_builders_and_recovery() -> void:
	var sim: Variant = _fixture()
	sim.units = sim.units.filter(func(unit: Dictionary) -> bool: return str(unit["kind"]) != "worker")
	var query: Dictionary = sim.query_build("tower", Vector2i(8, 10))
	_check(bool(query["ok"]) and not str(query["warning"]).is_empty(), "no builders warns without refusing placement")
	_check(sim.build("tower", Vector2i(8, 10)), "construction accepts order without an engineer or worker")
	var ordered: Dictionary = sim.buildings.back()
	var worker: Dictionary = sim._add_unit("worker", "friendly", Vector2(5, 10), int(sim.camps[0]["id"]), 0)
	worker["manual"] = true
	worker["order"] = "guard"
	sim._update_jobs(0.05)
	_check(int(sim._jobs[0]["assigned"]) == 0, "manual persistent orders keep crews unavailable")
	sim.command_move([int(worker["id"])], Vector2(5, 11))
	_advance(sim, 40.0)
	_check(float(ordered["progress"]) == 1.0, "arrived manual move returns worker to automation and worker-only crew completes")


func _factory(sim: Variant, workshop_position: Vector2 = Vector2(8, 10), generator_position: Vector2 = Vector2(6, 12)) -> Array:
	var camp_id: int = int(sim.camps[0]["id"])
	var workshop: Dictionary = sim._add_building("workshop", workshop_position, camp_id, 1.0)
	var generator: Dictionary = sim._add_building("generator", generator_position, camp_id, 1.0)
	sim._update_power(0.0)
	return [workshop, generator]


func _status_code(sim: Variant, expected: String, detail: String = "") -> Dictionary:
	var before: String = _snapshot(sim)
	var result: Dictionary = sim.get_production_status(int(sim.camps[0]["id"]))
	_check(result["code"] == expected, "production status: " + expected)
	_check(detail.is_empty() or str(result["detail"]).contains(detail), "production detail: " + detail)
	_check(_snapshot(sim) == before, "production query leaves saved state unchanged: " + expected)
	return result


func _test_production_status() -> void:
	var sim: Variant = _fixture()
	_status_code(sim, "idle")
	sim.camps[0]["recipe"] = "materials"
	_status_code(sim, "missing_workshop")
	var workshop: Dictionary = sim._add_building("workshop", Vector2(8, 10), int(sim.camps[0]["id"]), 0.0)
	_status_code(sim, "unfinished_workshop")
	workshop["progress"] = 1.0
	_status_code(sim, "unpowered", "没有已完工发电机")
	var generator: Dictionary = sim._add_building("generator", Vector2(6, 12), int(sim.camps[0]["id"]), 0.0)
	_status_code(sim, "unpowered", "发电机完工")
	generator["progress"] = 1.0
	sim.camps[0]["fuel"] = 0.0
	sim.camps[0]["crude"] = 100.0
	sim._update_power(0.0)
	_status_code(sim, "unpowered", "原油不能直接燃烧")
	sim.camps[0]["fuel"] = 100.0
	sim._update_power(0.0)
	var result: Dictionary = _status_code(sim, "running")
	_check(result["working"] == 1 and result["total"] == 1, "counts describe actually supplied completed workshops")
	for recipe: String in ["materials", "fuel", "supplies"]:
		sim.camps[0]["recipe"] = recipe
		var input: String = {"materials": "salvage", "fuel": "crude", "supplies": "fuel"}[recipe]
		var saved_input: float = float(sim.camps[0][input])
		sim.camps[0][input] = 0.0
		# Current powered flags are authoritative until the next simulation power step.
		_status_code(sim, "input_empty")
		sim.camps[0][input] = saved_input
		var output_before: float = float(sim.camps[0][recipe])
		sim._update_production(1.0)
		_check(float(sim.camps[0][recipe]) > output_before, recipe + " running status corresponds to actual output")
	sim.paused = true
	_status_code(sim, "paused")
	sim.camps[0]["state"] = "packing"
	_status_code(sim, "inactive")
	sim = _fixture()
	sim.camps[0]["recipe"] = "materials"
	_factory(sim, Vector2(8, 10), Vector2(15, 10))
	_status_code(sim, "unpowered", "发电机尚未连上")
	sim = _fixture()
	sim.camps[0]["recipe"] = "materials"
	_factory(sim, Vector2(15, 10))
	_status_code(sim, "unpowered", "工坊尚未连上")
	sim = _fixture()
	sim.camps[0]["recipe"] = "materials"
	_road(sim, 6, 20, 10)
	_factory(sim, Vector2(20, 10))
	_status_code(sim, "unpowered", "超出")
	sim = _fixture()
	sim.camps[0]["recipe"] = "materials"
	sim.camps[0]["priority"] = "defense"
	_factory(sim)
	for y: int in range(10, 15):
		_road(sim, 6, 9, y)
	for x: int in range(6, 10):
		sim._add_building("tower", Vector2(x, 14), int(sim.camps[0]["id"]), 1.0)
	sim._update_power(0.0)
	_status_code(sim, "unpowered", "优先级")


func _test_exit_power_is_progress_gate() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	_road(sim, 6, 12, 10)
	var exit_building: Dictionary = sim._add_building("exit", Vector2(12, 10), -1, 0.0)
	exit_building["required_power"] = 6.0
	exit_building["construction_started"] = false
	sim.exit_building_id = int(exit_building["id"])
	sim.exit_site_id = 9000
	sim.sites = [{"id": 9000, "kind": "exit", "name": "测试出口", "pos": Vector2(12, 10), "captured": true, "progress": 1.0, "stock": {}}]
	var materials_before: float = float(camp["materials"])
	sim._update_exit(0.0)
	_check(bool(exit_building["construction_started"]) and float(camp["materials"]) == materials_before - 140.0, "exit auto-funds without any generator or power")
	_check(sim.messages.back() == "撤离站已立项：工程师施工需要附近发电机提供 6 电力。完成后将指挥车和幸存者送达。", "exit legacy success message unchanged")
	_advance(sim, 20.0)
	_check(float(exit_building["progress"]) == 0.0, "funded delivered exit job waits for power before progress")
	sim._add_building("generator", Vector2(8, 8), int(camp["id"]), 1.0)
	_advance(sim, 90.0)
	_check(float(exit_building["progress"]) == 1.0, "worker can complete exit after local power returns")
