extends AspectTextureStyle

const Palette = preload("res://scripts/ui/ui_paper_palette.gd")
const ROOT := "res://assets/art/ui/title_family_20260922/"
var role: StringName = &"panel"
var journal_density := false

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
		return {"path":"res://assets/art/ui/forest_rebuild/menu-button-paper.png", "region":Rect2(70,180,1948,380)}
	if aspect >= 0.4 and aspect < 0.85:
		return {"path":ROOT+"pause-sheet-v2.png", "region":Rect2(36,31,987,1423)}
	if aspect < 1.65:
		return {"path":ROOT+"system-blank-v3.png", "region":Rect2(26,27,1206,1199)}
	if aspect < 3.6:
		return {"path":ROOT+"journal-blank-v3.png", "region":Rect2(11,41,1730,820)}
	return {"path":ROOT+"dialogue-sheet-v2.png", "region":Rect2(55,137,2068,448)}

static func _draw_sheet(canvas: RID, paper: Texture2D, source: Rect2, target: Rect2, color: Color, ornamented: bool) -> void:
	# 近似原比例直接等比显示；变宽/增高时只延展同一纸面的中部。
	# 九个区域分别等比取景，不拉伸纹理，也不循环平铺细密笔触。
	var ratio := (target.size.x / target.size.y) / (source.size.x / source.size.y)
	if absf(ratio - 1.0) < 0.035:
		ImagePlacement.draw(canvas,paper,target,&"contain",color,source)
		return
	var unit := minf(target.size.x/source.size.x,target.size.y/source.size.y)
	# 装饰花枝完整收在四角区，不能把它横切在接缝中。
	var margin := Vector2(source.size.x*0.22,source.size.y*0.40) if ornamented else Vector2.ONE*minf(source.size.x,source.size.y)*0.16
	var edge := margin*unit
	var sx := [source.position.x,source.position.x+margin.x,source.end.x-margin.x,source.end.x]
	var sy := [source.position.y,source.position.y+margin.y,source.end.y-margin.y,source.end.y]
	var dx := [target.position.x,target.position.x+edge.x,target.end.x-edge.x,target.end.x]
	var dy := [target.position.y,target.position.y+edge.y,target.end.y-edge.y,target.end.y]
	for y in range(3):
		for x in range(3):
			var src := Rect2(Vector2(sx[x],sy[y]),Vector2(sx[x+1]-sx[x],sy[y+1]-sy[y]))
			var dst := Rect2(Vector2(dx[x],dy[y]),Vector2(dx[x+1]-dx[x],dy[y+1]-dy[y]))
			ImagePlacement.draw(canvas,paper,dst,&"cover",color,src,Vector2(float(x)*0.5,float(y)*0.5))
