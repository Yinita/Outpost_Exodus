extends RefCounted
## Read-only, state-driven first-campaign guidance. This never issues game orders.
## Hints may be ignored; completed or superseded milestones are inferred from sim.

const SAVE_VERSION: int = 1
const TOTAL_STEPS: int = 11
const UNKNOWN_TARGET: Vector2 = Vector2(-1.0, -1.0)
const OBSERVABLE_ACTIONS: Array[String] = ["selection", "move", "clear", "build", "orders", "production", "train", "evacuate", "seal"]

var _enabled: bool = true
var _dismissed: bool = false
var _preferred_branch: String = "any"
var _observed: Array[String] = []
var _bound: bool = false
var _campaign_seed: int = 0
var _last_sim_time: float = 0.0
var _hint: Dictionary = {
	"title": "带4人清理公路补给", "text": "框选3名步枪兵和1名工程师。可用{pause}暂停观察，再用{orders}选择清剿目标。",
	"target": UNKNOWN_TARGET, "action": "none", "label": "", "step": 1, "total": TOTAL_STEPS, "complete": false
}


func reset(enabled: bool = true) -> void:
	_enabled = enabled
	_dismissed = false
	_preferred_branch = "any"
	_observed.clear()
	_bound = false
	_campaign_seed = 0
	_last_sim_time = 0.0
	_set_hint(1, "带4人清理公路补给", "框选3名步枪兵和1名工程师。可用{pause}暂停观察，再用{orders}选择清剿目标。", UNKNOWN_TARGET)


