extends StyleBox

const Typography = preload("res://scripts/ui/forest_ui_typography.gd")
const ControlPaper = preload("res://scripts/ui/settings_control_paper.gd")
const INK := Color("e3d6b8")
const MUTED := Color("aa9e86")
var active := false
var track := false
var popup_surface := false
var popup_full_size := Vector2.ZERO
static var _icons: Dictionary = {}


static func make(highlight := false, is_track := false) -> StyleBox:
	var style := new()
	style.active = highlight
	style.track = is_track
	style.set_content_margin_all(14 if not is_track else 0)
	style.content_margin_top = 8 if not is_track else 0
	style.content_margin_bottom = 8 if not is_track else 0
	return style


func _draw(canvas: RID, rect: Rect2) -> void:
	if track:
		if rect.size.x <= 0.0:
			return
		# 固定种子的微小边缘变化，滑动时不闪动；不向纸面撒噪点。
		var points := PackedVector2Array()
		var triangles := PackedInt32Array()
		var y := rect.position.y + rect.size.y * 0.5
		var radius := minf(2.4, rect.size.x * 0.5)
		var span := maxf(0.0, rect.size.x - radius * 2.0)
		var color := INK if active else Color("74746b")
		for index: int in range(ceili(span / 2.0) + 1):
			var x := minf(index * 2.0, span)
			var edge_fade := clampf(minf(x, span - x) / 5.0, 0.0, 1.0)
			var grain := (sin(index * 2.73) * 0.45 + sin(index * 1.31) * 0.3) * edge_fade
			points.append(Vector2(rect.position.x + radius + x, y - radius + grain))
			points.append(Vector2(rect.position.x + radius + x, y + radius + grain * 0.6))
			if index > 0:
				var vertex := index * 2
				triangles.append_array(PackedInt32Array([vertex - 2, vertex - 1, vertex, vertex, vertex - 1, vertex + 1]))
		# 直接提交三角带，避免拖动时反复剖分数百顶点的多边形。
		if not triangles.is_empty():
			RenderingServer.canvas_item_add_triangle_array(canvas, triangles, points, PackedColorArray([color]))
		# 圆头留在实际轨道范围内；极短填充收成圆点，零填充不越界。
		RenderingServer.canvas_item_add_circle(canvas, Vector2(rect.position.x + radius, y), radius, color, true)
		if span > 0.0:
			RenderingServer.canvas_item_add_circle(canvas, Vector2(rect.end.x - radius, y), radius, color, true)
		return
	if popup_surface:
		var full_rect := Rect2(rect.position, popup_full_size if popup_full_size != Vector2.ZERO else rect.size)
		ControlPaper.draw_paper(canvas, full_rect, ControlPaper.BASE_TINT, true)
	else:
		ControlPaper.draw_paper(canvas, rect, ControlPaper.HOVER_TINT if active else ControlPaper.BASE_TINT)


static func apply_button(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, ControlPaper.make(state in ["hover", "pressed", "hover_pressed", "focus"], state in ["pressed", "hover_pressed"]))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_font_override("font", Typography.regular())
	button.add_theme_font_size_override("font_size", 22)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	preload("res://scripts/ui/settings_control_motion.gd").bind(button)


