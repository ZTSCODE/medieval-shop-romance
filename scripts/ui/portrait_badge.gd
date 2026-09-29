class_name PortraitBadge
extends Control

var subject_id := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var art := GameArt.portrait(subject_id)
	if art != null:
		var placement := get_portrait_placement()
		var destination: Rect2 = placement.destination
		var source: Rect2 = placement.source
		var points := PackedVector2Array()
		var uv := PackedVector2Array()
		for index in 48:
			var direction := Vector2(cos(TAU * index / 48.0), sin(TAU * index / 48.0))
			points.append(destination.get_center() + direction * destination.size * 0.5)
			uv.append((source.position + (direction + Vector2.ONE) * 0.5 * source.size) / art.get_size())
		draw_polygon(points, PackedColorArray([Color.WHITE]), uv, art)
	var frame := GameTheme.art_texture("portrait_frame")
	if frame != null:
		ImagePlacement.draw(get_canvas_item(), frame, Rect2(Vector2.ZERO, size), &"contain")


func get_frame_rect() -> Rect2:
	var frame := GameTheme.art_texture("portrait_frame")
	if frame == null:
		return Rect2(Vector2.ZERO, size)
	return ImagePlacement.fit(Rect2(Vector2.ZERO, frame.get_size()), Rect2(Vector2.ZERO, size), &"contain").destination


func get_portrait_placement() -> Dictionary:
	var art := GameArt.portrait(subject_id)
	if art == null:
		return {"source": Rect2(), "destination": Rect2()}
	var region := get_portrait_region()
	var frame := get_frame_rect()
	var aperture := Rect2(frame.position + frame.size * Vector2(0.14, 0.10), frame.size * Vector2(0.72, 0.80))
	var source := Rect2(region.position * art.get_size(), region.size * art.get_size())
	return ImagePlacement.fit(source, aperture, &"cover", Vector2(0.5, 0.0))


func get_portrait_region() -> Rect2:
	var definition := ContentCatalog.npc_definition(subject_id)
	if definition.is_empty():
		definition = ContentCatalog.card_definition(ContentCatalog.card_id_for_kind(StringName(subject_id)))
	var region: Variant = definition.get("portrait_region", [])
	if not region is Array or region.size() != 4:
		return Rect2(0.0, 0.0, 1.0, 1.0)
	for value: Variant in region:
		if not (value is int or value is float) or not is_finite(float(value)):
			return Rect2(0.0, 0.0, 1.0, 1.0)
	var rect := Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2(0.0, 0.0, 1.0, 1.0)
	var clipped := rect.intersection(Rect2(0.0, 0.0, 1.0, 1.0))
	return clipped if clipped.has_area() else Rect2(0.0, 0.0, 1.0, 1.0)
