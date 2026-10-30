extends SceneTree
## Rendered HUD integration. Run with an isolated XDG_DATA_HOME under
## res://work/campaign-selection-data; real user saves are never touched.

const Catalog = preload("res://scripts/campaign_catalog.gd")
const Simulation = preload("res://scripts/campaign_simulation.gd")
var app: Variant
var failures: Array[String] = []
var checks: int = 0
var manual_path: String
var automatic_path: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/campaign-selection-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolated + "/") or DisplayServer.get_name() == "headless":
		printerr("Campaign selection test requires real rendering and isolated XDG_DATA_HOME: ", OS.get_user_data_dir())
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	var script: Script = load("res://scripts/main.gd")
	var constants: Dictionary = script.get_script_constant_map()
	manual_path = constants["SAVE_PATH"]
	automatic_path = constants["AUTOSAVE_PATH"]
	for path: String in [manual_path, manual_path + ".bak", automatic_path, automatic_path + ".bak", String(constants["CONFIG_PATH"])]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	AudioServer.set_bus_mute(0, true)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.ui_scale = 1.2
	app._apply_display_settings()
	await _frames(4)
	_check(app.selected_mission_id == "canyon", "fresh selection defaults to Canyon")
	_check(_has("campaigns"), "title exposes campaign selection")
	await _test_compact_menus()
	await _click("campaigns")
	_check(_fits(), "three campaign cards fit 1280x720 at120 percent UI scale")
	for id: String in Catalog.ids(): _check(_has("campaign:" + id), "real HUD offers campaign " + id)
	_check(app.hud._campaign_previews.size() == 3, "all three cards render their actual terrain previews")
	await _capture("campaign-selection.png")
	await _click("campaign:canyon")
	app.sim.paused = true
	_check_mission("canyon")
	_check(bool(app.save_campaign()), "first manual Canyon save succeeds")
	app.sim.paused = false
	app.sim.tick(0.5)
	app.sim.paused = true
	_check(bool(app.save_campaign()), "second manual Canyon save creates real older backup")
	_check(bool(app.save_campaign(false)), "old automatic slot exists before switching")
	var manual: PackedByteArray = _bytes(manual_path)
	var backup: PackedByteArray = _bytes(manual_path + ".bak")
	var automatic: PackedByteArray = _bytes(automatic_path)
	await _click("menu")
	await _click("campaigns")
	var before: String = _state(app.sim)
	await _click("campaign:delta")
	_check(app.menu == "restart" and app.pending_mission_id == "delta", "playing selection enters existing restart confirmation with pending ID")
	_check(app.selected_mission_id == "canyon" and _state(app.sim) == before, "pending selection leaves selected mission and complete simulation unchanged")
	_check(_bytes(automatic_path) == automatic and _bytes(manual_path) == manual and _bytes(manual_path + ".bak") == backup, "pending selection does not write any save slot")
	_check(_fits(), "switch confirmation fits the scaled viewport")
	await _capture("campaign-switch-confirm.png")
	await _click("resume")
	_check(app.menu.is_empty() and app.pending_mission_id.is_empty(), "cancel clears pending selection and resumes current mission")
	_check(app.selected_mission_id == "canyon" and _state(app.sim) == before, "cancel preserves complete current mission")
	_check(_bytes(automatic_path) == automatic and _bytes(manual_path) == manual and _bytes(manual_path + ".bak") == backup, "cancel preserves AUTO, manual and backup bytes")
	await _click("menu")
	await _click("campaigns")
	await _click("campaign:delta")
	await _click("restart_confirm")
	app.sim.paused = true
	_check_mission("delta")
	_check(_bytes(manual_path) == manual and _bytes(manual_path + ".bak") == backup, "confirmed switch preserves manual and backup byte-for-byte")
	var old: Variant = Simulation.new()
	_check(old.load_state(app.save_store.read(automatic_path).data), "confirmed switch creates valid automatic recovery save")
	_check(String(old.mission_id) == "canyon" and _state(old) == before, "AUTO contains complete old Canyon progress before Delta reset")
	_check(not app._save_payload().ui.has("mission_id"), "UI save metadata does not duplicate derived mission ID")
	_check(app.hud._mission_site_name("quarry") == "南岸沉船废料场" and app.hud._mission_site_name("fuel") == "北岸泵站油库", "Delta resource UI uses actual metadata geography")
	await _click("guide_more")
	_check(_fits(), "full guide dialog fits the scaled viewport")
	await _click("guide_branch:north")
	_check(app.guide.save_state().preferred_branch == "north", "materials button retains legacy north preference even for southern Delta salvage")
	await _click("guide_branch:south")
	_check(app.guide.save_state().preferred_branch == "south", "fuel button retains legacy south preference even for northern Delta oil")
	await _capture("delta-guide.png")
	await _click("resume")
	_check(bool(app.save_campaign()), "Delta manual save succeeds")
	await _click("menu")
	await _click("campaigns")
	await _click("campaign:ridge")
	await _click("restart_confirm")
	app.sim.paused = true
	_check_mission("ridge")
	await _click("menu")
	await _click("new")
	_check(app.pending_mission_id == "ridge", "existing restart action targets current playing mission")
	await _click("resume")
	await _click("menu")
	await _click("load")
	app.sim.paused = true
	_check_mission("delta", false)
	_check(app.selected_mission_id == "delta", "successful load restores selected mission from simulation metadata")
	await _test_failed_auto_switch()
	var safe: String = _state(app.sim)
	var selected: String = app.selected_mission_id
	var old_auto: PackedByteArray = _bytes(automatic_path)
	app.ui_action("campaign:unknown")
	app.start_campaign("unknown")
	_check(_state(app.sim) == safe and app.selected_mission_id == selected and _bytes(automatic_path) == old_auto, "unknown campaign IDs leave simulation, selection and save files unchanged")
	await _click("menu")
	await _click("load_backup")
	app.sim.paused = true
	_check_mission("canyon", false)
	_check(app.selected_mission_id == "canyon", "legacy Canyon backup loads without new UI mission fields")
	await _click("menu")
	await _click("title")
	await _click("new")
	app.sim.paused = true
	_check_mission("canyon")
	app.queue_free()
	await _frames(4)
	root.content_scale_factor = 1.0
	print("Campaign selection checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - ", failure)
	quit(0 if failures.is_empty() else 1)


