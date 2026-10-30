extends Node2D
## Original modular sprite artwork and procedural terrain for the campaign.
## All positions are continuous simulation tile coordinates, never screen pixels.

const TILE_SIZE: float = 48.0
const INK: Color = Color("252a2c")
const SAND: Color = Color("cda16a")
const SAND_LIGHT: Color = Color("d7b37b")
const HIGH_SAND: Color = Color("e4bc7b")
const CLIFF: Color = Color("9a6b4f")
const TEAL: Color = Color("3a9297")
const CYAN: Color = Color("6ce2df")
const ORANGE: Color = Color("f3a343")
const RED: Color = Color("df6a57")
const GREEN: Color = Color("93b37a")
const BUILDING_ATLAS_PATH: String = "res://assets/buildings-atlas.png"
const BUILDING_REGIONS: Dictionary = {
	"command": Rect2(12.0, 31.0, 435.0, 404.0),
	"generator": Rect2(464.0, 148.0, 320.0, 275.0),
	"workshop": Rect2(811.0, 110.0, 429.0, 326.0),
	"barracks": Rect2(22.0, 541.0, 431.0, 281.0),
	"tower": Rect2(517.0, 469.0, 249.0, 367.0),
	"barricade": Rect2(809.0, 651.0, 426.0, 142.0),
	"fuel": Rect2(32.0, 945.0, 407.0, 245.0),
	"quarry": Rect2(463.0, 836.0, 321.0, 381.0),
	"exit": Rect2(809.0, 849.0, 420.0, 356.0)
}
const BUILDING_WIDTHS: Dictionary = {
	"command": 138.0, "camp": 105.0, "generator": 106.0,
	"workshop": 142.0, "barracks": 145.0, "tower": 87.0,
	"barricade": 140.0, "fuel": 125.0, "quarry": 108.0, "exit": 142.0
}

var sim: Variant = null
var selected_ids: Array = []
var hover_tile: Vector2i = Vector2i(-1, -1)
var build_kind: String = ""
var show_logistics: bool = true
var show_ranges: bool = false
var drag_selection_rect: Rect2 = Rect2()
var drag_selecting: bool = false
var world_font: Font = null
var guide_target: Vector2 = Vector2(-1, -1)
var use_building_sprites: bool = true
var building_atlas: Texture2D = null


func _ready() -> void:
	# Keep a complete procedural fallback when the optional atlas is absent.
	if ResourceLoader.exists(BUILDING_ATLAS_PATH):
		building_atlas = load(BUILDING_ATLAS_PATH) as Texture2D
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func tile_to_world(p: Vector2) -> Vector2:
	return p * TILE_SIZE


func world_to_tile(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE_SIZE), floori(p.y / TILE_SIZE))


func _draw() -> void:
	if sim == null:
		return
	var size: Vector2i = sim.map_size
	var bounds: Rect2i = _visible_tiles(size)
	draw_rect(Rect2(Vector2(-80.0, -80.0), Vector2(size) * TILE_SIZE + Vector2(160.0, 160.0)), Color("343637"))
	_draw_ground(bounds)
	_draw_cliffs(bounds)
	_draw_roads(bounds)
	_draw_decorations(bounds)
	_draw_pursuit(size)
	_draw_sites()
	if show_logistics:
		_draw_logistics()
	if show_ranges:
		_draw_ranges()
	var draw_items: Array[Dictionary] = []
	var buildings: Array = sim.buildings
	for value: Variant in buildings:
		var building: Dictionary = value
		var draw_position: Vector2 = building.get("pos", Vector2.ZERO)
		if _position_visible(draw_position, bounds, 3):
			draw_items.append({"entity": building, "kind": "building", "y": draw_position.y + 0.15})
	var units: Array = sim.units
	for value: Variant in units:
		var unit: Dictionary = value
		var draw_position: Vector2 = unit.get("pos", Vector2.ZERO)
		if _position_visible(draw_position, bounds, 2):
			draw_items.append({"entity": unit, "kind": "unit", "y": draw_position.y})
	draw_items.sort_custom(_sort_draw_items)
	for item: Dictionary in draw_items:
		var entity: Dictionary = item["entity"]
		if String(item["kind"]) == "building":
			_draw_building(entity)
		else:
			_draw_unit(entity)
	_draw_effects()
	_draw_orders()
	_draw_guide_target()
	_draw_build_preview()
	if drag_selecting:
		draw_rect(drag_selection_rect.abs(), Color(CYAN, 0.10), true)
		draw_rect(drag_selection_rect.abs(), Color(CYAN, 0.88), false, 2.0)


func _visible_tiles(size: Vector2i) -> Rect2i:
	var viewport_size: Vector2 = get_viewport_rect().size
	var inverse: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var a: Vector2 = inverse * Vector2.ZERO
	var b: Vector2 = inverse * viewport_size
	var start: Vector2i = Vector2i(floori(minf(a.x, b.x) / TILE_SIZE) - 3, floori(minf(a.y, b.y) / TILE_SIZE) - 3)
	var end: Vector2i = Vector2i(ceili(maxf(a.x, b.x) / TILE_SIZE) + 3, ceili(maxf(a.y, b.y) / TILE_SIZE) + 3)
	start = start.clamp(Vector2i.ZERO, size)
	end = end.clamp(Vector2i.ZERO, size)
	return Rect2i(start, end - start)


func _position_visible(draw_position: Vector2, bounds: Rect2i, margin: int) -> bool:
	return bounds.grow(margin).has_point(Vector2i(draw_position))


func _sort_draw_items(a: Dictionary, b: Dictionary) -> bool:
	return float(a["y"]) < float(b["y"])


func _terrain_at(tile: Vector2i) -> int:
	var size: Vector2i = sim.map_size
	if tile.x < 0 or tile.y < 0 or tile.x >= size.x or tile.y >= size.y:
		return -2
	var rows: Array = sim.terrain
	if tile.y >= rows.size():
		return -2
	var row: Array = rows[tile.y]
	if tile.x >= row.size():
		return -2
	return int(row[tile.x])


func _noise(tile: Vector2i, channel: int = 0) -> float:
	var value: float = sin(float(tile.x * 127 + tile.y * 311 + channel * 73 + 17) * 12.9898) * 43758.5453
	return value - floorf(value)


func _draw_ground(bounds: Rect2i) -> void:
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var tile: Vector2i = Vector2i(x, y)
			var elevation: int = _terrain_at(tile)
			var origin: Vector2 = Vector2(tile) * TILE_SIZE
			var grain: float = _noise(tile)
			if elevation < 0:
				var canyon_color: Color = Color("66594f").lerp(Color("756052"), grain * 0.6)
				draw_rect(Rect2(origin, Vector2.ONE * TILE_SIZE), canyon_color)
				if grain < 0.17:
					draw_line(origin + Vector2(9.0, 31.0), origin + Vector2(28.0, 36.0), Color("554c46"), 2.0)
				continue
			var base: Color = SAND.lerp(SAND_LIGHT, 0.28 + grain * 0.13)
			if elevation > 0:
				base = HIGH_SAND.lerp(Color("d8ab6d"), 0.25 + grain * 0.12)
			draw_rect(Rect2(origin, Vector2.ONE * TILE_SIZE + Vector2.ONE), base)
			if grain < 0.22:
				var patch: Vector2 = origin + Vector2(7.0 + grain * 50.0, 10.0 + _noise(tile, 2) * 18.0)
				_oval(patch, Vector2(15.0, 5.0), Color(base.darkened(0.045), 0.65))
			if _noise(tile, 8) < 0.2:
				var p: Vector2 = origin + Vector2(8.0 + _noise(tile, 9) * 31.0, 9.0 + _noise(tile, 10) * 30.0)
				draw_line(p, p + Vector2(3.0, 0.0), Color("a98860"), 1.1)
				draw_line(p + Vector2(7.0, 3.0), p + Vector2(9.0, 3.0), Color("ead0a0"), 1.3)


func _draw_cliffs(bounds: Rect2i) -> void:
	var ramps: Dictionary = sim.ramps
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var tile: Vector2i = Vector2i(x, y)
			var height: int = _terrain_at(tile)
			if height < 0:
				continue
			var p: Vector2 = Vector2(tile) * TILE_SIZE
			var below: int = _terrain_at(tile + Vector2i.DOWN)
			var right: int = _terrain_at(tile + Vector2i.RIGHT)
			var left: int = _terrain_at(tile + Vector2i.LEFT)
			var cliff_depth: float = 34.0 if height > 0 else 22.0
			if below < height and not ramps.has(tile) and not ramps.has(tile + Vector2i.DOWN):
				_poly(PackedVector2Array([p + Vector2(0.0, 46.0), p + Vector2(48.0, 46.0), p + Vector2(45.0, 48.0 + cliff_depth), p + Vector2(31.0, 51.0 + cliff_depth), p + Vector2(13.0, 48.0 + cliff_depth), p + Vector2(-2.0, 47.0 + cliff_depth)]), CLIFF, 1.5)
				draw_line(p + Vector2(1.0, 46.0), p + Vector2(47.0, 46.0), Color("f3cc8a"), 3.0)
				for seam: int in range(3):
					var sx: float = 9.0 + float(seam) * 15.0 + _noise(tile, seam + 3) * 5.0
					draw_polyline(PackedVector2Array([p + Vector2(sx, 49.0), p + Vector2(sx - 3.0, 55.0), p + Vector2(sx - 1.0, 48.0 + cliff_depth)]), Color("795740"), 1.5)
			if right < height and not ramps.has(tile):
				_poly(PackedVector2Array([p + Vector2(47.0, 1.0), p + Vector2(63.0, 12.0), p + Vector2(62.0, 47.0 + cliff_depth), p + Vector2(47.0, 47.0)]), Color("8a6049"), 1.2)
				draw_line(p + Vector2(52.0, 17.0), p + Vector2(57.0, 45.0 + cliff_depth), Color("6f5442"), 1.4)
			if left < height and not ramps.has(tile):
				draw_line(p + Vector2(1.0, 3.0), p + Vector2(1.0, 44.0), Color("a97f53"), 2.0)


