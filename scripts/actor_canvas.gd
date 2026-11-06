extends "res://scripts/cartoon_canvas.gd"
## Original actor body artwork, shared by the live vector fallback and atlas.
## The caller supplies time explicitly; drawing never changes simulation state.
## Facing, world bob, shadows, health bars and selection remain with WorldView.
## Bodies are built from lit volumes (spheres, capsules and gradient shells, light
## from the upper left) so the cast reads as rounded toy figures, not cut-outs.

var _actor_time: float = 0.0
# Zombie posture: forward shear and uniform scale applied by _z().
var _lean: float = 0.0
var _zscale: float = 1.0


func _segment(a: Vector2, b: Vector2, radius: float, color: Color) -> void:
	draw_line(a, b, color, radius * 2.0, true)
	draw_circle(a, radius, color, true, -1.0, true)
	draw_circle(b, radius, color, true, -1.0, true)


func _ball(center: Vector2, radius: float, color: Color, outline: float = 1.2) -> void:
	# Core shadow, lit body, soft highlight and a small specular glint.
	if outline > 0.0: draw_circle(center, radius + outline, _outline_of(color), true, -1.0, true)
	draw_circle(center, radius, color.darkened(0.3), true, -1.0, true)
	draw_circle(center + LIGHT * radius * 0.2, radius * 0.8, color, true, -1.0, true)
	draw_circle(center + LIGHT * radius * 0.42, radius * 0.36, color.lightened(0.2), true, -1.0, true)
	draw_circle(center + LIGHT * radius * 0.56, radius * 0.13, Color(1.0, 1.0, 0.92, 0.5), true, -1.0, true)


func _limb(a: Vector2, b: Vector2, radius: float, color: Color, outline: float = 1.1) -> void:
	# A rounded capsule with its lit side facing the key light.
	var direction: Vector2 = (b - a).normalized() if a.distance_squared_to(b) > 0.0001 else Vector2.RIGHT
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	if normal.dot(LIGHT) < 0.0: normal = -normal
	if outline > 0.0: _segment(a, b, radius + outline, _outline_of(color))
	_segment(a, b, radius, color.darkened(0.3))
	_segment(a + normal * radius * 0.22, b + normal * radius * 0.22, radius * 0.72, color)
	_segment(a + normal * radius * 0.5, b + normal * radius * 0.5, radius * 0.2, color.lightened(0.18))


func _rounded(rect: Rect2, radius: float, steps: int = 3) -> PackedVector2Array:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var points: PackedVector2Array = PackedVector2Array()
	var corners: Array[Vector2] = [rect.end - Vector2(r, r), Vector2(rect.position.x + r, rect.end.y - r), rect.position + Vector2(r, r), Vector2(rect.end.x - r, rect.position.y + r)]
	for corner: int in range(4):
		for step: int in range(steps + 1):
			var angle: float = (float(corner) + float(step) / float(steps)) * PI * 0.5
			points.append(corners[corner] + Vector2(cos(angle), sin(angle)) * r)
	return points


func _dome(center: Vector2, radius: Vector2, steps: int = 10) -> PackedVector2Array:
	# Upper half-ellipse, used for helmets, caps and hunched backs.
	var points: PackedVector2Array = PackedVector2Array()
	for step: int in range(steps + 1):
		var angle: float = PI + PI * float(step) / float(steps)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points


func _boot(at: Vector2, color: Color) -> void:
	_body(_rounded(Rect2(at + Vector2(-3.2, -2.6), Vector2(8.0, 5.0)), 2.4), color, 1.0)


func _eye(at: Vector2, glow: Color = Color("2a2522")) -> void:
	draw_circle(at, 1.45, glow, true, -1.0, true)
	draw_circle(at + Vector2(-0.45, -0.5), 0.5, Color(1.0, 1.0, 1.0, 0.85), true, -1.0, true)


