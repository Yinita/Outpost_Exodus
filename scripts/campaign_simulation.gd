extends RefCounted
## Pure-state, deterministic first-campaign simulation. Coordinates are tile units.
## All orders, construction, logistics and evacuation happen in simulation time.

const SAVE_VERSION: int = 1
const CampaignCatalog = preload("res://scripts/campaign_catalog.gd")
const ConstructionRules = preload("res://scripts/construction_rules.gd")
const RecruitmentRules = preload("res://scripts/recruitment_rules.gd")
const MISSION_SAVE_TAGS: Dictionary = {"canyon": "rift_escape_01", "delta": "wetland_escape_02", "ridge": "ridge_escape_03"}
const BUILD_COSTS: Dictionary = {
	"road": {"materials": 2.0},
	"camp": {"materials": 50.0, "supplies": 10.0},
	"generator": {"materials": 30.0, "fuel": 5.0},
	"workshop": {"materials": 40.0},
	"tower": {"materials": 35.0, "supplies": 5.0},
	"barracks": {"materials": 60.0, "supplies": 20.0},
	"barricade": {"materials": 20.0},
	"exit": {"materials": 140.0, "fuel": 45.0, "supplies": 30.0}
}
const BUILD_SECONDS: Dictionary = {"road": 1.5, "camp": 16.0, "generator": 12.0, "workshop": 18.0, "tower": 14.0, "barracks": 24.0, "barricade": 7.0, "exit": 45.0}
const RECRUIT_COSTS: Dictionary = {
	"rifle": {"materials": 20.0, "supplies": 18.0},
	"engineer": {"materials": 25.0, "supplies": 15.0},
	"worker": {"materials": 8.0, "supplies": 12.0},
	"truck": {"materials": 70.0, "supplies": 25.0, "fuel": 12.0}
}
const RECRUIT_SECONDS: Dictionary = {"rifle": 20.0, "engineer": 26.0, "worker": 12.0, "truck": 40.0}
const POPULATION_CAP: int = 32
const RECRUIT_QUEUE_CAP: int = 4
const EVAC_RESERVES: Dictionary = {"fuel": 50.0, "supplies": 40.0}
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0)]
const RESOURCE_KEYS: Array[String] = ["materials", "supplies", "fuel", "salvage", "crude"]
const MAX_ENEMIES: int = 100
const EPSILON: float = 0.000001
const UNIT_RADII: Dictionary = {"rifle": 0.28, "engineer": 0.28, "worker": 0.24, "truck": 0.46, "zombie": 0.28, "runner": 0.24, "brute": 0.36}
const HIGH_GROUND_RANGE_BONUS: float = 1.0
# Conservative axis bound for rejecting distant neighbors before radius lookup.
const MAX_UNIT_RADIUS: float = 0.46

var time: float = 0.0
var phase: String = "preparation"
var outcome: String = "playing"
var paused: bool = false
var map_size: Vector2i = Vector2i(80, 40)
var terrain: Array = []
var roads: Dictionary = {}
var ramps: Dictionary = {}
var units: Array = []
var buildings: Array = []
var camps: Array = []
var sites: Array = []
var effects: Array = []
var messages: Array = []
var pursuit_x: float = -5.0
var pursuit_eta: float = 540.0
var exit_progress: float = 0.0
var evacuated: int = 0
var seed_value: int = 42
var chokes: Array = []
var mission_id: String = "canyon"
var _mission_data: Dictionary = CampaignCatalog.mission("canyon")
# A fresh copy prevents a UI consumer from changing this run's mission metadata.
var mission_data: Dictionary:
	get:
		return _mission_data.duplicate(true)
var mission_name: String = "裂谷突围"
var objective: String = "清理北部废料场与南部油库，铺路建立前营，修复东部撤离站。"
var main_truck_id: int = 0
var exit_building_id: int = 0
var exit_site_id: int = 0
var pursuit_speed: float = 0.035
var pursuit_start: float = 150.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_id: int = 1
var _jobs: Array = []
var _ai_clock: float = 0.0
var _logistics_clock: float = 0.0
var _spawn_clock: float = 0.0
var _food_clock: float = 0.0
var _notification_clock: float = 0.0
var _last_pursuit_warning: int = -1
var _decode_budget: int = 0

# Rebuilt indexes, not authoritative state. They must never enter save data.
var _nav_blocked: Dictionary = {}
var _nav_barriers: Dictionary = {}
var _occluder_tops: Dictionary = {}
var _occluder_ids: Dictionary = {}
var _nav_cache_time: float = -INF
var _nav_cache_count: int = -1
var _nav_cache_dirty: bool = true
var _nav_buildings_ref: Array = []
var _nav_terrain_ref: Array = []
var _nav_geometry_signature: int = -1
var _road_connections: Dictionary = {}
var _road_source_ref: Dictionary = {}
var _road_source_count: int = -1
var _spatial_buckets: Dictionary = {}
# Neighborhood snapshots are read-only and retain the bucket iteration order.
# Membership changes invalidate every affected snapshot; position dictionaries
# themselves stay live so body checks always see the latest coordinates.
var _spatial_neighborhoods: Dictionary = {}
var _spatial_valid: bool = false
var _movement_units: Array = []
var _walk_components: Dictionary = {}
# Filled only for the unit-update loop, in original units order. Targets stay
# live references so movement, deaths and nearest-target ties remain unchanged.
var _target_units_by_team: Dictionary = {}


func reset(mission_seed: int = 42, requested_mission_id: String = "canyon") -> bool:
	# Reject the request before touching RNG, clocks, metadata or live arrays.
	var definition: Dictionary = CampaignCatalog.mission(requested_mission_id)
	if definition.is_empty():
		return false
	var geometry: Dictionary = CampaignCatalog.terrain_for(definition)
	if geometry.is_empty():
		return false
	_apply_mission_metadata(definition)
	seed_value = mission_seed
	_rng.seed = mission_seed
	time = 0.0
	phase = "preparation"
	outcome = "playing"
	paused = false
	pursuit_x = _pacing("pursuit_x", -5.0)
	pursuit_eta = _pacing("pursuit_eta", 540.0)
	pursuit_speed = _pacing("pursuit_speed", 0.035)
	pursuit_start = _pacing("pursuit_start", 150.0)
	exit_progress = 0.0
	evacuated = 0
	main_truck_id = 0
	exit_building_id = 0
	exit_site_id = 0
	_next_id = 1
	_ai_clock = 0.0
	_logistics_clock = 0.0
	_spawn_clock = 0.0
	_food_clock = 0.0
	_notification_clock = 0.0
	_last_pursuit_warning = -1
	units.clear()
	buildings.clear()
	camps.clear()
	sites.clear()
	effects.clear()
	messages.clear()
	roads.clear()
	ramps.clear()
	_jobs.clear()
	_invalidate_navigation()
	_spatial_valid = false
	map_size = definition["map_size"]
	terrain = geometry["terrain"]
	ramps = geometry["ramps"]
	var camp_ids: Dictionary = {}
	for entry: Dictionary in definition["camps"]:
		var stock: Dictionary = entry["stock"]
		var camp: Dictionary = _make_camp(entry["pos"], entry["name"], float(stock.get("materials", 0.0)), float(stock.get("supplies", 0.0)), float(stock.get("fuel", 0.0)))
		for resource: String in ["salvage", "crude"]:
			camp[resource] = float(stock.get(resource, 0.0))
		camp["energy"] = float(entry["energy"])
		camp_ids[entry["key"]] = int(camp["id"])
	# Keep the original creation sequence: IDs, guard placement and RNG state are
	# part of existing Canyon saves and their deterministic continuation.
	for entry: Dictionary in definition["buildings"]:
		_add_building(entry["kind"], entry["pos"], int(camp_ids[entry["camp"]]), float(entry["progress"]))
	for entry: Dictionary in definition["roads"]:
		roads[entry["pos"]] = {"progress": 1.0, "camp_id": int(camp_ids[entry["camp"]])}
	for entry: Dictionary in definition["units"]:
		var unit: Dictionary = _add_unit(entry["kind"], "friendly", entry["pos"], int(camp_ids[entry["camp"]]), int(entry["squad"]))
		if bool(entry["main_truck"]):
			main_truck_id = int(unit["id"])
	var exit_position: Vector2 = Vector2.ZERO
	for entry: Dictionary in definition["sites"]:
		var site: Dictionary = _add_site(entry["kind"], entry["pos"], entry["name"], entry["stock"].duplicate(true))
		if entry["key"] == definition["exit"]["site"]:
			exit_site_id = int(site["id"])
			exit_position = entry["pos"]
	var exit_building: Dictionary = _add_building("exit", exit_position, -1, 0.0)
	exit_building["construction_started"] = false
	exit_building["required_power"] = float(definition["exit"]["required_power"])
	exit_building_id = int(exit_building["id"])
	for entry: Dictionary in definition["sites"]:
		_spawn_guards(entry["pos"], int(entry["guards"]), bool(entry["runner"]))
	chokes = []
	for entry: Dictionary in definition["chokes"]:
		chokes.append({"pos": entry["pos"], "name": entry["name"], "sealed": false, "pending": false, "building_id": 0})
	_update_power(0.0)
	for message: String in definition["messages"]:
		_message(message)
	return true


func _apply_mission_metadata(definition: Dictionary) -> void:
	_mission_data = definition.duplicate(true)
	mission_id = String(definition["id"])
	mission_name = String(definition["name"])
	objective = String(definition["objective"])


func _pacing(key: String, fallback: float) -> float:
	return float(_mission_data["pacing"].get(key, fallback))


func tick(delta: float) -> void:
	if paused or outcome != "playing" or not is_finite(delta) or delta <= 0.0:
		return
	var remaining: float = minf(delta, 120.0)
	while remaining > 0.00001 and outcome == "playing":
		var step: float = minf(0.1, remaining)
		_step(step)
		remaining -= step


func _step(delta: float) -> void:
	time += delta
	if time + EPSILON >= pursuit_start and phase == "preparation":
		phase = "advance"
		_message("后方主尸潮开始推进。留意地图西侧的红色前沿，准备建立前营。")
	if pursuit_x > _pacing("evacuation_x", 33.0) and phase != "evacuation":
		phase = "evacuation"
		_message("进入撤离阶段：将物资和能源向东转移，封关为车队争取时间。")
	for effect in effects:
		effect["ttl"] = float(effect.get("ttl", 0.0)) - delta
	effects = effects.filter(func(effect: Dictionary) -> bool: return float(effect.get("ttl", 0.0)) > 0.0)
	_update_power(delta)
	_update_production(delta)
	_update_training(delta)
	_update_capture(delta)
	_update_jobs(delta)
	_update_logistics(delta)
	_update_evacuations(delta)
	_update_units(delta)
	_update_towers(delta)
	_update_pursuit(delta)
	_update_exit(delta)
	_update_food(delta)
	_remove_dead()
	_update_camp_integrity()
	_check_outcome()


func _new_id() -> int:
	var result: int = _next_id
	_next_id += 1
	return result


func _make_camp(position: Vector2, camp_name: String, material_amount: float, supply_amount: float, fuel_amount: float) -> Dictionary:
	var camp: Dictionary = {
		"id": _new_id(), "name": camp_name, "pos": position, "state": "active",
		"materials": material_amount, "supplies": supply_amount, "fuel": fuel_amount,
		"salvage": 45.0, "crude": 0.0, "power": 0.0, "power_capacity": 0.0,
		"power_used": 0.0, "energy": 25.0, "priority": "production", "recipe": "supplies",
		"evac_target_id": 0, "pack_progress": 0.0, "evac_truck_id": 0, "last_shortage": -100.0,
		"recruit_queue": [], "recruit_status": "idle"
	}
	camps.append(camp)
	return camp


func _add_building(kind: String, position: Vector2, camp_id: int, progress: float) -> Dictionary:
	var maximum_hp: float = 180.0
	match kind:
		"command": maximum_hp = 500.0
		"camp": maximum_hp = 320.0
		"generator": maximum_hp = 220.0
		"workshop": maximum_hp = 280.0
		"tower": maximum_hp = 260.0
		"barracks": maximum_hp = 340.0
		"barricade": maximum_hp = 600.0
		"exit": maximum_hp = 900.0
	var building: Dictionary = {
		"id": _new_id(), "kind": kind, "pos": position, "hp": maximum_hp,
		"max_hp": maximum_hp, "camp_id": camp_id, "progress": progress,
		"powered": false, "cooldown": 0.0, "abandoned": false,
		"required_power": 3.0 if ["tower", "barracks"].has(kind) else (4.0 if kind == "workshop" else 0.0),
		"power_radius": 10.0 if kind == "generator" else 0.0, "range": 7.0 if kind == "tower" else 0.0
	}
	buildings.append(building)
	_nav_cache_dirty = true
	return building


func _add_unit(kind: String, team: String, position: Vector2, camp_id: int, squad: int, spawn_max_x: float = INF) -> Dictionary:
	var maximum_hp: float = 75.0
	var move_speed: float = 1.25
	var attack_range: float = 6.0
	var damage: float = 12.0
	var interval: float = 0.85
	match kind:
		"engineer":
			maximum_hp = 65.0
			move_speed = 1.15
			attack_range = 3.5
			damage = 7.0
			interval = 1.1
		"worker":
			maximum_hp = 45.0
			move_speed = 1.05
			attack_range = 0.0
			damage = 0.0
		"truck":
			maximum_hp = 380.0
			move_speed = 1.75
			attack_range = 0.0
			damage = 0.0
		"zombie":
			maximum_hp = 42.0
			move_speed = 0.62
			attack_range = 0.85
			damage = 6.0
			interval = 1.25
		"runner":
			maximum_hp = 30.0
			move_speed = 1.1
			attack_range = 0.8
			damage = 5.0
			interval = 1.0
		"brute":
			maximum_hp = 180.0
			move_speed = 0.43
			attack_range = 1.0
			damage = 15.0
			interval = 1.8
	position = _find_spawn_position(position, kind, team, spawn_max_x)
	var unit: Dictionary = {
		"id": _new_id(), "kind": kind, "team": team, "pos": position,
		"hp": maximum_hp, "max_hp": maximum_hp, "state": "idle" if team == "friendly" else "guard",
		"target": position, "camp_id": camp_id, "squad": squad, "speed": move_speed,
		"range": attack_range, "damage": damage, "attack_interval": interval, "cooldown": 0.0,
		"path": [], "path_index": 0, "repath": 0.0, "order": "idle", "attack_move": false,
		"manual": false, "job_id": 0, "cargo": {}, "haul_site": 0, "haul_stage": "",
		"guard_pos": position, "escort_id": 0, "pursuer": false, "evac_origin_id": 0,
		"evac_destination_id": 0, "capacity": 180.0 if kind == "truck" else 18.0
	}
	units.append(unit)
	_spatial_valid = false
	return unit


func _add_site(kind: String, position: Vector2, site_name: String, stock: Dictionary) -> Dictionary:
	var site: Dictionary = {"id": _new_id(), "kind": kind, "name": site_name, "pos": position, "captured": false, "progress": 0.0, "stock": stock, "camp_id": 0}
	sites.append(site)
	return site


func _spawn_guards(center: Vector2, amount: int, include_runner: bool) -> void:
	for index in range(amount):
		var kind: String = "runner" if include_runner and index == 0 else "zombie"
		if amount >= 6 and index == amount - 1:
			kind = "brute"
		var offset: Vector2 = Vector2(float(index % 3 - 1) * 1.6, float(index / 3) * 1.5 - 0.5)
		var tile: Vector2i = _nearest_tile(center + offset, "enemy")
		_add_unit(kind, "enemy", Vector2(tile), -1, 0)


func get_unit(unit_id: int) -> Dictionary:
	for unit in units:
		if int(unit["id"]) == unit_id:
			return unit
	return {}


func get_camp(camp_id: int) -> Dictionary:
	for camp in camps:
		if int(camp["id"]) == camp_id:
			return camp
	return {}


func _get_building(building_id: int) -> Dictionary:
	for building in buildings:
		if int(building["id"]) == building_id:
			return building
	return {}


