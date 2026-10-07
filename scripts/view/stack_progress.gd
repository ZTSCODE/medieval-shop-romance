class_name StackProgressView
extends Node2D

var stack_id := ""
var progress := 0.0
var _size := Vector2.ZERO
var _ink: ShaderMaterial


func _init() -> void:
	visible = false
	z_index = 3900
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	_ink = ShaderMaterial.new()
	_ink.shader = preload("res://assets/shaders/stack_progress.gdshader")
	material = _ink


func set_progress(id: String, value: float, screen_rect: Rect2) -> void:
	stack_id = id
	progress = clampf(value, 0.0, 1.0)
	position = screen_rect.position
	_size = screen_rect.size
	visible = not stack_id.is_empty() and screen_rect.has_area()
	queue_redraw()


func clear() -> void:
	stack_id = ""
	progress = 0.0
	visible = false
	queue_redraw()


func get_progress_rect() -> Rect2:
	return Rect2(position, _size) if visible else Rect2()


func _draw() -> void:
	if not visible or _ink == null:
		return
	_ink.set_shader_parameter("bar_size", _size)
	_ink.set_shader_parameter("progress", progress)
	_ink.set_shader_parameter("linear_canvas", get_viewport().use_hdr_2d)
	draw_rect(Rect2(Vector2.ZERO, _size), Color.WHITE)