func _draw_survivor(kind: String, id_value: int, moving: bool, carrying: bool) -> void:
	var phase: float = _actor_time * 8.0 + float(id_value)
	var stride: float = sin(phase) * 3.4 if moving else 0.0
	var lift_front: float = maxf(0.0, -cos(phase)) * 1.8 if moving else 0.0
	var lift_back: float = maxf(0.0, cos(phase)) * 1.8 if moving else 0.0
	var skin: Color = Color("eac196")
	var boot: Color = Color("4b3b2f")
	var pants: Color = {"rifle": Color("4f5f50"), "engineer": Color("4d5566"), "worker": Color("5d6170")}.get(kind, Color("4f5f50"))
	var shirt: Color = {"rifle": Color("819a68"), "engineer": Color("dc9744"), "worker": Color("c2a77a")}.get(kind, Color("819a68"))
	# Pack or satchel behind the back.
	if kind == "rifle":
		_body(_rounded(Rect2(-13.5, -20.0, 8.0, 13.0), 3.0), Color("6d6a4c"))
		draw_line(Vector2(-12.0, -15.0), Vector2(-6.5, -15.0), Color("4d4a36"), 1.4, true)
	elif kind == "engineer":
		_body(_rounded(Rect2(-14.0, -19.0, 8.5, 12.0), 2.0), Color("b4483a"))
		_box(Rect2(-12.5, -16.0, 5.5, 2.0), Color("e3c9a0"), 0.0)
	# Far leg first, slightly darker.
	_limb(Vector2(-2.6, -3.0), Vector2(-3.4 - stride, 5.0 - lift_back), 2.9, pants.darkened(0.14))
	_boot(Vector2(-3.4 - stride, 6.6 - lift_back), boot.darkened(0.12))
	_limb(Vector2(2.6, -3.0), Vector2(3.4 + stride, 5.0 - lift_front), 2.9, pants)
	_boot(Vector2(3.4 + stride, 6.6 - lift_front), boot)
	# Far arm sits behind the torso.
	var far_hand: Vector2 = Vector2(15.0, -11.5) if kind == "rifle" else (Vector2(11.0, -9.0) if carrying else Vector2(-6.0 + stride * 0.8, -6.0))
	_limb(Vector2(-2.5, -15.0), far_hand, 2.5, shirt.darkened(0.16))
	_ball(far_hand, 2.2, skin.darkened(0.1), 0.9)
	# Torso shell with belt and role details.
	_body(_rounded(Rect2(-8.5, -20.5, 17.0, 19.5), 6.0), shirt, 1.3)
	if kind == "rifle":
		_body(_rounded(Rect2(-6.5, -17.5, 13.0, 11.0), 3.0), Color("5e6e4b"), 0.8)
		for x: float in [-4.0, 1.0]:
			_body(_rounded(Rect2(x, -11.5, 4.2, 4.2), 1.2), Color("71815a"), 0.6)
	elif kind == "engineer":
		draw_line(Vector2(-6.0, -18.0), Vector2(-6.0, -4.0), Color("f2d25c"), 1.6, true)
		draw_line(Vector2(5.5, -18.0), Vector2(5.5, -4.0), Color("f2d25c"), 1.6, true)
	else:
		draw_line(Vector2(-6.0, -19.0), Vector2(6.0, -6.0), Color("7b5d3c"), 2.0, true)
	draw_line(Vector2(-8.0, -4.0), Vector2(8.0, -4.0), Color("3d3329"), 2.6, true)
	_box(Rect2(-1.6, -5.4, 3.2, 2.8), Color("d6b25c"), 0.0)
	# Head: big lit sphere with ear, eye and cheek.
	var head: Vector2 = Vector2(1.5, -27.0)
	_ball(head + Vector2(-5.2, 1.0), 2.2, skin.darkened(0.08), 0.9)
	_ball(head, 8.2, skin, 1.3)
	draw_circle(head + Vector2(5.0, 2.6), 2.0, Color(0.92, 0.45, 0.38, 0.28), true, -1.0, true)
	draw_circle(head + Vector2(4.6, 0.9), 2.3, Color("fbf6ea"), true, -1.0, true)
	_eye(head + Vector2(5.3, 1.1))
	_ball(head + Vector2(7.6, 1.6), 1.5, skin.darkened(0.05), 0.0)
	draw_line(head + Vector2(4.0, 5.0), head + Vector2(6.2, 4.6), Color("7a4a3a"), 1.0, true)
	if kind == "rifle":
		_body(_dome(head + Vector2(-0.5, -2.4), Vector2(9.6, 8.0)), Color("4f8f88"), 1.2)
		_limb(head + Vector2(-9.0, -2.3), head + Vector2(10.5, -2.3), 1.2, Color("3f7670"), 0.9)
		draw_line(head + Vector2(-7.0, -5.6), head + Vector2(0.0, -8.4), Color(1.0, 1.0, 1.0, 0.35), 1.6, true)
	elif kind == "engineer":
		_body(_dome(head + Vector2(-0.3, -2.6), Vector2(9.4, 8.2)), Color("f39c32"), 1.2)
		draw_line(head + Vector2(-0.3, -10.4), head + Vector2(-0.3, -3.0), Color("ffc46a"), 1.6, true)
		_limb(head + Vector2(-10.5, -2.4), head + Vector2(11.5, -2.4), 1.4, Color("de8526"), 0.9)
	else:
		_body(_dome(head + Vector2(-0.6, -2.4), Vector2(8.9, 7.0)), Color("8f7c5b"), 1.1)
		_body(PackedVector2Array([head + Vector2(5.0, -3.4), head + Vector2(13.0, -2.4), head + Vector2(12.0, -0.8), head + Vector2(4.0, -1.2)]), Color("7c6a4c"), 0.9)
	# Held item and near arm.
	if kind == "rifle":
		_body(PackedVector2Array([Vector2(-2.0, -15.5), Vector2(6.0, -13.5), Vector2(6.0, -9.5), Vector2(-1.5, -9.0)]), Color("8a5f3c"), 1.0)
		_body(PackedVector2Array([Vector2(5.0, -14.0), Vector2(25.0, -14.0), Vector2(25.0, -11.0), Vector2(13.0, -10.5), Vector2(11.5, -6.5), Vector2(8.5, -7.0), Vector2(7.5, -10.0), Vector2(5.0, -10.0)]), Color("465253"), 1.0)
		_limb(Vector2(24.0, -12.6), Vector2(30.0, -12.6), 0.9, Color("343c3e"), 0.7)
		_body(_rounded(Rect2(9.0, -17.2, 7.0, 3.2), 1.4), Color("2f3739"), 0.7)
		_limb(Vector2(2.5, -15.0), Vector2(8.5, -9.5), 2.6, shirt)
		_ball(Vector2(8.8, -9.8), 2.3, skin, 0.9)
	elif kind == "engineer":
		_limb(Vector2(2.5, -15.0), Vector2(11.0, -9.0), 2.6, shirt)
		_draw_wrench(Vector2(15.0, -12.0), Color("c9d3c2"), 0.7)
		_ball(Vector2(11.0, -9.0), 2.3, skin, 0.9)
	else:
		if carrying:
			_draw_crate(Vector2(14.0, -8.0), 0.5)
			_limb(Vector2(2.5, -15.0), Vector2(10.0, -10.0), 2.6, shirt)
			_ball(Vector2(10.0, -10.0), 2.3, skin, 0.9)
		else:
			_limb(Vector2(14.0, -20.0), Vector2(18.0, 3.0), 1.1, Color("7b5a3a"), 0.8)
			_limb(Vector2(8.0, -19.0), Vector2(14.0, -21.8), 1.3, Color("a7b0a3"), 0.8)
			_limb(Vector2(14.0, -21.8), Vector2(21.0, -18.0), 1.3, Color("a7b0a3"), 0.8)
			_limb(Vector2(2.5, -15.0), Vector2(13.5, -12.0), 2.6, shirt)
			_ball(Vector2(14.0, -12.0), 2.3, skin, 0.9)