func update(sim: Variant, selected_ids: Array = [], selected_camp: int = 0) -> void:
	if sim == null:
		return
	var now: float = float(sim.time)
	var mission_seed: int = int(sim.seed_value)
	if _bound and (mission_seed != _campaign_seed or now + 0.001 < _last_sim_time):
		# A new/reset/rewound simulation must not inherit another run's route facts.
		# Visibility is a user preference and survives automatic rebinding.
		_preferred_branch = "any"
		_observed.clear()
	_bound = true
	_campaign_seed = mission_seed
	_last_sim_time = now
	var exit_site: Dictionary = _site(sim, "exit", 60.0, 80.0)
	var exit_position: Vector2 = exit_site.get("pos", Vector2(72.0, 19.0))
	if String(sim.outcome) == "victory":
		_set_hint(TOTAL_STEPS, "突围完成", "指挥车和幸存者已实际抵达。你可以重新开始尝试另一条资源顺序，也可以隐藏引导。", exit_position, true)
		return
	if String(sim.outcome) == "defeat":
		_set_hint(int(_hint.get("step", 1)), "本次突围结束", "本轮未完成撤离。重新开始会重置路线提示；下一次可用{pause}留出判断时间，优先保住指挥车与幸存者。", UNKNOWN_TARGET)
		return
	var exit_building: Dictionary = _building(sim, "exit", -1)
	if not exit_building.is_empty() and float(exit_building.get("progress", 0.0)) >= 1.0 and bool(exit_building.get("powered", false)):
		_arrival_hint(sim, exit_position)
		return
	if not exit_building.is_empty() and bool(exit_building.get("construction_started", false)):
		_exit_hint(sim, exit_site, exit_building)
		return
	var camps: Array[Dictionary] = _ordered_camps(sim)
	if camps.is_empty():
		_set_hint(1, "寻找可用营地", "当前没有可接收物资的营地。保护幸存者；若本轮已无法继续，可以从暂停菜单重新开始。", UNKNOWN_TARGET)
		return
	var home: Dictionary = camps[0]
	var middle: Dictionary = {}
	var front: Dictionary = {}
	for camp: Dictionary in camps:
		var camp_position: Vector2 = camp.get("pos", Vector2.ZERO)
		if String(camp.get("state", "")) == "abandoned":
			continue
		if camp_position.x >= 45.0:
			front = camp
		elif camp_position.x >= 20.0:
			middle = camp
	if not front.is_empty():
		_forward_hint(sim, camps, front, exit_site, exit_building, selected_camp)
		return
	if not middle.is_empty():
		_middle_hint(sim, home, middle, selected_camp)
		return
	var highway: Dictionary = _site(sim, "cache", 20.0, 40.0)
	var highway_position: Vector2 = highway.get("pos", Vector2(25.0, 20.0))
	if not bool(highway.get("captured", false)):
		var selected_fighters: int = 0
		var first_fighter: Vector2 = home.get("pos", Vector2(9.0, 22.0))
		var units: Array = sim.units
		for value: Variant in units:
			var unit: Dictionary = value
			if String(unit.get("team", "")) == "friendly" and ["rifle", "engineer"].has(String(unit.get("kind", ""))) and float(unit.get("hp", 0.0)) > 0.0:
				first_fighter = unit.get("pos", first_fighter)
				if selected_ids.has(int(unit.get("id", -1))):
					selected_fighters += 1
		if selected_fighters < 4:
			_set_hint(1, "带4人清理公路补给", "先框选3名步枪兵和1名工程师，用{orders}选择清剿，再点公路补给点。可用{pause}观察地形；清掉守卫后留人在附近，完成占领再修路。", first_fighter)
		else:
			_set_hint(1, "清理西关东侧的公路补给", "用{orders}选择清剿并指定公路补给点，或下达攻击移动。清掉守卫并留人在附近占领；工程师可随队，战斗中可用{pause}调整。", highway_position)
		return
	var road_target: Vector2 = Vector2(26.0, 21.0)
	if not bool(sim.road_connected(Vector2(home["pos"]), road_target)):
		var road_text: String = "打开{build}选择道路，在定位点附近下单。道路会沿可通行路线逐格施工；工人送达材料并完工后才形成连接。"
		if _pending_road_near(sim, road_target):
			road_text = "道路已规划，等待工人领取建材并逐格铺设。先不要重复下单；规划线还不能运货，可用{pause}检查工人和施工进度。"
		_set_hint(2, "铺通通往中营的道路", road_text, road_target)
		return
	var camp_site: Vector2 = Vector2(26.0, 23.0)
	var camp_project: Dictionary = _camp_project(sim, 20.0, 45.0)
	if not camp_project.is_empty():
		_set_hint(3, "等待中营实际建成", "中营工地已存在。工程师要领取、运送材料并完成施工；完工前不会出现可用库存，也不要重复建造。", camp_project.get("pos", camp_site))
	else:
		_set_hint(3, "在关口东侧建立中营", "用{build}在已连通的公路附近建营地，定位点只是建议位置。新营建成时库存为零，下一步先从旧营运输物资，再考虑发电与工坊。", camp_site)


func _middle_hint(sim: Variant, home: Dictionary, middle: Dictionary, selected_camp: int) -> void:
	var middle_id: int = int(middle["id"])
	if not _setup_funded(sim, middle):
		if String(home.get("state", "")) != "abandoned" or _incoming_transfer(sim, middle_id):
			_transfer_hint(sim, home, middle, 4, selected_camp)
		else:
			_funding_hint(sim, middle, 4)
		return
	if _optional_seal_hint(sim, middle):
		return
	if _infrastructure_hint(sim, middle, 5):
		return
	if _branch_hint(sim, middle):
		return
	var east_site: Dictionary = _site(sim, "cache", 45.0, 65.0)
	var east_position: Vector2 = east_site.get("pos", Vector2(53.0, 21.0))
	if not bool(east_site.get("captured", false)):
		_set_hint(7, "清理东侧旧营址", "带战斗小队清理东侧旧营址。你可用{train}在供能军营补充兵力；先后选择资源支线都可以，推进前留意中营的口粮与燃料。", east_position)
		return
	if not bool(sim.road_connected(Vector2(middle["pos"]), east_position)):
		_set_hint(7, "把公路接向东侧营址", "用{build}把道路接到东侧旧营址附近，等待真实施工完成。可分段修路控制开销；铺路本身不会把中营库存搬过去。", Vector2(53.0, 22.0))
		return
	var camp_project: Dictionary = _camp_project(sim, 45.0, 80.0)
	if not camp_project.is_empty():
		_set_hint(7, "等待东侧前营完工", "工程师正在建立前营。保留中营物资与运输车，等前营成为有效接收点，再用{orders}撤收后营。", camp_project.get("pos", Vector2(54.0, 23.0)))
	else:
		_set_hint(7, "向东建立接收物资的前营", "用{build}在已连路的东侧营址附近建营地。先保留撤营与启动资金，前营建成后用{orders}把中营的人员和物资实际运过去。", Vector2(54.0, 23.0))


