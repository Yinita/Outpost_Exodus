extends SceneTree
## Public mission/reset/save contracts and paid construction. --staged selects
## the temporary integration source while the production source is frozen.
const Catalog = preload("res://scripts/campaign_catalog.gd")
const RESET_HASHES: Dictionary = {
	42: "0ed7a12bde699b8c8b3b1f1b590099fdb7a38eefc84b7fc29a6d25c930b993e7",
	7: "163b92af41548048d958614c5d11d5047886632034090f7e4833115ba796c7ea"
}
var simulation_script: Script
var checks: int = 0
var failures: Array[String] = []

# Full player-command routes are opt-in: --route=delta or --route=ridge.
var route_sim: RefCounted
var route_points: Dictionary
var route_mission_id: String = ""
var route_errors: Array[String] = []
var route_sealed_west: bool = false
var route_emergency_used: bool = false
var route_abandoned_stock: Dictionary = {}
var route_delivered_trips: Dictionary = {}
var route_last_stage: String = ""
var route_exit_powered_progress: bool = false
var route_exit_paid_costs: Dictionary = {}
var route_json_checkpointed: bool = false


func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var source: String = "res://work/mission-integration-sim.gd" if args.has("--staged") else "res://scripts/campaign_simulation.gd"
	simulation_script = load(source) as Script
	if simulation_script == null or not simulation_script.can_instantiate():
		push_error("Cannot load mission simulation")
		quit(1)
		return
	_test_original_compatibility()
	_test_atomic_rejection()
	_test_save_identity_binding()
	_test_independent_metadata_and_json_continue()
	_test_paid_construction_and_power()
	_test_real_evacuation_json_continue()
	for argument: String in args:
		if argument.begins_with("--route="):
			_run_route(argument.trim_prefix("--route="))
	print("Campaign variant checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)

func _test_original_compatibility() -> void:
	var sim: RefCounted = simulation_script.new()
	for seed_value: int in RESET_HASHES:
		_check(sim.reset(seed_value), "Default reset accepts original seed")
		_check(JSON.stringify(sim.save_state()).sha256_text() == RESET_HASHES[seed_value], "Canyon complete reset save equals original clone at seed %d" % seed_value)
	_check(sim.save_state()["mission"] == "rift_escape_01", "Canyon retains legacy top-level save tag")
	var old_save: Dictionary = JSON.parse_string(JSON.stringify(sim.save_state()))
	_check(sim.reset(42, "delta") and sim.load_state(old_save), "An old Canyon save can replace a different active mission")
	_check(sim.mission_id == "canyon" and sim.mission_name == "裂谷突围", "Old save restores Canyon identity and title")

func _test_atomic_rejection() -> void:
	var sim: RefCounted = simulation_script.new()
	sim.reset(42, "ridge")
	sim.tick(1.0)
	var before: String = JSON.stringify(sim.save_state())
	var metadata: Dictionary = sim.mission_data
	_check(not sim.reset(5, "missing"), "Unknown reset ID rejects")
	_check(JSON.stringify(sim.save_state()) == before and sim.mission_data == metadata, "Rejected reset changes neither world nor metadata")
	var bad_save: Dictionary = sim.save_state()
	bad_save["mission"] = "missing"
	_check(not sim.load_state(bad_save), "Unknown save mission tag rejects")
	_check(JSON.stringify(sim.save_state()) == before and sim.mission_data == metadata, "Rejected save tag changes neither world nor metadata")
	bad_save = sim.save_state()
	bad_save["mission"] = "wetland_escape_02"
	bad_save["payload"] = {"bad": true}
	_check(not sim.load_state(bad_save), "Known mission with invalid payload rejects")
	_check(JSON.stringify(sim.save_state()) == before and sim.mission_id == "ridge", "Invalid payload does not replace mission identity")

func _test_independent_metadata_and_json_continue() -> void:
	for mission_id: String in ["delta", "ridge"]:
		var sim: RefCounted = simulation_script.new()
		var definition: Dictionary = Catalog.mission(mission_id)
		_check(sim.reset(42, mission_id), mission_id + ": reset accepts")
		_check(sim.mission_name == definition["name"] and sim.objective == definition["objective"], mission_id + ": title/objective belong to mission")
		var exposed: Dictionary = sim.mission_data
		exposed["guide"]["landmarks"]["exit"] = Vector2(-1, -1)
		exposed["pacing"]["spawn_y"] = -100.0
		_check(sim.mission_data == definition, mission_id + ": consumer cannot mutate live mission metadata")
		var home_id: int = int(sim.camps[0]["id"])
		sim.set_production(home_id, "materials")
		var fighters: Array = []
		for unit: Dictionary in sim.units:
			if unit["team"] == "friendly" and unit["kind"] == "rifle": fighters.append(unit["id"])
		sim.command_move(fighters, definition["guide"]["landmarks"]["highway"], true)
		_advance(sim, 12.0)
		var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.save_state()))
		var resumed: RefCounted = simulation_script.new()
		_check(resumed.load_state(saved), mission_id + ": in-progress JSON save loads")
		_check(resumed.mission_id == mission_id and resumed.mission_data == definition, mission_id + ": JSON load restores full catalog metadata")
		_advance(sim, 35.0)
		_advance(resumed, 35.0)
		_check(_equivalent(_core_saved(sim.save_state()), _core_saved(resumed.save_state())), mission_id + ": JSON continuation keeps world state within serialized float precision")
		var stripped: Dictionary = sim.save_state()
		var entries: Array = stripped["payload"]["entries"]
		for index: int in range(entries.size() - 1, -1, -1):
			if entries[index][0] in ["pursuit_speed", "pursuit_start"]: entries.remove_at(index)
		_check(resumed.load_state(stripped), mission_id + ": optional legacy pacing fields may be absent")
		_check(resumed.pursuit_speed == definition["pacing"]["pursuit_speed"] and resumed.pursuit_start == definition["pacing"]["pursuit_start"], mission_id + ": missing pacing uses this mission's defaults")