func _get_site(site_id: int) -> Dictionary:
	for site in sites:
		if int(site["id"]) == site_id:
			return site
	return {}


func _get_job(job_id: int) -> Dictionary:
	for job in _jobs:
		if int(job["id"]) == job_id:
			return job
	return {}


func is_walkable(tile: Vector2i) -> bool:
	_ensure_navigation_index(true)
	return _terrain_walkable(tile) and not _tile_blocked(tile, "friendly")


func _terrain_walkable(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < map_size.x and tile.y < map_size.y and int(terrain[tile.y][tile.x]) >= 0


func _tile_blocked(tile: Vector2i, team: String) -> bool:
	_ensure_navigation_index()
	return _nav_barriers.has(tile) if team == "logistics" else _nav_blocked.has(tile)


func _invalidate_navigation() -> void:
	_nav_cache_dirty = true
	_nav_cache_time = -INF
	_nav_cache_count = -1
	_nav_blocked.clear()
	_nav_barriers.clear()
	_occluder_tops.clear()
	_occluder_ids.clear()
	_nav_geometry_signature = -1
	_road_connections.clear()
	_road_source_count = -1
	_walk_components.clear()


func _ensure_navigation_index(force: bool = false) -> void:
	var same_sources: bool = is_same(buildings, _nav_buildings_ref) and is_same(terrain, _nav_terrain_ref)
	if not force and not _nav_cache_dirty and _nav_cache_time == time and _nav_cache_count == buildings.size() and same_sources:
		return
	var geometry_signature: int = buildings.size()
	for building in buildings:
		geometry_signature = hash([geometry_signature, int(building["id"]), str(building["kind"]), building["pos"], float(building["hp"]) > 0.0, float(building.get("progress", 0.0)) >= 1.0, int(building.get("span", 0))])
	if not force and not _nav_cache_dirty and same_sources and geometry_signature == _nav_geometry_signature:
		_nav_cache_time = time
		return
	_nav_cache_time = time
	_nav_cache_count = buildings.size()
	_nav_cache_dirty = false
	_nav_buildings_ref = buildings
	_nav_terrain_ref = terrain
	_nav_geometry_signature = geometry_signature
	_road_connections.clear()
	_nav_blocked.clear()
	_nav_barriers.clear()
	_occluder_tops.clear()
	_occluder_ids.clear()
	for building in buildings:
		if float(building["hp"]) <= 0.0 or float(building.get("progress", 0.0)) < 1.0:
			continue
		var at: Vector2i = Vector2i(Vector2(building["pos"]).round())
		var kind: String = str(building["kind"])
		var base_height: float = float(terrain[at.y][at.x]) if _terrain_walkable(at) else 0.0
		var roof_height: float = 0.8 if kind == "barricade" else (0.9 if kind == "generator" else (1.5 if kind == "tower" else 1.2))
		if kind == "barricade":
			var span: int = int(building.get("span", 0))
			for offset in range(-span, span + 1):
				var tile: Vector2i = at + Vector2i(0, offset)
				_nav_blocked[tile] = int(building["id"])
				_nav_barriers[tile] = int(building["id"])
				_occluder_tops[tile] = base_height + roof_height
				_occluder_ids[tile] = int(building["id"])
		else:
			if kind != "exit":
				_nav_blocked[at] = int(building["id"])
			_occluder_tops[at] = base_height + roof_height
			_occluder_ids[at] = int(building["id"])
	_rebuild_walk_components()


func _rebuild_walk_components() -> void:
	_walk_components.clear()
	var component: int = 0
	for y in range(map_size.y):
		for x in range(map_size.x):
			var start: Vector2i = Vector2i(x, y)
			if not _terrain_walkable(start) or _nav_blocked.has(start) or _walk_components.has(start):
				continue
			component += 1
			var frontier: Array[Vector2i] = [start]
			_walk_components[start] = component
			var cursor: int = 0
			while cursor < frontier.size():
				var at: Vector2i = frontier[cursor]
				cursor += 1
				for direction in DIRECTIONS:
					var next: Vector2i = at + direction
					if _walk_components.has(next) or not _terrain_walkable(next) or _nav_blocked.has(next):
						continue
					if int(terrain[at.y][at.x]) != int(terrain[next.y][next.x]) and not (ramps.has(at) and ramps.has(next)):
						continue
					_walk_components[next] = component
					frontier.append(next)


func _can_step(from: Vector2i, to: Vector2i, team: String) -> bool:
	if not _terrain_walkable(to) or _tile_blocked(to, team):
		return false
	if not _terrain_walkable(from):
		return false
	if int(terrain[from.y][from.x]) != int(terrain[to.y][to.x]):
		return ramps.has(from) and ramps.has(to)
	return true


func _nearest_tile(position: Vector2, team: String = "friendly") -> Vector2i:
	var origin: Vector2i = Vector2i(position.round())
	if _terrain_walkable(origin) and not _tile_blocked(origin, team):
		return origin
	for radius in range(1, 10):
		var best: Vector2i = Vector2i(-1, -1)
		var best_distance: int = 1000000
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var test: Vector2i = origin + Vector2i(dx, dy)
				if _terrain_walkable(test) and not _tile_blocked(test, team):
					var distance: int = dx * dx + dy * dy
					if distance < best_distance:
						best = test
						best_distance = distance
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _find_path(origin: Vector2, destination: Vector2, team: String = "friendly") -> Array:
	var start: Vector2i = _nearest_tile(origin, team)
	var finish: Vector2i = _nearest_tile(destination, team)
	if start.x < 0 or finish.x < 0:
		return []
	if start == finish:
		return [Vector2(finish)]
	if team != "logistics" and int(_walk_components.get(start, -1)) != int(_walk_components.get(finish, -2)):
		return []
	var heuristic: int = absi(finish.x - start.x) + absi(finish.y - start.y)
	var frontier: Array = [{"tile": start, "g": 0, "h": heuristic, "order": 0}]
	var previous: Dictionary = {start: start}
	var costs: Dictionary = {start: 0}
	var closed: Dictionary = {}
	var sequence: int = 0
	while not frontier.is_empty():
		var entry: Dictionary = _path_heap_pop(frontier)
		var current: Vector2i = entry["tile"]
		if closed.has(current):
			continue
		closed[current] = true
		if current == finish:
			break
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if closed.has(next) or not _can_step(current, next, team):
				continue
			var next_cost: int = int(entry["g"]) + 1
			if costs.has(next) and int(costs[next]) <= next_cost:
				continue
			previous[next] = current
			costs[next] = next_cost
			sequence += 1
			var next_h: int = absi(finish.x - next.x) + absi(finish.y - next.y)
			_path_heap_push(frontier, {"tile": next, "g": next_cost, "h": next_h, "order": sequence})
	if not previous.has(finish):
		return []
	var reverse_path: Array = []
	var walk: Vector2i = finish
	while walk != start:
		reverse_path.append(Vector2(walk))
		walk = Vector2i(previous[walk])
	reverse_path.reverse()
	return reverse_path


func _path_heap_before(first: Dictionary, second: Dictionary) -> bool:
	var first_f: int = int(first["g"]) + int(first["h"])
	var second_f: int = int(second["g"]) + int(second["h"])
	if first_f != second_f:
		return first_f < second_f
	if int(first["h"]) != int(second["h"]):
		return int(first["h"]) < int(second["h"])
	return int(first["order"]) < int(second["order"])


func _path_heap_push(heap: Array, entry: Dictionary) -> void:
	heap.append(entry)
	var index: int = heap.size() - 1
	while index > 0:
		var parent: int = int((index - 1) / 2)
		if not _path_heap_before(heap[index], heap[parent]):
			break
		var temporary: Dictionary = heap[parent]
		heap[parent] = heap[index]
		heap[index] = temporary
		index = parent


func _path_heap_pop(heap: Array) -> Dictionary:
	var result: Dictionary = heap[0]
	var last: Dictionary = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = last
	var index: int = 0
	while true:
		var first_child: int = index * 2 + 1
		if first_child >= heap.size():
			break
		var best: int = first_child
		if first_child + 1 < heap.size() and _path_heap_before(heap[first_child + 1], heap[first_child]):
			best = first_child + 1
		if not _path_heap_before(heap[best], heap[index]):
			break
		var temporary: Dictionary = heap[index]
		heap[index] = heap[best]
		heap[best] = temporary
		index = best
	return result


func _unit_radius(unit: Dictionary) -> float:
	return UNIT_RADII.get(unit.get("kind", "rifle"), 0.28)


func _body_position_valid(position: Vector2, radius: float, team: String) -> bool:
	if position.x < radius or position.y < radius or position.x + radius >= float(map_size.x) or position.y + radius >= float(map_size.y):
		return false
	_ensure_navigation_index()
	var center: Vector2i = Vector2i(position.round())
	var blockers: Dictionary = _nav_barriers if team == "logistics" else _nav_blocked
	if not _terrain_walkable(center) or blockers.has(center):
		return false
	var fractional: Vector2 = (position - Vector2(center)).abs()
	if fractional.x + radius <= 0.5 + EPSILON and fractional.y + radius <= 0.5 + EPSILON:
		return true
	var first: Vector2i = Vector2i((position - Vector2(radius, radius)).round())
	var last: Vector2i = Vector2i((position + Vector2(radius, radius)).round())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var tile: Vector2i = Vector2i(x, y)
			if tile == center:
				continue
			var nearest: Vector2 = position.clamp(Vector2(tile) - Vector2(0.5, 0.5), Vector2(tile) + Vector2(0.5, 0.5))
			if position.distance_squared_to(nearest) >= radius * radius - EPSILON:
				continue
			if not _terrain_walkable(tile) or blockers.has(tile):
				return false
			if int(terrain[center.y][center.x]) != int(terrain[tile.y][tile.x]) and not (ramps.has(center) and ramps.has(tile)):
				return false
	return true


func _static_motion_clear(origin: Vector2, destination: Vector2, radius: float, team: String) -> bool:
	var length: float = origin.distance_to(destination)
	var samples: int = maxi(1, ceili(length / 0.2))
	var previous: Vector2i = Vector2i(origin.round())
	for index in range(1, samples + 1):
		var position: Vector2 = origin.lerp(destination, float(index) / float(samples))
		if not _body_position_valid(position, radius, team):
			return false
		var at: Vector2i = Vector2i(position.round())
		if at != previous:
			if at.x != previous.x and at.y != previous.y:
				var horizontal: Vector2i = Vector2i(at.x, previous.y)
				var vertical: Vector2i = Vector2i(previous.x, at.y)
				if not (_can_step(previous, horizontal, team) and _can_step(horizontal, at, team) and _can_step(previous, vertical, team) and _can_step(vertical, at, team)):
					return false
			elif not _can_step(previous, at, team):
				return false
		previous = at
	return true


func _find_spawn_position(requested: Vector2, kind: String, team: String, maximum_x: float = INF) -> Vector2:
	var radius: float = float(UNIT_RADII.get(kind, 0.28))
	var origin_tile: Vector2i = _nearest_tile(requested, team)
	var origin: Vector2 = Vector2(origin_tile)
	for ring in range(0, 9):
		var candidates: Array = []
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var candidate: Vector2 = origin + Vector2(dx, dy)
				if candidate.x > maximum_x + EPSILON or not _body_position_valid(candidate, radius, team):
					continue
				var clear: bool = true
				for other in units:
					if float(other["hp"]) <= 0.0 or str(other["state"]) == "evacuated":
						continue
					if candidate.distance_to(Vector2(other["pos"])) < radius + _unit_radius(other) + 0.02:
						clear = false
						break
				if clear:
					candidates.append(candidate)
		candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(requested) < b.distance_squared_to(requested))
		for candidate in candidates:
			if candidate == origin or not _find_path(origin, candidate, team).is_empty():
				return candidate
	return origin


func _rebuild_spatial_index() -> void:
	_spatial_buckets.clear()
	_spatial_neighborhoods.clear()
	_movement_units = units.duplicate()
	_movement_units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for unit in _movement_units:
		if float(unit["hp"]) <= 0.0 or str(unit["state"]) == "evacuated":
			continue
		var bucket: Vector2i = Vector2i(Vector2(unit["pos"]).floor())
		if not _spatial_buckets.has(bucket):
			_spatial_buckets[bucket] = []
		_spatial_buckets[bucket].append(unit)
	_spatial_valid = true


func _nearby_bodies(position: Vector2) -> Array:
	if not _spatial_valid:
		_rebuild_spatial_index()
	var bucket: Vector2i = Vector2i(position.floor())
	if _spatial_neighborhoods.has(bucket):
		return _spatial_neighborhoods[bucket]
	var result: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var key: Vector2i = bucket + Vector2i(dx, dy)
			if _spatial_buckets.has(key):
				result.append_array(_spatial_buckets[key])
	_spatial_neighborhoods[bucket] = result
	return result


func _set_unit_position(unit: Dictionary, position: Vector2) -> void:
	var previous_bucket: Vector2i = Vector2i(Vector2(unit["pos"]).floor())
	var next_bucket: Vector2i = Vector2i(position.floor())
	unit["pos"] = position
	if not _spatial_valid or previous_bucket == next_bucket:
		return
	if _spatial_buckets.has(previous_bucket):
		var previous: Array = _spatial_buckets[previous_bucket]
		for index in range(previous.size()):
			if int(previous[index]["id"]) == int(unit["id"]):
				previous.remove_at(index)
				break
	if not _spatial_buckets.has(next_bucket):
		_spatial_buckets[next_bucket] = []
	_spatial_buckets[next_bucket].append(unit)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var offset: Vector2i = Vector2i(dx, dy)
			_spatial_neighborhoods.erase(previous_bucket + offset)
			_spatial_neighborhoods.erase(next_bucket + offset)


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


func _recover_static_positions() -> void:
	# Legacy saves and completed construction may put a unit in a newly solid
	# footprint. Recover only through adjacent legal terrain, never across void.
	for unit in units:
		if float(unit["hp"]) <= 0.0 or str(unit["state"]) == "evacuated":
			continue
		var position: Vector2 = Vector2(unit["pos"])
		var radius: float = _unit_radius(unit)
		var team: String = str(unit["team"])
		if _body_position_valid(position, radius, team):
			continue
		var start: Vector2i = Vector2i(position.round())
		if not _terrain_walkable(start):
			continue
		var frontier: Array = [{"tile": start, "depth": 0}]
		var visited: Dictionary = {start: true}
		var cursor: int = 0
		while cursor < frontier.size():
			var entry: Dictionary = frontier[cursor]
			cursor += 1
			var at: Vector2i = entry["tile"]
			if at != start and _within_pursuit_front(unit, Vector2(at)) and _body_position_valid(Vector2(at), radius, team) and _body_is_clear(unit, Vector2(at)):
				_set_unit_position(unit, Vector2(at))
				break
			if int(entry["depth"]) >= 4:
				continue
			for direction in DIRECTIONS:
				var next: Vector2i = at + direction
				if not visited.has(next) and _can_step(at, next, team):
					visited[next] = true
					frontier.append({"tile": next, "depth": int(entry["depth"]) + 1})


func _movement_priority(unit: Dictionary) -> int:
	var order: String = str(unit.get("order", "idle"))
	if order == "evacuate_transport":
		return 5
	if order == "haul" or (str(unit["kind"]) == "truck" and order == "move"):
		return 4
	if order == "construct" or order == "evac_gather":
		return 3
	if ["move", "attack_move", "clear", "escort"].has(order):
		return 2
	return 0


