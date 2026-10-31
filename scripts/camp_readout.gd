extends RefCounted
## Read-only local work summaries. Main owns their short-lived presentation cache.
## No low-stock thresholds or simulation updates belong in this query.

const ConstructionRules = preload("res://scripts/construction_rules.gd")
const RecruitmentRules = preload("res://scripts/recruitment_rules.gd")


static func status(sim: Variant, camp_id: int) -> Dictionary:
	var result: Dictionary = _snapshot_status(sim, camp_id)
	var code: String = str(result["code"])
	if sim.paused and not ["no_camp", "abandoned", "ended", "inactive"].has(code):
		var text: String = str(result["text"]).trim_prefix("! ").trim_prefix("▶ ").trim_prefix("… ").trim_prefix("— ")
		if code == "production_running": text += "待续"
		elif code == "working": text = "生产·训练待续"
		elif code == "training": text = "训练待续"
		elif code == "packing_loading": text = "撤收装车待续"
		elif code == "packing_outbound": text = "撤收运输待续"
		elif code == "packing_returning": text = "撤收返程待续"
		result["text"] = "Ⅱ " + text
		result["detail"] = "战术暂停；以下为本营当前状态，继续后才会推进。\n" + str(result["detail"])
	return result


static func _snapshot_status(sim: Variant, camp_id: int) -> Dictionary:
	var camp: Dictionary = sim.get_camp(camp_id)
	if camp.is_empty():
		return _row("no_camp", "— 无此驻点", "该驻点当前不存在。", "muted")
	var state: String = str(camp.get("state", "active"))
	if state == "abandoned":
		return _row("abandoned", "— 已弃守", "驻点已弃守；库存数字表示留在原地的物资，在途撤收货物仍依实际运输状态处理。", "muted")
	if str(sim.outcome) != "playing":
		return _row("ended", "■ 战役已结束", "战役已结束，本地生产、训练与撤收不再推进。", "muted")
	if state == "packing":
		return _packing_status(sim, camp)
	if state != "active":
		return _row("inactive", "— 未运作", "驻点当前未运作。", "muted")
	# Planning while paused must retain the underlying reason without briefly
	# toggling the live pause flag or advancing any allocator/queue.
	var production: Dictionary = ConstructionRules.get_production_status(sim, camp_id, false)
	var training: Dictionary = RecruitmentRules.get_training_status(sim, camp_id, false)
	var production_code: String = str(production.get("code", "idle"))
	var training_code: String = str(training.get("code", "idle"))
	var queued: bool = int(training.get("queue_size", 0)) > 0
	var detail: String = _work_detail(production, training)
	# Only an admitted, nonempty queue can be interrupted training. The lack of
	# recruitment facilities at an otherwise idle camp is not an alert.
	if queued and training_code == "waiting_power":
		return _row("training_waiting_power", "! 训练等供能", detail, "attention")
	# Camp creation defaults to a recipe before any workshop exists. Treat that
	# setup state neutrally; production warnings require a completed workshop
	# and a real selected recipe, using the authoritative diagnostic's blocker.
	var requested_production: bool = ["materials", "supplies", "fuel"].has(str(camp.get("recipe", "idle"))) and int(production.get("total", 0)) > 0
	if requested_production and production_code == "unpowered":
		return _row("production_unpowered", "! 生产等供能", detail, "attention")
	if requested_production and production_code == "input_empty":
		return _row("production_input_empty", "! 生产缺原料", detail, "attention")
	if queued and training_code == "training":
		return _row("working" if production_code == "running" else "training", "▶ 生产·训练" if production_code == "running" else "▶ 正在训练", detail)
	if production_code == "running":
		var recipe_text: String = {"materials":"加工建材", "supplies":"生产补给", "fuel":"提炼燃料"}.get(str(production.get("recipe", "")), "正在生产")
		return _row("production_running", "▶ " + recipe_text, detail)
	if production_code == "unfinished_workshop":
		return _row("setup", "… 工坊施工中", detail)
	if production_code == "missing_workshop":
		return _row("setup", "… 尚未建工坊", detail)
	return _row("idle", "— 生产待命", detail)


static func _packing_status(sim: Variant, camp: Dictionary) -> Dictionary:
	var destination: Dictionary = sim.get_camp(int(camp.get("evac_target_id", 0)))
	if destination.is_empty():
		return _row("packing_waiting_destination", "! 撤收等接收营", "已请求撤收，但接收驻点当前不存在，物资运输无法继续。", "attention")
	var truck: Dictionary = sim.get_unit(int(camp.get("evac_truck_id", 0)))
	if truck.is_empty() or float(truck.get("hp", 0.0)) <= 0.0:
		return _row("packing_waiting_truck", "! 撤收等运输车", "已请求撤收，但指定运输车已不可用，物资运输无法继续。", "attention")
	var destination_name: String = str(destination.get("name", "前方驻点"))
	if str(truck.get("state", "")) == "packing":
		return _row("packing_loading", "↗ 正在装车", "撤收车正在装载本营物资，随后送往%s。" % destination_name)
	if str(truck.get("haul_stage", "")) == "outbound":
		return _row("packing_outbound", "→ 撤收运输中", "撤收车正在将已装载物资送往%s，未装车库存仍留在本营。" % destination_name)
	return _row("packing_returning", "↶ 撤收车返程", "撤收车正返回本营装货，接收驻点为%s。" % destination_name)


static func _work_detail(production: Dictionary, training: Dictionary) -> String:
	var result: String = "生产：%s。%s" % [str(production.get("text", "待命")), str(production.get("detail", ""))]
	if int(training.get("queue_size", 0)) > 0:
		result += "\n训练：%s。%s" % [str(training.get("text", "")), str(training.get("detail", ""))]
	return result


static func _row(code: String, text: String, detail: String, severity: String = "normal") -> Dictionary:
	return {"code":code, "text":text, "detail":detail, "severity":severity}