func _forward_hint(sim: Variant, camps: Array[Dictionary], front: Dictionary, exit_site: Dictionary, exit_building: Dictionary, selected_camp: int) -> void:
	var rear: Dictionary = {}
	for camp: Dictionary in camps:
		if Vector2(camp["pos"]).x < Vector2(front["pos"]).x - 5.0 and String(camp.get("state", "")) != "abandoned":
			rear = camp
	var front_id: int = int(front["id"])
	if not _setup_funded(sim, front) and (not rear.is_empty() or _incoming_transfer(sim, front_id)):
		_transfer_hint(sim, rear, front, 8, selected_camp)
		return
	if not rear.is_empty():
		_transfer_hint(sim, rear, front, 8, selected_camp)
		return
	if _incoming_transfer(sim, front_id):
		_transfer_hint(sim, rear, front, 8, selected_camp)
		return
	if _infrastructure_hint(sim, front, 9):
		return
	_exit_hint(sim, exit_site, exit_building)


func _optional_seal_hint(sim: Variant, camp: Dictionary) -> bool:
	# A safe optional detour, superseded by starting local construction.
	# No observed click is treated as a sealed barrier; sim remains authoritative.
	var generators: Dictionary = _building(sim, "generator", int(camp["id"]))
	var chokes: Array = sim.chokes
	if not generators.is_empty() or chokes.is_empty():
		return false
	var choke: Dictionary = chokes[0]
	var position: Vector2 = choke.get("pos", UNKNOWN_TARGET)
	if bool(choke.get("sealed", false)) or _friendlies_behind(sim, 0) > 0 or position.x < float(sim.pursuit_x) + 1.0:
		return false
	if float(camp.get("materials", 0.0)) < 105.0:
		return false
	_set_hint(5, "可选：安全封住后关争取时间", "人员和车辆已越过西关，可在{orders}使用“封锁后关”，消耗25建材拖延追兵。也可直接用{build}继续本营发电与工坊，引导不会限制你的选择。", position)
	return true


func _transfer_hint(sim: Variant, origin: Dictionary, destination: Dictionary, step_number: int, selected_camp: int) -> void:
	var destination_id: int = int(destination["id"])
	var transfer: Dictionary = _transfer_truck(sim, destination_id)
	var target: Vector2 = destination.get("pos", UNKNOWN_TARGET)
	if not origin.is_empty() and String(origin.get("state", "")) == "active":
		target = origin.get("pos", target)
		var selection_note: String = "先选中后方营地。" if selected_camp != int(origin["id"]) else "当前已选中要撤收的后营。"
		_set_hint(step_number, "先撤收旧营，给新营运入资金", selection_note + "打开{orders}选择撤营。新营不会凭空获得库存；运输车实际卸货后，再在新营建设发电机和工坊。", target)
		return
	if not transfer.is_empty():
		target = transfer.get("pos", target)
	var stock_text: String = "接收营当前：建材%d、燃料%d。" % [int(destination.get("materials", 0.0)), int(destination.get("fuel", 0.0))]
	if not origin.is_empty() and String(origin.get("state", "")) == "packing":
		var pursuit_gap: float = Vector2(origin.get("pos", UNKNOWN_TARGET)).x - float(sim.pursuit_x)
		if _setup_funded(sim, destination) or pursuit_gap < 10.0:
			_set_hint(step_number, "后营撤收：等待运输或紧急弃营", stock_text + "可继续等待搬运；也可再次点击{orders}里的“撤收驻点”紧急弃营。未装车物资会留在旧营，车上货物继续送达；封关前确认人员已通过。", target)
			return
	var safety: String = "等人员和车都到关口东侧，再考虑{orders}封关；也可自行选择分兵留守。"
	if _friendlies_behind(sim, 0) > 0:
		safety = "仍有友军在西关后方，暂时别封关；可用{pause}查看撤离队伍。"
	_set_hint(step_number, "等待运输车装运和卸货", stock_text + "不要手动改运输车命令。" + safety, target)


