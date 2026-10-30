extends Node2D

const Simulation = preload("res://scripts/campaign_simulation.gd")
const Catalog = preload("res://scripts/campaign_catalog.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Hud = preload("res://scripts/hud.gd")
const Guide = preload("res://scripts/campaign_guide.gd")
const SaveStore = preload("res://scripts/campaign_save_store.gd")
const TILE: float = 48.0
const MIN_CAMERA_ZOOM: float = 0.35
const MAX_CAMERA_ZOOM: float = 1.6
const CAMERA_FLOAT_EPSILON: float = 0.000001
const SAVE_PATH: String = "user://campaign-save.json"
const AUTOSAVE_PATH: String = "user://campaign-autosave.json"
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
var selected_mission_id: String = Catalog.DEFAULT_ID
var pending_mission_id: String = ""
var campaign_return_menu: String = "title"
var speed: float = 1.0
var volume: float = 0.6
var music_volume: float = 0.35
var effects_volume: float = 0.7
var muted: bool = false
var fullscreen: bool = false
var window_resolution: Vector2i = Vector2i(1440, 810)
var display_configured: bool = false
var ui_scale: float = 1.0
var settings_tab: String = "controls"
var settings_page: int = 0
var settings_feedback: String = ""
var guide: RefCounted = Guide.new()
var save_store: RefCounted = SaveStore.new()
var last_sim_message: String = ""
var guide_enabled: bool = true
var guide_clock: float = 0.0
var edge_scroll: bool = false
var dragging: bool = false
var selection_double_click: bool = false
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
var closing: bool = false
var feedback: String = ""
var feedback_left: float = 0.0
var sound_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var command_names: Dictionary = {
	"camera_up": "镜头向上", "camera_down": "镜头向下", "camera_left": "镜头向左", "camera_right": "镜头向右",
	"build_menu": "建设面板", "production_menu": "生产面板", "orders_menu": "小队指挥", "train_menu": "训练招募", "pause_game": "战术暂停",
	"attack_move": "攻击移动", "focus_command": "定位指挥部", "next_squad": "切换小队", "quick_save": "快速保存", "quick_load": "快速读取",
	"help_menu": "操作手册", "logistics_toggle": "补给线显示", "ranges_toggle": "覆盖范围", "speed_up": "加快速度", "speed_down": "减慢速度",
	"group_1": "编队1（Ctrl保存）", "group_2": "编队2（Ctrl保存）", "group_3": "编队3（Ctrl保存）", "group_4": "编队4（Ctrl保存）"
}

func _ready() -> void:
	var diagnostics: Script
	if OS.get_cmdline_user_args().has("--render-diagnostics"):
		diagnostics = load("res://scripts/diagnostics/render_runner.gd") as Script
		var isolation_errors: Array[String] = diagnostics.validate_environment()
		if not isolation_errors.is_empty():
			for error: String in isolation_errors: printerr("DIAGNOSTICS_REFUSED ", error)
			get_tree().quit(2)
			return
	_setup_inputs()
	_load_settings()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mission="):
			var requested: String = argument.trim_prefix("--mission=")
			if not Catalog.ids().has(requested):
				printerr("Unknown mission: ", requested)
				get_tree().quit(2)
				return
			selected_mission_id = requested
	sim = Simulation.new()
	sim.reset(42, selected_mission_id)
	guide.reset(guide_enabled)
	selected_camp = int(sim.camps[0].id)
	world = WorldView.new()
	world.sim = sim
	world.world_font = load("res://assets/fonts/NotoSansCJK-Regular.ttc")
	add_child(world)
	camera = Camera2D.new()
	camera.position = (Vector2(sim.camps[0].pos) + Vector2(7, 0)) * TILE
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
	_setup_audio()
	_apply_display_settings()
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_on_close_requested)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
			start_campaign()
		if arg == "--smoke":
			capture_frames = 240
			start_campaign()
	_notify("欢迎来到逐营突围。选择战役，带领小队开路并转移营地。")
	if diagnostics != null:
		var runner: Node = diagnostics.new()
		runner.app = self
		get_tree().root.call_deferred("add_child", runner)