func _test_save_identity_binding() -> void:
	var live: RefCounted = simulation_script.new()
	live.reset(42, "ridge")
	live.tick(1.0)
	for source_id: String in Catalog.ids():
		var source: RefCounted = simulation_script.new()
		source.reset(7, source_id)
		var valid: Dictionary = source.save_state()
		var marker: Variant = _payload_value(valid, "mission_id")
		_check(marker == source_id if source_id != "canyon" else marker == null, source_id + ": only new missions write payload identity")
		for tag_id: String in Catalog.ids():
			if tag_id == source_id: continue
			var swapped: Dictionary = valid.duplicate(true)
			swapped["mission"] = simulation_script.MISSION_SAVE_TAGS[tag_id]
			_reject_save_unchanged(live, swapped, source_id + " payload with " + tag_id + " known tag")
		if source_id != "canyon":
			var missing: Dictionary = valid.duplicate(true)
			_erase_payload_value(missing, "mission_id")
			_reject_save_unchanged(live, missing, source_id + " missing required identity marker")
		for wrong_marker: Variant in [null, 42, true, ["canyon"], "unknown"]:
			var wrong: Dictionary = valid.duplicate(true)
			_set_payload_value(wrong, "mission_id", wrong_marker)
			_reject_save_unchanged(live, wrong, source_id + " malformed payload identity " + str(wrong_marker))
		var restored: RefCounted = simulation_script.new()
		_check(restored.load_state(JSON.parse_string(JSON.stringify(valid))) and restored.mission_id == source_id, source_id + ": matching identity survives JSON roundtrip")
		if source_id == "canyon":
			var explicit_canyon: Dictionary = valid.duplicate(true)
			_set_payload_value(explicit_canyon, "mission_id", "canyon")
			_check(restored.load_state(explicit_canyon), "Canyon accepts its optional matching identity marker")
			_check(JSON.stringify(restored.save_state()) == JSON.stringify(valid), "Explicit Canyon marker returns to byte-compatible legacy save")

func _reject_save_unchanged(sim: RefCounted, invalid: Dictionary, description: String) -> void:
	var before: String = JSON.stringify(sim.save_state())
	var metadata: Dictionary = sim.mission_data
	_check(not sim.load_state(invalid), "Reject " + description)
	_check(JSON.stringify(sim.save_state()) == before and sim.mission_data == metadata, description + ": rejection leaves live bytes and metadata unchanged")