func _funding_hint(sim: Variant, camp: Dictionary, step_number: int) -> void:
	var target_site: Dictionary = _available_cache(sim)
	var target: Vector2 = target_site.get("pos", camp.get("pos", UNKNOWN_TARGET))
	_set_hint(step_number, "先补回本营启动物资", "本营库存不足以启动发电与工坊。先接收实际运输，或清理、连路回收补给；不要把全局总库存误当成本营可用资金。", target)


func _infrastructure_hint(sim: Variant, camp: Dictionary, step_number: int) -> bool:
	var camp_id: int = int(camp["id"])
	var camp_position: Vector2 = camp.get("pos", UNKNOWN_TARGET)
	if String(camp.get("state", "")) != "active":
		return false
	for kind: String in ["generator", "workshop"]:
		var building: Dictionary = _building(sim, kind, camp_id)
		var label: String = "发电机" if kind == "generator" else "工坊"
		var suggestion: Vector2 = _suggest_build_tile(sim, camp_position + (Vector2(2.0, -1.0) if kind == "generator" else Vector2(4.0, 1.0)))
		if building.is_empty():
			if not _can_afford(sim, camp, kind):
				_funding_hint(sim, camp, step_number)
				return true
			if suggestion != UNKNOWN_TARGET and not bool(sim.road_connected(camp_position, suggestion)):
				_set_hint(step_number, "先把本地道路接到设施附近", "用{build}把道路接到建议施工点附近。发电机和工坊都需要连接本营道路；营地之间的库存与电力不会远程共享。", suggestion)
				return true
			_set_hint(step_number, "在本营附近建立" + label, "用{build}建" + label + "，位置可自行调整。发电机需要成品燃料并只供附近设施；工坊完工、连路、供能后才能用{production}加工原料。", suggestion)
			return true
		var position: Vector2 = building.get("pos", camp_position)
		if float(building.get("progress", 0.0)) < 1.0:
			_set_hint(step_number, "等待" + label + "施工完成", "工地已经下单。工程师需要实际送料和施工；避免重复建设或手动打断施工队，可用{pause}检查进度。", position)
			return true
		if not bool(sim.road_connected(camp_position, position)):
			_set_hint(step_number, "修复" + label + "的本地道路", "建筑已经完成，但还没连接本营道路。用{build}补上连接，再检查供电；其他营地的道路和库存不能替代本地连接。", position)
			return true
		if not bool(building.get("powered", false)):
			var detail: String = "检查本营成品燃料、发电机半径和电力优先级。"
			if float(camp.get("fuel", 0.0)) <= 0.01:
				_classify_no_fuel_hint(sim, camp, step_number)
				return true
			_set_hint(step_number, "让" + label + "获得本地供能", detail + "可在{production}查看配方和优先级；电力由本营附近的实际发电机提供。", position)
			return true
	return false


func _classify_no_fuel_hint(sim: Variant, camp: Dictionary, step_number: int) -> void:
	var cache: Dictionary = _available_cache(sim)
	_set_hint(step_number, "恢复本营的成品燃料", "发电机缺少成品燃料，原油不能直接燃烧。先接收撤营燃料或回收补给；供能恢复后，可用{production}把运回的原油加工成燃料。", cache.get("pos", camp.get("pos", UNKNOWN_TARGET)))


