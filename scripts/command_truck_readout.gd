extends RefCounted
## Pure current-state display; no damage history, orders, caches or saved fields.

static func status(sim: Variant) -> Dictionary:
	var unavailable: Dictionary = {"unit_id": 0, "code": "missing", "hp": 0.0,
		"max_hp": 0.0, "enabled": false, "label": "指挥车：缺失",
		"tooltip": "指挥车记录不可用，无法选择定位。"}
	if sim == null: return unavailable
	var unit: Dictionary = sim.get_unit(int(sim.main_truck_id))
	if unit.is_empty() or int(unit.get("id", 0)) != int(sim.main_truck_id) or String(unit.get("team", "")) != "friendly" or String(unit.get("kind", "")) != "truck":
		return unavailable
	var position: Variant = unit.get("pos")
	if not position is Vector2 or not Vector2(position).is_finite():
		return unavailable
	var hp: float = float(unit.get("hp", 0.0))
	var maximum: float = float(unit.get("max_hp", 0.0))
	if not is_finite(hp) or not is_finite(maximum) or maximum <= 0.0:
		return unavailable
	if hp <= 0.0:
		return {"unit_id": int(unit.id), "code": "destroyed", "hp": hp,
			"max_hp": maximum, "enabled": false, "label": "指挥车：已摧毁",
			"tooltip": "指挥车已被摧毁，无法选择定位。"}
	var code: String = "healthy" if hp >= maximum else ("critical" if hp <= maximum * 0.3 else "damaged")
	var text: String = {"healthy": "完好", "damaged": "受损", "critical": "危急"}[code]
	return {"unit_id": int(unit.id), "code": code, "hp": hp, "max_hp": maximum,
		"enabled": true,
		"label": "指挥车 %d/%d · %s · 选择" % [ceili(hp), ceili(maximum), text],
		"tooltip": "选择并定位指挥车；保持现有任务。\n%s；指挥车被摧毁将导致战役失败。" % text}
