extends "res://scripts/cartoon_canvas.gd"
## Original actor body artwork, shared by the live vector fallback and atlas.
## The caller supplies time explicitly; drawing never changes simulation state.
## Facing, world bob, shadows, health bars and selection remain with WorldView.

var _actor_time: float = 0.0


func _draw_survivor(kind: String, id_value: int, moving: bool, carrying: bool) -> void:
	var stride: float = sin(_actor_time * 8.0 + float(id_value)) * 3.0 if moving else 0.0
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
	var stride: float = sin(_actor_time * (13.0 if kind == "runner" else 7.0) + float(id_value)) * 4.0 if moving else 0.0
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