func _branch_hint(sim: Variant, camp: Dictionary) -> bool:
	var north: Dictionary = _site(sim, "quarry", 0.0, 80.0)
	var south: Dictionary = _site(sim, "fuel", 0.0, 80.0)
	var ordered: Array[Dictionary] = [north, south]
	if _preferred_branch == "south" or (_preferred_branch == "any" and float(camp.get("fuel", 0.0)) < 20.0):
		ordered = [south, north]
	for site: Dictionary in ordered:
		if site.is_empty():
			continue
		var at: Vector2 = site.get("pos", UNKNOWN_TARGET)
		var name: String = String(site.get("name", "资源支线"))
		if not bool(site.get("captured", false)):
			_set_hint(6, "选择资源支线：" + name, "北线废料可加工建材，南线原油可加工燃料，先后顺序由你决定。带队清剿后还要连路，让工人实际运回，再用{production}选择配方。", at)
			return true
		if not bool(sim.road_connected(Vector2(camp["pos"]), at)):
			_set_hint(6, "把" + name + "接入营地道路", "此处已清理，但资源不会自动到账。用{build}连路，工人才能往返搬运；保留本营启动资金，再用{production}加工带回的原料。", at)
			return true
	return false


func _exit_hint(sim: Variant, exit_site: Dictionary, exit_building: Dictionary) -> void:
	var target: Vector2 = exit_site.get("pos", Vector2(72.0, 19.0))
	if not bool(exit_site.get("captured", false)):
		_set_hint(10, "先清理撤离站守卫", "带战斗小队清理东部撤离站并留人在附近占领。此时仍可{pause}整队；军营与{train}用于补充兵力，别把指挥车送进未清理的敌群。", target)
		return
	var active_camp: Dictionary = _east_active_camp(sim)
	if active_camp.is_empty():
		_set_hint(10, "为撤离站保留接收营地", "撤离站已清理，但需要一个可用营地提供本地物资、工程师与道路。先建立或保住东侧营地，别提前弃掉最后一个补给点。", target)
		return
	if not bool(sim.road_connected(Vector2(active_camp["pos"]), target)):
		_set_hint(10, "把前营道路接到撤离站", "用{build}把道路接到撤离站。守卫清理、道路完成并且本营物资足够后，工程会自动立项；无需重复建造出口。", target)
		return
	if exit_building.is_empty() or not bool(exit_building.get("construction_started", false)):
		var exit_cost: Dictionary = _cost(sim, "exit")
		var cost_text: String = "需要本营建材%d、燃料%d、口粮%d。" % [int(exit_cost.get("materials", 140.0)), int(exit_cost.get("fuel", 45.0)), int(exit_cost.get("supplies", 30.0))]
		_set_hint(10, "备齐撤离站施工物资", cost_text + "物资必须实际进入前营。用{production}加工原料并保留燃料；达到条件后会自动扣费立项，随后由工程师施工。", active_camp.get("pos", target))
		return
	if not bool(exit_building.get("powered", false)):
		_set_hint(10, "为出口施工提供本地电力", "撤离站工程已立项，需要附近发电机持续提供6电力。用{build}在出口附近接路建发电机，确保所属营地有成品燃料，并在{production}优先保障撤离供能。", target + Vector2(-2.0, 2.0))
		return
	_set_hint(10, "保护工程师，等待撤离站完工", "道路、资金和供能已就绪，工程师仍需实际到场施工。守住出口与运输线；可以整队、修理，等真实建造进度完成后再全员到场。", target)


func _arrival_hint(sim: Variant, exit_position: Vector2) -> void:
	var truck: Dictionary = sim.get_unit(int(sim.main_truck_id))
	var people: int = 0
	var units: Array = sim.units
	for value: Variant in units:
		var unit: Dictionary = value
		if String(unit.get("team", "")) == "friendly" and String(unit.get("kind", "")) != "truck" and float(unit.get("hp", 0.0)) > 0.0 and Vector2(unit.get("pos", UNKNOWN_TARGET)).distance_to(exit_position) <= 5.0:
			people += 1
	var truck_arrived: bool = not truck.is_empty() and Vector2(truck.get("pos", UNKNOWN_TARGET)).distance_to(exit_position) <= 5.0
	var arrival_text: String = "出口已完工并供能。将指挥车和至少4名幸存者送到撤离站5格范围内；目前到场%d人，指挥车%s。" % [people, "已到" if truck_arrived else "未到"]
	_set_hint(11, "让指挥车与幸存者到场", arrival_text + "别先封住还有己方人员在后面的关口。", exit_position)


