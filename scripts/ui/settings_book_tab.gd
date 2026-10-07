extends Button

signal visual_changed
var selection := 0.0
var _selection_motion: Tween
var _ink_motion: Tween
var _target := -1.0
var _ink := Color("aaa99e")
var _spring_from := 0.0
var _spring_to := 0.0


func _ready() -> void:
	set_meta("audio_event", "book.page")
	# 书签纸面由整页统一绘制，底端藏在正文页后，不再作为浮动按钮。
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	add_theme_font_size_override("font_size", 24)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_entered.connect(_update_selection)
	focus_exited.connect(_update_selection)
	mouse_entered.connect(_update_selection)
	mouse_exited.connect(_update_selection)
	_set_ink(_ink)
	_update_selection()


func _update_selection() -> void:
	var target := 1.0 if button_pressed else 0.0
	if target != _target:
		_target = target
		if is_instance_valid(_selection_motion):
			_selection_motion.kill()
		_spring_from = selection
		_spring_to = target
		_selection_motion = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		# 零初速阻尼弹簧：先柔和起步，再宽幅回落，避免弹性缓出首帧猛跳。
		_selection_motion.tween_method(_spring_step, 0.0, 0.72, 0.72)
		_selection_motion.tween_callback(_set_selection.bind(target))
	var ink := Color("efe4c8") if button_pressed or is_hovered() or has_focus() else Color("aaa99e")
	if is_instance_valid(_ink_motion):
		_ink_motion.kill()
	_ink_motion = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_ink_motion.tween_method(_set_ink, _ink, ink, 0.14)


func _set_selection(value: float) -> void:
	selection = value
	queue_redraw()
	visual_changed.emit()


func _spring_step(time: float) -> void:
	var progress := 1.0 - exp(-8.0 * time) * (cos(16.0 * time) + 0.5 * sin(16.0 * time))
	_set_selection(lerpf(_spring_from, _spring_to, progress))


func _set_ink(ink: Color) -> void:
	_ink = ink
	for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		add_theme_color_override(state, ink)
	queue_redraw()


func _draw() -> void:
	if icon != null:
		# 图标与父页绘制的书签共享同一位移，命中区域保持稳定。
		var at := (size - Vector2(40, 40)) * 0.5
		draw_texture_rect(icon, visual_rect(Rect2(at, Vector2(40, 40))), false, _ink)


func visual_offset() -> float:
	return 14.0 * (1.0 - selection)


func visual_rect(rect: Rect2) -> Rect2:
	# 底部像夹在纸页里，起落时微压扁再舒展；图标与纸面共用形变。
	var bend := sin(PI * selection)
	var stretch := Vector2(1.0 + 0.025 * bend, 1.0 - 0.045 * bend)
	var anchor := Vector2(size.x * 0.5, 96.0)
	return Rect2(anchor + (rect.position - anchor) * stretch + Vector2(0, visual_offset()), rect.size * stretch)