func _payload_value(save: Dictionary, key: String) -> Variant:
	for entry: Array in save["payload"]["entries"]:
		if entry[0] == key: return entry[1]
	return null

func _set_payload_value(save: Dictionary, key: String, value: Variant) -> void:
	for entry: Array in save["payload"]["entries"]:
		if entry[0] == key:
			entry[1] = value
			return
	save["payload"]["entries"].append([key, value])

func _erase_payload_value(save: Dictionary, key: String) -> void:
	var entries: Array = save["payload"]["entries"]
	for index: int in range(entries.size() - 1, -1, -1):
		if entries[index][0] == key: entries.remove_at(index)

func _test_paid_construction_and_power() -> void:
	for mission_id: String in ["delta", "ridge"]:
		var sim: RefCounted = simulation_script.new()
		sim.reset(42, mission_id)
		var home: Dictionary = sim.camps[0]
		sim.set_production(int(home["id"]), "idle")
		var materials_before: float = float(home["materials"])
		var old_road_count: int = sim.roads.size()
		var road_tile: Vector2i = Vector2i(home["pos"]) + Vector2i(6, 2)
		_check(sim.build("road", road_tile), mission_id + ": player can plan a paid local road")
		_check(is_equal_approx(materials_before - float(home["materials"]), float(sim.roads.size() - old_road_count) * 2.0), mission_id + ": every planned road tile pays unchanged global cost")
		_advance(sim, 25.0)
		_check(sim.roads.has(road_tile) and float(sim.roads[road_tile]["progress"]) == 1.0, mission_id + ": physical builders finish road")
		var generator_tile: Vector2i = Vector2i(home["pos"]) + Vector2i(6, 3)
		materials_before = float(home["materials"])
		var fuel_before: float = float(home["fuel"])
		_check(sim.build("generator", generator_tile), mission_id + ": paid generator order accepted")
		_check(is_equal_approx(materials_before - float(home["materials"]), 30.0) and is_equal_approx(fuel_before - float(home["fuel"]), 5.0), mission_id + ": generator deducts real unchanged materials/fuel")
		_advance(sim, 50.0)
		var finished: bool = false
		for building: Dictionary in sim.buildings:
			if building["kind"] == "generator" and Vector2i(building["pos"]) == generator_tile:
				finished = float(building["progress"]) == 1.0
		_check(finished, mission_id + ": engineer delivers and completes local generator")
		_check(float(home["power_capacity"]) == 24.0, mission_id + ": two real locally connected generators provide 24 power")
		_check(float(home["fuel"]) < fuel_before - 5.0, mission_id + ": running generators consume local fuel")

func _test_real_evacuation_json_continue() -> void:
	for mission_id: String in ["delta", "ridge"]:
		var sim: RefCounted = simulation_script.new()
		sim.reset(42, mission_id)
		var points: Dictionary = sim.mission_data["guide"]["landmarks"]
		var fighters: Array = []
		for unit: Dictionary in sim.units:
			if unit["team"] == "friendly" and unit["kind"] == "rifle": fighters.append(unit["id"])
		sim.command_move(fighters, points["highway"], true)
		_advance(sim, 40.0)
		_check(sim.build("road", Vector2i(points["highway_road"])), mission_id + ": real evacuation route is paid")
		_advance(sim, 40.0)
		_check(sim.build("camp", Vector2i(points["middle_camp"])), mission_id + ": real receiving camp is paid")
		_advance(sim, 45.0)
		_check(sim.camps.size() == 2, mission_id + ": engineer completes receiving camp")
		if sim.camps.size() != 2: continue
		var home_id: int = int(sim.camps[0]["id"])
		var middle_id: int = int(sim.camps[1]["id"])
		# Publicly move the squad out of the loading lane before macro retreat.
		sim.command_task(fighters, "guard", points["middle_camp"] + Vector2(4, -4))
		_advance(sim, 8.0)
		_check(sim.evacuate_camp(home_id), mission_id + ": player can start physical camp evacuation")
		_advance(sim, 15.0)
		_check(sim.get_camp(home_id)["state"] == "packing" and sim.get_unit(sim.main_truck_id)["order"] == "evacuate_transport", mission_id + ": checkpoint contains real active packing/transport")
		var resumed: RefCounted = simulation_script.new()
		_check(resumed.load_state(JSON.parse_string(JSON.stringify(sim.save_state()))), mission_id + ": active evacuation JSON checkpoint loads")
		_advance(sim, 45.0)
		_advance(resumed, 45.0)
		_check(_equivalent(_core_saved(sim.save_state()), _core_saved(resumed.save_state())), mission_id + ": in-flight evacuation continues after JSON load")
		_check(float(resumed.get_camp(middle_id)["materials"]) > 0.0 and float(resumed.get_camp(middle_id)["fuel"]) > 0.0, mission_id + ": actual truck unload delivers material and fuel")

