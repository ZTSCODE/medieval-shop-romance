class_name ImagePlacement
extends RefCounted


static func fit(source: Rect2, target: Rect2, mode: StringName = &"cover", anchor: Vector2 = Vector2(0.5, 0.5)) -> Dictionary:
	if not _valid_rect(source) or not _valid_rect(target):
		return {"source": Rect2(), "destination": Rect2()}
	var alignment := anchor.clamp(Vector2.ZERO, Vector2.ONE)
	var result_source := source
	var destination := target
	if mode == &"contain":
		var factor := minf(target.size.x / source.size.x, target.size.y / source.size.y)
		destination.size = source.size * factor
		destination.position += (target.size - destination.size) * alignment
	else:
		var factor := maxf(target.size.x / source.size.x, target.size.y / source.size.y)
		result_source.size = target.size / factor
		result_source.position += (source.size - result_source.size) * alignment
	return {"source": result_source, "destination": destination}


static func draw(canvas_item: RID, texture: Texture2D, target: Rect2, mode: StringName = &"cover", modulate: Color = Color.WHITE, source: Rect2 = Rect2(), anchor: Vector2 = Vector2(0.5, 0.5)) -> void:
	if texture == null:
		return
	var sampling := source if source.has_area() else Rect2(Vector2.ZERO, texture.get_size())
	var placement := fit(sampling, target, mode, anchor)
	if placement.destination.has_area():
		texture.draw_rect_region(canvas_item, placement.destination, placement.source, modulate, false, true)


static func _valid_rect(rect: Rect2) -> bool:
	return rect.has_area() and rect.position.is_finite() and rect.size.is_finite()
