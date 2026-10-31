extends Control

const Catalog = preload("res://scripts/campaign_catalog.gd")
const Cartoon = preload("res://scripts/cartoon_canvas.gd")
const WorldView = preload("res://scripts/world_view.gd")
const CommandTruckReadout = preload("res://scripts/command_truck_readout.gd")

const INK: Color = Color("1b292e")
const PANEL: Color = Color("22363c")
const PAPER: Color = Color("f6e6bd")
const MUTED: Color = Color("a8bdba")
const TEAL: Color = Color("64d4c5")
const GOLD: Color = Color("f0b45e")
const RED: Color = Color("e98572")

var main: Node
var font: Font:
	set(value):
		if font == value: return
		if font != null and font.changed.is_connected(_clear_text_layouts):
			font.changed.disconnect(_clear_text_layouts)
		font = value
		_clear_text_layouts()
		if font != null: font.changed.connect(_clear_text_layouts)
var hotspots: Array[Dictionary] = []
var map_rect: Rect2 = Rect2()
var training_queue_rect: Rect2 = Rect2()
var tooltip: String = ""
var _camp_tooltip: bool = false
var overlay_rects: Array[Rect2] = []
var _campaign_previews: Dictionary = {}
var _building_atlas: Texture2D
# Cache only pure presentation work. Game state, geometry, hover and hotspots
# are still read and drawn every frame; no simulation or input invalidation is
# needed. Bounds also cover arbitrarily many guide texts and window sizes.
const TEXT_LAYOUT_CACHE_LIMIT: int = 256
const PANEL_STYLE_CACHE_LIMIT: int = 64
var _text_layouts: Dictionary = {}
var _panel_styles: Dictionary = {}

