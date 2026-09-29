extends RefCounted

static func draw(canvas: RID, rect: Rect2, width: float = 10.0, tint: Color = Color.WHITE) -> void:
	var texture := GameArt.texture("res://assets/art/ui/unified_paper_20260922/brush-edge.png")
	if texture == null or not rect.has_area():
		return
	var source := Rect2(36,40,1184,1176)
	var cut := 64.0
	var edge := minf(width, minf(rect.size.x,rect.size.y)*0.2)
	for y in 3:
		for x in 3:
			if x == 1 and y == 1:
				continue
			var src_at := source.position + Vector2(0 if x == 0 else (cut if x == 1 else source.size.x-cut),0 if y == 0 else (cut if y == 1 else source.size.y-cut))
			var src_size := Vector2(source.size.x-2*cut if x == 1 else cut,source.size.y-2*cut if y == 1 else cut)
			var at := rect.position + Vector2(0 if x == 0 else (edge if x == 1 else rect.size.x-edge),0 if y == 0 else (edge if y == 1 else rect.size.y-edge))
			var dimensions := Vector2(rect.size.x-2*edge if x == 1 else edge,rect.size.y-2*edge if y == 1 else edge)
			_repeat(canvas,texture,Rect2(at,dimensions),Rect2(src_at,src_size),src_size*edge/cut,tint)

static func _repeat(canvas: RID, texture: Texture2D, area: Rect2, source: Rect2, period: Vector2, color: Color) -> void:
	if not area.has_area():
		return
	var y := 0.0
	while y < area.size.y-0.001:
		var h := minf(period.y,area.size.y-y)
		var x := 0.0
		while x < area.size.x-0.001:
			var w := minf(period.x,area.size.x-x)
			RenderingServer.canvas_item_add_texture_rect_region(canvas,Rect2(area.position+Vector2(x,y),Vector2(w,h)),texture.get_rid(),Rect2(source.position,Vector2(w,h)/period*source.size),color)
			x += period.x
		y += period.y
