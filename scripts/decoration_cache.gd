extends "res://scripts/cartoon_canvas.gd"
## Transparent, infrequently rebuilt scenery, above live roads and below actors.
func _draw() -> void:
	if sim != null:
		_draw_decorations(Rect2i(Vector2i.ZERO, Vector2i(sim.map_size)))