func _separate_bodies() -> void:
	for pass_index in range(2):
		for unit in _movement_units:
			if float(unit["hp"]) <= 0.0 or str(unit["state"]) == "evacuated":
				continue
			var radius: float = _unit_radius(unit)
			var broadphase_radius: float = radius + MAX_UNIT_RADIUS
			var team: String = str(unit["team"])
			var unit_id: int = int(unit["id"])
			for other in _nearby_bodies(Vector2(unit["pos"])):
				if int(other["id"]) <= unit_id:
					continue
				var offset: Vector2 = Vector2(unit["pos"]) - Vector2(other["pos"])
				if absf(offset.x) > broadphase_radius or absf(offset.y) > broadphase_radius:
					continue
				if float(other["hp"]) <= 0.0 or str(other["state"]) == "evacuated":
					continue
				var other_radius: float = _unit_radius(other)
				var minimum: float = radius + other_radius
				var distance: float = offset.length()
				if distance >= minimum - 0.005:
					continue
				var direction: Vector2 = offset / distance if distance > 0.0001 else Vector2.RIGHT.rotated(float((unit_id + int(other["id"])) % 8) * PI / 4.0)
				var push: float = minf(0.15, minimum - distance + 0.015)
				var first_weight: float = 0.5
				if team == str(other["team"]):
					if _movement_priority(unit) > _movement_priority(other):
						first_weight = 0.15
					elif _movement_priority(unit) < _movement_priority(other):
						first_weight = 0.85
				var first: Vector2 = Vector2(unit["pos"]) + direction * push * first_weight
				var second: Vector2 = Vector2(other["pos"]) - direction * push * (1.0 - first_weight)
				if _within_pursuit_front(unit, first) and _static_motion_clear(Vector2(unit["pos"]), first, radius, team):
					_set_unit_position(unit, first)
				if _within_pursuit_front(other, second) and _static_motion_clear(Vector2(other["pos"]), second, other_radius, str(other["team"])):
					_set_unit_position(other, second)


func _set_target(unit: Dictionary, destination: Vector2) -> void:
	var team: String = str(unit["team"])
	if ["construct", "haul", "evacuate_transport", "evac_gather"].has(str(unit.get("order", ""))):
		unit.erase("formation_anchor")
		unit.erase("formation_slot")
	var tile: Vector2i = _nearest_tile(destination, team)
	var job: Dictionary = _get_job(int(unit.get("job_id", 0)))
	if not job.is_empty() and str(job["kind"]) != "road" and destination.distance_to(Vector2(job["pos"])) < 0.25:
		var work_position: Vector2 = Vector2(job["pos"])
		var best_distance: float = INF
		for direction in DIRECTIONS:
			var candidate: Vector2i = Vector2i(work_position.round()) + direction
			if not _can_step(Vector2i(work_position.round()), candidate, team) or not _body_position_valid(Vector2(candidate), _unit_radius(unit), team):
				continue
			var distance: float = Vector2(unit["pos"]).distance_squared_to(Vector2(candidate))
			if distance < best_distance:
				tile = candidate
				best_distance = distance
	unit["target"] = Vector2(tile)
	unit["path"] = _find_path(Vector2(unit["pos"]), Vector2(tile), team)
	if team == "enemy" and Array(unit["path"]).is_empty():
		var approach: Dictionary = _reachable_barrier_approach(unit, destination)
		if not approach.is_empty():
			unit["target"] = approach["target"]
			unit["path"] = approach["path"]
	if str(unit.get("order", "")) == "idle" and unit.has("formation_slot"):
		if Array(unit["path"]).is_empty():
			unit.erase("formation_anchor")
			unit.erase("formation_slot")
			unit["target"] = Vector2(unit["pos"])
		else:
			unit["formation_slot"] = Vector2(tile)
	unit["path_index"] = 0
	unit["repath"] = 1.0
	unit["nav_wait"] = 0.0


func _reachable_barrier_approach(unit: Dictionary, destination: Vector2) -> Dictionary:
	# An unreachable survivor/camp across a sealed bridge is still a pursuit
	# goal. Approach its reachable western face even outside close attack sense.
	# Existing reachable routes, melee range and pursuit-front limits stay intact.
	var origin: Vector2 = unit["pos"]
	var component: int = int(_walk_components.get(_nearest_tile(origin, "enemy"), -1))
	if component < 0: return {}
	var goal: Vector2i = Vector2i(-1, -1)
	var best: float = INF
	for choke: Dictionary in chokes:
		if not bool(choke.get("sealed", false)): continue
		var barrier: Dictionary = _get_building(int(choke.get("building_id", 0)))
		if barrier.is_empty() or float(barrier["hp"]) <= 0.0: continue
		var at: Vector2 = barrier["pos"]
		if origin.x >= at.x or destination.x <= at.x: continue
		var span: int = int(barrier.get("span", 0))
		for offset: int in range(-span, span + 1):
			var candidate: Vector2i = Vector2i(at.round()) + Vector2i(-1, offset)
			if int(_walk_components.get(candidate, -2)) != component or not _body_position_valid(Vector2(candidate), _unit_radius(unit), "enemy"): continue
			var distance: float = origin.distance_squared_to(Vector2(candidate))
			if distance < best:
				best = distance
				goal = candidate
	if goal.x < 0: return {}
	var path: Array = _find_path(origin, Vector2(goal), "enemy")
	return {"target": Vector2(goal), "path": path} if not path.is_empty() else {}


func command_move(ids: Array, target: Vector2, attack_move: bool = false) -> void:
	if outcome != "playing" or not target.is_finite():
		return
	_ensure_navigation_index(true)
	var ordered_ids: Array = ids.duplicate()
	ordered_ids.sort()
	var selected: Dictionary = {}
	var center: Vector2 = Vector2.ZERO
	var count: int = 0
	for unit_id in ordered_ids:
		var candidate: Dictionary = get_unit(int(unit_id))
		if not candidate.is_empty() and str(candidate["team"]) == "friendly" and str(candidate["state"]) != "evacuated":
			selected[int(unit_id)] = true
			center += Vector2(candidate["pos"])
			count += 1
	center /= float(maxi(1, count))
	var forward: Vector2i = Vector2i(1 if target.x >= center.x else -1, 0)
	if absf(target.y - center.y) > absf(target.x - center.x):
		forward = Vector2i(0, 1 if target.y >= center.y else -1)
	var sideways: Vector2i = Vector2i(-forward.y, forward.x)
	var reserved: Dictionary = {}
	var formation_index: int = 0
	for unit_id in ordered_ids:
		var unit: Dictionary = get_unit(int(unit_id))
		if unit.is_empty() or str(unit["team"]) != "friendly" or float(unit["hp"]) <= 0.0 or str(unit["state"]) == "evacuated":
			continue
		if str(unit.get("order", "")) == "evacuate_transport":
			_message("运输车正在撤营运输；完成这一趟后再调整路线。")
			continue
		_release_job(unit, false)
		unit["order"] = "attack_move" if attack_move else "move"
		unit["attack_move"] = attack_move
		unit["manual"] = true
		unit["state"] = "moving"
		unit["haul_site"] = 0
		unit["haul_stage"] = ""
		var columns: Array[int] = [0, -1, 1, -2, 2]
		var rows: Array[int] = [0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5]
		var width: int = 3 if count <= 9 else 5
		var row_index: int = mini(rows.size() - 1, int(formation_index / width))
		var offset: Vector2i = sideways * columns[formation_index % width] + forward * rows[row_index]
		var slot: Vector2i = _formation_destination(unit, Vector2i(target.round()) + offset, reserved, selected)
		reserved[slot] = true
		unit["formation_anchor"] = target
		unit["formation_slot"] = Vector2(slot)
		_set_target(unit, Vector2(slot))
		formation_index += 1


func _formation_destination(unit: Dictionary, desired: Vector2i, reserved: Dictionary, selected: Dictionary) -> Vector2i:
	var team: String = str(unit["team"])
	for ring in range(0, 9):
		var candidates: Array[Vector2i] = []
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var at: Vector2i = desired + Vector2i(dx, dy)
				if reserved.has(at) or not _body_position_valid(Vector2(at), _unit_radius(unit), team):
					continue
				var clear: bool = true
				for other in units:
					if selected.has(int(other["id"])) or float(other["hp"]) <= 0.0 or str(other["state"]) == "evacuated":
						continue
					if Vector2(at).distance_to(Vector2(other["pos"])) < _unit_radius(unit) + _unit_radius(other):
						clear = false
						break
				if clear:
					candidates.append(at)
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var a_distance: int = (a - desired).length_squared()
			var b_distance: int = (b - desired).length_squared()
			if a_distance != b_distance: return a_distance < b_distance
			return a.y < b.y if a.y != b.y else a.x < b.x)
		for at in candidates:
			if not _find_path(Vector2(unit["pos"]), Vector2(at), team).is_empty():
				return at
	return _nearest_tile(Vector2(unit["pos"]), team)


func command_task(ids: Array, task: String, target: Vector2) -> void:
	if not ["clear", "escort", "guard", "repair"].has(task):
		return
	command_move(ids, target, task == "clear")
	for unit_id in ids:
		var unit: Dictionary = get_unit(int(unit_id))
		if unit.is_empty() or str(unit["team"]) != "friendly" or str(unit.get("order", "")) == "evacuate_transport":
			continue
		unit["order"] = task
		unit["guard_pos"] = Vector2(unit["target"])
		if task == "escort":
			var escort: Dictionary = _closest_unit(target, "friendly", ["truck"], 12.0)
			unit["escort_id"] = int(escort.get("id", main_truck_id))
		if task == "repair" and not ["engineer", "worker"].has(str(unit["kind"])):
			unit["order"] = "guard"


func _closest_unit(position: Vector2, team: String, kinds: Array = [], maximum_distance: float = INF) -> Dictionary:
	var result: Dictionary = {}
	var distance: float = maximum_distance
	for unit in _target_units_by_team.get(team, units):
		if str(unit["team"]) != team or float(unit["hp"]) <= 0.0 or str(unit["state"]) == "evacuated":
			continue
		if not kinds.is_empty() and not kinds.has(str(unit["kind"])):
			continue
		var test: float = position.distance_to(Vector2(unit["pos"]))
		if test < distance:
			distance = test
			result = unit
	return result


func _nearest_camp(position: Vector2, require_active: bool = true) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for camp in camps:
		if str(camp["state"]) == "abandoned" or (require_active and str(camp["state"]) != "active"):
			continue
		var distance: float = position.distance_squared_to(Vector2(camp["pos"]))
		if distance < best_distance:
			best = camp
			best_distance = distance
	return best


func _can_pay(camp: Dictionary, costs: Dictionary) -> bool:
	if camp.is_empty():
		return false
	for key in costs:
		if float(camp.get(key, 0.0)) + 0.0001 < float(costs[key]):
			return false
	return true


func _pay(camp: Dictionary, costs: Dictionary) -> void:
	for key in costs:
		camp[key] = maxf(0.0, float(camp.get(key, 0.0)) - float(costs[key]))


func _deposit(camp: Dictionary, cargo: Dictionary) -> void:
	for key in RESOURCE_KEYS:
		camp[key] = float(camp.get(key, 0.0)) + float(cargo.get(key, 0.0))


func query_build(kind: String, tile: Vector2i, refresh_navigation: bool = true) -> Dictionary:
	return ConstructionRules.query_build(self, kind, tile, BUILD_COSTS, refresh_navigation)


func can_build(kind: String, tile: Vector2i) -> bool:
	return bool(query_build(kind, tile)["ok"])


func build(kind: String, tile: Vector2i) -> bool:
	return bool(try_build(kind, tile)["ok"])


func try_build(kind: String, tile: Vector2i) -> Dictionary:
	# Re-query at commit time: a displayed preview never reserves resources.
	var result: Dictionary = query_build(kind, tile)
	if not bool(result["ok"]):
		_message(str(result["message"]))
		return result
	var camp: Dictionary = get_camp(int(result["camp_id"]))
	var costs: Dictionary = result["costs"]
	_pay(camp, costs)
	if kind == "road":
		var new_tiles: Array = result["road_tiles"]
		for at in new_tiles:
			roads[at] = {"progress": 0.0, "camp_id": int(camp["id"])}
		var road_job: Dictionary = _add_job("road", Vector2(new_tiles[0]), int(camp["id"]), 0, costs)
		road_job["road_tiles"] = new_tiles.duplicate()
		road_job["road_cursor"] = 0
		result["message"] = "已规划 %d 格道路，工人和工程师将逐段施工。" % new_tiles.size()
	else:
		var building: Dictionary = _add_building(kind, result["position"], int(camp["id"]), 0.0)
		_add_job(kind, result["position"], int(camp["id"]), int(building["id"]), costs)
		result["message"] = "已设立工地：%s。工程师会领取材料并前往施工。" % _building_name(kind)
	_message(str(result["message"]))
	return result


func get_production_status(camp_id: int) -> Dictionary:
	return ConstructionRules.get_production_status(self, camp_id)


func _add_job(kind: String, position: Vector2, source_id: int, building_id: int, costs: Dictionary) -> Dictionary:
	var job: Dictionary = {"id": _new_id(), "kind": kind, "pos": position, "source_camp_id": source_id, "building_id": building_id, "costs": costs.duplicate(true), "progress": 0.0, "assigned": 0, "funded": true, "picked_up": false, "delivered": false, "done": false}
	_jobs.append(job)
	return job


func road_connected(origin: Vector2, destination: Vector2) -> bool:
	_ensure_navigation_index(true)
	_road_connections.clear()
	return _road_connected(origin, destination)


func _road_connected(origin: Vector2, destination: Vector2) -> bool:
	if not origin.is_finite() or not destination.is_finite():
		return false
	_ensure_navigation_index()
	if not is_same(roads, _road_source_ref) or roads.size() != _road_source_count:
		_road_connections.clear()
		_road_source_ref = roads
		_road_source_count = roads.size()
	var cache_key: Vector4 = Vector4(origin.x, origin.y, destination.x, destination.y)
	if _road_connections.has(cache_key):
		return bool(_road_connections[cache_key])
	var frontier: Array[Vector2i] = []
	var visited: Dictionary = {}
	for key in roads:
		var tile: Vector2i = Vector2i(key)
		var data: Variant = roads[key]
		if data is Dictionary and float(data.get("progress", 1.0)) < 1.0:
			continue
		if _road_endpoint_reachable(tile, origin):
			frontier.append(tile)
			visited[tile] = true
	var cursor: int = 0
	while cursor < frontier.size():
		var at: Vector2i = frontier[cursor]
		cursor += 1
		if _road_endpoint_reachable(at, destination):
			_road_connections[cache_key] = true
			return true
		for direction in DIRECTIONS:
			var next: Vector2i = at + direction
			if visited.has(next) or not roads.has(next):
				continue
			var data: Variant = roads[next]
			if data is Dictionary and float(data.get("progress", 1.0)) < 1.0:
				continue
			if not _can_step(at, next, "logistics"):
				continue
			visited[next] = true
			frontier.append(next)
	_road_connections[cache_key] = false
	return false


func _road_endpoint_reachable(road_tile: Vector2i, position: Vector2) -> bool:
	# A nearby road across a cliff or a sealed gate is not a connection.
	if position.distance_to(Vector2(road_tile)) > 2.5:
		return false
	var target: Vector2i = Vector2i(position.round())
	if not _terrain_walkable(target):
		return false
	var frontier: Array = [{"tile": road_tile, "depth": 0}]
	var visited: Dictionary = {road_tile: true}
	var cursor: int = 0
	while cursor < frontier.size():
		var entry: Dictionary = frontier[cursor]
		cursor += 1
		var at: Vector2i = entry["tile"]
		if at == target:
			return true
		if int(entry["depth"]) >= 3:
			continue
		for direction in DIRECTIONS:
			var next: Vector2i = at + direction
			if not visited.has(next) and _can_step(at, next, "logistics"):
				visited[next] = true
				frontier.append({"tile": next, "depth": int(entry["depth"]) + 1})
	return false


