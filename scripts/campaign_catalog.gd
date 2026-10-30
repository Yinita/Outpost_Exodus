extends RefCounted
## Independent, deterministic mission definitions. No simulation or player state.
## Positions use tile units; terrain layers are applied in order, then explicit ramps.
## Returned definitions are fresh values and may safely be edited by a caller.

const DEFAULT_ID: String = "canyon"
const SCHEMA_VERSION: int = 1
const RESOURCE_KEYS: Array[String] = ["materials", "supplies", "fuel", "salvage", "crude"]
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0)]


static func ids() -> Array[String]:
	return ["canyon", "delta", "ridge"]


static func mission(mission_id: String = DEFAULT_ID) -> Dictionary:
	match mission_id:
		"canyon": return _canyon()
		"delta": return _delta()
		"ridge": return _ridge()
	return {}


static func _base(mission_id: String, title: String, objective_text: String, home: Vector2, middle: Vector2, forward: Vector2, highway: Vector2, quarry: Vector2, fuel: Vector2, cache: Vector2, exit_position: Vector2, west_y: int, east_y: int) -> Dictionary:
	var roads: Array = []
	var offset: Vector2i = Vector2i(home) - Vector2i(9, 22)
	# This insertion order intentionally matches the original Canyon initializer.
	for x: int in range(8, 19):
		roads.append({"pos": Vector2i(x, 23) + offset, "camp": "home"})
	for y: int in range(20, 26):
		roads.append({"pos": Vector2i(9, y) + offset, "camp": "home"})
	for y: int in range(20, 24):
		roads.append({"pos": Vector2i(18, y) + offset, "camp": "home"})
	roads.append({"pos": Vector2i(17, 22) + offset, "camp": "home"})
	return {
		"version": SCHEMA_VERSION, "id": mission_id, "name": title, "objective": objective_text,
		"map_size": Vector2i(80, 40), "terrain_layers": [], "ramp_rects": [],
		"visual": {"sand":"cda16a", "sand_light":"d7b37b", "high":"e4bc7b", "high_shade":"d8ab6d", "cliff":"9a6b4f", "void":"66594f", "void_light":"756052", "grass":"8d8c54", "grass_light":"9e8249", "map_low":"ae9567", "map_high":"d2b47c", "map_void":"374b53", "water":"527b7e", "water_light":"739a94", "water_rects":[], "bridge_rects":[]},
		"camps": [{"key": "home", "name": "后方营地", "pos": home, "stock": {"materials": 220.0, "supplies": 150.0, "fuel": 110.0, "salvage": 45.0, "crude": 0.0}, "energy": 25.0}],
		"buildings": [
			{"kind": "command", "pos": home, "camp": "home", "progress": 1.0},
			{"kind": "generator", "pos": home + Vector2(0, 3), "camp": "home", "progress": 1.0},
			{"kind": "workshop", "pos": home + Vector2(3, 0), "camp": "home", "progress": 1.0},
			{"kind": "tower", "pos": home + Vector2(7, -2), "camp": "home", "progress": 1.0}
		],
		"roads": roads,
		"units": [
			{"kind": "rifle", "pos": home + Vector2(3, -2), "camp": "home", "squad": 1, "main_truck": false},
			{"kind": "rifle", "pos": home + Vector2(4, -2), "camp": "home", "squad": 1, "main_truck": false},
			{"kind": "rifle", "pos": home + Vector2(3, -1), "camp": "home", "squad": 1, "main_truck": false},
			{"kind": "engineer", "pos": home + Vector2(1, -1), "camp": "home", "squad": 1, "main_truck": false},
			{"kind": "worker", "pos": home + Vector2(-1, 1), "camp": "home", "squad": 0, "main_truck": false},
			{"kind": "worker", "pos": home + Vector2(1, 2), "camp": "home", "squad": 0, "main_truck": false},
			{"kind": "worker", "pos": home + Vector2(2, 2), "camp": "home", "squad": 0, "main_truck": false},
			{"kind": "truck", "pos": home + Vector2(2, 1), "camp": "home", "squad": 0, "main_truck": true}
		],
		"sites": [
			{"key": "highway", "kind": "cache", "pos": highway, "name": "旧公路补给", "stock": {"materials": 35.0, "supplies": 45.0, "fuel": 15.0}, "guards": 3, "runner": false},
			{"key": "quarry", "kind": "quarry", "pos": quarry, "name": "北部废料场", "stock": {"salvage": 420.0}, "guards": 5, "runner": false},
			{"key": "fuel", "kind": "fuel", "pos": fuel, "name": "南部油库", "stock": {"crude": 280.0}, "guards": 4, "runner": true},
			{"key": "forward", "kind": "cache", "pos": cache, "name": "前营旧址", "stock": {"materials": 70.0, "supplies": 50.0, "fuel": 25.0}, "guards": 5, "runner": true},
			{"key": "exit", "kind": "exit", "pos": exit_position, "name": "东部撤离站", "stock": {}, "guards": 6, "runner": true}
		],
		"chokes": [
			{"key": "west", "pos": Vector2(21, west_y), "name": "西部关口"},
			{"key": "east", "pos": Vector2(61, east_y), "name": "东部关口"}
		],
		"exit": {"site": "exit", "required_power": 6.0},
		"guide": {
			"landmarks": {
				"home": home, "highway": highway, "highway_road": middle + Vector2(0, -2),
				"middle_camp": middle, "middle_road": middle + Vector2(3, 1), "quarry": quarry, "fuel": fuel,
				"forward_cache": cache, "forward_road": forward + Vector2(-1, -1), "front_camp": forward,
				"front_road": forward + Vector2(3, 0), "exit": exit_position,
				"exit_power": exit_position + Vector2(-4, 3),
				"west_gate": Vector2(21, west_y), "east_gate": Vector2(61, east_y)
			},
			"middle_min_x": 20.0, "front_min_x": 45.0,
			"branch_text": "北线废料可加工建材，南线原油可加工燃料，先后顺序由你决定。",
			"route_text": "经过两道关口，把人员、燃料与设备逐营向东转移。",
			"choices": []
		},
		"pacing": {"pursuit_x": -5.0, "pursuit_eta": 540.0, "pursuit_speed": 0.035, "pursuit_start": 150.0, "spawn_y": 19.0, "first_gate_x": 21.0, "evacuation_x": 33.0, "exit_x": 72.0, "target_minutes": Vector2i(25, 35)},
		"crossings": [],
		"messages": ["战役开始：先带步枪队与工程师越过西部关口，清理前方补给。", "道路连接资源点后，工人会实际往返运料；发电机只为附近设施供能。"]
	}


