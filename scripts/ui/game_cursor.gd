extends Node

const NORMAL_SOURCE = preload("res://assets/art/ui/hand_cursor/normal.png")
const HOVER_SOURCE = preload("res://assets/art/ui/hand_cursor/hover.png")
const PRESSED_SOURCE = preload("res://assets/art/ui/hand_cursor/pressed.png")
const DRAG_SOURCE = preload("res://assets/art/ui/hand_cursor/drag.png")
const CLICK_SPARK = preload("res://scripts/ui/cursor_click_spark.gd")
const SOURCE_SIZE := 256
const SOURCE_HOTSPOT := Vector2(24, 24)
const SOURCE_DRAG_HOTSPOT := Vector2(24, 24)
const BASE_CURSOR_SIZE := 128
const REFERENCE_SHORT_EDGE := 800.0
const MIN_CURSOR_SIZE := 88
const MAX_CURSOR_SIZE := 192
const DRAG_THRESHOLD := 5.0
const CUSTOM_SHAPES := [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_DRAG, Input.CURSOR_CAN_DROP, Input.CURSOR_MOVE]

var _pressed := false
var _dragging := false
var _press_origin := Vector2.ZERO
var _cursor_size := 0
var _hotspot := Vector2.ZERO
var _drag_hotspot := Vector2.ZERO
var _normal_texture: Texture2D
var _hover_texture: Texture2D
var _pressed_texture: Texture2D
var _drag_texture: Texture2D
var _resize_pending := false
var _particle_layer: CanvasLayer
var _cursor_layer: CanvasLayer
var _cursor_sprite: Sprite2D
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _click_serial := 0
var _child_windows: Array[Window] = []
var _native_window_cursor := false
var _native_cursor_state := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_particle_layer = CanvasLayer.new()
	_particle_layer.layer = 1000
	add_child(_particle_layer)
	_cursor_layer = CanvasLayer.new()
	_cursor_layer.layer = 1001
	add_child(_cursor_layer)
	_cursor_sprite = Sprite2D.new()
	_cursor_sprite.centered = false
	_cursor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cursor_layer.add_child(_cursor_sprite)
	get_tree().node_added.connect(_track_window)
	get_tree().node_removed.connect(_forget_window)
	_track_existing_windows(get_tree().root)
	get_window().size_changed.connect(_queue_scale_refresh)
	if DisplayServer.get_name() != "headless":
		_previous_mouse_mode = Input.get_mouse_mode()
	_refresh_scale()
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _process(_delta: float) -> void:
	var pressed := _is_any_mouse_button_pressed() and _has_pointer_focus()
	var pointer := get_viewport().get_mouse_position()
	_sync_pointer_state(pressed, pointer)
	_update_visual(pointer)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if event.pressed:
			_sync_pointer_state(true, event.position)
			if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				spawn_click_particles(event.position)
		_update_visual(event.position)
	elif event is InputEventMouseMotion:
		_update_visual(event.position)


func _is_any_mouse_button_pressed() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)


func _sync_pointer_state(pressed: bool, pointer_position: Vector2) -> void:
	if pressed and not _pressed:
		_press_origin = pointer_position
		_dragging = false
		_apply(true, false)
		return
	if not pressed:
		if _pressed or _dragging:
			_apply(false, false)
		return
	if not _dragging and _press_origin.distance_to(pointer_position) >= DRAG_THRESHOLD:
		_dragging = true
		_apply(true, true)


func texture_for_shape(shape: int, pressed: bool, dragging: bool = false) -> Texture2D:
	if dragging:
		return _drag_texture
	if pressed:
		return _pressed_texture
	return _normal_texture if shape == Input.CURSOR_ARROW else _hover_texture


func cursor_size_for_window(window_size: Vector2i) -> int:
	var short_edge := float(mini(window_size.x, window_size.y))
	var platform_max := 128 if OS.has_feature("web") else MAX_CURSOR_SIZE
	return clampi(roundi(BASE_CURSOR_SIZE * short_edge / REFERENCE_SHORT_EDGE), MIN_CURSOR_SIZE, platform_max)


func hotspot_for_size(cursor_size: int) -> Vector2:
	var scale := float(cursor_size) / SOURCE_SIZE
	return Vector2(round(SOURCE_HOTSPOT.x * scale), round(SOURCE_HOTSPOT.y * scale))


func drag_hotspot_for_size(cursor_size: int) -> Vector2:
	var scale := float(cursor_size) / SOURCE_SIZE
	return Vector2(round(SOURCE_DRAG_HOTSPOT.x * scale), round(SOURCE_DRAG_HOTSPOT.y * scale))


func current_textures() -> Array[Texture2D]:
	return [_normal_texture, _hover_texture, _pressed_texture, _drag_texture]


