extends RefCounted
## Pure-state, deterministic first-campaign simulation. Coordinates are tile units.
## All orders, construction, logistics and evacuation happen in simulation time.

const SAVE_VERSION: int = 1
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
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0)]
const RESOURCE_KEYS: Array[String] = ["materials", "supplies", "fuel", "salvage", "crude"]
const MAX_ENEMIES: int = 100
const EPSILON: float = 0.000001

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


func reset(mission_seed: int = 42) -> void:
	seed_value = mission_seed
	_rng.seed = mission_seed
	time = 0.0
	phase = "preparation"
	outcome = "playing"
	paused = false
	pursuit_x = -5.0
	pursuit_eta = 540.0
	pursuit_speed = 0.035
	pursuit_start = 150.0
	exit_progress = 0.0
	evacuated = 0
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
	_create_terrain()
	var home: Dictionary = _make_camp(Vector2(9, 22), "后方营地", 220.0, 150.0, 110.0)
	var home_id: int = int(home["id"])
	_add_building("command", Vector2(9, 22), home_id, 1.0)
	_add_building("generator", Vector2(9, 25), home_id, 1.0)
	_add_building("workshop", Vector2(12, 22), home_id, 1.0)
	_add_building("tower", Vector2(16, 20), home_id, 1.0)
	for x in range(8, 19):
		roads[Vector2i(x, 23)] = {"progress": 1.0, "camp_id": home_id}
	for y in range(20, 26):
		roads[Vector2i(9, y)] = {"progress": 1.0, "camp_id": home_id}
	for y in range(20, 24):
		roads[Vector2i(18, y)] = {"progress": 1.0, "camp_id": home_id}
	roads[Vector2i(17, 22)] = {"progress": 1.0, "camp_id": home_id}
	_add_unit("rifle", "friendly", Vector2(12, 20), home_id, 1)
	_add_unit("rifle", "friendly", Vector2(13, 20), home_id, 1)
	_add_unit("rifle", "friendly", Vector2(12, 21), home_id, 1)
	_add_unit("engineer", "friendly", Vector2(10, 21), home_id, 1)
	_add_unit("worker", "friendly", Vector2(8, 23), home_id, 0)
	_add_unit("worker", "friendly", Vector2(10, 24), home_id, 0)
	_add_unit("worker", "friendly", Vector2(11, 24), home_id, 0)
	var truck: Dictionary = _add_unit("truck", "friendly", Vector2(11, 23), home_id, 0)
	main_truck_id = int(truck["id"])
	_add_site("cache", Vector2(25, 20), "旧公路补给", {"materials": 35.0, "supplies": 45.0, "fuel": 15.0})
	_add_site("quarry", Vector2(35, 10), "北部废料场", {"salvage": 420.0})
	_add_site("fuel", Vector2(35, 31), "南部油库", {"crude": 280.0})
	_add_site("cache", Vector2(53, 21), "前营旧址", {"materials": 70.0, "supplies": 50.0, "fuel": 25.0})
	var exit_site: Dictionary = _add_site("exit", Vector2(72, 19), "东部撤离站", {})
	exit_site_id = int(exit_site["id"])
	var exit_building: Dictionary = _add_building("exit", Vector2(72, 19), -1, 0.0)
	exit_building["construction_started"] = false
	exit_building["required_power"] = 6.0
	exit_building_id = int(exit_building["id"])
	_spawn_guards(Vector2(25, 20), 3, false)
	_spawn_guards(Vector2(35, 10), 5, false)
	_spawn_guards(Vector2(35, 31), 4, true)
	_spawn_guards(Vector2(53, 21), 5, true)
	_spawn_guards(Vector2(72, 19), 6, true)
	chokes = [
		{"pos": Vector2(21, 20), "name": "西部关口", "sealed": false, "pending": false, "building_id": 0},
		{"pos": Vector2(61, 20), "name": "东部关口", "sealed": false, "pending": false, "building_id": 0}
	]
	_update_power(0.0)
	_message("战役开始：先带步枪队与工程师越过西部关口，清理前方补给。")
	_message("道路连接资源点后，工人会实际往返运料；发电机只为附近设施供能。")


