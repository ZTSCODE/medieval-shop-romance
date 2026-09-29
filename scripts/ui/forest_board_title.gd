extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(184, 48)

func _draw() -> void:
	ForestPaperStyle.draw_paper(get_canvas_item(), Rect2(Vector2.ZERO, size), true, Color(1.28,1.13,1.02))
	draw_string(GameTheme.paper_font(), Vector2(8,33), tr("FOREST_TABLE_TITLE"), HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 27, Color("e7dec7"))
