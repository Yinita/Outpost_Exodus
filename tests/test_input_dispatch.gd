extends SceneTree
## Rendered engine-event integration. No direct main selection/input or HUD calls.
## Buttons enter Viewport.push_input; motion/keys enter Input.parse_input_event.
## Native Window cursor queries require aligning the test cursor with warp_mouse.
## This is still synthetic engine dispatch, not native hardware/human usability.
## DISPLAY=:0 XDG_DATA_HOME="$PWD/work/input-dispatch-data" Godot --path .
##   --audio-driver Dummy --script res://tests/test_input_dispatch.gd

var app: Variant
var checks: int = 0
var failures: Array[String] = []
var last_mouse: Vector2 = Vector2.ZERO
var saved_screen_mouse: Vector2i = Vector2i.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/input-dispatch-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Refusing input test outside isolated XDG_DATA_HOME: ", OS.get_user_data_dir())
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("Engine input dispatch test requires a real rendering display")
		quit(2)
		return
	saved_screen_mouse = DisplayServer.mouse_get_position()
	var main_script: Script = load("res://scripts/main.gd") as Script
	if main_script == null or not main_script.can_instantiate():
		printerr("Main controller cannot compile")
		quit(1)
		return
	var constants: Dictionary = main_script.get_script_constant_map()
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for key: String in ["SAVE_PATH", "AUTOSAVE_PATH", "CONFIG_PATH"]:
		var path: String = String(constants[key])
		for suffix: String in ["", ".bak", ".tmp"]:
			var absolute: String = ProjectSettings.globalize_path(path + suffix)
			if not absolute.begins_with(isolated + "/"):
				printerr("Refusing nonisolated fixture file: ", absolute)
				quit(2)
				return
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(absolute)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	root.content_scale_factor = 1.0
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	app = scene.instantiate()
	root.add_child(app)
	await _frames(12)
	_check(root.size == Vector2i(1600, 900) and DisplayServer.get_name() != "headless", "test has a real 1600 x 900 rendering window")
	var cases: Array[Callable] = [
		_test_new_game_and_keyboard_dispatch,
		_test_single_shift_and_box_selection,
		_test_right_click_orders,
		_test_release_over_hud,
		_test_middle_release_over_hud,
		_test_menu_blocks_combat_dispatch,
		_test_double_click_visible_same_kind,
	]
	for test_case: Callable in cases:
		var previous: int = failures.size()
		await test_case.call()
		print("%s %s" % ["PASS" if failures.size() == previous else "FAIL", test_case.get_method()])
	await _capture()
	print("Engine input dispatch checks: %d; failures: %d" % [checks, failures.size()])
	print("Isolated user data: ", OS.get_user_data_dir())
	for failure: String in failures:
		printerr(" - " + failure)
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
		await process_frame
	Input.warp_mouse(Vector2(saved_screen_mouse))
	await _frames(6)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _frames(count: int = 2) -> void:
	for index: int in range(count):
		if is_instance_valid(app) and app.hud != null:
			app.hud.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw


