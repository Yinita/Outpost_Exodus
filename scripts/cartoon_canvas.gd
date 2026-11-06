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
# Key light from the upper left, shared by terrain props and actors.
const LIGHT: Vector2 = Vector2(-0.55, -0.83)
const OUTLINE: Color = Color("1d2224")

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


func _smooth_noise(corner: Vector2i, period: int, channel: int) -> float:
	# Bilinear value noise on a coarse lattice: continuous across tile borders.
	var cell: Vector2i = Vector2i(floori(float(corner.x) / period), floori(float(corner.y) / period))
	var f: Vector2 = Vector2(float(corner.x - cell.x * period), float(corner.y - cell.y * period)) / float(period)
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a: float = _noise(cell, channel)
	var b: float = _noise(cell + Vector2i(1, 0), channel)
	var c: float = _noise(cell + Vector2i(0, 1), channel)
	var d: float = _noise(cell + Vector2i(1, 1), channel)
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


func _corner_shade(corner: Vector2i, elevation: int) -> float:
	# Ambient occlusion at cliff bases, a faint rim light along plateau lips.
	var shade: float = 1.0
	for offset: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var other: int = _terrain_at(corner + offset)
		if other > elevation: shade = minf(shade, 0.8)
		elif other < elevation and other >= -1 and elevation >= 0: shade = maxf(shade, 1.05)
	return shade


func _draw_ground(bounds: Rect2i) -> void:
	var style: Dictionary = _visual_style()
	var sand: Color = Color(style.get("sand", "cda16a"))
	var sand_light: Color = Color(style.get("sand_light", "d7b37b"))
	var high: Color = Color(style.get("high", "e4bc7b"))
	var high_shade: Color = Color(style.get("high_shade", "d8ab6d"))
	var void_dark: Color = Color(style.get("void", "66594f"))
	var void_light: Color = Color(style.get("void_light", "756052"))
	var water_dark: Color = Color(style.get("water", "527b7e"))
	var water_light: Color = Color(style.get("water_light", "739a94"))
	_cliff_tint = Color(style.get("cliff", "9a6b4f"))
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var tile: Vector2i = Vector2i(x, y)
			var elevation: int = _terrain_at(tile)
			var origin: Vector2 = Vector2(tile) * TILE_SIZE
			var grain: float = _noise(tile)
			var water: bool = false
			if elevation < 0:
				for region: Rect2i in style.get("water_rects", []):
					if region.has_point(tile): water = true
			var quad: PackedVector2Array = PackedVector2Array()
			var colors: PackedColorArray = PackedColorArray()
			for corner_offset: Vector2i in corners:
				var corner: Vector2i = tile + corner_offset
				var broad: float = _smooth_noise(corner, 7, 21)
				var fine: float = _smooth_noise(corner, 2, 22)
				var t: float = clampf(broad * 0.7 + fine * 0.3, 0.0, 1.0)
				var color: Color
				if elevation < 0:
					color = water_dark.lerp(water_light, t * 0.8) if water else void_dark.lerp(void_light, t * 0.75)
					# Canyon floors and river banks fall into shade beside the walls.
					var walls: int = 0
					for offset: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
						if _terrain_at(corner + offset) >= 0: walls += 1
					color = color.darkened(0.12 + 0.07 * walls) if walls > 0 else color.lightened(0.04)
				else:
					color = sand.lerp(sand_light, 0.15 + t * 0.6) if elevation == 0 else high_shade.lerp(high, 0.2 + t * 0.7)
					var shade: float = _corner_shade(corner, elevation)
					color = color.darkened(1.0 - shade) if shade < 1.0 else color.lightened(shade - 1.0)
				quad.append(Vector2(corner) * TILE_SIZE)
				colors.append(color)
			draw_polygon(quad, colors)
			if elevation < 0:
				if grain < 0.17:
					draw_line(origin + Vector2(9.0, 31.0), origin + Vector2(28.0, 36.0), Color(Color("cfe4d8") if water else Color("4f4640"), 0.55), 2.0, true)
				elif not water and grain > 0.72:
					# Rubble on canyon floors.
					var at: Vector2 = origin + Vector2(10.0 + _noise(tile, 4) * 28.0, 12.0 + _noise(tile, 5) * 24.0)
					_oval(at + Vector2(1.5, 2.5), Vector2(6.0, 2.5), Color(0.1, 0.08, 0.07, 0.3))
					_body(PackedVector2Array([at + Vector2(-5.0, 1.0), at + Vector2(-2.0, -4.0), at + Vector2(4.0, -3.0), at + Vector2(5.0, 2.0)]), void_light.lightened(0.12), 0.6)
				continue
			var base: Color = colors[0]
			if grain < 0.22:
				var patch: Vector2 = origin + Vector2(7.0 + grain * 50.0, 10.0 + _noise(tile, 2) * 18.0)
				_oval(patch, Vector2(15.0, 5.0), Color(base.darkened(0.06), 0.45))
			if _noise(tile, 8) < 0.2:
				var p: Vector2 = origin + Vector2(8.0 + _noise(tile, 9) * 31.0, 9.0 + _noise(tile, 10) * 30.0)
				draw_line(p, p + Vector2(3.0, 0.0), Color(Color("a98860"), 0.7), 1.1, true)
				draw_line(p + Vector2(7.0, 3.0), p + Vector2(9.0, 3.0), Color(Color("ead0a0"), 0.8), 1.3, true)


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
				var face: PackedVector2Array = PackedVector2Array([p + Vector2(0.0, 46.0), p + Vector2(48.0, 46.0), p + Vector2(45.0, 48.0 + cliff_depth), p + Vector2(31.0, 51.0 + cliff_depth), p + Vector2(13.0, 48.0 + cliff_depth), p + Vector2(-2.0, 47.0 + cliff_depth)])
				var top_tone: Color = _cliff_tint.lightened(0.12)
				var foot_tone: Color = _cliff_tint.darkened(0.38)
				draw_polygon(face, PackedColorArray([top_tone, top_tone, foot_tone, foot_tone.darkened(0.08), foot_tone, foot_tone]))
				var rim: PackedVector2Array = face.duplicate()
				rim.append(face[0])
				draw_polyline(rim, Color(INK, 0.55), 1.2, true)
				# Rock strata and a sunlit lip give the wall some depth.
				draw_line(p + Vector2(2.0, 52.0 + cliff_depth * 0.25), p + Vector2(46.0, 51.0 + cliff_depth * 0.3), Color(_cliff_tint.lightened(0.05), 0.7), 1.4, true)
				draw_line(p + Vector2(0.0, 48.0 + cliff_depth * 0.6), p + Vector2(44.0, 49.0 + cliff_depth * 0.62), Color(_cliff_tint.darkened(0.25), 0.7), 1.4, true)
				draw_line(p + Vector2(1.0, 46.0), p + Vector2(47.0, 46.0), Color("f3cc8a"), 2.6, true)
				for seam: int in range(3):
					var sx: float = 9.0 + float(seam) * 15.0 + _noise(tile, seam + 3) * 5.0
					draw_polyline(PackedVector2Array([p + Vector2(sx, 49.0), p + Vector2(sx - 3.0, 55.0), p + Vector2(sx - 1.0, 48.0 + cliff_depth)]), Color(Color("6e4f3a"), 0.75), 1.4, true)
			if right < height and not ramps.has(tile):
				var side: PackedVector2Array = PackedVector2Array([p + Vector2(47.0, 1.0), p + Vector2(63.0, 12.0), p + Vector2(62.0, 47.0 + cliff_depth), p + Vector2(47.0, 47.0)])
				draw_polygon(side, PackedColorArray([_cliff_tint.darkened(0.08), _cliff_tint.darkened(0.3), _cliff_tint.darkened(0.45), _cliff_tint.darkened(0.25)]))
				var side_rim: PackedVector2Array = side.duplicate()
				side_rim.append(side[0])
				draw_polyline(side_rim, Color(INK, 0.5), 1.1, true)
				draw_line(p + Vector2(52.0, 17.0), p + Vector2(57.0, 45.0 + cliff_depth), Color("6f5442"), 1.4)
			if left < height and not ramps.has(tile):
				draw_line(p + Vector2(1.0, 3.0), p + Vector2(1.0, 44.0), Color("a97f53"), 2.0)


