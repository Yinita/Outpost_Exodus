extends Node2D

const Simulation = preload("res://scripts/campaign_simulation.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Hud = preload("res://scripts/hud.gd")
const TILE: float = 48.0
const SAVE_PATH: String = "user://campaign-save.json"
const CONFIG_PATH: String = "user://settings.cfg"

var sim: Variant
var world: Node2D
var camera: Camera2D
var hud: Control
var selected_ids: Array = []
var selected_camp: int = 0
var current_tab: String = "build"
var build_kind: String = ""
var attack_move: bool = false
var pending_task: String = ""
var started: bool = false
var menu: String = "title"
var speed: float = 1.0
var volume: float = 0.6
var edge_scroll: bool = false
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var pan_active: bool = false
var group_bindings: Dictionary = {}
var waiting_binding: String = ""
var accumulator: float = 0.0
var autosave_time: float = 0.0
var sound_cooldown: float = 0.0
var capture_path: String = ""
var capture_frames: int = 0
var tick_count: int = 0
var feedback: String = ""
var feedback_left: float = 0.0
var sound_player: AudioStreamPlayer
var command_names: Dictionary = {
	"camera_up": "镜头向上", "camera_down": "镜头向下", "camera_left": "镜头向左", "camera_right": "镜头向右",
	"build_menu": "建设面板", "production_menu": "生产面板", "orders_menu": "小队指挥", "train_menu": "训练招募", "pause_game": "战术暂停",
	"attack_move": "攻击移动", "focus_command": "定位指挥部", "next_squad": "切换小队", "quick_save": "快速保存", "quick_load": "快速读取"
}

func _ready() -> void:
	_setup_inputs()
	_load_settings()
	sim = Simulation.new()
	sim.reset(42)
	selected_camp = int(sim.camps[0].id)
	world = WorldView.new()
	world.sim = sim
	world.world_font = load("res://assets/fonts/NotoSansCJK-Regular.ttc")
	add_child(world)
	camera = Camera2D.new()
	camera.position = Vector2(16.0, 22.0) * TILE
	camera.zoom = Vector2.ONE * 1.05
	add_child(camera)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Hud.new()
	hud.main = self
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hud)
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
			start_campaign()
		if arg == "--smoke":
			capture_frames = 240
			start_campaign()
	_notify("欢迎来到峡谷。先选择小队，清理燃料点并建立前哨。")

