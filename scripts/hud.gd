extends Control

const INK: Color = Color("1b292e")
const PANEL: Color = Color("22363c")
const PAPER: Color = Color("f6e6bd")
const MUTED: Color = Color("a8bdba")
const TEAL: Color = Color("64d4c5")
const GOLD: Color = Color("f0b45e")
const RED: Color = Color("e98572")

var main: Node
var font: Font
var hotspots: Array[Dictionary] = []
var map_rect: Rect2 = Rect2()
var tooltip: String = ""
var overlay_rects: Array[Rect2] = []

func _ready() -> void:
	font = load("res://assets/fonts/NotoSansCJK-Regular.ttc")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if main == null or main.sim == null or font == null: return
	hotspots.clear()
	overlay_rects.clear()
	tooltip = ""
	var screen: Vector2 = get_viewport_rect().size
	var summary: Dictionary = main.sim.get_summary()
	_draw_top(screen, summary)
	_draw_objectives(screen, summary)
	if main.started: _draw_guide(screen)
	_draw_camp_cards(screen)
	_draw_dock(screen)
	_draw_minimap(screen)
	if main.feedback_left > 0.0:
		var notification: Rect2 = Rect2(340, 82, maxf(300, screen.x - 670), 42)
		_panel(notification, Color("253d40"), TEAL)
		_text(notification.position + Vector2(14, 27), main.feedback, 16, PAPER, notification.size.x - 28)
	if main.sim.paused and main.menu.is_empty():
		_panel(Rect2(screen.x * 0.5 - 110, 138, 220, 40), INK, GOLD)
		_text(Vector2(screen.x * 0.5 - 86, 165), "战术暂停 · 空格继续", 18, GOLD)
	if not main.menu.is_empty(): _draw_menu(screen)
	elif not tooltip.is_empty() and main.capture_path.is_empty():
		var mouse: Vector2 = get_viewport().get_mouse_position()
		var pos: Vector2 = Vector2(clampf(mouse.x - 160, 16, screen.x - 376), maxf(80, mouse.y - 90))
		_panel(Rect2(pos, Vector2(360, 72)), INK, GOLD)
		_lines(pos + Vector2(12, 24), tooltip, 15, PAPER)

func _draw_top(screen: Vector2, summary: Dictionary) -> void:
	_panel(Rect2(0, 0, screen.x, 64), INK, Color("456065"))
	_text(Vector2(22, 43), "逐营突围", 29, PAPER)
	_text(Vector2(165, 42), "OUTPOST EXODUS", 12, MUTED)
	var entries: Array = [["材", "materials", TEAL], ["供", "supplies", PAPER], ["油", "fuel", GOLD], ["人", "people", TEAL]]
	for i: int in range(entries.size()):
		var x: float = 340 + i * 132
		_panel(Rect2(x, 12, 31, 36), PANEL, entries[i][2])
		_text(Vector2(x + 7, 37), entries[i][0], 17, entries[i][2])
		_text(Vector2(x + 42, 39), str(int(summary.get(entries[i][1], 0))), 23, PAPER)
	var minutes: int = int(main.sim.time) / 60
	var seconds: int = int(main.sim.time) % 60
	_text(Vector2(screen.x - 357, 39), "%02d:%02d" % [minutes, seconds], 22, MUTED)
	_button(Rect2(screen.x - 263, 13, 72, 36), "暂停" if not main.sim.paused else "继续", "pause", main.binding_label("pause_game") + "：战术暂停，可继续下达指令")
	_button(Rect2(screen.x - 181, 13, 68, 36), "×%d" % int(main.speed), "speed", "切换游戏速度；%s / %s" % [main.binding_label("speed_up"), main.binding_label("speed_down")])
	_button(Rect2(screen.x - 103, 13, 82, 36), "菜单", "menu", "设置、帮助和战役存档")