func _draw_roads(bounds: Rect2i) -> void:
	var roads: Dictionary = sim.roads
	var ramps: Dictionary = sim.ramps
	for key: Variant in roads:
		var tile: Vector2i = key
		if not bounds.grow(1).has_point(tile):
			continue
		var center: Vector2 = (Vector2(tile) + Vector2.ONE * 0.5) * TILE_SIZE
		var road_data: Variant = roads[tile]
		if road_data is Dictionary and float(road_data.get("progress", 1.0)) < 0.999:
			var progress: float = float(road_data.get("progress", 0.0))
			draw_rect(Rect2(center - Vector2(17.0, 15.0), Vector2(34.0, 30.0)), Color(CYAN, 0.10))
			draw_rect(Rect2(center - Vector2(17.0, 15.0), Vector2(34.0, 30.0)), Color(CYAN, 0.55), false, 1.5)
			_progress_bar(center + Vector2(-15.0, 17.0), 30.0, progress, CYAN, 3.0)
			continue
		if ramps.has(tile):
			continue
		var bridge: bool = _terrain_at(tile) < 0
		if bridge:
			_draw_bridge(tile, roads)
			continue
		var connected: bool = false
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if roads.has(tile + direction):
				connected = true
				var end: Vector2 = center + Vector2(direction) * TILE_SIZE * 0.52
				draw_line(center, end, Color("a98861"), 29.0)
				draw_line(center, end, Color("ead1a1"), 23.0)
				if _noise(tile, 11) < 0.57:
					draw_line(center + Vector2(direction) * 5.0, center + Vector2(direction) * 15.0, Color("c6a577"), 2.0)
		if not connected:
			_oval(center, Vector2(16.0, 14.0), Color("ead1a1"))
	_draw_ramp_regions(bounds)


func _draw_ramp_regions(bounds: Rect2i) -> void:
	var ramps: Dictionary = sim.ramps
	var visited: Dictionary = {}
	for key: Variant in ramps:
		var first: Vector2i = key
		if visited.has(first):
			continue
		var frontier: Array[Vector2i] = [first]
		var minimum: Vector2i = first
		var maximum: Vector2i = first
		visited[first] = true
		while not frontier.is_empty():
			var tile: Vector2i = frontier.pop_back()
			minimum = Vector2i(mini(minimum.x, tile.x), mini(minimum.y, tile.y))
			maximum = Vector2i(maxi(maximum.x, tile.x), maxi(maximum.y, tile.y))
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = tile + direction
				if ramps.has(next) and not visited.has(next):
					visited[next] = true
					frontier.append(next)
		var region: Rect2i = Rect2i(minimum, maximum - minimum + Vector2i.ONE)
		if not bounds.intersects(region):
			continue
		var center: Vector2 = (Vector2(minimum) + Vector2(region.size) * 0.5) * TILE_SIZE
		var middle_y: int = (minimum.y + maximum.y) >> 1
		var west: int = _terrain_at(Vector2i(minimum.x - 1, middle_y))
		var east: int = _terrain_at(Vector2i(maximum.x + 1, middle_y))
		var horizontal: bool = west != east
		var length: float = float(region.size.x if horizontal else region.size.y) * TILE_SIZE
		var width: float = float(region.size.y if horizontal else region.size.x) * TILE_SIZE - 12.0
		draw_set_transform(center, 0.0 if horizontal else PI * 0.5)
		_box(Rect2(-length * 0.5, -width * 0.5, length, width), Color("8d795b"), 2.0)
		var steps: int = maxi(5, int(length / 11.0))
		for step: int in range(steps):
			var px: float = -length * 0.5 + float(step) * length / float(steps) + 1.0
			var plank_color: Color = Color("d0b285").lerp(Color("c6a475"), float(step % 3) * 0.1)
			_box(Rect2(px, -width * 0.5 + 4.0, length / float(steps) - 1.0, width - 8.0), plank_color, 0.8)
		for rail_y: float in [-width * 0.5, width * 0.5]:
			draw_line(Vector2(-length * 0.5, rail_y), Vector2(length * 0.5, rail_y), Color("5c5847"), 4.0)
			for post: int in range(4):
				var px: float = -length * 0.5 + float(post) * length / 3.0
				draw_line(Vector2(px, rail_y - 5.0), Vector2(px, rail_y + 5.0), INK, 3.0)
		draw_set_transform(Vector2.ZERO)


func _draw_bridge(tile: Vector2i, roads: Dictionary) -> void:
	var center: Vector2 = (Vector2(tile) + Vector2.ONE * 0.5) * TILE_SIZE
	var horizontal: bool = roads.has(tile + Vector2i.LEFT) or roads.has(tile + Vector2i.RIGHT)
	draw_set_transform(center, 0.0 if horizontal else PI * 0.5)
	_box(Rect2(-25.0, -17.0, 50.0, 34.0), Color("715743"), 2.0)
	for plank: int in range(6):
		var px: float = -23.0 + float(plank) * 8.0
		_box(Rect2(px, -14.0, 7.0, 27.0), Color("b98b59"), 1.0)
		draw_circle(Vector2(px + 3.0, -10.0), 1.2, INK)
		draw_circle(Vector2(px + 3.0, 9.0), 1.2, INK)
	draw_line(Vector2(-25.0, -19.0), Vector2(25.0, -19.0), Color("544a3b"), 4.0)
	draw_line(Vector2(-25.0, 17.0), Vector2(25.0, 17.0), Color("544a3b"), 4.0)
	for px: float in [-22.0, 22.0]:
		draw_line(Vector2(px, -24.0), Vector2(px, -13.0), INK, 4.0)
		draw_line(Vector2(px, 12.0), Vector2(px, 22.0), INK, 4.0)
	draw_set_transform(Vector2.ZERO)


func _draw_ramp(tile: Vector2i) -> void:
	var p: Vector2 = Vector2(tile) * TILE_SIZE
	_poly(PackedVector2Array([p + Vector2(5.0, 3.0), p + Vector2(42.0, 3.0), p + Vector2(46.0, 47.0), p + Vector2(1.0, 47.0)]), Color("b69a73"), 1.4)
	for step: int in range(7):
		var sy: float = 6.0 + float(step) * 6.0
		draw_line(p + Vector2(5.0, sy), p + Vector2(42.0, sy), Color("e5c89b"), 3.0)
		draw_line(p + Vector2(5.0, sy + 2.0), p + Vector2(42.0, sy + 2.0), Color("8b775c"), 1.0)
	draw_line(p + Vector2(2.0, 5.0), p + Vector2(0.0, 46.0), Color("665644"), 3.0)
	draw_line(p + Vector2(45.0, 5.0), p + Vector2(48.0, 46.0), Color("665644"), 3.0)


func _draw_decorations(bounds: Rect2i) -> void:
	var roads: Dictionary = sim.roads
	var ramps: Dictionary = sim.ramps
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var tile: Vector2i = Vector2i(x, y)
			if _terrain_at(tile) < 0 or roads.has(tile) or ramps.has(tile):
				continue
			var n: float = _noise(tile, 12)
			var center: Vector2 = (Vector2(tile) + Vector2(0.3 + _noise(tile, 13) * 0.4, 0.3 + _noise(tile, 14) * 0.4)) * TILE_SIZE
			if n < 0.033:
				_draw_rock(center, 0.55 + _noise(tile, 15) * 0.65)
			elif n < 0.048:
				_draw_dead_tree(center, 0.7 + _noise(tile, 15) * 0.4)
			elif n < 0.17:
				_draw_grass(center, _noise(tile, 15))
			elif n > 0.987:
				draw_set_transform(center)
				_draw_barrel(Vector2.ZERO, Color("7d8980"), 0.55)
				draw_set_transform(Vector2.ZERO)


func _draw_rock(center: Vector2, scale_value: float) -> void:
	var s: float = scale_value
	_oval(center + Vector2(1.0, 5.0) * s, Vector2(15.0, 6.0) * s, Color("a58b68"))
	_poly(PackedVector2Array([center + Vector2(-13.0, 2.0) * s, center + Vector2(-8.0, -9.0) * s, center + Vector2(3.0, -13.0) * s, center + Vector2(13.0, -4.0) * s, center + Vector2(14.0, 5.0) * s, center + Vector2(-1.0, 8.0) * s]), Color("8d9187"), 1.6)
	_poly(PackedVector2Array([center + Vector2(-8.0, -9.0) * s, center + Vector2(3.0, -13.0) * s, center + Vector2(5.0, -2.0) * s, center + Vector2(-2.0, 2.0) * s]), Color("b2b3a0"), 0.0)