func _ready() -> void:
	font = load("res://assets/fonts/NotoSansCJK-Regular.ttc")
	if ResourceLoader.exists(WorldView.BUILDING_ATLAS_PATH):
		_building_atlas = load(WorldView.BUILDING_ATLAS_PATH) as Texture2D
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if main == null or main.sim == null or font == null: return
	hotspots.clear()
	overlay_rects.clear()
	tooltip = ""
	_camp_tooltip = false
	training_queue_rect = Rect2()
	var screen: Vector2 = get_viewport_rect().size
	var summary: Dictionary = main.sim.get_summary()
	_draw_top(screen, summary)
	_draw_objectives(screen, summary)
	if main.started: _draw_guide(screen)
	_draw_camp_cards(screen)
	if main.menu.is_empty() and main.build_kind.is_empty() and not main.construction_readout.is_empty(): _draw_construction_details(screen)
	_draw_dock(screen)
	_draw_minimap(screen)
	if main.feedback_left > 0.0:
		var notification: Rect2 = Rect2(340, 82, maxf(300, screen.x - 670), 42)
		_panel(notification, Color("253d40"), TEAL)
		_text(notification.position + Vector2(14, 27), main.feedback, 16, PAPER, notification.size.x - 28)
	if _pause_banner_visible():
		var pause_text: String = _pause_banner_text()
		var pause_width: float = maxf(220, font.get_string_size(pause_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 32)
		var pause_left: float = (screen.x - pause_width) * 0.5
		_panel(Rect2(pause_left, 138, pause_width, 40), INK, GOLD)
		_text(Vector2(pause_left + 16, 165), pause_text, 18, GOLD)
	if not main.menu.is_empty(): _draw_menu(screen)
	elif not tooltip.is_empty() and main.capture_path.is_empty():
		var mouse: Vector2 = get_viewport().get_mouse_position()
		if _camp_tooltip:
			var lines: Array[String] = _wrap_text(tooltip, 332, 15, false)
			var maximum_lines: int = maxi(2, floori((screen.y - 106) / 21.0))
			var count: int = mini(lines.size(), maximum_lines)
			var height: float = count * 21.0 + 24.0
			var pos: Vector2 = Vector2(clampf(mouse.x - 360, 16, screen.x - 376), clampf(mouse.y - height - 10, 72, screen.y - height - 10))
			var rect: Rect2 = Rect2(pos, Vector2(360, height))
			_panel(rect, INK, GOLD)
			for index: int in range(count):
				_text(pos + Vector2(12, 25 + index * 21), lines[index] + ("…" if index == count - 1 and lines.size() > count else ""), 15, PAPER)
			overlay_rects.append(rect)
			return
		var pos: Vector2 = Vector2(clampf(mouse.x - 160, 16, screen.x - 376), maxf(80, mouse.y - 90))
		_panel(Rect2(pos, Vector2(360, 72)), INK, GOLD)
		_lines(pos + Vector2(12, 24), tooltip, 15, PAPER)

func _pause_banner_text() -> String:
	return "战术暂停 · %s 继续" % main.binding_label("pause_game")

func _pause_banner_visible() -> bool:
	# Project details already contain pause state; the central banner would cover
	# their progress/source rows in compact logical viewports.
	return main.sim.paused and main.menu.is_empty() and main.build_kind.is_empty() and main.construction_readout.is_empty()

func _compact_tab_tip() -> String:
	var status: String = "战术已暂停" if main.sim.paused else "地图继续运行"
	var action: String = "继续" if main.sim.paused else "暂停"
	return "切换面板或显示范围；%s\n可用 %s %s" % [status, main.binding_label("pause_game"), action]

func _draw_top(screen: Vector2, summary: Dictionary) -> void:
	_panel(Rect2(0, 0, screen.x, 64), INK, Color("456065"))
	var compact: bool = screen.x < 1280
	_text(Vector2(22, 43), "逐营突围", 24 if compact else 29, PAPER)
	if not compact: _text(Vector2(165, 42), "OUTPOST EXODUS", 12, MUTED)
	var entries: Array = [["材", "materials", TEAL], ["供", "supplies", PAPER], ["油", "fuel", GOLD], ["人", "people", TEAL]]
	for i: int in range(entries.size()):
		var spacing: float = minf(120, (screen.x - 560) / 4.0) if compact else 132.0
		var x: float = (160 if compact else 340) + i * spacing
		_panel(Rect2(x, 12, 27 if compact else 31, 36), PANEL, entries[i][2])
		_text(Vector2(x + 6, 37), entries[i][0], 15 if compact else 17, entries[i][2])
		_text(Vector2(x + (35 if compact else 42), 39), str(int(summary.get(entries[i][1], 0))), 20 if compact else 23, PAPER)
	var minutes: int = int(main.sim.time) / 60
	var seconds: int = int(main.sim.time) % 60
	_text(Vector2(screen.x - 357, 39), "%02d:%02d" % [minutes, seconds], 22, MUTED)
	_button(Rect2(screen.x - 263, 13, 72, 36), "暂停" if not main.sim.paused else "继续", "pause", main.binding_label("pause_game") + "：战术暂停，可继续下达指令")
	_button(Rect2(screen.x - 181, 13, 68, 36), "×%d" % int(main.speed), "speed", "切换游戏速度；%s / %s" % [main.binding_label("speed_up"), main.binding_label("speed_down")])
	_button(Rect2(screen.x - 103, 13, 82, 36), "菜单", "menu", "设置、帮助和战役存档")

func _draw_objectives(screen: Vector2, summary: Dictionary) -> void:
	_panel(Rect2(18, 82, 300, 222), Color(PANEL, 0.95), Color("52716d"))
	var phase_text: String = {"preparation": "整备", "advance": "推进", "evacuation": "撤守"}.get(main.sim.phase, "推进")
	_text(Vector2(34, 111), "%02d  %s · %s" % [Catalog.ids().find(String(main.sim.mission_id)) + 1, String(main.sim.mission_name), phase_text], 22, PAPER, 268)
	_text(Vector2(34, 139), "指挥车 + 至少4人抵达撤离站", 14, MUTED)
	var command: Dictionary = CommandTruckReadout.status(main.sim)
	var critical: bool = command.code == "critical"
	_button(_command_truck_rect(), String(command.label), "select_command_truck", String(command.tooltip), main.selected_ids == [command.unit_id] and not critical, critical, bool(command.enabled) and main.started and main.menu.is_empty())
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
	var targeting: bool = main.attack_move or not main.pending_task.is_empty()
	if targeting:
		var modes: Dictionary = {"clear": "清理搜刮", "escort": "护送补给", "guard": "驻守关口", "repair": "维修工程"}
		selection_text = ("攻击移动" if main.attack_move else String(modes.get(main.pending_task, main.pending_task))) + " · 左键指定区域"
	var short: bool = screen.y < 580
	var selection_top: float = 306 if short else 318
	_panel(Rect2(18, selection_top, 300, 40 if short else 64), Color(INK, 0.92), Color("456065"))
	_text(Vector2(33, selection_top + (17 if short else 28)), selection_text, 13 if short else 15, GOLD if targeting else PAPER)
	var selection_hint: String = "右键 / Esc 取消当前指令" if targeting else "%s 攻击 · %s 切队 · Ctrl+编队键保存" % [main.binding_label("attack_move"), main.binding_label("next_squad")]
	_text(Vector2(33, selection_top + (34 if short else 51)), selection_hint, 10 if short else 12, MUTED)

func _command_truck_rect() -> Rect2:
	return Rect2(34, 153, 266, 31)

func _draw_camp_cards(screen: Vector2) -> void:
	var y: float = 82
	var bottom: float = y
	var page_size: int = main.camp_page_size()
	var first: int = main.camp_page * page_size
	for index: int in range(first, mini(first + page_size, main.sim.camps.size())):
		var camp: Dictionary = main.sim.camps[index]
		var rect: Rect2 = Rect2(screen.x - 268, y, 250, 91)
		var chosen: bool = int(camp.get("id", -1)) == main.selected_camp
		_panel(rect, Color(PANEL, 0.95), TEAL if chosen else Color("456065"))
		var state: String = String(camp.get("state", "active"))
		var states: Dictionary = {"active":"运作", "packing":"撤收中", "abandoned":"已弃守"}
		_text(rect.position + Vector2(12, 24), String(camp.get("name", "驻点")), 16, PAPER, 150)
		_text(rect.position + Vector2(172, 24), states.get(state, state), 12, GOLD if state == "packing" else MUTED)
		_text(rect.position + Vector2(12, 44), "材 %d  供 %d  油 %d" % [int(camp.get("materials", 0)), int(camp.get("supplies", 0)), int(camp.get("fuel", 0))], 13, MUTED)
		var readout: Dictionary = main.camp_readouts.get(int(camp.get("id", 0)), {})
		var severity: String = String(readout.get("severity", "normal"))
		var status_color: Color = GOLD if severity == "attention" else (MUTED if severity == "muted" else TEAL)
		if readout.has("transport_text"):
			# Keep the same card/stock rows and input geometry. Packing uses its two
			# remaining lines for destination/cargo; exact cargo and power stay in tip.
			_text(rect.position + Vector2(12, 64), String(readout.transport_text), 13, GOLD if severity == "attention" else TEAL, 224)
			_text(rect.position + Vector2(12, 84), String(readout.cargo_text), 12, status_color, 224)
		else:
			_text(rect.position + Vector2(12, 64), String(readout.get("text", "… 更新状态")), 13, status_color, 224)
			var capacity: float = float(camp.get("power_capacity", 0.0))
			_bar(Rect2(rect.position + Vector2(100, 77), Vector2(136, 6)), float(camp.get("power_used", 0.0)) / maxf(capacity, 1), GOLD)
			_text(rect.position + Vector2(12, 84), "供能 %d/%d" % [int(camp.get("power_used", 0)), int(capacity)], 10, GOLD)
		var tip: String = String(camp.get("name", "驻点")) + "：" + String(readout.get("detail", "正在更新本地工作状态。")) + "\n点击定位并管理；Shift+%s 切换运作驻点。" % main.binding_label("focus_command")
		hotspots.append({"rect":rect, "action":"camp:%d" % int(camp.get("id", 0)), "tip":tip})
		if rect.has_point(get_viewport().get_mouse_position()):
			tooltip = tip
			_camp_tooltip = true
		bottom = rect.end.y
		y += 102
	if main.camp_page_count() > 1:
		var pager: Vector2 = Vector2(screen.x - 268, 82 + page_size * 102)
		_button(Rect2(pager, Vector2(72, 27)), "上一页", "camp_page_prev", "浏览驻点，不改变当前选中驻点", false, false, main.camp_page > 0)
		_text(pager + Vector2(84, 20), "%d / %d" % [main.camp_page + 1, main.camp_page_count()], 14, PAPER)
		_button(Rect2(pager + Vector2(178, 0), Vector2(72, 27)), "下一页", "camp_page_next", "浏览驻点，不改变当前选中驻点", false, false, main.camp_page + 1 < main.camp_page_count())
		_button(Rect2(pager + Vector2(78, 32), Vector2(172, 26)), "切换运作驻点", "camp_cycle", "Shift+%s：跳过已弃营地，定位下一运作或撤收驻点" % main.binding_label("focus_command"))
		bottom = pager.y + 58
	if bottom > 82:
		# Consume clicks throughout the actual visible panel, including disabled
		# pager buttons and page-number gaps; enabled hotspots still win first.
		overlay_rects.append(Rect2(screen.x - 268, 82, 250, bottom - 82))

func _draw_dock(screen: Vector2) -> void:
	var top: float = screen.y - 190
	_panel(Rect2(0, top, screen.x, 190), INK, Color("52716d"))
	if screen.x < 1120:
		var tab_width: float = (screen.x - 342) / 6.0
		var tabs: Array = [["建设 [%s]" % main.binding_label("build_menu"), "tab:build", main.current_tab == "build"], ["指挥 [%s]" % main.binding_label("orders_menu"), "tab:orders", main.current_tab == "orders"], ["生产 [%s]" % main.binding_label("production_menu"), "tab:production", main.current_tab == "production"], ["训练 [%s]" % main.binding_label("train_menu"), "tab:training", main.current_tab == "training"], ["补给线", "logistics", main.world.show_logistics], ["范围", "ranges", main.world.show_ranges]]
		for index: int in range(tabs.size()):
			_button(Rect2(18 + index * (tab_width + 8), top + 12, tab_width, 33), tabs[index][0], tabs[index][1], _compact_tab_tip(), tabs[index][2])
	else:
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
			_draw_build_icon(rect, String(items[i][0]), i, main.build_kind == items[i][0])
			_text(rect.position + Vector2(11, 75), items[i][1], 17, PAPER)
			_text(rect.position + Vector2(11, 98), items[i][2], 12, MUTED)
	elif main.current_tab == "orders":
		var items: Array = [["task:clear","清理并搜刮","向当前驻点区域派队清理"], ["task:escort","护送补给","保护驻点与运输队"], ["task:guard","驻守关口","持续守备指定区域"], ["evacuate","撤收驻点","打包人员和设备，运输至前方；取消未完成训练并返还一半费用"], ["seal:0","封锁后关","先让友军通过，再拖延追兵"], ["seal:1","封锁前关","争取出口施工和撤离时间"]]
		var current_camp: Dictionary = main.sim.get_camp(main.selected_camp)
		if current_camp.get("state", "") == "packing":
			items[3] = ["evacuate", "紧急弃营", "留下未装车物资，人员立即撤离；在途货物继续运输。"]
		var card_width: float = (width - 50) / 6.0
		for i: int in range(items.size()):
			_button(Rect2(18 + i * (card_width + 6), top + 62, card_width, 96), items[i][1], items[i][0], items[i][2], items[i][0] == "task:" + main.pending_task, i >= 3)
	elif main.current_tab == "production":
		var camp: Dictionary = main.sim.get_camp(main.selected_camp)
		var name_text: String = String(camp.get("name", "未选择驻点"))
		var recipe_area: float = width * 0.55
		var priority_x: float = 20 + recipe_area + 12
		var priority_width: float = (width - recipe_area - 36) / 3.0
		_text(Vector2(20, top + 79), name_text + " · 连续生产", 17, PAPER, recipe_area - 12)
		var recipe: String = String(camp.get("recipe", "idle"))
		var recipes: Array = [["materials", "加工建材"], ["supplies", "生产补给"], ["fuel", "提炼燃料"], ["idle", "暂停生产"]]
		var recipe_width: float = (recipe_area - 24) / 4.0
		for i: int in range(recipes.size()):
			_button(Rect2(20 + i * (recipe_width + 6), top + 95, recipe_width, 58), recipes[i][1], "recipe:" + recipes[i][0], "驻点需要实际运入的原料、完工工坊与本地供电；生产补给消耗成品燃料。", recipe == recipes[i][0])
		var priority: String = String(camp.get("priority", "production"))
		var priorities: Array = [["production","生产优先"], ["defense","防守优先"], ["evacuation","撤离优先"]]
		for i: int in range(priorities.size()):
			_button(Rect2(priority_x + i * (priority_width + 6), top + 95, priority_width, 58), priorities[i][1], "priority:" + priorities[i][0], "供电不足时，优先保障选定任务。", priority == priorities[i][0])
		_text(Vector2(priority_x, top + 79), "供能预设", 16, GOLD)
		var status: Dictionary = main.production_readout
		var running: bool = status.get("code", "") == "running"
		var readout: String = "%s · 供能工坊 %d/%d" % [String(status.get("text", "读取生产状态")), int(status.get("working", 0)), int(status.get("total", 0))]
		if running:
			readout += " · 废料 %d / 原油 %d / 燃料 %d" % [int(camp.get("salvage", 0)), int(camp.get("crude", 0)), int(camp.get("fuel", 0))]
		else:
			readout += " · " + String(status.get("detail", ""))
		var status_rect: Rect2 = Rect2(20, top + 158, width - 20, 29)
		_text(Vector2(20, top + 178), readout, 12, TEAL if running else GOLD, width - 20)
		if status_rect.has_point(get_viewport().get_mouse_position()): tooltip = String(status.get("detail", ""))
	elif main.current_tab == "training":
		var camp: Dictionary = main.sim.get_camp(main.selected_camp)
		var card_area: float = width * 0.60
		var card_width: float = (card_area - 18) / 4.0
		var queue_x: float = 20 + card_area + 18
		var queue_width: float = width - card_area - 28
		_text(Vector2(20, top + 75), String(camp.get("name", "未选择驻点")) + " · 本地训练", 16, PAPER, card_area)
		var recruits: Array[String] = ["rifle", "engineer", "worker", "truck"]
		var status: Dictionary = main.training_readout
		for i: int in range(recruits.size()):
			var kind: String = recruits[i]
			var plan: Dictionary = main.recruit_plans.get(kind, {})
			var rect: Rect2 = Rect2(20 + i * (card_width + 6), top + 87, card_width, 82)
			var tip: String = String(plan.get("message", "选择本营单位"))
			var active: bool = int(status.get("queue_size", 0)) > 0 and status.get("current_name", "") == plan.get("unit_name", "")
			_button(rect, "", "recruit:" + kind, tip, active)
			_text(rect.position + Vector2(7, 21), String(plan.get("unit_name", kind)), 14, PAPER, card_width - 14)
			_text(rect.position + Vector2(7, 41), String(plan.get("facility", "")), 11, MUTED, card_width - 14)
			var prices: PackedStringArray = []
			var labels: Dictionary = {"materials":"材", "supplies":"供", "fuel":"油"}
			for key: String in plan.get("costs", {}): prices.append("%d%s" % [int(plan.costs[key]), String(labels.get(key, key))])
			_text(rect.position + Vector2(7, 61), "/".join(prices), 11, GOLD if bool(plan.get("ok", false)) else RED, card_width - 14)
			_text(rect.position + Vector2(7, 76), "%d秒" % int(plan.get("duration", 0)), 10, MUTED, card_width - 14)
		_text(Vector2(queue_x, top + 75), "训练队列 %d / 4" % int(status.get("queue_size", 0)), 16, TEAL, queue_width)
		_bar(Rect2(queue_x, top + 87, queue_width, 8), float(status.get("progress", 0.0)), TEAL)
		_text(Vector2(queue_x, top + 116), String(status.get("text", "读取训练状态")), 13, GOLD, queue_width)
		var detail: String = String(status.get("detail", ""))
		var lines: Array[String] = _wrap_text(detail, queue_width, 11)
		for index: int in range(mini(2, lines.size())): _text(Vector2(queue_x, top + 137 + index * 15), lines[index], 11, MUTED, queue_width)
		training_queue_rect = Rect2(queue_x, top + 61, queue_width, 103)
		if training_queue_rect.has_point(get_viewport().get_mouse_position()): tooltip = detail
		var plan: Dictionary = main.recruit_plans.get("rifle", {})
		var stocks: String = "本营：材 %d / 供 %d / 油 %d · 指挥人口 %d/%d（含训练）" % [int(camp.get("materials", 0)), int(camp.get("supplies", 0)), int(camp.get("fuel", 0)), int(plan.get("population", 0)), int(plan.get("cap", 32))]
		_text(Vector2(20, top + 184), stocks, 11, PAPER, width - 12)

func _draw_build_icon(rect: Rect2, kind: String, fallback_index: int, active: bool) -> void:
	# Match the actual world sprite, including the shared command/camp artwork.
	# Roads and a missing/invalid optional atlas retain the established fallback.
	var source_kind: String = "command" if kind == "camp" else kind
	if _building_atlas != null and WorldView.BUILDING_REGIONS.has(source_kind):
		var source: Rect2 = WorldView.BUILDING_REGIONS[source_kind]
		if source.size.x > 0.0 and source.size.y > 0.0 and source.end.x <= _building_atlas.get_width() and source.end.y <= _building_atlas.get_height():
			var area: Rect2 = Rect2(rect.position + Vector2(8, 6), Vector2(maxf(1, rect.size.x - 16), 49))
			var ratio: float = minf(area.size.x / source.size.x, area.size.y / source.size.y)
			var size: Vector2 = source.size * ratio
			draw_texture_rect_region(_building_atlas, Rect2(area.position + (area.size - size) * 0.5, size), source)
			return
	_icon(rect.position + Vector2(rect.size.x * 0.5, 31), fallback_index, GOLD if active else TEAL)

var _minimap_terrain_signature: int = -1
var _minimap_terrain_texture: ImageTexture

func _minimap_background() -> Texture2D:
	var signature: int = hash([main.sim.mission_id, main.sim.map_size, main.sim.terrain])
	if _minimap_terrain_texture != null and signature == _minimap_terrain_signature:
		return _minimap_terrain_texture
	var map_size: Vector2i = main.sim.map_size
	var style: Dictionary = main.sim.mission_data.get("visual", {})
	var pixels: Image = Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGBA8)
	for y: int in range(map_size.y):
		for x: int in range(map_size.x):
			var height: int = int(main.sim.terrain[y][x])
			pixels.set_pixel(x, y, Cartoon.map_color(style, Vector2i(x,y), height))
	pixels.resize(256, 148, Image.INTERPOLATE_NEAREST)
	_minimap_terrain_texture = ImageTexture.create_from_image(pixels)
	_minimap_terrain_signature = signature
	return _minimap_terrain_texture

