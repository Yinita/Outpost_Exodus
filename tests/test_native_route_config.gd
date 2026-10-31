extends SceneTree
## Source-only route selection/data checks. No rendered/native victory claim.
const Route = preload("res://scripts/diagnostics/campaign_route.gd")
const Catalog = preload("res://scripts/campaign_catalog.gd")
const Simulation = preload("res://scripts/campaign_simulation.gd")

class StoppedController extends Node2D:
	var sim: RefCounted
	var started: bool = false

class RejectObserver extends Node:
	var failures: Array[String] = []
	func check(ok: bool, label: String) -> bool:
		if not ok: failures.append(label)
		return ok

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(Route.configuration("unknown").is_empty(), "unknown mission has no fallback Canyon route")
	var expected: Dictionary = {
		"canyon": {"home": Vector2(9, 22), "quarry": Vector2(35, 10), "fuel": Vector2(35, 31), "front_camp": Vector2(54, 23), "exit": Vector2(72, 19)},
		"delta": {"home": Vector2(9, 12), "quarry": Vector2(35, 29), "fuel": Vector2(42, 7), "front_camp": Vector2(54, 28), "exit": Vector2(72, 30)},
		"ridge": {"home": Vector2(9, 29), "quarry": Vector2(36, 8), "fuel": Vector2(38, 29), "front_camp": Vector2(54, 12), "exit": Vector2(72, 10)}
	}
	for mission_id: String in Catalog.ids():
		var mission: Dictionary = Catalog.mission(mission_id)
		var config: Dictionary = Route.configuration(mission_id)
		_check(config.get("mission_id") == mission_id, mission_id + ": selected route retains identity")
		_check(config.get("landmarks") == mission.guide.landmarks, mission_id + ": route uses actual catalog landmarks")
		for key: String in expected[mission_id]:
			_check(config.landmarks[key] == expected[mission_id][key], mission_id + ": actual route target " + key)
		for key: String in ["opening_capture", "middle_generator", "middle_workshop", "middle_tower", "middle_capture", "middle_guard", "home_loading_guard", "front_rally", "front_generator", "front_workshop", "exit_approach"]:
			var point: Vector2 = config[key]
			_check(not Catalog.path(mission, Vector2i(config.landmarks.home), Vector2i(point)).is_empty(), mission_id + ": physical terrain/ramp route to " + key)
		_check(Vector2(config.exit_approach).distance_to(Vector2(config.landmarks.exit)) > 3.0, mission_id + ": power preparation stops outside exit capture radius")
		_check(Vector2(config.landmarks.exit_power).distance_to(Vector2(config.landmarks.exit)) <= 10.0, mission_id + ": real local generator reaches exit")
		_check(float(config.home_loading_guard_seconds) == (8.0 if mission_id == "ridge" else 0.0), mission_id + ": only Ridge clears home loading approach")
		_check(float(config.forward_road_seconds) == (90.0 if mission_id == "canyon" else 130.0), mission_id + ": established forward road window")
		_check(float(config.forward_camp_seconds) == (90.0 if mission_id == "canyon" else 100.0), mission_id + ": established forward camp window")
		_check(float(config.packing_material_reserve) == (0.0 if mission_id == "canyon" else 340.0), mission_id + ": established pre-packing funding reserve")
		_check(float(config.withdrawal_timeout) == (360.0 if mission_id == "canyon" else 450.0), mission_id + ": established physical withdrawal window")
		_check(bool(config.relocate_army_after_abandonment) == (mission_id != "canyon"), mission_id + ": established post-abandonment squad command")
		config.landmarks.exit = Vector2(-1, -1)
		_check(Route.configuration(mission_id).landmarks.exit == mission.guide.landmarks.exit and Catalog.mission(mission_id).guide.landmarks.exit == mission.guide.landmarks.exit, mission_id + ": config is a defensive copy")
		await _failed_route_identity(mission_id)
	var canyon: Dictionary = Route.configuration("canyon")
	var original_targets: Dictionary = {"opening_capture": Vector2(18, 21), "middle_generator": Vector2(28, 22), "middle_workshop": Vector2(30, 24), "middle_tower": Vector2(25, 20), "middle_capture": Vector2(29, 22), "middle_guard": Vector2(27, 19), "front_generator": Vector2(56, 21), "front_workshop": Vector2(57, 25), "exit_approach": Vector2(68, 20)}
	for key: String in original_targets:
		_check(canyon[key] == original_targets[key], "Canyon preserves accepted native command target " + key)
	print("Native route configuration checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _failed_route_identity(mission_id: String) -> void:
	var controller: StoppedController = StoppedController.new()
	controller.sim = Simulation.new()
	_check(controller.sim.reset(42, mission_id), mission_id + ": real simulation reset accepted")
	var before: String = JSON.stringify(controller.sim.save_state())
	var observer: RejectObserver = RejectObserver.new()
	var route: RefCounted = Route.new()
	var result: Dictionary = await route.run(controller, observer)
	_check(not bool(result.get("success", true)) and result.get("mission_id") == mission_id, mission_id + ": rejected non-running route reports actual mission")
	_check(observer.failures.size() == 1 and result.get("milestones", []).is_empty(), mission_id + ": rejected start issues no gameplay commands")
	_check(JSON.stringify(controller.sim.save_state()) == before, mission_id + ": rejected route leaves complete simulation/RNG unchanged")
	observer.free()
	controller.free()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