func _setup_inputs() -> void:
	var bindings: Dictionary = {
		"camera_up": KEY_W, "camera_down": KEY_S, "camera_left": KEY_A, "camera_right": KEY_D,
		"build_menu": KEY_B, "production_menu": KEY_P, "orders_menu": KEY_V, "train_menu": KEY_N, "pause_game": KEY_SPACE,
		"attack_move": KEY_X, "focus_command": KEY_HOME, "next_squad": KEY_TAB,
		"quick_save": KEY_F5, "quick_load": KEY_F9,
		"help_menu": KEY_H, "logistics_toggle": KEY_L, "ranges_toggle": KEY_O, "speed_up": KEY_EQUAL, "speed_down": KEY_MINUS,
		"group_1": KEY_1, "group_2": KEY_2, "group_3": KEY_3, "group_4": KEY_4
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = bindings[action]
		InputMap.action_add_event(action, key)

func _process(delta: float) -> void:
	if menu == "settings": settings_page = clampi(settings_page, 0, (command_names.size() - 1) / settings_binding_page_size())
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
	if sim.effects.size() > 0 and sound_cooldown <= 0.0 and started and menu.is_empty() and not sim.paused:
		_play_tone(115.0, 0.035, 0.10)
		sound_cooldown = 0.28
	selected_ids = selected_ids.filter(func(id: int) -> bool: return not sim.get_unit(id).is_empty() and float(sim.get_unit(id).get("hp", 0.0)) > 0.0)
	guide_clock += delta
	if started and guide_clock >= 0.25:
		guide_clock = 0.0
		guide.update(sim, selected_ids, selected_camp)
		if feedback_left <= 0.0 and not sim.messages.is_empty() and String(sim.messages.back()) != last_sim_message:
			last_sim_message = String(sim.messages.back())
			_notify(last_sim_message)
	world.selected_ids = selected_ids
	world.hover_tile = Vector2i(get_global_mouse_position() / TILE)
	world.build_kind = build_kind
	world.drag_selecting = dragging
	world.drag_selection_rect = Rect2(drag_start, get_global_mouse_position() - drag_start)
	var hint: Dictionary = guide.get_hint()
	world.guide_target = hint.get("target", Vector2(-1, -1)) if started and bool(hint.get("visible", false)) else Vector2(-1, -1)
	world.queue_redraw()
	hud.queue_redraw()
	if not capture_path.is_empty():
		capture_frames += 1
		if capture_frames == 40:
			await RenderingServer.frame_post_draw
			var frame: Image = get_viewport().get_texture().get_image()
			var result: Error = frame.save_png(capture_path)
			print("CAPTURE_RESULT ", result, " ", capture_path)
			_quit_cleanly(0 if result == OK else 1)
	elif capture_frames > 0:
		capture_frames -= 1
		if capture_frames == 0:
			print("SMOKE_OK ticks=", tick_count, " units=", sim.units.size())
			_quit_cleanly()

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
				settings_feedback = "已取消，原按键保持不变。"
				return
			_try_bind(waiting_binding, event)
			return
		if event.keycode == KEY_ESCAPE:
			if not pending_task.is_empty() or attack_move:
				pending_task = ""
				attack_move = false
			elif not build_kind.is_empty():
				build_kind = ""
			elif menu == "campaigns":
				ui_action("campaign_back")
			elif menu == "restart":
				ui_action("resume")
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
		elif _group_action_index(event) > 0:
			_group_key(_group_action_index(event), event.ctrl_pressed, event.shift_pressed)
		elif event.is_action_pressed("logistics_toggle"): world.show_logistics = not world.show_logistics
		elif event.is_action_pressed("ranges_toggle"): world.show_ranges = not world.show_ranges
		elif event.is_action_pressed("help_menu"): menu = "help"
		elif event.is_action_pressed("speed_up"): speed = minf(3.0, speed + 1.0)
		elif event.is_action_pressed("speed_down"): speed = maxf(1.0, speed - 1.0)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed: pan_active = false
		if hud.handle_mouse(event):
			if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: dragging = false
			return
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
					var target: Vector2 = get_global_mouse_position() / TILE
					sim.command_move(selected_ids, target, true)
					guide.observe("move", {"target": target})
					attack_move = false
				elif not pending_task.is_empty():
					var target: Vector2 = get_global_mouse_position() / TILE
					guide.observe(pending_task, {"target": target})
					sim.command_task(selected_ids, pending_task, target)
					pending_task = ""
				else:
					dragging = true
					selection_double_click = event.double_click
					drag_start = get_global_mouse_position()
			else:
				if dragging:
					_select(get_global_mouse_position(), event.shift_pressed, selection_double_click)
					dragging = false
					selection_double_click = false
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
				var visible_position: Vector2 = get_canvas_transform() * (Vector2(u.get("pos", Vector2.ZERO)) * TILE)
				if u.get("team") == "friendly" and u.get("kind") == closest.get("kind") and float(u.get("hp",0)) > 0 and get_viewport_rect().has_point(visible_position):
					if not selected_ids.has(u.id): selected_ids.append(u.id)
		elif not selected_ids.has(closest.id): selected_ids.append(closest.id)
		if int(closest.get("camp_id", -1)) >= 0: selected_camp = int(closest.get("camp_id"))
	if click and closest.is_empty():
		var best: float = 4.0
		for camp: Dictionary in sim.camps:
			var d: float = Vector2(camp.pos).distance_to(point / TILE)
			if d < best: selected_camp = int(camp.id); best = d
	_play_tone(650.0, 0.025, 0.15)
	guide.observe("selection", {"count": selected_ids.size()})

func _issue_context(target: Vector2) -> void:
	if selected_ids.is_empty():
		_notify("先左键选择或拖框选择小队。")
		return
	if not pending_task.is_empty():
		guide.observe(pending_task, {"target": target})
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
		guide.observe("move", {"target": target})
	_notify("已下达小队指令。")
	_play_tone(540.0, 0.035, 0.15)

func _zoom(factor: float) -> void:
	var before: Vector2 = get_global_mouse_position()
	var value: float = clampf(camera.zoom.x * factor, MIN_CAMERA_ZOOM, MAX_CAMERA_ZOOM)
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
	if action == "new":
		if started and sim.outcome == "playing":
			pending_mission_id = String(sim.mission_id)
			menu = "restart"
		else: start_campaign()
	elif action == "campaigns":
		campaign_return_menu = menu if menu in ["title", "pause", "victory", "defeat"] else ("pause" if started else "title")
		pending_mission_id = ""
		menu = "campaigns"
	elif action == "campaign_back":
		pending_mission_id = ""
		menu = campaign_return_menu
	elif action.begins_with("campaign:"):
		var requested: String = action.trim_prefix("campaign:")
		if not Catalog.ids().has(requested):
			_notify("无法选择此战役，当前进度保持不变。")
			return
		if started and sim.outcome == "playing":
			pending_mission_id = requested
			menu = "restart"
		else: start_campaign(requested)
	elif action == "restart_confirm":
		var requested: String = pending_mission_id if not pending_mission_id.is_empty() else (String(sim.mission_id) if started else selected_mission_id)
		if not Catalog.ids().has(requested):
			_notify("无法选择此战役，当前进度保持不变。")
			return
		if started and not save_campaign(false):
			_notify("自动保存失败，未重新开始；请先手动保存或检查存储空间。")
			return
		start_campaign(requested)
	elif action == "resume":
		pending_mission_id = ""
		menu = ""
	elif action == "title":
		if started and sim.outcome == "playing": save_campaign(false)
		started = false
		pending_mission_id = ""
		menu = "title"
		build_kind = ""
		pending_task = ""
	elif action.begins_with("guide_branch:"):
		var branch: String = action.trim_prefix("guide_branch:")
		if branch in ["north", "south", "any"]:
			guide.observe("branch", {"kind": branch})
			guide.update(sim, selected_ids, selected_camp)
	elif action == "guide_more": menu = "guide"
	elif action == "load": load_campaign()
	elif action == "save": save_campaign()
	elif action == "settings":
		menu = "settings"
		settings_page = 0
		settings_feedback = ""
	elif action.begins_with("settings_tab:"):
		settings_tab = action.trim_prefix("settings_tab:")
	elif action == "bindings_prev": settings_page = maxi(0, settings_page - 1)
	elif action == "bindings_next": settings_page = mini((command_names.size() - 1) / settings_binding_page_size(), settings_page + 1)
	elif action == "bindings_reset":
		_setup_inputs()
		waiting_binding = ""
		settings_feedback = "所有快捷键已恢复默认。"
		_save_settings()
	elif action == "guide_toggle":
		guide_enabled = not bool(guide.get_hint().get("visible", false))
		if guide_enabled: guide.observe("show")
		else: guide.dismiss()
		_save_settings()
	elif action == "guide_focus":
		var point: Vector2 = guide.get_hint().get("target", Vector2(-1, -1))
		if point.x >= 0: camera.position = point * TILE
		if menu == "guide": menu = ""
	elif action == "load_auto": load_campaign("auto")
	elif action == "load_backup": load_campaign("backup")
	elif action == "fullscreen":
		fullscreen = not fullscreen
		display_configured = true
		_apply_display_settings()
		_save_settings()
	elif action == "resolution":
		var resolutions: Array[Vector2i] = [Vector2i(1280,720), Vector2i(1440,810), Vector2i(1600,900), Vector2i(1920,1080)]
		window_resolution = resolutions[(resolutions.find(window_resolution) + 1) % resolutions.size()]
		display_configured = true
		_apply_display_settings()
		_save_settings()
	elif action == "ui_scale":
		ui_scale = 1.0 if ui_scale >= 1.19 else snappedf(ui_scale + 0.1, 0.1)
		_apply_display_settings()
		_save_settings()
	elif action == "mute":
		muted = not muted
		_apply_audio_settings()
		_save_settings()
	elif action == "music_volume" or action == "effects_volume":
		if action == "music_volume": music_volume = 0.0 if music_volume >= 0.99 else minf(1.0, music_volume + 0.1)
		else: effects_volume = 0.0 if effects_volume >= 0.99 else minf(1.0, effects_volume + 0.1)
		_apply_audio_settings()
		_save_settings()
	elif action == "help": menu = "help"
	elif action == "back": menu = "pause" if started else "title"
	elif action == "quit": _on_close_requested()
	elif action == "pause": sim.paused = not sim.paused
	elif action == "speed": speed = 1.0 if speed >= 3.0 else speed + 1.0
	elif action == "menu": menu = "pause"
	elif action == "logistics": world.show_logistics = not world.show_logistics
	elif action == "ranges": world.show_ranges = not world.show_ranges
	elif action == "volume":
		volume = 0.0 if volume > 0.95 else minf(1.0, volume + 0.2)
		_apply_audio_settings()
		_save_settings()
	elif action == "edge_scroll": edge_scroll = not edge_scroll; _save_settings()
	elif action.begins_with("bind:"):
		waiting_binding = action.trim_prefix("bind:")
		settings_feedback = "请按一个新按键；Esc 取消。"
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

func start_campaign(mission_id: String = "") -> void:
	var requested: String = selected_mission_id if mission_id.is_empty() else mission_id
	if not Catalog.ids().has(requested):
		_notify("无法选择此战役，当前进度保持不变。")
		return
	sim.reset(42, requested)
	selected_mission_id = String(sim.mission_id)
	pending_mission_id = ""
	guide.reset(guide_enabled)
	guide.update(sim, [], int(sim.camps[0].id))
	started = true
	menu = ""
	build_kind = ""
	pending_task = ""
	attack_move = false
	dragging = false
	selection_double_click = false
	pan_active = false
	speed = 1.0
	accumulator = 0.0
	autosave_time = 0.0
	last_sim_message = ""
	group_bindings.clear()
	selected_camp = int(sim.camps[0].id)
	selected_ids.clear()
	for unit: Dictionary in sim.units:
		if unit.get("team") == "friendly" and unit.get("kind") in ["rifle", "engineer"]: selected_ids.append(unit.id)
	camera.position = (Vector2(sim.camps[0].pos) + Vector2(7, 0)) * TILE
	camera.zoom = Vector2.ONE * 1.05
	_notify("%s · 前方清场扩张，后方尸潮将在整备期后抵达。%s 查看操作。" % [String(sim.mission_name), binding_label("help_menu")])

func _save_payload() -> Dictionary:
	var state: Dictionary = sim.save_state()
	var live_groups: Dictionary = {}
	for key: Variant in group_bindings:
		var ids: Array = []
		for id: int in group_bindings[key]:
			if not sim.get_unit(id).is_empty(): ids.append(id)
		live_groups[str(key)] = ids
	var live_selection: Array = []
	for id: int in selected_ids:
		if not sim.get_unit(id).is_empty(): live_selection.append(id)
	state["ui"] = {
		"camera_x": camera.position.x, "camera_y": camera.position.y, "zoom": camera.zoom.x,
		"selected_camp": selected_camp, "selected_ids": live_selection, "groups": live_groups,
		"speed": speed, "logistics": world.show_logistics, "ranges": world.show_ranges,
		"guide": guide.save_state()
	}
	return state

func _valid_number(value: Variant, limit: float = 10000000.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= limit

func _valid_ids(value: Variant) -> bool:
	if not value is Array or value.size() > 256: return false
	for id: Variant in value:
		if not _valid_number(id) or float(id) < 1 or float(id) != floorf(float(id)): return false
	return true

func _validate_save_payload(data: Dictionary) -> bool:
	var ui_value: Variant = data.get("ui", {})
	if not ui_value is Dictionary: return false
	var ui: Dictionary = ui_value
	for key: String in ["camera_x", "camera_y", "zoom", "selected_camp", "speed"]:
		if ui.has(key) and not _valid_number(ui[key]): return false
	# Camera2D stores Vector2 components as float32: both legal endpoints can
	# round just outside their double-precision bounds during a real save.
	if ui.has("zoom") and (float(ui.zoom) < MIN_CAMERA_ZOOM - CAMERA_FLOAT_EPSILON or float(ui.zoom) > MAX_CAMERA_ZOOM + CAMERA_FLOAT_EPSILON): return false
	if ui.has("speed") and (float(ui.speed) < 1 or float(ui.speed) > 3): return false
	for key: String in ["logistics", "ranges"]:
		if ui.has(key) and not ui[key] is bool: return false
	if ui.has("selected_ids") and not _valid_ids(ui.selected_ids): return false
	var groups: Variant = ui.get("groups", {})
	if not groups is Dictionary or groups.size() > 4: return false
	for key: Variant in groups:
		if not str(key).is_valid_int() or int(key) < 1 or int(key) > 4 or not _valid_ids(groups[key]): return false
	if ui.has("guide"):
		if not ui.guide is Dictionary: return false
		var restored_guide: RefCounted = Guide.new()
		if not restored_guide.load_state(ui.guide): return false
	var candidate: RefCounted = Simulation.new()
	if not candidate.load_state(data): return false
	for id: Variant in ui.get("selected_ids", []):
		if candidate.get_unit(int(id)).is_empty(): return false
	for key: Variant in groups:
		for id: Variant in groups[key]:
			if candidate.get_unit(int(id)).is_empty(): return false
	return true

func save_campaign(manual: bool = true) -> bool:
	if not started: return false
	var path: String = SAVE_PATH if manual else AUTOSAVE_PATH
	var error: Error = save_store.write(path, _save_payload(), Callable(self, "_validate_save_payload"))
	if manual:
		_notify("战役已保存 · %s 快速读取" % binding_label("quick_load") if error == OK else "存档失败：原存档和有效备份保持不变。")
	elif error != OK:
		_notify("自动保存失败，请检查存储空间；手动存档未被覆盖。")
	return error == OK

func load_campaign(slot: String = "manual") -> bool:
	var path: String = SAVE_PATH
	if slot == "auto": path = AUTOSAVE_PATH
	elif slot == "backup": path = SAVE_PATH + ".bak"
	elif slot != "manual": return false
	var read_result: Dictionary = save_store.read(path)
	if not bool(read_result.get("ok", false)):
		_notify("无法读取存档：%s。可在菜单选择自动存档或有效备份。" % String(read_result.get("error", "数据不可用")))
		return false
	var data: Dictionary = read_result.data
	if not _validate_save_payload(data):
		_notify("无法读取存档：数据损坏或版本不兼容，当前战役保持不变。")
		return false
	var ui: Dictionary = data.get("ui", {})
	var restored_guide: RefCounted = Guide.new()
	if ui.has("guide"): restored_guide.load_state(ui.guide)
	else: restored_guide.reset(guide_enabled)
	# Every metadata field and the complete simulation have been validated before
	# touching the live run. Simulation.load_state is itself transactional.
	if not sim.load_state(data): return false
	selected_mission_id = String(sim.mission_id)
	pending_mission_id = ""
	guide = restored_guide
	started = true
	menu = ""
	build_kind = ""
	pending_task = ""
	attack_move = false
	dragging = false
	pan_active = false
	accumulator = 0.0
	autosave_time = 0.0
	last_sim_message = ""
	# JSON numbers decode as floats; IDs must retain integer semantics for
	# selection membership, groups and the guide's observed milestones.
	selected_ids.clear()
	for id: Variant in ui.get("selected_ids", []): selected_ids.append(int(id))
	group_bindings.clear()
	for key: Variant in ui.get("groups", {}):
		var group_ids: Array = []
		for id: Variant in ui.groups[key]: group_ids.append(int(id))
		group_bindings[int(key)] = group_ids
	var home_camera: Vector2 = (Vector2(sim.camps[0].pos) + Vector2(7, 0)) * TILE
	camera.position = Vector2(float(ui.get("camera_x", home_camera.x)), float(ui.get("camera_y", home_camera.y)))
	camera.zoom = Vector2.ONE * clampf(float(ui.get("zoom", 1.05)), MIN_CAMERA_ZOOM, MAX_CAMERA_ZOOM)
	selected_camp = int(ui.get("selected_camp", 0))
	if sim.get_camp(selected_camp).is_empty(): selected_camp = int(sim.camps[0].id)
	guide.update(sim, selected_ids, selected_camp)
	speed = float(ui.get("speed", 1.0))
	world.show_logistics = bool(ui.get("logistics", true))
	world.show_ranges = bool(ui.get("ranges", false))
	_notify("已恢复有效备份；可手动保存修复主存档。" if slot == "backup" else ("自动存档已恢复。" if slot == "auto" else "战役已恢复。"))
	return true

func binding_label(action: String) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty() or not events[0] is InputEventKey: return "—"
	return OS.get_keycode_string(events[0].physical_keycode)

func _notify(text: String) -> void:
	feedback = text
	feedback_left = 5.0

func _group_action_index(event: InputEventKey) -> int:
	for index: int in range(1, 5):
		if event.is_action_pressed("group_%d" % index): return index
	return 0

func _try_bind(action: String, event: InputEventKey) -> bool:
	if not command_names.has(action): return false
	var code: int = int(event.physical_keycode)
	if code == 0 or code in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META] or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		settings_feedback = "请选择一个独立按键。编队保存仍使用 Ctrl + 编队键。"
		return false
	for other: String in command_names:
		if other == action: continue
		var events: Array[InputEvent] = InputMap.action_get_events(other)
		if not events.is_empty() and events[0] is InputEventKey and int(events[0].physical_keycode) == code:
			settings_feedback = "与“%s”冲突，原绑定未改变。请换一个键或按 Esc。" % command_names[other]
			return false
	var binding: InputEventKey = InputEventKey.new()
	binding.physical_keycode = code
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, binding)
	waiting_binding = ""
	settings_feedback = "%s 已设为 %s。" % [command_names[action], binding_label(action)]
	_save_settings()
	return true

