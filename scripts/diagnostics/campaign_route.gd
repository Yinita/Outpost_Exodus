extends RefCounted
## Selected-mission public-command route driven by the real controller's clock.
## All waiting, observation, capture and disk continuation belong to the runner.
## This route never advances the simulation or changes its rules/state directly.
const Catalog = preload("res://scripts/campaign_catalog.gd")

var app: Node2D
var observer: Node
var milestones: Array[Dictionary] = []
var abandoned_stock: Dictionary = {}
var west_gate_was_sealed: bool = false
var deliberate_abandonment: bool = false
var loaded_withdrawal_reloaded: bool = false
var funded_exit: Dictionary = {}
var route_config: Dictionary = {}


static func configuration(mission_id: String) -> Dictionary:
	# Landmarks are shared with the actual mission and its established public
	# route tests. Only strategy windows/commands vary; rules and costs do not.
	var mission: Dictionary = Catalog.mission(mission_id)
	if mission.is_empty(): return {}
	var points: Dictionary = mission.guide.landmarks.duplicate(true)
	return {
		"mission_id": mission_id, "landmarks": points,
		"opening_capture": Vector2(points.home) + Vector2(9, -1),
		"middle_generator": Vector2(points.middle_camp) + Vector2(2, -1),
		"middle_workshop": Vector2(points.middle_camp) + Vector2(4, 1),
		"middle_tower": Vector2(points.middle_camp) + Vector2(-1, -3),
		"middle_capture": Vector2(points.middle_camp) + Vector2(3, -1),
		"middle_guard": Vector2(points.middle_camp) + Vector2(1, -4),
		"home_loading_guard": Vector2(points.middle_camp) + Vector2(4, -4),
		"home_loading_guard_seconds": 8.0 if mission_id == "ridge" else 0.0,
		"forward_road_seconds": 90.0 if mission_id == "canyon" else 130.0,
		"forward_camp_seconds": 90.0 if mission_id == "canyon" else 100.0,
		"packing_material_reserve": 0.0 if mission_id == "canyon" else 340.0,
		"withdrawal_timeout": 360.0 if mission_id == "canyon" else 450.0,
		"relocate_army_after_abandonment": mission_id != "canyon",
		"front_rally": Vector2(points.front_camp) + Vector2(4, -3),
		"front_generator": Vector2(points.front_camp) + Vector2(2, -2),
		"front_workshop": Vector2(points.front_camp) + Vector2(3, 2),
		"exit_approach": Vector2(points.exit) + Vector2(-4, 1)
	}


