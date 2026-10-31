extends SceneTree
## Native focus/window and actual filesystem recovery checks; not human input acceptance.
## DISPLAY=:0 XDG_DATA_HOME="$PWD/work/focus-recovery-data" ./run.sh --script res://tests/test_focus_recovery.gd

var app: Variant
var focus_helper_pid: int = -1
const HELPER_READY: String = "res://work/focus-recovery-helper.ready"
const HELPER_RELEASE: String = "res://work/focus-recovery-helper.release"
var checks: int = 0
var failures: Array[String] = []
var finishing: bool = false
var saved_mouse: Vector2i
var focus_exits: int = 0
var focus_enters: int = 0
var preserved: Dictionary = {}
var blocked: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/focus-recovery-data").trim_suffix("/")
	if DisplayServer.get_name() != "X11" or not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Focus recovery requires native X11 DISPLAY, python3/libX11 and isolated work/focus-recovery-data")
		quit(2)
		return
	create_timer(90.0).timeout.connect(_deadline)
	saved_mouse = DisplayServer.mouse_get_position()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1152, 648)
	root.content_scale_size = root.size
	root.content_scale_factor = 1.2
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	# Keep real playback available but the hardware test nearly inaudible.
	AudioServer.set_bus_volume_db(0, -80.0)
	root.focus_exited.connect(func() -> void: focus_exits += 1)
	root.focus_entered.connect(func() -> void: focus_enters += 1)
	root.grab_focus()
	await _wait_focus(root)
	await _frames(4)
	app.start_campaign("canyon")
	app.set_process(false)
	_check(app.started and app.menu.is_empty() and not app.sim.paused, "live original campaign starts running")
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	_check(app.save_campaign(), "first manual save is written in isolated directory")
	app.sim.tick(0.1)
	_check(app.save_campaign(), "second manual save creates recovery backup")
	_check(app.save_campaign(false), "actual AUTO save exists before focus test")
	preserved = _slot_bytes()
	await _test_native_focus_loss()
	await _test_tactical_pause_and_menus()
	await _test_native_minimize()
	await _test_failed_title_save()
	await _finish()

