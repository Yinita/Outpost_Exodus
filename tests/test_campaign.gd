extends SceneTree
## Headless behavioral tests. Run: Godot --headless --path . -s tests/test_campaign.gd
## Fixtures isolate public simulation state; assertions test outcomes, not helper internals.

const SIM_PATH: String = "res://scripts/campaign_simulation.gd"
const STEP: float = 1.0 / 30.0

var failures: Array[String] = []
var checks: int = 0
var simulation_script: Script

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not ResourceLoader.exists(SIM_PATH):
		push_error("Simulation script is missing: " + SIM_PATH)
		quit(1)
		return
	simulation_script = load(SIM_PATH) as Script
	if simulation_script == null or not simulation_script.can_instantiate():
		push_error("Simulation script cannot be instantiated")
		quit(1)
		return
	var tests: Array[Callable] = [
		_test_reset_and_pause,
		_test_terrain_and_road_boundaries,
		_test_construction_cost_and_progress,
		_test_production_inputs_and_local_power,
		_test_recruitment_and_training_save,
		_test_independent_camp_and_evacuation,
		_test_camp_integrity,
		_test_pursuit_and_sealing,
		_test_exit_is_not_a_timer,
		_test_save_roundtrip_and_rejection,
	]
	for test_case: Callable in tests:
		var failure_count: int = failures.size()
		test_case.call()
		print("%s %s" % ["PASS" if failures.size() == failure_count else "FAIL", test_case.get_method()])
	print("Campaign checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures:
		printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _new_sim() -> Variant:
	var sim: Variant = simulation_script.new()
	sim.reset(42)
	return sim

func _advance(sim: Variant, seconds: float) -> void:
	var steps: int = ceili(seconds / STEP)
	for index: int in range(steps):
		sim.tick(STEP)

func _camp(id_value: int, position: Vector2) -> Dictionary:
	return {
		"id": id_value, "name": "Test camp %d" % id_value, "pos": position,
		"state": "active", "materials": 250.0, "supplies": 100.0,
		"fuel": 60.0, "power": 0.0, "priority": "production",
		"salvage": 80.0, "crude": 80.0, "recipe": "idle",
	}

func _unit(id_value: int, kind: String, position: Vector2, camp_id: int) -> Dictionary:
	return {
		"id": id_value, "kind": kind, "team": "friendly", "pos": position,
		"hp": 100.0, "max_hp": 100.0, "state": "idle", "target": position,
		"camp_id": camp_id, "squad": 1, "speed": 1.75 if kind == "truck" else 1.25,
		"range": 0.0, "damage": 0.0, "order": "idle", "path": [],
		"capacity": 180.0 if kind == "truck" else 18.0,
	}

func _building(id_value: int, kind: String, position: Vector2, camp_id: int) -> Dictionary:
	return {
		"id": id_value, "kind": kind, "pos": position,
		"hp": 200.0, "max_hp": 200.0, "camp_id": camp_id,
		"progress": 1.0, "powered": false,
		"required_power": 4.0 if kind == "workshop" else (3.0 if kind == "tower" else 0.0),
		"power_radius": 10.0 if kind == "generator" else 0.0,
	}

func _flat_fixture() -> Variant:
	var sim: Variant = _new_sim()
	var rows: Array = []
	for y: int in range(40):
		var row: Array = []
		row.resize(80)
		row.fill(0)
		rows.append(row)
	sim.terrain = rows
	sim.roads = {Vector2i(6, 10): {"progress": 1.0, "camp_id": 10}}
	sim.ramps = {}
	sim.camps = [_camp(10, Vector2(6, 10))]
	sim.buildings = [_building(1000, "command", Vector2(6, 10), 10)]
	sim.units = [
		_unit(100, "truck", Vector2(6, 10), 10),
		_unit(101, "rifle", Vector2(7, 10), 10),
		_unit(102, "rifle", Vector2(7, 11), 10),
		_unit(103, "engineer", Vector2(6, 11), 10),
		_unit(104, "worker", Vector2(5, 10), 10),
	]
	sim.sites = []
	sim.effects = []
	sim.messages = []
	sim.main_truck_id = 100
	sim.exit_building_id = 0
	sim.exit_site_id = 0
	sim.chokes = []
	sim.pursuit_x = -10000.0
	sim.pursuit_start = 1000000.0
	sim.phase = "preparation"
	sim.outcome = "playing"
	sim.paused = false
	return sim

func _add_local_factory(sim: Variant, camp_id: int, position: Vector2, powered: bool = true) -> void:
	sim.buildings.append(_building(2000 + camp_id, "workshop", position + Vector2(1, 0), camp_id))
	if powered:
		sim.buildings.append(_building(3000 + camp_id, "generator", position + Vector2(0, 1), camp_id))
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN]:
		sim.roads[Vector2i(position) + offset] = {"progress": 1.0, "camp_id": camp_id}

