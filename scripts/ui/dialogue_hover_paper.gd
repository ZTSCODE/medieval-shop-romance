extends Control

# 对话交互专用底纸；与已有按压反馈共用按钮，不移动按钮命中区域。
var _button: Button
var _paper: StyleBoxTexture
var _hovered := false
var _held := false
var _opacity := 0.0
var _idle_ink: Color
const HOVER_INK := Color("eadfc7")

static func bind(button: Button, long_reply := false) -> void:
	if button.has_node("DialogueHoverPaper"):
		return
	var background := new()
	background.name = "DialogueHoverPaper"
	background._button = button
	background.set_meta("long_reply", long_reply)
	button.add_child(background)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_idle_ink = _button.get_theme_color("font_color")
	var recolor := ShaderMaterial.new()
	recolor.shader = preload("res://scripts/ui/dialogue_hover_paper.gdshader")
	recolor.set_shader_parameter("linear_canvas", get_viewport().use_hdr_2d)
	material = recolor
	_paper = StyleBoxTexture.new()
	var long_reply: bool = get_meta("long_reply", false)
	_paper.texture = load("res://assets/art/ui/dialogue_20261003/hover-button-distinct.png")
	_paper.region_rect = Rect2(44, 162, 2012, 424)
	# 源图边缘以高度为尺度保留；中段平铺适配长句，避免整幅横向拉伸。
	_paper.texture_margin_left = _paper.region_rect.size.y * 0.5
	_paper.texture_margin_right = _paper.region_rect.size.y * 0.5
	_paper.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	_button.mouse_entered.connect(func() -> void: _hovered = true)
	_button.mouse_exited.connect(func() -> void: _hovered = false)
	_button.button_down.connect(func() -> void: _held = true)
	_button.button_up.connect(func() -> void: _held = false)
	_button.visibility_changed.connect(_reset_hidden)
	_button.resized.connect(_layout)
	_layout()
	modulate.a = 0.0
	if not long_reply:
		_button.alignment = HORIZONTAL_ALIGNMENT_CENTER

func _layout() -> void:
	size = _button.size
	queue_redraw()

func _reset_hidden() -> void:
	if not _button.is_visible_in_tree():
		_hovered = false
		_held = false
		_opacity = 0.0
		modulate.a = 0.0

func _process(delta: float) -> void:
	if _button.disabled or not _button.is_visible_in_tree():
		_hovered = false
		_held = false
	var target := 1.0 if (_hovered or _held) else 0.0
	var previous := _opacity
	_opacity = move_toward(_opacity, target, delta / (0.12 if target > _opacity else 0.16))
	modulate.a = _opacity
	var ink := _idle_ink.lerp(HOVER_INK, _opacity)
	if _button.get_theme_color("font_color") != ink:
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			_button.add_theme_color_override(state, ink)
	var caption := _button.get_node_or_null("ChoiceCaption") as Label
	if caption != null and not _button.disabled and caption.get_theme_color("font_color") != ink:
		caption.add_theme_color_override("font_color", ink)
	if previous != _opacity:
		_button.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_hovered = false
		_held = false

func _draw() -> void:
	if _paper != null:
		var factor := size.y / _paper.region_rect.size.y
		if factor > 0.0:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * factor)
			# 阴影使用同一纸张轮廓，稍向右下偏移，保留薄纸的叠放感。
			_paper.modulate_color = Color(0, 0, 0, 0.12)
			for offset: Vector2 in [Vector2(-5, 14), Vector2(0, 14), Vector2(5, 14)]:
				_paper.draw(get_canvas_item(), Rect2(offset, size / factor))
			_paper.modulate_color = Color.WHITE
			_paper.draw(get_canvas_item(), Rect2(Vector2.ZERO, size / factor))