func _draw_minimap(screen: Vector2) -> void:
	map_rect = Rect2(screen.x - 274, screen.y - 176, 256, 148)
	_panel(map_rect.grow(4), PANEL, TEAL)
	var map_size: Vector2i = main.sim.map_size
	var scale_value: Vector2 = map_rect.size / Vector2(map_size)
	draw_texture_rect(_minimap_background(), map_rect, false)
	for road: Variant in main.sim.roads:
		draw_rect(Rect2(map_rect.position + Vector2(road) * scale_value, scale_value + Vector2.ONE), Color("eddbb0"))
	for camp: Dictionary in main.sim.camps:
		var p: Vector2 = camp.get("pos", Vector2.ZERO)
		draw_circle(map_rect.position + p * scale_value, 4.0, TEAL if camp.get("state", "") != "abandoned" else MUTED)
	for site: Dictionary in main.sim.sites:
		var p: Vector2 = site.get("pos", Vector2.ZERO)
		var point: Vector2 = map_rect.position + p * scale_value
		point = point.clamp(map_rect.position + Vector2(7, 7), map_rect.end - Vector2(7, 7))
		_draw_minimap_site(point, String(site.get("kind", "cache")), bool(site.get("captured", false)))
	for unit: Dictionary in main.sim.units:
		var p: Vector2 = unit.get("pos", Vector2.ZERO)
		draw_circle(map_rect.position + p * scale_value, 1.5, RED if unit.get("team") == "enemy" else Color("f8f1d4"))
	var pursuit: float = clampf(float(main.sim.pursuit_x), 0, map_size.x)
	draw_line(map_rect.position + Vector2(pursuit * scale_value.x, 0), map_rect.position + Vector2(pursuit * scale_value.x, map_rect.size.y), RED, 2)
	# Follow the same visibility rule as the world marker: no title-screen hint,
	# and dismissing the guide also removes its minimap target.
	if main.started:
		var hint: Dictionary = main.guide.get_hint()
		var target: Vector2 = hint.get("target", Vector2(-1, -1))
		if bool(hint.get("visible", false)) and target.x >= 0.0 and target.y >= 0.0:
			var point: Vector2 = (map_rect.position + target * scale_value).clamp(map_rect.position + Vector2(8, 8), map_rect.end - Vector2(8, 8))
			_draw_minimap_target(point)
	var view_size: Vector2 = get_viewport_rect().size / main.camera.zoom / 48.0
	var camera_tile: Vector2 = main.camera.position / 48.0
	var camera_rect: Rect2 = Rect2(map_rect.position + (camera_tile - view_size * 0.5) * scale_value, view_size * scale_value)
	draw_rect(camera_rect.intersection(map_rect), PAPER, false, 1.5)
	_text(map_rect.position + Vector2(7, 18), "战略地图", 12, INK)
	var tip: String = "左键定位，右键下令。菱形废料／油桶燃料／方箱补给／旗帜出口／准星引导"
	hotspots.append({"rect":map_rect, "action":"minimap", "tip":tip})
	if map_rect.has_point(get_viewport().get_mouse_position()) and main.capture_path.is_empty(): tooltip = tip