static func _layer(rect: Rect2i, value: int) -> Dictionary:
	return {"rect": rect, "value": value}


static func _frame(west_y: int, east_y: int) -> Array:
	return [
		_layer(Rect2i(2, 3, 76, 34), 0),
		_layer(Rect2i(20, 0, 3, 40), -1), _layer(Rect2i(20, west_y - 1, 3, 3), 0),
		_layer(Rect2i(60, 0, 3, 40), -1), _layer(Rect2i(60, east_y - 1, 3, 3), 0)
	]


static func _canyon() -> Dictionary:
	var data: Dictionary = _base("canyon", "裂谷突围", "清理北部废料场与南部油库，铺路建立前营，修复东部撤离站。", Vector2(9, 22), Vector2(26, 23), Vector2(54, 23), Vector2(25, 20), Vector2(35, 10), Vector2(35, 31), Vector2(53, 21), Vector2(72, 19), 20, 20)
	data["terrain_layers"] = _frame(20, 20)
	data["terrain_layers"].append_array([
		_layer(Rect2i(3, 14, 15, 16), 1), _layer(Rect2i(29, 6, 15, 10), 1),
		_layer(Rect2i(48, 16, 12, 10), 1), _layer(Rect2i(67, 14, 10, 12), 1)
	])
	data["ramp_rects"] = [Rect2i(17, 20, 3, 3), Rect2i(34, 15, 3, 3), Rect2i(47, 20, 3, 3), Rect2i(58, 19, 3, 3), Rect2i(65, 18, 4, 4)]
	data["guide"]["choices"] = ["先取北线建材扩充设施，或先取南线原油保住生产。", "撤收旧营后封住西关；前营建成后，再决定留下多少物资。"]
	return data


