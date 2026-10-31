extends SceneTree
## Controlled native source-project UI checks and captures. These are not a
## complete campaign, exported-build acceptance, benchmark or human playtest.
## DISPLAY=:0 XDG_DATA_HOME="$PWD/work/camp-guidance-ui-data" ./run.sh
##   --audio-driver Dummy --script res://tests/test_camp_guidance_ui.gd

var app: Variant
var checks: int = 0
var failures: Array[String] = []
var screenshots: Array[Dictionary] = []
var saved_mouse: Vector2i
var last_mouse: Vector2 = Vector2.ZERO
var finishing: bool = false
var case_completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/camp-guidance-ui-data").trim_suffix("/")
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Camp guidance UI requires native DISPLAY and isolated work/camp-guidance-ui-data")
		quit(2)
		return
	saved_mouse = DisplayServer.mouse_get_position()
	create_timer(90.0).timeout.connect(_deadline)
	AudioServer.set_bus_mute(0, true)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1152, 648)
	root.content_scale_size = root.size
	root.content_scale_factor = 1.2
	root.grab_focus()
	await _frames(8)
	_check(root.size == Vector2i(1152, 648), "native physical window is 1152 by 648")
	_check(app.get_viewport_rect().size.is_equal_approx(Vector2(960, 540)), "120 percent UI scale produces a 960 by 540 logical viewport")
	for test_case: Callable in [_test_pause_rebinding, _test_packing_source_guidance]:
		var previous: int = failures.size()
		case_completed = false
		await test_case.call()
		_check(case_completed, "case reaches completion guard: " + test_case.get_method())
		print("%s %s" % ["PASS" if failures.size() == previous else "FAIL", test_case.get_method()])
	await _finish()


func _reset(show_guide: bool = false) -> void:
	app.start_campaign("canyon")
	app.set_process(false)
	app._setup_inputs()
	app.sim.paused = true
	app.edge_scroll = false
	app.menu = ""
	app.feedback_left = 0.0
	app.guide.reset(show_guide)
	app.guide_clock = 0.0
	await _frames(2)
	_check(not app._window_suspended, "native test window is not suspended by focus loss")


func _test_pause_rebinding() -> void:
	await _reset()
	app.sim.paused = false
	var binding: InputEventKey = InputEventKey.new()
	binding.physical_keycode = KEY_J
	_check(app._try_bind("pause_game", binding), "actual settings controller rebinds pause to J")
	await _key(KEY_SPACE)
	_check(not app.sim.paused, "old Space input does not pause after rebinding")
	await _key(KEY_J)
	_check(app.sim.paused, "native engine-dispatched J pauses the actual simulation")
	_check(app.hud._pause_banner_text().contains("J 继续"), "drawn banner text uses rebound J")
	await _hover_action("tab:build")
	_check(app.hud.tooltip.contains("战术已暂停") and app.hud.tooltip.contains("J 继续") and not app.hud.tooltip.contains("地图继续运行"), "actual small-screen hover describes paused state and J continue action")
	await _capture("pause-j-small.png", true)
	await _key(KEY_J)
	_check(not app.sim.paused, "engine-dispatched J resumes the actual simulation")
	await _hover_action("tab:build")
	_check(app.hud.tooltip.contains("地图继续运行") and app.hud.tooltip.contains("J 暂停"), "actual small-screen hover changes to running and J pause action")
	binding.physical_keycode = KEY_BACKSPACE
	_check(app._try_bind("pause_game", binding), "actual settings controller accepts the longer Backspace binding")
	await _key(KEY_J)
	_check(not app.sim.paused, "previous J input stops toggling after the second rebind")
	await _key(KEY_BACKSPACE)
	_check(app.sim.paused, "engine-dispatched Backspace pauses the actual simulation")
	var label: String = app.binding_label("pause_game")
	_check(app.hud._pause_banner_text().contains(label + " 继续"), "banner preserves complete current long key name")
	await _hover_action("tab:training")
	_check(app.hud.tooltip.contains(label + " 继续"), "actual training-tab hover uses the same complete long key name")
	await _capture("pause-backspace-small.png", true)
	case_completed = true


