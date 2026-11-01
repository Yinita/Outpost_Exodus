extends SceneTree
## Synthetic native rendering/input regression, not a human playtest or benchmark.
## DISPLAY=:92 XDG_DATA_HOME="$PWD/work/macro-controls-data" Godot --path .
##   --audio-driver Dummy --script res://tests/test_macro_controls.gd

var app: Variant
var checks: int = 0
var failures: Array[String] = []
var saved_mouse: Vector2i
var last_mouse: Vector2 = Vector2.ZERO
var finishing: bool = false
var case_completed: bool = false
var fixture_camp_ids: Array[int] = []
var screenshot_paths: Array[String] = []

func _focus_visible(world: Vector2) -> bool:
	var point: Vector2 = app.get_canvas_transform() * world
	return app.get_viewport_rect().grow(-16).has_point(point) and not app.hud.blocks_world_point(point)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/macro-controls-data").trim_suffix("/")
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Macro controls require native DISPLAY and isolated work/macro-controls-data")
		quit(2)
		return
	saved_mouse = DisplayServer.mouse_get_position()
	create_timer(150.0).timeout.connect(_deadline)
	AudioServer.set_bus_mute(0, true)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	root.content_scale_factor = 1.0
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await _frames(8)
	app.set_process(false)
	var cases: Array[Callable] = [_test_camp_pagination, _test_disabled_camp_pager_isolation, _test_camp_selection_and_rebinding, _test_camp_status_detail, _test_training_layout_and_status, _test_targeting_and_tabs, _test_small_range_toggle]
	if OS.get_cmdline_user_args().has("--pager-only"): cases = [_test_disabled_camp_pager_isolation]
	elif OS.get_cmdline_user_args().has("--status-only"): cases = [_test_camp_status_detail]
	for test_case: Callable in cases:
		var previous: int = failures.size()
		case_completed = false
		await test_case.call()
		_check(case_completed, "case reaches its completion guard: " + test_case.get_method())
		print("%s %s" % ["PASS" if failures.size() == previous else "FAIL", test_case.get_method()])
	await _finish()

func _deadline() -> void:
	if finishing: return
	_check(false, "150 second deadline reached; test coroutine may have failed")
	await _finish()

func _finish() -> void:
	if finishing: return
	finishing = true
	print("Macro control checks: %d; failures: %d" % [checks, failures.size()])
	print("Isolated user data: ", OS.get_user_data_dir())
	for path: String in screenshot_paths: print("Screenshot: ", path)
	for message: String in failures: printerr(" - ", message)
	if is_instance_valid(app):
		app.set_process(false)
		app.set_process_unhandled_input(false)
		app._release_audio()
		var audio_deadline: int = Time.get_ticks_usec() + 120000
		while Time.get_ticks_usec() < audio_deadline:
			await process_frame
		app.queue_free()
		app = null
	root.content_scale_factor = 1.0
	for frame: int in range(8): await process_frame
	DisplayServer.warp_mouse(saved_mouse)
	quit(0 if failures.is_empty() else 1)

func _reset() -> void:
	app.start_campaign("canyon")
	app.set_process(false)
	app.sim.paused = true
	app.edge_scroll = false
	app.guide.reset(false)
	app.guide.reset(false)
	app.menu = ""
	app.feedback_left = 0.0
	app.last_sim_message = ""
	await _frames()

func _frames(count: int = 2) -> void:
	for frame: int in range(count):
		if is_instance_valid(app):
			app._process(0.0)
			app.hud.queue_redraw()
			app.world.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw

func _size(physical: Vector2i, scale: float) -> void:
	root.size = physical
	root.content_scale_size = physical
	root.content_scale_factor = scale
	await _frames(4)
	_check(root.size == physical, "native window reaches " + str(physical))
	_check(app.get_viewport_rect().size.is_equal_approx(Vector2(physical) / scale), "logical viewport respects UI scale " + str(scale))

func _motion(point: Vector2) -> void:
	root.warp_mouse(point)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - last_mouse
	last_mouse = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(1)

