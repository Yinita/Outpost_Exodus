extends SceneTree
## Exact path-cache contracts; no timing, actor caps or changed navigation rules.
const Simulation = preload("res://scripts/campaign_simulation.gd")
var checks: int = 0
var failures: Array[String] = []

class CountedSimulation:
	extends "res://scripts/campaign_simulation.gd"
	var path_computations: int = 0
	func _find_path_uncached(start: Vector2i, finish: Vector2i, team: String) -> Array:
		path_computations += 1
		return super._find_path_uncached(start, finish, team)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_path_order_and_array_ownership()
	_test_empty_and_team_queries()
	_test_time_and_navigation_invalidation()
	_test_in_place_terrain_ramps_and_map_size()
	_test_bound_and_save_lifecycle()
	print("Path query cache checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)


func _flat(width: int = 8, height: int = 6) -> CountedSimulation:
	var sim: CountedSimulation = CountedSimulation.new()
	sim.map_size = Vector2i(width, height)
	for y: int in range(height):
		var row: Array = []
		row.resize(width)
		row.fill(0)
		sim.terrain.append(row)
	return sim


func _building(at: Vector2, kind: String = "generator") -> Dictionary:
	return {"id": 500, "kind": kind, "pos": at, "hp": 100.0, "progress": 1.0, "span": 0}


func _test_path_order_and_array_ownership() -> void:
	var sim: CountedSimulation = _flat()
	var first: Array = sim._find_path(Vector2(1, 1), Vector2(3, 3))
	var expected: Array = [Vector2(2, 1), Vector2(3, 1), Vector2(3, 2), Vector2(3, 3)]
	_check(first == expected, "original east-first A* tie/order is retained exactly")
	first[0] = Vector2(77, 77)
	first.append(Vector2(88, 88))
	var second: Array = sim._find_path(Vector2(1, 1), Vector2(3, 3))
	_check(second == expected and sim.path_computations == 1, "miss result cannot mutate the private stored path")
	var third: Array = sim._find_path(Vector2(1, 1), Vector2(3, 3))
	_check(not is_same(second, third), "each hit returns its own Array")
	var first_unit: Dictionary = {"path": second}
	var second_unit: Dictionary = {"path": third}
	first_unit.path.clear()
	_check(second_unit.path == expected and sim._find_path(Vector2(1, 1), Vector2(3, 3)) == expected, "two units and later hits cannot share mutable path arrays")
	var tile: Array = sim._find_path(Vector2(2, 2), Vector2(2, 2))
	tile.clear()
	_check(sim._find_path(Vector2(2, 2), Vector2(2, 2)) == [Vector2(2, 2)], "same-tile result is independently owned and includes its finish")
	var blocked: CountedSimulation = _flat()
	blocked.buildings.append(_building(Vector2(2, 2)))
	var resolved: Array = blocked._find_path(Vector2(2, 2), Vector2(5, 1))
	_check(resolved == blocked._find_path(Vector2(2, 1), Vector2(5, 1)) and blocked.path_computations == 1, "key uses original canonical nearest-tile resolution, not raw positions")


func _test_empty_and_team_queries() -> void:
	var sim: CountedSimulation = _flat(2, 1)
	sim.terrain[0][1] = 1
	var empty: Array = sim._find_path(Vector2.ZERO, Vector2(1, 0))
	empty.append(Vector2(9, 9))
	_check(sim._find_path(Vector2.ZERO, Vector2(1, 0)).is_empty() and sim.path_computations == 1, "empty component-rejection result is cached and privately copied")
	var invalid: CountedSimulation = _flat(2, 1)
	invalid.terrain[0] = [-1, -1]
	_check(invalid._find_path(Vector2.ZERO, Vector2.ONE).is_empty() and invalid._find_path(Vector2.ZERO, Vector2.ONE).is_empty() and invalid.path_computations == 1, "invalid endpoints are an independently cacheable empty result")
	var teams: CountedSimulation = _flat()
	teams.buildings.append(_building(Vector2(3, 2)))
	var friendly: Array = teams._find_path(Vector2(1, 2), Vector2(5, 2), "friendly")
	var logistics: Array = teams._find_path(Vector2(1, 2), Vector2(5, 2), "logistics")
	var enemy: Array = teams._find_path(Vector2(1, 2), Vector2(5, 2), "enemy")
	_check(not friendly.has(Vector2(3, 2)) and logistics.has(Vector2(3, 2)) and enemy == friendly, "logistics keeps its original non-barrier building traversal")
	_check(teams.path_computations == 3, "team selectors are distinct cache keys")
	teams.buildings[0].kind = "barricade"
	teams._ensure_navigation_index(true)
	_check(not teams._find_path(Vector2(1, 2), Vector2(5, 2), "logistics").has(Vector2(3, 2)), "forced barrier rebuild preserves logistics obstruction")


func _test_time_and_navigation_invalidation() -> void:
	var sim: CountedSimulation = _flat()
	var expected: Array = sim._find_path(Vector2(1, 2), Vector2(5, 2))
	sim.time += 0.05
	_check(sim._find_path(Vector2(1, 2), Vector2(5, 2)) == expected and sim.path_computations == 1, "new simulation time reuses an exactly unchanged static query")
	sim.time = 0.0
	sim._find_path(Vector2(1, 2), Vector2(5, 2))
	_check(sim.path_computations == 1 and sim._path_query_cache_count == 1, "time rewind alone cannot change a static path")
	sim._invalidate_navigation()
	_check(sim._path_query_cache_count == 0, "explicit navigation invalidation drops path entries immediately")
	sim._find_path(Vector2(1, 2), Vector2(5, 2))
	sim._ensure_navigation_index(true)
	_check(sim._path_query_cache_count == 0, "forced navigation rebuild drops path entries immediately")
	sim._find_path(Vector2(1, 2), Vector2(5, 2))
	_check(sim.path_computations == 3, "forced rebuild cannot reuse a preceding path")
	sim.buildings.append(_building(Vector2(3, 4)))
	sim._find_path(Vector2(1, 2), Vector2(5, 2))
	_check(sim.path_computations == 4, "actual navigation rebuild from building-count change invalidates paths")
	sim.buildings[0].pos = Vector2(3, 2)
	_check(sim._find_path(Vector2(1, 2), Vector2(5, 2)) == expected and sim.path_computations == 4, "cache does not secretly force old same-time stale-building geometry to rebuild")
	sim.time += 0.05
	_check(not sim._find_path(Vector2(1, 2), Vector2(5, 2)).has(Vector2(3, 2)) and sim.path_computations == 5, "new-time geometry relocation triggers original navigation rebuild before a cache hit")
	sim.buildings[0].hp = 0.0
	sim._invalidate_navigation()
	_check(sim._find_path(Vector2(1, 2), Vector2(5, 2)) == expected, "lethal geometry invalidation restores the original unobstructed path")


func _test_in_place_terrain_ramps_and_map_size() -> void:
	var sim: CountedSimulation = _flat()
	var first: Array = sim._find_path(Vector2(1, 2), Vector2(5, 2))
	sim.terrain[2][3] = -1
	_check(sim._path_query_terrain_snapshot[2][3] == 0, "terrain snapshot owns deeply copied rows")
	var changed: Array = sim._find_path(Vector2(1, 2), Vector2(5, 2))
	_check(changed != first and not changed.has(Vector2(3, 2)) and sim.path_computations == 2, "same-time in-place terrain edit is observed without changing old component semantics")
	sim.terrain[2][3] = 0
	_check(sim._find_path(Vector2(1, 2), Vector2(5, 2)) == first and sim.path_computations == 3, "same-time terrain restoration cannot hit the intervening result")
	sim.terrain[0] = sim.terrain[0].duplicate()
	sim._find_path(Vector2(1, 2), Vector2(5, 2))
	_check(sim.path_computations == 3, "same-valued row replacement has exact deep equality")
	sim.terrain = sim.terrain.duplicate(true)
	sim._find_path(Vector2(1, 2), Vector2(5, 2))
	_check(sim.path_computations == 4, "same-valued outer terrain replacement still preserves original navigation-source rebuild")
	sim.map_size = Vector2i(7, 6)
	_check(sim._find_path(Vector2(1, 2), Vector2(5, 2)) == first and sim.path_computations == 5, "map-size changes invalidate queries without forcing navigation")
	sim.time += 0.05
	sim.terrain[2][3] = -1
	_check(not sim._find_path(Vector2(1, 2), Vector2(5, 2)).has(Vector2(3, 2)) and sim.path_computations == 6, "new-time in-place terrain edit cannot reuse old static path")
	var ramps: CountedSimulation = _flat(2, 1)
	ramps.terrain[0][1] = 1
	ramps.ramps = {Vector2i.ZERO: true, Vector2i(1, 0): true}
	_check(ramps._find_path(Vector2.ZERO, Vector2(1, 0)) == [Vector2(1, 0)], "original ramp pair permits an elevation step")
	ramps.ramps.erase(Vector2i(1, 0))
	_check(ramps._path_query_ramps_snapshot.has(Vector2i(1, 0)), "ramp snapshot is privately owned")
	_check(ramps._find_path(Vector2.ZERO, Vector2(1, 0)).is_empty() and ramps.path_computations == 2, "same-time ramp removal cannot return a previously traversable path")
	ramps.ramps[Vector2i(1, 0)] = true
	_check(ramps._find_path(Vector2.ZERO, Vector2(1, 0)) == [Vector2(1, 0)] and ramps.path_computations == 3, "same-time ramp restoration is observed with old component state intact")
	ramps.ramps[Vector2i(1, 0)] = false
	_check(ramps._find_path(Vector2.ZERO, Vector2(1, 0)) == [Vector2(1, 0)], "ramp values do not change original has-key traversal semantics")
	ramps.time += 0.05
	ramps.ramps.erase(Vector2i(1, 0))
	_check(ramps._find_path(Vector2.ZERO, Vector2(1, 0)).is_empty() and ramps.path_computations == 5, "new-time ramp edit invalidates a static query")
	var disconnected: CountedSimulation = _flat(2, 1)
	disconnected.terrain[0][1] = 1
	_check(disconnected._find_path(Vector2.ZERO, Vector2(1, 0)).is_empty(), "initial unequal elevation has separate original components")
	disconnected.ramps = {Vector2i.ZERO: true, Vector2i(1, 0): true}
	disconnected.time += 0.05
	_check(disconnected._find_path(Vector2.ZERO, Vector2(1, 0)).is_empty() and disconnected.path_computations == 2, "adding ramps does not force-repair the original stale disconnected component index")


func _test_bound_and_save_lifecycle() -> void:
	var sim: CountedSimulation = _flat()
	for index: int in range(Simulation.PATH_QUERY_CACHE_LIMIT + 17):
		_check(sim._find_path(Vector2(1, 1), Vector2(5, 1), "team_%d" % index) == [Vector2(2, 1), Vector2(3, 1), Vector2(4, 1), Vector2(5, 1)], "cache capacity never changes uncached path behavior")
	var entries: int = 0
	for team: String in sim._path_query_cache: entries += Dictionary(sim._path_query_cache[team]).size()
	_check(entries == Simulation.PATH_QUERY_CACHE_LIMIT and sim._path_query_cache_count == entries and sim._path_query_fifo.size() == entries, "hard entry and FIFO limits apply across all teams")
	_check(sim._path_query_cache.size() == entries and not sim._path_query_cache.has("team_0"), "FIFO removes empty team buckets instead of growing an outer history")
	var calls: int = sim.path_computations
	sim._find_path(Vector2(1, 1), Vector2(5, 1), "team_17")
	_check(sim.path_computations == calls, "FIFO retains the oldest not-yet-evicted entry")
	sim._find_path(Vector2(1, 1), Vector2(5, 1), "team_0")
	_check(sim.path_computations == calls + 1 and not sim._path_query_cache.has("team_17") and sim._path_query_cache.has("team_0"), "a hit does not reorder FIFO and a later miss evicts the original oldest entry")
	var copied: Array = sim._find_path(Vector2(1, 1), Vector2(5, 1), "team_0")
	copied.clear()
	_check(not sim._find_path(Vector2(1, 1), Vector2(5, 1), "team_0").is_empty(), "eviction and reinsertion keep independently owned path returns")
	sim.time += 0.05
	sim._find_path(Vector2(1, 1), Vector2(5, 1), "team_0")
	_check(sim.path_computations == calls + 1 and sim._path_query_cache_count == entries, "new time preserves static entries while the total structure stays bounded")
	sim._invalidate_navigation()
	_check(sim._path_query_fifo.is_empty() and sim._path_query_fifo_cursor == 0 and sim._path_query_cache.is_empty(), "navigation invalidation clears the whole FIFO lifecycle")
	var campaign: CountedSimulation = CountedSimulation.new()
	_check(campaign.reset(42, "ridge"), "real campaign resets normally")
	var before: String = JSON.stringify(campaign.save_state(), "", false, true)
	campaign._find_path(Vector2(8, 19), Vector2(14, 19), "prior_run")
	_check(JSON.stringify(campaign.save_state(), "", false, true) == before, "query entries and snapshots never enter full saved state or RNG")
	var checkpoint: Dictionary = campaign.save_state()
	_check(not campaign.reset(42, "missing") and not campaign.load_state({"version": -1}), "rejected reset/load preserve original state")
	_check(JSON.stringify(campaign.save_state(), "", false, true) == before and campaign._path_query_cache.has("prior_run"), "rejected reset/load do not clear a valid current query")
	_check(campaign.reset(43, "ridge") and not campaign._path_query_cache.has("prior_run"), "successful reset cannot retain prior-run paths")
	campaign._find_path(Vector2(8, 19), Vector2(14, 19))
	_check(campaign.load_state(checkpoint) and campaign._path_query_cache_count == 0, "successful real load discards all derived paths")
	_check(JSON.stringify(campaign.save_state(), "", false, true) == before, "load retains complete authoritative state and RNG exactly")
