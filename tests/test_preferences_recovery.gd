extends SceneTree
## Rendered application integration, using actual HUD hotspots and controller keys.
## This does not emulate a human/native desktop mouse or claim manual usability.
## DISPLAY=:0 XDG_DATA_HOME="$PWD/work/preferences-test-data" Godot --path .
##   --audio-driver Dummy --script res://tests/test_preferences_recovery.gd

var app: Variant
var failures: Array[String] = []
var checks: int = 0
var save_path: String = ""
var automatic_path: String = ""
var config_path: String = ""
var isolated_root: String = ""
var default_bindings: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	isolated_root = ProjectSettings.globalize_path("res://work/preferences-test-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolated_root + "/"):
		printerr("Refusing preferences test outside isolated XDG_DATA_HOME: ", OS.get_user_data_dir())
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("Preferences integration requires DISPLAY and real rendering")
		quit(2)
		return
	var main_script: Script = load("res://scripts/main.gd") as Script
	if main_script == null or not main_script.can_instantiate():
		printerr("Main scene controller cannot compile")
		quit(1)
		return
	var constants: Dictionary = main_script.get_script_constant_map()
	save_path = String(constants["SAVE_PATH"])
	automatic_path = String(constants["AUTOSAVE_PATH"])
	config_path = String(constants["CONFIG_PATH"])
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	for path: String in [save_path, save_path + ".bak", automatic_path, automatic_path + ".bak", config_path, config_path + ".tmp"]:
		if not _isolated(path):
			printerr("Refusing nonisolated game path: ", path)
			quit(2)
			return
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	root.content_scale_factor = 1.0
	await _reload_scene()
	default_bindings = _bindings()
	_check(root.size == Vector2i(1600, 900), "test starts in a real 1600 x 900 window")
	_check(DisplayServer.get_name() != "headless", "test uses real DISPLAY rendering")
	var cases: Array[Callable] = [
		_test_guide_controls_and_real_progress,
		_test_save_slots_recovery_and_ui_state,
		_test_bindings_pages_conflicts_and_cancel,
		_test_audio_display_and_persisted_restart,
		_test_corrupt_settings_are_safe,
		_test_restart_confirmation_and_auto_recovery,
	]
	for test_case: Callable in cases:
		var previous: int = failures.size()
		await test_case.call()
		print("%s %s" % ["PASS" if failures.size() == previous else "FAIL", test_case.get_method()])
	await _restore_window()
	print("Preferences/recovery checks: %d; failures: %d" % [checks, failures.size()])
	print("Isolated user data: ", OS.get_user_data_dir())
	for failure: String in failures:
		printerr(" - " + failure)
	if is_instance_valid(app):
		app.queue_free()
		# Let asynchronous audio playback release its stream before engine teardown.
		await _frames(6)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _frames(count: int = 4) -> void:
	for index: int in range(count):
		if is_instance_valid(app) and app.hud != null:
			app.hud.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw


func _reload_scene() -> void:
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
		await process_frame
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	app = scene.instantiate()
	root.add_child(app)
	await _frames(12)


func _hotspot(action: String) -> Dictionary:
	for value: Dictionary in app.hud.hotspots:
		if String(value.get("action", "")) == action:
			return value
	return {}


func _click(action: String) -> bool:
	await _frames()
	var found: Dictionary = _hotspot(action)
	if found.is_empty():
		var available: Array[String] = []
		for hotspot: Dictionary in app.hud.hotspots:
			available.append(String(hotspot.get("action", "")))
		_check(false, "visible hotspot exists: %s; actual=%s" % [action, str(available)])
		return false
	var rectangle: Rect2 = found["rect"]
	var logical: Rect2 = app.hud.get_viewport_rect()
	_check(logical.encloses(rectangle), "hotspot lies within current logical viewport: " + action)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = rectangle.get_center()
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var consumed: bool = app.hud.handle_mouse(event)
	_check(consumed, "real HUD consumes " + action)
	await _frames()
	return consumed


func _key(code: Key, control: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.ctrl_pressed = control
	event.pressed = true
	app._unhandled_input(event)
	await _frames()
	event.pressed = false
	app._unhandled_input(event)


func _all_hotspots_fit(label: String) -> void:
	var logical: Rect2 = app.hud.get_viewport_rect()
	var overflow: Array[String] = []
	for hotspot: Dictionary in app.hud.hotspots:
		if not logical.encloses(hotspot["rect"]):
			overflow.append(String(hotspot.get("action", "")) + ":" + str(hotspot["rect"]))
	_check(overflow.is_empty(), "%s hotspots fit %s: %s" % [label, str(logical.size), str(overflow)])


func _bindings() -> Dictionary:
	var result: Dictionary = {}
	for action: String in app.command_names:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		var keys: Array[Dictionary] = []
		for event: InputEvent in events:
			if event is InputEventKey:
				keys.append({"physical": event.physical_keycode, "key": event.keycode, "ctrl": event.ctrl_pressed, "alt": event.alt_pressed, "shift": event.shift_pressed, "meta": event.meta_pressed})
		result[action] = keys
	return result


func _code(action: String) -> int:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	return int(events[0].physical_keycode) if not events.is_empty() and events[0] is InputEventKey else 0


func _canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _snapshot() -> String:
	return _canonical(app._save_payload())


func _json_normalized(snapshot: String) -> String:
	# JSON has one numeric type: parsing converts integer leaves to float.
	# Normalize both sides once so complete persisted states compare by value.
	return _canonical(JSON.parse_string(snapshot))


func _difference(expected: String, actual: String) -> String:
	for index: int in range(mini(expected.length(), actual.length())):
		if expected[index] != actual[index]:
			return " at character %d: expected %s; actual %s" % [index, expected.substr(maxi(0, index - 75), 170), actual.substr(maxi(0, index - 75), 170)]
	return " (lengths %d and %d)" % [expected.length(), actual.length()]


func _ids(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	result.sort()
	return result


func _isolated(path: String) -> bool:
	return ProjectSettings.globalize_path(path).begins_with(isolated_root + "/")


func _bytes(path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var result: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return result


func _put(path: String, bytes: PackedByteArray) -> void:
	_check(_isolated(path), "fixture writes only to isolated user data")
	if not _isolated(path):
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "isolated corruption fixture opens")
	if file == null:
		return
	file.store_buffer(bytes)
	file.flush()
	_check(file.get_error() == OK, "isolated fixture write completes")
	file.close()


func _advance_real(seconds: float) -> void:
	app.sim.paused = false
	for index: int in range(ceili(seconds / 0.1)):
		app.sim.tick(0.1)
		if String(app.sim.outcome) != "playing":
			break
	app.sim.paused = true


func _capture(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work"))
	await _frames(6)
	var frame: Image = root.get_texture().get_image()
	_check(frame != null and not frame.is_empty(), "rendered screenshot has actual viewport pixels")
	if frame != null and not frame.is_empty():
		_check(frame.save_png(ProjectSettings.globalize_path(path)) == OK, "saved real rendered screenshot " + path)


func _test_guide_controls_and_real_progress() -> void:
	_check(app.menu == "title" and not app.started, "real application opens the title menu")
	await _click("new")
	app.sim.paused = true
	await _frames(25)
	_check(app.started and app.menu.is_empty(), "actual new-game hotspot starts campaign")
	_check(app.selected_ids.size() >= 4, "real new campaign selects the four-person starting squad")
	var hint: Dictionary = app.guide.get_hint()
	_check(bool(hint["visible"]) and int(hint["step"]) == 1, "live guide panel begins on real first milestone")
	var before: String = _canonical(app.sim.save_state())
	var target: Vector2 = hint["target"]
	await _click("guide_focus")
	_check(Vector2(app.camera.position).distance_to(target * 48.0) < 0.1, "guide focus moves camera to its real tile target")
	_check(_canonical(app.sim.save_state()) == before, "guide focus changes no simulation state or unit orders")
	# Compare simulation alone because camera movement is the purpose of focus.
	var stable_sim: String = _canonical(app.sim.save_state())
	await _click("guide_more")
	_check(app.menu == "guide", "guide expands through its rendered hotspot")
	await _click("guide_focus")
	_check(app.menu.is_empty() and _canonical(app.sim.save_state()) == stable_sim, "expanded-guide focus returns to game without issuing orders")
	await _click("guide_toggle")
	_check(not bool(app.guide.get_hint()["visible"]), "hide hotspot actually hides the guide")
	await _click("tab:orders")
	await _click("task:clear")
	app._issue_context(Vector2(25.0, 20.0))
	_advance_real(45.0)
	await _frames(25)
	var road_captured: bool = false
	for site: Dictionary in app.sim.sites:
		if String(site.get("kind", "")) == "cache" and Vector2(site["pos"]).x < 40.0:
			road_captured = bool(site.get("captured", false))
	_check(road_captured, "actual squad command, combat and occupation capture the road point")
	_check(not bool(app.guide.get_hint()["visible"]) and int(app.guide.get_hint()["step"]) >= 2, "hidden guide follows real simulation progress")
	await _click("guide_toggle")
	_check(bool(app.guide.get_hint()["visible"]) and int(app.guide.get_hint()["step"]) >= 2, "restoring guide keeps the current milestone")
	_all_hotspots_fit("campaign and guide")
	await _capture("res://work/guide.png")


func _test_save_slots_recovery_and_ui_state() -> void:
	var all_selected: Array = app.selected_ids.duplicate()
	await _key(KEY_1, true)
	_check(_ids(app.group_bindings.get(1, [])) == _ids(all_selected), "Ctrl+1 saves actual selected IDs")
	var rifles: Array[Dictionary] = []
	for unit: Dictionary in app.sim.units:
		if String(unit.get("team", "")) == "friendly" and String(unit.get("kind", "")) == "rifle":
			rifles.append(unit)
	var minimum: Vector2 = Vector2(INF, INF)
	var maximum: Vector2 = Vector2(-INF, -INF)
	for unit: Dictionary in rifles:
		var point: Vector2 = unit["pos"]
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	app.drag_start = (minimum - Vector2.ONE * 0.15) * 48.0
	app._select((maximum + Vector2.ONE * 0.15) * 48.0, false, false)
	await _key(KEY_2, true)
	var saved_selection: Array = app.selected_ids.duplicate()
	var saved_group1: Array = app.group_bindings.get(1, []).duplicate()
	var saved_group2: Array = app.group_bindings.get(2, []).duplicate()
	_check(not saved_selection.is_empty() and not saved_group2.is_empty(), "real box controller and group input prepare live save metadata")
	await _key(KEY_EQUAL)
	await _click("ranges")
	await _click("logistics")
	await _click("guide_toggle")
	var expected_camera: Vector2 = app.camera.position
	var expected_zoom: float = float(app.camera.zoom.x)
	var expected_camp: int = int(app.selected_camp)
	var expected_step: int = int(app.guide.get_hint()["step"])
	var expected_speed: float = float(app.speed)
	_check(expected_speed == 2.0 and app.world.show_ranges and not app.world.show_logistics, "real controls set speed and overlay metadata")
	_check(bool(app.save_campaign()), "first manual save succeeds through main and SaveStore")
	var first: PackedByteArray = _bytes(save_path)
	var first_time: float = float(app.sim.time)
	_check(not first.is_empty() and _bytes(save_path + ".bak") == first, "first main save also has a valid first backup")
	_advance_real(1.0)
	await _frames(22)
	_check(bool(app.save_campaign()), "second manual save succeeds")
	var second: PackedByteArray = _bytes(save_path)
	_check(second != first and _bytes(save_path + ".bak") == first, "second manual save rotates exact first bytes into backup")
	await _key(KEY_EQUAL)
	await _click("ranges")
	await _click("logistics")
	await _key(KEY_4)
	await _click("minimap")
	_advance_real(2.0)
	await _frames(22)
	_check(bool(app.save_campaign(false)), "actual automatic-save API writes its own slot")
	_check(FileAccess.file_exists(automatic_path) and not _bytes(automatic_path).is_empty(), "automatic slot is present")
	_check(_bytes(save_path) == second and _bytes(save_path + ".bak") == first, "automatic save never overwrites manual primary or backup")
	_put(save_path, "{ corrupt primary".to_utf8_buffer())
	var before_bad: String = _snapshot()
	_check(not bool(app.load_campaign()), "corrupt manual load fails without automatic recovery")
	_check(_snapshot() == before_bad, "bad primary does not partially replace simulation, selection, camera, groups or guide")
	await _click("menu")
	_check(not _hotspot("load_backup").is_empty(), "real pause menu exposes an explicit backup recovery action")
	await _click("load_backup")
	_check(app.menu.is_empty() and is_equal_approx(float(app.sim.time), first_time), "explicit backup action really restores the older simulation")
	_check(_ids(app.selected_ids) == _ids(saved_selection), "backup restores selected live IDs")
	_check(_ids(app.group_bindings.get(1, [])) == _ids(saved_group1) and _ids(app.group_bindings.get(2, [])) == _ids(saved_group2), "backup restores both numbered formations")
	_check(is_equal_approx(float(app.speed), expected_speed) and app.world.show_ranges and not app.world.show_logistics, "backup restores speed and logistics/range overlays")
	_check(int(app.selected_camp) == expected_camp and Vector2(app.camera.position).distance_to(expected_camera) < 0.1 and is_equal_approx(float(app.camera.zoom.x), expected_zoom), "backup restores camp and camera metadata")
	_check(not bool(app.guide.get_hint()["visible"]) and int(app.guide.get_hint()["step"]) == expected_step, "backup restores hidden guide and progressed milestone")
	_check(bool(app.save_campaign()), "saving after explicit backup recovery repairs primary")
	_check(_bytes(save_path + ".bak") == first, "repairing corrupt primary cannot poison the good backup")
	var repaired: PackedByteArray = _bytes(save_path)
	var malformed: Dictionary = app.save_store.read(save_path)["data"]
	malformed["ui"]["guide"]["dismissed"] = "not a bool"
	_put(save_path, JSON.stringify(malformed).to_utf8_buffer())
	var before_bad_guide: String = _snapshot()
	_check(not bool(app.load_campaign()), "malformed guide metadata in otherwise valid save is rejected")
	_check(_snapshot() == before_bad_guide, "bad guide metadata cannot replace any live state")
	_put(save_path, repaired)
	await _click("guide_toggle")


func _test_bindings_pages_conflicts_and_cancel() -> void:
	await _click("menu")
	await _click("settings")
	await _click("settings_tab:controls")
	var seen: Dictionary = {}
	var total: int = app.command_names.size()
	var pages: int = ceili(float(total) / 10.0)
	_check(total == 23, "all 23 named actions are represented in application settings")
	for page: int in range(pages):
		_check(int(app.settings_page) == page, "binding pagination reaches actual page %d" % page)
		for item: Dictionary in app.hud.hotspots:
			var action: String = String(item.get("action", ""))
			if action.begins_with("bind:"):
				seen[action.trim_prefix("bind:")] = true
		_all_hotspots_fit("binding page %d" % page)
		if page + 1 < pages:
			await _click("bindings_next")
	_check(seen.size() == total, "all named binding actions have visible accessible hotspots across pages")
	for action: String in app.command_names:
		_check(seen.has(action), "binding action is accessible: " + action)
	for page: int in range(pages - 1):
		await _click("bindings_prev")
	var previous_bindings: String = _canonical(_bindings())
	_check(_code("production_menu") == KEY_P and _code("camera_up") == KEY_W, "clean isolated settings start with expected P and W bindings")
	await _click("bind:production_menu")
	await _key(KEY_W)
	_check(_canonical(_bindings()) == previous_bindings, "P-to-W conflict changes none of the 23 input bindings")
	_check(String(app.settings_feedback).contains("冲突") and app.waiting_binding == "production_menu", "conflict is reported and capture remains pending")
	await _key(KEY_ESCAPE)
	_check(app.waiting_binding.is_empty() and app.menu == "settings" and _canonical(_bindings()) == previous_bindings, "Escape cancels capture without leaving settings or changing bindings")
	await _click("bind:production_menu")
	await _key(KEY_U)
	_check(app.waiting_binding.is_empty() and _code("production_menu") == KEY_U and _code("camera_up") == KEY_W, "P-to-U binding succeeds and leaves W intact")
	var config: ConfigFile = ConfigFile.new()
	_check(config.load(config_path) == OK and int(config.get_value("keys", "production_menu", 0)) == KEY_U, "valid rebind is saved to the isolated configuration")
	await _click("back")
	await _click("resume")
	app.current_tab = "build"
	await _key(KEY_U)
	_check(app.current_tab == "production", "new physical U key activates the actual production tab")
	app.current_tab = "orders"
	await _key(KEY_P)
	_check(app.current_tab == "orders", "replaced physical P key no longer activates production")


func _test_audio_display_and_persisted_restart() -> void:
	await _click("menu")
	await _click("settings")
	await _click("settings_tab:display")
	var music_bus: int = AudioServer.get_bus_index("Music")
	var effects_bus: int = AudioServer.get_bus_index("SFX")
	_check(music_bus > 0 and effects_bus > 0 and music_bus != effects_bus, "actual Music and SFX audio buses exist separately")
	_check(String(app.music_player.bus) == "Music" and String(app.sound_player.bus) == "SFX", "real audio players route to their own buses")
	var effects_before: float = AudioServer.get_bus_volume_db(effects_bus)
	var music_before: float = AudioServer.get_bus_volume_db(music_bus)
	await _click("music_volume")
	_check(not is_equal_approx(AudioServer.get_bus_volume_db(music_bus), music_before) and is_equal_approx(AudioServer.get_bus_volume_db(effects_bus), effects_before), "music control changes Music bus without changing SFX bus")
	var music_after: float = AudioServer.get_bus_volume_db(music_bus)
	await _click("effects_volume")
	_check(not is_equal_approx(AudioServer.get_bus_volume_db(effects_bus), effects_before) and is_equal_approx(AudioServer.get_bus_volume_db(music_bus), music_after), "effects control changes SFX without changing Music")
	await _audio_boundaries(music_bus, effects_bus)
	var master_level: float = float(app.volume)
	var music_level: float = float(app.music_volume)
	var effects_level: float = float(app.effects_volume)
	await _click("mute")
	_check(app.muted and AudioServer.is_bus_mute(0), "mute reaches the actual Master bus")
	_check(is_equal_approx(float(app.volume), master_level) and is_equal_approx(float(app.music_volume), music_level) and is_equal_approx(float(app.effects_volume), effects_level), "mute preserves all three remembered levels")
	for attempt: int in range(5):
		if app.window_resolution == Vector2i(1600, 900):
			break
		await _click("resolution")
	_check(app.window_resolution == Vector2i(1600, 900) and root.size == Vector2i(1600, 900), "resolution control changes real window to 1600 x 900")
	await _click("fullscreen")
	await _frames(20)
	_check(app.fullscreen and root.mode == Window.MODE_FULLSCREEN, "fullscreen control changes the real test window mode")
	await _click("ui_scale")
	await _click("ui_scale")
	_check(is_equal_approx(float(app.ui_scale), 1.2) and is_equal_approx(float(root.content_scale_factor), 1.2), "120 percent UI scaling reaches the actual viewport")
	_all_hotspots_fit("fullscreen at 120 percent")
	await _reload_scene()
	_check(_code("production_menu") == KEY_U, "valid U binding survives scene reconstruction")
	_check(app.fullscreen and root.mode == Window.MODE_FULLSCREEN and app.window_resolution == Vector2i(1600, 900) and is_equal_approx(float(app.ui_scale), 1.2), "fullscreen, chosen window resolution and 120 percent scale persist")
	_check(app.muted and AudioServer.is_bus_mute(0) and is_equal_approx(float(app.music_volume), music_level) and is_equal_approx(float(app.effects_volume), effects_level), "mute and independent audio levels survive scene reconstruction")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(maxf(music_level, 0.0001))) and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(maxf(effects_level, 0.0001))), "persisted levels reach real buses after reconstruction")
	await _click("settings")
	await _click("settings_tab:display")
	await _click("fullscreen")
	await _frames(20)
	_check(not app.fullscreen and root.mode == Window.MODE_WINDOWED and root.size == Vector2i(1600, 900), "leaving fullscreen restores chosen real window resolution")
	_all_hotspots_fit("1600 x 900 window at 120 percent")
	await _click("ui_scale")
	_check(is_equal_approx(float(app.ui_scale), 1.0), "UI scale cycle can restore 100 percent")
	_all_hotspots_fit("restored settings")
	await _capture("res://work/preferences-settings.png")
	await _click("back")
	await _click("new")
	app.sim.paused = true
	app.current_tab = "build"
	await _key(KEY_U)
	_check(app.current_tab == "production", "persisted custom key works in a fresh campaign after restart")


func _audio_boundaries(music_bus: int, effects_bus: int) -> void:
	var remembered_music: float = float(app.music_volume)
	var remembered_effects: float = float(app.effects_volume)
	var effects_gain: float = AudioServer.get_bus_volume_db(effects_bus)
	# Set up the non-cycle-aligned edge; the actual HUD must clamp the next click.
	app.volume = 0.9
	app._apply_audio_settings()
	await _click("volume")
	_check(is_equal_approx(float(app.volume), 1.0) and is_equal_approx(AudioServer.get_bus_volume_db(0), 0.0), "master 90 percent plus one real HUD click clamps to exactly 100 percent")
	await _click("volume")
	_check(is_equal_approx(float(app.volume), 0.0) and AudioServer.is_bus_mute(0) and is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.001)), "zero master gain really mutes Master with the defined finite gain floor")
	_check(not app.muted and not AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(effects_bus) and is_equal_approx(float(app.music_volume), remembered_music) and is_equal_approx(float(app.effects_volume), remembered_effects), "zero master leaves the remembered mute toggle and independent channel levels intact")
	await _click("volume")
	_check(is_equal_approx(float(app.volume), 0.2) and not AudioServer.is_bus_mute(0), "raising master from zero restores audible Master without changing the mute preference")
	for attempt: int in range(12):
		if is_equal_approx(float(app.music_volume), 0.0): break
		await _click("music_volume")
	_check(is_equal_approx(float(app.music_volume), 0.0) and AudioServer.is_bus_mute(music_bus), "music gain cycle reaches zero and actually mutes Music")
	_check(not AudioServer.is_bus_mute(effects_bus) and not AudioServer.is_bus_mute(0) and is_equal_approx(float(app.effects_volume), remembered_effects) and is_equal_approx(AudioServer.get_bus_volume_db(effects_bus), effects_gain), "muting Music cannot mute or change the SFX channel or Master")
	await _click("music_volume")
	_check(is_equal_approx(float(app.music_volume), 0.1) and not AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(effects_bus), "raising Music from zero unmutes only its channel")
	var restored_music_gain: float = AudioServer.get_bus_volume_db(music_bus)
	for attempt: int in range(12):
		if is_equal_approx(float(app.effects_volume), 0.0): break
		await _click("effects_volume")
	_check(is_equal_approx(float(app.effects_volume), 0.0) and AudioServer.is_bus_mute(effects_bus), "effects gain cycle reaches zero and actually mutes SFX")
	_check(not AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(0) and is_equal_approx(float(app.music_volume), 0.1) and is_equal_approx(AudioServer.get_bus_volume_db(music_bus), restored_music_gain), "muting SFX cannot mute or change Music or Master")
	await _click("effects_volume")
	_check(is_equal_approx(float(app.effects_volume), 0.1) and not AudioServer.is_bus_mute(effects_bus) and not AudioServer.is_bus_mute(music_bus) and is_equal_approx(AudioServer.get_bus_volume_db(music_bus), restored_music_gain), "raising SFX from zero restores effects while preserving Music")