func _draw_minimap_site(point: Vector2, kind: String, captured: bool) -> void:
	# Geometry carries the meaning even without colour: diamond, barrel,
	# crossed crate and exit flag stay distinct from camp and actor dots.
	draw_circle(point, 6.0, Color(INK, 0.90))
	var fill: Color = TEAL if captured else PAPER
	match kind:
		"quarry":
			draw_colored_polygon(PackedVector2Array([point + Vector2(0, -4.5), point + Vector2(4.5, 0), point + Vector2(0, 4.5), point + Vector2(-4.5, 0)]), fill)
		"fuel":
			draw_rect(Rect2(point + Vector2(-3, -4.5), Vector2(6, 9)), fill)
			draw_line(point + Vector2(-3, -2), point + Vector2(3, -2), INK, 1.0)
			draw_line(point + Vector2(-3, 2), point + Vector2(3, 2), INK, 1.0)
		"exit":
			draw_line(point + Vector2(-3, 5), point + Vector2(-3, -5), PAPER, 1.5)
			draw_colored_polygon(PackedVector2Array([point + Vector2(-2, -5), point + Vector2(5, -2), point + Vector2(-2, 1)]), PAPER)
		_:
			draw_rect(Rect2(point - Vector2(3.5, 3.5), Vector2(7, 7)), fill)
			draw_line(point + Vector2(-2, -2), point + Vector2(2, 2), INK, 1.0)
			draw_line(point + Vector2(2, -2), point + Vector2(-2, 2), INK, 1.0)

func _draw_minimap_target(point: Vector2) -> void:
	# Four open corners preserve the site/unit symbol at the target's centre.
	for sign_x: int in [-1, 1]:
		for sign_y: int in [-1, 1]:
			var corner: Vector2 = point + Vector2(sign_x * 7, sign_y * 7)
			var horizontal: Vector2 = corner - Vector2(sign_x * 4, 0)
			var vertical: Vector2 = corner - Vector2(0, sign_y * 4)
			draw_line(corner, horizontal, INK, 3.5)
			draw_line(corner, vertical, INK, 3.5)
			draw_line(corner, horizontal, GOLD, 1.5)
			draw_line(corner, vertical, GOLD, 1.5)

