extends SceneTree
## Controller + real HUD pixels/hotspots in isolated data. Synthetic hover and
## controller placement exercise the same path as clicks, not human usability.
var app: Variant
var checks: int = 0
var failures: Array[String] = []
var saved_mouse: Vector2i

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://work/construction-ui-data/")):
		printerr("Construction UI checks require native DISPLAY and isolated construction-ui-data")
		quit(2)
		return
	saved_mouse = DisplayServer.mouse_get_position()
	AudioServer.set_bus_mute(0, true)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await _frames(6)
	app.set_process(false)
	app.start_campaign("canyon")
	app.sim.paused = true
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	root.content_scale_factor = 1.0
	await _frames(3)
	var tile: Vector2i = Vector2i(16, 23)
	_check(app.sim.query_build("workshop", tile).ok, "real opening map offers the test workshop site")
	app.sim.camps[0].materials = 0.0
	app.ui_action("build:workshop")
	await _hover(tile)
	_check(app.build_preview.code == "resources" and float(app.build_preview.missing.materials) == 40.0, "hover reports exact local workshop deficit")
	_check(app.world.build_preview == app.build_preview and not app.world.build_preview.ok, "world marker receives the actual rejected plan")
	var before: String = JSON.stringify(app.sim.save_state())
	var cached: Dictionary = app.build_preview
	for frame: int in range(12): app._process(0.0)
	_check(is_same(cached, app.build_preview), "stationary paused hover reuses the plan instead of routing every frame")
	_check(JSON.stringify(app.sim.save_state()) == before, "preview and HUD do not create messages, charges or jobs")
	await _capture("construction-deficit.png")
	# The displayed rejection is deliberately stale: commit must read new funds.
	app.sim.camps[0].materials = 100.0
	var placed: Dictionary = app._place_build(tile)
	_check(placed.ok and app.build_kind.is_empty(), "fresh click accepts newly available funds and exits building placement")
	_check(float(app.sim.camps[0].materials) == 60.0, "real click charges the exact workshop price once")
	_check(app.feedback == placed.message and app.feedback.contains("工坊"), "successful click immediately displays its own precise message")
	app.ui_action("build:road")
	await _hover(Vector2i(16, 24))
	_check(app.build_preview.ok and not app.build_preview.road_tiles.is_empty(), "road hover exposes the actual complete segment")
	_check(float(app.build_preview.costs.materials) == app.build_preview.road_tiles.size() * 2.0, "visible segment total matches real per-tile pricing")
	app.sim.camps[0].materials = 0.0
	var roads: Dictionary = app.sim.roads.duplicate(true)
	var rejected: Dictionary = app._place_build(Vector2i(16, 24))
	_check(not rejected.ok and app.build_kind == "road" and app.sim.roads == roads, "fresh click rejects spent funds without laying a partial road or leaving placement mode")
	_check(app.feedback == rejected.message and app.feedback.contains("建材"), "failed click retains its precise resource reason")
	app.sim.camps[0].materials = 100.0
	await _hover(Vector2i(17, 24))
	var ordered: Dictionary = app._place_build(Vector2i(17, 24))
	_check(ordered.ok and app.build_kind == "road", "successful road order keeps continuous road placement active")
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1152, 648)]:
		root.size = resolution
		root.content_scale_size = resolution
		root.content_scale_factor = 1.2
		await _frames(3)
		app.ui_action("build:generator")
		await _hover(Vector2i(15, 26))
		_check(_placement_fits(), "construction panel and cancel fit at120percent in " + str(resolution))
		await _capture("construction-%d.png" % resolution.x)
		await _click("cancel_build")
		_check(app.build_kind.is_empty(), "actual cancel hotspot exits placement")
		var has_workshop: bool = false
		for building: Dictionary in app.sim.buildings:
			if building.kind == "workshop": has_workshop = true
		if not has_workshop: _check(app.sim.build("workshop", tile), "new compact fixture accepts real workshop order")
		app.sim.paused = false
		app.ui_action("tab:production")
		app._process(0.0)
		await _frames()
		_check(_production_fits(), "all seven production/priority controls stay left of minimap in " + str(resolution))
		_check(app.production_readout.code == "running" and app.production_readout.working == 1, "existing powered workshop keeps operating while the second is unfinished")
		await _click("recipe:idle")
		_check(app.production_readout.code == "idle", "recipe click immediately refreshes production status")
		await _capture("production-%d.png" % resolution.x)
		# Direct restart can have the same time and camp ID, so it must invalidate.
		app.start_campaign("canyon")
		app.sim.paused = false
		app._process(0.0)
		await _frames()
		_check(app.production_readout.code == "running", "same-time direct restart cannot retain prior paused-recipe readout")
		app.sim.paused = true
	app.ui_action("build:generator")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_P
	key.physical_keycode = KEY_P
	key.pressed = true
	app._unhandled_input(key)
	_check(app.current_tab == "production" and app.build_kind.is_empty(), "production shortcut cancels placement consistently with the tab hotspot")
	print("Construction UI checks: %d; failures: %d" % [checks, failures.size()])
	for message: String in failures: printerr(" - ", message)
	app._release_audio()
	app.queue_free()
	app = null
	root.content_scale_factor = 1.0
	for frame: int in range(8): await process_frame
	DisplayServer.warp_mouse(saved_mouse)
	quit(0 if failures.is_empty() else 1)

func _frames(count: int = 2) -> void:
	for frame: int in range(count):
		if is_instance_valid(app):
			app.hud.queue_redraw()
			app.world.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw

func _hover(tile: Vector2i) -> void:
	app.camera.force_update_scroll()
	await _frames()
	root.warp_mouse(app.world.get_global_transform_with_canvas() * ((Vector2(tile) + Vector2(0.2, 0.2)) * 48.0))
	await _frames()
	app._process(0.0)
	await _frames()
	_check(app.world.hover_tile == tile, "synthetic native hover targets " + str(tile))

func _click(action: String) -> void:
	for hotspot: Dictionary in app.hud.hotspots:
		if hotspot.action == action:
			var event: InputEventMouseButton = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			event.position = hotspot.rect.get_center()
			app.hud.handle_mouse(event)
			app._process(0.0)
			await _frames()
			return
	_check(false, "missing real HUD hotspot " + action)

func _placement_fits() -> bool:
	var screen: Rect2 = root.get_visible_rect()
	for rect: Rect2 in app.hud.overlay_rects:
		if not screen.encloses(rect) or rect.end.y >= screen.size.y - 190.0: return false
	return not app.hud.overlay_rects.is_empty()

func _production_fits() -> bool:
	var count: int = 0
	for hotspot: Dictionary in app.hud.hotspots:
		if String(hotspot.action).begins_with("recipe:") or String(hotspot.action).begins_with("priority:"):
			count += 1
			if not root.get_visible_rect().encloses(hotspot.rect) or hotspot.rect.end.x >= app.hud.map_rect.position.x: return false
	return count == 7

func _capture(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/construction-ui"))
	root.warp_mouse(Vector2(root.get_visible_rect().size.x * 0.5, 70))
	await _frames()
	root.get_texture().get_image().save_png("res://work/construction-ui/" + name)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