func _draw_objectives(_screen: Vector2, summary: Dictionary) -> void:
	_panel(Rect2(18, 82, 300, 222), Color(PANEL, 0.95), Color("52716d"))
	_text(Vector2(34, 111), "01  峡谷突围", 22, PAPER)
	_text(Vector2(34, 139), "指挥车 + 至少4人抵达东部出口", 14, MUTED)
	var phase_text: Dictionary = {"preparation": "整备 · 小队开路", "advance": "推进 · 建立补给线", "evacuation": "撤守 · 争取最后时间"}
	_text(Vector2(34, 171), phase_text.get(main.sim.phase, "推进战役"), 18, TEAL)
	var progress: float = float(summary.get("exit_progress", main.sim.exit_progress))
	_text(Vector2(34, 202), "出口工程", 15, MUTED)
	_bar(Rect2(34, 214, 266, 10), progress, TEAL)
	_text(Vector2(245, 202), "%d%%" % int(progress * 100), 16, PAPER)
	_text(Vector2(34, 240), "维修需 140材 / 45油 / 30供 · 6电", 12, MUTED)
	var eta: float = float(summary.get("pursuit_eta", main.sim.pursuit_eta))
	_text(Vector2(34, 263), "后方压力", 15, MUTED)
	_text(Vector2(139, 264), "整备中" if main.sim.phase == "preparation" else ("约 %d 秒" % int(maxf(eta, 0))), 18, GOLD)
	_text(Vector2(34, 286), "%s 帮助 · %s 保存 / %s 读取" % [main.binding_label("help_menu"), main.binding_label("quick_save"), main.binding_label("quick_load")], 13, MUTED)
	var selection_text: String = "未选择单位 · 左键或拖框选择"
	if not main.selected_ids.is_empty(): selection_text = "已选择 %d 人 / 辆 · 右键下令" % main.selected_ids.size()
	_panel(Rect2(18, 318, 300, 64), Color(INK, 0.92), Color("456065"))
	_text(Vector2(33, 346), selection_text, 15, PAPER)
	_text(Vector2(33, 369), "%s 攻击 · %s 切队 · Ctrl+编队键保存" % [main.binding_label("attack_move"), main.binding_label("next_squad")], 12, MUTED)
	if not main.build_kind.is_empty():
		_panel(Rect2(18, 397, 300, 75), PANEL, GOLD)
		var names: Dictionary = {"road":"道路", "camp":"前哨营地", "generator":"发电机", "workshop":"工坊", "tower":"岗哨炮塔", "barricade":"路障"}
		_text(Vector2(33, 426), "施工：" + names.get(main.build_kind, main.build_kind), 18, GOLD)
		_text(Vector2(33, 452), "左键放置 · 右键取消", 14, MUTED)

func _draw_camp_cards(screen: Vector2) -> void:
	var y: float = 82
	for camp: Dictionary in main.sim.camps:
		if y > screen.y - 400: break
		var rect: Rect2 = Rect2(screen.x - 268, y, 250, 91)
		var chosen: bool = int(camp.get("id", -1)) == main.selected_camp
		_panel(rect, Color(PANEL, 0.95), TEAL if chosen else Color("456065"))
		var state: String = String(camp.get("state", "active"))
		var states: Dictionary = {"active":"运作", "packing":"撤收中", "abandoned":"已撤空"}
		_text(rect.position + Vector2(12, 27), String(camp.get("name", "驻点")), 17, PAPER)
		_text(rect.position + Vector2(172, 26), states.get(state, state), 13, GOLD if state == "packing" else MUTED)
		_text(rect.position + Vector2(12, 52), "材 %d  供 %d  油 %d" % [int(camp.get("materials", 0)), int(camp.get("supplies", 0)), int(camp.get("fuel", 0))], 14, MUTED)
		var capacity: float = float(camp.get("power_capacity", 0.0))
		_bar(Rect2(rect.position + Vector2(12, 66), Vector2(224, 8)), float(camp.get("power_used", 0.0)) / maxf(capacity, 1), GOLD)
		_text(rect.position + Vector2(12, 85), "供能 %d / %d" % [int(camp.get("power_used", 0)), int(capacity)], 11, GOLD)
		hotspots.append({"rect":rect, "action":"camp:%d" % int(camp.get("id", 0)), "tip":"定位此驻点，并选择生产与撤收操作"})
		y += 102