func _test_packing_source_guidance() -> void:
	await _reset(true)
	# A focused presentation fixture: created camps/resources are declared here.
	# Packing itself uses the unchanged actual evacuation command and its truck.
	var origin: Dictionary = app.sim.camps[0]
	origin.name = "西部医疗营"
	var receiver: Dictionary = app.sim._make_camp(Vector2(54, 23), "河谷接收营", 160.0, 80.0, 30.0)
	app.sim._add_building("camp", Vector2(receiver.pos), int(receiver.id), 1.0)
	_check(app.sim.evacuate_camp(int(origin.id)), "original evacuation command starts packing toward the receiver")
	_check(origin.state == "packing" and int(origin.evac_target_id) == int(receiver.id), "real source camp is packing for the named receiver")
	await _frames(2)
	if not await _click_action("camp:%d" % int(receiver.id)):
		return
	_check(app.selected_camp == int(receiver.id), "actual camp card selects the receiving camp")
	var before: String = JSON.stringify(app.sim.save_state())
	app.guide.update(app.sim, app.selected_ids, app.selected_camp)
	var hint: Dictionary = app.guide.get_hint()
	var text: String = String(hint.text)
	_check(text.contains("先选中「西部医疗营」"), "wrong-camp guide explicitly names the source that must be selected")
	_check(text.contains("河谷接收营") and text.contains("“紧急弃营”") and not text.contains("“撤收驻点”"), "packing guide names the receiver and the actual emergency button")
	var dialog_lines: Array[String] = app.hud._wrap_text(app.guide_text(text), 848, 18)
	var visible_text: String = ""
	# Actual dialog at 960x540: 900x508 panel, 848 text width, eight lines.
	for index: int in range(mini(8, dialog_lines.size())):
		visible_text += dialog_lines[index]
	_check(visible_text.contains("先选中「西部医疗营」") and visible_text.contains("“紧急弃营”"), "critical source-selection and emergency action fit the actual small dialog line limit")
	_check(Vector2(hint.target).is_equal_approx(Vector2(origin.pos)), "emergency action hint locates the source camp rather than the transport truck")
	_check(app.selected_camp == int(receiver.id) and before == JSON.stringify(app.sim.save_state()), "guide observation preserves selected receiver and complete simulation/RNG")
	app.menu = "guide"
	app.feedback_left = 0.0
	await _capture("packing-wrong-camp-guide-small.png")
	var camera_before: Vector2 = app.camera.position
	var selected_before: Array = app.selected_ids.duplicate()
	if not await _click_action("guide_focus"):
		return
	_check(app.menu.is_empty() and app.camera.position.is_equal_approx(Vector2(origin.pos) * app.TILE), "actual guide-focus button returns to battle and locates the source")
	_check(not app.camera.position.is_equal_approx(camera_before), "guide focus actually moves the camera from the receiver")
	_check(app.selected_camp == int(receiver.id) and app.selected_ids == selected_before and before == JSON.stringify(app.sim.save_state()), "guide focus does not change camp selection, unit selection, orders or simulation/RNG")
	if not await _click_action("camp:%d" % int(origin.id)):
		return
	if not await _click_action("tab:orders"):
		return
	var emergency: Dictionary = _hotspot("evacuate")
	_check(not emergency.is_empty() and String(emergency.get("tip", "")).contains("未装车物资"), "selected source exposes its real emergency-abandon action")
	app.guide.update(app.sim, app.selected_ids, app.selected_camp)
	_check(String(app.guide.get_hint().text).contains("当前已选中「西部医疗营」"), "guide reflects the source selected explicitly by the player")
	await _capture("packing-source-action-small.png")
	_check(origin.state == "packing", "inspecting the button never executes emergency abandonment")
	case_completed = true


func _frames(count: int = 2) -> void:
	for frame: int in range(count):
		if is_instance_valid(app):
			app._process(0.0)
			app.hud.queue_redraw()
			app.world.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(1)


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


func _hotspot(action: String) -> Dictionary:
	for hotspot: Dictionary in app.hud.hotspots:
		if String(hotspot.action) == action:
			return hotspot
	return {}


func _hover_action(action: String) -> bool:
	await _frames(1)
	var hotspot: Dictionary = _hotspot(action)
	_check(not hotspot.is_empty(), "rendered hotspot exists: " + action)
	if hotspot.is_empty():
		return false
	_check(app.get_viewport_rect().encloses(hotspot.rect), "rendered hotspot fits logical viewport: " + action)
	await _motion(hotspot.rect.get_center())
	return true


func _click_action(action: String) -> bool:
	if not await _hover_action(action):
		return false
	var point: Vector2 = _hotspot(action).rect.get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(1)
	return true


func _capture(name: String, keep_mouse: bool = false) -> void:
	if not keep_mouse:
		await _motion(Vector2(480, 70))
	await _frames(2)
	var directory: String = ProjectSettings.globalize_path("res://work/camp-guidance-ui")
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join(name)
	var image: Image = root.get_texture().get_image()
	_check(image.get_size() == Vector2i(1152, 648), "actual native capture has physical dimensions: " + name)
	_check(image.save_png(path) == OK, "native screenshot saved: " + name)
	screenshots.append({"path": path, "sha256": FileAccess.get_sha256(path), "width": image.get_width(), "height": image.get_height()})


func _deadline() -> void:
	if finishing:
		return
	_check(false, "90 second watchdog reached; case may not have completed")
	await _finish()


func _finish() -> void:
	if finishing:
		return
	finishing = true
	if is_instance_valid(app):
		app.set_process(false)
		app.set_process_unhandled_input(false)
		app._release_camera_actions()
		app._release_audio()
		var audio_deadline: int = Time.get_ticks_usec() + 120000
		while Time.get_ticks_usec() < audio_deadline:
			await process_frame
		app.queue_free()
		app = null
	for frame: int in range(3):
		await process_frame
	root.content_scale_factor = 1.0
	DisplayServer.warp_mouse(saved_mouse)
	print("Camp guidance UI checks: %d; failures: %d" % [checks, failures.size()])
	print("Scope: controlled native source UI; no complete campaign, exported build, benchmark or human-playtest claim")
	print("Isolated user data: ", OS.get_user_data_dir())
	for screenshot: Dictionary in screenshots:
		print("Screenshot: ", JSON.stringify(screenshot))
	for failure: String in failures:
		printerr(" - ", failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
