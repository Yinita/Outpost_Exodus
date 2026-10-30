extends SceneTree
## Reproducible native vector render. Run with a real rendering driver:
## GODOT --path . --rendering-method gl_compatibility --script tools/render_icon.gd
## On a displayless Linux host, prefix the command with xvfb-run -a.
## Writes the 512px PNG plus standard PNG-backed ICO layers. No source raster is edited.

const SOURCE := "res://assets/identity/icon.svg"
const OUTPUT := "res://assets/identity/"
const SIZES := [32, 64, 128, 256, 512]

func _initialize() -> void:
	call_deferred("_render_icons")

func _render_icons() -> void:
	var source := FileAccess.get_file_as_string(SOURCE)
	if source.is_empty():
		push_error("Cannot read original icon SVG: " + SOURCE)
		quit(1)
		return
	var svg := Image.new()
	var result := svg.load_svg_from_string(source)
	if result != OK:
		push_error("SVG render failed: " + error_string(result))
		quit(1)
		return
	var texture := ImageTexture.create_from_image(svg)
	var payloads: Array[PackedByteArray] = []
	for size: int in SIZES:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(size, size)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2.ONE * float(size) / 512.0
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		viewport.add_child(sprite)
		root.add_child(viewport)
		await process_frame
		await RenderingServer.frame_post_draw
		var rendered := viewport.get_texture().get_image()
		var path := OUTPUT + ("icon.png" if size == 512 else "icon-%d.png" % size)
		result = rendered.save_png(path)
		if result != OK:
			push_error("PNG save failed: " + error_string(result))
			quit(1)
			return
		if size <= 256:
			payloads.append(rendered.save_png_to_buffer())
		viewport.queue_free()
	if not _write_ico(payloads):
		quit(1)
		return
	print("Rendered original icon SVG to icon.png, 32/64/128/256 PNGs, and icon.ico")
	quit()

func _write_ico(payloads: Array[PackedByteArray]) -> bool:
	var file := FileAccess.open(OUTPUT + "icon.ico", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write icon.ico")
		return false
	file.store_16(0)
	file.store_16(1)
	file.store_16(payloads.size())
	var offset := 6 + payloads.size() * 16
	for index in payloads.size():
		var dimension: int = SIZES[index]
		file.store_8(0 if dimension == 256 else dimension)
		file.store_8(0 if dimension == 256 else dimension)
		file.store_8(0)
		file.store_8(0)
		file.store_16(1)
		file.store_16(32)
		file.store_32(payloads[index].size())
		file.store_32(offset)
		offset += payloads[index].size()
	for payload in payloads:
		file.store_buffer(payload)
	file.close()
	return true