func _draw_dock(screen: Vector2) -> void:
	var top: float = screen.y - 190
	_panel(Rect2(0, top, screen.x, 190), INK, Color("52716d"))
	_button(Rect2(18, top + 12, 125, 33), "建设 [%s]" % main.binding_label("build_menu"), "tab:build", "道路、营地、工坊与防守设施", main.current_tab == "build")
	_button(Rect2(153, top + 12, 125, 33), "指挥 [%s]" % main.binding_label("orders_menu"), "tab:orders", "给所选小队委派任务", main.current_tab == "orders")
	_button(Rect2(288, top + 12, 125, 33), "生产 [%s]" % main.binding_label("production_menu"), "tab:production", "管理当前驻点生产与供能", main.current_tab == "production")
	_button(Rect2(423, top + 12, 125, 33), "训练 [%s]" % main.binding_label("train_menu"), "tab:training", "扩充小队、工程与运输能力", main.current_tab == "training")
	_button(Rect2(570, top + 12, 105, 33), "补给线", "logistics", "显示道路与本地能源连接", main.world.show_logistics)
	_button(Rect2(685, top + 12, 105, 33), "范围", "ranges", "显示供电与防守覆盖范围", main.world.show_ranges)
	var width: float = minf(screen.x - 302, 1030)
	if main.current_tab == "build":
		var items: Array = [["road", "道路", "2 材 / 格", "连通工地和仓库，让补给车通行。"], ["camp", "前哨营地", "50 材 / 10 供", "建立新的驻点，接续推进和撤收。"], ["generator", "发电机", "30 材 / 5 油", "为本地生产和自动炮塔供能。"], ["workshop", "工坊", "40 建材", "将当地资源加工成建材或补给。"], ["tower", "岗哨炮塔", "35 材 / 5 供", "自动防守，保护坡道与运输线。"], ["barricade", "临时路障", "20 建材", "延缓尸群；无法永久挡住追兵。"]]
		items.append(["barracks", "军营", "60 材 / 20 供", "消耗本地电力，训练步枪兵与工程师。"])
		var card_width: float = (width - 56) / 7.0
		for i: int in range(items.size()):
			var rect: Rect2 = Rect2(18 + i * (card_width + 6), top + 57, card_width, 112)
			_button(rect, "", "build:" + items[i][0], items[i][3], main.build_kind == items[i][0])
			_icon(rect.position + Vector2(card_width * 0.5, 31), i, GOLD if main.build_kind == items[i][0] else TEAL)
			_text(rect.position + Vector2(11, 75), items[i][1], 17, PAPER)
			_text(rect.position + Vector2(11, 98), items[i][2], 12, MUTED)
	elif main.current_tab == "orders":
		var items: Array = [["task:clear","清理并搜刮","向当前驻点区域派队清理"], ["task:escort","护送补给","保护驻点与运输队"], ["task:guard","驻守关口","持续守备指定区域"], ["evacuate","撤收驻点","打包人员和设备，运输至前方"], ["seal:0","封锁后关","先让友军通过，再拖延追兵"], ["seal:1","封锁前关","争取出口施工和撤离时间"]]
		var current_camp: Dictionary = main.sim.get_camp(main.selected_camp)
		if current_camp.get("state", "") == "packing":
			items[3] = ["evacuate", "紧急弃营", "留下未装车物资，人员立即撤离；在途货物继续运输。"]
		var card_width: float = (width - 50) / 6.0
		for i: int in range(items.size()):
			_button(Rect2(18 + i * (card_width + 6), top + 62, card_width, 96), items[i][1], items[i][0], items[i][2], false, i >= 3)
	elif main.current_tab == "production":
		var camp: Dictionary = main.sim.get_camp(main.selected_camp)
		var name_text: String = String(camp.get("name", "未选择驻点"))
		_text(Vector2(20, top + 79), name_text + " · 生产队列", 18, PAPER)
		var recipe: String = String(camp.get("recipe", "idle"))
		var recipes: Array = [["materials", "加工建材"], ["supplies", "生产补给"], ["fuel", "提炼燃料"], ["idle", "暂停生产"]]
		for i: int in range(recipes.size()):
			_button(Rect2(20 + i * 136, top + 95, 125, 58), recipes[i][1], "recipe:" + recipes[i][0], "驻点需要相应资源来源、工坊与本地供电。", recipe == recipes[i][0])
		var priority: String = String(camp.get("priority", "production"))
		var priorities: Array = [["production","生产优先"], ["defense","防守优先"], ["evacuation","撤离优先"]]
		for i: int in range(priorities.size()):
			_button(Rect2(590 + i * 130, top + 95, 120, 58), priorities[i][1], "priority:" + priorities[i][0], "供电不足时，优先保障选定任务。", priority == priorities[i][0])
		_text(Vector2(590, top + 79), "供能预设", 16, GOLD)
		_text(Vector2(20, top + 178), "原料：废料 %d  /  原油 %d" % [int(camp.get("salvage", 0)), int(camp.get("crude", 0))], 12, MUTED)
	elif main.current_tab == "training":
		var camp: Dictionary = main.sim.get_camp(main.selected_camp)
		var recruits: Array = [["rifle","步枪兵","供能军营"], ["engineer","工程师","供能军营"], ["worker","工人","本地发电"], ["truck","运输车","供能工坊"]]
		for i: int in range(recruits.size()):
			var rect: Rect2 = Rect2(20 + i * 150, top + 61, 139, 103)
			_button(rect, "", "recruit:" + recruits[i][0], "加入当前驻点的训练队列；需要资源、时间和能源。")
			_text(rect.position + Vector2(14, 37), recruits[i][1], 20, PAPER)
			_text(rect.position + Vector2(14, 68), recruits[i][2], 14, GOLD)
		var queue: Array = camp.get("recruit_queue", [])
		_text(Vector2(640, top + 84), "训练队列  %d" % queue.size(), 20, TEAL)
		if queue.is_empty():
			_text(Vector2(640, top + 118), "在本地设施完成后自动集结。", 14, MUTED)
		else:
			var entry: Dictionary = queue[0]
			_bar(Rect2(640, top + 100, 320, 10), float(entry.get("progress", 0.0)), TEAL)
			_text(Vector2(640, top + 131), "进度 %d%% · %s" % [int(float(entry.get("progress", 0.0))*100), String(camp.get("recruit_status", "training"))], 14, GOLD)
		_text(Vector2(640, top + 147), "扩军后用 Ctrl+编队键 保存编队。", 14, MUTED)