func _test_reset_and_pause() -> void:
	var left: Variant = _new_sim()
	var right: Variant = _new_sim()
	_check(_equivalent(left.save_state(), right.save_state()), "same seed must initialize the same state")
	_check(left.outcome == "playing", "fresh campaign is playing")
	_check(left.camps.size() > 0 and left.units.size() > 0, "fresh mission contains a real camp and units")
	_check(left.terrain.size() == left.map_size.y, "terrain height matches map")
	left.paused = true
	var before: Dictionary = left.save_state()
	_advance(left, 2.0)
	_check(_equivalent(before, left.save_state()), "pause must freeze simulation state")
	left.paused = false
	var previous_time: float = float(left.time)
	left.tick(STEP)
	_check(float(left.time) > previous_time, "unpaused tick advances time")

func _test_terrain_and_road_boundaries() -> void:
	var sim: Variant = _flat_fixture()
	var camp: Dictionary = sim.get_camp(10)
	var materials_before: float = float(camp.materials)
	_check(not sim.is_walkable(Vector2i(-1, 10)), "negative tile is not walkable")
	_check(not sim.is_walkable(Vector2i(80, 10)), "outside map tile is not walkable")
	_check(not sim.build("road", Vector2i(-1, 10)), "road cannot be placed outside the map")
	_check(is_equal_approx(float(camp.materials), materials_before), "rejected outside road has no resource cost")
	sim.terrain[10][8] = -1
	_check(not sim.is_walkable(Vector2i(8, 10)), "impassable terrain is not walkable")
	_check(not sim.build("road", Vector2i(8, 10)), "road cannot occupy an impassable tile")
	for y: int in range(40):
		for x: int in range(12, 80):
			sim.terrain[y][x] = 1
	var road_count: int = sim.roads.size()
	_check(not sim.build("road", Vector2i(18, 10)), "a road cannot climb an unconnected cliff")
	_check(sim.roads.size() == road_count, "rejected cliff road creates no partial paid order")
	sim.command_move([101], Vector2(18, 10))
	_advance(sim, 12.0)
	var rifle: Dictionary = sim.get_unit(101)
	_check(float(rifle.pos.x) < 12.0, "unit movement cannot cross a cliff without a ramp")
	var flat: Variant = _flat_fixture()
	flat.command_move([101], Vector2(10, 10))
	_advance(flat, 8.0)
	_check(Vector2(flat.get_unit(101).pos).distance_to(Vector2(flat.get_unit(101).target)) < 0.1, "a normal walkable movement order must finish at its formation target")
	_check(flat.build("road", Vector2i(10, 10)), "road order succeeds over connected flat terrain")
	for road_tile: Variant in flat.roads.keys():
		_check(int(flat.terrain[road_tile.y][road_tile.x]) >= 0, "every ordered road tile remains on traversable terrain (including building entrances)")
	var crossing: Variant = _flat_fixture()
	for y: int in range(40):
		for x: int in range(12, 80):
			crossing.terrain[y][x] = 1
	crossing.ramps[Vector2i(11, 10)] = true
	crossing.ramps[Vector2i(12, 10)] = true
	crossing.command_move([101], Vector2(18, 10))
	_advance(crossing, 12.0)
	_check(float(crossing.get_unit(101).pos.x) > 12.0, "explicit two-sided ramp permits a real height crossing")
	_check(crossing.build("road", Vector2i(18, 10)), "a road can be routed through the explicit crossing")
	for road_tile: Variant in crossing.roads.keys():
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor: Vector2i = Vector2i(road_tile) + offset
			if crossing.roads.has(neighbor) and int(crossing.terrain[road_tile.y][road_tile.x]) != int(crossing.terrain[neighbor.y][neighbor.x]):
				_check(crossing.ramps.has(road_tile) and crossing.ramps.has(neighbor), "every road height change is at an explicit crossing")

