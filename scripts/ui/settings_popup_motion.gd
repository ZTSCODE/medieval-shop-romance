extends Node

const DURATION := 0.18
var _popup: PopupMenu
var _tween: Tween
var _expansion := 1.0
var _closing_layer: CanvasLayer
var _target_size := Vector2i.ZERO
var _minimum_size := Vector2i.ZERO
var _last_close_capture_usec := 0
var _scrollbars: Array[ScrollBar] = []
var _scroll_motion: Tween
var _scroll_ready := false


static func bind(popup: PopupMenu) -> void:
	if popup.has_node("SettingsPopupMotion"):
		return
	var motion := new()
	motion.name = "SettingsPopupMotion"
	motion._popup = popup
	popup.add_child(motion)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_popup.about_to_popup.connect(_reveal)
	_popup.popup_hide.connect(_close)
	_bind_scrollbars(_popup)
	_hide_scrollbars()


func _bind_scrollbars(node: Node) -> void:
	for child in node.get_children(true):
		if child is ScrollBar:
			_scrollbars.append(child)
			child.value_changed.connect(_on_scroll_changed.bind(child))
		_bind_scrollbars(child)


func _hide_scrollbars() -> void:
	_scroll_ready = false
	if _scroll_motion != null and _scroll_motion.is_valid():
		_scroll_motion.kill()
	for bar in _scrollbars:
		# 只隐藏绘制，保留原生滚动布局，避免内容宽度跳变。
		bar.self_modulate.a = 0.0


func _on_scroll_changed(_value: float, bar: ScrollBar) -> void:
	if not _scroll_ready or not _popup.visible or bar.max_value - bar.min_value <= bar.page:
		return
	if _scroll_motion != null and _scroll_motion.is_valid():
		_scroll_motion.kill()
	_scroll_motion = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_scroll_motion.tween_property(bar, "self_modulate:a", 1.0, 0.08)
	_scroll_motion.tween_interval(0.65)
	_scroll_motion.tween_property(bar, "self_modulate:a", 0.0, 0.18)


func _finish_expansion() -> void:
	_restore_window_limits()
	# 等原生容器完成最后一次布局，排除动画引起的滚动范围校正。
	_arm_scrolling.call_deferred()


func _arm_scrolling() -> void:
	_scroll_ready = _popup.visible and is_equal_approx(_expansion, 1.0)


func _reveal() -> void:
	_reset()
	if is_instance_valid(_closing_layer):
		_closing_layer.queue_free()
	# 从顶部逐渐揭开真实窗口，不缩放文字；鼠标始终使用原生项坐标。
	_start_expansion.call_deferred()


func _start_expansion() -> void:
	if not _popup.visible:
		return
	_target_size = _popup.size
	_minimum_size = _popup.min_size
	_popup.min_size = Vector2i(_minimum_size.x, 1)
	_set_expansion(0.70)
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_expansion, 0.70, 1.0, DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_finish_expansion)


func _set_expansion(value: float) -> void:
	_expansion = value
	if _target_size != Vector2i.ZERO:
		_popup.size = Vector2i(_target_size.x, maxi(1, roundi(_target_size.y * value)))


func _reset() -> void:
	_hide_scrollbars()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_set_expansion(1.0)
	_restore_window_limits()


func _restore_window_limits() -> void:
	if _target_size == Vector2i.ZERO:
		return
	_popup.min_size = _minimum_size
	_target_size = Vector2i.ZERO


func _close() -> void:
	# 原生弹窗的隐藏不可延迟；用最后完整内容帧收起，输入立即回到真实界面。
	# 只在关闭时读回一次，动画期间不读回纹理，也不拦截鼠标。
	if DisplayServer.get_name() == "headless" or not is_inside_tree() or not _popup.is_embedded():
		_reset()
		return
	var capture_started := Time.get_ticks_usec()
	var frame := get_tree().root.get_texture().get_image()
	var region := Rect2i(_popup.position, _popup.size).intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	var bitmap := frame.get_region(region)
	_last_close_capture_usec = Time.get_ticks_usec() - capture_started
	_reset()
	if bitmap == null or bitmap.is_empty():
		return
	if is_instance_valid(_closing_layer):
		_closing_layer.queue_free()
	_closing_layer = CanvasLayer.new()
	_closing_layer.layer = 999
	_closing_layer.transform = get_tree().root.get_final_transform().affine_inverse()
	get_tree().root.add_child(_closing_layer)
	var reveal := Control.new()
	reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reveal.clip_contents = true
	reveal.size = Vector2(region.size)
	reveal.position = Vector2(region.position)
	_closing_layer.add_child(reveal)
	var snapshot := TextureRect.new()
	snapshot.texture = ImageTexture.create_from_image(bitmap)
	snapshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snapshot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	snapshot.size = Vector2(region.size)
	reveal.add_child(snapshot)
	var motion := _closing_layer.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	motion.tween_property(reveal, "size:y", 0.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	motion.tween_callback(_closing_layer.queue_free)