func _draw_minimap(screen: Vector2) -> void:
	map_rect = Rect2(screen.x - 274, screen.y - 176, 256, 148)
	_panel(map_rect.grow(4), PANEL, TEAL)
	var map_size: Vector2i = main.sim.map_size
	var scale_value: Vector2 = map_rect.size / Vector2(map_size)
	for y: int in range(map_size.y):
		for x: int in range(map_size.x):
			var height: int = int(main.sim.terrain[y][x])
			var color: Color = Color("ae9567") if height == 0 else (Color("d2b47c") if height > 0 else Color("374b53"))
			draw_rect(Rect2(map_rect.position + Vector2(x, y) * scale_value, scale_value + Vector2(0.3, 0.3)), color)
	for road: Variant in main.sim.roads:
		draw_rect(Rect2(map_rect.position + Vector2(road) * scale_value, scale_value + Vector2.ONE), Color("eddbb0"))
	for camp: Dictionary in main.sim.camps:
		var p: Vector2 = camp.get("pos", Vector2.ZERO)
		draw_circle(map_rect.position + p * scale_value, 4.0, TEAL if camp.get("state", "") != "abandoned" else MUTED)
	for unit: Dictionary in main.sim.units:
		var p: Vector2 = unit.get("pos", Vector2.ZERO)
		draw_circle(map_rect.position + p * scale_value, 1.5, RED if unit.get("team") == "enemy" else Color("f8f1d4"))
	var pursuit: float = clampf(float(main.sim.pursuit_x), 0, map_size.x)
	draw_line(map_rect.position + Vector2(pursuit * scale_value.x, 0), map_rect.position + Vector2(pursuit * scale_value.x, map_rect.size.y), RED, 2)
	var view_size: Vector2 = get_viewport_rect().size / main.camera.zoom / 48.0
	var camera_tile: Vector2 = main.camera.position / 48.0
	var camera_rect: Rect2 = Rect2(map_rect.position + (camera_tile - view_size * 0.5) * scale_value, view_size * scale_value)
	draw_rect(camera_rect.intersection(map_rect), PAPER, false, 1.5)
	_text(map_rect.position + Vector2(7, 18), "战略地图", 12, INK)
	hotspots.append({"rect":map_rect, "action":"minimap", "tip":"左键移动镜头，右键向此处下令"})