func _test_native_focus_loss() -> void:
	app.menu = ""
	app.sim.paused = false
	app.build_kind = "road"
	app.pending_task = "repair"
	app.attack_move = true
	app.dragging = true
	app.selection_double_click = true
	app.pan_active = true
	var selected: Array = app.selected_ids.duplicate()
	var before: String = _sim_state()
	var camera_before: Vector2 = app.camera.position
	var accumulator_before: float = app.accumulator
	var autosave_before: float = app.autosave_time
	var binding_before: Array = _binding_codes()
	await _key(KEY_W, true)
	_check(Input.is_action_pressed("camera_up"), "actual engine key dispatch holds a mapped camera action")
	app.game_audio.set_gameplay_active(true, app.sim)
	_check(app.game_audio.play_world("impact", camera_before / app.TILE, camera_before / app.TILE), "real world effect starts before focus loss")
	_check(app.game_audio.active_world_voices() > 0, "pre-focus effect has an active playback voice")
	for path: String in [HELPER_READY, HELPER_RELEASE]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var exits_before: int = focus_exits
	focus_helper_pid = OS.create_process("python3", [ProjectSettings.globalize_path("res://tests/native_focus_helper.py"), ProjectSettings.globalize_path(HELPER_READY), ProjectSettings.globalize_path(HELPER_RELEASE)])
	_check(focus_helper_pid > 0, "independent native focus helper starts successfully")
	for frame: int in range(180):
		if FileAccess.file_exists(HELPER_READY) and app._window_suspended: break
		await process_frame
	_check(FileAccess.file_exists(HELPER_READY) and focus_exits > exits_before and not root.has_focus(), "external native X11 window generates real main-window focus exit")
	_check(app._window_suspended and app.menu == "pause", "focus loss suspends running campaign behind visible pause menu")
	_check(not app.sim.paused, "focus pause preserves previous running tactical flag")
	_check(not app.dragging and not app.pan_active and not app.selection_double_click, "focus exit cancels held mouse gestures immediately")
	_check(app.build_kind == "road" and app.pending_task == "repair" and app.attack_move, "focus exit preserves armed commands")
	_check(app.selected_ids == selected and _sim_state() == before, "focus exit preserves exact live simulation, orders and selection")
	_check(not Input.is_action_pressed("camera_up") and _binding_codes() == binding_before, "focus releases camera action without changing any key mappings")
	_check(not app.game_audio.gameplay_active and app.game_audio.active_world_voices() == 0, "focus exit retires world sound immediately")
	app._process(0.6)
	_check(_sim_state() == before and app.accumulator == accumulator_before and app.autosave_time == autosave_before, "background frame advances neither simulation nor autosave clock")
	_check(app.camera.position == camera_before, "held key cannot move camera in background")
	_check(_slot_bytes() == preserved, "focus pause does not write or rotate any save slots")
	var notice: String = app.menu_notice
	await _key(KEY_SPACE, true)
	await _key(KEY_B, true)
	await _key(KEY_F5, true)
	await _key(KEY_ESCAPE, true)
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.position = Vector2(600, 300)
	mouse.pressed = true
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	app._process(0.2)
	_check(app.menu == "pause" and app.menu_notice == notice and _sim_state() == before and _slot_bytes() == preserved, "background keys and world mouse cannot resume, save, alter orders or consume the pause notice")
	var enters_before: int = focus_enters
	_release_focus_helper()
	root.grab_focus()
	await _wait_focus(root)
	_check(focus_enters > enters_before and not app._window_suspended, "native main-window focus entry clears only suspension")
	_check(app.menu == "pause" and _sim_state() == before, "returning focus does not resume combat automatically")
	for code: Key in [KEY_W, KEY_SPACE, KEY_B, KEY_F5, KEY_ESCAPE]: await _key(code, false)
	_check(_binding_codes() == binding_before and not Input.is_action_pressed("camera_up"), "returning focus leaves remaps intact and no stuck camera action")
	app.build_kind = ""
	app.pending_task = ""
	app.attack_move = false
	await _frames()
	_check(await _click_action("resume"), "real rendered Continue button is available after focus returns")
	_check(app.menu.is_empty() and app.menu_notice.is_empty(), "explicit Continue retires focus notice and opens live campaign")
	var resume_time: float = app.sim.time
	app._process(0.1)
	_check(app.sim.time > resume_time and app.camera.position == camera_before, "explicit Continue resumes actual simulation without phantom held camera movement")
	print("PASS _test_native_focus_loss")

func _test_tactical_pause_and_menus() -> void:
	app.menu = ""
	app.sim.paused = true
	app._on_window_focus_exited()
	app._on_window_focus_entered()
	_check(app.menu == "pause" and app.sim.paused, "focus round-trip preserves pre-existing tactical pause")
	app.ui_action("resume")
	var before: String = _sim_state()
	app._process(0.1)
	_check(app.menu.is_empty() and app.sim.paused and _sim_state() == before, "Continue cannot override a prior tactical pause")
	for menu: String in ["settings", "help", "guide", "campaigns", "restart", "exit_save_failed"]:
		app.menu = menu
		app.waiting_binding = "camera_up"
		app.exit_return_menu = "settings"
		app._on_window_focus_exited()
		app._process(0.2)
		app._on_window_focus_entered()
		_check(app.menu == menu and app.waiting_binding == "camera_up" and app.exit_return_menu == "settings", "focus preserves existing menu and modal context: " + menu)
		_check(_sim_state() == before, "focus cannot alter tactically paused campaign in " + menu)
	app.waiting_binding = ""
	app.menu = "pause"
	print("PASS _test_tactical_pause_and_menus")