func _test_construction_cost_and_progress() -> void:
	var sim: Variant = _flat_fixture()
	var camp: Dictionary = sim.get_camp(10)
	var before_materials: float = float(camp.materials)
	var before_buildings: int = sim.buildings.size()
	_check(sim.build("tower", Vector2i(8, 12)), "funded reachable tower order is accepted")
	_check(float(camp.materials) < before_materials, "construction pays real materials when ordered")
	var declared_costs: Dictionary = simulation_script.get_script_constant_map()["BUILD_COSTS"]["tower"]
	_check(is_equal_approx(before_materials - float(camp.materials), float(declared_costs.materials)), "tower material payment matches its declared cost exactly")
	_check(sim.buildings.size() == before_buildings + 1, "accepted order creates one construction site")
	var ordered: Dictionary = sim.buildings.back()
	_check(float(ordered.progress) < 1.0, "new building is unfinished before workers act")
	var after_payment: float = float(camp.materials)
	_check(not sim.build("tower", Vector2i(8, 12)), "duplicate building order is rejected")
	_check(is_equal_approx(float(camp.materials), after_payment), "duplicate order does not charge again")
	_advance(sim, 30.0)
	_check(float(ordered.progress) > 0.0, "engineer or worker actually advances construction")
	_check(float(ordered.progress) <= 1.0, "construction progress is bounded")
	var poor: Variant = _flat_fixture()
	poor.get_camp(10).materials = 0.0
	poor.get_camp(10).fuel = 0.0
	_check(not poor.build("tower", Vector2i(8, 12)), "unfunded construction is refused")
	_check(poor.buildings.size() == 1, "unfunded construction creates no building")

func _test_production_inputs_and_local_power() -> void:
	var ready: Variant = _flat_fixture()
	_add_local_factory(ready, 10, Vector2(6, 10))
	ready.set_production(10, "materials")
	var camp: Dictionary = ready.get_camp(10)
	var output_before: float = float(camp.materials)
	var raw_before: float = float(camp.salvage)
	var fuel_before: float = float(camp.fuel)
	_advance(ready, 24.0)
	_check(float(camp.materials) > output_before, "powered supplied workshop produces materials")
	_check(float(camp.salvage) < raw_before, "materials production consumes salvage")
	_check(float(camp.fuel) < fuel_before, "local generation consumes fuel")
	var no_power: Variant = _flat_fixture()
	_add_local_factory(no_power, 10, Vector2(6, 10), false)
	no_power.set_production(10, "materials")
	var unpowered_before: float = float(no_power.get_camp(10).materials)
	_advance(no_power, 24.0)
	_check(is_equal_approx(float(no_power.get_camp(10).materials), unpowered_before), "workshop cannot produce without a local generator")
	var no_fuel: Variant = _flat_fixture()
	_add_local_factory(no_fuel, 10, Vector2(6, 10))
	no_fuel.get_camp(10).fuel = 0.0
	no_fuel.set_production(10, "materials")
	var dry_before: float = float(no_fuel.get_camp(10).materials)
	_advance(no_fuel, 24.0)
	_check(is_equal_approx(float(no_fuel.get_camp(10).materials), dry_before), "generator without fuel cannot support production")
	var no_input: Variant = _flat_fixture()
	_add_local_factory(no_input, 10, Vector2(6, 10))
	no_input.get_camp(10).salvage = 0.0
	no_input.set_production(10, "materials")
	var empty_before: float = float(no_input.get_camp(10).materials)
	_advance(no_input, 24.0)
	_check(is_equal_approx(float(no_input.get_camp(10).materials), empty_before), "production cannot invent missing raw input")
	var no_workshop: Variant = _flat_fixture()
	no_workshop.buildings.append(_building(3001, "generator", Vector2(6, 11), 10))
	no_workshop.set_production(10, "materials")
	var workshop_before: float = float(no_workshop.get_camp(10).materials)
	_advance(no_workshop, 24.0)
	_check(is_equal_approx(float(no_workshop.get_camp(10).materials), workshop_before), "a generator alone cannot create workshop output")

func _friendly_count(sim: Variant) -> int:
	var count: int = 0
	for unit: Dictionary in sim.units:
		if unit.team == "friendly" and float(unit.hp) > 0.0:
			count += 1
	return count

func _recruit_fixture() -> Variant:
	var sim: Variant = _new_sim()
	sim.units = sim.units.filter(func(unit: Dictionary) -> bool: return unit.team == "friendly")
	sim.buildings = sim.buildings.filter(func(building: Dictionary) -> bool: return ["command", "generator", "exit"].has(str(building.kind)))
	var camp: Dictionary = sim.camps[0]
	camp.materials = 1000.0
	camp.supplies = 1000.0
	camp.fuel = 100.0
	sim.set_production(int(camp.id), "idle")
	_check(sim.build("barracks", Vector2i(13, 25)), "recruitment fixture orders a real barracks")
	_advance(sim, 40.0)
	var barracks_complete: bool = false
	for building: Dictionary in sim.buildings:
		if building.kind == "barracks" and float(building.progress) >= 1.0 and bool(building.powered):
			barracks_complete = true
	_check(barracks_complete, "workers complete and supply power to the real barracks")
	return sim

