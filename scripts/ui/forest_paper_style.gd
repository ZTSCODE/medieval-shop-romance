class_name ForestPaperStyle
extends StyleBox

const ART_DIR := "res://assets/art/ui/forest_rebuild/"
const TILE_LOGICAL_SIZE := 460.0
const BORDER_LOGICAL_SIZE := 16.0
const BORDER_SOURCE_SIZE := 96.0
var dark := false
var tint := Color.WHITE
static var _textures: Dictionary = {}


static func make(use_dark: bool = false, margin: float = 0.0, color: Color = Color.WHITE) -> ForestPaperStyle:
	var result := ForestPaperStyle.new()
	result.dark = use_dark
	result.tint = color
	result.set_content_margin_all(margin)
	return result


func _draw(canvas_item: RID, rect: Rect2) -> void:
	draw_paper(canvas_item, rect, dark, tint)


static func draw_paper(canvas_item: RID, rect: Rect2, use_dark: bool = false, color: Color = Color.WHITE) -> void:
	var style := preload("res://scripts/ui/paper_skin.gd").make(&"panel" if use_dark else &"slip")
	style.modulate_color = color
	style.draw(canvas_item,rect)


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