func _draw_menu(screen: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.08, 0.09, 0.78))
	hotspots.clear()
	if main.menu == "restart":
		var confirm: Rect2 = Rect2(screen*0.5-Vector2(360,215), Vector2(720,430))
		_panel(confirm, PANEL, GOLD)
		_text(confirm.position+Vector2(32,58), "重新开始本关？", 32, GOLD)
		var lines: Array[String] = _wrap_text("确认后会重置本关队伍、建筑和资源。系统会先把当前进度保存到独立的自动存档，手动存档与备份保持不变。需要长期保留这一局时，请先取消并手动保存。", 656, 19)
		for index: int in range(lines.size()): _text(confirm.position+Vector2(32,112+index*30), lines[index], 19, PAPER)
		_button(Rect2(confirm.position+Vector2(32,320),Vector2(314,54)),"取消，继续当前战役","resume","")
		_button(Rect2(confirm.position+Vector2(374,320),Vector2(314,54)),"确认重新开始","restart_confirm","先创建自动存档，成功后才重置",false,true)
		return
	if main.menu == "settings":
		_draw_settings(screen)
		return
	if main.menu == "guide":
		_draw_guide_dialog(screen)
		return
	if main.menu == "help":
		_draw_help(screen)
		return
	var panel: Rect2 = Rect2(screen.x * 0.5 - 325, screen.y * 0.5 - 302, 650, 604)
	_panel(panel, Color("20383b"), TEAL)
	_text(panel.position + Vector2(46, 91), "逐营突围", 56, PAPER)
	_text(panel.position + Vector2(48, 124), "O U T P O S T   E X O D U S", 17, TEAL)
	var subtitle: String = "向前建设，向后撤守。把人和希望带出峡谷。"
	if main.menu == "victory": subtitle = "突围成功 · 指挥车与 %d 名幸存者抵达出口。" % main.sim.evacuated
	elif main.menu == "defeat": subtitle = String(main.sim.messages.back()) if not main.sim.messages.is_empty() else "战役失败，可读取存档或重新开始。"
	elif main.menu == "pause": subtitle = "战役已暂停 · 调整计划后继续推进。"
	_text(panel.position + Vector2(48, 176), subtitle, 18, MUTED)
	var primary: Array = ["继续战役", "resume"] if main.menu == "pause" else ["开始峡谷战役" if main.menu == "title" else "重新开始战役", "new"]
	_button(Rect2(panel.position + Vector2(48, 211), Vector2(554, 46)), primary[0], primary[1], "")
	var buttons: Array = []
	if main.menu == "pause":
		buttons.append(["保存当前战役", "save", true])
		buttons.append(["重新开始", "new", true])
	buttons.append(["读取手动存档", "load", FileAccess.file_exists(main.SAVE_PATH)])
	buttons.append(["读取自动存档", "load_auto", FileAccess.file_exists(main.AUTOSAVE_PATH)])
	buttons.append(["恢复手动备份", "load_backup", FileAccess.file_exists(main.SAVE_PATH + ".bak")])
	buttons.append(["操作与目标", "help", true])
	buttons.append(["设置与快捷键", "settings", true])
	if main.menu == "pause": buttons.append(["返回标题", "title", true])
	buttons.append(["退出游戏", "quit", true])
	for index: int in range(buttons.size()):
		var rect: Rect2 = Rect2(panel.position + Vector2(48 + (index % 2) * 284, 273 + (index / 2) * 51), Vector2(270, 42))
		_button(rect, buttons[index][0], buttons[index][1], "尚无此类存档" if not buttons[index][2] else "", false, false, buttons[index][2])
	_text(panel.position + Vector2(48, 579), "开发中版本 · 独立战役 · 2D 卡通生存策略", 13, MUTED)


