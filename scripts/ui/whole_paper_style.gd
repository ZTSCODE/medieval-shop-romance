extends AspectTextureStyle

var asset: String
var region := Rect2()

static func make(path: String, source: Rect2, inset: float = 0.0) -> AspectTextureStyle:
	var result := new()
	result.asset = path
	result.region = source
	result.set_content_margin_all(inset)
	return result

func _draw(canvas: RID, rect: Rect2) -> void:
	# 一个连续源区域、一次等比绘制；禁止九区取景放大笔触或拼接外边。
	var paper := GameArt.texture(asset)
	if paper != null:
		ImagePlacement.draw(canvas,paper,rect,&"contain",modulate_color,region)
