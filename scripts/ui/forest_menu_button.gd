extends Button

const Typography = preload("res://scripts/ui/forest_ui_typography.gd")
const Recolor = preload("res://scripts/ui/forest_menu_recolor.gdshader")

var _paper: TextureRect
var _leaf: TextureRect
var _visual: Control
var _caption: Label
var _selection := 0.0
var _feedback: Tween
var press_feedback: UiPressFeedback
var _caption_ink := Color("efe4c8")
var _disabled_ink := Color("a19985")


func _init() -> void:
	# 命中区域保持固定，纸、叶标与文字在独立绘制层一起轻压。
	set_meta("paper_motion_bound", true)


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_visual = Control.new()
	_visual.name = "MenuButtonVisual"
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual)
	_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper = TextureRect.new()
	_paper.name = "OriginalButtonPaper"
	var original := AtlasTexture.new()
	original.atlas = GameArt.texture("res://assets/art/ui/rebuild_20260923/system/button.png")
	original.region = Rect2(35, 97, 2100, 507)
	_paper.texture = original
	_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_paper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.show_behind_parent = true
	var recolor := preload("res://scripts/ui/ui_paper_palette.gd").button_material()
	_paper.material = recolor
	_visual.add_child(_paper)
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_font_override("font", Typography.regular())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		add_theme_color_override(state, Color("efe4c8"))
	add_theme_color_override("font_disabled_color", Color("a19985"))
	_leaf = TextureRect.new()
	_leaf.name = "SelectionLeaf"
	var leaf_atlas := AtlasTexture.new()
	leaf_atlas.atlas = GameArt.texture("res://assets/art/ui/forest_rebuild/type-leaf.png")
	leaf_atlas.region = Rect2(340, 160, 590, 1030)
	_leaf.texture = leaf_atlas
	_leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_leaf.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leaf.modulate = Color(0.64, 0.32, 0.20, 0)
	_visual.add_child(_leaf)
	_caption = Label.new()
	_caption.name = "MenuButtonCaption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_visual.add_child(_caption)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	press_feedback = UiPressFeedback.new()
	press_feedback.changed.connect(_update_press_visual)
	add_child(press_feedback)
	resized.connect(_layout_leaf)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_update_selection)
	focus_entered.connect(_update_selection)
	focus_exited.connect(_update_selection)
	button_down.connect(_update_selection)
	button_up.connect(_update_selection)
	_layout_leaf()
	_sync_caption()


func _process(_delta: float) -> void:
	_sync_caption()


func _sync_caption() -> void:
	# 保留 Button.text 供本地化、无障碍与外部逻辑读取；只隐藏原生字形。
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		var incoming := get_theme_color(state)
		if incoming.a > 0.0:
			if state == "font_color":
				_caption_ink = incoming
			elif state == "font_disabled_color":
				_disabled_ink = incoming
			add_theme_color_override(state, Color(incoming, 0.0))
	if _caption.text != text:
		_caption.text = text
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	if _caption.get_theme_font("font") != font:
		_caption.add_theme_font_override("font", font)
	if _caption.get_theme_font_size("font_size") != font_size:
		_caption.add_theme_font_size_override("font_size", font_size)
	var ink := _disabled_ink if disabled else _caption_ink
	if _caption.get_theme_color("font_color") != ink:
		_caption.add_theme_color_override("font_color", ink)


func _on_mouse_entered() -> void:
	if not disabled:
		grab_focus()
	_update_selection()


func _update_selection() -> void:
	var active := not disabled and has_focus()
	var target := 1.0 if active else 0.0
	if is_instance_valid(_feedback):
		_feedback.kill()
	_feedback = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_feedback.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_feedback.tween_method(_set_selection, _selection, target, 0.16)


func _set_selection(value: float) -> void:
	_selection = value
	_paper.material.set_shader_parameter("selection", value)
	_leaf.modulate.a = value
	queue_redraw()


func _update_press_visual(amount: float) -> void:
	_visual.pivot_offset = _visual.size * 0.5
	_visual.scale = Vector2.ONE * amount


func _layout_leaf() -> void:
	if not is_instance_valid(_leaf):
		return
	_leaf.size = Vector2(size.y * 0.30, size.y * 0.62)
	_leaf.position = Vector2(size.y * 0.27, (size.y - _leaf.size.y) * 0.5)
	_update_press_visual(press_feedback.amount if is_instance_valid(press_feedback) else 1.0)
