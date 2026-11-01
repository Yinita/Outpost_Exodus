extends SceneTree
## Headless presentation/input regression. Flat high-stock/loading/arrival
## fixtures are controlled states, not an ordinary campaign or native pixel test.
const Simulation = preload("res://scripts/campaign_simulation.gd")
class QuietMain:
	extends "res://scripts/main.gd"
	func _ready() -> void: pass
	func _play_tone(_frequency: float, _duration: float, _gain: float = 0.25) -> void: pass
	func _play_sfx(_cue: String, _gain: float = 1.0) -> void: pass
class QuietHud:
	extends "res://scripts/hud.gd"
	func _ready() -> void: pass
	func _draw() -> void: pass
class QuietWorld:
	extends "res://scripts/world_view.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _draw() -> void: pass
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/camp-card-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Camp card checks require isolated work/camp-card-data")
		quit(2)
		return
	for test: Callable in [_test_priority_and_current_input, _test_actual_last_trip_and_cache, _test_pager_and_small_viewport]:
		var previous: int = failures.size()
		test.call()
		print("%s %s" % ["PASS" if previous == failures.size() else "FAIL", test.get_method()])
	print("Camp card priority checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)
func _app(screen: Vector2i) -> Variant:
	var vp: SubViewport = SubViewport.new()
	vp.size = screen
	root.add_child(vp)
	var app: Variant = QuietMain.new()
	vp.add_child(app)
	app.set_process(false)
	app._setup_inputs()
	app.sim = Simulation.new()
	app.sim.reset(42)
	for y: int in range(app.sim.map_size.y):
		for x: int in range(app.sim.map_size.x): app.sim.terrain[y][x] = 0
	app.sim.camps = []
	app.sim.buildings = []
	app.sim.units = []
	app.sim.sites = []
	app.sim.effects = []
	app.sim.messages = []
	app.sim.chokes = []
	app.sim.roads = {}
	app.sim.ramps = {}
	app.sim._jobs = []
	app.sim._next_id = 10000
	app.sim.pursuit_x = -10000.0
	app.sim.pursuit_start = 1000000.0
	var home: Dictionary = app.sim._make_camp(Vector2(6, 10), "西营", 1000, 500, 100)
	home.recipe = "idle"
	app.sim._add_building("command", home.pos, int(home.id), 1.0)
	var truck: Dictionary = app.sim._add_unit("truck", "friendly", Vector2(5, 11), int(home.id), 0)
	app.sim.main_truck_id = int(truck.id)
	app.sim._invalidate_navigation()
	app.world = QuietWorld.new()
	app.world.sim = app.sim
	app.world.motion.reset(app.sim)
	app.add_child(app.world)
	app.hud = QuietHud.new()
	app.hud.main = app
	app.add_child(app.hud)
	app.hud.font = load("res://assets/fonts/NotoSansCJK-Regular.ttc")
	app.camera = Camera2D.new()
	app.add_child(app.camera)
	app.camera.position = Vector2(1200, 800)
	app.camera.zoom = Vector2.ONE
	app.started = true
	app.menu = ""
	app.selected_camp = int(home.id)
	app.selected_ids = [int(truck.id)]
	app.group_bindings = {2:[int(truck.id)]}
	app.speed = 3.0
	app.sim.paused = true
	app._refresh_camp_readouts(0.0, true)
	return app
func _state(app: Variant) -> String: return JSON.stringify(app.sim.save_state())
func _rows(app: Variant) -> Array: return app.hud._camp_cards_layout(app.get_viewport_rect().size).rows
func _click(app: Variant, p: Vector2, button: int = MOUSE_BUTTON_LEFT) -> bool:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = p
	event.button_index = button as MouseButton
	event.pressed = true
	return app.hud.handle_mouse(event)
func _retire(app: Variant) -> void: app.get_parent().free()
func _old_full_hotspots(app: Variant) -> void:
	app.hud.hotspots.clear()
	for index: int in range(mini(app.camp_page_size(), app.sim.camps.size())):
		app.hud.hotspots.append({"rect":Rect2(app.get_viewport_rect().size.x - 268, 82 + index * 102, 250, 91), "action":"camp:%d" % int(app.sim.camps[index].id), "tip":"old draw"})
func _test_priority_and_current_input() -> void:
	var app: Variant = _app(Vector2i(1600, 900))
	var a: Dictionary = app.sim.camps[0]
	var b: Dictionary = app.sim._make_camp(Vector2(22, 10), "中营", 0, 67, 43)
	var c: Dictionary = app.sim._make_camp(Vector2(40, 10), "前营", 100, 20, 18)
	a.state = "abandoned"
	b.state = "abandoned"
	app.selected_camp = int(c.id)
	app._refresh_camp_readouts(0.0, true)
	_old_full_hotspots(app)
	var before: String = _state(app)
	var rows: Array = _rows(app)
	_check(rows.size() == 3 and rows[0].rect.size.y == 52 and rows[1].rect.size.y == 52 and rows[2].rect.size.y == 91, "only unselected abandoned camps shrink; active stays full")
	_check(rows[1].stock.contains("遗留") and rows[1].stock.contains("67") and rows[1].tip.contains("库存"), "compact row retains abandoned inventory and detailed tip")
	var original_stock: Array = [a.materials, a.supplies, a.fuel]
	a.materials = 123456789.0
	a.supplies = 987654321.0
	a.fuel = 555666777.0
	var large_before: String = _state(app)
	var inventory_tip: String = _rows(app)[0].tip
	_check(inventory_tip.contains("遗留库存") and inventory_tip.contains("123456789") and inventory_tip.contains("987654321") and inventory_tip.contains("555666777") and _state(app) == large_before, "unclipped abandoned inventory tip retains all three large values without changing Sim/RNG")
	a.materials = original_stock[0]
	a.supplies = original_stock[1]
	a.fuel = original_stock[2]
	_check(rows[2].rect.position.y == 208, "two closed camps bring current camp upward by78 logical pixels")
	var freed: Vector2 = Vector2(1450, 340)
	_check(not app.hud.blocks_world_point(freed) and not _click(app, freed), "old larger camp hotspot and old invisible right column do not capture freed map")
	_check(app.hud.blocks_world_point(Vector2(1450, 140)), "small gap between actual visible cards still consumes input")
	_check(_state(app) == before, "layout and freed/gap queries preserve complete Sim and RNG")
	var groups: Dictionary = app.group_bindings.duplicate(true)
	var ids: Array = app.selected_ids.duplicate()
	_check(_click(app, Vector2(1450, 155)), "current second compact card consumes left click despite old first card occupying that pixel")
	_check(app.selected_camp == int(b.id), "fresh geometry selects the correct camp identity")
	_check(_rows(app)[1].rect.size.y == 91, "selected abandoned camp expands immediately")
	_check(app.selected_ids == ids and app.group_bindings == groups and app.speed == 3 and app.sim.paused, "camp browse preserves selected units/groups/speed/pause")
	_check(_state(app) == before, "selection/focus issues no simulation order and preserves full state/RNG")
	var selected: int = app.selected_camp
	_check(_click(app, Vector2(1450, 100), MOUSE_BUTTON_RIGHT) and app.selected_camp == selected, "right click on card is consumed without changing camp or issuing world order")
	app.hud.hotspots.clear()
	for menu: String in ["pause", "title"]:
		app.menu = menu
		_check(_click(app, Vector2(1450, 100)) and app.selected_camp == selected, menu + " with empty draw hotspots consumes without selecting underlying camp")
		_check(_state(app) == before, menu + " empty-hotspot modal preserves full Sim/RNG")
	app.menu = ""
	app.sim.camps = []
	app.selected_camp = 0
	_check(not app.hud.blocks_world_point(Vector2(1450, 100)), "no visible camps means no old camp hotspot or empty reserved column")
	_retire(app)
func _test_actual_last_trip_and_cache() -> void:
	var app: Variant = _app(Vector2i(1600, 900))
	var origin: Dictionary = app.sim.camps[0]
	var receiver: Dictionary = app.sim._make_camp(Vector2(22, 10), "实际接收营", 0, 0, 0)
	app.selected_camp = int(receiver.id)
	app._refresh_camp_readouts(0.0, true)
	_check(app.sim.evacuate_camp(int(origin.id)), "real public evacuation is admitted")
	_check(_rows(app)[0].rect.size.y == 91, "packing camp is full even before cache refresh")
	app.sim._update_evacuations(0.0)
	app.sim._update_evacuations(6.0)
	var truck: Dictionary = app.sim.get_unit(int(app.sim.main_truck_id))
	_check(truck.haul_stage == "outbound" and not Dictionary(truck.cargo).is_empty(), "controlled real loading created an actual outbound parcel")
	_check(app.sim.evacuate_camp(int(origin.id)), "second public request actually abandons origin")
	_check(not app.camp_readouts[int(origin.id)].has("transport_text"), "cached pre-order row deliberately lacks current final transport")
	var before: String = _state(app)
	var clock: float = app._camp_readout_clock
	var row: Dictionary = _rows(app)[0]
	_check(row.rect.size.y == 91 and row.readout.has("transport_text") and row.tip.contains(receiver.name), "fresh abandoned readout keeps final trip full and names real receiver")
	_check(row.readout.transport.cargo == truck.cargo, "height/body/tip share the same real parcel snapshot")
	row.readout.transport.cargo["fuel"] = 999999
	_check(_state(app) == before and app._camp_readout_clock == clock, "row copies cannot alias Sim cargo and do not advance global cache clock")
	var cargo: Dictionary = truck.cargo.duplicate(true)
	truck.cargo = {}
	_check(_rows(app)[0].rect.size.y == 91 and _rows(app)[0].readout.cargo_text.contains("空车"), "controlled outbound empty vehicle is still transport and never folded")
	truck.cargo = cargo
	_retire(app)
	# Separate admitted packing fixture: marker loss, without rewinding an
	# already-abandoned origin or assigning a fabricated transport order.
	app = _app(Vector2i(1600, 900))
	origin = app.sim.camps[0]
	receiver = app.sim._make_camp(Vector2(22, 10), "原接收营", 0, 0, 0)
	app.selected_camp = int(receiver.id)
	_check(app.sim.evacuate_camp(int(origin.id)), "fallback fixture uses a separate admitted evacuation")
	app.sim._update_evacuations(0.0)
	app.sim._update_evacuations(6.0)
	truck = app.sim.get_unit(int(app.sim.main_truck_id))
	var fallback: Dictionary = app.sim._make_camp(Vector2(40, 10), "后备接收营", 0, 0, 0)
	# Actual integrity fallback rule, as in the existing camp-readout regression.
	app.sim.buildings[0].hp = 0.0
	app.sim._update_camp_integrity()
	_check(origin.state == "abandoned" and int(truck.evac_destination_id) == int(fallback.id), "real marker-loss rule retargets final truck")
	row = _rows(app)[0]
	_check(row.rect.size.y == 91 and row.tip.contains(fallback.name) and int(row.readout.transport.destination_id) == int(fallback.id), "fresh final row follows actual fallback rather than stale origin target")
	app._refresh_camp_readouts(0.0, true)
	_check(app.camp_readouts[int(origin.id)].has("transport_text"), "cache now deliberately retains final trip")
	truck.pos = fallback.pos
	app.sim._update_evacuations(0.0)
	before = _state(app)
	row = _rows(app)[0]
	_check(row.rect.size.y == 52 and not row.readout.has("transport_text"), "real deposit retires trip and immediately folds despite old transport cache")
	_check(_state(app) == before, "post-delivery presentation preserves full Sim and RNG")
	_retire(app)
func _test_pager_and_small_viewport() -> void:
	for screen: Vector2i in [Vector2i(960, 540), Vector2i(1600, 900)]:
		var app: Variant = _app(screen)
		for index: int in range(1, 8): app.sim._make_camp(Vector2(6 + index * 8, 10), "营%d" % index, 0, index, 0)
		for camp: Dictionary in app.sim.camps: camp.state = "abandoned"
		app.selected_camp = int(app.sim.camps.back().id)
		var capacity: int = app.camp_page_size()
		var pages: int = app.camp_page_count()
		app.camp_page = 0
		var before: String = _state(app)
		var layout: Dictionary = app.hud._camp_cards_layout(Vector2(screen))
		_check(capacity == (2 if screen.y == 540 else 5) and app.camp_page_count() == pages, "existing conservative page capacity is unchanged at" + str(screen))
		_check(not layout.pager.is_empty() and layout.pager.origin.y == layout.rows.back().rect.end.y + 11, "pager follows actual visible stack at" + str(screen))
		var old_page: int = app.camp_page
		var rev: int = app._ui_revision
		_check(_click(app, layout.pager.previous.get_center()) and app.camp_page == old_page and app._ui_revision == rev, "disabled previous pager consumes without action at" + str(screen))
		_check(app.hud.blocks_world_point(layout.pager.origin + Vector2(90, 12)), "pager label/button gap consumes at" + str(screen))
		_check(_click(app, layout.pager.next.get_center()) and app.camp_page == 1, "enabled pager changes page using current geometry at" + str(screen))
		_check(app.selected_camp == int(app.sim.camps.back().id) and _state(app) == before, "page browse preserves selection and full Sim/RNG at" + str(screen))
		app.camp_page = pages - 1
		layout = app.hud._camp_cards_layout(Vector2(screen))
		_check(layout.rows.back().rect.size.y == 91 and layout.occupied.end.y < screen.y - 190, "selected last camp remains full and pager fits above dock at" + str(screen))
		_retire(app)
