extends SceneTree
## Real GPU render checks. Fixtures change visual state, never claim mission wins.
## DISPLAY=:0 ./run.sh --script res://tests/test_render_cache.gd

const Simulation = preload("res://scripts/campaign_simulation.gd")
const World = preload("res://scripts/world_view.gd")
const Atlas = preload("res://scripts/actor_atlas.gd")
var checks: int = 0
var failures: Array[String] = []
var simulation: Variant
var view: SubViewport
var world: Node2D
var camera: Camera2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Render cache checks require DISPLAY")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/render-cache-tests"))
	root.size = Vector2i(1280, 720)
	simulation = Simulation.new()
	simulation.reset(42)
	simulation.paused = true
	view = SubViewport.new()
	view.size = Vector2i(1280, 720)
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	world = World.new()
	world.sim = simulation
	world.world_font = load("res://assets/fonts/NotoSansCJK-Regular.ttc")
	view.add_child(world)
	camera = Camera2D.new()
	camera.position = Vector2(16, 22) * 48.0
	camera.zoom = Vector2.ONE
	view.add_child(camera)
	var display: TextureRect = TextureRect.new()
	display.texture = view.get_texture()
	display.size = Vector2(1280, 720)
	root.add_child(display)
	await _frames(8)
	var state: String = JSON.stringify(simulation.save_state())
	var cached: Image = _image()
	_check(not cached.is_empty() and cached.get_size() == view.size, "cached world renders actual native pixels")
	_check(JSON.stringify(simulation.save_state()) == state, "terrain and actor caches do not mutate authoritative state")
	_check(world._actor_viewport.get_texture().get_image().get_size() == Atlas.ATLAS_SIZE, "actor texture is available at its declared dimensions")
	cached.save_png("res://work/render-cache-tests/cached-canyon.png")
	world.cache_decorations = false
	world.cache_terrain = false
	world.cache_actors = false
	await _frames()
	var vector: Image = _image()
	_check(not vector.is_empty(), "vector fallback still renders when caches are disabled")
	_check(JSON.stringify(simulation.save_state()) == state, "vector fallback also remains read-only")
	vector.save_png("res://work/render-cache-tests/vector-canyon.png")
	world.cache_decorations = true
	world.cache_terrain = true
	world.cache_actors = true
	await _frames()
	_check(hash(_image().get_data()) == hash(cached.get_data()), "re-enabling cached drawing restores the same paused visual state")
	var worker: Dictionary = {}
	for unit: Dictionary in simulation.units:
		if unit.kind == "worker": worker = unit; break
	var before_cargo: int = hash(_image().get_data())
	worker.cargo = {"materials": 5.0}
	await _frames()
	_check(hash(_image().get_data()) != before_cargo, "worker cargo changes appear without regenerating the atlas")
	worker.cargo = {}
	await _frames()
	_check(hash(_image().get_data()) == before_cargo, "empty-handed worker pose restores immediately")
	world.selected_ids = [int(worker.id)]
	await _frames()
	_check(hash(_image().get_data()) != before_cargo, "selection remains a live overlay rather than baked into cached bodies")
	world.selected_ids = []
	var road_tile: Vector2i = Vector2i(16, 24)
	var pixel: Vector2i = Vector2i(world.get_global_transform_with_canvas() * ((Vector2(road_tile) + Vector2.ONE * 0.5) * 48.0))
	# Sample inside the incoming road segment, away from its unfilled butt cap.
	pixel.y -= 8
	var old_road_pixel: Color = _image().get_pixelv(pixel)
	_check(simulation.build("road", road_tile), "real paid road order is accepted for live-overlay check")
	simulation.paused = false
	for index: int in range(300): simulation.tick(0.1)
	simulation.paused = true
	await _frames()
	_check(simulation.roads.has(road_tile) and float(simulation.roads[road_tile].get("progress", 0.0)) >= 1.0, "workers complete the road using actual simulation construction")
	_image().save_png("res://work/render-cache-tests/completed-road.png")
	_check(_image().get_pixelv(pixel) != old_road_pixel, "completed road draws over cached ground without waiting for a terrain reset")
	var prior_terrain: int = hash(world._terrain_viewport.get_texture().get_image().get_data())
	for id: String in ["delta", "ridge", "canyon"]:
		_check(simulation.reset(42, id), "actual mission reset accepts " + id)
		simulation.paused = true
		camera.position = (Vector2(simulation.camps[0].pos) + Vector2(7, 0)) * 48.0
		await _frames(5)
		var next_terrain: int = hash(world._terrain_viewport.get_texture().get_image().get_data())
		_check(next_terrain != prior_terrain, "terrain cache refreshes when mission geometry changes to " + id)
		if id == "delta":
			var water_pixel: Vector2i = Vector2i(Vector2(40.5,19.5)*48.0) + Vector2i(80,80)
			var water_color: Color = world._terrain_viewport.get_texture().get_image().get_pixelv(water_pixel)
			_check(water_color.b > water_color.r + 0.05, "Delta renders its actual impassable river as water")
		if id == "ridge":
			var ridge_pixel: Vector2i = Vector2i(Vector2(36.5,8.5)*48.0) + Vector2i(80,80)
			var ridge_color: Color = world._terrain_viewport.get_texture().get_image().get_pixelv(ridge_pixel)
			_check(ridge_color.g > ridge_color.r, "Ridge renders a distinct rocky plateau palette")
		prior_terrain = next_terrain
		var previous_image: int = hash(_image().get_data())
		camera.position += Vector2(12, 0) * 48.0
		camera.zoom = Vector2.ONE * 0.7
		await _frames()
		_check(hash(_image().get_data()) != previous_image, "camera pan and zoom remain live for " + id)
		_image().save_png("res://work/render-cache-tests/" + id + ".png")
	print("Rendered cache checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - ", failure)
	display.queue_free()
	view.queue_free()
	await _frames(6)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _frames(count: int = 4) -> void:
	for index: int in range(count):
		if is_instance_valid(world): world.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw

func _image() -> Image:
	return view.get_texture().get_image()
