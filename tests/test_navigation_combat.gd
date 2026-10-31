extends SceneTree
## Behavioral navigation/combat tests: no private pathfinding, separation or LOS
## helper is called to establish an outcome. Fixtures use public state and orders.

const Simulation = preload("res://scripts/campaign_simulation.gd")
const STEP: float = 0.05
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for radius: float in Simulation.UNIT_RADII.values():
		_check(radius <= Simulation.MAX_UNIT_RADIUS, "collision prefilter contains every configured body radius")
	var cases: Array[Callable] = [
		_test_group_arrival_and_spacing,
		_test_separation_respects_cliffs,
		_test_crowded_pursuit_front,
		_test_bridge_traffic_and_logistics,
		_test_balanced_evacuation_loading,
		_test_recorded_return_trip,
		_test_packing_save_continuation,
		_test_rifle_obstruction,
		_test_high_ground_canyon_fire,
		_test_melee_cannot_bite_through_cliff,
		_test_congested_save_continuation,
		_test_distant_sealed_barrier,
		_test_barrier_fallback_reachability,
	]
	if OS.get_cmdline_user_args().has("--loading-only"):
		cases = [_test_balanced_evacuation_loading]
	if OS.get_cmdline_user_args().has("--snapshot-return-only"):
		cases = [_test_recorded_return_trip]
	if OS.get_cmdline_user_args().has("--packing-save-only"):
		cases = [_test_packing_save_continuation]
	if OS.get_cmdline_user_args().has("--barrier-only"):
		cases = [_test_distant_sealed_barrier, _test_barrier_fallback_reachability]
	for test_case: Callable in cases:
		var before: int = failures.size()
		test_case.call()
		print("%s %s" % ["PASS" if failures.size() == before else "FAIL", test_case.get_method()])
	print("Navigation/combat checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures:
		printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _barrier_fixture(bypass: bool = false, unreachable_approach: bool = false) -> Variant:
	var sim: Variant = _base()
	sim.get_camp(1).pos = Vector2(30, 20)
	sim.buildings[0].pos = Vector2(30, 20)
	for y: int in range(40):
		for x: int in range(20, 23):
			sim.terrain[y][x] = 0 if (y >= 19 and y <= 21) or (bypass and y == 24) else -1
		if unreachable_approach: sim.terrain[y][18] = -1
	var index: int = 0
	for unit: Dictionary in sim.units:
		unit.pos = Vector2(26, 20) if int(unit.id) == 10 else Vector2(30 + index, 24)
		unit.target = unit.pos
		index += 1
	sim.pursuit_x = 18.5
	sim.chokes = [{"name": "Test rear bridge", "pos": Vector2(22, 20), "sealed": false, "pending": false, "building_id": 0, "delay_remaining": 0.0}]
	var enemy: Dictionary = _unit(500, "zombie", Vector2(13.9, 20), "enemy")
	enemy.pursuer = true
	enemy.range = 0.85
	enemy.damage = 12.0
	sim.units.append(enemy)
	_check(sim.seal_choke(0), "controlled bridge uses real paid sealing with every survivor already east")
	_check(sim.load_state(JSON.parse_string(JSON.stringify(sim.save_state()))), "controlled distant-barrier layout is a valid saved campaign")
	return sim


func _test_distant_sealed_barrier() -> void:
	var sim: Variant = _barrier_fixture()
	var origin: Vector2 = sim.get_unit(500).pos
	var barrier_id: int = int(sim.chokes[0].building_id)
	var hp: float = 0.0
	for building: Dictionary in sim.buildings:
		if int(building.id) == barrier_id: hp = float(building.hp)
	_advance(sim, 24.0)
	var unit: Dictionary = sim.get_unit(500)
	var remaining: float = hp
	for building: Dictionary in sim.buildings:
		if int(building.id) == barrier_id: remaining = float(building.hp)
	_check(Vector2(unit.pos).distance_to(origin) > 6.0 and float(unit.pos.x) > 20.0, "pursuer outside close barrier range approaches the reachable western face")
	_check(remaining < hp and bool(sim.chokes[0].sealed), "real melee damages sealed barrier without abstract wave damage before pursuit start")
	_check(float(unit.pos.x) <= 21.5 and sim.pursuit_x == 18.5, "barrier approach keeps body collision and the configured pursuit-front limit")
	_check(float(sim.get_unit(10).hp) == 1000.0, "pursuer cannot attack the command truck through the sealed bridge")
	var resumed: Variant = Simulation.new()
	_check(resumed.load_state(JSON.parse_string(JSON.stringify(sim.save_state(), "", true, true))), "active barrier approach and attack survive real encoded save/load")
	var same: bool = true
	for step: int in range(80):
		sim.tick(STEP)
		resumed.tick(STEP)
		var equal: bool = _barrier_saved_equivalent(sim.save_state(), resumed.save_state())
		if same and not equal:
			for record: Array in [["original", sim], ["resumed", resumed]]:
				var file: FileAccess = FileAccess.open("res://work/barrier-continuation-" + str(record[0]) + ".json", FileAccess.WRITE)
				file.store_string(_exact_saved_state(record[1]))
				file.close()
		same = same and equal
	_check(same, "barrier continuation preserves every state field (double roundtrip ULPs only) and exact RNG on subsequent steps")


func _exact_saved_state(sim: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(sim.save_state(), "", true, true)), "", true, true)


