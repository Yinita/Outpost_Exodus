extends RefCounted
## Shared fonts. The bundled Noto Sans CJK collection opens on its Japanese face
## by default, which draws several Chinese characters (骨, 这, 说…) in Japanese
## forms; every caller uses the Simplified Chinese face instead.

const FONT_PATH: String = "res://assets/fonts/NotoSansCJK-Regular.ttc"
const SIMPLIFIED_CHINESE_FACE: int = 2

static var _body: Font = null
static var _heading: Font = null


static func body() -> Font:
	if _body == null: _body = _variation(0.0)
	return _body


static func heading() -> Font:
	# Synthetic weight for titles; no extra font file is shipped.
	if _heading == null: _heading = _variation(0.6)
	return _heading


static func _variation(embolden: float) -> Font:
	var file: Font = load(FONT_PATH) as Font
	if file == null: return ThemeDB.fallback_font
	var variation: FontVariation = FontVariation.new()
	variation.base_font = file
	variation.variation_face_index = SIMPLIFIED_CHINESE_FACE
	variation.variation_embolden = embolden
	return variation
