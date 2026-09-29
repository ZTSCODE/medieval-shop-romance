extends Texture2D

var source: Texture2D
var logical_size := Vector2i(24,24)

func _get_width() -> int:
	return logical_size.x

func _get_height() -> int:
	return logical_size.y

func _has_alpha() -> bool:
	return true

func _get_rid() -> RID:
	return source.get_rid() if source != null else RID()

func _draw(canvas: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
	_draw_rect(canvas,Rect2(pos,Vector2(logical_size)),false,modulate,transpose)

func _draw_rect(canvas: RID, rect: Rect2, _tile: bool, modulate: Color, transpose: bool) -> void:
	if source != null:
		var fit := ImagePlacement.fit(Rect2(Vector2.ZERO,source.get_size()),rect,&"contain")
		source.draw_rect(canvas,fit.destination,false,modulate,transpose)

func _draw_rect_region(canvas: RID, rect: Rect2, src_rect: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
	if source != null:
		var ratio := source.get_size()/Vector2(logical_size)
		source.draw_rect_region(canvas,rect,Rect2(src_rect.position*ratio,src_rect.size*ratio),modulate,transpose,clip_uv)
