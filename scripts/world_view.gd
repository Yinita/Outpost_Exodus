extends "res://scripts/actor_canvas.gd"
## Original modular sprite artwork and procedural terrain for the campaign.
## All positions are continuous simulation tile coordinates, never screen pixels.

const DecorationCache = preload("res://scripts/decoration_cache.gd")
const ActorAtlas = preload("res://scripts/actor_atlas.gd")
const TerrainCache = preload("res://scripts/terrain_cache.gd")
const RenderMotion = preload("res://scripts/render_motion.gd")

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
const LABEL_CELL_SIZE: float = 64.0
const LABEL_GAP: float = 4.0
const LABEL_OFFSETS: Array[Vector2] = [Vector2.ZERO, Vector2.UP, Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT,
	Vector2(1, -1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(0, -2), Vector2(0, 2)]

var selected_ids: Array = []
var hover_tile: Vector2i = Vector2i(-1, -1)
var build_kind: String = ""
var build_preview: Dictionary = {}
var show_logistics: bool = true
var show_ranges: bool = false
var drag_selection_rect: Rect2 = Rect2()
var drag_selecting: bool = false
var world_font: Font = null
var guide_target: Vector2 = Vector2(-1, -1)
var use_building_sprites: bool = true
var building_atlas: Texture2D = null
var cache_terrain: bool = true
var cache_actors: bool = true
var cache_decorations: bool = true
var _decoration_viewport: SubViewport
var _decoration_surface: Node2D
var _decoration_signature: int = -1
var _actor_viewport: SubViewport
var _terrain_viewport: SubViewport
var _terrain_surface: Node2D
var _terrain_signature: int = -1
var motion: RefCounted = RenderMotion.new()
var _world_labels: Array[Dictionary] = []


func render_unit_position(unit: Dictionary) -> Vector2:
	return motion.position(unit)


func render_time() -> float:
	return motion.time(sim)


func _ready() -> void:
	# Keep a complete procedural fallback when the optional atlas is absent.
	if ResourceLoader.exists(BUILDING_ATLAS_PATH):
		building_atlas = load(BUILDING_ATLAS_PATH) as Texture2D
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_refresh_terrain_cache()
	_refresh_decoration_cache()
	_setup_actor_atlas()


func _process(_delta: float) -> void:
	_refresh_terrain_cache()
	_refresh_decoration_cache()


func _refresh_decoration_cache() -> void:
	if sim == null or not cache_decorations: return
	var signature: int = hash([sim.mission_id, sim.map_size, sim.terrain, sim.ramps, sim.roads.keys()])
	if _decoration_viewport != null and signature == _decoration_signature: return
	if _decoration_viewport == null:
		_decoration_viewport = SubViewport.new()
		_decoration_viewport.disable_3d = true
		_decoration_viewport.transparent_bg = true
		add_child(_decoration_viewport)
		_decoration_surface = DecorationCache.new()
		_decoration_surface.position = Vector2(80, 80)
		_decoration_viewport.add_child(_decoration_surface)
	_decoration_viewport.size = Vector2i(sim.map_size) * int(TILE_SIZE) + Vector2i(160, 160)
	_decoration_surface.sim = sim
	_decoration_surface.queue_redraw()
	_decoration_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_decoration_signature = signature


func _setup_actor_atlas() -> void:
	if not cache_actors or _actor_viewport != null: return
	_actor_viewport = SubViewport.new()
	_actor_viewport.size = ActorAtlas.ATLAS_SIZE
	_actor_viewport.disable_3d = true
	_actor_viewport.transparent_bg = true
	add_child(_actor_viewport)
	var painter: Node2D = ActorAtlas.new()
	_actor_viewport.add_child(painter)
	painter.queue_redraw()
	_actor_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _refresh_terrain_cache() -> void:
	if sim == null or not cache_terrain: return
	var signature: int = hash([sim.mission_id, sim.map_size, sim.terrain, sim.ramps])
	if _terrain_viewport != null and signature == _terrain_signature: return
	if _terrain_viewport == null:
		_terrain_viewport = SubViewport.new()
		_terrain_viewport.disable_3d = true
		_terrain_viewport.transparent_bg = false
		add_child(_terrain_viewport)
		_terrain_surface = TerrainCache.new()
		_terrain_surface.position = Vector2(80, 80)
		_terrain_viewport.add_child(_terrain_surface)
	_terrain_viewport.size = Vector2i(sim.map_size) * int(TILE_SIZE) + Vector2i(160, 160)
	_terrain_surface.sim = sim
	_terrain_surface.queue_redraw()
	_terrain_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_terrain_signature = signature


func tile_to_world(p: Vector2) -> Vector2:
	return p * TILE_SIZE


func world_to_tile(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE_SIZE), floori(p.y / TILE_SIZE))


