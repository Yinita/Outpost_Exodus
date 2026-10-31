extends RefCounted
## Read-only order planning and presentation queries. Simulation owns all commits.

const RESOURCE_NAMES: Dictionary = {"materials": "建材", "supplies": "补给", "fuel": "燃料", "salvage": "废料", "crude": "原油"}


static func query_build(sim: Variant, kind: String, tile: Vector2i, build_costs: Dictionary, refresh_navigation: bool = true) -> Dictionary:
	var road_tiles: Array[Vector2i] = []
	var result: Dictionary = {"ok": false, "code": "", "message": "", "camp_id": 0, "camp_name": "", "costs": {}, "missing": {}, "position": Vector2(tile), "road_tiles": road_tiles, "warning": ""}
	if sim.outcome != "playing":
		return _reject(result, "not_playing", "战役已经结束，无法安排施工。")
	if not build_costs.has(kind):
		return _reject(result, "unknown_kind", "无法安排这种建筑。")
	result["costs"] = Dictionary(build_costs[kind]).duplicate(true)
	if kind == "exit":
		return _reject(result, "automatic_exit", "撤离站在占领、道路连通且本营物资足够后自动立项。")
	sim._ensure_navigation_index(refresh_navigation)
	if not sim._terrain_walkable(tile):
		return _reject(result, "terrain", "不能在悬崖或地图边缘施工。")
	var position: Vector2 = Vector2(tile)
	var camp: Dictionary = sim._nearest_camp(position)
	if camp.is_empty():
		return _reject(result, "no_active_camp", "没有可供料的运作中营地；撤收中或已撤空的营地不能接单。")
	result["camp_id"] = int(camp["id"])
	result["camp_name"] = str(camp.get("name", "营地"))
	if kind == "road":
		return _query_road(sim, tile, camp, result)
	result["missing"] = _missing(camp, result["costs"])
	for existing in sim.buildings:
		if float(existing["hp"]) > 0.0 and Vector2(existing["pos"]).distance_to(position) < 1.7:
			return _reject(result, "spacing", "建筑之间需要留出通行与施工空间。")
	if position.x < sim.pursuit_x + 1.0:
		return _reject(result, "pursuit", "该区域已被主尸潮淹没。")
	if Vector2(camp["pos"]).distance_to(position) > 13.0 and not sim._road_connected(Vector2(camp["pos"]), position):
		return _reject(result, "road_connection", "先将道路铺到施工点附近，再建立远方设施。")
	if sim._find_path(Vector2(camp["pos"]), position).is_empty():
		return _reject(result, "unreachable", "施工队无法到达这里；检查坡道和关口。")
	if not sim._can_pay(camp, result["costs"]):
		return _reject(result, "resources", _shortage_text(camp, result["missing"]))
	result["ok"] = true
	result["code"] = "ready"
	result["message"] = "可下单：%s供料，需%s。" % [result["camp_name"], _cost_text(result["costs"])]
	result["warning"] = _builder_warning(sim)
	return result


static func _query_road(sim: Variant, tile: Vector2i, camp: Dictionary, result: Dictionary) -> Dictionary:
	# A total price exists only after a route has been planned, not for an
	# unreachable or already ordered destination.
	result["costs"] = {}
	if sim.roads.has(tile):
		var data: Variant = sim.roads[tile]
		var complete: bool = not data is Dictionary or float(data.get("progress", 1.0)) >= 1.0
		return _reject(result, "road_exists" if complete else "road_planned", "这里已有道路。" if complete else "这里已有道路工地；等待施工，无需重复下单。")
	var start: Vector2 = Vector2(camp["pos"])
	var best_distance: float = INF
	for existing_tile in sim.roads:
		var data: Variant = sim.roads[existing_tile]
		var complete: bool = not data is Dictionary or float(data.get("progress", 1.0)) >= 1.0
		if not complete:
			continue
		var test: float = Vector2(existing_tile).distance_squared_to(Vector2(tile))
		if test < best_distance and sim._road_connected(Vector2(camp["pos"]), Vector2(existing_tile)):
			start = Vector2(existing_tile)
			best_distance = test
	var path: Array = sim._find_path(start, Vector2(tile), "road")
	if path.is_empty():
		return _reject(result, "road_unreachable", "道路无法跨越悬崖；请利用坡道或现有桥面。")
	var new_tiles: Array[Vector2i] = []
	for waypoint in path:
		var at: Vector2i = Vector2i(Vector2(waypoint).round())
		if not sim.roads.has(at):
			new_tiles.append(at)
	result["road_tiles"] = new_tiles
	result["costs"] = {"materials": float(new_tiles.size()) * 2.0}
	result["missing"] = _missing(camp, result["costs"])
	if new_tiles.is_empty():
		return _reject(result, "road_no_new_tiles", "这段路线没有需要新铺的道路。")
	if not sim._can_pay(camp, result["costs"]):
		return _reject(result, "resources", "这段道路共%d格，需要%d建材。%s 可先铺较短一段。" % [new_tiles.size(), int(result["costs"]["materials"]), _shortage_text(camp, result["missing"])])
	result["ok"] = true
	result["code"] = "ready"
	result["message"] = "可下单：%s供料，%d格道路共需%d建材。" % [result["camp_name"], new_tiles.size(), int(result["costs"]["materials"])]
	result["warning"] = _builder_warning(sim)
	return result


