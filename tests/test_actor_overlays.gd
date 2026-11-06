extends SceneTree
## Native positive pixel checks and an isolated actor redraw/draw-call comparison.
## DISPLAY=:0 ./run.sh --audio-driver Dummy --script res://tests/test_actor_overlays.gd

const World = preload("res://scripts/world_view.gd")
const Atlas = preload("res://scripts/actor_atlas.gd")
const BACKGROUND: Color = Color("d7b37b")
const PIXELS: Vector2i = Vector2i(1280, 720)

class Clock:
	extends RefCounted
	var time: float = 2.0

class Painter:
	extends World
	var units: Array[Dictionary] = []
	var samples: Array[int] = []
	var overlays_only: bool = false
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_setup_actor_atlas()
	func _process(_delta: float) -> void:
		pass
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(PIXELS) / scale), BACKGROUND)
		var started: int = Time.get_ticks_usec()
		for unit: Dictionary in units:
			if overlays_only:
				_draw_actor_overlays(tile_to_world(unit.pos), str(unit.kind), selected_ids.has(int(unit.id)))
			else:
				_draw_unit(unit)
		samples.append(Time.get_ticks_usec() - started)

class OriginalOverlays:
	extends Painter
	func _draw_actor_overlays(p: Vector2, kind: String, selected: bool) -> void:
		# The previous live vector implementation, independent of the new cache.
		_oval(p + Vector2(2.0, 9.0), Vector2(13.0 if kind != "truck" else 29.0, 5.0 if kind != "truck" else 11.0), Color(0.18, 0.22, 0.20, 0.30))
		if selected:
			_dashed_circle(p + Vector2(0.0, 4.0), 17.0 if kind != "truck" else 33.0, Color(CYAN, 0.95), 2.5, 10)
			_oval(p + Vector2(0.0, 4.0), Vector2(15.0, 6.0), Color(CYAN, 0.13))

