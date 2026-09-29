extends StyleBox

const PAPER_TILE := "res://assets/art/ui/dialogue_20260922/plum-brush-tile.png"
const PAPER_SHAPE := "res://assets/art/ui/dialogue_20260922/plum-paper-shape.png"
const PAPER_SHADER := preload("res://scripts/ui/bottom_dialogue_paper.gdshader")

static func create() -> StyleBox:
	return load("res://scripts/ui/legacy_journal_shape.gd").new()

static func material() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = PAPER_SHADER
	result.set_shader_parameter("brush_texture", GameArt.texture(PAPER_TILE))
	return result

static func metrics(screen: Vector2) -> Rect2:
	var factor := minf(screen.y / 941.0, screen.x / 1250.0)
	var width := minf(screen.x - 64.0 * factor, maxf(screen.x * 0.60, 720.0 * factor))
	return Rect2(Vector2((screen.x - width) * 0.5, screen.y - 207.0 * factor), Vector2(width, 164.0 * factor))

func _draw(canvas_item: RID, rect: Rect2) -> void:
	_sheet(canvas_item, Rect2(rect.position + Vector2(-8, -8), rect.size + Vector2(-25, 0)), Color(0.88, 0.88, 0.88))
	_sheet(canvas_item, Rect2(rect.position + Vector2(5, -3), rect.size + Vector2(-4, 6)), Color(0.78, 0.78, 0.78))
	_sheet(canvas_item, rect, Color.WHITE)

func _sheet(canvas_item: RID, rect: Rect2, tint: Color) -> void:
	var texture := GameArt.texture(PAPER_SHAPE)
	if texture == null:
		return
	var src := Rect2(30, 32, 1196, 1192)
	var s := 128.0
	var b := 18.0
	for y in 3:
		for x in 3:
			var source_pos := src.position + Vector2(0.0 if x == 0 else (s if x == 1 else src.size.x - s), 0.0 if y == 0 else (s if y == 1 else src.size.y - s))
			var source_size := Vector2(src.size.x - 2 * s if x == 1 else s, src.size.y - 2 * s if y == 1 else s)
			var dest_pos := rect.position + Vector2(0.0 if x == 0 else (b if x == 1 else rect.size.x - b), 0.0 if y == 0 else (b if y == 1 else rect.size.y - b))
			var dest_size := Vector2(rect.size.x - 2 * b if x == 1 else b, rect.size.y - 2 * b if y == 1 else b)
			if x == 1 and y == 1:
				RenderingServer.canvas_item_add_texture_rect_region(canvas_item, Rect2(dest_pos, dest_size), texture.get_rid(), Rect2(source_pos, source_size), tint)
			else:
				LegacyForestPaperStyle._repeat(canvas_item, texture, Rect2(dest_pos, dest_size), Rect2(source_pos, source_size), source_size * b / s, tint)