func _advance(sim: RefCounted, seconds: float) -> void:
	for index: int in range(ceili(seconds / 0.1)):
		sim.tick(0.1)

func _core_saved(value: Dictionary) -> Dictionary:
	var copy: Dictionary = value.duplicate(true)
	var entries: Array = copy["payload"]["entries"]
	for index: int in range(entries.size() - 1, -1, -1):
		if entries[index][0] in ["effects", "messages"]: entries.remove_at(index)
	return copy

func _equivalent(first: Variant, second: Variant) -> bool:
	if (first is int or first is float) and (second is int or second is float):
		return is_equal_approx(float(first), float(second))
	if first is Dictionary and second is Dictionary:
		if first.size() != second.size(): return false
		for key: Variant in first:
			if not second.has(key) or not _equivalent(first[key], second[key]): return false
		return true
	if first is Array and second is Array:
		if first.size() != second.size(): return false
		for index: int in range(first.size()):
			if not _equivalent(first[index], second[index]): return false
		return true
	return first == second

func _run_route(selected_mission: String) -> void:
	route_sim = simulation_script.new()
	route_mission_id = selected_mission
	route_errors.clear()
	route_sealed_west = false
	route_emergency_used = false
	route_abandoned_stock.clear()
	route_delivered_trips.clear()
	route_last_stage = ""
	route_exit_powered_progress = false
	route_exit_paid_costs.clear()
	route_json_checkpointed = false
	if not route_sim.reset(42, route_mission_id):
		_check(false, "Unknown public route mission: " + route_mission_id)
		return
	route_points = route_sim.mission_data.guide.landmarks
	var home_id: int = route_sim.camps[0].id
	route_sim.set_production(home_id, "materials")
	_route_clear(route_points.highway,40.0)
	_route_construct("road",Vector2i(route_points.highway_road),40.0)
	_route_construct("camp",Vector2i(route_points.middle_camp),45.0)
	if route_sim.camps.size()<2:
		_route_finish("NO MIDDLE CAMP")
		return
	var middle_id: int = route_sim.camps[1].id
	if route_mission_id == "ridge":
		# The southern cache sits beside this mission's depot loading approach.
		route_sim.command_task(_route_army(),"guard",route_points.middle_camp+Vector2(4,-4))
		_route_advance(8.0)
	if not route_sim.evacuate_camp(home_id): route_errors.append("Home evacuation rejected")
	_route_wait(func() -> bool:
		if route_sim.get_camp(home_id).state!="abandoned": return false
		if route_sim.get_unit(route_sim.main_truck_id).get("order","")=="evacuate_transport": return false
		for unit: Dictionary in route_sim.units:
			if unit.team=="friendly" and Vector2(unit.pos).x<21.8: return false
		return true, 200.0, "home convoy and everyone cross west gate")
	route_sealed_west=route_sim.seal_choke(0)
	if not route_sealed_west: route_errors.append("West gate rejected after actual crossing")
	_route_construct("road",Vector2i(route_points.middle_road),30.0)
	_route_construct("generator",Vector2i(route_points.middle_camp+Vector2(2,-1)),30.0)
	_route_construct("workshop",Vector2i(route_points.middle_camp+Vector2(4,1)),35.0)
	# Paid local defense covers the longer, physical middle-camp withdrawal.
	_route_construct("tower",Vector2i(route_points.middle_camp+Vector2(-1,-3)),30.0)
	route_sim.set_production(middle_id,"materials")
	_route_clear(route_points.quarry,50.0)
	_route_construct("road",Vector2i(route_points.quarry),70.0)
	_route_clear(route_points.fuel,50.0)
	_route_construct("road",Vector2i(route_points.fuel),70.0)
	_route_advance(100.0)
	print("MIDDLE STOCK ",route_sim.get_camp(middle_id)," time=",route_sim.time)
	_route_clear(route_points.forward_cache,60.0)
	_route_construct("road",Vector2i(route_points.forward_road),130.0)
	_route_construct("camp",Vector2i(route_points.front_camp),100.0)
	if route_sim.camps.size()<3 or not route_errors.is_empty():
		_route_finish("NO FORWARD CAMP")
		return
	var front_id: int = route_sim.camps[2].id
	if float(route_sim.get_camp(middle_id).materials)<340.0:
		_route_wait(func() -> bool: return float(route_sim.get_camp(middle_id).materials)>=340.0,120.0,"produce retreat funding before packing")
	route_sim.command_task(_route_army(),"guard",route_points.middle_camp+Vector2(1,-4))
	if not route_sim.evacuate_camp(middle_id): route_errors.append("Middle evacuation rejected")
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(route_sim.save_state()))
	var continued: RefCounted = simulation_script.new()
	if continued.load_state(checkpoint):
		route_sim = continued
		route_json_checkpointed = true
	else:
		route_errors.append("Real in-flight route JSON checkpoint rejected")
	_route_wait(func() -> bool:
		var front: Dictionary=route_sim.get_camp(front_id)
		return float(front.materials)>=320.0 and float(front.supplies)>=35.0 and float(front.fuel)>=45.0 and float(front.get("crude",0.0))>=50.0 and int(route_delivered_trips.get(middle_id,0))>=3,
		450.0,"three or more delivered loads and viable forward stocks")
	if not route_errors.is_empty():
		_route_finish("MIDDLE TRANSPORT FAILED")
		return
	print("RECEIVED BEFORE ABANDON ",route_sim.get_camp(front_id)," trips=",route_delivered_trips.get(middle_id,0)," time=",route_sim.time)
	if route_sim.get_camp(middle_id).state=="packing":
		for key: String in ["materials","supplies","fuel","salvage","crude"]:
			route_abandoned_stock[key]=float(route_sim.get_camp(middle_id).get(key,0.0))
		route_emergency_used=route_sim.evacuate_camp(middle_id)
		if not route_emergency_used: route_errors.append("Emergency abandonment rejected")
		route_sim.command_move(_route_army(),route_points.front_camp+Vector2(4,-3),false)
	else:
		route_errors.append("No remaining rear stock to deliberately abandon")
	_route_wait(func() -> bool:
		var truck: Dictionary=route_sim.get_unit(route_sim.main_truck_id)
		return not truck.is_empty() and str(truck.get("order",""))!="evacuate_transport" and Vector2(truck.pos).distance_to(Vector2(route_sim.get_camp(front_id).pos))<3.0,
		70.0,"last loaded truck arrives at forward camp")
	_route_advance(35.0)
	print("ABANDONED INVENTORY ",route_abandoned_stock," time=",route_sim.time)
	print("FRONT ",route_sim.get_camp(front_id))
	_route_construct("road",Vector2i(route_points.front_road),25.0)
	_route_construct("generator",Vector2i(route_points.front_camp+Vector2(2,-2)),30.0)
	_route_construct("workshop",Vector2i(route_points.front_camp+Vector2(3,2)),40.0)
	route_sim.set_production(front_id,"fuel")
	_route_wait(func() -> bool: return float(route_sim.get_camp(front_id).fuel)>=85.0,140.0,"refine transported crude to fuel margin")
	route_sim.set_production(front_id,"supplies")
	_route_wait(func() -> bool: return float(route_sim.get_camp(front_id).supplies)>=80.0,150.0,"produce rations before exit construction")
	route_sim.set_production(front_id,"idle")
	# Stop outside capture radius, fund and finish local exit power first.
	_route_clear(route_points.exit+Vector2(-4,1),65.0)
	_route_construct("road",Vector2i(route_points.exit_power),90.0)
	_route_construct("generator",Vector2i(route_points.exit_power),45.0)
	print("EXIT PREPARATION STOCK ",route_sim.get_camp(front_id)," time=",route_sim.time)
	_route_clear(route_points.exit,35.0)
	_route_construct("road",Vector2i(route_points.exit),60.0)
	_route_wait(func() -> bool: return float(route_sim.exit_progress)>=1.0,180.0,"actual funded powered exit finishes")
	var everyone: Array=[]
	for unit: Dictionary in route_sim.units:
		if unit.team=="friendly": everyone.append(unit.id)
	route_sim.command_move(everyone,route_points.exit,true)
	_route_wait(func() -> bool: return route_sim.outcome=="victory",90.0,"command truck and survivors arrive")
	_route_finish("COMPLETE")