func _draw_grass(center: Vector2, variation: float) -> void:
	var color: Color = Color("8d8c54").lerp(Color("9e8249"), variation)
	draw_line(center, center + Vector2(-5.0, -7.0), color, 1.8)
	draw_line(center, center + Vector2(-1.0, -10.0), color, 1.8)
	draw_line(center, center + Vector2(4.0, -8.0), color, 1.8)
	draw_line(center + Vector2(-4.0, 1.0), center + Vector2(6.0, 1.0), Color("b19560"), 1.3)


func _draw_dead_tree(center: Vector2, scale_value: float) -> void:
	var s: float = scale_value
	_oval(center + Vector2(3.0, 3.0) * s, Vector2(16.0, 5.0) * s, Color("b1946c"))
	draw_polyline(PackedVector2Array([center + Vector2(-2.0, 2.0) * s, center + Vector2(1.0, -18.0) * s, center + Vector2(-2.0, -33.0) * s]), INK, 5.0 * s)
	draw_line(center + Vector2(0.0, -15.0) * s, center + Vector2(-13.0, -25.0) * s, INK, 3.5 * s)
	draw_line(center + Vector2(0.0, -20.0) * s, center + Vector2(12.0, -29.0) * s, INK, 3.5 * s)
	draw_line(center + Vector2(-1.0, -1.0) * s, center + Vector2(1.0, -26.0) * s, Color("796547"), 2.0 * s)


func _draw_pursuit(size: Vector2i) -> void:
	var pursuit_x: float = float(sim.pursuit_x) * TILE_SIZE
	if pursuit_x < 0.0:
		return
	var height: float = float(size.y) * TILE_SIZE
	draw_rect(Rect2(0.0, 0.0, pursuit_x, height), Color(0.42, 0.12, 0.10, 0.12))
	draw_rect(Rect2(pursuit_x - 16.0, 0.0, 32.0, height), Color(0.71, 0.26, 0.18, 0.10))
	for y: int in range(0, int(height), 38):
		draw_line(Vector2(pursuit_x, float(y)), Vector2(pursuit_x, float(y) + 20.0), Color(RED, 0.65), 3.0)


func _draw_sites() -> void:
	var sites: Array = sim.sites
	for value: Variant in sites:
		var site: Dictionary = value
		var p: Vector2 = tile_to_world(site.get("pos", Vector2.ZERO))
		var kind: String = String(site.get("kind", "cache"))
		var captured: bool = bool(site.get("captured", false))
		var tint: Color = CYAN if captured else ORANGE
		_dashed_circle(p, 49.0, Color(tint, 0.48), 1.8, 12)
		draw_set_transform(p)
		if kind == "quarry":
			_draw_rock(Vector2(-14.0, 8.0), 1.5)
			_draw_rock(Vector2(10.0, -6.0), 1.7)
			_draw_rock(Vector2(28.0, 13.0), 0.8)
			_draw_pickaxe(Vector2(-26.0, -22.0), Color("e6c38e"))
		elif kind == "fuel":
			_draw_barrel(Vector2(-16.0, 3.0), Color("ba744a"), 1.2)
			_draw_barrel(Vector2(9.0, -4.0), Color("c78043"), 1.25)
			_draw_barrel(Vector2(27.0, 13.0), Color("825d49"), 0.9)
		elif kind == "exit":
			_draw_exit_gate()
		else:
			_draw_crate(Vector2(-15.0, 5.0), 1.1)
			_draw_crate(Vector2(10.0, -7.0), 1.0)
			_draw_crate(Vector2(23.0, 14.0), 0.8)
		draw_set_transform(Vector2.ZERO)
		var label: String = {"quarry": "废料场", "fuel": "油料仓库", "cache": "公路补给", "exit": "撤离站"}.get(kind, "资源点")
		_badge(p + Vector2(0.0, 49.0), label, tint, 12)
		var progress: float = float(site.get("progress", 0.0))
		if progress > 0.0 and progress < 1.0:
			_progress_bar(p + Vector2(-27.0, 62.0), 54.0, progress, CYAN)


func _draw_logistics() -> void:
	var buildings: Array = sim.buildings
	var generators: Array[Dictionary] = []
	for value: Variant in buildings:
		var building: Dictionary = value
		if String(building.get("kind", "")) == "generator" and float(building.get("progress", 1.0)) >= 1.0 and bool(building.get("powered", false)):
			generators.append(building)
	for value: Variant in buildings:
		var building: Dictionary = value
		var kind: String = String(building.get("kind", ""))
		if not ["workshop", "tower", "barracks", "exit"].has(kind) or not bool(building.get("powered", false)):
			continue
		var p: Vector2 = building.get("pos", Vector2.ZERO)
		var nearest: Dictionary = {}
		var distance: float = INF
		for generator: Dictionary in generators:
			if int(generator.get("camp_id", -1)) != int(building.get("camp_id", -2)):
				continue
			var gp: Vector2 = generator.get("pos", Vector2.ZERO)
			var candidate: float = p.distance_squared_to(gp)
			var radius: float = float(generator.get("power_radius", 10.0))
			if candidate > radius * radius:
				continue
			if candidate < distance:
				distance = candidate
				nearest = generator
		if nearest.is_empty():
			continue
		var source: Vector2 = tile_to_world(nearest.get("pos", Vector2.ZERO)) + Vector2(20.0, 12.0)
		var destination: Vector2 = tile_to_world(p) + Vector2(-15.0, 12.0)
		var bend: Vector2 = Vector2(destination.x, source.y + 8.0)
		var points: PackedVector2Array = PackedVector2Array([source, source + Vector2(10.0, 8.0), bend, destination])
		draw_polyline(points, Color(INK, 0.65), 6.0, true)
		draw_polyline(points, Color(ORANGE, 0.72), 3.0, true)
		var pulse: float = fposmod(float(sim.time) * 0.45 + float(building.get("id", 0)) * 0.13, 1.0)
		var spark: Vector2 = _polyline_point(points, pulse)
		draw_circle(spark, 2.4, Color("ffe1a0"))
	var units: Array = sim.units
	for value: Variant in units:
		var unit: Dictionary = value
		if String(unit.get("kind", "")) != "truck":
			continue
		var path_value: Variant = unit.get("path", [])
		if not path_value is Array:
			continue
		var path: Array = path_value
		if path.is_empty():
			continue
		var points: PackedVector2Array = PackedVector2Array([tile_to_world(unit.get("pos", Vector2.ZERO))])
		for point_value: Variant in path:
			if point_value is Vector2 or point_value is Vector2i:
				points.append(tile_to_world(Vector2(point_value)))
			if points.size() >= 20:
				break
		if points.size() > 1:
			draw_polyline(points, Color(CYAN, 0.22), 3.0, true)


func _draw_ranges() -> void:
	var buildings: Array = sim.buildings
	for value: Variant in buildings:
		var building: Dictionary = value
		var kind: String = String(building.get("kind", ""))
		var p: Vector2 = tile_to_world(building.get("pos", Vector2.ZERO))
		if kind == "generator":
			var radius: float = float(building.get("power_radius", 7.0)) * TILE_SIZE
			draw_circle(p, radius, Color(ORANGE, 0.045))
			_dashed_circle(p, radius, Color(ORANGE, 0.45), 1.5, 40)
		elif kind == "tower":
			var radius: float = float(building.get("range", 8.0)) * TILE_SIZE
			_dashed_circle(p, radius, Color(CYAN, 0.32), 1.5, 40)


