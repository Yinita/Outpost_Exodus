extends SceneTree
## Real rendered input and filesystem regression; isolated XDG_DATA_HOME only.
## -- --exit-regression-only safely reproduces the original save-loss bug.

class QuitProbe:
	extends "res://scripts/main.gd"
	var quit_calls: int = 0
	func _quit_cleanly(_exit_code: int = 0) -> void:
		if closing: return
		closing = true
		quit_calls += 1
		set_process(false)
		set_process_unhandled_input(false)

const Simulation = preload("res://scripts/campaign_simulation.gd")
var app: Variant
var checks: int = 0
var failures: Array[String] = []
var manual: PackedByteArray
var backup: PackedByteArray
var automatic: PackedByteArray
var auto_backup: PackedByteArray
var blocked: bool = false
var finishing: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/exit-recovery-data").trim_suffix("/")
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Exit recovery requires native DISPLAY and isolated work/exit-recovery-data")
		quit(2)
		return
	create_timer(90.0).timeout.connect(_deadline)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	AudioServer.set_bus_mute(0, true)
	app = QuitProbe.new()
	root.add_child(app)
	app.set_process(false)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1152, 648)
	root.content_scale_size = root.size
	root.content_scale_factor = 1.2
	await _frames(4)
	app.start_campaign("canyon")
	app.sim.paused = false
	_check(app.save_campaign(), "first real manual save succeeds")
	app.sim.tick(0.1)
	_check(app.save_campaign(), "second real manual save produces older backup")
	_check(app.save_campaign(false), "real AUTO and recovery backup exist before failure")
	manual = _bytes(app.SAVE_PATH)
	backup = _bytes(app.SAVE_PATH + ".bak")
	automatic = _bytes(app.AUTOSAVE_PATH)
	auto_backup = _bytes(app.AUTOSAVE_PATH + ".bak")
	app.sim.tick(0.1)
	app.selected_ids = [int(app.sim.units[0].id)]
	app.build_kind = "road"
	app.pending_task = "repair"
	app.attack_move = true
	app.pan_active = false
	app.dragging = false
	app.menu = "settings"
	app.waiting_binding = "camera_up"
	var before: String = _state()
	_block_auto()
	app._on_close_requested()
	_check(app.quit_calls == 0 and not app.closing, "failed real AUTO write leaves application alive instead of quitting")
	_check(app.menu == "exit_save_failed", "failed close presents dedicated recovery modal")
	_check(_state() == before, "failed close preserves complete live simulation, selection and orders")
	_check(_good_files_unchanged(), "failed close preserves manual, backup and automatic recovery bytes")
	if OS.get_cmdline_user_args().has("--exit-regression-only"):
		await _finish()
		return
	if app.quit_calls != 0 or app.menu != "exit_save_failed":
		await _finish()
		return
	await _frames()
	_check(_modal_fits(), "all three recovery options fit 1152x648 at 120 percent UI scale")
	_capture("exit-save-failed-small.png")
	app._on_close_requested()
	await _click_action("exit_retry")
	_check(app.menu == "exit_save_failed" and app.quit_calls == 0 and not app.closing, "repeated WM close and failed Retry keep the recovery modal alive")
	_check(app.exit_return_menu == "settings", "repeated close and retry preserve original settings return destination")
	var ticks: int = app.tick_count
	app.set_process(true)
	await _frames(8)
	app._process(0.8)
	app.set_process(false)
	_check(app.tick_count == ticks and _state() == before, "no simulation ticks occur while the failure modal is visible")
	await _key(KEY_SPACE)
	await _key(KEY_F5)
	await _key(KEY_X)
	await _click(Vector2(24, 24), MOUSE_BUTTON_RIGHT)
	await _click(Vector2(500, 28))
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(100, 100)
	motion.relative = Vector2(120, 70)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _frames()
	app.ui_action("title")
	_check(app.menu == "exit_save_failed" and _state() == before and _good_files_unchanged(), "modal blocks world clicks, pan motion, hotkeys and unrelated UI actions")
	await _key(KEY_ESCAPE)
	_check(app.menu == "settings" and app.waiting_binding == "camera_up", "Escape returns to original menu before binding capture or generic pause logic")
	_check(_state() == before, "Escape cancel preserves simulation, selections, pending orders and pointer modes")
	app.waiting_binding = ""
	app.menu = ""
	await _frames()
	app.pan_active = true
	app.dragging = true
	app.selection_double_click = true
	app._on_close_requested()
	_check(not app.pan_active and not app.dragging and not app.selection_double_click, "opening recovery stops held mouse gestures without clearing armed orders")
	_check(app.hud.hotspots.is_empty(), "opening recovery immediately removes stale gameplay hotspots before redraw")
	await _click_action("exit_cancel")
	_check(app.menu.is_empty() and _state() == before, "rendered Return option restores gameplay and all live state")
	app.menu = "pause"
	app._on_close_requested()
	await _click_action("exit_retry")
	_check(app.exit_return_menu == "pause" and _good_files_unchanged(), "new exit attempt records its own return menu and failed retry preserves good saves")
	_unblock_auto()
	await _click_action("exit_retry")
	_check(app.quit_calls == 1 and app.closing, "successful Retry saves and reaches existing quit path exactly once")
	var restored: Variant = Simulation.new()
	var read: Dictionary = app.save_store.read(app.AUTOSAVE_PATH)
	_check(read.ok and restored.load_state(read.data), "successful Retry creates a valid actual AUTO save")
	_check(_sim_state(restored) == _sim_state(app.sim), "successful Retry stores complete latest live simulation")
	_check(_bytes(app.SAVE_PATH) == manual and _bytes(app.SAVE_PATH + ".bak") == backup, "successful Retry preserves manual and backup byte for byte")
	app._on_close_requested()
	app.ui_action("exit_retry")
	_check(app.quit_calls == 1, "repeated close after successful Retry cannot request a second quit")
	_reset_quit_probe()
	app.menu = "pause"
	automatic = _bytes(app.AUTOSAVE_PATH)
	auto_backup = _bytes(app.AUTOSAVE_PATH + ".bak")
	_block_auto()
	app._on_close_requested()
	await _click_action("exit_discard")
	_check(app.quit_calls == 1 and app.closing, "explicit rendered Discard option quits exactly once despite real write failure")
	_check(_good_files_unchanged() and _state() == before, "explicit Discard performs no extra save or live-state mutation")
	app._on_close_requested()
	_check(app.quit_calls == 1, "repeated WM close after Discard remains idempotent")
	_unblock_auto()
	_reset_quit_probe()
	app.started = false
	app.menu = "title"
	await _frames()
	await _click_action("quit")
	_check(app.quit_calls == 1 and app.closing, "title Quit reaches existing clean quit without a live-run save")
	_check(_good_files_unchanged(), "title Quit preserves every existing save slot")
	_reset_quit_probe()
	app.started = true
	app.menu = "pause"
	app._on_close_requested()
	app._on_close_requested()
	_check(app.quit_calls == 1 and app.closing, "normal successful live-run close requests exactly one clean quit")
	await _finish()