func _z(point: Vector2) -> Vector2:
	return Vector2(point.x - point.y * _lean, point.y) * _zscale


func _zpoints(points: Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points: result.append(_z(point))
	return result


func _draw_zombie(kind: String, id_value: int, moving: bool) -> void:
	var brute: bool = kind == "brute"
	var runner: bool = kind == "runner"
	_zscale = 1.4 if brute else (0.96 if runner else 1.0)
	_lean = 0.3 if runner else (0.12 if brute else 0.18)
	var phase: float = _actor_time * (13.0 if runner else 7.0) + float(id_value)
	var stride: float = sin(phase) * (4.2 if runner else 3.0) if moving else 0.0
	var reach: float = sin(phase * 0.5 + 1.0) * 1.6 if moving else 0.0
	var skin: Color = Color("a7ad7c") if runner else (Color("7f9566") if brute else Color("93a86d"))
	var cloth: Color = Color("8e5a4a") if runner else (Color("5f5d55") if brute else Color("6f7d66"))
	var pants: Color = Color("4b4e5a")
	# Legs: one stiff, one dragging.
	_limb(_z(Vector2(-2.5, -3.0)), _z(Vector2(-4.0 - stride, 5.5)), 2.8 * _zscale * (1.15 if brute else 1.0), pants.darkened(0.15))
	_boot(_z(Vector2(-4.0 - stride, 7.0)), Color("3e3a35"))
	_limb(_z(Vector2(2.5, -3.0)), _z(Vector2(4.0 + stride, 5.5)), 2.8 * _zscale * (1.15 if brute else 1.0), pants)
	_boot(_z(Vector2(4.0 + stride, 7.0)), Color("46413b"))
	# Far arm reaches forward behind the body.
	var arm_r: float = 3.6 if brute else 2.4
	_limb(_z(Vector2(-1.0, -15.0)), _z(Vector2(17.0, -14.0 - reach)), arm_r * _zscale, skin.darkened(0.18))
	_ball(_z(Vector2(17.5, -14.0 - reach)), 2.3 * _zscale, skin.darkened(0.18), 0.9)
	# Hunched torso with a torn hem.
	if brute:
		_body(_zpoints([Vector2(-10.0, -20.0), Vector2(-4.0, -24.0), Vector2(7.0, -23.0), Vector2(12.0, -14.0), Vector2(11.0, -2.0), Vector2(-9.0, -1.0), Vector2(-12.0, -10.0)]), cloth, 1.3)
		_body(_zpoints([Vector2(-6.0, -21.0), Vector2(6.0, -21.0), Vector2(8.0, -13.0), Vector2(-7.0, -12.5)]), Color("7f8580"), 1.0)
		for rivet: Vector2 in [Vector2(-4.0, -19.0), Vector2(4.0, -19.0), Vector2(-5.0, -14.5), Vector2(5.5, -14.5)]:
			draw_circle(_z(rivet), 0.9 * _zscale, Color("c8c9b8"), true, -1.0, true)
		_body(_zpoints([Vector2(-8.0, -11.0), Vector2(9.0, -11.0), Vector2(10.0, -3.0), Vector2(-8.0, -2.5)]), skin, 1.0)
		draw_arc(_z(Vector2(1.0, -6.5)), 3.0 * _zscale, 0.2, PI - 0.2, 8, skin.darkened(0.3), 1.2, true)
	else:
		_body(_zpoints([Vector2(-8.0, -18.0), Vector2(-2.0, -21.0), Vector2(6.0, -20.0), Vector2(9.0, -10.0), Vector2(9.0, 0.0), Vector2(5.5, -2.0), Vector2(3.0, 1.5), Vector2(-1.0, -1.5), Vector2(-4.5, 1.0), Vector2(-9.0, -1.0)]), cloth, 1.3)
		draw_line(_z(Vector2(-6.0, -15.0)), _z(Vector2(-1.0, -9.0)), cloth.darkened(0.35), 1.2, true)
		_ball(_z(Vector2(3.0, -9.0)), 1.6, Color(0.55, 0.16, 0.14, 0.75), 0.0)
	# Head pushed forward, sunken eyes with a yellow glint, slack jaw.
	var head: Vector2 = _z(Vector2(5.5, -26.0) if not brute else Vector2(7.0, -25.0))
	var head_r: float = (6.8 if brute else 7.6) * _zscale
	_ball(head, head_r, skin, 1.3)
	var s: float = _zscale
	draw_circle(head + Vector2(3.6, -1.0) * s, 2.3 * s, Color(0.2, 0.22, 0.16, 0.75), true, -1.0, true)
	draw_circle(head + Vector2(3.9, -1.0) * s, 1.1 * s, Color("f2d35a"), true, -1.0, true)
	draw_circle(head + Vector2(-0.8, -1.4) * s, 1.8 * s, Color(0.2, 0.22, 0.16, 0.6), true, -1.0, true)
	_body(PackedVector2Array([head + Vector2(1.5, 3.0) * s, head + Vector2(6.8, 2.4) * s, head + Vector2(6.0, 5.6) * s, head + Vector2(2.4, 5.8) * s]), Color("3b2424"), 0.7)
	for tooth: float in [3.0, 4.6]:
		draw_line(head + Vector2(tooth, 2.8) * s, head + Vector2(tooth, 3.9) * s, Color("e8dfc0"), 0.9, true)
	if runner:
		_body(_dome(head + Vector2(-0.4, -1.0) * s, Vector2(8.0, 6.0) * s, 8), Color("c94a3c"), 1.0)
		var flutter: float = sin(phase * 1.3) * 1.5
		_body(PackedVector2Array([head + Vector2(-7.0, -2.0) * s, head + Vector2(-13.0, -1.0 + flutter) * s, head + Vector2(-12.0, 2.5 + flutter) * s]), Color("b13e33"), 0.8)
	elif brute:
		_body(_dome(head + Vector2(0.0, -1.0) * s, Vector2(7.6, 5.4) * s, 8), Color("6d756b"), 1.0)
	else:
		draw_line(head + Vector2(-4.0, -6.0), head + Vector2(-1.0, -9.0), Color("4c4f3c"), 1.4, true)
		draw_line(head + Vector2(0.0, -7.2), head + Vector2(2.5, -9.0), Color("4c4f3c"), 1.4, true)
		_ball(head + Vector2(-3.5, 2.0), 1.4, Color(0.55, 0.18, 0.15, 0.7), 0.0)
	# Near arm reaching out, with clawed fingers.
	var shoulder: Vector2 = _z(Vector2(2.0, -15.5))
	var hand: Vector2 = _z(Vector2(19.0, -10.5 + reach))
	_limb(shoulder, hand, arm_r * _zscale, skin)
	_ball(hand, 2.5 * _zscale, skin, 0.9)
	for finger: float in [-1.6, 0.0, 1.6]:
		draw_line(hand + Vector2(1.5, finger) * _zscale, hand + Vector2(4.2, finger * 1.4 + 0.6) * _zscale, skin.darkened(0.45), 1.1, true)
	_lean = 0.0
	_zscale = 1.0


func _draw_truck(unit: Dictionary) -> void:
	# Far wheels peek out below the chassis; near wheels are full spheres.
	for x: float in [-15.0, 20.0]:
		_ball(Vector2(x - 3.0, 9.0), 6.0, Color("272b2d"), 1.0)
	_body(_rounded(Rect2(-34.0, 4.0, 72.0, 7.0), 2.5), Color("39403f"), 1.0)
	# Cargo bed: side panel, top lip and a canvas cover.
	_body(_rounded(Rect2(-34.0, -11.0, 42.0, 21.0), 3.0), Color("6f9188"), 1.4)
	_body(PackedVector2Array([Vector2(-34.0, -11.0), Vector2(-28.0, -17.0), Vector2(11.0, -17.0), Vector2(8.0, -11.0)]), Color("8fb0a5"), 1.1)
	for x: float in [-24.0, -12.0, 0.0]:
		draw_line(Vector2(x, -9.0), Vector2(x, 8.0), Color("587970"), 1.4, true)
	var cargo: float = _cargo_amount(unit.get("cargo", unit.get("cargo_amount", 0.0)))
	if cargo > 0.0:
		_draw_crate(Vector2(-21.0, -15.0), 0.62)
		_draw_crate(Vector2(-6.0, -17.0), 0.62)
	else:
		_body(_rounded(Rect2(-31.0, -21.0, 37.0, 8.0), 4.0), Color("a5ad8e"), 1.0)
		for x: float in [-20.0, -7.0]:
			draw_line(Vector2(x, -20.0), Vector2(x + 1.0, -14.0), Color("7e8669"), 1.2, true)
	# Cab with roof, windshield glare, lamp and bumper.
	_body(PackedVector2Array([Vector2(7.0, 10.0), Vector2(7.0, -12.0), Vector2(11.0, -24.0), Vector2(27.0, -24.0), Vector2(35.0, -9.0), Vector2(37.0, 10.0)]), Color("e09b48"), 1.4)
	_body(PackedVector2Array([Vector2(11.0, -24.0), Vector2(15.0, -27.0), Vector2(29.0, -27.0), Vector2(27.0, -24.0)]), Color("f0b464"), 1.0)
	var glass: PackedVector2Array = PackedVector2Array([Vector2(13.5, -20.5), Vector2(25.0, -20.5), Vector2(30.5, -10.0), Vector2(12.0, -10.0)])
	draw_polygon(glass, PackedColorArray([Color("b7e0da"), Color("8cc4c0"), Color("4f8f8f"), Color("6aa7a5")]))
	var frame: PackedVector2Array = glass.duplicate()
	frame.append(glass[0])
	draw_polyline(frame, Color("2d3a3a"), 1.4, true)
	draw_line(Vector2(16.0, -19.0), Vector2(21.0, -12.0), Color(1.0, 1.0, 1.0, 0.55), 1.6, true)
	draw_line(Vector2(20.0, -19.5), Vector2(23.0, -15.0), Color(1.0, 1.0, 1.0, 0.35), 1.0, true)
	draw_line(Vector2(9.0, -6.0), Vector2(9.0, 6.0), Color("b8772f"), 1.2, true)
	draw_circle(Vector2(34.5, -2.0), 6.0, Color(1.0, 0.86, 0.5, 0.18), true, -1.0, true)
	_ball(Vector2(34.0, -2.0), 2.6, Color("ffe39a"), 0.9)
	_body(_rounded(Rect2(29.0, 9.0, 11.0, 4.0), 1.5), Color("6f7b75"), 0.9)
	# Beacon on the roof.
	draw_circle(Vector2(21.0, -31.0), 6.5, Color(1.0, 0.62, 0.2, 0.18), true, -1.0, true)
	_body(_rounded(Rect2(17.0, -29.5, 8.0, 3.0), 1.0), Color("6a5644"), 0.8)
	_ball(Vector2(21.0, -31.0), 2.8, ORANGE, 0.9)
	# Near wheels last so they overlap the body like real tyres.
	for x: float in [-15.0, 22.0]:
		_ball(Vector2(x, 11.0), 6.8, Color("2c3133"), 1.1)
		_ball(Vector2(x, 11.0), 3.0, Color("a7b0a6"), 0.6)
		draw_circle(Vector2(x, 11.0), 0.9, Color("4b5250"), true, -1.0, true)


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
	_body(PackedVector2Array([p + Vector2(-12.0, -12.0) * s, p + Vector2(12.0, -12.0) * s, p + Vector2(12.0, 11.0) * s, p + Vector2(-12.0, 11.0) * s]), Color("bf955d"), 1.2)
	_body(PackedVector2Array([p + Vector2(-12.0, -12.0) * s, p + Vector2(-5.0, -17.0) * s, p + Vector2(17.0, -17.0) * s, p + Vector2(12.0, -12.0) * s]), Color("dcb87c"), 1.0)
	_body(PackedVector2Array([p + Vector2(12.0, -12.0) * s, p + Vector2(17.0, -17.0) * s, p + Vector2(17.0, 5.0) * s, p + Vector2(12.0, 11.0) * s]), Color("8a7150"), 1.0)
	draw_line(p + Vector2(-9.0, -8.0) * s, p + Vector2(9.0, 7.0) * s, Color("75613f"), 2.0 * s, true)
	draw_line(p + Vector2(9.0, -8.0) * s, p + Vector2(-9.0, 7.0) * s, Color("75613f"), 2.0 * s, true)


func _draw_wrench(p: Vector2, color: Color, scale_value: float = 1.0) -> void:
	var s: float = scale_value
	_limb(p + Vector2(-6.0, 7.0) * s, p + Vector2(5.0, -4.0) * s, 2.0 * s, color, 0.9)
	draw_arc(p + Vector2(7.0, -6.0) * s, 5.5 * s, 0.05, PI * 1.48, 12, _outline_of(color), 6.0 * s, true)
	draw_arc(p + Vector2(7.0, -6.0) * s, 5.5 * s, 0.05, PI * 1.48, 12, color, 3.4 * s, true)
	draw_arc(p + Vector2(6.6, -6.4) * s, 5.5 * s, PI * 0.9, PI * 1.4, 6, color.lightened(0.3), 1.2 * s, true)
