extends SceneTree
## Frozen 07ce movement methods are the behavioral oracle. No timing claim.
const Simulation = preload("res://scripts/campaign_simulation.gd")
const ORIGINAL_SIMULATION_SHA256: String = "8f80e3cea63b023a19c4dc624761dacbbaf1991cdd82234b45e984bb68c0eddb"
var checks: int = 0
var failures: Array[String] = []

class CountedSimulation:
	extends "res://scripts/campaign_simulation.gd"
	var overlap_calls: int = 0
	var blocker_calls: int = 0
	func _first_body_blocker(unit: Dictionary, position: Vector2) -> Dictionary:
		blocker_calls += 1
		return super._first_body_blocker(unit, position)
	func _improves_existing_overlap(unit: Dictionary, destination: Vector2) -> bool:
		overlap_calls += 1
		return super._improves_existing_overlap(unit, destination)

class OriginalMovement:
	extends "res://scripts/campaign_simulation.gd"
	# These three bodies are verbatim from frozen Simulation SHA above.
	func _body_is_clear(unit: Dictionary, position: Vector2) -> bool:
		var radius: float = _unit_radius(unit)
		var broadphase_radius: float = radius + MAX_UNIT_RADIUS
		var unit_id: int = int(unit["id"])
		for other in _nearby_bodies(position):
			if int(other["id"]) == unit_id:
				continue
			var other_position: Vector2 = Vector2(other["pos"])
			var offset: Vector2 = position - other_position
			if absf(offset.x) > broadphase_radius or absf(offset.y) > broadphase_radius:
				continue
			if float(other["hp"]) <= 0.0 or str(other["state"]) == "evacuated":
				continue
			var minimum: float = radius + _unit_radius(other) - 0.01
			if offset.length_squared() < minimum * minimum:
				return false
		return true

	func _try_body_move(unit: Dictionary, destination: Vector2) -> bool:
		if not _within_pursuit_front(unit, destination):
			return false
		if not _static_motion_clear(Vector2(unit["pos"]), destination, _unit_radius(unit), str(unit["team"])):
			return false
		if not _body_is_clear(unit, destination) and not _improves_existing_overlap(unit, destination):
			return false
		_set_unit_position(unit, destination)
		return true

	func _improves_existing_overlap(unit: Dictionary, destination: Vector2) -> bool:
		# Existing overlaps from old saves/spawn fixtures may slide apart along a
		# wall; requiring a completely clear first step would deadlock both bodies.
		var origin: Vector2 = Vector2(unit["pos"])
		var radius: float = _unit_radius(unit)
		var broadphase_radius: float = radius + MAX_UNIT_RADIUS
		var unit_id: int = int(unit["id"])
		var old_penetration: float = 0.0
		var new_penetration: float = 0.0
		var seen: Dictionary = {}
		var neighbors: Array = _nearby_bodies(origin)
		# Short movement within one bucket has exactly the same neighbor sequence.
		# Avoid scanning it twice, and copy only when merging two cached snapshots.
		var same_bucket: bool = Vector2i(origin.floor()) == Vector2i(destination.floor())
		if not same_bucket:
			neighbors = neighbors.duplicate()
			neighbors.append_array(_nearby_bodies(destination))
		for other in neighbors:
			var identifier: int = int(other["id"])
			if identifier == unit_id or (not same_bucket and seen.has(identifier)):
				continue
			var other_position: Vector2 = Vector2(other["pos"])
			var old_offset: Vector2 = origin - other_position
			var new_offset: Vector2 = destination - other_position
			if (absf(old_offset.x) > broadphase_radius or absf(old_offset.y) > broadphase_radius) and (absf(new_offset.x) > broadphase_radius or absf(new_offset.y) > broadphase_radius):
				continue
			if float(other["hp"]) <= 0.0 or str(other["state"]) == "evacuated":
				continue
			if not same_bucket:
				seen[identifier] = true
			var minimum: float = radius + _unit_radius(other) - 0.01
			var previous: float = maxf(0.0, minimum - old_offset.length())
			var next: float = maxf(0.0, minimum - new_offset.length())
			if next > previous + EPSILON:
				return false
			old_penetration += previous
			new_penetration += next
		return old_penetration > EPSILON and new_penetration + EPSILON < old_penetration


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_rejection_and_required_fallbacks()
	_test_epsilon_and_radius_cases()
	_test_buckets_live_reads_and_attempts()
	_test_unchanged_yield_and_short_circuit()
	_test_reset_load_and_public_ticks()
	print("First blocker rejection checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)


func _encoded(sim: Variant) -> String:
	return JSON.stringify(sim.save_state(), "", false, true)


func _unit(identifier: int, position: Vector2, kind: String = "rifle") -> Dictionary:
	return {"id": identifier, "kind": kind, "team": "friendly", "pos": position,
		"hp": 100.0, "max_hp": 100.0, "state": "idle", "target": position,
		"order": "idle", "manual": false, "job_id": 0, "cargo": {},
		"path": [], "path_index": 0, "repath": 0.0, "nav_wait": 0.0}


func _pair(bodies: Array) -> Array:
	var pair: Array = [CountedSimulation.new(), OriginalMovement.new()]
	for sim: Variant in pair:
		sim._rng.seed = 42
		sim.map_size = Vector2i(20, 12)
		for y: int in range(12):
			var row: Array = []
			row.resize(20)
			row.fill(0)
			sim.terrain.append(row)
		sim.units = bodies.duplicate(true)
	return pair


func _move(pair: Array, destination: Vector2, label: String, expected: int = -1, fallback: int = -1) -> void:
	var before: int = int(pair[0].overlap_calls)
	var actual: bool = pair[0]._try_body_move(pair[0].get_unit(1), destination)
	var original: bool = pair[1]._try_body_move(pair[1].get_unit(1), destination)
	_check(actual == original, label + ": original move decision")
	if expected >= 0: _check(actual == bool(expected), label + ": required outcome")
	if fallback >= 0: _check(int(pair[0].overlap_calls) - before == fallback, label + ": required fallback count")
	_check(_encoded(pair[0]) == _encoded(pair[1]), label + ": complete encoded state/entry order")
	_check(str(pair[0]._rng.state) == str(pair[1]._rng.state), label + ": exact RNG")


func _test_rejection_and_required_fallbacks() -> void:
	var worsening: Array = _pair([_unit(1, Vector2(5, 5)), _unit(2, Vector2(5.4, 5))])
	_move(worsening, Vector2(5.05, 5), "one live worsening pair rejects", 0, 0)
	var clear: Array = _pair([_unit(1, Vector2(5, 5)), _unit(2, Vector2(7, 5))])
	_move(clear, Vector2(5.05, 5), "clear body move still succeeds", 1, 0)
	var retreat: Array = _pair([_unit(1, Vector2(5, 5)), _unit(2, Vector2(5.4, 5))])
	_check(not retreat[0]._body_is_clear(retreat[0].get_unit(1), Vector2(4.95, 5)), "sliding legacy overlap remains body-blocked")
	_move(retreat, Vector2(4.95, 5), "existing overlap can slide apart", 1, 1)
	var second: Array = _pair([_unit(1, Vector2(5.2, 5)), _unit(3, Vector2(5.6, 5)), _unit(2, Vector2(4.8, 5))])
	_check(int(second[0]._first_body_blocker(second[0].get_unit(1), Vector2(5.25, 5)).id) == 2, "first destination blocker improves before a later blocker worsens")
	_move(second, Vector2(5.25, 5), "improving witness cannot imply overall allowance", 0, 1)
	var unchanged: Array = _pair([_unit(1, Vector2(5, 5)), _unit(2, Vector2(5.4, 5))])
	_move(unchanged, Vector2(5, 5), "unchanged penetration is not improvement", 0, 1)
	var tiny_improvement: Array = _pair([_unit(1, Vector2(5, 5)), _unit(2, Vector2(5.4, 5))])
	_move(tiny_improvement, Vector2(4.9999995, 5), "aggregate improvement below epsilon is rejected", 0, 1)
	var new_shallow: Array = _pair([_unit(1, Vector2(5, 5)), _unit(2, Vector2(5.55, 5))])
	_move(new_shallow, Vector2(5.0000005, 5), "new shallow contact cannot bypass old-sum requirement", 0, 1)


func _test_epsilon_and_radius_cases() -> void:
	for displacement: float in [0.0000005, 0.0000015]:
		var pair: Array = _pair([_unit(1, Vector2(5, 5)), _unit(2, Vector2(5.55, 5))])
		var origin: Vector2 = pair[0].get_unit(1).pos
		var other: Vector2 = pair[0].get_unit(2).pos
		var destination: Vector2 = Vector2(5.0 + displacement, 5)
		var minimum: float = pair[0]._unit_radius(pair[0].get_unit(1)) + pair[0]._unit_radius(pair[0].get_unit(2)) - 0.01
		var previous: float = maxf(0.0, minimum - (origin - other).length())
		var next: float = maxf(0.0, minimum - (destination - other).length())
		var predicted: bool = next > previous + Simulation.EPSILON
		_check(predicted == (displacement > 0.000001), "representable contact fixtures lie on opposite sides of actual scalar epsilon test")
		_move(pair, destination, "epsilon boundary uses original length/maxf/strict greater", 0, 0 if predicted else 1)
	for kind: String in Simulation.UNIT_RADII:
		for other_kind: String in ["worker", "truck"]:
			for direction: Vector2 in [Vector2.RIGHT, Vector2(0.6, 0.8), Vector2.LEFT]:
				var minimum: float = float(Simulation.UNIT_RADII[kind]) + float(Simulation.UNIT_RADII[other_kind]) - 0.01
				var pair: Array = _pair([_unit(1, Vector2(5.25, 5.25), kind), _unit(2, Vector2(5.25, 5.25) + direction * (minimum - 0.08), other_kind)])
				_move(pair, Vector2(5.25, 5.25) + direction * 0.04, "all configured radii and non-axis worsening", 0, 0)


func _test_buckets_live_reads_and_attempts() -> void:
	var crossing: Array = _pair([_unit(1, Vector2(4.98, 5.2)), _unit(2, Vector2(5.38, 5.2))])
	_move(crossing, Vector2(5.03, 5.2), "cross-bucket worsening", 0, 0)
	_move(crossing, Vector2(4.93, 5.2), "next attempt recomputes improving witness", 1, 1)
	var merged: Array = _pair([_unit(3, Vector2(5.41, 5.2)), _unit(1, Vector2(5.01, 5.2)), _unit(2, Vector2(5.45, 5.25))])
	_move(merged, Vector2(4.96, 5.2), "cross-bucket fallback retains origin then destination and ID de-duplication", 1, 1)
	var live: Array = _pair([_unit(1, Vector2(5, 5)), _unit(2, Vector2(5.4, 5)), _unit(3, Vector2(5.3, 5))])
	for sim: Variant in live:
		sim._nearby_bodies(Vector2(5, 5))
		sim.get_unit(2).hp = 0.0
		sim.get_unit(3).state = "evacuated"
	_move(live, Vector2(5.05, 5), "cached bodies still read live death and evacuation", 1, 0)
	for sim: Variant in live:
		sim.get_unit(2).hp = 100.0
		sim._set_unit_position(sim.get_unit(2), Vector2(6.01, 5))
	_move(live, Vector2(5.55, 5), "another unit crossing buckets invalidates snapshots", 0, 0)
	for sim: Variant in live:
		sim.get_unit(2).kind = "worker"
		sim._set_unit_position(sim.get_unit(2), Vector2(7, 5))
	_move(live, Vector2(5.55, 5), "new attempt reads moved body and changed radius", 1, 0)
	var self_only: Array = _pair([_unit(1, Vector2(5, 5))])
	_check(self_only[0]._body_is_clear(self_only[0].get_unit(1), Vector2(5, 5)), "boolean API excludes self")
	_move(self_only, Vector2(5.05, 5), "self cannot supply a blocker", 1, 0)


func _test_unchanged_yield_and_short_circuit() -> void:
	var pair: Array = _pair([_unit(1, Vector2(5, 5)), _unit(2, Vector2(5.52, 5), "worker")])
	for sim: Variant in pair:
		sim.get_unit(1).order = "construct"
		sim._nearby_bodies(Vector2(5.1, 5))
		sim.get_unit(2).hp = 0.0
	var before: Vector2 = pair[0].get_unit(2).pos
	var actual: bool = pair[0]._yield_idle_friend(pair[0].get_unit(1), Vector2(5.1, 5), Vector2.RIGHT, 0.05)
	var original: bool = pair[1]._yield_idle_friend(pair[1].get_unit(1), Vector2(5.1, 5), Vector2.RIGHT, 0.05)
	_check(actual and actual == original and Vector2(pair[0].get_unit(2).pos) != before, "unchanged yield can move a newly dead cached low-priority body")
	_check(_encoded(pair[0]) == _encoded(pair[1]), "yield preserves full original state")
	_move(pair, Vector2(5.1, 5), "post-yield attempt has no retained witness", 1, 0)
	var front: Array = _pair([_unit(1, Vector2(1.5, 5))])
	for sim: Variant in front:
		sim.get_unit(1).team = "enemy"
		sim.get_unit(1).pursuer = true
	_move(front, Vector2(3, 5), "pursuit-front rejection remains first", 0, 0)
	_check(front[0].blocker_calls == 0 and front[0]._nav_cache_time == -INF, "front short circuit calls neither body query nor static navigation")
	var static_block: Array = _pair([_unit(1, Vector2(5, 5))])
	for sim: Variant in static_block: sim.terrain[5][6] = -1
	_move(static_block, Vector2(6, 5), "static geometry rejection stays before body scan", 0, 0)
	_check(static_block[0].blocker_calls == 0, "static short circuit never queries a body blocker")


func _test_reset_load_and_public_ticks() -> void:
	var pair: Array = [CountedSimulation.new(), OriginalMovement.new()]
	for sim: Variant in pair: _check(sim.reset(42, "ridge"), "real Ridge reset")
	var checkpoint: Dictionary = pair[0].save_state()
	for sim: Variant in pair:
		var truck: Dictionary = sim.get_unit(sim.main_truck_id)
		sim._try_body_move(truck, Vector2(truck.pos))
		_check(sim.load_state(checkpoint.duplicate(true)), "real public save/load after collision queries")
	_check(_encoded(pair[0]) == _encoded(pair[1]), "load contains no new witness/context state")
	for step: int in range(30):
		for sim: Variant in pair: sim.tick(0.05)
		_check(_encoded(pair[0]) == _encoded(pair[1]) and str(pair[0]._rng.state) == str(pair[1]._rng.state), "loaded Ridge public tick retains full state and RNG")
	for sim: Variant in pair: _check(sim.reset(43, "canyon"), "next real campaign resets normally")
	for step: int in range(30):
		for sim: Variant in pair: sim.tick(0.05)
		_check(_encoded(pair[0]) == _encoded(pair[1]) and str(pair[0]._rng.state) == str(pair[1]._rng.state), "reset public tick retains full state and RNG")