func _setup_inputs() -> void:
	var bindings: Dictionary = {
		"camera_up": KEY_W, "camera_down": KEY_S, "camera_left": KEY_A, "camera_right": KEY_D,
		"build_menu": KEY_B, "production_menu": KEY_P, "orders_menu": KEY_V, "train_menu": KEY_N, "pause_game": KEY_SPACE,
		"attack_move": KEY_X, "focus_command": KEY_HOME, "next_squad": KEY_TAB,
		"quick_save": KEY_F5, "quick_load": KEY_F9
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = bindings[action]
		InputMap.action_add_event(action, key)

func _process(delta: float) -> void:
	feedback_left = maxf(0.0, feedback_left - delta)
	sound_cooldown = maxf(0.0, sound_cooldown - delta)
	if started and menu.is_empty():
		_move_camera(delta)
		accumulator += minf(delta, 0.2) * speed
		var steps: int = 0
		while accumulator >= 0.05 and steps < 12:
			sim.tick(0.05)
			accumulator -= 0.05
			steps += 1
			tick_count += 1
		autosave_time += delta
		if autosave_time > 45.0 and sim.outcome == "playing":
			autosave_time = 0.0
			save_campaign(false)
		if sim.outcome != "playing":
			menu = sim.outcome
	if sim.effects.size() > 0 and sound_cooldown <= 0.0 and started and menu.is_empty():
		_play_tone(115.0, 0.035, 0.10)
		sound_cooldown = 0.28
	selected_ids = selected_ids.filter(func(id: int) -> bool: return not sim.get_unit(id).is_empty() and float(sim.get_unit(id).get("hp", 0.0)) > 0.0)
	world.selected_ids = selected_ids
	world.hover_tile = Vector2i(get_global_mouse_position() / TILE)
	world.build_kind = build_kind
	world.drag_selecting = dragging
	world.drag_selection_rect = Rect2(drag_start, get_global_mouse_position() - drag_start)
	world.queue_redraw()
	hud.queue_redraw()
	if not capture_path.is_empty():
		capture_frames += 1
		if capture_frames == 40:
			await RenderingServer.frame_post_draw
			var frame: Image = get_viewport().get_texture().get_image()
			var result: Error = frame.save_png(capture_path)
			print("CAPTURE_RESULT ", result, " ", capture_path)
			get_tree().quit(0 if result == OK else 1)
	elif capture_frames > 0:
		capture_frames -= 1
		if capture_frames == 0:
			print("SMOKE_OK ticks=", tick_count, " units=", sim.units.size())
			get_tree().quit()

func _move_camera(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if edge_scroll and not dragging:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		var screen: Vector2 = get_viewport_rect().size
		if mouse.x < 8: direction.x -= 1.0
		if mouse.x > screen.x - 8: direction.x += 1.0
		if mouse.y < 8: direction.y -= 1.0
		if mouse.y > screen.y - 8: direction.y += 1.0
	camera.position += direction.limit_length() * delta * 780.0 / camera.zoom.x
	camera.position = camera.position.clamp(Vector2.ZERO, Vector2(sim.map_size) * TILE)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if not waiting_binding.is_empty():
			if event.keycode == KEY_ESCAPE:
				waiting_binding = ""
				return
			var binding: InputEventKey = InputEventKey.new()
			binding.physical_keycode = event.physical_keycode
			InputMap.action_erase_events(waiting_binding)
			InputMap.action_add_event(waiting_binding, binding)
			waiting_binding = ""
			_save_settings()
			return
		if event.keycode == KEY_ESCAPE:
			if not pending_task.is_empty() or attack_move:
				pending_task = ""
				attack_move = false
			elif not build_kind.is_empty():
				build_kind = ""
			elif menu == "settings" or menu == "help":
				menu = "pause" if started else "title"
			else:
				menu = "" if menu == "pause" else ("pause" if started else "title")
			return
		if not menu.is_empty(): return
		if event.is_action_pressed("pause_game"): sim.paused = not sim.paused
		elif event.is_action_pressed("build_menu"): current_tab = "build"
		elif event.is_action_pressed("production_menu"): current_tab = "production"
		elif event.is_action_pressed("orders_menu"): current_tab = "orders"
		elif event.is_action_pressed("train_menu"): current_tab = "training"
		elif event.is_action_pressed("quick_save"): save_campaign()
		elif event.is_action_pressed("quick_load"): load_campaign()
		elif event.is_action_pressed("focus_command"): focus_camp(selected_camp)
		elif event.is_action_pressed("attack_move"):
			attack_move = true
			_notify("攻击移动：左键选择目标区域，右键取消。")
		elif event.is_action_pressed("next_squad"): _next_squad()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			_group_key(int(event.keycode - KEY_0), event.ctrl_pressed, event.shift_pressed)
		elif event.keycode == KEY_L: world.show_logistics = not world.show_logistics
		elif event.keycode == KEY_O: world.show_ranges = not world.show_ranges
		elif event.keycode == KEY_H: menu = "help"
		elif event.keycode == KEY_EQUAL: speed = minf(3.0, speed + 1.0)
		elif event.keycode == KEY_MINUS: speed = maxf(1.0, speed - 1.0)
	if event is InputEventMouseButton:
		if hud.handle_mouse(event): return
		if not started or not menu.is_empty(): return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: _zoom(1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: _zoom(1.0 / 1.12)
		elif event.button_index == MOUSE_BUTTON_MIDDLE: pan_active = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not build_kind.is_empty():
					var ok: bool = sim.build(build_kind, Vector2i(get_global_mouse_position() / TILE))
					_notify("已安排施工。工程师会前往工地。" if ok else "无法施工：检查材料、可达性和工程师位置。")
					_play_tone(460.0 if ok else 140.0, 0.08)
					if build_kind != "road" and ok: build_kind = ""
				elif attack_move:
					sim.command_move(selected_ids, get_global_mouse_position() / TILE, true)
					attack_move = false
				elif not pending_task.is_empty():
					sim.command_task(selected_ids, pending_task, get_global_mouse_position() / TILE)
					pending_task = ""
				else:
					dragging = true
					drag_start = get_global_mouse_position()
			else:
				if dragging:
					_select(get_global_mouse_position(), event.shift_pressed, event.double_click)
					dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not build_kind.is_empty() or attack_move or not pending_task.is_empty():
				build_kind = ""
				attack_move = false
				pending_task = ""
			else:
				_issue_context(get_global_mouse_position() / TILE)
	if event is InputEventMouseMotion and pan_active:
		camera.position -= event.relative / camera.zoom

func _select(point: Vector2, append: bool, same_kind: bool) -> void:
	var rect: Rect2 = Rect2(drag_start, point - drag_start).abs()
	var click: bool = rect.size.length() < 12.0 / camera.zoom.x
	if not append: selected_ids.clear()
	var closest: Dictionary = {}
	var distance: float = 0.85
	for unit: Dictionary in sim.units:
		if unit.get("team", "") != "friendly" or float(unit.get("hp", 0.0)) <= 0: continue
		var p: Vector2 = unit.get("pos", Vector2.ZERO)
		if click:
			var d: float = p.distance_to(point / TILE)
			if d < distance: closest = unit; distance = d
		elif rect.has_point(p * TILE):
			if not selected_ids.has(unit.id): selected_ids.append(unit.id)
	if not closest.is_empty():
		if same_kind:
			for u: Dictionary in sim.units:
				if u.get("team") == "friendly" and u.get("kind") == closest.get("kind"):
					if not selected_ids.has(u.id): selected_ids.append(u.id)
		elif not selected_ids.has(closest.id): selected_ids.append(closest.id)
		if int(closest.get("camp_id", -1)) >= 0: selected_camp = int(closest.get("camp_id"))
	if click and closest.is_empty():
		var best: float = 4.0
		for camp: Dictionary in sim.camps:
			var d: float = Vector2(camp.pos).distance_to(point / TILE)
			if d < best: selected_camp = int(camp.id); best = d
	_play_tone(650.0, 0.025, 0.15)

func _issue_context(target: Vector2) -> void:
	if selected_ids.is_empty():
		_notify("先左键选择或拖框选择小队。")
		return
	if not pending_task.is_empty():
		sim.command_task(selected_ids, pending_task, target)
		pending_task = ""
		_notify("已向目标区域派出任务小队。")
		return
	var repair: bool = false
	for site: Dictionary in sim.sites:
		if site.get("kind") == "exit" and Vector2(site.pos).distance_to(target) < 3.5: repair = true
	if repair:
		sim.command_task(selected_ids, "repair", target)
	else:
		sim.command_move(selected_ids, target, true)
	_notify("已下达小队指令。")
	_play_tone(540.0, 0.035, 0.15)

func _zoom(factor: float) -> void:
	var before: Vector2 = get_global_mouse_position()
	var value: float = clampf(camera.zoom.x * factor, 0.35, 1.6)
	camera.zoom = Vector2.ONE * value
	camera.force_update_scroll()
	var after: Vector2 = get_global_mouse_position()
	camera.position += before - after

func _next_squad() -> void:
	var groups: Array = []
	for u: Dictionary in sim.units:
		if u.get("team") == "friendly" and not groups.has(int(u.get("squad", 0))): groups.append(int(u.get("squad", 0)))
	if groups.is_empty(): return
	var current: int = -1
	if not selected_ids.is_empty(): current = int(sim.get_unit(selected_ids[0]).get("squad", -1))
	var next_index: int = (groups.find(current) + 1) % groups.size()
	selected_ids.clear()
	for u: Dictionary in sim.units:
		if u.get("team") == "friendly" and int(u.get("squad", 0)) == int(groups[next_index]): selected_ids.append(u.id)
	_focus_selection()

func _group_key(index: int, store_group: bool, append: bool) -> void:
	if store_group:
		group_bindings[index] = selected_ids.duplicate()
		_notify("已保存编队 %d" % index)
		return
	if not append: selected_ids.clear()
	var group: Array = group_bindings.get(index, [])
	if group.is_empty():
		for u: Dictionary in sim.units:
			if u.get("team") == "friendly" and int(u.get("squad", 0)) == index: group.append(u.id)
	for id: int in group:
		if not selected_ids.has(id) and not sim.get_unit(id).is_empty(): selected_ids.append(id)
	_focus_selection()

func _focus_selection() -> void:
	if selected_ids.is_empty(): return
	var center: Vector2 = Vector2.ZERO
	for id: int in selected_ids: center += Vector2(sim.get_unit(id).get("pos", Vector2.ZERO))
	camera.position = center / selected_ids.size() * TILE

func focus_camp(id: int) -> void:
	var camp: Dictionary = sim.get_camp(id)
	if camp.is_empty(): return
	selected_camp = id
	camera.position = Vector2(camp.pos) * TILE

func ui_action(action: String) -> void:
	_play_tone(500.0, 0.04, 0.18)
	if action == "new": start_campaign()
	elif action == "resume": menu = ""
	elif action == "load": load_campaign()
	elif action == "save": save_campaign()
	elif action == "settings": menu = "settings"
	elif action == "help": menu = "help"
	elif action == "back": menu = "pause" if started else "title"
	elif action == "quit": get_tree().quit()
	elif action == "pause": sim.paused = not sim.paused
	elif action == "speed": speed = 1.0 if speed >= 3.0 else speed + 1.0
	elif action == "menu": menu = "pause"
	elif action == "logistics": world.show_logistics = not world.show_logistics
	elif action == "ranges": world.show_ranges = not world.show_ranges
	elif action == "volume":
		volume = 0.0 if volume > 0.95 else volume + 0.2
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
		_save_settings()
	elif action == "edge_scroll": edge_scroll = not edge_scroll; _save_settings()
	elif action.begins_with("bind:"): waiting_binding = action.trim_prefix("bind:")
	elif action.begins_with("tab:"): current_tab = action.trim_prefix("tab:"); build_kind = ""
	elif action.begins_with("build:"):
		pending_task = ""
		attack_move = false
		build_kind = action.trim_prefix("build:")
		_notify("在地图点击放置，右键取消；道路可以连续铺设。")
	elif action.begins_with("camp:"): focus_camp(int(action.trim_prefix("camp:")))
	elif action.begins_with("recipe:"): sim.set_production(selected_camp, action.trim_prefix("recipe:"))
	elif action.begins_with("priority:"): sim.set_priority(selected_camp, action.trim_prefix("priority:"))
	elif action.begins_with("recruit:"):
		var queued: bool = sim.recruit(selected_camp, action.trim_prefix("recruit:"))
		_notify("已加入训练队列，需要本地设施和持续供能。" if queued else "无法招募：检查设施、电力、资源与人口上限。")
	elif action == "evacuate":
		_notify("驻点开始撤收，请保护运输路线。" if sim.evacuate_camp(selected_camp) else "暂时不能撤收这个驻点。")
	elif action.begins_with("seal:"):
		_notify("已安排关口封锁。" if sim.seal_choke(int(action.trim_prefix("seal:"))) else "暂不能封锁：检查材料与尚未通过的友军。")
	elif action.begins_with("task:"):
		if selected_ids.is_empty():
			_notify("先选择执行任务的小队。")
		else:
			build_kind = ""
			attack_move = false
			pending_task = action.trim_prefix("task:")
			_notify("在地图左键选择任务区域；也可在小地图右键指定。")

func start_campaign() -> void:
	sim.reset(42)
	started = true
	menu = ""
	build_kind = ""
	pending_task = ""
	speed = 1.0
	accumulator = 0.0
	selected_camp = int(sim.camps[0].id)
	selected_ids.clear()
	for unit: Dictionary in sim.units:
		if unit.get("team") == "friendly" and unit.get("kind") in ["rifle", "engineer"]: selected_ids.append(unit.id)
	camera.position = Vector2(16, 22) * TILE
	camera.zoom = Vector2.ONE * 1.05
	_notify("第一战役 · 峡谷突围。前方清场扩张，后方尸潮将在整备期后抵达。H 查看操作。")

func save_campaign(manual: bool = true) -> bool:
	if not started: return false
	var state: Dictionary = sim.save_state()
	state["ui"] = {"camera_x": camera.position.x, "camera_y": camera.position.y, "zoom": camera.zoom.x, "selected_camp": selected_camp}
	var file: FileAccess = FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		if manual: _notify("存档失败：无法写入存档文件。")
		return false
	file.store_string(JSON.stringify(state))
	file.close()
	var error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".tmp"), ProjectSettings.globalize_path(SAVE_PATH))
	if manual: _notify("战役已保存 · %s 快速读取" % binding_label("quick_load") if error == OK else "存档替换失败。")
	return error == OK

func load_campaign() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		_notify("尚无战役存档。")
		return false
	var text: String = FileAccess.get_file_as_string(SAVE_PATH)
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		_notify("无法读取存档：JSON 数据损坏。")
		return false
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		_notify("无法读取存档：数据格式不正确。")
		return false
	var ui_value: Variant = parsed.get("ui", {})
	if not ui_value is Dictionary:
		_notify("无法读取存档：界面状态损坏，当前战役保持不变。")
		return false
	var ui_state: Dictionary = ui_value
	for key: String in ["camera_x", "camera_y", "zoom", "selected_camp"]:
		if ui_state.has(key):
			var value: Variant = ui_state[key]
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 10000000.0:
				_notify("无法读取存档：镜头或驻点数据损坏。")
				return false
	if ui_state.has("zoom") and (float(ui_state.zoom) < 0.35 or float(ui_state.zoom) > 1.6):
		_notify("无法读取存档：缩放数据超出范围。")
		return false
	if not sim.load_state(parsed):
		_notify("无法读取存档：数据损坏或版本不兼容。")
		return false
	started = true
	menu = ""
	selected_ids.clear()
	camera.position = Vector2(float(ui_state.get("camera_x", 624)), float(ui_state.get("camera_y", 1008)))
	camera.zoom = Vector2.ONE * clampf(float(ui_state.get("zoom", 0.95)), 0.35, 1.6)
	selected_camp = int(ui_state.get("selected_camp", 0))
	_notify("战役已恢复。")
	return true

func binding_label(action: String) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty() or not events[0] is InputEventKey: return "—"
	return OS.get_keycode_string(events[0].physical_keycode)

func _notify(text: String) -> void:
	feedback = text
	feedback_left = 5.0

func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(CONFIG_PATH) != OK: return
	volume = float(config.get_value("audio", "volume", 0.6))
	edge_scroll = bool(config.get_value("input", "edge_scroll", false))
	for action: String in command_names:
		var keycode: int = int(config.get_value("keys", action, 0))
		if keycode > 0:
			var key: InputEventKey = InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, key)

func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "volume", volume)
	config.set_value("input", "edge_scroll", edge_scroll)
	for action: String in command_names:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if not events.is_empty() and events[0] is InputEventKey: config.set_value("keys", action, events[0].physical_keycode)
	config.save(CONFIG_PATH)

func _play_tone(frequency: float, duration: float, gain: float = 0.25) -> void:
	if sound_player == null or volume <= 0.001: return
	var count: int = int(22050.0 * duration)
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	for i: int in range(count):
		var envelope: float = pow(1.0 - float(i) / maxf(count, 1), 2.0)
		var sample: int = int(sin(float(i) * TAU * frequency / 22050.0) * envelope * gain * 18000.0)
		data.encode_s16(i * 2, sample)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = data
	sound_player.stream = stream
	sound_player.play()
