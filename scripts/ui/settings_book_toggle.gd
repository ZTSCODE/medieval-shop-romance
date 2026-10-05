extends HBoxContainer

signal toggled(value: bool)
var button_pressed := false:
	set(value):
		var changed := value != button_pressed
		button_pressed = value
		if changed and is_node_ready():
			_animate_selection()
		_refresh()
var disabled := false:
	set(value):
		disabled = value
		_refresh()
var _choices: Array[Button] = []
var _underline := 1.0
var _selection_motion: Tween
var _reveals: Array[float] = [0.0, 1.0]
var _alphas: Array[float] = [0.0, 1.0]
var _stroke: Texture2D
var _stroke_region := Rect2()
const BookSkin = preload("res://scripts/ui/settings_book_skin.gd")
const STROKE_PATH := "res://assets/art/ui/settings_20260929/toggle-underline.png"


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	# 只统一笔触墨色，保留生成图的透明颗粒；子控件不继承材质。
	var ink_shader := Shader.new()
	ink_shader.code = "shader_type canvas_item; varying vec4 ink_modulate; void vertex(){ ink_modulate = COLOR; } void fragment(){ COLOR = vec4(vec3(0.8902,0.8392,0.7216),texture(TEXTURE,UV).a) * ink_modulate; }"
	var ink_material := ShaderMaterial.new()
	ink_material.shader = ink_shader
	material = ink_material
	_stroke = load(STROKE_PATH)
	if _stroke != null:
		_stroke_region = Rect2(116, 364, 1753, 60)
	for index: int in 2:
		if index == 1:
			var slash := Label.new()
			slash.text = "/"
			slash.add_theme_color_override("font_color", BookSkin.MUTED)
			add_child(slash)
		var choice := Button.new()
		choice.custom_minimum_size = Vector2(72, 48)
		choice.add_theme_font_override("font", BookSkin.Typography.regular())
		choice.add_theme_font_size_override("font_size", 26)
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			choice.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		choice.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		choice.pressed.connect(_choose.bind(index == 0))
		_choices.append(choice)
		add_child(choice)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_settle()
	)
	_settle()
	_refresh()


func _choose(value: bool) -> void:
	if disabled or value == button_pressed:
		return
	button_pressed = value
	toggled.emit(value)


func _animate_selection() -> void:
	if is_instance_valid(_selection_motion):
		_selection_motion.kill()
	var chosen := 0 if button_pressed else 1
	var old := 1 - chosen
	_reveals[chosen] = 0.0
	_alphas[chosen] = 1.0
	_selection_motion = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_selection_motion.tween_method(_set_ink_blend, _underline, float(chosen), 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_selection_motion.tween_method(_set_stroke_alpha.bind(old), _alphas[old], 0.0, 0.10)
	_selection_motion.tween_method(_set_reveal.bind(chosen), 0.0, 1.0, 0.28).set_delay(0.035).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_ink_blend(value: float) -> void:
	_underline = value
	_refresh()


func _set_stroke_alpha(value: float, index: int) -> void:
	_alphas[index] = value
	queue_redraw()


func _set_reveal(value: float, index: int) -> void:
	_reveals[index] = value
	queue_redraw()


func _settle() -> void:
	if is_instance_valid(_selection_motion):
		_selection_motion.kill()
	_underline = 0.0 if button_pressed else 1.0
	_reveals = [1.0 if button_pressed else 0.0, 0.0 if button_pressed else 1.0]
	_alphas = _reveals.duplicate()
	_refresh()


func _draw() -> void:
	if _stroke == null or _stroke_region.size.x <= 0.0:
		return
	for index: int in _choices.size():
		var amount := _reveals[index]
		if amount <= 0.0 or _alphas[index] <= 0.0:
			continue
		var choice := _choices[index]
		var at := choice.position + Vector2((choice.size.x - 42.0) * 0.5, choice.size.y - 7.0)
		var height := 5.0
		var source := Rect2(_stroke_region.position, Vector2(_stroke_region.size.x * amount, _stroke_region.size.y))
		draw_texture_rect_region(_stroke, Rect2(at, Vector2(42.0 * amount, height)), source, Color(1, 1, 1, _alphas[index] * (0.4 if disabled else 1.0)))


func _refresh() -> void:
	queue_redraw()
	for index: int in _choices.size():
		var choice := _choices[index]
		choice.text = tr("SETTINGS_ON" if index == 0 else "SETTINGS_OFF")
		choice.disabled = disabled
		var amount := 1.0 - _underline if index == 0 else _underline
		var color := BookSkin.MUTED.lerp(BookSkin.INK, amount)
		for state: String in ["font_color", "font_pressed_color", "font_hover_pressed_color"]:
			choice.add_theme_color_override(state, color)
		for state: String in ["font_hover_color", "font_focus_color"]:
			choice.add_theme_color_override(state, color.lightened(0.12))
		choice.add_theme_color_override("font_disabled_color", Color(BookSkin.MUTED, 0.55))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()