func _click(point: Vector2) -> void:
	await _motion(point)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(1)

func _key(code: Key, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(1)

func _hotspot(action: String) -> Dictionary:
	for hotspot: Dictionary in app.hud.hotspots:
		if String(hotspot.action) == action: return hotspot
	return {}

func _click_action(action: String) -> bool:
	await _frames(1)
	var hotspot: Dictionary = _hotspot(action)
	_check(not hotspot.is_empty(), "rendered clickable action exists: " + action)
	if hotspot.is_empty(): return false
	_check(app.get_viewport_rect().encloses(hotspot.rect), "clicked action is within logical viewport: " + action)
	await _click(hotspot.rect.get_center())
	return true

func _visible_camps() -> Array[int]:
	var result: Array[int] = []
	for hotspot: Dictionary in app.hud.hotspots:
		if String(hotspot.action).begins_with("camp:"):
			result.append(int(String(hotspot.action).trim_prefix("camp:")))
	return result

func _snapshot() -> String:
	return JSON.stringify(app.sim.save_state(), "", true, true)

func _six_camps() -> void:
	fixture_camp_ids.clear()
	var first: Dictionary = app.sim.camps[0]
	first.name = "旧营地一"
	fixture_camp_ids.append(int(first.id))
	for index: int in range(1, 6):
		var camp: Dictionary = app.sim._make_camp(Vector2(12 + index * 7, 20), "审计营地%d" % (index + 1), 120.0 + index, 80.0 + index, 30.0 + index)
		fixture_camp_ids.append(int(camp.id))
	for index: int in range(3): app.sim.camps[index].state = "abandoned"
	app.sim.camps[4].state = "packing"
	app.focus_camp(fixture_camp_ids[5])

func _test_camp_pagination() -> void:
	await _reset()
	_six_camps()
	var configurations: Array = [[Vector2i(1600, 900), 1.0], [Vector2i(1152, 648), 1.0], [Vector2i(1152, 648), 1.2]]
	for configuration: Array in configurations:
		await _size(configuration[0], configuration[1])
		app.focus_camp(fixture_camp_ids[5])
		await _frames()
		_check(_visible_camps().has(fixture_camp_ids[5]), "selected sixth camp remains visible after resize " + str(configuration))
		var selected: int = app.selected_camp
		var snapshot: String = _snapshot()
		while not _hotspot("camp_page_prev").is_empty(): await _click_action("camp_page_prev")
		var visited: Array[int] = []
		var pages: int = 0
		while pages < 10:
			for camp_id: int in _visible_camps():
				if not visited.has(camp_id): visited.append(camp_id)
			for hotspot: Dictionary in app.hud.hotspots:
				if String(hotspot.action).begins_with("camp:") or String(hotspot.action).begins_with("camp_page_") or hotspot.action == "camp_cycle":
					_check(app.get_viewport_rect().encloses(hotspot.rect) and hotspot.rect.end.y < app.get_viewport_rect().size.y - 190.0, "camp card/pager fits above dock: " + String(hotspot.action))
			var page: int = app.camp_page
			await _frames(4)
			_check(app.camp_page == page and app.selected_camp == selected, "manual browsing does not snap back or select a different camp")
			pages += 1
			if _hotspot("camp_page_next").is_empty(): break
			await _click_action("camp_page_next")
		visited.sort()
		var expected: Array[int] = fixture_camp_ids.duplicate()
		expected.sort()
		_check(visited == expected, "all six camps, including three abandoned camps, remain accessible " + str(configuration))
		_check(_snapshot() == snapshot, "camp browsing leaves simulation unchanged")
		for camp_id: int in fixture_camp_ids:
			app.focus_camp(camp_id)
			await _frames(1)
			await _click_action("camp:%d" % camp_id)
			_check(app.selected_camp == camp_id and _focus_visible(Vector2(app.sim.get_camp(camp_id).pos) * 48.0), "real camp card exposes the requested camp outside the HUD")
	# A stale/out-of-range page must recover on a normal frame after resize.
	app.camp_page = 99
	await _size(Vector2i(1600, 900), 1.0)
	_check(app.camp_page >= 0 and app.camp_page < app.camp_page_count(), "resize clamps stale camp page into a rendered range")
	await _capture("camps-1600.png")
	case_completed = true

func _point_for_tile(tile: Vector2) -> Vector2:
	return app.world.get_global_transform_with_canvas() * (tile * 48.0)

func _test_disabled_camp_pager_isolation() -> void:
	await _size(Vector2i(1152, 648), 1.2)
	await _reset()
	_six_camps()
	await _frames()
	while not _hotspot("camp_page_prev").is_empty(): await _click_action("camp_page_prev")
	var pager: Vector2 = Vector2(app.get_viewport_rect().size.x - 268, 82 + app.camp_page_size() * 102)
	var points: Array[Vector2] = [pager + Vector2(36, 13.5), pager + Vector2(136, 13.5)]
	_check(_hotspot("camp_page_prev").is_empty(), "first-page previous control is disabled for isolation check")
	for index: int in range(3):
		if index == 2:
			while not _hotspot("camp_page_next").is_empty(): await _click_action("camp_page_next")
			_check(_hotspot("camp_page_next").is_empty(), "last-page next control is disabled for isolation check")
		var point: Vector2 = points[index] if index < 2 else pager + Vector2(214, 13.5)
		app.ui_action("task:guard")
		var snapshot: String = _snapshot()
		var selection: Array = app.selected_ids.duplicate()
		var selected_camp: int = app.selected_camp
		var page: int = app.camp_page
		await _click(point)
		_check(_snapshot() == snapshot, "disabled pager/blank click cannot issue a world task: %d" % index)
		_check(app.pending_task == "guard" and not app.dragging, "pager click retains targeting without world drag: %d" % index)
		_check(app.selected_ids == selection and app.selected_camp == selected_camp and app.camp_page == page, "pager non-action preserves selection and browsing: %d" % index)
		app._cancel_pointer_modes()
	await _capture("camp-pager-isolation-960.png")
	case_completed = true

func _camera_for_tile(tile: Vector2) -> void:
	# Keep the chosen world target in the unobstructed center, away from side HUD.
	app.camera.position = tile * 48.0
	app.camera.force_update_scroll()
	await _frames(2)

func _test_camp_selection_and_rebinding() -> void:
	await _size(Vector2i(1600, 900), 1.0)
	await _reset()
	_six_camps()
	var unit: Dictionary = app.sim.get_unit(app.selected_ids[0])
	unit.camp_id = fixture_camp_ids[5]
	await _camera_for_tile(unit.pos)
	while not _hotspot("camp_page_prev").is_empty(): await _click_action("camp_page_prev")
	await _click(_point_for_tile(unit.pos))
	_check(app.selected_ids.has(int(unit.id)) and app.selected_camp == fixture_camp_ids[5] and _visible_camps().has(fixture_camp_ids[5]), "engine unit selection re-exposes selected camp even when its ID was unchanged")
	var camp: Dictionary = app.sim.get_camp(fixture_camp_ids[5])
	var empty_tile: Vector2 = Vector2(camp.pos) + Vector2(0, 2)
	await _camera_for_tile(empty_tile)
	while not _hotspot("camp_page_prev").is_empty(): await _click_action("camp_page_prev")
	await _click(_point_for_tile(empty_tile))
	_check(app.selected_ids.is_empty() and app.selected_camp == int(camp.id) and _visible_camps().has(int(camp.id)), "ordinary world camp click re-exposes same-ID selected camp")
	while not _hotspot("camp_page_prev").is_empty(): await _click_action("camp_page_prev")
	await _key(KEY_HOME)
	_check(_visible_camps().has(int(camp.id)), "focus shortcut re-exposes same-ID selected camp")
	var expected_cycle: Array[int] = [fixture_camp_ids[3], fixture_camp_ids[4], fixture_camp_ids[5]]
	for camp_id: int in expected_cycle:
		await _key(KEY_HOME, true)
		_check(app.selected_camp == camp_id and _visible_camps().has(camp_id), "Shift focus cycles active/packing camps and skips abandoned camps")
	var binding: InputEventKey = InputEventKey.new()
	binding.physical_keycode = KEY_J
	_check(app._try_bind("focus_command", binding), "focus command accepts a nonconflicting replacement binding")
	var selected: int = app.selected_camp
	await _key(KEY_HOME, true)
	_check(app.selected_camp == selected, "old Shift focus key stops cycling after rebinding")
	await _key(KEY_J, true)
	_check(app.selected_camp == fixture_camp_ids[3], "rebound Shift focus key cycles through the real action map")
	binding.physical_keycode = KEY_HOME
	_check(app._try_bind("focus_command", binding), "focus binding restored inside isolated preferences")
	case_completed = true

func _training_fixture() -> Dictionary:
	var camp: Dictionary = app.sim.camps[0]
	camp.name = "本地训练营"
	camp.materials = 500.0
	camp.supplies = 400.0
	camp.fuel = 100.0
	camp.power_capacity = 50.0
	var barracks: Dictionary = app.sim._add_building("barracks", Vector2(camp.pos) + Vector2(1, 1), int(camp.id), 1.0)
	barracks.powered = true
	return barracks

func _test_camp_status_detail() -> void:
	await _reset()
	_training_fixture()
	var camp: Dictionary = app.sim.camps[0]
	app.ui_action("recruit:rifle")
	_check(Array(camp.recruit_queue).size() == 1, "status fixture has an actually admitted local training order")
	# Synthetic power-loss setup; input/rendering assertions below are not a
	# construction, economic or full-playthrough claim.
	camp.fuel = 0.0
	app.sim._update_power(0.0)
	app.ui_action("recipe:materials")
	for configuration: Array in [[Vector2i(1600, 900), 1.0], [Vector2i(1152, 648), 1.2]]:
		await _size(configuration[0], configuration[1])
		var snapshot: String = _snapshot()
		var row: Dictionary = app.camp_readouts[int(camp.id)]
		_check(row.code == "training_waiting_power" and row.severity == "attention" and String(row.text).begins_with("Ⅱ "), "paused card preserves actual admitted-training power blocker")
		var card: Dictionary = _hotspot("camp:%d" % int(camp.id))
		_check(not card.is_empty(), "blocked camp retains its full rendered card action")
		if card.is_empty(): continue
		await _motion(card.rect.get_center())
		_check(app.hud.tooltip.contains("成品燃料") and app.hud.tooltip.contains("战术暂停"), "actual camp hover shows paused fuel cause instead of only a generic pause")
		_check(not app.hud.overlay_rects.is_empty() and app.get_viewport_rect().encloses(app.hud.overlay_rects.back()), "rendered full camp detail fits inside the logical viewport")
		await _capture("camp-status-%d-%d.png" % [configuration[0].x, int(configuration[1] * 100)], true)
		_check(_snapshot() == snapshot, "hovering and drawing full camp status preserve simulation and RNG")
	case_completed = true

func _test_training_layout_and_status() -> void:
	await _reset()
	var barracks: Dictionary = _training_fixture()
	var camp: Dictionary = app.sim.camps[0]
	for configuration: Array in [[Vector2i(1600, 900), 1.0], [Vector2i(1152, 648), 1.0], [Vector2i(1152, 648), 1.2]]:
		await _size(configuration[0], configuration[1])
		await _click_action("tab:training")
		var cards: Array[Rect2] = []
		for kind: String in ["rifle", "engineer", "worker", "truck"]:
			var hotspot: Dictionary = _hotspot("recruit:" + kind)
			_check(not hotspot.is_empty(), "responsive training retains " + kind + " card")
			if hotspot.is_empty(): continue
			cards.append(hotspot.rect)
			_check(app.get_viewport_rect().encloses(hotspot.rect) and hotspot.rect.end.x < app.hud.map_rect.position.x, "training card is fully visible before minimap: " + kind)
			var plan: Dictionary = app.recruit_plans[kind]
			_check(float(plan.duration) > 0 and not plan.costs.is_empty() and not String(plan.facility).is_empty() and not String(plan.unit_name).is_empty(), "displayed recruitment metadata includes unit, local price, facility and duration: " + kind)
		var queue_rect: Rect2 = app.hud.training_queue_rect
		_check(queue_rect.has_area() and app.get_viewport_rect().encloses(queue_rect) and queue_rect.end.x < app.hud.map_rect.position.x, "actual queue tooltip geometry fits before minimap")
		for rect: Rect2 in cards: _check(not rect.intersects(queue_rect), "queue geometry does not overlap recruitment card")
		_check(app.training_readout.code == "idle", "empty queue exposes its actual idle status")
		await _motion(queue_rect.get_center())
		_check(app.hud.tooltip == app.training_readout.detail, "actual queue hover exposes full displayed detail")
		await _capture("training-%d-%d.png" % [configuration[0].x, int(configuration[1] * 100)])
	# Enqueue through the rendered card, then observe all real head statuses.
	app.sim.paused = false
	await _click_action("recruit:rifle")
	_check(camp.recruit_queue.size() == 1 and app.training_readout.code == "training", "rendered rifle card creates an actual running local order")
	var entry: Dictionary = camp.recruit_queue[0]
	entry.elapsed = 5.0
	entry.progress = 0.25
	app._ui_revision += 1
	await _frames()
	_check(is_equal_approx(float(app.training_readout.progress), 0.25) and is_equal_approx(float(app.training_readout.remaining), 15.0) and app.training_readout.current_name == "步枪兵", "queue metadata identifies the head and its actual elapsed/remaining training")
	barracks.powered = false
	app._ui_revision += 1
	await _frames()
	_check(app.training_readout.code == "waiting_power" and not String(app.training_readout.detail).is_empty(), "lost facility power produces actionable waiting status")
	app.sim.paused = true
	await _frames()
	_check(app.training_readout.code == "paused" and is_equal_approx(float(app.training_readout.progress), 0.25), "pause status preserves queue progress and identifies pause")
	barracks.powered = true
	camp.recruit_queue = []
	camp.materials = 20.0
	camp.supplies = 18.0
	app._ui_revision += 1
	await _frames()
	_check(app.recruit_plans.rifle.ok, "initial displayed local price is affordable")
	var queue_before: int = camp.recruit_queue.size()
	camp.supplies = 17.995
	var materials_before: float = camp.materials
	await _click_action("recruit:rifle")
	_check(camp.recruit_queue.size() == queue_before and is_equal_approx(float(camp.materials), materials_before), "fresh click rejects newly unaffordable local order without charging")
	_check(app.feedback.contains("不足0.01") and app.feedback.contains("本地训练营") and app.feedback.contains("补给"), "fresh recruitment rejection names local camp and sub-cent shortage precisely")
	camp.supplies = 18.0
	await _click_action("recruit:rifle")
	_check(camp.recruit_queue.size() == queue_before + 1 and is_zero_approx(float(camp.materials)) and is_zero_approx(float(camp.supplies)), "fresh click accepts restored stock and pays exact local costs once")
	_check(app.feedback.contains("步枪兵") and app.feedback.contains("本地训练营"), "successful order feedback names actual unit and camp")
	await _capture("training-paused-960.png")
	case_completed = true

func _no_modes() -> bool:
	return app.build_kind.is_empty() and app.pending_task.is_empty() and not app.attack_move

func _gold_pixels(rect: Rect2) -> int:
	var frame: Image = root.get_texture().get_image()
	var scale: Vector2 = Vector2(frame.get_size()) / app.get_viewport_rect().size
	var pixels: Rect2i = Rect2i(rect.position * scale, rect.size * scale).intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	var result: int = 0
	for y: int in range(pixels.position.y, pixels.end.y):
		for x: int in range(pixels.position.x, pixels.end.x):
			var color: Color = frame.get_pixel(x, y)
			if color.r > 0.7 and color.g > 0.4 and color.g < 0.85 and color.b < 0.55: result += 1
	return result

func _test_targeting_and_tabs() -> void:
	await _size(Vector2i(1600, 900), 1.0)
	await _reset()
	var unit: Dictionary = app.sim.get_unit(app.selected_ids[0])
	await _camera_for_tile(unit.pos)
	app.ui_action("build:generator")
	await _key(KEY_X)
	_check(app.attack_move and app.build_kind.is_empty() and app.pending_task.is_empty(), "Build then X arms attack move exclusively")
	app.ui_action("tab:orders")
	await _frames()
	await _click_action("task:clear")
	await _key(KEY_X)
	_check(app.attack_move and app.pending_task.is_empty() and app.build_kind.is_empty(), "Task then X removes old task and arms attack move exclusively")
	var target: Vector2 = Vector2(unit.pos) + Vector2(2, 0)
	await _click(_point_for_tile(target))
	_check(_no_modes() and unit.order == "attack_move", "one explicit attack click issues and consumes exactly one attack order")
	var actual_target: Vector2 = unit.target
	await _click(_point_for_tile(unit.pos))
	_check(app.selected_ids.has(int(unit.id)) and Vector2(unit.target).is_equal_approx(actual_target), "following ordinary click selects without dispatching an old task")
	for input_kind: String in ["mouse", "key"]:
		for mode: String in ["build", "task", "attack"]:
			app.selected_ids = [unit.id]
			if mode == "build": app.ui_action("build:road")
			elif mode == "task": app.ui_action("task:guard")
			else: await _key(KEY_X)
			if input_kind == "mouse": await _click_action("tab:production")
			else: await _key(KEY_N)
			_check(_no_modes(), input_kind + " tab change cancels " + mode + " targeting")
			var before: Vector2 = unit.target
			await _click(_point_for_tile(unit.pos))
			_check(app.selected_ids.has(int(unit.id)) and Vector2(unit.target).is_equal_approx(before), "ordinary world click after tab selects instead of commanding " + mode)
	await _click_action("tab:orders")
	app.feedback_left = 0.0
	await _frames()
	var normal_gold: int = _gold_pixels(Rect2(30, 326, 270, 49))
	await _click_action("task:guard")
	app.feedback_left = 0.0
	await _motion(Vector2(800, 70))
	await _frames(3)
	var pending_gold: int = _gold_pixels(Rect2(30, 326, 270, 49))
	_check(app.pending_task == "guard" and pending_gold > normal_gold + 40, "native selection-panel targeting cue remains gold after notification expires")
	var task_rect: Rect2 = _hotspot("task:guard").rect
	_check(_gold_pixels(Rect2(task_rect.position + Vector2(2, 2), Vector2(task_rect.size.x - 4, 3))) > 10, "active pending task has a gold button border")
	await _capture("pending-task-persistent.png")
	await _key(KEY_ESCAPE)
	_check(_no_modes() and app.menu.is_empty(), "Escape clears pending task before opening pause menu")
	case_completed = true

func _test_small_range_toggle() -> void:
	await _size(Vector2i(1152, 648), 1.2)
	await _reset()
	await _click_action("tab:orders")
	var hotspot: Dictionary = _hotspot("ranges")
	_check(not hotspot.is_empty() and not hotspot.rect.intersects(app.hud.map_rect), "small logical viewport keeps range toggle outside minimap")
	var camera_before: Vector2 = app.camera.position
	var previous: bool = app.world.show_ranges
	await _click_action("ranges")
	_check(app.world.show_ranges != previous and app.camera.position.is_equal_approx(camera_before), "actual small-screen range click toggles coverage without panning minimap")
	await _capture("range-toggle-960.png")
	case_completed = true

func _capture(name: String, keep_mouse: bool = false) -> void:
	var directory: String = ProjectSettings.globalize_path("res://work/macro-controls")
	DirAccess.make_dir_recursive_absolute(directory)
	if not keep_mouse: await _motion(Vector2(app.get_viewport_rect().size.x * 0.5, 70))
	await _frames()
	var path: String = directory.path_join(name)
	_check(root.get_texture().get_image().save_png(path) == OK, "native screenshot saved: " + name)
	screenshot_paths.append(path)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
