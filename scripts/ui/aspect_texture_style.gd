class_name AspectTextureStyle
extends StyleBox

var texture: Texture2D
var modulate_color := Color.WHITE
var fit_mode: StringName = &"cover"
var alignment := Vector2(0.5, 0.5)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	ImagePlacement.draw(to_canvas_item, texture, rect, fit_mode, modulate_color, Rect2(), alignment)


func get_draw_plan(rect: Rect2) -> Dictionary:
	if texture == null:
		return {"source": Rect2(), "destination": Rect2()}
	return ImagePlacement.fit(Rect2(Vector2.ZERO, texture.get_size()), rect, fit_mode, alignment)