func _update_jobs(delta: float) -> void:
	for job in _jobs:
		if bool(job.get("done", false)):
			continue
		var camp: Dictionary = get_camp(int(job["source_camp_id"]))
		if camp.is_empty() or str(camp["state"]) != "active":
			continue
		if not bool(job.get("funded", false)):
			if not _can_pay(camp, Dictionary(job["costs"])):
				continue
			_pay(camp, Dictionary(job["costs"]))
			job["funded"] = true
		var builder: Dictionary = get_unit(int(job.get("assigned", 0)))
		if builder.is_empty() or float(builder["hp"]) <= 0.0:
			job["assigned"] = 0
			continue
		if not bool(job.get("picked_up", false)):
			if Vector2(builder["pos"]).distance_to(Vector2(camp["pos"])) <= 2.5:
				builder["cargo"] = Dictionary(job["costs"]).duplicate(true)
				job["picked_up"] = true
				builder["state"] = "delivering"
				_set_target(builder, Vector2(job["pos"]))
			continue
		if not bool(job.get("delivered", false)):
			if Vector2(builder["pos"]).distance_to(Vector2(job["pos"])) <= 1.25:
				job["delivered"] = true
				if str(job["kind"]) != "road":
					builder["cargo"] = {}
				builder["state"] = "building"
			continue
		if Vector2(builder["pos"]).distance_to(Vector2(job["pos"])) > 1.5:
			_set_target(builder, Vector2(job["pos"]))
			continue
		var kind: String = str(job["kind"])
		if kind == "exit":
			var exit_building: Dictionary = _get_building(int(job["building_id"]))
			if exit_building.is_empty() or not bool(exit_building.get("powered", false)):
				builder["state"] = "waiting_power"
				continue
		var rate: float = 1.2 if str(builder["kind"]) == "engineer" else 0.65
		job["progress"] = minf(1.0, float(job["progress"]) + delta * rate / float(BUILD_SECONDS[kind]))
		if float(job["progress"]) + EPSILON >= 1.0:
			job["progress"] = 1.0
		builder["state"] = "building"
		if kind == "road":
			var tile: Vector2i = Vector2i(Vector2(job["pos"]).round())
			if roads.has(tile):
				roads[tile]["progress"] = float(job["progress"])
		else:
			var building: Dictionary = _get_building(int(job["building_id"]))
			if building.is_empty() or float(building["hp"]) <= 0.0:
				job["done"] = true
				_release_job(builder, false)
				continue
			building["progress"] = float(job["progress"])
		if float(job["progress"]) >= 1.0:
			_complete_job(job, builder)
	# Assign by distance, one real builder and parcel per project.
	for builder in units:
		if str(builder["team"]) != "friendly" or not ["engineer", "worker"].has(str(builder["kind"])) or float(builder["hp"]) <= 0.0:
			continue
		if int(builder.get("job_id", 0)) != 0 or bool(builder.get("manual", false)) or str(builder.get("order", "idle")) != "idle" or not Dictionary(builder.get("cargo", {})).is_empty():
			continue
		var best: Dictionary = {}
		var best_distance: float = INF
		for job in _jobs:
			if bool(job.get("done", false)) or int(job.get("assigned", 0)) != 0 or not bool(job.get("funded", false)):
				continue
			var source: Dictionary = get_camp(int(job["source_camp_id"]))
			if source.is_empty() or str(source["state"]) != "active":
				continue
			var distance: float = Vector2(builder["pos"]).distance_squared_to(Vector2(job["pos"]))
			if str(job["kind"]) != "road":
				distance *= 0.75
			if distance < best_distance:
				best = job
				best_distance = distance
		if not best.is_empty():
			best["assigned"] = int(builder["id"])
			builder["job_id"] = int(best["id"])
			builder["order"] = "construct"
			builder["state"] = "collecting_materials"
			var source: Dictionary = get_camp(int(best["source_camp_id"]))
			_set_target(builder, Vector2(source["pos"]))


func _complete_job(job: Dictionary, builder: Dictionary) -> void:
	if str(job["kind"]) == "road":
		_road_connections.clear()
	else:
		_nav_cache_dirty = true
	# One road crew takes a physical bundle once, then lays the whole segment.
	# Returning to the warehouse for every single tile made long roads unusable.
	if str(job["kind"]) == "road" and job.has("road_tiles"):
		var road_tiles: Array = job["road_tiles"]
		var cursor: int = int(job.get("road_cursor", 0)) + 1
		var cargo: Dictionary = builder.get("cargo", {})
		cargo["materials"] = maxf(0.0, float(cargo.get("materials", 0.0)) - 2.0)
		builder["cargo"] = cargo
		job["costs"] = {"materials": float(road_tiles.size() - cursor) * 2.0}
		if cursor < road_tiles.size():
			job["road_cursor"] = cursor
			job["pos"] = Vector2(road_tiles[cursor])
			job["progress"] = 0.0
			job["delivered"] = false
			builder["state"] = "delivering"
			_set_target(builder, Vector2(job["pos"]))
			return
		builder["cargo"] = {}
	job["done"] = true
	builder["job_id"] = 0
	builder["order"] = "idle"
	builder["state"] = "idle"
	builder["manual"] = false
	var kind: String = str(job["kind"])
	if kind == "camp":
		var building: Dictionary = _get_building(int(job["building_id"]))
		var camp: Dictionary = _make_camp(Vector2(job["pos"]), "前进营地 %d" % camps.size(), 0.0, 0.0, 0.0)
		camp["salvage"] = 0.0
		building["camp_id"] = int(camp["id"])
		building["powered"] = true
		_message("前进营地建立。可撤收后方物资至此，再配置发电与工坊。")
	elif kind != "road":
		_message("%s施工完成。" % _building_name(kind))


func _release_job(unit: Dictionary, lost_cargo: bool) -> void:
	var job: Dictionary = _get_job(int(unit.get("job_id", 0)))
	if not job.is_empty() and not bool(job.get("done", false)):
		job["assigned"] = 0
		if bool(job.get("picked_up", false)) and not bool(job.get("delivered", false)):
			job["funded"] = false
			job["picked_up"] = false
			if lost_cargo:
				unit["cargo"] = {}
	unit["job_id"] = 0


func set_production(camp_id: int, recipe: String) -> void:
	var camp: Dictionary = get_camp(camp_id)
	if camp.is_empty() or not ["materials", "supplies", "fuel", "idle"].has(recipe):
		return
	camp["recipe"] = recipe
	_message("%s生产调整为：%s。" % [str(camp["name"]), {"materials": "建材（消耗废料）", "supplies": "口粮（消耗燃料）", "fuel": "燃料（消耗原油）", "idle": "暂停"}[recipe]])


func set_priority(camp_id: int, priority: String) -> void:
	var camp: Dictionary = get_camp(camp_id)
	if camp.is_empty() or not ["production", "defense", "evacuation"].has(priority):
		return
	camp["priority"] = priority
	_message("%s已调整供能优先级。" % str(camp["name"]))


func _update_power(delta: float) -> void:
	for building in buildings:
		building["powered"] = false
	for camp in camps:
		camp["power"] = 0.0
		camp["power_capacity"] = 0.0
		camp["power_used"] = 0.0
		if str(camp["state"]) == "abandoned":
			continue
		var generators: Array = []
		for building in buildings:
			if int(building["camp_id"]) != int(camp["id"]) or float(building["hp"]) <= 0.0:
				continue
			if ["command", "camp"].has(str(building["kind"])) and float(building["progress"]) >= 1.0:
				building["powered"] = true
			if str(building["kind"]) == "generator" and float(building["progress"]) >= 1.0 and float(camp["fuel"]) > 0.001 and _road_connected(Vector2(camp["pos"]), Vector2(building["pos"])):
				building["powered"] = true
				building["available_output"] = 12.0
				generators.append(building)
				camp["power_capacity"] = float(camp["power_capacity"]) + 12.0
				camp["fuel"] = maxf(0.0, float(camp["fuel"]) - delta * 0.025)
		var first: String = "tower" if str(camp["priority"]) == "defense" else "workshop"
		var kinds: Array = [first, "exit", "barracks", "workshop" if first == "tower" else "tower"]
		if str(camp["priority"]) == "evacuation":
			kinds = ["exit", "tower", "barracks", "workshop"]
		for kind in kinds:
			for consumer in buildings:
				if str(consumer["kind"]) != kind or int(consumer["camp_id"]) != int(camp["id"]) or float(consumer["hp"]) <= 0.0:
					continue
				if kind != "exit" and float(consumer["progress"]) < 1.0:
					continue
				if not _road_connected(Vector2(camp["pos"]), Vector2(consumer["pos"])):
					continue
				var demand: float = float(consumer.get("required_power", 0.0))
				for generator in generators:
					if Vector2(generator["pos"]).distance_to(Vector2(consumer["pos"])) <= float(generator.get("power_radius", 10.0)) and float(generator["available_output"]) >= demand:
						generator["available_output"] = float(generator["available_output"]) - demand
						consumer["powered"] = true
						camp["power_used"] = float(camp["power_used"]) + demand
						break
		camp["power"] = maxf(0.0, float(camp["power_capacity"]) - float(camp["power_used"]))
		camp["energy"] = clampf(float(camp.get("energy", 0.0)) + delta * (float(camp["power"]) * 0.25 - 0.03), 0.0, 100.0)


func _update_production(delta: float) -> void:
	for camp in camps:
		if str(camp["state"]) != "active":
			continue
		var working: int = 0
		for building in buildings:
			if int(building["camp_id"]) == int(camp["id"]) and str(building["kind"]) == "workshop" and bool(building["powered"]) and float(building["progress"]) >= 1.0:
				working += 1
		if working <= 0:
			continue
		var rate: float = float(working) * delta
		var recipe: String = str(camp.get("recipe", "idle"))
		match recipe:
			"materials":
				var amount: float = minf(float(camp.get("salvage", 0.0)), rate * 0.8)
				camp["salvage"] = float(camp.get("salvage", 0.0)) - amount
				camp["materials"] = float(camp["materials"]) + amount
			"fuel":
				var amount: float = minf(float(camp.get("crude", 0.0)), rate * 0.65)
				camp["crude"] = float(camp.get("crude", 0.0)) - amount
				camp["fuel"] = float(camp["fuel"]) + amount
			"supplies":
				var amount: float = minf(rate * 0.55, float(camp["fuel"]) / 0.08)
				camp["fuel"] = maxf(0.0, float(camp["fuel"]) - amount * 0.08)
				camp["supplies"] = float(camp["supplies"]) + amount


func query_recruit(camp_id: int, kind: String) -> Dictionary:
	return RecruitmentRules.query_recruit(self, camp_id, kind, RECRUIT_COSTS, RECRUIT_SECONDS, POPULATION_CAP, RECRUIT_QUEUE_CAP)


func recruit(camp_id: int, kind: String) -> bool:
	return bool(try_recruit(camp_id, kind)["ok"])


func try_recruit(camp_id: int, kind: String) -> Dictionary:
	# A preview reserves neither inventory nor population; validate live state.
	var result: Dictionary = query_recruit(camp_id, kind)
	if not bool(result["ok"]):
		_message(str(result["message"]))
		return result
	var camp: Dictionary = get_camp(camp_id)
	var queue: Array = camp.get("recruit_queue", [])
	var costs: Dictionary = Dictionary(result["costs"]).duplicate(true)
	_pay(camp, costs)
	queue.append({"kind": kind, "elapsed": 0.0, "progress": 0.0, "duration": float(RECRUIT_SECONDS[kind]), "costs": costs})
	camp["recruit_queue"] = queue
	camp["recruit_status"] = "training"
	result["message"] = "%s已安排训练：%s。" % [str(camp.get("name", "营地")), str({"rifle": "步枪兵", "engineer": "工程师", "worker": "工人", "truck": "补给卡车"}[kind])]
	_message(str(result["message"]))
	return result


func get_training_status(camp_id: int) -> Dictionary:
	return RecruitmentRules.get_training_status(self, camp_id)


func _training_power_available(camp: Dictionary, kind: String) -> bool:
	if float(camp.get("power_capacity", 0.0)) <= 0.0:
		return false
	var facility_kind: String = "barracks"
	if kind == "truck":
		facility_kind = "workshop"
	for building in buildings:
		if int(building["camp_id"]) != int(camp["id"]) or float(building["hp"]) <= 0.0 or float(building["progress"]) < 1.0:
			continue
		if kind == "worker" and ["camp", "command"].has(str(building["kind"])) and bool(building.get("powered", false)):
			return true
		if str(building["kind"]) == facility_kind and bool(building.get("powered", false)):
			return true
	return false


func _update_training(delta: float) -> void:
	for camp in camps:
		var queue: Array = camp.get("recruit_queue", [])
		if queue.is_empty():
			camp["recruit_status"] = "idle"
			continue
		if str(camp["state"]) != "active":
			camp["recruit_status"] = "paused"
			continue
		var entry: Dictionary = queue[0]
		var kind: String = str(entry["kind"])
		if not _training_power_available(camp, kind):
			camp["recruit_status"] = "waiting_power"
			continue
		camp["recruit_status"] = "training"
		entry["elapsed"] = float(entry.get("elapsed", 0.0)) + delta
		entry["progress"] = minf(1.0, float(entry["elapsed"]) / float(entry["duration"]))
		if float(entry["elapsed"]) + EPSILON < float(entry["duration"]):
			continue
		var squad: int = 0
		if ["rifle", "engineer"].has(kind):
			var soldiers: int = 0
			for existing in units:
				if str(existing["team"]) == "friendly" and ["rifle", "engineer"].has(str(existing["kind"])):
					soldiers += 1
			squad = mini(4, int(soldiers / 4) + 1)
		var spawn_tile: Vector2i = _nearest_tile(Vector2(camp["pos"]) + Vector2(2, 1), "friendly")
		var recruit_unit: Dictionary = _add_unit(kind, "friendly", Vector2(spawn_tile), int(camp["id"]), squad)
		if kind == "truck":
			recruit_unit["capacity"] = 100.0
		queue.pop_front()
		camp["recruit_queue"] = queue
		_message("%s完成一名%s训练。" % [str(camp.get("name", "营地")), str({"rifle": "步枪兵", "engineer": "工程师", "worker": "工人", "truck": "补给卡车"}[kind])])


func _update_capture(delta: float) -> void:
	for site in sites:
		if bool(site["captured"]):
			continue
		var position: Vector2 = Vector2(site["pos"])
		var enemy: Dictionary = _closest_unit(position, "enemy", [], 5.0)
		var captor: Dictionary = _closest_unit(position, "friendly", ["rifle", "engineer"], 2.8)
		if captor.is_empty() or not enemy.is_empty():
			site["progress"] = maxf(0.0, float(site["progress"]) - delta * 0.02)
			continue
		site["progress"] = minf(1.0, float(site["progress"]) + delta * 0.12)
		if float(site["progress"]) + EPSILON >= 1.0:
			site["progress"] = 1.0
		if float(site["progress"]) >= 1.0:
			site["captured"] = true
			site["camp_id"] = int(captor["camp_id"])
			_message("已清理 %s。铺路连通后，工人可取回储备。" % str(site["name"]))
			_add_effect("loot", position, position, 1.8)


