extends SceneTree
## Guide checks against the actual first-mission simulation and public commands.
## Run: Godot --headless --path . --script res://tests/test_guide.gd

const Simulation = preload("res://scripts/campaign_simulation.gd")
const Guide = preload("res://scripts/campaign_guide.gd")

var failures: Array[String] = []
var checks: int = 0
var delivered_trips: Dictionary = {}
var last_haul_stage: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulation_script: Script = Simulation
	var guide_script: Script = Guide
	if not simulation_script.can_instantiate() or not guide_script.can_instantiate():
		printerr("Guide suite cannot run: simulation or guide failed to compile")
		quit(1)
		return
	var cases: Array[Callable] = [_test_read_only_observation, _test_persistence_and_bad_states]
	if OS.get_cmdline_user_args().has("--quick"):
		print("SKIP full mission in explicitly requested --quick run")
	else:
		cases.append(_test_actual_mission_progression)
	for test_case: Callable in cases:
		var previous_failures: int = failures.size()
		test_case.call()
		print("%s %s" % ["PASS" if failures.size() == previous_failures else "FAIL", test_case.get_method()])
	print("Guide checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures:
		printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _new_sim() -> Variant:
	var sim: Variant = Simulation.new()
	sim.reset(42)
	return sim


func _fighters(sim: Variant, include_engineer: bool = false) -> Array:
	var result: Array = []
	for unit: Dictionary in sim.units:
		if String(unit.get("team", "")) == "friendly" and (String(unit.get("kind", "")) == "rifle" or (include_engineer and String(unit.get("kind", "")) == "engineer")):
			result.append(int(unit["id"]))
	return result


func _advance(sim: Variant, seconds: float) -> void:
	for index: int in range(ceili(seconds / 0.1)):
		sim.tick(0.1)
		var truck: Dictionary = sim.get_unit(int(sim.main_truck_id))
		if not truck.is_empty():
			var stage: String = String(truck.get("haul_stage", ""))
			if last_haul_stage == "outbound" and stage != "outbound" and Dictionary(truck.get("cargo", {})).is_empty():
				var origin: int = int(truck.get("evac_origin_id", 0))
				delivered_trips[origin] = int(delivered_trips.get(origin, 0)) + 1
			last_haul_stage = stage
		if String(sim.outcome) != "playing":
			break


func _wait_for(sim: Variant, condition: Callable, timeout: float, description: String) -> bool:
	var deadline: float = float(sim.time) + timeout
	for tick: int in range(ceili(timeout / 0.1) + 1):
		if bool(condition.call()) or float(sim.time) >= deadline or String(sim.outcome) != "playing": break
		_advance(sim, 0.1)
	var reached: bool = bool(condition.call())
	_check(reached, "real mission reaches " + description)
	print("GUIDE_ROUTE wait ", description, " reached=", reached, " t=", sim.time)
	return reached


func _clear(sim: Variant, target: Vector2, seconds: float) -> void:
	sim.command_move(_fighters(sim), target, true)
	_advance(sim, seconds)


func _construct(sim: Variant, kind: String, tile: Vector2i, seconds: float) -> void:
	_check(bool(sim.build(kind, tile)), "real mission accepts %s at %s" % [kind, str(tile)])
	_advance(sim, seconds)


func _step(guide: Variant) -> int:
	return int(guide.get_hint()["step"])


func _test_read_only_observation() -> void:
	var sim: Variant = _new_sim()
	var guide: Variant = Guide.new()
	guide.reset()
	var before: String = JSON.stringify(sim.save_state())
	guide.update(sim)
	var hint: Dictionary = guide.get_hint()
	_check(int(hint["step"]) == 1 and not bool(hint["complete"]), "fresh game starts with an incomplete squad/road-point hint")
	_check(bool(hint["visible"]) and String(hint["action"]) == "focus", "fresh hint is visible and has a non-mutating focus action")
	_check(Vector2(hint["target"]).x < 20.0, "before selection the focus locates actual friendly squad members")
	guide.observe("clear", {"captured": true})
	guide.observe("build", {"kind": "camp", "complete": true})
	guide.observe("evacuate", {"complete": true})
	guide.update(sim, _fighters(sim, true), int(sim.camps[0]["id"]))
	hint = guide.get_hint()
	_check(int(hint["step"]) == 1, "observing UI clicks cannot pretend real capture/construction/evacuation happened")
	_check(Vector2(hint["target"]).distance_to(Vector2(25.0, 20.0)) < 0.1, "four selected squad members reveal the real road-point target")
	_check(JSON.stringify(sim.save_state()) == before, "guide update and observe do not mutate simulation, consume resources or issue orders")
	guide.dismiss()
	_check(not bool(guide.get_hint()["visible"]), "dismiss hides the guide without changing completion")
	guide.observe("resume")
	_check(bool(guide.get_hint()["visible"]), "resume restores an existing guide without resetting the route")
	guide.reset(false)
	guide.update(sim)
	_check(not bool(guide.get_hint()["visible"]), "disabled guide stays hidden while reading current simulation")
	guide.observe("show")
	_check(bool(guide.get_hint()["visible"]), "show restores a disabled guide")


func _test_persistence_and_bad_states() -> void:
	var sim: Variant = _new_sim()
	var guide: Variant = Guide.new()
	guide.reset()
	guide.update(sim, _fighters(sim, true))
	guide.observe("branch", {"kind": "south"})
	guide.observe("production")
	guide.dismiss()
	var encoded: String = JSON.stringify(guide.save_state())
	var decoded: Variant = JSON.parse_string(encoded)
	_check(decoded is Dictionary, "guide state is JSON serializable")
	var restored: Variant = Guide.new()
	_check(bool(restored.load_state(decoded)), "JSON guide state loads")
	_check(not bool(restored.get_hint()["visible"]), "hidden preference survives JSON roundtrip")
	_check(Vector2(restored.get_hint()["target"]).distance_to(Vector2(25.0, 20.0)) < 0.1, "cached focus target is restored as Vector2")
	_check(String(restored.save_state()["preferred_branch"]) == "south", "player route preference survives save/load")
	var valid: Dictionary = restored.save_state()
	var malformed: Array[Dictionary] = []
	var candidate: Dictionary = valid.duplicate(true)
	candidate["version"] = 999
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate.erase("dismissed")
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["enabled"] = "yes"
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["last_sim_time"] = NAN
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["preferred_branch"] = "teleport"
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["observed"] = ["build", "build"]
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["hint"]["target"] = [-1.0, 20.0]
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["hint"]["target"] = [INF, 20.0]
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["hint"]["target"] = [81.0, 20.0]
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["hint"]["step"] = 1.5
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["hint"]["action"] = "evacuate"
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["hint"]["complete"] = true
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["extra"] = {"unexpected": "state"}
	malformed.append(candidate)
	candidate = valid.duplicate(true)
	candidate["hint"]["extra"] = 1
	malformed.append(candidate)
	for invalid: Dictionary in malformed:
		var before: String = JSON.stringify(restored.save_state())
		_check(not bool(restored.load_state(invalid)), "malformed guide state is rejected")
		_check(JSON.stringify(restored.save_state()) == before, "bad guide load is atomic and leaves all live fields unchanged")
	var external: Dictionary = restored.get_hint()
	external["step"] = 11
	_check(_step(restored) == 1, "get_hint returns a defensive copy")
	restored.observe("show")
	restored.update(sim)
	_check(bool(restored.get_hint()["visible"]) and _step(restored) == 1, "loaded hidden guide can resume against unchanged real simulation")


func _test_actual_mission_progression() -> void:
	# This is the same public-command route documented in test_mission_playthrough.
	# No inventories, enemy HP, terrain, pursuit timing or outcomes are injected.
	var sim: Variant = _new_sim()
	var guide: Variant = Guide.new()
	delivered_trips.clear()
	last_haul_stage = ""
	guide.reset()
	guide.update(sim)
	var home_id: int = int(sim.camps[0]["id"])
	sim.set_production(home_id, "materials")
	_clear(sim, Vector2(25.0, 20.0), 40.0)
	guide.update(sim)
	_check(_step(guide) == 2, "actual combat and capture advance to road construction")
	print("GUIDE_ROUTE road point captured t=", sim.time)
	_check(bool(sim.build("road", Vector2i(26, 21))), "first connecting road is accepted")
	guide.update(sim)
	_check(_step(guide) == 2, "planned but unfinished road does not satisfy connectivity")
	guide.dismiss()
	_advance(sim, 40.0)
	guide.update(sim)
	_check(_step(guide) == 3 and not bool(guide.get_hint()["visible"]), "hidden guide still follows actual road completion")
	guide.observe("show")
	_check(bool(sim.build("camp", Vector2i(26, 23))), "middle camp real construction is accepted")
	guide.update(sim)
	_check(_step(guide) == 3 and sim.camps.size() == 1, "an unfinished camp does not become an inventory or completed milestone")
	_advance(sim, 45.0)
	_check(sim.camps.size() == 2, "middle camp actually finishes")
	if sim.camps.size() < 2:
		return
	var middle_id: int = int(sim.camps[1]["id"])
	guide.update(sim, [], middle_id)
	_check(float(sim.camps[1]["materials"]) == 0.0 and float(sim.get_summary()["materials"]) > 70.0, "new camp is empty despite stock elsewhere")
	_check(_step(guide) == 4, "empty middle camp is guided to physical evacuation, not unfunded construction")
	guide.observe("evacuate", {"camp_id": home_id})
	guide.update(sim, [], middle_id)
	_check(_step(guide) == 4, "an evacuation UI observation alone does not create delivered funds")
	_check(bool(sim.evacuate_camp(home_id)), "real home evacuation starts")
	_advance(sim, 1.0)
	guide.update(sim)
	_check(_step(guide) == 4, "just-started packing is not treated as delivered inventory")
	guide.dismiss()
	if not _wait_for(sim, func() -> bool:
		if String(sim.get_camp(home_id).state) != "abandoned": return false
		if String(sim.get_unit(int(sim.main_truck_id)).get("order", "")) == "evacuate_transport": return false
		for unit: Dictionary in sim.units:
			if unit.team == "friendly" and Vector2(unit.pos).x < 21.8: return false
		return true, 199.0, "home convoy and all friendlies crossing west gate"):
		return
	guide.update(sim)
	_check(_step(guide) == 5, "real truck deliveries enable local infrastructure guidance")
	print("GUIDE_ROUTE first evacuation delivered t=", sim.time)
	var saved_guide: Dictionary = JSON.parse_string(JSON.stringify(guide.save_state()))
	var resumed: Variant = Guide.new()
	_check(bool(resumed.load_state(saved_guide)), "mid-route hidden guide reloads")
	resumed.update(sim)
	_check(_step(resumed) == 5 and not bool(resumed.get_hint()["visible"]), "resume neither replays the opening nor unhides itself")
	resumed.observe("resume")
	guide = resumed
	_check(bool(sim.seal_choke(0)), "real west choke can be sealed after the evacuation")
	_construct(sim, "road", Vector2i(29, 24), 30.0)
	_construct(sim, "generator", Vector2i(28, 22), 30.0)
	guide.update(sim)
	_check(_step(guide) == 5, "generator alone does not pretend a workshop exists")
	_construct(sim, "workshop", Vector2i(30, 24), 35.0)
	# Match the public route's paid defense before the longer physical withdrawal.
	_construct(sim, "tower", Vector2i(25, 20), 30.0)
	sim.set_production(middle_id, "materials")
	guide.observe("branch", {"kind": "south"})
	guide.update(sim)
	_check(_step(guide) == 6 and Vector2(guide.get_hint()["target"]).y > 20.0, "player can prefer the southern resource branch")
	guide.observe("branch", {"kind": "north"})
	guide.update(sim)
	_check(_step(guide) == 6 and Vector2(guide.get_hint()["target"]).y < 20.0, "branch order can change without locking input or simulation")
	_clear(sim, Vector2(35.0, 10.0), 50.0)
	guide.update(sim)
	_check(_step(guide) == 6, "capture without a hauling road keeps the resource logistics hint")
	_construct(sim, "road", Vector2i(35, 10), 70.0)
	_clear(sim, Vector2(35.0, 31.0), 50.0)
	_construct(sim, "road", Vector2i(35, 31), 70.0)
	_advance(sim, 100.0)
	guide.update(sim)
	_check(_step(guide) == 7, "both real branch connections lead to eastern advance")
	print("GUIDE_ROUTE resource branches connected t=", sim.time)
	_clear(sim, Vector2(53.0, 21.0), 60.0)
	_construct(sim, "road", Vector2i(53, 22), 90.0)
	_construct(sim, "camp", Vector2i(54, 23), 90.0)
	_check(sim.camps.size() >= 3, "forward camp really exists")
	if sim.camps.size() < 3:
		return
	guide.update(sim)
	_check(_step(guide) == 8, "empty eastern camp first needs real rear transfers")
	var front_id: int = int(sim.camps[2]["id"])
	sim.command_task(_fighters(sim), "guard", Vector2(27, 19))
	_check(bool(sim.evacuate_camp(middle_id)), "real middle evacuation starts")
	if not _wait_for(sim, func() -> bool:
		var front: Dictionary = sim.get_camp(front_id)
		return float(front.materials) >= 320.0 and float(front.supplies) >= 35.0 and float(front.fuel) >= 45.0 and float(front.get("crude", 0.0)) >= 50.0 and int(delivered_trips.get(middle_id, 0)) >= 3,
		360.0, "three or more physically delivered loads and viable forward inventories"):
		return
	_check(String(sim.get_camp(middle_id).get("state", "")) == "packing", "funded forward camp still has real rear inventory available to abandon")
	if String(sim.get_camp(middle_id).get("state", "")) == "packing":
		guide.update(sim)
		_check(_step(guide) == 8 and String(guide.get_hint()["text"]).contains("未装车物资"), "ongoing real rear evacuation explains the urgent-abandon cargo tradeoff")
		var abandoned_total: float = 0.0
		for key: String in ["materials", "supplies", "fuel", "salvage", "crude"]:
			abandoned_total += float(sim.get_camp(middle_id).get(key, 0.0))
		_check(abandoned_total > 0.0, "urgent abandonment deliberately leaves actual unshipped inventory behind")
		_check(bool(sim.evacuate_camp(middle_id)), "expert route may urgently abandon remaining raw stock")
	if not _wait_for(sim, func() -> bool:
		var truck: Dictionary = sim.get_unit(int(sim.main_truck_id))
		return not truck.is_empty() and String(truck.get("order", "")) != "evacuate_transport" and Vector2(truck.pos).distance_to(Vector2(sim.get_camp(front_id).pos)) < 3.0,
		70.0, "last loaded truck arriving at forward camp"):
		return
	_advance(sim, 35.0)
	guide.update(sim)
	_check(_step(guide) == 9, "physically supplied eastern camp gets local utility guidance")
	print("GUIDE_ROUTE forward camp supplied t=", sim.time)
	_construct(sim, "road", Vector2i(57, 23), 25.0)
	_construct(sim, "generator", Vector2i(56, 21), 30.0)
	_construct(sim, "workshop", Vector2i(57, 25), 40.0)
	sim.set_production(front_id, "fuel")
	guide.update(sim)
	_check(_step(guide) == 10, "operational forward infrastructure leads to exit preparation")
	if not _wait_for(sim, func() -> bool: return float(sim.get_camp(front_id).fuel) >= 85.0, 140.0, "transported crude refined into a fuel reserve"):
		return
	sim.set_production(front_id, "supplies")
	if not _wait_for(sim, func() -> bool: return float(sim.get_camp(front_id).supplies) >= 80.0, 150.0, "rations produced before exit construction"):
		return
	sim.set_production(front_id, "idle")
	# Fund nearby power before capturing/connecting the exit triggers its paid job.
	_clear(sim, Vector2(68.0, 20.0), 65.0)
	_construct(sim, "road", Vector2i(68, 22), 90.0)
	_construct(sim, "generator", Vector2i(68, 22), 45.0)
	_clear(sim, Vector2(72.0, 19.0), 35.0)
	_construct(sim, "road", Vector2i(72, 19), 60.0)
	if not _wait_for(sim, func() -> bool: return float(sim.exit_progress) >= 1.0, 180.0, "funded powered exit actually finishing"):
		return
	guide.update(sim)
	_check(float(sim.exit_progress) >= 1.0, "exit really finishes with funding, engineer work and local power")
	_check(_step(guide) == 11 and not bool(guide.get_hint()["complete"]), "completed exit alone is not a completed tutorial or victory")
	var late_guide: Variant = Guide.new()
	late_guide.reset()
	late_guide.update(sim)
	_check(_step(late_guide) == 11, "fresh guide skips completed earlier milestones on an existing late mission")
	var everyone: Array = []
	for unit: Dictionary in sim.units:
		if String(unit.get("team", "")) == "friendly":
			everyone.append(int(unit["id"]))
	sim.command_move(everyone, Vector2(72.0, 19.0), true)
	if not _wait_for(sim, func() -> bool: return String(sim.outcome) == "victory", 90.0, "command truck and survivors arriving at the exit"):
		return
	guide.update(sim)
	_check(String(sim.outcome) == "victory" and bool(guide.get_hint()["complete"]), "only real people/truck arrival completes the guide")
	sim.reset(42)
	guide.update(sim)
	_check(_step(guide) == 1 and not bool(guide.get_hint()["complete"]), "real simulation reset clears a completed guide's old route")
	guide.reset(false)
	guide.update(sim)
	_check(_step(guide) == 1 and not bool(guide.get_hint()["visible"]), "explicit disabled reset starts a clean hidden first step")