func _route_advance(seconds: float) -> void:
	for _index in range(ceili(seconds/0.1)):
		if route_sim.outcome!="playing" or not route_errors.is_empty(): break
		var exit_before: Dictionary = _route_exit_building()
		var started_before: bool = bool(exit_before.get("construction_started", false))
		var last_camp: Dictionary = route_sim.camps.back()
		var stock_before: Dictionary = {"materials": float(last_camp.materials), "fuel": float(last_camp.fuel), "supplies": float(last_camp.supplies)}
		route_sim.tick(0.1)
		var exit_after: Dictionary = _route_exit_building()
		if not started_before and bool(exit_after.get("construction_started", false)):
			for resource: String in ["materials", "fuel", "supplies"]:
				route_exit_paid_costs[resource] = float(stock_before[resource]) - float(last_camp[resource])
		if float(exit_after.get("progress", 0.0)) > 0.0 and float(exit_after.get("progress", 0.0)) < 1.0 and bool(exit_after.get("powered", false)) and float(exit_after.get("required_power", 0.0)) == 6.0:
			route_exit_powered_progress = true
		var truck: Dictionary=route_sim.get_unit(route_sim.main_truck_id)
		if truck.is_empty(): continue
		var stage: String=str(truck.get("haul_stage",""))
		if route_last_stage=="outbound" and stage!="outbound" and Dictionary(truck.get("cargo",{})).is_empty():
			var origin_id: int=int(truck.get("evac_origin_id",0))
			route_delivered_trips[origin_id]=int(route_delivered_trips.get(origin_id,0))+1
		route_last_stage=stage