func _update_logistics(delta: float) -> void:
	_logistics_clock += delta
	for unit in units:
		if str(unit["team"]) != "friendly" or float(unit["hp"]) <= 0.0 or str(unit["state"]) == "evacuated":
			continue
		var order: String = str(unit.get("order", "idle"))
		var cargo: Dictionary = unit.get("cargo", {})
		if order == "haul":
			var camp: Dictionary = get_camp(int(unit["camp_id"]))
			var site: Dictionary = _get_site(int(unit["haul_site"]))
			if camp.is_empty() or str(camp["state"]) != "active" or site.is_empty():
				unit["order"] = "idle"
				unit["haul_stage"] = ""
				continue
			if str(unit["haul_stage"]) == "to_site" and Vector2(unit["pos"]).distance_to(Vector2(site["pos"])) <= 1.4:
				var taken: Dictionary = {}
				var stock: Dictionary = site.get("stock", {})
				var capacity: float = float(unit.get("capacity", 18.0))
				for key in RESOURCE_KEYS:
					var amount: float = minf(float(stock.get(key, 0.0)), capacity)
					if amount > 0.0:
						taken[key] = amount
						stock[key] = float(stock.get(key, 0.0)) - amount
						capacity -= amount
				unit["cargo"] = taken
				unit["haul_stage"] = "to_camp"
				unit["state"] = "hauling"
				_set_target(unit, Vector2(camp["pos"]))
			elif str(unit["haul_stage"]) == "to_camp" and Vector2(unit["pos"]).distance_to(Vector2(camp["pos"])) <= 2.0:
				_deposit(camp, cargo)
				unit["cargo"] = {}
				unit["order"] = "idle"
				unit["state"] = "idle"
				unit["haul_stage"] = ""
		elif order == "idle" and not cargo.is_empty() and int(unit.get("job_id", 0)) == 0:
			var camp: Dictionary = _nearest_camp(Vector2(unit["pos"]), false)
			if not camp.is_empty():
				if Vector2(unit["pos"]).distance_to(Vector2(camp["pos"])) <= 2.0:
					_deposit(camp, cargo)
					unit["cargo"] = {}
				else:
					_set_target(unit, Vector2(camp["pos"]))
	if _logistics_clock + EPSILON < 1.0:
		return
	_logistics_clock = 0.0
	_clear_idle_depot_approaches()
	for worker in units:
		var can_haul: bool = str(worker["kind"]) == "worker" or (str(worker["kind"]) == "truck" and int(worker["id"]) != main_truck_id)
		if not can_haul or str(worker["team"]) != "friendly" or float(worker["hp"]) <= 0.0 or str(worker.get("order", "idle")) != "idle" or bool(worker.get("manual", false)) or not Dictionary(worker.get("cargo", {})).is_empty():
			continue
		var camp: Dictionary = get_camp(int(worker["camp_id"]))
		if camp.is_empty() or str(camp["state"]) != "active":
			continue
		var best: Dictionary = {}
		var score: float = INF
		for site in sites:
			if not bool(site["captured"]) or str(site["kind"]) == "exit" or Vector2(site["pos"]).x < pursuit_x + 1.0:
				continue
			var total: float = 0.0
			for key in RESOURCE_KEYS:
				total += float(Dictionary(site.get("stock", {})).get(key, 0.0))
			if total <= 0.01 or not _road_connected(Vector2(camp["pos"]), Vector2(site["pos"])):
				continue
			var test: float = Vector2(camp["pos"]).distance_to(Vector2(site["pos"]))
			if str(camp.get("recipe", "")) == "materials" and str(site["kind"]) == "quarry":
				test *= 0.6
			elif str(camp.get("recipe", "")) == "fuel" and str(site["kind"]) == "fuel":
				test *= 0.6
			if test < score:
				score = test
				best = site
		if not best.is_empty():
			worker["haul_site"] = int(best["id"])
			worker["haul_stage"] = "to_site"
			worker["order"] = "haul"
			worker["state"] = "collecting"
			_set_target(worker, Vector2(best["pos"]))


func _clear_idle_depot_approaches() -> void:
	# Delivered parcels leave idle units targeting the same depot tile. If a
	# working crew is blocked there, walk those arrivals to separate waiting
	# places instead of repeatedly nudging them back toward their old targets.
	# An assigned path survives save/load; its off-depot target prevents repeats.
	for camp: Dictionary in camps:
		if str(camp["state"]) != "active": continue
		var center: Vector2 = Vector2(camp["pos"])
		var dock: Vector2 = Vector2(_nearest_tile(center, "friendly"))
		var blocked: bool = false
		for mover: Dictionary in units:
			if str(mover["team"]) == "friendly" and float(mover["hp"]) > 0.0 and ["construct", "haul", "evacuate_transport"].has(str(mover.get("order", ""))) and float(mover.get("nav_wait", 0.0)) >= 0.5 and Vector2(mover["pos"]).distance_to(dock) < 3.0:
				blocked = true
				break
		if not blocked: continue
		var arrivals: Array = []
		var selected: Dictionary = {}
		for unit: Dictionary in units:
			if str(unit["team"]) != "friendly" or float(unit["hp"]) <= 0.0 or str(unit["state"]) == "evacuated" or int(unit["camp_id"]) != int(camp["id"]): continue
			if str(unit.get("order", "")) != "idle" or bool(unit.get("manual", false)) or int(unit.get("job_id", 0)) != 0 or not Dictionary(unit.get("cargo", {})).is_empty() or unit.has("formation_anchor"): continue
			if Vector2(unit["pos"]).distance_to(dock) >= 2.0 or Vector2(unit["target"]).distance_to(dock) > 0.75: continue
			arrivals.append(unit)
			selected[int(unit["id"])] = true
		arrivals.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return int(first["id"]) < int(second["id"]))
		var away: Vector2 = (center - dock).normalized()
		if away.length_squared() < 0.5: away = Vector2.DOWN
		var side: Vector2 = Vector2(-away.y, away.x)
		var reserved: Dictionary = {}
		for index: int in range(arrivals.size()):
			var unit: Dictionary = arrivals[index]
			var preferred: Vector2i = Vector2i((center + away * (3.0 + int(index / 3)) + side * (index % 3 - 1)).round())
			var slot: Vector2i = _formation_destination(unit, preferred, reserved, selected)
			if Vector2(slot).distance_to(dock) <= 2.0: continue
			reserved[slot] = true
			unit["order"] = "move"
			unit["state"] = "moving"
			_set_target(unit, Vector2(slot))


func evacuate_camp(camp_id: int) -> bool:
	var camp: Dictionary = get_camp(camp_id)
	if camp.is_empty() or outcome != "playing":
		return false
	if str(camp["state"]) == "packing":
		return _emergency_abandon(camp)
	if str(camp["state"]) != "active":
		return false
	var destination: Dictionary = {}
	var distance: float = INF
	for candidate in camps:
		if str(candidate["state"]) != "active" or Vector2(candidate["pos"]).x < Vector2(camp["pos"]).x + 5.0:
			continue
		var test: float = Vector2(candidate["pos"]).distance_to(Vector2(camp["pos"]))
		if test < distance and not _find_path(Vector2(camp["pos"]), Vector2(candidate["pos"])).is_empty():
			destination = candidate
			distance = test
	if destination.is_empty():
		_message("先在东侧建立接收物资的前进营地。")
		return false
	var truck: Dictionary = get_unit(main_truck_id)
	if truck.is_empty() or float(truck["hp"]) <= 0.0 or str(truck.get("order", "")) == "evacuate_transport":
		_message("指挥运输车尚未空闲，无法开始下一次撤营。")
		return false
	_release_job(truck, false)
	camp["state"] = "packing"
	camp["priority"] = "evacuation"
	camp["evac_target_id"] = int(destination["id"])
	camp["evac_truck_id"] = main_truck_id
	camp["pack_progress"] = 0.0
	for entry in camp.get("recruit_queue", []):
		var refund: Dictionary = {}
		for resource in Dictionary(entry.get("costs", {})):
			refund[resource] = float(entry["costs"][resource]) * 0.5
		_deposit(camp, refund)
	camp["recruit_queue"] = []
	camp["recruit_status"] = "idle"
	for job in _jobs:
		if int(job["source_camp_id"]) != camp_id or bool(job.get("done", false)):
			continue
		var builder: Dictionary = get_unit(int(job.get("assigned", 0)))
		if bool(job.get("funded", false)) and not bool(job.get("picked_up", false)):
			_deposit(camp, Dictionary(job["costs"]))
		if not builder.is_empty():
			builder["job_id"] = 0
			builder["order"] = "idle"
			builder["state"] = "idle"
		job["done"] = true
		if str(job["kind"]) == "road":
			for road_tile in job.get("road_tiles", [Vector2i(Vector2(job["pos"]).round())]):
				var road_data: Variant = roads.get(road_tile, {})
				if road_data is Dictionary and float(road_data.get("progress", 0.0)) < 1.0:
					roads.erase(road_tile)
		else:
			var unfinished: Dictionary = _get_building(int(job["building_id"]))
			if not unfinished.is_empty():
				unfinished["hp"] = 0.0
	truck["order"] = "evacuate_transport"
	truck["evac_origin_id"] = camp_id
	truck["evac_destination_id"] = int(destination["id"])
	truck["haul_stage"] = "returning"
	truck["manual"] = false
	_set_target(truck, Vector2(camp["pos"]))
	for unit in units:
		if str(unit["team"]) == "friendly" and int(unit["camp_id"]) == camp_id and ["worker", "engineer"].has(str(unit["kind"])):
			_release_job(unit, false)
			unit["manual"] = false
			unit["order"] = "evac_gather"
			unit["haul_stage"] = ""
			_set_target(unit, Vector2(camp["pos"]))
	_message("%s开始打包。运输车将分批运送物资，最后一批离开后全营东撤。" % str(camp["name"]))
	return true


func _emergency_abandon(camp: Dictionary) -> bool:
	var destination: Dictionary = get_camp(int(camp.get("evac_target_id", 0)))
	var truck: Dictionary = get_unit(int(camp.get("evac_truck_id", 0)))
	if destination.is_empty() or truck.is_empty():
		return false
	var left: float = _camp_stock(camp)
	_abandon_camp(camp, destination)
	truck["haul_stage"] = "outbound"
	truck["state"] = "evacuating"
	_set_target(truck, Vector2(destination["pos"]))
	_message("紧急弃营：约 %d 单位未装车物资留在原地。人员立即向前营撤退，车上货物继续运输。" % int(left))
	return true


func _update_evacuations(delta: float) -> void:
	for camp in camps:
		if str(camp["state"]) != "packing":
			continue
		_ensure_evacuation_staging(camp)
		var destination: Dictionary = get_camp(int(camp.get("evac_target_id", 0)))
		var truck: Dictionary = get_unit(int(camp.get("evac_truck_id", 0)))
		if destination.is_empty() or truck.is_empty() or float(truck["hp"]) <= 0.0:
			continue
		var stage: String = str(truck.get("haul_stage", "returning"))
		if stage == "returning" and Vector2(truck["pos"]).distance_to(Vector2(camp["pos"])) <= 2.0:
			camp["pack_progress"] = float(camp.get("pack_progress", 0.0)) + delta
			truck["state"] = "packing"
			if float(camp["pack_progress"]) < 6.0:
				continue
			camp["pack_progress"] = 0.0
			_load_evacuation_cargo(camp, destination, truck)
			truck["haul_stage"] = "outbound"
			truck["state"] = "evacuating"
			_set_target(truck, Vector2(destination["pos"]))
			if _camp_stock(camp) < 0.5:
				_abandon_camp(camp, destination)
		elif stage == "outbound" and Vector2(truck["pos"]).distance_to(Vector2(destination["pos"])) <= 2.0:
			_deposit(destination, Dictionary(truck.get("cargo", {})))
			truck["cargo"] = {}
			if str(camp["state"]) == "packing":
				truck["haul_stage"] = "returning"
				_set_target(truck, Vector2(camp["pos"]))
	# Last delivery is processed even after its origin becomes abandoned.
	for truck in units:
		if str(truck.get("order", "")) != "evacuate_transport" or str(truck.get("haul_stage", "")) != "outbound":
			continue
		var origin: Dictionary = get_camp(int(truck.get("evac_origin_id", 0)))
		var destination: Dictionary = get_camp(int(truck.get("evac_destination_id", 0)))
		if origin.is_empty() or destination.is_empty() or str(origin["state"]) != "abandoned":
			continue
		if Vector2(truck["pos"]).distance_to(Vector2(destination["pos"])) <= 2.0:
			_deposit(destination, Dictionary(truck.get("cargo", {})))
			truck["cargo"] = {}
			truck["camp_id"] = int(destination["id"])
			truck["order"] = "idle"
			truck["state"] = "idle"
			truck["haul_stage"] = ""
			_message("最后一批撤营物资已送达 %s。" % str(destination["name"]))


func _ensure_evacuation_staging(camp: Dictionary) -> void:
	if int(camp.get("evac_gather_version", 0)) == 1:
		return
	# Workers wait beside the depot, away from its vehicle approach. Stopping
	# everyone at the first point inside a camp radius can seal the loading lane.
	# The version is saved so a resumed run keeps its exact assigned paths;
	# older packing saves receive this layout once on their next simulation tick.
	var center: Vector2 = Vector2(camp["pos"])
	var dock: Vector2 = Vector2(_nearest_tile(center, "friendly"))
	var away: Vector2 = (center - dock).normalized()
	if away.length_squared() < 0.5: away = Vector2.DOWN
	var side: Vector2 = Vector2(-away.y, away.x)
	var gathering: Array = []
	var selected: Dictionary = {}
	for unit: Dictionary in units:
		if str(unit["team"]) == "friendly" and float(unit["hp"]) > 0.0 and int(unit["camp_id"]) == int(camp["id"]) and str(unit.get("order", "")) == "evac_gather":
			gathering.append(unit)
			selected[int(unit["id"])] = true
	gathering.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return int(first["id"]) < int(second["id"]))
	var reserved: Dictionary = {}
	var index: int = 0
	for unit: Dictionary in gathering:
		var column: int = index % 3 - 1
		var row: int = int(index / 3)
		var preferred: Vector2i = Vector2i((center + away * (3.0 + row) + side * column).round())
		var slot: Vector2i = _formation_destination(unit, preferred, reserved, selected)
		reserved[slot] = true
		_set_target(unit, Vector2(slot))
		unit["state"] = "moving"
		index += 1
	camp["evac_gather_version"] = 1


func _load_evacuation_cargo(origin: Dictionary, destination: Dictionary, truck: Dictionary) -> void:
	# Default macro policy: the first convoy must establish a viable camp, not
	# fill every truck with stone while leaving all food and generator fuel behind.
	# Nothing is granted: the source inventory and physical vehicle capacity pay
	# for every parcel. A short supply still dispatches its available partial load.
	var cargo: Dictionary = truck.get("cargo", {})
	var capacity: float = maxf(0.0, float(truck.get("capacity", 180.0)) - _cargo_weight(cargo))
	for resource in ["fuel", "supplies"]:
		var needed: float = maxf(0.0, float(EVAC_RESERVES[resource]) - float(destination.get(resource, 0.0)) - float(cargo.get(resource, 0.0)))
		var amount: float = minf(capacity, minf(needed, float(origin.get(resource, 0.0))))
		if amount > 0.0:
			cargo[resource] = float(cargo.get(resource, 0.0)) + amount
			origin[resource] = float(origin.get(resource, 0.0)) - amount
			capacity -= amount
	for resource in ["materials", "salvage", "crude", "supplies", "fuel"]:
		var amount: float = minf(float(origin.get(resource, 0.0)), capacity)
		if amount > 0.0:
			cargo[resource] = float(cargo.get(resource, 0.0)) + amount
			origin[resource] = float(origin.get(resource, 0.0)) - amount
			capacity -= amount
	truck["cargo"] = cargo


func _camp_stock(camp: Dictionary) -> float:
	var total: float = 0.0
	for key in RESOURCE_KEYS:
		total += float(camp.get(key, 0.0))
	return total


func _cargo_weight(cargo: Dictionary) -> float:
	var total: float = 0.0
	for key in RESOURCE_KEYS:
		total += float(cargo.get(key, 0.0))
	return total


func _abandon_camp(camp: Dictionary, destination: Dictionary) -> void:
	camp["state"] = "abandoned"
	camp["recruit_queue"] = []
	camp["recruit_status"] = "idle"
	for job in _jobs:
		if int(job["source_camp_id"]) == int(camp["id"]) and not bool(job.get("done", false)):
			job["done"] = true
			var builder: Dictionary = get_unit(int(job.get("assigned", 0)))
			if not builder.is_empty():
				builder["job_id"] = 0
	for building in buildings:
		if int(building["camp_id"]) == int(camp["id"]):
			building["abandoned"] = true
	var relocating: Array = []
	for unit in units:
		if str(unit["team"]) != "friendly" or int(unit["camp_id"]) != int(camp["id"]) or str(unit["kind"]) == "truck":
			continue
		unit["camp_id"] = int(destination["id"])
		relocating.append(int(unit["id"]))
	command_move(relocating, Vector2(destination["pos"]) + Vector2(0, 1))
	for identifier in relocating:
		get_unit(int(identifier))["manual"] = false
	_message("%s已撤收，留下的设施可为车队拖延追兵。确认所有人过关后可封关。" % str(camp["name"]))


