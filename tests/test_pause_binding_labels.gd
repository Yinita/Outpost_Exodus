extends SceneTree
## Headless controller/text regression. No rendering or human usability claim.
## XDG_DATA_HOME="$PWD/work/pause-binding-labels-data" ./run.sh --headless
##   --script res://tests/test_pause_binding_labels.gd

const Main = preload("res://scripts/main.gd")
const Simulation = preload("res://scripts/campaign_simulation.gd")
const Hud = preload("res://scripts/hud.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolation: String = ProjectSettings.globalize_path("res://work/pause-binding-labels-data").trim_suffix("/")
	if not OS.get_user_data_dir().begins_with(isolation + "/"):
		printerr("Pause binding checks require isolated work/pause-binding-labels-data")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	var app: Variant = Main.new()
	app.sim = Simulation.new()
	_check(app.sim.reset(42), "actual simulation initializes")
	app._setup_inputs()
	app.started = true
	app.menu = ""
	var hud: Variant = Hud.new()
	hud.main = app
	var default_label: String = app.binding_label("pause_game")
	_check(hud._compact_tab_tip().contains(default_label + " 暂停"), "running compact tip uses the actual default binding and pause action")
	_key(app, KEY_SPACE)
	_check(app.sim.paused, "default binding actually pauses through Main input")
	_check(hud._pause_banner_text().contains(default_label + " 继续"), "paused banner uses the actual default binding and continue action")
	_check(hud._compact_tab_tip().contains("战术已暂停") and not hud._compact_tab_tip().contains("地图继续运行"), "paused compact tip no longer claims that the map is running")

	var replacement: InputEventKey = _event(KEY_J)
	_check(app._try_bind("pause_game", replacement), "real rebinding accepts J")
	var settings: ConfigFile = ConfigFile.new()
	_check(settings.load(app.CONFIG_PATH) == OK and int(settings.get_value("keys", "pause_game", 0)) == KEY_J, "rebound pause key persists in isolated settings")
	_check(hud._pause_banner_text().contains("J 继续") and not hud._pause_banner_text().contains("空格"), "banner follows rebound J instead of hardcoded Space")
	_check(hud._compact_tab_tip().contains("J 继续"), "paused compact tip follows rebound J")
	_key(app, KEY_SPACE)
	_check(app.sim.paused, "old Space cannot resume after rebinding")
	_key(app, KEY_J)
	_check(not app.sim.paused, "rebound J actually resumes through Main input")
	_check(hud._compact_tab_tip().contains("地图继续运行") and hud._compact_tab_tip().contains("J 暂停"), "running compact tip changes its state and J action after resume")
	_key(app, KEY_J)
	_check(app.sim.paused and hud._compact_tab_tip().contains("J 继续"), "same rebound key pauses again and updates the action text")

	_check(app._try_bind("pause_game", _event(KEY_BACKSPACE)), "a longer key name can be bound")
	var long_label: String = app.binding_label("pause_game")
	_check(hud._pause_banner_text().contains(long_label + " 继续") and hud._compact_tab_tip().contains(long_label + " 继续"), "both texts use the complete longer current key name")
	var before: String = JSON.stringify(app.sim.save_state())
	for index: int in range(20):
		hud._pause_banner_text()
		hud._compact_tab_tip()
	_check(before == JSON.stringify(app.sim.save_state()), "text queries preserve the complete simulation and RNG state")
	hud.free()
	app.free()
	print("Pause binding label checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures:
		printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _event(code: int) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _key(app: Variant, code: int) -> void:
	app._unhandled_input(_event(code))


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
