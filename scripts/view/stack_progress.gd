class_name StackProgressView
extends Node2D

const TRACK_PATH := "res://assets/art/ui/paper_v2/progress_track.png"
const FILL_PATH := "res://assets/art/ui/paper_v2/progress_fill.png"

var stack_id := ""
var progress := 0.0
var _size := Vector2.ZERO
var _track: Texture2D
var _fill: Texture2D
var _track_region := Rect2()
var _fill_region := Rect2()


func _init() -> void:
	visible = false
	z_index = 3900
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	if ResourceLoader.exists(TRACK_PATH):
		_track = GameTheme.art_texture("progress_track")
		if _track != null:
			_track_region = Rect2(Vector2.ZERO, _track.get_size())
	if ResourceLoader.exists(FILL_PATH):
		_fill = GameTheme.art_texture("progress_fill")
		if _fill != null:
			_fill_region = Rect2(Vector2.ZERO, _fill.get_size())


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
	if not visible or _track == null or _fill == null:
		return
	var rect := Rect2(Vector2.ZERO, _size)
	ImagePlacement.draw(get_canvas_item(), _track, rect, &"cover", Color.WHITE, _track_region)
	if progress <= 0.0:
		return
	var placement := get_fill_draw_plan()
	if placement.destination.has_area():
		_fill.draw_rect_region(get_canvas_item(), placement.destination, placement.source, Color("70856e"), false, true)


func get_fill_draw_plan() -> Dictionary:
	var padding := Vector2(minf(4.0, _size.x * 0.04), _size.y * 0.20)
	var placement := ImagePlacement.fit(_fill_region, Rect2(padding, _size - padding * 2.0), &"cover", Vector2(0.0, 0.5))
	placement.source.size.x *= progress
	placement.destination.size.x *= progress
	return placement