static func _reject(result: Dictionary, code: String, message: String) -> Dictionary:
	result["code"] = code
	result["message"] = message
	return result


static func _missing(camp: Dictionary, costs: Dictionary) -> Dictionary:
	var missing: Dictionary = {}
	for key in costs:
		var amount: float = float(costs[key]) - float(camp.get(key, 0.0))
		if amount > 0.0001:
			missing[key] = amount
	return missing


static func _amount(value: float) -> String:
	if value > 0.0 and value < 0.01:
		return "不足0.01"
	return String.num(value, 2).trim_suffix("0").trim_suffix("0").trim_suffix(".")


static func _cost_text(costs: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in costs:
		parts.append(str(RESOURCE_NAMES.get(key, key)) + _amount(float(costs[key])))
	return " / ".join(parts)


static func _shortage_text(camp: Dictionary, missing: Dictionary) -> String:
	return "%s本地缺少%s；其他营地库存不会直接支付。" % [str(camp.get("name", "营地")), _cost_text(missing)]


static func _builder_warning(sim: Variant) -> String:
	for builder in sim.units:
		if str(builder["team"]) != "friendly" or not ["engineer", "worker"].has(str(builder["kind"])) or float(builder["hp"]) <= 0.0:
			continue
		if int(builder.get("job_id", 0)) == 0 and not bool(builder.get("manual", false)) and str(builder.get("order", "idle")) == "idle" and Dictionary(builder.get("cargo", {})).is_empty():
			return ""
	return "暂无空闲工人或工程师；可先下单，待施工队空闲后施工。"


static func get_construction_status(sim: Variant, building_id: int) -> Dictionary:
	# Observe the existing parcel/job only. No allocator, routing or simulation step.
	var building: Dictionary = sim._get_building(building_id)
	if building.is_empty() or float(building.get("hp", 0.0)) <= 0.0 or bool(building.get("abandoned", false)) or float(building.get("progress", 1.0)) >= 1.0:
		return {}
	var result: Dictionary = {"building_id": building_id, "name": sim._building_name(str(building.get("kind", ""))), "progress": float(building.get("progress", 0.0)), "source_name": "记录不可用", "builder_text": "未指定", "code": "missing_job", "text": "施工记录不可用。", "paused": bool(sim.paused)}
	var job: Dictionary = {}
	for candidate: Dictionary in sim._jobs:
		if int(candidate.get("building_id", 0)) == building_id:
			job = candidate
			break
	if job.is_empty(): return result
	var camp: Dictionary = sim.get_camp(int(job.get("source_camp_id", 0)))
	result["source_name"] = str(camp.get("name", "原供料营不存在"))
	if bool(job.get("done", false)):
		result["code"] = "cancelled"
		result["text"] = "本工程已停止，尚未完工。"
		return result
	var builder: Dictionary = sim.get_unit(int(job.get("assigned", 0)))
	var assigned: bool = not builder.is_empty() and float(builder.get("hp", 0.0)) > 0.0
	if assigned:
		result["builder_text"] = ("工程师" if str(builder.get("kind", "")) == "engineer" else "工人") + " #%d" % int(builder.id)
	if camp.is_empty() or str(camp.get("state", "")) != "active":
		result["code"] = "source_inactive"
		result["text"] = "原供料营不存在或已停止接单；本工程当前不推进。"
	elif not bool(job.get("funded", false)):
		var missing: Dictionary = _missing(camp, Dictionary(job.get("costs", {})))
		result["code"] = "awaiting_payment" if missing.is_empty() else "awaiting_materials"
		result["text"] = "原供料营物资已足，等待重新备料与支付。" if missing.is_empty() else "原供料营缺少%s；等待重新备料。" % _cost_text(missing)
	elif not assigned:
		result["code"] = "awaiting_builder"
		var materials: String = "材料已送达；" if bool(job.get("delivered", false)) else ""
		result["text"] = materials + ("等待施工队接单。" if _builder_warning(sim).is_empty() else "暂无空闲工人或工程师；等待施工队空闲。")
	elif not bool(job.get("picked_up", false)):
		result["code"] = "collecting"
		result["text"] = "指定人员正在前往供料营或领取材料。"
	elif not bool(job.get("delivered", false)):
		result["code"] = "delivering"
		result["text"] = "材料运往工地，尚未送达。"
	elif Vector2(builder.get("pos", Vector2.ZERO)).distance_to(Vector2(job.pos)) > 1.5:
		result["code"] = "awaiting_arrival"
		result["text"] = "材料已送达，指定施工人员尚未到场。"
	elif str(job.get("kind", "")) == "exit" and not bool(building.get("powered", false)):
		result["code"] = "waiting_power"
		result["text"] = "材料与人员已到场，出口工程等待实际供能。"
	else:
		result["code"] = "building"
		result["text"] = "材料与人员已到场。"
	return result


static func get_production_status(sim: Variant, camp_id: int, include_pause: bool = true) -> Dictionary:
	var camp: Dictionary = sim.get_camp(camp_id)
	var result: Dictionary = {"code": "no_camp", "text": "未选择驻点", "detail": "选择一个驻点查看本地生产。", "working": 0, "total": 0, "recipe": str(camp.get("recipe", "idle"))}
	if camp.is_empty():
		return result
	var completed: Array[Dictionary] = []
	var unfinished: int = 0
	for building in sim.buildings:
		if int(building["camp_id"]) != camp_id or str(building["kind"]) != "workshop" or float(building["hp"]) <= 0.0:
			continue
		if float(building["progress"]) < 1.0:
			unfinished += 1
		else:
			completed.append(building)
			if bool(building.get("powered", false)):
				result["working"] = int(result["working"]) + 1
	result["total"] = completed.size()
	if str(camp["state"]) != "active":
		return _status(result, "inactive", "驻点停止生产", "驻点正在撤收或已弃守，无法继续加工。")
	if include_pause and sim.paused:
		return _status(result, "paused", "战术暂停", "继续战役后，本地生产才会推进。")
	var recipe: String = result["recipe"]
	if recipe == "idle":
		return _status(result, "idle", "生产已暂停", "选择加工建材、生产补给或提炼燃料。")
	if completed.is_empty():
		if unfinished > 0:
			return _status(result, "unfinished_workshop", "等待工坊完工", "工人或工程师送达材料并完成施工后，工坊才能加工。")
		return _status(result, "missing_workshop", "缺少工坊", "在本营建设工坊；完工后仍需道路连接和本地供能。")
	if int(result["working"]) == 0:
		return _status(result, "unpowered", "工坊未获供能", _power_detail(sim, camp, completed))
	var input: String = {"materials": "salvage", "fuel": "crude", "supplies": "fuel"}.get(recipe, "")
	if input.is_empty():
		return _status(result, "idle", "未选择有效配方", "选择加工建材、生产补给或提炼燃料。")
	if float(camp.get(input, 0.0)) <= 0.0:
		return _status(result, "input_empty", "缺少本地" + str(RESOURCE_NAMES[input]), "当前配方消耗%s；需要实际运入本营。" % str(RESOURCE_NAMES[input]))
	var details: Dictionary = {"materials": "消耗废料，每座供能工坊每秒产出0.8建材。", "fuel": "消耗原油，每座供能工坊每秒产出0.65燃料。", "supplies": "每份补给消耗0.08燃料，每座供能工坊每秒产出0.55补给。"}
	return _status(result, "running", "正在生产", "%d/%d座已完工工坊获供能。%s" % [int(result["working"]), int(result["total"]), details[recipe]])


static func _status(result: Dictionary, code: String, text: String, detail: String) -> Dictionary:
	result["code"] = code
	result["text"] = text
	result["detail"] = detail
	return result


static func _power_detail(sim: Variant, camp: Dictionary, workshops: Array[Dictionary]) -> String:
	var generators: Array[Dictionary] = []
	var unfinished: int = 0
	for building in sim.buildings:
		if int(building["camp_id"]) != int(camp["id"]) or str(building["kind"]) != "generator" or float(building["hp"]) <= 0.0:
			continue
		if float(building["progress"]) < 1.0:
			unfinished += 1
		else:
			generators.append(building)
	if generators.is_empty():
		return "等待本营发电机完工。" if unfinished > 0 else "本营没有已完工发电机；其他营地不会远程供电。"
	if float(camp.get("fuel", 0.0)) <= 0.001:
		return "本营缺少成品燃料，发电机停机；原油不能直接燃烧。"
	# Reuse the simulation's road cache; queries never run the power allocator.
	sim._ensure_navigation_index()
	var connected_generators: Array[Dictionary] = []
	for generator in generators:
		if sim._road_connected(Vector2(camp["pos"]), Vector2(generator["pos"])):
			connected_generators.append(generator)
	if connected_generators.is_empty():
		return "本营发电机尚未连上已完工道路；规划中的道路不能供能。"
	var connected_workshops: Array[Dictionary] = []
	for workshop in workshops:
		if sim._road_connected(Vector2(camp["pos"]), Vector2(workshop["pos"])):
			connected_workshops.append(workshop)
	if connected_workshops.is_empty():
		return "工坊尚未连上本营已完工道路；请补齐通向工坊的连接。"
	for workshop in connected_workshops:
		for generator in connected_generators:
			if Vector2(generator["pos"]).distance_to(Vector2(workshop["pos"])) <= float(generator.get("power_radius", 10.0)):
				return "覆盖工坊的本营发电机输出不足；检查供能优先级或增建附近发电机。"
	return "工坊超出本营已连路发电机的供能范围；在工坊附近接路建设发电机。"
