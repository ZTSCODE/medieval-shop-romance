extends StyleBox

const PausePaper = preload("res://scripts/ui/pause_reference_paper.gd")
const SHADOW_OFFSETS := [Vector2(-1, 3), Vector2(1, 3), Vector2(0, 2)]
const BASE_TINT := Color(0.88, 0.99, 1.12)
const HOVER_TINT := Color(1.16, 1.25, 1.35)
const TAB_ACTIVE := Color(1.48, 1.53, 1.56)
var tint := Color.WHITE
var pressed := false
var popup := false
var press_amount := 1.0


static func make(highlight := false, down := false, menu := false) -> StyleBox:
	var result := new()
	result.tint = HOVER_TINT if highlight else BASE_TINT
	result.pressed = down
	result.popup = menu
	result.set_content_margin_all(18)
	result.content_margin_top = 10
	result.content_margin_bottom = 10
	return result


func _draw(canvas: RID, rect: Rect2) -> void:
	var visual := rect
	var amount := 0.97 if pressed else press_amount
	visual = Rect2(rect.position + rect.size * (1.0 - amount) * 0.5, rect.size * amount)
	draw_paper(canvas, visual, tint, popup)


static func draw_paper(canvas: RID, rect: Rect2, pigment: Color, menu := false, pixels_per_unit := 2.0) -> void:
	var part := "button"
	var texture := PausePaper.texture(part)
	var source := PausePaper.region(part)
	# 长菜单与按钮使用同一张暂停纸条，采样始终限于资源区域内。
	# 九区保留完整素材边角；长菜单中部固定密度铺纸，不超出素材区域。
	for offset: Vector2 in SHADOW_OFFSETS:
		_draw_sliced(canvas, texture, source, Rect2(rect.position + offset, rect.size), Color(0, 0, 0, 0.10), menu, pixels_per_unit)
	_draw_sliced(canvas, texture, source, rect, pigment, menu, pixels_per_unit)


static func _draw_sliced(canvas: RID, texture: Texture2D, source: Rect2, target: Rect2, pigment: Color, fixed_density := false, pixels_per_unit := 2.0) -> void:
	var source_edge := 90.0
	var edge := minf(12.0, minf(target.size.x, target.size.y) * 0.2)
	var sx := [source.position.x, source.position.x + source_edge, source.end.x - source_edge, source.end.x]
	var sy := [source.position.y, source.position.y + source_edge, source.end.y - source_edge, source.end.y]
	var dx := [target.position.x, target.position.x + edge, target.end.x - edge, target.end.x]
	var dy := [target.position.y, target.position.y + edge, target.end.y - edge, target.end.y]
	for y: int in 3:
		for x: int in 3:
			var from := Rect2(sx[x], sy[y], sx[x + 1] - sx[x], sy[y + 1] - sy[y])
			var to := Rect2(dx[x], dy[y], dx[x + 1] - dx[x], dy[y + 1] - dy[y])
			if x == 1 and y == 1:
				if fixed_density:
					_draw_fixed_paper(canvas, texture, from, to, pigment, pixels_per_unit)
					continue
				# 中部按比例取景，竖书签和长菜单不会把笔触拉成长条。
				from = ImagePlacement.fit(from, to, &"cover").source
			RenderingServer.canvas_item_add_texture_rect_region(canvas, to, texture.get_rid(), from, pigment, false, true)


static func _draw_fixed_paper(canvas: RID, texture: Texture2D, source: Rect2, target: Rect2, pigment: Color, pixels_per_unit := 2.0) -> void:
	# 纸纹维持固定采样密度，长列表只增加覆盖面积，不放大或拉糊笔触。
	var tile := source.size / pixels_per_unit
	for row in range(ceili(target.size.y / tile.y)):
		for column in range(ceili(target.size.x / tile.x)):
			var start := Vector2(column, row) * tile
			var extent := (target.size - start).min(tile)
			var part := Rect2(source.position, extent * pixels_per_unit)
			var destination := Rect2(target.position + start, extent)
			# 相邻块镜像衔接，共用同一采样边，避免重复拼接出现横缝。
			if row % 2 == 1:
				part.position.y = source.end.y - part.size.y
			if column % 2 == 1:
				part.position.x = source.end.x - part.size.x
			var uv_start := part.position / texture.get_size()
			var uv_end := part.end / texture.get_size()
			if row % 2 == 1:
				var temporary_y := uv_start.y
				uv_start.y = uv_end.y
				uv_end.y = temporary_y
			if column % 2 == 1:
				var temporary_x := uv_start.x
				uv_start.x = uv_end.x
				uv_end.x = temporary_x
			var vertices := PackedVector2Array([destination.position, Vector2(destination.end.x, destination.position.y), destination.end, Vector2(destination.position.x, destination.end.y)])
			var uv := PackedVector2Array([uv_start, Vector2(uv_end.x, uv_start.y), uv_end, Vector2(uv_start.x, uv_end.y)])
			RenderingServer.canvas_item_add_polygon(canvas, vertices, PackedColorArray([pigment]), uv, texture.get_rid())