func spawn_click_particles(at: Vector2) -> void:
	if _particle_layer == null:
		return
	var spark = CLICK_SPARK.new()
	_particle_layer.add_child(spark)
	_click_serial += 1
	var phase := -0.18 + float(_click_serial % 3 - 1) * 0.08
	var canvas_scale := get_viewport().get_final_transform().get_scale()
	var canvas_to_screen := maxf(0.1, minf(absf(canvas_scale.x), absf(canvas_scale.y)))
	var visual_scale := float(_cursor_size) / BASE_CURSOR_SIZE / canvas_to_screen
	spark.setup(at, visual_scale, phase)


func particle_count() -> int:
	return _particle_layer.get_child_count() if _particle_layer != null else 0


func latest_particle_position() -> Vector2:
	if _particle_layer == null or _particle_layer.get_child_count() == 0:
		return Vector2(-1, -1)
	return (_particle_layer.get_child(_particle_layer.get_child_count() - 1) as Node2D).position


func is_dragging_visual() -> bool:
	return _dragging


func _queue_scale_refresh() -> void:
	if _resize_pending:
		return
	_resize_pending = true
	call_deferred("_refresh_scale")


func _refresh_scale() -> void:
	_resize_pending = false
	var target_size := cursor_size_for_window(get_window().size)
	if target_size == _cursor_size:
		return
	_cursor_size = target_size
	_hotspot = hotspot_for_size(target_size)
	_drag_hotspot = drag_hotspot_for_size(target_size)
	_normal_texture = _scaled_texture(NORMAL_SOURCE, target_size)
	_hover_texture = _scaled_texture(HOVER_SOURCE, target_size)
	_pressed_texture = _scaled_texture(PRESSED_SOURCE, target_size)
	_drag_texture = _scaled_texture(DRAG_SOURCE, target_size)
	_native_cursor_state = -1
	_apply(_pressed, _dragging)


func _scaled_texture(source: Texture2D, size: int) -> Texture2D:
	var image := source.get_image()
	if size != SOURCE_SIZE:
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


func _apply(pressed: bool, dragging: bool = false) -> void:
	var probe_started := HitchProbe.stamp()
	_pressed = pressed
	_dragging = dragging if pressed else false
	_update_visual(get_viewport().get_mouse_position())
	HitchProbe.record("cursor_apply", probe_started)


func _update_visual(pointer: Vector2) -> void:
	if not is_instance_valid(_cursor_sprite):
		return
	if DisplayServer.get_name() == "headless":
		_cursor_sprite.visible = false
		return
	_sync_window_cursor()
	if _native_window_cursor:
		_cursor_sprite.visible = false
		return
	if not get_window().has_focus():
		_cursor_sprite.visible = false
		return
	var shape := DisplayServer.cursor_get_shape()
	if shape not in CUSTOM_SHAPES:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_cursor_sprite.visible = false
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_HIDDEN:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_cursor_sprite.texture = texture_for_shape(shape, _pressed, _dragging)
	var final_scale := get_viewport().get_final_transform().get_scale().abs()
	var pixel_scale := maxf(0.1, minf(final_scale.x, final_scale.y))
	_cursor_sprite.scale = Vector2.ONE / pixel_scale
	_cursor_sprite.position = pointer - (_drag_hotspot if _dragging else _hotspot) / pixel_scale
	_cursor_sprite.visible = get_viewport().get_visible_rect().has_point(pointer)


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		_clear_native_cursor()
		Input.set_mouse_mode(_previous_mouse_mode)


func _track_existing_windows(node: Node) -> void:
	_track_window(node)
	for child in node.get_children():
		_track_existing_windows(child)


func _track_window(node: Node) -> void:
	if node is Window and node != get_window() and node not in _child_windows:
		_child_windows.append(node)
		node.visibility_changed.connect(_window_visibility_changed)


func _forget_window(node: Node) -> void:
	if node is Window:
		_child_windows.erase(node)


func _window_visibility_changed() -> void:
	_update_visual(get_viewport().get_mouse_position())


func _has_pointer_focus() -> bool:
	if get_window().has_focus():
		return true
	for window in _child_windows:
		if is_instance_valid(window) and window.visible and window.has_focus():
			return true
	return false


func _sync_window_cursor() -> void:
	var has_visible_window := false
	for window in _child_windows:
		if is_instance_valid(window) and window.visible:
			has_visible_window = true
			break
	if not has_visible_window:
		if _native_window_cursor:
			_clear_native_cursor()
		return
	# 子窗口在所有 CanvasLayer 之后合成，因此弹出期间使用相同纹理的原生光标。
	var state := 2 if _dragging else (1 if _pressed else 0)
	if not _native_window_cursor or state != _native_cursor_state:
		for shape in CUSTOM_SHAPES:
			Input.set_custom_mouse_cursor(texture_for_shape(shape, _pressed, _dragging), shape, _drag_hotspot if _dragging else _hotspot)
		_native_cursor_state = state
	_native_window_cursor = true
	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _clear_native_cursor() -> void:
	if _native_window_cursor:
		for shape in CUSTOM_SHAPES:
			Input.set_custom_mouse_cursor(null, shape)
	_native_window_cursor = false
	_native_cursor_state = -1
