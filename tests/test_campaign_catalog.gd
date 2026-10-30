extends SceneTree
## Geography, finite resources and schema contracts, not an AI victory/balance claim.
## Run: ./run.sh --headless -s tests/test_campaign_catalog.gd

const Catalog = preload("res://scripts/campaign_catalog.gd")
const Simulation = preload("res://scripts/campaign_simulation.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_fresh_deterministic_definitions()
	_test_original_canyon()
	_test_legal_routes_and_retreat_cuts()
	_test_distinct_route_decisions()
	_test_finite_resource_floor()
	_test_rejection_is_safe()
	_test_visual_regions()
	print("Campaign catalog checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures:
		printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _test_visual_regions() -> void:
	for value: Variant in ["bad", {"sand":"no-color"}, {"water_rects":[Rect2i(79,39,4,4)]}, {"bridge_rects":[Vector2(30,19)]}, {"bridge_rects":[Rect2i(38,18,3,3)]}]:
		var data: Dictionary = Catalog.mission("delta")
		var before: Dictionary = data.duplicate(true)
		data.visual = value
		_check(not Catalog.validate(data).is_empty(), "invalid visual data cannot advertise a nonexistent bridge or crash color drawing")
		_check(Catalog.mission("delta") == before, "visual validation leaves the stored definition unchanged")


func _test_fresh_deterministic_definitions() -> void:
	_check(Catalog.ids() == ["canyon", "delta", "ridge"], "Three stable mission IDs in campaign order")
	_check(Catalog.mission("unknown").is_empty(), "Unknown ID never silently starts another mission")
	_check(Catalog.route_report("unknown").is_empty(), "Unknown report is empty")
	for mission_id: String in Catalog.ids():
		var first: Dictionary = Catalog.mission(mission_id)
		var second: Dictionary = Catalog.mission(mission_id)
		_check(first == second, mission_id + ": deterministic definitions")
		var errors: Array[String] = Catalog.validate(first)
		_check(errors.is_empty(), mission_id + ": validates: " + str(errors))
		first["camps"][0]["stock"]["materials"] = -99.0
		first["guide"]["landmarks"]["home"] = Vector2(-1, -1)
		_check(Catalog.mission(mission_id) == second, mission_id + ": callers cannot mutate catalog")


func _test_original_canyon() -> void:
	var definition: Dictionary = Catalog.mission()
	var geometry: Dictionary = Catalog.terrain_for(definition)
	var sim: RefCounted = Simulation.new()
	sim.reset(42)
	_check(geometry["terrain"] == sim.terrain, "Canyon terrain remains identical to existing reset")
	_check(geometry["ramps"] == sim.ramps, "Canyon ramps remain identical to existing reset")
	_check(definition["name"] == "裂谷突围" and definition["camps"][0]["pos"] == Vector2(9, 22), "Original title and home")
	_check(definition["camps"][0]["stock"] == {"materials": 220.0, "supplies": 150.0, "fuel": 110.0, "salvage": 45.0, "crude": 0.0}, "Original finite initial stock")
	_check(definition["buildings"].size() == 4 and definition["units"].size() == 8, "Original force and building counts")
	_check(definition["sites"].size() == 5 and definition["chokes"].size() == 2, "Original objective and choke counts")
	var guard_counts: Array = []
	for index: int in range(definition["sites"].size()):
		var site: Dictionary = definition["sites"][index]
		guard_counts.append(site["guards"])
		_check(site["pos"] == sim.sites[index]["pos"] and site["stock"] == sim.sites[index]["stock"], "Original site order/position/stock %d" % index)
	_check(guard_counts == [3, 5, 4, 5, 6], "Original 23 guards in exact groups")
	var original_roads: Dictionary = {}
	for record: Dictionary in definition["roads"]:
		original_roads[record["pos"]] = {"progress": 1.0, "camp_id": 1}
	_check(original_roads == sim.roads, "Original road insertion payload")
	for field: String in ["pursuit_x", "pursuit_eta", "pursuit_speed", "pursuit_start"]:
		_check(float(definition["pacing"][field]) == float(sim.get(field)), "Original pursuit: " + field)


func _test_legal_routes_and_retreat_cuts() -> void:
	for mission_id: String in Catalog.ids():
		var definition: Dictionary = Catalog.mission(mission_id)
		var points: Dictionary = definition["guide"]["landmarks"]
		var geometry: Dictionary = Catalog.terrain_for(definition)
		var report: Dictionary = Catalog.route_report(mission_id)
		for name: String in report["distances"]:
			_check(int(report["distances"][name]) > 0 and int(report["distances"][name]) < 100, mission_id + ": bounded required route " + name)
		for target: String in ["middle_camp", "quarry", "fuel", "front_camp", "exit"]:
			var route: Array[Vector2i] = Catalog.path(definition, Vector2i(points["home"]), Vector2i(points[target]))
			_check(not route.is_empty(), mission_id + ": home can reach " + target)
			var legal: bool = true
			for index: int in range(1, route.size()):
				var previous: Vector2i = route[index - 1]
				var next: Vector2i = route[index]
				if absi(previous.x - next.x) + absi(previous.y - next.y) != 1:
					legal = false
				if geometry["terrain"][previous.y][previous.x] != geometry["terrain"][next.y][next.x] and not (geometry["ramps"].has(previous) and geometry["ramps"].has(next)):
					legal = false
			_check(legal, mission_id + ": route uses adjacent tiles and explicit ramps to " + target)
		# Closing a three-wide gate must physically cut the return journey.
		var west: Array[Vector2i] = _gate_tiles(Vector2i(points["west_gate"]))
		var east: Array[Vector2i] = _gate_tiles(Vector2i(points["east_gate"]))
		_check(Catalog.path(definition, Vector2i(points["home"]), Vector2i(points["middle_camp"]), west).is_empty(), mission_id + ": west seal cuts rear convoy route")
		_check(not Catalog.path(definition, Vector2i(points["middle_camp"]), Vector2i(points["exit"]), west).is_empty(), mission_id + ": west seal preserves forward escape")
		_check(Catalog.path(definition, Vector2i(points["front_camp"]), Vector2i(points["exit"]), east).is_empty(), mission_id + ": east seal can strand a late convoy")
		_check(not Catalog.path(definition, Vector2i(points["exit"]), Vector2i(points["exit_power"]), east).is_empty(), mission_id + ": eastern power remains reachable after seal")
		print("CATALOG ROUTES ", mission_id, " ", report["distances"])


func _test_distinct_route_decisions() -> void:
	var canyon: Dictionary = Catalog.mission("canyon")
	var delta: Dictionary = Catalog.mission("delta")
	var ridge: Dictionary = Catalog.mission("ridge")
	var canyon_distance: Dictionary = Catalog.route_report("canyon")["distances"]
	var delta_distance: Dictionary = Catalog.route_report("delta")["distances"]
	var ridge_distance: Dictionary = Catalog.route_report("ridge")["distances"]
	_check(Catalog.terrain_for(canyon)["terrain"] != Catalog.terrain_for(delta)["terrain"] and Catalog.terrain_for(delta)["terrain"] != Catalog.terrain_for(ridge)["terrain"], "Mission terrain differs")
	_check(delta_distance["middle_camp_to_front_camp"] >= canyon_distance["middle_camp_to_front_camp"] + 10, "Wetland adds a material logistics detour")
	_check(ridge_distance["middle_camp_to_fuel"] + 10 < ridge_distance["middle_camp_to_quarry"], "Ridge oil is much closer to middle camp than high quarry")
	_check(ridge_distance["quarry_to_front_camp"] + 10 < ridge_distance["fuel_to_front_camp"], "Ridge inverts the resource advantage for forward production")
	var wetland_points: Dictionary = delta["guide"]["landmarks"]
	var blocked_west_bridge: Array[Vector2i] = _horizontal_tiles(29, 31, 19)
	var one_bridge_route: Array[Vector2i] = Catalog.path(delta, Vector2i(wetland_points["middle_camp"]), Vector2i(wetland_points["quarry"]), blocked_west_bridge)
	var both_bridges: Array[Vector2i] = blocked_west_bridge.duplicate()
	both_bridges.append_array(_horizontal_tiles(51, 53, 19))
	# The river reaches both gate barriers: there is no accidental shore bypass.
	var west_only: Array[Vector2i] = _horizontal_tiles(51, 53, 19)
	var east_only: Array[Vector2i] = blocked_west_bridge.duplicate()
	_check(not Catalog.path(delta, Vector2i(wetland_points["middle_camp"]), Vector2i(wetland_points["quarry"]), west_only).is_empty(), "Wetland west bridge is a complete legal route")
	_check(not Catalog.path(delta, Vector2i(wetland_points["middle_camp"]), Vector2i(wetland_points["quarry"]), east_only).is_empty(), "Wetland east bridge is a complete legal alternate route")
	_check(not one_bridge_route.is_empty() and one_bridge_route.size() - 1 > delta_distance["middle_camp_to_quarry"], "Losing west crossing increases wetland haul distance")
	_check(Catalog.path(delta, Vector2i(wetland_points["middle_camp"]), Vector2i(wetland_points["quarry"]), both_bridges).is_empty(), "Wetland crossing cut separates the banks")
	var ridge_points: Dictionary = ridge["guide"]["landmarks"]
	var ridge_neck: Array[Vector2i] = _gate_tiles(Vector2i(44, 11))
	var ridge_alternate: Array[Vector2i] = Catalog.path(ridge, Vector2i(ridge_points["quarry"]), Vector2i(ridge_points["front_camp"]), ridge_neck)
	_check(not ridge_alternate.is_empty(), "Ridge has a real valley/east-slope alternative")
	_check(ridge_alternate.size() - 1 >= ridge_distance["quarry_to_front_camp"] + 10, "Ridge neck loss creates a long retreat rather than a cosmetic change")


func _test_finite_resource_floor() -> void:
	for mission_id: String in Catalog.ids():
		var definition: Dictionary = Catalog.mission(mission_id)
		var resources: Dictionary = Catalog.route_report(mission_id)["available_resources"]
		var points: Dictionary = definition["guide"]["landmarks"]
		var network: Dictionary = {}
		for edge: Array in [["home", "middle_camp"], ["middle_camp", "quarry"], ["middle_camp", "fuel"], ["middle_camp", "front_camp"], ["front_camp", "exit"], ["exit", "exit_power"]]:
			for tile: Vector2i in Catalog.path(definition, Vector2i(points[edge[0]]), Vector2i(points[edge[1]])):
				network[tile] = true
		for road: Dictionary in definition["roads"]:
			network.erase(road["pos"])
		# A terrain-path network plus two new camps/workshops and three generators.
		# Actual play also needs local building spurs, food, combat and fuel margin.
		var material_floor: float = float(network.size()) * float(Simulation.BUILD_COSTS["road"]["materials"])
		material_floor += 2.0 * float(Simulation.BUILD_COSTS["camp"]["materials"])
		material_floor += 2.0 * float(Simulation.BUILD_COSTS["workshop"]["materials"])
		material_floor += 3.0 * float(Simulation.BUILD_COSTS["generator"]["materials"])
		material_floor += float(Simulation.BUILD_COSTS["exit"]["materials"])
		var fuel_floor: float = float(Simulation.BUILD_COSTS["exit"]["fuel"]) + 3.0 * float(Simulation.BUILD_COSTS["generator"]["fuel"]) + float(Simulation.EVAC_RESERVES["fuel"])
		var supply_floor: float = float(Simulation.BUILD_COSTS["exit"]["supplies"]) + 2.0 * float(Simulation.BUILD_COSTS["camp"]["supplies"]) + float(Simulation.EVAC_RESERVES["supplies"])
		_check(float(resources["materials"]) + float(resources["salvage"]) >= material_floor + 50.0, mission_id + ": finite material stock exceeds terrain network/setup floor by at least 50")
		_check(float(resources["fuel"]) + float(resources["crude"]) >= fuel_floor + 100.0, mission_id + ": finite fuel reserves leave production/retreat headroom")
		_check(float(resources["supplies"]) >= supply_floor + 100.0, mission_id + ": finite ready rations exceed camp/exit/reserve floor")
		_check(float(definition["camps"][0]["stock"]["materials"]) >= 2.0 * 30.0 + 50.0 + 30.0 + 40.0, mission_id + ": starting cash permits a road/camp/local infrastructure plan before refining")
		_check(float(definition["camps"][0]["stock"]["fuel"]) >= 50.0, mission_id + ": no crude-only generator bootstrap trap")
		print("CATALOG FLOOR ", mission_id, " material floor=", material_floor, " finite material/salvage=", float(resources["materials"]) + float(resources["salvage"]))


func _test_rejection_is_safe() -> void:
	var malformed: Array[Dictionary] = []
	var data: Dictionary = Catalog.mission()
	data["id"] = "canyon/../delta"
	malformed.append(data)
	data = Catalog.mission()
	data["sites"][0]["pos"] = Vector2(NAN, 20)
	malformed.append(data)
	data = Catalog.mission()
	data["units"][0]["pos"] = Vector2(12.5, 20)
	malformed.append(data)
	data = Catalog.mission()
	data["camps"][0]["stock"]["fuel"] = -1.0
	malformed.append(data)
	data = Catalog.mission()
	data["sites"][1]["stock"] = {"diamonds": 500.0}
	malformed.append(data)
	data = Catalog.mission()
	data["sites"][2]["stock"]["crude"] = INF
	malformed.append(data)
	data = Catalog.mission()
	data["sites"][2]["key"] = "quarry"
	malformed.append(data)
	data = Catalog.mission()
	data["sites"][2]["key"] = ["fuel"]
	malformed.append(data)
	data = Catalog.mission()
	data["roads"][0]["camp"] = "missing"
	malformed.append(data)
	data = Catalog.mission()
	data["exit"]["site"] = "missing"
	malformed.append(data)
	data = Catalog.mission()
	data["exit"]["site"] = "quarry"
	malformed.append(data)
	data = Catalog.mission()
	data["sites"][2]["kind"] = "cache"
	malformed.append(data)
	data = Catalog.mission()
	data["sites"][1]["stock"] = {"materials": 420.0}
	malformed.append(data)
	data = Catalog.mission()
	data["units"][0]["main_truck"] = true
	malformed.append(data)
	data = Catalog.mission()
	data["ramp_rects"] = [Rect2i(20, 2, 3, 3)]
	malformed.append(data)
	data = Catalog.mission()
	data["terrain_layers"].append({"rect": Rect2i(79, 20, 3, 3), "value": 0})
	malformed.append(data)
	data = Catalog.mission()
	data["guide"]["landmarks"]["front_camp"] = Vector2(80, 20)
	malformed.append(data)
	data = Catalog.mission()
	data["pacing"]["pursuit_speed"] = "fast"
	malformed.append(data)
	data = Catalog.mission()
	data["pacing"]["spawn_y"] = 90.0
	malformed.append(data)
	data = Catalog.mission()
	data["guide"]["landmarks"]["quarry"] = Vector2(36, 10)
	malformed.append(data)
	data = Catalog.mission()
	data.erase("sites")
	malformed.append(data)
	data = Catalog.mission()
	data["sites"][0] = 5
	malformed.append(data)
	data = Catalog.mission()
	# Keep both heights legal but remove the quarry's only plateau access.
	data["ramp_rects"].remove_at(1)
	malformed.append(data)
	for index: int in range(malformed.size()):
		_check(not Catalog.validate(malformed[index]).is_empty(), "Reject malformed mission %d" % index)
	_check(Catalog.path(Catalog.mission(), Vector2i(-1, 0), Vector2i(9, 22)).is_empty(), "Out-of-map path origin is rejected")
	_check(Catalog.path(Catalog.mission(), Vector2i(9, 22), Vector2i(21, 4)).is_empty(), "Blocked path endpoint is rejected")


func _gate_tiles(center: Vector2i) -> Array[Vector2i]:
	return [center + Vector2i(0, -1), center, center + Vector2i(0, 1)]


func _horizontal_tiles(first: int, last: int, y: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x: int in range(first, last + 1):
		result.append(Vector2i(x, y))
	return result