func _setup_funded(sim: Variant, camp: Dictionary) -> bool:
	var camp_id: int = int(camp["id"])
	var materials: float = 0.0
	var fuel: float = 0.0
	for kind: String in ["generator", "workshop"]:
		if _building(sim, kind, camp_id).is_empty():
			var costs: Dictionary = _cost(sim, kind)
			materials += float(costs.get("materials", 0.0))
			fuel += float(costs.get("fuel", 0.0))
	if materials > 0.0:
		var workshop_spot: Vector2 = Vector2(camp["pos"]) + Vector2(4.0, 1.0)
		if not bool(sim.road_connected(Vector2(camp["pos"]), workshop_spot)):
			materials += 10.0
		fuel += 1.0
	return float(camp.get("materials", 0.0)) >= materials and float(camp.get("fuel", 0.0)) >= fuel


func _can_afford(sim: Variant, camp: Dictionary, kind: String) -> bool:
	var costs: Dictionary = _cost(sim, kind)
	for key: Variant in costs:
		if float(camp.get(key, 0.0)) < float(costs[key]):
			return false
	return true


func _cost(sim: Variant, kind: String) -> Dictionary:
	var script: Script = sim.get_script() as Script
	if script == null:
		return {}
	var constants: Dictionary = script.get_script_constant_map()
	var table: Dictionary = constants.get("BUILD_COSTS", {})
	return Dictionary(table.get(kind, {}))


func _ordered_camps(sim: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var camps: Array = sim.camps
	for value: Variant in camps:
		result.append(value)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Vector2(a["pos"]).x < Vector2(b["pos"]).x)
	return result


func _east_active_camp(sim: Variant) -> Dictionary:
	var result: Dictionary = {}
	for camp: Dictionary in _ordered_camps(sim):
		if String(camp.get("state", "")) == "active":
			result = camp
	return result


func _site(sim: Variant, kind: String, minimum_x: float, maximum_x: float) -> Dictionary:
	var sites: Array = sim.sites
	for value: Variant in sites:
		var site: Dictionary = value
		var at: Vector2 = site.get("pos", UNKNOWN_TARGET)
		if String(site.get("kind", "")) == kind and at.x >= minimum_x and at.x < maximum_x:
			return site
	return {}


func _building(sim: Variant, kind: String, camp_id: int) -> Dictionary:
	var result: Dictionary = {}
	var buildings: Array = sim.buildings
	for value: Variant in buildings:
		var building: Dictionary = value
		if String(building.get("kind", "")) != kind or float(building.get("hp", 0.0)) <= 0.0 or bool(building.get("abandoned", false)):
			continue
		if camp_id >= 0 and int(building.get("camp_id", -1)) != camp_id:
			continue
		if result.is_empty() or float(building.get("progress", 0.0)) > float(result.get("progress", 0.0)):
			result = building
	return result


func _camp_project(sim: Variant, minimum_x: float, maximum_x: float) -> Dictionary:
	var buildings: Array = sim.buildings
	for value: Variant in buildings:
		var building: Dictionary = value
		var at: Vector2 = building.get("pos", UNKNOWN_TARGET)
		if String(building.get("kind", "")) == "camp" and float(building.get("progress", 0.0)) < 1.0 and float(building.get("hp", 0.0)) > 0.0 and at.x >= minimum_x and at.x < maximum_x:
			return building
	return {}


func _pending_road_near(sim: Variant, position: Vector2) -> bool:
	var roads: Dictionary = sim.roads
	for key: Variant in roads:
		var data: Variant = roads[key]
		if data is Dictionary and float(data.get("progress", 1.0)) < 1.0 and Vector2(key).distance_to(position) < 4.0:
			return true
	return false


