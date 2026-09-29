extends StyleBox

const Paper = preload("res://scripts/ui/settings_control_paper.gd")
var role := "entry"
var tint := Color.WHITE

static func make(part: String, color: Color = Color.WHITE) -> StyleBox:
	var style := new()
	style.role = part
	style.tint = color
	return style

static func draw_paper(canvas: RID, rect: Rect2, part: String, color: Color = Color.WHITE) -> void:
	# 时间纸条、入口和头像统一使用设置控件原纸，保留同一边角与笔触密度。
	# 竖向纸面采用固定采样，避免把横按钮纹理拉成长条。
	if part in ["time", "portrait"]:
		var backing := Rect2(rect.position + Vector2(2, 3), rect.size - Vector2(2, 3))
		Paper.draw_paper(canvas, backing, Paper.BASE_TINT * Color(0.78, 0.78, 0.78) * color, true, 6.0)
	Paper.draw_paper(canvas, rect, Paper.BASE_TINT * color, part == "time", 6.0)

func _draw(canvas: RID, rect: Rect2) -> void:
	draw_paper(canvas, rect, role, tint)
