extends RefCounted

const PAGE = preload("res://assets/art/ui/settings_20260929/selected-book-page.png")
const PAGE_REGION := Rect2(49, 12, 1484, 953)
const REFERENCE_SIZE := Vector2(1484, 953)


static func make() -> StyleBox:
	return StyleBoxEmpty.new()


static func page_rect(available: Rect2) -> Rect2:
	var factor := minf(available.size.x / REFERENCE_SIZE.x, available.size.y / REFERENCE_SIZE.y)
	var dimensions := REFERENCE_SIZE * factor
	return Rect2(available.position + Vector2((available.size.x - dimensions.x) * 0.5, 0), dimensions)


static func draw_page(canvas: RID, available: Rect2) -> void:
	var rect := page_rect(available)
	ImagePlacement.draw(canvas, PAGE, Rect2(rect.position + Vector2(0, 4), rect.size), &"contain", Color(0, 0, 0, 0.18), PAGE_REGION)
	ImagePlacement.draw(canvas, PAGE, rect, &"contain", Color.WHITE, PAGE_REGION)


static func draw_bookmark(canvas: RID, rect: Rect2, selection: float) -> void:
	var paper = preload("res://scripts/ui/settings_control_paper.gd")
	paper.draw_paper(canvas, rect, (paper.BASE_TINT * Color(0.85, 0.85, 0.85)).lerp(paper.TAB_ACTIVE, clampf(selection, 0.0, 1.0)))