func _test_compact_menus() -> void:
	await _capture("campaign-title.png")
	await _click("settings")
	_check(app.settings_binding_page_size() == 6, "short-screen controls use six bindings per page without reducing UI scale")
	var seen: Dictionary = {}
	var pages: int = ceili(float(app.command_names.size()) / 6.0)
	for page: int in range(pages):
		_check(app.settings_page == page and _fits(), "short-screen binding page %d fits with reachable navigation" % page)
		for hotspot: Dictionary in app.hud.hotspots:
			var action: String = String(hotspot.action)
			if action.begins_with("bind:"): seen[action.trim_prefix("bind:")] = true
		if page == 0: await _capture("campaign-settings-controls.png")
		if page + 1 < pages: await _click("bindings_next")
	_check(seen.size() == app.command_names.size(), "compact pagination exposes every existing command")
	app.ui_action("bindings_next")
	_check(app.settings_page == pages - 1, "controller next-page boundary matches compact HUD pagination")
	await _click("settings_tab:display")
	_check(_fits() and is_equal_approx(float(app.ui_scale), 1.2), "display settings fit while retaining real120 percent scale")
	await _capture("campaign-settings-display.png")
	await _click("back")
	await _click("help")
	_check(_fits(), "metadata help dialog fits the short scaled viewport")
	await _capture("campaign-help.png")
	await _click("back")
	for end_menu: String in ["victory", "defeat"]:
		app.menu = end_menu
		await _frames()
		_check(_has("campaigns") and _fits(), end_menu + " menu exposes reachable campaign selection")
		await _click("campaigns")
		await _click("campaign_back")
		_check(app.menu == end_menu, "campaign back returns to " + end_menu + " menu")
	app.menu = "title"
	await _frames()


func _test_failed_auto_switch() -> void:
	await _click("menu")
	await _click("campaigns")
	await _click("campaign:ridge")
	var before: String = _state(app.sim)
	var selected: String = app.selected_mission_id
	var automatic: PackedByteArray = _bytes(automatic_path)
	var manual: PackedByteArray = _bytes(manual_path)
	var backup: PackedByteArray = _bytes(manual_path + ".bak")
	var absolute: String = ProjectSettings.globalize_path(automatic_path)
	DirAccess.remove_absolute(absolute)
	DirAccess.make_dir_absolute(absolute)
	await _click("restart_confirm")
	_check(app.menu == "restart" and app.pending_mission_id == "ridge" and app.selected_mission_id == selected and _state(app.sim) == before, "failed real AUTO write leaves old mission and pending confirmation intact")
	_check(_bytes(manual_path) == manual and _bytes(manual_path + ".bak") == backup, "failed AUTO write preserves manual and backup")
	DirAccess.remove_absolute(absolute)
	var file: FileAccess = FileAccess.open(automatic_path, FileAccess.WRITE)
	file.store_buffer(automatic)
	file.close()
	await _click("resume")


func _check_mission(id: String, check_camera: bool = true) -> void:
	_check(String(app.sim.mission_id) == id and app.selected_mission_id == id, "HUD starts/restores real " + id + " mission")
	var definition: Dictionary = Catalog.mission(id)
	_check(String(app.sim.mission_name) == String(definition.name) and Vector2(app.sim.camps[0].pos) == Vector2(definition.camps[0].pos), id + " uses actual mission name and home geometry")
	if check_camera:
		_check(Vector2(app.camera.position).distance_to((Vector2(definition.camps[0].pos) + Vector2(7, 0)) * 48.0) < 0.01, id + " camera derives from home camp")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _frames(count: int = 2) -> void:
	for index: int in range(count):
		if is_instance_valid(app): app.hud.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw


func _has(action: String) -> bool:
	for hotspot: Dictionary in app.hud.hotspots:
		if String(hotspot.action) == action: return true
	return false


func _click(action: String) -> void:
	await _frames()
	for hotspot: Dictionary in app.hud.hotspots:
		if String(hotspot.action) != action: continue
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = Rect2(hotspot.rect).get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		_check(app.hud.handle_mouse(event), "actual HUD consumes " + action)
		await _frames()
		return
	_check(false, "actual visible HUD action exists: " + action)


func _fits() -> bool:
	var bounds: Rect2 = app.hud.get_viewport_rect()
	for hotspot: Dictionary in app.hud.hotspots:
		if not bounds.encloses(hotspot.rect): return false
	return true


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


func _state(simulation: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(simulation.save_state(), "", true, true)), "", true, true)


func _capture(name: String) -> void:
	await _frames()
	root.get_texture().get_image().save_png("res://work/" + name)