func run(controller: Node2D, monitor: Node) -> Dictionary:
	app = controller
	observer = monitor
	milestones.clear()
	abandoned_stock.clear()
	west_gate_was_sealed = false
	deliberate_abandonment = false
	loaded_withdrawal_reloaded = false
	funded_exit.clear()
	route_config = configuration(str(_sim().mission_id))
	if not observer.check(not route_config.is_empty() and _sim().outcome == "playing" and app.started, "selected route starts a supported real running campaign"):
		return _failed()
	var points: Dictionary = _sim().mission_data.guide.landmarks.duplicate(true)
	if not observer.check(points == route_config.landmarks, "route landmarks match the actual selected mission"):
		return _failed()
	var home_id: int = int(_sim().camps[0].id)
	observer.set_frame_phase("opening")
	_production(home_id, "materials")
	_mark("opening", {"home_id": home_id})
	if not await observer.capture("opening", route_config.opening_capture): return _failed()
	if not await _clear(points.highway, 40.0, "clear_highway"): return _failed()
	if not await observer.wait_for(func() -> bool: return _site_captured("cache", points.highway), 60.0, "highway actually captured"):
		return _failed()
	_mark("highway_captured")
	if not await _build("road", Vector2i(points.highway_road), 40.0, "home_to_middle_road"): return _failed()
	if not await _build("camp", Vector2i(points.middle_camp), 45.0, "middle_camp"): return _failed()
	var middle_id: int = _camp_id_near(points.middle_camp)
	if not observer.check(middle_id > 0 and middle_id != home_id, "middle camp is a separately completed real inventory"):
		return _failed()
	if float(route_config.home_loading_guard_seconds) > 0.0:
		# Ridge's nearby southern cache otherwise crowds the depot approach.
		_sim().command_task(_army_ids(), "guard", route_config.home_loading_guard)
		if not await observer.advance(float(route_config.home_loading_guard_seconds), "guard Ridge home loading approach"): return _failed()
	observer.set_frame_phase("home_transfer")
	if not observer.check(_sim().evacuate_camp(home_id), "home evacuation command accepted"):
		return _failed()
	if not await observer.wait_for(func() -> bool: return _home_crossed(home_id), 200.0, "home convoy and every friendly cross west gate"):
		return _failed()
	west_gate_was_sealed = bool(_sim().seal_choke(0))
	if not observer.check(west_gate_was_sealed and bool(_sim().chokes[0].sealed), "west choke is actually sealed after friendly crossing"):
		return _failed()
	_mark("home_evacuated_and_west_sealed", {"home_deliveries": observer.deliveries_from(home_id)})
	observer.set_frame_phase("middle_economy")
	if not await _build("road", Vector2i(points.middle_road), 30.0, "middle_local_road"): return _failed()
	if not await _build("generator", Vector2i(route_config.middle_generator), 30.0, "middle_generator"): return _failed()
	if not await _build("workshop", Vector2i(route_config.middle_workshop), 35.0, "middle_workshop"): return _failed()
	# Paid defense protects the longer physical withdrawal. Do not grant a tower.
	if not await _build("tower", Vector2i(route_config.middle_tower), 30.0, "middle_defense"): return _failed()
	if not await observer.wait_for(func() -> bool: return _powered_at("generator", route_config.middle_generator) and _powered_at("workshop", route_config.middle_workshop), 30.0, "middle production has real local power"):
		return _failed()
	_production(middle_id, "materials")
	if not await observer.capture("middle_infrastructure", route_config.middle_capture): return _failed()
	if not await _clear(points.quarry, 50.0, "clear_materials_branch"): return _failed()
	if not await observer.wait_for(func() -> bool: return _site_captured("quarry", points.quarry), 60.0, "quarry branch actually captured"):
		return _failed()
	if not await _build("road", Vector2i(points.quarry), 70.0, "quarry_road"): return _failed()
	if not await _clear(points.fuel, 50.0, "clear_fuel_branch"): return _failed()
	if not await observer.wait_for(func() -> bool: return _site_captured("fuel", points.fuel), 60.0, "fuel branch actually captured"):
		return _failed()
	if not await _build("road", Vector2i(points.fuel), 70.0, "fuel_road"): return _failed()
	# These economic windows are part of the public strategy, not wall-clock sleeps.
	if not await observer.advance(100.0, "accumulate physically hauled branch stocks"): return _failed()
	if not observer.check(_sim().road_connected(_sim().get_camp(middle_id).pos, points.quarry) and _sim().road_connected(_sim().get_camp(middle_id).pos, points.fuel), "both captured resource branches have completed local roads"):
		return _failed()
	_mark("both_resource_branches_connected")
	if not await _clear(points.forward_cache, 60.0, "clear_forward_cache"): return _failed()
	if not await observer.wait_for(func() -> bool: return _site_captured("cache", points.forward_cache), 60.0, "forward cache actually captured"):
		return _failed()
	if not await _build("road", Vector2i(points.forward_road), float(route_config.forward_road_seconds), "forward_road"): return _failed()
	if not await _build("camp", Vector2i(points.front_camp), float(route_config.forward_camp_seconds), "forward_camp"): return _failed()
	var front_id: int = _camp_id_near(points.front_camp)
	if not observer.check(front_id > 0 and front_id != middle_id and _sim().camps.size() >= 3, "forward camp is the third actual camp"):
		return _failed()
	var reserve: float = float(route_config.packing_material_reserve)
	if reserve > 0.0 and _stock(middle_id, "materials") < reserve:
		if not await observer.wait_for(func() -> bool: return _stock(middle_id, "materials") >= reserve, 120.0, "produce retreat funding before packing"):
			return _failed()
	observer.set_frame_phase("middle_withdrawal")
	_sim().command_task(_army_ids(), "guard", route_config.middle_guard)
	if not observer.check(_sim().evacuate_camp(middle_id), "middle evacuation command accepted"):
		return _failed()
	if not await observer.wait_for(func() -> bool: return _loaded_withdrawal(middle_id), 160.0, "middle withdrawal carries an actual outbound parcel"):
		return _failed()
	_mark("loaded_middle_withdrawal", {"origin_id": middle_id, "destination_id": front_id})
	loaded_withdrawal_reloaded = observer.save_and_reload("loaded_middle_withdrawal")
	if not loaded_withdrawal_reloaded: return _failed()
	# load_state replaces the live dictionaries: retain IDs and re-read everything.
	if not observer.check(_loaded_withdrawal(middle_id), "real disk continuation retains packing and loaded outbound truck"):
		return _failed()
	if not await observer.capture("withdrawal_after_disk_load", Vector2(_sim().get_unit(_sim().main_truck_id).pos)):
		return _failed()
	if not await observer.wait_for(func() -> bool: return _forward_stock_ready(front_id) and observer.deliveries_from(middle_id) >= 3, float(route_config.withdrawal_timeout), "three real middle deliveries and viable forward inventory"):
		return _failed()
	if not observer.check(_sim().get_camp(middle_id).state == "packing", "middle retains real stock to deliberately abandon"):
		return _failed()
	for resource: String in ["materials", "supplies", "fuel", "salvage", "crude"]:
		abandoned_stock[resource] = float(_sim().get_camp(middle_id).get(resource, 0.0))
	var left: float = 0.0
	for amount: Variant in abandoned_stock.values(): left += float(amount)
	if not observer.check(left > 0.0, "urgent abandonment leaves actual unshipped inventory"):
		return _failed()
	deliberate_abandonment = bool(_sim().evacuate_camp(middle_id))
	if not observer.check(deliberate_abandonment and _sim().get_camp(middle_id).state == "abandoned", "second evacuation command deliberately abandons middle camp"):
		return _failed()
	if bool(route_config.relocate_army_after_abandonment):
		_sim().command_move(_army_ids(), route_config.front_rally, false)
	_mark("middle_deliberately_abandoned", {"stock_left": abandoned_stock.duplicate(true), "middle_deliveries": observer.deliveries_from(middle_id)})
	if not await observer.wait_for(func() -> bool: return _last_truck_arrived(front_id), 70.0, "last loaded truck reaches forward camp"):
		return _failed()
	observer.set_frame_phase("forward_rebuild")
	if not await observer.advance(35.0, "forward arrival and relocation buffer"): return _failed()
	if not await _build("road", Vector2i(points.front_road), 25.0, "front_local_road"): return _failed()
	if not await _build("generator", Vector2i(route_config.front_generator), 30.0, "front_generator"): return _failed()
	if not await _build("workshop", Vector2i(route_config.front_workshop), 40.0, "front_workshop"): return _failed()
	if not await observer.wait_for(func() -> bool: return _powered_at("generator", route_config.front_generator) and _powered_at("workshop", route_config.front_workshop), 30.0, "forward workshop actually powered"):
		return _failed()
	_production(front_id, "fuel")
	if not await observer.wait_for(func() -> bool: return _stock(front_id, "fuel") >= 85.0, 140.0, "transported crude is refined into exit fuel reserve"):
		return _failed()
	_production(front_id, "supplies")
	if not await observer.wait_for(func() -> bool: return _stock(front_id, "supplies") >= 80.0, 150.0, "forward workshop produces real exit rations"):
		return _failed()
	_production(front_id, "idle")
	_mark("forward_exit_reserves", {"camp": _sim().get_camp(front_id).duplicate(true)})
	# Stop outside capture radius and finish nearby power before the automatic
	# paid exit job can consume the actual140materials/45fuel/30supplies.
	observer.set_frame_phase("exit_build")
	if not await _clear(route_config.exit_approach, 65.0, "clear_exit_approach"): return _failed()
	if not await _build("road", Vector2i(points.exit_power), 90.0, "exit_power_road"): return _failed()
	if not await _build("generator", Vector2i(points.exit_power), 45.0, "exit_local_generator"): return _failed()
	if not observer.check(_powered_at("generator", points.exit_power), "exit generator has real fuel and local road before exit capture"):
		return _failed()
	if not await _clear(points.exit, 35.0, "capture_exit_site"): return _failed()
	if not await _build("road", Vector2i(points.exit), 60.0, "exit_construction_road"): return _failed()
	if not await observer.wait_for(func() -> bool: return float(_sim().exit_progress) >= 1.0 and _exit_powered(), 180.0, "funded powered exit actually completes"):
		return _failed()
	funded_exit = _exit_job_record(front_id)
	if not observer.check(not funded_exit.is_empty(), "actual funded exit job records140materials45fuel30supplies"):
		return _failed()
	_mark("exit_funded_and_complete", {"funded_job": funded_exit.duplicate(true)})
	observer.set_frame_phase("exit_arrival")
	if not await observer.capture("completed_powered_exit", points.exit): return _failed()
	var everyone: Array = []
	for unit: Dictionary in _sim().units:
		if unit.team == "friendly" and float(unit.hp) > 0.0: everyone.append(int(unit.id))
	_sim().command_move(everyone, points.exit, true)
	if not await observer.wait_for(func() -> bool: return _sim().outcome == "victory", 90.0, "command truck and four survivors actually reach exit"):
		return _failed()
	if not observer.check(int(_sim().evacuated) >= 4 and _exit_powered() and float(_sim().exit_progress) >= 1.0, "real victory includes completed powered exit and enough evacuees"):
		return _failed()
	_mark("actual_victory", {"evacuated": int(_sim().evacuated)})
	if not await observer.capture("victory", points.exit): return _failed()
	return {
		"success": observer.failures.is_empty() and _sim().outcome == "victory",
		"mission_id": str(_sim().mission_id), "simulated_seconds": float(_sim().time),
		"evacuated": int(_sim().evacuated), "actual_camp_count": _sim().camps.size(),
		"west_gate_was_sealed": west_gate_was_sealed,
		"deliberate_abandonment": deliberate_abandonment,
		"abandoned_stock": abandoned_stock.duplicate(true),
		"loaded_withdrawal_reloaded": loaded_withdrawal_reloaded,
		"home_deliveries": observer.deliveries_from(home_id),
		"middle_deliveries": observer.deliveries_from(middle_id),
		"funded_exit_job": funded_exit.duplicate(true), "exit_powered_at_victory": _exit_powered(),
		"both_resource_sites_captured": _site_captured("quarry", points.quarry) and _site_captured("fuel", points.fuel),
		"milestones": milestones.duplicate(true), "final_summary": _sim().get_summary()
	}


