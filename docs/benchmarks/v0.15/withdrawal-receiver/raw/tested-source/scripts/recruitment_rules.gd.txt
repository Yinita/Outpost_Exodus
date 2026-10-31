extends RefCounted
## Read-only recruitment plans. Simulation owns payment, queues and training.

const UNIT_NAMES: Dictionary = {"rifle": "步枪兵", "engineer": "工程师", "worker": "工人", "truck": "补给卡车"}
const RESOURCE_NAMES: Dictionary = {"materials": "建材", "supplies": "补给", "fuel": "燃料"}


static func query_recruit(sim: Variant, camp_id: int, kind: String, recruit_costs: Dictionary, recruit_seconds: Dictionary, cap: int, queue_cap: int) -> Dictionary:
	var camp: Dictionary = sim.get_camp(camp_id)
	var queue: Array = camp.get("recruit_queue", [])
	var population: int = 0
	for unit in sim.units:
		if str(unit["team"]) == "friendly" and float(unit["hp"]) > 0.0:
			population += 1
	for other_camp in sim.camps:
		population += Array(other_camp.get("recruit_queue", [])).size()
	var costs: Dictionary = Dictionary(recruit_costs.get(kind, {})).duplicate(true)
	var result: Dictionary = {"ok": false, "code": "", "message": "", "costs": costs, "missing": _missing(camp, costs), "facility": _facility_name(kind), "unit_name": str(UNIT_NAMES.get(kind, kind)), "duration": float(recruit_seconds.get(kind, 0.0)), "population": population, "cap": cap, "queue_size": queue.size(), "queue_cap": queue_cap}
	# Keep the simulation's original acceptance order and power predicate.
	if sim.outcome != "playing":
		return _reject(result, "not_playing", "战役已经结束，无法安排训练。")
	if not recruit_costs.has(kind):
		return _reject(result, "unknown_kind", "无法训练这种单位。")
	if camp.is_empty():
		return _reject(result, "no_camp", "未选择有效驻点，无法安排训练。")
	if str(camp["state"]) != "active":
		if str(camp["state"]) == "packing":
			return _reject(result, "camp_packing", "本营正在撤收，无法接收训练订单；请选择仍在运作的营地。")
		return _reject(result, "camp_inactive", "本营已停止运作，无法安排训练。")
	if population >= cap:
		return _reject(result, "population_full", "已达到 %d 单位指挥上限（含所有营地训练中的单位）。" % cap)
	if queue.size() >= queue_cap:
		return _reject(result, "queue_full", "该营地的训练队列已满（%d/%d）。" % [queue.size(), queue_cap])
	if not sim._training_power_available(camp, kind):
		var power: Dictionary = _power_failure(sim, camp, kind)
		return _reject(result, str(power["code"]), str(power["message"]))
	if not sim._can_pay(camp, costs):
		return _reject(result, "resources", "%s本地缺少%s；其他营地库存不会直接支付。" % [str(camp.get("name", "营地")), _cost_text(result["missing"])])
	result["ok"] = true
	result["code"] = "ready"
	result["message"] = "可安排%s：本营支付%s，训练需%s秒。" % [result["unit_name"], _cost_text(costs), _amount(result["duration"])]
	return result


static func get_training_status(sim: Variant, camp_id: int, include_pause: bool = true) -> Dictionary:
	var camp: Dictionary = sim.get_camp(camp_id)
	var result: Dictionary = {"code": "no_camp", "text": "未选择驻点", "detail": "选择一个驻点查看本地训练队列。", "queue_size": 0, "progress": 0.0, "current_name": "", "remaining": 0.0}
	if camp.is_empty():
		return result
	var queue: Array = camp.get("recruit_queue", [])
	result["queue_size"] = queue.size()
	if queue.is_empty():
		if str(camp["state"]) != "active":
			return _status(result, "inactive", "驻点已停止训练", "本营正在撤收或已停止运作，无法接收新的训练订单；请选择仍在运作的营地。")
		return _status(result, "idle", "训练队列为空", "选择单位查看本营设施、价格和人口条件。")
	var entry: Dictionary = queue[0]
	var kind: String = str(entry["kind"])
	var duration: float = float(entry["duration"])
	var elapsed: float = float(entry.get("elapsed", 0.0))
	result["current_name"] = str(UNIT_NAMES.get(kind, kind))
	result["progress"] = clampf(elapsed / duration, 0.0, 1.0)
	# Remaining time belongs to the head's elapsed training, regardless of UI speed.
	result["remaining"] = maxf(0.0, duration - elapsed)
	if str(camp["state"]) != "active":
		return _status(result, "inactive", "训练因撤收停止", "本营正在撤收或已停止运作；当前保留的队列不会继续训练。")
	if include_pause and sim.paused:
		return _status(result, "paused", "战术暂停", "继续战役后，本营队首训练才会推进。")
	if not sim._training_power_available(camp, kind):
		return _status(result, "waiting_power", "等待训练设施供能", str(_power_failure(sim, camp, kind)["message"]))
	return _status(result, "training", "正在训练：" + str(result["current_name"]), "队首还需%s秒；后续单位依次训练。" % _amount(result["remaining"]))