static func _delta() -> Dictionary:
	var data: Dictionary = _base("delta", "双桥湿地", "穿过北闸进入湿地，在南岸回收废料、北岸夺取原油，选择桥线转移到东南前营。", Vector2(9, 12), Vector2(27, 13), Vector2(54, 28), Vector2(25, 11), Vector2(35, 29), Vector2(42, 7), Vector2(53, 26), Vector2(72, 30), 11, 28)
	data["terrain_layers"] = _frame(11, 28)
	data["terrain_layers"].append_array([
		_layer(Rect2i(3, 5, 15, 15), 1), _layer(Rect2i(29, 24, 15, 11), 1),
		_layer(Rect2i(48, 23, 12, 11), 1), _layer(Rect2i(67, 25, 10, 11), 1),
		# A river divides the whole central basin. Both crossings are real terrain.
		_layer(Rect2i(23, 18, 37, 3), -1),
		_layer(Rect2i(29, 18, 3, 3), 0), _layer(Rect2i(51, 18, 3, 3), 0)
	])
	data["ramp_rects"] = [Rect2i(17, 10, 3, 3), Rect2i(34, 22, 3, 3), Rect2i(47, 26, 3, 3), Rect2i(58, 27, 3, 3), Rect2i(65, 28, 4, 4)]
	data["visual"].merge({"sand":"b9b890", "sand_light":"d1c39b", "high":"d0bf91", "high_shade":"b4a880", "grass":"658363", "grass_light":"8c9e6d", "map_low":"99a183", "map_high":"c6b58c", "water_rects":[Rect2i(23,18,37,3)], "bridge_rects":[Rect2i(29,18,3,3),Rect2i(51,18,3,3)]}, true)
	data["camps"][0]["stock"] = {"materials": 230.0, "supplies": 150.0, "fuel": 100.0, "salvage": 45.0, "crude": 0.0}
	data["sites"][0]["name"] = "北闸公路补给"
	data["sites"][0]["stock"] = {"materials": 45.0, "supplies": 55.0, "fuel": 25.0}
	data["sites"][1]["name"] = "南岸沉船废料场"
	data["sites"][1]["stock"] = {"salvage": 560.0}
	data["sites"][2]["name"] = "北岸泵站油库"
	data["sites"][2]["stock"] = {"crude": 340.0}
	data["sites"][3]["name"] = "东南堤岸旧营"
	data["sites"][3]["stock"] = {"materials": 85.0, "supplies": 55.0, "fuel": 30.0}
	data["chokes"][0]["name"] = "北岸西闸"
	data["chokes"][1]["name"] = "东南堤口"
	data["guide"]["branch_text"] = "南岸沉船提供废料，北岸泵站提供原油。先回收哪一岸，会改变工人的桥梁往返路线。"
	data["guide"]["route_text"] = "西桥靠近中营，东桥靠近前营。北岸油料更易先接入中营；南岸废料更易随前营保留下来。"
	data["guide"]["choices"] = ["留在北岸先取燃料，或过西桥优先回收南岸建材。", "从西桥带着废料向前，或走北岸经东桥迁营；撤收前确认两岸工人均已离开。"]
	data["pacing"]["pursuit_speed"] = 0.030
	data["pacing"]["pursuit_start"] = 180.0
	data["pacing"]["spawn_y"] = 10.0
	data["crossings"] = [{"key": "west_bridge", "pos": Vector2(30, 19), "kind": "bridge"}, {"key": "east_bridge", "pos": Vector2(52, 19), "kind": "bridge"}]
	data["messages"][0] = "湿地行动：南岸废料和北岸原油隔水分布，先选择要保住的生产线。"
	return data


