extends RefCounted
## Read-only local work summaries. Main owns their short-lived presentation cache.
## No low-stock thresholds or simulation updates belong in this query.

const ConstructionRules = preload("res://scripts/construction_rules.gd")
const RecruitmentRules = preload("res://scripts/recruitment_rules.gd")
const CARGO_KEYS: Array[String] = ["materials", "supplies", "fuel", "salvage", "crude"]
const CARGO_NAMES: Dictionary = {"materials":"建材", "supplies":"补给", "fuel":"成品燃料", "salvage":"废料", "crude":"原油"}


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
	if sim.paused and result.has("transport_text"):
		result["transport_text"] = "Ⅱ " + str(result["transport_text"])
		if code == "abandoned": result["detail"] = "战术暂停；末班货物待续。\n" + str(result["detail"])
	return result


static func _snapshot_status(sim: Variant, camp_id: int) -> Dictionary:
	var camp: Dictionary = sim.get_camp(camp_id)
	if camp.is_empty():
		return _row("no_camp", "— 无此驻点", "该驻点当前不存在。", "muted")
	var state: String = str(camp.get("state", "active"))
	if state == "abandoned":
		var row: Dictionary = _row("abandoned", "— 已弃守", "驻点已弃守；库存数字表示留在原地的物资，在途撤收货物仍依实际运输状态处理。", "muted")
		var truck: Dictionary = sim.get_unit(int(camp.get("evac_truck_id", 0)))
		if str(sim.outcome) == "playing" and _assigned_transport(camp, truck) and str(truck.get("haul_stage", "")) == "outbound":
			return _transport_row(row, camp, sim.get_camp(int(truck.get("evac_destination_id", 0))), truck, "末班")
		return row
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
	var truck: Dictionary = sim.get_unit(int(camp.get("evac_truck_id", 0)))
	if destination.is_empty():
		return _transport_row(_row("packing_waiting_destination", "! 撤收等接收营", "已请求撤收，但接收驻点当前不存在，物资运输无法继续。", "attention"), camp, destination, truck, "等待接收营")
	if not _assigned_transport(camp, truck):
		return _transport_row(_row("packing_waiting_truck", "! 撤收等运输车", "已请求撤收，但指定运输车已不可用或未在执行本营撤收，物资运输无法继续。", "attention"), camp, destination, truck, "等车")
	var destination_name: String = str(destination.get("name", "前方驻点"))
	if str(truck.get("state", "")) == "packing":
		return _transport_row(_row("packing_loading", "↗ 正在装车", "撤收车正在装载本营物资，随后送往%s。" % destination_name), camp, destination, truck, "装车")
	if str(truck.get("haul_stage", "")) == "outbound":
		return _transport_row(_row("packing_outbound", "→ 撤收运输中", "撤收车正在将已装载物资送往%s，未装车库存仍留在本营。" % destination_name), camp, destination, truck, "运输")
	return _transport_row(_row("packing_returning", "↶ 撤收车返程", "撤收车正返回本营装货，接收驻点为%s。" % destination_name), camp, destination, truck, "返程")


static func _assigned_transport(camp: Dictionary, truck: Dictionary) -> bool:
	if truck.is_empty() or float(truck.get("hp", 0.0)) <= 0.0 or str(truck.get("order", "")) != "evacuate_transport" or int(truck.get("evac_origin_id", 0)) != int(camp.id): return false
	# Integrity loss may retarget the real last truck to a fallback without
	# rewriting its abandoned origin's old target. Packing still requires both.
	return str(camp.get("state", "")) == "abandoned" or int(truck.get("evac_destination_id", 0)) == int(camp.get("evac_target_id", 0))


static func _transport_row(row: Dictionary, camp: Dictionary, destination: Dictionary, truck: Dictionary, stage: String) -> Dictionary:
	# Copy only this camp's assigned real vehicle cargo. No stock, capacity or
	# allocator query is used, and a missing vehicle never implies an empty load.
	var available: bool = _assigned_transport(camp, truck)
	var cargo: Dictionary = Dictionary(truck.get("cargo", {})).duplicate(true) if available else {}
	var destination_name: String = str(destination.get("name", "接收营缺失"))
	row["transport_text"] = stage + " → " + destination_name if not destination.is_empty() else "! 接收营缺失"
	row["cargo_text"] = _compact_cargo(cargo) if available else "车上载货未知 · 运输车不可用"
	row["transport"] = {"destination_id": int(truck.get("evac_destination_id", 0)) if available else int(camp.get("evac_target_id", 0)), "destination_name": destination_name,
		"truck_id": int(camp.get("evac_truck_id", 0)), "stage": stage, "cargo_available": available, "cargo": cargo}
	row["detail"] = str(row["detail"]) + "\n接收营：" + destination_name + "。\n车上：" + (_full_inventory(cargo) if available else "运输车不可用，不能确认可送达货物") + "。\n未装车：" + _full_inventory(camp) + "。\n本营供能 %d/%d；库存行不含车上货物。" % [int(camp.get("power_used", 0)), int(camp.get("power_capacity", 0))]
	for key: String in CARGO_KEYS:
		if float(cargo.get(key, 0.0)) >= 1000.0:
			row["detail"] += "\n载货简写：k为千，M为百万。"
			break
	if str(camp.get("state", "")) == "packing":
		row["detail"] += "\n紧急弃营会留下未装车库存，车上货物仍按实际运输状态送达。"
	return row


static func _compact_cargo(cargo: Dictionary) -> String:
	var total: float = 0.0
	for key: String in CARGO_KEYS: total += float(cargo.get(key, 0.0))
	if total <= 0.0: return "车上 空车"
	var result: String = "车上 材%s 供%s 油%s" % [_compact_amount(float(cargo.get("materials", 0))), _compact_amount(float(cargo.get("supplies", 0))), _compact_amount(float(cargo.get("fuel", 0)))]
	var extra: int = 0
	for key: String in ["salvage", "crude"]:
		if float(cargo.get(key, 0.0)) > 0.0: extra += 1
	if extra > 0: result += " +%d项" % extra
	return result


static func _compact_amount(amount: float) -> String:
	if amount >= 1000000.0: return _short_number(amount / 1000000.0) + "M"
	if amount >= 1000.0: return _short_number(amount / 1000.0) + "k"
	if amount > 0.0 and amount < 0.1: return "<0.1"
	return _short_number(amount)


static func _short_number(amount: float) -> String:
	if amount >= 100.0: return str(int(amount))
	return ("%.1f" % (floorf(amount * 10.0) / 10.0)).trim_suffix(".0")


static func _full_inventory(inventory: Dictionary) -> String:
	var entries: Array[String] = []
	for key: String in CARGO_KEYS:
		var amount: float = float(inventory.get(key, 0.0))
		var text: String = str(int(roundf(amount))) if is_equal_approx(amount, roundf(amount)) else ("%.1f" % amount).trim_suffix(".0")
		if amount > 0.0 and amount < 0.1: text = "<0.1"
		entries.append(str(CARGO_NAMES[key]) + " " + text)
	return "、".join(entries)


static func _work_detail(production: Dictionary, training: Dictionary) -> String:
	var result: String = "生产：%s。%s" % [str(production.get("text", "待命")), str(production.get("detail", ""))]
	if int(training.get("queue_size", 0)) > 0:
		result += "\n训练：%s。%s" % [str(training.get("text", "")), str(training.get("detail", ""))]
	return result


static func _row(code: String, text: String, detail: String, severity: String = "normal") -> Dictionary:
	return {"code":code, "text":text, "detail":detail, "severity":severity}