func _suggest_build_tile(sim: Variant, preferred: Vector2) -> Vector2:
	var candidates: Array[Vector2i] = []
	var tile: Vector2i = Vector2i(preferred.round())
	candidates.append(tile)
	for radius: int in range(1, 5):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) == radius:
					candidates.append(tile + Vector2i(dx, dy))
	var buildings: Array = sim.buildings
	for candidate: Vector2i in candidates:
		if not bool(sim.is_walkable(candidate)):
			continue
		var clear: bool = true
		for value: Variant in buildings:
			var building: Dictionary = value
			if float(building.get("hp", 0.0)) > 0.0 and Vector2(building.get("pos", UNKNOWN_TARGET)).distance_to(Vector2(candidate)) < 1.7:
				clear = false
				break
		if clear:
			return Vector2(candidate)
	return UNKNOWN_TARGET


func _transfer_truck(sim: Variant, destination_id: int) -> Dictionary:
	var units: Array = sim.units
	for value: Variant in units:
		var unit: Dictionary = value
		if String(unit.get("kind", "")) == "truck" and String(unit.get("order", "")) == "evacuate_transport" and int(unit.get("evac_destination_id", -1)) == destination_id and float(unit.get("hp", 0.0)) > 0.0:
			return unit
	return {}


func _incoming_transfer(sim: Variant, destination_id: int) -> bool:
	return not _transfer_truck(sim, destination_id).is_empty()


func _available_cache(sim: Variant) -> Dictionary:
	var sites: Array = sim.sites
	for value: Variant in sites:
		var site: Dictionary = value
		if String(site.get("kind", "")) != "cache" or Vector2(site.get("pos", UNKNOWN_TARGET)).x < float(sim.pursuit_x) + 1.0:
			continue
		var stock: Dictionary = site.get("stock", {})
		if float(stock.get("materials", 0.0)) > 0.0 or float(stock.get("fuel", 0.0)) > 0.0:
			return site
	return {}


func _friendlies_behind(sim: Variant, choke_index: int) -> int:
	var chokes: Array = sim.chokes
	if choke_index < 0 or choke_index >= chokes.size():
		return 0
	var choke: Dictionary = chokes[choke_index]
	var boundary: float = Vector2(choke.get("pos", Vector2.ZERO)).x + 0.8
	var count: int = 0
	var units: Array = sim.units
	for value: Variant in units:
		var unit: Dictionary = value
		if String(unit.get("team", "")) == "friendly" and float(unit.get("hp", 0.0)) > 0.0 and String(unit.get("state", "")) != "evacuated" and Vector2(unit.get("pos", UNKNOWN_TARGET)).x < boundary:
			count += 1
	return count


func observe(action: String, data: Dictionary = {}) -> void:
	if ["show", "resume", "restore"].has(action):
		_enabled = true
		_dismissed = false
	elif ["hide", "dismiss"].has(action):
		dismiss()
	elif action == "disable":
		_enabled = false
	elif action == "branch":
		var branch: String = String(data.get("kind", ""))
		if ["north", "south", "any"].has(branch):
			_preferred_branch = branch
	elif OBSERVABLE_ACTIONS.has(action) and not _observed.has(action):
		_observed.append(action)
	if ["clear", "move"].has(action):
		var raw_target: Variant = data.get("target", UNKNOWN_TARGET)
		if raw_target is Vector2 or raw_target is Vector2i:
			var target: Vector2 = Vector2(raw_target)
			if target.x >= 28.0 and target.x <= 44.0:
				if target.y < 17.0:
					_preferred_branch = "north"
				elif target.y > 25.0:
					_preferred_branch = "south"


func dismiss() -> void:
	_dismissed = true


func get_hint() -> Dictionary:
	var result: Dictionary = _hint.duplicate(true)
	result["visible"] = _enabled and not _dismissed
	result["enabled"] = _enabled
	result["dismissed"] = _dismissed
	return result


func _set_hint(step_number: int, title: String, text: String, target: Vector2, complete: bool = false) -> void:
	var valid: bool = _valid_target(target)
	_hint = {
		"title": title, "text": text, "target": target if valid else UNKNOWN_TARGET,
		"action": "focus" if valid and not complete else "none",
		"label": "定位提示目标" if valid and not complete else "",
		"step": clampi(step_number, 1, TOTAL_STEPS), "total": TOTAL_STEPS, "complete": complete
	}