func _route_wait(condition: Callable, timeout: float, description: String) -> void:
	var deadline: float=float(route_sim.time)+timeout
	while not condition.call() and float(route_sim.time)<deadline and route_sim.outcome=="playing" and route_errors.is_empty():
		_route_advance(0.1)
	if not condition.call():
		route_errors.append("Timed out: "+description)
		var diagnostic_path: String=ProjectSettings.globalize_path("res://work/variant-" + route_mission_id + "-route-failure.json")
		DirAccess.make_dir_recursive_absolute(diagnostic_path.get_base_dir())
		var diagnostic: FileAccess=FileAccess.open(diagnostic_path,FileAccess.WRITE)
		if diagnostic!=null:
			diagnostic.store_string(JSON.stringify(route_sim.save_state()))
			diagnostic.close()
		print("DIAGNOSTIC_SAVE written=",diagnostic!=null," path=",diagnostic_path)
		var truck: Dictionary=route_sim.get_unit(route_sim.main_truck_id)
		if not truck.is_empty():
			print("TRUCK_DIAGNOSTIC pos=",truck.pos," target=",truck.target," path_index=",truck.get("path_index",0)," pathlen=",Array(truck.get("path",[])).size()," nav_wait=",truck.get("nav_wait",0.0)," haul_stage=",truck.get("haul_stage","")," HP=",truck.hp," cargo=",truck.get("cargo",{}))
			for camp: Dictionary in route_sim.camps:
				print("TRUCK_CAMP_DISTANCE id=",camp.id," state=",camp.state," pos=",camp.pos," distance=",Vector2(truck.pos).distance_to(Vector2(camp.pos)))
	print("WAIT ",description," reached=",condition.call()," time=",route_sim.time)

