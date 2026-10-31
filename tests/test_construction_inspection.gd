extends SceneTree
## Bounded headless UI/query checks. No native pixels, human input or FPS claim.
const Rules = preload("res://scripts/construction_rules.gd")

class CountingSim:
	extends "res://scripts/campaign_simulation.gd"
	var queries: int = 0
	func query_build(kind: String, tile: Vector2i, refresh_navigation: bool = true) -> Dictionary:
		queries += 1
		return super.query_build(kind, tile, refresh_navigation)

class QuietMain:
	extends "res://scripts/main.gd"
	func _ready() -> void: pass
	func _play_tone(_frequency: float, _duration: float, _gain: float = 0.25) -> void: pass

class QuietWorld:
	extends "res://scripts/world_view.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

class QuietHud:
	extends "res://scripts/hud.gd"
	func _ready() -> void: pass

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/construction-inspection-data/")
	if not OS.get_user_data_dir().begins_with(isolated):
		printerr("Construction inspection checks require isolated work/construction-inspection-data")
		quit(2)
		return
	_test_preview()
	_test_project_selection()
	_test_status()
	print("Construction inspection checks: %d; failures: %d" % [checks, failures.size()])
	for message: String in failures: printerr(" - ", message)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _state(sim: Variant) -> String:
	return JSON.stringify(sim.save_state())

func _fixture() -> Variant:
	var sim: Variant = CountingSim.new()
	sim.reset(42)
	var terrain: Array = []
	for y: int in range(sim.map_size.y):
		var row: Array = []
		row.resize(sim.map_size.x)
		row.fill(0)
		terrain.append(row)
	sim.terrain = terrain
	sim.ramps = {}
	sim.camps = []
	sim.buildings = []
	sim.units = []
	sim.sites = []
	sim.chokes = []
	sim.effects = []
	sim.messages = []
	sim._jobs = []
	var camp: Dictionary = sim._make_camp(Vector2(6, 10), "供料营", 300.0, 100.0, 100.0)
	camp.recipe = "idle"
	sim._add_building("command", camp.pos, int(camp.id), 1.0)
	var truck: Dictionary = sim._add_unit("truck", "friendly", Vector2(5, 11), int(camp.id), 0)
	sim.main_truck_id = int(truck.id)
	for position: Vector2 in [Vector2(4, 14), Vector2(5, 14), Vector2(6, 14), Vector2(7, 14)]:
		sim._add_unit("rifle", "friendly", position, int(camp.id), 1)
	sim.roads = {Vector2i(6, 10): {"progress": 1.0, "camp_id": int(camp.id)}}
	sim.exit_building_id = 0
	sim.exit_site_id = 0
	sim.pursuit_x = -10000.0
	sim.pursuit_start = 1000000.0
	sim._invalidate_navigation()
	return sim

func _app(sim: Variant) -> Variant:
	var app: Variant = QuietMain.new()
	root.add_child(app)
	app.set_process(false)
	app.sim = sim
	app.world = QuietWorld.new()
	app.world.sim = sim
	app.add_child(app.world)
	app.hud = QuietHud.new()
	app.hud.main = app
	app.add_child(app.hud)
	app.camera = Camera2D.new()
	app.add_child(app.camera)
	app.started = true
	app.menu = ""
	app.selected_camp = int(sim.camps[0].id)
	return app

func _preview(app: Variant, point: Vector2, tile: Vector2i) -> void:
	app.world.hover_tile = tile
	if app.has_method("_refresh_build_preview"):
		app._refresh_build_preview(point)
	else:
		# Run the original controller path too, exposing its HUD-underlay query.
		app._refresh_context_readouts()