func _draw_menu(screen: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.08, 0.09, 0.78))
	hotspots.clear()
	if main.menu == "exit_save_failed":
		var recovery_size: Vector2 = Vector2(minf(700, screen.x - 32), minf(410, screen.y - 32))
		var recovery: Rect2 = Rect2((screen - recovery_size) * 0.5, recovery_size)
		_panel(recovery, PANEL, RED)
		_text(recovery.position + Vector2(28, 50), "退出前自动保存失败", 28, RED, recovery.size.x - 56)
		var explanation: Array[String] = _wrap_text("当前战役的最新进度尚未保存，游戏已暂停。可返回检查存储空间，重试保存后退出，或明确放弃未保存进度并退出。已有手动存档与备份保持不变。", recovery.size.x - 56, 18)
		for index: int in range(explanation.size()):
			_text(recovery.position + Vector2(28, 90 + index * 26), explanation[index], 18, PAPER)
		var choices: Array = [["返回原菜单 / 游戏（Esc）", "exit_cancel"], ["重试保存并退出", "exit_retry"], ["放弃未保存进度并退出", "exit_discard"]]
		for index: int in range(choices.size()):
			_button(Rect2(recovery.position + Vector2(28, recovery.size.y - 180 + index * 54), Vector2(recovery.size.x - 56, 44)), choices[index][0], choices[index][1], "", false, index == 2)
		return
	if main.menu == "campaigns":
		_draw_campaign_selection(screen)
		return
	if main.menu == "restart":
		var confirm_size: Vector2 = Vector2(minf(720, screen.x - 32), minf(430, screen.y - 32))
		var confirm: Rect2 = Rect2((screen - confirm_size) * 0.5, confirm_size)
		_panel(confirm, PANEL, GOLD)
		var requested: String = String(main.pending_mission_id)
		var definition: Dictionary = Catalog.mission(requested if not requested.is_empty() else String(main.sim.mission_id))
		var switching: bool = requested != "" and requested != String(main.sim.mission_id)
		_text(confirm.position + Vector2(28, 54), "切换至「%s」？" % String(definition.get("name", "战役")) if switching else "重新开始本关？", 28, GOLD, confirm.size.x - 56)
		var lines: Array[String] = _wrap_text("确认后会重置队伍、建筑和资源。系统先把当前进度保存到独立的自动存档，成功后才进入所选战役；手动存档与备份保持不变。需要长期保留这一局时，请先取消并手动保存。", confirm.size.x - 56, 18)
		for index: int in range(lines.size()): _text(confirm.position + Vector2(28, 104 + index * 28), lines[index], 18, PAPER)
		var button_width: float = (confirm.size.x - 72) * 0.5
		_button(Rect2(confirm.position + Vector2(28, confirm.size.y - 80), Vector2(button_width, 50)), "取消，继续当前战役", "resume", "")
		_button(Rect2(confirm.position + Vector2(44 + button_width, confirm.size.y - 80), Vector2(button_width, 50)), "确认切换战役" if switching else "确认重新开始", "restart_confirm", "先创建自动存档，成功后才重置", false, true)
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
	var panel_size: Vector2 = Vector2(minf(650, screen.x - 32), minf(604, screen.y - 32))
	var panel: Rect2 = Rect2((screen - panel_size) * 0.5, panel_size)
	_panel(panel, Color("20383b"), TEAL)
	_text(panel.position + Vector2(46, 91), "逐营突围", 56, PAPER)
	_text(panel.position + Vector2(48, 124), "O U T P O S T   E X O D U S", 17, TEAL)
	var subtitle: String = "向前建设，向后撤守。选择路线，把幸存者带到出口。"
	if main.menu == "victory": subtitle = "突围成功 · 指挥车与 %d 名幸存者抵达出口。" % main.sim.evacuated
	elif main.menu == "defeat": subtitle = String(main.sim.messages.back()) if not main.sim.messages.is_empty() else "战役失败，可读取存档或重新开始。"
	elif main.menu == "pause": subtitle = String(main.menu_notice) if not main.menu_notice.is_empty() else "战役已暂停 · 调整计划后继续推进。"
	_text(panel.position + Vector2(48, 176), subtitle, 18, GOLD if main.menu == "pause" and not main.menu_notice.is_empty() else MUTED, panel.size.x - 96)
	var chosen: Dictionary = Catalog.mission(String(main.selected_mission_id))
	var primary: Array = ["继续战役", "resume"] if main.menu == "pause" else ["开始「%s」" % String(chosen.get("name", "战役")) if main.menu == "title" else "重新开始战役", "new"]
	_button(Rect2(panel.position + Vector2(48, 211), Vector2(panel.size.x - 96, 46)), primary[0], primary[1], "")
	var buttons: Array = [["选择战役", "campaigns", true]]
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
		var button_width: float = (panel.size.x - 110) * 0.5
		var row_gap: float = minf(51, (panel.size.y - 312) / maxf(1, ceilf(buttons.size() / 2.0)))
		var rect: Rect2 = Rect2(panel.position + Vector2(48 + (index % 2) * (button_width + 14), 273 + (index / 2) * row_gap), Vector2(button_width, minf(42, row_gap - 6)))
		_button(rect, buttons[index][0], buttons[index][1], "尚无此类存档" if not buttons[index][2] else "", false, false, buttons[index][2])
	_text(panel.position + Vector2(48, panel.size.y - 24), "开发中版本 · 三场独立战役 · 2D 卡通生存策略", 13, MUTED)


func _draw_campaign_selection(screen: Vector2) -> void:
	var panel_size: Vector2 = Vector2(minf(1120, screen.x - 32), minf(660, screen.y - 32))
	var panel: Rect2 = Rect2((screen - panel_size) * 0.5, panel_size)
	_panel(panel, PANEL, TEAL)
	_text(panel.position + Vector2(24, 43), "选择战役", 29, PAPER)
	_text(panel.position + Vector2(24, 70), "独立地图与真实路线选择 · 每场都从后方营地出发", 15, MUTED)
	var card_width: float = (panel.size.x - 72) / 3.0
	var card_height: float = panel.size.y - 150
	var ids: Array[String] = Catalog.ids()
	for index: int in range(ids.size()):
		var mission_id: String = ids[index]
		var definition: Dictionary = Catalog.mission(mission_id)
		var card: Rect2 = Rect2(panel.position + Vector2(24 + index * (card_width + 12), 88), Vector2(card_width, card_height))
		var chosen: bool = mission_id == String(main.selected_mission_id)
		_panel(card, Color("1b3035"), GOLD if chosen else Color("456065"))
		_text(card.position + Vector2(14, 31), "%02d  %s" % [index + 1, String(definition["name"])], 21, GOLD if chosen else PAPER, card_width - 28)
		var preview_height: float = clampf(card_height * 0.27, 90, 132)
		var preview: Rect2 = Rect2(card.position + Vector2(14, 45), Vector2(card_width - 28, preview_height))
		_draw_campaign_preview(preview, mission_id, definition)
		var cursor: float = 45 + preview_height + 23
		var objective_lines: Array[String] = _wrap_text(String(definition["objective"]), card_width - 28, 14)
		for line: String in objective_lines:
			_text(card.position + Vector2(14, cursor), line, 14, PAPER)
			cursor += 21
		cursor += 9
		_text(card.position + Vector2(14, cursor), "路线抉择", 14, GOLD)
		cursor += 22
		var choices: Array = definition["guide"]["choices"]
		for choice: Variant in choices:
			var choice_lines: Array[String] = _wrap_text(String(choice), card_width - 28, 13)
			for line: String in choice_lines:
				_text(card.position + Vector2(14, cursor), line, 13, MUTED)
				cursor += 19
			cursor += 7
		_button(Rect2(card.position + Vector2(14, card_height - 48), Vector2(card_width - 28, 36)), "进入「%s」" % String(definition["name"]), "campaign:" + mission_id, "切换进行中的战役前，会先确认并创建独立自动存档", chosen)
	_button(Rect2(panel.position + Vector2(24, panel.size.y - 46), Vector2(panel.size.x - 48, 32)), "返回", "campaign_back", "保留当前战役与所选战役")


