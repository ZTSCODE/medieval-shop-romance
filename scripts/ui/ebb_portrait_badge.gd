extends PortraitBadge

var press_feedback: UiPressFeedback


func _ready() -> void:
	super._ready()
	press_feedback = UiPressFeedback.new()
	press_feedback.changed.connect(func(_amount: float) -> void: queue_redraw())
	add_child(press_feedback)


func get_frame_rect() -> Rect2:
	var side := minf(size.x, size.y)
	return Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)


func get_portrait_placement() -> Dictionary:
	var art := GameArt.card_face(subject_id)
	if art == null:
		return {"source": Rect2(), "destination": Rect2()}
	var region := get_portrait_region()
	var aperture := get_frame_rect().grow(-4.0)
	return ImagePlacement.fit(Rect2(region.position * art.get_size(), region.size * art.get_size()), aperture, &"cover", Vector2(0.5, 0.0))


func _draw() -> void:
	var amount := press_feedback.amount if is_instance_valid(press_feedback) else 1.0
	draw_set_transform(size * (1.0 - amount) * 0.5, 0.0, Vector2.ONE * amount)
	preload("res://scripts/ui/hud_reference_paper.gd").draw_paper(get_canvas_item(), Rect2(Vector2.ZERO,size), "portrait")
	var art := GameArt.card_face(subject_id)
	if art != null:
		var region := get_portrait_region()
		var source := Rect2(region.position * art.get_size(), region.size * art.get_size())
		ImagePlacement.draw(get_canvas_item(),art,Rect2(Vector2(7,9),size-Vector2(14,18)),&"cover",Color.WHITE,source,Vector2(0.5,0.0))
