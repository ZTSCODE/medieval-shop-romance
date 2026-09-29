class_name TableBackdrop
extends Node2D


func _draw() -> void:
	var bounds := TableState.WORLD_BOUNDS
	draw_rect(bounds, Color(0.48, 0.54, 0.56, 0.58), false, 2.0)
