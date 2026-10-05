extends Node

const Paper = preload("res://scripts/ui/settings_control_paper.gd")
var _button: Button
var _paper: StyleBox
var _tween: Tween
var _feedback: UiPressFeedback
var _highlight := 0.0
var _visual: Control
var _caption: Label
var _arrow: TextureRect
var _ink := Color.WHITE
var _disabled_ink := Color.WHITE


static func bind(button: Button) -> void:
	if button.has_meta("settings_motion"):
		return
	button.set_meta("settings_motion", true)
	var motion := new()
	motion.name = "SettingsControlMotion"
	button.add_child(motion)


static func bind_slider(slider: HSlider) -> void:
	for event: String in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited"]:
		slider.connect(event, _slider_feedback.bind(slider))
	slider.visibility_changed.connect(func():
		if not slider.is_visible_in_tree():
			var previous: Tween = slider.get_meta("settings_glow") if slider.has_meta("settings_glow") else null
			if is_instance_valid(previous):
				previous.kill()
			slider.self_modulate = Color.WHITE
	)


static func _slider_feedback(slider: HSlider) -> void:
	var previous: Tween = slider.get_meta("settings_glow") if slider.has_meta("settings_glow") else null
	if is_instance_valid(previous):
		previous.kill()
	var motion := slider.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	slider.set_meta("settings_glow", motion)
	var active := slider.has_focus() or slider.get_global_rect().has_point(slider.get_global_mouse_position())
	motion.tween_property(slider, "self_modulate", Color(1.12, 1.12, 1.10) if active else Color.WHITE, 0.14)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_button = get_parent() as Button
	_paper = Paper.make()
	# 状态共用连续插值纸面，命中区域与容器布局始终不动。
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		_button.add_theme_stylebox_override(state, _paper)
	for event: String in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited"]:
		_button.connect(event, _update)
	_feedback = UiPressFeedback.new()
	_feedback.changed.connect(func(amount: float):
		_paper.press_amount = amount
		if is_instance_valid(_visual):
			_visual.pivot_offset = _button.size * 0.5
			_visual.scale = Vector2.ONE * amount
		_button.queue_redraw()
	)
	_button.add_child.call_deferred(_feedback)
	if _button is OptionButton:
		_button.get_popup().about_to_popup.connect(_option_opened)
	_button.visibility_changed.connect(_reset)
	_build_visual.call_deferred()


func _build_visual() -> void:
	if not is_instance_valid(_button):
		return
	_ink = _button.get_theme_color("font_color")
	_disabled_ink = _button.get_theme_color("font_disabled_color")
	# 原生文字保留给可访问性和布局；独立绘制层与纸面共享轻压幅度。
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		_button.add_theme_color_override(state, Color.TRANSPARENT)
	_visual = Control.new()
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(_visual)
	_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption = Label.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.horizontal_alignment = _button.alignment
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_visual.add_child(_caption)
	if _button is OptionButton:
		_arrow = TextureRect.new()
		_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_arrow.texture = _button.get_theme_icon("arrow")
		_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_visual.add_child(_arrow)
		var empty := Image.create(24, 24, false, Image.FORMAT_RGBA8)
		empty.fill(Color.TRANSPARENT)
		_button.add_theme_icon_override("arrow", ImageTexture.create_from_image(empty))
	_button.resized.connect(_layout_visual)
	_layout_visual()
	_process(0.0)


func _layout_visual() -> void:
	if not is_instance_valid(_caption):
		return
	_caption.position = Vector2(18, 0)
	_caption.size = Vector2(maxf(0.0, _button.size.x - 36.0 - (38.0 if _arrow != null else 0.0)), _button.size.y)
	_visual.pivot_offset = _button.size * 0.5
	if is_instance_valid(_arrow):
		_arrow.position = Vector2(_button.size.x - 38, (_button.size.y - 24) * 0.5)
		_arrow.size = Vector2(24, 24)


func _process(_delta: float) -> void:
	if not is_instance_valid(_caption):
		return
	if _caption.text != _button.text:
		_caption.text = _button.text
	var font := _button.get_theme_font("font")
	var font_size := _button.get_theme_font_size("font_size")
	if _caption.get_theme_font("font") != font:
		_caption.add_theme_font_override("font", font)
	if _caption.get_theme_font_size("font_size") != font_size:
		_caption.add_theme_font_size_override("font_size", font_size)
	var color := _disabled_ink if _button.disabled else _ink
	if _caption.get_theme_color("font_color") != color:
		_caption.add_theme_color_override("font_color", color)
	if is_instance_valid(_arrow):
		_arrow.modulate.a = 0.5 if _button.disabled else 1.0


func _option_opened() -> void:
	# 弹窗接管焦点后再播放完整轻压，避免首次展开被焦点通知立即取消。
	_pulse_option.call_deferred()


func _pulse_option() -> void:
	if not is_instance_valid(_feedback) or not _feedback.is_inside_tree():
		return
	_feedback.set_pressed(true)
	_feedback.set_pressed(false)


func _update() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	var target := 1.0 if not _button.disabled and (_button.is_hovered() or _button.has_focus()) else 0.0
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_paint, _highlight, target, 0.16)


func _paint(value: float) -> void:
	_highlight = value
	_paper.tint = Paper.BASE_TINT.lerp(Paper.HOVER_TINT, value)
	_button.queue_redraw()


func _reset() -> void:
	if not _button.is_visible_in_tree():
		if is_instance_valid(_tween):
			_tween.kill()
		_paint(0.0)

