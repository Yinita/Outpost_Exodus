extends SceneTree
## Headless controller/geometry checks in real logical SubViewports. Constructed
## HUD hit regions establish input eligibility, not native pixels or usability.
## XDG_DATA_HOME="$PWD/work/camera-viewport-data" Godot --headless --path .
##   --script res://tests/test_camera_viewport_bounds.gd
const Simulation = preload("res://scripts/campaign_simulation.gd")

class QuietMain:
	extends "res://scripts/main.gd"
	func _ready() -> void: pass
	func _play_tone(_frequency: float, _duration: float, _gain: float = 0.25) -> void: pass
	func _play_sfx(_cue: String, _gain: float = 1.0) -> void: pass

class QuietWorld:
	extends "res://scripts/world_view.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _draw() -> void: pass

class QuietHud:
	extends "res://scripts/hud.gd"
	func _ready() -> void: pass
	func _draw() -> void: pass

class RefuseRead:
	extends RefCounted
	func read(_path: String) -> Dictionary: return {"ok": false, "error": "controlled failure"}

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/camera-viewport-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Camera checks require isolated work/camera-viewport-data")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for test: Callable in [_test_full_view_and_small_maps, _test_focus_and_manual_input, _test_public_focus_and_minimap, _test_resize_and_stale_layout, _test_focus_escape_direction, _test_exact_load_and_new_run]:
		var previous: int = failures.size()
		test.call()
		print("%s %s" % ["PASS" if failures.size() == previous else "FAIL", test.get_method()])
	print("Camera viewport checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _app(screen: Vector2i) -> Variant:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = screen
	root.add_child(viewport)
	var app: Variant = QuietMain.new()
	viewport.add_child(app)
	app.set_process(false)
	app._setup_inputs()
	app.sim = Simulation.new()
	app.sim.reset(42)
	app.sim.paused = true
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
	app.started = true
	app.menu = ""
	app.selected_camp = int(app.sim.camps[0].id)
	app.guide.update(app.sim, [], app.selected_camp)
	app._camera_viewport_size = app.get_viewport_rect().size
	_layout(app)
	return app

func _layout(app: Variant) -> void:
	# Same occupied normal-HUD regions as a two-card page; the real pure HUD
	# query also supplies top/dock/left/project/preview hit testing.
	var screen: Vector2 = app.get_viewport_rect().size
	app.hud.hotspots.clear()
	app.hud.overlay_rects.clear()
	app.hud.overlay_rects.append(Rect2(screen.x - 268, 82, 250, 193))
	if screen.y < 744:
		app.hud.overlay_rects.append(Rect2(340, 186, minf(300, screen.x - 620), 34))
	app.hud.map_rect = Rect2(screen - Vector2(258, 172), Vector2(240, 154))
	app.hud.hotspots.append({"rect": app.hud.map_rect, "action": "minimap", "tip": ""})

func _retire(app: Variant) -> void:
	app.get_parent().free()

func _state(app: Variant) -> String:
	return JSON.stringify(app.sim.save_state())

func _normalized(value: Variant) -> String:
	# Identical to the native campaign verifier: JSON numbers become floats on
	# read. Keep exact values, complete structure and encoded entry-array order.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)

func _full_view(app: Variant, label: String) -> void:
	var screen: Vector2 = app.get_viewport_rect().size
	var half_view: Vector2 = screen * 0.5 / app.camera.zoom
	var extent: Vector2 = Vector2(app.sim.map_size) * 48.0
	for axis: int in range(2):
		if half_view[axis] * 2.0 <= extent[axis]:
			_check(app.camera.position[axis] - half_view[axis] >= -0.001 and app.camera.position[axis] + half_view[axis] <= extent[axis] + 0.001, label + " keeps complete view inside axis " + str(axis))
		else:
			_check(is_equal_approx(app.camera.position[axis], extent[axis] * 0.5), label + " centres the smaller map axis " + str(axis))

func _external_click_margin_clear(app: Variant, point: Vector2) -> bool:
	# External acceptance remains 16px; production uses an extra 1px guard.
	for offset: Vector2 in [Vector2.ZERO, Vector2(-16, -16), Vector2(16, -16), Vector2(-16, 16), Vector2(16, 16)]:
		if app.hud.blocks_world_point(point + offset): return false
	var screen: Vector2 = app.get_viewport_rect().size
	if app.feedback_left > 0.0 and Rect2(340, 82, maxf(300, screen.x - 670), 42).grow(16).has_point(point): return false
	if app.hud._pause_banner_visible() and app.hud.font != null:
		var width: float = maxf(220, app.hud.font.get_string_size(app.hud._pause_banner_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 32)
		if Rect2((screen.x - width) * 0.5, 138, width, 40).grow(16).has_point(point): return false
	return true

func _visible_focus(app: Variant, target: Vector2, label: String) -> void:
	var point: Vector2 = app.get_canvas_transform() * target
	_check(app.get_viewport_rect().has_point(point) and not app.hud.blocks_world_point(point), label + " projects to an interactive world point")
	_check(_external_click_margin_clear(app, point), label + " leaves a logical click margin")
	var base: Vector2 = app._bounded_camera_position(target, app.get_viewport_rect().size)
	var overscan: Vector2 = ((app.camera.position - base) * app.camera.zoom).abs()
	_check(overscan.x <= 335.01 and overscan.y <= 238.01, label + " bounds exceptional overscan by the HUD margins")
	# The current canvas inverse must agree immediately, before a process frame.
	_check((app.get_canvas_transform().affine_inverse() * point).distance_to(target) < 0.001, label + " retains the real world coordinate under the target")

func _test_full_view_and_small_maps() -> void:
	for screen: Vector2i in [Vector2i(1920, 1080), Vector2i(960, 540)]:
		var app: Variant = _app(screen)
		var saved: String = _state(app)
		var rng: int = app.sim._rng.state
		for map_size: Vector2i in [Vector2i(80, 40), Vector2i(8, 40), Vector2i(80, 5), Vector2i(8, 5)]:
			# Geometry-only fixtures: no ticks or orders use these reduced extents.
			app.sim.map_size = map_size
			for zoom: float in [0.35, 1.05, 1.6]:
				app.camera.zoom = Vector2.ONE * zoom
				for destination: Vector2 in [Vector2(-99999, -99999), Vector2(99999, 99999), Vector2(-99999, 99999), Vector2(99999, -99999)]:
					app._pan_camera(destination)
					_full_view(app, "%s %s zoom %s" % [screen, map_size, zoom])
		app.sim.map_size = Vector2i(80, 40)
		_check(_state(app) == saved and app.sim._rng.state == rng, "all camera-only geometry cases preserve exact saved Sim/RNG")
		_retire(app)

func _test_focus_and_manual_input() -> void:
	var app: Variant = _app(Vector2i(960, 540))
	app.camera.zoom = Vector2.ONE * 1.05
	var target: Vector2 = Vector2(app.sim.map_size) * 48.0 - Vector2(24, 120)
	var before: String = _state(app)
	var rng: int = app.sim._rng.state
	app._focus_camera(target)
	_visible_focus(app, target, "bottom-right compact focus")
	_check(app.camera.position != target, "an edge focus is not forced to exact centre")
	var focused: Vector2 = app.camera.position
	for frame: int in range(5): app._move_camera(0.1)
	_check(app.camera.position == focused, "idle camera frames preserve safe-focus overscan")
	Input.action_press("camera_right")
	app._move_camera(20.0)
	Input.action_release("camera_right")
	_full_view(app, "large keyboard movement")
	_check(app._camera_focus_target.x < 0.0, "manual keyboard movement retires focus")
	app._focus_camera(target)
	app.pan_active = true
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(99999, -99999)
	app._unhandled_input(motion)
	_full_view(app, "middle drag in the same input event")
	_check(app._camera_focus_target.x < 0.0, "middle drag retires focus")
	app.pan_active = false
	app._pan_camera(Vector2(1800, 1000))
	var anchor: Vector2 = app.get_global_mouse_position()
	app._zoom(1.12)
	_check(app.get_global_mouse_position().distance_to(anchor) < 0.001, "interior zoom retains the real mouse world anchor")
	_full_view(app, "interior zoom")
	app._focus_camera(target)
	app._zoom(0.01)
	_check(is_equal_approx(app.camera.zoom.x, app.MIN_CAMERA_ZOOM) and app._camera_focus_target.x < 0.0, "zoom limit remains legal and cancels special focus")
	_full_view(app, "edge zoom at the minimum")
	_check(_state(app) == before and app.sim._rng.state == rng, "movement, focus and zoom preserve full Sim/RNG")
	_retire(app)

func _test_public_focus_and_minimap() -> void:
	for screen: Vector2i in [Vector2i(1920, 1080), Vector2i(960, 540)]:
		var app: Variant = _app(screen)
		app.camera.zoom = Vector2.ONE * 1.05
		var unit: Dictionary = app.sim.get_unit(int(app.sim.main_truck_id))
		unit.pos = Vector2(app.sim.map_size) - Vector2(1, 5)
		unit.order = "move"
		unit.target = Vector2(20, 20)
		unit.cargo = {"materials": 9.0}
		var saved: String = _state(app)
		var rng: int = app.sim._rng.state
		var camp: int = app.selected_camp
		_check(app.focus_main_truck(), "public main-vehicle focus accepts live ID")
		_check(app.selected_ids == [int(unit.id)] and app.selected_camp == camp, "main focus selects only the actual vehicle and keeps camp selection")
		_visible_focus(app, Vector2(unit.pos) * 48.0, "main vehicle " + str(screen))
		app.focus_camp(camp)
		_visible_focus(app, Vector2(app.sim.get_camp(camp).pos) * 48.0, "camp " + str(screen))
		app.selected_ids = [int(unit.id)]
		app._focus_selection()
		_visible_focus(app, Vector2(unit.pos) * 48.0, "selection " + str(screen))
		app.guide._hint.target = Vector2(app.sim.map_size) - Vector2(1, 4)
		app.menu = "guide"
		app.ui_action("guide_focus")
		_check(app.menu.is_empty(), "guide modal closes before normal-HUD focus")
		_visible_focus(app, Vector2(app.guide._hint.target) * 48.0, "guide " + str(screen))
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = app.hud.map_rect.position + app.hud.map_rect.size * Vector2(0.99, 0.5)
		var tile: Vector2 = Vector2(app.sim.map_size) * Vector2(0.99, 0.5)
		app._unhandled_input(click)
		_visible_focus(app, tile * 48.0, "actual minimap dispatch " + str(screen))
		var focused: Vector2 = app.camera.position
		app.selected_ids = []
		click.button_index = MOUSE_BUTTON_RIGHT
		app._unhandled_input(click)
		_check(app.camera.position == focused, "minimap right click does not replace camera focus")
		_check(_state(app) == saved and app.sim._rng.state == rng, "all public focus routes preserve real orders/cargo and complete Sim/RNG")
		_retire(app)

func _test_resize_and_stale_layout() -> void:
	var app: Variant = _app(Vector2i(1920, 1080))
	app.camera.zoom = Vector2.ONE * 1.05
	var target: Vector2 = (Vector2(app.sim.map_size) - Vector2(1, 5)) * 48.0
	app._focus_camera(target)
	var before: String = _state(app)
	var rng: int = app.sim._rng.state
	app.get_viewport().size = Vector2i(960, 540)
	app.menu = "pause"
	app._process(0.0)
	_check(app.camera.position == app._bounded_camera_position(target, Vector2(960, 540)), "resize applies full bounds even behind a paused menu")
	app.menu = ""
	app._update_camera_viewport()
	_layout(app)
	# Invoke the same one-shot callback after replacing the prior draw regions.
	app._refresh_camera_focus_layout()
	_visible_focus(app, target, "new compact HUD after resize")
	var compact: Vector2 = app.camera.position
	for frame: int in range(5): app._update_camera_viewport()
	_check(app.camera.position == compact, "same logical viewport does not drift or normalize focus")
	app.construction_readout = {"building_id": 123}
	app._focus_camera(Vector2(1800, 900))
	_visible_focus(app, Vector2(1800, 900), "construction panel remains open and target usable")
	_check(not app.construction_readout.is_empty(), "safe focus does not close existing project details")
	_check(_state(app) == before and app.sim._rng.state == rng, "resize/menu/project focus preserve exact paused simulation/RNG")
	_retire(app)

func _test_focus_escape_direction() -> void:
	var app: Variant = _app(Vector2i(960, 540))
	app.camera.zoom = Vector2.ONE
	app.sim.paused = false
	var before: String = _state(app)
	var rng: int = app.sim._rng.state
	# The compact Guide covers projected (500,200). Up is a short escape into
	# ordinary camera bounds; down is a short escape out of those bounds.
	var target: Vector2 = Vector2(3380, 200)
	app._focus_camera(target)
	_visible_focus(app, target, "compact Guide escape")
	_full_view(app, "inward compact Guide escape")
	_check(app.camera.position.y > 270.0, "focus considers the short upper edge, not just the nearest distant anchor")
	# Below the last right card there is usable world space at the same X.
	# A horizontal-only escape would add over 250px; down needs about 32px.
	target = Vector2(3810, 260)
	app._focus_camera(target)
	_visible_focus(app, target, "short vertical escape from right camp cards")
	var base: Vector2 = app._bounded_camera_position(target, Vector2(960, 540))
	_check(app.camera.position.x == base.x and absf(app.camera.position.y - base.y) < 40.0, "safe focus uses the smaller necessary exceptional offset")
	app.sim.paused = true
	app.feedback_left = 5.0
	app._focus_camera(Vector2(3380, 200))
	var projected: Vector2 = app.get_canvas_transform() * Vector2(3380, 200)
	_check(not Rect2(340, 82, 300, 42).grow(16).has_point(projected), "visible notification does not cover the focus marker")
	var width: float = maxf(220, app.hud.font.get_string_size(app.hud._pause_banner_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 32)
	_check(not Rect2((960 - width) * 0.5, 138, width, 40).grow(16).has_point(projected), "visible tactical-pause banner does not cover the focus marker")
	app.sim.paused = false
	_check(_state(app) == before and app.sim._rng.state == rng, "all escape-direction queries preserve full Sim/RNG")
	_retire(app)

func _test_exact_load_and_new_run() -> void:
	var app: Variant = _app(Vector2i(960, 540))
	app.camera.position = Vector2(-432.25, 5432.5)
	app.camera.zoom = Vector2.ONE * app.MIN_CAMERA_ZOOM
	var saved_position: Vector2 = app.camera.position
	var saved_zoom: Vector2 = app.camera.zoom
	var before: String = _normalized(app.sim.save_state())
	var saved_ui: String = _normalized(app._save_payload().ui)
	var rng: int = app.sim._rng.state
	_check(app.save_campaign(), "public SaveStore writes an old-style finite overscan view")
	app._focus_camera(Vector2(3000, 1000))
	_check(app.load_campaign(), "public load restores the actual isolated save")
	_check(app.camera.position == saved_position and app.camera.zoom == saved_zoom and app._camera_focus_target.x < 0.0, "load retains exact camera/zoom and clears unsaved focus")
	for frame: int in range(5): app._process(0.0)
	_check(app.camera.position == saved_position and app.camera.zoom == saved_zoom, "idle paused frames do not rewrite the loaded view")
	app.menu = "pause"
	app._process(0.0)
	app.menu = ""
	app._process(0.0)
	app._refresh_camera_focus_layout()
	_check(app.camera.position == saved_position, "menus and stale pending focus callback preserve loaded exact camera")
	_check(_normalized(app.sim.save_state()) == before and app.sim._rng.state == rng, "real save/load and idle camera preserve complete normalized paused Sim/RNG")
	_check(_normalized(app._save_payload().ui) == saved_ui, "real save/load and idle frames retain the complete normalized UI payload")
	var store: RefCounted = app.save_store
	app._focus_camera(Vector2(3600, 500))
	var focus: Vector2 = app._camera_focus_target
	var position: Vector2 = app.camera.position
	app.save_store = RefuseRead.new()
	_check(not app.load_campaign() and app.camera.position == position and app._camera_focus_target == focus, "failed load leaves the previous view and focus intact")
	app.save_store = store
	_check(app.load_campaign(), "original valid save can still be loaded")
	app.get_viewport().size = Vector2i(1920, 1080)
	app._update_camera_viewport()
	_full_view(app, "first actual viewport change after load")
	_check(app.camera.position != saved_position, "actual resize adopts the new bounds")
	app.start_campaign("delta")
	_full_view(app, "new campaign")
	_check(app._camera_focus_target.x < 0.0 and app.sim.mission_id == "delta", "restart clears old mission focus without adding saved fields")
	_retire(app)