static func _ridge() -> Dictionary:
	var data: Dictionary = _base("ridge", "山脊换防", "沿南谷取得燃料，夺取北侧山脊废料场；选择高脊通道或东坡迂回，向东北撤离。", Vector2(9, 29), Vector2(27, 28), Vector2(54, 12), Vector2(25, 29), Vector2(36, 8), Vector2(38, 29), Vector2(53, 10), Vector2(72, 10), 29, 11)
	data["terrain_layers"] = _frame(29, 11)
	data["terrain_layers"].append_array([
		_layer(Rect2i(3, 21, 15, 15), 1),
		# The quarry and forward camp share one long ridge, with a narrow neck.
		_layer(Rect2i(29, 5, 31, 11), 1),
		_layer(Rect2i(43, 5, 3, 11), -1), _layer(Rect2i(43, 10, 3, 3), 1),
		_layer(Rect2i(67, 5, 10, 12), 1),
		# The valley's ruined retaining wall makes the fuel route a real detour.
		_layer(Rect2i(44, 21, 3, 14), -1), _layer(Rect2i(44, 25, 3, 3), 0)
	])
	data["ramp_rects"] = [Rect2i(17, 27, 3, 3), Rect2i(29, 14, 3, 3), Rect2i(47, 14, 3, 3), Rect2i(58, 10, 3, 3), Rect2i(65, 9, 4, 4)]
	data["visual"].merge({"sand":"b5ab8a", "sand_light":"c6bea2", "high":"a8afa2", "high_shade":"929d93", "cliff":"727b72", "void":"505a58", "void_light":"626e68", "grass":"7f8f66", "grass_light":"a0a27c", "map_low":"a7a086", "map_high":"9ca99d", "map_void":"354c4a"}, true)
	data["camps"][0]["stock"] = {"materials": 230.0, "supplies": 150.0, "fuel": 100.0, "salvage": 45.0, "crude": 0.0}
	data["sites"][0]["name"] = "南谷公路补给"
	data["sites"][0]["stock"] = {"materials": 45.0, "supplies": 55.0, "fuel": 25.0}
	data["sites"][1]["name"] = "山脊回收站"
	data["sites"][1]["stock"] = {"salvage": 580.0}
	data["sites"][2]["name"] = "南谷加油站"
	data["sites"][2]["stock"] = {"crude": 340.0}
	data["sites"][3]["name"] = "东北观察营"
	data["sites"][3]["stock"] = {"materials": 85.0, "supplies": 55.0, "fuel": 30.0}
	data["chokes"][0]["name"] = "南谷西关"
	data["chokes"][1]["name"] = "山脊东关"
	data["guide"]["branch_text"] = "北侧废料场与前营共用山脊，南谷油库靠近中营。先上山可缩短后续物料运输，先取油能维持更久的生产。"
	data["guide"]["route_text"] = "山脊中段只有三格宽的颈道；南谷可绕到东坡，但多出爬坡与转运。迁营时保护东坡入口。"
	data["guide"]["choices"] = ["先把油库接回中营，或上山回收废料后沿高脊推进。", "护住山脊颈道走高线，或经南谷与东坡转移运输车；撤离前别把工人留在西坡。"]
	data["pacing"]["pursuit_speed"] = 0.031
	data["pacing"]["pursuit_start"] = 180.0
	data["pacing"]["spawn_y"] = 28.0
	data["crossings"] = [{"key": "ridge_neck", "pos": Vector2(44, 11), "kind": "pass"}, {"key": "valley_gap", "pos": Vector2(45, 26), "kind": "pass"}]
	data["messages"][0] = "山脊行动：北线废料可沿高地送往前营，南谷燃料需要额外的爬坡与护送。"
	return data