func seal_choke(index: int) -> bool:
	if outcome != "playing" or index < 0 or index >= chokes.size():
		return false
	var choke: Dictionary = chokes[index]
	if bool(choke.get("sealed", false)):
		return false
	var position: Vector2 = Vector2(choke["pos"])
	var behind: int = 0
	for unit in units:
		if str(unit["team"]) == "friendly" and float(unit["hp"]) > 0.0 and str(unit["state"]) != "evacuated" and Vector2(unit["pos"]).x < position.x + 0.8:
			behind += 1
	if behind > 0:
		choke["pending"] = true
		_message("暂不能封关：仍有 %d 个友方单位未到关口东侧。" % behind)
		return false
	var camp: Dictionary = _nearest_camp(position)
	if camp.is_empty() or not _can_pay(camp, {"materials": 25.0}):
		_message("封关需要东侧营地提供 25 建材。")
		return false
	_pay(camp, {"materials": 25.0})
	var barrier: Dictionary = _add_building("barricade", position, int(camp["id"]), 1.0)
	barrier["span"] = 1
	barrier["hp"] = 6000.0
	barrier["max_hp"] = 6000.0
	barrier["choke_index"] = index
	choke["sealed"] = true
	choke["pending"] = false
	choke["building_id"] = int(barrier["id"])
	choke["delay_remaining"] = 220.0
	for unit in units:
		unit["repath"] = 0.0
	_message("%s已封锁。障碍会被尸潮逐步摧毁，请利用窗口继续东撤。" % str(choke["name"]))
	return true


func get_attack_range(attacker: Dictionary) -> float:
	var result: float = float(attacker.get("range", 7.0 if str(attacker.get("kind", "")) == "tower" else 0.0))
	var at: Vector2i = Vector2i(Vector2(attacker.get("pos", Vector2.ZERO)).round())
	if result > 2.0 and _terrain_walkable(at) and int(terrain[at.y][at.x]) == 1:
		result += HIGH_GROUND_RANGE_BONUS
	return result


func has_line_of_sight(origin: Vector2, destination: Vector2, shooter_kind: String = "rifle") -> bool:
	# Public inspection also sees direct state edits made by scenarios/test tools.
	_ensure_navigation_index(true)
	return _line_of_sight(origin, destination, shooter_kind)


func _line_of_sight(origin: Vector2, destination: Vector2, shooter_kind: String) -> bool:
	if not origin.is_finite() or not destination.is_finite():
		return false
	_ensure_navigation_index()
	var start: Vector2i = Vector2i(origin.round())
	var finish: Vector2i = Vector2i(destination.round())
	if not _terrain_walkable(start) or not _terrain_walkable(finish):
		return false
	var start_height: float = float(terrain[start.y][start.x]) + (1.8 if shooter_kind == "tower" else 0.65)
	var finish_height: float = float(terrain[finish.y][finish.x]) + 0.65
	var start_building: int = int(_occluder_ids.get(start, 0))
	var finish_building: int = int(_occluder_ids.get(finish, 0))
	var direction: Vector2 = destination - origin
	if direction.length_squared() < 0.000001:
		return true
	var step_x: int = 1 if direction.x > 0.0 else -1
	var step_y: int = 1 if direction.y > 0.0 else -1
	var delta_x: float = absf(1.0 / direction.x) if absf(direction.x) > EPSILON else INF
	var delta_y: float = absf(1.0 / direction.y) if absf(direction.y) > EPSILON else INF
	var boundary_x: float = float(start.x) + (0.5 if step_x > 0 else -0.5)
	var boundary_y: float = float(start.y) + (0.5 if step_y > 0 else -0.5)
	var next_x: float = (boundary_x - origin.x) / direction.x if absf(direction.x) > EPSILON else INF
	var next_y: float = (boundary_y - origin.y) / direction.y if absf(direction.y) > EPSILON else INF
	var at: Vector2i = start
	var entered: float = 0.0
	for _index in range(160):
		var leaving: float = minf(1.0, minf(next_x, next_y))
		var ray_minimum: float = minf(lerpf(start_height, finish_height, entered), lerpf(start_height, finish_height, leaving))
		if _ray_cell_blocks(at, ray_minimum, start_building, finish_building):
			return false
		if at == finish or leaving >= 1.0 - EPSILON:
			return true
		if absf(next_x - next_y) <= EPSILON:
			# Supercover corner: neither a roof nor a cliff corner is transparent.
			var corner_height: float = lerpf(start_height, finish_height, leaving)
			if _ray_cell_blocks(at + Vector2i(step_x, 0), corner_height, start_building, finish_building) or _ray_cell_blocks(at + Vector2i(0, step_y), corner_height, start_building, finish_building):
				return false
			at += Vector2i(step_x, step_y)
			next_x += delta_x
			next_y += delta_y
		elif next_x < next_y:
			at.x += step_x
			next_x += delta_x
		else:
			at.y += step_y
			next_y += delta_y
		entered = leaving
	return false


func _ray_cell_blocks(tile: Vector2i, ray_height: float, start_building: int, finish_building: int) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= map_size.x or tile.y >= map_size.y:
		return true
	var floor_height: int = int(terrain[tile.y][tile.x])
	# -1 is an open canyon/void. It prevents walking, not shooting across it.
	if floor_height >= 0 and float(floor_height) + EPSILON >= ray_height:
		return true
	var building_id: int = int(_occluder_ids.get(tile, 0))
	if building_id != 0 and building_id != start_building and building_id != finish_building:
		return float(_occluder_tops.get(tile, 0.0)) + EPSILON >= ray_height
	return false


func _closest_visible_target(attacker: Dictionary, team: String) -> Dictionary:
	var position: Vector2 = Vector2(attacker["pos"])
	var maximum: float = get_attack_range(attacker)
	var best: Dictionary = {}
	for target in _target_units_by_team.get(team, units):
		if str(target["team"]) != team or float(target["hp"]) <= 0.0 or str(target["state"]) == "evacuated":
			continue
		var distance: float = position.distance_to(Vector2(target["pos"]))
		if distance < maximum and _line_of_sight(position, Vector2(target["pos"]), str(attacker["kind"])):
			best = target
			maximum = distance
	return best


func _melee_attack_possible(attacker: Dictionary, target: Dictionary) -> bool:
	var origin: Vector2 = Vector2(attacker["pos"])
	var destination: Vector2 = Vector2(target["pos"])
	if not target.has("team"):
		var half_width: float = 0.5
		var half_height: float = float(target.get("span", 0)) + 0.5
		destination = origin.clamp(Vector2(target["pos"]) - Vector2(half_width, half_height), Vector2(target["pos"]) + Vector2(half_width, half_height))
	if origin.distance_to(destination) > float(attacker.get("range", 0.85)) + EPSILON:
		return false
	var previous: Vector2i = Vector2i(origin.round())
	var samples: int = maxi(1, ceili(origin.distance_to(destination) / 0.15))
	for index in range(samples + 1):
		var at: Vector2i = Vector2i(origin.lerp(destination, float(index) / float(samples)).round())
		if not _terrain_walkable(at) or not _terrain_walkable(previous):
			return false
		if int(terrain[previous.y][previous.x]) != int(terrain[at.y][at.x]) and not (ramps.has(previous) and ramps.has(at)):
			return false
		if at.x != previous.x and at.y != previous.y:
			var side_a: Vector2i = Vector2i(at.x, previous.y)
			var side_b: Vector2i = Vector2i(previous.x, at.y)
			if not _terrain_walkable(side_a) or not _terrain_walkable(side_b):
				return false
		previous = at
	return true


func _update_units(delta: float) -> void:
	_ensure_navigation_index()
	_spatial_valid = false
	_recover_static_positions()
	_rebuild_spatial_index()
	_separate_bodies()
	_ai_clock += delta
	var rethink: bool = _ai_clock + EPSILON >= 0.4
	if rethink:
		_ai_clock = 0.0
	var barrier_attackers: Dictionary = {}
	for target in units:
		var team: String = str(target["team"])
		if not _target_units_by_team.has(team):
			_target_units_by_team[team] = []
		_target_units_by_team[team].append(target)
	for unit in _movement_units:
		if float(unit["hp"]) <= 0.0 or str(unit["state"]) == "evacuated":
			continue
		unit["cooldown"] = maxf(0.0, float(unit.get("cooldown", 0.0)) - delta)
		unit["repath"] = maxf(0.0, float(unit.get("repath", 0.0)) - delta)
		if str(unit["team"]) == "enemy":
			_update_enemy(unit, delta, rethink, barrier_attackers)
			continue
		var position: Vector2 = Vector2(unit["pos"])
		var enemy: Dictionary = _closest_visible_target(unit, "enemy") if float(unit.get("range", 0.0)) > 0.0 else {}
		if not enemy.is_empty() and float(unit.get("damage", 0.0)) > 0.0:
			_attack(unit, enemy)
			if ["clear", "attack_move", "guard", "idle"].has(str(unit.get("order", "idle"))):
				unit["state"] = "fighting"
				continue
		if str(unit.get("order", "")) == "escort":
			var escort: Dictionary = get_unit(int(unit.get("escort_id", main_truck_id)))
			if not escort.is_empty() and position.distance_to(Vector2(escort["pos"])) > 2.5 and rethink:
				_set_target(unit, Vector2(escort["pos"]) + Vector2(-1, 1))
		if str(unit.get("order", "")) == "repair":
			_repair_nearby(unit, delta)
		if str(unit.get("order", "")) == "evac_gather":
			if _at_target(unit):
				unit["path"] = []
				unit["path_index"] = 0
				unit["state"] = "packing"
				continue
			if rethink and int(unit.get("path_index", 0)) >= Array(unit.get("path", [])).size():
				_set_target(unit, Vector2(unit["target"]))
		var path: Array = unit.get("path", [])
		if str(unit.get("order", "idle")) == "idle" and unit.has("formation_slot") and int(unit.get("path_index", 0)) >= path.size() and position.distance_to(Vector2(unit["formation_slot"])) > 0.35:
			_set_target(unit, Vector2(unit["formation_slot"]))
		_move_unit(unit, delta)
		if _at_target(unit):
			var order: String = str(unit.get("order", "idle"))
			if ["move", "attack_move", "clear"].has(order):
				unit["order"] = "idle"
				unit["manual"] = false
				unit["state"] = "idle"
			elif order == "guard":
				unit["state"] = "guarding"
			elif order == "evac_gather":
				unit["state"] = "packing"
	_separate_bodies()
	_target_units_by_team.clear()


func _update_enemy(unit: Dictionary, delta: float, rethink: bool, barrier_attackers: Dictionary) -> void:
	var position: Vector2 = Vector2(unit["pos"])
	var victim: Dictionary = _closest_unit(position, "friendly", [], 8.0 if not bool(unit.get("pursuer", false)) else 14.0)
	# Seeing survivors across a sealed bridge must not prevent the horde from
	# attacking that bridge. Otherwise it stared at an unreachable target.
	var barrier: Dictionary = _blocking_barrier_ahead(position, Vector2(victim["pos"]) if not victim.is_empty() else Vector2(_mission_data["guide"]["landmarks"]["exit"]) + Vector2(6, 1))
	if not barrier.is_empty():
		if _melee_attack_possible(unit, barrier):
			var barrier_id: int = int(barrier["id"])
			var count: int = int(barrier_attackers.get(barrier_id, 0))
			if count < 4:
				barrier_attackers[barrier_id] = count + 1
				_attack(unit, barrier)
			unit["state"] = "sieging"
			return
		if rethink and float(unit["repath"]) <= EPSILON:
			_set_target(unit, Vector2(barrier["pos"]))
		_move_unit(unit, delta)
		return
	if not victim.is_empty():
		var distance: float = position.distance_to(Vector2(victim["pos"]))
		var can_attack: bool = distance <= get_attack_range(unit)
		if float(unit.get("range", 0.0)) > 2.0:
			can_attack = can_attack and _line_of_sight(position, Vector2(victim["pos"]), str(unit["kind"]))
		else:
			can_attack = can_attack and _melee_attack_possible(unit, victim)
		if can_attack:
			_attack(unit, victim)
			unit["state"] = "fighting"
			return
		if rethink and float(unit["repath"]) <= 0.0:
			_set_target(unit, Vector2(victim["pos"]))
			unit["state"] = "chasing"
	else:
		var target_building: Dictionary = _closest_enemy_building(position, 5.0)
		if not target_building.is_empty():
			var distance: float = position.distance_to(Vector2(target_building["pos"]))
			var range_bonus: float = float(target_building.get("span", 0))
			if distance <= float(unit["range"]) + 0.8 + range_bonus and _melee_attack_possible(unit, target_building):
				var building_id: int = int(target_building["id"])
				var count: int = int(barrier_attackers.get(building_id, 0))
				if str(target_building["kind"]) != "barricade" or count < 4:
					barrier_attackers[building_id] = count + 1
					_attack(unit, target_building)
				unit["state"] = "sieging"
				return
			if rethink and float(unit["repath"]) <= 0.0:
				_set_target(unit, Vector2(target_building["pos"]))
		elif bool(unit.get("pursuer", false)):
			if rethink and float(unit["repath"]) <= 0.0:
				var destination: Vector2 = Vector2(_mission_data["guide"]["landmarks"]["exit"]) + Vector2(1, 1)
				var active_camp: Dictionary = _nearest_camp(position, false)
				if not active_camp.is_empty():
					destination = Vector2(active_camp["pos"])
				_set_target(unit, destination)
		else:
			unit["state"] = "guard"
			return
	_move_unit(unit, delta)


func _blocking_barrier_ahead(position: Vector2, target: Vector2) -> Dictionary:
	for choke in chokes:
		if not bool(choke.get("sealed", false)):
			continue
		var barrier: Dictionary = _get_building(int(choke.get("building_id", 0)))
		if barrier.is_empty() or float(barrier["hp"]) <= 0.0:
			continue
		var at: Vector2 = Vector2(barrier["pos"])
		if position.x < at.x and target.x > at.x and position.distance_to(at) < 8.0:
			return barrier
	return {}


func _closest_enemy_building(position: Vector2, maximum_distance: float) -> Dictionary:
	var result: Dictionary = {}
	var distance: float = maximum_distance
	for building in buildings:
		if float(building["hp"]) <= 0.0 or float(building["progress"]) < 0.1 or str(building["kind"]) == "exit":
			continue
		var test: float = position.distance_to(Vector2(building["pos"]))
		if test < distance:
			distance = test
			result = building
	return result


func _move_unit(unit: Dictionary, delta: float) -> void:
	var path: Array = unit.get("path", [])
	var index: int = int(unit.get("path_index", 0))
	if index >= path.size():
		return
	var position: Vector2 = Vector2(unit["pos"])
	var waypoint: Vector2 = Vector2(path[index])
	var tile: Vector2i = Vector2i(waypoint.round())
	if _tile_blocked(tile, str(unit["team"])):
		unit["path"] = []
		unit["repath"] = 0.0
		return
	var radius: float = _unit_radius(unit)
	var team: String = str(unit["team"])
	# Look through a few legal corridor waypoints instead of orbiting a soldier
	# who happens to stand at the center of an intermediate grid cell.
	for lookahead in range(index + 1, mini(path.size(), index + 4)):
		var candidate: Vector2 = Vector2(path[lookahead])
		if position.distance_to(candidate) > 2.5 or not _static_motion_clear(position, candidate, radius, team):
			break
		index = lookahead
		waypoint = candidate
	unit["path_index"] = index
	var speed: float = float(unit.get("speed", 1.0))
	if str(unit["team"]) == "friendly":
		var on_road: bool = roads.has(Vector2i(position.round()))
		if on_road:
			var data: Variant = roads[Vector2i(position.round())]
			on_road = not data is Dictionary or float(data.get("progress", 1.0)) >= 1.0
		if str(unit["kind"]) == "truck":
			speed *= 1.35 if on_road else 0.55
		elif on_road:
			speed *= 1.18
		if not Dictionary(unit.get("cargo", {})).is_empty() and str(unit["kind"]) != "truck":
			speed *= 0.85
	var travel: float = speed * delta
	var direction: Vector2 = position.direction_to(waypoint)
	var direct: Vector2 = position.move_toward(waypoint, travel)
	if _try_body_move(unit, direct):
		unit["nav_wait"] = 0.0
		if Vector2(unit["pos"]).distance_to(waypoint) < 0.06:
			unit["path_index"] = index + 1
		return
	var side: Vector2 = Vector2(-direction.y, direction.x)
	# Right-hand traffic is symmetric for two units moving in opposite directions.
	var alternatives: Array[Vector2] = [(direction + side * 0.8).normalized(), (direction - side * 0.8).normalized(), (direction * 0.25 + side).normalized(), (direction * 0.25 - side).normalized(), side, -side]
	for alternative in alternatives:
		if _try_body_move(unit, position + alternative * travel):
			unit["nav_wait"] = 0.0
			return
	unit["nav_wait"] = float(unit.get("nav_wait", 0.0)) + delta
	if _yield_idle_friend(unit, direct, direction, travel):
		_try_body_move(unit, direct)


