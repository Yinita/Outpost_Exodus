extends SceneTree
## Pure presentation caches must keep changed text, width, size, punctuation and
## fonts live, preserve the established wrapping, and use bounded storage.
const Hud = preload("res://scripts/hud.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var hud: Control = Hud.new()
	root.add_child(hud)
	var width: float = hud.font.get_string_size("甲乙", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 0.5
	var wrapped: Array[String] = hud._wrap_text("甲乙丙丁", width, 16)
	_check(wrapped == ["甲乙", "丙丁"], "two glyph columns preserve the established Chinese wrapping")
	_check(is_same(wrapped, hud._wrap_text("甲乙丙丁", width, 16)), "unchanged layout reuses its computed lines")
	_check(wrapped.is_read_only(), "callers cannot mutate shared cached lines")
	_check(hud._wrap_text("甲乙丙丁", width * 2, 16) == ["甲乙丙丁"], "changed width appears immediately")
	_check(hud._wrap_text("甲乙丙丁", width, 32) == ["甲", "乙", "丙", "丁"], "changed font size appears immediately")
	_check(hud._wrap_text("甲乙，丙丁", width, 16) == ["甲乙，", "丙丁"], "guide text keeps punctuation at the previous line's end")
	_check(hud._wrap_text("甲乙，丙丁", width, 16, false) == ["甲乙", "，丙", "丁"], "tooltip wrapping retains its separate strict width rule")
	_check(hud._wrap_text("第一行\n第二行\n", 1000, 16) == ["第一行", "第二行"], "explicit newlines preserve established line breaks")
	_check(hud._wrap_text("", 1000, 16).is_empty(), "empty text produces no visible lines")
	hud.font.emit_changed()
	_check(hud._text_layouts.is_empty(), "an in-place font change invalidates all measured wraps")
	hud._wrap_text("字体更换", 100, 16)
	var original: Font = hud.font
	hud.font = ThemeDB.fallback_font
	_check(hud._text_layouts.is_empty(), "replacing the font invalidates measured wraps")
	hud._wrap_text("current font", 1000, 16)
	original.emit_changed()
	_check(not hud._text_layouts.is_empty(), "old font no longer invalidates the current font's layouts")
	hud.font = original
	var style: StyleBoxFlat = hud._panel_style(Color("22363c"), Color("64d4c5"))
	_check(style == hud._panel_style(Color("22363c"), Color("64d4c5")), "identical colors reuse a panel style")
	_check(style != hud._panel_style(Color("22363d"), Color("64d4c5")), "changed fill color appears immediately")
	_check(style != hud._panel_style(Color("22363c"), Color("64d4c6")), "changed border color appears immediately")
	_check(style.bg_color == Color("22363c") and style.border_color == Color("64d4c5"), "style cache retains the exact original colors")
	_check(style.border_width_left == 2 and style.corner_radius_top_left == 8, "cached style retains original border geometry")
	for index: int in range(Hud.PANEL_STYLE_CACHE_LIMIT + 10):
		hud._panel_style(Color(float(index) / 100.0, 0.0, 0.0), Color.WHITE)
	_check(hud._panel_styles.size() == Hud.PANEL_STYLE_CACHE_LIMIT, "panel style cache remains bounded")
	for index: int in range(Hud.TEXT_LAYOUT_CACHE_LIMIT + 10):
		var text: String = "当前库存 %d" % index
		_check(hud._wrap_text(text, 1000, 16) == [text], "new displayed values appear immediately across eviction")
	_check(hud._text_layouts.size() == Hud.TEXT_LAYOUT_CACHE_LIMIT, "text cache remains bounded after changing values")
	_check(hud._wrap_text("甲乙丙丁", width, 16) == wrapped, "an evicted layout is reconstructed identically")
	hud.free()
	print("HUD layout cache checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures: printerr(" - ", failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
