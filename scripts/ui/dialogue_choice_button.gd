extends Button

const Palette = preload("res://scripts/ui/ui_paper_palette.gd")
const Typography = preload("res://scripts/ui/forest_ui_typography.gd")
var caption: Label
var _leaf: TextureRect


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 回答直接写在整张对白纸上；细长行不再塞进固定比例的小纸条。
	for state: String in ["normal", "pressed", "disabled", "hover", "focus", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	caption = Label.new()
	caption.name = "ChoiceCaption"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", Typography.regular())
	caption.add_theme_color_override("font_color", Palette.INK)
	add_child(caption)
	_leaf = TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = GameArt.texture("res://assets/art/ui/forest_rebuild/type-leaf.png")
	atlas.region = Rect2(340, 160, 590, 1030)
	_leaf.texture = atlas
	_leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_leaf.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leaf.modulate = Color("d8b887")
	add_child(_leaf)
	mouse_entered.connect(_update_selection)
	mouse_exited.connect(_update_selection)
	focus_entered.connect(_update_selection)
	focus_exited.connect(_update_selection)
	preload("res://scripts/ui/paper_button_feedback.gd").bind(self)


func fit_caption(value: String, width: float, font_size: int, ui_scale: float) -> float:
	caption.text = value
	caption.add_theme_font_size_override("font_size", font_size)
	caption.position = Vector2(34, 8) * ui_scale
	caption.size = Vector2(maxf(width - 58 * ui_scale, 80), 0)
	var height := maxf(46 * ui_scale, caption.get_minimum_size().y + 20 * ui_scale)
	caption.size.y = height - 16 * ui_scale
	custom_minimum_size = Vector2(0, height)
	size = Vector2(width, height)
	_leaf.position = Vector2(6 * ui_scale, (height - 27 * ui_scale) * 0.5)
	_leaf.size = Vector2(17, 27) * ui_scale
	_update_selection()
	return height


func _update_selection() -> void:
	if not is_instance_valid(caption):
		return
	var selected := not disabled and (is_hovered() or has_focus())
	caption.add_theme_color_override("font_color", Palette.MUTED if disabled else (Color("f4d7a0") if selected else Palette.INK))
	_leaf.modulate.a = 1.0 if selected else 0.30