func _draw_building(building: Dictionary) -> void:
	var p: Vector2 = tile_to_world(building.get("pos", Vector2.ZERO))
	var kind: String = String(building.get("kind", "camp"))
	var progress: float = clampf(float(building.get("progress", 1.0)), 0.0, 1.0)
	var abandoned: bool = bool(building.get("abandoned", false))
	var powered: bool = bool(building.get("powered", false)) and not abandoned
	var hp: float = float(building.get("hp", 100.0))
	var max_hp: float = maxf(1.0, float(building.get("max_hp", 100.0)))
	var construction_started: bool = bool(building.get("construction_started", true))
	var visual_size: Vector2 = _building_visual_size(kind)
	_oval(p + Vector2(3.0, 1.0), Vector2(visual_size.x * 0.36, 12.0), Color(0.21, 0.22, 0.19, 0.23))
	draw_set_transform(p)
	var drawn_sprite: bool = _draw_building_sprite(kind, powered, abandoned, progress, p)
	if not drawn_sprite:
		# Procedural bodies historically use a local ground line at y=30.
		draw_set_transform(p - Vector2(0.0, 30.0))
		match kind:
			"command":
				_draw_command_tent()
			"camp":
				_draw_camp_tent()
			"generator":
				_draw_generator(powered and progress >= 1.0, int(building.get("id", 0)))
			"workshop":
				_draw_workshop(powered and progress >= 1.0)
			"barracks":
				_draw_barracks()
			"tower":
				_draw_tower(powered)
			"barricade":
				_draw_barricade()
			"quarry":
				_draw_quarry()
			"fuel":
				_draw_fuel_station()
			"exit":
				_draw_exit_gate()
			_:
				_draw_camp_tent()
	draw_set_transform(p)
	if progress < 1.0 and construction_started:
		_draw_scaffolding(progress, visual_size)
	if abandoned:
		var board_top: float = -minf(visual_size.y * 0.45, 42.0)
		draw_line(Vector2(-18.0, board_top), Vector2(17.0, -7.0), INK, 6.0)
		draw_line(Vector2(-18.0, board_top), Vector2(17.0, -7.0), Color("96856a"), 3.5)
		draw_line(Vector2(17.0, board_top), Vector2(-18.0, -7.0), INK, 6.0)
		draw_line(Vector2(17.0, board_top), Vector2(-18.0, -7.0), Color("96856a"), 3.5)
	if kind == "generator" or kind == "workshop" or kind == "tower" or kind == "barracks":
		var lamp: Vector2 = Vector2(visual_size.x * 0.31, -13.0)
		draw_circle(lamp, 4.5, INK)
		draw_circle(lamp, 2.8, ORANGE if powered else Color("7b7d6b"))
	if drawn_sprite and powered and progress >= 1.0 and kind == "generator":
		_draw_generator_activity(visual_size, int(building.get("id", 0)))
	draw_set_transform(Vector2.ZERO)
	if hp < max_hp - 0.1:
		var label_offset: float = 31.0 if ["command", "camp", "barracks"].has(kind) else 13.0
		_progress_bar(p + Vector2(-26.0, -visual_size.y - label_offset), 52.0, hp / max_hp, GREEN if hp / max_hp > 0.4 else RED)
	if progress < 1.0:
		if construction_started:
			_progress_bar(p + Vector2(-26.0, 12.0), 52.0, progress, CYAN)
			_badge(p + Vector2(0.0, 27.0), "施工 %d%%" % int(progress * 100.0), CYAN, 10)
		else:
			_badge(p + Vector2(0.0, 18.0), "待修复", ORANGE, 10)
	if kind == "barracks":
		_badge(p + Vector2(0.0, -visual_size.y - 6.0), "军营", CYAN, 11)
	if kind == "command" or kind == "camp":
		var camp_id: int = int(building.get("camp_id", -1))
		var camp_state: String = ""
		var camp_name: String = "营地 %d" % camp_id
		var camps: Array = sim.camps
		for value: Variant in camps:
			var camp: Dictionary = value
			if int(camp.get("id", -2)) == camp_id:
				camp_state = String(camp.get("state", "active"))
				camp_name = String(camp.get("name", camp_name))
		var label: String = camp_name
		if camp_state == "packing":
			label = "正在打包"
		elif camp_state == "abandoned":
			label = "已弃置"
		_badge(p + Vector2(0.0, -visual_size.y - 6.0), label, CYAN if camp_state == "active" else ORANGE, 11)


func _building_visual_size(kind: String) -> Vector2:
	var source_kind: String = "command" if kind == "camp" else kind
	if use_building_sprites and building_atlas != null and BUILDING_REGIONS.has(source_kind):
		var source: Rect2 = BUILDING_REGIONS[source_kind]
		var width: float = float(BUILDING_WIDTHS.get(kind, 120.0))
		return Vector2(width, width * source.size.y / source.size.x)
	return Vector2(94.0, 110.0 if kind == "tower" else 94.0)


func _draw_building_sprite(kind: String, powered: bool, abandoned: bool, progress: float, anchor: Vector2) -> bool:
	var source_kind: String = "command" if kind == "camp" else kind
	if not use_building_sprites or building_atlas == null or not BUILDING_REGIONS.has(source_kind):
		return false
	var source: Rect2 = BUILDING_REGIONS[source_kind]
	if source.end.x > float(building_atlas.get_width()) or source.end.y > float(building_atlas.get_height()):
		return false
	var size: Vector2 = _building_visual_size(kind)
	var destination: Rect2 = Rect2(Vector2(-size.x * 0.5, -size.y), size)
	var tint: Color = Color.WHITE
	if abandoned:
		tint = Color(0.59, 0.62, 0.58, 0.90)
	elif not powered and ["generator", "workshop", "tower", "barracks"].has(kind):
		tint = Color(0.67, 0.73, 0.73, 1.0)
	if progress < 1.0:
		tint.a = 0.34 + progress * 0.56
	# Tall sprites may cover selectable soldiers standing behind the structure.
	# Reveal selected friendlies while retaining normal depth sorting otherwise.
	if not selected_ids.is_empty():
		var roof_margin: float = minf(24.0, size.y * 0.25)
		var footprint: Rect2 = Rect2(anchor + destination.position + Vector2(0.0, roof_margin), destination.size - Vector2(0.0, roof_margin))
		var units: Array = sim.units
		for value: Variant in units:
			var unit: Dictionary = value
			if selected_ids.has(int(unit.get("id", -1))) and footprint.has_point(tile_to_world(unit.get("pos", Vector2.ZERO))):
				tint.a *= 0.60
				break
	draw_texture_rect_region(building_atlas, destination, source, tint)
	return true


func _draw_generator_activity(size: Vector2, object_id: int) -> void:
	var pulse: float = 0.5 + sin(float(sim.time) * 4.0) * 0.13
	_oval(Vector2(0.0, -size.y * 0.66), Vector2(size.x * 0.17, size.y * 0.09), Color(ORANGE, pulse * 0.15))
	for puff: int in range(3):
		var age: float = fposmod(float(sim.time) * 0.35 + float(puff) / 3.0 + float(object_id) * 0.11, 1.0)
		var smoke_position: Vector2 = Vector2(-size.x * 0.35 + sin(age * 5.0) * 7.0, -size.y * 0.84 - age * 32.0)
		draw_circle(smoke_position, 3.0 + age * 7.0, Color(0.37, 0.37, 0.32, (1.0 - age) * 0.23))


func _draw_command_tent() -> void:
	_box(Rect2(-39.0, -7.0, 77.0, 37.0), Color("a78e66"), 2.4)
	_poly(PackedVector2Array([Vector2(-46.0, -10.0), Vector2(-15.0, -44.0), Vector2(22.0, -43.0), Vector2(46.0, -9.0)]), Color("4b9290"), 3.0)
	_poly(PackedVector2Array([Vector2(-15.0, -44.0), Vector2(0.0, -8.0), Vector2(46.0, -9.0), Vector2(22.0, -43.0)]), Color("367b80"), 1.5)
	draw_line(Vector2(-17.0, -42.0), Vector2(-2.0, -9.0), Color("81b3a3"), 2.5)
	_poly(PackedVector2Array([Vector2(-17.0, 28.0), Vector2(-4.0, -6.0), Vector2(10.0, 28.0)]), Color("2e3f40"), 2.0)
	_poly(PackedVector2Array([Vector2(-4.0, -6.0), Vector2(19.0, 25.0), Vector2(10.0, 28.0)]), Color("7eaa9a"), 1.0)
	_box(Rect2(19.0, 1.0, 13.0, 12.0), Color("f1cd78"), 2.0)
	draw_line(Vector2(25.5, 1.0), Vector2(25.5, 13.0), INK, 1.5)
	draw_line(Vector2(19.0, 7.0), Vector2(32.0, 7.0), INK, 1.5)
	draw_line(Vector2(-40.0, -7.0), Vector2(-52.0, 29.0), Color("665845"), 1.8)
	draw_line(Vector2(40.0, -7.0), Vector2(52.0, 29.0), Color("665845"), 1.8)
	_draw_crate(Vector2(-37.0, 27.0), 0.65)
	_draw_barrel(Vector2(37.0, 26.0), Color("72887e"), 0.65)
	draw_line(Vector2(-31.0, -30.0), Vector2(-31.0, -64.0), INK, 3.0)
	_poly(PackedVector2Array([Vector2(-30.0, -63.0), Vector2(-8.0, -59.0), Vector2(-9.0, -44.0), Vector2(-30.0, -47.0)]), TEAL, 1.8)
	draw_line(Vector2(-24.0, -54.0), Vector2(-15.0, -53.0), Color("f0e1b8"), 2.0)
	draw_line(Vector2(-20.0, -58.0), Vector2(-20.0, -49.0), Color("f0e1b8"), 2.0)


func _draw_camp_tent() -> void:
	_poly(PackedVector2Array([Vector2(-34.0, 22.0), Vector2(-6.0, -30.0), Vector2(34.0, 20.0)]), Color("c8c29b"), 2.5)
	_poly(PackedVector2Array([Vector2(-6.0, -30.0), Vector2(11.0, -34.0), Vector2(43.0, 16.0), Vector2(34.0, 20.0)]), Color("8b9f8b"), 2.0)
	_poly(PackedVector2Array([Vector2(-17.0, 21.0), Vector2(-5.0, -13.0), Vector2(10.0, 21.0)]), Color("394746"), 1.6)
	_poly(PackedVector2Array([Vector2(-5.0, -13.0), Vector2(19.0, 21.0), Vector2(10.0, 21.0)]), Color("e0d2a5"), 1.0)
	draw_line(Vector2(-32.0, 5.0), Vector2(-42.0, 25.0), Color("74644b"), 1.5)
	draw_line(Vector2(34.0, 5.0), Vector2(46.0, 25.0), Color("74644b"), 1.5)
	_draw_crate(Vector2(-30.0, 26.0), 0.6)
	_box(Rect2(17.0, -3.0, 14.0, 13.0), Color("e1d8b2"), 1.5)
	draw_line(Vector2(24.0, -1.0), Vector2(24.0, 8.0), RED, 3.0)
	draw_line(Vector2(19.5, 3.5), Vector2(28.5, 3.5), RED, 3.0)