func _test_recruitment_and_training_save() -> void:
	var initial: Variant = _new_sim()
	_check(initial.has_method("recruit"), "simulation exposes the real recruitment API")
	if not initial.has_method("recruit"):
		return
	var constants: Dictionary = simulation_script.get_script_constant_map()
	var costs: Dictionary = constants["RECRUIT_COSTS"]["rifle"]
	var duration: float = float(constants["RECRUIT_SECONDS"]["rifle"])
	var cap: int = int(constants["POPULATION_CAP"])
	var sim: Variant = _recruit_fixture()
	var camp: Dictionary = sim.camps[0]
	var before_population: int = _friendly_count(sim)
	var resources_before: Dictionary = {"materials": camp.materials, "supplies": camp.supplies, "fuel": camp.fuel}
	_check(sim.recruit(int(camp.id), "rifle"), "funded powered barracks accepts training")
	_check(_friendly_count(sim) == before_population, "payment does not instantly spawn a recruit")
	_check(camp.get("recruit_queue", []).size() == 1, "accepted recruit occupies a real training queue")
	for key: Variant in costs:
		_check(is_equal_approx(float(resources_before[key]) - float(camp[key]), float(costs[key])), "recruit pays its declared " + str(key) + " cost exactly once")
	_advance(sim, minf(2.0, duration * 0.25))
	_check(_friendly_count(sim) == before_population, "partial training has not spawned a unit")
	var queue: Array = camp.get("recruit_queue", [])
	_check(not queue.is_empty() and float(queue[0].elapsed) > 0.0, "powered training makes measurable progress")
	var progress_before: float = float(queue[0].elapsed) if not queue.is_empty() else -1.0
	camp.fuel = 0.0
	_advance(sim, duration + 2.0)
	queue = camp.get("recruit_queue", [])
	_check(_friendly_count(sim) == before_population, "power loss cannot complete training")
	_check(not queue.is_empty() and is_equal_approx(float(queue[0].elapsed), progress_before), "power loss pauses rather than advancing or deleting the queued training")
	camp.fuel = 100.0
	_advance(sim, duration + 2.0)
	_check(_friendly_count(sim) == before_population + 1, "restored power completes training and spawns one friendly unit")
	_check(camp.get("recruit_queue", []).is_empty(), "completed training leaves the queue exactly once")
	var unpowered: Variant = _recruit_fixture()
	var unpowered_camp: Dictionary = unpowered.camps[0]
	unpowered_camp.fuel = 0.0
	_advance(unpowered, STEP)
	var no_power_materials: float = float(unpowered_camp.materials)
	_check(not unpowered.recruit(int(unpowered_camp.id), "rifle"), "unpowered barracks refuses a new training order")
	_check(is_equal_approx(float(unpowered_camp.materials), no_power_materials), "rejected unpowered training has no cost")
	_check(not initial.recruit(int(initial.camps[0].id), "rifle"), "rifle training requires an actual completed barracks")
	var capped: Variant = _recruit_fixture()
	var capped_camp: Dictionary = capped.camps[0]
	var test_id: int = 8000
	while _friendly_count(capped) < cap - 1:
		capped.units.append(_unit(test_id, "rifle", Vector2(12, 20), int(capped_camp.id)))
		test_id += 1
	_check(capped.recruit(int(capped_camp.id), "rifle"), "one last population slot can be reserved")
	var cap_materials: float = float(capped_camp.materials)
	_check(not capped.recruit(int(capped_camp.id), "rifle"), "queued recruits count toward the population cap")
	_check(is_equal_approx(float(capped_camp.materials), cap_materials), "cap rejection does not charge resources")
	var training: Variant = _recruit_fixture()
	var training_camp: Dictionary = training.camps[0]
	_check(training.recruit(int(training_camp.id), "rifle"), "save fixture begins actual training")
	_advance(training, minf(3.0, duration * 0.25))
	var training_save: Dictionary = training.save_state()
	var loaded: Variant = _new_sim()
	_check(loaded.load_state(JSON.parse_string(JSON.stringify(training_save))), "save during active training loads")
	_check(_equivalent(_core_saved(training_save), _core_saved(loaded.save_state())), "active training queue and paid inventory survive JSON roundtrip")
	_advance(training, duration + 3.0)
	_advance(loaded, duration + 3.0)
	_check(_equivalent(_core_saved(training.save_state()), _core_saved(loaded.save_state())), "saved training continues to the same recruited unit and subsequent state")
	var bad_queue: Dictionary = training_save.duplicate(true)
	var saved_camps: Array = _entry(bad_queue.payload, "camps")
	var saved_queue: Array = _entry(saved_camps[0], "recruit_queue")
	_check(not saved_queue.is_empty(), "training save contains a nonempty queue")
	if not saved_queue.is_empty():
		_set_entry(saved_queue[0], "duration", 0.0)
		_reject_without_mutation(loaded, bad_queue, "zero-duration training entry")