func _create_terrain() -> void:
	terrain.clear()
	for y in range(map_size.y):
		var row: Array = []
		for x in range(map_size.x):
			var value: int = 0
			if x < 2 or x > 77 or y < 3 or y > 36:
				value = -1
			if x >= 3 and x <= 17 and y >= 14 and y <= 29:
				value = 1
			if x >= 29 and x <= 43 and y >= 6 and y <= 15:
				value = 1
			if x >= 48 and x <= 59 and y >= 16 and y <= 25:
				value = 1
			if x >= 67 and x <= 76 and y >= 14 and y <= 25:
				value = 1
			if (x >= 20 and x <= 22) or (x >= 60 and x <= 62):
				value = 0 if y >= 19 and y <= 21 else -1
			row.append(value)
		terrain.append(row)
	# Explicit crossings are the only way to change terrain height.
	for x in range(17, 20):
		for y in range(20, 23):
			ramps[Vector2i(x, y)] = true
	for x in range(34, 37):
		for y in range(15, 18):
			ramps[Vector2i(x, y)] = true
	for x in range(47, 50):
		for y in range(20, 23):
			ramps[Vector2i(x, y)] = true
	for x in range(58, 61):
		for y in range(19, 22):
			ramps[Vector2i(x, y)] = true
	for x in range(65, 69):
		for y in range(18, 22):
			ramps[Vector2i(x, y)] = true


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
	if pursuit_x > 33.0 and phase != "evacuation":
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
	return building


func _add_unit(kind: String, team: String, position: Vector2, camp_id: int, squad: int) -> Dictionary:
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
	return _terrain_walkable(tile) and not _tile_blocked(tile, "friendly")