func _draw_generator(active: bool, object_id: int) -> void:
	_box(Rect2(-31.0, -15.0, 59.0, 40.0), Color("54777b"), 2.8)
	_poly(PackedVector2Array([Vector2(-31.0, -15.0), Vector2(-22.0, -25.0), Vector2(36.0, -25.0), Vector2(28.0, -15.0)]), Color("8caaa0"), 2.0)
	_poly(PackedVector2Array([Vector2(28.0, -15.0), Vector2(36.0, -25.0), Vector2(36.0, 15.0), Vector2(28.0, 25.0)]), Color("36585e"), 1.8)
	draw_circle(Vector2(-12.0, 3.0), 13.0, INK)
	draw_circle(Vector2(-12.0, 3.0), 10.5, Color("8eab9b"))
	var fan_angle: float = float(sim.time) * 4.2 if active else 0.2
	for blade: int in range(3):
		var direction: Vector2 = Vector2.from_angle(fan_angle + float(blade) * TAU / 3.0)
		draw_line(Vector2(-12.0, 3.0) + direction * 3.0, Vector2(-12.0, 3.0) + direction * 8.0, Color("344e50"), 4.0)
	draw_circle(Vector2(-12.0, 3.0), 2.8, INK)
	_poly(PackedVector2Array([Vector2(11.0, -10.0), Vector2(2.0, 4.0), Vector2(11.0, 4.0), Vector2(5.0, 17.0), Vector2(22.0, -1.0), Vector2(12.0, -1.0)]), ORANGE if active else Color("b8a67a"), 1.0)
	_box(Rect2(-23.0, -44.0, 9.0, 20.0), Color("596967"), 1.8)
	_box(Rect2(-26.0, -47.0, 15.0, 5.0), Color("8a9384"), 1.6)
	_box(Rect2(17.0, -37.0, 9.0, 11.0), Color("a4a98b"), 1.8)
	draw_line(Vector2(-25.0, 27.0), Vector2(27.0, 27.0), INK, 4.0)
	if active:
		for puff: int in range(3):
			var age: float = fposmod(float(sim.time) * 0.35 + float(puff) / 3.0 + float(object_id) * 0.11, 1.0)
			var smoke_position: Vector2 = Vector2(-18.0 + sin(age * 5.0) * 9.0, -49.0 - age * 36.0)
			draw_circle(smoke_position, 4.0 + age * 8.0, Color(0.37, 0.37, 0.32, (1.0 - age) * 0.23))


func _draw_workshop(active: bool) -> void:
	_box(Rect2(-36.0, -7.0, 72.0, 38.0), Color("ad8a59"), 2.6)
	_poly(PackedVector2Array([Vector2(-43.0, -8.0), Vector2(-31.0, -37.0), Vector2(35.0, -35.0), Vector2(43.0, -8.0)]), Color("46888a"), 2.5)
	for seam: int in range(6):
		var px: float = -30.0 + float(seam) * 12.0
		draw_line(Vector2(px, -33.0), Vector2(px + 3.0, -10.0), Color("79aaa0"), 2.0)
	_box(Rect2(-15.0, -5.0, 24.0, 35.0), Color("364749"), 2.0)
	_box(Rect2(15.0, 0.0, 15.0, 12.0), Color("e4b56c") if active else Color("6c7771"), 1.6)
	_box(Rect2(-34.0, 3.0, 12.0, 11.0), Color("617e79"), 1.6)
	_box(Rect2(-38.0, 23.0, 23.0, 7.0), Color("7c6349"), 1.8)
	draw_line(Vector2(-35.0, 30.0), Vector2(-35.0, 36.0), INK, 2.3)
	draw_line(Vector2(-19.0, 30.0), Vector2(-19.0, 36.0), INK, 2.3)
	_draw_wrench(Vector2(-3.0, -23.0), Color("efe0b2"), 0.9)
	_draw_crate(Vector2(37.0, 29.0), 0.75)
	_box(Rect2(25.0, -49.0, 9.0, 16.0), Color("667672"), 1.8)
	_box(Rect2(22.0, -52.0, 15.0, 5.0), Color("a0a78e"), 1.5)


func _draw_barracks() -> void:
	# Broad prefab hut, military chevrons, flag and a real-looking rifle rack.
	# The silhouettes deliberately differ from the triangular command tent.
	_box(Rect2(-39.0, -8.0, 78.0, 39.0), Color("9aab8c"), 2.6)
	_poly(PackedVector2Array([Vector2(-46.0, -10.0), Vector2(-31.0, -37.0), Vector2(31.0, -37.0), Vector2(46.0, -10.0)]), Color("c0c5a0"), 2.6)
	for seam: int in range(6):
		var px: float = -29.0 + float(seam) * 12.0
		draw_line(Vector2(px, -33.0), Vector2(px - 5.0, -12.0), Color("879b83"), 1.8)
	_poly(PackedVector2Array([Vector2(-12.0, -31.0), Vector2(0.0, -23.0), Vector2(12.0, -31.0), Vector2(12.0, -25.0), Vector2(0.0, -17.0), Vector2(-12.0, -25.0)]), TEAL, 1.2)
	_box(Rect2(-26.0, -6.0, 20.0, 36.0), Color("35494a"), 2.0)
	draw_line(Vector2(-15.0, -4.0), Vector2(-15.0, 28.0), Color("788a78"), 1.5)
	_box(Rect2(5.0, -2.0, 24.0, 13.0), Color("76aba7"), 1.8)
	draw_line(Vector2(17.0, -1.0), Vector2(17.0, 10.0), INK, 1.5)
	draw_line(Vector2(7.0, 1.0), Vector2(12.0, 6.0), Color("c4d7b9"), 1.4)
	_box(Rect2(-30.0, 29.0, 30.0, 6.0), Color("b49c6a"), 1.5)
	_draw_crate(Vector2(34.0, 28.0), 0.8)
	for rifle: int in range(3):
		var px: float = 29.0 + float(rifle) * 6.0
		draw_line(Vector2(px, 20.0), Vector2(px + 2.0, -9.0), INK, 4.0)
		draw_line(Vector2(px, 20.0), Vector2(px + 1.0, 8.0), Color("9b744b"), 2.5)
		draw_line(Vector2(px + 1.0, 5.0), Vector2(px + 2.0, -9.0), Color("687a75"), 2.0)
	_box(Rect2(24.0, 7.0, 22.0, 5.0), Color("8f815e"), 1.5)
	draw_line(Vector2(-43.0, 23.0), Vector2(-43.0, -61.0), INK, 3.0)
	_poly(PackedVector2Array([Vector2(-42.0, -60.0), Vector2(-18.0, -56.0), Vector2(-22.0, -38.0), Vector2(-42.0, -42.0)]), TEAL, 1.8)
	draw_polyline(PackedVector2Array([Vector2(-37.0, -51.0), Vector2(-31.0, -46.0), Vector2(-25.0, -50.0)]), Color("f0dfb1"), 2.2)


func _draw_tower(powered: bool) -> void:
	draw_line(Vector2(-22.0, 27.0), Vector2(-16.0, -24.0), INK, 7.0)
	draw_line(Vector2(22.0, 27.0), Vector2(16.0, -24.0), INK, 7.0)
	draw_line(Vector2(-22.0, 27.0), Vector2(-16.0, -24.0), Color("9e8055"), 4.0)
	draw_line(Vector2(22.0, 27.0), Vector2(16.0, -24.0), Color("9e8055"), 4.0)
	draw_line(Vector2(-20.0, 18.0), Vector2(18.0, -16.0), Color("6b604b"), 4.0)
	draw_line(Vector2(20.0, 18.0), Vector2(-18.0, -16.0), Color("6b604b"), 4.0)
	_box(Rect2(-28.0, -29.0, 56.0, 11.0), Color("aa8c5c"), 2.5)
	_box(Rect2(-24.0, -44.0, 48.0, 18.0), Color("6b9084"), 2.2)
	for post: float in [-23.0, 0.0, 23.0]:
		draw_line(Vector2(post, -44.0), Vector2(post, -26.0), Color("344946"), 2.0)
	_poly(PackedVector2Array([Vector2(-32.0, -47.0), Vector2(-18.0, -60.0), Vector2(23.0, -59.0), Vector2(32.0, -46.0)]), Color("417c80"), 2.3)
	draw_circle(Vector2(2.0, -43.0), 7.0, INK)
	draw_circle(Vector2(2.0, -43.0), 5.0, Color("dcc19a"))
	_box(Rect2(-6.0, -51.0, 16.0, 7.0), TEAL, 1.5)
	_box(Rect2(-38.0, -38.0, 34.0, 6.0), Color("4d5d59"), 2.0)
	_box(Rect2(-43.0, -39.0, 7.0, 8.0), Color("303a3a"), 1.4)
	draw_line(Vector2(23.0, -58.0), Vector2(23.0, -76.0), INK, 2.0)
	draw_circle(Vector2(23.0, -77.0), 3.0, ORANGE if powered else Color("9b9d7e"))
	for step: int in range(4):
		draw_line(Vector2(0.0, float(step) * 9.0 - 12.0), Vector2(10.0, float(step) * 9.0 - 12.0), Color("b8a176"), 2.0)