func _sim() -> RefCounted:
	return app.sim


func _failed() -> Dictionary:
	return {"success": false, "mission_id": str(_sim().mission_id), "simulated_seconds": float(_sim().time), "milestones": milestones.duplicate(true)}


func _mark(label: String, details: Dictionary = {}) -> void:
	var recorded: Dictionary = details.duplicate(true)
	recorded["label"] = label
	recorded["simulation_time"] = float(_sim().time)
	milestones.append(recorded)
	observer.event(label, details)


func _production(camp_id: int, recipe: String) -> void:
	app.focus_camp(camp_id)
	_sim().set_production(camp_id, recipe)
	_mark("production_" + recipe, {"camp_id": camp_id})


func _army_ids() -> Array:
	var result: Array = []
	for unit: Dictionary in _sim().units:
		if unit.team == "friendly" and unit.kind == "rifle" and float(unit.hp) > 0.0: result.append(int(unit.id))
	return result


func _clear(position: Vector2, seconds: float, label: String) -> bool:
	var ids: Array = _army_ids()
	if not observer.check(not ids.is_empty(), label + " has a living rifle squad"): return false
	_sim().command_move(ids, position, true)
	_mark(label, {"target": [position.x, position.y], "army_ids": ids.duplicate()})
	return await observer.advance(seconds, label)