func settings_binding_page_size() -> int:
	return 6 if get_viewport_rect().size.y < 736 else 10

func _setting_number(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	return clampf(float(value), minimum, maximum) if _valid_number(value) else fallback

func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(CONFIG_PATH) != OK: return
	volume = _setting_number(config.get_value("audio", "volume", 0.6), 0.6, 0, 1)
	music_volume = _setting_number(config.get_value("audio", "music", 0.35), 0.35, 0, 1)
	effects_volume = _setting_number(config.get_value("audio", "effects", 0.7), 0.7, 0, 1)
	var mute_value: Variant = config.get_value("audio", "muted", false)
	muted = mute_value if mute_value is bool else false
	var edge_value: Variant = config.get_value("input", "edge_scroll", false)
	edge_scroll = edge_value if edge_value is bool else false
	var guide_value: Variant = config.get_value("game", "guide", true)
	guide_enabled = guide_value if guide_value is bool else true
	var full_value: Variant = config.get_value("video", "fullscreen", false)
	fullscreen = full_value if full_value is bool else false
	var configured: Variant = config.get_value("video", "configured", false)
	display_configured = configured if configured is bool else false
	var resolution: Variant = config.get_value("video", "resolution", Vector2i(1440,810))
	if resolution is Vector2i and resolution.x >= 1152 and resolution.x <= 7680 and resolution.y >= 648 and resolution.y <= 4320:
		window_resolution = resolution
	ui_scale = _setting_number(config.get_value("video", "ui_scale", 1.0), 1.0, 1.0, 1.2)
	var proposed: Dictionary = {}
	var used: Dictionary = {}
	var valid: bool = true
	for action: String in command_names:
		var current_events: Array[InputEvent] = InputMap.action_get_events(action)
		var default_code: int = int(current_events[0].physical_keycode) if not current_events.is_empty() else 0
		var saved: Variant = config.get_value("keys", action, default_code)
		if not saved is int or saved <= 0 or saved > 0x02000000 or saved in [KEY_ESCAPE, KEY_CTRL, KEY_ALT, KEY_SHIFT, KEY_META] or used.has(saved):
			valid = false
			break
		proposed[action] = saved
		used[saved] = true
	if not valid:
		_setup_inputs()
		settings_feedback = "按键配置无效或重复，已恢复默认快捷键。"
		return
	for action: String in proposed:
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = int(proposed[action])
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, key)