static func apply_option(option: OptionButton) -> void:
	apply_button(option)
	option.add_theme_icon_override("arrow", icon("arrow"))
	option.add_theme_constant_override("arrow_margin", 14)
	var popup := option.get_popup()
	popup.borderless = true
	popup.transparent_bg = true
	popup.transparent = true
	var fit_popup := _fit_option_popup.bind(option)
	if not popup.about_to_popup.is_connected(fit_popup):
		popup.about_to_popup.connect(fit_popup)
	popup.about_to_popup.connect(func() -> void:
		popup.max_size = Vector2i(0, maxi(160, roundi(option.get_viewport_rect().size.y * 0.70)))
	)
	var panel_style := make()
	panel_style.popup_surface = true
	panel_style.set_content_margin_all(18)
	popup.add_theme_stylebox_override("panel", panel_style)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.65, 0.61, 0.53, 0.88)
	hover_style.set_border_width_all(0)
	hover_style.shadow_size = 0
	popup.add_theme_stylebox_override("hover", hover_style)
	popup.add_theme_constant_override("v_separation", 14)
	popup.add_theme_font_override("font", Typography.regular())
	popup.add_theme_font_size_override("font_size", 22)
	popup.add_theme_color_override("font_color", INK)
	popup.add_theme_color_override("font_hover_color", Color("292923"))
	popup.add_theme_icon_override("radio_checked", icon("menu_check"))
	popup.add_theme_icon_override("radio_unchecked", icon("menu_empty"))
	popup.add_theme_icon_override("checked", icon("menu_check"))
	popup.add_theme_icon_override("unchecked", icon("menu_empty"))
	preload("res://scripts/ui/settings_popup_motion.gd").bind(popup)
	_style_popup_scrollbars(popup)


static func _style_popup_scrollbars(node: Node) -> void:
	for child in node.get_children(true):
		if child is ScrollBar:
			var rail := StyleBoxFlat.new()
			rail.bg_color = Color(0, 0, 0, 0.12)
			rail.set_corner_radius_all(5)
			rail.content_margin_left = 4
			rail.content_margin_right = 4
			child.add_theme_stylebox_override("scroll", rail)
			child.add_theme_stylebox_override("scroll_focus", rail)
			for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
				var grip := StyleBoxFlat.new()
				grip.bg_color = Color(0, 0, 0, 0.48 if state == "grabber" else 0.65)
				grip.set_corner_radius_all(5)
				grip.content_margin_left = 4
				grip.content_margin_right = 4
				grip.content_margin_top = 8
				grip.content_margin_bottom = 8
				child.add_theme_stylebox_override(state, grip)
			var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			blank.fill(Color.TRANSPARENT)
			var no_arrow := ImageTexture.create_from_image(blank)
			for arrow: String in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
				child.add_theme_icon_override(arrow, no_arrow)
		_style_popup_scrollbars(child)


static func _fit_option_popup(option: OptionButton) -> void:
	# 等待 OptionButton 算出自然尺寸和屏幕限高，再解除内容撑高约束。
	_resize_option_popup.bind(option).call_deferred()


static func _resize_option_popup(option: OptionButton) -> void:
	if not is_instance_valid(option):
		return
	var popup := option.get_popup()
	if not popup.visible:
		return
	var natural_size := popup.size
	var height_limit := popup.max_size.y
	if height_limit <= 0:
		return
	popup.wrap_controls = false
	# 按钮逻辑宽度也要转换成窗口单位，确保下拉与按钮等宽。
	var button_width := ceili(option.size.x * popup.content_scale_factor)
	popup.size = Vector2i(maxi(natural_size.x, button_width), mini(natural_size.y, height_limit))
	# Window.size 是窗口像素，纸面与菜单内容使用缩放后的逻辑坐标。
	# 固定完整纸面必须记录逻辑尺寸，否则小比例下文字和高亮会伸出纸面。
	popup.get_theme_stylebox("panel").popup_full_size = popup.get_visible_rect().size
	popup.popup_hide.connect(func(): popup.wrap_controls = true, CONNECT_ONE_SHOT)


