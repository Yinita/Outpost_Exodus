extends "res://scripts/actor_canvas.gd"
## Render this canvas once in a transparent SubViewport of ATLAS_SIZE.
## Bodies and four ground-overlay variants share the existing texture. Selection
## chooses a region live; positions, facing, bob, health and labels stay in World.

const FRAME_COUNT: int = 8
# Cells are painted at PIXEL_SCALE and shown at their logical CELL_SIZE, so
# bodies stay smooth when the camera zooms in.
const PIXEL_SCALE: int = 2
const CELL_SIZE: Vector2i = Vector2i(96, 96)
const ORIGIN: Vector2 = Vector2(48.0, 64.0)
const OVERLAY_ORIGIN: Vector2 = Vector2(48.0, 48.0)
const ROW_COUNT: int = 16
const ATLAS_SIZE: Vector2i = Vector2i(CELL_SIZE.x * FRAME_COUNT * PIXEL_SCALE, CELL_SIZE.y * ROW_COUNT * PIXEL_SCALE)
const KIND_ROWS: Dictionary = {
	"rifle": 0, "engineer": 2, "worker": 4,
	"zombie": 8, "runner": 10, "brute": 12, "truck": 14,
}


static func animation_speed(kind: String) -> float:
	if kind == "runner":
		return 13.0
	if kind == "zombie" or kind == "brute":
		return 7.0
	return 8.0


static func frame(kind: String, moving: bool, actor_time: float, id_value: int = 0) -> int:
	if not moving or kind == "truck" or not is_finite(actor_time):
		return 0
	var angle: float = fposmod(actor_time * animation_speed(kind) + float(id_value), TAU)
	# The nearest sampled pose keeps stride error below half an animation frame.
	return posmod(int(floor(angle * float(FRAME_COUNT) / TAU + 0.5)), FRAME_COUNT)


static func row(kind: String, moving: bool, carrying: bool) -> int:
	var first: int = int(KIND_ROWS.get(kind, -1))
	if first < 0:
		return -1
	if kind == "truck":
		return first + (1 if carrying else 0)
	return first + (1 if moving else 0) + (2 if kind == "worker" and carrying else 0)


static func region(kind: String, moving: bool, carrying: bool, phase: int = 0) -> Rect2:
	var row_index: int = row(kind, moving, carrying)
	if row_index < 0:
		return Rect2()
	var column: int = posmod(phase, FRAME_COUNT) if moving and kind != "truck" else 0
	return Rect2(Vector2(column * CELL_SIZE.x, row_index * CELL_SIZE.y) * PIXEL_SCALE, Vector2(CELL_SIZE * PIXEL_SCALE))


static func destination() -> Rect2:
	return Rect2(-ORIGIN, Vector2(CELL_SIZE))


static func overlay_region(kind: String, selected: bool) -> Rect2:
	# Idle rifle uses column zero only. Reuse columns 1–4 without growing the
	# texture or adding another viewport; truck rings fit around the lower origin.
	var column: int = 1 + (2 if kind == "truck" else 0) + (1 if selected else 0)
	return Rect2(Vector2(column * CELL_SIZE.x, 0.0) * PIXEL_SCALE, Vector2(CELL_SIZE * PIXEL_SCALE))


static func overlay_destination(position: Vector2) -> Rect2:
	return Rect2(position - OVERLAY_ORIGIN, Vector2(CELL_SIZE))


func _draw() -> void:
	for truck: bool in [false, true]:
		for selected: bool in [false, true]:
			var cell: Rect2 = overlay_region("truck" if truck else "rifle", selected)
			draw_set_transform(cell.position + OVERLAY_ORIGIN * PIXEL_SCALE, 0.0, Vector2.ONE * PIXEL_SCALE)
			_soft_shadow(Vector2(2.0, 9.0), Vector2(29.0, 11.0) if truck else Vector2(13.0, 5.0))
			if selected:
				# Match World's ten five-point antialiased arcs exactly at bake time.
				for segment: int in range(10):
					var start: float = float(segment) * TAU / 10.0
					draw_arc(Vector2(0.0, 4.0), 33.0 if truck else 17.0, start, start + TAU / 10.0 * 0.64, 5, Color(CYAN, 0.95), 2.5, true)
				_oval(Vector2(0.0, 4.0), Vector2(15.0, 6.0), Color(CYAN, 0.13))
	for kind_value: Variant in KIND_ROWS:
		var kind: String = str(kind_value)
		var cargo_variants: int = 2 if kind == "worker" or kind == "truck" else 1
		for cargo_index: int in range(cargo_variants):
			var carrying: bool = cargo_index > 0
			var movement_variants: int = 1 if kind == "truck" else 2
			for movement_index: int in range(movement_variants):
				var moving: bool = movement_index > 0
				var columns: int = FRAME_COUNT if moving else 1
				for column: int in range(columns):
					var cell: Rect2 = region(kind, moving, carrying, column)
					draw_set_transform(cell.position + ORIGIN * PIXEL_SCALE, 0.0, Vector2.ONE * PIXEL_SCALE)
					_actor_time = TAU * float(column) / (float(FRAME_COUNT) * animation_speed(kind))
					if kind == "truck":
						_draw_truck({"cargo_amount": 1.0 if carrying else 0.0})
					elif kind == "zombie" or kind == "runner" or kind == "brute":
						_draw_zombie(kind, 0, moving)
					else:
						_draw_survivor(kind, 0, moving, carrying)
	_actor_time = 0.0
	draw_set_transform(Vector2.ZERO)