func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "volume", volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("audio", "muted", muted)
	config.set_value("input", "edge_scroll", edge_scroll)
	config.set_value("game", "guide", guide_enabled)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "configured", display_configured)
	config.set_value("video", "resolution", window_resolution)
	config.set_value("video", "ui_scale", ui_scale)
	for action: String in command_names:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if not events.is_empty() and events[0] is InputEventKey: config.set_value("keys", action, events[0].physical_keycode)
	var temporary: String = CONFIG_PATH + ".tmp"
	if config.save(temporary) == OK:
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(CONFIG_PATH)) != OK:
			settings_feedback = "设置保存失败，当前设置仍在本次运行生效。"

func _apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless": return
	var window: Window = get_window()
	window.content_scale_factor = ui_scale
	if display_configured:
		window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		if not fullscreen: window.size = window_resolution

func _setup_audio() -> void:
	for name_value: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(name_value) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name_value)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	sound_player.bus = "SFX"
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	if ResourceLoader.exists("res://assets/audio/canyon_ambient.wav"):
		var music: AudioStreamWAV = load("res://assets/audio/canyon_ambient.wav") as AudioStreamWAV
		music.loop_mode = AudioStreamWAV.LOOP_FORWARD
		music.loop_begin = 0
		music.loop_end = music.data.size() / 2
		music_player.stream = music
	add_child(music_player)
	_apply_audio_settings()
	if music_player.stream != null and DisplayServer.get_name() != "headless": music_player.play()