func _draw_barricade() -> void:
	for plank: int in range(5):
		var px: float = -34.0 + float(plank) * 15.0
		var top: float = -22.0 - float(plank % 2) * 6.0
		_poly(PackedVector2Array([Vector2(px, 19.0), Vector2(px - 2.0, top), Vector2(px + 7.0, top - 5.0), Vector2(px + 13.0, top + 1.0), Vector2(px + 12.0, 19.0)]), Color("9d7c51"), 2.0)
	_box(Rect2(-38.0, -10.0, 78.0, 8.0), Color("6b776b"), 2.0)
	draw_line(Vector2(-32.0, 14.0), Vector2(30.0, -25.0), INK, 8.0)
	draw_line(Vector2(-32.0, 14.0), Vector2(30.0, -25.0), Color("bca16a"), 5.0)
	for bag: int in range(5):
		var px: float = -29.0 + float(bag) * 15.0
		_oval(Vector2(px, 23.0), Vector2(11.0, 6.0), Color("aaa379"))
		draw_arc(Vector2(px, 23.0), 9.0, PI, TAU, 8, Color("5f624c"), 1.0)


func _draw_quarry() -> void:
	_draw_rock(Vector2(-20.0, 14.0), 1.6)
	_draw_rock(Vector2(10.0, 19.0), 1.1)
	_box(Rect2(8.0, -14.0, 21.0, 32.0), Color("b88643"), 2.2)
	draw_line(Vector2(17.0, -12.0), Vector2(8.0, -50.0), INK, 7.0)
	draw_line(Vector2(17.0, -12.0), Vector2(8.0, -50.0), ORANGE, 4.0)
	draw_line(Vector2(8.0, -50.0), Vector2(-30.0, -42.0), INK, 7.0)
	draw_line(Vector2(8.0, -50.0), Vector2(-30.0, -42.0), ORANGE, 4.0)
	draw_line(Vector2(-30.0, -42.0), Vector2(-30.0, -14.0), INK, 1.5)
	_box(Rect2(-35.0, -17.0, 12.0, 9.0), Color("687873"), 1.5)
	_draw_pickaxe(Vector2(25.0, -23.0), Color("e8d8af"))


func _draw_fuel_station() -> void:
	_box(Rect2(-23.0, -28.0, 38.0, 48.0), Color("b9784a"), 2.0)
	_oval(Vector2(-4.0, -28.0), Vector2(19.0, 7.0), Color("dfad6b"))
	draw_arc(Vector2(-4.0, -28.0), 19.0, PI, TAU, 16, INK, 2.0)
	draw_line(Vector2(-23.0, -8.0), Vector2(15.0, -8.0), Color("785b45"), 3.0)
	draw_line(Vector2(-23.0, 9.0), Vector2(15.0, 9.0), Color("785b45"), 3.0)
	_draw_barrel(Vector2(27.0, 23.0), Color("bd7847"), 0.95)
	_box(Rect2(-37.0, -5.0, 14.0, 27.0), Color("5b7774"), 2.0)
	draw_polyline(PackedVector2Array([Vector2(-30.0, 0.0), Vector2(-43.0, -6.0), Vector2(-45.0, 18.0), Vector2(-38.0, 22.0)]), INK, 3.0)
	_poly(PackedVector2Array([Vector2(-6.0, -17.0), Vector2(-13.0, -4.0), Vector2(-10.0, 1.0), Vector2(-3.0, 1.0), Vector2(0.0, -4.0)]), Color("ead4a0"), 1.0)


func _draw_exit_gate() -> void:
	_box(Rect2(-43.0, -55.0, 10.0, 79.0), Color("687d73"), 2.5)
	_box(Rect2(33.0, -55.0, 10.0, 79.0), Color("687d73"), 2.5)
	_box(Rect2(-46.0, -61.0, 92.0, 18.0), Color("3d5e5d"), 2.5)
	_box(Rect2(-28.0, -57.0, 56.0, 10.0), Color("9fb18a"), 1.0)
	for x: float in [-38.0, 38.0]:
		draw_circle(Vector2(x, -31.0), 4.0, ORANGE)
		draw_circle(Vector2(x, -31.0), 7.0, Color(ORANGE, 0.10))
	for lane: int in range(3):
		var x: float = -13.0 + float(lane) * 16.0
		draw_polyline(PackedVector2Array([Vector2(x - 4.0, 13.0), Vector2(x + 3.0, 7.0), Vector2(x - 4.0, 1.0)]), Color("efe0b2"), 3.0)
	_label(Vector2(0.0, -47.0), "EVAC", Color("263f40"), 10)


func _draw_scaffolding(progress: float, visual_size: Vector2) -> void:
	var half_width: float = visual_size.x * 0.48
	var top: float = -visual_size.y * 0.77
	for x: float in [-half_width, half_width]:
		draw_line(Vector2(x, 5.0), Vector2(x, top), Color("4e5146"), 3.0)
		draw_line(Vector2(x - 5.0, top * 0.5), Vector2(x + 5.0, top * 0.5), Color("bba070"), 3.0)
	draw_line(Vector2(-half_width - 2.0, top * 0.45), Vector2(half_width + 2.0, top * 0.45), Color("b89d6a"), 4.0)
	draw_line(Vector2(-half_width, 2.0), Vector2(half_width, top), Color("7b7559"), 2.0)
	_box(Rect2(-half_width, -3.0, half_width * 2.0, 8.0), Color("d0a452"), 1.6)
	for stripe: int in range(6):
		var x: float = -half_width + 8.0 + float(stripe) * (half_width * 2.0 - 12.0) / 6.0
		draw_line(Vector2(x, -2.0), Vector2(x - 5.0, 4.0), INK, 4.0)
	if progress < 0.6:
		_draw_crate(Vector2(-half_width + 3.0, 5.0), 0.6)


func _draw_unit(unit: Dictionary) -> void:
	var draw_position: Vector2 = unit.get("pos", Vector2.ZERO)
	var p: Vector2 = tile_to_world(draw_position)
	var kind: String = String(unit.get("kind", "rifle"))
	var team: String = String(unit.get("team", "friendly"))
	var selected: bool = selected_ids.has(int(unit.get("id", -1)))
	var target: Vector2 = unit.get("target", draw_position)
	var id_value: int = int(unit.get("id", 0))
	var moving: bool = draw_position.distance_squared_to(target) > 0.05 and String(unit.get("state", "idle")) != "idle"
	var bob: float = sin(float(sim.time) * (13.0 if kind == "runner" else 8.0) + float(id_value)) * 1.5 if moving else 0.0
	var facing: float = -1.0 if target.x < draw_position.x - 0.05 else 1.0
	if team == "enemy" and absf(target.x - draw_position.x) < 0.05:
		facing = -1.0
	_oval(p + Vector2(2.0, 9.0), Vector2(13.0 if kind != "truck" else 29.0, 5.0 if kind != "truck" else 11.0), Color(0.18, 0.22, 0.20, 0.30))
	if selected:
		_dashed_circle(p + Vector2(0.0, 4.0), 17.0 if kind != "truck" else 33.0, Color(CYAN, 0.95), 2.5, 10)
		_oval(p + Vector2(0.0, 4.0), Vector2(15.0, 6.0), Color(CYAN, 0.13))
	draw_set_transform(p + Vector2(0.0, bob), 0.0, Vector2(facing, 1.0))
	if kind == "truck":
		_draw_truck(unit)
	elif team == "enemy":
		_draw_zombie(kind, id_value, moving)
	else:
		_draw_survivor(kind, id_value, moving, _cargo_amount(unit.get("cargo", {})) > 0.0)
	draw_set_transform(Vector2.ZERO)
	var hp: float = float(unit.get("hp", 100.0))
	var max_hp: float = maxf(1.0, float(unit.get("max_hp", 100.0)))
	if selected or hp < max_hp - 0.1:
		var width: float = 35.0 if kind == "truck" else 24.0
		var bar_y: float = -40.0 if kind == "brute" else -33.0
		_progress_bar(p + Vector2(-width * 0.5, bar_y), width, hp / max_hp, CYAN if team == "friendly" else RED, 4.0)
	if selected:
		var squad: int = int(unit.get("squad", 0))
		if squad > 0:
			_label(p + Vector2(0.0, 24.0), str(squad), Color("31595b"), 11)