func _draw_settings(screen: Vector2) -> void:
	var panel: Rect2 = Rect2(screen.x * 0.5 - 410, screen.y * 0.5 - 352, 820, 704)
	_panel(panel, PANEL, TEAL)
	_text(panel.position + Vector2(30, 48), "设置与按键", 30, PAPER)
	_button(Rect2(panel.position + Vector2(30, 68), Vector2(365, 38)), "快捷键", "settings_tab:controls", "所有主要操作均可重绑", main.settings_tab == "controls")
	_button(Rect2(panel.position + Vector2(415, 68), Vector2(375, 38)), "显示与声音", "settings_tab:display", "分辨率、缩放、独立音量和静音", main.settings_tab == "display")
	if main.settings_tab == "controls":
		_button(Rect2(panel.position + Vector2(30, 122), Vector2(350, 42)), "主音量  %d%%" % int(main.volume * 100), "volume", "点击循环切换主音量")
		_button(Rect2(panel.position + Vector2(400, 122), Vector2(390, 42)), "边缘滚屏：" + ("开" if main.edge_scroll else "关"), "edge_scroll", "靠近屏幕边缘时移动镜头")
		var actions: Array = main.command_names.keys()
		var start: int = main.settings_page * 10
		for i: int in range(start, mini(actions.size(), start + 10)):
			var action: String = actions[i]
			var relative: int = i - start
			_button(Rect2(panel.position + Vector2(30 + (relative % 2) * 395, 186 + (relative / 2) * 55), Vector2(365, 44)), main.command_names[action] + "    " + main.binding_label(action), "bind:" + action, "点击后按新按键；冲突会提示且保留原绑定。")
		_button(Rect2(panel.position + Vector2(30, 479), Vector2(180, 38)), "上一页", "bindings_prev", "", false, false, main.settings_page > 0)
		_text(panel.position + Vector2(228, 505), "%d / %d" % [main.settings_page+1, ceili(actions.size()/10.0)], 17, MUTED)
		_button(Rect2(panel.position + Vector2(335, 479), Vector2(180, 38)), "下一页", "bindings_next", "", false, false, start + 10 < actions.size())
		_button(Rect2(panel.position + Vector2(545, 479), Vector2(245, 38)), "恢复默认按键", "bindings_reset", "会替换所有自定义快捷键")
		var feedback: String = main.settings_feedback
		if not main.waiting_binding.is_empty() and feedback.is_empty(): feedback = "请按新按键，Esc 取消。"
		var lines: Array[String] = _wrap_text(feedback, 750, 16)
		for i: int in range(mini(3, lines.size())): _text(panel.position + Vector2(30, 548+i*23), lines[i], 16, GOLD)
	else:
		_button(Rect2(panel.position + Vector2(30, 128), Vector2(365, 48)), "主音量  %d%%" % int(main.volume*100), "volume", "主音量控制所有声音")
		_button(Rect2(panel.position + Vector2(415, 128), Vector2(375, 48)), "静音：" + ("开" if main.muted else "关"), "mute", "静音不改变各声道的音量设置")
		_button(Rect2(panel.position + Vector2(30, 192), Vector2(365, 48)), "音乐  %d%%" % int(main.music_volume*100), "music_volume", "独立调整营地与远行背景音乐")
		_button(Rect2(panel.position + Vector2(415, 192), Vector2(375, 48)), "音效  %d%%" % int(main.effects_volume*100), "effects_volume", "独立调整界面和战斗反馈音")
		_button(Rect2(panel.position + Vector2(30, 268), Vector2(365, 48)), "显示模式：" + ("全屏" if main.fullscreen else "窗口"), "fullscreen", "切换全屏；窗口分辨率会保留")
		_button(Rect2(panel.position + Vector2(415, 268), Vector2(375, 48)), "窗口 %d × %d" % [main.window_resolution.x,main.window_resolution.y], "resolution", "循环选择窗口分辨率")
		_button(Rect2(panel.position + Vector2(30, 332), Vector2(365, 48)), "界面倍率 %d%%" % int(round(main.ui_scale*100)), "ui_scale", "100% / 110% / 120%，地图仍可独立缩放")
		_button(Rect2(panel.position + Vector2(415, 332), Vector2(375, 48)), "边缘滚屏：" + ("开" if main.edge_scroll else "关"), "edge_scroll", "可用 WASD 或中键拖动替代")
		_button(Rect2(panel.position + Vector2(30, 414), Vector2(760, 48)), "战役引导：" + ("显示" if bool(main.guide.get_hint().get("visible",false)) else "隐藏"), "guide_toggle", "可随时隐藏或恢复，不限制任务路线")
		_text(panel.position + Vector2(30, 510), "设置自动保存在本机，不随战役存档覆盖。", 17, MUTED)
		_text(panel.position + Vector2(30, 542), "音量点击循环调整；独立音乐和音效声道立即生效。", 15, MUTED)
	_button(Rect2(panel.position + Vector2(30, 627), Vector2(760, 46)), "返回", "back", "")

func _wrap_text(text: String, width: float, size_value: int) -> Array[String]:
	var result: Array[String] = []
	var line: String = ""
	for character: String in text:
		if character == "\n" or font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,size_value).x > width:
			result.append(line)
			line = "" if character == "\n" else character
		else: line += character
	if not line.is_empty(): result.append(line)
	return result

func _draw_guide(screen: Vector2) -> void:
	var hint: Dictionary = main.guide.get_hint()
	if not bool(hint.get("visible", false)):
		_button(Rect2(18,397,300,34), "显示战役引导", "guide_toggle", "提示会跟随当前真实战役进度")
		return
	var height: float = clampf(screen.y - 599, 145, 248)
	var rect: Rect2 = Rect2(18,397,300,height)
	overlay_rects.append(rect)
	_panel(rect, Color(PANEL,0.97), GOLD)
	_text(rect.position+Vector2(12,27), "%d/%d  %s" % [int(hint.get("step",1)),int(hint.get("total",11)),String(hint.get("title","当前目标"))],15,GOLD,276)
	_bar(Rect2(rect.position+Vector2(12,39),Vector2(276,4)),float(hint.get("step",1))/float(hint.get("total",11)),TEAL)
	var lines: Array[String] = _wrap_text(main.guide_text(String(hint.get("text",""))),276,14)
	var limit: int = clampi(int((height-112)/20),2,6)
	for i: int in range(mini(limit,lines.size())):
		var line: String = lines[i]+("…" if i == limit-1 and lines.size()>limit else "")
		_text(rect.position+Vector2(12,67+i*20),line,14,PAPER)
	var bottom: float = rect.end.y-38
	_button(Rect2(30,bottom,84,27),"定位","guide_focus","只移动镜头，不替你下令",false,false,Vector2(hint.get("target",Vector2(-1,-1))).x>=0)
	_button(Rect2(124,bottom,84,27),"展开","guide_more","暂停查看完整提示")
	_button(Rect2(218,bottom,88,27),"隐藏","guide_toggle","之后可从这里或设置中恢复")