func _test_independent_camp_and_evacuation() -> void:
	var sim: Variant = _flat_fixture()
	var front: Dictionary = _camp(11, Vector2(30, 10))
	front.materials = 10.0
	front.fuel = 20.0
	sim.camps.append(front)
	sim.buildings.append(_building(1011, "camp", Vector2(30, 10), 11))
	_add_local_factory(sim, 11, Vector2(30, 10))
	sim.set_production(11, "materials")
	var original_materials: float = float(front.materials)
	_advance(sim, 20.0)
	_check(float(front.materials) > original_materials, "disconnected stocked forward camp uses its own local power and supplies")
	var rear: Dictionary = sim.get_camp(10)
	sim.set_production(11, "idle")
	rear.materials = 50.0
	rear.supplies = 0.0
	rear.fuel = 0.0
	rear.salvage = 0.0
	rear.crude = 0.0
	var front_before: float = float(front.materials)
	var rear_before: float = float(rear.materials)
	var accepted: bool = sim.evacuate_camp(10)
	_check(accepted, "a rear camp with a forward destination can begin evacuation")
	if accepted:
		_check(rear.state == "packing", "evacuation enters packing rather than instantly abandoning")
		_check(is_equal_approx(float(front.materials), front_before), "evacuation does not teleport rear inventory immediately")
		_check(float(rear.materials) > 0.0 or rear_before <= 0.0, "packing initially retains physical inventory at its source")
		_advance(sim, 0.5)
		_check(is_equal_approx(float(front.materials), front_before) or float(front.materials) - front_before < rear_before, "half-second packing cannot instantly transfer a distant camp's whole inventory")
		_advance(sim, 70.0)
		_check(rear.state == "abandoned", "a fully packed camp eventually becomes abandoned")
		_check(float(rear.materials) < 0.001, "evacuated material leaves its source inventory")
		_check(is_equal_approx(float(front.materials), front_before + rear_before), "transport eventually deposits the actual evacuated material at the forward camp")
		_check(Vector2(sim.get_unit(100).pos).distance_to(Vector2(front.pos)) < 3.0, "evacuation truck physically reaches the receiving camp")
	var emergency: Variant = _flat_fixture()
	var emergency_front: Dictionary = _camp(11, Vector2(30, 10))
	emergency_front.recipe = "idle"
	emergency.camps.append(emergency_front)
	emergency.buildings.append(_building(1011, "camp", Vector2(30, 10), 11))
	var emergency_rear: Dictionary = emergency.get_camp(10)
	var emergency_rear_materials: float = float(emergency_rear.materials)
	var emergency_front_materials: float = float(emergency_front.materials)
	_check(emergency.evacuate_camp(10), "emergency-abandonment fixture starts packing")
	_check(emergency.evacuate_camp(10), "reissuing evacuation while packing confirms urgent abandonment")
	_check(emergency_rear.state == "abandoned", "urgent abandonment closes the rear camp")
	_check(is_equal_approx(float(emergency_front.materials), emergency_front_materials), "urgent abandonment never teleports unpacked material to the forward camp")
	_check(is_equal_approx(float(emergency_rear.materials), emergency_rear_materials), "unpacked material remains at the abandoned source")
	_advance(emergency, 2.0)
	_check(is_equal_approx(float(emergency_front.materials), emergency_front_materials), "abandoned inventory does not arrive without a physical cargo delivery")
	var abandoned: Variant = _flat_fixture()
	_add_local_factory(abandoned, 10, Vector2(6, 10))
	abandoned.get_camp(10).state = "abandoned"
	abandoned.set_production(10, "materials")
	var abandoned_before: float = float(abandoned.get_camp(10).materials)
	_advance(abandoned, 20.0)
	_check(is_equal_approx(float(abandoned.get_camp(10).materials), abandoned_before), "abandoned camps cannot keep producing")

