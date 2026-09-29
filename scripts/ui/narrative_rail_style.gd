extends RefCounted

const INK := Color("e9e5df")
const MUTED := Color("9ca5b0")
const GOLD := Color("d9ab72")
const SURFACE := Color("101722")

static func label(node_name: String, font_size: int, color: Color = INK) -> Label:
	var result := Label.new()
	result.name = node_name
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_override("font", GameTheme.paper_font())
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_constant_override("outline_size", 0)
	result.add_theme_constant_override("line_spacing", 8)
	return result

static func panel_style() -> StyleBox:
	return ForestPaperStyle.make(true, 0.0)

static func setup_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", GameTheme.paper_font())
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, ForestPaperStyle.make(false, 8.0))
	button.add_theme_color_override("font_color", Color("39433f"))
	button.add_theme_color_override("font_hover_color", Color("79593d"))
	button.add_theme_color_override("font_pressed_color", Color("303932"))
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_constant_override("outline_size", 0)

static func metrics(screen: Vector2) -> Dictionary:
	var scale := clampf(screen.y / 900.0, 0.78, 1.45)
	var width := clampf(screen.x * 0.35, 330.0, screen.x * 0.45)
	var margin := 38.0 * scale
	return {"scale": scale, "rect": Rect2(screen.x - width - 10.0, 20.0, width, screen.y - 40.0),
		"margin": margin, "body_size": roundi(28.0 * scale), "name_size": roundi(32.0 * scale)}

static func size_story(story: Label, width: float, font_size: int) -> void:
	story.add_theme_font_size_override("font_size", font_size)
	story.custom_minimum_size.x = maxf(width, 80.0)
	story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