func _test_preview() -> void:
	var sim: Variant = _fixture()
	var app: Variant = _app(sim)
	app.build_kind = "generator"
	var tile: Vector2i = Vector2i(11, 10)
	var before: String = _state(sim)
	var rng_before: int = sim._rng.state
	var screen: Vector2 = app.hud.get_viewport_rect().size
	_preview(app, Vector2(screen.x * 0.5, screen.y - 30), tile)
	_check(app.build_preview.get("code", "") == "choose_map", "HUD hover shows neutral choose-map instead of a world error")
	_check(sim.queries == 0, "HUD hover never queries the hidden world tile")
	_check(app.world.hover_tile == Vector2i(-1, -1), "HUD hover hides the world placement ghost")
	_check(_state(sim) == before and sim._rng.state == rng_before, "neutral hover preserves the full encoded Sim and RNG")
	var map_point: Vector2 = Vector2(screen.x * 0.55, screen.y * 0.55)
	_preview(app, map_point, tile)
	_check(app.build_preview.get("code", "") == "ready", "moving to the map immediately restores the actual plan")
	var queries: int = sim.queries
	_preview(app, map_point, tile)
	_check(sim.queries == queries, "stationary map hover still reuses its unchanged actual plan")
	if app.hud.has_method("blocks_world_point"):
		for scale: float in [1.0, 1.2]:
			root.content_scale_factor = scale
			var logical: Vector2 = app.hud.get_viewport_rect().size
			_check(app.hud.blocks_world_point(Vector2(logical.x - 10, logical.y - 10)), "bottom HUD blank is blocked at UI scale " + str(scale))
			_check(app.hud.blocks_world_point(Vector2(25, 100)), "left panel blank is blocked at UI scale " + str(scale))
			_check(not app.hud.blocks_world_point(Vector2(logical.x * 0.65, logical.y * 0.48)), "map remains available at UI scale " + str(scale))
			app.construction_readout = {"building_id": 1}
			app.build_kind = ""
			var panel: Rect2 = app.hud._construction_details_rect(logical)
			_check(panel.position.x >= 318 and panel.end.x <= logical.x - 268 and panel.end.y < logical.y - 190, "project details preserve Guide, camp cards and dock at UI scale " + str(scale))
			_check(app.hud.blocks_world_point(panel.get_center()), "project details consume their own world area")
			var paused_before: bool = sim.paused
			sim.paused = true
			_check(not app.hud._pause_banner_visible(), "project pause footer suppresses the central banner that could cover detail rows")
			app.construction_readout = {}
			_check(app.hud._pause_banner_visible(), "ordinary tactical pause still keeps its central banner")
			sim.paused = paused_before
			app.build_kind = "generator"
		root.content_scale_factor = 1.0
		var compact: Rect2 = app.hud._construction_details_rect(Vector2(960, 540))
		_check(compact.intersects(Rect2(320, 138, 320, 40)), "compact regression geometry actually intersects the old central pause banner")
		app.hud.overlay_rects.clear()
		app.hud.overlay_rects.append(Rect2(map_point - Vector2(20, 20), Vector2(40, 40)))
		_preview(app, map_point, tile)
		_check(app.build_preview.code == "choose_map" and sim.queries == queries, "drawn overlay blocks hover queries as well as clicks")
		app.hud.overlay_rects.clear()
		_preview(app, map_point, tile)
		_check(app.build_preview.code == "ready" and sim.queries == queries + 1, "leaving an overlay refreshes the map plan without a simulation tick")
	else:
		_check(false, "HUD exposes a pure shared world-point query")
	sim.camps[0].materials = 0.0
	var jobs: int = sim._jobs.size()
	var rejected: Dictionary = app._place_build(tile)
	_check(not rejected.ok and rejected.code == "resources" and sim._jobs.size() == jobs, "placement click revalidates funds instead of trusting the old ready preview")
	app.free()

func _test_project_selection() -> void:
	var sim: Variant = _fixture()
	_check(sim.build("generator", Vector2i(11, 10)), "public paid order creates the selectable real generator project")
	var building: Dictionary = sim.buildings.back()
	var app: Variant = _app(sim)
	var before: String = _state(sim)
	var point: Vector2 = Vector2(building.pos) * 48.0 - Vector2(0, 30)
	app.drag_start = point
	app._select(point, false, false)
	_check(app.get("selected_project_id") == int(building.id), "clicking the visible unfinished building selects that exact project")
	_check(_state(sim) == before, "project selection preserves full encoded Sim and RNG")
	if app.get("selected_project_id") == int(building.id):
		_check(app.construction_readout.source_name == "供料营" and app.construction_readout.progress == 0.0, "selected project exposes its actual source and progress")
		var ui: Dictionary = app._save_payload().ui
		_check(not ui.has("selected_project_id") and not ui.has("construction_readout"), "project selection/readout add no saved UI or simulation fields")
		app.ui_action("close_project")
		_check(app.selected_project_id == 0 and app.construction_readout.is_empty(), "close action clears only the temporary project selection")
		app.drag_start = point
		app._select(point, false, false)
		var escape: InputEventKey = InputEventKey.new()
		escape.pressed = true
		escape.keycode = KEY_ESCAPE
		app._unhandled_input(escape)
		_check(app.selected_project_id == 0 and app.menu.is_empty(), "Escape closes project details without opening a menu")
		app.drag_start = point
		app._select(point, false, false)
		building.progress = 1.0
		app._refresh_context_readouts()
		_check(app.selected_project_id == 0 and app.construction_readout.is_empty(), "completion clears selection rather than silently selecting another project")
		building.progress = 0.0
		var worker: Dictionary = sim._add_unit("worker", "friendly", Vector2(building.pos), int(sim.camps[0].id), 0)
		point = Vector2(worker.pos) * 48.0
		app.drag_start = point
		app._select(point, false, false)
		_check(app.selected_ids == [worker.id] and app.selected_project_id == 0, "existing friendly-unit selection retains priority over a project")
		worker.pos = Vector2(6, 11)
		point = Vector2(building.pos) * 48.0 - Vector2(0, 30)
		app.drag_start = point
		app._select(point, false, false)
		app.guide.reset(true)
		app.guide.update(sim)
		_check(app.selected_project_id == int(building.id) and app.save_campaign(), "real SaveStore writes a project-selected controlled campaign")
		_check(app.load_campaign() and app.selected_project_id == 0 and app.construction_readout.is_empty(), "real disk load clears temporary project selection without reviving a stale panel")
		app.selected_project_id = int(building.id)
		app.start_campaign("canyon")
		_check(app.selected_project_id == 0 and app.construction_readout.is_empty(), "new campaign clears the prior run's project ID")
	app.free()

