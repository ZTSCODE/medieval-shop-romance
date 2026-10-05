extends StyleBox
const PaperSkin = preload("res://scripts/ui/paper_skin.gd")
const LegacyPauseSkin = preload("res://scripts/ui/legacy_pause_skin.gd")
var tint := Color.WHITE
var use_legacy := false

static func make(margin: float = 0.0, color: Color = Color.WHITE, legacy := false) -> StyleBox:
	var result := new()
	result.tint = color
	result.use_legacy = legacy
	result.set_content_margin_all(margin)
	return result

func _draw(canvas: RID, rect: Rect2) -> void:
	var skin = LegacyPauseSkin if use_legacy else PaperSkin
	var style := skin.make(&"panel" if rect.size.y > 180 else &"heading")
	style.modulate_color = tint
	style.draw(canvas,rect)
	if rect.size.y > 180:
		var leaf := GameArt.texture("res://assets/art/ui/forest_rebuild/type-leaf.png")
		if leaf != null:
			var ink := Color(0.49,0.46,0.36,0.70) * tint
			var leaf_size := Vector2(rect.size.x * 0.052,rect.size.y * 0.080)
			ImagePlacement.draw(canvas,leaf,Rect2(rect.position+Vector2(rect.size.x*0.065,rect.size.y*0.052),leaf_size),&"contain",ink,Rect2(340,160,590,1030))
			ImagePlacement.draw(canvas,leaf,Rect2(rect.end-Vector2(rect.size.x*0.105,rect.size.y*0.11),leaf_size),&"contain",ink,Rect2(340,160,590,1030))
