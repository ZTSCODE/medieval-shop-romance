extends StyleBox

func _init() -> void:
	set_content_margin_all(28.0)

func _draw(canvas: RID, rect: Rect2) -> void:
	preload("res://scripts/ui/journal_brown_style.gd").make().draw(canvas,rect)