func _test_native_minimize() -> void:
	app.menu = ""
	app.sim.paused = false
	var before: String = _sim_state()
	root.mode = Window.MODE_MINIMIZED
	for frame: int in range(8): await process_frame
	app._process(0.4)
	_check(root.mode == Window.MODE_MINIMIZED, "native window reaches minimized mode")
	_check(app.menu == "pause" and app._window_suspended and not app.sim.paused and _sim_state() == before, "native minimize pauses without changing tactical flag or live state")
	root.mode = Window.MODE_WINDOWED
	root.grab_focus()
	await _wait_focus(root)
	_check(app.menu == "pause" and not app._window_suspended and _sim_state() == before, "native restore waits for explicit Continue")
	print("PASS _test_native_minimize")

func _test_failed_title_save() -> void:
	app.menu = "pause"
	app.sim.paused = false
	app.build_kind = "road"
	app.pending_task = "repair"
	app.attack_move = true
	var before: String = _full_state()
	preserved = _slot_bytes()
	var reject_before: int = app.game_audio.play_counts.get("reject", 0)
	_block_auto()
	_check(await _click_action("title"), "real pause-menu Return to title button receives engine click")
	_check(app.started and app.menu == "pause" and _full_state() == before, "failed real AUTO write keeps live run, original menu, selection and commands")
	_check(_good_slots_unchanged(), "failed title transition preserves manual, backup and AUTO recovery bytes")
	_check(app.menu_notice.contains("未返回标题") and app.feedback.contains("自动保存失败"), "failed title transition explains retained progress inside pause menu")
	_check(int(app.game_audio.play_counts.get("reject", 0)) > reject_before, "failed title transition uses rejection cue")
	await _frames()
	var panel: Rect2 = Rect2((app.hud.get_viewport_rect().size - Vector2(650, 508)) * 0.5, Vector2(650, 508))
	_check(app.hud.font.get_string_size(app.menu_notice,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x <= panel.size.x - 96, "complete title-save failure notice fits smallest supported scaled pause panel")
	var image: Image = root.get_texture().get_image()
	var path: String = "res://work/focus-recovery-title-failed.png"
	_check(image.save_png(path) == OK, "failed title transition screenshot is recorded")
	app.ui_action("title")
	_check(app.started and _full_state() == before and _good_slots_unchanged(), "repeated failed title attempts preserve the same live run and slots")
	_unblock_auto()
	_check(await _click_action("title"), "real Return to title retry is available after fixing storage")
	_check(not app.started and app.menu == "title", "successful AUTO write permits title transition")
	var saved: Dictionary = app.save_store.read(app.AUTOSAVE_PATH)
	var restored: Variant = load("res://scripts/campaign_simulation.gd").new()
	_check(saved.ok and restored.load_state(saved.data), "successful title transition writes a valid latest AUTO")
	_check(_canonical_saved_state(restored) == _canonical_saved_state(app.sim), "successful title transition saves the exact live simulation")
	_check(_bytes(app.SAVE_PATH) == preserved[app.SAVE_PATH] and _bytes(app.SAVE_PATH + ".bak") == preserved[app.SAVE_PATH + ".bak"], "successful title transition leaves manual recovery files unchanged")
	print("PASS _test_failed_title_save")

func _full_state() -> String:
	return JSON.stringify({"simulation":app.sim.save_state(),"selected_ids":app.selected_ids,"selected_camp":app.selected_camp,"build":app.build_kind,"task":app.pending_task,"attack":app.attack_move,"menu":app.menu,"started":app.started},"",true,true)

func _sim_state() -> String:
	return JSON.stringify(app.sim.save_state(), "", true, true)

func _canonical_saved_state(simulation: Variant) -> String:
	# JSON restores both integral and fractional numeric literals as float.
	return JSON.stringify(JSON.parse_string(JSON.stringify(simulation.save_state(), "", true, true)), "", true, true)

func _binding_codes() -> Array:
	var result: Array = []
	for action: String in app.command_names:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		result.append([action, int(events[0].physical_keycode)])
	return result

func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func _slot_bytes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in [app.SAVE_PATH, app.SAVE_PATH + ".bak", app.AUTOSAVE_PATH, app.AUTOSAVE_PATH + ".bak"]: result[path] = _bytes(path)
	return result

func _good_slots_unchanged() -> bool:
	for path: String in preserved:
		var actual: String = path + ".focus-fixture" if path == app.AUTOSAVE_PATH else path
		if _bytes(actual) != preserved[path]: return false
	return true

func _block_auto() -> void:
	var path: String = ProjectSettings.globalize_path(app.AUTOSAVE_PATH)
	_check(DirAccess.rename_absolute(path, path + ".focus-fixture") == OK, "valid AUTO bytes retained before isolated failure")
	_check(DirAccess.make_dir_absolute(path) == OK, "real directory blocks AUTO file replacement")
	blocked = true

func _unblock_auto() -> void:
	if not blocked: return
	var path: String = ProjectSettings.globalize_path(app.AUTOSAVE_PATH)
	_check(DirAccess.remove_absolute(path) == OK, "isolated write obstruction removed")
	_check(DirAccess.rename_absolute(path + ".focus-fixture", path) == OK, "previous AUTO recovery bytes restored exactly")
	blocked = false

func _release_focus_helper() -> void:
	if focus_helper_pid <= 0: return
	var file: FileAccess = FileAccess.open(HELPER_RELEASE, FileAccess.WRITE)
	if file != null:
		file.store_string("release")
		file.close()

func _wait_focus(window: Window) -> void:
	for frame: int in range(60):
		# grab_focus updates the requested focus before native X11 events arrive.
		# Require real event-pump frames before inspecting controller reactions.
		await process_frame
		if window.has_focus():
			await process_frame
			await process_frame
			return
		window.grab_focus()
	_check(false, "native focus reaches requested window: " + window.title)

func _frames(count: int = 2) -> void:
	for frame: int in range(count):
		if is_instance_valid(app): app._process(0.0)
		await process_frame
	await RenderingServer.frame_post_draw

func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(1)

func _click_action(action: String) -> bool:
	await _frames()
	for hotspot: Dictionary in app.hud.hotspots:
		if String(hotspot.get("action", "")) != action: continue
		var rectangle: Rect2 = hotspot["rect"]
		_check(app.hud.get_viewport_rect().encloses(rectangle), "clicked action fits supported viewport: " + action)
		root.warp_mouse(rectangle.get_center())
		for pressed: bool in [true, false]:
			var event: InputEventMouseButton = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = rectangle.get_center()
			event.pressed = pressed
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			await _frames()
		return true
	return false

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description)

func _deadline() -> void:
	if finishing: return
	_check(false, "focus recovery reached 90 second watchdog")
	await _finish()

func _finish() -> void:
	if finishing: return
	finishing = true
	_unblock_auto()
	for code: Key in [KEY_W, KEY_SPACE, KEY_B, KEY_F5, KEY_ESCAPE]: await _key(code, false)
	_release_focus_helper()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_factor = 1.0
	if is_instance_valid(app):
		app.set_process(false)
		app.set_process_unhandled_input(false)
		app._release_audio()
		var deadline: int = Time.get_ticks_usec() + 120000
		while Time.get_ticks_usec() < deadline: await process_frame
		app.free()
	for frame: int in range(4): await process_frame
	DisplayServer.warp_mouse(saved_mouse)
	print("Focus/title recovery checks: %d; failures: %d; native exits=%d enters=%d" % [checks, failures.size(), focus_exits, focus_enters])
	for message: String in failures: printerr(" - ", message)
	quit(0 if failures.is_empty() else 1)
