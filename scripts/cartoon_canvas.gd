extends Node2D
## Shared original cartoon drawing primitives for world and cached terrain.

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
const OVAL_SHAPE_CACHE_LIMIT: int = 128

var sim: Variant = null
var _cliff_tint: Color = CLIFF
var _grass_tint: Color = Color("8d8c54")
var _grass_highlight: Color = Color("9e8249")
var _oval_shapes: Dictionary = {}

func _visual_style() -> Dictionary:
	return sim.mission_data.get("visual", {}) if sim != null else {}

static func map_color(style: Dictionary, tile: Vector2i, elevation: int) -> Color:
	if elevation < 0:
		for rect: Rect2i in style.get("water_rects", []):
			if rect.has_point(tile): return Color(style.get("water", "527b7e"))
	return Color(style.get("map_low", "ae9567") if elevation == 0 else (style.get("map_high", "d2b47c") if elevation > 0 else style.get("map_void", "374b53")))


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
	var style: Dictionary = _visual_style()
	var sand: Color = Color(style.get("sand", "cda16a"))
	var sand_light: Color = Color(style.get("sand_light", "d7b37b"))
	var high: Color = Color(style.get("high", "e4bc7b"))
	var high_shade: Color = Color(style.get("high_shade", "d8ab6d"))
	_cliff_tint = Color(style.get("cliff", "9a6b4f"))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var tile: Vector2i = Vector2i(x, y)
			var elevation: int = _terrain_at(tile)
			var origin: Vector2 = Vector2(tile) * TILE_SIZE
			var grain: float = _noise(tile)
			if elevation < 0:
				var water: bool = false
				for region: Rect2i in style.get("water_rects", []):
					if region.has_point(tile): water = true
				var canyon_color: Color = Color(style.get("water", "527b7e")).lerp(Color(style.get("water_light", "739a94")), grain * 0.6) if water else Color(style.get("void", "66594f")).lerp(Color(style.get("void_light", "756052")), grain * 0.6)
				draw_rect(Rect2(origin, Vector2.ONE * TILE_SIZE), canyon_color)
				if grain < 0.17:
					draw_line(origin + Vector2(9.0, 31.0), origin + Vector2(28.0, 36.0), Color("94b0a2") if water else Color("554c46"), 2.0)
				continue
			var base: Color = sand.lerp(sand_light, 0.28 + grain * 0.13)
			if elevation > 0:
				base = high.lerp(high_shade, 0.25 + grain * 0.12)
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
				_poly(PackedVector2Array([p + Vector2(0.0, 46.0), p + Vector2(48.0, 46.0), p + Vector2(45.0, 48.0 + cliff_depth), p + Vector2(31.0, 51.0 + cliff_depth), p + Vector2(13.0, 48.0 + cliff_depth), p + Vector2(-2.0, 47.0 + cliff_depth)]), _cliff_tint, 1.5)
				draw_line(p + Vector2(1.0, 46.0), p + Vector2(47.0, 46.0), Color("f3cc8a"), 3.0)
				for seam: int in range(3):
					var sx: float = 9.0 + float(seam) * 15.0 + _noise(tile, seam + 3) * 5.0
					draw_polyline(PackedVector2Array([p + Vector2(sx, 49.0), p + Vector2(sx - 3.0, 55.0), p + Vector2(sx - 1.0, 48.0 + cliff_depth)]), Color("795740"), 1.5)
			if right < height and not ramps.has(tile):
				_poly(PackedVector2Array([p + Vector2(47.0, 1.0), p + Vector2(63.0, 12.0), p + Vector2(62.0, 47.0 + cliff_depth), p + Vector2(47.0, 47.0)]), Color("8a6049"), 1.2)
				draw_line(p + Vector2(52.0, 17.0), p + Vector2(57.0, 45.0 + cliff_depth), Color("6f5442"), 1.4)
			if left < height and not ramps.has(tile):
				draw_line(p + Vector2(1.0, 3.0), p + Vector2(1.0, 44.0), Color("a97f53"), 2.0)


func _poly(points: PackedVector2Array, color: Color, outline_width: float = 2.0) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, color)
	if outline_width > 0.0:
		var outline: PackedVector2Array = points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, INK, outline_width, true)


func _oval(center: Vector2, radii: Vector2, color: Color) -> void:
	# Shadows and selection ovals reuse the same radii. Translate their original
	# sixteen vertices in native code rather than recomputing trig per actor.
	if not _oval_shapes.has(radii):
		var shape: PackedVector2Array = PackedVector2Array()
		for step: int in range(16):
			var angle: float = TAU * float(step) / 16.0
			shape.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
		if _oval_shapes.size() >= OVAL_SHAPE_CACHE_LIMIT:
			_oval_shapes.erase(_oval_shapes.keys()[0])
		_oval_shapes[radii] = shape
	draw_colored_polygon(Transform2D(0.0, center) * _oval_shapes[radii], color)


func _draw_decorations(bounds: Rect2i) -> void:
	var style: Dictionary = _visual_style()
	_grass_tint = Color(style.get("grass", "8d8c54"))
	_grass_highlight = Color(style.get("grass_light", "9e8249"))
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
	var color: Color = _grass_tint.lerp(_grass_highlight, variation)
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


func _draw_barrel(p: Vector2, color: Color, scale_value: float = 1.0) -> void:
	var s: float = scale_value
	_box(Rect2(p + Vector2(-10.0, -15.0) * s, Vector2(20.0, 26.0) * s), color, 1.7)
	_oval(p + Vector2(0.0, -15.0) * s, Vector2(10.0, 4.0) * s, color.lightened(0.18))
	draw_line(p + Vector2(-10.0, -7.0) * s, p + Vector2(10.0, -7.0) * s, color.darkened(0.35), 2.0 * s)
	draw_line(p + Vector2(-10.0, 4.0) * s, p + Vector2(10.0, 4.0) * s, color.darkened(0.35), 2.0 * s)
	draw_circle(p + Vector2(3.0, -15.0) * s, 1.4 * s, INK)


func _box(rectangle: Rect2, color: Color, outline_width: float = 2.0) -> void:
	draw_rect(rectangle, color)
	if outline_width > 0.0:
		draw_rect(rectangle, INK, false, outline_width)


func _draw_water_bridges() -> void:
	for region: Rect2i in _visual_style().get("bridge_rects", []):
		var center: Vector2 = (Vector2(region.position) + Vector2(region.size) * 0.5) * TILE_SIZE
		var width: float = region.size.x * TILE_SIZE - 12.0
		var length: float = region.size.y * TILE_SIZE
		draw_set_transform(center)
		_box(Rect2(-width*0.5, -length*0.5, width, length), Color("625647"), 3.0)
		for plank: int in range(int(length / 12.0)):
			_box(Rect2(-width*0.5+5, -length*0.5+plank*12, width-10, 10), Color("c1a37c"), 1.0)
		for side: float in [-1.0,1.0]:
			var x: float = side * width * 0.5
			draw_line(Vector2(x,-length*0.5),Vector2(x,length*0.5),INK,4.0)
			for post: int in range(4):
				var y: float = -length*0.5 + post*length/3.0
				draw_line(Vector2(x-4,y-5),Vector2(x+4,y+5),Color("594f40"),5.0)
		draw_set_transform(Vector2.ZERO)