func _status(sim: Variant, building: Dictionary, code: String) -> Dictionary:
	var before: String = _state(sim)
	var rng_before: int = sim._rng.state
	var rules: Variant = Rules.new()
	var row: Dictionary = rules.call("get_construction_status", sim, int(building.id))
	_check(row.get("code", "") == code, "project reports actual stage " + code)
	_check(_state(sim) == before and sim._rng.state == rng_before, code + " query preserves full encoded Sim/entry order and RNG")
	_check(not str(row.get("text", "")).contains("堵") and not str(row.get("text", "")).contains("可达"), code + " does not infer an unqueried route condition")
	return row

func _test_status() -> void:
	var rules: Variant = Rules.new()
	if not rules.has_method("get_construction_status"):
		_check(false, "read-only existing-project status is available")
		return
	var sim: Variant = _fixture()
	_check(sim.build("generator", Vector2i(11, 10)), "status fixture pays the actual public generator cost")
	var building: Dictionary = sim.buildings.back()
	var job: Dictionary = sim._jobs.back()
	var row: Dictionary = _status(sim, building, "awaiting_builder")
	_check(row.text.contains("暂无空闲"), "no eligible worker is explained without a reachability claim")
	var worker: Dictionary = sim._add_unit("worker", "friendly", Vector2(6, 11), int(sim.camps[0].id), 0)
	_status(sim, building, "awaiting_builder")
	sim.tick(0.05)
	_status(sim, building, "collecting")
	sim.tick(0.05)
	_status(sim, building, "delivering")
	var saw_building: bool = false
	for tick: int in range(1200):
		sim.tick(0.05)
		if float(building.progress) >= 1.0: break
		if float(building.progress) > 0.0 and bool(job.delivered) and Vector2(worker.pos).distance_to(Vector2(job.pos)) <= 1.5:
			_status(sim, building, "building")
			saw_building = true
			break
	_check(saw_building and float(building.progress) > 0.0, "real normal ticks deliver the parcel and start real construction")
	worker.pos = Vector2(6, 11)
	_status(sim, building, "awaiting_arrival")
	sim.paused = true
	row = _status(sim, building, "awaiting_arrival")
	_check(row.paused, "pause is reported separately while preserving the underlying construction stage")
	sim.camps[0].state = "packing"
	_status(sim, building, "source_inactive")
	sim.camps[0].state = "active"
	job.funded = false
	_status(sim, building, "awaiting_payment")
	sim.camps[0].materials = 0.0
	_status(sim, building, "awaiting_materials")
	job.funded = true
	worker.hp = 0.0
	row = _status(sim, building, "awaiting_builder")
	_check(row.text.contains("材料已送达"), "delivered materials remain visible when the assigned builder becomes unavailable")
	job.done = true
	_status(sim, building, "cancelled")
	job.done = false
	worker.hp = 100.0
	worker.pos = Vector2(job.pos)
	building.kind = "exit"
	job.kind = "exit"
	building.powered = false
	_status(sim, building, "waiting_power")
	building.powered = true
	_status(sim, building, "building")
	sim._jobs.clear()
	_status(sim, building, "missing_job")
	building.progress = 1.0
	_check(Dictionary(rules.call("get_construction_status", sim, int(building.id))).is_empty(), "finished project has no stale construction detail")
	building.progress = 0.5
	building.hp = 0.0
	_check(Dictionary(rules.call("get_construction_status", sim, int(building.id))).is_empty(), "destroyed project has no stale construction detail")