func _test_corrupt_settings_are_safe() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "volume", "loud")
	config.set_value("audio", "music", [])
	config.set_value("audio", "effects", 7.5)
	config.set_value("audio", "muted", "yes")
	config.set_value("input", "edge_scroll", 7)
	config.set_value("game", "guide", "hidden")
	config.set_value("video", "fullscreen", 2)
	config.set_value("video", "configured", "yes")
	config.set_value("video", "resolution", Vector2(-500.0, 99999.0))
	config.set_value("video", "ui_scale", "huge")
	config.set_value("keys", "camera_up", KEY_W)
	config.set_value("keys", "production_menu", KEY_W)
	_check(_isolated(config_path) and config.save(config_path) == OK, "malformed-value settings fixture is written only in isolated profile")
	await _reload_scene()
	_check(app.menu == "title" and is_instance_valid(app.hud), "malformed settings do not crash scene construction")
	_check(is_equal_approx(float(app.volume), 0.6) and is_equal_approx(float(app.music_volume), 0.35) and is_equal_approx(float(app.effects_volume), 1.0), "invalid audio types fall back while valid out-of-range numbers clamp")
	_check(not app.muted and not app.edge_scroll and app.guide_enabled and not app.fullscreen and is_equal_approx(float(app.ui_scale), 1.0), "corrupt boolean/guide/display values get safe typed defaults")
	_check(app.window_resolution == Vector2i(1440, 810), "invalid resolution type cannot enter display configuration")
	_check(_canonical(_bindings()) == _canonical(default_bindings) and String(app.settings_feedback).contains("无效"), "duplicate persisted bindings restore the complete default input map")
	_all_hotspots_fit("safe title after corrupt settings")
	await _click("new")
	app.sim.paused = true
	await _frames(22)
	_check(bool(app.guide.get_hint()["visible"]) and int(app.guide.get_hint()["step"]) == 1, "invalid guide setting still allows a fresh visible guide")