func _try_body_move(unit: Dictionary, destination: Vector2) -> bool:
	if not _within_pursuit_front(unit, destination):
		return false
	if not _static_motion_clear(Vector2(unit["pos"]), destination, _unit_radius(unit), str(unit["team"])):
		return false
	if not _body_is_clear(unit, destination) and not _improves_existing_overlap(unit, destination):
		return false
	_set_unit_position(unit, destination)
	return true


func _within_pursuit_front(unit: Dictionary, destination: Vector2) -> bool:
	if str(unit["team"]) != "enemy" or not bool(unit.get("pursuer", false)):
		return true
	var limit: float = maxf(2.0, pursuit_x + 3.0)
	if destination.x <= limit + EPSILON:
		return true
	# An old save with an already illegal vanguard can retreat toward the front.
	return Vector2(unit["pos"]).x > limit + EPSILON and destination.x < Vector2(unit["pos"]).x - EPSILON


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


func _yield_idle_friend(mover: Dictionary, destination: Vector2, direction: Vector2, travel: float) -> bool:
	var priority: int = _movement_priority(mover)
	var side: Vector2 = Vector2(-direction.y, direction.x)
	var mover_id: int = int(mover["id"])
	var team: String = str(mover["team"])
	var radius: float = _unit_radius(mover)
	for other in _nearby_bodies(destination):
		if int(other["id"]) == mover_id or str(other["team"]) != team or _movement_priority(other) >= priority:
			continue
		var other_radius: float = _unit_radius(other)
		if destination.distance_to(Vector2(other["pos"])) >= radius + other_radius + 0.03:
			continue
		for yield_direction in [side, -side, direction, -direction]:
			var displaced: Vector2 = Vector2(other["pos"]) + Vector2(yield_direction) * maxf(0.08, travel * 1.25)
			if _within_pursuit_front(other, displaced) and _static_motion_clear(Vector2(other["pos"]), displaced, other_radius, str(other["team"])) and (_body_is_clear(other, displaced) or _improves_existing_overlap(other, displaced)):
				_set_unit_position(other, displaced)
				return true
	return false


func _at_target(unit: Dictionary) -> bool:
	var path: Array = unit.get("path", [])
	return int(unit.get("path_index", 0)) >= path.size() and Vector2(unit["pos"]).distance_to(Vector2(unit["target"])) <= 0.12


func _attack(attacker: Dictionary, target: Dictionary) -> void:
	if float(attacker.get("cooldown", 0.0)) > EPSILON or float(target["hp"]) <= 0.0:
		return
	if float(attacker.get("range", 0.0)) > 2.0:
		if Vector2(attacker["pos"]).distance_to(Vector2(target["pos"])) > get_attack_range(attacker) + EPSILON or not _line_of_sight(Vector2(attacker["pos"]), Vector2(target["pos"]), str(attacker["kind"])):
			return
	elif not _melee_attack_possible(attacker, target):
		return
	attacker["cooldown"] = float(attacker.get("attack_interval", 1.0))
	target["hp"] = maxf(0.0, float(target["hp"]) - float(attacker.get("damage", 0.0)))
	if float(target["hp"]) <= 0.0 and not target.has("team"):
		_nav_cache_dirty = true
	_add_effect("shot" if float(attacker.get("range", 0.0)) > 2.0 else "hit", Vector2(attacker["pos"]), Vector2(target["pos"]), 0.18)


func _update_towers(delta: float) -> void:
	for tower in buildings:
		if str(tower["kind"]) != "tower" or float(tower["hp"]) <= 0.0 or float(tower["progress"]) < 1.0 or not bool(tower["powered"]):
			continue
		tower["cooldown"] = maxf(0.0, float(tower.get("cooldown", 0.0)) - delta)
		if float(tower["cooldown"]) > EPSILON:
			continue
		var enemy: Dictionary = _closest_visible_target(tower, "enemy")
		var camp: Dictionary = get_camp(int(tower["camp_id"]))
		if enemy.is_empty() or camp.is_empty() or float(camp["supplies"]) < 0.12:
			continue
		camp["supplies"] = float(camp["supplies"]) - 0.12
		enemy["hp"] = maxf(0.0, float(enemy["hp"]) - 15.0)
		tower["cooldown"] = 0.65
		_add_effect("shot", Vector2(tower["pos"]), Vector2(enemy["pos"]), 0.16)


func _repair_nearby(unit: Dictionary, delta: float) -> void:
	var target: Dictionary = {}
	var distance: float = 3.0
	for building in buildings:
		if float(building["hp"]) <= 0.0 or float(building["hp"]) >= float(building["max_hp"]) or float(building["progress"]) < 1.0:
			continue
		var test: float = Vector2(unit["pos"]).distance_to(Vector2(building["pos"]))
		if test < distance:
			distance = test
			target = building
	if target.is_empty():
		return
	var camp: Dictionary = _nearest_camp(Vector2(unit["pos"]), false)
	if camp.is_empty() or float(camp["materials"]) < delta * 0.25:
		return
	camp["materials"] = float(camp["materials"]) - delta * 0.25
	target["hp"] = minf(float(target["max_hp"]), float(target["hp"]) + delta * 8.0)
	unit["state"] = "repairing"


func _update_pursuit(delta: float) -> void:
	if time + EPSILON < pursuit_start:
		pursuit_eta = pursuit_start - time + (_pacing("first_gate_x", 21.0) - pursuit_x) / pursuit_speed
		return
	var blocked: bool = false
	for choke in chokes:
		if not bool(choke.get("sealed", false)):
			continue
		var barrier: Dictionary = _get_building(int(choke.get("building_id", 0)))
		if barrier.is_empty() or float(barrier["hp"]) <= 0.0:
			choke["sealed"] = false
			choke["delay_remaining"] = 0.0
			_message("%s已被突破！" % str(choke["name"]))
			continue
		choke["delay_remaining"] = float(barrier["hp"]) / 27.0
		var gate_x: float = Vector2(choke["pos"]).x
		if pursuit_x + pursuit_speed * delta >= gate_x - 2.5:
			pursuit_x = minf(pursuit_x, gate_x - 2.5)
			barrier["hp"] = maxf(0.0, float(barrier["hp"]) - delta * 8.0)
			blocked = true
	if not blocked:
		pursuit_x += pursuit_speed * delta
	_spawn_clock += delta
	var enemy_count: int = 0
	for unit in units:
		if str(unit["team"]) == "enemy" and float(unit["hp"]) > 0.0:
			enemy_count += 1
	if _spawn_clock + EPSILON >= 7.0 and enemy_count < MAX_ENEMIES:
		_spawn_clock = 0.0
		var amount: int = 2 if time < 500.0 else 3
		for index in range(mini(amount, MAX_ENEMIES - enemy_count)):
			var raw: Vector2 = Vector2(maxf(2.0, pursuit_x - 0.5), _pacing("spawn_y", 19.0) + float(index))
			var tile: Vector2i = _nearest_tile(raw, "enemy")
			if tile.x < 0:
				continue
			var kind: String = "zombie"
			if time > 500.0 and _rng.randf() < 0.18:
				kind = "runner"
			if time > 850.0 and _rng.randf() < 0.1:
				kind = "brute"
			var unit: Dictionary = _add_unit(kind, "enemy", Vector2(tile), -1, 0, maxf(2.0, pursuit_x + 3.0))
			unit["pursuer"] = true
			unit["state"] = "pursuing"
	for unit in units:
		if str(unit["team"]) == "friendly" and str(unit["state"]) != "evacuated" and Vector2(unit["pos"]).x < pursuit_x - 2.0:
			unit["hp"] = maxf(0.0, float(unit["hp"]) - delta * 10.0)
	for building in buildings:
		if float(building["hp"]) > 0.0 and Vector2(building["pos"]).x < pursuit_x - 3.0:
			building["hp"] = maxf(0.0, float(building["hp"]) - delta * 8.0)
	var threatened_x: float = _pacing("exit_x", 72.0)
	for camp in camps:
		if str(camp["state"]) != "abandoned" and Vector2(camp["pos"]).x >= pursuit_x:
			threatened_x = minf(threatened_x, Vector2(camp["pos"]).x)
	pursuit_eta = maxf(0.0, (threatened_x - pursuit_x) / pursuit_speed)
	var warning_zone: int = int(pursuit_x / 10.0)
	if warning_zone != _last_pursuit_warning and warning_zone >= 0:
		_last_pursuit_warning = warning_zone
		_message("主尸潮前沿推进至西侧 %d 区。检查后方工人和运输车。" % warning_zone)


func _update_exit(_delta: float) -> void:
	var exit_building: Dictionary = _get_building(exit_building_id)
	var site: Dictionary = _get_site(exit_site_id)
	if exit_building.is_empty() or site.is_empty():
		return
	exit_progress = float(exit_building["progress"])
	if not bool(site["captured"]) or bool(exit_building.get("construction_started", false)):
		return
	var camp: Dictionary = _nearest_camp(Vector2(exit_building["pos"]))
	if camp.is_empty() or not _road_connected(Vector2(camp["pos"]), Vector2(exit_building["pos"])):
		return
	var costs: Dictionary = BUILD_COSTS["exit"].duplicate(true)
	if not _can_pay(camp, costs):
		return
	_pay(camp, costs)
	exit_building["camp_id"] = int(camp["id"])
	exit_building["construction_started"] = true
	_add_job("exit", Vector2(exit_building["pos"]), int(camp["id"]), exit_building_id, costs)
	_message("撤离站已立项：工程师施工需要附近发电机提供 6 电力。完成后将指挥车和幸存者送达。")


func _update_food(delta: float) -> void:
	_food_clock += delta
	if _food_clock + EPSILON < 5.0:
		return
	var elapsed: float = _food_clock
	_food_clock = 0.0
	for camp in camps:
		if str(camp["state"]) == "abandoned":
			continue
		var people: int = 0
		for unit in units:
			if str(unit["team"]) == "friendly" and str(unit["kind"]) != "truck" and int(unit["camp_id"]) == int(camp["id"]) and float(unit["hp"]) > 0.0:
				people += 1
		if people == 0:
			continue
		var consumption: float = float(people) * elapsed * 0.012
		camp["supplies"] = maxf(0.0, float(camp["supplies"]) - consumption)
		if float(camp["supplies"]) <= 0.0:
			if time - float(camp.get("last_shortage", -100.0)) > 30.0:
				camp["last_shortage"] = time
				_message("%s口粮耗尽，驻营人员开始失去生命；切换口粮生产或撤营。" % str(camp["name"]))
			for unit in units:
				if str(unit["team"]) == "friendly" and str(unit["kind"]) != "truck" and int(unit["camp_id"]) == int(camp["id"]):
					unit["hp"] = maxf(0.0, float(unit["hp"]) - elapsed * 0.18)
		else:
			for unit in units:
				if str(unit["team"]) == "friendly" and float(unit["hp"]) > 0.0 and Vector2(unit["pos"]).distance_to(Vector2(camp["pos"])) < 3.0:
					unit["hp"] = minf(float(unit["max_hp"]), float(unit["hp"]) + elapsed * 0.8)


func _remove_dead() -> void:
	for unit in units:
		if float(unit["hp"]) > 0.0:
			continue
		_release_job(unit, true)
		if str(unit["team"]) == "enemy":
			_add_effect("loot", Vector2(unit["pos"]), Vector2(unit["pos"]), 0.6)
	units = units.filter(func(unit: Dictionary) -> bool: return float(unit["hp"]) > 0.0)


func _update_camp_integrity() -> void:
	for camp in camps:
		if str(camp["state"]) == "abandoned":
			continue
		var has_marker: bool = false
		var marker_alive: bool = false
		for building in buildings:
			if int(building["camp_id"]) == int(camp["id"]) and ["command", "camp"].has(str(building["kind"])):
				has_marker = true
				if float(building["hp"]) > 0.0:
					marker_alive = true
		if not has_marker or marker_alive:
			continue
		var fallback: Dictionary = {}
		var best_x: float = -INF
		for other in camps:
			if int(other["id"]) != int(camp["id"]) and str(other["state"]) == "active" and Vector2(other["pos"]).x > best_x:
				fallback = other
				best_x = Vector2(other["pos"]).x
		if fallback.is_empty():
			camp["state"] = "abandoned"
			outcome = "defeat"
			_message("战役失败：最后的指挥营地被攻破，车队失去补给组织。")
			return
		_abandon_camp(camp, fallback)
		_message("%s被攻破！剩余人员向%s撤退，未运出的物资留在失守营地。" % [str(camp["name"]), str(fallback["name"])])
		for vehicle in units:
			if str(vehicle["team"]) == "friendly" and str(vehicle["kind"]) == "truck" and int(vehicle["camp_id"]) == int(camp["id"]) and str(vehicle.get("order", "")) != "evacuate_transport":
				vehicle["camp_id"] = int(fallback["id"])
				vehicle["order"] = "move"
				vehicle["state"] = "evacuating"
				_set_target(vehicle, Vector2(fallback["pos"]))
		var truck: Dictionary = get_unit(main_truck_id)
		if not truck.is_empty() and int(truck.get("evac_origin_id", 0)) == int(camp["id"]) and str(truck.get("order", "")) == "evacuate_transport":
			truck["evac_destination_id"] = int(fallback["id"])
			truck["haul_stage"] = "outbound"
			_set_target(truck, Vector2(fallback["pos"]))


func _check_outcome() -> void:
	if outcome != "playing":
		return
	var truck: Dictionary = get_unit(main_truck_id)
	var living: int = 0
	for unit in units:
		if str(unit["team"]) == "friendly" and str(unit["kind"]) != "truck" and float(unit["hp"]) > 0.0:
			living += 1
	if truck.is_empty() or float(truck["hp"]) <= 0.0:
		outcome = "defeat"
		_message("战役失败：指挥运输车被摧毁。")
		return
	if living < 4:
		outcome = "defeat"
		_message("战役失败：幸存者不足四人，无法完成撤离。")
		return
	if exit_progress < 1.0:
		return
	var exit_building: Dictionary = _get_building(exit_building_id)
	if exit_building.is_empty() or not bool(exit_building.get("powered", false)):
		return
	var at: Vector2 = Vector2(exit_building["pos"])
	if Vector2(truck["pos"]).distance_to(at) > 5.0:
		return
	var near: Array = []
	for unit in units:
		if str(unit["team"]) == "friendly" and str(unit["kind"]) != "truck" and Vector2(unit["pos"]).distance_to(at) <= 5.0:
			near.append(unit)
	if near.size() < 4:
		return
	evacuated = near.size()
	for unit in near:
		unit["state"] = "evacuated"
	truck["state"] = "evacuated"
	outcome = "victory"
	_message("突围成功：指挥车与 %d 名幸存者抵达撤离站。" % evacuated)


func get_summary() -> Dictionary:
	var result: Dictionary = {"materials": 0.0, "supplies": 0.0, "fuel": 0.0, "power": 0.0, "power_capacity": 0.0, "salvage": 0.0, "crude": 0.0, "people": 0, "zombies": 0, "phase": phase, "outcome": outcome, "exit_progress": exit_progress, "evacuated": evacuated, "pursuit_eta": pursuit_eta, "time": time}
	for camp in camps:
		if str(camp["state"]) == "abandoned":
			continue
		for key in ["materials", "supplies", "fuel", "power", "power_capacity", "salvage", "crude"]:
			result[key] = float(result[key]) + float(camp.get(key, 0.0))
	for unit in units:
		if str(unit["team"]) == "enemy":
			result["zombies"] = int(result["zombies"]) + 1
		elif str(unit["kind"]) != "truck":
			result["people"] = int(result["people"]) + 1
	return result


