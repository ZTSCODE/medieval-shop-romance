extends Control

var branch_count := 1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var arrow := GameArt.texture("res://assets/art/ui/independent_components_20260922/recipe/recipe-arrow-right.png")
	if arrow != null:
		ImagePlacement.draw(get_canvas_item(),arrow,Rect2(Vector2.ZERO,size),&"contain")
