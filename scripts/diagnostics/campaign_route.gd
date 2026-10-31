extends RefCounted
## Canyon public-command route driven by the real controller's clock.
## All waiting, observation, capture and disk continuation belong to the runner.
## This route never advances the simulation or changes its rules/state directly.

var app: Node2D
var observer: Node
var milestones: Array[Dictionary] = []
var abandoned_stock: Dictionary = {}
var west_gate_was_sealed: bool = false
var deliberate_abandonment: bool = false
var loaded_withdrawal_reloaded: bool = false
var funded_exit: Dictionary = {}


func run(controller: Node2D, monitor: Node) -> Dictionary:
	app = controller
	observer = monitor
	milestones.clear()
	abandoned_stock.clear()
	west_gate_was_sealed = false
	deliberate_abandonment = false
	loaded_withdrawal_reloaded = false
	funded_exit.clear()
	if not observer.check(_sim().mission_id == "canyon" and _sim().outcome == "playing" and app.started, "Canyon route starts a real running campaign"):
		return _failed()
	var home_id: int = int(_sim().camps[0].id)
	_production(home_id, "materials")
	_mark("opening", {"home_id": home_id})
	if not await observer.capture("opening", Vector2(18, 21)): return _failed()
	if not await _clear(Vector2(25, 20), 40.0, "clear_highway"): return _failed()
	if not await observer.wait_for(func() -> bool: return _site_captured("cache", Vector2(25, 20)), 60.0, "highway actually captured"):
		return _failed()
	_mark("highway_captured")
	if not await _build("road", Vector2i(26, 21), 40.0, "home_to_middle_road"): return _failed()
	if not await _build("camp", Vector2i(26, 23), 45.0, "middle_camp"): return _failed()
	var middle_id: int = _camp_id_near(Vector2(26, 23))
	if not observer.check(middle_id > 0 and middle_id != home_id, "middle camp is a separately completed real inventory"):
		return _failed()
	if not observer.check(_sim().evacuate_camp(home_id), "home evacuation command accepted"):
		return _failed()
	if not await observer.wait_for(func() -> bool: return _home_crossed(home_id), 200.0, "home convoy and every friendly cross west gate"):
		return _failed()
	west_gate_was_sealed = bool(_sim().seal_choke(0))
	if not observer.check(west_gate_was_sealed and bool(_sim().chokes[0].sealed), "west choke is actually sealed after friendly crossing"):
		return _failed()
	_mark("home_evacuated_and_west_sealed", {"home_deliveries": observer.deliveries_from(home_id)})
	if not await _build("road", Vector2i(29, 24), 30.0, "middle_local_road"): return _failed()
	if not await _build("generator", Vector2i(28, 22), 30.0, "middle_generator"): return _failed()
	if not await _build("workshop", Vector2i(30, 24), 35.0, "middle_workshop"): return _failed()
	# Paid defense protects the longer physical withdrawal. Do not grant a tower.
	if not await _build("tower", Vector2i(25, 20), 30.0, "middle_defense"): return _failed()
	if not await observer.wait_for(func() -> bool: return _powered_at("generator", Vector2(28, 22)) and _powered_at("workshop", Vector2(30, 24)), 30.0, "middle production has real local power"):
		return _failed()
	_production(middle_id, "materials")
	if not await observer.capture("middle_infrastructure", Vector2(29, 22)): return _failed()
	if not await _clear(Vector2(35, 10), 50.0, "clear_materials_branch"): return _failed()
	if not await observer.wait_for(func() -> bool: return _site_captured("quarry", Vector2(35, 10)), 60.0, "quarry branch actually captured"):
		return _failed()
	if not await _build("road", Vector2i(35, 10), 70.0, "quarry_road"): return _failed()
	if not await _clear(Vector2(35, 31), 50.0, "clear_fuel_branch"): return _failed()
	if not await observer.wait_for(func() -> bool: return _site_captured("fuel", Vector2(35, 31)), 60.0, "fuel branch actually captured"):
		return _failed()
	if not await _build("road", Vector2i(35, 31), 70.0, "fuel_road"): return _failed()
	# These economic windows are part of the public strategy, not wall-clock sleeps.
	if not await observer.advance(100.0, "accumulate physically hauled branch stocks"): return _failed()
	if not observer.check(_sim().road_connected(_sim().get_camp(middle_id).pos, Vector2(35, 10)) and _sim().road_connected(_sim().get_camp(middle_id).pos, Vector2(35, 31)), "both captured resource branches have completed local roads"):
		return _failed()
	_mark("both_resource_branches_connected")
	if not await _clear(Vector2(53, 21), 60.0, "clear_forward_cache"): return _failed()
	if not await observer.wait_for(func() -> bool: return _site_captured("cache", Vector2(53, 21)), 60.0, "forward cache actually captured"):
		return _failed()
	if not await _build("road", Vector2i(53, 22), 90.0, "forward_road"): return _failed()
	if not await _build("camp", Vector2i(54, 23), 90.0, "forward_camp"): return _failed()
	var front_id: int = _camp_id_near(Vector2(54, 23))
	if not observer.check(front_id > 0 and front_id != middle_id and _sim().camps.size() >= 3, "forward camp is the third actual camp"):
		return _failed()
	_sim().command_task(_army_ids(), "guard", Vector2(27, 19))
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
	if not await observer.wait_for(func() -> bool: return _forward_stock_ready(front_id) and observer.deliveries_from(middle_id) >= 3, 360.0, "three real middle deliveries and viable forward inventory"):
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
	_mark("middle_deliberately_abandoned", {"stock_left": abandoned_stock.duplicate(true), "middle_deliveries": observer.deliveries_from(middle_id)})
	if not await observer.wait_for(func() -> bool: return _last_truck_arrived(front_id), 70.0, "last loaded truck reaches forward camp"):
		return _failed()
	if not await observer.advance(35.0, "forward arrival and relocation buffer"): return _failed()
	if not await _build("road", Vector2i(57, 23), 25.0, "front_local_road"): return _failed()
	if not await _build("generator", Vector2i(56, 21), 30.0, "front_generator"): return _failed()
	if not await _build("workshop", Vector2i(57, 25), 40.0, "front_workshop"): return _failed()
	if not await observer.wait_for(func() -> bool: return _powered_at("generator", Vector2(56, 21)) and _powered_at("workshop", Vector2(57, 25)), 30.0, "forward workshop actually powered"):
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
	if not await _clear(Vector2(68, 20), 65.0, "clear_exit_approach"): return _failed()
	if not await _build("road", Vector2i(68, 22), 90.0, "exit_power_road"): return _failed()
	if not await _build("generator", Vector2i(68, 22), 45.0, "exit_local_generator"): return _failed()
	if not observer.check(_powered_at("generator", Vector2(68, 22)), "exit generator has real fuel and local road before exit capture"):
		return _failed()
	if not await _clear(Vector2(72, 19), 35.0, "capture_exit_site"): return _failed()
	if not await _build("road", Vector2i(72, 19), 60.0, "exit_construction_road"): return _failed()
	if not await observer.wait_for(func() -> bool: return float(_sim().exit_progress) >= 1.0 and _exit_powered(), 180.0, "funded powered exit actually completes"):
		return _failed()
	funded_exit = _exit_job_record(front_id)
	if not observer.check(not funded_exit.is_empty(), "actual funded exit job records140materials45fuel30supplies"):
		return _failed()
	_mark("exit_funded_and_complete", {"funded_job": funded_exit.duplicate(true)})
	if not await observer.capture("completed_powered_exit", Vector2(72, 19)): return _failed()
	var everyone: Array = []
	for unit: Dictionary in _sim().units:
		if unit.team == "friendly" and float(unit.hp) > 0.0: everyone.append(int(unit.id))
	_sim().command_move(everyone, Vector2(72, 19), true)
	if not await observer.wait_for(func() -> bool: return _sim().outcome == "victory", 90.0, "command truck and four survivors actually reach exit"):
		return _failed()
	if not observer.check(int(_sim().evacuated) >= 4 and _exit_powered() and float(_sim().exit_progress) >= 1.0, "real victory includes completed powered exit and enough evacuees"):
		return _failed()
	_mark("actual_victory", {"evacuated": int(_sim().evacuated)})
	if not await observer.capture("victory", Vector2(72, 19)): return _failed()
	return {
		"success": observer.failures.is_empty() and _sim().outcome == "victory",
		"mission_id": "canyon", "simulated_seconds": float(_sim().time),
		"evacuated": int(_sim().evacuated), "actual_camp_count": _sim().camps.size(),
		"west_gate_was_sealed": west_gate_was_sealed,
		"deliberate_abandonment": deliberate_abandonment,
		"abandoned_stock": abandoned_stock.duplicate(true),
		"loaded_withdrawal_reloaded": loaded_withdrawal_reloaded,
		"home_deliveries": observer.deliveries_from(home_id),
		"middle_deliveries": observer.deliveries_from(middle_id),
		"funded_exit_job": funded_exit.duplicate(true), "exit_powered_at_victory": _exit_powered(),
		"both_resource_sites_captured": _site_captured("quarry", Vector2(35, 10)) and _site_captured("fuel", Vector2(35, 31)),
		"milestones": milestones.duplicate(true), "final_summary": _sim().get_summary()
	}


func _sim() -> RefCounted:
	return app.sim


func _failed() -> Dictionary:
	return {"success": false, "mission_id": "canyon", "simulated_seconds": float(_sim().time), "milestones": milestones.duplicate(true)}


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
		if unit.team == "friendly" and float(unit.hp) > 0.0 and Vector2(unit.pos).x < 21.8: return false
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
	var saved: Dictionary = _sim().save_state()
	for job: Dictionary in Dictionary(saved.get("payload", {})).get("jobs", []):
		if str(job.get("kind", "")) != "exit" or int(job.get("building_id", 0)) != int(_sim().exit_building_id) or int(job.get("source_camp_id", 0)) != front_id: continue
		var costs: Dictionary = job.get("costs", {})
		if bool(job.get("funded", false)) and is_equal_approx(float(costs.get("materials", 0.0)), 140.0) and is_equal_approx(float(costs.get("fuel", 0.0)), 45.0) and is_equal_approx(float(costs.get("supplies", 0.0)), 30.0):
			return {"id": int(job.id), "building_id": int(job.building_id), "source_camp_id": front_id, "funded": true, "done": bool(job.get("done", false)), "costs": costs.duplicate(true)}
	return {}
