extends SceneTree
## Rendered integration test. Requires DISPLAY and an isolated XDG_DATA_HOME.
## HUD tests click actual rendered hotspots. Keys enter main._unhandled_input.
## Box selection uses the controller's world-coordinate drag interface; this is
## not an assertion that a human can discover or comfortably use these controls.

var app: Variant
var failures: Array[String] = []
var checks: int = 0
var save_path: String
var config_path: String

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolated_root: String = ProjectSettings.globalize_path("res://work/test-ui-data").trim_suffix("/")
	var user_root: String = OS.get_user_data_dir()
	if not user_root.begins_with(isolated_root + "/"):
		printerr("Refusing UI test outside isolated XDG_DATA_HOME: ", user_root)
		quit(2)
		return
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	AudioServer.set_bus_mute(0, true)
	var packed: PackedScene = load("res://main.tscn") as PackedScene
	app = packed.instantiate()
	root.add_child(app)
	await _frames(8)
	var constants: Dictionary = app.get_script().get_script_constant_map()
	save_path = str(constants["SAVE_PATH"])
	config_path = str(constants["CONFIG_PATH"])
	for file: String in [save_path, save_path + ".tmp", config_path]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	_check(DisplayServer.get_name() != "headless", "test uses a real rendering display")
	_check(root.size == Vector2i(1600, 900), "test renders a 1600 x 900 window")
	await _test_new_campaign()
	await _test_selection_and_groups()
	await _test_zoom_and_minimap()
	await _test_build_mode_and_cancel()
	await _test_targeted_macro_tasks()
	await _test_production_and_training()
	await _test_pause_menu()
	await _test_quick_save_load_and_bad_data()
	await _test_settings_and_rebinding()
	await _capture("res://work/ui-test.png")
	print("Rendered UI checks: %d; failures: %d" % [checks, failures.size()])
	print("Test user data: ", user_root)
	for failure: String in failures:
		printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _frames(count: int = 3) -> void:
	for index: int in range(count):
		if is_instance_valid(app) and app.hud != null:
			app.hud.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw

func _click_action(action: String, button: MouseButton = MOUSE_BUTTON_LEFT) -> bool:
	await _frames()
	for hotspot: Dictionary in app.hud.hotspots:
		if str(hotspot.get("action", "")) != action:
			continue
		var rect: Rect2 = hotspot["rect"]
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = rect.get_center()
		event.global_position = event.position
		event.button_index = button
		event.pressed = true
		var consumed: bool = app.hud.handle_mouse(event)
		_check(consumed, "HUD consumes visible hotspot " + action)
		await _frames()
		return consumed
	_check(false, "visible HUD hotspot exists: " + action)
	return false

func _click_point(point: Vector2, button: MouseButton) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = true
	_check(app.hud.handle_mouse(event), "HUD consumes minimap click")
	await _frames()