func _build(kind: String, tile: Vector2i, minimum_seconds: float, label: String) -> bool:
	var result: Dictionary = _sim().try_build(kind, tile)
	if not observer.check(bool(result.get("ok", false)), label + ": " + str(result.get("message", "construction rejected"))): return false
	var position: Vector2 = result.get("position", Vector2(tile))
	var road_tiles: Array = Array(result.get("road_tiles", [])).duplicate()
	_mark(label + "_ordered", {"kind": kind, "tile": [tile.x, tile.y], "source_camp_id": int(result.get("camp_id", 0)), "costs": Dictionary(result.get("costs", {})).duplicate(true)})
	if not await observer.advance(minimum_seconds, label + " minimum construction window"): return false
	var completed: Callable = func() -> bool: return _road_complete(road_tiles) if kind == "road" else _building_complete(kind, position)
	if not await observer.wait_for(completed, 120.0, label + " actual completion"): return false
	_mark(label + "_complete")
	return true


func _road_complete(tiles: Array) -> bool:
	if tiles.is_empty(): return false
	for value: Variant in tiles:
		var tile: Vector2i = Vector2i(value)
		if not _sim().roads.has(tile) or float(_sim().roads[tile].get("progress", 0.0)) < 1.0: return false
	return true


func _building_at(kind: String, position: Vector2) -> Dictionary:
	for building: Dictionary in _sim().buildings:
		if str(building.kind) == kind and float(building.hp) > 0.0 and Vector2(building.pos).distance_to(position) < 0.2: return building
	return {}


func _building_complete(kind: String, position: Vector2) -> bool:
	var building: Dictionary = _building_at(kind, position)
	return not building.is_empty() and float(building.progress) >= 1.0


func _powered_at(kind: String, position: Vector2) -> bool:
	var building: Dictionary = _building_at(kind, position)
	return not building.is_empty() and float(building.progress) >= 1.0 and bool(building.get("powered", false))


func _camp_id_near(position: Vector2) -> int:
	for camp: Dictionary in _sim().camps:
		if Vector2(camp.pos).distance_to(position) < 0.2: return int(camp.id)
	return 0