func _barrier_saved_equivalent(left: Variant, right: Variant) -> bool:
	# JSON double parsing can move time by one ULP (24.050000000000207 vs
	# 24.05000000000021). Retain all fields/effects/messages and exact RNG text.
	if (left is int or left is float) and (right is int or right is float):
		return absf(float(left) - float(right)) <= maxf(0.000000000001, maxf(absf(float(left)), absf(float(right))) * 0.000000000000002)
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for key: Variant in left:
			if not right.has(key) or not _barrier_saved_equivalent(left[key], right[key]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index: int in range(left.size()):
			if not _barrier_saved_equivalent(left[index], right[index]): return false
		return true
	return left == right


func _test_barrier_fallback_reachability() -> void:
	var bypass: Variant = _barrier_fixture(true)
	_advance(bypass, 0.4)
	var unit: Dictionary = bypass.get_unit(500)
	_check(Vector2(unit.target).distance_to(Vector2(26, 20)) < 0.2, "reachable distant victim keeps its original target when a legal bypass exists")
	var uses_bypass: bool = false
	for point: Vector2 in unit.path:
		if point.y == 24.0: uses_bypass = true
	_check(uses_bypass, "initial reachable route uses the open alternate bridge")
	var isolated: Variant = _barrier_fixture(false, true)
	var original: Vector2 = isolated.get_unit(500).pos
	_advance(isolated, 2.0)
	_check(Vector2(isolated.get_unit(500).pos).is_equal_approx(original), "unreachable barrier approach does not teleport a pursuer across another canyon")
	_check(Array(isolated.get_unit(500).path).is_empty(), "unreachable fallback is left empty instead of advertising a false route")

func _unit(id_value: int, kind: String, position: Vector2, team: String = "friendly") -> Dictionary:
	var hostile: bool = team == "enemy"
	return {
		"id": id_value, "kind": kind, "team": team, "pos": position,
		"hp": 1000.0, "max_hp": 1000.0, "state": "guard" if hostile else "idle",
		"target": position, "camp_id": -1 if hostile else 1, "squad": 1,
		"speed": 1.7 if kind == "truck" else (0.62 if hostile else 1.25),
		"range": 0.0, "damage": 0.0, "attack_interval": 0.85,
		"cooldown": 0.0, "path": [], "path_index": 0, "repath": 0.0,
		"order": "idle", "manual": false, "job_id": 0, "cargo": {},
		"haul_site": 0, "haul_stage": "", "guard_pos": position,
		"pursuer": false, "capacity": 180.0 if kind == "truck" else 18.0,
	}

func _building(id_value: int, kind: String, position: Vector2) -> Dictionary:
	return {
		"id": id_value, "kind": kind, "pos": position, "camp_id": 1,
		"hp": 2000.0, "max_hp": 2000.0, "progress": 1.0,
		"powered": false, "required_power": 4.0 if kind == "workshop" else 0.0,
		"power_radius": 10.0 if kind == "generator" else 0.0,
	}

func _base() -> Variant:
	var sim: Variant = Simulation.new()
	sim.reset(42)
	var rows: Array = []
	for y: int in range(40):
		var row: Array = []
		row.resize(80)
		row.fill(0)
		rows.append(row)
	sim.terrain = rows
	sim.ramps = {}
	sim.roads = {Vector2i(5, 30): {"progress": 1.0, "camp_id": 1}}
	sim.camps = [{
		"id": 1, "name": "Navigation test camp", "pos": Vector2(4, 30),
		"state": "active", "materials": 5000.0, "supplies": 5000.0,
		"fuel": 5000.0, "salvage": 0.0, "crude": 0.0, "power": 0.0,
		"priority": "production", "recipe": "idle", "recruit_queue": [],
	}]
	sim.buildings = [_building(2, "command", Vector2(4, 30))]
	sim.units = [
		_unit(10, "truck", Vector2(5, 30)),
		_unit(11, "engineer", Vector2(6, 30)),
		_unit(12, "worker", Vector2(4, 31)),
		_unit(13, "rifle", Vector2(5, 31)),
		_unit(14, "worker", Vector2(6, 31)),
	]
	sim.sites = []
	sim.effects = []
	sim.messages = []
	sim.chokes = []
	sim.main_truck_id = 10
	sim.exit_building_id = 0
	sim.exit_site_id = 0
	sim.pursuit_start = 1000000.0
	sim.pursuit_x = -10000.0
	# Use the public save/load schema to keep the fixture's future IDs valid.
	var state: Dictionary = sim.save_state()
	for pair: Array in state.payload.entries:
		if pair[0] == "next_id":
			pair[1] = 10000
	_check(sim.load_state(state), "controlled fixture is a semantically valid public save")
	return sim

func _advance(sim: Variant, seconds: float) -> void:
	for index: int in range(ceili(seconds / STEP)):
		sim.tick(STEP)

func _group(sim: Variant, amount: int = 16, origin: Vector2 = Vector2(8, 18)) -> Array:
	var ids: Array = []
	for index: int in range(amount):
		var position: Vector2 = origin + Vector2(index % 4, index / 4)
		var id_value: int = 100 + index
		sim.units.append(_unit(id_value, "rifle", position))
		ids.append(id_value)
	return ids

func _test_group_arrival_and_spacing() -> void:
	var sim: Variant = _base()
	var ids: Array = _group(sim)
	var destination: Vector2 = Vector2(30, 20)
	sim.command_move(ids, destination)
	_advance(sim, 55.0)
	var unique_tiles: Dictionary = {}
	var minimum_distance: float = INF
	var arrived: int = 0
	var center: Vector2 = Vector2.ZERO
	for id: int in ids:
		var unit: Dictionary = sim.get_unit(id)
		center += Vector2(unit.pos)
		unique_tiles[Vector2i(Vector2(unit.pos).round())] = true
		if Vector2(unit.pos).distance_to(Vector2(unit.target)) < 0.65:
			arrived += 1
		for other_id: int in ids:
			if other_id <= id:
				continue
			minimum_distance = minf(minimum_distance, Vector2(unit.pos).distance_to(Vector2(sim.get_unit(other_id).pos)))
	center /= float(ids.size())
	_check(arrived == ids.size(), "every member reaches its commanded formation area")
	_check(unique_tiles.size() >= 12, "sixteen arrivals do not collapse into one or a few occupied tiles")
	_check(minimum_distance >= 0.49, "arrived infantry retain at least half-tile practical separation")
	_check(center.distance_to(destination) < 2.0, "arrival formation remains centered on the player's actual destination")

func _test_separation_respects_cliffs() -> void:
	var sim: Variant = _base()
	for y: int in range(40):
		for x: int in range(20, 80):
			sim.terrain[y][x] = 1
	var ids: Array = []
	for index: int in range(8):
		var id_value: int = 200 + index
		sim.units.append(_unit(id_value, "rifle", Vector2(19.18, 10.0 + index * 0.04)))
		ids.append(id_value)
	sim.command_move(ids, Vector2(24, 10))
	var illegal_samples: int = 0
	for index: int in range(240):
		sim.tick(STEP)
		for id: int in ids:
			var position: Vector2 = sim.get_unit(id).pos
			var tile: Vector2i = Vector2i(position.round())
			if tile.x < 0 or tile.y < 0 or tile.x >= 80 or tile.y >= 40 or position.x + 0.28 > 19.501:
				illegal_samples += 1
	_check(illegal_samples == 0, "crowd separation never pushes low-ground units across an illegal steep edge")
	var edge: Variant = _base()
	for index: int in range(4):
		edge.units.append(_unit(300 + index, "rifle", Vector2(0.35 + index * 0.02, 0.35)))
	var outside_samples: int = 0
	for index: int in range(80):
		edge.tick(STEP)
		for id: int in range(300, 304):
			var position: Vector2 = edge.get_unit(id).pos
			if position.x < 0.279 or position.y < 0.279 or position.x + 0.28 > 80.001 or position.y + 0.28 > 40.001:
				outside_samples += 1
	_check(outside_samples == 0, "avoidance cannot push crowded units outside map bounds")

func _test_crowded_pursuit_front() -> void:
	var sim: Variant = _base()
	sim.get_camp(1).pos = Vector2(38, 30)
	sim.buildings[0].pos = Vector2(38, 30)
	var friendly_index: int = 0
	for unit: Dictionary in sim.units:
		unit.pos = Vector2(37, 20 + friendly_index * 0.8)
		unit.target = unit.pos
		friendly_index += 1
	sim.time = 200.0
	sim.pursuit_start = 120.0
	sim.pursuit_x = 30.0
	for index: int in range(40):
		var zombie: Dictionary = _unit(800 + index, "zombie", Vector2(32.75 + index % 3 * 0.02, 18.0 + index * 0.035), "enemy")
		zombie.pursuer = true
		zombie.range = 0.85
		zombie.damage = 0.0
		sim.units.append(zombie)
	var violations: int = 0
	for index: int in range(200):
		sim.tick(STEP)
		for unit: Dictionary in sim.units:
			if unit.team == "enemy" and bool(unit.get("pursuer", false)) and float(unit.pos.x) > float(sim.pursuit_x) + 3.001:
				violations += 1
	_check(violations == 0, "dense pursuer movement, spawning and separation never bypass the visible pursuit front")

func _bridge_fixture() -> Variant:
	var sim: Variant = _base()
	sim.get_camp(1).pos = Vector2(8, 20)
	sim.buildings[0].pos = Vector2(8, 20)
	for y: int in range(40):
		for x: int in range(20, 23):
			sim.terrain[y][x] = 0 if y >= 19 and y <= 21 else -1
	sim.roads.clear()
	for x: int in range(8, 31):
		sim.roads[Vector2i(x, 20)] = {"progress": 1.0, "camp_id": 1}
	for y: int in range(20, 24):
		sim.roads[Vector2i(28, y)] = {"progress": 1.0, "camp_id": 1}
	var index: int = 0
	for unit: Dictionary in sim.units:
		unit.pos = Vector2(9 + index % 3, 21 + index / 3)
		unit.target = unit.pos
		index += 1
	sim.sites = [{"id": 400, "kind": "quarry", "name": "Bridge salvage", "pos": Vector2(30, 20), "captured": true, "progress": 1.0, "stock": {"salvage": 180.0}}]
	for offset: int in range(2):
		var blocker: Dictionary = _unit(420 + offset, "rifle", Vector2(21, 19.3 + offset * 0.9))
		blocker.order = "guard"
		blocker.manual = true
		sim.units.append(blocker)
	return sim

func _test_bridge_traffic_and_logistics() -> void:
	var sim: Variant = _bridge_fixture()
	var army: Array = _group(sim, 8, Vector2(13, 18))
	_check(sim.road_connected(Vector2(8, 20), Vector2(30, 20)), "bridge fixture has a real usable supply road")
	_check(sim.build("tower", Vector2i(28, 23)), "bridge scenario orders a paid reachable far-bank construction site")
	sim.command_move(army, Vector2(32, 20))
	sim.command_move([10], Vector2(31, 22))
	var carried_samples: int = 0
	var illegal_samples: int = 0
	for index: int in range(2800):
		sim.tick(STEP)
		for unit: Dictionary in sim.units:
			var tile: Vector2i = Vector2i(Vector2(unit.pos).round())
			if tile.x < 0 or tile.y < 0 or tile.x >= 80 or tile.y >= 40 or int(sim.terrain[tile.y][tile.x]) < 0:
				illegal_samples += 1
			if not Dictionary(unit.get("cargo", {})).is_empty():
				carried_samples += 1
	var passed: int = 0
	for id: int in army:
		if float(sim.get_unit(id).pos.x) > 23.0:
			passed += 1
	_check(passed == army.size(), "all squad members pass a three-tile bridge containing stationary friendly traffic")
	_check(float(sim.get_unit(10).pos.x) > 23.0, "command vehicle can pass the same congested bridge")
	_check(illegal_samples == 0, "bridge traffic never resolves congestion by walking through the canyon")
	_check(carried_samples > 0 and float(sim.get_camp(1).salvage) > 0.0, "workers physically carry and deliver salvage across the bridge")
	var completed: bool = false
	for building: Dictionary in sim.buildings:
		if building.kind == "tower" and Vector2(building.pos).distance_to(Vector2(28, 23)) < 0.1 and float(building.progress) >= 1.0:
			completed = true
	_check(completed, "far-bank engineer construction finishes instead of deadlocking at the bridge")

func _evac_fixture(materials: float, fuel: float, supplies: float, destination_fuel: float = 0.0, destination_supplies: float = 0.0) -> Variant:
	var sim: Variant = _base()
	var source: Dictionary = sim.get_camp(1)
	source.materials = materials
	source.fuel = fuel
	source.supplies = supplies
	var destination: Dictionary = source.duplicate(true)
	destination.id = 900
	destination.name = "Loading test receiving camp"
	destination.pos = Vector2(20, 30)
	destination.materials = 0.0
	destination.fuel = destination_fuel
	destination.supplies = destination_supplies
	destination.salvage = 0.0
	destination.crude = 0.0
	sim.camps.append(destination)
	var marker: Dictionary = _building(901, "camp", Vector2(20, 30))
	marker.camp_id = 900
	sim.buildings.append(marker)
	# Keep ordinary food consumption in a third camp so the loading/deposit
	# conservation assertions cannot mistake a legitimate meal for lost cargo.
	var staging: Dictionary = source.duplicate(true)
	staging.id = 950
	staging.name = "Survivor staging camp"
	staging.pos = Vector2(4, 35)
	staging.materials = 0.0
	staging.fuel = 0.0
	staging.supplies = 1000.0
	sim.camps.append(staging)
	var staging_marker: Dictionary = _building(951, "camp", Vector2(4, 35))
	staging_marker.camp_id = 950
	sim.buildings.append(staging_marker)
	var people: int = 0
	for unit: Dictionary in sim.units:
		if unit.kind == "truck": continue
		unit.camp_id = 950
		unit.pos = Vector2(5 + people % 3, 35 + people / 3)
		unit.target = unit.pos
		unit.guard_pos = unit.pos
		people += 1
	for x: int in range(4, 21):
		sim.roads[Vector2i(x, 30)] = {"progress": 1.0, "camp_id": 1}
	return sim

func _resources(camp: Dictionary) -> Dictionary:
	return {"materials": float(camp.materials), "fuel": float(camp.fuel), "supplies": float(camp.supplies), "salvage": float(camp.get("salvage", 0.0)), "crude": float(camp.get("crude", 0.0))}

func _cargo_weight(cargo: Dictionary) -> float:
	var weight: float = 0.0
	for amount: Variant in cargo.values(): weight += float(amount)
	return weight

func _wait_for_departure(sim: Variant) -> Dictionary:
	_check(sim.evacuate_camp(1), "public evacuation order begins real packing")
	for index: int in range(400):
		var before: Dictionary = _resources(sim.get_camp(1))
		sim.tick(STEP)
		var truck: Dictionary = sim.get_unit(10)
		var cargo: Dictionary = truck.get("cargo", {})
		if str(truck.get("haul_stage", "")) == "outbound" and not cargo.is_empty():
			_check(_cargo_weight(cargo) <= float(truck.capacity) + 0.0001, "packed cargo never exceeds the unchanged truck capacity")
			var after: Dictionary = _resources(sim.get_camp(1))
			for resource: String in before:
				_check(is_equal_approx(float(before[resource]) - float(after[resource]), float(cargo.get(resource, 0.0))), "loading deducts the actual " + resource + " cargo from its source")
			return cargo.duplicate(true)
	_check(false, "stocked or partially stocked camp dispatches its truck without waiting for full reserves")
	return {}

func _wait_for_delivery(sim: Variant, dispatched: Dictionary) -> void:
	_check(not dispatched.is_empty(), "delivery check has a physically dispatched cargo")
	if dispatched.is_empty(): return
	for index: int in range(1200):
		var before: Dictionary = _resources(sim.get_camp(900))
		var carried: bool = not Dictionary(sim.get_unit(10).get("cargo", {})).is_empty()
		sim.tick(STEP)
		var truck: Dictionary = sim.get_unit(10)
		if carried and Dictionary(truck.get("cargo", {})).is_empty() and Vector2(truck.pos).distance_to(Vector2(sim.get_camp(900).pos)) < 2.5:
			var after: Dictionary = _resources(sim.get_camp(900))
			for resource: String in dispatched:
				_check(is_equal_approx(float(after[resource]) - float(before[resource]), float(dispatched[resource])), "physical arrival deposits the dispatched " + resource + " into the receiving camp")
			return
	_check(false, "dispatched balanced cargo physically arrives at the receiving camp")

func _test_balanced_evacuation_loading() -> void:
	var balanced: Variant = _evac_fixture(500.0, 100.0, 100.0)
	var cargo: Dictionary = _wait_for_departure(balanced)
	_check(is_equal_approx(float(cargo.get("fuel", 0.0)), 50.0), "empty receiving camp gets its fifty-unit emergency fuel reserve")
	_check(is_equal_approx(float(cargo.get("supplies", 0.0)), 40.0), "empty receiving camp gets its forty-unit food reserve")
	_check(is_equal_approx(float(cargo.get("materials", 0.0)), 90.0), "remaining capacity carries construction material rather than exceeding capacity")
	_check(is_equal_approx(float(balanced.get_camp(900).materials), 0.0), "departure alone does not teleport cargo to the destination")
	_wait_for_delivery(balanced, cargo)
	var partial_reserves: Variant = _evac_fixture(500.0, 100.0, 100.0, 35.0, 30.0)
	var top_up: Dictionary = _wait_for_departure(partial_reserves)
	_check(is_equal_approx(float(top_up.get("fuel", 0.0)), 15.0), "partial fuel reserve is topped up only by its actual shortfall")
	_check(is_equal_approx(float(top_up.get("supplies", 0.0)), 10.0), "partial food reserve is topped up only by its actual shortfall")
	_check(is_equal_approx(float(top_up.get("materials", 0.0)), 155.0), "limited reserve top-ups leave the remaining capacity for material")
	_wait_for_delivery(partial_reserves, top_up)
	var sufficient: Variant = _evac_fixture(300.0, 30.0, 30.0, 70.0, 80.0)
	var material_cargo: Dictionary = _wait_for_departure(sufficient)
	_check(is_equal_approx(float(material_cargo.get("materials", 0.0)), 180.0), "destination with sufficient reserves receives material first")
	_check(is_zero_approx(float(material_cargo.get("fuel", 0.0))) and is_zero_approx(float(material_cargo.get("supplies", 0.0))), "existing destination reserves are not needlessly topped up before material")
	_wait_for_delivery(sufficient, material_cargo)
	var scarce: Variant = _evac_fixture(7.0, 3.0, 2.0)
	var scarce_cargo: Dictionary = _wait_for_departure(scarce)
	_check(not scarce_cargo.is_empty() and _cargo_weight(scarce_cargo) < 180.0, "insufficient source stock still departs as a partial load")
	_check(is_equal_approx(float(scarce_cargo.get("materials", 0.0)), 7.0) and is_equal_approx(float(scarce_cargo.get("fuel", 0.0)), 3.0), "partial load uses only the actually available material and fuel")
	_check(scarce.get_camp(1).state == "abandoned", "exhausted source abandons without inventing missing reserve stock")
	_wait_for_delivery(scarce, scarce_cargo)
	var repeat: Variant = _evac_fixture(500.0, 100.0, 100.0)
	_check(repeat.evacuate_camp(1), "multi-trip evacuation starts through the public command")
	var deliveries: int = 0
	for index: int in range(2500):
		var old_cargo: bool = not Dictionary(repeat.get_unit(10).get("cargo", {})).is_empty()
		var before_total: float = _cargo_weight(_resources(repeat.get_camp(900)))
		repeat.tick(0.1)
		var truck: Dictionary = repeat.get_unit(10)
		var after_total: float = _cargo_weight(_resources(repeat.get_camp(900)))
		if old_cargo and Dictionary(truck.get("cargo", {})).is_empty() and after_total > before_total + 0.001:
			deliveries += 1
			print("EVAC_DELIVERY count=", deliveries, " time=", repeat.time, " received_total=", after_total, " pos=", truck.pos)
		if deliveries >= 3: break
	var stalled: Dictionary = repeat.get_unit(10)
	print("EVAC_MULTI_TRIP deliveries=", deliveries, " time=", repeat.time, " pos=", stalled.pos, " target=", stalled.target, " path_index=", stalled.get("path_index", 0), " pathlen=", Array(stalled.get("path", [])).size(), " source_distance=", Vector2(stalled.pos).distance_to(Vector2(repeat.get_camp(1).pos)), " destination_distance=", Vector2(stalled.pos).distance_to(Vector2(repeat.get_camp(900).pos)), " stage=", stalled.get("haul_stage", ""))
	_check(deliveries >= 3, "public evacuation completes at least three actual cargo deliveries within 250 seconds")

func _test_recorded_return_trip() -> void:
	var path: String = "res://tests/fixtures/evacuation-return-blocked.json"
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var sim: Variant = Simulation.new()
	sim.reset(42)
	var valid: bool = data is Dictionary and sim.load_state(data)
	_check(valid, "recorded public-playthrough return blockage loads without rewriting terrain, actors or roads")
	if not valid: return
	var truck_id: int = int(sim.main_truck_id)
	var truck: Dictionary = sim.get_unit(truck_id)
	var source_id: int = int(truck.get("evac_origin_id", 0))
	var destination_id: int = int(truck.get("evac_destination_id", 0))
	print("RECORDED_RETURN_START pos=", truck.pos, " target=", truck.target, " index=", truck.get("path_index", 0), "/", Array(truck.get("path", [])).size(), " wait=", truck.get("nav_wait", 0.0), " stage=", truck.get("haul_stage", ""))
	var loaded: bool = false
	for index: int in range(100):
		sim.tick(0.1)
		truck = sim.get_unit(truck_id)
		if not Dictionary(truck.get("cargo", {})).is_empty() and str(truck.get("haul_stage", "")) == "outbound":
			loaded = true
			break
	print("RECORDED_RETURN_AFTER time=", sim.time, " loaded=", loaded, " pos=", truck.pos, " target=", truck.target, " index=", truck.get("path_index", 0), "/", Array(truck.get("path", [])).size(), " wait=", truck.get("nav_wait", 0.0), " source_distance=", Vector2(truck.pos).distance_to(Vector2(sim.get_camp(source_id).pos)), " destination_distance=", Vector2(truck.pos).distance_to(Vector2(sim.get_camp(destination_id).pos)), " stage=", truck.get("haul_stage", ""), " cargo=", truck.get("cargo", {}))
	_check(loaded, "recorded near-camp return can resume packing and dispatch the next real cargo within ten seconds")

func _test_packing_save_continuation() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/evacuation-return-blocked.json"))
	var original: Variant = Simulation.new()
	original.reset(42)
	var valid: bool = data is Dictionary and original.load_state(data)
	_check(valid, "legacy packing save loads for one-time staging correction")
	if not valid: return
	var source_id: int = int(original.get_unit(original.main_truck_id).evac_origin_id)
	_check(int(original.get_camp(source_id).get("evac_gather_version", 0)) == 0, "recorded legacy packing fixture predates the staging version")
	original.tick(STEP)
	_check(int(original.get_camp(source_id).get("evac_gather_version", 0)) == 1, "legacy packing receives its staging correction on the next real tick")
	var targets: Dictionary = {}
	var unique_targets: Dictionary = {}
	for unit: Dictionary in original.units:
		if unit.team == "friendly" and int(unit.camp_id) == source_id and str(unit.get("order", "")) == "evac_gather":
			targets[int(unit.id)] = Vector2(unit.target)
			unique_targets[Vector2i(Vector2(unit.target).round())] = true
	_check(not targets.is_empty(), "packing continuation fixture contains actual gathering personnel")
	_check(unique_targets.size() == targets.size(), "corrected gather targets reserve distinct staging positions")
	var corrected: Dictionary = original.save_state()
	var restored: Variant = Simulation.new()
	restored.reset(42)
	_check(restored.load_state(JSON.parse_string(JSON.stringify(corrected))), "corrected packing save JSON-roundtrips")
	_check(int(restored.get_camp(source_id).get("evac_gather_version", 0)) == 1, "staging version persists across load")
	_check(_equivalent(_core(corrected), _core(restored.save_state())), "loading corrected packing preserves paths and targets without replanning")
	for id: int in targets:
		_check(Vector2(restored.get_unit(id).target) == Vector2(targets[id]), "gathering target persists for unit %d" % id)
	_advance(original, 10.0)
	_advance(restored, 10.0)
	_check(_equivalent(_core(original.save_state()), _core(restored.save_state())), "corrected packing and actual next cargo continue identically after load")
	var again: Variant = Simulation.new()
	again.reset(42)
	_check(again.load_state(JSON.parse_string(JSON.stringify(restored.save_state()))), "a second corrected packing save loads")
	_check(_equivalent(_core(restored.save_state()), _core(again.save_state())), "repeated load does not reset or replan established gather paths")
	_advance(restored, 2.0)
	_advance(again, 2.0)
	_check(_equivalent(_core(restored.save_state()), _core(again.save_state())), "repeated packing load keeps subsequent deterministic continuation")
	var invalid: Dictionary = corrected.duplicate(true)
	var mutated: bool = false
	for pair: Array in invalid.payload.entries:
		if pair[0] != "camps": continue
		for encoded_camp: Dictionary in pair[1]:
			var matches_source: bool = false
			for field: Array in encoded_camp.entries:
				if field[0] == "id" and int(field[1]) == source_id: matches_source = true
			if not matches_source: continue
			for field: Array in encoded_camp.entries:
				if field[0] == "evac_gather_version":
					field[1] = "broken"
					mutated = true
	_check(mutated, "semantic corruption test locates the saved staging version")
	var before: Dictionary = again.save_state()
	_check(not again.load_state(invalid), "invalid staging-version type is rejected")
	_check(_equivalent(before, again.save_state()), "invalid staging version leaves the active campaign unchanged")

func _combat_fixture(source: Vector2 = Vector2(10, 10), target: Vector2 = Vector2(15, 10)) -> Variant:
	var sim: Variant = _base()
	var shooter: Dictionary = _unit(500, "rifle", source)
	shooter.range = 6.0
	shooter.damage = 12.0
	shooter.order = "guard"
	shooter.speed = 0.0
	var enemy: Dictionary = _unit(501, "zombie", target, "enemy")
	enemy.speed = 0.0
	enemy.range = 0.0
	enemy.damage = 0.0
	sim.units.append(shooter)
	sim.units.append(enemy)
	return sim

func _test_rifle_obstruction() -> void:
	var clear: Variant = _combat_fixture()
	_advance(clear, 4.0)
	_check(float(clear.get_unit(501).hp) < 1000.0, "unobstructed rifle fire actually damages a stationary in-range zombie")
	var workshop: Variant = _combat_fixture()
	workshop.buildings.append(_building(510, "workshop", Vector2(12, 10)))
	_advance(workshop, 4.0)
	_check(is_equal_approx(float(workshop.get_unit(501).hp), 1000.0), "rifle cannot shoot through an intervening completed workshop")
	var plateau: Variant = _combat_fixture()
	for y: int in range(8, 13):
		for x: int in range(12, 14):
			plateau.terrain[y][x] = 1
	_advance(plateau, 4.0)
	_check(is_equal_approx(float(plateau.get_unit(501).hp), 1000.0), "low-ground rifle cannot shoot through a solid intervening high plateau")
	var ruined: Variant = _combat_fixture()
	var wreck: Dictionary = _building(510, "workshop", Vector2(12, 10))
	wreck.hp = 0.0
	ruined.buildings.append(wreck)
	_advance(ruined, 4.0)
	_check(float(ruined.get_unit(501).hp) < 1000.0, "a destroyed workshop no longer acts as an invisible firing wall")
	var changing: Variant = _combat_fixture()
	var weakened: Dictionary = _building(510, "workshop", Vector2(12, 10))
	weakened.hp = 0.5
	changing.buildings.append(weakened)
	_advance(changing, 0.1)
	_check(is_equal_approx(float(changing.get_unit(501).hp), 1000.0), "a live weakened workshop still blocks fire before its destruction")
	changing.time = 200.0
	changing.pursuit_start = 150.0
	changing.pursuit_x = 20.0
	_advance(changing, 3.0)
	_check(float(weakened.hp) <= 0.0, "actual pursuit damage destroys the intervening workshop")
	_check(float(changing.get_unit(501).hp) < 1000.0, "destroyed geometry stops blocking subsequent fire without a save/load or manual cache reset")

func _test_high_ground_canyon_fire() -> void:
	var high: Variant = _combat_fixture(Vector2(10, 10), Vector2(16.5, 10))
	for y: int in range(8, 13):
		for x: int in range(9, 12):
			high.terrain[y][x] = 1
		for x: int in range(12, 16):
			high.terrain[y][x] = -1
		for x: int in range(16, 20):
			high.terrain[y][x] = 1
	_advance(high, 4.0)
	_check(float(high.get_unit(501).hp) < 1000.0, "high-ground rifle can legally fire across open canyon space at extended range")
	var low_range: Variant = _combat_fixture(Vector2(10, 10), Vector2(16.5, 10))
	_advance(low_range, 4.0)
	_check(is_equal_approx(float(low_range.get_unit(501).hp), 1000.0), "the same distance is outside an ordinary low-ground rifle's range")

func _test_melee_cannot_bite_through_cliff() -> void:
	var cliff: Variant = _base()
	var flat: Variant = _base()
	for sim: Variant in [cliff, flat]:
		var victim: Dictionary = _unit(600, "worker", Vector2(11, 10.65))
		victim.speed = 0.0
		victim.manual = true
		var zombie: Dictionary = _unit(601, "zombie", Vector2(11, 10.35), "enemy")
		zombie.speed = 0.0
		zombie.range = 0.85
		zombie.damage = 6.0
		sim.units.append(victim)
		sim.units.append(zombie)
	for y: int in range(11, 40):
		for x: int in range(80):
			cliff.terrain[y][x] = 1
	_advance(cliff, 3.0)
	_advance(flat, 3.0)
	_check(is_equal_approx(float(cliff.get_unit(600).hp), 1000.0), "nearby zombie cannot bite a survivor through an unconnected elevation edge")
	_check(float(flat.get_unit(600).hp) < 1000.0, "the same close-range zombie can damage a survivor on continuous flat terrain")

func _test_congested_save_continuation() -> void:
	var original: Variant = _bridge_fixture()
	var army: Array = _group(original, 12, Vector2(13, 17))
	for id: int in army:
		var unit: Dictionary = original.get_unit(id)
		unit.range = 6.0
		unit.damage = 12.0
	for index: int in range(6):
		var zombie: Dictionary = _unit(700 + index, "zombie", Vector2(28 + index % 3, 19 + index / 3), "enemy")
		zombie.range = 0.85
		zombie.damage = 6.0
		original.units.append(zombie)
	original.command_move(army, Vector2(29, 20), true)
	_check(original.build("tower", Vector2i(28, 23)), "continuation fixture contains live bridge construction")
	_advance(original, 8.0)
	var data: Variant = JSON.parse_string(JSON.stringify(original.save_state()))
	var restored: Variant = Simulation.new()
	restored.reset(42)
	_check(data is Dictionary and restored.load_state(data), "congested combat/construction JSON save loads")
	_advance(original, 25.0)
	_advance(restored, 25.0)
	_check(_equivalent(_core(original.save_state()), _core(restored.save_state())), "formation, separation, combat and traffic continue identically after save/load")

func _core(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	var entries: Array = result.payload.entries
	for index: int in range(entries.size() - 1, -1, -1):
		if entries[index][0] in ["effects", "messages"]:
			entries.remove_at(index)
	return result

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