func _draw() -> void:
	_world_labels.clear()
	if sim == null:
		return
	var size: Vector2i = sim.map_size
	var bounds: Rect2i = _visible_tiles(size)
	if cache_terrain and _terrain_viewport != null:
		draw_texture(_terrain_viewport.get_texture(), Vector2(-80, -80))
	else:
		draw_rect(Rect2(Vector2(-80.0, -80.0), Vector2(size) * TILE_SIZE + Vector2(160.0, 160.0)), Color("343637"))
		_draw_ground(bounds)
		_draw_cliffs(bounds)
		_draw_water_bridges()
	_draw_roads(bounds)
	if cache_decorations and _decoration_viewport != null:
		draw_texture(_decoration_viewport.get_texture(), Vector2(-80, -80))
	else:
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
		var draw_position: Vector2 = render_unit_position(unit)
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
	_draw_world_labels()
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
		_badge(p + Vector2(0.0, 49.0), label, tint, 12, p + Vector2(0.0, 32.0))
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
		var points: PackedVector2Array = PackedVector2Array([tile_to_world(render_unit_position(unit))])
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
		_badge(p + Vector2(0.0, -visual_size.y - 6.0), "军营", CYAN, 11, p - Vector2(0.0, visual_size.y), 1)
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
		_badge(p + Vector2(0.0, -visual_size.y - 6.0), label, CYAN if camp_state == "active" else ORANGE, 11, p - Vector2(0.0, visual_size.y), 0)


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
			if selected_ids.has(int(unit.get("id", -1))) and footprint.has_point(tile_to_world(render_unit_position(unit))):
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
	var draw_position: Vector2 = render_unit_position(unit)
	var p: Vector2 = tile_to_world(draw_position)
	var kind: String = String(unit.get("kind", "rifle"))
	var team: String = String(unit.get("team", "friendly"))
	var selected: bool = selected_ids.has(int(unit.get("id", -1)))
	var target: Vector2 = unit.get("target", draw_position)
	var id_value: int = int(unit.get("id", 0))
	var moving: bool = draw_position.distance_squared_to(target) > 0.05 and String(unit.get("state", "idle")) != "idle"
	var actor_time: float = render_time()
	var bob: float = sin(actor_time * (13.0 if kind == "runner" else 8.0) + float(id_value)) * 1.5 if moving else 0.0
	var facing: float = -1.0 if target.x < draw_position.x - 0.05 else 1.0
	if team == "enemy" and absf(target.x - draw_position.x) < 0.05:
		facing = -1.0
	_draw_actor_overlays(p, kind, selected)
	draw_set_transform(p + Vector2(0.0, bob), 0.0, Vector2(facing, 1.0))
	var carrying: bool = _cargo_amount(unit.get("cargo", unit.get("cargo_amount", 0.0))) > 0.0
	var region: Rect2 = ActorAtlas.region(kind, moving, carrying, ActorAtlas.frame(kind, moving, actor_time, id_value))
	if cache_actors and _actor_viewport != null and region.has_area():
		draw_texture_rect_region(_actor_viewport.get_texture(), ActorAtlas.destination(), region)
	else:
		_actor_time = actor_time
		if kind == "truck":
			_draw_truck(unit)
		elif team == "enemy":
			_draw_zombie(kind, id_value, moving)
		else:
			_draw_survivor(kind, id_value, moving, carrying)
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