func save_state() -> Dictionary:
	var hint: Dictionary = _hint.duplicate(true)
	var target: Vector2 = hint.get("target", UNKNOWN_TARGET)
	hint["target"] = [target.x, target.y]
	return {
		"version": SAVE_VERSION, "enabled": _enabled, "dismissed": _dismissed,
		"preferred_branch": _preferred_branch, "observed": _observed.duplicate(),
		"bound": _bound, "campaign_seed": _campaign_seed, "last_sim_time": _last_sim_time,
		"hint": hint
	}


func load_state(data: Dictionary) -> bool:
	# Validate every field and build replacements locally before touching live state.
	var required: Array[String] = ["version", "enabled", "dismissed", "preferred_branch", "observed", "bound", "campaign_seed", "last_sim_time", "hint"]
	for key: String in required:
		if not data.has(key):
			return false
	if data.size() != required.size():
		return false
	if not _integer(data["version"]) or int(data["version"]) != SAVE_VERSION:
		return false
	if not data["enabled"] is bool or not data["dismissed"] is bool or not data["bound"] is bool:
		return false
	if not data["preferred_branch"] is String or not ["any", "north", "south"].has(data["preferred_branch"]):
		return false
	if not _integer(data["campaign_seed"]) or absf(float(data["campaign_seed"])) > 2147483647.0:
		return false
	if not _number(data["last_sim_time"]) or float(data["last_sim_time"]) < 0.0 or float(data["last_sim_time"]) > 100000000.0:
		return false
	if not data["observed"] is Array or Array(data["observed"]).size() > OBSERVABLE_ACTIONS.size():
		return false
	var observations: Array[String] = []
	for value: Variant in data["observed"]:
		if not value is String or not OBSERVABLE_ACTIONS.has(value) or observations.has(value):
			return false
		observations.append(value)
	if not data["hint"] is Dictionary:
		return false
	var hint: Dictionary = Dictionary(data["hint"]).duplicate(true)
	if hint.size() != 8:
		return false
	for key: String in ["title", "text", "target", "action", "label", "step", "total", "complete"]:
		if not hint.has(key):
			return false
	for key: String in ["title", "text", "action", "label"]:
		if not hint[key] is String or String(hint[key]).length() > (2048 if key == "text" else 128):
			return false
	if not ["focus", "none"].has(hint["action"]) or not hint["complete"] is bool:
		return false
	if not _integer(hint["step"]) or int(hint["step"]) < 1 or int(hint["step"]) > TOTAL_STEPS:
		return false
	if not _integer(hint["total"]) or int(hint["total"]) != TOTAL_STEPS:
		return false
	if not hint["target"] is Array or Array(hint["target"]).size() != 2:
		return false
	var coordinates: Array = hint["target"]
	if not _number(coordinates[0]) or not _number(coordinates[1]):
		return false
	var target: Vector2 = Vector2(float(coordinates[0]), float(coordinates[1]))
	if target != UNKNOWN_TARGET and not _valid_target(target):
		return false
	if String(hint["action"]) == "focus" and (target == UNKNOWN_TARGET or bool(hint["complete"])):
		return false
	if bool(hint["complete"]) and int(hint["step"]) != TOTAL_STEPS:
		return false
	hint["target"] = target
	hint["step"] = int(hint["step"])
	hint["total"] = TOTAL_STEPS
	_enabled = bool(data["enabled"])
	_dismissed = bool(data["dismissed"])
	_preferred_branch = String(data["preferred_branch"])
	_observed = observations
	_bound = bool(data["bound"])
	_campaign_seed = int(data["campaign_seed"])
	_last_sim_time = float(data["last_sim_time"])
	_hint = hint
	return true


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


func _valid_target(target: Vector2) -> bool:
	return is_finite(target.x) and is_finite(target.y) and target.x >= 0.0 and target.x < 80.0 and target.y >= 0.0 and target.y < 40.0
