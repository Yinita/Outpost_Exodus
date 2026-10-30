extends SceneTree
## Native pixel equivalence for cached actor shadows, including nested transforms.
## DISPLAY=:0 ./run.sh --audio-driver Dummy --script res://tests/test_cartoon_primitives.gd

class Painter:
	extends "res://scripts/cartoon_canvas.gd"
	var samples: Array[int] = []
	var varied_shapes: bool = false
	func _draw() -> void:
		var started: int = Time.get_ticks_usec()
		for index: int in range(192):
			var center: Vector2 = Vector2(24 + (index % 16) * 38, 20 + (index / 16) * 28) + Vector2(0.125, 0.375)
			var radii: Vector2 = Vector2(13, 5) if index % 3 else Vector2(15, 6)
			_oval(center, radii, Color(0.18, 0.22, 0.20, 0.30))
		# A generator/body can call this primitive inside its own local transform.
		draw_set_transform(Vector2(180.25, 390.75), 0.27, Vector2(-1.0, 0.8))
		_oval(Vector2(1.25, -2.5), Vector2(29, 11), Color(0.3, 0.8, 0.7, 0.55))
		draw_set_transform(Vector2.ZERO)
		if varied_shapes:
			for index: int in range(OVAL_SHAPE_CACHE_LIMIT + 8):
				_oval(Vector2(-1000, -1000), Vector2(index + 100.5, 2), Color.WHITE)
		samples.append(Time.get_ticks_usec() - started)

class Original:
	extends Painter
	func _oval(center: Vector2, radii: Vector2, color: Color) -> void:
		var points: PackedVector2Array = PackedVector2Array()
		for step: int in range(16):
			var angle: float = TAU * float(step) / 16.0
			points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
		draw_colored_polygon(points, color)

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Cartoon primitive checks require a native display")
		quit(2)
		return
	var original: Node2D = Original.new()
	var cached: Node2D = Painter.new()
	var views: Array[SubViewport] = []
	for painter: Node2D in [original, cached]:
		var view: SubViewport = SubViewport.new()
		view.size = Vector2i(640, 432)
		view.disable_3d = true
		view.transparent_bg = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		view.add_child(painter)
		views.append(view)
	for frame: int in range(140):
		original.queue_redraw()
		cached.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
	var expected: Image = views[0].get_texture().get_image()
	_check(expected.get_used_rect().has_area(), "reference contains actual rendered shadow pixels")
	_check(expected.get_data() == views[1].get_texture().get_image().get_data(), "cached shadows retain exact pixels, alpha and caller transforms")
	_check(cached._oval_shapes.size() == 3, "repeated actor shadow sizes reuse three original shapes")
	var before: Array = original.samples.slice(20)
	var after: Array = cached.samples.slice(20)
	before.sort()
	after.sort()
	print("CARTOON_OVAL_DRAW_CPU_USEC baseline_median=", before[before.size() / 2], " cached_median=", after[after.size() / 2], " shapes_per_frame=193 samples=", before.size())
	# Actual offscreen drawing exercises eviction without changing the visible scene.
	cached.varied_shapes = true
	for frame: int in range(3):
		cached.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
	_check(cached._oval_shapes.size() == cached.OVAL_SHAPE_CACHE_LIMIT, "varied radii keep the geometry cache bounded")
	cached.varied_shapes = false
	cached.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	_check(expected.get_data() == views[1].get_texture().get_image().get_data(), "evicted shapes reconstruct the same visible pixels")
	print("Cartoon primitive checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - ", failure)
	for view: SubViewport in views: view.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