func _add_effect(kind: String, position: Vector2, destination: Vector2, lifetime: float) -> void:
	if effects.size() > 120:
		effects.pop_front()
	effects.append({"kind": kind, "pos": position, "to": destination, "ttl": lifetime})


func _message(content: String) -> void:
	messages.append(content)
	while messages.size() > 12:
		messages.pop_front()


func _building_name(kind: String) -> String:
	return str({"camp": "前进营地", "generator": "发电机", "workshop": "工坊", "tower": "自动炮塔", "barracks": "军营", "barricade": "路障", "exit": "撤离站", "road": "道路"}.get(kind, kind))


func save_state() -> Dictionary:
	var payload: Dictionary = {
		"time": time, "phase": phase, "outcome": outcome, "paused": paused,
		"map_size": map_size, "terrain": terrain, "roads": roads, "ramps": ramps,
		"units": units, "buildings": buildings, "camps": camps, "sites": sites,
		"effects": effects, "messages": messages, "pursuit_x": pursuit_x,
		"pursuit_eta": pursuit_eta, "exit_progress": exit_progress, "evacuated": evacuated,
		"seed_value": seed_value, "chokes": chokes, "main_truck_id": main_truck_id,
		"exit_building_id": exit_building_id, "exit_site_id": exit_site_id,
		"pursuit_speed": pursuit_speed, "pursuit_start": pursuit_start,
		"next_id": _next_id, "jobs": _jobs, "ai_clock": _ai_clock,
		"logistics_clock": _logistics_clock, "spawn_clock": _spawn_clock,
		"food_clock": _food_clock, "last_pursuit_warning": _last_pursuit_warning,
		"rng_state": str(_rng.state)
	}
	# Keep legacy Canyon saves byte-compatible while binding new mission payloads
	# to their outer tag, so swapping two recognized tags cannot change identity.
	if mission_id != "canyon":
		payload["mission_id"] = mission_id
	return {"version": SAVE_VERSION, "mission": MISSION_SAVE_TAGS[mission_id], "payload": _encode_value(payload)}


func load_state(data: Dictionary) -> bool:
	if not _is_number(data.get("version")) or int(data["version"]) != SAVE_VERSION or not data.get("mission", null) is String or not data.has("payload"):
		return false
	var requested_id: String = ""
	for candidate: String in MISSION_SAVE_TAGS:
		if data["mission"] == MISSION_SAVE_TAGS[candidate]:
			requested_id = candidate
			break
	if requested_id.is_empty():
		return false
	var definition: Dictionary = CampaignCatalog.mission(requested_id)
	_decode_budget = 120000
	var decoded: Variant = _decode_value(data["payload"], 0)
	if _decode_budget < 0 or not decoded is Dictionary or not _validate_state(decoded):
		return false
	var state: Dictionary = decoded
	if state.has("mission_id"):
		if not state["mission_id"] is String or state["mission_id"] != requested_id:
			return false
	elif requested_id != "canyon":
		return false
	_apply_mission_metadata(definition)
	time = float(state["time"])
	phase = str(state["phase"])
	outcome = str(state["outcome"])
	paused = bool(state["paused"])
	map_size = state["map_size"]
	terrain = state["terrain"]
	roads = state["roads"]
	ramps = state["ramps"]
	units = state["units"]
	buildings = state["buildings"]
	camps = state["camps"]
	sites = state["sites"]
	effects = state["effects"]
	messages = state["messages"]
	pursuit_x = float(state["pursuit_x"])
	pursuit_eta = float(state["pursuit_eta"])
	exit_progress = float(state["exit_progress"])
	evacuated = int(state["evacuated"])
	seed_value = int(state["seed_value"])
	chokes = state["chokes"]
	main_truck_id = int(state["main_truck_id"])
	exit_building_id = int(state["exit_building_id"])
	exit_site_id = int(state["exit_site_id"])
	pursuit_speed = float(state.get("pursuit_speed", _pacing("pursuit_speed", 0.035)))
	pursuit_start = float(state.get("pursuit_start", _pacing("pursuit_start", 150.0)))
	_next_id = int(state["next_id"])
	_jobs = state["jobs"]
	_ai_clock = float(state.get("ai_clock", 0.0))
	_logistics_clock = float(state.get("logistics_clock", 0.0))
	_spawn_clock = float(state.get("spawn_clock", 0.0))
	_food_clock = float(state.get("food_clock", 0.0))
	_last_pursuit_warning = int(state.get("last_pursuit_warning", -1))
	_rng.seed = seed_value
	_rng.state = str(state["rng_state"]).to_int()
	_invalidate_navigation()
	_spatial_valid = false
	return true


func _encode_value(value: Variant) -> Variant:
	if value is Vector2:
		return {"$type": "Vector2", "x": value.x, "y": value.y}
	if value is Vector2i:
		return {"$type": "Vector2i", "x": value.x, "y": value.y}
	if value is Array:
		var encoded: Array = []
		for element in value:
			encoded.append(_encode_value(element))
		return encoded
	if value is Dictionary:
		var entries: Array = []
		for key in value:
			entries.append([_encode_value(key), _encode_value(value[key])])
		return {"$type": "Dictionary", "entries": entries}
	return value


func _decode_value(value: Variant, depth: int) -> Variant:
	_decode_budget -= 1
	if depth > 40 or _decode_budget < 0:
		return null
	if value is Array:
		var decoded: Array = []
		for element in value:
			decoded.append(_decode_value(element, depth + 1))
		return decoded
	if value is Dictionary:
		var tag: String = str(value.get("$type", ""))
		if tag == "Vector2":
			if not _is_number(value.get("x")) or not _is_number(value.get("y")):
				return null
			return Vector2(float(value["x"]), float(value["y"]))
		if tag == "Vector2i":
			if not _is_number(value.get("x")) or not _is_number(value.get("y")):
				return null
			return Vector2i(int(value["x"]), int(value["y"]))
		if tag == "Dictionary" and value.get("entries") is Array:
			var decoded: Dictionary = {}
			for pair in value["entries"]:
				if not pair is Array or pair.size() != 2:
					return null
				var key: Variant = _decode_value(pair[0], depth + 1)
				if not (key is String or key is int or key is float or key is Vector2i):
					return null
				decoded[key] = _decode_value(pair[1], depth + 1)
			return decoded
		return null
	if value is float and not is_finite(value):
		return null
	if value is String or value is bool or value is int or value is float or value == null:
		return value
	return null


func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _validate_state(state: Dictionary) -> bool:
	for key in ["time", "phase", "outcome", "paused", "map_size", "terrain", "roads", "ramps", "units", "buildings", "camps", "sites", "effects", "messages", "chokes", "jobs", "pursuit_x", "pursuit_eta", "exit_progress", "evacuated", "seed_value", "main_truck_id", "exit_building_id", "exit_site_id", "next_id", "rng_state"]:
		if not state.has(key):
			return false
	if state["map_size"] != Vector2i(80, 40) or not state["terrain"] is Array or state["terrain"].size() != 40:
		return false
	for row in state["terrain"]:
		if not row is Array or row.size() != 80:
			return false
		for tile in row:
			if not _is_number(tile) or int(tile) < -1 or int(tile) > 1:
				return false
	if not ["preparation", "advance", "evacuation"].has(str(state["phase"])) or not ["playing", "victory", "defeat"].has(str(state["outcome"])):
		return false
	for key in ["time", "pursuit_x", "pursuit_eta", "exit_progress", "evacuated", "seed_value", "next_id", "main_truck_id", "exit_building_id", "exit_site_id"]:
		if not _is_number(state[key]):
			return false
	if float(state["time"]) < 0.0 or float(state["time"]) > 1000000.0 or float(state["exit_progress"]) < 0.0 or float(state["exit_progress"]) > 1.0:
		return false
	if not state["paused"] is bool or not str(state["rng_state"]).is_valid_int():
		return false
	for timer_key in ["ai_clock", "logistics_clock", "spawn_clock", "food_clock", "pursuit_speed", "pursuit_start"]:
		if state.has(timer_key) and (not _is_number(state[timer_key]) or float(state[timer_key]) < 0.0):
			return false
	if float(state.get("pursuit_speed", 0.035)) <= 0.0 or float(state.get("pursuit_speed", 0.035)) > 1.0:
		return false
	for key in ["roads", "ramps"]:
		if not state[key] is Dictionary or state[key].size() > 3200:
			return false
		for tile in state[key]:
			if not tile is Vector2i or tile.x < 0 or tile.y < 0 or tile.x >= 80 or tile.y >= 40:
				return false
	var identifiers: Dictionary = {}
	for key in ["units", "buildings", "camps", "sites"]:
		if not state[key] is Array or state[key].size() > 800:
			return false
		for item in state[key]:
			if not item is Dictionary or not item.has("id") or not _is_number(item["id"]) or identifiers.has(int(item["id"])) or not item.get("pos") is Vector2 or not Vector2(item["pos"]).is_finite():
				return false
			var position: Vector2 = item["pos"]
			if position.x < -10.0 or position.x > 90.0 or position.y < -10.0 or position.y > 50.0:
				return false
			identifiers[int(item["id"])] = true
			if key == "units" or key == "buildings":
				if not _is_number(item.get("hp")) or not _is_number(item.get("max_hp")) or float(item["max_hp"]) <= 0.0:
					return false
				if not item.get("kind") is String or not _is_number(item.get("camp_id")):
					return false
			if key == "units":
				if not ["friendly", "enemy"].has(str(item.get("team", ""))) or not item.get("target") is Vector2 or not item.get("state") is String or not item.get("path", []) is Array:
					return false
				for waypoint in item.get("path", []):
					if not waypoint is Vector2 or not Vector2(waypoint).is_finite():
						return false
				for numeric_key in ["speed", "range", "damage", "attack_interval", "cooldown", "repath", "capacity", "job_id", "squad", "escort_id", "haul_site", "evac_origin_id", "evac_destination_id", "path_index", "nav_wait"]:
					if item.has(numeric_key) and not _is_number(item[numeric_key]):
						return false
				for coordinate_key in ["formation_anchor", "formation_slot"]:
					if item.has(coordinate_key) and (not item[coordinate_key] is Vector2 or not Vector2(item[coordinate_key]).is_finite()):
						return false
			if key == "camps":
				if item.has("evac_gather_version") and (not _is_number(item["evac_gather_version"]) or float(item["evac_gather_version"]) != 1.0):
					return false
				if not ["active", "packing", "abandoned"].has(str(item.get("state", ""))):
					return false
				if not item.get("name") is String or not ["production", "defense", "evacuation"].has(str(item.get("priority", ""))):
					return false
				for required_resource in ["materials", "supplies", "fuel", "power"]:
					if not _is_number(item.get(required_resource)):
						return false
				for resource in RESOURCE_KEYS:
					if not _is_number(item.get(resource, 0.0)) or float(item.get(resource, 0.0)) < 0.0:
						return false
			if key == "sites":
				if not item.get("captured") is bool or not _is_number(item.get("progress")) or not _valid_inventory(item.get("stock", {})) or not item.get("kind") is String:
					return false
	for key in ["effects", "messages", "chokes", "jobs"]:
		if not state[key] is Array or state[key].size() > 4000:
			return false
	if state["messages"].size() > 12 or not state["rng_state"] is String:
		return false
	for job in state["jobs"]:
		if not job is Dictionary or not job.get("pos") is Vector2 or not BUILD_SECONDS.has(str(job.get("kind", ""))) or not job.get("costs") is Dictionary:
			return false
	for choke in state["chokes"]:
		if not choke is Dictionary or not choke.get("pos") is Vector2:
			return false
	# Validate references before committing anything: a syntactically valid save
	# must not duplicate future IDs, strand cargo, or remove its command vehicle.
	var camp_ids: Dictionary = {}
	var unit_ids: Dictionary = {}
	var building_ids: Dictionary = {}
	var site_ids: Dictionary = {}
	var maximum_id: int = 0
	for camp in state["camps"]:
		camp_ids[int(camp["id"])] = camp
	for unit in state["units"]:
		unit_ids[int(unit["id"])] = unit
	for building in state["buildings"]:
		building_ids[int(building["id"])] = building
	for site in state["sites"]:
		site_ids[int(site["id"])] = site
	for identifier in identifiers:
		if int(identifier) <= 0:
			return false
		maximum_id = maxi(maximum_id, int(identifier))
	var truck_id: int = int(state["main_truck_id"])
	if str(state["outcome"]) != "defeat":
		if not unit_ids.has(truck_id) or str(unit_ids[truck_id].get("kind", "")) != "truck" or str(unit_ids[truck_id].get("team", "")) != "friendly":
			return false
	var saved_exit_id: int = int(state["exit_building_id"])
	if saved_exit_id != 0 and (not building_ids.has(saved_exit_id) or str(building_ids[saved_exit_id].get("kind", "")) != "exit"):
		return false
	var saved_site_id: int = int(state["exit_site_id"])
	if saved_site_id != 0 and (not site_ids.has(saved_site_id) or str(site_ids[saved_site_id].get("kind", "")) != "exit"):
		return false
	for unit in state["units"]:
		if str(unit["team"]) == "friendly" and not camp_ids.has(int(unit["camp_id"])):
			return false
		if not ["rifle", "engineer", "worker", "truck", "zombie", "runner", "brute"].has(str(unit["kind"])):
			return false
		if not _valid_inventory(unit.get("cargo", {})):
			return false
		var path: Array = unit.get("path", [])
		if int(unit.get("path_index", 0)) < 0 or int(unit.get("path_index", 0)) > path.size():
			return false
	for building in state["buildings"]:
		var owner: int = int(building["camp_id"])
		if owner != -1 and not camp_ids.has(owner):
			return false
		if not _is_number(building.get("progress")) or float(building["progress"]) < 0.0 or float(building["progress"]) > 1.0:
			return false
	for camp in state["camps"]:
		if not camp.get("recruit_queue", []) is Array:
			return false
		for entry in camp.get("recruit_queue", []):
			if not entry is Dictionary or not RECRUIT_SECONDS.has(str(entry.get("kind", ""))) or not _valid_inventory(entry.get("costs", {})):
				return false
			if not _is_number(entry.get("duration")) or float(entry["duration"]) <= 0.0 or not _is_number(entry.get("elapsed")) or float(entry["elapsed"]) < 0.0 or float(entry["elapsed"]) > float(entry["duration"]) + 1.0:
				return false
	for job in state["jobs"]:
		if not _is_number(job.get("id")) or identifiers.has(int(job["id"])) or not _valid_inventory(job["costs"]):
			return false
		for numeric_key in ["source_camp_id", "building_id", "assigned"]:
			if not _is_number(job.get(numeric_key)):
				return false
		identifiers[int(job["id"])] = true
		maximum_id = maxi(maximum_id, int(job["id"]))
		if not camp_ids.has(int(job.get("source_camp_id", 0))):
			return false
		if not _is_number(job.get("progress")) or float(job["progress"]) < 0.0 or float(job["progress"]) > 1.0:
			return false
		if not bool(job.get("done", false)):
			var assigned: int = int(job.get("assigned", 0))
			if assigned != 0 and not unit_ids.has(assigned):
				return false
			if str(job["kind"]) != "road" and not building_ids.has(int(job.get("building_id", 0))):
				return false
		if job.has("road_tiles"):
			if not job["road_tiles"] is Array:
				return false
			for tile in job["road_tiles"]:
				if not tile is Vector2i or tile.x < 0 or tile.y < 0 or tile.x >= 80 or tile.y >= 40:
					return false
	if int(state["next_id"]) <= maximum_id:
		return false
	for message in state["messages"]:
		if not message is String or message.length() > 2048:
			return false
	for effect in state["effects"]:
		if not effect is Dictionary or not effect.get("pos") is Vector2 or not effect.get("to") is Vector2 or not _is_number(effect.get("ttl")):
			return false
	return true


func _valid_inventory(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not RESOURCE_KEYS.has(str(key)) or not _is_number(value[key]) or float(value[key]) < 0.0 or float(value[key]) > 10000000.0:
			return false
	return true
