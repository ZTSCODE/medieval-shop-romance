extends StyleBox

const Paper = preload("res://scripts/ui/legacy_forest_paper_style.gd")
const Shape = preload("res://scripts/ui/legacy_journal_shape.gd")
var kind: StringName = &"sheet"

static func make(value: StringName = &"sheet", margin: float = 0) -> StyleBox:
	var style := load("res://scripts/ui/journal_brown_style.gd").new() as StyleBox
	style.kind = value
	style.set_content_margin_all(margin)
	return style

static func material() -> ShaderMaterial:
	return Shape.material()

func _draw(canvas: RID, rect: Rect2) -> void:
	if rect.size.x < 38 or rect.size.y < 38:
		return
	var visual_kind := kind
	match kind:
		&"recipe_sheet", &"relation_sheet": visual_kind = &"sheet"
		&"recipe_title", &"relation_title", &"recipe_heading": visual_kind = &"heading"
		&"recipe_selected", &"relation_selected": visual_kind = &"selected"
		&"recipe_normal", &"relation_normal", &"relation_thumbnail": visual_kind = &"slip"
		&"relation_portrait": visual_kind = &"card"
		&"relation_detail": visual_kind = &"encounter"
		&"recipe_close", &"relation_close", &"hover": visual_kind = &"close"
	if visual_kind == &"close":
		Paper.draw_paper(canvas,rect,false,Color("ded4b8"))
		return
	var tint := Color(0.79,0.72,0.57)
	if visual_kind == &"selected":
		tint = Color(1.82,1.13,0.83)
	elif visual_kind in [&"slip", &"card", &"card_gold"]:
		tint = Color(1.32,1.44,1.21)
	elif visual_kind == &"heading":
		tint = Color(1.20,1.12,0.94)
	elif visual_kind == &"encounter":
		tint = Color(0.95,0.92,0.79)
	var sheet := Shape.new()
	if visual_kind == &"sheet":
		sheet._sheet(canvas,Rect2(rect.position+Vector2(-7,6),rect.size+Vector2(9,0)),tint.lightened(0.24))
		sheet._sheet(canvas,Rect2(rect.position+Vector2(4,-3),rect.size),tint.lightened(0.16))
	sheet._sheet(canvas,rect,tint)
