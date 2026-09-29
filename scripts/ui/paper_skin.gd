extends AspectTextureStyle

const Palette = preload("res://scripts/ui/ui_paper_palette.gd")
const ROOT := "res://assets/art/ui/rebuild_20260923/system/"
var role: StringName = &"panel"
var journal_density := false

static func field_style(active := false, inset := 14.0) -> StyleBoxFlat:
	# 内嵌字段用安静的墨底占满命中框，不缩小纸条导致文字浮出底色。
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.SELECTED_PIGMENT.x, Palette.SELECTED_PIGMENT.y, Palette.SELECTED_PIGMENT.z) if active else Color("302b29")
	style.border_color = Color("91856c") if active else Color("62574a")
	style.border_width_bottom = 1
	style.set_corner_radius_all(3)
	style.set_content_margin_all(inset)
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

static func make(kind: StringName = &"panel", inset: float = 0.0) -> AspectTextureStyle:
	var result := new()
	result.role = kind
	result.set_content_margin_all(inset)
	return result

func _draw(canvas: RID, rect: Rect2) -> void:
	if not rect.has_area():
		return
	if role == &"bar":
		RenderingServer.canvas_item_add_rect(canvas, rect, modulate_color)
		return
	var spec := _source(rect.size.x / rect.size.y)
	var paper := GameArt.texture(spec.path)
	if paper == null:
		return
	var color := Palette.tint_for(role) * modulate_color
	_draw_sheet(canvas, paper, spec.region, rect, color, str(spec.path).ends_with("sheet-v2.png"))

func _source(aspect: float) -> Dictionary:
	# 每张皮肤均来自完整绘制的纸面；不用旧版独立纸边或平铺噪纹。
	if role != &"panel":
		return {"path":ROOT+"button.png", "region":Rect2(35,97,2100,507)}
	if aspect < 0.90:
		return {"path":ROOT+"pause.png", "region":Rect2(29,28,1038,1394)}
	if aspect < 1.50:
		return {"path":ROOT+"panel.png", "region":Rect2(41,69,1238,1065)}
	return {"path":ROOT+"wide.png", "region":Rect2(25,103,1725,679)}

static func _draw_sheet(canvas: RID, paper: Texture2D, source: Rect2, target: Rect2, color: Color, _ornamented: bool) -> void:
	# 完整单张纸一次等比绘制，杜绝端部拼缝与轮廓裁切。
	ImagePlacement.draw(canvas,paper,target,&"contain",color,source)
