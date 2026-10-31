extends SceneTree
## Actual terminal simulation steps through Main; controlled fixtures, not a
## native full campaign or a human playtest. --baseline selects visible cases.
const Simulation = preload("res://scripts/campaign_simulation.gd")
const Main = preload("res://scripts/main.gd")
const FIXTURE: String = "res://tests/fixtures/native-exit-funded.json"

class CountingGuide:
	extends "res://scripts/campaign_guide.gd"
	var update_calls: int = 0
	func update(sim: Variant, selected: Array = [], camp: int = 0) -> void:
		update_calls += 1
		super.update(sim, selected, camp)

var app: Node2D
var checks: int = 0
var failures: Array[String] = []
var preterminal: Dictionary = {}
var expected: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolation: String = ProjectSettings.globalize_path("res://work/terminal-guide-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolation + "/"):
		printerr("Terminal guide checks require isolated work/terminal-guide-data")
		quit(2)
		return
	if OS.get_cmdline_user_args().has("--require-rendered") and DisplayServer.get_name() == "headless":
		quit(2)
		return
	var baseline: bool = OS.get_cmdline_user_args().has("--baseline")
	var sim_hash_before: String = FileAccess.get_sha256("res://scripts/campaign_simulation.gd")
	var main_hash_before: String = FileAccess.get_sha256("res://scripts/main.gd")
	_prepare_terminal("victory")
	_prepare_terminal("defeat")
	if preterminal.size() != 2:
		_finish_without_app()
		return
	app = Main.new()
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	AudioServer.set_bus_mute(0, true)
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1440, 810)
		root.content_scale_size = root.size
		root.content_scale_factor = 1.0
		root.grab_focus()
		await process_frame
		await RenderingServer.frame_post_draw
	for outcome: String in ["victory", "defeat"]:
		for visibility: String in (["visible"] if baseline else ["visible", "dismissed", "disabled"]):
			await _test_terminal(outcome, visibility)
	app._release_audio()
	var deadline: int = Time.get_ticks_usec() + 120000
	while Time.get_ticks_usec() < deadline: await process_frame
	app.queue_free()
	await process_frame
	print("TERMINAL_GUIDE_SOURCE simulation_before=%s simulation_after=%s main_before=%s main_after=%s" % [sim_hash_before, FileAccess.get_sha256("res://scripts/campaign_simulation.gd"), main_hash_before, FileAccess.get_sha256("res://scripts/main.gd")])
	_finish_without_app()


func _prepare_terminal(outcome: String) -> void:
	var sim: RefCounted = Simulation.new()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	_check(sim.load_state(saved), outcome + " source fixture is an actual valid saved native campaign")
	if sim.outcome != "playing":
		_check(false, outcome + " fixture begins before terminal state")
		return
	var ids: Array = []
	if outcome == "victory":
		for unit: Dictionary in sim.units:
			if unit.team == "friendly" and float(unit.hp) > 0.0: ids.append(int(unit.id))
		sim.command_move(ids, Vector2(72, 19), true)
	else:
		# A real player move deliberately sends the command truck into the actual
		# rear horde. The original HP, enemies, fuel and outcome rules remain.
		sim.command_move([int(sim.main_truck_id)], Vector2(14, 20), false)
	for index: int in range(2000):
		var before: Dictionary = sim.save_state()
		sim.tick(0.05)
		if sim.outcome != "playing":
			_check(sim.outcome == outcome, "public-order fixture reaches actual " + outcome)
			if sim.outcome == outcome:
				preterminal[outcome] = before
				expected[outcome] = sim.save_state()
				print("TERMINAL_FIXTURE outcome=%s time=%0.3f last_step=0.05" % [outcome, sim.time])
			return
	_check(false, "public-order fixture did not reach " + outcome + " within100 simulation seconds")


func _test_terminal(outcome: String, visibility: String) -> void:
	_check(app.sim.load_state(preterminal[outcome]), outcome + " preterminal state loads")
	app.world.motion.reset(app.sim)
	app.started = true
	app.menu = ""
	app.speed = 1.0
	app.accumulator = 0.0
	app.autosave_time = 0.0
	app.guide_clock = 0.0
	app.selected_ids.clear()
	for unit: Dictionary in app.sim.units:
		if unit.team == "friendly" and float(unit.hp) > 0.0: app.selected_ids.append(int(unit.id))
	app.selected_camp = int(app.sim.camps.back().id)
	var guide: CountingGuide = CountingGuide.new()
	guide.reset(visibility != "disabled")
	guide.update(app.sim, app.selected_ids, app.selected_camp)
	if visibility == "dismissed": guide.dismiss()
	app.guide = guide
	var prior_hint: Dictionary = guide.get_hint()
	var calls: int = guide.update_calls
	_check(not prior_hint.complete and prior_hint.title != "本次突围结束", outcome + " starts with nonterminal guidance")
	app._process(0.05)
	_check(app.sim.outcome == outcome and app.menu == outcome, outcome + " actual Main step selects terminal menu")
	_check(app.guide_clock < 0.25, outcome + " transition occurs before periodic guidance deadline")
	_check(_normalized(app.sim.save_state()) == _normalized(expected[outcome]), outcome + " Main transition/guide refresh preserve complete simulation and RNG")
	var hint: Dictionary = guide.get_hint()
	_check(guide.update_calls == calls + 1, outcome + " guidance refresh occurs exactly once on terminal frame")
	_check(hint.title == ("突围完成" if outcome == "victory" else "本次突围结束"), outcome + " terminal title is current immediately for " + visibility)
	_check(bool(hint.complete) == (outcome == "victory"), outcome + " completion flag is truthful for " + visibility)
	_check(hint.visible == prior_hint.visible and hint.enabled == prior_hint.enabled and hint.dismissed == prior_hint.dismissed, outcome + " preserves " + visibility + " preference")
	_check(app.world.guide_target == (hint.target if hint.visible else Vector2(-1, -1)), outcome + " world target uses current terminal hint")
	if DisplayServer.get_name() != "headless" and visibility == "visible":
		app.camera.position = Vector2(72, 19) * app.TILE
		app.camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/terminal-guide"))
		_check(image != null and not image.is_empty() and image.save_png("res://work/terminal-guide/" + outcome + "-immediate.png") == OK, outcome + " actual immediate terminal pixels captured")
	var state: String = _normalized(app.sim.save_state())
	calls = guide.update_calls
	app._process(0.01)
	_check(guide.update_calls == calls, outcome + " next terminal frame does not redundantly refresh")
	_check(_normalized(app.sim.save_state()) == state, outcome + " terminal menu does not advance simulation")


func _normalized(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)


func _finish_without_app() -> void:
	print("Terminal guide checks: %d; failures: %d; display=%s" % [checks, failures.size(), DisplayServer.get_name()])
	for failure: String in failures: printerr(" - ", failure)
	quit(0 if failures.is_empty() else 1)
