extends SceneTree
## Actual simulation/controller checks. --require-rendered adds GPU pose checks.
const Simulation = preload("res://scripts/campaign_simulation.gd")
const Motion = preload("res://scripts/render_motion.gd")
const Main = preload("res://scripts/main.gd")
var checks: int = 0
var failures: Array[String] = []
var app: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://work/render-motion-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolated + "/"):
		printerr("Motion checks require isolated work/render-motion-data")
		quit(2)
		return
	if OS.get_cmdline_user_args().has("--require-rendered") and DisplayServer.get_name() == "headless":
		quit(2)
		return
	AudioServer.set_bus_mute(0, true)
	_test_actual_steps()
	_test_discontinuities()
	app = Main.new()
	root.add_child(app)
	app.set_process(false)
	app.start_campaign()
	var hero: Dictionary = app.sim.units[0]
	app.sim.command_move([int(hero.id)], Vector2(hero.pos) + Vector2(5, 0))
	var before: Vector2 = hero.pos
	app._process(0.075)
	var after: Vector2 = hero.pos
	var visual: Vector2 = app.world.render_unit_position(hero)
	_check(before.distance_to(after) > 0.001, "real public move command advances a unit")
	_check(visual.is_equal_approx(before.lerp(after, 0.5)), "actual controller renders the half-step pose")
	_check(is_equal_approx(app.sim.time, 0.05), "display fraction does not advance simulation time")
	var state: String = _state(app.sim)
	# Put a real drag-box edge between the visible and authoritative positions.
	# Before integration the same box misses this unit, despite enclosing its art.
	var p: Vector2 = visual * 48.0
	var current: Vector2 = after * 48.0
	var lower: Vector2 = p - Vector2(15, 15)
	var upper: Vector2 = p + Vector2(15, 15)
	if absf(current.x - p.x) >= absf(current.y - p.y):
		if current.x > p.x: upper.x = (current.x + p.x) * 0.5
		else: lower.x = (current.x + p.x) * 0.5
	else:
		if current.y > p.y: upper.y = (current.y + p.y) * 0.5
		else: lower.y = (current.y + p.y) * 0.5
	_check(Rect2(lower, upper - lower).has_point(p) and not Rect2(lower, upper - lower).has_point(current), "drag fixture distinguishes visible and simulation positions")
	app.drag_start = lower
	app._select(upper, false, false)
	_check(app.selected_ids.has(int(hero.id)), "actual drag selection hits the displayed unit position")
	_check(_state(app.sim) == state, "selection and display sampling leave full simulation and RNG unchanged")
	if DisplayServer.get_name() != "headless": await _test_pixels(hero, before, after)
	app.sim.paused = true
	app._process(0.0)
	_check(app.world.render_unit_position(hero) == Vector2(hero.pos), "tactical pause uses exact current unit position")
	_check(app.world.motion.previous_positions.is_empty(), "pause retires previous moving poses")
	app.sim.paused = false
	app._process(0.001)
	_check(app.world.render_unit_position(hero) == Vector2(hero.pos), "resume cannot rewind into a pre-pause pose")
	app._process(0.05)
	_check(app.save_campaign(), "real manual save accepts current authoritative motion state")
	var saved: String = _state(app.sim)
	app._process(0.05)
	_check(app.load_campaign(), "real manual save reloads through controller")
	_check(_state(app.sim) == saved, "load restores only authoritative simulation, without display samples")
	_check(app.world.motion.previous_positions.is_empty(), "loading a save clears even reused unit IDs")
	app.start_campaign("delta")
	_check(app.world.motion.previous_positions.is_empty() and app.world.render_unit_position(app.sim.units[0]) == Vector2(app.sim.units[0].pos), "campaign replacement cannot blend same-ID actors across maps")
	app.speed = 3.0
	app._process(0.034)
	_check(is_equal_approx(app.sim.time, 0.1) and is_equal_approx(app.world.motion.fraction, 0.04), "3x speed captures the final step and uses the true remainder")
	app.menu = "pause"
	app._process(0.0)
	_check(app.world.motion.previous_positions.is_empty(), "pause menu retires motion independently of tactical pause")
	app._release_audio()
	var deadline: int = Time.get_ticks_usec() + 120000
	while Time.get_ticks_usec() < deadline: await process_frame
	app.queue_free()
	await process_frame
	print("Render motion checks: %d; failures: %d; display=%s" % [checks, failures.size(), DisplayServer.get_name()])
	for failure: String in failures: printerr(" - ", failure)
	quit(0 if failures.is_empty() else 1)


