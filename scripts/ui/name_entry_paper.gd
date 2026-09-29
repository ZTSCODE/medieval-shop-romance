extends StyleBox

const BookPaper = preload("res://scripts/ui/settings_book_paper.gd")

func _init() -> void:
	content_margin_left = 64
	content_margin_right = 64
	content_margin_top = 45
	content_margin_bottom = 38

func _draw(canvas: RID, rect: Rect2) -> void:
	BookPaper.draw_page(canvas, rect)