func _apply_audio_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	AudioServer.set_bus_mute(0, muted or volume <= 0.0)
	var music_bus: int = AudioServer.get_bus_index("Music")
	var effects_bus: int = AudioServer.get_bus_index("SFX")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(maxf(music_volume, 0.0001)))
		AudioServer.set_bus_mute(music_bus, music_volume <= 0.0)
	if effects_bus >= 0:
		AudioServer.set_bus_volume_db(effects_bus, linear_to_db(maxf(effects_volume, 0.0001)))
		AudioServer.set_bus_mute(effects_bus, effects_volume <= 0.0)

func guide_text(text: String) -> String:
	var result: String = text
	var names: Dictionary = {"pause":"pause_game", "build":"build_menu", "orders":"orders_menu", "production":"production_menu", "train":"train_menu"}
	for key: String in names: result = result.replace("{" + key + "}", binding_label(names[key]))
	return result

func _on_close_requested() -> void:
	if closing: return
	if started and sim.outcome == "playing": save_campaign(false)
	_quit_cleanly()

func _quit_cleanly(exit_code: int = 0) -> void:
	if closing: return
	closing = true
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	_release_audio()
	# Let the audio thread retire active WAV playbacks before engine shutdown.
	await get_tree().create_timer(0.12).timeout
	get_tree().quit(exit_code)

func _exit_tree() -> void:
	_release_audio()

func _release_audio() -> void:
	if is_instance_valid(music_player):
		music_player.stop()
		music_player.stream = null
	if is_instance_valid(sound_player):
		sound_player.stop()
		sound_player.stream = null

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
