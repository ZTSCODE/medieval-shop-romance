extends StyleBox

const Paper = preload("res://scripts/ui/legacy_forest_paper_style.gd")
const BRUSH = preload("res://assets/art/ui/dialogue_20260922/plum-brush-tile.png")
var tint := Color.WHITE

static func make(margin: float = 0.0, color: Color = Color.WHITE) -> StyleBox:
	var result := new()
	result.tint = color
	result.set_content_margin_all(margin)
	return result

func _draw(canvas: RID, rect: Rect2) -> void:
	if rect.size.y > 180:
		_sheet(canvas, Rect2(rect.position + Vector2(-4, 5), rect.size), tint * Color(0.75, 0.73, 0.69))
	_sheet(canvas, rect, tint)

func _sheet(canvas: RID, rect: Rect2, color: Color) -> void:
	var edge := Paper._texture("paper-dark-edge-v2.png")
	var b := 16.0
	Paper._repeat(canvas, BRUSH, rect.grow(-b * 0.4), Rect2(Vector2.ZERO, BRUSH.get_size()), Vector2(460, 460), color * Color(0.91, 0.94, 0.78))
	var src := Rect2(48, 82, 1168, 1090)
	var s := 96.0
	for y in 3:
		for x in 3:
			if x == 1 and y == 1:
				continue
			var source_pos := src.position + Vector2(0.0 if x == 0 else (s if x == 1 else src.size.x - s), 0.0 if y == 0 else (s if y == 1 else src.size.y - s))
			var source_size := Vector2(src.size.x - 2 * s if x == 1 else s, src.size.y - 2 * s if y == 1 else s)
			var dest_pos := rect.position + Vector2(0.0 if x == 0 else (b if x == 1 else rect.size.x - b), 0.0 if y == 0 else (b if y == 1 else rect.size.y - b))
			var dest_size := Vector2(rect.size.x - 2 * b if x == 1 else b, rect.size.y - 2 * b if y == 1 else b)
			Paper._repeat(canvas, edge, Rect2(dest_pos, dest_size), Rect2(source_pos, source_size), source_size * b / s, color * Color(0.80, 0.78, 0.71))