func _draw_survivor(kind: String, id_value: int, moving: bool, carrying: bool) -> void:
	var stride: float = sin(float(sim.time) * 8.0 + float(id_value)) * 3.0 if moving else 0.0
	draw_line(Vector2(-5.0, 0.0), Vector2(-6.0 + stride, 8.0), INK, 5.5)
	draw_line(Vector2(5.0, 0.0), Vector2(6.0 - stride, 8.0), INK, 5.5)
	_box(Rect2(-9.0 + stride, 6.0, 8.0, 4.0), Color("354647"), 1.1)
	_box(Rect2(2.0 - stride, 6.0, 8.0, 4.0), Color("354647"), 1.1)
	var shirt: Color = Color("cf994e") if kind == "engineer" or kind == "worker" else Color("8b9a7b")
	_poly(PackedVector2Array([Vector2(-8.0, -13.0), Vector2(6.0, -13.0), Vector2(10.0, 1.0), Vector2(-9.0, 2.0)]), shirt, 1.8)
	_box(Rect2(-13.0, -12.0, 6.0, 13.0), Color("796d4f"), 1.5)
	draw_line(Vector2(-3.0, -11.0), Vector2(0.0, 0.0), Color("554e3b"), 2.0)
	draw_circle(Vector2(0.0, -19.0), 7.7, INK)
	draw_circle(Vector2(0.0, -19.0), 6.0, Color("e2ba8b"))
	var helmet: Color = ORANGE if kind == "engineer" else (Color("b5aa78") if kind == "worker" else TEAL)
	_poly(PackedVector2Array([Vector2(-8.0, -20.0), Vector2(-7.0, -26.0), Vector2(-3.0, -29.0), Vector2(5.0, -28.0), Vector2(8.0, -23.0), Vector2(9.0, -20.0)]), helmet, 1.7)
	draw_line(Vector2(-9.0, -20.0), Vector2(10.0, -20.0), INK, 2.0)
	draw_line(Vector2(-6.0, -25.0), Vector2(1.0, -27.0), Color("b7d3b1") if kind == "rifle" else Color("f5d78f"), 1.5)
	draw_circle(Vector2(4.0, -18.0), 1.3, INK)
	if kind == "rifle":
		_box(Rect2(3.0, -10.0, 22.0, 5.0), Color("425352"), 1.5)
		_box(Rect2(22.0, -10.0, 7.0, 4.0), Color("2d3739"), 1.0)
		draw_line(Vector2(3.0, -6.0), Vector2(13.0, -5.0), Color("e1b585"), 4.0)
		_box(Rect2(10.0, -6.0, 5.0, 6.0), Color("655944"), 1.0)
	elif kind == "engineer":
		draw_line(Vector2(6.0, -7.0), Vector2(13.0, -4.0), Color("e2ba8b"), 4.0)
		_draw_wrench(Vector2(17.0, -7.0), Color("c7d1bd"), 0.65)
	else:
		draw_line(Vector2(5.0, -7.0), Vector2(12.0, -2.0), Color("e2ba8b"), 4.0)
		if carrying:
			_draw_crate(Vector2(17.0, -3.0), 0.48)
		else:
			draw_line(Vector2(13.0, -8.0), Vector2(17.0, 6.0), INK, 3.0)
			_box(Rect2(9.0, -11.0, 11.0, 5.0), Color("a5aea0"), 1.0)


func _draw_zombie(kind: String, id_value: int, moving: bool) -> void:
	var brute: bool = kind == "brute"
	var scale_value: float = 1.42 if brute else 1.0
	var stride: float = sin(float(sim.time) * (13.0 if kind == "runner" else 7.0) + float(id_value)) * 4.0 if moving else 0.0
	var skin: Color = Color("90a16a") if not brute else Color("7e9365")
	var cloth: Color = Color("8d6658") if kind == "runner" else Color("737f68")
	draw_line(Vector2(-5.0 * scale_value, 0.0), Vector2(-6.0 * scale_value + stride, 9.0), INK, 5.0 * scale_value)
	draw_line(Vector2(4.0 * scale_value, 0.0), Vector2(7.0 * scale_value - stride, 8.0), INK, 5.0 * scale_value)
	_poly(PackedVector2Array([Vector2(-8.0, -15.0) * scale_value, Vector2(8.0, -14.0) * scale_value, Vector2(9.0, 3.0) * scale_value, Vector2(2.0, 0.0) * scale_value, Vector2(-1.0, 4.0) * scale_value, Vector2(-10.0, 1.0) * scale_value]), cloth, 1.8)
	draw_line(Vector2(5.0, -11.0) * scale_value, Vector2(19.0, -7.0) * scale_value, INK, 5.0)
	draw_line(Vector2(5.0, -11.0) * scale_value, Vector2(19.0, -7.0) * scale_value, skin, 3.0)
	draw_line(Vector2(-5.0, -8.0) * scale_value, Vector2(12.0, -3.0) * scale_value, INK, 4.5)
	draw_line(Vector2(-5.0, -8.0) * scale_value, Vector2(12.0, -3.0) * scale_value, skin, 2.5)
	draw_circle(Vector2(1.0, -21.0) * scale_value, 8.0 * scale_value, INK)
	draw_circle(Vector2(1.0, -21.0) * scale_value, 6.5 * scale_value, skin)
	draw_circle(Vector2(5.0, -22.0) * scale_value, 1.7, Color("d7b364"))
	draw_circle(Vector2(5.0, -22.0) * scale_value, 0.8, INK)
	draw_line(Vector2(2.0, -16.0) * scale_value, Vector2(7.0, -16.0) * scale_value, INK, 1.5)
	if brute:
		_box(Rect2(-11.0, -44.0, 24.0, 10.0), Color("69736a"), 2.0)
		_box(Rect2(-12.0, -17.0, 25.0, 12.0), Color("797f68"), 1.5)
		draw_line(Vector2(-11.0, -12.0), Vector2(12.0, -12.0), Color("b5aa7d"), 2.0)
	elif kind == "runner":
		draw_line(Vector2(-6.0, -26.0), Vector2(8.0, -25.0), RED, 3.0)
	else:
		draw_line(Vector2(-5.0, -25.0), Vector2(-3.0, -29.0), Color("555b46"), 2.0)


func _draw_truck(unit: Dictionary) -> void:
	_oval(Vector2(-17.0, 13.0), Vector2(7.0, 8.0), INK)
	_oval(Vector2(18.0, 13.0), Vector2(7.0, 8.0), INK)
	_oval(Vector2(-17.0, 13.0), Vector2(3.0, 4.0), Color("8a9489"))
	_oval(Vector2(18.0, 13.0), Vector2(3.0, 4.0), Color("8a9489"))
	_box(Rect2(-32.0, -10.0, 39.0, 25.0), Color("6f9188"), 2.3)
	_poly(PackedVector2Array([Vector2(-32.0, -10.0), Vector2(-24.0, -22.0), Vector2(8.0, -22.0), Vector2(7.0, -10.0)]), Color("a2ad92"), 1.7)
	_poly(PackedVector2Array([Vector2(7.0, -10.0), Vector2(11.0, -23.0), Vector2(26.0, -23.0), Vector2(34.0, -8.0), Vector2(34.0, 14.0), Vector2(7.0, 14.0)]), Color("d29a4d"), 2.2)
	_poly(PackedVector2Array([Vector2(13.0, -19.0), Vector2(24.0, -19.0), Vector2(29.0, -9.0), Vector2(12.0, -9.0)]), Color("79b0ab"), 1.7)
	draw_line(Vector2(15.0, -17.0), Vector2(20.0, -12.0), Color("c6e0c3"), 1.4)
	_box(Rect2(30.0, -1.0, 6.0, 7.0), Color("f4d98e"), 1.4)
	_box(Rect2(28.0, 12.0, 11.0, 4.0), Color("63736c"), 1.2)
	draw_line(Vector2(-30.0, 5.0), Vector2(4.0, 5.0), Color("405d5d"), 2.0)
	var cargo: float = _cargo_amount(unit.get("cargo", unit.get("cargo_amount", 0.0)))
	if cargo > 0.0:
		_draw_crate(Vector2(-19.0, -12.0), 0.65)
		_draw_crate(Vector2(-4.0, -14.0), 0.65)
	_box(Rect2(14.0, -31.0, 10.0, 7.0), Color("b77537"), 1.4)
	draw_circle(Vector2(19.0, -31.0), 3.4, ORANGE)


func _cargo_amount(value: Variant) -> float:
	if value is Dictionary:
		var cargo: Dictionary = value
		var total: float = 0.0
		for quantity_value: Variant in cargo.values():
			if quantity_value is int or quantity_value is float:
				total += maxf(0.0, float(quantity_value))
		return total
	if value is int or value is float:
		return maxf(0.0, float(value))
	return 0.0


func _draw_effects() -> void:
	var effects: Array = sim.effects
	for value: Variant in effects:
		var effect: Dictionary = value
		var kind: String = String(effect.get("kind", "hit"))
		var p: Vector2 = tile_to_world(effect.get("pos", Vector2.ZERO))
		var destination: Vector2 = tile_to_world(effect.get("to", effect.get("pos", Vector2.ZERO)))
		var ttl: float = float(effect.get("ttl", 0.1))
		var alpha: float = clampf(ttl * 6.0, 0.15, 1.0)
		if kind == "shot":
			p += Vector2(0.0, -9.0)
			destination += Vector2(0.0, -10.0)
			draw_line(p, destination, Color(1.0, 0.83, 0.42, alpha * 0.7), 2.3, true)
			var direction: Vector2 = (destination - p).normalized()
			var perpendicular: Vector2 = direction.orthogonal()
			_poly(PackedVector2Array([p + direction * 11.0, p + perpendicular * 4.0, p - direction * 4.0, p - perpendicular * 4.0]), Color(1.0, 0.89, 0.50, alpha), 0.0)
		elif kind == "loot":
			var lift: float = (1.0 - clampf(ttl, 0.0, 1.0)) * 25.0
			_star(p + Vector2(0.0, -18.0 - lift), 7.0, Color(1.0, 0.85, 0.38, alpha))
		else:
			var offset: Vector2 = Vector2(0.0, -13.0)
			draw_circle(p + offset, 5.0 + (1.0 - alpha) * 7.0, Color(0.93, 0.65, 0.35, alpha * 0.55))
			draw_line(p + offset + Vector2(-5.0, -5.0), p + offset + Vector2(5.0, 5.0), Color(1.0, 0.87, 0.58, alpha), 2.0)
			draw_line(p + offset + Vector2(5.0, -5.0), p + offset + Vector2(-5.0, 5.0), Color(1.0, 0.87, 0.58, alpha), 2.0)