func _test_actual_steps() -> void:
	var sim: RefCounted = Simulation.new()
	var twin: RefCounted = Simulation.new()
	sim.reset(42)
	twin.reset(42)
	var ids: Array = [int(sim.units[0].id)]
	sim.command_move(ids, Vector2(sim.units[0].pos) + Vector2(6, 0))
	twin.command_move(ids, Vector2(twin.units[0].pos) + Vector2(6, 0))
	var motion: RefCounted = Motion.new()
	motion.reset(sim)
	var identical: bool = true
	var bounded: bool = true
	var moving_steps: int = 0
	for step: int in range(120):
		var previous: Vector2 = sim.units[0].pos
		motion.before_step(sim)
		sim.tick(0.05)
		twin.tick(0.05)
		motion.after_step(sim)
		var current: Vector2 = sim.units[0].pos
		if previous.distance_to(current) > 0.001: moving_steps += 1
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			motion.prepare_frame(sim, fraction * 0.05, true)
			bounded = bounded and motion.position(sim.units[0]).is_equal_approx(previous.lerp(current, fraction))
		identical = identical and _state(sim) == _state(twin)
	_check(moving_steps >= 20, "paired workload includes sustained real movement")
	_check(bounded, "120 real steps produce all five bounded sub-step poses")
	_check(identical, "full encoded state and RNG match unobserved twin after every real step")
	motion.prepare_frame(sim, -1.0, true)
	_check(motion.fraction == 0.0, "negative render remainder is bounded")
	motion.prepare_frame(sim, 2.0, true)
	_check(motion.fraction == 1.0, "late render frames never extrapolate")
	motion.prepare_frame(sim, 0.025, true)
	_check(is_equal_approx(motion.time(sim), sim.time - 0.025), "gait clock advances between actual fixed steps")


func _test_discontinuities() -> void:
	var sim: RefCounted = Simulation.new()
	sim.reset(42)
	var motion: RefCounted = Motion.new()
	var unit: Dictionary = sim.units[0]
	motion.before_step(sim)
	sim.tick(0.05)
	motion.after_step(sim)
	motion.prepare_frame(sim, 0.025, true)
	var newborn: Dictionary = {"id": -999, "pos": Vector2(3, 4)}
	_check(motion.position(newborn) == Vector2(3, 4), "newly spawned IDs have no inherited trajectory")
	unit.pos = Vector2(unit.pos) + Vector2(5, 0)
	_check(motion.position(unit) == Vector2(unit.pos), "large corrections snap instead of crossing terrain")
	sim.tick(0.05)
	motion.prepare_frame(sim, 0.025, true)
	_check(motion.previous_positions.is_empty(), "unobserved simulation step invalidates stale interpolation")
	motion.before_step(sim)
	sim.paused = true
	sim.tick(0.05)
	motion.after_step(sim)
	_check(motion.previous_positions.is_empty(), "a no-op paused tick is not a movement frame")
	sim.reset(42, "ridge")
	motion.prepare_frame(sim, 0.025, true)
	_check(motion.position(sim.units[0]) == Vector2(sim.units[0].pos), "different mission resets display coordinates")
	var other: RefCounted = Simulation.new()
	other.reset(42, "ridge")
	motion.prepare_frame(other, 0.025, true)
	_check(motion.previous_positions.is_empty(), "different simulation object invalidates samples even at equal time")


func _test_pixels(hero: Dictionary, previous: Vector2, current: Vector2) -> void:
	app.camera.position = current * 48.0
	app.camera.zoom = Vector2.ONE * 1.6
	app.world.guide_target = Vector2(-1, -1)
	app.world.selected_ids = [int(hero.id)]
	var state: String = _state(app.sim)
	var hashes: Array[int] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/render-motion"))
	for fraction: float in [0.0, 0.5, 1.0]:
		app.world.motion.prepare_frame(app.sim, fraction * 0.05, true)
		app.world.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var frame: Image = root.get_texture().get_image()
		var screen: Vector2 = app.world.get_global_transform_with_canvas() * (previous * 48.0)
		var crop: Rect2i = Rect2i(Vector2i(screen) - Vector2i(75, 90), Vector2i(150, 150)).intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
		_check(crop.size.x >= 100 and crop.size.y >= 100, "unit pixel sample remains on screen")
		hashes.append(hash(frame.get_region(crop).get_data()))
		frame.save_png("res://work/render-motion/pose-%d.png" % roundi(fraction * 100.0))
	_check(hashes[0] != hashes[1] and hashes[1] != hashes[2] and hashes[0] != hashes[2], "actual GPU body, shadow, selection and HP render distinct intermediate poses")
	_check(_state(app.sim) == state, "native rendering across fractions leaves simulation and RNG unchanged")


func _state(sim: RefCounted) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(sim.save_state())))


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