var checks: int = 0
var failures: Array[String] = []
var view: SubViewport
var painter: Painter
var display: TextureRect
var results: Dictionary = {"pixel_comparison": [], "performance": []}
var output_dir: String = "res://work/actor-overlays"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Actor overlay checks require a native display")
		quit(2)
		return
	root.size = PIXELS
	root.title = "Outpost Exodus — actor overlay pixel checks"
	root.content_scale_size = PIXELS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	display = TextureRect.new()
	display.size = Vector2(PIXELS)
	root.add_child(display)
	for zoom: float in [1.05, 0.35]:
		await _pixel_checks(zoom)
	await _positive_checks()
	var pixels_only: bool = OS.get_cmdline_user_args().has("--pixels-only")
	if not pixels_only:
		for zoom: float in [1.05, 0.35]:
			await _performance(zoom)
	var file: FileAccess = FileAccess.open(output_dir + ("/pixels-only-results.json" if pixels_only else "/results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	print("ACTOR_OVERLAY_RESULTS ", JSON.stringify(results))
	print("Actor overlay checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - ", failure)
	if view != null: view.queue_free()
	display.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _fixture() -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	var friendlies: Array[String] = ["rifle", "engineer", "worker", "truck"]
	var enemies: Array[String] = ["zombie", "runner", "brute"]
	for index: int in range(132):
		var pos: Vector2 = Vector2(60.25 + float(index % 16) * 73.0, 75.375 + float(index / 16) * 68.0) / 48.0
		var kind: String = friendlies[index % friendlies.size()] if index < 32 else enemies[index % enemies.size()]
		units.append({"id": index + 1, "kind": kind, "team": "friendly" if index < 32 else "enemy", "pos": pos, "target": pos + Vector2(-1.5 if index % 2 else 1.5, 0.0), "state": "move", "hp": 72.0 if index % 5 == 0 else 100.0, "max_hp": 100.0, "cargo": {"materials": 5.0} if index % 3 == 0 else {}, "squad": 1 if index < 32 else 0})
	return units

func _create(original: bool, zoom: float) -> void:
	view = SubViewport.new()
	view.size = PIXELS
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	painter = OriginalOverlays.new() if original else Painter.new()
	painter.sim = Clock.new()
	painter.scale = Vector2.ONE * zoom
	painter.units = _fixture()
	for index: int in range(32): painter.selected_ids.append(index + 1)
	view.add_child(painter)
	display.texture = view.get_texture()

func _remove() -> void:
	display.texture = null
	view.queue_free()
	view = null
	painter = null
	await process_frame
	await RenderingServer.frame_post_draw

func _frames(count: int = 4) -> void:
	for index: int in range(count):
		painter.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw

func _image() -> Image:
	return view.get_texture().get_image()

func _pixel_checks(zoom: float) -> void:
	_create(true, zoom)
	await _frames(6)
	var original: Image = _image()
	original.save_png(output_dir + "/vector-overlays-%.2f.png" % zoom)
	await _remove()
	_create(false, zoom)
	await _frames(6)
	var cached: Image = _image()
	cached.save_png(output_dir + "/cached-overlays-%.2f.png" % zoom)
	var metrics: Dictionary = _compare(original, cached)
	metrics.zoom = zoom
	results.pixel_comparison.append(metrics)
	_check(metrics.foreground_pixels > 1000, "zoom %.2f reference has actual actor pixels" % zoom)
	_check(metrics.foreground_mean_channel_error_255 < 5.0, "zoom %.2f cached overlays retain actor pixels within quantified raster resampling bound" % zoom)
	# All body regions stay byte-identical in the atlas; only the four unused idle cells change.
	var atlas_image: Image = painter._actor_viewport.get_texture().get_image()
	for truck: bool in [false, true]:
		for selected: bool in [false, true]:
			var cell: Rect2 = Atlas.overlay_region("truck" if truck else "rifle", selected)
			_check(atlas_image.get_region(Rect2i(cell)).get_used_rect().has_area(), "ground overlay cell truck=%s selected=%s contains visible pixels" % [truck, selected])
	await _remove()

func _positive_checks() -> void:
	for zoom: float in [1.05, 0.35]:
		_create(false, zoom)
		painter.units = [{"id": 1, "kind": "worker", "team": "friendly", "pos": Vector2(4, 4), "target": Vector2(4, 4), "state": "idle", "hp": 100.0, "max_hp": 100.0, "cargo": {}, "squad": 0}]
		painter.selected_ids = []
		await _frames(6)
		var idle: Image = _image()
		var atlas_id: int = painter._actor_viewport.get_instance_id()
		var atlas_hash: int = hash(painter._actor_viewport.get_texture().get_image().get_data())
		var unit: Dictionary = painter.units[0]
		# Isolate ground decorations so a selected actor's new HP bar cannot make
		# the selection-ring check pass when its ring is missing.
		painter.overlays_only = true
		await _frames()
		var unselected_ground: Image = _image()
		painter.selected_ids = [1]
		await _frames()
		var selected_ground: Image = _image()
		_check(_different(unselected_ground, selected_ground) and _cyan_pixels(selected_ground) > 10, "zoom %.2f cyan dashed ring appears on live selection without relying on HP pixels" % zoom)
		painter.selected_ids = []
		await _frames()
		_check(not _different(unselected_ground, _image()), "zoom %.2f deselection immediately removes the ring" % zoom)
		painter.overlays_only = false
		unit.hp = 43.0
		await _frames()
		var injured: Image = _image()
		_check(_different(idle, injured), "zoom %.2f damaged unselected actor keeps its live health bar" % zoom)
		unit.hp = 100.0
		unit.cargo = {"materials": 5.0}
		await _frames()
		var carrying: Image = _image()
		_check(_different(idle, carrying), "zoom %.2f worker cargo appears immediately" % zoom)
		unit.cargo = {}
		unit.target = unit.pos - Vector2(1.0, 0.0)
		await _frames()
		var facing: Image = _image()
		_check(_different(idle, facing), "zoom %.2f facing updates immediately" % zoom)
		unit.target = unit.pos
		unit.pos += Vector2(1.0, 0.0)
		unit.target = unit.pos
		await _frames()
		_check(_different(idle, _image()), "zoom %.2f position updates immediately" % zoom)
		unit.pos -= Vector2(1.0, 0.0)
		unit.target = unit.pos + Vector2(1.0, 0.0)
		unit.state = "move"
		painter.overlays_only = true
		painter.selected_ids = [1]
		await _frames()
		var ground: Image = _image()
		painter.sim.time += 0.2
		await _frames()
		_check(not _different(ground, _image()), "zoom %.2f walking bob leaves shadow and ring fixed on ground" % zoom)
		unit.kind = "truck"
		await _frames()
		_check(_different(ground, _image()) and _cyan_pixels(_image()) > 10, "zoom %.2f truck retains its larger visible cyan ring and shadow" % zoom)
		unit.cargo = {"fuel": 4.0}
		painter.overlays_only = false
		await _frames()
		var loaded_truck: Image = _image()
		unit.cargo = {}
		await _frames()
		_check(_different(loaded_truck, _image()), "zoom %.2f truck cargo remains live" % zoom)
		_check(painter._actor_viewport.get_instance_id() == atlas_id and hash(painter._actor_viewport.get_texture().get_image().get_data()) == atlas_hash, "zoom %.2f visual changes never regenerate or replace actor atlas" % zoom)
		_check(painter._actor_viewport.size == Atlas.ATLAS_SIZE and painter.get_child_count() == 1, "overlay cache uses existing atlas size and one existing viewport")
		await _remove()

func _performance(zoom: float) -> void:
	for original: bool in [true, false]:
		_create(original, zoom)
		await _frames(30)
		painter.samples.clear()
		var calls: Array[float] = []
		for index: int in range(120):
			painter.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var values: Array[int] = painter.samples.duplicate()
		values.sort()
		calls.sort()
		results.performance.append({"zoom": zoom, "original_vector_overlays": original, "actors": painter.units.size(), "selected": painter.selected_ids.size(), "samples": values.size(), "draw_cpu_median_usec": values[values.size() / 2], "draw_calls_median": calls[calls.size() / 2]})
		await _remove()

func _different(a: Image, b: Image) -> bool:
	return a.get_data() != b.get_data()

func _cyan_pixels(pixels: Image) -> int:
	var count: int = 0
	var bounds: Rect2i = Rect2i(Vector2i(Vector2(140, 140) * painter.scale), Vector2i(Vector2(105, 105) * painter.scale))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var color: Color = pixels.get_pixel(x, y)
			if color.g > color.r + 0.05 and color.b > color.r + 0.05: count += 1
	return count

func _compare(a: Image, b: Image) -> Dictionary:
	var foreground: int = 0
	var changed: int = 0
	var absolute_error: float = 0.0
	var max_error: float = 0.0
	for y: int in range(a.get_height()):
		for x: int in range(a.get_width()):
			var before: Color = a.get_pixel(x, y)
			var after: Color = b.get_pixel(x, y)
			if before != BACKGROUND or after != BACKGROUND:
				foreground += 1
			if before != after: changed += 1
			for channel: int in range(3):
				var error: float = absf(before[channel] - after[channel]) * 255.0
				absolute_error += error
				max_error = maxf(max_error, error)
	return {"pixels": a.get_width() * a.get_height(), "foreground_pixels": foreground, "changed_pixels": changed, "foreground_mean_channel_error_255": absolute_error / maxf(1.0, foreground * 3.0), "max_channel_error_255": max_error}

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