func _draw_campaign_preview(rect: Rect2, mission_id: String, definition: Dictionary) -> void:
	if not _campaign_previews.has(mission_id):
		var map_size: Vector2i = definition["map_size"]
		var pixels: Image = Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGBA8)
		var geometry: Dictionary = Catalog.terrain_for(definition)
		var style: Dictionary = definition.get("visual", {})
		for y: int in range(map_size.y):
			for x: int in range(map_size.x):
				pixels.set_pixel(x, y, Cartoon.map_color(style, Vector2i(x,y), int(geometry.terrain[y][x])))
		for ramp: Rect2i in definition["ramp_rects"]: pixels.fill_rect(ramp, Color("9fb781"))
		for road: Dictionary in definition["roads"]:
			var at: Vector2i = road["pos"]
			pixels.set_pixel(at.x, at.y, Color("f4e4b8"))
		_campaign_previews[mission_id] = ImageTexture.create_from_image(pixels)
	draw_texture_rect(_campaign_previews[mission_id], rect, false)
	var map_size: Vector2 = Vector2(definition["map_size"])
	for site: Dictionary in definition["sites"]:
		var point: Vector2 = rect.position + Vector2(site["pos"]) / map_size * rect.size
		var color: Color = GOLD if String(site["kind"]) == "fuel" else (TEAL if String(site["kind"]) == "exit" else PAPER)
		draw_circle(point, 3.0, INK)
		draw_circle(point, 2.0, color)
	for camp: Dictionary in definition["camps"]:
		draw_circle(rect.position + Vector2(camp["pos"]) / map_size * rect.size, 3.5, TEAL)
	draw_rect(rect, Color("52716d"), false, 1.0)


func _mission_site_name(key: String) -> String:
	var definition: Dictionary = main.sim.mission_data
	for site: Dictionary in definition["sites"]:
		if String(site["key"]) == key: return String(site["name"])
	return "资源点"


func _draw_settings(screen: Vector2) -> void:
	var panel_size: Vector2 = Vector2(minf(820, screen.x - 32), minf(704, screen.y - 32))
	var panel: Rect2 = Rect2((screen - panel_size) * 0.5, panel_size)
	var compact: bool = screen.y < 736
	var per_page: int = main.settings_binding_page_size()
	_panel(panel, PANEL, TEAL)
	_text(panel.position + Vector2(30, 40 if compact else 48), "设置与按键", 30, PAPER)
	_button(Rect2(panel.position + Vector2(30, 58 if compact else 68), Vector2(365, 34 if compact else 38)), "快捷键", "settings_tab:controls", "所有主要操作均可重绑", main.settings_tab == "controls")
	_button(Rect2(panel.position + Vector2(415, 58 if compact else 68), Vector2(375, 34 if compact else 38)), "显示与声音", "settings_tab:display", "分辨率、缩放、独立音量和静音", main.settings_tab == "display")
	if main.settings_tab == "controls":
		_button(Rect2(panel.position + Vector2(30, 108 if compact else 122), Vector2(350, 42)), "主音量  %d%%" % int(main.volume * 100), "volume", "点击循环切换主音量")
		_button(Rect2(panel.position + Vector2(400, 108 if compact else 122), Vector2(390, 42)), "边缘滚屏：" + ("开" if main.edge_scroll else "关"), "edge_scroll", "靠近屏幕边缘时移动镜头")
		var actions: Array = main.command_names.keys()
		var start: int = main.settings_page * per_page
		for i: int in range(start, mini(actions.size(), start + per_page)):
			var action: String = actions[i]
			var relative: int = i - start
			_button(Rect2(panel.position + Vector2(30 + (relative % 2) * 395, (164 if compact else 186) + (relative / 2) * (48 if compact else 55)), Vector2(365, 44)), main.command_names[action] + "    " + main.binding_label(action), "bind:" + action, "点击后按新按键；冲突会提示且保留原绑定。")
		_button(Rect2(panel.position + Vector2(30, 320 if compact else 479), Vector2(180, 38)), "上一页", "bindings_prev", "", false, false, main.settings_page > 0)
		_text(panel.position + Vector2(228, 346 if compact else 505), "%d / %d" % [main.settings_page+1, ceili(float(actions.size()) / float(per_page))], 17, MUTED)
		_button(Rect2(panel.position + Vector2(335, 320 if compact else 479), Vector2(180, 38)), "下一页", "bindings_next", "", false, false, start + per_page < actions.size())
		_button(Rect2(panel.position + Vector2(545, 320 if compact else 479), Vector2(245, 38)), "恢复默认按键", "bindings_reset", "会替换所有自定义快捷键")
		var feedback: String = main.settings_feedback
		if not main.waiting_binding.is_empty() and feedback.is_empty(): feedback = "请按新按键，Esc 取消。"
		var lines: Array[String] = _wrap_text(feedback, 750, 16)
		for i: int in range(mini(3, lines.size())): _text(panel.position + Vector2(30, (384 if compact else 548) + i * 23), lines[i], 16, GOLD)
	else:
		_button(Rect2(panel.position + Vector2(30, 112 if compact else 128), Vector2(365, 48)), "主音量  %d%%" % int(main.volume*100), "volume", "主音量控制所有声音")
		_button(Rect2(panel.position + Vector2(415, 112 if compact else 128), Vector2(375, 48)), "静音：" + ("开" if main.muted else "关"), "mute", "静音不改变各声道的音量设置")
		_button(Rect2(panel.position + Vector2(30, 166 if compact else 192), Vector2(365, 48)), "音乐  %d%%" % int(main.music_volume*100), "music_volume", "独立调整营地与远行背景音乐")
		_button(Rect2(panel.position + Vector2(415, 166 if compact else 192), Vector2(375, 48)), "音效  %d%%" % int(main.effects_volume*100), "effects_volume", "独立调整界面和战斗反馈音")
		_button(Rect2(panel.position + Vector2(30, 226 if compact else 268), Vector2(365, 48)), "显示模式：" + ("全屏" if main.fullscreen else "窗口"), "fullscreen", "切换全屏；窗口分辨率会保留")
		_button(Rect2(panel.position + Vector2(415, 226 if compact else 268), Vector2(375, 48)), "窗口 %d × %d" % [main.window_resolution.x,main.window_resolution.y], "resolution", "循环选择窗口分辨率")
		_button(Rect2(panel.position + Vector2(30, 280 if compact else 332), Vector2(365, 48)), "界面倍率 %d%%" % int(round(main.ui_scale*100)), "ui_scale", "100% / 110% / 120%，地图仍可独立缩放")
		_button(Rect2(panel.position + Vector2(415, 280 if compact else 332), Vector2(375, 48)), "边缘滚屏：" + ("开" if main.edge_scroll else "关"), "edge_scroll", "可用 WASD 或中键拖动替代")
		_button(Rect2(panel.position + Vector2(30, 342 if compact else 414), Vector2(760, 48)), "战役引导：" + ("显示" if bool(main.guide.get_hint().get("visible",false)) else "隐藏"), "guide_toggle", "可随时隐藏或恢复，不限制任务路线")
		_text(panel.position + Vector2(30, 410 if compact else 510), "设置自动保存在本机，不随战役存档覆盖。", 17, MUTED)
		_text(panel.position + Vector2(30, 440 if compact else 542), "音量点击循环调整；独立音乐和音效声道立即生效。", 15, MUTED)
	_button(Rect2(panel.position + Vector2(30, panel.size.y - 77), Vector2(760, 46)), "返回", "back", "")

func _clear_text_layouts() -> void:
	_text_layouts.clear()