func _draw_guide_dialog(screen: Vector2) -> void:
	var panel: Rect2 = Rect2(screen*0.5-Vector2(420,280),Vector2(840,560))
	_panel(panel,PANEL,GOLD)
	var hint: Dictionary = main.guide.get_hint()
	_text(panel.position+Vector2(30,49),String(hint.get("title","战役引导")),28,GOLD)
	var lines: Array[String] = _wrap_text(main.guide_text(String(hint.get("text",""))),780,20)
	for i: int in range(mini(lines.size(),10)): _text(panel.position+Vector2(30,101+i*31),lines[i],20,PAPER)
	_text(panel.position+Vector2(30,440),"引导不会改变任务状态，你可以自由选择推进与撤收方案。",16,MUTED)
	_button(Rect2(panel.position+Vector2(30,482),Vector2(370,46)),"定位并返回战役","guide_focus","",false,false,Vector2(hint.get("target",Vector2(-1,-1))).x>=0)
	_button(Rect2(panel.position+Vector2(420,482),Vector2(390,46)),"返回战役","resume","")

func _draw_help(screen: Vector2) -> void:
	var panel: Rect2 = Rect2(screen.x * 0.5 - 430, screen.y * 0.5 - 325, 860, 650)
	_panel(panel, PANEL, TEAL)
	_text(panel.position + Vector2(34, 48), "峡谷突围 · 指挥手册", 30, PAPER)
	var lines: Array[String] = [
		"目标：修复东侧出口，使指挥车与至少四名幸存者抵达。",
		"1. 拖框选择小队，右键移动；%s 后左键执行攻击移动。" % main.binding_label("attack_move"),
		"2. 清理北侧矿场、南侧燃料库，搜刮补给并建立道路。",
		"3. %s 建设：铺路、前哨、发电机、工坊、军营和防守设施。" % main.binding_label("build_menu"),
		"4. %s 生产：选择配方与供能优先级。燃料维持当地发电。" % main.binding_label("production_menu"),
		"5. %s 指挥：委派驻守、护送与搜刮，或撤收当前营地。" % main.binding_label("orders_menu"),
		"   %s 训练：招募小队、工程师、工人与运输车，需要本地供能。" % main.binding_label("train_menu"),
		"6. 后方追兵持续逼近。先运走人员设备，再封关争取时间。",
		"7. 派工程师到东侧出口施工，保护最后的补给与撤离路线。",
		"镜头：%s/%s/%s/%s 或中键拖动，滚轮缩放，小地图定位。" % [main.binding_label("camera_up"),main.binding_label("camera_left"),main.binding_label("camera_down"),main.binding_label("camera_right")],
		"编队：%s / %s / %s / %s 选择，配合 Ctrl 保存；%s 切队，%s 定位。" % [main.binding_label("group_1"),main.binding_label("group_2"),main.binding_label("group_3"),main.binding_label("group_4"),main.binding_label("next_squad"),main.binding_label("focus_command")],
		"%s 暂停；%s 保存，%s 读取；%s 补给线，%s 范围。" % [main.binding_label("pause_game"),main.binding_label("quick_save"),main.binding_label("quick_load"),main.binding_label("logistics_toggle"),main.binding_label("ranges_toggle")]
	]
	for i: int in range(lines.size()):
		_text(panel.position + Vector2(34, 91 + i * 41), lines[i], 17, PAPER if i == 0 else MUTED)
	_button(Rect2(panel.position + Vector2(34, 577), Vector2(792, 44)), "明白，返回", "back", "")