func _deadline() -> void:
	_check(false, "90 second deadline reached")
	await _finish()

func _finish() -> void:
	if finishing: return
	finishing = true
	_unblock_auto()
	print("Exit recovery checks: %d; failures: %d" % [checks, failures.size()])
	print("Isolated data: ", OS.get_user_data_dir())
	for failure: String in failures: printerr(" - ", failure)
	if is_instance_valid(app):
		app.set_process(false)
		app.set_process_unhandled_input(false)
		app._release_audio()
		var deadline: int = Time.get_ticks_usec() + 120000
		while Time.get_ticks_usec() < deadline: await process_frame
		app.queue_free()
		app = null
	await _frames(4)
	root.content_scale_factor = 1.0
	quit(0 if failures.is_empty() else 1)

func _block_auto() -> void:
	var path: String = ProjectSettings.globalize_path(app.AUTOSAVE_PATH)
	_check(DirAccess.rename_absolute(path, path + ".exit-fixture") == OK, "preserve real AUTO bytes before fault")
	_check(DirAccess.make_dir_absolute(path) == OK, "actual directory blocks AUTO writes")
	blocked = true

func _unblock_auto() -> void:
	if not blocked: return
	var path: String = ProjectSettings.globalize_path(app.AUTOSAVE_PATH)
	_check(DirAccess.remove_absolute(path) == OK, "remove actual AUTO directory fault")
	_check(DirAccess.rename_absolute(path + ".exit-fixture", path) == OK, "restore original AUTO file without rewriting it")
	blocked = false

func _reset_quit_probe() -> void:
	app.closing = false
	app.quit_calls = 0
	app.set_process_unhandled_input(true)

func _good_files_unchanged() -> bool:
	var auto_path: String = app.AUTOSAVE_PATH + (".exit-fixture" if blocked else "")
	return _bytes(app.SAVE_PATH) == manual and _bytes(app.SAVE_PATH + ".bak") == backup and _bytes(auto_path) == automatic and _bytes(app.AUTOSAVE_PATH + ".bak") == auto_backup

func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)

func _sim_state(simulation: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(simulation.save_state(), "", true, true)), "", true, true)

func _state() -> String:
	return JSON.stringify([_sim_state(app.sim), app.selected_ids, app.selected_camp, app.build_kind, app.pending_task, app.attack_move, app.dragging, app.pan_active, app.camera.position, app.camera.zoom, app.group_bindings, app.pending_mission_id], "", true, true)

func _frames(count: int = 2) -> void:
	for frame: int in range(count):
		if is_instance_valid(app): app.hud.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw

func _modal_fits() -> bool:
	if app.hud.hotspots.size() != 3: return false
	for hotspot: Dictionary in app.hud.hotspots:
		if not String(hotspot.action) in ["exit_cancel", "exit_retry", "exit_discard"]: return false
		if not app.hud.get_viewport_rect().encloses(hotspot.rect): return false
	return true

func _click_action(action: String) -> void:
	await _frames()
	for hotspot: Dictionary in app.hud.hotspots:
		if String(hotspot.action) == action:
			_check(app.hud.get_viewport_rect().encloses(hotspot.rect), "reachable rendered action: " + action)
			await _click(Rect2(hotspot.rect).get_center())
			return
	_check(false, "rendered action exists: " + action)

func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(1)

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(1)

func _capture(name: String) -> void:
	root.get_texture().get_image().save_png("res://work/" + name)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