func _test_restart_confirmation_and_auto_recovery() -> void:
	_advance_real(3.0)
	await _key(KEY_3, true)
	await _frames(25)
	_check(app.started and app.menu.is_empty() and String(app.sim.outcome) == "playing" and app.sim.paused, "restart fixture is a real progressed paused campaign")
	var previous_campaign: String = _snapshot()
	var previous_saved_campaign: String = _json_normalized(previous_campaign)
	var previous_selection: Array = app.selected_ids.duplicate()
	var previous_time: float = float(app.sim.time)
	var manual_before: PackedByteArray = _bytes(save_path)
	var backup_before: PackedByteArray = _bytes(save_path + ".bak")
	var automatic_before: PackedByteArray = _bytes(automatic_path)
	await _click("menu")
	await _click("new")
	_check(app.menu == "restart", "restarting a live campaign opens the dedicated confirmation menu")
	_check(not _hotspot("restart_confirm").is_empty() and not _hotspot("resume").is_empty(), "restart confirmation offers explicit confirm and cancel actions")
	_check(_snapshot() == previous_campaign, "opening restart confirmation preserves the complete current campaign")
	_check(_bytes(save_path) == manual_before and _bytes(save_path + ".bak") == backup_before and _bytes(automatic_path) == automatic_before, "opening restart confirmation writes no save slot")
	await _click("resume")
	_check(app.menu.is_empty() and _snapshot() == previous_campaign, "cancelling restart resumes the unchanged campaign")
	_check(_bytes(save_path) == manual_before and _bytes(save_path + ".bak") == backup_before and _bytes(automatic_path) == automatic_before, "cancelling restart leaves manual, backup and automatic slots untouched")
	await _click("menu")
	await _click("new")
	_check(app.menu == "restart" and _snapshot() == previous_campaign, "a second restart request still waits for confirmation without resetting simulation")
	await _click("restart_confirm")
	_check(app.started and app.menu.is_empty() and String(app.sim.outcome) == "playing", "confirming restart starts a playable new campaign through the real HUD")
	_check(float(app.sim.time) < previous_time and app.sim.camps.size() == 1 and int(app.guide.get_hint()["step"]) == 1, "confirmed restart resets real simulation time, camps and guide progress")
	if not app.sim.paused:
		await _click("pause")
	_check(app.sim.paused, "new campaign can be tactically paused through its HUD")
	var saved_previous: Dictionary = app.save_store.read(automatic_path)
	var saved_previous_state: String = _json_normalized(_canonical(saved_previous.get("data", {})))
	_check(bool(saved_previous.get("ok", false)) and saved_previous_state == previous_saved_campaign, "confirmed restart autosaves the exact previous simulation, guide and UI before resetting" + ("" if saved_previous_state == previous_saved_campaign else _difference(previous_saved_campaign, saved_previous_state)))
	_check(not _bytes(automatic_path).is_empty() and _bytes(automatic_path) != automatic_before, "confirmed restart writes the previous campaign into the separate automatic slot")
	_check(_bytes(save_path) == manual_before and _bytes(save_path + ".bak") == backup_before, "confirmed restart preserves the existing manual primary and manual backup")
	await _click("menu")
	_check(not _hotspot("load_auto").is_empty(), "new campaign menu exposes the previous campaign automatic save")
	await _click("load_auto")
	_check(app.started and app.menu.is_empty() and is_equal_approx(float(app.sim.time), previous_time), "explicit automatic-load action restores the campaign that preceded restart")
	var restored_campaign: String = _json_normalized(_snapshot())
	_check(restored_campaign == previous_saved_campaign, "automatic recovery restores complete old simulation, selection, camera, groups, overlays and guide" + ("" if restored_campaign == previous_saved_campaign else _difference(previous_saved_campaign, restored_campaign)))
	var selection_usable: bool = app.selected_ids.size() == previous_selection.size()
	var formation_usable: bool = app.group_bindings.get(3, []).size() == previous_selection.size()
	for id: int in previous_selection:
		selection_usable = selection_usable and app.selected_ids.has(id)
		formation_usable = formation_usable and app.group_bindings.get(3, []).has(id)
	_check(selection_usable, "restored selected IDs support integer membership used by real unit highlights and guide")
	_check(formation_usable, "restored numbered formation IDs support integer membership used by actual selection")
	_check(_bytes(save_path) == manual_before and _bytes(save_path + ".bak") == backup_before, "recovering the restart autosave leaves manual primary and backup intact")


func _restore_window() -> void:
	if is_instance_valid(app):
		app.fullscreen = false
		app.ui_scale = 1.0
		app.window_resolution = Vector2i(1600, 900)
		app.display_configured = true
		app._apply_display_settings()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_factor = 1.0
	root.content_scale_size = Vector2i(1600, 900)
	root.size = Vector2i(1600, 900)
	await _frames(10)
	_check(root.mode == Window.MODE_WINDOWED and root.size == Vector2i(1600, 900) and is_equal_approx(float(root.content_scale_factor), 1.0), "test leaves its window at 1600 x 900 and scale 1")