static func terrain_for(data: Dictionary) -> Dictionary:
	# This accepts only structural terrain data; validate() handles the full schema.
	var size_value: Variant = data.get("map_size", null)
	if not size_value is Vector2i or size_value.x < 1 or size_value.x > 128 or size_value.y < 1 or size_value.y > 128:
		return {}
	var size: Vector2i = size_value
	var rows: Array = []
	for y: int in range(size.y):
		var row: Array = []
		row.resize(size.x)
		row.fill(-1)
		rows.append(row)
	var layers: Variant = data.get("terrain_layers", null)
	var ramp_values: Variant = data.get("ramp_rects", null)
	if not layers is Array or not ramp_values is Array:
		return {}
	for layer_value: Variant in layers:
		if not layer_value is Dictionary or not _valid_rect(layer_value.get("rect", null), size) or not layer_value.get("value", null) is int or not [-1, 0, 1].has(layer_value["value"]):
			return {}
		var rectangle: Rect2i = layer_value["rect"]
		for y: int in range(rectangle.position.y, rectangle.end.y):
			for x: int in range(rectangle.position.x, rectangle.end.x):
				rows[y][x] = int(layer_value["value"])
	var ramp_tiles: Dictionary = {}
	for rectangle_value: Variant in ramp_values:
		if not _valid_rect(rectangle_value, size):
			return {}
		var rectangle: Rect2i = rectangle_value
		# Ramp insertion order is serialized by legacy Canyon saves.
		for x: int in range(rectangle.position.x, rectangle.end.x):
			for y: int in range(rectangle.position.y, rectangle.end.y):
				if int(rows[y][x]) < 0:
					return {}
				ramp_tiles[Vector2i(x, y)] = true
	return {"terrain": rows, "ramps": ramp_tiles}


static func path(data: Dictionary, from: Vector2i, to: Vector2i, blocked_tiles: Array = []) -> Array[Vector2i]:
	var geometry: Dictionary = terrain_for(data)
	if geometry.is_empty():
		return []
	return _path_geometry(geometry, from, to, blocked_tiles)


static func _path_geometry(geometry: Dictionary, from: Vector2i, to: Vector2i, blocked_tiles: Array = []) -> Array[Vector2i]:
	var rows: Array = geometry["terrain"]
	var ramp_tiles: Dictionary = geometry["ramps"]
	var size: Vector2i = Vector2i(rows[0].size(), rows.size())
	var blocked: Dictionary = {}
	for tile: Variant in blocked_tiles:
		if tile is Vector2i:
			blocked[tile] = true
	if not _walkable(from, size, rows) or not _walkable(to, size, rows) or blocked.has(from) or blocked.has(to):
		return []
	var queue: Array[Vector2i] = [from]
	var previous: Dictionary = {from: from}
	var cursor: int = 0
	while cursor < queue.size():
		var at: Vector2i = queue[cursor]
		cursor += 1
		if at == to:
			var result: Array[Vector2i] = [to]
			while result.back() != from:
				result.append(previous[result.back()])
			result.reverse()
			return result
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = at + direction
			if previous.has(next) or blocked.has(next) or not _walkable(next, size, rows):
				continue
			if int(rows[at.y][at.x]) != int(rows[next.y][next.x]) and not (ramp_tiles.has(at) and ramp_tiles.has(next)):
				continue
			previous[next] = at
			queue.append(next)
	return []


static func route_report(mission_id: String) -> Dictionary:
	var data: Dictionary = mission(mission_id)
	if data.is_empty():
		return {}
	var points: Dictionary = data["guide"]["landmarks"]
	var geometry: Dictionary = terrain_for(data)
	var routes: Dictionary = {}
	for edge: Array in [["home", "middle_camp"], ["middle_camp", "quarry"], ["middle_camp", "fuel"], ["middle_camp", "front_camp"], ["quarry", "front_camp"], ["fuel", "front_camp"], ["front_camp", "exit"]]:
		var route: Array[Vector2i] = _path_geometry(geometry, Vector2i(points[edge[0]]), Vector2i(points[edge[1]]))
		routes["%s_to_%s" % edge] = route.size() - 1 if not route.is_empty() else -1
	var resources: Dictionary = {"materials": 0.0, "supplies": 0.0, "fuel": 0.0, "salvage": 0.0, "crude": 0.0}
	for collection: String in ["camps", "sites"]:
		for record: Dictionary in data[collection]:
			for resource: String in RESOURCE_KEYS:
				resources[resource] = float(resources[resource]) + float(record["stock"].get(resource, 0.0))
	return {"id": mission_id, "distances": routes, "available_resources": resources,
		"note": "Terrain-only shortest distances and finite stock totals; excludes construction, bodies, combat, production time, food and generator consumption. This is not a victory or balance proof."}