func _motion(point: Vector2, buttons: MouseButtonMask = 0, shift: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - last_mouse
	event.button_mask = buttons
	event.shift_pressed = shift
	last_mouse = point
	# Native root Windows query DisplayServer, not synthetic Input mouse state.
	# Align this window's cursor, then exercise the real engine event pipeline.
	root.warp_mouse(point)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(1)


func _button(point: Vector2, button: MouseButton, pressed: bool, shift: bool = false, double_click: bool = false) -> void:
	await _motion(point, _mask(button) if pressed else 0, shift)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.button_mask = _mask(button) if pressed else 0
	event.pressed = pressed
	event.shift_pressed = shift
	event.double_click = double_click
	root.push_input(event, true)
	await _frames()


func _mask(button: MouseButton) -> MouseButtonMask:
	if button == MOUSE_BUTTON_LEFT:
		return MOUSE_BUTTON_MASK_LEFT
	if button == MOUSE_BUTTON_RIGHT:
		return MOUSE_BUTTON_MASK_RIGHT
	if button == MOUSE_BUTTON_MIDDLE:
		return MOUSE_BUTTON_MASK_MIDDLE
	return 0


func _key_event(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = pressed and code == KEY_SHIFT
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()


func _key(code: Key) -> void:
	await _key_event(code, true)
	await _key_event(code, false)


func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	if shift:
		await _key_event(KEY_SHIFT, true)
	await _button(point, button, true, shift, false)
	await _button(point, button, false, shift, false)
	if shift:
		await _key_event(KEY_SHIFT, false)


func _click_action(action: String) -> bool:
	await _frames()
	for hotspot: Dictionary in app.hud.hotspots:
		if String(hotspot.get("action", "")) == action:
			var rectangle: Rect2 = hotspot["rect"]
			_check(app.hud.get_viewport_rect().encloses(rectangle), "engine-clicked hotspot is visible: " + action)
			await _click(rectangle.get_center())
			return true
	_check(false, "real rendered action exists: " + action)
	return false


func _tile_screen(tile: Vector2) -> Vector2:
	return app.world.get_global_transform_with_canvas() * (tile * 48.0)


func _rifles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: Dictionary in app.sim.units:
		if String(unit.get("team", "")) == "friendly" and String(unit.get("kind", "")) == "rifle" and float(unit.get("hp", 0.0)) > 0.0:
			result.append(unit)
	return result


func _ids(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	result.sort()
	return result


func _simulation_snapshot() -> String:
	return JSON.stringify(app.sim.save_state(), "", true, true)


func _minimap(tile: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await _frames()
	var rectangle: Rect2 = app.hud.map_rect
	var point: Vector2 = rectangle.position + tile / Vector2(app.sim.map_size) * rectangle.size
	await _click(point, button)


func _test_new_game_and_keyboard_dispatch() -> void:
	_check(app.menu == "title" and not app.started, "application begins at title")
	await _click_action("new")
	_check(app.started and app.menu.is_empty(), "engine-dispatched HUD click actually starts the game")
	_check(app.selected_ids.size() == 4, "starting squad is selected by real new-game handling")
	_check(not app.sim.paused, "new game is initially running")
	await _key(KEY_SPACE)
	_check(app.sim.paused, "Input.parse_input_event reaches the real pause binding")
	_check(not Input.is_action_pressed("pause_game"), "key release clears the Input singleton action state")


func _test_single_shift_and_box_selection() -> void:
	var rifles: Array[Dictionary] = _rifles()
	_check(rifles.size() == 3, "selection test has the real initial three rifle units")
	if rifles.size() < 3:
		return
	var first: Vector2 = _tile_screen(rifles[0]["pos"])
	var second: Vector2 = _tile_screen(rifles[1]["pos"])
	await _click(first)
	_check(_ids(app.selected_ids) == [int(rifles[0]["id"])], "engine mouse down/up single-click selects exactly the clicked unit")
	_check(not app.dragging, "world click release ends selection dragging")
	await _click(second, MOUSE_BUTTON_LEFT, true)
	var expected: Array[int] = [int(rifles[0]["id"]), int(rifles[1]["id"])]
	expected.sort()
	_check(_ids(app.selected_ids) == expected, "real Shift key plus mouse events append the second unit")
	_check(not Input.is_key_pressed(KEY_SHIFT), "Shift release is delivered to the Input singleton")
	var minimum: Vector2 = Vector2(rifles[0]["pos"]).min(Vector2(rifles[1]["pos"])) - Vector2.ONE * 0.18
	var maximum: Vector2 = Vector2(rifles[0]["pos"]).max(Vector2(rifles[1]["pos"])) + Vector2.ONE * 0.18
	var start: Vector2 = _tile_screen(minimum)
	var end: Vector2 = _tile_screen(maximum)
	await _button(start, MOUSE_BUTTON_LEFT, true)
	_check(app.dragging, "world press starts drag through engine dispatch")
	for step: int in range(1, 5):
		await _motion(start.lerp(end, float(step) / 4.0), MOUSE_BUTTON_MASK_LEFT)
	await _button(end, MOUSE_BUTTON_LEFT, false)
	_check(not app.dragging and _ids(app.selected_ids) == expected, "engine motion and release perform the actual world drag-box selection")
	_check(root.get_mouse_position().distance_to(end) <= 1.0, "test motion and integer hardware cursor agree within one pixel")


func _test_right_click_orders() -> void:
	var chosen: Array = app.selected_ids.duplicate()
	var target: Vector2 = Vector2(15.0, 18.0)
	await _click(_tile_screen(target), MOUSE_BUTTON_RIGHT)
	_check(not chosen.is_empty(), "right-click test has real selected units")
	for id: int in chosen:
		var unit: Dictionary = app.sim.get_unit(id)
		_check(String(unit.get("order", "")) == "attack_move", "engine right-click changes actual simulation order")
		_check(Vector2(unit.get("target", Vector2.ZERO)).distance_to(target) < 2.0, "right-click order uses event-dispatched viewport-to-world position")


func _test_release_over_hud() -> void:
	var selected: Array[int] = _ids(app.selected_ids)
	var start: Vector2 = Vector2(1050.0, 520.0)
	await _button(start, MOUSE_BUTTON_LEFT, true)
	_check(app.dragging, "world press starts drag before crossing HUD")
	await _motion(Vector2(600.0, 30.0), MOUSE_BUTTON_MASK_LEFT)
	await _button(Vector2(600.0, 30.0), MOUSE_BUTTON_LEFT, false)
	_check(not app.dragging, "release consumed by HUD still clears world dragging")
	_check(_ids(app.selected_ids) == selected, "release over HUD does not issue an accidental box selection")
	await _motion(Vector2(1000.0, 500.0))
	_check(not app.dragging, "later mouse motion cannot resurrect the released selection drag")


func _test_middle_release_over_hud() -> void:
	var start: Vector2 = Vector2(1000.0, 520.0)
	var before: Vector2 = app.camera.position
	await _button(start, MOUSE_BUTTON_MIDDLE, true)
	_check(app.pan_active, "middle press enters real camera-panning mode")
	await _motion(start + Vector2(70.0, 15.0), MOUSE_BUTTON_MASK_MIDDLE)
	_check(Vector2(app.camera.position).distance_to(before) > 20.0, "engine mouse motion genuinely pans the camera")
	await _motion(Vector2(600.0, 30.0), MOUSE_BUTTON_MASK_MIDDLE)
	await _button(Vector2(600.0, 30.0), MOUSE_BUTTON_MIDDLE, false)
	_check(not app.pan_active, "middle release over HUD ends panning before HUD consumption")
	var released_camera: Vector2 = app.camera.position
	await _motion(Vector2(1000.0, 500.0))
	await _frames(4)
	_check(Vector2(app.camera.position).distance_to(released_camera) < 0.1, "unpressed later motion cannot continue panning")
	await _minimap(Vector2(16.0, 22.0))
	_check(Vector2(app.camera.position).distance_to(Vector2(16.0, 22.0) * 48.0) < 0.1, "engine-dispatched minimap click restores the view")


func _test_menu_blocks_combat_dispatch() -> void:
	await _click_action("menu")
	_check(app.menu == "pause", "real menu click opens the pause overlay")
	var snapshot: String = _simulation_snapshot()
	var selected: Array[int] = _ids(app.selected_ids)
	await _click(Vector2(1230.0, 500.0), MOUSE_BUTTON_RIGHT)
	await _click(Vector2(1220.0, 520.0), MOUSE_BUTTON_LEFT)
	await _key(KEY_X)
	await _key(KEY_B)
	_check(_simulation_snapshot() == snapshot, "overlay consumes world mouse/key events without combat or building orders leaking")
	_check(_ids(app.selected_ids) == selected and not app.attack_move and app.pending_task.is_empty() and app.build_kind.is_empty(), "menu input cannot change selection or arm hidden combat/build modes")
	_check(not app.dragging and not app.pan_active and app.menu == "pause", "menu interactions leave no stuck dragging/panning state")
	await _click_action("resume")
	_check(app.menu.is_empty() and app.sim.paused, "resume closes menu while preserving tactical pause")


func _test_double_click_visible_same_kind() -> void:
	var rifles: Array[Dictionary] = _rifles()
	if rifles.size() < 3:
		_check(false, "double-click fixture requires three surviving initial rifle units")
		return
	var away_id: int = int(rifles[2]["id"])
	await _click(_tile_screen(rifles[2]["pos"]))
	_check(_ids(app.selected_ids) == [away_id], "engine single-click selects the unit used for the offscreen movement fixture")
	await _minimap(Vector2(3.0, 26.0), MOUSE_BUTTON_RIGHT)
	_check(String(app.sim.get_unit(away_id).get("order", "")) == "attack_move", "real minimap right-click orders the distant unit")
	await _key(KEY_SPACE)
	_check(not app.sim.paused, "engine pause key resumes actual movement")
	# Advance the already-issued real orders; no units are teleported or injected.
	for index: int in range(220):
		app.sim.tick(0.1)
	await _key(KEY_SPACE)
	_check(app.sim.paused, "engine pause key freezes completed movement fixture")
	await _minimap(Vector2(20.5, 22.0))
	var away: Dictionary = app.sim.get_unit(away_id)
	_check(not away.is_empty() and Vector2(away["pos"]).x < 5.0, "ordered unit actually walked to the western side")
	var visible: Array[int] = []
	var clicked: Dictionary = {}
	var screen: Rect2 = app.get_viewport_rect()
	for unit: Dictionary in _rifles():
		if screen.has_point(_tile_screen(unit["pos"])):
			visible.append(int(unit["id"]))
			clicked = unit
	visible.sort()
	_check(visible.size() == 2 and not visible.has(away_id), "real camera viewport contains two same-kind units and excludes the moved third")
	if clicked.is_empty():
		return
	var point: Vector2 = _tile_screen(clicked["pos"])
	await _click(point)
	# The OS/Godot double-click bit belongs to the second PRESS, never the UP.
	await _button(point, MOUSE_BUTTON_LEFT, true, false, true)
	await _button(point, MOUSE_BUTTON_LEFT, false, false, false)
	_check(_ids(app.selected_ids) == visible, "double-click PRESS flag survives release and selects all visible same-kind units")
	_check(not app.selected_ids.has(away_id), "double-click does not select an offscreen same-kind unit elsewhere on the map")
	_check(not app.dragging, "double-click release ends selection drag")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work"))
	await _frames(4)
	var frame: Image = root.get_texture().get_image()
	_check(frame != null and frame.get_size() == Vector2i(1600, 900), "final event-dispatch frame contains real 1600 x 900 pixels")
	if frame != null:
		_check(frame.save_png(ProjectSettings.globalize_path("res://work/input-dispatch.png")) == OK, "engine input fixture screenshot is saved")
