class_name LegacyForestPaperStyle
extends StyleBox

const ART_DIR := "res://assets/art/ui/forest_rebuild/"
const TILE_LOGICAL_SIZE := 512.0
const BORDER_LOGICAL_SIZE := 16.0
const BORDER_SOURCE_SIZE := 96.0
var dark := false
var tint := Color.WHITE
static var _textures: Dictionary = {}


static func make(use_dark: bool = false, margin: float = 0.0, color: Color = Color.WHITE) -> LegacyForestPaperStyle:
	var result := LegacyForestPaperStyle.new()
	result.dark = use_dark
	result.tint = color
	result.set_content_margin_all(margin)
	return result


func _draw(canvas_item: RID, rect: Rect2) -> void:
	draw_paper(canvas_item, rect, dark, tint)


static func draw_paper(canvas_item: RID, rect: Rect2, use_dark: bool = false, color: Color = Color.WHITE) -> void:
	if not rect.has_area():
		return
	if rect.size.x > 260.0 and rect.size.y > 180.0:
		_draw_sheet(canvas_item, Rect2(rect.position + Vector2(-5.0, 6.0), rect.size + Vector2(8.0, 1.0)), use_dark, color * Color(0.73, 0.72, 0.66, 1.0))
		_draw_sheet(canvas_item, Rect2(rect.position + Vector2(4.0, -3.0), rect.size + Vector2(-2.0, 7.0)), use_dark, color * Color(0.87, 0.86, 0.79, 1.0))
	_draw_sheet(canvas_item, rect, use_dark, color)


static func _draw_sheet(canvas_item: RID, rect: Rect2, use_dark: bool, color: Color) -> void:
	var prefix := "paper-dark-" if use_dark else "paper-light-"
	var body := _texture(prefix + "tile.png")
	var border := _texture(prefix + "edge-v2.png")
	if body == null or border == null:
		return
	var b := minf(BORDER_LOGICAL_SIZE, minf(rect.size.x, rect.size.y) * 0.25)
	var inside := rect.grow(-b * 0.4)
	var body_tint := Color(0.94, 0.95, 1.02, 1.0) if use_dark else Color(0.94, 0.95, 0.93, 1.0)
	_repeat(canvas_item, body, inside, Rect2(Vector2.ZERO, body.get_size()), Vector2.ONE * TILE_LOGICAL_SIZE, color * body_tint)
	var src := Rect2(48, 82, 1168, 1090) if use_dark else Rect2(48, 62, 1170, 1134)
	var edge_tint := Color(0.78, 0.78, 0.77, 1.0) if use_dark else Color.WHITE
	var s := BORDER_SOURCE_SIZE
	var inner_source := src.size - Vector2.ONE * s * 2.0
	var scale_factor := b / s
	for y in range(3):
		for x in range(3):
			if x == 1 and y == 1:
				continue
			var source_pos := src.position + Vector2(0.0 if x == 0 else (s if x == 1 else src.size.x - s), 0.0 if y == 0 else (s if y == 1 else src.size.y - s))
			var source_size := Vector2(inner_source.x if x == 1 else s, inner_source.y if y == 1 else s)
			var dest_pos := rect.position + Vector2(0.0 if x == 0 else (b if x == 1 else rect.size.x - b), 0.0 if y == 0 else (b if y == 1 else rect.size.y - b))
			var dest_size := Vector2(rect.size.x - b * 2.0 if x == 1 else b, rect.size.y - b * 2.0 if y == 1 else b)
			_repeat(canvas_item, border, Rect2(dest_pos, dest_size), Rect2(source_pos, source_size), source_size * scale_factor, color * edge_tint)


static func _repeat(canvas_item: RID, texture: Texture2D, area: Rect2, source: Rect2, period: Vector2, color: Color) -> void:
	if not area.has_area():
		return
	var y := 0.0
	while y < area.size.y - 0.001:
		var h := minf(period.y, area.size.y - y)
		var x := 0.0
		while x < area.size.x - 0.001:
			var w := minf(period.x, area.size.x - x)
			var sample_rect := Rect2(source.position, Vector2(w, h) / period * source.size)
			RenderingServer.canvas_item_add_texture_rect_region(canvas_item, Rect2(area.position + Vector2(x, y), Vector2(w, h)), texture.get_rid(), sample_rect, color)
			x += period.x
		y += period.y


static func _texture(filename: String) -> Texture2D:
	if not _textures.has(filename):
		_textures[filename] = load(ART_DIR + filename) as Texture2D
		if filename.ends_with("edge-v2.png") and _textures[filename] != null:
			var original := _textures[filename] as Texture2D
			var pixels := original.get_image()
			var source := Rect2i(48, 82, 1168, 1090) if filename.contains("dark") else Rect2i(48, 62, 1170, 1134)
			for y in range(source.position.y, source.end.y):
				for x in range(source.position.x, source.end.x):
					var distance := mini(mini(x - source.position.x, source.end.x - 1 - x), mini(y - source.position.y, source.end.y - 1 - y))
					if distance > 42:
						var pixel := pixels.get_pixel(x, y)
						pixel.a *= 1.0 - smoothstep(42.0, 95.0, float(distance))
						pixels.set_pixel(x, y, pixel)
			_textures[filename] = ImageTexture.create_from_image(pixels)
	return _textures[filename] as Texture2D