func _route_army() -> Array:
	var result: Array=[]
	for unit: Dictionary in route_sim.units:
		if unit.team=="friendly" and unit.kind=="rifle": result.append(unit.id)
	return result

func _route_clear(position: Vector2, seconds: float) -> void:
	if not route_errors.is_empty(): return
	route_sim.command_move(_route_army(),position,true)
	_route_advance(seconds)
	print("CLEAR ",position," time=",route_sim.time," people=",route_sim.get_summary().people," outcome=",route_sim.outcome)

func _route_construct(kind: String, tile: Vector2i, seconds: float) -> void:
	if not route_errors.is_empty(): return
	var accepted: bool=route_sim.build(kind,tile)
	print("BUILD ",kind," ",tile," accepted=",accepted," time=",route_sim.time," materials=",route_sim.get_summary().materials)
	if not accepted: route_errors.append("Rejected construction: %s %s (%s)" % [kind,tile,route_sim.messages.back()])
	_route_advance(seconds)

func _route_finish(label: String) -> void:
	if route_sim.camps.size()<3: route_errors.append("Fewer than three actual camps")
	for kind: String in ["quarry","fuel"]:
		var found: bool=false
		for site: Dictionary in route_sim.sites:
			if site.kind==kind and bool(site.captured): found=true
		if not found: route_errors.append("Uncaptured branch: "+kind)
	if not route_sealed_west: route_errors.append("No real sealed rear choke")
	if not route_emergency_used: route_errors.append("No explicit urgent abandonment")
	var abandoned_total: float=0.0
	for amount: Variant in route_abandoned_stock.values(): abandoned_total+=float(amount)
	if abandoned_total<=0.0: route_errors.append("No actual inventory deliberately left behind")
	if route_sim.outcome!="victory" or float(route_sim.exit_progress)<1.0 or int(route_sim.evacuated)<4:
		route_errors.append("Actual exit and survivor victory conditions not reached")
	print(label," SUMMARY ",route_sim.get_summary())
	print("CAMPS ",route_sim.camps)
	print("DELIVERED TRIPS ",route_delivered_trips)
	print("ABANDONED INVENTORY ",route_abandoned_stock)
	print("PENDING BUILDINGS ",route_sim.buildings.filter(func(b:Dictionary)->bool:return float(b.progress)<1.0))
	print("MESSAGES ",route_sim.messages)
	for failure: String in route_errors: printerr("PLAYTHROUGH FAILURE: ",failure)
	if not route_exit_powered_progress: route_errors.append("No observed real 6-power exit construction")
	if float(route_exit_paid_costs.get("materials", 0.0)) < 139.99 or float(route_exit_paid_costs.get("fuel", 0.0)) < 44.99 or float(route_exit_paid_costs.get("supplies", 0.0)) < 29.99:
		route_errors.append("Actual exit construction did not deduct its unchanged local costs")
	if not route_json_checkpointed: route_errors.append("Full route never continued from real JSON checkpoint")
	var evidence: Dictionary = {"mission": route_mission_id, "label": label, "summary": route_sim.get_summary(), "sealed_west": route_sealed_west, "emergency_abandonment": route_emergency_used, "abandoned_stock": route_abandoned_stock, "delivered_trips": route_delivered_trips, "exit_paid_costs": route_exit_paid_costs, "exit_powered_progress": route_exit_powered_progress, "json_checkpointed": route_json_checkpointed, "failures": route_errors}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work"))
	var evidence_file: FileAccess = FileAccess.open("res://work/variant-" + route_mission_id + "-evidence.json", FileAccess.WRITE)
	if evidence_file != null: evidence_file.store_string(JSON.stringify(evidence, "\t"))
	var state_file: FileAccess = FileAccess.open("res://work/variant-" + route_mission_id + "-final-state.json", FileAccess.WRITE)
	if state_file != null: state_file.store_string(JSON.stringify(route_sim.save_state()))
	_check(route_errors.is_empty(), route_mission_id + ": full public-command route reaches funded/powered victory: " + str(route_errors))

func _route_exit_building() -> Dictionary:
	for building: Dictionary in route_sim.buildings:
		if int(building["id"]) == int(route_sim.exit_building_id): return building
	return {}
