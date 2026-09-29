class_name GameTheme
extends RefCounted

const Palette = preload("res://scripts/ui/ui_paper_palette.gd")
const INK := Palette.INK
const DEEP_INK := Color("303c36")
const PAPER := Palette.INK
const MUTED := Palette.MUTED
const GOLD := Color("677d69")
const GOLD_DIM := Color("9ca28a")
const RED := Palette.ERROR
const SURFACE := Color("e6e5cf")
const ART_DIR := "res://assets/art/ui/paper_v2/"
const FLAT_ART_DIR := "res://assets/art/ui/paper_v3_flat/"
const FLAT_ART_NAMES := ["card_face", "dialogue_panel", "dialogue_button"]
const ROSE_INK := Color("513b48")
const ROSE_MUTED := Color("81656a")
static var _small_icons: Dictionary = {}
static var _trimmed_art: Dictionary = {}
static var _art_layout: Dictionary = {}
static var _flat_art: Dictionary = {}
static var _flat_art_layout: Dictionary = {}
static var _flat_layout_loaded := false
static var _paper_font: SystemFont


static func paper_font() -> SystemFont:
	return preload("res://scripts/ui/forest_ui_typography.gd").regular()


static func art_texture(asset_name: String) -> Texture2D:
	if _art_layout.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART_DIR + "layout.json"))
		if parsed is Dictionary:
			_art_layout = parsed
	if not _trimmed_art.has(asset_name):
		var source := GameArt.texture(ART_DIR + asset_name + ".png")
		if source == null:
			return null
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		if _art_layout.has(asset_name):
			var region: Array = _art_layout[asset_name].region
			atlas.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
		else:
			atlas.region = source.get_image().get_used_rect()
		_trimmed_art[asset_name] = atlas
	return _trimmed_art[asset_name]


static func flat_art_texture(asset_name: String) -> Texture2D:
	if asset_name not in FLAT_ART_NAMES:
		return null
	if not _flat_layout_loaded and FileAccess.file_exists(FLAT_ART_DIR + "layout.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FLAT_ART_DIR + "layout.json"))
		if parsed is Dictionary:
			_flat_art_layout = parsed
		_flat_layout_loaded = true
	if not _flat_art.has(asset_name):
		var path := FLAT_ART_DIR + asset_name + ".png"
		if not ResourceLoader.exists(path):
			return null
		var source := GameArt.texture(path)
		if source == null:
			return null
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		if _flat_art_layout.has(asset_name):
			var region: Array = _flat_art_layout[asset_name].region
			atlas.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
		else:
			atlas.region = source.get_image().get_used_rect()
		_flat_art[asset_name] = atlas
	return _flat_art[asset_name]


static func card_face_texture() -> Texture2D:
	return flat_art_texture("card_face")


static func rose_style(role: StringName = &"panel", inset: float = 12.0) -> RosePaperStyle:
	return RosePaperStyle.style_for(role, inset)


static func dialogue_style(inset: float = 24.0) -> RosePaperStyle:
	return RosePaperStyle.style_for(&"dialogue", inset)


static func dialogue_button_style(state: String) -> StyleBox:
	if state == "focus":
		return StyleBoxEmpty.new()
	var style := RosePaperStyle.style_for(&"button", 8.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.modulate_color = Color.WHITE
	if state == "hover":
		style.modulate_color = Color(1.035, 1.02, 1.025, 1.0)
	elif state == "pressed":
		style.modulate_color = Color(0.97, 0.92, 0.94, 1.0)
	elif state == "disabled":
		style.modulate_color = Color(0.91, 0.86, 0.87, 0.75)
	return style


static func apply_dialogue_button(button: Button) -> void:
	apply_button(button)
	button.add_theme_font_override("font", paper_font())
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, dialogue_button_style(state))
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, ROSE_INK)
	button.add_theme_color_override("font_disabled_color", ROSE_MUTED)


