extends RefCounted

static func measure(label: Label, width: float, font_size: int) -> float:
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(maxf(width, 80.0), 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.size = Vector2(maxf(width, 80.0), 0)
	return ceilf(label.get_minimum_size().y) + 4.0

static func fit_paper(rect: Rect2, text_height: float, scale: float) -> Rect2:
	var height := maxf(rect.size.y, text_height + 96.0 * scale)
	return Rect2(Vector2(rect.position.x, rect.end.y - height), Vector2(rect.size.x, height))