static func validate(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var required: Array[String] = ["version", "id", "name", "objective", "map_size", "terrain_layers", "ramp_rects", "camps", "buildings", "roads", "units", "sites", "chokes", "exit", "guide", "pacing", "crossings", "messages"]
	for field: String in required:
		if not data.has(field):
			errors.append("Missing field: " + field)
	if not errors.is_empty():
		return errors
	if not data["version"] is int or int(data["version"]) != SCHEMA_VERSION:
		errors.append("Unsupported mission version")
	if not data["id"] is String or not ids().has(data["id"]):
		errors.append("Unknown mission id")
	for field: String in ["name", "objective"]:
		if not _nonempty_text(data[field], 512):
			errors.append("Invalid mission " + field)
	var geometry: Dictionary = terrain_for(data)
	if geometry.is_empty():
		errors.append("Malformed terrain, bounds or ramp on blocked terrain")
		return errors
	var size: Vector2i = data["map_size"]
	if size != Vector2i(80, 40):
		errors.append("Mission map must remain 80 by 40")
	if data.has("visual"):
		if not data.visual is Dictionary:
			errors.append("Invalid visual palette")
		else:
			for key: Variant in data.visual:
				var value: Variant = data.visual[key]
				if key in ["water_rects", "bridge_rects"]:
					if not value is Array or value.size() > 16:
						errors.append("Invalid visual regions")
					else:
						for region: Variant in value:
							if not _valid_rect(region, size):
								errors.append("Visual region outside map")
							elif key == "bridge_rects":
								for y: int in range(region.position.y, region.end.y):
									for x: int in range(region.position.x, region.end.x):
										if int(geometry.terrain[y][x]) < 0: errors.append("Visual bridge must be physically passable")
				else:
					var valid_color: bool = value is String and value.length() == 6
					if valid_color:
						for character: String in value:
							if not "0123456789abcdefABCDEF".contains(character): valid_color = false
					if not valid_color: errors.append("Invalid visual color")
	for field: String in ["camps", "buildings", "roads", "units", "sites", "chokes", "crossings", "messages"]:
		if not data[field] is Array or Array(data[field]).size() > (1024 if field == "roads" else 128):
			errors.append("Invalid collection: " + field)
	if not errors.is_empty():
		return errors
	var camp_keys: Dictionary = {}
	var site_keys: Dictionary = {}
	var choke_keys: Dictionary = {}
	var positions: Array[Vector2i] = []
	for collection: String in ["camps", "sites", "chokes", "buildings", "units", "roads", "crossings"]:
		var record_keys: Dictionary = {}
		for record_value: Variant in data[collection]:
			if not record_value is Dictionary:
				errors.append("Non-record in " + collection)
				continue
			var record: Dictionary = record_value
			if not _valid_position(record.get("pos", null), size) or not _walkable(Vector2i(record.get("pos", Vector2(-1, -1))), size, geometry["terrain"]):
				errors.append("Invalid or blocked position in " + collection)
			else:
				positions.append(Vector2i(record["pos"]))
			if ["camps", "sites", "chokes", "crossings"].has(collection):
				var key_value: Variant = record.get("key", null)
				if not _identifier(key_value) or record_keys.has(key_value):
					errors.append("Invalid or duplicate key in " + collection)
				else:
					record_keys[key_value] = true
			if ["camps", "sites"].has(collection) and not _valid_stock(record.get("stock", null)):
				errors.append("Invalid resource stock in " + collection)
			if ["camps", "sites", "chokes"].has(collection) and not _nonempty_text(record.get("name", null), 128):
				errors.append("Invalid name in " + collection)
			if collection == "sites":
				if not ["cache", "quarry", "fuel", "exit"].has(record.get("kind", "")):
					errors.append("Invalid site kind")
				if not record.get("guards", null) is int or int(record.get("guards", -1)) < 0 or int(record.get("guards", -1)) > 12 or not record.get("runner", null) is bool:
					errors.append("Invalid site guards")
			if collection == "buildings":
				if not ["command", "camp", "generator", "workshop", "tower", "barracks", "barricade"].has(record.get("kind", "")) or not _bounded_number(record.get("progress", null), 0.0, 1.0):
					errors.append("Invalid initial building")
			if collection == "units":
				if not ["rifle", "engineer", "worker", "truck"].has(record.get("kind", "")) or not record.get("squad", null) is int or int(record.get("squad", -1)) < 0 or int(record.get("squad", -1)) > 4 or not record.get("main_truck", null) is bool:
					errors.append("Invalid initial unit")
			if collection == "camps" and not _bounded_number(record.get("energy", null), 0.0, 1000.0):
				errors.append("Invalid camp energy")
		if collection == "camps": camp_keys = record_keys
		if collection == "sites": site_keys = record_keys
		if collection == "chokes": choke_keys = record_keys
	if not camp_keys.has("home") or data["camps"].size() != 1:
		errors.append("Exactly one home camp is required")
	for key: String in ["highway", "quarry", "fuel", "forward", "exit"]:
		if not site_keys.has(key): errors.append("Missing required site: " + key)
	if not choke_keys.has("west") or not choke_keys.has("east") or data["chokes"].size() != 2:
		errors.append("Exactly one west and east choke are required")
	var required_site_kinds: Dictionary = {"highway": "cache", "quarry": "quarry", "fuel": "fuel", "forward": "cache", "exit": "exit"}
	for value: Variant in data["sites"]:
		if not value is Dictionary: continue
		if not value.get("key", null) is String: continue
		var site_key: String = value["key"]
		if required_site_kinds.has(site_key) and value.get("kind", "") != required_site_kinds[site_key]:
			errors.append("Site key has incorrect kind: " + site_key)
		if value.get("kind", "") == "quarry" and (not value.get("stock", null) is Dictionary or not value["stock"].has("salvage")):
			errors.append("Quarry requires explicit salvage stock")
		if value.get("kind", "") == "fuel" and (not value.get("stock", null) is Dictionary or not value["stock"].has("crude")):
			errors.append("Fuel site requires explicit crude stock")
	var main_trucks: int = 0
	for collection: String in ["buildings", "units", "roads"]:
		for value: Variant in data[collection]:
			if not value is Dictionary: continue
			if not camp_keys.has(value.get("camp", null)):
				errors.append("Unknown camp reference in " + collection)
			if collection == "units" and value.get("main_truck", false) == true:
				main_trucks += 1
				if value.get("kind", "") != "truck": errors.append("Main truck must be a truck")
	if main_trucks != 1: errors.append("Exactly one main truck is required")
	if not data["exit"] is Dictionary or data["exit"].get("site", null) != "exit" or not site_keys.has(data["exit"].get("site", null)) or not _bounded_number(data["exit"].get("required_power", null), 6.0, 6.0):
		errors.append("Invalid exit reference or power requirement")
	if not data["guide"] is Dictionary or not data["guide"].get("landmarks", null) is Dictionary:
		errors.append("Invalid guide landmarks")
	else:
		var landmarks: Dictionary = data["guide"]["landmarks"]
		for key: String in ["home", "highway", "highway_road", "middle_camp", "middle_road", "quarry", "fuel", "forward_cache", "forward_road", "front_camp", "front_road", "exit", "exit_power", "west_gate", "east_gate"]:
			if not _valid_position(landmarks.get(key, null), size) or not _walkable(Vector2i(landmarks.get(key, Vector2(-1, -1))), size, geometry["terrain"]):
				errors.append("Invalid guide landmark: " + key)
			else:
				positions.append(Vector2i(landmarks[key]))
		for key: String in ["branch_text", "route_text"]:
			if not _nonempty_text(data["guide"].get(key, null), 1024): errors.append("Invalid guide text: " + key)
		if not data["guide"].get("choices", null) is Array or data["guide"]["choices"].size() != 2:
			errors.append("Two route choices are required")
		else:
			for choice: Variant in data["guide"]["choices"]:
				if not _nonempty_text(choice, 512): errors.append("Invalid route choice")
		if not _bounded_number(data["guide"].get("middle_min_x", null), 20.0, 20.0) or not _bounded_number(data["guide"].get("front_min_x", null), 45.0, 45.0):
			errors.append("Invalid camp phase ranges")
		if errors.is_empty():
			for site: Dictionary in data["sites"]:
				var landmark_key: String = "forward_cache" if site["key"] == "forward" else String(site["key"])
				if landmarks.has(landmark_key) and Vector2(landmarks[landmark_key]) != Vector2(site["pos"]):
					errors.append("Guide target differs from site: " + landmark_key)
			for choke: Dictionary in data["chokes"]:
				if Vector2(landmarks[String(choke["key"]) + "_gate"]) != Vector2(choke["pos"]):
					errors.append("Guide target differs from choke")
			if Vector2(landmarks["home"]) != Vector2(data["camps"][0]["pos"]):
				errors.append("Guide target differs from home")
			if Vector2(landmarks["exit_power"]).distance_to(Vector2(landmarks["exit"])) > 10.0:
				errors.append("Exit generator suggestion cannot reach exit")
	if not data["pacing"] is Dictionary:
		errors.append("Invalid pacing")
	else:
		for key: String in ["pursuit_x", "pursuit_eta", "pursuit_speed", "pursuit_start", "spawn_y", "first_gate_x", "evacuation_x", "exit_x"]:
			if not _bounded_number(data["pacing"].get(key, null), -10.0 if key == "pursuit_x" else 0.0, 3600.0): errors.append("Invalid pacing: " + key)
		if not _bounded_number(data["pacing"].get("pursuit_speed", null), 0.01, 0.1): errors.append("Invalid pursuit speed")
		if not _bounded_number(data["pacing"].get("spawn_y", null), 3.0, 34.0): errors.append("Pursuit spawn row is outside map interior")
		for key: String in ["first_gate_x", "evacuation_x", "exit_x"]:
			if not _bounded_number(data["pacing"].get(key, null), 2.0, 77.0): errors.append("Pacing landmark is outside map interior: " + key)
		if not data["pacing"].get("target_minutes", null) is Vector2i or data["pacing"]["target_minutes"] != Vector2i(25, 35): errors.append("Invalid target duration")
	for message: Variant in data["messages"]:
		if not _nonempty_text(message, 512): errors.append("Invalid opening message")
	if errors.is_empty():
		var origin: Vector2i = Vector2i(data["camps"][0]["pos"])
		for target: Vector2i in positions:
			if _path_geometry(geometry, origin, target).is_empty():
				errors.append("Unreachable required position: " + str(target))
	return errors


static func _valid_rect(value: Variant, size: Vector2i) -> bool:
	return value is Rect2i and value.size.x > 0 and value.size.y > 0 and value.position.x >= 0 and value.position.y >= 0 and value.end.x <= size.x and value.end.y <= size.y


static func _valid_position(value: Variant, size: Vector2i) -> bool:
	if not value is Vector2 and not value is Vector2i:
		return false
	var position: Vector2 = Vector2(value)
	return is_finite(position.x) and is_finite(position.y) and position == position.round() and position.x >= 0.0 and position.x < size.x and position.y >= 0.0 and position.y < size.y


static func _walkable(tile: Vector2i, size: Vector2i, rows: Array) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < size.x and tile.y < size.y and int(rows[tile.y][tile.x]) >= 0


static func _valid_stock(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		if not key is String or not RESOURCE_KEYS.has(key) or not _bounded_number(value[key], 0.0, 10000.0):
			return false
	return true


static func _bounded_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _nonempty_text(value: Variant, maximum: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= maximum


static func _identifier(value: Variant) -> bool:
	if not value is String or value.length() < 1 or value.length() > 32:
		return false
	for index: int in range(value.length()):
		var character: int = value.unicode_at(index)
		if not ((character >= 97 and character <= 122) or (character >= 48 and character <= 57 and index > 0) or (character == 95 and index > 0)):
			return false
	return true