static func make_theme() -> Theme:
	var result := Theme.new()
	var font := preload("res://scripts/ui/forest_ui_typography.gd").regular()
	result.default_font = font
	result.default_font_size = 18
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "RichTextLabel", INK)
	result.set_stylebox("panel", "PanelContainer", panel_style())
	result.set_stylebox("panel", "PopupMenu", paper_style("name_panel", 20.0))
	result.set_stylebox("panel", "AcceptDialog", paper_style("name_panel", 28.0))
	result.set_stylebox("embedded_border", "Window", paper_style("name_panel", 18.0))
	result.set_stylebox("embedded_unfocused_border", "Window", paper_style("name_panel", 18.0))
	result.set_color("title_color", "Window", INK)
	result.set_icon("close", "Window", small_icon("close", Vector2i(22, 22)))
	result.set_icon("close_pressed", "Window", small_icon("close", Vector2i(20, 20)))
	result.set_stylebox("normal", "LineEdit", paper_style("button", 14.0))
	result.set_stylebox("focus", "LineEdit", paper_style("button_hover", 14.0))
	result.set_color("font_color", "LineEdit", INK)
	result.set_color("caret_color", "LineEdit", INK)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("selection_color", "LineEdit", Color("68705b"))
	for type_name: String in ["Button", "OptionButton", "CheckBox"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			result.set_stylebox(state, type_name, button_style(state))
		result.set_color("font_color", type_name, INK)
		result.set_color("font_hover_color", type_name, INK)
		result.set_color("font_pressed_color", type_name, INK)
		result.set_color("font_disabled_color", type_name, MUTED)
		result.set_color("font_focus_color", type_name, INK)
		result.set_color("icon_normal_color", type_name, Color.WHITE)
		result.set_color("icon_hover_color", type_name, Color.WHITE)
	result.set_color("font_color", "PopupMenu", INK)
	result.set_icon("arrow", "OptionButton", small_icon("arrow", Vector2i(18, 14)))
	result.set_color("font_hover_color", "PopupMenu", INK)
	result.set_stylebox("hover", "PopupMenu", button_style("hover"))
	result.set_icon("checked", "CheckBox", small_icon("checkbox_on", Vector2i(24, 24)))
	result.set_icon("unchecked", "CheckBox", small_icon("checkbox_off", Vector2i(24, 24)))
	result.set_icon("checked_disabled", "CheckBox", small_icon("checkbox_on", Vector2i(24, 24)))
	result.set_icon("unchecked_disabled", "CheckBox", small_icon("checkbox_off", Vector2i(24, 24)))
	result.set_constant("h_separation", "CheckBox", 12)
	for type_name: String in ["HSlider", "VSlider"]:
		var track := bar_style(DEEP_INK)
		track.content_margin_top = 5.0
		track.content_margin_bottom = 5.0
		result.set_stylebox("slider", type_name, track)
		result.set_stylebox("grabber_area", type_name, bar_style(GOLD))
		result.set_stylebox("grabber_area_highlight", type_name, bar_style(GOLD))
		result.set_icon("grabber", type_name, small_icon("slider_knob", Vector2i(24, 24)))
		result.set_icon("grabber_highlight", type_name, small_icon("slider_knob", Vector2i(28, 28)))
		result.set_icon("grabber_disabled", type_name, small_icon("slider_knob", Vector2i(24, 24)))
	for type_name: String in ["VScrollBar", "HScrollBar"]:
		var track := bar_style(DEEP_INK)
		track.content_margin_left = 4.0
		track.content_margin_right = 4.0
		result.set_stylebox("scroll", type_name, track)
		result.set_stylebox("grabber", type_name, bar_style(GOLD))
		result.set_stylebox("grabber_highlight", type_name, bar_style(GOLD))
		result.set_stylebox("grabber_pressed", type_name, bar_style(GOLD))
	return result


static func paper_style(asset_name: String, inset: float = 24.0) -> AspectTextureStyle:
	if asset_name == "card_frame":
		var frame := AspectTextureStyle.new()
		frame.texture = art_texture(asset_name)
		return frame
	var role: StringName = &"panel"
	if asset_name in ["button", "market_panel"]:
		role = &"slip"
	elif asset_name == "button_hover":
		role = &"selected"
	elif asset_name in ["progress_track", "progress_fill"]:
		role = &"bar"
	return preload("res://scripts/ui/paper_skin.gd").make(role,inset)


static func panel_style(inset: float = 24.0, _raised: bool = true) -> AspectTextureStyle:
	return preload("res://scripts/ui/paper_skin.gd").make(&"panel",inset)


static func button_style(state: String, _quiet: bool = false) -> StyleBox:
	var role: StringName = &"selected" if state in ["hover","pressed","hover_pressed","focus"] else &"slip"
	var style := preload("res://scripts/ui/paper_skin.gd").make(role,12)
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	if state == "disabled":
		style.modulate_color = Color(1,1,1,0.60)
	return style


static func bar_style(color: Color) -> AspectTextureStyle:
	var style := preload("res://scripts/ui/paper_skin.gd").make(&"bar")
	style.modulate_color = Color("312c29") if color == DEEP_INK else Color("92967b")
	if color == RED:
		style.modulate_color = RED
	return style


static func small_icon(asset_name: String, dimensions: Vector2i) -> Texture2D:
	var key := asset_name + str(dimensions)
	if not _small_icons.has(key):
		var source := GameArt.texture("res://assets/art/ui/forest_rebuild/close-mural-v1.png") if asset_name == "close" else art_texture(asset_name)
		if source == null:
			return null
		var proxy := preload("res://scripts/ui/ui_icon_texture.gd").new()
		proxy.source = source
		proxy.logical_size = dimensions
		_small_icons[key] = proxy
	return _small_icons[key]


static func apply_button(button: Button, quiet: bool = false) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, button_style(state, quiet))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	preload("res://scripts/ui/paper_button_feedback.gd").bind(button)


static func animate_open(control: Control) -> Tween:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * 0.97
	control.modulate.a = 0.0
	var motion := control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	motion.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(control, "scale", Vector2.ONE, 0.24)
	motion.tween_property(control, "modulate:a", 1.0, 0.16)
	return motion


static func title_font() -> SystemFont:
	return preload("res://scripts/ui/forest_ui_typography.gd").regular()
