extends SceneTree
## Screenshot fixture: real simulation and renderer, independent of menus/input.
## DISPLAY=:0 Godot --path . --script res://tests/render_fixture.gd -- --output=/absolute/path.png

const Simulation = preload("res://scripts/campaign_simulation.gd")
const WorldView = preload("res://scripts/world_view.gd")

var simulation: Variant
var viewport: SubViewport
var view: Node2D
var output_path: String = "user://render-fixture.png"


func _initialize() -> void:
	var overview: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		if argument == "--overview":
			overview = true
	simulation = Simulation.new()
	simulation.reset(42)
	simulation.tick(0.1)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	view = WorldView.new()
	view.sim = simulation
	view.world_font = load("res://assets/fonts/NotoSansCJK-Regular.ttc")
	view.selected_ids = [int(simulation.units[0]["id"]), int(simulation.units[1]["id"])]
	viewport.add_child(view)
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(40.0, 20.0) * 48.0 if overview else Vector2(13.0, 22.0) * 48.0
	camera.zoom = Vector2.ONE * (0.39 if overview else 1.15)
	viewport.add_child(camera)
	call_deferred("_capture")


func _capture() -> void:
	await process_frame
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = viewport.get_texture().get_image()
	if frame == null or frame.is_empty():
		printerr("RENDER_FIXTURE_EMPTY: run with a graphics display, not --headless")
		quit(2)
		return
	var result: Error = frame.save_png(output_path)
	print("RENDER_FIXTURE_RESULT ", result, " ", output_path)
	quit(0 if result == OK else 1)
