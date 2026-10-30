extends "res://scripts/cartoon_canvas.gd"
## Drawn once into an offscreen texture; dynamic roads, actors and effects stay live.

func _draw() -> void:
	if sim == null: return
	var size: Vector2i = sim.map_size
	draw_rect(Rect2(Vector2(-80, -80), Vector2(size) * TILE_SIZE + Vector2(160, 160)), Color("343637"))
	var bounds: Rect2i = Rect2i(Vector2i.ZERO, size)
	_draw_ground(bounds)
	_draw_cliffs(bounds)
	_draw_water_bridges()