static func _power_failure(sim: Variant, camp: Dictionary, kind: String) -> Dictionary:
	var facility: String = _facility_name(kind)
	var candidates: Array[Dictionary] = []
	var generators: Array[Dictionary] = []
	var unfinished_facilities: int = 0
	var unfinished_generators: int = 0
	for building in sim.buildings:
		if int(building["camp_id"]) != int(camp["id"]) or float(building["hp"]) <= 0.0:
			continue
		var building_kind: String = str(building["kind"])
		if _facility_kinds(kind).has(building_kind):
			if float(building["progress"]) < 1.0:
				unfinished_facilities += 1
			else:
				candidates.append(building)
		if building_kind == "generator":
			if float(building["progress"]) < 1.0:
				unfinished_generators += 1
			else:
				generators.append(building)
	if candidates.is_empty():
		if unfinished_facilities > 0:
			return _failure("unfinished_facility", "等待本营%s完工后才能训练%s。" % [facility, str(UNIT_NAMES.get(kind, kind))])
		return _failure("missing_facility", "本营缺少已完工%s；其他营地设施不能代为训练。" % facility)
	if generators.is_empty():
		if unfinished_generators > 0:
			return _failure("unfinished_generator", "等待本营发电机完工；训练需要本地发电。")
		return _failure("missing_generator", "本营没有已完工发电机；训练需要本地发电，其他营地不能远程供能。")
	if float(camp.get("fuel", 0.0)) <= 0.001:
		return _failure("fuel_empty", "本营缺少成品燃料，发电机停机；原油不能直接燃烧。")
	# Diagnostics inspect the allocator's latest snapshot; never run it here.
	sim._ensure_navigation_index()
	var connected_generators: Array[Dictionary] = []
	for generator in generators:
		if sim._road_connected(Vector2(camp["pos"]), Vector2(generator["pos"])):
			connected_generators.append(generator)
	if connected_generators.is_empty():
		return _failure("generator_road", "本营发电机尚未连上已完工道路；规划中的道路不能供能。")
	var connected_facilities: Array[Dictionary] = []
	for candidate in candidates:
		# Command/camp buildings power themselves; workers may also use barracks.
		if kind == "worker" and ["command", "camp"].has(str(candidate["kind"])):
			return _failure("power_pending", "本营尚无可用供能快照；继续战役后，发电机和驻点会重新分配供能。")
		if sim._road_connected(Vector2(camp["pos"]), Vector2(candidate["pos"])):
			connected_facilities.append(candidate)
	if connected_facilities.is_empty():
		return _failure("facility_road", "%s尚未连上本营已完工道路；请补齐通向训练设施的连接。" % facility)
	var covered: bool = false
	for candidate in connected_facilities:
		for generator in connected_generators:
			if Vector2(generator["pos"]).distance_to(Vector2(candidate["pos"])) > float(generator.get("power_radius", 10.0)):
				continue
			covered = true
			if bool(generator.get("powered", false)) and float(generator.get("available_output", 0.0)) < float(candidate.get("required_power", 0.0)):
				continue
			return _failure("power_pending", "本营训练设施尚未获供能；继续战役以更新供能状态。")
	if covered:
		return _failure("power_output", "覆盖%s的本营发电机输出不足；检查供能优先级或增建附近发电机。" % facility)
	return _failure("power_range", "%s超出本营已连路发电机的供能范围；在训练设施附近接路建设发电机。" % facility)


static func _facility_kinds(kind: String) -> Array:
	if kind == "worker":
		return ["command", "camp", "barracks"]
	return ["workshop"] if kind == "truck" else ["barracks"]


static func _facility_name(kind: String) -> String:
	return {"rifle": "军营", "engineer": "军营", "worker": "驻点（指挥部/营地）或军营", "truck": "工坊"}.get(kind, "训练设施")


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


static func _failure(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message}


static func _reject(result: Dictionary, code: String, message: String) -> Dictionary:
	result["code"] = code
	result["message"] = message
	return result


static func _status(result: Dictionary, code: String, text: String, detail: String) -> Dictionary:
	result["code"] = code
	result["text"] = text
	result["detail"] = detail
	return result