func _terrain_walkable(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < map_size.x and tile.y < map_size.y and int(terrain[tile.y][tile.x]) >= 0


func _tile_blocked(tile: Vector2i, team: String) -> bool:
	for building in buildings:
		if float(building["hp"]) <= 0.0 or float(building.get("progress", 0.0)) < 1.0:
			continue
		var at: Vector2i = Vector2i(Vector2(building["pos"]).round())
		if str(building["kind"]) == "barricade":
			var span: int = int(building.get("span", 0))
			if tile.x == at.x and absi(tile.y - at.y) <= span:
				return true
		elif team != "logistics" and str(building["kind"]) != "exit" and tile == at:
			return true
	return false


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
	var frontier: Array[Vector2i] = [start]
	var previous: Dictionary = {start: start}
	var cursor: int = 0
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		if current == finish:
			break
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if not previous.has(next) and _can_step(current, next, team):
				previous[next] = current
				frontier.append(next)
	if not previous.has(finish):
		return []
	var reverse_path: Array = []
	var walk: Vector2i = finish
	while walk != start:
		reverse_path.append(Vector2(walk))
		walk = Vector2i(previous[walk])
	reverse_path.reverse()
	return reverse_path


func _set_target(unit: Dictionary, destination: Vector2) -> void:
	var team: String = str(unit["team"])
	var tile: Vector2i = _nearest_tile(destination, team)
	unit["target"] = Vector2(tile)
	unit["path"] = _find_path(Vector2(unit["pos"]), Vector2(tile), team)
	unit["path_index"] = 0
	unit["repath"] = 1.0


func command_move(ids: Array, target: Vector2, attack_move: bool = false) -> void:
	if outcome != "playing" or not target.is_finite():
		return
	var formation_index: int = 0
	for unit_id in ids:
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
		var offset: Vector2 = Vector2(float(formation_index % 3 - 1) * 0.7, float(formation_index / 3) * 0.7)
		_set_target(unit, target + offset)
		formation_index += 1


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
	for unit in units:
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


func build(kind: String, tile: Vector2i) -> bool:
	if outcome != "playing" or not BUILD_COSTS.has(kind) or kind == "exit":
		return false
	if not _terrain_walkable(tile):
		_message("不能在悬崖或地图边缘施工。")
		return false
	var position: Vector2 = Vector2(tile)
	var camp: Dictionary = _nearest_camp(position)
	if camp.is_empty():
		return false
	if kind == "road":
		return _build_road(tile, camp)
	for existing in buildings:
		if float(existing["hp"]) > 0.0 and Vector2(existing["pos"]).distance_to(position) < 1.7:
			_message("建筑之间需要留出通行与施工空间。")
			return false
	if position.x < pursuit_x + 1.0:
		_message("该区域已被主尸潮淹没。")
		return false
	if Vector2(camp["pos"]).distance_to(position) > 13.0 and not road_connected(Vector2(camp["pos"]), position):
		_message("先将道路铺到施工点附近，再建立远方设施。")
		return false
	if _find_path(Vector2(camp["pos"]), position).is_empty():
		_message("施工队无法到达这里；检查坡道和关口。")
		return false
	var costs: Dictionary = BUILD_COSTS[kind].duplicate(true)
	if not _can_pay(camp, costs):
		_message("附近营地缺少建造材料或补给。")
		return false
	_pay(camp, costs)
	var building: Dictionary = _add_building(kind, position, int(camp["id"]), 0.0)
	_add_job(kind, position, int(camp["id"]), int(building["id"]), costs)
	_message("已设立工地：%s。工程师会领取材料并前往施工。" % _building_name(kind))
	return true


func _build_road(tile: Vector2i, camp: Dictionary) -> bool:
	if roads.has(tile):
		return false
	var start: Vector2 = Vector2(camp["pos"])
	var best_distance: float = INF
	for existing_tile in roads:
		var data: Variant = roads[existing_tile]
		var complete: bool = not data is Dictionary or float(data.get("progress", 1.0)) >= 1.0
		if not complete:
			continue
		var test: float = Vector2(existing_tile).distance_squared_to(Vector2(tile))
		if test < best_distance and road_connected(Vector2(camp["pos"]), Vector2(existing_tile)):
			start = Vector2(existing_tile)
			best_distance = test
	var path: Array = _find_path(start, Vector2(tile), "road")
	if path.is_empty():
		_message("道路无法跨越悬崖；请利用坡道或现有桥面。")
		return false
	var new_tiles: Array[Vector2i] = []
	for waypoint in path:
		var at: Vector2i = Vector2i(Vector2(waypoint).round())
		if not roads.has(at):
			new_tiles.append(at)
	if new_tiles.is_empty():
		return false
	var costs: Dictionary = {"materials": float(new_tiles.size()) * 2.0}
	if not _can_pay(camp, costs):
		_message("这段道路需要 %d 建材；可先铺较短一段。" % int(costs["materials"]))
		return false
	_pay(camp, costs)
	for at in new_tiles:
		roads[at] = {"progress": 0.0, "camp_id": int(camp["id"])}
	var road_job: Dictionary = _add_job("road", Vector2(new_tiles[0]), int(camp["id"]), 0, costs)
	road_job["road_tiles"] = new_tiles
	road_job["road_cursor"] = 0
	_message("已规划 %d 格道路，工人和工程师将逐段施工。" % new_tiles.size())
	return true


func _add_job(kind: String, position: Vector2, source_id: int, building_id: int, costs: Dictionary) -> Dictionary:
	var job: Dictionary = {"id": _new_id(), "kind": kind, "pos": position, "source_camp_id": source_id, "building_id": building_id, "costs": costs.duplicate(true), "progress": 0.0, "assigned": 0, "funded": true, "picked_up": false, "delivered": false, "done": false}
	_jobs.append(job)
	return job


func road_connected(origin: Vector2, destination: Vector2) -> bool:
	var frontier: Array[Vector2i] = []
	var visited: Dictionary = {}
	for key in roads:
		var tile: Vector2i = Vector2i(key)
		var data: Variant = roads[key]
		if data is Dictionary and float(data.get("progress", 1.0)) < 0.999:
			continue
		if _road_endpoint_reachable(tile, origin):
			frontier.append(tile)
			visited[tile] = true
	var cursor: int = 0
	while cursor < frontier.size():
		var at: Vector2i = frontier[cursor]
		cursor += 1
		if _road_endpoint_reachable(at, destination):
			return true
		for direction in DIRECTIONS:
			var next: Vector2i = at + direction
			if visited.has(next) or not roads.has(next):
				continue
			var data: Variant = roads[next]
			if data is Dictionary and float(data.get("progress", 1.0)) < 0.999:
				continue
			if not _can_step(at, next, "logistics"):
				continue
			visited[next] = true
			frontier.append(next)
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
			if str(building["kind"]) == "generator" and float(building["progress"]) >= 1.0 and float(camp["fuel"]) > 0.001 and road_connected(Vector2(camp["pos"]), Vector2(building["pos"])):
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
				if not road_connected(Vector2(camp["pos"]), Vector2(consumer["pos"])):
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


func recruit(camp_id: int, kind: String) -> bool:
	if outcome != "playing" or not RECRUIT_COSTS.has(kind):
		return false
	var camp: Dictionary = get_camp(camp_id)
	if camp.is_empty() or str(camp["state"]) != "active":
		return false
	var population: int = 0
	for unit in units:
		if str(unit["team"]) == "friendly" and float(unit["hp"]) > 0.0:
			population += 1
	for other_camp in camps:
		population += Array(other_camp.get("recruit_queue", [])).size()
	if population >= POPULATION_CAP:
		_message("已达到 32 单位指挥上限（含训练中的单位）。")
		return false
	var queue: Array = camp.get("recruit_queue", [])
	if queue.size() >= 4:
		_message("该营地的训练队列已满。")
		return false
	if not _training_power_available(camp, kind):
		_message("训练需要正常供能的军营；工人需要营地供电，车辆需要供能工坊。")
		return false
	var costs: Dictionary = Dictionary(RECRUIT_COSTS[kind]).duplicate(true)
	if not _can_pay(camp, costs):
		_message("该营地缺少训练所需的材料、口粮或燃料。")
		return false
	_pay(camp, costs)
	queue.append({"kind": kind, "elapsed": 0.0, "progress": 0.0, "duration": float(RECRUIT_SECONDS[kind]), "costs": costs})
	camp["recruit_queue"] = queue
	camp["recruit_status"] = "training"
	_message("%s已安排训练：%s。" % [str(camp.get("name", "营地")), str({"rifle": "步枪兵", "engineer": "工程师", "worker": "工人", "truck": "补给卡车"}[kind])])
	return true


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
			if total <= 0.01 or not road_connected(Vector2(camp["pos"]), Vector2(site["pos"])):
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
			var cargo: Dictionary = truck.get("cargo", {})
			var capacity: float = maxf(0.0, float(truck.get("capacity", 180.0)) - _cargo_weight(cargo))
			for key in RESOURCE_KEYS:
				var amount: float = minf(float(camp.get(key, 0.0)), capacity)
				if amount > 0.0:
					cargo[key] = float(cargo.get(key, 0.0)) + amount
					camp[key] = float(camp.get(key, 0.0)) - amount
					capacity -= amount
			truck["cargo"] = cargo
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
	for unit in units:
		if str(unit["team"]) != "friendly" or int(unit["camp_id"]) != int(camp["id"]) or str(unit["kind"]) == "truck":
			continue
		unit["camp_id"] = int(destination["id"])
		unit["order"] = "move"
		unit["state"] = "moving"
		unit["manual"] = false
		_set_target(unit, Vector2(destination["pos"]) + Vector2(0, 1))
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


func _update_units(delta: float) -> void:
	_ai_clock += delta
	var rethink: bool = _ai_clock + EPSILON >= 0.4
	if rethink:
		_ai_clock = 0.0
	var barrier_attackers: Dictionary = {}
	for unit in units:
		if float(unit["hp"]) <= 0.0 or str(unit["state"]) == "evacuated":
			continue
		unit["cooldown"] = maxf(0.0, float(unit.get("cooldown", 0.0)) - delta)
		unit["repath"] = maxf(0.0, float(unit.get("repath", 0.0)) - delta)
		if str(unit["team"]) == "enemy":
			_update_enemy(unit, delta, rethink, barrier_attackers)
			continue
		var position: Vector2 = Vector2(unit["pos"])
		var attack_range: float = float(unit.get("range", 0.0))
		var enemy: Dictionary = _closest_unit(position, "enemy", [], attack_range)
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


func _update_enemy(unit: Dictionary, delta: float, rethink: bool, barrier_attackers: Dictionary) -> void:
	var position: Vector2 = Vector2(unit["pos"])
	var victim: Dictionary = _closest_unit(position, "friendly", [], 8.0 if not bool(unit.get("pursuer", false)) else 14.0)
	# Seeing survivors across a sealed bridge must not prevent the horde from
	# attacking that bridge. Otherwise it stared at an unreachable target.
	var barrier: Dictionary = _blocking_barrier_ahead(position, Vector2(victim["pos"]) if not victim.is_empty() else Vector2(78, 20))
	if not barrier.is_empty():
		if position.distance_to(Vector2(barrier["pos"])) <= float(unit["range"]) + 1.8:
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
		if distance <= float(unit["range"]):
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
			if distance <= float(unit["range"]) + 0.8 + range_bonus:
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
				var destination: Vector2 = Vector2(73, 20)
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
	# Vanguard units may lead the visible horde edge slightly, but cannot race
	# twenty tiles ahead and kill an apparently safe convoy without warning.
	if str(unit["team"]) == "enemy" and bool(unit.get("pursuer", false)) and waypoint.x > pursuit_x + 3.0:
		return
	var tile: Vector2i = Vector2i(waypoint.round())
	if _tile_blocked(tile, str(unit["team"])):
		unit["path"] = []
		unit["repath"] = 0.0
		return
	var speed: float = float(unit.get("speed", 1.0))
	if str(unit["team"]) == "friendly":
		var on_road: bool = roads.has(Vector2i(position.round()))
		if on_road:
			var data: Variant = roads[Vector2i(position.round())]
			on_road = not data is Dictionary or float(data.get("progress", 1.0)) >= 0.999
		if str(unit["kind"]) == "truck":
			speed *= 1.35 if on_road else 0.55
		elif on_road:
			speed *= 1.18
		if not Dictionary(unit.get("cargo", {})).is_empty() and str(unit["kind"]) != "truck":
			speed *= 0.85
	var travel: float = speed * delta
	if position.distance_to(waypoint) <= travel:
		unit["pos"] = waypoint
		unit["path_index"] = index + 1
	else:
		unit["pos"] = position.move_toward(waypoint, travel)


func _at_target(unit: Dictionary) -> bool:
	var path: Array = unit.get("path", [])
	return int(unit.get("path_index", 0)) >= path.size() and Vector2(unit["pos"]).distance_to(Vector2(unit["target"])) <= 1.3


func _attack(attacker: Dictionary, target: Dictionary) -> void:
	if float(attacker.get("cooldown", 0.0)) > EPSILON or float(target["hp"]) <= 0.0:
		return
	attacker["cooldown"] = float(attacker.get("attack_interval", 1.0))
	target["hp"] = maxf(0.0, float(target["hp"]) - float(attacker.get("damage", 0.0)))
	_add_effect("shot" if float(attacker.get("range", 0.0)) > 2.0 else "hit", Vector2(attacker["pos"]), Vector2(target["pos"]), 0.18)


func _update_towers(delta: float) -> void:
	for tower in buildings:
		if str(tower["kind"]) != "tower" or float(tower["hp"]) <= 0.0 or float(tower["progress"]) < 1.0 or not bool(tower["powered"]):
			continue
		tower["cooldown"] = maxf(0.0, float(tower.get("cooldown", 0.0)) - delta)
		if float(tower["cooldown"]) > EPSILON:
			continue
		var enemy: Dictionary = _closest_unit(Vector2(tower["pos"]), "enemy", [], float(tower.get("range", 7.0)))
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
		pursuit_eta = pursuit_start - time + (21.0 - pursuit_x) / pursuit_speed
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
			var raw: Vector2 = Vector2(maxf(2.0, pursuit_x - 0.5), 19.0 + float(index))
			var tile: Vector2i = _nearest_tile(raw, "enemy")
			if tile.x < 0:
				continue
			var kind: String = "zombie"
			if time > 500.0 and _rng.randf() < 0.18:
				kind = "runner"
			if time > 850.0 and _rng.randf() < 0.1:
				kind = "brute"
			var unit: Dictionary = _add_unit(kind, "enemy", Vector2(tile), -1, 0)
			unit["pursuer"] = true
			unit["state"] = "pursuing"
	for unit in units:
		if str(unit["team"]) == "friendly" and str(unit["state"]) != "evacuated" and Vector2(unit["pos"]).x < pursuit_x - 2.0:
			unit["hp"] = maxf(0.0, float(unit["hp"]) - delta * 10.0)
	for building in buildings:
		if float(building["hp"]) > 0.0 and Vector2(building["pos"]).x < pursuit_x - 3.0:
			building["hp"] = maxf(0.0, float(building["hp"]) - delta * 8.0)
	var threatened_x: float = 72.0
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
	if camp.is_empty() or not road_connected(Vector2(camp["pos"]), Vector2(exit_building["pos"])):
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
	return {"version": SAVE_VERSION, "mission": "rift_escape_01", "payload": _encode_value(payload)}


func load_state(data: Dictionary) -> bool:
	if not _is_number(data.get("version")) or int(data["version"]) != SAVE_VERSION or str(data.get("mission", "")) != "rift_escape_01" or not data.has("payload"):
		return false
	_decode_budget = 120000
	var decoded: Variant = _decode_value(data["payload"], 0)
	if _decode_budget < 0 or not decoded is Dictionary or not _validate_state(decoded):
		return false
	var state: Dictionary = decoded
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
	pursuit_speed = float(state.get("pursuit_speed", 0.035))
	pursuit_start = float(state.get("pursuit_start", 150.0))
	_next_id = int(state["next_id"])
	_jobs = state["jobs"]
	_ai_clock = float(state.get("ai_clock", 0.0))
	_logistics_clock = float(state.get("logistics_clock", 0.0))
	_spawn_clock = float(state.get("spawn_clock", 0.0))
	_food_clock = float(state.get("food_clock", 0.0))
	_last_pursuit_warning = int(state.get("last_pursuit_warning", -1))
	_rng.seed = seed_value
	_rng.state = str(state["rng_state"]).to_int()
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
				for numeric_key in ["speed", "range", "damage", "attack_interval", "cooldown", "repath", "capacity", "job_id", "squad", "escort_id", "haul_site", "evac_origin_id", "evac_destination_id", "path_index"]:
					if item.has(numeric_key) and not _is_number(item[numeric_key]):
						return false
			if key == "camps":
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