func _site_captured(kind: String, position: Vector2) -> bool:
	for site: Dictionary in _sim().sites:
		if str(site.kind) == kind and Vector2(site.pos).distance_to(position) < 0.2: return bool(site.captured)
	return false


func _home_crossed(home_id: int) -> bool:
	if _sim().get_camp(home_id).get("state", "") != "abandoned": return false
	if _sim().get_unit(_sim().main_truck_id).get("order", "") == "evacuate_transport": return false
	for unit: Dictionary in _sim().units:
		if unit.team == "friendly" and float(unit.hp) > 0.0 and Vector2(unit.pos).x < float(route_config.landmarks.west_gate.x) + 0.8: return false
	return true


func _loaded_withdrawal(origin_id: int) -> bool:
	var truck: Dictionary = _sim().get_unit(_sim().main_truck_id)
	if _sim().get_camp(origin_id).get("state", "") != "packing" or truck.is_empty(): return false
	if truck.get("order", "") != "evacuate_transport" or int(truck.get("evac_origin_id", 0)) != origin_id or truck.get("haul_stage", "") != "outbound": return false
	var weight: float = 0.0
	for amount: Variant in Dictionary(truck.get("cargo", {})).values(): weight += float(amount)
	return weight > 0.0


func _stock(camp_id: int, resource: String) -> float:
	return float(_sim().get_camp(camp_id).get(resource, 0.0))


func _forward_stock_ready(front_id: int) -> bool:
	return _stock(front_id, "materials") >= 320.0 and _stock(front_id, "supplies") >= 35.0 and _stock(front_id, "fuel") >= 45.0 and _stock(front_id, "crude") >= 50.0


func _last_truck_arrived(front_id: int) -> bool:
	var truck: Dictionary = _sim().get_unit(_sim().main_truck_id)
	return not truck.is_empty() and truck.get("order", "") != "evacuate_transport" and Vector2(truck.pos).distance_to(Vector2(_sim().get_camp(front_id).pos)) < 3.0


func _exit_powered() -> bool:
	for building: Dictionary in _sim().buildings:
		if int(building.id) == int(_sim().exit_building_id):
			return float(building.hp) > 0.0 and float(building.progress) >= 1.0 and bool(building.get("powered", false))
	return false


func _exit_job_record(front_id: int) -> Dictionary:
	# Public serialized state retains actual paid job records, including completed
	# exit work. Reading it neither pays resources nor calls the power allocator.
	return extract_exit_job(_sim().save_state(), front_id, int(_sim().exit_building_id))


static func serialized_dictionary(value: Variant) -> Dictionary:
	# Version1 encodes Dictionary as tagged entries to preserve typed keys.
	# Decode one string-field map only; nested values retain their encoded form.
	if not value is Dictionary or value.get("$type") != "Dictionary" or not value.get("entries") is Array: return {}
	var result: Dictionary = {}
	for pair: Variant in value.entries:
		if not pair is Array or pair.size() != 2 or not pair[0] is String or result.has(pair[0]): return {}
		result[pair[0]] = pair[1]
	return result


static func extract_exit_job(saved: Dictionary, front_id: int, exit_id: int) -> Dictionary:
	var payload: Dictionary = serialized_dictionary(saved.get("payload"))
	var jobs: Variant = payload.get("jobs", [])
	if not jobs is Array: return {}
	for raw: Variant in jobs:
		var job: Dictionary = serialized_dictionary(raw)
		if job.get("kind") != "exit" or not _saved_id(job.get("building_id"), exit_id) or not _saved_id(job.get("source_camp_id"), front_id): continue
		var complete: bool = true
		for flag: String in ["funded", "delivered", "done"]:
			if not job.get(flag) is bool or not bool(job[flag]): complete = false
		if not complete: continue
		var costs: Dictionary = serialized_dictionary(job.get("costs"))
		if costs.size() != 3: continue
		var exact: bool = true
		for key: String in ["materials", "fuel", "supplies"]:
			var value: Variant = costs.get(key)
			var expected: float = float({"materials": 140.0, "fuel": 45.0, "supplies": 30.0}[key])
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value) - expected) > 0.000001: exact = false
		var job_id: Variant = job.get("id")
		if exact and (job_id is int or job_id is float) and is_finite(float(job_id)) and float(job_id) > 0.0 and float(job_id) == floorf(float(job_id)):
			return {"id": int(job.id), "building_id": exit_id, "source_camp_id": front_id, "funded": true, "delivered": true, "done": true, "costs": costs.duplicate(true)}
	return {}


static func _saved_id(value: Variant, expected: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0 and float(value) == float(expected)