func _draw_actor_overlays(p: Vector2, kind: String, selected: bool) -> void:
	# Ground decorations are independent of the body's facing and walking bob.
	# A live selection chooses one of four prepainted regions in the body atlas.
	if cache_actors and _actor_viewport != null:
		draw_texture_rect_region(_actor_viewport.get_texture(), ActorAtlas.overlay_destination(p), ActorAtlas.overlay_region(kind, selected))
		return
	_oval(p + Vector2(2.0, 9.0), Vector2(29.0, 11.0) if kind == "truck" else Vector2(13.0, 5.0), Color(0.18, 0.22, 0.20, 0.30))
	if selected:
		_dashed_circle(p + Vector2(0.0, 4.0), 33.0 if kind == "truck" else 17.0, Color(CYAN, 0.95), 2.5, 10)
		_oval(p + Vector2(0.0, 4.0), Vector2(15.0, 6.0), Color(CYAN, 0.13))


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
		_badge(point + Vector2(0, -55), "目标", ORANGE, 14, point + Vector2(0, -47), 1)

func _draw_build_preview() -> void:
	if build_kind.is_empty() or hover_tile.x < 0 or hover_tile.y < 0:
		return
	# Buildings use the simulation's integer anchor; roads paint tile centers.
	var draw_position: Vector2 = (Vector2(hover_tile) + (Vector2.ONE * 0.5 if build_kind == "road" else Vector2.ZERO)) * TILE_SIZE
	var valid: bool = bool(build_preview.get("ok", false))
	var color: Color = CYAN if valid else RED
	if build_kind == "road":
		for tile: Vector2i in build_preview.get("road_tiles", []):
			var center: Vector2 = (Vector2(tile) + Vector2.ONE * 0.5) * TILE_SIZE
			draw_rect(Rect2(center - Vector2(16, 13), Vector2(32, 26)), Color(color, 0.12))
			draw_rect(Rect2(center - Vector2(16, 13), Vector2(32, 26)), Color(color, 0.6), false, 1.3)
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


func _draw_pickaxe(p: Vector2, color: Color) -> void:
	draw_line(p + Vector2(-8.0, 9.0), p + Vector2(7.0, -10.0), INK, 5.0)
	draw_line(p + Vector2(-8.0, 9.0), p + Vector2(7.0, -10.0), Color("a18151"), 2.7)
	draw_polyline(PackedVector2Array([p + Vector2(-3.0, -14.0), p + Vector2(8.0, -11.0), p + Vector2(15.0, -3.0)]), INK, 6.0)
	draw_polyline(PackedVector2Array([p + Vector2(-3.0, -14.0), p + Vector2(8.0, -11.0), p + Vector2(15.0, -3.0)]), color, 3.0)


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


func _badge(draw_position: Vector2, text: String, accent: Color, font_size: int = 12, leader_origin: Vector2 = Vector2.INF, priority: int = 2) -> void:
	# Only this frame's annotations are retained. Bodies, hit tests and commands
	# continue using their original world coordinates and depth ordering.
	_world_labels.append({"position": draw_position, "text": text, "accent": accent, "font_size": maxi(12, font_size),
		"leader_origin": draw_position if leader_origin == Vector2.INF else leader_origin, "priority": priority, "order": _world_labels.size()})


func _sort_world_labels(a: Dictionary, b: Dictionary) -> bool:
	if int(a.priority) != int(b.priority): return int(a.priority) < int(b.priority)
	return int(a.order) < int(b.order)