func _test_camp_integrity() -> void:
	var sim: Variant = _flat_fixture()
	var fallback: Dictionary = _camp(11, Vector2(30, 10))
	fallback.recipe = "idle"
	sim.camps.append(fallback)
	sim.buildings.append(_building(1011, "camp", Vector2(30, 10), 11))
	_add_local_factory(sim, 10, Vector2(6, 10))
	_advance(sim, STEP)
	_check(sim.build("tower", Vector2i(8, 12)), "camp-loss fixture has a real outstanding construction order")
	_check(sim.recruit(10, "worker"), "camp-loss fixture has a real queued recruit")
	_advance(sim, STEP)
	var front_before: float = float(fallback.materials)
	sim.buildings[0].hp = 0.0
	_advance(sim, STEP)
	var lost: Dictionary = sim.get_camp(10)
	_check(lost.state == "abandoned" and sim.outcome == "playing", "destroyed command camp is abandoned while a valid forward camp preserves the mission")
	_check(lost.get("recruit_queue", []).is_empty(), "lost camp cancels its unfinished training queue")
	_check(is_equal_approx(float(fallback.materials), front_before), "camp loss does not teleport its inventory into the fallback")
	for unit: Dictionary in sim.units:
		if unit.team == "friendly":
			_check(int(unit.camp_id) == 11, "camp-loss survivors and vehicle are reassigned to the fallback")
			_check(int(unit.get("job_id", 0)) == 0, "retreating survivor has no dangling construction assignment")
	var lost_materials: float = float(lost.materials)
	_advance(sim, 3.0)
	_check(is_equal_approx(float(lost.materials), lost_materials), "lost camp cannot continue production")
	var final_camp: Variant = _flat_fixture()
	final_camp.buildings[0].hp = 0.0
	_advance(final_camp, STEP)
	_check(final_camp.outcome == "defeat", "loss of the last command camp causes a real defeat")
	_check(final_camp.get_camp(10).state == "abandoned", "destroyed last camp is no longer a valid active supply center")

func _test_pursuit_and_sealing() -> void:
	var normal: Variant = _new_sim()
	normal.time = 200.0
	normal.phase = "advance"
	normal.pursuit_x = 5.0
	var initial_front: float = float(normal.pursuit_x)
	_advance(normal, 10.0)
	_check(float(normal.pursuit_x) > initial_front, "pursuit front advances during the campaign")
	var seal: Variant = _new_sim()
	var friendly_count: int = 0
	for unit: Dictionary in seal.units:
		if unit.team == "friendly":
			friendly_count += 1
	_check(friendly_count > 0, "sealing fixture has survivors to protect")
	_check(not seal.seal_choke(0), "rear choke refuses sealing while friendlies remain behind")
	for unit: Dictionary in seal.units:
		if unit.team == "friendly":
			unit.pos = Vector2(30, 20)
			unit.target = unit.pos
	for camp: Dictionary in seal.camps:
		camp.materials = 500.0
	var buildings_before: int = seal.buildings.size()
	_check(seal.seal_choke(0), "cleared rear choke can be sealed when funded")
	_check(seal.buildings.size() > buildings_before, "sealing creates a real delaying building")
	var has_barrier: bool = false
	for building: Dictionary in seal.buildings:
		if building.kind == "barricade" and float(building.hp) > 0.0:
			has_barrier = true
	_check(has_barrier, "the choke has a visible destructible barricade")
	var free: Variant = _flat_fixture()
	var blocked: Variant = _flat_fixture()
	for comparison: Variant in [free, blocked]:
		comparison.time = 200.0
		comparison.pursuit_start = 120.0
		comparison.pursuit_x = 17.49
		comparison.chokes = [{"pos": Vector2(20, 10), "name": "Test choke", "sealed": false, "pending": false, "building_id": 0}]
		for unit: Dictionary in comparison.units:
			unit.pos = Vector2(30, 10)
			unit.target = unit.pos
	_check(blocked.seal_choke(0), "controlled delaying choke can be sealed")
	var barrier: Dictionary = blocked.buildings.back()
	var hp_before: float = float(barrier.hp)
	_advance(free, 10.0)
	_advance(blocked, 10.0)
	_check(float(free.pursuit_x) > float(blocked.pursuit_x) + 0.25, "a sealed choke measurably delays pursuit versus the control")
	_check(float(barrier.hp) < hp_before, "pursuit actually damages its delaying barrier")
	barrier.hp = 0.1
	var held_front: float = float(blocked.pursuit_x)
	_advance(blocked, 2.0)
	_check(float(barrier.hp) <= 0.0, "the weakened barrier is destructible")
	_check(float(blocked.pursuit_x) > held_front, "pursuit resumes after the barrier falls")

func _exit_fixture() -> Variant:
	var sim: Variant = _flat_fixture()
	sim.exit_site_id = 4000
	sim.exit_building_id = 4001
	sim.sites = [{"id": 4000, "kind": "exit", "name": "Test exit", "pos": Vector2(12, 10), "captured": true, "progress": 1.0, "stock": {}}]
	var exit_building: Dictionary = _building(4001, "exit", Vector2(12, 10), -1)
	exit_building.progress = 0.0
	exit_building.required_power = 6.0
	exit_building.construction_started = false
	sim.buildings.append(exit_building)
	for x: int in range(6, 13):
		sim.roads[Vector2i(x, 10)] = {"progress": 1.0, "camp_id": 10}
	return sim