func _key(code: Key, control: bool = false, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.ctrl_pressed = control
	event.shift_pressed = shift
	event.pressed = true
	app._unhandled_input(event)
	await _frames()
	event.pressed = false
	app._unhandled_input(event)

func _world_mouse(button: MouseButton) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = Vector2(800, 450)
	event.global_position = event.position
	event.button_index = button
	event.pressed = true
	app._unhandled_input(event)
	await _frames()

func _hotspots_fit_view() -> bool:
	var screen: Rect2 = Rect2(Vector2.ZERO, Vector2(1600, 900))
	for hotspot: Dictionary in app.hud.hotspots:
		if not screen.encloses(hotspot.rect):
			return false
	return true

func _test_new_campaign() -> void:
	_check(app.menu == "title" and not app.started, "new scene opens on the title menu")
	_check(_hotspots_fit_view(), "title buttons fit within the viewport")
	await _click_action("new")
	_check(app.started and app.menu.is_empty(), "new-game HUD click enters the campaign")
	_check(app.sim.outcome == "playing" and app.sim.camps.size() > 0, "new game resets a real playable simulation")
	_check(app.selected_ids.size() >= 4, "new game selects the initial controllable squad")
	app.sim.paused = true
	await _frames()
	_check(_hotspots_fit_view(), "campaign HUD controls fit within the viewport")

func _test_selection_and_groups() -> void:
	app.selected_ids.clear()
	app.drag_start = Vector2(11.5, 19.5) * 48.0
	app._select(Vector2(13.5, 21.5) * 48.0, false, false)
	_check(app.selected_ids.size() == 3, "world drag-box controller selects the three rifle units in its rectangle")
	var selected: Array = app.selected_ids.duplicate()
	await _key(KEY_1, true)
	_check(app.group_bindings.has(1) and app.group_bindings[1] == selected, "Ctrl+1 stores the actual selected unit IDs")
	app.selected_ids.clear()
	await _key(KEY_1)
	_check(app.selected_ids == selected, "number-key recall restores the saved group")
	await _key(KEY_TAB)
	_check(not app.selected_ids.is_empty(), "squad-cycle key selects live units")
	for id: int in app.selected_ids:
		_check(not app.sim.get_unit(id).is_empty(), "recalled/cycled selection references a real live unit")
	await _key(KEY_1)

func _test_zoom_and_minimap() -> void:
	for index: int in range(50):
		var wheel_up: InputEventMouseButton = InputEventMouseButton.new()
		wheel_up.position = Vector2(800, 450)
		wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel_up.pressed = true
		app._unhandled_input(wheel_up)
	_check(is_equal_approx(float(app.camera.zoom.x), 1.6), "actual wheel input clamps to maximum camera zoom")
	for index: int in range(60):
		var wheel_down: InputEventMouseButton = InputEventMouseButton.new()
		wheel_down.position = Vector2(800, 450)
		wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel_down.pressed = true
		app._unhandled_input(wheel_down)
	_check(is_equal_approx(float(app.camera.zoom.x), 0.35), "actual wheel input clamps to minimum camera zoom")
	await _frames()
	var rect: Rect2 = app.hud.map_rect
	var fraction: Vector2 = Vector2(0.70, 0.40)
	await _click_point(rect.position + rect.size * fraction, MOUSE_BUTTON_LEFT)
	var expected_camera: Vector2 = fraction * Vector2(app.sim.map_size) * 48.0
	_check(Vector2(app.camera.position).distance_to(expected_camera) < 1.0, "left minimap click positions the world camera")
	await _key(KEY_1)
	var commanded: Array = app.selected_ids.duplicate()
	var target_tile: Vector2 = Vector2(26, 20)
	await _click_point(rect.position + rect.size * target_tile / Vector2(app.sim.map_size), MOUSE_BUTTON_RIGHT)
	_check(not commanded.is_empty(), "minimap command has a selected squad")
	if not commanded.is_empty():
		var unit: Dictionary = app.sim.get_unit(int(commanded[0]))
		_check(str(unit.get("order", "")) == "attack_move", "right minimap click reaches the simulation movement order")
		_check(Vector2(unit.target).distance_to(target_tile) <= 2.0, "minimap order targets the clicked map location")
	app.focus_camp(app.selected_camp)
	app._zoom(0.95 / float(app.camera.zoom.x))
	await _frames()

func _test_build_mode_and_cancel() -> void:
	await _click_action("tab:build")
	await _click_action("build:tower")
	_check(app.build_kind == "tower" and app.world.build_kind == "tower", "build-card click enters controller and renderer placement mode")
	await _world_mouse(MOUSE_BUTTON_RIGHT)
	_check(app.build_kind.is_empty(), "right-click cancels placement without issuing a movement order")
	await _click_action("build:road")
	await _key(KEY_ESCAPE)
	_check(app.build_kind.is_empty() and app.menu.is_empty(), "Escape cancels placement before opening the menu")

func _test_targeted_macro_tasks() -> void:
	await _key(KEY_1)
	await _click_action("tab:orders")
	var selected: Array = app.selected_ids.duplicate()
	_check(not selected.is_empty(), "targeted task test has a real selected squad")
	var before_choice: String = JSON.stringify(app.sim.save_state())
	await _click_action("task:clear")
	_check(app.pending_task == "clear", "clear-task HUD enters target-selection mode")
	_check(JSON.stringify(app.sim.save_state()) == before_choice, "choosing clear does not silently send the squad to its current camp")
	var clear_target: Vector2 = Vector2(35, 10)
	var map_rect: Rect2 = app.hud.map_rect
	await _click_point(map_rect.position + map_rect.size * clear_target / Vector2(app.sim.map_size), MOUSE_BUTTON_RIGHT)
	_check(app.pending_task.is_empty(), "minimap task target consumes the pending clear order")
	for id: int in selected:
		var unit: Dictionary = app.sim.get_unit(id)
		_check(str(unit.get("order", "")) == "clear", "clear task reaches each selected simulation unit")
		_check(Vector2(unit.target).distance_to(clear_target) <= 2.0, "clear task actually targets the selected frontline area")
		_check(Vector2(unit.target).distance_to(Vector2(app.sim.get_camp(app.selected_camp).pos)) > 15.0, "clear target remains distinct from the selected camp center")
	await _click_action("task:guard")
	_check(app.pending_task == "guard", "guard-task HUD waits for an explicit target")
	var guard_target: Vector2 = Vector2(49, 21)
	app._issue_context(guard_target)
	await _frames()
	_check(app.pending_task.is_empty(), "explicit context target consumes the pending guard task")
	for id: int in selected:
		var unit: Dictionary = app.sim.get_unit(id)
		_check(str(unit.get("order", "")) == "guard", "guard task reaches the selected simulation unit")
		_check(Vector2(unit.target).distance_to(guard_target) <= 2.0 and Vector2(unit.get("guard_pos", Vector2.ZERO)).distance_to(guard_target) <= 2.0, "guard movement and guard position use the actual chosen frontline area")
	var before_cancel: String = JSON.stringify(app.sim.save_state())
	await _click_action("task:escort")
	_check(app.pending_task == "escort", "escort-task HUD enters target-selection mode")
	await _world_mouse(MOUSE_BUTTON_RIGHT)
	_check(app.pending_task.is_empty(), "world right-click cancels a pending task")
	_check(JSON.stringify(app.sim.save_state()) == before_cancel, "right-click cancellation issues no movement or task order")
	await _click_action("task:clear")
	await _key(KEY_ESCAPE)
	_check(app.pending_task.is_empty() and app.menu.is_empty(), "Escape cancels a pending task before opening the pause menu")
	_check(JSON.stringify(app.sim.save_state()) == before_cancel, "Escape task cancellation leaves all simulation orders unchanged")
	app.selected_ids.clear()
	await _click_action("task:guard")
	_check(app.pending_task.is_empty(), "a task requires a selected squad before target selection")
	await _key(KEY_1)

func _test_production_and_training() -> void:
	await _click_action("tab:production")
	await _click_action("recipe:fuel")
	var camp: Dictionary = app.sim.get_camp(app.selected_camp)
	_check(camp.get("recipe", "") == "fuel", "production HUD changes the selected real camp recipe")
	await _click_action("priority:defense")
	_check(camp.get("priority", "") == "defense", "supply-priority HUD changes simulation power allocation policy")
	await _click_action("tab:training")
	var queue_before: int = camp.get("recruit_queue", []).size()
	var population_before: int = app.sim.units.size()
	var materials_before: float = float(camp.materials)
	await _click_action("recruit:worker")
	_check(camp.get("recruit_queue", []).size() == queue_before + 1, "training card creates an actual camp training order")
	_check(app.sim.units.size() == population_before, "HUD recruitment does not instantly spawn a unit")
	_check(float(camp.materials) < materials_before, "training HUD pays actual material costs")
	await _click_action("tab:build")

func _test_pause_menu() -> void:
	app.sim.paused = false
	await _click_action("menu")
	_check(app.menu == "pause", "menu hotspot opens the pause menu")
	var paused_time: float = float(app.sim.time)
	await _frames(15)
	_check(is_equal_approx(float(app.sim.time), paused_time), "pause menu stops actual simulation time")
	_check(_hotspots_fit_view(), "pause-menu controls fit within the screen")
	await _click_action("resume")
	await _frames(15)
	_check(app.menu.is_empty() and float(app.sim.time) > paused_time, "resume hotspot restarts simulation time")
	await _click_action("pause")
	_check(app.sim.paused, "top-bar pause toggles tactical simulation pause")

func _test_quick_save_load_and_bad_data() -> void:
	var camp: Dictionary = app.sim.get_camp(app.selected_camp)
	camp.materials = 173.25
	app.camera.position = Vector2(850, 755)
	app.camera.zoom = Vector2.ONE * 1.15
	await _key(KEY_F5)
	_check(FileAccess.file_exists(save_path), "F5 creates the actual campaign save file")
	var valid_text: String = FileAccess.get_file_as_string(save_path)
	var valid_data: Variant = JSON.parse_string(valid_text)
	_check(valid_data is Dictionary and valid_data.has("payload"), "F5 writes a real versioned simulation payload")
	_check(not FileAccess.file_exists(save_path + ".tmp"), "successful save leaves no unfinished temp replacement")
	camp.materials = 1.0
	app.camera.position = Vector2(100, 100)
	app.camera.zoom = Vector2.ONE * 0.5
	await _key(KEY_F9)
	var restored: Dictionary = app.sim.get_camp(app.selected_camp)
	_check(is_equal_approx(float(restored.materials), 173.25), "F9 restores actual resource state from disk")
	_check(Vector2(app.camera.position).distance_to(Vector2(850, 755)) < 0.1, "F9 restores saved camera position")
	_check(is_equal_approx(float(app.camera.zoom.x), 1.15), "F9 restores saved camera zoom")
	var state_before: String = JSON.stringify(app.sim.save_state())
	_write_test_save("{ malformed save")
	await _key(KEY_F9)
	_check(JSON.stringify(app.sim.save_state()) == state_before, "malformed disk save does not replace the running simulation")
	_check(app.feedback.contains("无法读取"), "failed disk load reports a clear user-facing error")
	if valid_data is Dictionary:
		valid_data["version"] = -1
		_write_test_save(JSON.stringify(valid_data))
		await _key(KEY_F9)
		_check(JSON.stringify(app.sim.save_state()) == state_before, "incompatible save does not replace the running simulation")
	var bad_ui: Variant = JSON.parse_string(valid_text)
	if bad_ui is Dictionary:
		bad_ui["ui"] = "not a camera/settings dictionary"
		app.sim.get_camp(app.selected_camp).materials = 88.5
		var before_bad_ui: String = JSON.stringify(app.sim.save_state())
		_write_test_save(JSON.stringify(bad_ui))
		await _key(KEY_F9)
		_check(JSON.stringify(app.sim.save_state()) == before_bad_ui, "malformed UI metadata is rejected before any simulation state is replaced")
	_write_test_save(valid_text)

func _write_test_save(text: String) -> void:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	_check(file != null, "isolated test save can be written")
	if file != null:
		file.store_string(text)
		file.close()

func _test_settings_and_rebinding() -> void:
	await _click_action("menu")
	await _click_action("settings")
	_check(app.menu == "settings", "settings menu opens through real HUD controls")
	_check(_hotspots_fit_view(), "settings and binding buttons fit the viewport")
	var previous_volume: float = float(app.volume)
	await _click_action("volume")
	_check(not is_equal_approx(float(app.volume), previous_volume), "volume UI changes the application volume")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(maxf(float(app.volume), 0.001))), "volume change reaches the actual audio bus")
	var saved_volume: float = float(app.volume)
	await _click_action("bind:production_menu")
	_check(app.waiting_binding == "production_menu", "binding hotspot enters key-capture mode")
	await _key(KEY_U)
	_check(app.waiting_binding.is_empty(), "a physical key completes binding capture")
	_check(FileAccess.file_exists(config_path), "rebinding writes the real settings file")
	var config: ConfigFile = ConfigFile.new()
	_check(config.load(config_path) == OK, "persisted settings can be read")
	_check(int(config.get_value("keys", "production_menu", 0)) == KEY_U, "new production binding is persisted")
	await _capture("res://work/ui-settings-test.png")
	await _click_action("back")
	await _click_action("resume")
	app.current_tab = "build"
	await _key(KEY_U)
	_check(app.current_tab == "production", "newly bound physical key drives the production panel")
	app.current_tab = "orders"
	await _key(KEY_P)
	_check(app.current_tab == "orders", "replaced default production key no longer triggers the action")
	app.queue_free()
	await process_frame
	await process_frame
	var packed: PackedScene = load("res://main.tscn") as PackedScene
	app = packed.instantiate()
	root.add_child(app)
	await _frames(8)
	var events: Array[InputEvent] = InputMap.action_get_events("production_menu")
	_check(not events.is_empty() and events[0] is InputEventKey and events[0].physical_keycode == KEY_U, "new scene reloads the binding from persisted settings")
	_check(is_equal_approx(float(app.volume), saved_volume), "new scene reloads saved audio volume")
	await _click_action("new")
	app.sim.paused = true
	app.current_tab = "build"
	await _key(KEY_U)
	_check(app.current_tab == "production", "persisted binding works after scene reconstruction")
	await _click_action("tab:build")
	app.focus_camp(app.selected_camp)
	app.camera.zoom = Vector2.ONE * 0.95
	await _frames()

func _capture(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work"))
	await _frames()
	var image: Image = root.get_texture().get_image()
	_check(image != null and image.get_size() == Vector2i(1600, 900), "rendered capture has real viewport pixels")
	if image != null:
		var result: Error = image.save_png(ProjectSettings.globalize_path(path))
		_check(result == OK, "screenshot saved to " + path)