func _draw_orders() -> void:
	var units: Array = sim.units
	var targets: Array[Vector2] = []
	for value: Variant in units:
		var unit: Dictionary = value
		if not selected_ids.has(int(unit.get("id", -1))):
			continue
		var draw_position: Vector2 = unit.get("pos", Vector2.ZERO)
		var target: Vector2 = unit.get("target", draw_position)
		if draw_position.distance_squared_to(target) < 0.2:
			continue
		var exists: bool = false
		for previous: Vector2 in targets:
			if previous.distance_squared_to(target) < 0.5:
				exists = true
				break
		if exists:
			continue
		targets.append(target)
		var p: Vector2 = tile_to_world(target)
		var radius: float = 11.0 + sin(float(sim.time) * 5.0) * 2.0
		_dashed_circle(p, radius, Color(CYAN, 0.8), 2.0, 4)
		draw_line(p + Vector2(-4.0, 0.0), p + Vector2(4.0, 0.0), CYAN, 2.0)
		draw_line(p + Vector2(0.0, -4.0), p + Vector2(0.0, 4.0), CYAN, 2.0)


func _draw_guide_target() -> void:
	if guide_target.x < 0.0 or guide_target.y < 0.0:
		return
	var point: Vector2 = guide_target * TILE_SIZE
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 320.0)
	draw_arc(point, 24.0 + pulse * 5.0, 0, TAU, 32, Color(ORANGE, 0.75), 2.0)
	draw_colored_polygon(PackedVector2Array([point+Vector2(-9,-47), point+Vector2(9,-47), point+Vector2(0,-34)]), ORANGE)
	if world_font != null:
		draw_string(world_font, point+Vector2(-14,-55), "目标", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ORANGE)

func _draw_build_preview() -> void:
	if build_kind.is_empty() or hover_tile.x < 0 or hover_tile.y < 0:
		return
	var draw_position: Vector2 = (Vector2(hover_tile) + Vector2.ONE * 0.5) * TILE_SIZE
	var valid: bool = bool(sim.is_walkable(hover_tile))
	var buildings: Array = sim.buildings
	if build_kind != "road":
		for value: Variant in buildings:
			var building: Dictionary = value
			var building_position: Vector2 = building.get("pos", Vector2.ZERO)
			if building_position.distance_to(Vector2(hover_tile) + Vector2.ONE * 0.5) < 1.3:
				valid = false
	var color: Color = CYAN if valid else RED
	var half: float = 20.0 if build_kind == "road" else 36.0
	draw_rect(Rect2(draw_position - Vector2.ONE * half, Vector2.ONE * half * 2.0), Color(color, 0.14))
	var points: Array[Vector2] = [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
	for corner: Vector2 in points:
		var x_sign: float = -signf(corner.x)
		var y_sign: float = -signf(corner.y)
		draw_line(draw_position + corner, draw_position + corner + Vector2(x_sign * 13.0, 0.0), color, 3.0)
		draw_line(draw_position + corner, draw_position + corner + Vector2(0.0, y_sign * 13.0), color, 3.0)
	draw_line(draw_position + Vector2(-8.0, 0.0), draw_position + Vector2(8.0, 0.0), color, 2.0)
	draw_line(draw_position + Vector2(0.0, -8.0), draw_position + Vector2(0.0, 8.0), color, 2.0)
	var preview_label: String = {"road": "道路", "camp": "营地", "generator": "发电机", "workshop": "工坊", "tower": "哨塔", "barracks": "军营", "barricade": "路障"}.get(build_kind, build_kind.to_upper())
	_badge(draw_position + Vector2(0.0, half + 18.0), preview_label, color, 11)


func _draw_barrel(p: Vector2, color: Color, scale_value: float = 1.0) -> void:
	var s: float = scale_value
	_box(Rect2(p + Vector2(-10.0, -15.0) * s, Vector2(20.0, 26.0) * s), color, 1.7)
	_oval(p + Vector2(0.0, -15.0) * s, Vector2(10.0, 4.0) * s, color.lightened(0.18))
	draw_line(p + Vector2(-10.0, -7.0) * s, p + Vector2(10.0, -7.0) * s, color.darkened(0.35), 2.0 * s)
	draw_line(p + Vector2(-10.0, 4.0) * s, p + Vector2(10.0, 4.0) * s, color.darkened(0.35), 2.0 * s)
	draw_circle(p + Vector2(3.0, -15.0) * s, 1.4 * s, INK)


func _draw_crate(p: Vector2, scale_value: float = 1.0) -> void:
	var s: float = scale_value
	_box(Rect2(p + Vector2(-12.0, -12.0) * s, Vector2(24.0, 23.0) * s), Color("b68e58"), 1.7)
	_poly(PackedVector2Array([p + Vector2(-12.0, -12.0) * s, p + Vector2(-5.0, -17.0) * s, p + Vector2(17.0, -17.0) * s, p + Vector2(12.0, -12.0) * s]), Color("d0ac71"), 1.2)
	_poly(PackedVector2Array([p + Vector2(12.0, -12.0) * s, p + Vector2(17.0, -17.0) * s, p + Vector2(17.0, 5.0) * s, p + Vector2(12.0, 11.0) * s]), Color("846f4f"), 1.2)
	draw_line(p + Vector2(-9.0, -8.0) * s, p + Vector2(9.0, 7.0) * s, Color("6c5e43"), 2.0 * s)
	draw_line(p + Vector2(9.0, -8.0) * s, p + Vector2(-9.0, 7.0) * s, Color("6c5e43"), 2.0 * s)


func _draw_wrench(p: Vector2, color: Color, scale_value: float = 1.0) -> void:
	var s: float = scale_value
	draw_line(p + Vector2(-6.0, 7.0) * s, p + Vector2(5.0, -4.0) * s, INK, 7.0 * s)
	draw_line(p + Vector2(-6.0, 7.0) * s, p + Vector2(5.0, -4.0) * s, color, 4.0 * s)
	draw_arc(p + Vector2(7.0, -6.0) * s, 5.5 * s, 0.05, PI * 1.48, 10, INK, 6.0 * s)
	draw_arc(p + Vector2(7.0, -6.0) * s, 5.5 * s, 0.05, PI * 1.48, 10, color, 3.0 * s)


func _draw_pickaxe(p: Vector2, color: Color) -> void:
	draw_line(p + Vector2(-8.0, 9.0), p + Vector2(7.0, -10.0), INK, 5.0)
	draw_line(p + Vector2(-8.0, 9.0), p + Vector2(7.0, -10.0), Color("a18151"), 2.7)
	draw_polyline(PackedVector2Array([p + Vector2(-3.0, -14.0), p + Vector2(8.0, -11.0), p + Vector2(15.0, -3.0)]), INK, 6.0)
	draw_polyline(PackedVector2Array([p + Vector2(-3.0, -14.0), p + Vector2(8.0, -11.0), p + Vector2(15.0, -3.0)]), color, 3.0)


func _poly(points: PackedVector2Array, color: Color, outline_width: float = 2.0) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, color)
	if outline_width > 0.0:
		var outline: PackedVector2Array = points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, INK, outline_width, true)


func _polyline_point(points: PackedVector2Array, fraction: float) -> Vector2:
	var total: float = 0.0
	for index: int in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	var remaining: float = total * clampf(fraction, 0.0, 1.0)
	for index: int in range(1, points.size()):
		var length: float = points[index - 1].distance_to(points[index])
		if remaining <= length and length > 0.001:
			return points[index - 1].lerp(points[index], remaining / length)
		remaining -= length
	return points[points.size() - 1]


func _box(rectangle: Rect2, color: Color, outline_width: float = 2.0) -> void:
	draw_rect(rectangle, color)
	if outline_width > 0.0:
		draw_rect(rectangle, INK, false, outline_width)


func _oval(center: Vector2, radii: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for step: int in range(16):
		var angle: float = TAU * float(step) / 16.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)


func _dashed_circle(center: Vector2, radius: float, color: Color, width: float, segments: int) -> void:
	for segment: int in range(segments):
		var start: float = float(segment) * TAU / float(segments)
		var end: float = start + TAU / float(segments) * 0.64
		draw_arc(center, radius, start, end, 5, color, width, true)


func _star(center: Vector2, radius: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for point: int in range(8):
		var angle: float = float(point) * TAU / 8.0 - PI * 0.5
		var distance: float = radius if point % 2 == 0 else radius * 0.35
		points.append(center + Vector2.from_angle(angle) * distance)
	draw_colored_polygon(points, color)


func _progress_bar(origin: Vector2, width: float, fraction: float, color: Color, height: float = 5.0) -> void:
	draw_rect(Rect2(origin - Vector2.ONE, Vector2(width + 2.0, height + 2.0)), INK)
	draw_rect(Rect2(origin, Vector2(width, height)), Color("48564d"))
	draw_rect(Rect2(origin, Vector2(width * clampf(fraction, 0.0, 1.0), height)), color)


func _font() -> Font:
	return world_font if world_font != null else ThemeDB.fallback_font


func _label(draw_position: Vector2, text: String, color: Color, font_size: int = 12) -> void:
	var font: Font = _font()
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, draw_position - Vector2(size.x * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _badge(draw_position: Vector2, text: String, accent: Color, font_size: int = 12) -> void:
	var font: Font = _font()
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var rectangle: Rect2 = Rect2(draw_position - Vector2(text_size.x * 0.5 + 6.0, float(font_size) + 2.0), Vector2(text_size.x + 12.0, float(font_size) + 8.0))
	draw_rect(rectangle, Color("334747"))
	draw_line(rectangle.position, rectangle.position + Vector2(0.0, rectangle.size.y), accent, 3.0)
	_label(draw_position, text, accent.lightened(0.15), font_size)