func _test_exit_is_not_a_timer() -> void:
	var waiting: Variant = _flat_fixture()
	waiting.phase = "evacuation"
	_advance(waiting, 900.0)
	_check(waiting.outcome == "playing" and float(waiting.time) >= 899.0, "a viable campaign can wait fifteen minutes without a timed victory")
	_check(float(waiting.exit_progress) < 1.0, "an unattended exit cannot construct itself")
	var nearby: Variant = _exit_fixture()
	for unit: Dictionary in nearby.units:
		unit.pos = Vector2(12, 10)
		unit.target = unit.pos
	nearby.get_camp(10).materials = 0.0
	nearby.get_camp(10).fuel = 0.0
	nearby.get_camp(10).supplies = 0.0
	_advance(nearby, 30.0)
	_check(nearby.outcome != "victory", "walking survivors to a cleared but unfunded exit is insufficient")
	_check(float(nearby.exit_progress) < 1.0, "exit work requires the actual road, resources and power prerequisites")
	var powered: Variant = _exit_fixture()
	powered.buildings.append(_building(5000, "generator", Vector2(8, 10), 10))
	var material_before: float = float(powered.get_camp(10).materials)
	_advance(powered, 60.0)
	_check(float(powered.get_camp(10).materials) <= material_before - 140.0, "exit construction pays its declared material cost")
	_check(float(powered.exit_progress) >= 1.0, "funded connected powered exit can actually be constructed by an engineer")
	_check(powered.outcome == "playing", "finished exit still waits for the command truck and survivors")
	powered.command_move([100, 101, 102, 103, 104], Vector2(12, 10))
	_advance(powered, 12.0)
	_check(powered.outcome == "victory", "real exit construction plus survivor/vehicle arrival wins")
	_check(int(powered.evacuated) >= 4, "victory reports actual evacuated survivors")
	var no_energy: Variant = _exit_fixture()
	var ready_exit: Dictionary = no_energy.buildings.back()
	ready_exit.progress = 1.0
	ready_exit.camp_id = 10
	ready_exit.construction_started = true
	no_energy.get_camp(10).fuel = 0.0
	for unit: Dictionary in no_energy.units:
		unit.pos = Vector2(12, 10)
		unit.target = unit.pos
	_advance(no_energy, 1.0)
	_check(no_energy.outcome != "victory", "a finished exit without local energy cannot evacuate the convoy")

