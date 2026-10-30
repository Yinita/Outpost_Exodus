extends SceneTree
## Mission-aware guide checks. Paid openings use real commands and construction;
## later phases are explicitly focused fixtures, never victory-playthrough claims.
## Run: ./run.sh --headless --script res://tests/test_mission_guide.gd

const Simulation = preload("res://scripts/campaign_simulation.gd")
const Guide = preload("res://scripts/campaign_guide.gd")
const Catalog = preload("res://scripts/campaign_catalog.gd")

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_binding_and_persistence()
	for mission: String in Catalog.ids():
		_test_focused_targets(mission)
		_test_actual_paid_opening(mission)
	print("Mission guide checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures:
		printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _new_sim(mission: String) -> Variant:
	var sim: Variant = Simulation.new()
	_check(bool(sim.reset(42, mission)), mission + " initializes")
	return sim


func _fighters(sim: Variant, engineer: bool = false) -> Array:
	var result: Array = []
	for unit: Dictionary in sim.units:
		if unit["team"] == "friendly" and (unit["kind"] == "rifle" or (engineer and unit["kind"] == "engineer")):
			result.append(int(unit["id"]))
	return result


func _site(sim: Variant, kind: String, position: Vector2) -> Dictionary:
	for site: Dictionary in sim.sites:
		if site["kind"] == kind and Vector2(site["pos"]).distance_to(position) < 0.01:
			return site
	return {}


func _target(guide: Variant, step: int, position: Vector2, description: String) -> void:
	var hint: Dictionary = guide.get_hint()
	_check(int(hint["step"]) == step and Vector2(hint["target"]).distance_to(position) < 0.01, description)


func _wait_for(sim: Variant, condition: Callable, timeout: float) -> bool:
	for tick: int in range(ceili(timeout / 0.1)):
		if bool(condition.call()):
			return true
		if sim.outcome != "playing":
			return false
		sim.tick(0.1)
	return bool(condition.call())


func _test_actual_paid_opening(mission: String) -> void:
	var sim: Variant = _new_sim(mission)
	var data: Dictionary = sim.mission_data
	var points: Dictionary = data["guide"]["landmarks"]
	var guide: Variant = Guide.new()
	guide.reset()
	var before: String = JSON.stringify(sim.save_state())
	guide.update(sim, _fighters(sim, true))
	_target(guide, 1, points["highway"], mission + " selected squad points to its actual highway cache")
	_check(before == JSON.stringify(sim.save_state()), mission + " initial guide update is read-only")
	sim.command_move(_fighters(sim), points["highway"], true)
	var highway: Dictionary = _site(sim, "cache", points["highway"])
	if not _wait_for(sim, func() -> bool: return bool(highway["captured"]), 90.0):
		_check(false, mission + " real combat captures the opening cache")
		return
	guide.update(sim)
	_target(guide, 2, points["highway_road"], mission + " real capture reveals its connecting road target")
	var home: Dictionary = sim.camps[0]
	var materials_before: float = float(home["materials"])
	if not bool(sim.build("road", Vector2i(points["highway_road"]))):
		_check(false, mission + " opening road is a legal paid order")
		return
	_check(float(home["materials"]) < materials_before, mission + " opening road spends real local material")
	guide.update(sim)
	_target(guide, 2, points["highway_road"], mission + " planned road remains incomplete guidance")
	if not _wait_for(sim, func() -> bool: return sim.road_connected(home["pos"], points["highway_road"]), 120.0):
		_check(false, mission + " road reaches the initial marker")
		return
	var extension_needed: bool = not sim.road_connected(home["pos"], points["middle_camp"])
	if ["canyon", "delta"].has(mission):
		_check(extension_needed, mission + " real partial road exposes the marker-versus-camp reachability gap")
	if extension_needed:
		var pending_before: String = JSON.stringify(sim.save_state())
		guide.update(sim)
		_target(guide, 2, points["middle_camp"], mission + " partial road focuses the remaining camp extension")
		_check(pending_before == JSON.stringify(sim.save_state()), mission + " partial-road recovery remains read-only")
	if not _wait_for(sim, func() -> bool: return sim.road_connected(home["pos"], points["highway_road"]) and sim.road_connected(home["pos"], points["middle_camp"]), 120.0):
		_check(false, mission + " workers actually finish the connecting road")
		return
	guide.update(sim)
	_target(guide, 3, points["middle_camp"], mission + " completed road reveals its middle camp target")
	materials_before = float(home["materials"])
	if not bool(sim.build("camp", Vector2i(points["middle_camp"]))):
		_check(false, mission + " middle camp is a legal paid order")
		return
	_check(float(home["materials"]) < materials_before, mission + " middle camp spends real local material")
	guide.update(sim)
	_target(guide, 3, points["middle_camp"], mission + " guide waits at the actual unfinished camp")
	_check(sim.camps.size() == 1, mission + " unfinished camp has no inventory")
	if not _wait_for(sim, func() -> bool: return sim.camps.size() == 2, 120.0):
		_check(false, mission + " engineer actually completes the middle camp")
		return
	guide.update(sim)
	_target(guide, 4, home["pos"], mission + " empty finished camp prompts physical withdrawal from home")
	_check(float(sim.camps[1]["materials"]) == 0.0, mission + " new camp does not invent startup material")
	print("PASS paid opening ", mission, " t=", sim.time)


func _fixture_road(sim: Variant, from: Vector2, to: Vector2, camp_id: int) -> void:
	# Focused late-phase setup: only public arrays are edited; no jobs or victory
	# are synthesized. The paid opening above separately verifies actual work.
	for tile: Vector2i in Catalog.path(sim.mission_data, Vector2i(from), Vector2i(to)):
		sim.roads[tile] = {"progress": 1.0, "camp_id": camp_id}


func _fixture_utilities(sim: Variant, camp: Dictionary) -> void:
	for building: Dictionary in sim.buildings:
		if ["generator", "workshop"].has(building["kind"]):
			building["camp_id"] = int(camp["id"])
			building["pos"] = Vector2(camp["pos"]) + (Vector2(2, -1) if building["kind"] == "generator" else Vector2(4, 1))
			building["progress"] = 1.0
			building["powered"] = true
			_fixture_road(sim, camp["pos"], building["pos"], int(camp["id"]))


func _test_focused_targets(mission: String) -> void:
	var sim: Variant = _new_sim(mission)
	var points: Dictionary = sim.mission_data["guide"]["landmarks"]
	var guide: Variant = Guide.new()
	var camp: Dictionary = sim.camps[0]
	camp["pos"] = points["middle_camp"]
	camp["materials"] = 2000.0
	camp["fuel"] = 200.0
	_fixture_utilities(sim, camp)
	guide.update(sim)
	var quarry: Dictionary = _site(sim, "quarry", points["quarry"])
	var fuel: Dictionary = _site(sim, "fuel", points["fuel"])
	for preference: String in ["north", "south"]:
		guide.observe("branch", {"kind": preference})
		var before: String = JSON.stringify(sim.save_state())
		guide.update(sim)
		var expected: Dictionary = quarry if preference == "north" else fuel
		_target(guide, 6, expected["pos"], mission + " legacy " + preference + " preference maps to its resource kind")
		_check(String(guide.get_hint()["title"]).contains(String(expected["name"])), mission + " branch title names the actual site")
		_check(String(guide.get_hint()["text"]).begins_with(String(sim.mission_data["guide"]["branch_text"])), mission + " branch explanation uses the mission geography")
		_check(before == JSON.stringify(sim.save_state()), mission + " branch guidance does not mutate simulation")
	guide.observe("clear", {"target": points["quarry"]})
	_check(guide.save_state()["preferred_branch"] == "north", mission + " quarry click infers material preference regardless of map direction")
	guide.observe("move", {"target": points["fuel"]})
	_check(guide.save_state()["preferred_branch"] == "south", mission + " fuel click infers fuel preference regardless of map direction")
	quarry["captured"] = true
	fuel["captured"] = true
	_fixture_road(sim, camp["pos"], quarry["pos"], int(camp["id"]))
	_fixture_road(sim, camp["pos"], fuel["pos"], int(camp["id"]))
	guide.update(sim)
	_target(guide, 7, points["forward_cache"], mission + " branch completion points to the actual forward cache")
	var forward_site: Dictionary = _site(sim, "cache", points["forward_cache"])
	forward_site["captured"] = true
	guide.update(sim)
	_target(guide, 7, points["forward_road"], mission + " forward road uses its mission landmark")
	var front_extension_seen: bool = false
	var near_marker: Vector2i = Vector2i(points["forward_road"]) + Vector2i(-2, 0)
	for tile: Vector2i in Catalog.path(sim.mission_data, Vector2i(camp["pos"]), near_marker):
		sim.roads[tile] = {"progress": 1.0, "camp_id": int(camp["id"])}
		if sim.road_connected(camp["pos"], points["forward_road"]) and sim.road_connected(camp["pos"], forward_site["pos"]) and not sim.road_connected(camp["pos"], points["front_camp"]):
			guide.update(sim)
			_target(guide, 7, points["front_camp"], mission + " partial forward connection focuses the remaining camp extension")
			front_extension_seen = true
			break
	_check(front_extension_seen, mission + " focused fixture exercises the forward-marker reachability gap")
	_fixture_road(sim, camp["pos"], forward_site["pos"], int(camp["id"]))
	_fixture_road(sim, camp["pos"], points["forward_road"], int(camp["id"]))
	guide.update(sim)
	_target(guide, 7, points["front_camp"], mission + " forward camp uses its mission landmark")
	camp["pos"] = points["front_camp"]
	_fixture_utilities(sim, camp)
	guide.update(sim)
	_target(guide, 10, points["exit"], mission + " operational forward camp points to the actual exit")
	var exit_building: Dictionary = {}
	for building: Dictionary in sim.buildings:
		if building["kind"] == "exit":
			exit_building = building
	exit_building["construction_started"] = true
	exit_building["powered"] = false
	_site(sim, "exit", points["exit"])["captured"] = true
	_fixture_road(sim, camp["pos"], points["exit"], int(camp["id"]))
	guide.update(sim)
	_target(guide, 10, points["exit_power"], mission + " exit power suggestion uses its mission landmark")
	exit_building["progress"] = 1.0
	exit_building["powered"] = true
	guide.update(sim)
	_target(guide, 11, points["exit"], mission + " finished exit focuses on its actual arrival area")
	_check(not bool(guide.get_hint()["complete"]) and sim.outcome == "playing", mission + " fixture completion is never reported as mission victory")
	_test_focused_gate(mission)
	print("PASS focused guide fixtures ", mission)


func _test_focused_gate(mission: String) -> void:
	var sim: Variant = _new_sim(mission)
	var points: Dictionary = sim.mission_data["guide"]["landmarks"]
	var camp: Dictionary = sim.camps[0]
	camp["pos"] = points["middle_camp"]
	camp["materials"] = 2000.0
	# Remove local utilities so the optional seal hint is not superseded.
	for building: Dictionary in sim.buildings:
		if ["generator", "workshop"].has(building["kind"]):
			building["hp"] = 0.0
	for unit: Dictionary in sim.units:
		if unit["team"] == "friendly":
			unit["pos"] = points["middle_camp"]
	# Choke array order is not a permission key: use the real rear gate.
	sim.chokes.reverse()
	var guide: Variant = Guide.new()
	var before: String = JSON.stringify(sim.save_state())
	guide.update(sim)
	_target(guide, 5, points["west_gate"], mission + " safe optional sealing targets the actual rear gate after reordering")
	_check(String(guide.get_hint()["title"]).contains("封住后关"), mission + " optional seal requires actual safe positions")
	_check(before == JSON.stringify(sim.save_state()), mission + " optional seal hint never seals or spends resources")
	var friendly: Dictionary = sim.get_unit(int(sim.main_truck_id))
	friendly["pos"] = Vector2(points["west_gate"]) + Vector2(-1, 0)
	guide.update(sim)
	_check(not String(guide.get_hint()["title"]).contains("封住后关"), mission + " friend behind the actual rear gate suppresses optional sealing")


func _test_binding_and_persistence() -> void:
	var guide: Variant = Guide.new()
	var canyon: Variant = _new_sim("canyon")
	guide.update(canyon)
	guide.observe("branch", {"kind": "south"})
	guide.observe("production")
	guide.dismiss()
	var legacy: Dictionary = guide.save_state()
	legacy.erase("mission_id")
	var restored: Variant = Guide.new()
	_check(bool(restored.load_state(JSON.parse_string(JSON.stringify(legacy)))), "legacy v1 guide state without mission id loads")
	restored.update(canyon)
	_check(restored.save_state()["preferred_branch"] == "south", "legacy Canyon guide retains its route preference")
	var delta: Variant = _new_sim("delta")
	restored.update(delta)
	var state: Dictionary = restored.save_state()
	_check(state["mission_id"] == "delta" and state["preferred_branch"] == "any" and state["observed"].is_empty(), "same seed and clock in another mission clears old route facts")
	_check(not bool(restored.get_hint()["visible"]), "automatic mission binding preserves hidden user preference")
	restored.observe("branch", {"kind": "north"})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(restored.save_state()))
	var loaded: Variant = Guide.new()
	_check(bool(loaded.load_state(saved)), "mission-specific guide state loads after JSON roundtrip")
	loaded.update(delta)
	_check(loaded.save_state()["preferred_branch"] == "north", "same mission and seed preserve saved route facts")
	for invalid_id: Variant in ["unknown", "", 4, null, {"id": "delta"}]:
		var invalid: Dictionary = saved.duplicate(true)
		invalid["mission_id"] = invalid_id
		var before: String = JSON.stringify(loaded.save_state())
		_check(not bool(loaded.load_state(invalid)), "malformed mission binding is rejected")
		_check(before == JSON.stringify(loaded.save_state()), "malformed mission binding rejection is atomic")
	var ridge: Variant = _new_sim("ridge")
	loaded.update(ridge)
	_check(loaded.save_state()["mission_id"] == "ridge" and loaded.save_state()["preferred_branch"] == "any", "second same-seed mission change clears saved preference")