func _wrap_text(text: String, width: float, size_value: int, hanging_punctuation: bool = true) -> Array[String]:
	var key: Array = [text, width, size_value, hanging_punctuation]
	if _text_layouts.has(key): return _text_layouts[key]
	var result: Array[String] = []
	var line: String = ""
	for character: String in text:
		if character == "\n" or (font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,size_value).x > width and not (hanging_punctuation and "，。；：！？、）】」".contains(character))):
			result.append(line)
			line = "" if character == "\n" else character
		else: line += character
	if not line.is_empty(): result.append(line)
	# Callers only inspect lines. Prevent accidental mutation of a shared layout.
	result.make_read_only()
	if _text_layouts.size() >= TEXT_LAYOUT_CACHE_LIMIT:
		_text_layouts.erase(_text_layouts.keys()[0])
	_text_layouts[key] = result
	return result

func _draw_guide(screen: Vector2) -> void:
	if not main.build_kind.is_empty():
		_draw_construction_preview(screen)
		return
	var hint: Dictionary = main.guide.get_hint()
	var guide_top: float = 397.0
	var available_height: float = screen.y - 190.0 - guide_top - 12.0
	if available_height < 145.0:
		var compact: Rect2 = Rect2(340, 186, minf(300, screen.x - 620), 34)
		overlay_rects.append(compact)
		var visible_hint: bool = bool(hint.get("visible", false))
		_button(compact, "战役引导 · 展开查看" if visible_hint else "显示战役引导", "guide_more" if visible_hint else "guide_toggle", "暂停查看当前目标与资源路线")
		return
	if not bool(hint.get("visible", false)):
		_button(Rect2(18,guide_top,300,34), "显示战役引导", "guide_toggle", "提示会跟随当前真实战役进度")
		return
	var maximum_height: float = minf(available_height,248.0)
	var lines: Array[String] = _wrap_text(main.guide_text(String(hint.get("text",""))),276,14)
	# Preserve the viewport's original line budget before fitting the card.
	var limit: int = clampi(int((maximum_height-112)/20),2,6)
	var visible_lines: int = mini(limit,lines.size())
	# Keep the existing header/button allowance, without reserving empty rows.
	var height: float = minf(maximum_height,maxf(145.0,112.0+visible_lines*20.0))
	var rect: Rect2 = Rect2(18,guide_top,300,height)
	overlay_rects.append(rect)
	_panel(rect, Color(PANEL,0.97), GOLD)
	_text(rect.position+Vector2(12,27), "%d/%d  %s" % [int(hint.get("step",1)),int(hint.get("total",11)),String(hint.get("title","当前目标"))],15,GOLD,276)
	_bar(Rect2(rect.position+Vector2(12,39),Vector2(276,4)),float(hint.get("step",1))/float(hint.get("total",11)),TEAL)
	for i: int in range(visible_lines):
		var line: String = lines[i]+("…" if i == limit-1 and lines.size()>limit else "")
		_text(rect.position+Vector2(12,67+i*20),line,14,PAPER)
	var bottom: float = rect.end.y-38
	_button(Rect2(30,bottom,84,27),"定位","guide_focus","只移动镜头，不替你下令",false,false,Vector2(hint.get("target",Vector2(-1,-1))).x>=0)
	_button(Rect2(124,bottom,84,27),"展开","guide_more","暂停查看完整提示")
	_button(Rect2(218,bottom,88,27),"隐藏","guide_toggle","之后可从这里或设置中恢复")

func _resource_text(values: Dictionary) -> String:
	var labels: Dictionary = {"materials": "建材", "supplies": "补给", "fuel": "燃料"}
	var parts: PackedStringArray = []
	for key: String in values:
		var amount: float = float(values[key])
		var number: String = "<0.1" if amount > 0.0 and amount < 0.1 else String.num(amount, 1).trim_suffix(".0")
		parts.append(String(labels.get(key, key)) + " " + number)
	return " / ".join(parts)

func _construction_preview_rect(screen: Vector2) -> Rect2:
	return Rect2(340, 140, minf(422, screen.x - 628), minf(230, screen.y - 350)) if screen.y < 840 else Rect2(18, 397, 300, clampf(screen.y - 607, 230, 248))

func _draw_construction_preview(screen: Vector2) -> void:
	var rect: Rect2 = _construction_preview_rect(screen)
	var plan: Dictionary = main.build_preview
	var valid: bool = bool(plan.get("ok", false))
	var choosing: bool = str(plan.get("code", "")) == "choose_map"
	var accent: Color = MUTED if choosing else (TEAL if valid else RED)
	var names: Dictionary = {"road": "道路", "camp": "前哨营地", "generator": "发电机", "workshop": "工坊", "tower": "岗哨炮塔", "barracks": "军营", "barricade": "临时路障"}
	overlay_rects.append(rect)
	_panel(rect, PANEL, accent)
	var title: String = "施工预览 · " + String(names.get(main.build_kind, main.build_kind)) + (" · 暂停" if main.sim.paused else "")
	_text(rect.position + Vector2(12, 27), title, 17, accent, rect.size.x - 24)
	var camp_name: String = String(plan.get("camp_name", ""))
	var source_text: String = camp_name if not camp_name.is_empty() else ("无运作营地" if str(plan.get("code", "")) == "no_active_camp" else "选择位置后确定")
	_text(rect.position + Vector2(12, 51), "供料：" + source_text, 13, PAPER, rect.size.x - 24)
	var costs: Dictionary = plan.get("costs", {})
	_text(rect.position + Vector2(12, 73), "需要：" + ("选择位置后核对" if choosing else (_resource_text(costs) if not costs.is_empty() else "暂无可下单路线")), 13, GOLD, rect.size.x - 24)
	var lines: Array[String] = _wrap_text(String(plan.get("message", "移动到地图选择施工位置。")), rect.size.x - 24, 14)
	var limit: int = clampi(int((rect.size.y - 164) / 18) + 1, 1, 4)
	for i: int in range(mini(limit, lines.size())):
		_text(rect.position + Vector2(12, 98 + i * 18), lines[i] + ("…" if i == limit - 1 and lines.size() > limit else ""), 14, PAPER)
	var missing: Dictionary = plan.get("missing", {})
	var note: String = "缺少：" + _resource_text(missing) if not missing.is_empty() else String(plan.get("warning", ""))
	if note.is_empty(): note = "左键下单 · 右键取消"
	_text(Vector2(rect.position.x + 12, rect.end.y - 48), note, 12, GOLD, rect.size.x - 24)
	_button(Rect2(rect.position.x + 12, rect.end.y - 36, rect.size.x - 24, 26), "取消施工", "cancel_build", "取消放置，不影响已安排的工程")

func _construction_details_rect(screen: Vector2) -> Rect2:
	var top: float = maxf(132.0, screen.y - 430.0)
	var height: float = minf(228.0, screen.y - 192.0 - top)
	return Rect2(Vector2((screen.x - 320.0) * 0.5, top), Vector2(320, height))