func _draw_world_labels() -> void:
	var canvas: Transform2D = get_global_transform_with_canvas()
	var viewport: Rect2 = get_viewport_rect().grow(-4.0)
	var occupied: Dictionary = {}
	var placed: Array[Dictionary] = []
	var font: Font = _font()
	_world_labels.sort_custom(_sort_world_labels)
	# Cancel only the drawing transform so badge text keeps a readable screen
	# size at strategic zoom. This never changes the Node/camera/input transform.
	draw_set_transform_matrix(canvas.affine_inverse())
	for label: Dictionary in _world_labels:
		var preferred: Vector2 = canvas * Vector2(label.position)
		if not viewport.grow(64.0).has_point(preferred): continue
		var font_size: int = int(label.font_size)
		var text: String = str(label.text)
		var ascent: float = font.get_ascent(font_size)
		var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		var size: Vector2 = Vector2(text_size.x + 12.0, ascent + font.get_descent(font_size) + 8.0)
		var natural: Vector2 = preferred - Vector2(size.x * 0.5, ascent + 4.0)
		var rectangle: Rect2 = Rect2()
		for offset: Vector2 in LABEL_OFFSETS:
			var candidate_position: Vector2 = natural + offset * (size + Vector2.ONE * (LABEL_GAP + 2.0))
			candidate_position = candidate_position.clamp(viewport.position, viewport.end - size)
			var candidate: Rect2 = Rect2(candidate_position, size)
			if not _world_label_overlaps(candidate, occupied):
				rectangle = candidate
				break
		# The fixed local search never lets a dense group become a quadratic
		# layout pass. If no slot fits, lower-priority text yields to camp status.
		if not rectangle.has_area(): continue
		_reserve_world_label(rectangle.grow(LABEL_GAP), occupied)
		placed.append({"label": label, "rectangle": rectangle, "natural": natural, "ascent": ascent})
	# Leaders stay below every badge, including ones placed earlier, so a moved
	# guide label cannot draw a line through the packing text it avoided.
	for placement: Dictionary in placed:
		var label: Dictionary = placement.label
		var rectangle: Rect2 = placement.rectangle
		if rectangle.position.distance_squared_to(Vector2(placement.natural)) > 1.0:
			var origin: Vector2 = canvas * Vector2(label.leader_origin)
			var end: Vector2 = origin.clamp(rectangle.position, rectangle.end)
			draw_line(origin, end, Color("334747"), 3.0)
			draw_line(origin, end, label.accent, 1.0)
	for placement: Dictionary in placed:
		var label: Dictionary = placement.label
		var rectangle: Rect2 = placement.rectangle
		var accent: Color = label.accent
		draw_rect(rectangle, Color("334747"))
		draw_line(rectangle.position, rectangle.position + Vector2(0.0, rectangle.size.y), accent, 3.0)
		draw_string(font, rectangle.position + Vector2(6.0, float(placement.ascent) + 4.0), str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(label.font_size), accent.lightened(0.15))
	draw_set_transform(Vector2.ZERO)
	_world_labels.clear()


func _world_label_overlaps(rectangle: Rect2, occupied: Dictionary) -> bool:
	var first: Vector2i = Vector2i((rectangle.position / LABEL_CELL_SIZE).floor())
	var last: Vector2i = Vector2i((rectangle.end / LABEL_CELL_SIZE).floor())
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			for other: Rect2 in occupied.get(Vector2i(x, y), []):
				if rectangle.intersects(other): return true
	return false


func _reserve_world_label(rectangle: Rect2, occupied: Dictionary) -> void:
	var first: Vector2i = Vector2i((rectangle.position / LABEL_CELL_SIZE).floor())
	var last: Vector2i = Vector2i((rectangle.end / LABEL_CELL_SIZE).floor())
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not occupied.has(cell): occupied[cell] = []
			occupied[cell].append(rectangle)
