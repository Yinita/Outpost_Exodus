extends SceneTree
## Local macro summaries observe real admitted work and never drive simulation.

const Simulation = preload("res://scripts/campaign_simulation.gd")
const Readout = preload("res://scripts/camp_readout.gd")
const ConstructionRules = preload("res://scripts/construction_rules.gd")
const RecruitmentRules = preload("res://scripts/recruitment_rules.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_test_read_only_and_detached_rows, _test_intent_and_setup, _test_actual_production_blockers, _test_admitted_training_and_priority, _test_real_packing_stages, _test_terminal_and_missing]:
		var previous: int = failures.size()
		test.call()
		print("%s %s" % ["PASS" if previous == failures.size() else "FAIL", test.get_method()])
	await _test_public_main_cache()
	print("Camp readout checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)


func _fixture() -> Variant:
	var sim: Variant = Simulation.new()
	sim.reset(42)
	for y: int in range(sim.map_size.y):
		for x: int in range(sim.map_size.x): sim.terrain[y][x] = 0
	sim.ramps = {}
	sim.camps = []
	sim.buildings = []
	sim.units = []
	sim.sites = []
	sim.effects = []
	sim.messages = []
	sim.chokes = []
	sim._jobs = []
	sim._next_id = 10000
	var camp: Dictionary = sim._make_camp(Vector2(6, 10), "西营", 1000.0, 500.0, 100.0)
	camp.recipe = "idle"
	sim.roads = {}
	for x: int in range(6, 23):
		for y: int in range(10, 14): sim.roads[Vector2i(x, y)] = {"progress":1.0, "camp_id":int(camp.id)}
	sim._add_building("command", Vector2(6, 10), int(camp.id), 1.0)
	sim._add_building("generator", Vector2(6, 12), int(camp.id), 1.0)
	sim._add_building("barracks", Vector2(9, 10), int(camp.id), 1.0)
	sim._add_building("workshop", Vector2(9, 13), int(camp.id), 1.0)
	var truck: Dictionary = sim._add_unit("truck", "friendly", Vector2(5, 11), int(camp.id), 0)
	sim.main_truck_id = int(truck.id)
	for position: Vector2 in [Vector2(12, 18), Vector2(13, 18), Vector2(14, 18), Vector2(15, 18)]:
		sim._add_unit("rifle", "friendly", position, int(camp.id), 1)
	sim.exit_site_id = 0
	sim.exit_building_id = 0
	sim.pursuit_x = -10000.0
	sim.pursuit_start = 1000000.0
	sim._invalidate_navigation()
	sim._update_power(0.0)
	return sim


func _snapshot(sim: Variant) -> String:
	return JSON.stringify(sim.save_state())


func _building(sim: Variant, kind: String) -> Dictionary:
	for building: Dictionary in sim.buildings:
		if building.kind == kind: return building
	return {}


func _expect(sim: Variant, code: String, severity: String, label: String) -> Dictionary:
	var before: String = _snapshot(sim)
	var result: Dictionary = Readout.status(sim, int(sim.camps[0].id))
	_check(result.code == code and result.severity == severity, label + " reports " + code + "/" + severity)
	_check(not str(result.text).is_empty() and not str(result.detail).is_empty(), label + " has visible text and an explanation")
	_check(_snapshot(sim) == before, label + " preserves encoded state, IDs and RNG")
	return result


func _test_read_only_and_detached_rows() -> void:
	var sim: Variant = _fixture()
	sim.camps[0].recipe = "materials"
	var before: String = _snapshot(sim)
	var first: Dictionary = Readout.status(sim, int(sim.camps[0].id))
	for index: int in range(12):
		var row: Dictionary = Readout.status(sim, int(sim.camps[0].id))
		_check(row == first, "unchanged real work yields stable row %d" % index)
		row.text = "caller override"
		row.severity = "attention"
	_check(_snapshot(sim) == before, "repeated caller-mutated observations preserve complete simulation state")
	_check(Readout.status(sim, int(sim.camps[0].id)) == first, "returned rows do not alias a shared mutable result")
	sim.paused = true
	before = _snapshot(sim)
	var row: Dictionary = Readout.status(sim, int(sim.camps[0].id))
	_check(row.code == "production_running" and str(row.text).begins_with("Ⅱ ") and str(row.text).ends_with("待续"), "paused ready production is described as pending continuation")
	_check(not str(row.text).contains("正在"), "paused ready work is never described as currently advancing")
	_check(_snapshot(sim) == before and sim.paused, "paused observation never temporarily resumes the live simulation")


func _test_intent_and_setup() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	camp.fuel = 0.0
	sim._update_power(0.0)
	_expect(sim, "idle", "normal", "intentional idle with no power and no queue")
	camp.recipe = "materials"
	_building(sim, "workshop").hp = 0.0
	_expect(sim, "setup", "normal", "default recipe without a live workshop")
	var unfinished: Dictionary = sim._add_building("workshop", Vector2(9, 13), int(camp.id), 0.3)
	_expect(sim, "setup", "normal", "unfinished workshop is setup, not interrupted production")
	camp.recipe = "idle"
	_expect(sim, "idle", "normal", "explicit idle overrides unfinished workshop")
	camp.recipe = "not_a_recipe"
	unfinished.progress = 1.0
	_expect(sim, "idle", "normal", "invalid/unselected recipe never invents a productive request")


func _test_actual_production_blockers() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	camp.recipe = "materials"
	_expect(sim, "production_running", "normal", "powered selected recipe with local input")
	camp.salvage = 0.0
	var other: Dictionary = sim._make_camp(Vector2(22, 10), "东营", 1000.0, 500.0, 100.0)
	other.salvage = 9999.0
	var row: Dictionary = _expect(sim, "production_input_empty", "attention", "real missing local production input")
	_check(str(row.detail).contains("废料") and str(row.text).begins_with("! "), "input interruption names its actual resource and has a non-colour signal")
	sim.paused = true
	row = _expect(sim, "production_input_empty", "attention", "planning pause retains the underlying missing input")
	_check(str(row.text).begins_with("Ⅱ ") and str(row.detail).contains("废料"), "paused shortage stays visible beside the pause qualifier")
	_check(sim.get_production_status(int(camp.id)).code == "paused", "existing two-argument production diagnostic preserves its pause behavior")
	_check(ConstructionRules.get_production_status(sim, int(camp.id), false).code == "input_empty", "optional production diagnostic reads underlying snapshot")
	sim.paused = false
	camp.salvage = 45.0
	camp.fuel = 0.0
	sim._update_power(0.0)
	row = _expect(sim, "production_unpowered", "attention", "completed requested work loses actual local power")
	_check(str(row.detail).contains("成品燃料"), "power interruption retains the allocator diagnostic's actual cause")
	camp.recipe = "idle"
	_expect(sim, "idle", "normal", "deliberately stopping production clears a productive-work alert")


func _test_admitted_training_and_priority() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	var id: int = int(camp.id)
	_check(sim.recruit(id, "rifle"), "real funded powered barracks admits an order")
	_expect(sim, "training", "normal", "admitted local queue is training")
	camp.recipe = "materials"
	_expect(sim, "working", "normal", "production and training both run")
	camp.salvage = 0.0
	_expect(sim, "production_input_empty", "attention", "blocked production remains visible while training runs")
	camp.fuel = 0.0
	sim._update_power(0.0)
	_expect(sim, "training_waiting_power", "attention", "admitted training interruption outranks production interruption")
	sim.paused = true
	var row: Dictionary = _expect(sim, "training_waiting_power", "attention", "paused training retains its actual blocker")
	_check(str(row.text).begins_with("Ⅱ ") and str(row.detail).contains("成品燃料"), "pause qualifier retains the queued unit's true power cause")
	_check(sim.get_training_status(id).code == "paused", "existing two-argument training diagnostic preserves pause behavior")
	_check(RecruitmentRules.get_training_status(sim, id, false).code == "waiting_power", "optional training diagnostic does not hide its actual blocker")
	camp.recruit_queue = []
	camp.recipe = "idle"
	_expect(sim, "idle", "normal", "empty queue and deliberate idle do not warn about missing recruitment power")


func _test_real_packing_stages() -> void:
	var sim: Variant = _fixture()
	var camp: Dictionary = sim.camps[0]
	var destination: Dictionary = sim._make_camp(Vector2(22, 10), "东营", 1000.0, 500.0, 100.0)
	_check(sim.evacuate_camp(int(camp.id)), "actual evacuation request finds a reachable forward receiver")
	_expect(sim, "packing_returning", "normal", "evacuation truck returns for its first load")
	sim._update_evacuations(0.0)
	_expect(sim, "packing_loading", "normal", "truck at the depot is actually loading")
	sim._update_evacuations(6.0)
	_expect(sim, "packing_outbound", "normal", "loaded truck is actually outbound")
	sim.paused = true
	var row: Dictionary = _expect(sim, "packing_outbound", "normal", "paused transport preserves its real stage")
	_check(str(row.text) == "Ⅱ 撤收运输待续", "paused transport never implies movement is currently advancing")
	sim.paused = false
	sim.get_unit(int(sim.main_truck_id)).hp = 0.0
	_expect(sim, "packing_waiting_truck", "attention", "requested evacuation loses its assigned vehicle")
	sim.get_unit(int(sim.main_truck_id)).hp = 380.0
	sim.camps.erase(destination)
	_expect(sim, "packing_waiting_destination", "attention", "requested evacuation loses its real receiver")
	camp.state = "abandoned"
	row = _expect(sim, "abandoned", "muted", "abandonment supersedes old work and packing blockers")
	_check(float(camp.materials) > 0.0 and str(row.detail).contains("留在原地"), "abandoned camp never implies its remaining stock is empty")


func _test_terminal_and_missing() -> void:
	var sim: Variant = _fixture()
	sim.camps[0].recipe = "materials"
	sim.camps[0].salvage = 0.0
	sim.outcome = "defeat"
	_expect(sim, "ended", "muted", "completed campaign does not present active job alerts")
	var before: String = _snapshot(sim)
	var row: Dictionary = Readout.status(sim, 999999)
	_check(row.code == "no_camp" and row.severity == "muted", "unknown ID produces an inert non-alert row")
	_check(_snapshot(sim) == before, "missing camp lookup preserves state")


func _test_public_main_cache() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/camp-readout-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolated + "/"):
		_check(false, "Main integration refuses non-isolated XDG_DATA_HOME")
		return
	AudioServer.set_bus_mute(0, true)
	var app: Variant = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.start_campaign("canyon")
	var id: int = int(app.selected_camp)
	_check(app.camp_readouts.has(id) and app.camp_readouts[id].code == "production_running", "public start immediately exposes current camp work")
	app.ui_action("pause")
	app._process(0.0)
	_check(str(app.camp_readouts[id].text).begins_with("Ⅱ "), "public pause updates camp planning state without a timed wait")
	app.ui_action("recipe:idle")
	app._process(0.0)
	_check(app.camp_readouts[id].code == "idle", "public recipe action refreshes selected camp immediately")
	app.sim.set_production(id, "materials")
	var before: String = _snapshot(app.sim)
	app._process(0.24)
	_check(app.camp_readouts[id].code == "idle", "unannounced live change remains bounded by the quarter-second observation interval")
	app._process(0.02)
	_check(app.camp_readouts[id].code == "production_running", "quarter-second refresh picks up live local conditions without another UI action")
	_check(_snapshot(app.sim) == before, "paused cache refresh preserves simulation payload and RNG")
	var extra: Dictionary = app.sim._make_camp(Vector2(30, 20), "新增营地", 0.0, 0.0, 0.0)
	app._process(0.0)
	_check(app.camp_readouts.has(int(extra.id)) and app.camp_readouts[int(extra.id)].severity == "normal", "new camp is visible immediately and starts as neutral setup")
	app.start_campaign("delta")
	id = int(app.selected_camp)
	_check(app.camp_readouts.size() == app.sim.camps.size() and not app.camp_readouts.has(int(extra.id)), "starting another mission clears stale camp observations")
	app.ui_action("pause")
	app.ui_action("recipe:idle")
	app._process(0.0)
	_check(app.save_campaign(), "public save writes an isolated real campaign")
	app.ui_action("recipe:materials")
	app._process(0.0)
	_check(app.camp_readouts[id].code == "production_running", "live recipe differs from the saved idle state")
	_check(app.load_campaign(), "public load restores the isolated real campaign")
	_check(app.camp_readouts[id].code == "idle", "successful load immediately replaces stale macro observations")
	var payload: Dictionary = app._save_payload()
	_check(not payload.has("camp_readouts") and not Dictionary(payload.get("ui", {})).has("camp_readouts"), "derived macro rows do not enter campaign saves")
	app.ui_action("title")
	app._process(0.0)
	_check(not app.started and app.camp_readouts.is_empty(), "return to title clears live camp observations")
	app._release_audio()
	app.queue_free()
	app = null
	# Stopped WAV playbacks retire on the mixer thread, independent of fast
	# headless frames. Allow the same real wall-clock retirement as clean exit.
	var retirement_deadline: int = Time.get_ticks_usec() + 120000
	while Time.get_ticks_usec() < retirement_deadline: await process_frame