static func apply_check(check: CheckBox) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		check.add_theme_stylebox_override(state, make(state in ["hover", "focus", "pressed", "hover_pressed"]))
	for state: String in ["checked", "checked_disabled"]:
		check.add_theme_icon_override(state, icon("check"))
	for state: String in ["unchecked", "unchecked_disabled"]:
		check.add_theme_icon_override(state, icon("box"))
	check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func apply_slider(slider: HSlider) -> void:
	preload("res://scripts/ui/settings_control_motion.gd").bind_slider(slider)
	slider.add_theme_stylebox_override("slider", make(false, true))
	slider.add_theme_stylebox_override("grabber_area", make(true, true))
	slider.add_theme_stylebox_override("grabber_area_highlight", make(true, true))
	for state: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(state, icon("knob"))
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func icon(kind: String) -> Texture2D:
	if _icons.has(kind):
		return _icons[kind]
	# 同一墨色和线宽；矢量源保留分辨率，运行时只创建一次。
	var shape := ""
	match kind:
		"arrow":
			shape = '<path d="M7 11 L16 21 L25 11 Z" fill="#e3d6b8"/>'
		"knob":
			shape = '<path d="M16 5 L29 19 L16 33 L3 19 Z" fill="#11110f" stroke="#11110f" stroke-width="3" stroke-linejoin="round" opacity="0.32"/><path d="M16 3.8 L29 17.8 L16 31.8 L3 17.8 Z" fill="#11110f" opacity="0.58"/><path d="M16 2 L29 16 L16 30 L3 16 Z" fill="#11110f" stroke="#11110f" stroke-width="1.8" stroke-linejoin="round" opacity="0.6"/><path d="M16 2 L29 16 L16 30 L3 16 Z" fill="#e3d6b8"/>'
		"display":
			shape = '<path d="M2 16 Q16 1 30 16 Q16 31 2 16 Z" fill="none" stroke="white" stroke-width="2.6"/><ellipse cx="16" cy="16" rx="5" ry="7" fill="white"/>'
		"audio":
			shape = '<path d="M12 23 V6 L27 3 V22 H24 V8 L15 10 V25 Z" fill="white"/><ellipse cx="9" cy="25" rx="6" ry="4" fill="white"/><ellipse cx="22" cy="23" rx="6" ry="4" fill="white"/>'
		"master_volume":
			shape = '<path d="M3 11 H8 L15 5 V27 L8 21 H3 Z" fill="white"/><path d="M20 10 Q25 16 20 22 M25 5 Q33 16 25 27" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round"/>'
		"sfx_volume":
			shape = '<path d="M7 17 L1 13 Q0 19 7 22 L11 22 Z M17 14 L14 3 Q20 0 21 13 Z M12 27 L4 30 Q3 25 11 24 Z" fill="white"/>'
		"language":
			shape = '<path d="M10 2 V6 M3 7 H19 M7 7 Q8 16 18 19 M15 7 Q14 16 3 21 M19 29 L24 15 L30 29 M21 25 H28" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
		"menu_check":
			shape = '<path d="M6 16 L13 23 L27 8" fill="none" stroke="#e3d6b8" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>'
		"menu_empty":
			shape = '<path d="M0 0" fill="none"/>'
		"box", "check":
			shape = '<path d="M5 5 L27 4 L28 27 L4 28 Z" fill="#4c453a" stroke="#b5a486" stroke-width="1.7"/>'
			if kind == "check":
				shape += '<path d="M9 16 L14 22 L24 10" fill="none" stroke="#d4c4a3" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>'
	var bitmap := Image.new()
	var svg_size := 40 if kind == "knob" else 32
	var svg_view := "-4 -4 40 40" if kind == "knob" else "0 0 32 32"
	bitmap.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%s">' % [svg_size, svg_size, svg_view] + shape + '</svg>', 4.0)
	var proxy := preload("res://scripts/ui/ui_icon_texture.gd").new()
	proxy.source = ImageTexture.create_from_image(bitmap)
	proxy.logical_size = Vector2i(24, 24) if kind == "arrow" else Vector2i(28, 28)
	if kind == "knob":
		# 增加透明边距但保持原菱形的可见尺寸。
		proxy.logical_size = Vector2i(35, 35)
	if kind in ["display", "audio", "language"]:
		proxy.logical_size = Vector2i(40, 40)
	_icons[kind] = proxy
	return proxy