func _test_save_roundtrip_and_rejection() -> void:
	var original: Variant = _new_sim()
	_check(original.build("road", Vector2i(25, 20)), "roundtrip fixture contains a funded real road-construction order")
	var first_rifle: Dictionary = original.units[0]
	original.command_move([int(first_rifle.id)], Vector2(24, 20), true)
	_advance(original, 2.0)
	var saved: Dictionary = original.save_state()
	var encoded: String = JSON.stringify(saved)
	var decoded: Variant = JSON.parse_string(encoded)
	_check(decoded is Dictionary, "save state is JSON serializable")
	if not decoded is Dictionary:
		return
	var restored: Variant = _new_sim()
	_check(restored.load_state(decoded), "a valid JSON-roundtripped save loads")
	_check(_equivalent(_core_saved(saved), _core_saved(restored.save_state())), "save/load preserves all meaningful state")
	_advance(original, 8.0)
	_advance(restored, 8.0)
	var continued_original: Dictionary = _core_saved(original.save_state())
	var continued_restored: Dictionary = _core_saved(restored.save_state())
	_check(_equivalent(continued_original, continued_restored), "roundtrip preserves subsequent simulation continuation: " + _first_difference(continued_original, continued_restored))
	_reject_without_mutation(restored, {}, "empty save")
	var wrong_version: Dictionary = saved.duplicate(true)
	wrong_version["version"] = -1
	_reject_without_mutation(restored, wrong_version, "unsupported version")
	var invalid_units: Dictionary = saved.duplicate(true)
	_check(_set_entry(invalid_units.payload, "units", "not an array"), "save mutation locates units")
	_reject_without_mutation(restored, invalid_units, "invalid units type")
	var missing_time: Dictionary = saved.duplicate(true)
	_check(_erase_entry(missing_time.payload, "time"), "save mutation locates time")
	_reject_without_mutation(restored, missing_time, "missing required time")
	var negative_inventory: Dictionary = saved.duplicate(true)
	var encoded_camps: Array = _entry(negative_inventory.payload, "camps")
	_check(_set_entry(encoded_camps[0], "materials", -100.0), "save mutation locates material inventory")
	_reject_without_mutation(restored, negative_inventory, "negative inventory")
	var duplicate_ids: Dictionary = saved.duplicate(true)
	var encoded_units: Array = _entry(duplicate_ids.payload, "units")
	_check(_set_entry(encoded_units[1], "id", _entry(encoded_units[0], "id")), "save mutation locates a unit ID")
	_reject_without_mutation(restored, duplicate_ids, "duplicate unit IDs")
	var invalid_position: Dictionary = saved.duplicate(true)
	var positioned_units: Array = _entry(invalid_position.payload, "units")
	_check(_set_entry(positioned_units[0], "pos", "not a coordinate"), "save mutation locates a unit position")
	_reject_without_mutation(restored, invalid_position, "invalid position encoding")
	var outside_position: Dictionary = saved.duplicate(true)
	var outside_units: Array = _entry(outside_position.payload, "units")
	_set_entry(outside_units[0], "pos", {"$type": "Vector2", "x": -1000.0, "y": 20.0})
	_reject_without_mutation(restored, outside_position, "out-of-bounds unit position")
	var nonfinite: Dictionary = saved.duplicate(true)
	_set_entry(nonfinite.payload, "time", NAN)
	_reject_without_mutation(restored, nonfinite, "non-finite mission time")
	var missing_truck: Dictionary = saved.duplicate(true)
	_set_entry(missing_truck.payload, "main_truck_id", 999999)
	_reject_without_mutation(restored, missing_truck, "missing command-truck reference")
	var reused_id: Dictionary = saved.duplicate(true)
	_set_entry(reused_id.payload, "next_id", 1)
	_reject_without_mutation(restored, reused_id, "next ID reuses an existing identifier")
	var missing_camp: Dictionary = saved.duplicate(true)
	var camp_units: Array = _entry(missing_camp.payload, "units")
	_set_entry(camp_units[0], "camp_id", 999999)
	_reject_without_mutation(restored, missing_camp, "friendly unit references a missing camp")
	var negative_cost: Dictionary = saved.duplicate(true)
	var jobs: Array = _entry(negative_cost.payload, "jobs")
	_check(not jobs.is_empty(), "save fixture contains a construction job")
	if not jobs.is_empty():
		var costs: Dictionary = _entry(jobs[0], "costs")
		_set_entry(costs, "materials", -100.0)
		_reject_without_mutation(restored, negative_cost, "negative construction-job cost")

func _reject_without_mutation(sim: Variant, invalid: Dictionary, label: String) -> void:
	var before: Dictionary = sim.save_state()
	_check(not sim.load_state(invalid), "load rejects " + label)
	_check(_equivalent(before, sim.save_state()), "rejected " + label + " leaves live state unchanged")

func _core_saved(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	_erase_entry(result.payload, "messages")
	_erase_entry(result.payload, "effects")
	return result

func _entry(encoded_dictionary: Dictionary, key: String) -> Variant:
	for pair: Array in encoded_dictionary.get("entries", []):
		if pair[0] == key:
			return pair[1]
	return null

func _set_entry(encoded_dictionary: Dictionary, key: String, value: Variant) -> bool:
	for pair: Array in encoded_dictionary.get("entries", []):
		if pair[0] == key:
			pair[1] = value
			return true
	return false

func _erase_entry(encoded_dictionary: Dictionary, key: String) -> bool:
	var entries: Array = encoded_dictionary.get("entries", [])
	for index: int in range(entries.size()):
		if entries[index][0] == key:
			entries.remove_at(index)
			return true
	return false

func _equivalent(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return is_equal_approx(float(left), float(right))
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _equivalent(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _equivalent(left[index], right[index]):
				return false
		return true
	return left == right

func _first_difference(left: Variant, right: Variant, path: String = "save") -> String:
	if _equivalent(left, right):
		return "none"
	if left is Dictionary and right is Dictionary:
		for key: Variant in left:
			if not right.has(key):
				return path + "." + str(key) + " is missing"
			if not _equivalent(left[key], right[key]):
				return _first_difference(left[key], right[key], path + "." + str(key))
	if left is Array and right is Array:
		if left.size() != right.size():
			return path + " array length %d != %d" % [left.size(), right.size()]
		for index: int in range(left.size()):
			if not _equivalent(left[index], right[index]):
				return _first_difference(left[index], right[index], path + "[%d]" % index)
	return path + ": " + str(left).left(100) + " != " + str(right).left(100)