func handle_mouse(event: InputEventMouseButton) -> bool:
	var point: Vector2 = event.position
	if event.pressed:
		for i: int in range(hotspots.size() - 1, -1, -1):
			var item: Dictionary = hotspots[i]
			var rect: Rect2 = item.rect
			if not rect.has_point(point): continue
			if item.action == "minimap":
				var tile: Vector2 = (point - map_rect.position) / map_rect.size * Vector2(main.sim.map_size)
				if event.button_index == MOUSE_BUTTON_LEFT: main.camera.position = tile * 48.0
				elif event.button_index == MOUSE_BUTTON_RIGHT: main._issue_context(tile)
			elif event.button_index == MOUSE_BUTTON_LEFT: main.ui_action(item.action)
			return true
	for rect: Rect2 in overlay_rects:
		if rect.has_point(point): return true
	var screen: Vector2 = get_viewport_rect().size
	return not main.menu.is_empty() or point.y < 64 or point.y > screen.y - 190 or Rect2(18, 82, 300, 305).has_point(point) or Rect2(screen.x - 268, 82, 250, maxf(0, screen.y - 482)).has_point(point)

func _panel(rect: Rect2, fill: Color, border: Color) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	draw_style_box(style, rect)

func _button(rect: Rect2, label: String, action: String, tip: String, active: bool = false, danger: bool = false, enabled: bool = true) -> void:
	var over: bool = enabled and rect.has_point(get_viewport().get_mouse_position()) and main.capture_path.is_empty()
	var border: Color = Color("34464b") if not enabled else (GOLD if active else (RED if danger else Color("4d6c70")))
	_panel(rect, Color("35555a") if over else (Color("3a4840") if active else PANEL), border)
	if not label.is_empty():
		var size_value: int = 17 if rect.size.x > 130 else 15
		var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x
		_text(rect.position + Vector2(maxf(9, (rect.size.x - text_width) * 0.5), rect.size.y * 0.5 + size_value * 0.38), label, size_value, MUTED if not enabled else (GOLD if active else PAPER))
	if enabled: hotspots.append({"rect":rect, "action":action, "tip":tip})
	if over and not tip.is_empty(): tooltip = tip

func _text(pos: Vector2, text: String, size_value: int = 18, color: Color = PAPER, width: float = -1.0) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, size_value, color)

func _lines(pos: Vector2, text: String, size_value: int, color: Color) -> void:
	var lines: Array[String] = []
	var current: String = ""
	for character: String in text:
		if character == "\n" or font.get_string_size(current + character, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x > 332:
			lines.append(current)
			current = "" if character == "\n" else character
		else:
			current += character
	if not current.is_empty(): lines.append(current)
	for i: int in range(mini(lines.size(), 2)): _text(pos + Vector2(0, i * (size_value + 6)), lines[i], size_value, color)

func _bar(rect: Rect2, amount: float, color: Color) -> void:
	draw_rect(rect, Color("10252b"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(amount, 0, 1), rect.size.y)), color)

func _icon(center: Vector2, index: int, color: Color) -> void:
	match index:
		0:
			draw_line(center + Vector2(-28, 6), center + Vector2(28, -6), color, 15)
			draw_line(center + Vector2(-28, 6), center + Vector2(28, -6), INK, 2)
		1:
			draw_colored_polygon(PackedVector2Array([center + Vector2(-25, 17), center + Vector2(0, -21), center + Vector2(25, 17)]), color)
			draw_line(center + Vector2(0, -13), center + Vector2(0, 16), INK, 3)
		2:
			draw_rect(Rect2(center - Vector2(25, 17), Vector2(50, 34)), color)
			_text(center + Vector2(-9, 8), "电", 20, INK)
		3:
			draw_rect(Rect2(center - Vector2(23, 9), Vector2(46, 27)), color)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-29,-8),center + Vector2(0,-25),center + Vector2(29,-8)]), color)
		4:
			draw_line(center + Vector2(-12, 21), center + Vector2(-9, -17), color, 5)
			draw_line(center + Vector2(12, 21), center + Vector2(9, -17), color, 5)
			draw_rect(Rect2(center + Vector2(-20,-19), Vector2(40,12)), color)
		5:
			for x: int in range(-2,3): draw_line(center + Vector2(x*11,17), center + Vector2(x*11-5,-13), color, 7)
			draw_line(center + Vector2(-29,3), center + Vector2(27,3), INK, 5)
		6:
			draw_rect(Rect2(center + Vector2(-24,-4), Vector2(48,23)), color)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-29,-4),center + Vector2(0,-23),center + Vector2(29,-4)]), color)
			draw_line(center + Vector2(15,-17), center + Vector2(15,-34), PAPER, 3)
