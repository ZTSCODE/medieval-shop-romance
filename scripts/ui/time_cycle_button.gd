extends Button

const Paper = preload("res://scripts/ui/settings_control_paper.gd")
const ROOT := "res://assets/art/ui/time_controls_20260929/"
const REGIONS := {"pause": Rect2(368, 255, 519, 744), "speed-1x": Rect2(270, 343, 694, 596), "speed-3x": Rect2(238, 373, 767, 543)}
var _paper: StyleBox
var _glyph: TextureRect
var _feedback: UiPressFeedback
var _highlight: Tween
var _state := ""
var _icons: Dictionary = {}
var _was_disabled := false
var _keyboard_focus := false


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	_paper = Paper.make()
	_paper.tint = Paper.HOVER_TINT
	_paper.set_content_margin_all(5)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(state, _paper)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# 原生文字保留状态语义，实际显示使用独立生成的图标。
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	_glyph = TextureRect.new()
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_glyph)
	_feedback = UiPressFeedback.new()
	_feedback.changed.connect(_press)
	add_child(_feedback)
	for event: String in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited"]:
		connect(event, _hover)
	resized.connect(_layout_glyph)
	_layout_glyph()
	for key: String in ["pause", "speed-1x", "speed-3x"]:
		_load_icon(key)
	set_time_state(1.0, false)


func set_time_state(speed: float, paused: bool) -> void:
	var key := "pause" if paused else "speed-3x" if speed > 1.0 else "speed-1x"
	if not is_instance_valid(_glyph):
		return
	if _state == key and _was_disabled == disabled:
		return
	_state = key
	_was_disabled = disabled
	_glyph.texture = _icons[key]
	_glyph.modulate.a = 0.45 if disabled else 1.0
	_hover()


func _load_icon(key: String) -> void:
	var texture: Texture2D = load(ROOT + key + ".png")
	if texture == null:
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = REGIONS[key]
	_icons[key] = atlas


func _layout_glyph() -> void:
	_glyph.size = Vector2(34, 22)
	_glyph.position = (size - _glyph.size) * 0.5
	_glyph.pivot_offset = _glyph.size * 0.5


func _press(amount: float) -> void:
	_paper.press_amount = amount
	_glyph.scale = Vector2.ONE * amount
	queue_redraw()


func _hover() -> void:
	if is_instance_valid(_highlight):
		_highlight.kill()
	var target: Color = Paper.TAB_ACTIVE if not disabled and (is_hovered() or (has_focus() and _keyboard_focus)) else Paper.HOVER_TINT
	_highlight = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_highlight.tween_method(_tint, _paper.tint, target, 0.16)


func _input(event: InputEvent) -> void:
	var keyboard := _keyboard_focus
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		keyboard = false
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.pressed:
		keyboard = true
	if keyboard != _keyboard_focus:
		_keyboard_focus = keyboard
		_hover()


func _tint(value: Color) -> void:
	_paper.tint = value
	queue_redraw()