func _outline_of(color: Color) -> Color:
	return color.darkened(0.7).lerp(OUTLINE, 0.55)


func _body(points: PackedVector2Array, color: Color, outline: float = 1.2) -> void:
	# Gradient shell: vertices facing the light are brighter, the far side falls
	# into shadow. The outline is drawn first so only its outer half shows.
	if points.size() < 3: return
	var center: Vector2 = Vector2.ZERO
	for point: Vector2 in points: center += point
	center /= float(points.size())
	var reach: float = 0.001
	for point: Vector2 in points: reach = maxf(reach, absf((point - center).dot(LIGHT)))
	var lit: Color = color.lightened(0.16)
	var shade: Color = color.darkened(0.34)
	var colors: PackedColorArray = PackedColorArray()
	for point: Vector2 in points:
		colors.append(lit.lerp(shade, clampf(0.5 - 0.5 * (point - center).dot(LIGHT) / reach, 0.0, 1.0)))
	if outline > 0.0:
		var ring: PackedVector2Array = points.duplicate()
		ring.append(points[0])
		ring.append(points[1])
		draw_polyline(ring, _outline_of(color), outline * 2.0, true)
	draw_polygon(points, colors)


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


func _soft_shadow(center: Vector2, radii: Vector2, strength: float = 0.36) -> void:
	# Stacked ovals approximate a blurred contact shadow, darkest under the feet.
	for step: int in range(4):
		var shrink: float = 1.25 - float(step) * 0.2
		_oval(center, radii * shrink, Color(0.16, 0.13, 0.10, strength * 0.3))


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
	_soft_shadow(center + Vector2(2.0, 6.0) * s, Vector2(14.0, 5.0) * s, 0.32)
	_body(PackedVector2Array([center + Vector2(-13.0, 2.0) * s, center + Vector2(-8.0, -9.0) * s, center + Vector2(3.0, -13.0) * s, center + Vector2(13.0, -4.0) * s, center + Vector2(14.0, 5.0) * s, center + Vector2(-1.0, 8.0) * s]), Color("969a8e"), 1.0)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-8.0, -9.0) * s, center + Vector2(3.0, -13.0) * s, center + Vector2(5.0, -2.0) * s, center + Vector2(-2.0, 2.0) * s]), Color(Color("c9c9b4"), 0.55))


func _draw_grass(center: Vector2, variation: float) -> void:
	var color: Color = _grass_tint.lerp(_grass_highlight, variation)
	draw_line(center, center + Vector2(-5.0, -7.0), color, 1.8)
	draw_line(center, center + Vector2(-1.0, -10.0), color, 1.8)
	draw_line(center, center + Vector2(4.0, -8.0), color, 1.8)
	draw_line(center + Vector2(-4.0, 1.0), center + Vector2(6.0, 1.0), Color("b19560"), 1.3)


func _draw_dead_tree(center: Vector2, scale_value: float) -> void:
	var s: float = scale_value
	_soft_shadow(center + Vector2(4.0, 3.0) * s, Vector2(15.0, 4.5) * s, 0.28)
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