func _draw_construction_details(screen: Vector2) -> void:
	var rect: Rect2 = _construction_details_rect(screen)
	var status: Dictionary = main.construction_readout
	overlay_rects.append(rect)
	_panel(rect, PANEL, TEAL)
	_text(rect.position + Vector2(12, 26), str(status.get("name", "工地")) + " · 施工 %d%%" % int(float(status.get("progress", 0.0)) * 100.0), 17, PAPER, 296)
	_bar(Rect2(rect.position + Vector2(12, 36), Vector2(296, 6)), float(status.get("progress", 0.0)), TEAL)
	_text(rect.position + Vector2(12, 64), "供料：" + str(status.get("source_name", "记录不可用")), 14, PAPER, 296)
	_text(rect.position + Vector2(12, 88), "施工者：" + str(status.get("builder_text", "未指定")), 14, PAPER, 296)
	var lines: Array[String] = _wrap_text(str(status.get("text", "")), 296, 14)
	for index: int in range(mini(3, lines.size())):
		_text(rect.position + Vector2(12, 113 + index * 19), lines[index], 14, GOLD, 296)
	_text(rect.position + Vector2(12, rect.size.y - 47), "战术暂停 · 继续后推进 · Esc关闭" if bool(status.get("paused", false)) else "Esc 关闭详情", 12, MUTED, 296)
	_button(Rect2(rect.position + Vector2(12, rect.size.y - 36), Vector2(296, 26)), "关闭详情", "close_project", "")

func _draw_guide_dialog(screen: Vector2) -> void:
	var panel_size: Vector2 = Vector2(minf(900, screen.x - 32), minf(620, screen.y - 32))
	var panel: Rect2 = Rect2((screen - panel_size) * 0.5, panel_size)
	_panel(panel, PANEL, GOLD)
	var hint: Dictionary = main.guide.get_hint()
	_text(panel.position + Vector2(26, 42), String(main.sim.mission_name) + " · 战役引导", 27, GOLD, panel.size.x - 52)
	_text(panel.position + Vector2(26, 76), String(hint.get("title", "当前目标")), 19, PAPER, panel.size.x - 52)
	var lines: Array[String] = _wrap_text(main.guide_text(String(hint.get("text", ""))), panel.size.x - 52, 18)
	var limit: int = maxi(1, int((panel.size.y - 270) / 27))
	for index: int in range(mini(lines.size(), limit)): _text(panel.position + Vector2(26, 114 + index * 27), lines[index], 18, PAPER)
	var button_width: float = (panel.size.x - 66) * 0.5
	var branch_y: float = panel.size.y - 164
	_text(panel.position + Vector2(26, branch_y - 14), "选择资源优先级，只调整引导，不替你下令。", 15, MUTED)
	_button(Rect2(panel.position + Vector2(26, branch_y), Vector2(button_width, 40)), "建材：" + _mission_site_name("quarry"), "guide_branch:north", "先回收废料，再由工坊加工建材")
	_button(Rect2(panel.position + Vector2(40 + button_width, branch_y), Vector2(button_width, 40)), "燃料：" + _mission_site_name("fuel"), "guide_branch:south", "先运回原油，维持发电与生产")
	_text(panel.position + Vector2(26, panel.size.y - 100), "可自由选择推进与撤收方案；定位仅移动镜头。", 15, MUTED)
	_button(Rect2(panel.position + Vector2(26, panel.size.y - 74), Vector2(button_width, 46)), "定位并返回战役", "guide_focus", "", false, false, Vector2(hint.get("target", Vector2(-1, -1))).x >= 0)
	_button(Rect2(panel.position + Vector2(40 + button_width, panel.size.y - 74), Vector2(button_width, 46)), "返回战役", "resume", "")

func _draw_help(screen: Vector2) -> void:
	var panel_size: Vector2 = Vector2(minf(930, screen.x - 32), minf(680, screen.y - 32))
	var panel: Rect2 = Rect2((screen - panel_size) * 0.5, panel_size)
	_panel(panel, PANEL, TEAL)
	_text(panel.position + Vector2(28, 45), String(main.sim.mission_name) + " · 指挥手册", 28, PAPER, panel.size.x - 56)
	var definition: Dictionary = main.sim.mission_data
	var entries: Array[String] = [
		"目标：" + String(definition["objective"]),
		"1. 拖框选择小队，右键移动；%s 后左键执行攻击移动。" % main.binding_label("attack_move"),
		"2. 清理 %s 与 %s，铺路让工人运回废料和原油。" % [_mission_site_name("quarry"), _mission_site_name("fuel")],
		"3. %s 建设前哨和设施；%s 调整生产、当地供能与优先级。" % [main.binding_label("build_menu"), main.binding_label("production_menu")],
		"4. %s 指挥驻守、护送、搜刮与撤营；%s 训练单位，需要设施和当地供能。" % [main.binding_label("orders_menu"), main.binding_label("train_menu")],
		"5. 后方追兵持续逼近。先运走人员设备，再封关争取时间。",
		"6. 工程师修复 %s，指挥车与至少四名幸存者抵达才算胜利。" % _mission_site_name("exit"),
		String(definition["guide"]["route_text"]),
		"镜头：%s/%s/%s/%s 或中键拖动，滚轮缩放，小地图定位。" % [main.binding_label("camera_up"), main.binding_label("camera_left"), main.binding_label("camera_down"), main.binding_label("camera_right")],
		"编队：%s / %s / %s / %s，Ctrl 保存；%s 切队，%s 定位驻点；Shift+%s切换运作驻点。" % [main.binding_label("group_1"), main.binding_label("group_2"), main.binding_label("group_3"), main.binding_label("group_4"), main.binding_label("next_squad"), main.binding_label("focus_command"), main.binding_label("focus_command")],
		"%s 暂停；%s 保存，%s 读取；%s 补给线，%s 范围。" % [main.binding_label("pause_game"), main.binding_label("quick_save"), main.binding_label("quick_load"), main.binding_label("logistics_toggle"), main.binding_label("ranges_toggle")]
	]
	var y: float = 82
	var font_size: int = 15 if panel.size.y < 620 else 17
	var line_gap: float = 23 if panel.size.y < 620 else 27
	for entry: String in entries:
		for line: String in _wrap_text(entry, panel.size.x - 56, font_size):
			_text(panel.position + Vector2(28, y), line, font_size, PAPER if y == 82 else MUTED)
			y += line_gap
		y += 5
	_button(Rect2(panel.position + Vector2(28, panel.size.y - 65), Vector2(panel.size.x - 56, 40)), "明白，返回", "back", "")

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
	return blocks_world_point(point)

func blocks_world_point(point: Vector2) -> bool:
	# Pure logical-viewport hit testing, shared by clicks and placement hover.
	# Include panel gaps and disabled controls, not just enabled action hotspots.
	if not main.menu.is_empty(): return true
	for item: Dictionary in hotspots:
		if Rect2(item.rect).has_point(point): return true
	for rect: Rect2 in overlay_rects:
		if rect.has_point(point): return true
	var screen: Vector2 = get_viewport_rect().size
	if not Rect2(Vector2.ZERO, screen).has_point(point): return true
	if not main.build_kind.is_empty() and _construction_preview_rect(screen).has_point(point): return true
	if not main.construction_readout.is_empty() and main.build_kind.is_empty() and _construction_details_rect(screen).has_point(point): return true
	return point.y < 64 or point.y >= screen.y - 190 or Rect2(18, 82, 300, 305).has_point(point) or Rect2(screen.x - 268, 82, 250, maxf(0, screen.y - 482)).has_point(point)

func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var key: Array = [fill, border]
	if _panel_styles.has(key): return _panel_styles[key]
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	if _panel_styles.size() >= PANEL_STYLE_CACHE_LIMIT:
		_panel_styles.erase(_panel_styles.keys()[0])
	_panel_styles[key] = style
	return style

func _panel(rect: Rect2, fill: Color, border: Color) -> void:
	draw_style_box(_panel_style(fill, border), rect)

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
	var lines: Array[String] = _wrap_text(text, 332, size_value, false)
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
